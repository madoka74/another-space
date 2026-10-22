import SwiftUI
import RealityKit
import simd

/// 별자리 하나 (skydata.json — tools/sky_data.py 가 d3-celestial 자료로 만듦: 88개 별자리 선·별 위치·등급·한국어 이름 + 해설)
struct Constellation {
    struct Star { let ra: Double; let dec: Double; let mag: Float; let name: String }
    let id: String
    let name: String
    let latin: String
    let season: String
    let text: String
    let story: [String]
    let find: [String]
    let lines: [[Star]]

    /// 이름 있는 밝은 별 (밝은 순, 최대 6개)
    var starNote: String {
        var seen = Set<String>()
        var list: [Star] = []
        for l in lines { for s in l where !s.name.isEmpty && !seen.contains(s.name) { seen.insert(s.name); list.append(s) } }
        return list.sorted { $0.mag < $1.mag }.prefix(6).map(\.name).joined(separator: " · ")
    }
}

/// 하늘 자료 읽기 (한 번)
enum SkyData {
    struct BG { let ra: Double; let dec: Double; let mag: Float; let bv: Float }
    static let shared: (cons: [Constellation], bg: [BG]) = {
        guard let u = Bundle.main.url(forResource: "skydata", withExtension: "json"),
              let d = try? Data(contentsOf: u),
              let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return ([], []) }
        var cons: [Constellation] = []
        for c in (j["constellations"] as? [[String: Any]]) ?? [] {
            var lines: [[Constellation.Star]] = []
            for pl in (c["lines"] as? [[[Any]]]) ?? [] {
                var pts: [Constellation.Star] = []
                for p in pl where p.count >= 4 {
                    let ra = (p[0] as? NSNumber)?.doubleValue ?? 0
                    let dec = (p[1] as? NSNumber)?.doubleValue ?? 0
                    let mag = (p[2] as? NSNumber)?.floatValue ?? 4
                    pts.append(Constellation.Star(ra: ra, dec: dec, mag: mag, name: (p[3] as? String) ?? ""))
                }
                if pts.count >= 2 { lines.append(pts) }
            }
            cons.append(Constellation(id: (c["id"] as? String) ?? "", name: (c["ko"] as? String) ?? "", latin: (c["la"] as? String) ?? "",
                                      season: (c["season"] as? String) ?? "", text: (c["text"] as? String) ?? "",
                                      story: (c["story"] as? [String]) ?? [], find: (c["find"] as? [String]) ?? [], lines: lines))
        }
        var bg: [BG] = []
        for s in (j["stars"] as? [[Any]]) ?? [] where s.count >= 4 {
            bg.append(BG(ra: (s[0] as? NSNumber)?.doubleValue ?? 0, dec: (s[1] as? NSNumber)?.doubleValue ?? 0,
                         mag: (s[2] as? NSNumber)?.floatValue ?? 4, bv: (s[3] as? NSNumber)?.floatValue ?? 0.5))
        }
        return (cons, bg)
    }()
}

