import Foundation
import UIKit
import RealityKit
import simd

/// 계곡 테마의 특징: 배경 폭포에서 내려온 강물이 갈래로 나뉘어 벽 너머에서 방 안 바닥으로 흘러 들어와,
/// 방 안의 비어 있는 평평한 바닥에 맑은 웅덩이를 이룸. 그 물속을 여러 크기·여러 빛깔의 작은 물고기들이 헤엄침.
/// - 물길·웅덩이: 자갈 바닥 + 그 위 맑은 물(물결이 흐름) + 물가 돌. 가구 블록·문이 쓸고 지나가는 자리는 피해 감
/// - 물고기: 비단잉어·금빛·은빛 피라미·줄무늬·파랑노랑·반점 — 꼬리를 흔들며 천천히 돌다가 가끔 휙. 손을 물 가까이 대면 흩어짐
/// - 웅덩이에서 졸졸 물소리
@MainActor
final class ValleyCreek {
    let local = Entity()                     // 방 안 (저장 좌표)
    let world = Entity()                     // 벽 너머 물길 갈래 (하늘 세계, 저장 좌표)
    private(set) var ok = false

    private final class Fish {
        let e = Entity()
        let tail = Entity()
        var pos = SIMD2<Float>(0, 0)
        var head: Float = 0
        var speed: Float = 0.1
        var cruise: Float = 0.1
        var dart: Float = 0
        var turn: Float = 0
        var depth: Float = 0.03
        var size: Float = 0.08
        var wag: Float = 0
    }

    private var fish: [Fish] = []
    private var flows: [(ModelEntity, UnlitMaterial, Float, Float)] = []
    private var path: [SIMD2<Float>] = []        // 물길 (저장 좌표 xz), 마지막이 웅덩이 가운데
    private var pool = SIMD2<Float>(0, 0)
    private var poolR: Float = 0
    private let halfW: Float = 0.17
    private let floorY: Float
    private let look: LookMode
    private var t: Float = 0
    private var hum: AudioPlaybackController?

