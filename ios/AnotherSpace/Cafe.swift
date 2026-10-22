import Foundation
import UIKit
import RealityKit
import simd

/// 카페 배경 오르골: 앱에 담긴 오르골 곡들(저작권이 끝난 옛 곡·전통곡을 앱이 오르골 소리로 연주해 만든 것)을
/// 무작위로 끊이지 않게 이어 틂 — 한 곡이 끝나기 3초 전부터 다음 곡이 겹쳐 들어옴. 카페 천장 스피커에서 나는 낮은 소리
@MainActor
final class CafeMusic {
    private struct Item: Decodable { let file: String; let ext: String; let dur: Double; let name: String }
    private static let items: [Item] = {
        guard let u = Bundle.main.url(forResource: "jazz", withExtension: "json", subdirectory: "sfx"),
              let d = try? Data(contentsOf: u), let l = try? JSONDecoder().decode([Item].self, from: d) else { return [] }
        return l
    }()

    let root = Entity()                          // 스피커 자리 (저장 좌표)
    private var cur: (AudioPlaybackController, Entity, Double)?     // 재생 중, 엔티티, 끝나는 때
    private var recent: [Int] = []
    private var t: Double = 0
    private var on = false
    static let gain: Double = -15

    var available: Bool { !Self.items.isEmpty }

    /// 카페에 들어오면 켜고(스피커 자리), 나가면 천천히 끔
    func set(_ active: Bool, at p: SIMD3<Float>? = nil) {
        if let p { root.position = p }
        guard active != on else { return }
        on = active
        if !active, let c = cur {
            c.0.fade(to: -60, duration: 2.5)
            let e = c.1
            cur = nil
            Task { try? await Task.sleep(for: .seconds(2.8)); e.removeFromParent() }
        }
    }

    func tick(_ dt: Float) {
        t += Double(dt)
        guard on, !Self.items.isEmpty else { return }
        if cur == nil || t > (cur?.2 ?? 0) - 3 { next() }
    }

    private func next() {
        // 최근 4곡은 빼고 무작위
        let pool = Self.items.indices.filter { !recent.contains($0) }
        guard let i = (pool.isEmpty ? Array(Self.items.indices) : pool).randomElement() else { return }
        recent.append(i)
        if recent.count > min(4, Self.items.count - 1) { recent.removeFirst() }
        let it = Self.items[i]
        guard let u = Bundle.main.url(forResource: it.file, withExtension: it.ext, subdirectory: "sfx") else { return }
        let cfg = AudioFileResource.Configuration(loadingStrategy: .stream, shouldLoop: false)
        guard let r = try? AudioFileResource.load(contentsOf: u, withName: nil, configuration: cfg) else { return }
        if let c = cur {                                       // 앞 곡은 3초에 걸쳐 줄이고 정리
            c.0.fade(to: -60, duration: 3)
            let e = c.1
            Task { try? await Task.sleep(for: .seconds(3.3)); e.removeFromParent() }
        }
        let e = Entity()
        var sa = SpatialAudioComponent()
        sa.gain = 0
        e.components.set(sa)
        root.addChild(e)
        let c = e.playAudio(r)
        c.gain = -60
        c.fade(to: Self.gain, duration: cur == nil ? 2.5 : 3)
        cur = (c, e, t + it.dur)
    }

    func remove() {
        cur?.0.stop()
        root.removeFromParent()
        cur = nil
    }
}

/// 카페 테이블: 비전프로가 '탁자'로 알아본 실제 수평면(정확한 높이·크기·방향)에만 차림을 올림 → 공중에 뜨지 않음.
/// 탁자 크기에 맞춰 마주 앉는 두 자리(잔+받침, 디저트 접시)와 가운데 꽃병·화분·촛불. 잔·접시는 여러 빛깔 유약, 실제 방 빛을 받는 재질.
/// 탁자 면이 움직이거나 커지면 다시 놓고, 사라지면 치움. 따뜻한 음료는 김, 해질녘·밤엔 촛불
@MainActor
final class CafeTables {
    struct Table: Equatable {
        var c: SIMD3<Float>                      // 면 가운데 (저장 좌표, y = 윗면 높이)
        var w: Float, d: Float                   // 면 크기 (x, z)
        var yaw: Float
    }

    let root = Entity()
    private var sets: [UUID: (Table, Entity)] = [:]
    private var flames: [(Entity, Float)] = []
    private var scanT: Float = 0.5
    private var t: Float = 0
    private let look: LookMode
    private let time: String

    init(look: LookMode, time: String) {
        self.look = look
        self.time = time
    }