/// 숲 테마의 밤하늘: 오늘 밤(테마 시간에 맞춘 시각) 서울에서 보이는 실제 하늘.
/// - 별은 아주 많이: 실제 밝은 별들 + 고르지 않은 별자리의 별 + 희미한 별 무리(눈으로 겨우 보이는 별처럼)
/// - 별자리는 한 번에 3~4개, 하늘 여기저기 떨어진 것으로 (머리 위는 피해 지평선 위 24~50도, 숲은 밤에 나무를 멀리 물려 19도 아래)
/// - 바라보면 그 별자리 별들이 크고 밝게 반짝임(선 없음). 탭하면 선이 이어지고 정보판이 그 별자리 높이 옆에 뜸
/// - 별은 '오려 내기'(가장자리 투명 부분은 아예 그리지 않음)로 그려 별끼리·선과 겹쳐도 네모 판이 비치지 않음.
///   밝기 바꾸기·반짝임도 투명도 대신 재질을 바꿔 끼움 (반투명이 되면 다시 네모가 비침)
/// 밤에 가장 또렷하고, 새벽·해질녘엔 밝은 별만 흐리게, 낮엔 안 보임. 구름이 끼면 흐려졌다 또렷해졌다, 비·눈이면 가려짐.
/// 북쪽은 방의 한 방향으로 정해 둠(실제 나침반 방향과는 다를 수 있음), 별의 배치·높이는 실제와 같음
@MainActor
final class SkyStars {
    private final class Group {
        let c: Constellation
        let dir: SIMD3<Float>
        let radius: Float
        let verts: [SIMD3<Float>]
        let segs: [(SIMD3<Float>, SIMD3<Float>)]
        var stars: ModelEntity?
        var lines: ModelEntity?
        var label: Entity?
        var focus: Float = 0
        var level = -1
        var reveal: Float = 0
        var picked = false
        var lineLevel = 0
        init(c: Constellation, dir: SIMD3<Float>, radius: Float, verts: [SIMD3<Float>], segs: [(SIMD3<Float>, SIMD3<Float>)]) {
            self.c = c; self.dir = dir; self.radius = radius; self.verts = verts; self.segs = segs
        }
    }

    let root = Entity()
    private var groups: [Group] = []
    private var bgEnts: [(ModelEntity, [UnlitMaterial])] = []      // 별 무리, 반짝임 단계별 재질
    private var conMats: [UnlitMaterial] = []                       // 별자리 별: 0 = 평소 … 마지막 = 바라볼 때
    private var lineMats: [UnlitMaterial] = []                      // 별자리 선: 0 = 평소(흐리게), 1 = 바라볼 때, 2 = 탭해서 고른 것
    private let vis: Float
    private let dimOnly: Bool
    private let cloudy: Bool
    private let windy: Bool
    private let look: LookMode
    private var t: Float = 0
    private var focusT: Float = 0
    private var twT: Float = 0
    private var focused: Group?
    private let R: Float = 200
    private var mask: TextureResource?
    private let lat: Double = 37.5            // 서울
    private let lon: Double = 127.0

    var visible: Bool { vis > 0.05 }

    /// constellations: 별자리를 띄울지 (숲만). 다른 장소의 밤하늘은 별·달만
    init(room: RoomRec, center: SIMD3<Float>, look: LookMode, constellations: Bool) {
        self.look = look
        let tm = room.time, w = room.weather
        var v: Float = 0
        if tm == "night" { v = 1 } else if tm == "dusk" || tm == "dawn" { v = 0.55 }
        switch w {
        case "clear", "wind": break
        case "cloudy": v *= 0.8
        default: v = 0
        }
        vis = v
        dimOnly = tm != "night"
        cloudy = w == "cloudy"
        windy = w == "wind"
        root.position = center + SIMD3<Float>(0, 1.6, 0)
        guard v > 0 else { root.isEnabled = false; return }
        mask = Tex.get("glow_a", raw: true)
        let hour: Double = tm == "night" ? 21.5 : (tm == "dusk" ? 19.5 : 4.5)
        let lst = Self.localSidereal(hour: hour, lon: lon)
        // 밝기 단계 (반짝임·구름·포커스 모두 재질을 바꿔 끼움)
        // 별자리 별 재질 단계: 0~3 = 평소 반짝임(밝기·크기가 오르내림), 4~7 = 바라볼 때(훨씬 밝고 크게, 따뜻한 빛)
        for k in 0..<4 {
            let f = Float(k) / 3
            conMats.append(starMat(SIMD3<Float>(0.86, 0.9, 1), vis * (0.82 + 0.18 * f), cut: 0.34 - 0.12 * f))
        }
        for k in 0..<4 {
            let f = Float(k) / 3
            conMats.append(starMat(SIMD3<Float>(1, 0.95, 0.82), vis, cut: 0.16 - 0.08 * f))
        }
        let lineK: [Float] = [0.3, 0.62, 1]
        for k in lineK {
            let c: UIColor
            switch look {
            case .line: c = UIColor(white: CGFloat(0.6 - 0.48 * k), alpha: 1)
            case .mono: c = UIColor(white: CGFloat(0.85 * k * vis), alpha: 1)
            case .color: c = UIColor(red: CGFloat(0.62 * k * vis), green: CGFloat(0.76 * k * vis), blue: CGFloat(1 * k * vis), alpha: 1)
            }
            lineMats.append(UnlitMaterial(color: c))
        }
        let chosen = constellations ? choose(lst) : []
        buildBackground(lst, skip: Set(chosen.map(\.id)))
        for c in chosen { build(c, lst) }
        if tm == "night" && w != "storm" { addMoon(room) }
    }

