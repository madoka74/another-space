import Foundation
import UIKit
import RealityKit
import simd

/// 장소마다 둘러 세울 풍경
struct Decor {
    /// 지평선 띠: 방 가운데를 둘러싼 원기둥에 붙인 그림 (먼 산 · 능선 · 숲 가장자리 · 도시)
    struct Band {
        let tex: String
        var night: String? = nil          // 밤·새벽에 쓸 그림 (불 켜진 창)
        let radius: Float                 // relative면 '방 반지름 + radius'
        var relative = false
        let height: Float
        var base: Float = -2              // 바닥 기준 아래 끝 높이
        let aspect: Float                 // 그림 가로/세로
        let layer: Int                    // 0 먼 곳(지평선 빛으로 물듦), 1 중간, 2 가까움
    }
    /// 십자로 세운 나무들
    struct Trees {
        let tex: String
        let count: Int
        let h: ClosedRange<Float>
        let d: ClosedRange<Float>         // 벽 바깥으로 떨어진 거리
        var aspect: Float = 0.5
    }
    struct Rocks {
        let tex: String
        let count: Int
        let size: ClosedRange<Float>
        let d: ClosedRange<Float>
    }
    var bands: [Band] = []
    var trees: [Trees] = []
    var rocks: Rocks? = nil
    var tents = false
    var lanterns = false
    var sea = false
    var city = false
    var paintings = false
    var stringLights = false

    static func of(_ place: String) -> Decor {
        var d = Decor()
        switch place {
        case "camp":
            d.bands = [Band(tex: "far_mtn", radius: 270, height: 70, base: -6, aspect: 4, layer: 0),
                       Band(tex: "mid_ridge", radius: 140, height: 32, base: -3, aspect: 4, layer: 1),
                       Band(tex: "near_pines", radius: 34, relative: true, height: 20, base: -1, aspect: 2, layer: 2)]
            d.trees = [Trees(tex: "tree_pine", count: 18, h: 8...15, d: 3...20)]
            d.tents = true
            d.lanterns = true
        case "forest":
            d.bands = [Band(tex: "mid_ridge", radius: 140, height: 40, base: -3, aspect: 4, layer: 1),
                       Band(tex: "near_broad", radius: 24, relative: true, height: 24, base: -1, aspect: 2, layer: 2)]
            d.trees = [Trees(tex: "tree_broad", count: 16, h: 10...18, d: 2...16),
                       Trees(tex: "tree_pine", count: 10, h: 12...20, d: 3...18)]
            d.rocks = Rocks(tex: "mossrock", count: 7, size: 0.4...1.2, d: 1.5...10)
        case "valley":
            d.bands = [Band(tex: "far_peaks", radius: 270, height: 90, base: -6, aspect: 4, layer: 0),
                       Band(tex: "mid_cliffs", radius: 40, relative: true, height: 48, base: -2, aspect: 2, layer: 2)]
            d.trees = [Trees(tex: "tree_pine", count: 6, h: 6...11, d: 4...22)]
            d.rocks = Rocks(tex: "rock", count: 16, size: 0.6...3, d: 1...24)
        case "sea":
            d.bands = [Band(tex: "far_islands", radius: 280, height: 16, base: -1.5, aspect: 8, layer: 0)]
            d.trees = [Trees(tex: "tree_twisted", count: 5, h: 6...10, d: 1.5...6)]
            d.rocks = Rocks(tex: "basalt", count: 8, size: 0.5...2.2, d: 5...26)
            d.sea = true
        case "village":
            d.bands = [Band(tex: "far_mtn", radius: 270, height: 60, base: -6, aspect: 4, layer: 0),
                       Band(tex: "mid_village", night: "mid_village_night", radius: 100, height: 36, base: -4, aspect: 4, layer: 1)]
            d.trees = [Trees(tex: "tree_broad", count: 8, h: 7...12, d: 4...25)]
        case "city":
            d.bands = [Band(tex: "far_city", night: "far_city_night", radius: 260, height: 160, base: -30, aspect: 2, layer: 1)]
            d.city = true
        case "cafe":
            d.bands = [Band(tex: "far_city", night: "far_city_night", radius: 35, relative: true, height: 60, base: -1, aspect: 2, layer: 2)]
            d.stringLights = true
        case "gallery":
            d.bands = [Band(tex: "far_mtn", radius: 270, height: 60, base: -6, aspect: 4, layer: 0)]
            d.trees = [Trees(tex: "tree_broad", count: 6, h: 7...11, d: 4...14)]
            d.paintings = true
        default:   // home
            d.bands = [Band(tex: "mid_ridge", radius: 140, height: 32, base: -3, aspect: 4, layer: 1),
                       Band(tex: "near_pines", radius: 26, relative: true, height: 20, base: -1, aspect: 2, layer: 2)]
            d.trees = [Trees(tex: "tree_pine", count: 12, h: 9...16, d: 2...14)]
        }
        return d
    }
}

/// 방 하나의 다른 세계.
/// - 하늘 세계(WorldComponent): 하늘, 땅, 지평선 띠(먼 산·숲·도시), 나무·바위·텐트, 울타리. 천장·벽(바깥 장소)·창(실내 장소)으로 보임
/// - 방 안(실제 공간): 바닥, 실내 장소의 벽·유리 지붕 틀·그림·전구, 비·눈·바람·반딧불
/// 엔티티를 물체마다 만들지 않고 같은 그림끼리 그물 하나로 모아서(방마다 20개 안팎) 가볍게 그림
@MainActor
final class RoomWorld {
    let room: RoomRec
    let style: WorldStyle
    let world = Entity()            // 포털 너머 세계
    let local = Entity()            // 방 안 (저장 좌표)
    private(set) var tint: SIMD3<Float>
    private(set) var shades: [Float]
    private var skyEntity: ModelEntity?
    private var skyMat: UnlitMaterial?
    private var flashMat: UnlitMaterial?
    private var clouds: [(Entity, SIMD3<Float>)] = []
    private var emitters: [Entity] = []
    private var flashLeft: Float = 0
    private var water: ModelEntity?
    private var waterOff: Float = 0
    private(set) var center = SIMD3<Float>(0, 0, 0)         // 방 가운데 바닥 (저장 좌표)
    private(set) var halfSize = SIMD2<Float>(1, 1)           // 방 반 크기 (격자 방향, m)
    let angle: Float
    private let sortGroup = ModelSortGroup(depthPass: nil)
    /// 문 번호 → 이 방 쪽 문짝 (닫히면 이 방 벽처럼 보임). 열 때 가로로 오므라듦
    private(set) var doorPanels: [Int: [Entity]] = [:]
    /// 문 번호 → 가까이 가면 보이는 문틀·열쇠 구멍·떠 있는 열쇠 (root, 숨 쉬는 빛, 열쇠)
    private(set) var doorUI: [Int: (root: Entity, glow: Entity, key: Entity)] = [:]

