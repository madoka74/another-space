import Foundation
import UIKit
import RealityKit
import simd

/// 계곡 테마의 특징: 배경 폭포에서 내려온 강물이 갈래로 나뉘어 벽 너머에서 방 안으로 흘러 들어와,
/// 방의 비어 있는 바닥을 모두 이어 얕고 맑은 물로 천천히 흘러감 (가구 둘레는 비켜 흐름). 반대쪽 벽 너머로 다시 흘러 나감.
/// - 물: 자갈 바닥 + 그 위 맑은 물(들어온 곳에서 멀어지는 쪽으로 물결이 흐름) + 물살 반짝임 + 물가 돌.
///   가장자리는 10cm 칸 계단이 보이지 않게 둥글게 다듬음. 가구 블록·문이 쓸고 지나가는 자리는 비움
/// - 새로 알게 된 가구가 물에 걸치면 그 자리를 비우고 물을 다시 그림 (refresh)
/// - 물고기: 비단잉어·금빛·은빛 피라미·줄무늬·파랑노랑·반점 — 물 전체를 천천히 돌아다니다 가끔 휙. 손·발이 가까이 오면 흩어짐
/// - 물속을 걸으면 걸음마다 첨벙 소리 + 발밑에 물결 고리. 들어온 곳 쪽에서 졸졸 물소리
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
        var goal = SIMD2<Float>(0, 0)
        var goalT: Float = 0
        var need: Float = 0.08                // 몸 전체가 물 안에 있으려면 물가에서 떨어져야 하는 거리 (m)
        var path: [SIMD2<Float>] = []         // 목적지까지 물길을 따라가는 경유점 (저장 좌표)
        var stuck: Float = 0
    }

    private static let steps8: [(Int, Int, Float)] = [(1, 0, 0.1), (-1, 0, 0.1), (0, 1, 0.1), (0, -1, 0.1),
                                                      (1, 1, 0.1414), (1, -1, 0.1414), (-1, 1, 0.1414), (-1, -1, 0.1414)]
    private var fish: [Fish] = []
    private var flows: [(ModelEntity, UnlitMaterial, Float, Float)] = []
    private let L: Layout
    private let roomId: Int
    private let floorY: Float
    private let look: LookMode
    private let tint: SIMD3<Float>
    private var t: Float = 0
    private var hum: AudioPlaybackController?
    // 10cm 칸 격자 (평면 좌표)
    private var u0 = 0, v0 = 0, nu = 0, nv = 0
    private var water: [Bool] = []
    private var flowD: [Float] = []           // 들어온 곳에서 물길을 따라 잰 거리 (m)
    private var entryCell = -1
    private var waterCells: [Int] = []
    private var blocked: Set<Int64>
    private var waterRoot = Entity()
    private(set) var entry: (SIMD2<Float>, SIMD2<Float>)? = nil      // 들어오는 벽 점·방 안쪽 방향 (평면)
    private(set) var exitPt: (SIMD2<Float>, SIMD2<Float>)? = nil     // 나가는 벽 점·방 안쪽 방향
    private let fed: Bool                                             // 바깥 강이 벽까지 곧장 흘러옴 (들어오는 갈래 물길이 필요 없음)
    private var exitRun: Float = 22                                    // 나가는 벽 너머로 트인 거리
    private let streamLen: Float                                       // 나가는 물길 길이 (방에서 지평선 쪽까지)
    private let endInRocks: Bool                                       // 나가는 물길 끝을 바위 틈으로 (같은 세계 무리의 다른 방 — 절벽 협곡은 대표 방 물길에만 있음)
    private(set) var exitPath: [SIMD2<Float>] = []                     // 나가는 물길 가운데 선 (저장 좌표 xz) — 절벽 협곡·바위 자리 비우기용
    private(set) var exitPathW: [Float] = []
    private var cellDir: [SIMD2<Float>] = []                           // 칸마다 물이 흐르는 쪽 (저장 좌표, 8방향 중 하나 — 나가는 곳으로)
    private var edgeD: [Float] = []                                   // 물 칸마다 물가까지 거리 (m)
    private var maxEdge: Float = 0.1
    private let riverNear: SIMD3<Float>?
    private let riverWidth: Float
    // 걸음 첨벙
    private var lastStep: SIMD2<Float>?
    private var stepGap: Float = 0
    private var stepClock: Float = 0
    private var lastSplash = 0
    private var ripples: [(ModelEntity, Float)] = []
    private var rippleMat: UnlitMaterial?

    init(room: RoomRec, layout L: Layout, floorY: Float, blocked: Set<Int64>, riverNear: SIMD3<Float>?, entryHint: (SIMD2<Float>, SIMD2<Float>)? = nil,
         riverWidth: Float, look: LookMode, tint: SIMD3<Float>, streamLen: Float = 30, endInRocks: Bool = false) {
        self.streamLen = streamLen
        self.endInRocks = endInRocks
        self.L = L
        self.roomId = room.id
        self.floorY = floorY
        self.look = look
        self.tint = tint
        self.blocked = blocked
        self.riverNear = riverNear
        self.riverWidth = riverWidth
        self.fed = entryHint != nil
        let rects = L.rects(room.id)
        guard !rects.isEmpty else { return }
        var lo = rects[0].0, hi = rects[0].1
        for r in rects { lo = simd_min(lo, r.0); hi = simd_max(hi, r.1) }
        u0 = Int((lo.x / 0.1).rounded(.down)); v0 = Int((lo.y / 0.1).rounded(.down))
        nu = Int(((hi.x - lo.x) / 0.1).rounded(.up)) + 2; nv = Int(((hi.y - lo.y) / 0.1).rounded(.up)) + 2
        guard nu > 4, nv > 4, nu * nv < 200_000 else { return }
        // 들어오는 곳: 바깥 강이 흘러드는 벽 점 (정해져 있으면 그대로), 아니면 바깥 강에서 가장 가까운 이 방 바깥벽
        if let h = entryHint {
            entry = h
        } else if let rn = riverNear {
            let rp = L.plane(rn.x, rn.z)
            var best: (SIMD2<Float>, SIMD2<Float>, Float)? = nil
            for s in L.walls where s.room == room.id && !s.inner {
                let ab = s.b - s.a
                let len = simd_length(ab)
                guard len > 0.5 else { continue }
                let k = max(0.25, min(len - 0.25, simd_dot(rp - s.a, ab / len)))
                let q = s.a + ab / len * k
                let d = simd_distance(q, rp)
                if best == nil || d < best!.2 { best = (q, s.n, d) }
            }
            if let b = best { entry = (b.0, b.1) }
        }
        guard compute() else { return }
        rebuild()
        buildBranches()
        addFish(room.id)
        startSound()
        ok = true
    }

    // MARK: 물 자리 계산
    private func cellP(_ k: Int) -> SIMD2<Float> { SIMD2<Float>((Float(u0 + k % nu) + 0.5) * 0.1, (Float(v0 + k / nu) + 0.5) * 0.1) }
    private func cellOf(_ p: SIMD2<Float>) -> Int? {
        let i = Int((p.x / 0.1).rounded(.down)) - u0, j = Int((p.y / 0.1).rounded(.down)) - v0
        guard i >= 0, j >= 0, i < nu, j < nv else { return nil }
        return j * nu + i
    }

    /// 빈 바닥 칸 → 들어온 곳과 이어진 덩어리 = 물. 물길 거리(흐름 방향)도 계산. 물이 너무 적으면 false
    private func compute() -> Bool {
        var free = [Bool](repeating: false, count: nu * nv)
        // 가구 블록 둘레 한 칸(10cm)도 비움 (물이 가구 속으로 들어가 보이지 않게)
        var near = Set<Int64>()
        for k in blocked {
            let u = Int((k >> 20) & 0xFFFFF) - 100_000, v = Int(k & 0xFFFFF) - 100_000
            for du in -1...1 { for dv in -1...1 { near.insert(Vox.planeCell(u + du, v + dv)) } }
        }
        for k in 0..<(nu * nv) {
            let p = cellP(k)
            let w = L.flat(p)
            let c = L.at(x: w.x, z: w.y)
            guard c.room == roomId, c.wall > 0.05 else { continue }
            if near.contains(RoomWorld.clutterKey(p)) || Skin.inSwing(L, p) { continue }
            if L.doors.contains(where: { $0.zone(p, margin: 0.12) }) { continue }
            free[k] = true
        }
        // 들어오는 칸: 들어오는 벽 점에서 가장 가까운 빈 칸 (없으면 가장 넓은 덩어리의 아무 칸)
        var start = -1
        if let e = entry {
            var bd: Float = 0.7
            for k in 0..<(nu * nv) where free[k] {
                let d = simd_distance(cellP(k), e.0)
                if d < bd { bd = d; start = k }
            }
        }
        func flood(_ s: Int) -> [Int] {
            var out = [s], seen = Set([s]), qi = 0
            while qi < out.count {
                let k = out[qi]; qi += 1
                let i = k % nu, j = k / nu
                for (di, dj) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let a = i + di, b = j + dj
                    guard a >= 0, b >= 0, a < nu, b < nv else { continue }
                    let n = b * nu + a
                    if free[n] && !seen.contains(n) { seen.insert(n); out.append(n) }
                }
            }
            return out
        }
        var comp: [Int] = []
        if start >= 0 { comp = flood(start) }
        if comp.count < 60 {
            // 들어오는 곳 쪽 덩어리가 작으면 가장 넓은 덩어리로 (들어오는 곳은 그 덩어리에서 강 쪽에 가장 가까운 칸)
            var seenAll = Set<Int>()
            var bestC: [Int] = []
            for k in 0..<(nu * nv) where free[k] && !seenAll.contains(k) {
                let c = flood(k)
                seenAll.formUnion(c)
                if c.count > bestC.count { bestC = c }
            }
            comp = bestC
            if let e = entry, !comp.isEmpty {
                start = comp.min { simd_distance(cellP($0), e.0) < simd_distance(cellP($1), e.0) }!
            } else {
                start = comp.first ?? -1
            }
        }
        guard comp.count >= 50, start >= 0 else { return false }
        water = [Bool](repeating: false, count: nu * nv)
        for k in comp { water[k] = true }
        waterCells = comp
        entryCell = start
        // 물 칸에서 벽 점까지 곧게 물길을 이어 팜 (벽 바로 앞 5cm까지 — 바깥 물길과 끊김 없이 이어져 보이게). 가구에 막히면 거기까지
        func carve(from k0: Int, to wp: SIMD2<Float>) {
            let a = cellP(k0)
            let n = Int(simd_distance(a, wp) / 0.05) + 1
            for i in 0...n {
                let p = a + (wp - a) * (Float(i) / Float(n))
                guard let c = cellOf(p) else { continue }
                let w = L.flat(cellP(c))
                guard L.at(x: w.x, z: w.y).room == roomId else { continue }
                if near.contains(RoomWorld.clutterKey(cellP(c))) { return }
                if !water[c] { water[c] = true; waterCells.append(c) }
            }
        }
        if let e = entry { carve(from: start, to: e.0 + e.1 * 0.03) }
        // 들어온 칸에서 물길을 따라 잰 거리
        func geodesic(_ s0: Int) -> [Float] {
            var dist = [Float](repeating: .infinity, count: nu * nv)
            dist[s0] = 0
            var q = [s0], qi = 0
            while qi < q.count {
                let k = q[qi]; qi += 1
                let i = k % nu, j = k / nu
                for (di, dj, c) in Self.steps8 {
                    let a = i + di, b = j + dj
                    guard a >= 0, b >= 0, a < nu, b < nv else { continue }
                    let n = b * nu + a
                    guard water[n], dist[k] + c < dist[n] - 1e-4 else { continue }
                    dist[n] = dist[k] + c
                    q.append(n)
                }
            }
            return dist
        }
        let dIn = geodesic(start)
        // 나가는 곳: 처음 정한 곳이 아직 물과 닿아 있으면 그대로 (벽 둑을 비운 자리·바깥 물길과 어긋나지 않게), 아니면
        // 이 방 벽(바깥벽 우선)을 30cm마다 훑어, 벽 50cm 안쪽에 물이 닿아 있는 곳 중 들어온 곳에서 가장 먼 곳 — 보통 맞은편의 넓은 쪽.
        // (v0.5.21은 '벽 너머가 트인 곳'을 크게 쳐서 들어온 곳 옆(서쪽)을 고르기도 했음 → 거리를 가장 크게 침)
        // 물에서 빈 바닥을 따라 닿을 수 있는 칸 (물길을 새로 팔 수 있는 곳): 가구에 막혀 물이 그 벽까지 바로 닿지 않아도
        // 가구 사이 빈 바닥으로 물길을 내어 나가는 곳과 잇기 위해 (예전엔 '벽 50cm 안에 이미 물이 있는 곳'만 나가는 곳이 될 수 있어,
        // 가구가 조금만 달라져도 나가는 곳이 하나도 없거나, 처음 정한 나가는 곳과 물이 끊겼음)
        var par = [Int](repeating: -2, count: nu * nv)        // -2 못 닿음, -1 물(시작), 그 밖 = 앞 칸
        var bq: [Int] = []
        for k in waterCells where dIn[k].isFinite { par[k] = -1; bq.append(k) }
        var bi = 0
        while bi < bq.count {
            let k = bq[bi]; bi += 1
            let i = k % nu, j = k / nu
            for (di, dj) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let a = i + di, b = j + dj
                guard a >= 0, b >= 0, a < nu, b < nv else { continue }
                let n = b * nu + a
                if free[n] && par[n] == -2 { par[n] = k; bq.append(n) }
            }
        }
        /// 벽 점 q 에서 r 안의 닿을 수 있는 칸 중 가장 가까운 것
        func reach(_ q: SIMD2<Float>, _ r: Float) -> Int {
            var best = -1, bd = r
            for k in bq {
                let d = simd_distance(cellP(k), q)
                if d < bd { bd = d; best = k }
            }
            return best
        }
        /// 그 칸에서 물까지 물길을 팜
        func dig(_ k0: Int) {
            var c = k0
            while c >= 0 {
                if !water[c] { water[c] = true; waterCells.append(c) }
                c = par[c]
            }
        }
        var exitCell = -1
        if let x = exitPt {
            // 처음 정한 나가는 곳은 그대로 (바깥 물길·둑을 비운 자리가 이미 그곳에 있음) — 가구가 바뀌어도 물길을 다시 내어 이음
            let k = reach(x.0, 0.9)
            if k >= 0 { dig(k); exitCell = k }
        } else {
            let ep = entry?.0 ?? cellP(start)
            var lo = SIMD2<Float>(repeating: .greatestFiniteMagnitude), hi = -lo
            for r in L.rects(roomId) { lo = simd_min(lo, r.0); hi = simd_max(hi, r.1) }
            let span = lo.x < hi.x ? max(hi.x - lo.x, hi.y - lo.y) : 0
            // 나가는 곳은 들어온 곳과 떨어진 다른 쪽: 방의 긴 길이(span)의 45% 넘게, 들어온 벽과 같은 방향의 벽이면 60% 넘게.
            // 그런 곳이 없으면(좁은 방·가구로 막힘) 조건을 조금씩 풀어서라도 하나는 냄 (마지막엔 들어온 곳에서 0.8m 넘게만)
            for tier in 0..<3 where exitPt == nil {
                var best: (SIMD2<Float>, SIMD2<Float>, Int, Float, Float)? = nil        // 벽 점, 안쪽 방향, 닿는 칸, 점수, 트인 거리
                for s in L.walls where s.room == roomId {
                    let ab = s.b - s.a
                    let len = simd_length(ab)
                    guard len > 0.7 else { continue }
                    var k: Float = 0.35
                    while k <= len - 0.35 + 1e-3 {
                        let q = s.a + ab / len * k
                        let mid: Float = 0.25 * min(k, len - k)
                        k += 0.3
                        if L.doors.contains(where: { $0.zone(q, margin: 0.6) }) { continue }
                        if let e = entry {
                            let dd = simd_distance(q, e.0)
                            switch tier {
                            case 0:
                                if dd < max(1.5, span * 0.45) { continue }
                                if simd_dot(s.n, e.1) > 0.7 && dd < span * 0.6 { continue }
                            case 1:
                                if dd < max(1.2, span * 0.3) { continue }
                            default:
                                if dd < 0.8 { continue }
                            }
                        }
                        let wk = reach(q, 0.5)
                        guard wk >= 0 else { continue }
                        let run = openRun(q, s.n)
                        let far: Float = simd_distance(q, ep)
                        let bonus: Float = (s.inner ? 0 : 0.8) + 0.05 * min(run, 20)
                        let sc: Float = far + bonus + mid - (water[wk] ? 0 : 0.5)       // 물길을 새로 파야 하는 곳은 조금 덜
                        if best == nil || sc > best!.3 { best = (q, s.n, wk, sc, run) }
                    }
                }
                if let b = best { exitPt = (b.0, b.1); exitCell = b.2; exitRun = max(12, b.4); dig(b.2) }
            }
        }
        if let x = exitPt, exitCell >= 0 { carve(from: exitCell, to: x.0 + x.1 * 0.03) }
        // 흐름: 나가는 곳까지 물길 거리(d1)가 줄어드는 쪽 — 들어온 곳에서 나가는 곳으로, 옆 웅덩이 물은 큰 물줄기 쪽으로 모였다 나감
        var ek = exitCell >= 0 ? exitCell : start
        if let x = exitPt, let c = cellOf(x.0 + x.1 * 0.03), water[c] { ek = c }
        var d1 = geodesic(ek)
        if exitCell < 0 {                                   // 나가는 곳이 없으면 들어온 곳에서 멀어지는 쪽
            let mx = waterCells.map { d1[$0].isFinite ? d1[$0] : 0 }.max() ?? 0
            for k in waterCells where d1[k].isFinite { d1[k] = mx - d1[k] }
        }
        flowD = d1
        // 칸마다 흐르는 방향 (저장 좌표, 단위 벡터): d1이 줄어드는 쪽, 이웃과 몇 번 고르게 다듬음
        var dirs = [SIMD2<Float>](repeating: .zero, count: nu * nv)
        for k in waterCells where d1[k].isFinite {
            let i = k % nu, j = k / nu
            var v = SIMD2<Float>(0, 0)
            for (di, dj, c) in Self.steps8 {
                let a = i + di, b = j + dj
                guard a >= 0, b >= 0, a < nu, b < nv else { continue }
                let n = b * nu + a
                guard water[n], d1[n].isFinite else { continue }
                v += SIMD2<Float>(Float(di), Float(dj)) * ((d1[k] - d1[n]) / (c * c))
            }
            dirs[k] = v
        }
        for _ in 0..<4 {
            var d2 = dirs
            for k in waterCells {
                let i = k % nu, j = k / nu
                var v = dirs[k] * 2
                for (di, dj) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let a = i + di, b = j + dj
                    guard a >= 0, b >= 0, a < nu, b < nv, water[b * nu + a] else { continue }
                    v += dirs[b * nu + a]
                }
                d2[k] = v
            }
            dirs = d2
        }
        cellDir = [SIMD2<Float>](repeating: SIMD2<Float>(1, 0), count: nu * nv)
        for k in waterCells where simd_length(dirs[k]) > 1e-5 {
            let pl = simd_normalize(dirs[k])
            let w = L.flat(cellP(k) + pl * 0.1) - L.flat(cellP(k))
            // 8방향으로 맞춤 — 같은 방향인 칸끼리는 무늬가 이어져 흐름 (방향이 바뀌는 곳만 이음새)
            let a = (atan2(w.y, w.x) / (.pi / 4)).rounded() * (.pi / 4)
            cellDir[k] = SIMD2<Float>(cos(a), sin(a))
        }
        computeEdge()
        return true
    }

    /// 물 칸마다 물가(물 아닌 칸)까지 거리 — 물고기가 물가에 걸치지 않게 이 거리 안쪽으로만 다님
    private func computeEdge() {
        var d = [Float](repeating: .infinity, count: nu * nv)
        var q: [Int] = []
        for k in waterCells {
            let i = k % nu, j = k / nu
            var border = false
            for (di, dj) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let a = i + di, b = j + dj
                if a < 0 || b < 0 || a >= nu || b >= nv || !water[b * nu + a] { border = true; break }
            }
            if border { d[k] = 0.05; q.append(k) }
        }
        var qi = 0
        while qi < q.count {
            let k = q[qi]; qi += 1
            let i = k % nu, j = k / nu
            for (di, dj, c) in Self.steps8 {
                let a = i + di, b = j + dj
                guard a >= 0, b >= 0, a < nu, b < nv else { continue }
                let n = b * nu + a
                guard water[n], d[k] + c < d[n] - 1e-4 else { continue }
                d[n] = d[k] + c
                q.append(n)
            }
        }
        edgeD = d
        maxEdge = waterCells.map { d[$0] }.max() ?? 0.1
    }

    /// 그 자리(저장 좌표)에서 물가까지 거리 (물 밖이면 0)
    private func edgeAt(_ p: SIMD2<Float>) -> Float {
        guard let c = cellOf(L.plane(p.x, p.y)), water[c] else { return 0 }
        return edgeD[c]
    }

    /// 물가에서 need 이상 떨어진 칸만 지나 a → b 로 가는 길 (경유점, 저장 좌표). 길이 없으면 빈 배열
    private func route(_ a: SIMD2<Float>, _ b: SIMD2<Float>, need: Float) -> [SIMD2<Float>] {
        guard let s = cellOf(L.plane(a.x, a.y)), let t = cellOf(L.plane(b.x, b.y)), water[s], water[t] else { return [] }
        var prev = [Int](repeating: -1, count: nu * nv)
        prev[s] = s
        var q = [s], qi = 0
        while qi < q.count {
            let k = q[qi]; qi += 1
            if k == t { break }
            let i = k % nu, j = k / nu
            for (di, dj, _) in Self.steps8 {
                let x = i + di, y = j + dj
                guard x >= 0, y >= 0, x < nu, y < nv else { continue }
                let n = y * nu + x
                guard prev[n] < 0, water[n], edgeD[n] >= need || n == t else { continue }
                prev[n] = k
                q.append(n)
            }
        }
        guard prev[t] >= 0 else { return [] }
        var cells: [Int] = []
        var k = t
        while k != s { cells.append(k); k = prev[k] }
        cells.reverse()
        // 3칸(30cm)마다 하나씩 경유점
        var out: [SIMD2<Float>] = []
        for (i, c) in cells.enumerated() where i % 3 == 2 || i == cells.count - 1 { out.append(L.flat(cellP(c))) }
        return out
    }

    /// 벽 점 q(평면)에서 바깥쪽(-n)으로 다른 방(걸을 수 있는 곳) 없이 몇 m까지 트여 있는지 (물길 폭만큼 양옆도, 최대 25m)
    private func openRun(_ q: SIMD2<Float>, _ n: SIMD2<Float>) -> Float {
        let side = SIMD2<Float>(-n.y, n.x)
        var d: Float = 0.6
        while d <= 25 {
            for o: Float in [0, 0.9, -0.9] where L.walkable(q - n * d + side * o) { return d - 0.6 }
            d += 0.5
        }
        return 25
    }

    /// 그 칸(평면 좌표, 벽 가까이)에서 가장 가까운 바깥벽 너머로 몇 m까지 다른 방 없이 트여 있는지 (최대 12m)
    private func outsideRoom(_ p: SIMD2<Float>) -> Float {
        var best: (SIMD2<Float>, Float)? = nil
        for s in L.walls where s.room == roomId && !s.inner {
            let ab = s.b - s.a
            let len = simd_length(ab)
            guard len > 0.3 else { continue }
            let k = max(0, min(len, simd_dot(p - s.a, ab / len)))
            let d = simd_distance(s.a + ab / len * k, p)
            if best == nil || d < best!.1 { best = (s.n, d) }
        }
        guard let n = best?.0 else { return 0 }
        var d: Float = 0.5
        while d < 12 {
            if L.walkable(p - n * d) { return d }
            d += 0.5
        }
        return 12
    }

    /// 새로 알게 된 가구(blocked)가 물에 걸치면 그 자리를 비우고 다시 그림
    func refresh(blocked nb: Set<Int64>) {
        guard ok, nb != blocked else { return }
        var hit = false
        for k in nb where !blocked.contains(k) {
            let u = Int((k >> 20) & 0xFFFFF) - 100_000, v = Int(k & 0xFFFFF) - 100_000
            for du in -1...1 {
                for dv in -1...1 {
                    if let c = cellOf(SIMD2<Float>((Float(u + du) + 0.5) * 0.1, (Float(v + dv) + 0.5) * 0.1)), water[c] { hit = true }
                }
            }
        }
        blocked = nb
        guard hit, compute() else { return }
        // 탐험 중에 다시 그림: 이 방 표시 방식으로 (예전엔 기본(컬러)으로 다시 그려 선 그림·흑백 방에 컬러 자갈 바닥·돌이 나왔음)
        Tex.with(look) { rebuild() }
        for f in fish {
            f.need = min(0.7 * f.size + 0.035, maxEdge * 0.85)
            f.path = []
            if edgeAt(f.pos) < f.need, let k = waterCells.filter({ edgeD[$0] >= f.need }).randomElement() { f.pos = L.flat(cellP(k)) }
        }
    }

    // MARK: 만들기
    /// 물·바닥·물가 돌 그물 (방 안)
    private func rebuild() {
        let old = waterRoot
        flows.removeAll { $0.0.parent === old }
        old.removeFromParent()
        waterRoot = Entity()
        local.addChild(waterRoot)
        let line = look == .line
        let bedY = floorY + 0.008, waterY = floorY + 0.05
        // 칸 모서리 점 (nu+1)×(nv+1): 물 칸과 아닌 칸에 함께 닿은 점 = 물가 → 둥글게 다듬음
        let W = nu + 1
        func isW(_ i: Int, _ j: Int) -> Bool { i >= 0 && j >= 0 && i < nu && j < nv && water[j * nu + i] }
        var vp = [SIMD2<Float>](repeating: .zero, count: W * (nv + 1))
        var edge = [Bool](repeating: false, count: W * (nv + 1))
        for j in 0...nv {
            for i in 0...nu {
                vp[j * W + i] = SIMD2<Float>(Float(u0 + i) * 0.1, Float(v0 + j) * 0.1)
                let c = [isW(i - 1, j - 1), isW(i, j - 1), isW(i - 1, j), isW(i, j)]
                let n = c.filter { $0 }.count
                edge[j * W + i] = n > 0 && n < 4
            }
        }
        var g = SeededRNG(seed: UInt64(roomId * 811 + 5))
        for _ in 0..<3 {
            var v2 = vp
            for j in 0...nv {
                for i in 0...nu where edge[j * W + i] {
                    var s = vp[j * W + i], n: Float = 1
                    for (di, dj) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                        let a = i + di, b = j + dj
                        guard a >= 0, b >= 0, a <= nu, b <= nv, edge[b * W + a] else { continue }
                        s += vp[b * W + a]; n += 1
                    }
                    v2[j * W + i] = s / n
                }
            }
            vp = v2
        }
        for k in vp.indices where edge[k] { vp[k] += SIMD2<Float>(Float.random(in: -0.015...0.015, using: &g), Float.random(in: -0.015...0.015, using: &g)) }
        // 점마다 물길 거리 (닿은 물 칸의 평균)
        func vd(_ i: Int, _ j: Int) -> Float {
            var s: Float = 0, n: Float = 0
            for (a, b) in [(i - 1, j - 1), (i, j - 1), (i - 1, j), (i, j)] where isW(a, b) && flowD[b * nu + a].isFinite { s += flowD[b * nu + a]; n += 1 }
            return n > 0 ? s / n : 0
        }
        var bed = Geo(), wat = Geo(), stones = Geo(), lines = Geo()
        for k in waterCells {
            let i = k % nu, j = k / nu
            let ids = [j * W + i, j * W + i + 1, (j + 1) * W + i + 1, (j + 1) * W + i]
            let ps = ids.map { L.flat(vp[$0]) }
            let ds = [vd(i, j), vd(i + 1, j), vd(i + 1, j + 1), vd(i, j + 1)]
            let raw = ids.map { vp[$0] }
            // 바닥 자갈: 평면 좌표 그대로 (흐르지 않음), 물: v = 물길 거리 → 흐름 방향으로 이어짐
            let bu = raw.map { $0 / 0.45 }
            // 물 무늬: 칸마다 그 칸의 흐르는 쪽(cellDir, 나가는 곳으로)으로 흐름 — v = 흐르는 쪽 거리, u = 그 옆 방향
            let fd = cellDir.indices.contains(k) ? cellDir[k] : SIMD2<Float>(1, 0), fs = SIMD2<Float>(-fd.y, fd.x)
            let wu = ps.map { SIMD2<Float>(simd_dot($0, fs) / 0.9, simd_dot($0, fd) / 0.9) }
            _ = ds
            func p3(_ q: SIMD2<Float>, _ y: Float) -> SIMD3<Float> { SIMD3<Float>(q.x, y, q.y) }
            bed.quad(p3(ps[0], bedY), p3(ps[1], bedY), p3(ps[2], bedY), p3(ps[3], bedY), bu[0], bu[1], bu[2], bu[3])
            wat.quad(p3(ps[0], waterY), p3(ps[1], waterY), p3(ps[2], waterY), p3(ps[3], waterY), wu[0], wu[1], wu[2], wu[3])
            if line {
                let cs = [(0, 1, (i, j - 1)), (1, 2, (i + 1, j)), (2, 3, (i, j + 1)), (3, 0, (i - 1, j))]
                for (a, b, n) in cs where !isW(n.0, n.1) { lines.stroke(p3(ps[a], waterY), p3(ps[b], waterY), width: 0.01) }
            }
            // 물가 돌: 물 밖(가구·벽 쪽)과 닿은 칸에 가끔
            let outside = [(i + 1, j), (i - 1, j), (i, j + 1), (i, j - 1)].filter { !isW($0.0, $0.1) }
            if let o = outside.first, Float.random(in: 0...1, using: &g) < 0.28 {
                let c = cellP(k), oc = SIMD2<Float>((Float(u0 + o.0) + 0.5) * 0.1, (Float(v0 + o.1) + 0.5) * 0.1)
                let p = L.flat(c + (oc - c) * Float.random(in: 0.45...0.7, using: &g))
                stones.rock(at: SIMD3<Float>(p.x, floorY + 0.004, p.y), size: Float.random(in: 0.025...0.06, using: &g), using: &g)
            }
            // 물속 자갈 몇 개 (물 밑에 비쳐 보임)
            if Float.random(in: 0...1, using: &g) < 0.03 {
                let p = L.flat(cellP(k))
                stones.rock(at: SIMD3<Float>(p.x, floorY - 0.004, p.y), size: Float.random(in: 0.03...0.07, using: &g), using: &g)
            }
        }
        if let e = bed.entity("creekBed", Tex.unlit("pebble", tint: Worlds.safe(tint * 0.6, min: 0.25))) { waterRoot.addChild(e) }
        if let e = stones.entity("creekStones", Tex.unlit("rock", tint: Worlds.safe(tint * 0.8, min: 0.3))) { waterRoot.addChild(e) }
        if line, let h = stones.inkHull("creekStonesInk", width: { _ in Ink.w * 0.6 }) { waterRoot.addChild(h) }
        if !line {
            // 맑은 물: 옅게 비치는 물빛(바닥·물고기가 비쳐 보임) + 그 위 물살 반짝임. 천천히 흐름
            var wm = Tex.unlit("river", tint: Worlds.safe(tint, min: 0.35) * SIMD3<Float>(0.75, 1.0, 1.05))
            wm.blending = .transparent(opacity: .init(floatLiteral: 0.3))
            wm.writesDepth = false
            if let e = wat.entity("creekWater", wm) {
                waterRoot.addChild(e)
                flows.append((e, wm, 0.11, 0))
            }
            var hm = Tex.unlit("river_hi", tint: [1, 1, 1])
            if let mk = Tex.get("river_hi_a", raw: true) {
                var tp = MaterialParameters.Texture(mk); tp.sampler = Tex.tiling
                hm.blending = .transparent(opacity: .init(scale: 0.35, texture: tp))
                hm.writesDepth = false
            }
            var hg = wat
            hg.pos = hg.pos.map { SIMD3<Float>($0.x, $0.y + 0.002, $0.z) }
            hg.uv = hg.uv.map { SIMD2<Float>($0.x * 0.8, $0.y * 1.2) }
            if let e = hg.entity("creekHi", hm) {
                waterRoot.addChild(e)
                flows.append((e, hm, 0.2, 0.4))
            }
        } else if let e = lines.entity("creekLines", Ink.line) {
            waterRoot.addChild(e)
        }
        Sorting.apply(waterRoot, 25)          // 포털(0번)보다 나중에 — 물 면이 하늘 쪽에서 지워지지 않게
    }

    /// 벽 너머: (바깥 강이 벽까지 오지 않을 때) 큰 강에서 갈라져 들어오는 벽까지 오는 물길 +
    /// 나가는 벽에서 바깥으로 흘러 나가 점점 넓어지며 멀리 바위 틈으로 사라지는 냇물 (하늘 세계).
    /// 물길이 벽 바로 앞까지 와서 방 안 개울과 이어져 보임 (그 자리는 바위 둑을 비움)
    private func buildBranches() {
        var g = SeededRNG(seed: UInt64(roomId * 97 + 1))
        if !fed, let e = entry, let rn = riverNear {
            let out = L.flat(e.0 - e.1 * 0.03)
            branch(from: SIMD2<Float>(rn.x, rn.z), to: out, w0: riverWidth * 0.6, w1: 0.9, flow: 0.13, &g)
        }
        if let x = exitPt {
            let a = L.flat(x.0 - x.1 * 0.03)
            let base = L.flat(x.0 - x.1 * 4) - L.flat(x.0)
            let b0 = atan2(base.y, base.x)
            // 바깥으로 흘러 나가 멀리(절벽 사이 협곡을 지나 지평선 가까이까지) 끊기지 않고 이어짐.
            // 벽 가까운 12m 안이 다른 방에 걸리면 조금씩 비스듬히 (그래도 막히면 그대로 — 이 방 벽 너머로만 보이는 풍경)
            var done = false
            for da: Float in [0, 0.3, -0.3, 0.6, -0.6, 0.9, -0.9] where !done {
                let dir = SIMD2<Float>(cos(b0 + da), sin(b0 + da))
                done = branch(from: a, to: a + dir * streamLen, w0: 0.9, w1: endInRocks ? 2.2 : 4.5, flow: 0.13, endRocks: endInRocks, checkLen: 12, record: true, &g)
            }
            if !done { branch(from: a, to: a + SIMD2<Float>(cos(b0), sin(b0)) * streamLen, w0: 0.9, w1: endInRocks ? 2.2 : 4.5, flow: 0.13, endRocks: endInRocks, checkLen: 0, record: true, &g) }
        }
    }

    @discardableResult
    private func branch<G: RandomNumberGenerator>(from a: SIMD2<Float>, to eo: SIMD2<Float>, w0: Float, w1: Float, flow: Float,
                                                  endRocks: Bool = false, checkLen: Float = 1e9, record: Bool = false, _ g: inout G) -> Bool {
        let total = simd_distance(a, eo)
        let n = max(32, Int(total / 1.5))
        let side = SIMD2<Float>(-(eo - a).y, (eo - a).x) / max(0.01, total)
        let amp = min(total * 0.1, 6)
        var pts: [SIMD2<Float>] = []
        for i in 0...n {
            let k = Float(i) / Float(n)
            // 굽이침: 벽 가까이는 거의 곧게, 멀어질수록 크게
            let p = a + (eo - a) * k + side * (amp * sin(k * .pi) + min(1, k * 6) * amp * 0.5 * sin(k * 9.0))
            // 벽 가까운 checkLen m 안에서 집 안(걸을 수 있는 곳)을 지나면 그리지 않음 (끝 두세 점은 벽 바로 앞)
            if i > 2 && simd_distance(p, a) < checkLen && L.walkable(L.plane(p.x, p.y)) { return false }
            pts.append(p)
        }
        var wg = Geo(), bg = Geo(), rk = Geo()
        var va: Float = 0
        var pl = SIMD2<Float>(0, 0), pr = SIMD2<Float>(0, 0), pv: Float = 0
        // 방 둘레 가까운 땅(80m)을 벗어나면 먼 땅 높이(36cm 아래)로 천천히 내려감 (먼 땅 위에 떠 보이지 않게)
        func drop(_ q: SIMD2<Float>) -> Float { max(0, min(1, (simd_distance(q, a) - 66) / 10)) * 0.36 }
        var pdrop: Float = 0
        for i in pts.indices {
            let p0 = pts[max(0, i - 1)], p1 = pts[min(pts.count - 1, i + 1)]
            let td = simd_normalize(p1 - p0)
            let nn = SIMD2<Float>(-td.y, td.x)
            let k = Float(i) / Float(n)
            let sk = k * k * (3 - 2 * k)
            let w = (w0 * (1 - sk) + w1 * sk) / 2
            let l = pts[i] + nn * w, r = pts[i] - nn * w
            if i > 0 {
                va += simd_distance(pts[i], pts[i - 1])
                let v1 = va / 3.5
                let cd = drop(pts[i])
                let y = floorY - 0.012 - cd, yp = floorY - 0.012 - pdrop
                wg.quad(SIMD3<Float>(pl.x, yp, pl.y), SIMD3<Float>(pr.x, yp, pr.y), SIMD3<Float>(r.x, y, r.y), SIMD3<Float>(l.x, y, l.y),
                        SIMD2<Float>(0, pv), SIMD2<Float>(1, pv), SIMD2<Float>(1, v1), SIMD2<Float>(0, v1))
                let yb = floorY - 0.022 - max(cd, pdrop)
                let bl = pl + simd_normalize(pl - pr) * 0.4, br = pr + simd_normalize(pr - pl) * 0.4
                let cl = l + simd_normalize(l - r) * 0.4, cr = r + simd_normalize(r - l) * 0.4
                bg.quad(SIMD3<Float>(bl.x, yb, bl.y), SIMD3<Float>(br.x, yb, br.y), SIMD3<Float>(cr.x, yb, cr.y), SIMD3<Float>(cl.x, yb, cl.y),
                        SIMD2<Float>(0, pv * 2), SIMD2<Float>(1, pv * 2), SIMD2<Float>(1, v1 * 2), SIMD2<Float>(0, v1 * 2))
                pv = v1
                pdrop = cd
            }
            pl = l; pr = r
            if i % 3 == 1 {
                let far = simd_distance(pts[i], a)
                let sc: Float = 1 + far / 25                           // 멀리 있는 물가 돌은 크게 (멀리서도 보이게)
                for s: Float in [-1, 1] {
                    let p = pts[i] + nn * s * (w + 0.15 * sc)
                    rk.rock(at: SIMD3<Float>(p.x, floorY - 0.04 - drop(p), p.y), size: Float.random(in: 0.1...0.26, using: &g) * sc, using: &g)
                }
            }
        }
        // 그리는 순서는 바깥 강(RoomWorld.addRiver)과 같게: 물가 자갈 5 → 물 6 (예전엔 순서가 없어 물이 자갈·땅 밑으로 묻혀 보이지 않기도 했음)
        if let e = bg.entity("branchBank", Tex.unlit("pebble", tint: Worlds.safe(tint * 0.55, min: 0.2))) { Sorting.apply(e, 5); world.addChild(e) }
        let wm = Tex.unlit("river", tint: Worlds.safe(tint, min: 0.2))
        if let e = wg.entity("branchWater", wm) { Sorting.apply(e, 6); world.addChild(e); flows.append((e, wm, flow, 0)) }
        if endRocks, pts.count > 2 {
            // 끝: 큰 바위 사이로 물이 사라짐
            let pe = pts[pts.count - 1], te = simd_normalize(pts[pts.count - 1] - pts[pts.count - 2])
            let ne = SIMD2<Float>(-te.y, te.x)
            for k in -1...1 {
                let p = pe + ne * Float(k) * w1 * 0.7 + te * 0.3
                rk.rock(at: SIMD3<Float>(p.x, floorY - 0.15, p.y), size: Float.random(in: 0.9...1.5, using: &g), using: &g)
            }
        }
        if let e = rk.entity("branchRocks", Tex.unlit("rock", tint: Worlds.safe(tint * 0.85, min: 0.25))) { Sorting.apply(e, 5); world.addChild(e) }
        if look == .line, let h = rk.inkHull("branchRocksInk", width: { p in Ink.width(at: simd_distance(SIMD2<Float>(p.x, p.z), a)) }) { Sorting.apply(h, 5); world.addChild(h) }
        if look == .line {
            var ln = Geo()
            var pl: SIMD2<Float>? = nil, pr: SIMD2<Float>? = nil
            for i in pts.indices {
                let p0 = pts[max(0, i - 1)], p1 = pts[min(pts.count - 1, i + 1)]
                let td = simd_normalize(p1 - p0)
                let nn = SIMD2<Float>(-td.y, td.x)
                let k = Float(i) / Float(n)
                let sk = k * k * (3 - 2 * k)
                let w = (w0 * (1 - sk) + w1 * sk) / 2
                let l = pts[i] + nn * w, r = pts[i] - nn * w
                let y = floorY - 0.005
                if let a = pl, let b = pr {
                    ln.stroke(SIMD3<Float>(a.x, y, a.y), SIMD3<Float>(l.x, y, l.y), width: 0.03)
                    ln.stroke(SIMD3<Float>(b.x, y, b.y), SIMD3<Float>(r.x, y, r.y), width: 0.03)
                }
                pl = l; pr = r
            }
            if let e = ln.entity("branchLines", Ink.line) { world.addChild(e) }
        }
        if record {
            exitPath = pts
            exitPathW = pts.indices.map { i in
                let k = Float(i) / Float(n)
                let sk = k * k * (3 - 2 * k)
                return w0 * (1 - sk) + w1 * sk
            }
        }
        return true
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
        let area = Float(waterCells.count) * 0.01
        let n = max(9, min(24, Int(area / 0.22)))                // 작은 물고기를 넉넉히
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
            // 크기 여러 가지 (얕고 좁은 개울에 맞게): 작은 피라미(3.5~8cm) 60% · 중간(8~13cm) 30% · 큰 물고기(13~18cm, 느긋하게) 10%
            let r = Float.random(in: 0...1, using: &g)
            let big = r > 0.9
            f.size = r < 0.6 ? Float.random(in: 0.035...0.08, using: &g) : (big ? Float.random(in: 0.13...0.18, using: &g) : Float.random(in: 0.08...0.13, using: &g))
            f.cruise = Float.random(in: 0.06...0.14, using: &g) * (big ? 0.75 : (r < 0.6 ? 1.25 : 1))
            f.speed = f.cruise
            f.depth = Float.random(in: 0.015...0.03, using: &g)
            if f.size > 0.12 { f.e.scale = [1, 0.75, 1]; f.depth = 0.018 }       // 큰 물고기는 얕은 물에 맞게 조금 납작하게 (등이 물 밖으로 나오지 않게)
            f.head = Float.random(in: 0...(2 * .pi), using: &g)
            f.wag = Float.random(in: 0...6, using: &g)
            // 몸 전체(머리~꼬리)가 물 안에 들도록 물가에서 떨어져 다님. 좁은 개울이면 큰 물고기는 넓은 곳에서만
            f.need = min(0.7 * f.size + 0.035, maxEdge * 0.85)
            let okCells = waterCells.filter { edgeD[$0] >= f.need }
            let pool = okCells.isEmpty ? waterCells : okCells
            let k = pool[Int(g.next() % UInt64(pool.count))]
            f.pos = L.flat(cellP(k))
            f.goal = f.pos
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
                // 선 그림: 위에서 본 몸 윤곽(머리→꼬리 양쪽 선) + 꼬리 윤곽 + 눈 — 물 위에서 내려다봐도 또렷하게
                var l = Geo(), tl = Geo()
                let s = f.size, y = 0.135 * s, w = max(0.0025, s * 0.03)
                func half(_ k: Float) -> Float { 0.13 * pow(sin(.pi * min(1, max(0, k)) * 0.95 + 0.08), 0.85) * s * 0.55 }
                for side: Float in [-1, 1] {
                    for i in 0..<10 {
                        let k0 = Float(i) / 10, k1 = Float(i + 1) / 10
                        l.stroke([(0.5 - k0) * s, y, side * half(k0)], [(0.5 - k1) * s, y, side * half(k1)], width: w)
                    }
                    tl.stroke([0, y, 0], [-0.22 * s, y, side * 0.09 * s], width: w)
                    tl.stroke([-0.22 * s, y, side * 0.09 * s], [-0.17 * s, y, 0], width: w)
                    l.stroke([0.36 * s, y, side * 0.035 * s], [0.33 * s, y, side * 0.035 * s], width: w * 1.6)
                }
                if let e = l.entity("fishLine", Ink.line) { f.e.addChild(e) }
                if let e = tl.entity("fishTailLine", Ink.line) { f.tail.addChild(e) }
            }
            Sorting.apply(f.e, 26)
            local.addChild(f.e)
            fish.append(f)
        }
    }

    /// 물 안인지 (저장 좌표 xz, 가장자리에서 margin m 안쪽)
    private func inWater(_ p: SIMD2<Float>, margin: Float) -> Bool {
        let pl = L.plane(p.x, p.y)
        guard let c = cellOf(pl), water[c] else { return false }
        guard margin > 0 else { return true }
        for o in [SIMD2<Float>(margin, 0), SIMD2<Float>(-margin, 0), SIMD2<Float>(0, margin), SIMD2<Float>(0, -margin)] {
            guard let c2 = cellOf(pl + o), water[c2] else { return false }
        }
        return true
    }

    private func startSound() {
        guard let u = Bundle.main.url(forResource: "stream_loop", withExtension: "wav", subdirectory: "sfx") else { return }
        let cfg = AudioFileResource.Configuration(loadingStrategy: .preload, shouldLoop: true)
        guard let r = try? AudioFileResource.load(contentsOf: u, withName: nil, configuration: cfg) else { return }
        let e = Entity()
        var sa = SpatialAudioComponent()
        sa.gain = -9                                   // 실제 개울 녹음 (졸졸) — 물가에서 또렷하고 멀어지면 잦아듦
        sa.distanceAttenuation = .rolloff(factor: 0.8)
        e.components.set(sa)
        let p = L.flat(entryCell >= 0 ? cellP(entryCell) : SIMD2<Float>(0, 0))
        e.position = SIMD3<Float>(p.x, floorY + 0.1, p.y)
        local.addChild(e)
        hum = e.playAudio(r)
    }

    func stop() { hum?.stop() }

    // MARK: 걸음 첨벙
    /// 발(머리 아래 바닥)이 물 위에서 걸음 하나만큼(약 45cm) 움직일 때마다 첨벙 소리 + 물결 고리
    private func steps(_ dt: Float, feet: SIMD3<Float>?) {
        stepClock += dt
        guard let f = feet else { lastStep = nil; return }
        let p = SIMD2<Float>(f.x, f.z)
        guard inWater(p, margin: 0) else { lastStep = nil; return }
        guard let l = lastStep else { lastStep = p; stepGap = 0.2; stepClock = 0; return }
        // 몸 자리가 2cm 넘게 움직였을 때만 걸은 거리로 셈 (예전엔 화면마다 4mm 넘게 움직여야 세어,
        // 이 앱처럼 천천히 걸으면 한 화면 사이 움직임이 늘 그보다 작아 첨벙 소리가 전혀 안 났음)
        let d = simd_distance(p, l)
        guard d > 0.02 else { return }
        lastStep = p
        stepGap += min(d, 0.3)
        // 30cm 걸을 때마다 얕은 물을 가볍게 차는 소리 (실제 녹음 네 가지를 번갈아, 크기를 조금씩 다르게)
        if stepGap >= 0.3 {
            stepGap -= 0.3
            stepClock = 0
            var n = Int.random(in: 1...4)
            if n == lastSplash { n = n % 4 + 1 }
            lastSplash = n
            Sfx.play("splash\(n)", in: local, at: SIMD3<Float>(p.x, floorY + 0.05, p.y), gain: Double.random(in: -4 ... -1), rolloff: 0.5)
            ripple(at: p)
        }
    }

    private func ripple(at p: SIMD2<Float>) {
        if rippleMat == nil {
            // 선 그림: 물결 고리를 검은 선으로 (오려 내기), 컬러·흑백: 하얀 물결
            var m = UnlitMaterial(color: look == .line ? UIColor(white: 0.07, alpha: 1) : UIColor(white: 0.95, alpha: 1))
            if let mk = Tex.get("ripple_a", raw: true) {
                var tp = MaterialParameters.Texture(mk); tp.sampler = Tex.clamp
                m.blending = .transparent(opacity: .init(scale: look == .line ? 1 : 0.55, texture: tp))
                if look == .line { m.opacityThreshold = 0.35 }
            } else {
                m.blending = .transparent(opacity: .init(floatLiteral: 0.2))
            }
            m.writesDepth = false
            rippleMat = m
        }
        guard let m = rippleMat else { return }
        var q = Geo()
        let r: Float = 0.5
        q.quad(SIMD3<Float>(-r, 0, -r), SIMD3<Float>(r, 0, -r), SIMD3<Float>(r, 0, r), SIMD3<Float>(-r, 0, r),
               SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(1, 1), SIMD2<Float>(0, 1))
        guard let e = q.entity("ripple", m) else { return }
        e.position = SIMD3<Float>(p.x, floorY + 0.054, p.y)
        e.scale = SIMD3<Float>(repeating: 0.1)
        Sorting.apply(e, 27)
        local.addChild(e)
        ripples.append((e, 0))
        if ripples.count > 6 { ripples.first?.0.removeFromParent(); ripples.removeFirst() }
    }

    // MARK: 매 프레임
    /// hands: 손 자리, feet: 머리 바로 아래 바닥 자리 (저장 좌표)
    /// 물 무늬 흐름만 (같은 세계 무리의 다른 방 개울 — 벽 너머로 보이는 그 방 물길·나가는 물길도 흐르게)
    func flowTick(_ dt: Float) {
        for i in flows.indices {
            var f = flows[i]
            f.3 = (f.3 + f.2 * dt).truncatingRemainder(dividingBy: 1)
            f.1.textureCoordinateTransform.offset = SIMD2<Float>(0, f.3)
            f.0.model?.materials = [f.1]
            flows[i] = f
        }
    }

    func tick(_ dt: Float, hands: [SIMD3<Float>], feet: SIMD3<Float>? = nil) {
        t += dt
        for i in flows.indices {
            var f = flows[i]
            f.3 = (f.3 + f.2 * dt).truncatingRemainder(dividingBy: 1)
            f.1.textureCoordinateTransform.offset = SIMD2<Float>(0, f.3)
            f.0.model?.materials = [f.1]
            flows[i] = f
        }
        steps(dt, feet: feet)
        for i in ripples.indices.reversed() {
            ripples[i].1 += dt
            let a = ripples[i].1 / 1.4
            if a >= 1 { ripples[i].0.removeFromParent(); ripples.remove(at: i); continue }
            ripples[i].0.scale = SIMD3<Float>(repeating: 0.12 + a * 0.9)
            ripples[i].0.setOpacity((1 - a) * (1 - a))
        }
        var g = SystemRandomNumberGenerator()
        // 손이 물 가까이(물 위 50cm 안) 오거나 발이 다가오면 둘레 물고기가 놀라 흩어짐
        var scare = hands.filter { $0.y - floorY < 0.5 && inWater(SIMD2<Float>($0.x, $0.z), margin: 0) }.map { SIMD2<Float>($0.x, $0.z) }
        if let f = feet { scare.append(SIMD2<Float>(f.x, f.z)) }
        for f in fish {
            for hp in scare {
                let d = simd_distance(hp, f.pos)
                if d < 0.45 && f.dart <= 0 {
                    f.dart = Float.random(in: 0.5...0.9, using: &g)
                    let away = f.pos - hp
                    if simd_length(away) > 0.001 { f.head = atan2(away.y, away.x) + Float.random(in: -0.4...0.4, using: &g) }
                }
            }
            // 물 여기저기로 천천히: 가끔 새 목적지 — 가구·바위에 막히지 않게 물길을 따라 돌아가는 길(경유점)로
            f.goalT -= dt
            if f.goalT <= 0 || (f.path.isEmpty && simd_distance(f.pos, f.goal) < 0.15) {
                f.goalT = Float.random(in: 6...14, using: &g)
                let okCells = waterCells.filter { edgeD[$0] >= f.need }
                if let k = okCells.randomElement(using: &g) {
                    f.goal = L.flat(cellP(k))
                    f.path = route(f.pos, f.goal, need: f.need)
                }
            }
            while let w = f.path.first, simd_distance(f.pos, w) < 0.12 { f.path.removeFirst() }
            let aim = f.path.first ?? f.goal
            let tg = aim - f.pos
            var dh = atan2(tg.y, tg.x) - f.head
            while dh > .pi { dh -= 2 * .pi }
            while dh < -.pi { dh += 2 * .pi }
            f.turn += (Float.random(in: -1...1, using: &g) * 1.0 + dh * 1.1 - f.turn) * min(1, dt * 1.2)
            if f.dart <= 0 && Float.random(in: 0...1, using: &g) < dt * 0.04 { f.dart = Float.random(in: 0.3...0.6, using: &g) }
            f.dart -= dt
            let want = f.dart > 0 ? f.cruise * 4.5 : f.cruise * (0.6 + 0.4 * sin(t * 0.3 + f.wag))
            f.speed += (want - f.speed) * min(1, dt * (f.dart > 0 ? 6 : 1.5))
            f.head += f.turn * dt * (f.dart > 0 ? 0.3 : 1)
            var dir = SIMD2<Float>(cos(f.head), sin(f.head))
            var np = f.pos + dir * f.speed * dt
            // 물가에 걸치려 하면: 둘레 방향 중 물가에서 가장 먼 쪽(목적지 쪽을 조금 더 선호)으로 부드럽게 틀고 느려짐
            if edgeAt(np) < f.need && edgeAt(np) <= edgeAt(f.pos) {
                var best = f.head, bs: Float = -1
                for k in 0..<12 {
                    let h = f.head + Float(k) / 12 * 2 * .pi
                    let probe = f.pos + SIMD2<Float>(cos(h), sin(h)) * max(0.08, f.size * 0.6)
                    var dd = h - atan2(tg.y, tg.x)
                    while dd > .pi { dd -= 2 * .pi }
                    while dd < -.pi { dd += 2 * .pi }
                    let sc = edgeAt(probe) - abs(dd) * 0.01
                    if sc > bs { bs = sc; best = h }
                }
                var turn = best - f.head
                while turn > .pi { turn -= 2 * .pi }
                while turn < -.pi { turn += 2 * .pi }
                f.head += max(-dt * 4, min(dt * 4, turn))
                f.turn *= 0.5
                dir = SIMD2<Float>(cos(f.head), sin(f.head))
                np = f.pos + dir * f.speed * dt * 0.35
                if edgeAt(np) < min(f.need, edgeAt(f.pos)) { np = f.pos }
                f.stuck += dt
                if f.stuck > 3 { f.path = route(f.pos, f.goal, need: f.need); f.stuck = 0; f.goalT = min(f.goalT, 1) }
            } else {
                f.stuck = max(0, f.stuck - dt)
            }
            f.pos = np
            f.wag += dt * (6 + f.speed * 60)
            let bob = sin(t * 1.3 + f.wag * 0.1) * 0.003
            f.e.position = SIMD3<Float>(np.x, floorY + 0.008 + f.depth + bob, np.y)
            f.e.orientation = simd_quatf(angle: -f.head, axis: [0, 1, 0]) * simd_quatf(angle: sin(f.wag) * 0.08, axis: [0, 1, 0])
            f.tail.orientation = simd_quatf(angle: sin(f.wag) * (0.35 + min(0.4, f.speed * 2)), axis: [0, 1, 0])
        }
    }
}