    /// 오늘 그 시각(이 기기의 시간대)의 지방 항성시 (도)
    static func localSidereal(hour: Double, lon: Double) -> Double {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current
        var comp = cal.dateComponents([.year, .month, .day], from: Date())
        comp.hour = Int(hour)
        comp.minute = Int((hour - floor(hour)) * 60)
        let date = cal.date(from: comp) ?? Date()
        let jd = date.timeIntervalSince1970 / 86400 + 2440587.5
        let d = jd - 2451545.0
        let gmst = 280.46061837 + 360.98564736629 * d
        return (gmst + lon).truncatingRemainder(dividingBy: 360)
    }

    /// 적경·적위(도) → 방 안에서 본 방향 (북쪽 = -z, 동쪽 = +x, 위 = +y)
    private func dir(_ ra: Double, _ dec: Double, _ lst: Double) -> SIMD3<Float> {
        let h = (lst - ra) * .pi / 180
        let d = dec * .pi / 180, p = lat * .pi / 180
        let alt = asin(sin(p) * sin(d) + cos(p) * cos(d) * cos(h))
        let az = atan2(-sin(h) * cos(d), cos(p) * sin(d) - sin(p) * cos(d) * cos(h))
        return SIMD3<Float>(Float(cos(alt) * sin(az)), Float(sin(alt)), Float(-cos(alt) * cos(az)))
    }

    /// 보여 줄 별자리 3~4개: 가운데가 지평선 위 20도 넘고, 별이 4개 넘게 보이고, 너무 크지 않은 것 중 무작위로,
    /// 서로 50도 넘게 떨어진 것만 (모자라면 35도까지 좁혀 다시)
    private func choose(_ lst: Double) -> [Constellation] {
        var cands: [(Constellation, SIMD3<Float>)] = []
        for c in SkyData.shared.cons {
            var sum = SIMD3<Float>(0, 0, 0), up = 0, n = 0
            for l in c.lines { for s in l { let v = dir(s.ra, s.dec, lst); sum += v; n += 1; if v.y > 0.1 { up += 1 } } }
            guard n > 0 else { continue }
            let ctr = simd_normalize(sum)
            var rad: Float = 0
            for l in c.lines { for s in l { rad = max(rad, acos(min(1, simd_dot(dir(s.ra, s.dec, lst), ctr)))) } }
            // 고개를 많이 젖히지 않고 볼 수 있게 (머리 위는 피함): 가운데가 지평선 위 24~50도, 모든 별이 숲 나무 꼭대기(19도)보다 위인 20도 넘게
            var low: Float = 1
            for l in c.lines { for s in l { low = min(low, dir(s.ra, s.dec, lst).y) } }
            if ctr.y > 0.41 && ctr.y < 0.77 && low > 0.34 && n >= 4 && rad < 0.42 && rad > 0.06 { cands.append((c, ctr)) }
        }
        // 덜 알려진 아주 작은 것보다 모양이 또렷한 것(별이 많은 것)을 먼저, 그 안에서 무작위
        cands.shuffle()
        cands.sort { a, b in
            let na = a.0.lines.reduce(0) { $0 + $1.count }, nb = b.0.lines.reduce(0) { $0 + $1.count }
            return min(na, 8) > min(nb, 8)
        }
        var best: [(Constellation, SIMD3<Float>)] = []
        for minSep in [Float(0.75), 0.58, 0.45] {
            var out: [(Constellation, SIMD3<Float>)] = []
            for c in cands where out.count < 4 {
                if out.allSatisfy({ acos(min(1, simd_dot($0.1, c.1))) > minSep }) { out.append(c) }
            }
            if out.count > best.count { best = out }
            if best.count >= 3 { break }
        }
        return best.map { $0.0 }
    }