    func tick(_ dt: Float, head: SIMD3<Float>, floorY: Float, tables: [UUID: Table], inRoom: (SIMD2<Float>) -> Bool) {
        t += dt
        for (e, ph) in flames where e.parent != nil {
            let k = 0.85 + 0.15 * sin(t * 13 + ph) * sin(t * 7.1 + ph * 2)
            e.scale = SIMD3<Float>(1, k, 1)
        }
        scanT -= dt
        guard scanT <= 0 else { return }
        scanT = 1
        let me = SIMD2<Float>(head.x, head.z)
        func ok(_ tb: Table) -> Bool {
            let h = tb.c.y - floorY
            return h > 0.4 && h < 1.2 && min(tb.w, tb.d) >= 0.28 && inRoom(SIMD2<Float>(tb.c.x, tb.c.z))
        }
        // 사라졌거나 옮겨진 탁자
        for (id, s) in sets {
            guard let tb = tables[id], ok(tb) else {
                s.1.removeFromParent(); sets[id] = nil; continue
            }
            let moved = simd_distance(tb.c, s.0.c) > 0.04 || abs(tb.yaw - s.0.yaw) > 0.08
            let grown = abs(min(tb.w, tb.d) - min(s.0.w, s.0.d)) > 0.15 || abs(max(tb.w, tb.d) - max(s.0.w, s.0.d)) > 0.25
            if grown {
                s.1.removeFromParent(); sets[id] = nil
            } else if moved {
                s.1.position = tb.c
                s.1.orientation = simd_quatf(angle: tb.yaw, axis: [0, 1, 0])
                sets[id] = (tb, s.1)
            }
        }
        guard sets.count < 6 else { return }
        let fresh = tables.filter { sets[$0.key] == nil && ok($0.value) && simd_distance(SIMD2<Float>($0.value.c.x, $0.value.c.z), me) < 4.5 }
            .sorted { simd_distance(SIMD2<Float>($0.value.c.x, $0.value.c.z), me) < simd_distance(SIMD2<Float>($1.value.c.x, $1.value.c.z), me) }
        for (id, tb) in fresh.prefix(6 - sets.count) {
            // 다른 탁자 면과 겹치면(같은 탁자를 두 번 알아봄) 건너뜀
            if sets.values.contains(where: { simd_distance($0.0.c, tb.c) < 0.5 }) { continue }
            var g = SeededRNG(seed: UInt64(truncatingIfNeeded: id.hashValue))
            let e = makeSet(tb, &g)
            e.position = tb.c
            e.orientation = simd_quatf(angle: tb.yaw, axis: [0, 1, 0])
            root.addChild(e)
            sets[id] = (tb, e)
        }
    }

    func remove() {
        root.removeFromParent()
        sets.removeAll()
        flames.removeAll()
    }

    // MARK: 재질
    private static let glazes: [SIMD3<Float>] = [[0.95, 0.93, 0.88], [0.62, 0.71, 0.6], [0.5, 0.61, 0.73], [0.77, 0.46, 0.33],
                                                 [0.24, 0.24, 0.26], [0.86, 0.69, 0.32], [0.89, 0.71, 0.69], [0.97, 0.97, 0.96]]
    private static let flowers: [SIMD3<Float>] = [[0.95, 0.55, 0.62], [0.98, 0.84, 0.3], [0.97, 0.96, 0.94], [0.96, 0.5, 0.36], [0.7, 0.55, 0.85]]