    var outdoor: Bool { style.open }
    var dark: Bool { room.time == "night" || room.time == "dawn" }

    typealias PRect = (SIMD2<Float>, SIMD2<Float>)

    init(_ d: SpaceData, _ r: RoomRec, layout: Layout) {
        room = r
        style = Worlds.style(r.place, time: r.time)
        angle = d.rec.angle
        tint = Worlds.timeTint(r.time, indoor: Worlds.indoor(r.place)) * Worlds.weatherDim(r.weather)
        shades = Worlds.contrast(r.time, weather: r.weather)
        world.components.set(WorldComponent())
        build(d, layout)
    }

    /// 이 방을 그리는 데 필요한 그림 (미리 읽어 두기용)
    static func textures(_ r: RoomRec) -> [(String, String)] {
        let st = Worlds.style(r.place, time: r.time)
        let dc = Decor.of(r.place)
        let night = r.time == "night" || r.time == "dawn"
        var l: [(String, String)] = [(Worlds.skyName(time: r.time, weather: r.weather), "sky"), (st.floor, "tex"), (st.prop, "tex"), (st.ground, "tex")]
        l.append((st.open ? st.barrier : st.wall, "tex"))
        for b in dc.bands { l.append(((night ? b.night : nil) ?? b.tex, "tex")) }
        for t in dc.trees { l.append((t.tex, "tex")) }
        if let rk = dc.rocks { l.append((rk.tex, "tex")) }
        if dc.tents { l.append(("canvas", "tex")) }
        if dc.sea { l.append(("water", "tex")) }
        if dc.city { l.append((night ? "facade_night" : "facade", "tex")) }
        if dc.paintings { for i in 0..<6 { l.append(("art_\(i)", "tex")) } }
        if Worlds.cloudCount(r.weather) > 0 { for i in 0..<3 { l.append(("cloud_\(i)", "sky")) } }
        return l
    }

    private func layer(_ e: Entity, _ order: Int) {
        e.components.set(ModelSortGroupComponent(group: sortGroup, order: Int32(order)))
    }

    // MARK: 만들기
    private func build(_ d: SpaceData, _ L: Layout) {
        let rec = d.rec
        let floorY = rec.floorY
        let ceilY = floorY + room.ceil
        let rects = L.rects(room.id)                 // 이 방이 차지하는 곳 (문·통로 포함, 평면 좌표 m)
        if let f = rects.first {
            var lo = f.0, hi = f.1
            for r in rects { lo = simd_min(lo, r.0); hi = simd_max(hi, r.1) }
            let c = L.flat((lo + hi) / 2)
            center = SIMD3<Float>(c.x, floorY, c.y)
            halfSize = (hi - lo) / 2
        }
        let R = simd_length(halfSize)
        let segs = L.walls.filter { $0.room == room.id }

        // 바닥 (바닥 위 6mm)
        if let m = Self.flatMesh(rects, L, y: floorY + 0.006, tile: style.floorTile) {
            local.addChild(ModelEntity(mesh: m, materials: [Tex.unlit(style.floor, tint: Worlds.safe(tint, min: 0.4))]))
        }
        // 천장 = 하늘 세계로 열린 창 (천장보다 2cm 아래)
        if let m = Self.flatMesh(rects, L, y: ceilY - 0.02, tile: 1) {
            let p = ModelEntity(mesh: m, materials: [PortalMaterial()])
            p.components.set(PortalComponent(target: world))
            local.addChild(p)
        }
        if style.open {
            openWalls(segs, L, floorY: floorY, ceilY: ceilY)
        } else {
            solidWalls(segs, L, floorY: floorY, ceilY: ceilY)
            addSkylightFrame(rects, L, y: ceilY - 0.06)
        }
        addDoors(L, floorY: floorY, ceilY: ceilY)

        let dc = Decor.of(room.place)
        addSky()
        addGround(dc, R: R, floorY: floorY)
        addBands(dc, R: R, floorY: floorY)
        addThings(dc, rec: rec, floorY: floorY)
        if dc.paintings { addPaintings(segs, L, floorY: floorY) }
        if dc.stringLights { addStringLights(segs, L, ceilY: ceilY) }
        addClouds(ceilY: ceilY)
        addWeather(rects, L, floorY: floorY, ceilY: ceilY)
        setActive(false)
    }

    // MARK: 벽
    /// 바깥 장소: 벽 자리 전체가 하늘 세계로 열린 창. 그 너머 22cm에 울타리·덤불·바위·난간을 둘러 세워 '막힌 곳'으로 보이게 (안전)
    private func openWalls(_ segs: [WallSeg], _ L: Layout, floorY: Float, ceilY: Float) {
        var portal = Geo(), fence = Geo()
        let tileW = style.barrierH * 2                       // 그림 가로:세로 = 2:1
        for s in segs {
            let a2 = L.flat(s.a), b2 = L.flat(s.b)
            let a = SIMD3<Float>(a2.x, floorY, a2.y), b = SIMD3<Float>(b2.x, floorY, b2.y)
            let len = simd_distance(a2, b2)
            guard len > 0.01 else { continue }
            portal.wall(a, b, y0: 0, y1: ceilY - floorY, u0: 0, u1: 1)
            let dir = (b2 - a2) / len
            let n = L.flat(s.n) - L.flat(SIMD2<Float>(0, 0))           // 방 안쪽
            let o = -n * 0.22
            let along0 = abs(s.a.x - s.b.x) > abs(s.a.y - s.b.y) ? min(s.a.x, s.b.x) : min(s.a.y, s.b.y)
            let fa = a2 + o - dir * 0.3, fb = b2 + o + dir * 0.3
            fence.wall(SIMD3<Float>(fa.x, floorY, fa.y), SIMD3<Float>(fb.x, floorY, fb.y), y0: -0.05, y1: style.barrierH,
                       u0: (along0 - 0.3) / tileW, u1: (along0 + len + 0.3) / tileW, v0: 0.02, v1: 1)
        }
        if let m = portal.mesh("walls") {
            let p = ModelEntity(mesh: m, materials: [PortalMaterial()])
            p.components.set(PortalComponent(target: world))
            local.addChild(p)
        }
        if let e = fence.entity("fence", Tex.cutout(style.barrier, tint: Worlds.safe(tint, min: 0.45))) {
            layer(e, 6)
            world.addChild(e)
        }
    }