    private func starQuad(_ g: inout Geo, _ v: SIMD3<Float>, size: Float, r: Float? = nil) {
        let p = v * (r ?? R)
        let up0 = abs(v.y) > 0.95 ? SIMD3<Float>(0, 0, 1) : SIMD3<Float>(0, 1, 0)
        let right = simd_normalize(simd_cross(v, up0))
        let up = simd_cross(right, v)
        let hr = right * (size / 2), hu = up * (size / 2)
        g.quad(p - hr - hu, p + hr - hu, p + hr + hu, p - hr + hu, SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(1, 1), SIMD2<Float>(0, 1))
    }

    /// 별 재질: 오려 내기(cut 보다 투명한 곳은 그리지 않음). cut 이 낮을수록 별이 크고 밝게 보임
    private func starMat(_ c: SIMD3<Float>, _ k: Float, cut: Float) -> UnlitMaterial {
        let col: UIColor
        switch look {
        case .line: col = UIColor(white: CGFloat(0.35 - 0.3 * min(1, k)), alpha: 1)
        case .mono: col = UIColor(white: CGFloat(min(1, (c.x + c.y + c.z) / 3 * k)), alpha: 1)
        case .color: col = UIColor(red: CGFloat(min(1, c.x * k)), green: CGFloat(min(1, c.y * k)), blue: CGFloat(min(1, c.z * k)), alpha: 1)
        }
        var m = UnlitMaterial(color: col)
        if let mask {
            var mp = MaterialParameters.Texture(mask); mp.sampler = Tex.clamp
            m.blending = .transparent(opacity: .init(scale: 1, texture: mp))
            m.opacityThreshold = cut
        }
        return m
    }

    private func size(_ mag: Float) -> Float {
        let deg = max(0.16, 0.78 - 0.13 * mag)
        return R * deg * .pi / 180 * 2.0
    }

    private func buildBackground(_ lst: Double, skip: Set<String>) {
        // 밝기 무리 셋 (무리마다 다르게 반짝임): 실제 밝은 별 + 고르지 않은 별자리의 별
        var gs = [Geo(), Geo(), Geo()]
        var n = 0
        func add(_ v: SIMD3<Float>, _ mag: Float) {
            guard v.y > 0.02 else { return }
            if dimOnly && mag > 2.6 { return }
            starQuad(&gs[n % 3], v, size: size(mag) * 0.85)
            n += 1
        }
        for s in SkyData.shared.bg { add(dir(s.ra, s.dec, lst), s.mag) }
        var keys = Set<String>()
        for c in SkyData.shared.cons where !skip.contains(c.id) {
            for l in c.lines { for s in l where !keys.contains("\(s.ra),\(s.dec)") { keys.insert("\(s.ra),\(s.dec)"); add(dir(s.ra, s.dec, lst), s.mag) } }
        }
        // 희미한 별 무리: 은하수 쪽(하늘을 가로지르는 띠)에 더 많이
        if !dimOnly {
            var rg = SeededRNG(seed: 1987)
            let band = simd_normalize(SIMD3<Float>(0.35, 0.25, 0.9))          // 띠의 축 (띠 = 이 축과 직각인 큰 원)
            var made = 0, tries = 0
            while made < 1500 && tries < 9000 {
                tries += 1
                let z = Float.random(in: 0.03...1, using: &rg), a = Float.random(in: 0...(2 * .pi), using: &rg)
                let rr = sqrt(max(0, 1 - z * z))
                let v = SIMD3<Float>(rr * cos(a), z, rr * sin(a))
                let near = 1 - abs(simd_dot(v, band))
                if Float.random(in: 0...1, using: &rg) > 0.35 + 0.65 * pow(near, 6) { continue }
                starQuad(&gs[made % 3], v, size: size(Float.random(in: 5.2...6.4, using: &rg)) * 0.75)
                made += 1
            }
        }
        for (i, g) in gs.enumerated() {
            var mats: [UnlitMaterial] = []
            for k in 0..<4 {
                let f = Float(k) / 3
                mats.append(starMat([0.88, 0.9, 1], vis * (0.62 + 0.3 * f), cut: 0.42 - 0.08 * f))
            }
            if let e = g.entity("bgStars\(i)", mats[2]) {
                root.addChild(e)
                bgEnts.append((e, mats))
            }
        }
    }

