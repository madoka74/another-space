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
    static let gain: Double = -7

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

/// 카페 테이블 차림: 방에 보이는 가구 블록 중 평평한 윗면(높이 50cm~1.1m, 같은 높이로 이어진 면)에만 올림.
/// 보이는 블록 윗면 높이에 정확히 놓으므로 뜨거나 묻히지 않음 — 가구 블록은 한 번 보이면 탐험이 끝날 때까지 그대로라 차림도 그대로.
/// 윗면 크기에 맞춰: 넓으면 서로 떨어진 두 자리(잔·받침 + 디저트 접시), 좁으면 한 자리, 가운데엔 꽃병·화분·책(밤엔 촛불).
/// 물건마다 차지하는 둥근 자리가 윗면 안쪽(가장자리에서 떨어진 곳)에 다 들어가고 서로 겹치지 않을 때만 놓음.
/// 한 번 놓은 차림은 이 방에 있는 동안(다른 방에 다녀와도) 바뀌지 않음
@MainActor
final class CafeTables {
    let root = Entity()
    private var used = Set<Int64>()                 // 차림이 놓인 윗면의 칸 (다시 고르지 않게)
    private var sets = 0
    private var flames: [(Entity, Float)] = []
    private var scanT: Float = 0.8
    private var t: Float = 0
    private let look: LookMode
    private let time: String
    private let room: Int

    init(look: LookMode, time: String, room: Int) {
        self.look = look
        self.time = time
        self.room = room
    }

    private static func key(_ u: Int, _ v: Int) -> Int64 { (Int64(u) + 100_000) << 20 | (Int64(v) + 100_000) }