    /// 실내 장소: 바닥부터 천장까지 반듯한 벽 (해를 보는 쪽은 밝게). 창: 0.85m~2.15m를 하늘 세계로 열린 창으로
    private func solidWalls(_ segs: [WallSeg], _ L: Layout, floorY: Float, ceilY: Float) {
        let sun = Worlds.sunDir(room.time)
        var parts = [Geo(), Geo(), Geo()]
        var win = Geo(), frame = Geo()
        let tile = style.wallTile
        let top = ceilY - floorY
        for s in segs {
            let a2 = L.flat(s.a), b2 = L.flat(s.b)
            let a = SIMD3<Float>(a2.x, floorY, a2.y), b = SIMD3<Float>(b2.x, floorY, b2.y)
            let len = simd_distance(a2, b2)
            guard len > 0.01 else { continue }
            let nw = L.flat(s.n) - L.flat(SIMD2<Float>(0, 0))
            let l = simd_dot(SIMD3<Float>(nw.x, 0, nw.y), sun)
            let k = l > 0.25 ? 0 : (l > -0.25 ? 1 : 2)
            let along0 = abs(s.a.x - s.b.x) > abs(s.a.y - s.b.y) ? min(s.a.x, s.b.x) : min(s.a.y, s.b.y)
            let u0 = along0 / tile, u1 = (along0 + len) / tile
            if s.window && top > 1.6 {
                let w0: Float = 0.85, w1 = min(2.15, top - 0.15)
                parts[k].wall(a, b, y0: 0, y1: w0, u0: u0, u1: u1, v0: 0, v1: w0 / tile)
                parts[k].wall(a, b, y0: w1, y1: top, u0: u0, u1: u1, v0: w1 / tile, v1: top / tile)
                win.wall(a, b, y0: w0, y1: w1, u0: 0, u1: 1)
                let inn = SIMD3<Float>(nw.x, 0, nw.y) * 0.02
                for y in [w0, w1] {
                    frame.wall(a + inn, b + inn, y0: y - 0.03, y1: y + 0.03, u0: 0, u1: 1)
                }
            } else {
                parts[k].wall(a, b, y0: 0, y1: top, u0: u0, u1: u1, v0: 0, v1: top / tile)
            }
        }
        for k in 0..<3 {
            if let e = parts[k].entity("wall\(k)", Tex.unlit(style.wall, tint: Worlds.safe(tint * shades[k], min: 0.36))) {
                local.addChild(e)
            }
        }
        if let m = win.mesh("window") {
            let p = ModelEntity(mesh: m, materials: [PortalMaterial()])
            p.components.set(PortalComponent(target: world))
            local.addChild(p)
            if let f = frame.entity("frame", UnlitMaterial(color: Tex.color(SIMD3<Float>(0.24, 0.2, 0.17) * Worlds.safe(tint)))) {
                local.addChild(f)
            }
        }
    }

