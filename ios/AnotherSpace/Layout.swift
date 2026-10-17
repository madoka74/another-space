import Foundation
import simd

/// 벽 한 줄 (평면 좌표 m). n: 걸을 수 있는 쪽(방 안)으로 향함
struct WallSeg: Sendable {
    var a: SIMD2<Float>
    var b: SIMD2<Float>
    var n: SIMD2<Float>
    var room: Int
    var window: Bool
    var inner = false          // 방과 방 사이 벽 (양쪽 방이 각자 1cm씩 안쪽에 하나씩 세움)
}

/// 문 하나 = 문·통로 사각형 하나가 두 방을 잇는 곳 (평면 좌표 m).
/// 문짝은 각 방의 실제 입구 줄(그 방 칸이 끝나는 곳 = 양옆 벽과 같은 줄)에 하나씩 섬 → 벽과 문짝 사이에 틈이 없음
struct DoorSeg: Sendable {
    var roomA: Int
    var roomB: Int
    var alongU: Bool                // true: 방 A→B 가 u 방향으로 건너감
    var nA: SIMD2<Float>            // 방 A 쪽을 향함 (B 쪽은 -nA)
    var pA: Float                   // 방 A 입구 줄 (건너가는 축 좌표)
    var pB: Float                   // 방 B 입구 줄
    var s0: Float                   // 문 폭 (다른 축 좌표)
    var s1: Float

    var lo: SIMD2<Float> { alongU ? SIMD2<Float>(min(pA, pB), s0) : SIMD2<Float>(s0, min(pA, pB)) }
    var hi: SIMD2<Float> { alongU ? SIMD2<Float>(max(pA, pB), s1) : SIMD2<Float>(s1, max(pA, pB)) }
    var mid: SIMD2<Float> { (lo + hi) / 2 }
    var width: Float { s1 - s0 }
    /// 방 r 쪽 입구 변 (a, b, 그 방을 향한 방향)
    func edge(for r: Int) -> (SIMD2<Float>, SIMD2<Float>, SIMD2<Float>) {
        let n = r == roomA ? nA : -nA
        let p = r == roomA ? pA : pB
        return alongU ? (SIMD2<Float>(p, s0), SIMD2<Float>(p, s1), n) : (SIMD2<Float>(s0, p), SIMD2<Float>(s1, p), n)
    }
    /// 문 자리(두 입구 줄 사이)까지 거리 (안이면 0)
    func dist(_ p: SIMD2<Float>) -> Float { simd_length(simd_max(simd_max(lo - p, p - hi), SIMD2<Float>(0, 0))) }
    func inside(_ p: SIMD2<Float>) -> Bool { p.x > lo.x && p.x < hi.x && p.y > lo.y && p.y < hi.y }
    /// + 면 방 A 쪽, - 면 방 B 쪽
    func side(_ p: SIMD2<Float>) -> Float { simd_dot(p - mid, nA) }
    /// 문 자리 근처 (문짝 앞뒤 margin m, 폭 양옆 5cm) — 실제 문짝 그물은 여기서 따로 다룸
    func zone(_ p: SIMD2<Float>, margin: Float) -> Bool {
        let a = alongU ? p.x : p.y, s = alongU ? p.y : p.x
        return s > s0 - 0.05 && s < s1 + 0.05 && a > min(pA, pB) - margin && a < max(pA, pB) + margin
    }
}

/// 사각형들을 5cm 칸으로 그려 둔 탐험용 배치.
/// - 걸을 수 있는 곳 = 방 사각형 + 문·통로 사각형
/// - 벽 = 걸을 수 있는 칸과 아닌 칸 사이 + 서로 다른 방이 맞닿은 곳. 문·통로 사각형이 덮은 곳은 벽 없이 뚫림
///   (방끼리 딱 붙여 두면 그 사이에 벽이 서고, 실제 문 자리에 문 사각형을 경계에 걸쳐 그리면 그곳만 열림)
/// - 창 = 벽 바로 바깥 40cm 안에 스캔이 창으로 알아본 칸이 있는 곳
struct Layout: Sendable {
    static let res: Float = 0.05
    let u0: Float, v0: Float
    let W: Int, H: Int
    let walk: [UInt8]           // 0 아님, 1 방, 2 문·통로
    let door: [Bool]            // 문·통로 사각형이 덮은 칸 (방 칸 위에 걸쳐도)
    let owner: [UInt8]          // 그 칸의 방 (문·통로는 가장 가까운 방)
    let dist: [Int16]           // 걸을 수 없는 칸까지 거리 (칸)
    let ox: Float, oz: Float
    let ex: SIMD2<Float>, ez: SIMD2<Float>
    let floorY: Float
    let ceil: [Float]           // 방 id → 천장 높이(바닥에서)
    let walls: [WallSeg]
    let doors: [DoorSeg]        // 서로 다른 방 사이에서 문·통로로 뚫린 곳