    init(room: RoomRec, layout L: Layout, floorY: Float, blocked: Set<Int64>, riverNear: SIMD3<Float>?, riverWidth: Float, look: LookMode, tint: SIMD3<Float>) {
        self.floorY = floorY
        self.look = look
        // 1) 방 안 빈 바닥 칸 (10cm): 이 방, 벽에서 25cm 넘게, 가구 블록 아님, 문이 쓸고 지나가는 곳 아님
        let rects = L.rects(room.id)
        guard !rects.isEmpty else { return }
        var lo = rects[0].0, hi = rects[0].1
        for r in rects { lo = simd_min(lo, r.0); hi = simd_max(hi, r.1) }
        let u0 = Int((lo.x / 0.1).rounded(.down)), v0 = Int((lo.y / 0.1).rounded(.down))
        let nu = Int(((hi.x - lo.x) / 0.1).rounded(.up)) + 1, nv = Int(((hi.y - lo.y) / 0.1).rounded(.up)) + 1
        guard nu > 4, nv > 4, nu * nv < 200_000 else { return }
        func cellP(_ i: Int, _ j: Int) -> SIMD2<Float> { SIMD2<Float>((Float(u0 + i) + 0.5) * 0.1, (Float(v0 + j) + 0.5) * 0.1) }
        var free = [Bool](repeating: false, count: nu * nv)
        for j in 0..<nv {
            for i in 0..<nu {
                let p = cellP(i, j)
                let w = L.flat(p)
                let c = L.at(x: w.x, z: w.y)
                free[j * nu + i] = c.room == room.id && c.wall > 0.22 && !blocked.contains(RoomWorld.clutterKey(p)) && !Skin.inSwing(L, p)
            }
        }
        // 2) 웅덩이: 막힌 곳에서 가장 먼 칸 (넉넉한 빈 바닥)
        var dist = [Int](repeating: 0, count: nu * nv)
        var queue: [Int] = []
        for k in 0..<(nu * nv) where !free[k] { queue.append(k) }
        for j in 0..<nv { for i in 0..<nu where (i == 0 || j == 0 || i == nu - 1 || j == nv - 1) && free[j * nu + i] { dist[j * nu + i] = 1; queue.append(j * nu + i) } }
        var seen = [Bool](repeating: false, count: nu * nv)
        for k in queue { seen[k] = true }
        var qi = 0
        while qi < queue.count {
            let k = queue[qi]; qi += 1
            let i = k % nu, j = k / nu
            for (di, dj) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let a = i + di, b = j + dj
                guard a >= 0, b >= 0, a < nu, b < nv else { continue }
                let n = b * nu + a
                if !seen[n] { seen[n] = true; dist[n] = dist[k] + 1; queue.append(n) }
            }
        }
        guard let best = (0..<(nu * nv)).filter({ free[$0] }).max(by: { dist[$0] < dist[$1] }), dist[best] >= 4 else { return }
        poolR = min(0.75, Float(dist[best] - 1) * 0.1 - 0.05)
        guard poolR >= 0.28 else { return }
        let poolP = cellP(best % nu, best / nu)
        // 3) 들어오는 곳: 바깥 강에서 가장 가까운 이 방 벽(창·바깥벽) — 거기서 웅덩이까지 빈 바닥을 따라
        var route: [SIMD2<Float>] = []
        var entry: SIMD2<Float>? = nil
        var entryN = SIMD2<Float>(0, 0)
        if let rn = riverNear {
            let rp = L.plane(rn.x, rn.z)
            var bestSeg: (SIMD2<Float>, SIMD2<Float>, Float)? = nil
            for s in L.walls where s.room == room.id && !s.inner {
                let ab = s.b - s.a
                let k = max(0.15, min(simd_length(ab) - 0.15, simd_dot(rp - s.a, simd_normalize(ab))))
                let q = s.a + simd_normalize(ab) * k
                let d = simd_distance(q, rp)
                if bestSeg == nil || d < bestSeg!.2 { bestSeg = (q, s.n, d) }
            }
            if let bs = bestSeg {
                entry = bs.0
                entryN = bs.1
            }
        }
        if let e = entry {
            // 벽 안쪽 첫 빈 칸에서 웅덩이까지 (너비 우선 탐색)
            var startK: Int? = nil
            var bestD: Float = 1e9
            for k in 0..<(nu * nv) where free[k] {
                let d = simd_distance(cellP(k % nu, k / nu), e)
                if d < bestD { bestD = d; startK = k }
            }
            if let sk = startK, bestD < 0.8 {
                var prev = [Int](repeating: -1, count: nu * nv)
                var q2 = [sk]
                var vis = [Bool](repeating: false, count: nu * nv)
                vis[sk] = true
                var qj = 0
                while qj < q2.count {
                    let k = q2[qj]; qj += 1
                    if k == best { break }
                    let i = k % nu, j = k / nu
                    for (di, dj) in [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)] {
                        let a = i + di, b = j + dj
                        guard a >= 0, b >= 0, a < nu, b < nv else { continue }
                        let n = b * nu + a
                        guard free[n], !vis[n], dist[n] >= 2 || n == best else { continue }
                        vis[n] = true; prev[n] = k; q2.append(n)
                    }
                }
                if vis[best] {
                    var cells: [SIMD2<Float>] = []
                    var k = best
                    while k != -1 { cells.append(cellP(k % nu, k / nu)); k = prev[k] }
                    cells.reverse()
                    route = [e - entryN * 0.02] + cells
                }
            }
        }
        // 매끄럽게 (계단 모양을 둥글게)
        if route.count > 3 {
            for _ in 0..<5 {
                var r2 = route
                for i in 1..<(route.count - 1) { r2[i] = (route[i - 1] + route[i] * 2 + route[i + 1]) / 4 }
                route = r2
            }
        }
        let poolW = L.flat(poolP)
        pool = poolW
        path = route.map { L.flat($0) }
        build(L, tint: tint, entryOut: entry.map { L.flat($0 - entryN * 0.35) }, riverNear: riverNear, riverWidth: riverWidth)
        addFish(room.id)
        startSound()
        ok = true
    }

    // MARK: 만들기
    private func build(_ L: Layout, tint: SIMD3<Float>, entryOut: SIMD2<Float>?, riverNear: SIMD3<Float>?, riverWidth: Float) {
        let line = look == .line
        let bedY = floorY + 0.009, waterY = floorY + 0.055
        var bed = Geo(), water = Geo(), stones = Geo(), lines = Geo()
        var g = SeededRNG(seed: UInt64(abs(Int(pool.x * 100)) * 7 + abs(Int(pool.y * 100)) + 3))
        // 물길 띠
        var vAcc: Float = 0
        if path.count > 1 {
            var pl = SIMD2<Float>(0, 0), pr = SIMD2<Float>(0, 0), pv: Float = 0
            for i in path.indices {
                let a = path[max(0, i - 1)], b = path[min(path.count - 1, i + 1)]
                var tdir = b - a
                tdir = simd_length(tdir) > 1e-4 ? simd_normalize(tdir) : SIMD2<Float>(1, 0)
                let n = SIMD2<Float>(-tdir.y, tdir.x)
                let w = halfW * (i == 0 ? 1.15 : 1)
                let l = path[i] + n * w, r = path[i] - n * w
                if i > 0 {
                    vAcc += simd_distance(path[i], path[i - 1])
                    let v1 = vAcc / 0.9
                    for (geo, y, uk) in [(0, bedY, Float(2.2)), (1, waterY, Float(1))] {
                        let a3 = SIMD3<Float>(pl.x, y, pl.y), b3 = SIMD3<Float>(pr.x, y, pr.y), c3 = SIMD3<Float>(r.x, y, r.y), d3 = SIMD3<Float>(l.x, y, l.y)
                        let uvs = [SIMD2<Float>(0, pv * uk), SIMD2<Float>(1, pv * uk), SIMD2<Float>(1, v1 * uk), SIMD2<Float>(0, v1 * uk)]
                        if geo == 0 { bed.quad(a3, b3, c3, d3, uvs[0], uvs[1], uvs[2], uvs[3]) } else { water.quad(a3, b3, c3, d3, uvs[0], uvs[1], uvs[2], uvs[3]) }
                    }
                    if line {
                        lines.stroke(SIMD3<Float>(pl.x, waterY, pl.y), SIMD3<Float>(l.x, waterY, l.y), width: 0.01)
                        lines.stroke(SIMD3<Float>(pr.x, waterY, pr.y), SIMD3<Float>(r.x, waterY, r.y), width: 0.01)
                    }
                    pv = v1
                }
                pl = l; pr = r
                if i % 2 == 1 {
                    for side: Float in [-1, 1] where Float.random(in: 0...1, using: &g) < 0.8 {
                        let p = path[i] + n * side * (w + Float.random(in: 0.0...0.05, using: &g))
                        let sz = Float.random(in: 0.03...0.07, using: &g)
                        stones.rock(at: SIMD3<Float>(p.x, floorY + 0.005, p.y), size: sz, using: &g)
                    }
                }
            }
        }
        // 웅덩이 (둥근 판, 가장자리는 조금 울퉁불퉁)
        let segN = 48
        var ring: [SIMD2<Float>] = []
        for k in 0..<segN {
            let a = Float(k) / Float(segN) * 2 * .pi
            let rr = poolR * (0.92 + 0.08 * sin(a * 3 + 1.3) * cos(a * 2))
            ring.append(pool + SIMD2<Float>(cos(a), sin(a)) * rr)
        }
        for k in 0..<segN {
            let a = ring[k], b = ring[(k + 1) % segN]
            for (geo, y) in [(0, bedY), (1, waterY)] {
                let c3 = SIMD3<Float>(pool.x, y, pool.y), a3 = SIMD3<Float>(a.x, y, a.y), b3 = SIMD3<Float>(b.x, y, b.y)
                let sc: Float = geo == 0 ? 2.2 : 1
                let ua = (a - pool) / 0.9 * sc, ub = (b - pool) / 0.9 * sc
                if geo == 0 { bed.quad(c3, a3, b3, c3, .zero, ua, ub, .zero) } else { water.quad(c3, a3, b3, c3, .zero, ua, ub, .zero) }
            }
            if line { lines.stroke(SIMD3<Float>(a.x, waterY, a.y), SIMD3<Float>(b.x, waterY, b.y), width: 0.012) }
            if k % 2 == 0 {
                let out = simd_normalize(a - pool)
                let p = a + out * Float.random(in: 0.0...0.06, using: &g)
                stones.rock(at: SIMD3<Float>(p.x, floorY + 0.005, p.y), size: Float.random(in: 0.035...0.09, using: &g), using: &g)
            }
        }
        if let e = bed.entity("creekBed", Tex.unlit("pebble", tint: Worlds.safe(tint * 0.62, min: 0.25))) { local.addChild(e) }
        if let e = stones.entity("creekStones", Tex.unlit("rock", tint: Worlds.safe(tint * 0.8, min: 0.3))) { local.addChild(e) }
        if !line {
            // 맑은 물: 옅게 비치는 물빛 + 위로 흐르는 반짝임 (바닥·물고기가 비쳐 보임)
            var wm = Tex.unlit("river", tint: Worlds.safe(tint, min: 0.35) * SIMD3<Float>(0.75, 1.0, 1.05))
            wm.blending = .transparent(opacity: .init(floatLiteral: 0.32))
            if let e = water.entity("creekWater", wm) {
                local.addChild(e)
                flows.append((e, wm, 0.25, 0))
            }
            var hm = Tex.unlit("river_hi", tint: [1, 1, 1])
            if let mk = Tex.get("river_hi_a", raw: true) {
                var tp = MaterialParameters.Texture(mk); tp.sampler = Tex.tiling
                hm.blending = .transparent(opacity: .init(scale: 0.7, texture: tp))
            }
            var hg = water
            hg.pos = hg.pos.map { SIMD3<Float>($0.x, $0.y + 0.002, $0.z) }
            if let e = hg.entity("creekHi", hm) {
                local.addChild(e)
                flows.append((e, hm, 0.45, 0.4))
            }
        } else if let e = lines.entity("creekLines", Ink.line) {
            local.addChild(e)
        }
        // 벽 너머: 큰 강에서 갈라져 이 벽까지 오는 물길 (하늘 세계)
        if let eo = entryOut, let rn = riverNear {
            let a = SIMD2<Float>(rn.x, rn.z)
            var pts: [SIMD2<Float>] = []
            let n = 24
            let side = SIMD2<Float>(-(eo - a).y, (eo - a).x) * 0.12
            var blockedOut = false
            for i in 0...n {
                let k = Float(i) / Float(n)
                let p = a + (eo - a) * k + side * sin(k * .pi)
                if i < n - 2 && L.walkable(L.plane(p.x, p.y)) { blockedOut = true }
                pts.append(p)
            }
            if !blockedOut {
                var wg = Geo(), bg = Geo(), rk = Geo()
                var va: Float = 0
                var pl = SIMD2<Float>(0, 0), pr = SIMD2<Float>(0, 0), pv: Float = 0
                for i in pts.indices {
                    let p0 = pts[max(0, i - 1)], p1 = pts[min(pts.count - 1, i + 1)]
                    let td = simd_normalize(p1 - p0)
                    let nn = SIMD2<Float>(-td.y, td.x)
                    let w = (riverWidth * 0.3) * (1 - Float(i) / Float(n)) + halfW * 1.2 * Float(i) / Float(n)
                    let l = pts[i] + nn * w, r = pts[i] - nn * w
                    if i > 0 {
                        va += simd_distance(pts[i], pts[i - 1])
                        let v1 = va / 3.5
                        let y = floorY - 0.013
                        wg.quad(SIMD3<Float>(pl.x, y, pl.y), SIMD3<Float>(pr.x, y, pr.y), SIMD3<Float>(r.x, y, r.y), SIMD3<Float>(l.x, y, l.y),
                                SIMD2<Float>(0, pv), SIMD2<Float>(1, pv), SIMD2<Float>(1, v1), SIMD2<Float>(0, v1))
                        let yb = floorY - 0.02
                        let bl = pl + simd_normalize(pl - pr) * 0.4, br = pr + simd_normalize(pr - pl) * 0.4
                        let cl = l + simd_normalize(l - r) * 0.4, cr = r + simd_normalize(r - l) * 0.4
                        bg.quad(SIMD3<Float>(bl.x, yb, bl.y), SIMD3<Float>(br.x, yb, br.y), SIMD3<Float>(cr.x, yb, cr.y), SIMD3<Float>(cl.x, yb, cl.y),
                                SIMD2<Float>(0, pv * 2), SIMD2<Float>(1, pv * 2), SIMD2<Float>(1, v1 * 2), SIMD2<Float>(0, v1 * 2))
                        pv = v1
                    }
                    pl = l; pr = r
                    if i % 3 == 1 {
                        for s: Float in [-1, 1] {
                            let p = pts[i] + nn * s * (w + 0.15)
                            rk.rock(at: SIMD3<Float>(p.x, floorY - 0.04, p.y), size: Float.random(in: 0.12...0.3, using: &g), using: &g)
                        }
                    }
                }
                if let e = bg.entity("branchBank", Tex.unlit("pebble", tint: Worlds.safe(tint * 0.55, min: 0.2))) { world.addChild(e) }
                let wm = Tex.unlit("river", tint: Worlds.safe(tint, min: 0.2))
                if let e = wg.entity("branchWater", wm) { world.addChild(e); flows.append((e, wm, 0.13, 0)) }
                if let e = rk.entity("branchRocks", Tex.unlit("rock", tint: Worlds.safe(tint * 0.85, min: 0.25))) { world.addChild(e) }
            }
        }
    }

    // MARK: 물고기
    /// 물고기 몸: 머리에서 꼬리로 갈수록 가늘어지는 납작한 몸 + 꼬리지느러미(따로 흔들림) + 등지느러미
    private func fishMesh(_ s: Float) -> (MeshResource?, MeshResource?) {
        var body = Geo()
        let nL = 12, nR = 10
        func rad(_ k: Float) -> Float { 0.13 * pow(sin(.pi * min(1, max(0, k)) * 0.95 + 0.08), 0.85) }
        for i in 0..<nL {
            for j in 0..<nR {
                let k0 = Float(i) / Float(nL), k1 = Float(i + 1) / Float(nL)
                let a0 = Float(j) / Float(nR) * 2 * .pi, a1 = Float(j + 1) / Float(nR) * 2 * .pi
                func p(_ k: Float, _ a: Float) -> SIMD3<Float> {
                    let r = rad(k) * s
                    return SIMD3<Float>((0.5 - k) * s, sin(a) * r, cos(a) * r * 0.55)         // x 앞, y 위, z 옆 (옆으로 납작)
                }
                func uv(_ k: Float, _ a: Float) -> SIMD2<Float> { SIMD2<Float>(k, 0.5 + 0.5 * sin(a)) }    // 등(위)=1 → 그림 위
                body.quad(p(k0, a0), p(k0, a1), p(k1, a1), p(k1, a0), uv(k0, a0), uv(k0, a1), uv(k1, a1), uv(k1, a0))
            }
        }
        // 등지느러미
        body.quad(SIMD3<Float>(0.1 * s, 0.1 * s, 0), SIMD3<Float>(-0.15 * s, 0.09 * s, 0), SIMD3<Float>(-0.2 * s, 0.17 * s, 0), SIMD3<Float>(0.02 * s, 0.17 * s, 0),
                  SIMD2<Float>(0.4, 0.95), SIMD2<Float>(0.65, 0.95), SIMD2<Float>(0.7, 1), SIMD2<Float>(0.45, 1))
        var tail = Geo()
        tail.quad(SIMD3<Float>(0, 0.015 * s, 0), SIMD3<Float>(-0.22 * s, 0.13 * s, 0), SIMD3<Float>(-0.17 * s, 0, 0), SIMD3<Float>(-0.22 * s, -0.13 * s, 0),
                  SIMD2<Float>(0.9, 0.55), SIMD2<Float>(1, 0.95), SIMD2<Float>(0.97, 0.5), SIMD2<Float>(1, 0.05))
        return (body.mesh("fish"), tail.mesh("fishTail"))
    }

    private func addFish(_ seed: Int) {
        let area = Float.pi * poolR * poolR + Float(path.count) * 0.1 * halfW * 2
        let n = max(5, min(14, Int(area / 0.07)))
        var g = SeededRNG(seed: UInt64(seed * 733 + 41))
        var mats: [RealityKit.Material] = []
        for i in 0..<6 {
            if look == .line { mats.append(Ink.paper(0)); continue }
            var m = UnlitMaterial(color: .white)
            if let tx = Tex.with(look == .color ? .color : .mono, { Tex.get("fish_\(i)") }) {
                var tp = MaterialParameters.Texture(tx); tp.sampler = Tex.clamp
                m.color = .init(tint: .white, texture: tp)
            }
            mats.append(m)
        }
        for _ in 0..<n {
            let f = Fish()
            let big = Float.random(in: 0...1, using: &g) < 0.25
            f.size = big ? Float.random(in: 0.1...0.15, using: &g) : Float.random(in: 0.045...0.09, using: &g)
            f.cruise = Float.random(in: 0.06...0.14, using: &g) * (big ? 0.8 : 1.2)
            f.speed = f.cruise
            f.depth = Float.random(in: 0.02...0.036, using: &g)
            f.head = Float.random(in: 0...(2 * .pi), using: &g)
            f.wag = Float.random(in: 0...6, using: &g)
            let a = Float.random(in: 0...(2 * .pi), using: &g)
            f.pos = pool + SIMD2<Float>(cos(a), sin(a)) * poolR * Float.random(in: 0...0.7, using: &g)
            let (bm, tm) = fishMesh(f.size)
            let mat = mats[Int(g.next() % 6)]
            if let bm { f.e.addChild(ModelEntity(mesh: bm, materials: [mat])) }
            if let tm {
                let te = ModelEntity(mesh: tm, materials: [mat])
                f.tail.position = [-0.36 * f.size, 0, 0]
                f.tail.addChild(te)
                f.e.addChild(f.tail)
            }
            if look == .line {
                var l = Geo()
                l.stroke([0.5 * f.size, 0, 0], [-0.4 * f.size, 0, 0], width: 0.004)
                if let e = l.entity("fishLine", Ink.line) { f.e.addChild(e) }
            }
            local.addChild(f.e)
            fish.append(f)
        }
    }

    /// 물 안인지 (웅덩이 또는 물길, 가장자리 m 안쪽)
    private func inWater(_ p: SIMD2<Float>, margin: Float) -> Bool {
        if simd_distance(p, pool) < poolR * 0.92 - margin { return true }
        guard path.count > 1 else { return false }
        for i in 0..<(path.count - 1) {
            let a = path[i], b = path[i + 1], ab = b - a
            let k = max(0, min(1, simd_dot(p - a, ab) / max(1e-6, simd_length_squared(ab))))
            if simd_distance(p, a + ab * k) < halfW - margin { return true }
        }
        return false
    }

    private func startSound() {
        guard let u = Bundle.main.url(forResource: "stream_loop", withExtension: "wav", subdirectory: "sfx") else { return }
        let cfg = AudioFileResource.Configuration(loadingStrategy: .preload, shouldLoop: true)
        guard let r = try? AudioFileResource.load(contentsOf: u, withName: nil, configuration: cfg) else { return }
        let e = Entity()
        var sa = SpatialAudioComponent()
        sa.gain = -14
        e.components.set(sa)
        e.position = SIMD3<Float>(pool.x, floorY + 0.1, pool.y)
        local.addChild(e)
        hum = e.playAudio(r)
    }

    func stop() { hum?.stop() }

    // MARK: 매 프레임
    func tick(_ dt: Float, hands: [SIMD3<Float>]) {
        t += dt
        for i in flows.indices {
            var f = flows[i]
            f.3 = (f.3 + f.2 * dt).truncatingRemainder(dividingBy: 1)
            f.1.textureCoordinateTransform.offset = SIMD2<Float>(0, f.3)
            f.0.model?.materials = [f.1]
            flows[i] = f
        }
        var g = SystemRandomNumberGenerator()
        // 손이 물 가까이(물 위 50cm 안) 오면 둘레 물고기가 놀라 흩어짐
        let wet = hands.filter { $0.y - floorY < 0.5 && inWater(SIMD2<Float>($0.x, $0.z), margin: -0.15) }
        for f in fish {
            for h in wet {
                let hp = SIMD2<Float>(h.x, h.z)
                let d = simd_distance(hp, f.pos)
                if d < 0.4 && f.dart <= 0 {
                    f.dart = Float.random(in: 0.5...0.9, using: &g)
                    let away = f.pos - hp
                    if simd_length(away) > 0.001 { f.head = atan2(away.y, away.x) + Float.random(in: -0.4...0.4, using: &g) }
                }
            }
            // 가끔 방향을 바꾸거나 휙 내달림
            f.turn += (Float.random(in: -1...1, using: &g) * 1.6 - f.turn) * min(1, dt * 0.8)
            if f.dart <= 0 && Float.random(in: 0...1, using: &g) < dt * 0.04 { f.dart = Float.random(in: 0.3...0.6, using: &g) }
            f.dart -= dt
            let want = f.dart > 0 ? f.cruise * 4.5 : f.cruise * (0.6 + 0.4 * sin(t * 0.3 + f.wag))
            f.speed += (want - f.speed) * min(1, dt * (f.dart > 0 ? 6 : 1.5))
            f.head += f.turn * dt * (f.dart > 0 ? 0.3 : 1)
            var dir = SIMD2<Float>(cos(f.head), sin(f.head))
            var np = f.pos + dir * f.speed * dt
            // 물 밖으로 나가려 하면 물 안쪽(웅덩이 가운데·물길 따라)으로 돌아섬
            if !inWater(np, margin: f.size * 0.4) {
                let back = pool - f.pos
                let tgt = atan2(back.y, back.x)
                var dh = tgt - f.head
                while dh > .pi { dh -= 2 * .pi }
                while dh < -.pi { dh += 2 * .pi }
                f.head += dh * min(1, dt * 4)
                dir = SIMD2<Float>(cos(f.head), sin(f.head))
                np = f.pos + dir * f.speed * dt * 0.3
                if !inWater(np, margin: 0) { np = f.pos }
            }
            f.pos = np
            f.wag += dt * (6 + f.speed * 60)
            let bob = sin(t * 1.3 + f.wag * 0.1) * 0.004
            f.e.position = SIMD3<Float>(np.x, floorY + 0.009 + f.depth + bob, np.y)
            f.e.orientation = simd_quatf(angle: -f.head, axis: [0, 1, 0]) * simd_quatf(angle: sin(f.wag) * 0.08, axis: [0, 1, 0])
            f.tail.orientation = simd_quatf(angle: sin(f.wag) * (0.35 + min(0.4, f.speed * 2)), axis: [0, 1, 0])
        }
    }
}