    // MARK: 문
    /// 다른 방과 이어진 문·통로마다: 이 방 쪽에 문짝(이 방의 벽과 같은 모양)과, 가까이 가면 보일 문틀·손잡이를 만들어 둠.
    /// 열고 닫는 것은 탐험 세션이 정함 (같은 세계끼리는 늘 열림)
    private func addDoors(_ L: Layout, floorY: Float, ceilY: Float) {
        let top = ceilY - floorY
        let sun = Worlds.sunDir(room.time)
        for (i, ds) in L.doors.enumerated() where ds.roomA == room.id || ds.roomB == room.id {
            let a2 = L.flat(ds.a), b2 = L.flat(ds.b)
            let len = simd_distance(a2, b2)
            guard len > 0.2 else { continue }
            let dir = (b2 - a2) / len
            let nw = L.flat(ds.normal(for: room.id)) - L.flat(SIMD2<Float>(0, 0))      // 이 방 쪽
            let yaw = atan2(-dir.y, dir.x)
            let q = simd_quatf(angle: yaw, axis: [0, 1, 0])
            let mid = (a2 + b2) / 2
            func place(_ e: Entity, _ off: Float, y: Float = floorY) {
                let p = mid + nw * off
                e.position = SIMD3<Float>(p.x, y, p.y)
                e.orientation = q
            }
            let hl = len / 2
            var panel = Geo()
            var list: [Entity] = []
            if style.open {
                panel.wall(SIMD3<Float>(-hl, 0, 0), SIMD3<Float>(hl, 0, 0), y0: 0, y1: top, u0: 0, u1: 1)
                if let m = panel.mesh("door\(i)") {
                    let e = ModelEntity(mesh: m, materials: [PortalMaterial()])
                    e.components.set(PortalComponent(target: world))
                    place(e, 0.012)
                    local.addChild(e)
                    list.append(e)
                }
                // 문짝 너머 울타리 (벽과 같은 모양이 이어지게)
                var fence = Geo()
                let tileW = style.barrierH * 2
                let along0 = abs(ds.a.x - ds.b.x) > abs(ds.a.y - ds.b.y) ? min(ds.a.x, ds.b.x) : min(ds.a.y, ds.b.y)
                fence.wall(SIMD3<Float>(-hl - 0.25, 0, 0), SIMD3<Float>(hl + 0.25, 0, 0), y0: -0.05, y1: style.barrierH,
                           u0: (along0 - 0.25) / tileW, u1: (along0 + len + 0.25) / tileW, v0: 0.02, v1: 1)
                if let e = fence.entity("doorFence\(i)", Tex.cutout(style.barrier, tint: Worlds.safe(tint, min: 0.45))) {
                    layer(e, 6)
                    place(e, -0.22)
                    world.addChild(e)
                    list.append(e)
                }
            } else {
                let l = simd_dot(SIMD3<Float>(nw.x, 0, nw.y), sun)
                let k = l > 0.25 ? 0 : (l > -0.25 ? 1 : 2)
                let tile = style.wallTile
                let along0 = abs(ds.a.x - ds.b.x) > abs(ds.a.y - ds.b.y) ? min(ds.a.x, ds.b.x) : min(ds.a.y, ds.b.y)
                panel.wall(SIMD3<Float>(-hl, 0, 0), SIMD3<Float>(hl, 0, 0), y0: 0, y1: top,
                           u0: along0 / tile, u1: (along0 + len) / tile, v0: 0, v1: top / tile)
                if let e = panel.entity("door\(i)", Tex.unlit(style.wall, tint: Worlds.safe(tint * shades[k], min: 0.36))) {
                    place(e, 0.012)
                    local.addChild(e)
                    list.append(e)
                }
            }
            doorPanels[i] = list

            // 문틀 + 손잡이 (처음엔 숨김)
            let ui = Entity()
            place(ui, 0.025)
            let dh = min(2.05, top - 0.05)
            var frame = Geo()
            let fw: Float = 0.06
            frame.wall(SIMD3<Float>(-hl, 0, 0), SIMD3<Float>(-hl + fw, 0, 0), y0: 0, y1: dh, u0: 0, u1: 1)
            frame.wall(SIMD3<Float>(hl - fw, 0, 0), SIMD3<Float>(hl, 0, 0), y0: 0, y1: dh, u0: 0, u1: 1)
            frame.wall(SIMD3<Float>(-hl, 0, 0), SIMD3<Float>(hl, 0, 0), y0: dh - fw, y1: dh, u0: 0, u1: 1)
            let lit = Worlds.safe(tint, min: 0.55)
            if let f = frame.entity("frame", UnlitMaterial(color: Tex.color(SIMD3<Float>(0.42, 0.3, 0.2) * lit))) { ui.addChild(f) }
            // 열쇠 구멍: 문 가장자리에서 18cm, 높이 1m (놋쇠 판 + 검은 구멍)
            let hx = hl - min(0.18, hl * 0.4)
            let brass = Self.gold(rough: 0.35)
            let plate = ModelEntity(mesh: .generateBox(width: 0.06, height: 0.13, depth: 0.008, cornerRadius: 0.004), materials: [brass])
            plate.position = [hx, 1.0, 0.004]
            ui.addChild(plate)
            let black = UnlitMaterial(color: UIColor(white: 0.02, alpha: 1))
            let hole = ModelEntity(mesh: .generateCylinder(height: 0.004, radius: 0.009), materials: [black])
            hole.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
            hole.position = [hx, 1.012, 0.009]
            ui.addChild(hole)
            let slot = ModelEntity(mesh: .generateBox(width: 0.008, height: 0.022, depth: 0.004), materials: [black])
            slot.position = [hx, 0.997, 0.009]
            ui.addChild(slot)
            // 그 앞에 떠서 천천히 오르내리는 황금 열쇠 + 숨 쉬는 빛. 바라보면 밝아지고, 손가락으로 집으면(누르면) 문이 열림
            let keyRoot = Entity()
            keyRoot.position = [hx, 1.0, 0.12]
            keyRoot.name = "door-\(i)"
            keyRoot.components.set(InputTargetComponent())
            keyRoot.components.set(CollisionComponent(shapes: [.generateBox(size: [0.24, 0.2, 0.16])]))
            keyRoot.components.set(HoverEffectComponent(.highlight(.init(color: UIColor(red: 1, green: 0.85, blue: 0.5, alpha: 1), strength: 2.5))))
            let key = Self.makeKey()
            keyRoot.addChild(key)
            var gm = UnlitMaterial(color: UIColor(red: 1, green: 0.84, blue: 0.5, alpha: 1))
            if let t = Tex.get("glow") {
                gm.color = .init(tint: UIColor(red: 1, green: 0.84, blue: 0.5, alpha: 1), texture: .init(t))
                if let mask = Tex.get("glow_a", raw: true) {
                    gm.blending = .transparent(opacity: .init(scale: 1, texture: .init(mask)))
                } else {
                    gm.blending = .transparent(opacity: .init(floatLiteral: 0.6))
                }
            } else {
                gm.blending = .transparent(opacity: .init(floatLiteral: 0.3))
            }
            let glow = ModelEntity(mesh: .generatePlane(width: 0.34, height: 0.34), materials: [gm])
            glow.position = [0, 0, -0.02]
            glow.components.set(OpacityComponent(opacity: 0))
            keyRoot.addChild(glow)
            ui.addChild(keyRoot)
            ui.components.set(OpacityComponent(opacity: 0))
            ui.isEnabled = false
            local.addChild(ui)
            doorUI[i] = (ui, glow, key)
        }
    }