    private func build(_ c: Constellation, _ lst: Double) {
        var verts: [SIMD3<Float>] = []
        var segs: [(SIMD3<Float>, SIMD3<Float>)] = []
        var stars = Geo(), lines = Geo()
        var keys = Set<String>()
        var sum = SIMD3<Float>(0, 0, 0)
        for l in c.lines {
            var prev: SIMD3<Float>? = nil
            for s in l {
                let v = dir(s.ra, s.dec, lst)
                if let pv = prev { segs.append((pv, v)) }
                prev = v
                let k = "\(s.ra),\(s.dec)"
                if keys.contains(k) { continue }
                keys.insert(k)
                verts.append(v)
                sum += v
                if dimOnly && s.mag > 2.6 { continue }
                if v.y > 0.02 { starQuad(&stars, v, size: size(min(s.mag, 3.6)) * 1.75) }      // 별자리 별은 또렷하게 크게
            }
        }
        guard !verts.isEmpty else { return }
        let center = simd_normalize(sum)
        var radius: Float = 0
        for v in verts { radius = max(radius, acos(min(1, simd_dot(v, center)))) }
        let g = Group(c: c, dir: center, radius: radius, verts: verts, segs: segs)
        if let e = stars.entity("con", conMats[0]) { root.addChild(e); g.stars = e; g.level = 0 }
        // 선: 별 앞에서 별을 비켜 (별 둘레에 틈), 불투명
        for (a, b) in segs where a.y > 0 || b.y > 0 {
            let pa = a * R * 0.99, pb = b * R * 0.99
            let d = simd_normalize(pb - pa)
            let gap: Float = R * 0.008
            guard simd_distance(pa, pb) > gap * 2.2 else { continue }
            lines.stroke(pa + d * gap, pb - d * gap, width: R * 0.0024)
        }
        // 선은 탭해서 고른 뒤에만 이어짐 (그 전엔 별의 크기·밝기 반짝임으로만 알려 줌)
        if let e = lines.entity("conLines", lineMats[2]) {
            e.isEnabled = false
            root.addChild(e)
            g.lines = e
        }
        groups.append(g)
    }

    /// 그 방향의 별자리 (별·선·별자리 안쪽에서 tol 안, 가장 가까운 것)
    private func near(_ dirIn: SIMD3<Float>, tol: Float) -> Group? {
        let d = simd_normalize(dirIn)
        var best: (Group, Float)? = nil
        for g in groups {
            let a = acos(min(1, max(-1, simd_dot(d, g.dir))))
            guard a < g.radius + tol else { continue }
            var m: Float = a < g.radius * 0.6 ? 0 : 10                 // 별자리 한가운데를 봐도 그 별자리
            for v in g.verts { m = min(m, acos(min(1, max(-1, simd_dot(d, v))))) }
            for (p, q) in g.segs {
                let pq = q - p
                let l2 = simd_length_squared(pq)
                guard l2 > 1e-8 else { continue }
                let k = min(1, max(0, simd_dot(d - p, pq) / l2))
                let x = simd_normalize(p + pq * k)
                m = min(m, acos(min(1, max(-1, simd_dot(d, x)))))
            }
            if m < tol, best == nil || m < best!.1 { best = (g, m) }
        }
        return best?.0
    }

