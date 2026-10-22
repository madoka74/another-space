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

/// 숲 테마의 밤하늘: 오늘 밤(테마 시간에 맞춘 시각) 우리나라(서울)에서 보이는 실제 하늘 그대로 — 88개 별자리 중 지평선 위의 것들이 다 떠 있음.
/// 바라보면 그 별자리의 별빛만 밝아져 포커스를 알 수 있고, 그 상태에서 탭하면 별을 잇는 선이 그려지고 이름이 뜨며 정보판이 열림.
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
        var normal: Entity?
        var bright: Entity?
        var lines: Entity?
        var label: Entity?
        var focus: Float = 0
        var reveal: Float = 0
        var picked = false
        init(c: Constellation, dir: SIMD3<Float>, radius: Float, verts: [SIMD3<Float>], segs: [(SIMD3<Float>, SIMD3<Float>)]) {
            self.c = c; self.dir = dir; self.radius = radius; self.verts = verts; self.segs = segs
        }
    }

    let root = Entity()
    private var groups: [Group] = []
    private var bgEnts: [Entity] = []
    private let vis: Float
    private let dimOnly: Bool
    private let cloudy: Bool
    private let windy: Bool
    private let look: LookMode
    private var t: Float = 0
    private var focusT: Float = 0
    private var focused: Group?
    private let R: Float = 200
    private var mask: TextureResource?
    private let lat: Double = 37.5            // 서울
    private let lon: Double = 127.0

    var visible: Bool { vis > 0.05 }

    init(room: RoomRec, center: SIMD3<Float>, look: LookMode) {
        self.look = look
        let tm = room.time, w = room.weather
        var v: Float = 0
        if tm == "night" { v = 1 } else if tm == "dusk" || tm == "dawn" { v = 0.55 }
        switch w {
        case "clear", "wind": break
        case "cloudy": v *= 0.75
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
        buildBackground(lst)
        for c in SkyData.shared.cons { build(c, lst) }
        root.components.set(OpacityComponent(opacity: v))
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

    private func starQuad(_ g: inout Geo, _ v: SIMD3<Float>, size: Float) {
        let p = v * R
        let up0 = abs(v.y) > 0.95 ? SIMD3<Float>(0, 0, 1) : SIMD3<Float>(0, 1, 0)
        let right = simd_normalize(simd_cross(v, up0))
        let up = simd_cross(right, v)
        let hr = right * (size / 2), hu = up * (size / 2)
        g.quad(p - hr - hu, p + hr - hu, p + hr + hu, p - hr + hu, SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(1, 1), SIMD2<Float>(0, 1))
    }

    private func starMat(_ c: SIMD3<Float>, _ k: Float) -> UnlitMaterial {
        let col: UIColor
        switch look {
        case .line: col = UIColor(white: 0.1, alpha: 1)
        case .mono: col = UIColor(white: CGFloat(min(1, k)), alpha: 1)
        case .color: col = UIColor(red: CGFloat(min(1, c.x * k)), green: CGFloat(min(1, c.y * k)), blue: CGFloat(min(1, c.z * k)), alpha: 1)
        }
        var m = UnlitMaterial(color: col)
        if let mask {
            var mp = MaterialParameters.Texture(mask); mp.sampler = Tex.clamp
            m.blending = .transparent(opacity: .init(scale: 1, texture: mp))
        }
        return m
    }

    private func size(_ mag: Float) -> Float {
        let deg = max(0.2, 0.8 - 0.13 * mag)
        return R * deg * .pi / 180 * 2.0
    }

    private func buildBackground(_ lst: Double) {
        // 별자리 선에 들지 않는 별들: 밝기 무리 세 개로 (무리마다 조금씩 다르게 반짝임)
        var gs = [Geo(), Geo(), Geo()]
        for (i, s) in SkyData.shared.bg.enumerated() {
            if dimOnly && s.mag > 2.6 { continue }
            let v = dir(s.ra, s.dec, lst)
            guard v.y > 0.02 else { continue }
            starQuad(&gs[i % 3], v, size: size(s.mag) * 0.8)
        }
        for g in gs {
            if let e = g.entity("bgStars", starMat([0.92, 0.94, 1], 0.85)) {
                root.addChild(e)
                bgEnts.append(e)
            }
        }
    }

    private func build(_ c: Constellation, _ lst: Double) {
        var verts: [SIMD3<Float>] = []
        var segs: [(SIMD3<Float>, SIMD3<Float>)] = []
        var normal = Geo(), bright = Geo(), lines = Geo()
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
                if v.y > 0.02 {
                    starQuad(&normal, v, size: size(s.mag))
                    starQuad(&bright, v, size: size(s.mag) * 1.7)
                }
            }
        }
        guard !verts.isEmpty else { return }
        let center = simd_normalize(sum)
        // 별자리 전체가 지평선 아래면 건너뜀 (가장 높은 별이 3도 밑)
        guard verts.contains(where: { $0.y > 0.05 }) else { return }
        var radius: Float = 0
        for v in verts { radius = max(radius, acos(min(1, simd_dot(v, center)))) }
        let g = Group(c: c, dir: center, radius: radius, verts: verts, segs: segs)
        if let e = normal.entity("con", starMat([0.95, 0.96, 1], 0.95)) { root.addChild(e); g.normal = e }
        if let e = bright.entity("conFocus", starMat([1, 0.97, 0.9], 1.25)) {
            e.components.set(OpacityComponent(opacity: 0))
            e.isEnabled = false
            root.addChild(e)
            g.bright = e
        }
        for (a, b) in segs where a.y > 0 || b.y > 0 {
            let pa = a * R * 0.995, pb = b * R * 0.995
            let d = simd_normalize(pb - pa)
            let gap: Float = R * 0.006
            guard simd_distance(pa, pb) > gap * 2.2 else { continue }
            lines.stroke(pa + d * gap, pb - d * gap, width: R * 0.0016)
        }
        let lineCol: UIColor = look == .line ? UIColor(white: 0.12, alpha: 1) : (look == .mono ? UIColor(white: 0.9, alpha: 1) : UIColor(red: 0.7, green: 0.82, blue: 1, alpha: 1))
        var lm = UnlitMaterial(color: lineCol)
        lm.blending = .transparent(opacity: .init(floatLiteral: 0.85))
        if let e = lines.entity("conLines", lm) {
            e.components.set(OpacityComponent(opacity: 0))
            e.isEnabled = false
            root.addChild(e)
            g.lines = e
        }
        groups.append(g)
    }

    /// 그 방향의 별자리 (별·선에서 3.5도 안, 가장 가까운 것)
    private func near(_ dirIn: SIMD3<Float>, tol: Float = 0.06) -> Group? {
        let d = simd_normalize(dirIn)
        var best: (Group, Float)? = nil
        for g in groups {
            let a = acos(min(1, max(-1, simd_dot(d, g.dir))))
            guard a < g.radius + tol else { continue }
            var m: Float = 10
            for v in g.verts { m = min(m, acos(min(1, max(-1, simd_dot(d, v))))) }
            for (p, q) in g.segs {
                // 큰 원 위 선분까지 거리 (작은 각이라 평면 근사)
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
            focused = near(gaze, tol: 0.055)
        }
        // 구름: 천천히 흐려졌다 또렷해짐
        let cl: Float = cloudy ? 0.5 + 0.5 * max(0, sin(t * 0.07)) : 1
        for (i, e) in bgEnts.enumerated() {
            let tw: Float = 0.82 + (windy ? 0.18 : 0.1) * sin(t * (2.1 + Float(i) * 0.9) + Float(i) * 2)
            e.components.set(OpacityComponent(opacity: tw * cl))
        }
        for g in groups {
            let want: Float = (g === focused || g.picked) ? 1 : 0
            if abs(g.focus - want) > 0.005 || want > 0 {
                g.focus += (want - g.focus) * min(1, dt * 6)
                if let b = g.bright {
                    let on = g.focus > 0.01
                    if b.isEnabled != on { b.isEnabled = on }
                    if on { b.components.set(OpacityComponent(opacity: g.focus * (0.85 + 0.15 * sin(t * 5)) * cl)) }
                }
            }
            if g.picked { g.reveal = min(1, g.reveal + dt / 0.9) } else if g.reveal > 0 { g.reveal = max(0, g.reveal - dt * 1.2) }
            if let l = g.lines {
                let on = g.reveal > 0.01
                if l.isEnabled != on { l.isEnabled = on }
                if on { l.components.set(OpacityComponent(opacity: g.reveal * cl)) }
            }
            if let lb = g.label {
                lb.components.set(OpacityComponent(opacity: g.reveal * cl))
                if !g.picked && g.reveal <= 0 { lb.removeFromParent(); g.label = nil }
            }
        }
    }

    /// 탭: 그 방향의 별자리를 고름 (없으면 nil) — 선을 긋고 이름을 띄움
    func pick(_ d: SIMD3<Float>) -> Constellation? {
        guard visible, let g = near(d, tol: 0.07) else { return nil }
        for o in groups { o.picked = o === g }
        g.reveal = 0
        if g.label == nil { g.label = makeLabel(g) }
        Sfx.play("star_chime", in: root, at: g.dir * 4, gain: -4)
        return g.c
    }

    func unpick() {
        for g in groups { g.picked = false }
    }

    private func makeLabel(_ g: Group) -> Entity {
        let up0 = SIMD3<Float>(0, 1, 0)
        var upT = up0 - g.dir * simd_dot(up0, g.dir)
        upT = simd_length(upT) > 0.01 ? simd_normalize(upT) : SIMD3<Float>(0, 0, -1)
        // 별자리 아래쪽 (가장 낮은 별보다 조금 아래)
        let below = simd_normalize(g.dir - upT * (g.radius + 0.05))
        let col: UIColor = look == .line ? UIColor(white: 0.12, alpha: 1) : UIColor(white: 0.95, alpha: 1)
        let text = MeshResource.generateText(g.c.name, extrusionDepth: 0.05, font: .systemFont(ofSize: CGFloat(R * 0.024), weight: .medium), alignment: .center)
        let te = ModelEntity(mesh: text, materials: [UnlitMaterial(color: col)])
        let bb = te.visualBounds(relativeTo: nil)
        te.position = SIMD3<Float>(-(bb.min.x + bb.max.x) / 2, -(bb.min.y + bb.max.y) / 2, 0)
        let holder = Entity()
        holder.look(at: .zero, from: below * R * 0.98, upVector: upT, relativeTo: root)
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