    init(_ d: SpaceData) {
        let shapes = d.shapes
        let r = Layout.res
        var lo = SIMD2<Float>(0, 0), hi = SIMD2<Float>(1, 1)
        if let f = shapes.first {
            lo = SIMD2<Float>(f.u0, f.v0); hi = SIMD2<Float>(f.u1, f.v1)
            for s in shapes { lo = simd_min(lo, SIMD2<Float>(s.u0, s.v0)); hi = simd_max(hi, SIMD2<Float>(s.u1, s.v1)) }
        }
        // 원점은 5cm 배수에 맞추고 둘레에 한 칸씩 여유
        let bu = (lo.x / r).rounded(.down) * r - r, bv = (lo.y / r).rounded(.down) * r - r
        let w = min(1200, max(4, Int(((hi.x - bu) / r).rounded(.up)) + 2))
        let h = min(1200, max(4, Int(((hi.y - bv) / r).rounded(.up)) + 2))
        u0 = bu; v0 = bv; W = w; H = h
        ox = d.rec.ox; oz = d.rec.oz; ex = d.rec.ex; ez = d.rec.ez; floorY = d.rec.floorY
        var c = [Float](repeating: 2.4, count: 256)
        for rm in d.rec.rooms where rm.id > 0 && rm.id < 256 { c[rm.id] = rm.ceil }
        ceil = c

        var wk = [UInt8](repeating: 0, count: w * h)
        var ow = [UInt8](repeating: 0, count: w * h)
        func range(_ s: ShapeRec) -> (Int, Int, Int, Int) {
            (max(0, Int(((s.u0 - bu) / r).rounded())), max(0, Int(((s.v0 - bv) / r).rounded())),
             min(w, Int(((s.u1 - bu) / r).rounded())), min(h, Int(((s.v1 - bv) / r).rounded())))
        }
        for s in shapes where !s.isDoor && s.room < 256 {           // 방 (나중 것이 위)
            let (a0, b0, a1, b1) = range(s)
            guard a1 > a0, b1 > b0 else { continue }
            for v in b0..<b1 { for u in a0..<a1 { wk[v * w + u] = 1; ow[v * w + u] = UInt8(s.room) } }
        }
        var dm = [Bool](repeating: false, count: w * h)
        for s in shapes where s.isDoor {                            // 문·통로: 방이 아닌 칸은 걸을 수 있게, 방 칸 위면 그 경계의 벽을 뚫음
            let (a0, b0, a1, b1) = range(s)
            guard a1 > a0, b1 > b0 else { continue }
            for v in b0..<b1 { for u in a0..<a1 { dm[v * w + u] = true; if wk[v * w + u] == 0 { wk[v * w + u] = 2 } } }
        }
        // 문·통로 칸의 방 = 맞닿은 방 중 가까운 것 (방에서 퍼져 나감)
        var q: [Int] = []
        for i in 0..<(w * h) where wk[i] == 1 { q.append(i) }
        var qi = 0
        while qi < q.count {
            let i = q[qi]; qi += 1
            let u = i % w, v = i / w
            for (du, dv) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let uu = u + du, vv = v + dv
                guard uu >= 0, vv >= 0, uu < w, vv < h else { continue }
                let j = vv * w + uu
                if wk[j] == 2 && ow[j] == 0 { ow[j] = ow[i]; q.append(j) }
            }
        }
        for i in 0..<(w * h) where wk[i] == 2 && ow[i] == 0 { wk[i] = 0 }      // 어느 방과도 안 닿은 통로는 버림
        walk = wk; owner = ow
        for i in 0..<(w * h) where wk[i] == 0 { dm[i] = false }
        door = dm
        /// 두 칸 사이에 방과 방 사이 벽이 서는지 (둘 다 걸을 수 있고, 방이 다르고, 문이 덮지 않음)
        func split(_ i: Int, _ j: Int) -> Bool {
            wk[i] != 0 && wk[j] != 0 && ow[i] != ow[j] && !dm[i] && !dm[j]
        }
        // 벽까지 거리 (4방향 퍼짐): 걸을 수 없는 칸 + 방과 방 사이 벽 바로 옆 칸에서 시작
        var ds = [Int16](repeating: Int16.max, count: w * h)
        var fq: [Int] = []
        for i in 0..<(w * h) {
            if wk[i] == 0 { ds[i] = 0; fq.append(i); continue }
            let u = i % w, v = i / w
            if (u + 1 < w && split(i, i + 1)) || (u > 0 && split(i, i - 1)) || (v + 1 < h && split(i, i + w)) || (v > 0 && split(i, i - w)) {
                ds[i] = 0; fq.append(i)
            }
        }
        var fi = 0
        while fi < fq.count {
            let i = fq[fi]; fi += 1
            let u = i % w, v = i / w
            for (du, dv) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let uu = u + du, vv = v + dv
                guard uu >= 0, vv >= 0, uu < w, vv < h else { continue }
                let j = vv * w + uu
                if ds[j] > ds[i] + 1 { ds[j] = ds[i] + 1; fq.append(j) }
            }
        }
        dist = ds

        // 벽: 칸 경계마다 만들고, 같은 줄·같은 방·같은 종류(창 여부)는 이어 붙임
        func isWin(_ p: SIMD2<Float>, _ out: SIMD2<Float>) -> Bool {
            for k in 1...4 {
                let q = (p + out * (Float(k) * 0.1)) / d.rec.cell
                if d.windowAt(Int(q.x.rounded(.down)), Int(q.y.rounded(.down))) { return true }
            }
            return false
        }
        var segs: [WallSeg] = []
        /// 같은 줄에서 이어지는 조각을 합침 (lane: 0 = 위·왼쪽 칸을 향한 벽, 1 = 아래·오른쪽 칸을 향한 벽)
        func merge(_ cur: inout [WallSeg?], _ lane: Int, _ seg: WallSeg?) {
            if let s = seg, var c = cur[lane], c.room == s.room, c.n == s.n, c.window == s.window, c.inner == s.inner,
               simd_distance(c.b, s.a) < 1e-4 {
                c.b = s.b; cur[lane] = c
            } else {
                if let c = cur[lane] { segs.append(c) }
                cur[lane] = seg
            }
        }
        // 가로 경계 (v 줄 사이): 위 칸(v-1)과 아래 칸(v)
        for v in 0...h {
            var cur: [WallSeg?] = [nil, nil]
            for u in 0...w {
                var lanes: [WallSeg?] = [nil, nil]
                if u < w {
                    let iu = v > 0 ? (v - 1) * w + u : -1, id = v < h ? v * w + u : -1
                    let up = iu >= 0 ? wk[iu] : 0, dn = id >= 0 ? wk[id] : 0
                    let a = SIMD2<Float>(bu + Float(u) * r, bv + Float(v) * r)
                    let b = a + SIMD2<Float>(r, 0)
                    if (up == 0) != (dn == 0) {
                        let n = SIMD2<Float>(0, up != 0 ? -1 : 1)
                        let seg = WallSeg(a: a, b: b, n: n, room: Int(ow[up != 0 ? iu : id]), window: isWin((a + b) / 2, -n))
                        lanes[up != 0 ? 0 : 1] = seg
                    } else if iu >= 0 && id >= 0 && split(iu, id) {
                        lanes[0] = WallSeg(a: a, b: b, n: SIMD2<Float>(0, -1), room: Int(ow[iu]), window: false, inner: true)
                        lanes[1] = WallSeg(a: a, b: b, n: SIMD2<Float>(0, 1), room: Int(ow[id]), window: false, inner: true)
                    }
                }
                merge(&cur, 0, lanes[0]); merge(&cur, 1, lanes[1])
            }
            for c in cur { if let c { segs.append(c) } }
        }
        // 세로 경계 (u 줄 사이): 왼 칸(u-1)과 오른 칸(u)
        for u in 0...w {
            var cur: [WallSeg?] = [nil, nil]
            for v in 0...h {
                var lanes: [WallSeg?] = [nil, nil]
                if v < h {
                    let il = u > 0 ? v * w + u - 1 : -1, ir = u < w ? v * w + u : -1
                    let lf = il >= 0 ? wk[il] : 0, rt = ir >= 0 ? wk[ir] : 0
                    let a = SIMD2<Float>(bu + Float(u) * r, bv + Float(v) * r)
                    let b = a + SIMD2<Float>(0, r)
                    if (lf == 0) != (rt == 0) {
                        let n = SIMD2<Float>(lf != 0 ? -1 : 1, 0)
                        let seg = WallSeg(a: a, b: b, n: n, room: Int(ow[lf != 0 ? il : ir]), window: isWin((a + b) / 2, -n))
                        lanes[lf != 0 ? 0 : 1] = seg
                    } else if il >= 0 && ir >= 0 && split(il, ir) {
                        lanes[0] = WallSeg(a: a, b: b, n: SIMD2<Float>(-1, 0), room: Int(ow[il]), window: false, inner: true)
                        lanes[1] = WallSeg(a: a, b: b, n: SIMD2<Float>(1, 0), room: Int(ow[ir]), window: false, inner: true)
                    }
                }
                merge(&cur, 0, lanes[0]); merge(&cur, 1, lanes[1])
            }
            for c in cur { if let c { segs.append(c) } }
        }
        // 방과 방 사이 벽은 각자 방 쪽으로 1cm 들여 세움 (두 벽이 겹쳐 깜빡이지 않게)
        // 모든 벽은 양 끝을 3cm씩 늘려 이어지는 곳(모서리·꺾임·문 옆)에 머리카락 같은 틈이 안 생기게
        segs = segs.map { s in
            var t = s
            if s.inner { t.a += s.n * 0.01; t.b += s.n * 0.01 }
            let len = simd_distance(t.a, t.b)
            if len > 0.001 {
                let d = (t.b - t.a) / len
                t.a -= d * 0.03; t.b += d * 0.03
            }
            return t
        }
        // 문: 문·통로 사각형마다, 안쪽과 둘레 10cm의 방 칸을 세어 가장 많이 닿은 두 방을 잇는 문으로.
        // 두 방이 어느 방향으로 놓였는지(무게중심)로 건너가는 방향과 양쪽 입구 변을 정함
        var dl: [DoorSeg] = []
        for sh in shapes where sh.isDoor {
            let (a0, b0, a1, b1) = range(sh)
            guard a1 > a0, b1 > b0 else { continue }
            var cnt: [Int: Int] = [:]
            var sum: [Int: SIMD2<Float>] = [:]
            for v in max(0, b0 - 2)..<min(h, b1 + 2) {
                for u in max(0, a0 - 2)..<min(w, a1 + 2) {
                    let i = v * w + u
                    guard wk[i] == 1 else { continue }
                    let rr = Int(ow[i])
                    cnt[rr, default: 0] += 1
                    sum[rr, default: SIMD2<Float>(0, 0)] += SIMD2<Float>(Float(u), Float(v))
                }
            }
            let top = cnt.sorted { $0.value > $1.value }
            guard top.count >= 2, top[1].value >= 3 else { continue }
            let ra = top[0].key, rb = top[1].key
            let ca = (sum[ra] ?? .zero) / Float(top[0].value), cb = (sum[rb] ?? .zero) / Float(top[1].value)
            let dd = cb - ca
            let alongU = abs(dd.x) >= abs(dd.y)
            let aLow = alongU ? dd.x > 0 : dd.y > 0              // 방 A가 낮은 쪽(왼쪽·위)에 있음
            // 각 방 칸이 문 폭 안에서 끝나는 줄 = 그 방의 입구 줄 (양옆 벽과 같은 줄)
            var aMin = Int.max, aMax = Int.min, bMin = Int.max, bMax = Int.min
            for v in max(0, b0 - 2)..<min(h, b1 + 2) {
                for u in max(0, a0 - 2)..<min(w, a1 + 2) {
                    // 문 폭 안의 칸만 (건너가는 축으로는 둘레 10cm까지)
                    if alongU ? (v < b0 || v >= b1) : (u < a0 || u >= a1) { continue }
                    let i = v * w + u
                    guard wk[i] == 1 else { continue }
                    let c = alongU ? u : v
                    if Int(ow[i]) == ra { aMin = min(aMin, c); aMax = max(aMax, c) }
                    if Int(ow[i]) == rb { bMin = min(bMin, c); bMax = max(bMax, c) }
                }
            }
            let base = alongU ? bu : bv
            let lo = alongU ? sh.u0 : sh.v0, hi = alongU ? sh.u1 : sh.v1
            let pA = aMax >= aMin ? base + Float(aLow ? aMax + 1 : aMin) * r : (aLow ? lo : hi)
            let pB = bMax >= bMin ? base + Float(aLow ? bMin : bMax + 1) * r : (aLow ? hi : lo)
            let nA = alongU ? SIMD2<Float>(aLow ? -1 : 1, 0) : SIMD2<Float>(0, aLow ? -1 : 1)
            dl.append(DoorSeg(roomA: ra, roomB: rb, alongU: alongU, nA: nA, pA: pA, pB: pB,
                              s0: alongU ? sh.v0 : sh.u0, s1: alongU ? sh.v1 : sh.u1))
        }
        doors = dl
        // 창은 50cm 안 되면 벽으로 (조각난 창 방지)
        walls = segs.map { s in
            var t = s
            if t.window && simd_distance(t.a, t.b) < 0.5 { t.window = false }
            return t
        }
    }

    /// 저장 좌표 (x, z) → 평면 좌표
    func plane(_ x: Float, _ z: Float) -> SIMD2<Float> {
        let d = SIMD2<Float>(x - ox, z - oz)
        return SIMD2<Float>(simd_dot(d, ex), simd_dot(d, ez))
    }
    /// 평면 좌표 → 저장 좌표 (x, z)
    func flat(_ p: SIMD2<Float>) -> SIMD2<Float> { SIMD2<Float>(ox, oz) + ex * p.x + ez * p.y }

    private func index(_ p: SIMD2<Float>) -> Int? {
        let u = Int(((p.x - u0) / Layout.res).rounded(.down)), v = Int(((p.y - v0) / Layout.res).rounded(.down))
        return (u >= 0 && v >= 0 && u < W && v < H) ? v * W + u : nil
    }

    /// 그 자리의 방 (걸을 수 없는 곳이면 0)과 벽까지 거리(m)
    func at(x: Float, z: Float) -> (room: Int, wall: Float) {
        guard let i = index(plane(x, z)), walk[i] != 0 else { return (0, 0) }
        return (Int(owner[i]), Float(dist[i]) * Layout.res)
    }

    /// 근처(반경 m)까지 둘러봐서 가장 가까운 방 — 문틀·벽 사이를 지날 때 깜박이지 않게
    func roomNear(x: Float, z: Float, radius: Float) -> Int {
        let p = plane(x, z)
        if let i = index(p), walk[i] != 0 { return Int(owner[i]) }
        let k = Int((radius / Layout.res).rounded(.up))
        guard let c = index(p) else { return 0 }
        let cu = c % W, cv = c / W
        var best = 0, bd = Int.max
        for dv in -k...k {
            for du in -k...k {
                let u = cu + du, v = cv + dv
                guard u >= 0, v >= 0, u < W, v < H, walk[v * W + u] != 0 else { continue }
                if du * du + dv * dv < bd { bd = du * du + dv * dv; best = Int(owner[v * W + u]) }
            }
        }
        return best
    }

    /// 서로 맞닿거나(문·통로 포함) 벽 하나(30cm 안)를 사이에 둔 방들
    func neighbors() -> [Int: Set<Int>] {
        var out: [Int: Set<Int>] = [:]
        let gap = 6                                            // 30cm
        for v in 0..<H {
            for u in 0..<W where walk[v * W + u] != 0 {
                let a = Int(owner[v * W + u])
                for (du, dv) in [(1, 0), (0, 1)] {
                    for k in 1...gap {
                        let uu = u + du * k, vv = v + dv * k
                        guard uu < W, vv < H else { break }
                        let j = vv * W + uu
                        if walk[j] == 0 { continue }
                        let b = Int(owner[j])
                        if b != a && b != 0 && a != 0 { out[a, default: []].insert(b); out[b, default: []].insert(a) }
                        break
                    }
                }
            }
        }
        return out
    }

    /// 방 r이 차지하는 칸(문·통로 포함)을 직사각형들로 (평면 좌표 m)
    func rects(_ room: Int) -> [(SIMD2<Float>, SIMD2<Float>)] {
        var used = [Bool](repeating: false, count: W * H)
        func mine(_ i: Int) -> Bool { walk[i] != 0 && Int(owner[i]) == room && !used[i] }
        var out: [(SIMD2<Float>, SIMD2<Float>)] = []
        for v in 0..<H {
            var u = 0
            while u < W {
                if !mine(v * W + u) { u += 1; continue }
                var u1 = u
                while u1 < W, mine(v * W + u1) { u1 += 1 }
                var v1 = v + 1
                while v1 < H {
                    var full = true
                    for k in u..<u1 where !mine(v1 * W + k) { full = false; break }
                    if !full { break }
                    v1 += 1
                }
                for vv in v..<v1 { for k in u..<u1 { used[vv * W + k] = true } }
                out.append((SIMD2<Float>(u0 + Float(u) * Layout.res, v0 + Float(v) * Layout.res),
                            SIMD2<Float>(u0 + Float(u1) * Layout.res, v0 + Float(v1) * Layout.res)))
                u = u1
            }
        }
        return out
    }
}
