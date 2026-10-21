import Foundation
import UIKit
import ARKit
import RealityKit
import simd
import Metal

/// 비전프로가 준 그물(메시) 버퍼 읽기
enum MeshRead {
    static func vertices(_ s: GeometrySource) -> [SIMD3<Float>] {
        let base = s.buffer.contents()
        var out: [SIMD3<Float>] = []
        out.reserveCapacity(s.count)
        for i in 0..<s.count {
            let p = base.advanced(by: s.offset + s.stride * i).assumingMemoryBound(to: Float.self)
            out.append(SIMD3<Float>(p[0], p[1], p[2]))
        }
        return out
    }

    static func indices(_ e: GeometryElement) -> [UInt32] {
        let n = e.count * e.primitive.indexCount
        let base = e.buffer.contents()
        var out: [UInt32] = []
        out.reserveCapacity(n)
        if e.bytesPerIndex == 2 {
            for i in 0..<n { out.append(UInt32(base.advanced(by: i * 2).assumingMemoryBound(to: UInt16.self).pointee)) }
        } else {
            for i in 0..<n { out.append(base.advanced(by: i * 4).assumingMemoryBound(to: UInt32.self).pointee) }
        }
        return out
    }

    /// 면마다 분류 (바닥·벽·천장·탁자…). 분류가 없으면 모두 0
    static func classes(_ s: GeometrySource?, faces: Int) -> [UInt8] {
        var out = [UInt8](repeating: 0, count: faces)
        guard let s else { return out }
        let base = s.buffer.contents()
        for i in 0..<min(faces, s.count) {
            out[i] = base.advanced(by: s.offset + s.stride * i).assumingMemoryBound(to: UInt8.self).pointee
        }
        return out
    }
}

/// 그물 면 분류 번호 (MeshAnchor.MeshClassification 의 rawValue)
enum MeshClass {
    static let none: UInt8 = 0
    static let wall: UInt8 = 1
    static let floor: UInt8 = 2
    static let ceiling: UInt8 = 3
    static let table: UInt8 = 4
    static let seat: UInt8 = 5
    static let window: UInt8 = 6
    static let door: UInt8 = 7
}

/// 그물 한 덩어리를 계산하기 좋게 복사해 둔 것 (다른 스레드로 넘김)
struct MeshCopy: Sendable {
    let id: UUID
    let m: simd_float4x4             // 앵커 → 세계
    let v: [SIMD3<Float>]
    let f: [UInt32]
    let c: [UInt8]

    init(_ a: MeshAnchor) {
        id = a.id
        m = a.originFromAnchorTransform
        v = MeshRead.vertices(a.geometry.vertices)
        f = MeshRead.indices(a.geometry.faces)
        c = MeshRead.classes(a.geometry.classifications, faces: f.count / 3)
    }

    init(id: UUID, m: simd_float4x4, v: [SIMD3<Float>], f: [UInt32], c: [UInt8]) {
        self.id = id; self.m = m; self.v = v; self.f = f; self.c = c
    }
}

/// 저장할 때의 좌표(저장 좌표) ↔ 지금 좌표: 위에서 본 회전(c, s)·이동(t) + 높이 차이(y)
struct Fit: Equatable, Sendable {
    var c: Float = 1
    var s: Float = 0
    var t = SIMD2<Float>(0, 0)
    var y: Float = 0

    func toCurrent(_ p: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3<Float>(c * p.x - s * p.z + t.x, p.y + y, s * p.x + c * p.z + t.y)
    }
    func toSaved(_ p: SIMD3<Float>) -> SIMD3<Float> {
        let qx = p.x - t.x, qz = p.z - t.y
        return SIMD3<Float>(c * qx + s * qz, p.y - y, -s * qx + c * qz)
    }
    /// 방향만 (이동 없이)
    func dirToCurrent(_ d: SIMD3<Float>) -> SIMD3<Float> { SIMD3<Float>(c * d.x - s * d.z, d.y, s * d.x + c * d.z) }
    func dirToSaved(_ d: SIMD3<Float>) -> SIMD3<Float> { SIMD3<Float>(c * d.x + s * d.z, d.y, -s * d.x + c * d.z) }

