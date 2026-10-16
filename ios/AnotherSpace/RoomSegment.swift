import Foundation
import simd

/// 스캔한 그물 → 위에서 본 격자(10cm 칸) → 방 자동 구분.
/// 순서: 바닥·벽 칸 표시 → 벽의 작은 구멍 메우기 → 걸어 다닌 곳에서 닿는 바닥만 남김(거울 속·벽 너머 가짜 공간 제거)
///       → 벽까지 거리 → 문(1m 안쪽)보다 넓은 곳을 방 '심'으로 → 심에서 바닥을 채워 나감
///       → 1.6m 넘게 트여 맞닿은 방은 하나로(거실+주방) → 너무 작은 방은 옆 방에 합침
/// (tools 에서 같은 규칙을 가상 집 구조로 시험함)
enum RoomSegment {
    static let cell: Float = 0.1
    static let EMPTY: UInt8 = 0, FLOOR: UInt8 = 1, WALL: UInt8 = 2

    struct Input: Sendable {
        var meshes: [MeshCopy]
        var path: [SIMD3<Float>]       // 스캔하며 지나간 머리 위치
        var headY: Float
    }

    /// 스캔 결과로 공간을 만듦. 두 번째 값: 월드 앵커를 둘 자리(저장 좌표)
    static func build(_ inp: Input, id: String, name: String) -> (SpaceData, [SIMD3<Float>])? {
        // 1) 세계 좌표 삼각형
        var P: [SIMD3<Float>] = []
        var C: [UInt8] = []
        for m in inp.meshes {
            let wv = m.v.map { simd_make_float3(m.m * SIMD4<Float>($0, 1)) }
            var i = 0, fi = 0
            while i + 2 < m.f.count {
                let a = Int(m.f[i]), b = Int(m.f[i + 1]), c = Int(m.f[i + 2])
                if a < wv.count, b < wv.count, c < wv.count {
                    P.append(wv[a]); P.append(wv[b]); P.append(wv[c])
                    C.append(fi < m.c.count ? m.c[fi] : 0)
                }
                i += 3; fi += 1
            }
        }
        let nTri = C.count
        guard nTri > 50 else { return nil }
        var N: [SIMD3<Float>] = []
        var Ctr: [SIMD3<Float>] = []
        var Area: [Float] = []
        N.reserveCapacity(nTri); Ctr.reserveCapacity(nTri); Area.reserveCapacity(nTri)
        for t in 0..<nTri {
            let a = P[3 * t], b = P[3 * t + 1], c = P[3 * t + 2]
            let cr = simd_cross(b - a, c - a)
            let l = simd_length(cr)
            N.append(l > 1e-9 ? cr / l : SIMD3<Float>(0, 0, 0))
            Area.append(l * 0.5)
            Ctr.append((a + b + c) / 3)
        }

        // 2) 바닥 높이
        var fys: [Float] = []
        for t in 0..<nTri where C[t] == MeshClass.floor && N[t].y > 0.8 { fys.append(Ctr[t].y) }
        if fys.count < 30 {
            for t in 0..<nTri where N[t].y > 0.85 && Ctr[t].y < inp.headY - 1.0 { fys.append(Ctr[t].y) }
        }
        fys.sort()
        let floorY: Float = fys.isEmpty ? inp.headY - 1.55 : fys[fys.count / 2]

        // 3) 벽의 주된 방향 (네 방향은 같은 것으로: 각도×4의 평균) → 격자를 벽과 나란하게
        var S4: Float = 0, C4: Float = 0
        for t in 0..<nTri {
            let n = N[t], hgt = Ctr[t].y - floorY
            guard abs(n.y) < 0.3, hgt > 0.3, hgt < 2.0, C[t] == MeshClass.wall || C[t] == MeshClass.none else { continue }
            let th = atan2(n.z, n.x)
            C4 += Area[t] * cos(4 * th); S4 += Area[t] * sin(4 * th)
        }
        let angle: Float = (C4 == 0 && S4 == 0) ? 0 : atan2(S4, C4) / 4
        let ex = SIMD2<Float>(cos(angle), sin(angle)), ez = SIMD2<Float>(-sin(angle), cos(angle))
        func loc(_ p: SIMD3<Float>) -> SIMD2<Float> { SIMD2<Float>(simd_dot(p.xz, ex), simd_dot(p.xz, ez)) }

        // 4) 범위: 바닥 면 + 지나간 길 (지나간 길 둘레 최대 15m — 창밖 땅 같은 먼 것 제외)
        var pts: [SIMD2<Float>] = inp.path.map { loc($0) }
        guard !pts.isEmpty else { return nil }
        var pc = pts.reduce(SIMD2<Float>(0, 0), +) / Float(pts.count)
        var plo = pts[0], phi = pts[0]
        for q in pts { plo = simd_min(plo, q); phi = simd_max(phi, q) }
        pc = (plo + phi) / 2
        let reach: Float = 15
        for t in 0..<nTri where (C[t] == MeshClass.floor || N[t].y > 0.85) && abs(Ctr[t].y - floorY) < 0.2 {
            let q = loc(Ctr[t])
            if abs(q.x - pc.x) < reach && abs(q.y - pc.y) < reach { pts.append(q) }
        }
        var lo = pts[0], hi = pts[0]
        for q in pts { lo = simd_min(lo, q); hi = simd_max(hi, q) }
        lo -= SIMD2<Float>(0.6, 0.6); hi += SIMD2<Float>(0.6, 0.6)
        let W = max(10, min(400, Int(ceil((hi.x - lo.x) / cell))))
        let H = max(10, min(400, Int(ceil((hi.y - lo.y) / cell))))
        let origin = ex * lo.x + ez * lo.y
        func cellIndex(_ q: SIMD2<Float>) -> Int? {
            let u = Int(floor((q.x - lo.x) / cell)), v = Int(floor((q.y - lo.y) / cell))
            return (u >= 0 && v >= 0 && u < W && v < H) ? v * W + u : nil
        }

        // 5) 칸마다 바닥·벽·천장 세기
        var floorCnt = [UInt16](repeating: 0, count: W * H)
        var wallCnt = [UInt16](repeating: 0, count: W * H)
        var ceilSum = [Float](repeating: 0, count: W * H)
        var ceilN = [UInt16](repeating: 0, count: W * H)
        for t in 0..<nTri {
            let n = N[t], cl = C[t]
            let hgt = Ctr[t].y - floorY
            if hgt < -0.35 || hgt > 3.8 { continue }
            let isCeil = cl == MeshClass.ceiling && n.y < -0.6 && hgt > 1.8
            let opening = cl == MeshClass.wall || cl == MeshClass.door || cl == MeshClass.window
            let isWall = (opening && abs(n.y) < 0.5 && hgt > 0.25 && hgt < 2.1)
                || ((cl == MeshClass.none || cl == 10) && abs(n.y) < 0.35 && hgt > 1.3 && hgt < 2.0)
            let isFloor = (cl == MeshClass.floor && hgt < 0.3) || (n.y > 0.85 && hgt < 0.08 && hgt > -0.2)
            let isTop = !isWall && !isCeil && n.y > 0.7 && hgt >= 0.08 && hgt < 1.3   // 탁자·의자·침대 윗면 → 그 아래도 바닥
            guard isCeil || isWall || isFloor || isTop else { continue }
            let a = P[3 * t], b = P[3 * t + 1], c = P[3 * t + 2]
            let edge = max(simd_distance(a, b), simd_distance(b, c), simd_distance(c, a))
            let k = max(1, min(40, Int(ceil(edge / (cell * 0.5)))))
            for i in 0...k {
                for j in 0...(k - i) {
                    let p = a + (b - a) * (Float(i) / Float(k)) + (c - a) * (Float(j) / Float(k))
                    guard let ci = cellIndex(loc(p)) else { continue }
                    if isWall { wallCnt[ci] &+= 1 }
                    else if isCeil { ceilSum[ci] += p.y - floorY; ceilN[ci] &+= 1 }
                    else { floorCnt[ci] &+= 1 }
                }
            }
        }
        var kind = [UInt8](repeating: EMPTY, count: W * H)
        for i in 0..<(W * H) {
            if wallCnt[i] >= 2 { kind[i] = WALL } else if floorCnt[i] >= 1 { kind[i] = FLOOR }
        }
        // 지나간 자리는 바닥 (발밑을 못 본 곳)
        var seeds: [Int] = []
        for p in inp.path {
            guard let ci = cellIndex(loc(p)) else { continue }
            let u = ci % W, v = ci / W
            for dv in -1...1 { for du in -1...1 {
                let uu = u + du, vv = v + dv
                if uu >= 0, vv >= 0, uu < W, vv < H, kind[vv * W + uu] == EMPTY { kind[vv * W + uu] = FLOOR }
            } }
            seeds.append(ci)
        }

        // 6) 방 구분
        var room = segment(kind: &kind, w: W, h: H, seeds: seeds)
        var ids = Set(room.map { Int($0) }).subtracting([0]).sorted()
        guard !ids.isEmpty else { return nil }
        // 큰 방부터 1, 2, 3… 으로 번호를 다시 붙임
        var areaOf: [Int: Int] = [:]
        for r in room where r > 0 { areaOf[Int(r), default: 0] += 1 }
        ids.sort { (areaOf[$0] ?? 0) > (areaOf[$1] ?? 0) }
        var remap = [UInt8](repeating: 0, count: 256)
        for (k, r) in ids.prefix(250).enumerated() { remap[r] = UInt8(k + 1) }
        for i in room.indices { room[i] = remap[Int(room[i])] }

        // 7) 방마다 천장 높이 (천장 면 높이의 중간값)
        var allCeil: [Float] = []
        var perRoom: [Int: [Float]] = [:]
        for i in 0..<(W * H) where ceilN[i] > 0 {
            let y = ceilSum[i] / Float(ceilN[i])
            allCeil.append(y)
            if room[i] > 0 { perRoom[Int(room[i]), default: []].append(y) }
        }
        allCeil.sort()
        let globalCeil: Float = allCeil.isEmpty ? 2.4 : allCeil[allCeil.count / 2]
        var g = SystemRandomNumberGenerator()
        var used = Set<String>()
        var rooms: [RoomRec] = []
        for k in 1...min(250, ids.count) {
            var cs = perRoom[k] ?? []
            cs.sort()
            let c = cs.count >= 20 ? cs[cs.count / 2] : globalCeil
            let (p, wth, t) = Worlds.random(using: &g, avoid: used)
            used.insert(p)
            if used.count >= Worlds.places.count { used.removeAll() }
            rooms.append(RoomRec(id: k, name: "공간 \(k)", place: p, weather: wth, time: t, ceil: min(3.6, max(2.0, c))))
        }

        // 8) 월드 앵커 자리: 방마다 가장 넓은 곳 + 2m 간격 격자 (최대 40곳)
        let dist = chamfer(kind, W, H)
        var anchorPts: [SIMD3<Float>] = []
        func wpos(_ i: Int) -> SIMD3<Float> {
            let u = Float(i % W) + 0.5, v = Float(i / W) + 0.5
            let xz = origin + ex * (u * cell) + ez * (v * cell)
            return SIMD3<Float>(xz.x, floorY + 1.2, xz.y)
        }
        for k in 1...rooms.count {
            var best = -1, bd: Int32 = -1
            for i in 0..<(W * H) where Int(room[i]) == k && dist[i] > bd { bd = dist[i]; best = i }
            if best >= 0 { anchorPts.append(wpos(best)) }
        }
        for v in stride(from: 10, to: H, by: 20) {
            for u in stride(from: 10, to: W, by: 20) {
                let i = v * W + u
                if room[i] > 0, dist[i] >= 12, anchorPts.count < 40,
                   anchorPts.allSatisfy({ simd_distance($0, wpos(i)) > 1.2 }) { anchorPts.append(wpos(i)) }
            }
        }

        let rec = SpaceRec(id: id, name: name, at: Date().timeIntervalSince1970 * 1000, cell: cell, angle: angle,
                           ox: origin.x, oz: origin.y, w: W, h: H, floorY: floorY, anchors: [], rooms: rooms)
        return (SpaceData(rec: rec, kind: kind, room: room), anchorPts)
    }

