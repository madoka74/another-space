import Foundation
import simd

/// 위치 기억(월드 앵커)이 없을 때(앱을 지웠다 다시 깔아 iCloud에서 되살린 공간 등) 저장해 둔 벽 모양과
/// 지금 비전프로가 보는 벽을 맞춰 '저장 좌표 ↔ 지금 좌표'를 찾음.
/// - 저장 쪽: 스캔 격자(10cm)의 벽 칸 → 벽까지 거리 지도 (평면 좌표)
/// - 지금 쪽: 비전프로가 '벽'으로 알아본 세운 면의 가운데 점들
/// - 벽 방향(90°마다 4가지 ± 3°)과 위치를 모두 훑어 점들이 벽에 가장 잘 붙는 자리를 고르고, 둘째로 좋은 자리와
///   확실히 차이 날 때만 씀 (비슷한 방이 많아 헷갈리면 더 둘러보게 하고 다시 시도)
enum Align {
    struct Map: Sendable {
        let W: Int, H: Int
        let res: Float
        let dist: [Float]          // 벽까지 거리(m, 0.5까지)
        let angle: Float           // 저장 공간의 평면 방향 (rec.angle)
        let o: SIMD2<Float>        // 평면 원점의 저장 좌표 (rec.ox, rec.oz)
        let floorY: Float

        func d(_ p: SIMD2<Float>) -> Float {
            let u = Int((p.x / res).rounded(.down)), v = Int((p.y / res).rounded(.down))
            guard u >= 0, v >= 0, u < W, v < H else { return 0.5 }
            return dist[v * W + u]
        }
    }

    static func map(_ s: SpaceData) -> Map? {
        let W = s.rec.w, H = s.rec.h
        guard W > 4, H > 4, s.kind.count == W * H else { return nil }
        let cap: Float = 0.5
        var dd = [Float](repeating: cap, count: W * H)
        var any = false
        for i in 0..<(W * H) where s.kind[i] == RoomSegment.WALL { dd[i] = 0; any = true }
        guard any else { return nil }
        // 두 번 훑는 거리 근사 (모서리 대각선 포함)
        let c = s.rec.cell, cd = c * 1.414
        for v in 0..<H { for u in 0..<W {
            let i = v * W + u
            var m = dd[i]
            if u > 0 { m = min(m, dd[i - 1] + c) }
            if v > 0 { m = min(m, dd[i - W] + c) }
            if u > 0 && v > 0 { m = min(m, dd[i - W - 1] + cd) }
            if u + 1 < W && v > 0 { m = min(m, dd[i - W + 1] + cd) }
            dd[i] = m
        } }
        for v in stride(from: H - 1, through: 0, by: -1) { for u in stride(from: W - 1, through: 0, by: -1) {
            let i = v * W + u
            var m = dd[i]
            if u + 1 < W { m = min(m, dd[i + 1] + c) }
            if v + 1 < H { m = min(m, dd[i + W] + c) }
            if u + 1 < W && v + 1 < H { m = min(m, dd[i + W + 1] + cd) }
            if u > 0 && v + 1 < H { m = min(m, dd[i + W - 1] + cd) }
            dd[i] = min(cap, m)
        } }
        return Map(W: W, H: H, res: c, dist: dd, angle: s.rec.angle, o: SIMD2<Float>(s.rec.ox, s.rec.oz), floorY: s.rec.floorY)
    }

    /// 지금 보이는 벽 점들 (지금 좌표 xz), 벽 방향(라디안, 0~π/2), 바닥 높이
    struct Live: Sendable {
        var pts: [SIMD2<Float>] = []
        var dir: Float = 0
        var floorY: Float?
    }

    static func live(_ meshes: [MeshCopy]) -> Live {
        var floors: [Float] = []
        var cells = Set<Int64>()
        var pts: [SIMD2<Float>] = []
        var sx: Float = 0, sy: Float = 0
        var walls: [(SIMD3<Float>, SIMD2<Float>, Float)] = []       // 가운데, 법선 xz, 넓이
        for m in meshes {
            let wv = m.v.map { simd_make_float3(m.m * SIMD4<Float>($0, 1)) }
            var i = 0, fi = 0
            while i + 2 < m.f.count {
                defer { i += 3; fi += 1 }
                let ia = Int(m.f[i]), ib = Int(m.f[i + 1]), ic = Int(m.f[i + 2])
                guard ia < wv.count, ib < wv.count, ic < wv.count else { continue }
                let a = wv[ia], b = wv[ib], c = wv[ic]
                let cr = simd_cross(b - a, c - a)
                let len = simd_length(cr)
                guard len > 1e-7 else { continue }
                let n = cr / len
                let cls: UInt8 = fi < m.c.count ? m.c[fi] : 0
                let ctr = (a + b + c) / 3
                if cls == MeshClass.floor { floors.append(ctr.y); continue }
                if cls == MeshClass.wall && abs(n.y) < 0.3 { walls.append((ctr, SIMD2<Float>(n.x, n.z), len / 2)) }
            }
        }
        var out = Live()
        if !floors.isEmpty { floors.sort(); out.floorY = floors[floors.count / 2] }
        for (ctr, n, area) in walls {
            if let f = out.floorY, ctr.y - f < 0.3 || ctr.y - f > 2.0 { continue }
            // 벽 방향: 4배 각도로 평균 (90°마다 같은 방향)
            let a = atan2(n.y, n.x) * 4
            sx += cos(a) * area; sy += sin(a) * area
            let key = (Int64((ctr.x / 0.1).rounded(.down)) + 1_000_000) << 21 | (Int64((ctr.z / 0.1).rounded(.down)) + 1_000_000)
            if cells.insert(key).inserted { pts.append(SIMD2<Float>(ctr.x, ctr.z)) }
        }
        out.pts = pts
        var d = atan2(sy, sx) / 4
        if d < 0 { d += .pi / 2 }
        out.dir = d
        return out
    }