    /// cellH: 그 10cm 칸에 보이는 가구 블록 높이(10cm 단위, 없으면 0)
    func tick(_ dt: Float, head: SIMD3<Float>, L: Layout, cellH: (Int, Int) -> Int) {
        t += dt
        for (e, ph) in flames where e.parent != nil {
            let k = 0.85 + 0.15 * sin(t * 13 + ph) * sin(t * 7.1 + ph * 2)
            e.scale = SIMD3<Float>(1, k, 1)
        }
        scanT -= dt
        guard scanT <= 0, sets < 6 else { return }
        scanT = 1
        let me = L.plane(head.x, head.z)
        let u0 = Int((me.x / 0.1).rounded(.down)), v0 = Int((me.y / 0.1).rounded(.down))
        let R = 35
        var seen = Set<Int64>()
        var regions: [(Int, [(Int, Int)])] = []
        for du in -R...R {
            for dv in -R...R where du * du + dv * dv <= R * R {
                let u = u0 + du, v = v0 + dv
                let k = Self.key(u, v)
                guard !seen.contains(k), !used.contains(k) else { continue }
                let h = cellH(u, v)
                guard h >= 5 && h <= 11 else { continue }
                let pc = SIMD2<Float>((Float(u) + 0.5) * 0.1, (Float(v) + 0.5) * 0.1)
                guard L.at(x: L.flat(pc).x, z: L.flat(pc).y).room == room else { continue }
                // 같은 높이로 이어진 칸 모으기
                var cells: [(Int, Int)] = []
                var stack = [(u, v)]
                seen.insert(k)
                while let c = stack.popLast(), cells.count < 400 {
                    cells.append(c)
                    for (a, b) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                        let n = (c.0 + a, c.1 + b), nk = Self.key(n.0, n.1)
                        guard !seen.contains(nk), !used.contains(nk), cellH(n.0, n.1) == h else { continue }
                        seen.insert(nk)
                        stack.append(n)
                    }
                }
                if cells.count >= 12 { regions.append((h, cells)) }
            }
        }
        regions.sort { $0.1.count > $1.1.count }
        for (h, cells) in regions.prefix(2) where sets < 6 {
            place(h, cells, L)
        }
    }

    /// 한 윗면에 차림 놓기
    private func place(_ h: Int, _ cells: [(Int, Int)], _ L: Layout) {
        let inside = Set(cells.map { Self.key($0.0, $0.1) })
        // 가장자리까지 칸 수 (가장자리 칸 = 1)
        var depth: [Int64: Int] = [:]
        var frontier: [(Int, Int)] = []
        for c in cells {
            let edge = [(1, 0), (-1, 0), (0, 1), (0, -1)].contains { !inside.contains(Self.key(c.0 + $0.0, c.1 + $0.1)) }
            if edge { depth[Self.key(c.0, c.1)] = 1; frontier.append(c) }
        }
        var d = 1
        while !frontier.isEmpty {
            d += 1
            var next: [(Int, Int)] = []
            for c in frontier {
                for (a, b) in [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)] {
                    let n = (c.0 + a, c.1 + b), nk = Self.key(n.0, n.1)
                    guard inside.contains(nk), depth[nk] == nil else { continue }
                    depth[nk] = d
                    next.append(n)
                }
            }
            frontier = next
        }
        func ctr(_ c: (Int, Int)) -> SIMD2<Float> { SIMD2<Float>((Float(c.0) + 0.5) * 0.1, (Float(c.1) + 0.5) * 0.1) }
        // 그 칸에 놓을 수 있는 물건 반지름 (칸 가운데에서 윗면 가장자리까지 - 2cm)
        func space(_ c: (Int, Int)) -> Float { Float(depth[Self.key(c.0, c.1)] ?? 0) * 0.1 - 0.07 }
        var placed: [(SIMD2<Float>, Float)] = []
        func fits(_ p: SIMD2<Float>, _ r: Float) -> Bool { placed.allSatisfy { simd_distance($0.0, p) >= $0.1 + r + 0.025 } }
        var g = SeededRNG(seed: UInt64(truncatingIfNeeded: cells.count * 7919 + cells[0].0 * 131 + cells[0].1 * 31 + 7))
        let setE = Entity()
        let top = L.floorY + Float(h) * 0.1
        var items: [(SIMD2<Float>, String)] = []
        // 잔 자리: 들어갈 수 있는 칸 중 서로 가장 먼 두 칸 (넓으면), 아니면 가장 안쪽 한 칸
        let cupR: Float = 0.08, plateR: Float = 0.1
        let cupCells = cells.filter { space($0) >= cupR }
        guard !cupCells.isEmpty else { return }
        var best: ((Int, Int), (Int, Int), Float)? = nil
        for _ in 0..<60 {
            let a = cupCells[Int(g.next() % UInt64(cupCells.count))], b = cupCells[Int(g.next() % UInt64(cupCells.count))]
            let dd = simd_distance(ctr(a), ctr(b))
            if best == nil || dd > best!.2 { best = (a, b, dd) }
        }
        guard let pair = best else { return }
        let seats = pair.2 >= 0.45 ? [pair.0, pair.1] : [cupCells.max { space($0) < space($1) } ?? pair.0]
        for sc in seats where fits(ctr(sc), cupR) {
            placed.append((ctr(sc), cupR))
            items.append((ctr(sc), "cup"))
        }
        // 접시: 잔 옆 (15~25cm), 들어갈 때만
        for (cp, _) in items where g.next() % 3 != 0 {
            let opts = cells.filter { space($0) >= plateR && simd_distance(ctr($0), cp) > 0.17 && simd_distance(ctr($0), cp) < 0.3 && fits(ctr($0), plateR) }
            if let pc = opts.randomElement(using: &g) {
                placed.append((ctr(pc), plateR))
                items.append((ctr(pc), "plate"))
            }
        }
        // 가운데 장식: 윗면 가운데에 가장 가까운 빈 곳
        let mean = cells.map(ctr).reduce(SIMD2<Float>(0, 0), +) / Float(cells.count)
        let night = time == "night" || time == "dusk" || time == "dawn"
        let deco = night ? "candle" : ["vase", "vase", "pot", "book"][Int(g.next() % 4)]
        let decoR: Float = deco == "book" ? 0.13 : 0.05
        if let dc = cells.filter({ space($0) >= decoR && fits(ctr($0), decoR) }).min(by: { simd_distance(ctr($0), mean) < simd_distance(ctr($1), mean) }) {
            placed.append((ctr(dc), decoR))
            items.append((ctr(dc), deco))
            if night, g.next() % 2 == 0, let vc = cells.filter({ space($0) >= 0.04 && fits(ctr($0), 0.04) }).min(by: { simd_distance(ctr($0), ctr(dc)) < simd_distance(ctr($1), ctr(dc)) }) {
                placed.append((ctr(vc), 0.04))
                items.append((ctr(vc), "vase"))
            }
        }
        guard !items.isEmpty else { return }
        let glaze = Self.glazes[Int(g.next() % UInt64(Self.glazes.count))]
        for (i, it) in items.enumerated() {
            let w2 = L.flat(it.0)
            let holder = Entity()
            holder.position = SIMD3<Float>(w2.x, top + 0.001, w2.y)
            var lines = Geo()
            curHolder = holder
            switch it.1 {
            case "cup":
                let drink = Int(g.next() % 5)
                let other = Self.glazes[Int(g.next() % UInt64(Self.glazes.count))]
                let mine = (i > 0 && g.next() % 2 == 0) ? other : glaze
                // 손잡이는 차림 가운데 반대쪽 (앉은 사람 쪽)
                let away = it.0 - mean
                let turn: Float = simd_length(away) > 0.01 ? atan2(away.y, away.x) : 0
                if drink == 4 { icedGlass(.zero, &g, holder, &lines) } else { cup(.zero, kind: drink, glaze: mine, turn: turn, &g, holder, &lines) }
            case "plate":
                let food = Int(g.next() % 3)
                plate(.zero, glaze, food: food, &g, holder, &lines)
            case "candle": candle(.zero, holder, &lines)
            case "pot": pot(.zero, &g, holder, &lines)
            case "book": book(.zero, &g, holder, &lines)
            default: budVase(.zero, &g, holder, &lines)
            }
            if let e = lines.entity("setLines", Ink.line) { holder.addChild(e) }
            setE.addChild(holder)
        }
        // 탁자 차림(유리잔·얼음 등 반투명 포함)도 포털보다 나중에 그림 (김은 따로 31번 — Sorting.apply는 그림 엔티티만 바꿈)
        Sorting.apply(setE, 30)
        root.addChild(setE)
        for c in cells { used.insert(Self.key(c.0, c.1)) }
        sets += 1
    }

    func remove() {
        root.removeFromParent()
        flames.removeAll()
    }

    // MARK: 재질
    private static let glazes: [SIMD3<Float>] = [[0.95, 0.93, 0.88], [0.62, 0.71, 0.6], [0.5, 0.61, 0.73], [0.77, 0.46, 0.33],
                                                 [0.24, 0.24, 0.26], [0.86, 0.69, 0.32], [0.89, 0.71, 0.69], [0.97, 0.97, 0.96]]
    private static let flowers: [SIMD3<Float>] = [[0.95, 0.55, 0.62], [0.98, 0.84, 0.3], [0.97, 0.96, 0.94], [0.96, 0.5, 0.36], [0.7, 0.55, 0.85]]

    private func pbr(_ c: SIMD3<Float>, rough: Float = 0.35, metal: Float = 0, coat: Bool = false) -> RealityKit.Material {
        if look == .line { return Ink.paper(0) }
        // 흑백: 빛을 받는 재질(PBR)은 실제 방의 빛 색(노란 조명 등)과 촛불 빛을 받아 색이 묻어나 보였음 → 빛을 받지 않는 회색
        if look == .mono {
            let l = min(1, max(0, c.x * 0.3 + c.y * 0.59 + c.z * 0.11))
            return UnlitMaterial(color: UIColor(white: CGFloat(0.12 + 0.8 * l), alpha: 1))
        }
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: Tex.with(look) { Tex.color(c) })
        m.roughness = .init(scale: rough)
        m.metallic = .init(scale: metal)
        if coat { m.clearcoat = .init(scale: 0.8); m.clearcoatRoughness = .init(scale: 0.05) }
        return m
    }

    private func glass(_ alpha: Float = 0.22) -> RealityKit.Material {
        if look == .line { return Ink.paper(0) }
        if look == .mono {
            var g = UnlitMaterial(color: UIColor(white: 0.85, alpha: 1))
            g.blending = .transparent(opacity: .init(scale: alpha))
            g.writesDepth = false
            return g
        }
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: UIColor(white: 0.95, alpha: 1))
        m.roughness = .init(scale: 0.04)
        m.specular = .init(scale: 1)
        m.blending = .transparent(opacity: .init(scale: alpha))
        m.writesDepth = false                 // 반투명 판이 뒤의 나무·물건을 네모나게 지우지 않게
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
        if look != .line { e.components.set(GroundingShadowComponent(castsShadow: true)) } else { Ink.hull(e) }
        p.addChild(e)
    }

    private var curHolder: Entity?

    /// 선 그림: 돌림체(컵·접시·병)의 바깥 윤곽 — 옆모습 선을 늘 나를 향하게 세운 판(빌보드)에 그림.
    /// 돌림체는 어느 쪽에서 봐도 옆모습이 같아, 이 선이 늘 물체의 외곽선과 겹침 (반지름 + 굵기 절반 바깥이라 물체에 가리지 않음)
    private func silhouette(_ prof: [SIMD2<Float>], at p: SIMD2<Float>, y0: Float) {
        guard look == .line, let h = curHolder, prof.count > 1 else { return }
        // 바깥쪽 선만: 아래 가운데에서 시작해 위로 올라가다 안쪽으로 꺾여 내려가기 전까지
        var outer: [SIMD2<Float>] = [prof[0]]
        for i in 1..<prof.count {
            if prof[i].y < prof[i - 1].y - 1e-4 && prof[i].x < prof[i - 1].x { break }
            outer.append(prof[i])
        }
        var g = Geo()
        let w = Ink.w
        for side: Float in [-1, 1] {
            for i in 0..<(outer.count - 1) {
                let a = outer[i], b = outer[i + 1]
                g.stroke(SIMD3<Float>(side * (a.x + w * 0.5), y0 + a.y, 0), SIMD3<Float>(side * (b.x + w * 0.5), y0 + b.y, 0), width: w)
            }
        }
        if let last = outer.last {                                           // 위 테두리 (가장자리 사이)
            g.stroke(SIMD3<Float>(-(last.x + w * 0.5), y0 + last.y, 0), SIMD3<Float>(last.x + w * 0.5, y0 + last.y, 0), width: w)
        }
        guard let e = g.entity("silhouette", Ink.line) else { return }
        e.position = SIMD3<Float>(p.x, 0, p.y)
        e.components.set(BillboardComponent())
        h.addChild(e)
    }

    private func outline(_ prof: [SIMD2<Float>], at p: SIMD2<Float>, y0: Float = 0, _ lines: inout Geo, rings: [Int]) {
        guard look == .line else { return }
        silhouette(prof, at: p, y0: y0)
        for i in rings where i < prof.count && prof[i].x > 0.004 {
            let r = prof[i].x, y = y0 + prof[i].y
            for k in 0..<18 {
                let a0 = Float(k) / 18 * 2 * .pi, a1 = Float(k + 1) / 18 * 2 * .pi
                lines.stroke(SIMD3<Float>(p.x + cos(a0) * r, y, p.y + sin(a0) * r), SIMD3<Float>(p.x + cos(a1) * r, y, p.y + sin(a1) * r), width: Ink.w)
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
        if look == .line { for i in 0..<hp.count - 1 { lines.stroke(hp[i], hp[i + 1], width: Ink.w) } }
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
            if look == .line { for i in 0..<pts.count - 1 { lines.stroke(pts[i], pts[i + 1], width: Ink.w) } }
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
            if look == .line { lines.stroke(SIMD3<Float>(a.x, y + 0.056, a.y), SIMD3<Float>(b.x, y + 0.056, b.y), width: Ink.w); lines.stroke(SIMD3<Float>(a.x, y + 0.056, a.y), SIMD3<Float>(c.x, y + 0.056, c.y), width: Ink.w); lines.stroke(SIMD3<Float>(b.x, y + 0.056, b.y), SIMD3<Float>(c.x, y + 0.056, c.y), width: Ink.w) }
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
            if look == .line { lines.stroke(SIMD3<Float>(p.x, 0.1, p.y), midp, width: Ink.w); lines.stroke(midp, tip, width: Ink.w) }
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
        if look == .line { lines.boxOutline(base: [p.x, 0, p.y], w: 0.15, d: 0.21, h: 0.024, yaw: yaw, width: Ink.w) }
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
        if let tx = Tex.with(look, { Tex.get("flame", color: look == .color) }) {
            var tp = MaterialParameters.Texture(tx); tp.sampler = Tex.clamp
            fm.color = .init(tint: look == .line ? UIColor(white: 0.15, alpha: 1) : .white, texture: tp)
        }
        if let mk = Tex.get("flame_a", raw: true) {
            var tp = MaterialParameters.Texture(mk); tp.sampler = Tex.clamp
            fm.blending = .transparent(opacity: .init(scale: 1, texture: tp))
            fm.writesDepth = false                 // 반투명 판이 뒤의 나무·물건을 네모나게 지우지 않게
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
        if look == .color {                                       // 흑백·선 그림엔 촛불 빛(주황)을 비추지 않음
            let light = Entity()
            let pl = PointLightComponent(color: UIColor(red: 1, green: 0.75, blue: 0.45, alpha: 1), intensity: 900, attenuationRadius: 0.8)
            light.components.set(pl)
            light.position = [p.x, 0.07, p.y]
            root.addChild(light)
        }
    }

    /// 따뜻한 음료의 김: 가늘고 옅은 김이 잔 위에서 피어 흔들리며 사라짐 (큰 덩어리가 겹쳐 보이지 않게 작고 많이)
    private func steam(_ at: SIMD3<Float>, _ root: Entity) {
        var pe = ParticleEmitterComponent()
        pe.emitterShape = .sphere
        pe.emitterShapeSize = [0.025, 0.004, 0.025]
        pe.birthLocation = .volume
        pe.birthDirection = .world
        pe.emissionDirection = [0, 1, 0]
        pe.speed = 0.035
        pe.speedVariation = 0.012
        pe.mainEmitter.birthRate = 14
        pe.mainEmitter.lifeSpan = 1.8
        pe.mainEmitter.lifeSpanVariation = 0.5
        pe.mainEmitter.size = 0.006
        pe.mainEmitter.sizeMultiplierAtEndOfLifespan = 5
        pe.mainEmitter.noiseStrength = 0.012
        pe.mainEmitter.noiseScale = 4
        pe.mainEmitter.noiseAnimationSpeed = 0.6
        pe.mainEmitter.acceleration = [0, 0.01, 0]
        pe.mainEmitter.color = .constant(.single(look == .line ? UIColor(white: 0.45, alpha: 0.12) : UIColor(white: 1, alpha: 0.11)))
        pe.mainEmitter.blendMode = .alpha
        pe.mainEmitter.opacityCurve = .gradualFadeInOut
        if let puff = Tex.particle("smoke_puff") { pe.mainEmitter.image = puff }
        let se = Entity()
        se.components.set(pe)
        // 포털(창·유리 지붕 너머 하늘 세계)보다 나중에 그림: 순서가 없으면 창을 배경으로 볼 때 그 포털이 김을 지워,
        // 김이 배경에 걸려 안 보였다가 시선·순서가 바뀌면 다시 보였음
        se.components.set(ModelSortGroupComponent(group: Sorting.group, order: 31))
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
