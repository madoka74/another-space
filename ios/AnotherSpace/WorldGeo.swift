import Foundation
import RealityKit
import simd

/// 여러 물체를 '그물 하나'로 모아 만드는 도구.
/// 나무 30그루를 엔티티 30개로 만들면 그릴 때마다 30번 따로 그리지만, 하나로 모으면 한 번에 그림 → 방마다 엔티티 수십 개 → 몇 개
struct Geo {
    var pos: [SIMD3<Float>] = []
    var uv: [SIMD2<Float>] = []
    var idx: [UInt32] = []
    var rocksMade: [(Int, SIMD3<Float>)] = []      // 선 그림일 때 만든 바위 (시작 번호, 가운데) — 외곽선 껍데기(inkHull)용

    var isEmpty: Bool { idx.isEmpty }

    /// 다른 그물을 (옮기고 돌린 뒤) 이어 붙임
    mutating func append(_ o: Geo, transform m: simd_float4x4 = matrix_identity_float4x4) {
        let base = UInt32(pos.count)
        pos += o.pos.map { simd_make_float3(m * SIMD4<Float>($0, 1)) }
        uv += o.uv
        idx += o.idx.map { $0 + base }
    }

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

    /// 한쪽에서만 보이는 세운 판 (앞면이 n 쪽). 반대편에서는 보이지 않음(뒷면은 그리지 않음) →
    /// 두 방이 맞닿은 같은 줄에 각자 자기 쪽을 보는 벽을 세워도 겹쳐 깜빡이지 않고, 틈을 막으려 띄우거나 늘릴 필요가 없음.
    /// (RealityKit은 반시계 방향으로 감긴 삼각형이 앞면)
    mutating func face(_ a: SIMD3<Float>, _ b: SIMD3<Float>, toward n: SIMD3<Float>, y0: Float, y1: Float,
                       u0: Float, u1: Float, v0: Float = 0, v1: Float = 1) {
        let d = b - a
        let front = SIMD3<Float>(-d.z, 0, d.x)                 // (b-a) × 위쪽
        let lo = SIMD3<Float>(0, y0, 0), hi = SIMD3<Float>(0, y1, 0)
        if simd_dot(front, n) >= 0 {
            quad(a + lo, b + lo, b + hi, a + hi, SIMD2<Float>(u0, v0), SIMD2<Float>(u1, v0), SIMD2<Float>(u1, v1), SIMD2<Float>(u0, v1), twoSided: false)
        } else {
            quad(b + lo, a + lo, a + hi, b + hi, SIMD2<Float>(u1, v0), SIMD2<Float>(u0, v0), SIMD2<Float>(u0, v1), SIMD2<Float>(u1, v1), twoSided: false)
        }
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

    // MARK: 입체 나무 (얇은 판 두 장을 엇갈린 나무 대신: 줄기는 둥근 기둥, 잎은 잎 덩이 판 수십 장을 사방으로 꽂아 어느 쪽에서 봐도 부피가 있게)
    /// 위로 가늘어지는 둥근 기둥 (줄기·가지). bend: 가운데가 휘는 정도(방향·크기). 나무껍질 무늬는 둘레 1바퀴 = u 1, 세로 1.2m = v 1
    mutating func trunk(from a: SIMD3<Float>, to b: SIMD3<Float>, r0: Float, r1: Float, sides: Int = 8, segs: Int = 4, bend: SIMD3<Float> = .zero) {
        let ax = simd_normalize(b - a)
        let ref = abs(ax.y) > 0.9 ? SIMD3<Float>(1, 0, 0) : SIMD3<Float>(0, 1, 0)
        let e1 = simd_normalize(simd_cross(ax, ref)), e2 = simd_cross(ax, e1)
        let len = simd_distance(a, b)
        func ring(_ t: Float) -> [SIMD3<Float>] {
            let c = a + (b - a) * t + bend * (4 * t * (1 - t))
            let r = r0 + (r1 - r0) * t
            return (0...sides).map { (k: Int) -> SIMD3<Float> in
                let ang = Float(k) / Float(sides) * 2 * .pi
                return c + (e1 * cos(ang) + e2 * sin(ang)) * r
            }
        }
        var prev = ring(0)
        for i in 1...segs {
            let t1 = Float(i) / Float(segs), t0 = Float(i - 1) / Float(segs)
            let cur = ring(t1)
            for k in 0..<sides {
                let u0 = Float(k) / Float(sides), u1 = Float(k + 1) / Float(sides)
                quad(prev[k], prev[k + 1], cur[k + 1], cur[k], SIMD2<Float>(u0, t0 * len / 1.2), SIMD2<Float>(u1, t0 * len / 1.2),
                     SIMD2<Float>(u1, t1 * len / 1.2), SIMD2<Float>(u0, t1 * len / 1.2))
            }
            prev = cur
        }
    }

    /// 잎 판 하나: 가운데 c, 판 안의 두 축 ua(가로)·ub(세로), 크기 w×h (그림 전체)
    mutating func card(_ c: SIMD3<Float>, _ ua: SIMD3<Float>, _ ub: SIMD3<Float>, w: Float, h: Float) {
        let x = ua * (w / 2), y = ub * (h / 2)
        quad(c - x - y, c + x - y, c + x + y, c - x + y, SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(1, 1), SIMD2<Float>(0, 1))
    }

    /// 가지 판: 뿌리 p에서 dir 쪽으로 길이 L, 폭 w (그림의 왼쪽 = 뿌리, 오른쪽 = 끝). side: 판의 폭 방향
    mutating func branchCard(_ p: SIMD3<Float>, dir: SIMD3<Float>, side: SIMD3<Float>, L: Float, w: Float, u0: Float = 0, u1: Float = 1) {
        let s = side * (w / 2)
        quad(p - s, p + dir * L - s, p + dir * L + s, p + s, SIMD2<Float>(u0, 0), SIMD2<Float>(u1, 0), SIMD2<Float>(u1, 1), SIMD2<Float>(u0, 1))
    }

    /// 넓은잎나무: 줄기 + 굵은 가지 몇 개 + 둥근 수관 (잎 덩이 판 30여 장을 타원체 둘레에 엇갈려)
    static func broadTree<G: RandomNumberGenerator>(_ trunk: inout Geo, _ leaves: inout Geo, at p: SIMD3<Float>, height h: Float, width w: Float, using g: inout G) {
        let lean = SIMD3<Float>(Float.random(in: -0.04...0.04, using: &g), 0, Float.random(in: -0.04...0.04, using: &g)) * h
        let top = p + SIMD3<Float>(0, h * 0.6, 0) + lean
        trunk.trunk(from: p - SIMD3<Float>(0, 0.2, 0), to: top, r0: h * 0.038, r1: h * 0.02, sides: 9, segs: 5,
                    bend: SIMD3<Float>(Float.random(in: -0.3...0.3, using: &g), 0, Float.random(in: -0.3...0.3, using: &g)))
        let c = p + SIMD3<Float>(0, h * 0.66, 0) + lean
        let rx = w * 0.7, ry = h * 0.3
        for _ in 0..<Int.random(in: 3...5, using: &g) {
            let a = Float.random(in: 0...(2 * .pi), using: &g)
            let from = p + SIMD3<Float>(0, h * Float.random(in: 0.42...0.56, using: &g), 0) + lean * 0.8
            let to = c + SIMD3<Float>(cos(a) * rx * 0.6, Float.random(in: -0.1...0.25, using: &g) * ry, sin(a) * rx * 0.6)
            trunk.trunk(from: from, to: to, r0: h * 0.014, r1: h * 0.005, sides: 6, segs: 2)
        }
        let n = 26 + Int(w * 1.5)
        for i in 0..<n {
            // 바깥쪽에 많이 (안쪽은 조금): 타원체 위 점, 판은 바깥을 향하되 조금씩 엇갈림
            let az = Float.random(in: 0...(2 * .pi), using: &g)
            let el = asin(Float.random(in: -0.75...1, using: &g))
            let rr: Float = i < n / 6 ? Float.random(in: 0.2...0.55, using: &g) : Float.random(in: 0.62...0.98, using: &g)
            let dir = SIMD3<Float>(cos(el) * cos(az), sin(el), cos(el) * sin(az))
            let q = c + SIMD3<Float>(dir.x * rx, dir.y * ry, dir.z * rx) * rr
            var nrm = simd_normalize(dir + SIMD3<Float>(Float.random(in: -0.6...0.6, using: &g), Float.random(in: -0.4...0.6, using: &g), Float.random(in: -0.6...0.6, using: &g)))
            if simd_length(nrm) < 0.1 { nrm = SIMD3<Float>(0, 1, 0) }
            let ref = abs(nrm.y) > 0.9 ? SIMD3<Float>(1, 0, 0) : SIMD3<Float>(0, 1, 0)
            var ua = simd_normalize(simd_cross(ref, nrm))
            let spin = Float.random(in: -0.6...0.6, using: &g)
            ua = simd_quatf(angle: spin, axis: nrm).act(ua)
            let ub = simd_cross(nrm, ua)
            let sz = w * Float.random(in: 0.34...0.5, using: &g)
            leaves.card(q, ua, ub, w: sz, h: sz)
        }
    }

    /// 침엽수: 꼭대기까지 곧은 줄기 + 층층이 둘러 난 처진 가지 판 (아래가 넓고 위로 갈수록 짧아 원뿔 모양)
    static func pineTree<G: RandomNumberGenerator>(_ trunk: inout Geo, _ leaves: inout Geo, at p: SIMD3<Float>, height h: Float, width w: Float, using g: inout G) {
        trunk.trunk(from: p - SIMD3<Float>(0, 0.2, 0), to: p + SIMD3<Float>(0, h * 0.97, 0), r0: h * 0.03, r1: h * 0.004, sides: 8, segs: 5)
        let tiers = 10 + Int(h / 3)
        for k in 0..<tiers {
            let t = Float(k) / Float(tiers - 1)                         // 0 아래 → 1 위
            let y = h * (0.22 + 0.74 * t)
            let L = (w / 2) * (1 - t * 0.88) + 0.25
            let m = max(4, Int(7 - t * 3))
            let off = Float.random(in: 0...(2 * .pi), using: &g)
            for j in 0..<m {
                let a = off + Float(j) / Float(m) * 2 * .pi + Float.random(in: -0.2...0.2, using: &g)
                let droop = -0.18 - 0.22 * (1 - t) + Float.random(in: -0.08...0.08, using: &g)
                let dir = simd_normalize(SIMD3<Float>(cos(a), droop, sin(a)))
                var side = simd_normalize(simd_cross(dir, SIMD3<Float>(0, 1, 0)))
                side = simd_normalize(side + SIMD3<Float>(0, Float.random(in: -0.35...0.35, using: &g), 0))
                leaves.branchCard(p + SIMD3<Float>(0, y, 0), dir: dir, side: side, L: L, w: L * 0.62)
            }
        }
        // 뾰족한 꼭대기
        for k in 0..<3 {
            let a = Float(k) / 3 * .pi
            let s = SIMD3<Float>(cos(a), 0, sin(a))
            leaves.branchCard(p + SIMD3<Float>(0, h * 0.86, 0), dir: SIMD3<Float>(0, 1, 0), side: s, L: h * 0.16, w: h * 0.08)
        }
    }

    /// 야자나무(바닷가): 한쪽으로 휜 줄기 + 꼭대기에서 사방으로 뻗어 끝이 처지는 잎 10여 장
    static func palmTree<G: RandomNumberGenerator>(_ trunk: inout Geo, _ leaves: inout Geo, at p: SIMD3<Float>, height h: Float, width w: Float, using g: inout G) {
        let a0 = Float.random(in: 0...(2 * .pi), using: &g)
        let leanDir = SIMD3<Float>(cos(a0), 0, sin(a0))
        let top = p + SIMD3<Float>(0, h, 0) + leanDir * h * Float.random(in: 0.12...0.25, using: &g)
        trunk.trunk(from: p - SIMD3<Float>(0, 0.2, 0), to: top, r0: h * 0.03, r1: h * 0.019, sides: 8, segs: 7, bend: leanDir * h * 0.08)
        let n = 11
        for j in 0..<n {
            let a = Float(j) / Float(n) * 2 * .pi + Float.random(in: -0.15...0.15, using: &g)
            let hd = SIMD3<Float>(cos(a), 0, sin(a))
            let L = h * Float.random(in: 0.4...0.5, using: &g)
            let up = Float.random(in: 0.25...0.6, using: &g)
            let d1 = simd_normalize(hd + SIMD3<Float>(0, up, 0))
            let d2 = simd_normalize(hd + SIMD3<Float>(0, up - 1.1, 0))
            var side = simd_normalize(simd_cross(hd, SIMD3<Float>(0, 1, 0)))
            side = simd_normalize(side + SIMD3<Float>(0, Float.random(in: -0.3...0.3, using: &g), 0))
            let mid = top + d1 * L * 0.5
            leaves.branchCard(top, dir: d1, side: side, L: L * 0.5, w: L * 0.28, u0: 0, u1: 0.5)
            leaves.branchCard(mid, dir: d2, side: side, L: L * 0.5, w: L * 0.28, u0: 0.5, u1: 1)
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
    @discardableResult
    mutating func rock<G: RandomNumberGenerator>(at c: SIMD3<Float>, size s: Float, using g: inout G) -> Int {
        let seg = 9, rings = 6
        let base = UInt32(pos.count)
        if Geo.inkMin > 0 { rocksMade.append((Int(base), c)) }
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
        return Int(base)
    }

    /// 선 그림 외곽선: src 에 rock() 으로 만든 바위(시작 번호 start, 가운데 c)를 굵기 w만큼 부풀린 '바깥을 향한 한쪽 면' 껍데기.
    /// 이 그물을 Ink.hullMat(뒷면만 그림)으로 그리면 바위 둘레에 어느 쪽에서 봐도 검은 윤곽선이 생김
    mutating func rockHull(of src: Geo, start: Int, center c: SIMD3<Float>, width w: Float) {
        let seg = 9, rings = 6
        let n = (rings + 1) * (seg + 1)
        guard start + n <= src.pos.count else { return }
        let base = UInt32(pos.count)
        for i in 0..<n {
            let p = src.pos[start + i]
            let d = p - c
            let l = simd_length(d)
            pos.append(l > 1e-5 ? c + d * ((l + w) / l) : p)
            uv.append(.zero)
        }
        for r in 0..<UInt32(rings) {
            for k in 0..<UInt32(seg) {
                let a = base + r * UInt32(seg + 1) + k, b = a + UInt32(seg + 1)
                idx += [a, a + 1, b, a + 1, b + 1, b]            // 바깥을 향한 면만
            }
        }
    }

    /// 선 그림 나무 수관·덤불 등 둥근 덩어리: rock() 과 같은 짜임(9×6)이라 inkHull 외곽선을 그대로 씀.
    /// rx·rz 가로 반지름, up·down 위·아래 높이, pointy: 위로 갈수록 뾰족(침엽수 층), lumpy: 울퉁불퉁한 정도
    @discardableResult
    mutating func blob<G: RandomNumberGenerator>(at c: SIMD3<Float>, rx: Float, rz: Float, up: Float, down: Float, pointy: Bool = false,
                                                 lumpy: Float = 0.12, yaw: Float = 0, using g: inout G) -> Int {
        let seg = 9, rings = 6
        let base = UInt32(pos.count)
        if Geo.inkMin > 0 { rocksMade.append((Int(base), c)) }
        var rad: [Float] = []
        for _ in 0...(rings * (seg + 1)) { rad.append(1 + Float.random(in: -lumpy...lumpy, using: &g)) }
        let ca = cos(yaw), sa = sin(yaw)
        for r in 0...rings {
            let el = Float.pi / 2 - Float.pi * Float(r) / Float(rings)
            let k: Float = pointy && el > 0 ? pow(max(0, 1 - sin(el)), 0.85) : cos(el)
            let y = sin(el) * (el > 0 ? up : down)
            for q in 0...seg {
                let az = Float(q) / Float(seg) * 2 * .pi
                let j = min(rad.count - 1, r * (seg + 1) + (q == seg ? 0 : q))
                let rr = (r == 0 || r == rings) ? 1 : rad[j]
                let lx = cos(az) * rx * k * rr, lz = sin(az) * rz * k * rr
                pos.append(c + SIMD3<Float>(lx * ca - lz * sa, y * (r == 0 || r == rings ? 1 : (1 + (rr - 1) * 0.5)), lx * sa + lz * ca))
                uv.append(SIMD2<Float>(Float(q) / Float(seg), Float(r) / Float(rings)))
            }
        }
        for r in 0..<UInt32(rings) {
            for q in 0..<UInt32(seg) {
                let a = base + r * UInt32(seg + 1) + q, b = a + UInt32(seg + 1)
                idx += [a, b, a + 1, a + 1, b, b + 1, a, a + 1, b, a + 1, b + 1, b]
            }
        }
        return Int(base)
    }

    /// 한쪽 면 사각형 (앞면이 out 쪽) — 외곽선 껍데기용
    mutating func shellQuad(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>, out: SIMD3<Float>) {
        let n = simd_cross(b - a, c - a)
        if simd_dot(n, out) >= 0 {
            quad(a, b, c, d, .zero, .zero, .zero, .zero, twoSided: false)
        } else {
            quad(a, d, c, b, .zero, .zero, .zero, .zero, twoSided: false)
        }
    }

    /// 선 그림 외곽선 껍데기: 줄기·가지(trunk 와 같은 모양)를 굵기 w만큼 부풀린 '바깥을 향한 면' — Ink.hullMat 으로 그리면 둘레에 검은 선
    mutating func trunkHull(from a: SIMD3<Float>, to b: SIMD3<Float>, r0: Float, r1: Float, width w: Float, sides: Int = 8, segs: Int = 4, bend: SIMD3<Float> = .zero) {
        let ax = simd_normalize(b - a)
        let ref = abs(ax.y) > 0.9 ? SIMD3<Float>(1, 0, 0) : SIMD3<Float>(0, 1, 0)
        let e1 = simd_normalize(simd_cross(ax, ref)), e2 = simd_cross(ax, e1)
        func center(_ t: Float) -> SIMD3<Float> { a + (b - a) * t + bend * (4 * t * (1 - t)) }
        func ring(_ t: Float) -> [SIMD3<Float>] {
            let c = center(t)
            let r = r0 + (r1 - r0) * t + w
            return (0...sides).map { (k: Int) -> SIMD3<Float> in
                let ang = Float(k) / Float(sides) * 2 * .pi
                return c + (e1 * cos(ang) + e2 * sin(ang)) * r
            }
        }
        var prev = ring(0)
        for i in 1...segs {
            let t1 = Float(i) / Float(segs)
            let cur = ring(t1)
            let mid = center((Float(i) - 0.5) / Float(segs))
            for k in 0..<sides {
                let m = (prev[k] + prev[k + 1] + cur[k + 1] + cur[k]) / 4
                shellQuad(prev[k], prev[k + 1], cur[k + 1], cur[k], out: m - mid)
            }
            prev = cur
        }
    }

    /// 선 그림 나무: 흰 종이 줄기·수관 + 같은 펜 굵기(w)의 외곽선. 잎 판(오려 낸 그림) 대신 덩어리로 그려 윤곽선이 또렷하고 굵기가 다른 물체와 같음.
    /// kind: "tree_pine" 침엽수, "tree_twisted" 야자, 그 밖 넓은잎나무. paper: 수관·줄기(흰), hull: 외곽선 껍데기
    static func inkTree<G: RandomNumberGenerator>(_ kind: String, _ paper: inout Geo, _ hull: inout Geo, at p: SIMD3<Float>,
                                                  height h: Float, width w: Float, pen: Float, using g: inout G) {
        switch kind {
        case "tree_pine":
            let r0 = h * 0.03, r1 = h * 0.008
            paper.trunk(from: p - SIMD3<Float>(0, 0.2, 0), to: p + SIMD3<Float>(0, h * 0.3, 0), r0: r0, r1: r0 * 0.8, sides: 8, segs: 1)
            hull.trunkHull(from: p - SIMD3<Float>(0, 0.2, 0), to: p + SIMD3<Float>(0, h * 0.3, 0), r0: r0, r1: r0 * 0.8, width: pen, segs: 1)
            _ = r1
            // 층층이 쌓인 원뿔 (아래가 넓고 위로 갈수록 좁게) — 위층이 아래층 끝을 조금 덮음
            let tiers = 4
            for k in 0..<tiers {
                let t = Float(k) / Float(tiers)
                let y = h * (0.24 + 0.62 * t)
                let rr = (w / 2) * (1 - t * 0.72)
                paper.blob(at: p + SIMD3<Float>(0, y, 0), rx: rr, rz: rr * Float.random(in: 0.9...1.1, using: &g), up: h * 0.3 * (1 - t * 0.3),
                           down: h * 0.04, pointy: true, lumpy: 0.08, yaw: Float.random(in: 0...6.28, using: &g), using: &g)
            }
        case "tree_twisted":
            let a0 = Float.random(in: 0...(2 * .pi), using: &g)
            let lean = SIMD3<Float>(cos(a0), 0, sin(a0))
            let top = p + SIMD3<Float>(0, h, 0) + lean * h * Float.random(in: 0.12...0.25, using: &g)
            let bend = lean * h * 0.08
            paper.trunk(from: p - SIMD3<Float>(0, 0.2, 0), to: top, r0: h * 0.03, r1: h * 0.019, sides: 8, segs: 6, bend: bend)
            hull.trunkHull(from: p - SIMD3<Float>(0, 0.2, 0), to: top, r0: h * 0.03, r1: h * 0.019, width: pen, segs: 6, bend: bend)
            // 잎: 사방으로 뻗어 끝이 처지는 길쭉한 잎 덩이
            for j in 0..<8 {
                let a = Float(j) / 8 * 2 * .pi + Float.random(in: -0.15...0.15, using: &g)
                let L = h * Float.random(in: 0.2...0.26, using: &g)
                let c = top + SIMD3<Float>(cos(a) * L, -L * 0.25, sin(a) * L)
                paper.blob(at: c, rx: L * 1.05, rz: L * 0.22, up: L * 0.12, down: L * 0.3, lumpy: 0.06, yaw: -a, using: &g)
            }
        default:
            let lean = SIMD3<Float>(Float.random(in: -0.04...0.04, using: &g), 0, Float.random(in: -0.04...0.04, using: &g)) * h
            let top = p + SIMD3<Float>(0, h * 0.6, 0) + lean
            paper.trunk(from: p - SIMD3<Float>(0, 0.2, 0), to: top, r0: h * 0.038, r1: h * 0.022, sides: 9, segs: 3)
            hull.trunkHull(from: p - SIMD3<Float>(0, 0.2, 0), to: top, r0: h * 0.038, r1: h * 0.022, width: pen, sides: 9, segs: 3)
            // 둥근 수관: 큰 덩어리 하나 + 둘레에 작은 덩어리 몇 개 (뭉게뭉게한 윤곽)
            let c = p + SIMD3<Float>(0, h * 0.68, 0) + lean
            let rx = w * 0.6, ry = h * 0.27
            paper.blob(at: c, rx: rx, rz: rx * Float.random(in: 0.85...1.05, using: &g), up: ry, down: ry * 0.8, lumpy: 0.1, yaw: Float.random(in: 0...6.28, using: &g), using: &g)
            for k in 0..<4 {
                let a = Float(k) / 4 * 2 * .pi + Float.random(in: -0.4...0.4, using: &g)
                let q = c + SIMD3<Float>(cos(a) * rx * 0.55, Float.random(in: -0.15...0.35, using: &g) * ry, sin(a) * rx * 0.55)
                let s = rx * Float.random(in: 0.45...0.6, using: &g)
                paper.blob(at: q, rx: s, rz: s, up: s * 0.85, down: s * 0.7, lumpy: 0.12, yaw: a, using: &g)
            }
        }
    }

    /// 선 그림용 가는 선 (a→b, 굵기 w): 서로 직각인 얇은 띠 두 장 — 어느 쪽에서 봐도 선으로 보임
    /// 선 그림일 때 가장 가는 선 굵기 (Tex.look 이 선 그림이면 0.6cm) — 실내 가구 테두리(1cm)와 배경·소품의 선 굵기가 너무 달라
    /// 가는 선이 묻혀 보이던 것을 비슷한 굵기로 맞춤
    static var inkMin: Float = 0
    /// 선 그림 방을 만드는 동안 보는 눈 자리 (방 가운데 1.5m 높이). 있으면 모든 선을 '눈에서 떨어진 거리에 맞춘 같은 펜 굵기'로 —
    /// 가까운 실내·소품과 먼 나무·집·절벽 선이 눈에 비슷한 굵기로 보이게 (예전엔 곳마다 굵기를 따로 정해 가늘거나 굵었음)
    static var inkEye: SIMD3<Float>?
    /// 펜 굵기: 가까이 0.7cm, 2.5m 넘으면 거리에 비례 (Ink.width 와 같은 식)
    static func penWidth(at d: Float) -> Float { 0.007 * max(1, d / 2.5) }

    mutating func stroke(_ a: SIMD3<Float>, _ b: SIMD3<Float>, width w0: Float) {
        var w = max(w0, Geo.inkMin)
        if let e = Geo.inkEye, Geo.inkMin > 0 { w = Geo.penWidth(at: simd_distance((a + b) / 2, e)) }
        let d = b - a
        let l = simd_length(d)
        guard l > 1e-4 else { return }
        let dir = d / l
        var p1 = simd_cross(dir, SIMD3<Float>(0, 1, 0))
        if simd_length(p1) < 0.1 { p1 = simd_cross(dir, SIMD3<Float>(1, 0, 0)) }
        p1 = simd_normalize(p1) * (w / 2)
        let p2 = simd_normalize(simd_cross(dir, p1)) * (w / 2)
        // 가는 네모 막대: 네 옆면이 모두 선이 지나는 면에서 굵기 절반만큼 떨어져 있어
        // 벽·가구 면과 같은 자리에 겹쳐 깜빡이지(z-fighting) 않음. 양끝을 굵기 절반 늘려 모서리 이음새도 메움
        let a2 = a - dir * (w / 2), b2 = b + dir * (w / 2)
        let c = [p1 + p2, p1 - p2, -p1 - p2, -p1 + p2]
        for k in 0..<4 {
            let o0 = c[k], o1 = c[(k + 1) % 4]
            quad(a2 + o0, b2 + o0, b2 + o1, a2 + o1, .zero, .zero, .zero, .zero)
        }
    }

    /// 선 그림: 상자 모서리 12개
    mutating func boxOutline(base c: SIMD3<Float>, w: Float, d: Float, h: Float, yaw: Float, width lw: Float) {
        let ax = SIMD3<Float>(cos(yaw), 0, -sin(yaw)), az = SIMD3<Float>(sin(yaw), 0, cos(yaw))
        let hw = w / 2, hd = d / 2
        let p = [c - ax * hw - az * hd, c + ax * hw - az * hd, c + ax * hw + az * hd, c - ax * hw + az * hd]
        let up = SIMD3<Float>(0, h, 0)
        for i in 0..<4 {
            let a = p[i], b = p[(i + 1) % 4]
            stroke(a, b, width: lw)
            stroke(a + up, b + up, width: lw)
            stroke(a, a + up, width: lw)
        }
    }

    /// 선 그림: 텐트 모서리
    mutating func tentOutline(base c: SIMD3<Float>, w: Float, l: Float, h: Float, yaw: Float) {
        let ax = SIMD3<Float>(cos(yaw), 0, -sin(yaw)), az = SIMD3<Float>(sin(yaw), 0, cos(yaw))
        let fl = c - ax * (w / 2) - az * (l / 2), fr = c + ax * (w / 2) - az * (l / 2)
        let bl = c - ax * (w / 2) + az * (l / 2), br = c + ax * (w / 2) + az * (l / 2)
        let ft = c - az * (l / 2) + SIMD3<Float>(0, h, 0), bt = c + az * (l / 2) + SIMD3<Float>(0, h, 0)
        for (a, b) in [(fl, fr), (bl, br), (fl, bl), (fr, br), (fl, ft), (fr, ft), (bl, bt), (br, bt), (ft, bt)] {
            stroke(a, b, width: 0.03)
        }
    }

    // MARK: 캠핑 텐트 (여러 모양). 모두 바닥 가운데 c, 앞(문) = 회전 yaw 의 +z. fabric: 천, dark: 문·창(짙은 천), poles: 폴대·줄, lines: 선 그림 윤곽
    struct TentParts { var fabric = Geo(); var dark = Geo(); var poles = Geo(); var lines = Geo() }

    private static func rot(_ yaw: Float) -> simd_quatf { simd_quatf(angle: yaw, axis: [0, 1, 0]) }

    /// 돔 텐트: 둥근 지붕 + 대각선으로 엇갈린 두 폴대 + 앞문 + 둘레 고정 줄
    static func domeTent(_ t: inout TentParts, at c: SIMD3<Float>, w: Float, l: Float, h: Float, yaw: Float) {
        let q = rot(yaw)
        func P(_ u: Float, _ v: Float, _ k: Float = 1) -> SIMD3<Float> {
            c + q.act(SIMD3<Float>(cos(v) * cos(u) * w / 2 * k, sin(v) * h * k, cos(v) * sin(u) * l / 2 * k))
        }
        let nu = 20, nv = 7
        for i in 0..<nu {
            for j in 0..<nv {
                let u0 = Float(i) / Float(nu) * 2 * .pi, u1 = Float(i + 1) / Float(nu) * 2 * .pi
                let v0 = Float(j) / Float(nv) * .pi / 2, v1 = Float(j + 1) / Float(nv) * .pi / 2
                // 폴대 사이 천이 살짝 처지게 (가운데를 조금 안쪽으로)
                let sag: Float = 1 - 0.035 * abs(sin(2 * (u0 + u1) / 2))
                t.fabric.quad(P(u0, v0, sag), P(u1, v0, sag), P(u1, v1, sag), P(u0, v1, sag), SIMD2<Float>(u0, v0) / 1.2, SIMD2<Float>(u1, v0) / 1.2,
                              SIMD2<Float>(u1, v1) / 1.2, SIMD2<Float>(u0, v1) / 1.2)
            }
        }
        // 문 (앞쪽 아래 둥근 판, 천보다 조금 바깥)
        for i in 0..<6 {
            let u0 = Float.pi / 2 - 0.42 + Float(i) / 6 * 0.84, u1 = Float.pi / 2 - 0.42 + Float(i + 1) / 6 * 0.84
            for j in 0..<4 {
                let v0 = Float(j) / 4 * 0.95, v1 = Float(j + 1) / 4 * 0.95
                let sh0: Float = 1 - pow(Float(j) / 4, 3) * 0.6, sh1: Float = 1 - pow(Float(j + 1) / 4, 3) * 0.6      // 위로 갈수록 좁아지는 둥근 문
                let um = Float.pi / 2
                t.dark.quad(P(um + (u0 - um) * sh0, v0, 1.012), P(um + (u1 - um) * sh0, v0, 1.012), P(um + (u1 - um) * sh1, v1, 1.012), P(um + (u0 - um) * sh1, v1, 1.012),
                            .zero, .zero, .zero, .zero)
            }
        }
        // 폴대 두 개 (대각선으로 꼭대기에서 엇갈림)
        for u in [Float.pi / 4, 3 * .pi / 4] {
            var prev: SIMD3<Float>? = nil
            for k in 0...16 {
                let s2 = Float(k) / 16
                let p = s2 < 0.5 ? P(u, s2 * .pi, 1.01) : P(u + .pi, (1 - s2) * .pi, 1.01)
                if let pr = prev { t.poles.stroke(pr, p, width: 0.022); t.lines.stroke(pr, p, width: 0.025) }
                prev = p
            }
        }
        // 고정 줄: 몸통 중간에서 바깥 말뚝으로
        for k in 0..<4 {
            let u = Float(k) / 4 * 2 * .pi + .pi / 4
            let a = P(u, 0.75, 1.0), b2 = c + q.act(SIMD3<Float>(cos(u) * w * 0.95, 0.02, sin(u) * l * 0.95))
            t.poles.stroke(a, b2, width: 0.008)
        }
        for i in 0..<nu { t.lines.stroke(P(Float(i) / Float(nu) * 2 * .pi, 0), P(Float(i + 1) / Float(nu) * 2 * .pi, 0), width: 0.025) }
    }

    /// 터널 텐트: 반원 단면을 길게 늘인 몸통 + 폴대 고리 셋 + 앞 끝 문 + 앞뒤 고정 줄
    static func tunnelTent(_ t: inout TentParts, at c: SIMD3<Float>, w: Float, l: Float, h: Float, yaw: Float) {
        let q = rot(yaw)
        func P(_ a: Float, _ z: Float, _ k: Float = 1) -> SIMD3<Float> {
            let hoop: Float = 1 - 0.05 * abs(sin((z / l + 0.5) * 2 * .pi))         // 고리 사이가 살짝 처짐
            return c + q.act(SIMD3<Float>(cos(a) * w / 2 * k * hoop, sin(a) * h * k * hoop, z))
        }
        let na = 12, nz = 12
        for i in 0..<na {
            let a0 = Float(i) / Float(na) * .pi, a1 = Float(i + 1) / Float(na) * .pi
            for j in 0..<nz {
                let z0 = -l / 2 + l * Float(j) / Float(nz), z1 = -l / 2 + l * Float(j + 1) / Float(nz)
                t.fabric.quad(P(a0, z0), P(a1, z0), P(a1, z1), P(a0, z1), SIMD2<Float>(a0, z0), SIMD2<Float>(a1, z0), SIMD2<Float>(a1, z1), SIMD2<Float>(a0, z1))
            }
            // 뒤 끝은 천, 앞 끝은 짙은 문
            t.fabric.quad(c + q.act(SIMD3<Float>(0, 0, -l / 2)), P(a0, -l / 2), P(a1, -l / 2), c + q.act(SIMD3<Float>(0, 0, -l / 2)), .zero, .zero, .zero, .zero)
            t.dark.quad(c + q.act(SIMD3<Float>(0, 0, l / 2 + 0.01)), P(a0, l / 2 + 0.01, 0.97), P(a1, l / 2 + 0.01, 0.97), c + q.act(SIMD3<Float>(0, 0, l / 2 + 0.01)),
                        .zero, .zero, .zero, .zero)
        }
        for z in [-l / 2 + 0.15, 0, l / 2 - 0.15] {
            for i in 0..<na {
                let a = P(Float(i) / Float(na) * .pi, z, 1.01), b2 = P(Float(i + 1) / Float(na) * .pi, z, 1.01)
                t.poles.stroke(a, b2, width: 0.022); t.lines.stroke(a, b2, width: 0.025)
            }
        }
        for zs: Float in [-1, 1] {
            let top = c + q.act(SIMD3<Float>(0, h * 0.9, zs * l / 2))
            t.poles.stroke(top, c + q.act(SIMD3<Float>(0, 0.02, zs * (l / 2 + 1.2))), width: 0.008)
            for i in 0..<na { t.lines.stroke(P(Float(i) / Float(na) * .pi, zs * l / 2), P(Float(i + 1) / Float(na) * .pi, zs * l / 2), width: 0.025) }
        }
    }

    /// 벨 텐트(캔버스 글램핑): 낮은 원통 벽 + 원뿔 지붕 + 가운데 기둥 끝 + 열린 문 + 둘레로 뻗은 고정 줄
    static func bellTent(_ t: inout TentParts, at c: SIMD3<Float>, r: Float, h: Float, yaw: Float) {
        let q = rot(yaw)
        let wallH = h * 0.24, n = 24
        func ring(_ k: Int, _ rr: Float, _ y: Float) -> SIMD3<Float> {
            let a = Float(k) / Float(n) * 2 * .pi
            return c + q.act(SIMD3<Float>(cos(a) * rr, y, sin(a) * rr))
        }
        let apex = c + SIMD3<Float>(0, h, 0)
        for k in 0..<n {
            let a = Float(k) / Float(n)
            let door = abs(a - 0.25) < 0.05                                        // 앞(+z)쪽 문
            let w0 = ring(k, r, 0), w1 = ring(k + 1, r, 0), u0 = ring(k, r, wallH), u1 = ring(k + 1, r, wallH)
            if door { t.dark.quad(w0, w1, u1, u0, .zero, .zero, .zero, .zero) } else { t.fabric.quad(w0, w1, u1, u0, .zero, .zero, .zero, .zero) }
            // 처마 (벽보다 조금 밖으로) → 꼭대기
            let e0 = ring(k, r * 1.04, wallH + 0.02), e1 = ring(k + 1, r * 1.04, wallH + 0.02)
            t.fabric.quad(e0, e1, apex, apex, .zero, .zero, .zero, .zero)
            t.lines.stroke(e0, e1, width: 0.025)
            t.lines.stroke(w0, w1, width: 0.025)
            if k % 3 == 0 {
                t.lines.stroke(e0, apex, width: 0.02)
                t.poles.stroke(e0, ring(k, r * 1.9, 0.02), width: 0.008)            // 고정 줄
            }
        }
        t.poles.stroke(apex, apex + SIMD3<Float>(0, 0.18, 0), width: 0.04)           // 가운데 기둥 끝
        // 걷어 올린 문 자락 (문 위 짙은 띠)
        t.dark.quad(ring(Int(Float(n) * 0.2), r * 1.01, wallH * 0.98), ring(Int(Float(n) * 0.3), r * 1.01, wallH * 0.98),
                    ring(Int(Float(n) * 0.3), r * 1.01, wallH * 0.8), ring(Int(Float(n) * 0.2), r * 1.01, wallH * 0.8), .zero, .zero, .zero, .zero)
    }

    /// A형(삼각) 텐트: 기존 삼각 기둥 + 앞 문(짙은 세모) + 앞뒤 기둥과 고정 줄
    static func ridgeTent(_ t: inout TentParts, at c: SIMD3<Float>, w: Float, l: Float, h: Float, yaw: Float) {
        t.fabric.tent(base: c, w: w, l: l, h: h, yaw: yaw)
        let ax = SIMD3<Float>(cos(yaw), 0, -sin(yaw)), az = SIMD3<Float>(sin(yaw), 0, cos(yaw))
        let fl = c - ax * (w * 0.32) - az * (l / 2 + 0.01), fr = c + ax * (w * 0.32) - az * (l / 2 + 0.01)
        let ft = c - az * (l / 2 + 0.01) + SIMD3<Float>(0, h * 0.82, 0)
        t.dark.quad(fl, fr, ft, ft, .zero, .zero, .zero, .zero)
        for zs: Float in [-1, 1] {
            let top = c + az * (zs * l / 2) + SIMD3<Float>(0, h, 0)
            t.poles.stroke(c + az * (zs * l / 2), top + SIMD3<Float>(0, 0.12, 0), width: 0.03)
            t.poles.stroke(top, c + az * (zs * (l / 2 + 1.3)), width: 0.008)
        }
        t.lines.tentOutline(base: c, w: w, l: l, h: h, yaw: yaw)
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

    /// 선 그림: 이 그물에 만든 바위들의 검은 외곽선 (바위마다 width(가운데) 만큼 부풀린 껍데기의 뒷면)
    @MainActor
    func inkHull(_ name: String, width: (SIMD3<Float>) -> Float) -> ModelEntity? {
        guard !rocksMade.isEmpty else { return nil }
        var h = Geo()
        for (st, c) in rocksMade { h.rockHull(of: self, start: st, center: c, width: width(c)) }
        return h.entity(name, Ink.hullMat)
    }

    @MainActor
    func entity(_ name: String, _ m: RealityKit.Material) -> ModelEntity? {
        guard let mesh = mesh(name) else { return nil }
        return ModelEntity(mesh: mesh, materials: [m])
    }
}
