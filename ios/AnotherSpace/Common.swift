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

/// 앱에 담은 그림(무늬·하늘)을 재질로
@MainActor
enum Tex {
    private static var cache: [String: TextureResource] = [:]

    static func get(_ name: String, folder: String = "tex") -> TextureResource? {
        let key = folder + "/" + name
        if let t = cache[key] { return t }
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: folder),
              let img = UIImage(contentsOfFile: url.path), let cg = img.cgImage,
              let t = try? TextureResource.generate(from: cg, options: .init(semantic: .color)) else { return nil }
        cache[key] = t
        return t
    }

    /// 반복해서 까는 무늬용 (가장자리에서 되풀이)
    static let tiling: MaterialParameters.Texture.Sampler = {
        let d = MTLSamplerDescriptor()
        d.minFilter = .linear
        d.magFilter = .linear
        d.mipFilter = .linear
        d.sAddressMode = .repeat
        d.tAddressMode = .repeat
        d.maxAnisotropy = 4
        return MaterialParameters.Texture.Sampler(d)
    }()

    static func color(_ v: SIMD3<Float>, alpha: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat(min(1, max(0, v.x))), green: CGFloat(min(1, max(0, v.y))), blue: CGFloat(min(1, max(0, v.z))), alpha: alpha)
    }

    /// 빛을 받지 않는(조명 계산 없이 그대로 보이는) 재질. tint로 시간·날씨·그늘을 곱함
    static func unlit(_ name: String, tint: SIMD3<Float>, folder: String = "tex", tiled: Bool = true) -> UnlitMaterial {
        var m = UnlitMaterial(color: color(tint))
        if let t = get(name, folder: folder) {
            var p = MaterialParameters.Texture(t)
            if tiled { p.sampler = tiling }
            m.color = .init(tint: color(tint), texture: p)
        }
        return m
    }
}

extension SIMD3 where Scalar == Float {
    var xz: SIMD2<Float> { SIMD2<Float>(x, z) }
}
