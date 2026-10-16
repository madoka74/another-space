import Foundation
import RealityKit
import simd

/// 여러 물체를 '그물 하나'로 모아 만드는 도구.
/// 나무 30그루를 엔티티 30개로 만들면 그릴 때마다 30번 따로 그리지만, 하나로 모으면 한 번에 그림 → 방마다 엔티티 수십 개 → 몇 개
struct Geo {
    var pos: [SIMD3<Float>] = []
    var uv: [SIMD2<Float>] = []
    var idx: [UInt32] = []

    var isEmpty: Bool { idx.isEmpty }

    /// 네 점 사각형 (a→b→c→d 둘레 순서, uv 같은 순서). 양면
    mutating func quad(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>,
                       _ ua: SIMD2<Float>, _ ub: SIMD2<Float>, _ uc: SIMD2<Float>, _ ud: SIMD2<Float>, twoSided: Bool = true) {
        let base = UInt32(pos.count)
        pos += [a, b, c, d]
        uv += [ua, ub, uc, ud]
        idx += [base, base + 1, base + 2, base, base + 2, base + 3]
        if twoSided { idx += [base, base + 2, base + 1, base, base + 3, base + 2] }
    }

    /// 세워 둔 판 (바닥 두 점 a→b, 높이 y0~y1). u는 길이(m)/tile, v는 0(아래)~1(위)
    mutating func wall(_ a: SIMD3<Float>, _ b: SIMD3<Float>, y0: Float, y1: Float, u0: Float, u1: Float, v0: Float = 0, v1: Float = 1) {
        quad(a + SIMD3<Float>(0, y0, 0), b + SIMD3<Float>(0, y0, 0), b + SIMD3<Float>(0, y1, 0), a + SIMD3<Float>(0, y1, 0),
             SIMD2<Float>(u0, v0), SIMD2<Float>(u1, v0), SIMD2<Float>(u1, v1), SIMD2<Float>(u0, v1))
    }

    /// 안쪽에서 보는 원기둥 띠 (지평선 둘레). repeats: 한 바퀴에 그림을 몇 번 되풀이할지
    mutating func ring(center c: SIMD3<Float>, radius r: Float, y0: Float, y1: Float, repeats: Float, segments: Int = 96, phase: Float = 0) {
        for i in 0..<segments {
            let t0 = Float(i) / Float(segments), t1 = Float(i + 1) / Float(segments)
            let a0 = t0 * 2 * .pi + phase, a1 = t1 * 2 * .pi + phase
            let p0 = c + SIMD3<Float>(cos(a0) * r, 0, sin(a0) * r)
            let p1 = c + SIMD3<Float>(cos(a1) * r, 0, sin(a1) * r)
            wall(p0, p1, y0: y0, y1: y1, u0: t0 * repeats, u1: t1 * repeats)
        }
    }

    /// 십자로 세운 나무 (판 두 장, 그림 한 장 전체)
    mutating func crossTree(at p: SIMD3<Float>, width w: Float, height h: Float, yaw: Float) {
        for k in 0..<2 {
            let a = yaw + Float(k) * .pi / 2
            let d = SIMD3<Float>(cos(a), 0, sin(a)) * (w / 2)
            wall(p - d, p + d, y0: 0, y1: h, u0: 0, u1: 1)
        }
    }

    /// 평평한 원판 (바닥·물). tile m마다 무늬 되풀이
    mutating func disc(center c: SIMD3<Float>, radius r: Float, tile: Float, segments: Int = 48) {
        let base = UInt32(pos.count)
        pos.append(c); uv.append(SIMD2<Float>(c.x, c.z) / tile)
        for i in 0...segments {
            let a = Float(i) / Float(segments) * 2 * .pi
            let p = c + SIMD3<Float>(cos(a) * r, 0, sin(a) * r)
            pos.append(p); uv.append(SIMD2<Float>(p.x, p.z) / tile)
        }
        for i in 0..<UInt32(segments) {
            idx += [base, base + 1 + i, base + 2 + i, base, base + 2 + i, base + 1 + i]
        }
    }

    /// 상자 (건물): 가운데 바닥 c, 크기, 방향. 옆면은 tile m마다 무늬 (창 격자가 건물마다 이어지게)
    mutating func box(base c: SIMD3<Float>, w: Float, d: Float, h: Float, yaw: Float, tile: Float) {
        let ax = SIMD3<Float>(cos(yaw), 0, -sin(yaw)), az = SIMD3<Float>(sin(yaw), 0, cos(yaw))
        let hw = w / 2, hd = d / 2
        let p = [c - ax * hw - az * hd, c + ax * hw - az * hd, c + ax * hw + az * hd, c - ax * hw + az * hd]
        let len = [w, d, w, d]
        for i in 0..<4 {
            let a = p[i], b = p[(i + 1) % 4]
            wall(a, b, y0: 0, y1: h, u0: 0, u1: len[i] / tile, v0: 0, v1: h / tile)
        }
        let top = SIMD3<Float>(0, h, 0)
        quad(p[0] + top, p[1] + top, p[2] + top, p[3] + top, .zero, SIMD2<Float>(0.05, 0), SIMD2<Float>(0.05, 0.05), SIMD2<Float>(0, 0.05))
    }

