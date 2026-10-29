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
    /// 바깥벽인데 벽 너머 45cm 안에 다른 방이 있음 (실제 벽 두께만큼 떨어진 옆방) → 그 방 번호, 없으면 0.
    /// 그 옆방이 같은 테마(같은 세계)일 때만 이 벽에 창을 내지 않음 — 방 세계(RoomWorld)가 테마를 보고 정함.
    /// (같은 세계면 두 방이 한 공간으로 이어져 보여 창이 서로 겹쳐 보였음. 다른 테마면 창을 그대로 냄)
    var nearRoom = 0
    /// 벽 너머 2m 안에 걸을 수 있는 곳이 있음: -1 = 이 방 자신(ㄱ자 방의 다른 쪽·같은 방 통로), 그 밖 = 그 방 번호, 0 = 없음.
    /// 창(바깥으로 열린 벽)은 그 너머가 바깥일 때만 — 이 방 자신이면 늘, 다른 방이면 같은 테마일 때 창을 내지 않음
    /// (예전엔 45cm 안만 봐서, 사이에 통로·옷방이 낀 벽은 너머에 방이 있어도 양쪽에 창이 났음)
    var behind = 0
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
    /// 통창·유리문 (방 구성에서 표시): 열림·닫힘을 알 수 없어 늘 닫힌 실제 문처럼 — 다가가면 현실 원
    var glass = false

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
    func zone(_ p: SIMD2<Float>, margin: Float, side: Float = 0.05) -> Bool {
        let a = alongU ? p.x : p.y, s = alongU ? p.y : p.x
        return s > s0 - side && s < s1 + side && a > min(pA, pB) - margin && a < max(pA, pB) + margin
    }
    /// 한 방 안의 문 (방을 나누지 않은 실제 문 자리) — 늘 '같은 세계'처럼 다룸
    var single: Bool { roomA == roomB }
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
        // 문: 문·통로 사각형마다, 안쪽과 둘레 10cm의 방 칸을 세어 가장 많이 닿은 두 방을 잇는 문으로.
        // 두 방이 어느 방향으로 놓였는지(무게중심)로 건너가는 방향과 양쪽 입구 줄을 정함.
        // 방이 하나뿐이면 '한 방 안의 문'(방을 나누지 않은 실제 문 자리): 짧은 변 방향으로 건너감
        var cand: [DoorSeg] = []
        var candRect: [(Int, Int, Int, Int)] = []
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
            guard let first = top.first, first.value >= 3 else { continue }
            if top.count < 2 || top[1].value < 3 {
                // 한 방 안의 문
                let alongU = (a1 - a0) <= (b1 - b0)
                let ra = first.key
                let pA = alongU ? bu + Float(a0) * r : bv + Float(b0) * r
                let pB = alongU ? bu + Float(a1) * r : bv + Float(b1) * r
                var dg = DoorSeg(roomA: ra, roomB: ra, alongU: alongU, nA: alongU ? SIMD2<Float>(-1, 0) : SIMD2<Float>(0, -1), pA: pA, pB: pB,
                                 s0: alongU ? bv + Float(b0) * r : bu + Float(a0) * r,
                                 s1: alongU ? bv + Float(b1) * r : bu + Float(a1) * r)
                dg.glass = d.rec.glassDoors?.contains(sh.id) ?? false
                cand.append(dg)
                candRect.append((a0, b0, a1, b1))
                continue
            }
            let ra = top[0].key, rb = top[1].key
            let ca = (sum[ra] ?? .zero) / Float(top[0].value), cb = (sum[rb] ?? .zero) / Float(top[1].value)
            let dd = cb - ca
            let alongU = abs(dd.x) >= abs(dd.y)
            let aLow = alongU ? dd.x > 0 : dd.y > 0              // 방 A가 낮은 쪽(왼쪽·위)에 있음
            // 각 방 칸이 문 폭 안에서 끝나는 줄 = 그 방의 입구 줄 (양옆 벽과 같은 줄)
            var aMin = Int.max, aMax = Int.min, bMin = Int.max, bMax = Int.min
            for v in max(0, b0 - 2)..<min(h, b1 + 2) {
                for u in max(0, a0 - 2)..<min(w, a1 + 2) {
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
            var dg = DoorSeg(roomA: ra, roomB: rb, alongU: alongU, nA: nA, pA: pA, pB: pB,
                             s0: alongU ? bv + Float(b0) * r : bu + Float(a0) * r,
                             s1: alongU ? bv + Float(b1) * r : bu + Float(a1) * r)
            dg.glass = d.rec.glassDoors?.contains(sh.id) ?? false
            cand.append(dg)
            candRect.append((a0, b0, a1, b1))
        }
        // 문 칸 표시. 방이 아닌 칸(틈)은 걸을 수 있게 하고, 그 칸의 방은 '이 문이 잇는 두 방' 중 가까운 쪽으로만
        // (예전엔 가장 가까운 아무 방이었음 → 문이 세 번째 방에 살짝 닿으면 엉뚱한 두 방 사이 벽이 뚫려 틈이 생겼음)
        var dof = [Int16](repeating: -1, count: w * h)
        for (k, dg) in cand.enumerated() {
            let (a0, b0, a1, b1) = candRect[k]
            let midLine = (dg.pA + dg.pB) / 2
            let base = dg.alongU ? bu : bv
            for v in b0..<b1 {
                for u in a0..<a1 {
                    let i = v * w + u
                    dof[i] = Int16(k)
                    if wk[i] == 0 {
                        wk[i] = 2
                        let c = base + (Float(dg.alongU ? u : v) + 0.5) * r
                        // 방 A 쪽 = nA 방향
                        let towardA = (c - midLine) * (dg.alongU ? dg.nA.x : dg.nA.y) > 0
                        ow[i] = UInt8(towardA ? dg.roomA : dg.roomB)
                    }
                }
            }
        }
        walk = wk; owner = ow
        /// 두 칸 사이가 문으로 뚫렸는지: 그 칸을 덮은 문이 바로 이 두 방을 잇는 문일 때만
        func opened(_ i: Int, _ j: Int) -> Bool {
            for k in [Int(dof[i]), Int(dof[j])] where k >= 0 {
                let dg = cand[k]
                let x = Int(ow[i]), y = Int(ow[j])
                if (dg.roomA == x && dg.roomB == y) || (dg.roomA == y && dg.roomB == x) { return true }
            }
            return false
        }
        door = dof.map { $0 >= 0 }
        /// 두 칸 사이에 방과 방 사이 벽이 서는지 (둘 다 걸을 수 있고, 방이 다르고, 두 방을 잇는 문이 덮지 않음)
        func split(_ i: Int, _ j: Int) -> Bool {
            wk[i] != 0 && wk[j] != 0 && ow[i] != ow[j] && !opened(i, j)
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
        /// 바깥벽 칸 경계 (a~b 가운데, 바깥 방향 out) 너머 45cm 안에 있는 다른 방 (없으면 0)
        func across(_ p: SIMD2<Float>, _ out: SIMD2<Float>, _ mine: Int) -> Int {
            for k in 0..<9 {
                let q = p + out * (0.025 + Float(k) * 0.05)
                let u = Int(((q.x - bu) / r).rounded(.down)), v = Int(((q.y - bv) / r).rounded(.down))
                guard u >= 0, v >= 0, u < w, v < h else { return 0 }
                let i = v * w + u
                if wk[i] != 0 { return Int(ow[i]) != mine ? Int(ow[i]) : 0 }
            }
            return 0
        }
        /// 벽 너머 2m 안에 처음 만나는 걸을 수 있는 곳: -1 이 방 자신, 그 밖은 다른 방 번호, 없으면 0
        func behindOf(_ p: SIMD2<Float>, _ out: SIMD2<Float>, _ mine: Int) -> Int {
            for k in 0..<40 {
                let q = p + out * (0.025 + Float(k) * 0.05)
                let u = Int(((q.x - bu) / r).rounded(.down)), v = Int(((q.y - bv) / r).rounded(.down))
                guard u >= 0, v >= 0, u < w, v < h else { return 0 }
                let i = v * w + u
                if wk[i] != 0 { return Int(ow[i]) == mine ? -1 : Int(ow[i]) }
            }
            return 0
        }
        var segs: [WallSeg] = []
        /// 같은 줄에서 이어지는 조각을 합침 (lane: 0 = 위·왼쪽 칸을 향한 벽, 1 = 아래·오른쪽 칸을 향한 벽)
        func merge(_ cur: inout [WallSeg?], _ lane: Int, _ seg: WallSeg?) {
            if let s = seg, var c = cur[lane], c.room == s.room, c.n == s.n, c.window == s.window, c.inner == s.inner, c.nearRoom == s.nearRoom, c.behind == s.behind,
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
                        let rm = Int(ow[up != 0 ? iu : id])
                        let nr = across((a + b) / 2, -n, rm)
                        let seg = WallSeg(a: a, b: b, n: n, room: rm, window: isWin((a + b) / 2, -n), nearRoom: nr, behind: behindOf((a + b) / 2, -n, rm))
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
                        let rm = Int(ow[lf != 0 ? il : ir])
                        let nr = across((a + b) / 2, -n, rm)
                        let seg = WallSeg(a: a, b: b, n: n, room: rm, window: isWin((a + b) / 2, -n), nearRoom: nr, behind: behindOf((a + b) / 2, -n, rm))
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
        // 벽은 모두 칸 경계 줄에 정확히 (띄우거나 늘리지 않음). 방과 방 사이는 같은 줄에 두 방이 각자 자기 쪽을 보는
        // 한쪽 면 벽을 세움 → 반대편에선 안 보이니 겹쳐 깜빡이지 않고, 이어지는 곳의 끝점이 정확히 같아 틈이 없음
        // 문 폭 = 실제로 뚫린 곳 (두 방 칸이 맞닿아 벽이 빠진 줄들). 문짝·문틀이 뚫린 곳과 정확히 같게.
        // 두 방이 문 안에서 한 번도 맞닿지 않으면(문이 경계에 안 걸침) 뚫린 곳이 없으니 문도 없음
        var dl: [DoorSeg] = []
        for (k, dg) in cand.enumerated() {
            if dg.roomA == dg.roomB { dl.append(dg); continue }
            let (a0, b0, a1, b1) = candRect[k]
            var sMin = Int.max, sMax = Int.min
            let vr = dg.alongU ? b0..<b1 : max(0, b0 - 2)..<min(h, b1 + 2)
            let ur = dg.alongU ? max(0, a0 - 2)..<min(w, a1 + 2) : a0..<a1
            for v in vr {
                for u in ur {
                    let i = v * w + u
                    let j = dg.alongU ? i + 1 : i + w
                    guard dg.alongU ? u + 1 < w : v + 1 < h else { continue }
                    guard wk[i] != 0, wk[j] != 0, ow[i] != ow[j], opened(i, j) else { continue }
                    let x = Int(ow[i]), y = Int(ow[j])
                    guard Set([x, y]) == Set([dg.roomA, dg.roomB]) else { continue }
                    let sc = dg.alongU ? v : u
                    sMin = min(sMin, sc); sMax = max(sMax, sc)
                }
            }
            guard sMax >= sMin else { continue }
            var t = dg
            let base = dg.alongU ? bv : bu
            t.s0 = base + Float(sMin) * r
            t.s1 = base + Float(sMax + 1) * r
            dl.append(t)
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

    /// 걸을 수 있는 칸 전체(모든 방·문 자리)를 감싸는 사각형 (평면 좌표)
    func walkBounds() -> (SIMD2<Float>, SIMD2<Float>)? {
        var lu = Int.max, lv = Int.max, hu = Int.min, hv = Int.min
        for v in 0..<H {
            for u in 0..<W where walk[v * W + u] != 0 {
                lu = min(lu, u); hu = max(hu, u); lv = min(lv, v); hv = max(hv, v)
            }
        }
        guard lu <= hu else { return nil }
        return (SIMD2<Float>(u0 + Float(lu) * Layout.res, v0 + Float(lv) * Layout.res),
                SIMD2<Float>(u0 + Float(hu + 1) * Layout.res, v0 + Float(hv + 1) * Layout.res))
    }

    /// 평면 좌표의 그 자리가 걸을 수 있는 곳(어느 방이든)인지
    func walkable(_ p: SIMD2<Float>) -> Bool {
        guard let i = index(p) else { return false }
        return walk[i] != 0
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