    private func pbr(_ c: SIMD3<Float>, rough: Float = 0.35, metal: Float = 0, coat: Bool = false) -> RealityKit.Material {
        if look == .line { return Ink.paper(0) }
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: Tex.with(look) { Tex.color(c) })
        m.roughness = .init(scale: rough)
        m.metallic = .init(scale: metal)
        if coat { m.clearcoat = .init(scale: 0.8); m.clearcoatRoughness = .init(scale: 0.05) }
        return m
    }

    private func glass(_ alpha: Float = 0.22) -> RealityKit.Material {
        if look == .line { return Ink.paper(0) }
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: UIColor(white: 0.95, alpha: 1))
        m.roughness = .init(scale: 0.04)
        m.specular = .init(scale: 1)
        m.blending = .transparent(opacity: .init(scale: alpha))
        return m
    }

    private func add(_ s: Solid, _ m: RealityKit.Material, to p: Entity, _ name: String) {
        guard let mesh = s.mesh(name) else { return }
        let e = ModelEntity(mesh: mesh, materials: [m])
        if look != .line { e.components.set(GroundingShadowComponent(castsShadow: true)) }
        p.addChild(e)
    }

    private func ball(_ r: Float, _ at: SIMD3<Float>, _ sc: SIMD3<Float>, _ m: RealityKit.Material, to p: Entity, yaw: Float = 0, tilt: Float = 0) {
        let e = ModelEntity(mesh: .generateSphere(radius: r), materials: [m])
        e.position = at
        e.scale = sc
        e.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0]) * simd_quatf(angle: tilt, axis: [0, 0, 1])
        if look != .line { e.components.set(GroundingShadowComponent(castsShadow: true)) }
        p.addChild(e)
    }

    // MARK: 차림
    private func makeSet(_ tb: Table, _ g: inout SeededRNG) -> Entity {
        let root = Entity()
        var lines = Geo()
        let long = max(tb.w, tb.d), short = min(tb.w, tb.d)
        let alongX = tb.w >= tb.d
        let night = time == "night" || time == "dusk" || time == "dawn"
        let glaze = Self.glazes[Int(g.next() % UInt64(Self.glazes.count))]
        // 탁자 안쪽(가장자리 8cm 안)으로만
        func clampIn(_ p: SIMD2<Float>, _ r: Float) -> SIMD2<Float> {
            SIMD2<Float>(max(-tb.w / 2 + r + 0.06, min(tb.w / 2 - r - 0.06, p.x)), max(-tb.d / 2 + r + 0.06, min(tb.d / 2 - r - 0.06, p.y)))
        }
        func axis(_ a: Float, _ b: Float) -> SIMD2<Float> { alongX ? SIMD2<Float>(a, b) : SIMD2<Float>(b, a) }
        let seats = (long >= 0.55 && short >= 0.4) ? 2 : 1
        let off = min(0.36, long * 0.3)
        for k in 0..<seats {
            let sgn: Float = seats == 1 ? 0 : (k == 0 ? -1 : 1)
            // 자리마다: 잔(받침 위) + 가끔 디저트 접시
            let cupAt = clampIn(axis(sgn * off, (seats == 1 ? -0.05 : 0.06 * sgn)), 0.08)
            let drink = Int(g.next() % 5)
            let other = Self.glazes[Int(g.next() % UInt64(Self.glazes.count))]
            let mine = (k == 1 && g.next() % 2 == 0) ? other : glaze
            let turn: Float = sgn >= 0 ? .pi : 0
            if drink == 4 {
                icedGlass(cupAt, &g, root, &lines)
            } else {
                cup(cupAt, kind: drink, glaze: mine, turn: turn, &g, root, &lines)
            }
            if g.next() % 3 != 0, short >= 0.45 || seats == 1 {
                let pl = clampIn(axis(sgn * off * 0.55 + (seats == 1 ? 0.16 : 0), (seats == 1 ? 0.08 : -0.12 * sgn)), 0.1)
                let food = Int(g.next() % 3)
                plate(pl, glaze, food: food, &g, root, &lines)
            }
        }
        // 가운데: 밤엔 촛불, 아니면 꽃병·화분 (가끔 책)
        let mid = clampIn(axis(0, seats == 1 ? 0.0 : 0), 0.05)
        if night {
            candle(mid + axis(0.0, -0.04), root, &lines)
            if seats == 2 && g.next() % 2 == 0 { budVase(mid + axis(0.07, 0.05), &g, root, &lines) }
        } else {
            switch g.next() % 4 {
            case 0, 1: budVase(mid, &g, root, &lines)
            case 2: pot(mid, &g, root, &lines)
            default: book(clampIn(mid + axis(0.05, 0.02), 0.12), &g, root, &lines)
            }
        }
        if let e = lines.entity("setLines", Ink.line) { root.addChild(e) }
        return root
    }

    private func outline(_ prof: [SIMD2<Float>], at p: SIMD2<Float>, y0: Float = 0, _ lines: inout Geo, rings: [Int]) {
        guard look == .line else { return }
        for i in rings where i < prof.count && prof[i].x > 0.004 {
            let r = prof[i].x, y = y0 + prof[i].y
            for k in 0..<18 {
                let a0 = Float(k) / 18 * 2 * .pi, a1 = Float(k + 1) / 18 * 2 * .pi
                lines.stroke(SIMD3<Float>(p.x + cos(a0) * r, y, p.y + sin(a0) * r), SIMD3<Float>(p.x + cos(a1) * r, y, p.y + sin(a1) * r), width: 0.0025)
            }
        }
    }

    private static let saucerP: [SIMD2<Float>] = [[0, 0], [0.045, 0], [0.05, 0.003], [0.07, 0.01], [0.078, 0.014], [0.077, 0.016], [0.066, 0.0125], [0.048, 0.0065], [0, 0.0065]]
    private static let cupP: [SIMD2<Float>] = [[0, 0], [0.024, 0], [0.03, 0.004], [0.038, 0.02], [0.045, 0.045], [0.048, 0.062], [0.047, 0.066],
                                               [0.044, 0.063], [0.04, 0.042], [0.031, 0.017], [0, 0.013]]
    private static let plateP: [SIMD2<Float>] = [[0, 0], [0.06, 0], [0.066, 0.004], [0.094, 0.012], [0.1, 0.016], [0.099, 0.018], [0.088, 0.0135], [0.062, 0.0075], [0, 0.0075]]

    /// 잔+받침. kind 0 라테(하트 무늬) 1 카푸치노 2 에스프레소(작은 잔) 3 아메리카노
    private func cup(_ p: SIMD2<Float>, kind: Int, glaze: SIMD3<Float>, turn: Float, _ g: inout SeededRNG, _ root: Entity, _ lines: inout Geo) {
        let small = kind == 2
        let s: Float = small ? 0.72 : 1
        let sy: Float = small ? 0.78 : 1
        let gm = pbr(glaze, rough: 0.18, coat: true)
        var sau = Solid()
        sau.lathe(Self.saucerP.map { $0 * s }, at: SIMD3<Float>(p.x, 0, p.y))
        add(sau, gm, to: root, "saucer")
        outline(Self.saucerP.map { $0 * s }, at: p, &lines, rings: [4])
        let y0: Float = 0.0065 * s
        var c = Solid()
        let prof = Self.cupP.map { SIMD2<Float>($0.x * s, $0.y * s * sy) }
        c.lathe(prof, at: SIMD3<Float>(p.x, y0, p.y))
        add(c, gm, to: root, "cup")
        outline(prof, at: p, y0: y0, &lines, rings: [1, 5])
        // 손잡이: 바깥 벽에서 둥글게
        let a = turn + Float(Int(g.next() % 3) - 1) * 0.5
        let dir = SIMD2<Float>(cos(a), sin(a))
        var hp: [SIMD3<Float>] = []
        for i in 0...10 {
            let u = Float(i) / 10
            let ang = -Float.pi / 2 + u * Float.pi
            let r = (0.044 + 0.016 * cos(ang)) * s
            let yy = y0 + (0.038 + 0.016 * sin(-ang + 0)) * s * sy
            hp.append(SIMD3<Float>(p.x + dir.x * r, yy, p.y + dir.y * r))
        }
        var h = Solid()
        h.tube(hp, radius: { _ in 0.0042 * s })
        add(h, gm, to: root, "handle")
        if look == .line { for i in 0..<hp.count - 1 { lines.stroke(hp[i], hp[i + 1], width: 0.0025) } }
        // 커피 면
        let top = y0 + 0.052 * s * sy
        let rr: Float = 0.041 * s
        var col = SIMD3<Float>(0.17, 0.1, 0.06)
        switch kind {
        case 0: col = SIMD3<Float>(0.68, 0.48, 0.31)
        case 1: col = SIMD3<Float>(0.82, 0.7, 0.56)
        case 2: col = SIMD3<Float>(0.5, 0.31, 0.16)
        default: break
        }
        var surf = Solid()
        surf.disc(r: rr, at: SIMD3<Float>(p.x, top, p.y))
        add(surf, pbr(col, rough: 0.12), to: root, "coffee")
        if kind == 0 || kind == 1 {
            // 우유 거품 무늬 (라테: 하트, 카푸치노: 가운데 동그라미)
            var art = Solid()
            if kind == 0 {
                art.disc(r: 0.013, at: SIMD3<Float>(p.x - 0.008, top + 0.0006, p.y - 0.004))
                art.disc(r: 0.013, at: SIMD3<Float>(p.x - 0.008, top + 0.0006, p.y + 0.004 + 0.008))
                art.disc(r: 0.009, at: SIMD3<Float>(p.x + 0.01, top + 0.0006, p.y + 0.004))
            } else {
                art.disc(r: 0.026, at: SIMD3<Float>(p.x, top + 0.0006, p.y))
            }
            add(art, pbr([0.96, 0.92, 0.84], rough: 0.5), to: root, "art")
        }
        if time != "night" || g.next() % 2 == 0 { steam(SIMD3<Float>(p.x, top + 0.01, p.y), root) }
        // 찻숟가락
        if g.next() % 2 == 0 {
            let sa = turn + 1.3
            let sd = SIMD2<Float>(cos(sa), sin(sa))
            let a0 = p + sd * 0.052 * s, a1 = p + sd * 0.074 * s
            var sp = Solid()
            sp.tube([SIMD3<Float>(a0.x, 0.0085 * s, a0.y), SIMD3<Float>(a1.x, 0.0125 * s, a1.y)], radius: { _ in 0.0018 })
            add(sp, pbr([0.82, 0.82, 0.84], rough: 0.2, metal: 1), to: root, "spoon")
        }
    }

    private func icedGlass(_ p: SIMD2<Float>, _ g: inout SeededRNG, _ root: Entity, _ lines: inout Geo) {
        let prof: [SIMD2<Float>] = [[0, 0], [0.03, 0], [0.033, 0.005], [0.037, 0.12], [0.035, 0.121], [0.032, 0.006], [0, 0.006]]
        var gl = Solid()
        gl.lathe(prof, at: SIMD3<Float>(p.x, 0, p.y))
        add(gl, glass(0.25), to: root, "glass")
        outline(prof, at: p, &lines, rings: [1, 3])
        guard look != .line else { return }
        // 아이스 라테: 아래 커피, 위 우유 (층), 얼음, 빨대
        let tea = g.next() % 3 == 0
        var low = Solid()
        low.lathe([[0, 0.007], [0.031, 0.007], [0.033, 0.055], [0, 0.055]], at: SIMD3<Float>(p.x, 0, p.y))
        add(low, pbr(tea ? [0.55, 0.68, 0.33] : [0.42, 0.25, 0.13], rough: 0.1), to: root, "liquid")
        var up = Solid()
        up.lathe([[0, 0.055], [0.033, 0.055], [0.035, 0.092], [0, 0.092]], at: SIMD3<Float>(p.x, 0, p.y))
        add(up, pbr([0.93, 0.89, 0.8], rough: 0.25), to: root, "milk")
        for k in 0..<3 {
            let a = Float(k) * 2.1 + Float(g.next() % 10) * 0.1
            let ice = ModelEntity(mesh: .generateBox(size: 0.018, cornerRadius: 0.004), materials: [glass(0.45)])
            ice.position = [p.x + cos(a) * 0.013, 0.088 + Float(k) * 0.004, p.y + sin(a) * 0.013]
            ice.orientation = simd_quatf(angle: a, axis: simd_normalize(SIMD3<Float>(1, 1, 0.3)))
            root.addChild(ice)
        }
        var st = Solid()
        st.tube([SIMD3<Float>(p.x + 0.008, 0.012, p.y), SIMD3<Float>(p.x + 0.02, 0.16, p.y + 0.008)], radius: { _ in 0.0032 })
        add(st, pbr([0.2, 0.45, 0.32], rough: 0.4), to: root, "straw")
    }

    /// 접시: food 0 크루아상 1 딸기 케이크 2 쿠키 두 개
    private func plate(_ p: SIMD2<Float>, _ glaze: SIMD3<Float>, food: Int, _ g: inout SeededRNG, _ root: Entity, _ lines: inout Geo) {
        var pl = Solid()
        pl.lathe(Self.plateP, at: SIMD3<Float>(p.x, 0, p.y))
        let plC: SIMD3<Float> = g.next() % 2 == 0 ? glaze : SIMD3<Float>(0.97, 0.97, 0.96)
        add(pl, pbr(plC, rough: 0.18, coat: true), to: root, "plate")
        outline(Self.plateP, at: p, &lines, rings: [4])
        let y: Float = 0.0075
        let yaw = Float(g.next() % 628) / 100
        switch food {
        case 0:
            // 크루아상: 초승달 모양으로 굵기가 변하는 관
            var pts: [SIMD3<Float>] = []
            for i in 0...16 {
                let u = Float(i) / 16
                let a = yaw - 1.25 + u * 2.5
                pts.append(SIMD3<Float>(p.x + cos(a) * 0.04 - cos(yaw) * 0.025, y + 0.016, p.y + sin(a) * 0.04 - sin(yaw) * 0.025))
            }
            var cr = Solid()
            cr.tube(pts, radius: { u in 0.006 + 0.019 * pow(sin(u * .pi), 0.8) }, flat: 0.72)
            add(cr, pbr([0.8, 0.53, 0.22], rough: 0.55), to: root, "croissant")
            if look == .line { for i in 0..<pts.count - 1 { lines.stroke(pts[i], pts[i + 1], width: 0.0025) } }
        case 1:
            // 케이크 조각: 시트·크림 층, 위에 딸기
            let L: Float = 0.085, W: Float = 0.036
            let cs = SIMD2<Float>(cos(yaw), sin(yaw)), sn = SIMD2<Float>(-sin(yaw), cos(yaw))
            let a = p - cs * L * 0.45, b = a + cs * L + sn * W, c = a + cs * L - sn * W
            let layers: [(Float, Float, SIMD3<Float>)] = [(0, 0.022, [0.93, 0.8, 0.55]), (0.022, 0.028, [0.97, 0.94, 0.88]), (0.028, 0.048, [0.93, 0.8, 0.55]), (0.048, 0.056, [0.98, 0.96, 0.92])]
            for (y0, y1, col) in layers {
                var w = Solid()
                w.prism([a, b, c], y0: y + y0, y1: y + y1)
                add(w, pbr(col, rough: 0.7), to: root, "cake")
            }
            let top = (b + c) / 2 * 0.6 + a * 0.4
            ball(0.011, SIMD3<Float>(top.x, y + 0.066, top.y), [1, 1.25, 1], pbr([0.84, 0.1, 0.15], rough: 0.3, coat: true), to: root)
            if look == .line { lines.stroke(SIMD3<Float>(a.x, y + 0.056, a.y), SIMD3<Float>(b.x, y + 0.056, b.y), width: 0.0025); lines.stroke(SIMD3<Float>(a.x, y + 0.056, a.y), SIMD3<Float>(c.x, y + 0.056, c.y), width: 0.0025); lines.stroke(SIMD3<Float>(b.x, y + 0.056, b.y), SIMD3<Float>(c.x, y + 0.056, c.y), width: 0.0025) }
        default:
            for k in 0..<2 {
                let o = SIMD2<Float>(cos(yaw + Float(k) * 2.4), sin(yaw + Float(k) * 2.4)) * 0.028
                var ck = Solid()
                ck.lathe([[0, 0], [0.026, 0], [0.028, 0.005], [0.025, 0.009], [0, 0.0095]], at: SIMD3<Float>(p.x + o.x, y + Float(k) * 0.003, p.y + o.y))
                add(ck, pbr([0.72, 0.48, 0.25], rough: 0.8), to: root, "cookie")
                for j in 0..<4 {
                    let q = o + SIMD2<Float>(cos(Float(j) * 1.7 + yaw), sin(Float(j) * 1.7 + yaw)) * 0.013
                    ball(0.0035, SIMD3<Float>(p.x + q.x, y + Float(k) * 0.003 + 0.009, p.y + q.y), [1, 0.6, 1], pbr([0.25, 0.13, 0.07], rough: 0.5), to: root)
                }
            }
        }
    }

    private func budVase(_ p: SIMD2<Float>, _ g: inout SeededRNG, _ root: Entity, _ lines: inout Geo) {
        let prof: [SIMD2<Float>] = [[0, 0], [0.026, 0], [0.032, 0.02], [0.03, 0.05], [0.014, 0.088], [0.011, 0.118], [0.014, 0.124], [0.009, 0.121], [0, 0.11]]
        let glaze = Self.glazes[Int(g.next() % UInt64(Self.glazes.count))]
        var v = Solid()
        v.lathe(prof, at: SIMD3<Float>(p.x, 0, p.y))
        add(v, pbr(glaze, rough: 0.2, coat: true), to: root, "vase")
        outline(prof, at: p, &lines, rings: [2, 6])
        let n = 1 + Int(g.next() % 3)
        for k in 0..<n {
            let lean = SIMD2<Float>(cos(Float(k) * 2.3 + Float(g.next() % 6)), sin(Float(k) * 2.3 + Float(g.next() % 6))) * (0.012 + 0.012 * Float(k))
            let h: Float = 0.2 + Float(g.next() % 6) * 0.012
            let tip = SIMD3<Float>(p.x + lean.x * 2.2, h, p.y + lean.y * 2.2)
            let midp = SIMD3<Float>(p.x + lean.x, 0.15, p.y + lean.y)
            var st = Solid()
            st.tube([SIMD3<Float>(p.x, 0.1, p.y), midp, tip], radius: { _ in 0.0017 })
            add(st, pbr([0.28, 0.48, 0.22], rough: 0.6), to: root, "stem")
            if look == .line { lines.stroke(SIMD3<Float>(p.x, 0.1, p.y), midp, width: 0.002); lines.stroke(midp, tip, width: 0.002) }
            let fc = Self.flowers[Int(g.next() % UInt64(Self.flowers.count))]
            let petal = pbr(fc, rough: 0.55)
            for j in 0..<5 {
                let a = Float(j) / 5 * 2 * .pi
                ball(0.011, tip + SIMD3<Float>(cos(a) * 0.01, 0.002, sin(a) * 0.01), [1, 0.35, 0.65], petal, to: root, yaw: -a, tilt: 0.35)
            }
            ball(0.0055, tip + SIMD3<Float>(0, 0.005, 0), [1, 0.7, 1], pbr([0.95, 0.75, 0.2], rough: 0.7), to: root)
            ball(0.012, midp + SIMD3<Float>(0.006, -0.01, 0), [1, 0.25, 0.45], pbr([0.3, 0.52, 0.24], rough: 0.6), to: root, yaw: Float(k), tilt: 0.6)
        }
    }

    private func pot(_ p: SIMD2<Float>, _ g: inout SeededRNG, _ root: Entity, _ lines: inout Geo) {
        let prof: [SIMD2<Float>] = [[0, 0], [0.034, 0], [0.044, 0.068], [0.05, 0.07], [0.05, 0.082], [0.045, 0.082], [0.043, 0.074], [0, 0.074]]
        var v = Solid()
        v.lathe(prof, at: SIMD3<Float>(p.x, 0, p.y))
        let alt = Self.glazes[Int(g.next() % UInt64(Self.glazes.count))]
        let potC: SIMD3<Float> = g.next() % 2 == 0 ? SIMD3<Float>(0.76, 0.45, 0.32) : alt
        add(v, pbr(potC, rough: 0.75), to: root, "pot")
        outline(prof, at: p, &lines, rings: [1, 4])
        var soil = Solid()
        soil.disc(r: 0.042, at: SIMD3<Float>(p.x, 0.075, p.y))
        add(soil, pbr([0.24, 0.17, 0.12], rough: 1), to: root, "soil")
        // 다육이: 바깥으로 벌어진 통통한 잎
        let leaf = pbr([0.42, 0.6, 0.42], rough: 0.45)
        for ring in 0..<2 {
            let n = ring == 0 ? 7 : 5
            for j in 0..<n {
                let a = Float(j) / Float(n) * 2 * .pi + Float(ring) * 0.4
                let r: Float = ring == 0 ? 0.026 : 0.012
                ball(ring == 0 ? 0.02 : 0.016, SIMD3<Float>(p.x + cos(a) * r, 0.088 + Float(ring) * 0.012, p.y + sin(a) * r), [1, 0.38, 0.55], leaf, to: root, yaw: -a, tilt: ring == 0 ? 0.5 : 0.9)
            }
        }
    }

    private func book(_ p: SIMD2<Float>, _ g: inout SeededRNG, _ root: Entity, _ lines: inout Geo) {
        let colors: [SIMD3<Float>] = [[0.5, 0.16, 0.14], [0.14, 0.26, 0.42], [0.2, 0.36, 0.24], [0.85, 0.7, 0.4], [0.3, 0.3, 0.32]]
        let yaw = Float(Int(g.next() % 80) - 40) / 100
        let cover = ModelEntity(mesh: .generateBox(width: 0.15, height: 0.024, depth: 0.21, cornerRadius: 0.002), materials: [pbr(colors[Int(g.next() % 5)], rough: 0.7)])
        cover.position = [p.x, 0.012, p.y]
        cover.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        if look != .line { cover.components.set(GroundingShadowComponent(castsShadow: true)) }
        root.addChild(cover)
        let pages = ModelEntity(mesh: .generateBox(width: 0.146, height: 0.019, depth: 0.204), materials: [pbr([0.96, 0.93, 0.85], rough: 0.9)])
        pages.position = [0.003, 0, 0]
        cover.addChild(pages)
        if look == .line { lines.boxOutline(base: [p.x, 0, p.y], w: 0.15, d: 0.21, h: 0.024, yaw: yaw, width: 0.0025) }
    }

    private func candle(_ p: SIMD2<Float>, _ root: Entity, _ lines: inout Geo) {
        let jarP: [SIMD2<Float>] = [[0, 0], [0.034, 0], [0.036, 0.004], [0.036, 0.08], [0.034, 0.081], [0.033, 0.005], [0, 0.004]]
        var jar = Solid()
        jar.lathe(jarP, at: SIMD3<Float>(p.x, 0, p.y))
        add(jar, glass(0.2), to: root, "jar")
        outline(jarP, at: p, &lines, rings: [1, 3])
        var wax = Solid()
        wax.lathe([[0, 0.004], [0.031, 0.004], [0.031, 0.045], [0, 0.047]], at: SIMD3<Float>(p.x, 0, p.y))
        add(wax, pbr([0.96, 0.92, 0.84], rough: 0.6), to: root, "wax")
        var fm = UnlitMaterial(color: look == .line ? UIColor(white: 0.15, alpha: 1) : Tex.with(look) { Tex.color([1, 0.8, 0.4]) })
        if let tx = Tex.get("flame", color: look == .color) {
            var tp = MaterialParameters.Texture(tx); tp.sampler = Tex.clamp
            fm.color = .init(tint: look == .line ? UIColor(white: 0.15, alpha: 1) : .white, texture: tp)
        }
        if let mk = Tex.get("flame_a", raw: true) {
            var tp = MaterialParameters.Texture(mk); tp.sampler = Tex.clamp
            fm.blending = .transparent(opacity: .init(scale: 1, texture: tp))
        }
        var q = Geo()
        q.crossTree(at: .zero, width: 0.016, height: 0.032, yaw: 0.3)
        if let f = q.entity("candleFlame", fm) {
            let h = Entity()
            h.position = [p.x, 0.047, p.y]
            h.addChild(f)
            root.addChild(h)
            flames.append((h, Float.random(in: 0...6)))
        }
        if look != .line {
            let light = Entity()
            let pl = PointLightComponent(color: UIColor(red: 1, green: 0.75, blue: 0.45, alpha: 1), intensity: 900, attenuationRadius: 0.8)
            light.components.set(pl)
            light.position = [p.x, 0.07, p.y]
            root.addChild(light)
        }
    }

    private func steam(_ at: SIMD3<Float>, _ root: Entity) {
        var pe = ParticleEmitterComponent()
        pe.emitterShape = .point
        pe.birthDirection = .world
        pe.emissionDirection = [0, 1, 0]
        pe.speed = 0.045
        pe.speedVariation = 0.015
        pe.mainEmitter.birthRate = 4
        pe.mainEmitter.lifeSpan = 2.4
        pe.mainEmitter.size = 0.014
        pe.mainEmitter.sizeMultiplierAtEndOfLifespan = 4
        pe.mainEmitter.noiseStrength = 0.02
        pe.mainEmitter.color = .constant(.single(look == .line ? UIColor(white: 0.4, alpha: 0.22) : UIColor(white: 1, alpha: 0.26)))
        pe.mainEmitter.opacityCurve = .gradualFadeInOut
        if let puff = Tex.get("smoke_puff", color: true) { pe.mainEmitter.image = puff }
        let se = Entity()
        se.components.set(pe)
        se.position = at
        root.addChild(se)
    }
}