    /// 텐트 (삼각 기둥): 바닥 가운데 c, 폭 w, 길이 l, 높이 h
    mutating func tent(base c: SIMD3<Float>, w: Float, l: Float, h: Float, yaw: Float) {
        let ax = SIMD3<Float>(cos(yaw), 0, -sin(yaw)), az = SIMD3<Float>(sin(yaw), 0, cos(yaw))
        let fl = c - ax * (w / 2) - az * (l / 2), fr = c + ax * (w / 2) - az * (l / 2)
        let bl = c - ax * (w / 2) + az * (l / 2), br = c + ax * (w / 2) + az * (l / 2)
        let ft = c - az * (l / 2) + SIMD3<Float>(0, h, 0), bt = c + az * (l / 2) + SIMD3<Float>(0, h, 0)
        quad(fl, bl, bt, ft, SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(1, 1), SIMD2<Float>(0, 1))
        quad(fr, br, bt, ft, SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(1, 1), SIMD2<Float>(0, 1))
        // 앞뒤 세모 (사각형의 두 점을 겹쳐 씀)
        quad(fl, fr, ft, ft, SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(0.5, 1), SIMD2<Float>(0.5, 1))
        quad(bl, br, bt, bt, SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(0.5, 1), SIMD2<Float>(0.5, 1))
    }

    /// 울퉁불퉁한 바위 (각진 공을 무작위로 눌러 만듦)
    mutating func rock<G: RandomNumberGenerator>(at c: SIMD3<Float>, size s: Float, using g: inout G) {
        let seg = 9, rings = 6
        let base = UInt32(pos.count)
        var rad: [Float] = []
        for _ in 0...(rings * (seg + 1)) { rad.append(Float.random(in: 0.72...1.12, using: &g)) }
        let flat = Float.random(in: 0.45...0.75, using: &g)
        let yaw = Float.random(in: 0...(2 * .pi), using: &g)
        for r in 0...rings {
            let el = Float.pi / 2 - Float.pi * Float(r) / Float(rings)
            for k in 0...seg {
                let az = Float(k) / Float(seg) * 2 * .pi + yaw
                let j = min(rad.count - 1, r * (seg + 1) + (k == seg ? 0 : k))
                let rr = s * rad[j]
                var p = SIMD3<Float>(cos(el) * cos(az), sin(el), cos(el) * sin(az)) * rr
                p.y = max(p.y * flat, -0.15 * s)
                pos.append(c + p)
                uv.append(SIMD2<Float>(Float(k) / Float(seg) * 2, Float(r) / Float(rings)) * max(1, s))
            }
        }
        for r in 0..<UInt32(rings) {
            for k in 0..<UInt32(seg) {
                let a = base + r * UInt32(seg + 1) + k, b = a + UInt32(seg + 1)
                idx += [a, b, a + 1, a + 1, b, b + 1, a, a + 1, b, a + 1, b + 1, b]
            }
        }
    }

    /// 작은 전구 (팔면체)
    mutating func bulb(at c: SIMD3<Float>, r: Float) {
        let pts: [SIMD3<Float>] = [c + SIMD3<Float>(r, 0, 0), c + SIMD3<Float>(-r, 0, 0), c + SIMD3<Float>(0, r, 0),
                                   c + SIMD3<Float>(0, -r, 0), c + SIMD3<Float>(0, 0, r), c + SIMD3<Float>(0, 0, -r)]
        let base = UInt32(pos.count)
        pos += pts
        uv += Array(repeating: SIMD2<Float>(0.5, 0.5), count: 6)
        let f: [UInt32] = [0, 2, 4, 4, 2, 1, 1, 2, 5, 5, 2, 0, 0, 4, 3, 4, 1, 3, 1, 5, 3, 5, 0, 3]
        let tri = f.map { base + $0 }
        idx += tri
        idx += Array(tri.reversed())
    }

    @MainActor
    func mesh(_ name: String) -> MeshResource? {
        guard !idx.isEmpty else { return nil }
        var d = MeshDescriptor(name: name)
        d.positions = MeshBuffers.Positions(pos)
        d.textureCoordinates = MeshBuffers.TextureCoordinates(uv)
        d.primitives = .triangles(idx)
        return try? MeshResource.generate(from: [d])
    }

    @MainActor
    func entity(_ name: String, _ m: RealityKit.Material) -> ModelEntity? {
        guard let mesh = mesh(name) else { return nil }
        return ModelEntity(mesh: mesh, materials: [m])
    }
}