    struct Result: Sendable {
        var fit: Fit
        var inliers: Float
    }

    private static func rot(_ p: SIMD2<Float>, _ a: Float) -> SIMD2<Float> {
        let c = cos(a), s = sin(a)
        return SIMD2<Float>(c * p.x - s * p.y, s * p.x + c * p.y)
    }

    /// 지금 좌표 점들을 평면 좌표로: plane = R(θ)·live + d. 점수 = 벽까지 거리 평균 (낮을수록 좋음)
    private static func score(_ P: [SIMD2<Float>], _ th: Float, _ d: SIMD2<Float>, _ M: Map) -> Float {
        let c = cos(th), s = sin(th)
        var sum: Float = 0
        for p in P { sum += M.d(SIMD2<Float>(c * p.x - s * p.y + d.x, s * p.x + c * p.y + d.y)) }
        return sum / Float(max(1, P.count))
    }

    static func solve(_ M: Map, _ L: Live, liveFloorFallback: Float) -> Result? {
        guard L.pts.count >= 150 else { return nil }
        // 점이 많으면 고르게 덜어 냄
        var g = SeededRNG(seed: 7)
        let all = L.pts.count > 600 ? Array(L.pts.shuffled(using: &g).prefix(600)) : L.pts
        let few = Array(all.prefix(160))
        let ext = SIMD2<Float>(Float(M.W), Float(M.H)) * M.res
        struct Cand { var th: Float; var d: SIMD2<Float>; var sc: Float }
        var cands: [Cand] = []
        // 평면 좌표의 벽은 축과 나란함 → 지금 벽 방향을 축에 맞추는 회전 4가지 ± 3°
        for k in 0..<4 {
            for j in -6...6 {
                let th = -L.dir + Float(k) * .pi / 2 + Float(j) * 0.5 * .pi / 180
                let rp = few.map { rot($0, th) }
                let cen = rp.reduce(SIMD2<Float>(0, 0), +) / Float(rp.count)
                var best: Cand?
                var x: Float = 0
                while x <= ext.x {
                    var y: Float = 0
                    while y <= ext.y {
                        let d = SIMD2<Float>(x, y) - cen
                        var sum: Float = 0
                        for p in rp { sum += M.d(p + d) }
                        let sc = sum / Float(rp.count)
                        if sc < (best?.sc ?? .infinity) { best = Cand(th: th, d: d, sc: sc) }
                        y += 0.2
                    }
                    x += 0.2
                }
                if let best { cands.append(best) }
            }
        }
        cands.sort { $0.sc < $1.sc }
        // 좋은 후보 몇 개를 촘촘히 다듬음 (모든 점으로)
        var refined: [Cand] = []
        for c0 in cands.prefix(6) {
            var c = c0
            c.sc = score(all, c.th, c.d, M)
            var step: Float = 0.1, astep: Float = 0.25 * .pi / 180
            for _ in 0..<5 {
                var improved = true
                while improved {
                    improved = false
                    for (dth, dx, dy) in [(Float(0), step, Float(0)), (0, -step, 0), (0, 0, step), (0, 0, -step), (astep, 0, 0), (-astep, 0, 0)] {
                        let n = Cand(th: c.th + dth, d: c.d + SIMD2<Float>(dx, dy), sc: 0)
                        let sc = score(all, n.th, n.d, M)
                        if sc < c.sc - 1e-5 { c = Cand(th: n.th, d: n.d, sc: sc); improved = true }
                    }
                }
                step /= 2; astep /= 2
            }
            refined.append(c)
        }
        refined.sort { $0.sc < $1.sc }
        guard let best = refined.first else { return nil }
        func inl(_ c: Cand) -> Float {
            let cs = cos(c.th), sn = sin(c.th)
            var k = 0
            for p in all where M.d(SIMD2<Float>(cs * p.x - sn * p.y + c.d.x, sn * p.x + cs * p.y + c.d.y)) < 0.12 { k += 1 }
            return Float(k) / Float(all.count)
        }
        let bi = inl(best)
        // 다른 자리(1m 넘게 또는 10° 넘게 다른)인데 거의 똑같이 잘 맞으면 헷갈리는 것 → 쓰지 않음
        for c in refined.dropFirst() {
            let far = simd_distance(c.d, best.d) > 1 || abs(remainder(c.th - best.th, 2 * .pi)) > 10 * .pi / 180
            if far && inl(c) > bi - 0.12 { return nil }
        }
        guard bi >= 0.6 else { return nil }
        // plane = R(θ)live + d,  saved = R(α)plane + O  →  saved = R(α+θ)live + R(α)d + O
        // Fit: current = R(β)saved + t  →  β = -(α+θ),  t = -R(β)(R(α)d + O)
        let beta = -(M.angle + best.th)
        let q = rot(best.d, M.angle) + M.o
        var f = Fit()
        f.c = cos(beta); f.s = sin(beta)
        f.t = -rot(q, beta)
        f.y = (L.floorY ?? liveFloorFallback) - M.floorY
        return Result(fit: f, inliers: bi)
    }
}