/// 빛을 받는 작은 물건용 그물 (법선 있음): 돌림체(잔·접시·꽃병), 관(손잡이·줄기·크루아상), 납작한 원, 세모 기둥(케이크)
struct Solid {
    var pos: [SIMD3<Float>] = []
    var nrm: [SIMD3<Float>] = []
    var idx: [UInt32] = []

    /// 옆모습 선(반지름 x, 높이 y)을 세로축으로 한 바퀴 돌림. 양면
    mutating func lathe(_ prof: [SIMD2<Float>], at c: SIMD3<Float>, seg: Int = 32) {
        guard prof.count >= 2 else { return }
        let base = UInt32(pos.count)
        var n2: [SIMD2<Float>] = []
        for i in prof.indices {
            let a = prof[max(0, i - 1)], b = prof[min(prof.count - 1, i + 1)]
            let tng = b - a
            var n = SIMD2<Float>(tng.y, -tng.x)
            if simd_length(n) < 1e-6 { n = SIMD2<Float>(0, 1) }
            n2.append(simd_normalize(n))
        }
        for j in 0...seg {
            let a = Float(j) / Float(seg) * 2 * .pi
            let ca = cos(a), sa = sin(a)
            for i in prof.indices {
                pos.append(c + SIMD3<Float>(prof[i].x * ca, prof[i].y, prof[i].x * sa))
                nrm.append(simd_normalize(SIMD3<Float>(n2[i].x * ca, n2[i].y, n2[i].x * sa)))
            }
        }
        let m = UInt32(prof.count)
        for j in 0..<UInt32(seg) {
            for i in 0..<(m - 1) {
                let a = base + j * m + i, b = a + 1, c2 = a + m, d = c2 + 1
                idx += [a, b, d, a, d, c2]
                idx += [a, d, b, a, c2, d]
            }
        }
    }