    func tick(_ dt: Float, gaze: SIMD3<Float>) {
        guard visible else { return }
        t += dt
        focusT -= dt
        if focusT <= 0 {
            focusT = 0.12
            focused = near(gaze, tol: 0.12)
        }
        // 구름: 천천히 흐려졌다 또렷해짐 (0~1), 반짝임은 무리마다 재질 단계를 바꿈
        let cl: Float = cloudy ? 0.5 + 0.5 * max(0, sin(t * 0.07)) : 1
        twT -= dt
        if twT <= 0 {
            twT = windy ? 0.18 : 0.3
            for (i, b) in bgEnts.enumerated() {
                let tw = 0.5 + 0.5 * sin(t * (1.7 + Float(i) * 0.8) + Float(i) * 2)
                let k = max(0, min(3, Int((tw * cl * 3).rounded())))
                b.0.model?.materials = [b.1[k]]
            }
        }
        for g in groups {
            let want: Float = (g === focused || g.picked) ? 1 : 0
            g.focus += (want - g.focus) * min(1, dt * 7)
            let tw = 0.5 + 0.5 * sin(t * 2.6 + g.dir.x * 9 + g.dir.z * 5)          // 반짝반짝 (별자리마다 다른 박자)
            var lv = max(0, min(3, Int((tw * cl * 3).rounded())))
            if g.focus > 0.5 { lv = 4 + max(0, min(3, Int(((0.5 + 0.5 * sin(t * 5)) * 3).rounded()))) }
            if lv != g.level, let e = g.stars { e.model?.materials = [conMats[lv]]; g.level = lv }
            if g.picked { g.reveal = min(1, g.reveal + dt / 0.8) } else if g.reveal > 0 { g.reveal = max(0, g.reveal - dt * 1.5) }
            if let l = g.lines, l.isEnabled != g.picked { l.isEnabled = g.picked }
            if let lb = g.label {
                lb.components.set(OpacityComponent(opacity: g.reveal * cl))
                if !g.picked && g.reveal <= 0 { lb.removeFromParent(); g.label = nil }
            }
        }
    }

    /// 탭: 그 방향의 별자리를 고름 (없으면 nil) — 선을 긋고 별자리 바로 아래(내 눈 기준 아래)에 이름. viewUp: 내 머리의 위쪽 방향
    /// 반환: 별자리, 가운데 방향, 가장 낮은 별의 고도(라디안) — 정보판을 별자리 바로 아래에 두려고
    func pick(_ d: SIMD3<Float>, viewUp: SIMD3<Float>) -> (Constellation, SIMD3<Float>, Float)? {
        guard visible, let g = near(d, tol: 0.16) else { return nil }
        for o in groups { o.picked = o === g }
        g.reveal = 0
        Sfx.play("star_chime", in: root, at: g.dir * 4, gain: -4)
        let low = g.verts.map(\.y).min() ?? g.dir.y
        return (g.c, g.dir, asin(max(-1, min(1, low))))
    }

    func unpick() {
        for g in groups { g.picked = false }
    }