    /// 빛을 받는 황금 (실제 방의 빛이 비쳐 반짝임)
    static func gold(rough: Float) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: UIColor(red: 1.0, green: 0.76, blue: 0.33, alpha: 1))
        m.metallic = .init(floatLiteral: 1)
        m.roughness = .init(floatLiteral: rough)
        m.emissiveColor = .init(color: UIColor(red: 1.0, green: 0.7, blue: 0.3, alpha: 1))
        m.emissiveIntensity = 0.35
        return m
    }

    /// 황금 열쇠 (가로로 누운 모양: 왼쪽 고리, 오른쪽 열쇠 이). 길이 약 15cm
    static func makeKey() -> Entity {
        let k = Entity()
        let m = gold(rough: 0.22)
        // 고리: 짧은 원기둥 14개를 둥글게
        let seg = MeshResource.generateCylinder(height: 0.016, radius: 0.0055)
        let rr: Float = 0.026
        for j in 0..<14 {
            let a = Float(j) / 14 * 2 * .pi
            let e = ModelEntity(mesh: seg, materials: [m])
            e.position = [-0.05 + cos(a) * rr, sin(a) * rr, 0]
            e.orientation = simd_quatf(angle: a, axis: [0, 0, 1])          // 원기둥(세로)이 원을 따라 눕도록
            k.addChild(e)
        }
        // 고리 가운데 장식 + 몸통
        let gem = ModelEntity(mesh: .generateSphere(radius: 0.008), materials: [m])
        gem.position = [-0.05, 0, 0]
        k.addChild(gem)
        let shaft = ModelEntity(mesh: .generateCylinder(height: 0.1, radius: 0.0055), materials: [m])
        shaft.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        shaft.position = [0.025, 0, 0]
        k.addChild(shaft)
        let collar = ModelEntity(mesh: .generateCylinder(height: 0.008, radius: 0.009), materials: [m])
        collar.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        collar.position = [-0.02, 0, 0]
        k.addChild(collar)
        // 열쇠 이 (아래로)
        for (x, h) in [(Float(0.062), Float(0.03)), (Float(0.048), Float(0.02))] {
            let bit = ModelEntity(mesh: .generateBox(width: 0.01, height: h, depth: 0.008), materials: [m])
            bit.position = [x, -h / 2, 0]
            k.addChild(bit)
        }
        return k
    }

    /// 실내 장소: 유리 지붕 틀 (1m 간격 가는 들보)
    private func addSkylightFrame(_ rects: [PRect], _ L: Layout, y: Float) {
        var g = Geo()
        for r in rects {
            var v = (r.0.y).rounded(.down) + 1
            while v < r.1.y {
                let a = L.flat(SIMD2<Float>(r.0.x, v)), b = L.flat(SIMD2<Float>(r.1.x, v))
                if r.1.x - r.0.x > 0.3 { g.wall(SIMD3<Float>(a.x, y, a.y), SIMD3<Float>(b.x, y, b.y), y0: -0.04, y1: 0.04, u0: 0, u1: 1) }
                v += 1
            }
            var u = (r.0.x).rounded(.down) + 1
            while u < r.1.x {
                let a = L.flat(SIMD2<Float>(u, r.0.y)), b = L.flat(SIMD2<Float>(u, r.1.y))
                if r.1.y - r.0.y > 0.3 { g.wall(SIMD3<Float>(a.x, y, a.y), SIMD3<Float>(b.x, y, b.y), y0: -0.04, y1: 0.04, u0: 0, u1: 1) }
                u += 1
            }
        }
        if let e = g.entity("beams", UnlitMaterial(color: Tex.color(SIMD3<Float>(0.18, 0.15, 0.12) * Worlds.safe(tint)))) {
            local.addChild(e)
        }
    }

    // MARK: 하늘 세계
    private static var skyMesh: MeshResource?

    private func addSky() {
        if Self.skyMesh == nil { Self.skyMesh = Self.skySphere(radius: 300) }
        guard let sphere = Self.skyMesh else { return }
        let name = Worlds.skyName(time: room.time, weather: room.weather)
        let base = Tex.unlit(name, tint: [1, 1, 1], folder: "sky", sampler: Tex.band)
        let bright = Tex.unlit(name, tint: [2.4, 2.4, 2.6], folder: "sky", sampler: Tex.band)
        let s = ModelEntity(mesh: sphere, materials: [base])
        s.position = center
        world.addChild(s)
        skyEntity = s; skyMat = base; flashMat = bright
    }

    private func addGround(_ dc: Decor, R: Float, floorY: Float) {
        var far = Geo()
        let farY: Float = dc.city ? floorY - 30 : floorY - 0.08
        far.disc(center: SIMD3<Float>(center.x, farY, center.z), radius: 600, tile: 50, segments: 32)
        let farCol = dc.city ? SIMD3<Float>(0.13, 0.13, 0.15) : style.groundFar
        if !dc.sea, let e = far.entity("farGround", UnlitMaterial(color: Tex.color(farCol * tint))) { world.addChild(e) }
        // 가까운 땅 (무늬): 도시는 옥상 끝까지만, 바다는 모래사장만
        let nearR: Float = dc.city ? R + 3 : (dc.sea ? R + 9 : 80)
        var near = Geo()
        near.disc(center: SIMD3<Float>(center.x, floorY - 0.03, center.z), radius: nearR, tile: style.groundTile)
        if let e = near.entity("ground", Tex.unlit(style.ground, tint: Worlds.safe(tint, min: 0.3))) { world.addChild(e) }
        if dc.sea {
            var w = Geo()
            w.disc(center: SIMD3<Float>(center.x, floorY - 0.35, center.z), radius: 420, tile: 6, segments: 48)
            if let e = w.entity("sea", Tex.unlit("water", tint: tint)) {
                world.addChild(e)
                water = e
            }
        }
    }

    private func addBands(_ dc: Decor, R: Float, floorY: Float) {
        let haze = Worlds.haze(room.time, weather: room.weather)
        let fog = ["rain", "storm", "heavysnow", "snow"].contains(room.weather)
        var g = SeededRNG(seed: UInt64(room.id * 131 + 7))
        for b in dc.bands {
            if fog && b.layer == 0 { continue }                      // 비·눈이면 먼 산은 안 보임
            let r = b.relative ? R + b.radius : b.radius
            let nightTex = dark ? b.night : nil
            let tex = nightTex ?? b.tex
            let k: SIMD3<Float>
            if nightTex != nil {
                k = SIMD3<Float>(repeating: 0.95) * (fog ? 0.8 : 1)       // 불 켜진 창은 밤에도 밝게
            } else {
                switch b.layer {
                case 0: k = haze * 1.2
                case 1: k = fog ? tint * 0.35 + haze * 0.75 : tint * 0.62 + haze * 0.45
                default: k = fog ? tint * 0.7 + haze * 0.3 : tint
                }
            }
            let reps = max(1, (2 * .pi * r / (b.height * b.aspect)).rounded())
            var geo = Geo()
            geo.ring(center: SIMD3<Float>(center.x, floorY + b.base, center.z), radius: r, y0: 0, y1: b.height,
                     repeats: reps, segments: r > 100 ? 128 : 72, phase: Float.random(in: 0...6.28, using: &g))
            if let e = geo.entity("band_\(b.tex)", Tex.cutout(tex, tint: k)) {
                layer(e, 2 + b.layer)
                world.addChild(e)
            }
        }
    }

    /// 방 둘레 바깥 d m 지점 (둘레를 t(0~1)로 한 바퀴)
    private func around(_ t: Float, _ d: Float, _ rec: SpaceRec, _ y: Float) -> SIMD3<Float> {
        let hx = halfSize.x + d, hz = halfSize.y + d
        let per = 4 * (hx + hz)
        var s = (t - t.rounded(.down)) * per
        var lu: Float = 0, lv: Float = 0
        if s < 2 * hx { lu = -hx + s; lv = -hz }
        else if s < 2 * hx + 2 * hz { s -= 2 * hx; lu = hx; lv = -hz + s }
        else if s < 4 * hx + 2 * hz { s -= 2 * hx + 2 * hz; lu = hx - s; lv = hz }
        else { s -= 4 * hx + 2 * hz; lu = -hx; lv = hz - s }
        let p = center.xz + rec.ex * lu + rec.ez * lv
        return SIMD3<Float>(p.x, y, p.y)
    }

    /// 나무·바위·텐트·건물
    private func addThings(_ dc: Decor, rec: SpaceRec, floorY: Float) {
        var g = SeededRNG(seed: UInt64(room.id * 7919 + room.place.count * 31 + 3))
        // 나무: 그림마다 그물 하나, 먼 것부터 (겹칠 때 가까운 것이 위에)
        for set in dc.trees {
            var list: [(SIMD3<Float>, Float, Float, Float)] = []
            for i in 0..<set.count {
                let p = around((Float(i) + Float.random(in: 0...0.8, using: &g)) / Float(set.count), Float.random(in: set.d, using: &g), rec, floorY - 0.1)
                let h = Float.random(in: set.h, using: &g)
                list.append((p, h, h * set.aspect * Float.random(in: 0.85...1.15, using: &g), Float.random(in: 0...3.14, using: &g)))
            }
            list.sort { simd_distance($0.0, center) > simd_distance($1.0, center) }
            var geo = Geo()
            for (p, h, w, yaw) in list { geo.crossTree(at: p, width: w, height: h, yaw: yaw) }
            if let e = geo.entity("trees_\(set.tex)", Tex.cutout(set.tex, tint: Worlds.safe(tint, min: 0.22), sampler: Tex.clamp)) {
                layer(e, 5)
                world.addChild(e)
            }
        }
        if let rk = dc.rocks {
            var geo = Geo()
            for i in 0..<rk.count {
                let p = around((Float(i) + Float.random(in: 0...0.9, using: &g)) / Float(rk.count), Float.random(in: rk.d, using: &g), rec, floorY)
                let size = Float.random(in: rk.size, using: &g)
                geo.rock(at: p, size: size, using: &g)
            }
            if let e = geo.entity("rocks", Tex.unlit(rk.tex, tint: Worlds.safe(tint * shades[1], min: 0.25))) { world.addChild(e) }
        }
        if dc.tents {
            var orange = Geo(), olive = Geo(), bulbs = Geo()
            for i in 0..<3 {
                let p = around(Float(i) / 3 + Float.random(in: 0...0.2, using: &g), Float.random(in: 3...8, using: &g), rec, floorY - 0.05)
                let yaw = Float.random(in: 0...6.28, using: &g)
                if i % 2 == 0 { orange.tent(base: p, w: 2.2, l: 2.6, h: 1.5, yaw: yaw) } else { olive.tent(base: p, w: 2.0, l: 2.4, h: 1.4, yaw: yaw) }
                bulbs.bulb(at: p + SIMD3<Float>(0, 1.0, 0) + SIMD3<Float>(sin(yaw), 0, cos(yaw)) * -1.5, r: 0.07)
            }
            if let e = orange.entity("tents", Tex.unlit("canvas", tint: SIMD3<Float>(0.95, 0.55, 0.3) * Worlds.safe(tint, min: 0.3))) { world.addChild(e) }
            if let e = olive.entity("tents2", Tex.unlit("canvas", tint: SIMD3<Float>(0.55, 0.62, 0.4) * Worlds.safe(tint, min: 0.3))) { world.addChild(e) }
            if dc.lanterns && (dark || room.time == "dusk"),
               let e = bulbs.entity("lanterns", UnlitMaterial(color: UIColor(red: 1, green: 0.78, blue: 0.45, alpha: 1))) {
                world.addChild(e)
            }
        }
        if dc.city {
            // 옥상 둘레의 빌딩 숲 (거리는 30m 아래)
            var geo = Geo()
            let R = simd_length(halfSize)
            for i in 0..<64 {
                let a = Float(i) / 64 * 2 * .pi + Float.random(in: 0...0.08, using: &g)
                let d = R + Float.random(in: 14...200, using: &g)
                let p = SIMD3<Float>(center.x + cos(a) * d, floorY - 30, center.z + sin(a) * d)
                let h = Float.random(in: 14...(d < 60 ? 70 : 150), using: &g)
                geo.box(base: p, w: Float.random(in: 10...26, using: &g), d: Float.random(in: 10...26, using: &g), h: h,
                        yaw: -angle + (i % 3 == 0 ? 0.3 : 0), tile: 12)
            }
            let face = dark ? "facade_night" : "facade"
            if let e = geo.entity("city", Tex.unlit(face, tint: dark ? SIMD3<Float>(repeating: 0.95) : tint * shades[1])) { world.addChild(e) }
        }
    }

    /// 전시관: 창이 아닌 벽에 그림을 걺 (벽 1.3m마다 한 점, 눈높이)
    private func addPaintings(_ segs: [WallSeg], _ L: Layout, floorY: Float) {
        var arts = Array(repeating: Geo(), count: 6)
        var frames = Geo()
        var k = room.id
        for s in segs where !s.window {
            let a2 = L.flat(s.a), b2 = L.flat(s.b)
            let len = simd_distance(a2, b2)
            guard len >= 1.3 else { continue }
            let dir = (b2 - a2) / len
            let n2 = L.flat(s.n) - L.flat(SIMD2<Float>(0, 0))
            let n = SIMD3<Float>(n2.x, 0, n2.y)
            let right = simd_cross(-n, SIMD3<Float>(0, 1, 0))
            let count = len >= 3.4 ? 2 : 1
            for i in 0..<count {
                let c2 = a2 + dir * (len * (Float(i) + 0.5) / Float(count))
                let w = min(1.1, len / Float(count) * 0.55), h = w * 1.25
                let c = SIMD3<Float>(c2.x, floorY + 1.5, c2.y)
                let p = c + n * 0.035, f = c + n * 0.025
                let hw = right * (w / 2), hh = SIMD3<Float>(0, h / 2, 0)
                arts[k % 6].quad(p - hw - hh, p + hw - hh, p + hw + hh, p - hw + hh,
                                 SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(1, 1), SIMD2<Float>(0, 1))
                let fw = right * (w / 2 + 0.06), fh = SIMD3<Float>(0, h / 2 + 0.06, 0)
                frames.quad(f - fw - fh, f + fw - fh, f + fw + fh, f - fw + fh, .zero, .zero, .zero, .zero)
                k += 1
            }
        }
        let lit = Worlds.safe(tint, min: 0.55)
        for i in 0..<6 {
            if let e = arts[i].entity("art\(i)", Tex.unlit("art_\(i)", tint: lit, folder: "tex", sampler: Tex.clamp)) { local.addChild(e) }
        }
        if let e = frames.entity("frames", UnlitMaterial(color: Tex.color(SIMD3<Float>(0.3, 0.22, 0.14) * lit))) { local.addChild(e) }
    }

    /// 카페: 벽 위쪽을 따라 늘어진 전구 줄
    private func addStringLights(_ segs: [WallSeg], _ L: Layout, ceilY: Float) {
        var g = Geo()
        for s in segs {
            let a2 = L.flat(s.a), b2 = L.flat(s.b)
            let len = simd_distance(a2, b2)
            guard len > 0.5 else { continue }
            let dir = (b2 - a2) / len
            let n2 = L.flat(s.n) - L.flat(SIMD2<Float>(0, 0))
            var t: Float = 0.2
            while t < len - 0.1 {
                let span = (t.truncatingRemainder(dividingBy: 1.2)) / 1.2
                let sag = 0.1 * sin(span * .pi)
                let p2 = a2 + dir * t + n2 * 0.08
                g.bulb(at: SIMD3<Float>(p2.x, ceilY - 0.2 - sag, p2.y), r: 0.028)
                t += 0.4
            }
        }
        if let e = g.entity("bulbs", UnlitMaterial(color: UIColor(red: 1, green: 0.84, blue: 0.55, alpha: 1))) { local.addChild(e) }
    }

    private func addClouds(ceilY: Float) {
        let n = Worlds.cloudCount(room.weather)
        guard n > 0 else { return }
        let dim: Float = room.weather == "storm" ? 0.45 : (["rain", "drizzle"].contains(room.weather) ? 0.7 : 1)
        let wind: Float = room.weather == "wind" || room.weather == "storm" ? 6 : 2
        let dir = simd_normalize(SIMD3<Float>(Float.random(in: -1...1), 0, Float.random(in: -1...1)) + SIMD3<Float>(0.01, 0, 0))
        let lit = Worlds.haze(room.time, weather: room.weather) * 0.4 + tint * 0.6
        for i in 0..<n {
            var m = UnlitMaterial(color: .white)
            if let t = Tex.get("cloud_\(i % 3)", folder: "sky") {
                m.color = .init(tint: Tex.color(lit * dim, alpha: 1), texture: .init(t))
            }
            m.blending = .transparent(opacity: .init(floatLiteral: 0.85))
            let e = ModelEntity(mesh: .generatePlane(width: Float.random(in: 60...130), depth: Float.random(in: 40...80)), materials: [m])
            e.orientation = simd_quatf(angle: .pi, axis: [1, 0, 0]) * simd_quatf(angle: Float.random(in: 0...(2 * .pi)), axis: [0, 1, 0])
            e.position = center + SIMD3<Float>(Float.random(in: -160...160), ceilY - center.y + Float.random(in: 55...110), Float.random(in: -160...160))
            layer(e, 1)
            world.addChild(e)
            clouds.append((e, dir * wind * Float.random(in: 0.7...1.3)))
        }
    }

    private func addWeather(_ rects: [PRect], _ L: Layout, floorY: Float, ceilY: Float) {
        let w = room.weather
        let wet = ["drizzle", "rain", "storm", "snow", "heavysnow"].contains(w)
        if wet {
            // 하늘 세계에도 (천장·벽 너머로 내려오는 게 보이게)
            let e = Self.precip(w, size: SIMD3<Float>(halfSize.x * 2 + 8, 0.1, halfSize.y * 2 + 8), height: 9)
            e.position = SIMD3<Float>(center.x, ceilY + 7, center.z)
            e.orientation = simd_quatf(angle: -angle, axis: [0, 1, 0])
            world.addChild(e)
            emitters.append(e)
        }
        guard outdoor else { return }
        for r in rects.sorted(by: { ($0.1.x - $0.0.x) * ($0.1.y - $0.0.y) > ($1.1.x - $1.0.x) * ($1.1.y - $1.0.y) }).prefix(5) {
            let c = L.flat((r.0 + r.1) / 2)
            let sx = r.1.x - r.0.x, sz = r.1.y - r.0.y
            guard sx * sz > 0.4 else { continue }
            var list: [Entity] = []
            if wet {
                let e = Self.precip(w, size: SIMD3<Float>(sx, 0.05, sz), height: room.ceil)
                e.position = SIMD3<Float>(c.x, ceilY - 0.08, c.y)
                list.append(e)
            }
            if w == "wind" {
                let e = Self.windBits(room.place, size: SIMD3<Float>(sx, 1.6, sz))
                e.position = SIMD3<Float>(c.x, floorY + 1.1, c.y)
                list.append(e)
            }
            if room.time == "night" || room.time == "dusk",
               ["camp", "forest", "valley", "village"].contains(room.place), ["clear", "cloudy", "wind"].contains(w) {
                let e = Self.fireflies(size: SIMD3<Float>(sx, 1.2, sz))
                e.position = SIMD3<Float>(c.x, floorY + 0.9, c.y)
                list.append(e)
            }
            for e in list {
                e.orientation = simd_quatf(angle: -angle, axis: [0, 1, 0])
                local.addChild(e)
                emitters.append(e)
            }
        }
    }

    /// 입자를 뿜을지 (지금 방과 이웃 방만 — 문턱을 넘을 때 이미 내리고 있게)
    func setActive(_ on: Bool) {
        for e in emitters {
            if var pe = e.components[ParticleEmitterComponent.self], pe.isEmitting != on {
                pe.isEmitting = on
                e.components.set(pe)
            }
        }
    }

    /// 매 프레임: 구름 흐름, 물결, 번개
    func tick(_ dt: Float, active: Bool) {
        guard active else { return }
        for (e, v) in clouds {
            e.position += v * dt
            let off = e.position - center
            if abs(off.x) > 180 { e.position.x = center.x - copysign(170, off.x) }
            if abs(off.z) > 180 { e.position.z = center.z - copysign(170, off.z) }
        }
        if let w = water {
            let speed: Float = room.weather == "storm" ? 0.8 : (room.weather == "wind" ? 0.5 : 0.22)
            waterOff += dt * speed
            if waterOff > 6 { waterOff -= 6 }
            w.position = SIMD3<Float>(waterOff, 0, waterOff * 0.4)
        }
        if flashLeft > 0 {
            flashLeft -= dt
            if flashLeft <= 0, let s = skyEntity, let m = skyMat { s.model?.materials = [m] }
        }
    }

    /// 번개: 하늘이 잠깐 밝아짐
    func flash() {
        guard let s = skyEntity, let f = flashMat else { return }
        s.model?.materials = [f]
        flashLeft = Float.random(in: 0.08...0.18)
    }

    // MARK: 입자
    /// 비·눈 (위에서 아래로, 바닥 근처에서 사라짐)
    static func precip(_ w: String, size: SIMD3<Float>, height: Float) -> Entity {
        let snow = w == "snow" || w == "heavysnow"
        var pe = snow ? ParticleEmitterComponent.Presets.snow : ParticleEmitterComponent.Presets.rain
        pe.emitterShape = .box
        pe.emitterShapeSize = size
        pe.birthLocation = .volume
        pe.birthDirection = .world
        pe.emissionDirection = [0, -1, 0]
        let area = max(0.5, size.x * size.z)
        let speed: Float
        switch w {
        case "drizzle": speed = 3.2; pe.mainEmitter.birthRate = 60 * area
        case "rain": speed = 5; pe.mainEmitter.birthRate = 160 * area
        case "storm": speed = 7; pe.mainEmitter.birthRate = 320 * area
        case "heavysnow": speed = 0.55; pe.mainEmitter.birthRate = 45 * area; pe.mainEmitter.size = 0.022
        default: speed = 0.75; pe.mainEmitter.birthRate = 22 * area; pe.mainEmitter.size = 0.012
        }
        pe.speed = speed
        pe.speedVariation = speed * 0.15
        pe.mainEmitter.acceleration = [0, 0, 0]
        pe.mainEmitter.lifeSpan = Double(max(0.4, (height - 0.05) / speed))
        pe.mainEmitter.lifeSpanVariation = 0.05
        if snow { pe.mainEmitter.sizeMultiplierAtEndOfLifespan = 1 }
        let e = Entity()
        e.components.set(pe)
        return e
    }

    /// 바람: 나뭇잎(자연)이나 먼지(도시·바다)가 옆으로 날림
    static func windBits(_ place: String, size: SIMD3<Float>) -> Entity {
        var pe = ParticleEmitterComponent()
        pe.emitterShape = .box
        pe.emitterShapeSize = size
        pe.birthLocation = .volume
        pe.birthDirection = .world
        pe.emissionDirection = simd_normalize(SIMD3<Float>(1, 0.1, 0.35))
        pe.speed = 1.3
        pe.speedVariation = 0.5
        let nature = ["camp", "forest", "valley", "village"].contains(place)
        pe.mainEmitter.birthRate = nature ? 7 : 14
        pe.mainEmitter.lifeSpan = 3.5
        pe.mainEmitter.size = nature ? 0.022 : 0.006
        pe.mainEmitter.sizeVariation = nature ? 0.008 : 0.003
        pe.mainEmitter.acceleration = [0, -0.12, 0]
        pe.mainEmitter.sizeMultiplierAtEndOfLifespan = 1
        pe.mainEmitter.angularSpeed = nature ? 2.5 : 0
        pe.mainEmitter.angularSpeedVariation = nature ? 2 : 0
        pe.mainEmitter.color = .constant(.single(nature ? UIColor(red: 0.62, green: 0.48, blue: 0.22, alpha: 1)
                                                        : UIColor(red: 0.85, green: 0.82, blue: 0.75, alpha: 0.6)))
        pe.mainEmitter.opacityCurve = .gradualFadeInOut
        let e = Entity()
        e.components.set(pe)
        return e
    }

    /// 반딧불 (밤·해질녘의 자연)
    static func fireflies(size: SIMD3<Float>) -> Entity {
        var pe = ParticleEmitterComponent()
        pe.emitterShape = .box
        pe.emitterShapeSize = size
        pe.birthLocation = .volume
        pe.speed = 0.06
        pe.speedVariation = 0.05
        pe.mainEmitter.birthRate = max(2, size.x * size.z * 0.4)
        pe.mainEmitter.lifeSpan = 4
        pe.mainEmitter.size = 0.012
        pe.mainEmitter.sizeMultiplierAtEndOfLifespan = 1
        pe.mainEmitter.noiseStrength = 0.12
        pe.mainEmitter.noiseScale = 1
        pe.mainEmitter.noiseAnimationSpeed = 0.3
        pe.mainEmitter.color = .constant(.single(UIColor(red: 0.85, green: 1, blue: 0.45, alpha: 1)))
        pe.mainEmitter.blendMode = .additive
        pe.mainEmitter.opacityCurve = .gradualFadeInOut
        let e = Entity()
        e.components.set(pe)
        return e
    }

    // MARK: 그물 만들기
    /// 방 칸 직사각형들로 평평한 판 (위아래 양면, 무늬는 저장 좌표 기준으로 tile m마다 반복)
    static func flatMesh(_ rects: [PRect], _ L: Layout, y: Float, tile: Float) -> MeshResource? {
        guard !rects.isEmpty else { return nil }
        var g = Geo()
        for r in rects {
            let c = [L.flat(r.0), L.flat(SIMD2<Float>(r.1.x, r.0.y)), L.flat(r.1), L.flat(SIMD2<Float>(r.0.x, r.1.y))]
            let p = c.map { SIMD3<Float>($0.x, y, $0.y) }
            let u = c.map { $0 / tile }
            g.quad(p[0], p[1], p[2], p[3], u[0], u[1], u[2], u[3])
        }
        return g.mesh("flat")
    }

    /// 안쪽에서 보는 하늘 구. 그림은 위 절반(꼭대기→지평선)만 있고, 지평선 아래는 위를 거울처럼 씀
    static func skySphere(radius: Float) -> MeshResource? {
        let seg = 64, rings = 32
        var g = Geo()
        for r in 0...rings {
            let el = Float.pi / 2 - Float.pi * Float(r) / Float(rings)
            for s in 0...seg {
                let az = 2 * Float.pi * Float(s) / Float(seg)
                g.pos.append(radius * SIMD3<Float>(cos(el) * cos(az), sin(el), cos(el) * sin(az)))
                g.uv.append(SIMD2<Float>(Float(s) / Float(seg), abs(el) / (Float.pi / 2)))
            }
        }
        for r in 0..<rings {
            for s in 0..<seg {
                let a = UInt32(r * (seg + 1) + s), b = a + UInt32(seg + 1)
                g.idx += [a, b, a + 1, a + 1, b, b + 1]          // 안쪽 면
                g.idx += [a, a + 1, b, a + 1, b + 1, b]          // 바깥 면 (방향이 뒤집혀도 보이게)
            }
        }
        return g.mesh("sky")
    }
}