    /// 점들을 잇는 관. radius(u) 로 굵기, flat 은 위아래로 눌린 정도(1 = 동그람)
    mutating func tube(_ pts: [SIMD3<Float>], radius: (Float) -> Float, seg: Int = 10, flat: Float = 1) {
        guard pts.count >= 2 else { return }
        var path = pts
        if path.count == 2 {                                   // 곧은 관은 가운데 점 하나 더
            path = [pts[0], (pts[0] + pts[1]) / 2, pts[1]]
        }
        let base = UInt32(pos.count)
        var prevN = SIMD3<Float>(0, 1, 0)
        for (i, p) in path.enumerated() {
            let t = simd_normalize(path[min(path.count - 1, i + 1)] - path[max(0, i - 1)])
            var n = prevN - t * simd_dot(prevN, t)
            if simd_length(n) < 1e-4 { n = abs(t.y) < 0.9 ? SIMD3<Float>(0, 1, 0) - t * t.y : SIMD3<Float>(1, 0, 0) - t * t.x }
            n = simd_normalize(n)
            prevN = n
            let b = simd_cross(t, n)
            let u = Float(i) / Float(path.count - 1)
            let r = radius(u)
            for k in 0...seg {
                let a = Float(k) / Float(seg) * 2 * .pi
                let dir = n * cos(a) * flat + b * sin(a)
                pos.append(p + dir * r)
                nrm.append(simd_normalize(n * cos(a) / max(0.2, flat) + b * sin(a)))
            }
        }
        let m = UInt32(seg + 1)
        for i in 0..<UInt32(path.count - 1) {
            for k in 0..<UInt32(seg) {
                let a = base + i * m + k, b = a + 1, c = a + m, d = c + 1
                idx += [a, b, d, a, d, c, a, d, b, a, c, d]
            }
        }
    }