    /// 달: 고도 30도쯤(방마다 다른 방향), 보이는 지름 2.2도 + 둘레 은은한 달무리
    private func addMoon(_ room: RoomRec) {
        var rg = SeededRNG(seed: UInt64(room.id * 97 + 13))
        let az = Float.random(in: 0...(2 * .pi), using: &rg)
        let alt: Float = Float.random(in: 0.42...0.62, using: &rg)
        let v = simd_normalize(SIMD3<Float>(cos(alt) * cos(az), sin(alt), cos(alt) * sin(az)))
        let dist = R * 0.95
        // 달 모양 (방마다 하나): 0 초승달 · 1 상현 · 2 차는 달 · 3 보름 · 4 기우는 달 · 5 하현 · 6 그믐달
        let phase = Int.random(in: 0...6, using: &rg)
        let elong: [Float] = [0.75, .pi / 2, 2.3, .pi, 2.3, .pi / 2, 0.75]
        let lit = (1 - cos(elong[phase])) / 2                          // 밝은 부분 비율 (달무리 밝기)
        func quad(_ size: Float) -> Geo {
            var g = Geo()
            starQuad(&g, v, size: size, r: dist)
            return g
        }
        // 달무리 (하늘 세계 안쪽이라 반투명이어도 현실이 비치지 않음)
        var hm = UnlitMaterial(color: look == .line ? UIColor(white: 0.5, alpha: 1) : UIColor(red: 0.75, green: 0.82, blue: 1, alpha: 1))
        if let mask {
            var mp = MaterialParameters.Texture(mask); mp.sampler = Tex.clamp
            hm.blending = .transparent(opacity: .init(scale: (look == .line ? 0.15 : 0.32) * (0.25 + 0.75 * lit), texture: mp))
            hm.writesDepth = false                 // 반투명 판이 뒤의 나무·물건을 네모나게 지우지 않게
        }
        if let e = quad(dist * 0.13).entity("moonHalo", hm) { root.addChild(e) }
        var mm = UnlitMaterial(color: look == .line ? UIColor(white: 0.97, alpha: 1) : .white)
        let mode: LookMode = look == .color ? .color : .mono
        if look != .line, let tx = Tex.with(mode, { Tex.get("moon_ph\(phase)") ?? Tex.get("moon") }) {
            var tp = MaterialParameters.Texture(tx); tp.sampler = Tex.clamp
            mm.color = .init(tint: .white, texture: tp)
        }
        if let a = Tex.get("moon_ph\(phase)_a", raw: true) ?? Tex.get("moon_a", raw: true) {
            var tp = MaterialParameters.Texture(a); tp.sampler = Tex.clamp
            mm.blending = .transparent(opacity: .init(scale: 1, texture: tp))
            mm.opacityThreshold = 0.5
        }
        if let e = quad(dist * 0.0384).entity("moon", mm) { root.addChild(e) }
        if look == .line {
            var l = Geo()
            let rr = dist * 0.0192
            let up0 = SIMD3<Float>(0, 1, 0)
            let right = simd_normalize(simd_cross(v, up0)), up = simd_cross(right, v)
            for k in 0..<32 {
                let a0 = Float(k) / 32 * 2 * .pi, a1 = Float(k + 1) / 32 * 2 * .pi
                l.stroke(v * dist * 0.995 + (right * cos(a0) + up * sin(a0)) * rr, v * dist * 0.995 + (right * cos(a1) + up * sin(a1)) * rr, width: dist * 0.0012)
            }
            // 밝은 곳과 어두운 곳의 경계 (보름이 아니면): x = ±cos(e)·√(1-y²)
            if phase != 3 {
                let sgn: Float = phase < 3 ? 1 : -1
                for k in 0..<16 {
                    let y0 = -1 + Float(k) / 8, y1 = -1 + Float(k + 1) / 8
                    let x0 = sgn * cos(elong[phase]) * sqrt(max(0, 1 - y0 * y0)), x1 = sgn * cos(elong[phase]) * sqrt(max(0, 1 - y1 * y1))
                    l.stroke(v * dist * 0.995 + (right * x0 + up * y0) * rr, v * dist * 0.995 + (right * x1 + up * y1) * rr, width: dist * 0.0009)
                }
            }
            if let e = l.entity("moonLine", Ink.line) { root.addChild(e) }
        }
    }