    /// 저장 좌표에 있는 것들을 지금 좌표로 옮기는 변환 (공간 뿌리 엔티티에 씀)
    var transform: Transform {
        Transform(scale: SIMD3<Float>(repeating: 1), rotation: simd_quatf(angle: atan2(-s, c), axis: [0, 1, 0]),
                  translation: SIMD3<Float>(t.x, y, t.y))
    }

    /// o 쪽으로 k(0~1)만큼 (회전은 짧은 쪽으로)
    func lerp(_ o: Fit, _ k: Float) -> Fit {
        let a0 = atan2(s, c), a1 = atan2(o.s, o.c)
        var d = a1 - a0
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        let a = a0 + d * k
        var f = Fit()
        f.c = cos(a); f.s = sin(a)
        f.t = t + (o.t - t) * k
        f.y = y + (o.y - y) * k
        return f.differs(o, meters: 0.002, radians: 0.001) ? f : o
    }

    func differs(_ o: Fit, meters: Float, radians: Float) -> Bool {
        let da = abs(atan2(s * o.c - c * o.s, c * o.c + s * o.s))
        return simd_distance(t, o.t) > meters || abs(y - o.y) > meters || da > radians
    }
}

/// 같은 seed면 같은 결과가 나오는 난수
struct SeededRNG: RandomNumberGenerator {
    private var st: UInt64
    init(seed: UInt64) { st = seed == 0 ? 0x1234_5678 : seed }
    mutating func next() -> UInt64 {
        st &+= 0x9E3779B97F4A7C15
        var z = st
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

/// 앱에 담은 그림(무늬·하늘)을 재질로. 한 번 읽은 그림은 다시 읽지 않음(모든 방이 같이 씀)
@MainActor
enum Tex {
    private static var cache: [String: TextureResource] = [:]
    private static var missing: Set<String> = []

    /// 지금 만드는 방의 표시 방식 (RoomWorld 가 만드는 동안만 바꿈). 흑백: 그림·색에서 색을 뺌, 선 그림: 흰 바탕 + 윤곽선 그림
    static var look: LookMode = .color

    /// 잠깐 다른 표시 방식으로 재질을 만듦
    static func with<T>(_ l: LookMode, _ f: () -> T) -> T {
        let o = look
        look = l
        defer { look = o }
        return f()
    }

    private static func key(_ name: String, _ folder: String, _ l: LookMode) -> String {
        folder + "/" + name + (l == .color ? "" : "#" + l.rawValue)
    }

    /// raw: 가림 그림 등 색이 아닌 값 (표시 방식과 상관없이 그대로), color: 표시 방식과 상관없이 컬러 (전시관 그림)
    static func get(_ name: String, folder: String = "tex", raw: Bool = false, color: Bool = false) -> TextureResource? {
        let l: LookMode = raw || color || folder == "file" ? .color : look
        let k = key(name, folder, l)
        if let t = cache[k] { return t }
        if missing.contains(k) { return nil }
        func url(_ n: String) -> URL? {
            if folder == "file" { return URL(fileURLWithPath: n) }            // 기기 안 파일 경로 (포켓 갤러리 보관함 그림 등)
            return Bundle.main.url(forResource: n, withExtension: "jpg", subdirectory: folder)
                ?? Bundle.main.url(forResource: n, withExtension: "png", subdirectory: folder)
        }
        // 선 그림: 윤곽선 그림(<이름>_ln)이 있는 것(나무·울타리·지평선 띠)만, 나머지는 흰 바탕
        let u = l == .line ? url(name + "_ln") : url(name)
        guard let u, let img = UIImage(contentsOfFile: u.path), var cg = img.cgImage else {
            missing.insert(k)
            return nil
        }
        if l == .mono, let g = gray(cg) { cg = g }
        guard let t = try? TextureResource.generate(from: cg, options: .init(semantic: raw ? .raw : .color)) else {
            missing.insert(k)
            return nil
        }
        cache[k] = t
        return t
    }

    /// 색을 뺀 그림
    nonisolated static func gray(_ cg: CGImage) -> CGImage? {
        let w = cg.width, h = cg.height
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return nil }
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        return ctx.makeImage()
    }

    static func has(_ name: String, folder: String = "tex") -> Bool { cache[key(name, folder, look)] != nil || missing.contains(key(name, folder, look)) }

    /// 미리 읽어 두기: 한 장 읽고 한 프레임 쉬어서 화면이 멈추지 않게 (방에 들어갈 때 기다리지 않도록)
    static func preload(_ list: [(String, String)], look l: LookMode = .color) async {
        for (name, folder) in list where !with(l, { has(name, folder: folder) }) {
            _ = with(l) { get(name, folder: folder) }
            try? await Task.sleep(for: .milliseconds(12))
            // 오려 내기 그림이면 가림 그림도 (없으면 그냥 넘어감)
            if folder == "tex", Bundle.main.url(forResource: name + "_a", withExtension: "png", subdirectory: folder) != nil {
                _ = get(name + "_a", folder: folder, raw: true)
                try? await Task.sleep(for: .milliseconds(6))
            }
        }
    }

    private static func sampler(_ s: MTLSamplerAddressMode, _ t: MTLSamplerAddressMode) -> MaterialParameters.Texture.Sampler {
        let d = MTLSamplerDescriptor()
        d.minFilter = .linear
        d.magFilter = .linear
        d.mipFilter = .linear
        d.sAddressMode = s
        d.tAddressMode = t
        d.maxAnisotropy = 8
        return MaterialParameters.Texture.Sampler(d)
    }
    /// 반복해서 까는 무늬용 (가장자리에서 되풀이)
    static let tiling = sampler(.repeat, .repeat)
    /// 가로로만 되풀이 (지평선 띠·담장: 위아래가 이어지면 위 끝에 줄이 생김)
    static let band = sampler(.repeat, .clampToEdge)
    static let clamp = sampler(.clampToEdge, .clampToEdge)

    /// 색 (표시 방식에 맞게: 흑백이면 밝기만, 선 그림이면 흰색)
    static func color(_ v: SIMD3<Float>, alpha: CGFloat = 1) -> UIColor {
        switch look {
        case .line:
            return UIColor(white: 1, alpha: alpha)
        case .mono:
            let l = CGFloat(min(1, max(0, v.x * 0.3 + v.y * 0.59 + v.z * 0.11)))
            return UIColor(white: l, alpha: alpha)
        case .color:
            return UIColor(red: CGFloat(min(1, max(0, v.x))), green: CGFloat(min(1, max(0, v.y))), blue: CGFloat(min(1, max(0, v.z))), alpha: alpha)
        }
    }

    /// 빛을 받지 않는(조명 계산 없이 그대로 보이는) 재질. tint로 시간·날씨·그늘을 곱함
    static func unlit(_ name: String, tint: SIMD3<Float>, folder: String = "tex", tiled: Bool = true) -> UnlitMaterial {
        unlit(name, tint: tint, folder: folder, sampler: tiled ? tiling : band)
    }

    static func unlit(_ name: String, tint: SIMD3<Float>, folder: String, sampler: MaterialParameters.Texture.Sampler) -> UnlitMaterial {
        var m = UnlitMaterial(color: color(tint))
        if let t = get(name, folder: folder) {
            var p = MaterialParameters.Texture(t)
            p.sampler = sampler
            m.color = .init(tint: color(tint), texture: p)
        }
        return m
    }

    /// 투명한 곳을 오려 내는 재질 (나무·담장·지평선 띠): 반투명 겹침 순서 문제 없이 윤곽만 남김
    static func cutout(_ name: String, tint: SIMD3<Float>, sampler: MaterialParameters.Texture.Sampler? = nil) -> UnlitMaterial {
        let sampler = sampler ?? band
        var m = unlit(name, tint: tint, folder: "tex", sampler: sampler)
        // 선 그림이면 윤곽선과 꼭 맞는 매끄러운 가림 그림(<이름>_lna)
        let lineMask = look == .line ? get(name + "_lna", folder: "tex", raw: true) : nil
        if let mask = lineMask ?? get(name + "_a", folder: "tex", raw: true) {
            var p = MaterialParameters.Texture(mask)
            p.sampler = sampler
            m.blending = .transparent(opacity: .init(scale: 1, texture: p))
        } else {
            m.blending = .transparent(opacity: .init(floatLiteral: 1))
        }
        m.opacityThreshold = 0.5
        return m
    }
}

extension SIMD3 where Scalar == Float {
    var xz: SIMD2<Float> { SIMD2<Float>(x, z) }
}