    /// 납작한 원 (위를 봄)
    mutating func disc(r: Float, at c: SIMD3<Float>, seg: Int = 28) {
        let base = UInt32(pos.count)
        pos.append(c); nrm.append([0, 1, 0])
        for k in 0...seg {
            let a = Float(k) / Float(seg) * 2 * .pi
            pos.append(c + SIMD3<Float>(cos(a) * r, 0, sin(a) * r)); nrm.append([0, 1, 0])
        }
        for k in 0..<UInt32(seg) { idx += [base, base + 2 + k, base + 1 + k, base, base + 1 + k, base + 2 + k] }
    }

    /// 바닥 다각형(xz)을 y0~y1로 세운 기둥 (면마다 평평한 법선)
    mutating func prism(_ poly: [SIMD2<Float>], y0: Float, y1: Float) {
        func face(_ q: [SIMD3<Float>], _ n: SIMD3<Float>) {
            let base = UInt32(pos.count)
            for p in q { pos.append(p); nrm.append(n) }
            for k in 1..<UInt32(q.count - 1) { idx += [base, base + k, base + k + 1, base, base + k + 1, base + k] }
        }
        face(poly.map { SIMD3<Float>($0.x, y1, $0.y) }, [0, 1, 0])
        face(poly.map { SIMD3<Float>($0.x, y0, $0.y) }, [0, -1, 0])
        for i in poly.indices {
            let a = poly[i], b = poly[(i + 1) % poly.count]
            let e = b - a
            var n = SIMD3<Float>(e.y, 0, -e.x)
            let ctr = poly.reduce(SIMD2<Float>(0, 0), +) / Float(poly.count)
            if simd_dot(SIMD2<Float>(n.x, n.z), (a + b) / 2 - ctr) < 0 { n = -n }
            face([SIMD3<Float>(a.x, y0, a.y), SIMD3<Float>(b.x, y0, b.y), SIMD3<Float>(b.x, y1, b.y), SIMD3<Float>(a.x, y1, a.y)], simd_normalize(n))
        }
    }

    @MainActor
    func mesh(_ name: String) -> MeshResource? {
        guard !idx.isEmpty else { return nil }
        var d = MeshDescriptor(name: name)
        d.positions = MeshBuffers.Positions(pos)
        d.normals = MeshBuffers.Normals(nrm)
        d.primitives = .triangles(idx)
        return try? MeshResource.generate(from: [d])
    }
}