    private func makeLabel(_ g: Group, viewUp: SIMD3<Float>) -> Entity {
        // 내 눈의 위쪽을 그 별자리 자리의 하늘 면에 눕힌 방향 = 글자 위쪽. 이름은 별자리의 가장 아래 별보다 조금 아래
        var upT = viewUp - g.dir * simd_dot(viewUp, g.dir)
        if simd_length(upT) < 0.05 { upT = SIMD3<Float>(0, 1, 0) - g.dir * g.dir.y }
        upT = simd_length(upT) > 0.01 ? simd_normalize(upT) : SIMD3<Float>(0, 0, -1)
        var low: Float = 0
        for v in g.verts { low = max(low, -simd_dot(v - g.dir, upT)) }        // 별자리 가운데에서 가장 아래 별까지 (내 눈 기준)
        let at = simd_normalize(g.dir - upT * (low + 0.075))
        let col: UIColor = look == .line ? UIColor(white: 0.12, alpha: 1) : UIColor(red: 0.86, green: 0.91, blue: 1, alpha: 1)
        let dist: Float = R * 0.97
        let text = MeshResource.generateText(g.c.name, extrusionDepth: 0.02, font: .systemFont(ofSize: CGFloat(dist * 0.045), weight: .semibold), alignment: .center)
        let te = ModelEntity(mesh: text, materials: [UnlitMaterial(color: col)])
        let bb = te.visualBounds(relativeTo: nil)
        te.position = SIMD3<Float>(-(bb.min.x + bb.max.x) / 2, -(bb.min.y + bb.max.y) / 2, 0)
        let holder = Entity()
        holder.look(at: .zero, from: at * dist, upVector: upT, relativeTo: root)
        let flipE = Entity()
        flipE.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])          // 글자 앞면이 나를 보게
        flipE.addChild(te)
        holder.addChild(flipE)
        holder.components.set(OpacityComponent(opacity: 0))
        root.addChild(holder)
        return holder
    }
}

/// 별자리 정보판 (도슨트처럼)
struct StarCard: View {
    let s: ExploreSession

    var body: some View {
        Group {
            if let c = s.starPick {
                content(c)
            } else {
                Color.clear.frame(width: 1, height: 1)
            }
        }
    }

    @ViewBuilder
    private func content(_ c: Constellation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("별자리").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(c.name).font(.title2.weight(.bold))
                    Text(c.latin).font(.headline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button {
                    s.closeStars()
                } label: {
                    Image(systemName: "xmark").font(.title3).frame(width: 36, height: 36)
                }
                .buttonBorderShape(.circle)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Label(c.season, systemImage: "calendar").font(.subheadline)
                    if !c.starNote.isEmpty { Label(c.starNote, systemImage: "sparkles").font(.subheadline) }
                    Text("이야기").font(.title3.weight(.semibold)).padding(.top, 6)
                    if c.story.isEmpty {
                        para(c.text)
                    } else {
                        ForEach(Array(c.story.enumerated()), id: \.offset) { _, t in para(t) }
                    }
                    if !c.find.isEmpty {
                        Text("찾아보기").font(.title3.weight(.semibold)).padding(.top, 6)
                        ForEach(Array(c.find.enumerated()), id: \.offset) { _, t in
                            HStack(alignment: .firstTextBaseline, spacing: 8) { Text("•"); para(t) }
                        }
                    }
                    Text("오늘 이 시각 서울 하늘의 별 배치예요. 북쪽은 방의 한 방향으로 정해 두어 실제 방위와 다를 수 있어요.")
                        .font(.caption).foregroundStyle(.secondary).padding(.top, 6)
                }
                .padding(.trailing, 6)
            }
        }
        .padding(24)
        .frame(width: 500, height: 560)
        .glassBackgroundEffect()
    }

    private func para(_ t: String) -> some View {
        Text(t).font(.body).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
    }
}