    // MARK: 방 구분 (격자만으로)
    /// seeds가 있으면 그 칸에서 닿는 바닥만 남김 (나머지 바닥은 없음으로 바꿈)
    static func segment(kind: inout [UInt8], w W: Int, h H: Int, seeds: [Int]? = nil) -> [UInt8] {
        let n = W * H
        // 벽 닫기: 한 칸 넓혔다가 다시 줄임 → 1~2칸짜리 구멍이 메워짐 (문은 그대로)
        var dil = [Bool](repeating: false, count: n)
        for v in 0..<H { for u in 0..<W where kind[v * W + u] == WALL {
            for dv in -1...1 { for du in -1...1 {
                let uu = u + du, vv = v + dv
                if uu >= 0, vv >= 0, uu < W, vv < H { dil[vv * W + uu] = true }
            } }
        } }
        for v in 0..<H { for u in 0..<W where dil[v * W + u] {
            var all = true
            for dv in -1...1 { for du in -1...1 {
                let uu = u + du, vv = v + dv
                if uu < 0 || vv < 0 || uu >= W || vv >= H || !dil[vv * W + uu] { all = false }
            } }
            if all { kind[v * W + u] = WALL }
        } }
        // 바닥 속 작은 구멍(가구 밑 등) 메우기
        for _ in 0..<3 {
            var fill: [Int] = []
            for v in 1..<(H - 1) { for u in 1..<(W - 1) where kind[v * W + u] == EMPTY {
                var c = 0
                if kind[v * W + u + 1] == FLOOR { c += 1 }
                if kind[v * W + u - 1] == FLOOR { c += 1 }
                if kind[(v + 1) * W + u] == FLOOR { c += 1 }
                if kind[(v - 1) * W + u] == FLOOR { c += 1 }
                if c >= 3 { fill.append(v * W + u) }
            } }
            for i in fill { kind[i] = FLOOR }
        }
        // 걸어 다닌 곳에서 닿는 바닥만
        if let seeds {
            var reach = [Bool](repeating: false, count: n)
            var q: [Int] = []
            for s in seeds where s >= 0 && s < n && kind[s] == FLOOR && !reach[s] { reach[s] = true; q.append(s) }
            var qi = 0
            while qi < q.count {
                let i = q[qi]; qi += 1
                let u = i % W, v = i / W
                for (du, dv) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let uu = u + du, vv = v + dv
                    guard uu >= 0, vv >= 0, uu < W, vv < H else { continue }
                    let j = vv * W + uu
                    if !reach[j] && kind[j] == FLOOR { reach[j] = true; q.append(j) }
                }
            }
            for i in 0..<n where kind[i] == FLOOR && !reach[i] { kind[i] = EMPTY }
        }
        let d = chamfer(kind, W, H)
        var lab = [Int](repeating: 0, count: n)
        var next = 1
        let T: Int32 = 18          // 벽에서 약 0.6m (체임퍼 3 = 한 칸) — 문(1m 안쪽)은 여기서 끊김
        for s in 0..<n where d[s] >= T && lab[s] == 0 {
            var comp = [s]; lab[s] = next
            var ci = 0
            while ci < comp.count {
                let i = comp[ci]; ci += 1
                let u = i % W, v = i / W
                for (du, dv) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let uu = u + du, vv = v + dv
                    guard uu >= 0, vv >= 0, uu < W, vv < H else { continue }
                    let j = vv * W + uu
                    if lab[j] == 0 && d[j] >= T { lab[j] = next; comp.append(j) }
                }
            }
            if comp.count < 6 { for i in comp { lab[i] = 0 } } else { next += 1 }
        }
        // 심에서 바닥을 채워 나감 (벽에서 먼 칸부터)
        let maxD = Int(d.max() ?? 0)
        var buckets = [[Int]](repeating: [], count: maxD + 1)
        for i in 0..<n where lab[i] > 0 { buckets[Int(d[i])].append(i) }
        var ptr = maxD
        while ptr >= 0 {
            guard let i = buckets[ptr].popLast() else { ptr -= 1; continue }
            let u = i % W, v = i / W
            for (du, dv) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let uu = u + du, vv = v + dv
                guard uu >= 0, vv >= 0, uu < W, vv < H else { continue }
                let j = vv * W + uu
                if kind[j] == FLOOR && lab[j] == 0 {
                    lab[j] = lab[i]
                    let dj = Int(d[j])
                    buckets[dj].append(j)
                    if dj > ptr { ptr = dj }
                }
            }
        }
        // 심이 없는 남은 바닥(좁은 드레스룸 등) → 따로 방으로
        for s in 0..<n where kind[s] == FLOOR && lab[s] == 0 {
            var comp = [s]; lab[s] = next
            var ci = 0
            while ci < comp.count {
                let i = comp[ci]; ci += 1
                let u = i % W, v = i / W
                for (du, dv) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let uu = u + du, vv = v + dv
                    guard uu >= 0, vv >= 0, uu < W, vv < H else { continue }
                    let j = vv * W + uu
                    if lab[j] == 0 && kind[j] == FLOOR { lab[j] = next; comp.append(j) }
                }
            }
            next += 1
        }
        // 넓게(1.6m 넘게) 맞닿은 두 방은 하나로 — 문은 1m 안쪽이라 그대로 나뉨
        while true {
            var touch: [Int: Set<Int>] = [:]          // 두 방 쌍(작은 id·큰 id) → 맞닿은 칸
            for v in 0..<H { for u in 0..<W {
                let a = lab[v * W + u]
                if a == 0 { continue }
                for (du, dv) in [(1, 0), (0, 1)] {
                    let uu = u + du, vv = v + dv
                    guard uu < W, vv < H else { continue }
                    let b = lab[vv * W + uu]
                    if b != 0 && b != a {
                        let key = min(a, b) * 4096 + max(a, b)
                        touch[key, default: []].insert(a < b ? v * W + u : vv * W + uu)
                    }
                }
            } }
            guard let best = touch.filter({ $0.value.count >= 16 }).max(by: { $0.value.count < $1.value.count }) else { break }
            let a = best.key / 4096, b = best.key % 4096
            for i in 0..<n where lab[i] == b { lab[i] = a }
        }
        // 너무 작은 방(0.8㎡ 미만)은 벽 너머 30cm 안의 이웃 중 가장 많이 맞댄 방에 합침
        var guardLoop = 0
        while guardLoop < 300 {
            guardLoop += 1
            var area: [Int: Int] = [:]
            for l in lab where l > 0 { area[l, default: 0] += 1 }
            guard let small = area.filter({ $0.value < 80 }).min(by: { $0.value < $1.value })?.key else { break }
            var cnt: [Int: Int] = [:]
            for v in 0..<H { for u in 0..<W where lab[v * W + u] == small {
                for (du, dv) in [(1, 0), (-1, 0), (0, 1), (0, -1), (2, 0), (-2, 0), (0, 2), (0, -2), (3, 0), (-3, 0), (0, 3), (0, -3)] {
                    let uu = u + du, vv = v + dv
                    guard uu >= 0, vv >= 0, uu < W, vv < H else { continue }
                    let b = lab[vv * W + uu]
                    if b != 0 && b != small { cnt[b, default: 0] += 1 }
                }
            } }
            if let to = cnt.max(by: { $0.value < $1.value })?.key {
                for i in 0..<n where lab[i] == small { lab[i] = to }
            } else if (area[small] ?? 0) < 30 {
                for i in 0..<n where lab[i] == small { lab[i] = 0; kind[i] = EMPTY }   // 혼자 떨어진 아주 작은 조각은 버림
            } else {
                break
            }
        }
        // 번호를 1부터 차례로 (최대 250개)
        var remap: [Int: UInt8] = [:]
        var out = [UInt8](repeating: 0, count: n)
        for i in 0..<n where lab[i] > 0 {
            if remap[lab[i]] == nil {
                if remap.count >= 250 { continue }
                remap[lab[i]] = UInt8(remap.count + 1)
            }
            out[i] = remap[lab[i]] ?? 0
        }
        return out
    }

    /// 바닥 칸마다 바닥이 아닌 칸까지의 거리 (체임퍼 3-4: 한 칸 3, 대각선 4)
    static func chamfer(_ kind: [UInt8], _ W: Int, _ H: Int) -> [Int32] {
        let INF: Int32 = 1 << 28
        var d = [Int32](repeating: 0, count: W * H)
        for i in 0..<(W * H) { d[i] = kind[i] == FLOOR ? INF : 0 }
        for v in 0..<H {
            for u in 0..<W where d[v * W + u] != 0 {
                var m = d[v * W + u]
                m = min(m, (u > 0 ? d[v * W + u - 1] : 0) + 3)
                m = min(m, (v > 0 ? d[(v - 1) * W + u] : 0) + 3)
                m = min(m, (u > 0 && v > 0 ? d[(v - 1) * W + u - 1] : 0) + 4)
                m = min(m, (u < W - 1 && v > 0 ? d[(v - 1) * W + u + 1] : 0) + 4)
                d[v * W + u] = m
            }
        }
        for v in stride(from: H - 1, through: 0, by: -1) {
            for u in stride(from: W - 1, through: 0, by: -1) where d[v * W + u] != 0 {
                var m = d[v * W + u]
                m = min(m, (u < W - 1 ? d[v * W + u + 1] : 0) + 3)
                m = min(m, (v < H - 1 ? d[(v + 1) * W + u] : 0) + 3)
                m = min(m, (u < W - 1 && v < H - 1 ? d[(v + 1) * W + u + 1] : 0) + 4)
                m = min(m, (u > 0 && v < H - 1 ? d[(v + 1) * W + u - 1] : 0) + 4)
                d[v * W + u] = m
            }
        }
        return d
    }
}
