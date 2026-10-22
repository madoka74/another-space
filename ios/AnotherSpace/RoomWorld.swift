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
            d.bands = [Band(tex: "pano_hills", radius: 270, height: 68, base: -7, aspect: 0, layer: 0),
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
            d.bands = [Band(tex: "pano_peaks", radius: 270, height: 92, base: -6, aspect: 0, layer: 0),
                       Band(tex: "mid_cliffs", radius: 40, relative: true, height: 48, base: -2, aspect: 2, layer: 2)]
            d.trees = [Trees(tex: "tree_pine", count: 6, h: 6...11, d: 4...22)]
            d.rocks = Rocks(tex: "rock", count: 16, size: 0.6...3, d: 1...24)
        case "sea":
            d.bands = [Band(tex: "far_islands", radius: 280, height: 16, base: -1.5, aspect: 8, layer: 0)]
            d.trees = [Trees(tex: "tree_twisted", count: 5, h: 6...10, d: 1.5...6)]
            d.rocks = Rocks(tex: "basalt", count: 8, size: 0.5...2.2, d: 5...26)
            d.sea = true
        case "village":
            d.bands = [Band(tex: "pano_hills", radius: 270, height: 68, base: -7, aspect: 0, layer: 0),
                       Band(tex: "mid_village", night: "mid_village_night", radius: 100, height: 36, base: -4, aspect: 4, layer: 1)]
            d.trees = [Trees(tex: "tree_broad", count: 8, h: 7...12, d: 4...25)]
        case "city":
            d.bands = [Band(tex: "far_city", night: "far_city_night", radius: 260, height: 160, base: -30, aspect: 2, layer: 1)]
            d.city = true
        case "cafe":
            // 창밖: 길 건너 가게들이 늘어선 거리 (1층은 차양 달린 가게), 그 뒤로 먼 도시
            d.bands = [Band(tex: "street_shops", night: "street_shops_night", radius: 9, relative: true, height: 9, base: -0.3, aspect: 4, layer: 2),
                       Band(tex: "far_city", night: "far_city_night", radius: 70, relative: true, height: 90, base: -2, aspect: 2, layer: 1)]
        case "gallery":
            d.bands = [Band(tex: "pano_hills", radius: 270, height: 68, base: -7, aspect: 0, layer: 0)]
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

/// 다른 세계로 이어진 문: 나무 양문 + 문틀 + 가운데 열쇠 구멍 + 그 앞에 떠 있는 황금 열쇠.
/// 열면 열쇠가 구멍에 들어가 돌고, 두 문짝이 양옆 벽 속으로 밀려 들어가며 사라짐
struct DoorView {
    let root: Entity
    let left: Entity            // 왼쪽 문짝 (왼쪽 문설주에 붙어 있음 — x 크기를 줄이면 벽 쪽으로 들어감)
    let right: Entity
    let lock: Entity            // 열쇠 구멍 장식
    let keyRoot: Entity         // 누르는 곳 (열쇠가 구멍으로 들어가는 움직임)
    let key: Entity             // 둥실둥실
    let parts: [ModelEntity]    // 열쇠 조각들 (숨 쉬는 빛)
    let hl: Float               // 문 반폭
    static let keyZ: Float = 0.2
    static let keyY: Float = 1.4
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
    // 계곡 개울·폭포
    private var riverPts: [SIMD3<Float>] = []
    private var riverW: [Float] = []
    private var flows: [(ModelEntity, UnlitMaterial, Float, Float)] = []     // 물 면, 재질, 속도(무늬/초), 지금 어긋남
    /// 개울에서 방과 가장 가까운 곳 (물소리 자리, 저장 좌표)
    private(set) var riverNear: SIMD3<Float>?
    /// 폭포 (물소리 자리)
    private(set) var fallSpot: SIMD3<Float>?
    private var emitters: [Entity] = []          // 하늘 세계 쪽 비·눈 (그 방 포털 너머로만 보임)
    private var roomEmitters: [Entity] = []      // 방 안 비·눈·바람·반딧불 (실제 공간이라 어디서든 보임 → 지금 방만 켬)
    private var flashLeft: Float = 0
    private var water: ModelEntity?
    private var waterOff: Float = 0
    private(set) var center = SIMD3<Float>(0, 0, 0)         // 방 가운데 바닥 (저장 좌표)
    private(set) var halfSize = SIMD2<Float>(1, 1)           // 방 반 크기 (격자 방향, m)
    let angle: Float
    private let sortGroup = ModelSortGroup(depthPass: nil)
    /// 문 번호 → 이 방 쪽 문짝 (닫히면 이 방 벽처럼 보임). 열 때 가로로 오므라듦
    private(set) var doorPanels: [Int: [Entity]] = [:]
    /// 문 번호 → 1m 안으로 다가가면 보이는 마법의 양문 (이 방 쪽)
    private(set) var doorView: [Int: DoorView] = [:]
    /// 문 번호 → 실제 문이 닫혀 있을 때 보이는 문짝 (방 A 쪽 세계에만)
    private(set) var doorLeaf: [Int: Entity] = [:]

    var outdoor: Bool { style.open }
    var dark: Bool { room.time == "night" || room.time == "dawn" }
    /// 표시 방식 (컬러·흑백·선 그림)
    let look: LookMode
    private var lineMode: Bool { look == .line }

    typealias PRect = (SIMD2<Float>, SIMD2<Float>)

    /// 평면 좌표 10cm 칸 키 (전시관 그림 자리 고르기 — Vox.planeCell 과 같음)
    nonisolated static func clutterKey(_ p: SIMD2<Float>) -> Int64 {
        (Int64((p.x / 0.1).rounded(.down)) + 100_000) << 20 | (Int64((p.y / 0.1).rounded(.down)) + 100_000)
    }

    /// 장소마다 움직이는 것들 (새·배·자동차·사람·연기…)과 실내 꾸밈
    private var scenery: Scenery?

    /// 가구 기둥이 있는 10cm 칸 (벽난로·선반·메뉴판을 가구 없는 벽에 두려고)
    private let blocked: Set<Int64>

    init(_ d: SpaceData, _ r: RoomRec, layout: Layout, blocked: Set<Int64> = []) {
        self.blocked = blocked
        room = r
        look = r.lookMode
        style = Worlds.style(r.place, time: r.time)
        angle = d.rec.angle
        tint = Worlds.timeTint(r.time, indoor: Worlds.indoor(r.place)) * Worlds.weatherDim(r.weather)
        shades = Worlds.contrast(r.time, weather: r.weather)
        world.components.set(WorldComponent())
        Tex.with(look) { build(d, layout) }
    }

    /// 벽 꾸밈 앞에 새로 가구가 보이면 다른 빈 벽으로 옮김
    func recheckDecor(blocked: Set<Int64>) {
        scenery?.relocate(blocked: blocked)
        creek?.refresh(blocked: blocked)          // 계곡 물: 새로 알게 된 가구 자리는 비우고 다시 그림
    }

    /// 선 그림이면 검은 선, 아니면 그 색 (창틀·들보·액자·전구 등)
    private func ink(_ c: SIMD3<Float>) -> UnlitMaterial {
        if lineMode { return Ink.line }
        return Tex.with(look) { UnlitMaterial(color: Tex.color(c)) }
    }

    /// 선 그림: 사각형 테두리 (x0~x1, y0~y1, 앞으로 z)
    private func rectLines(_ g: inout Geo, _ x0: Float, _ x1: Float, _ y0: Float, _ y1: Float, z: Float, w: Float = 0.012) {
        let a = SIMD3<Float>(x0, y0, z), b = SIMD3<Float>(x1, y0, z), c = SIMD3<Float>(x1, y1, z), d = SIMD3<Float>(x0, y1, z)
        g.stroke(a, b, width: w); g.stroke(b, c, width: w); g.stroke(c, d, width: w); g.stroke(d, a, width: w)
    }

    /// 가구·물건 블록 재질 (그늘 0~2)
    func propMaterial(_ shade: Int) -> RealityKit.Material {
        if lineMode { return Ink.paper(shade) }
        let k = shades[min(2, max(0, shade))]
        return Tex.with(look) { Tex.unlit(style.prop, tint: Worlds.safe(style.propTint * tint * k * 1.15, min: 0.4)) }
    }

    /// 이 방을 그리는 데 필요한 그림 (미리 읽어 두기용)
    static func textures(_ r: RoomRec) -> [(String, String)] {
        let st = Worlds.style(r.place, time: r.time)
        let dc = Decor.of(r.place)
        let night = r.time == "night" || r.time == "dawn"
        var l: [(String, String)] = [(Worlds.skyName(time: r.time, weather: r.weather), "sky"), (st.floor, "tex"), (st.prop, "tex"), (st.ground, "tex")]
        l.append((st.open ? st.barrier : st.wall, "tex"))
        for b in dc.bands { l.append(((night ? b.night : nil) ?? b.tex, "tex")) }
        for t in dc.trees { l.append((t.tex == "tree_pine" ? "pine_branch" : (t.tex == "tree_twisted" ? "palm_frond" : "leaf_clump"), "tex")) }
        if !dc.trees.isEmpty { l.append(("bark", "tex")) }
        if let rk = dc.rocks { l.append((rk.tex, "tex")) }
        if dc.tents { l.append(("canvas", "tex")) }
        if dc.sea { l.append(("water", "tex")) }
        if dc.city { l.append((night ? "facade_night" : "facade", "tex")) }
        if dc.paintings { for i in 0..<6 { l.append(("art_\(i)", "tex")) } }
        if r.place == "valley" { l += [("river", "tex"), ("river_hi", "tex"), ("fall", "tex"), ("pebble", "tex"), ("rock", "tex"), ("cliff", "tex"), ("ripple", "tex")] }
        if r.place == "valley" { for i in 0..<6 { l.append(("fish_\(i)", "tex")) } }
        if r.place == "sea" { l += [("jelly_bell", "tex"), ("jelly_tent", "tex"), ("jelly_arm", "tex"), ("glow", "tex"), ("spark_dot", "tex")] }
        if r.place == "city" { for i in 0..<16 { l += [(String(format: "neon_%02da", i), "tex"), (String(format: "neon_%02db", i), "tex")] } }
        if Worlds.cloudCount(r.weather) > 0 { for i in 0..<6 { l.append(("cloud_\(i)", "sky")) } }
        return l
    }

    private func layer(_ e: Entity, _ order: Int) {
        e.components.set(ModelSortGroupComponent(group: sortGroup, order: Int32(order)))
    }

    /// 안의 모든 그림에 그리는 순서를 줌. 반투명(깊이를 쓰지 않는) 것은 나무·바위·건물보다 나중에(큰 순서) 그려야
    /// 앞에 있을 땐 그 위에, 뒤에 있을 땐 그 뒤로 자연스럽게 보임 (먼저 그리면 뒤의 나무가 덮어써서 네모나게 깨져 보였음)
    private func layerAll(_ e: Entity, _ order: Int) {
        if e is ModelEntity { layer(e, order) }
        for c in e.children { layerAll(c, order) }
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
            let e = ModelEntity(mesh: m, materials: [Tex.unlit(style.floor, tint: Worlds.safe(tint, min: 0.4))])
            local.addChild(e)
            tinted.append((e, style.floor, Worlds.safe(tint, min: 0.4), true))
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
            if room.place == "cafe" { addCafeCeiling(rects, L, y: ceilY - 0.03) } else { addSkylightFrame(rects, L, y: ceilY - 0.06) }
        }
        addDoors(L, floorY: floorY, ceilY: ceilY)

        let dc = Decor.of(room.place)
        addSky()
        addGround(dc, R: R, floorY: floorY)
        addBands(dc, R: R, floorY: floorY)
        addThings(dc, rec: rec, L, floorY: floorY)
        addFeature(L, segs: segs, floorY: floorY, ceilY: ceilY)
        if dc.paintings {
            paintSegs = segs.filter { !$0.window }
            paintLayout = L
            paintFloor = floorY
            local.addChild(paintRoot)
        }
        if dc.stringLights { addStringLights(segs, L, ceilY: ceilY) }
        addClouds(ceilY: ceilY)                      // 선 그림이면 구름 윤곽선 그림(cloud_n_ln)으로
        addWeather(rects, L, floorY: floorY, ceilY: ceilY)
        if lineMode { addOutlines(segs, L, floorY: floorY, ceilY: ceilY) }
        let sc = Scenery(room: room, look: look, tint: tint, center: center, halfSize: halfSize, angle: angle,
                         floorY: floorY, ceilY: ceilY, segs: segs, layout: L, sortGroup: sortGroup, blocked: blocked)
        world.addChild(sc.far)
        local.addChild(sc.near)
        scenery = sc
        setActive(sky: false, room: false)
    }

    // MARK: 선 그림
    /// 선 그림: 방의 꺾이는 곳만 검은 선으로 — 바닥·천장과 벽이 만나는 줄, 벽 모서리(방향이 바뀌거나 벽이 끝나는 곳), 창 테두리, 문 위 가로대
    private func addOutlines(_ segs: [WallSeg], _ L: Layout, floorY: Float, ceilY: Float) {
        var g = Geo()
        let w: Float = 0.014
        let off = w / 2 + 0.005                 // 선을 벽·바닥·천장에서 방 안쪽으로 띄움 — 면과 겹쳐 깜빡이거나 옆방 벽에 비쳐 보이지 않게
        let top = ceilY - floorY
        func p3(_ p: SIMD2<Float>, _ y: Float) -> SIMD3<Float> { let f = L.flat(p); return SIMD3<Float>(f.x, floorY + y, f.y) }
        for s in segs {
            let len = simd_distance(s.a, s.b)
            guard len > 0.01 else { continue }
            let dir = (s.b - s.a) / len
            let inA = s.a + s.n * off, inB = s.b + s.n * off
            g.stroke(p3(inA, off + 0.006), p3(inB, off + 0.006), width: w)
            g.stroke(p3(inA, top - 0.02 - off), p3(inB, top - 0.02 - off), width: w)
            if s.window && top > 1.6 {
                let w0: Float = 0.85, w1 = min(2.15, top - 0.15)
                g.stroke(p3(inA, w0), p3(inB, w0), width: w)
                g.stroke(p3(inA, w1), p3(inB, w1), width: w)
                g.stroke(p3(inA + dir * off, w0), p3(inA + dir * off, w1), width: w)
                g.stroke(p3(inB - dir * off, w0), p3(inB - dir * off, w1), width: w)
            }
            // 끝점: 같은 방향으로 이어지는 벽이 없으면 모서리(세로선) — 방 안쪽·벽 안쪽으로 띄워 세움
            for (e, other, toward) in [(s.a, s.b, dir), (s.b, s.a, -dir)] {
                let cont = segs.contains { o in
                    o.n == s.n && (simd_distance(o.a, e) < 0.01 || simd_distance(o.b, e) < 0.01)
                        && simd_distance(o.a, other) > 0.01 && simd_distance(o.b, other) > 0.01
                }
                if !cont {
                    let q = e + s.n * off + toward * off
                    g.stroke(p3(q, 0), p3(q, top), width: w)
                }
            }
        }
        for ds in L.doors where (ds.roomA == room.id || ds.roomB == room.id) && !ds.single {
            let (ea, eb, en) = ds.edge(for: room.id)
            let dh = min(2.05, top - 0.05)
            if ds.width <= 1.6 { g.stroke(p3(ea + en * off, dh), p3(eb + en * off, dh), width: w) }
        }
        if let e = g.entity("outline", Ink.line) { local.addChild(e) }
    }

    // MARK: 벽
    /// 바깥 장소: 벽 자리 전체가 하늘 세계로 열린 창. 그 너머 22cm에 울타리·덤불·바위·난간을 둘러 세워 '막힌 곳'으로 보이게 (안전)
    private func openWalls(_ segs: [WallSeg], _ L: Layout, floorY: Float, ceilY: Float) {
        var portal = Geo(), fence = Geo()
        let tileW = style.barrierH * 2                       // 그림 가로:세로 = 2:1
        // 문 자리 양끝 점: 여기서 끝나는 울타리는 늘리지 않음 (문 자리 너머로 덤불이 삐져나오지 않게)
        var doorEnds: [SIMD2<Float>] = []
        for ds in L.doors where ds.roomA == room.id || ds.roomB == room.id {
            let (ea, eb, _) = ds.edge(for: room.id)
            doorEnds += [ea, eb]
        }
        func nearDoor(_ p: SIMD2<Float>) -> Bool { doorEnds.contains { simd_distance($0, p) < 0.08 } }
        for s in segs {
            let a2 = L.flat(s.a), b2 = L.flat(s.b)
            let a = SIMD3<Float>(a2.x, floorY, a2.y), b = SIMD3<Float>(b2.x, floorY, b2.y)
            let len = simd_distance(a2, b2)
            guard len > 0.01 else { continue }
            let n = L.flat(s.n) - L.flat(SIMD2<Float>(0, 0))           // 방 안쪽
            portal.face(a, b, toward: SIMD3<Float>(n.x, 0, n.y), y0: 0, y1: ceilY - floorY, u0: 0, u1: 1)
            // 울타리는 '아무도 걸을 수 없는 곳'에만. 포털 너머 세계의 물건은 포털 앞(방 안)에 있어도 포털을 통해 그려지므로,
            // 걸을 수 있는 곳(이 방·다른 방·문 자리)에 놓이면 복도 한가운데 덤불처럼 보임.
            // 방과 방 사이 벽: 뒤가 옆방이라 3cm 뒤에 바짝 (늘리지 않음). 바깥 벽: 22cm 뒤, 걸을 수 없는 칸만, 모서리 쪽으로 25cm까지
            let along0 = abs(s.a.x - s.b.x) > abs(s.a.y - s.b.y) ? min(s.a.x, s.b.x) : min(s.a.y, s.b.y)
            let pd = (s.b - s.a) / max(1e-4, simd_distance(s.a, s.b))      // 평면 좌표 방향
            let off: Float = s.inner ? 0.03 : 0.22
            let ext: Float = s.inner ? 0 : 0.25
            let step: Float = 0.05
            func clear(_ t: Float) -> Bool {
                if s.inner { return t >= 0 && t <= len }
                let q = s.a + pd * t - s.n * off
                if L.walkable(q) || L.walkable(q + s.n * 0.08) || L.walkable(q - s.n * 0.08) { return false }
                if (t < 0 && nearDoor(s.a)) || (t > len && nearDoor(s.b)) { return false }
                return true
            }
            var t0: Float? = nil
            var t = -ext
            while t < len + ext + 1e-4 {
                let t1 = min(t + step, len + ext)
                let ok = t1 - t > 1e-4 && clear((t + t1) / 2)
                if ok, t0 == nil { t0 = t }
                if (!ok || t1 >= len + ext - 1e-4), let st = t0 {
                    let en = ok ? t1 : t
                    if en - st > 0.04 {
                        let fa = s.a + pd * st - s.n * off, fb = s.a + pd * en - s.n * off
                        let wa = L.flat(fa), wb = L.flat(fb)
                        fence.wall(SIMD3<Float>(wa.x, floorY, wa.y), SIMD3<Float>(wb.x, floorY, wb.y), y0: -0.05, y1: style.barrierH,
                                   u0: (along0 + st) / tileW, u1: (along0 + en) / tileW, v0: 0.02, v1: 1)
                    }
                    t0 = nil
                }
                t = t1
                if t1 >= len + ext - 1e-4 { break }
            }
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
                let n3 = SIMD3<Float>(nw.x, 0, nw.y)
                parts[k].face(a, b, toward: n3, y0: 0, y1: w0, u0: u0, u1: u1, v0: 0, v1: w0 / tile)
                parts[k].face(a, b, toward: n3, y0: w1, y1: top, u0: u0, u1: u1, v0: w1 / tile, v1: top / tile)
                win.face(a, b, toward: n3, y0: w0, y1: w1, u0: 0, u1: 1)
                let inn = SIMD3<Float>(nw.x, 0, nw.y) * 0.02
                for y in [w0, w1] {
                    frame.wall(a + inn, b + inn, y0: y - 0.03, y1: y + 0.03, u0: 0, u1: 1)
                }
            } else {
                parts[k].face(a, b, toward: SIMD3<Float>(nw.x, 0, nw.y), y0: 0, y1: top, u0: u0, u1: u1, v0: 0, v1: top / tile)
            }
        }
        for k in 0..<3 {
            let tk = Worlds.safe(tint * shades[k], min: 0.36)
            if let e = parts[k].entity("wall\(k)", Tex.unlit(style.wall, tint: tk)) {
                local.addChild(e)
                tinted.append((e, style.wall, tk, false))
            }
        }
        if let m = win.mesh("window") {
            let p = ModelEntity(mesh: m, materials: [PortalMaterial()])
            p.components.set(PortalComponent(target: world))
            local.addChild(p)
            if let f = frame.entity("frame", ink(SIMD3<Float>(0.24, 0.2, 0.17) * Worlds.safe(tint))) {
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
            let (ea, eb, en) = ds.edge(for: room.id)                 // 이 방 쪽 입구 변
            let a2 = L.flat(ea), b2 = L.flat(eb)
            let len = simd_distance(a2, b2)
            guard len > 0.2 else { continue }
            let dir = (b2 - a2) / len
            let nw = L.flat(en) - L.flat(SIMD2<Float>(0, 0))        // 이 방 쪽
            // 문짝의 앞면(+z)이 이 방을 보게: x축 = 입구 변 방향, z축 = 방 쪽
            var xdir = SIMD3<Float>(dir.x, 0, dir.y)
            let zdir = SIMD3<Float>(nw.x, 0, nw.y)
            if simd_dot(simd_cross(xdir, SIMD3<Float>(0, 1, 0)), zdir) < 0 { xdir = -xdir }
            let yaw = atan2(-xdir.z, xdir.x)
            let q = simd_quatf(angle: yaw, axis: [0, 1, 0])
            let mid = (a2 + b2) / 2
            func place(_ e: Entity, _ off: Float) {
                let p = mid + nw * off
                e.position = SIMD3<Float>(p.x, floorY, p.y)
                e.orientation = q
            }
            let hl = len / 2
            let dh = min(2.05, top - 0.05)                           // 문 높이
            // 문 위 벽(상인방): 폭 1.6m 이하인 문은 실제 문처럼 문 위가 늘 벽. 그보다 넓은 통로는 천장까지 트임
            let header = len <= 1.6
            let low: Float = header ? dh : top
            // 한 방 안의 문(방을 나누지 않은 실제 문 자리)은 늘 열린 통로 — 실제 문이 닫혔을 때의 문짝만 만듦
            if !ds.single {
                var list: [Entity] = []
                // 닫혀 있을 때 = 이 방의 벽 (바깥 장소는 풍경으로 열린 벽, 실내는 그 방 벽). 이 방 쪽에서만 보이는 한쪽 면,
                // 폭은 양옆 벽 끝과 정확히 같게. 문 자리는 실제로 지나갈 수 있는 곳이라 울타리는 세우지 않음
                let front = SIMD3<Float>(0, 0, 1)
                let pa = SIMD3<Float>(-hl, 0, 0), pb = SIMD3<Float>(hl, 0, 0)
                if style.open {
                    var panel = Geo()
                    panel.face(pa, pb, toward: front, y0: 0, y1: low, u0: 0, u1: 1)
                    if let m = panel.mesh("door\(i)") {
                        let e = ModelEntity(mesh: m, materials: [PortalMaterial()])
                        e.components.set(PortalComponent(target: world))
                        place(e, 0)
                        local.addChild(e)
                        list.append(e)
                    }
                    if header {
                        var hd = Geo()
                        hd.face(pa, pb, toward: front, y0: dh, y1: top, u0: 0, u1: 1)
                        if let m = hd.mesh("header\(i)") {
                            let e = ModelEntity(mesh: m, materials: [PortalMaterial()])
                            e.components.set(PortalComponent(target: world))
                            place(e, 0)
                            local.addChild(e)
                        }
                    }
                } else {
                    let l = simd_dot(zdir, sun)
                    let k = l > 0.25 ? 0 : (l > -0.25 ? 1 : 2)
                    let tile = style.wallTile
                    let mat = Tex.unlit(style.wall, tint: Worlds.safe(tint * shades[k], min: 0.36))
                    var panel = Geo()
                    panel.face(pa, pb, toward: front, y0: 0, y1: low, u0: 0, u1: len / tile, v0: 0, v1: low / tile)
                    if let e = panel.entity("door\(i)", mat) {
                        place(e, 0)
                        local.addChild(e)
                        list.append(e)
                    }
                    if header {
                        var hd = Geo()
                        hd.face(pa, pb, toward: front, y0: dh, y1: top, u0: 0, u1: len / tile, v0: dh / tile, v1: top / tile)
                        if let e = hd.entity("header\(i)", mat) {
                            place(e, 0)
                            local.addChild(e)
                        }
                    }
                }
                doorPanels[i] = list

                // ── 마법의 양문 (처음엔 숨김). 모두 이 방 쪽 앞면(+z)
                let ui = Entity()
                place(ui, 0.02)
                let lit = Worlds.safe(tint, min: 0.6)
                let woodDark = Tex.unlit("planks_dark", tint: lit, folder: "tex", sampler: Tex.clamp)
                let woodLight = Tex.unlit("planks", tint: lit * 0.95, folder: "tex", sampler: Tex.clamp)
                let gold = Self.gold(rough: 0.3)
                // 문틀: 양옆 기둥 + 위 가로대 (벽에 4cm 걸치게)
                let fw: Float = 0.09
                for x in [-hl - fw / 2 + 0.04, hl + fw / 2 - 0.04] {
                    let post = ModelEntity(mesh: .generateBox(width: fw, height: dh + fw, depth: 0.06), materials: [woodDark])
                    post.position = [x, (dh + fw) / 2, 0.03]
                    ui.addChild(post)
                }
                let lintel = ModelEntity(mesh: .generateBox(width: len + 2 * fw - 0.08, height: fw, depth: 0.07), materials: [woodDark])
                lintel.position = [0, dh + fw / 2, 0.035]
                ui.addChild(lintel)
                if lineMode {
                    var lg = Geo()
                    rectLines(&lg, -hl - fw + 0.04, hl + fw - 0.04, 0.005, dh + fw, z: 0.072)
                    if let le = lg.entity("frameLines", Ink.line) { ui.addChild(le) }
                }
                // 문짝 두 장: 바깥 문설주에 붙여 두고(엔티티 원점 = 문설주), 안쪽으로 펼쳐짐
                let lw = hl + 0.012                                           // 가운데에서 서로 겹쳐 틈이 없게
                func leaf(_ sign: Float) -> Entity {
                    let e = Entity()
                    e.position = [sign * hl, 0, 0]
                    let cx = -sign * lw / 2                                       // 문설주에서 안쪽으로
                    let slab = ModelEntity(mesh: .generateBox(width: lw, height: dh - 0.01, depth: 0.035), materials: [woodDark])
                    slab.position = [cx, (dh - 0.01) / 2, sign > 0 ? 0.024 : 0.02]          // 오른쪽 문짝이 4mm 앞 (겹친 곳이 깜빡이지 않게)
                    e.addChild(slab)
                    if lineMode {
                        var lg = Geo()
                        rectLines(&lg, min(0, 2 * cx), max(0, 2 * cx), 0.005, dh - 0.01, z: 0.045)
                        for (y0, h) in [(Float(0.12), dh * 0.36), (dh * 0.55, dh * 0.36)] {
                            rectLines(&lg, cx - lw * 0.35, cx + lw * 0.35, y0, y0 + h, z: 0.05, w: 0.009)
                        }
                        if let le = lg.entity("leafLines", Ink.line) { e.addChild(le) }
                    }
                    // 위아래 두 칸 판넬 (도드라진 면) + 금빛 테
                    for (y0, h) in [(Float(0.12), dh * 0.36), (dh * 0.55, dh * 0.36)] {
                        let pw = lw * 0.7
                        let panel = ModelEntity(mesh: .generateBox(width: pw, height: h, depth: 0.012), materials: [woodLight])
                        panel.position = [cx, y0 + h / 2, 0.042]
                        e.addChild(panel)
                        for (dx, dy, w, hh) in [(Float(0), h / 2 + 0.008, pw + 0.016, Float(0.008)), (Float(0), -h / 2 - 0.008, pw + 0.016, Float(0.008)),
                                                (pw / 2 + 0.008, Float(0), Float(0.008), h), (-pw / 2 - 0.008, Float(0), Float(0.008), h)] {
                            let trim = ModelEntity(mesh: .generateBox(width: w, height: hh, depth: 0.006), materials: [gold])
                            trim.position = [cx + dx, y0 + h / 2 + dy, 0.04]
                            e.addChild(trim)
                        }
                    }
                    return e
                }
                let left = leaf(-1), right = leaf(1)
                ui.addChild(left); ui.addChild(right)
                // 가운데 열쇠 구멍 (높이 1.4m — 아래를 내려다볼 때 뜨는 안내판과 겹치지 않게)
                let lock = Entity()
                lock.position = [0, DoorView.keyY, 0.045]
                let rosette = ModelEntity(mesh: .generateCylinder(height: 0.006, radius: 0.034), materials: [gold])
                rosette.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
                lock.addChild(rosette)
                let black = UnlitMaterial(color: UIColor(white: 0.02, alpha: 1))
                let hole = ModelEntity(mesh: .generateCylinder(height: 0.002, radius: 0.008), materials: [black])
                hole.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
                hole.position = [0, 0.007, 0.0038]
                lock.addChild(hole)
                let slot = ModelEntity(mesh: .generateBox(width: 0.007, height: 0.02, depth: 0.002), materials: [black])
                slot.position = [0, -0.006, 0.0038]
                lock.addChild(slot)
                ui.addChild(lock)
                // 열쇠: 구멍 앞에 떠서 둥실둥실, 숨 쉬듯 빛남. 손가락으로 집으면(누르면) 열림
                let keyRoot = Entity()
                keyRoot.position = [0, DoorView.keyY, DoorView.keyZ]
                keyRoot.name = "door-\(i)"
                keyRoot.components.set(InputTargetComponent())
                keyRoot.components.set(CollisionComponent(shapes: [.generateBox(size: [0.24, 0.16, 0.14])]))
                keyRoot.components.set(HoverEffectComponent(.highlight(.init(color: UIColor(red: 1, green: 0.85, blue: 0.5, alpha: 1), strength: 2.5))))
                let (key, parts) = Self.makeKey()
                keyRoot.addChild(key)
                ui.addChild(keyRoot)
                ui.components.set(OpacityComponent(opacity: 0))
                ui.isEnabled = false
                local.addChild(ui)
                doorView[i] = DoorView(root: ui, left: left, right: right, lock: lock, keyRoot: keyRoot, key: key, parts: parts, hl: hl)
            }

            // 실제 문이 닫혀 있을 때(비전프로가 '문'으로 알아본 면이 문 자리를 막을 때)만 보이는 실제 문짝 (방 A 세계가 하나만 만듦)
            if room.id == ds.roomA {
                let c2 = L.flat(ds.mid)                                   // 두 입구 줄 사이 가운데
                let lit = Worlds.safe(tint, min: 0.6)
                let woodLight = Tex.unlit("planks", tint: lit * 0.95, folder: "tex", sampler: Tex.clamp)
                let gold = Self.gold(rough: 0.3)
                let real = Entity()
                real.position = SIMD3<Float>(c2.x, floorY, c2.y)
                real.orientation = q
                let slab = ModelEntity(mesh: .generateBox(width: len, height: dh, depth: 0.04), materials: [woodLight])
                slab.position = [0, dh / 2, 0]
                real.addChild(slab)
                if lineMode {
                    var lg = Geo()
                    for z: Float in [0.022, -0.022] { rectLines(&lg, -hl + 0.005, hl - 0.005, 0.005, dh - 0.005, z: z) }
                    if let le = lg.entity("realLines", Ink.line) { real.addChild(le) }
                }
                for z: Float in [0.035, -0.035] {
                    let lever = ModelEntity(mesh: .generateBox(width: 0.12, height: 0.02, depth: 0.02, cornerRadius: 0.008), materials: [gold])
                    lever.position = [hl - min(0.16, hl * 0.35), 1.0, z]
                    real.addChild(lever)
                }
                real.isEnabled = false
                local.addChild(real)
                doorLeaf[i] = real
            }
        }
    }

    /// 빛을 받는 황금 (실제 방의 빛이 비쳐 반짝임)
    static func gold(rough: Float, glow: Float = 0.35) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: UIColor(red: 1.0, green: 0.76, blue: 0.33, alpha: 1))
        m.metallic = .init(floatLiteral: 1)
        m.roughness = .init(floatLiteral: rough)
        m.emissiveColor = .init(color: UIColor(red: 1.0, green: 0.7, blue: 0.3, alpha: 1))
        m.emissiveIntensity = glow
        return m
    }

    /// 황금 열쇠 (가로로 누운 모양: 왼쪽 고리, 오른쪽 열쇠 이). 길이 약 15cm
    static func makeKey() -> (Entity, [ModelEntity]) {
        let k = Entity()
        var parts: [ModelEntity] = []
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
            parts.append(e)
        }
        // 고리 가운데 장식 + 몸통
        let gem = ModelEntity(mesh: .generateSphere(radius: 0.008), materials: [m])
        gem.position = [-0.05, 0, 0]
        k.addChild(gem); parts.append(gem)
        let shaft = ModelEntity(mesh: .generateCylinder(height: 0.1, radius: 0.0055), materials: [m])
        shaft.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        shaft.position = [0.025, 0, 0]
        k.addChild(shaft); parts.append(shaft)
        let collar = ModelEntity(mesh: .generateCylinder(height: 0.008, radius: 0.009), materials: [m])
        collar.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        collar.position = [-0.02, 0, 0]
        k.addChild(collar); parts.append(collar)
        // 열쇠 이 (아래로)
        for (x, h) in [(Float(0.062), Float(0.03)), (Float(0.048), Float(0.02))] {
            let bit = ModelEntity(mesh: .generateBox(width: 0.01, height: h, depth: 0.008), materials: [m])
            bit.position = [x, -h / 2, 0]
            k.addChild(bit); parts.append(bit)
        }
        return (k, parts)
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
        if let e = g.entity("beams", ink(SIMD3<Float>(0.18, 0.15, 0.12) * Worlds.safe(tint))) {
            local.addChild(e)
        }
    }

    /// 카페: 유리 천장 (온실 카페). 하늘·날씨가 그대로 보이고, 1.1m 간격 나무 들보 사이에 가는 철제 살(0.55m)이 유리를 나눔
    private func addCafeCeiling(_ rects: [PRect], _ L: Layout, y: Float) {
        let wood = Worlds.safe(tint * 0.9, min: 0.3)
        // (유리 면 자체는 그리지 않음: 방 안의 반투명 면은 그 뒤 하늘 창을 가려 현실이 비쳐 보일 수 있음 — 살과 들보로 유리 지붕을 나타냄)
        var g = Geo()
        var iron = Geo()
        var lines = Geo()
        for r in rects {
            guard r.1.x - r.0.x > 0.3, r.1.y - r.0.y > 0.3 else { continue }
            // 들보 (1.1m)
            var v = (r.0.y).rounded(.down) + 0.55
            while v < r.1.y - 0.2 {
                for side: Float in [-0.045, 0.045] {
                    let a = L.flat(SIMD2<Float>(r.0.x, v + side)), b = L.flat(SIMD2<Float>(r.1.x, v + side))
                    g.wall(SIMD3<Float>(a.x, y, a.y), SIMD3<Float>(b.x, y, b.y), y0: -0.12, y1: 0, u0: 0, u1: (r.1.x - r.0.x) / 1.2, v0: 0, v1: 0.15)
                }
                let a0 = L.flat(SIMD2<Float>(r.0.x, v - 0.045)), b0 = L.flat(SIMD2<Float>(r.1.x, v - 0.045))
                let a1 = L.flat(SIMD2<Float>(r.0.x, v + 0.045)), b1 = L.flat(SIMD2<Float>(r.1.x, v + 0.045))
                g.quad(SIMD3<Float>(a0.x, y - 0.12, a0.y), SIMD3<Float>(b0.x, y - 0.12, b0.y), SIMD3<Float>(b1.x, y - 0.12, b1.y), SIMD3<Float>(a1.x, y - 0.12, a1.y),
                       SIMD2<Float>(0, 0), SIMD2<Float>((r.1.x - r.0.x) / 1.2, 0), SIMD2<Float>((r.1.x - r.0.x) / 1.2, 0.1), SIMD2<Float>(0, 0.1))
                if lineMode {
                    for (p, q) in [(a0, b0), (a1, b1)] {
                        lines.stroke(SIMD3<Float>(p.x, y - 0.12, p.y), SIMD3<Float>(q.x, y - 0.12, q.y), width: 0.01)
                    }
                }
                v += 1.1
            }
            // 가는 철제 살: 들보 사이 한 줄, 가로로 0.55m마다
            var w = (r.0.y).rounded(.down) + 1.1
            while w < r.1.y - 0.1 {
                let a = L.flat(SIMD2<Float>(r.0.x, w)), b = L.flat(SIMD2<Float>(r.1.x, w))
                iron.wall(SIMD3<Float>(a.x, y, a.y), SIMD3<Float>(b.x, y, b.y), y0: -0.03, y1: 0, u0: 0, u1: 1)
                if lineMode { lines.stroke(SIMD3<Float>(a.x, y - 0.03, a.y), SIMD3<Float>(b.x, y - 0.03, b.y), width: 0.006) }
                w += 1.1
            }
            var u = (r.0.x).rounded(.down) + 0.55
            while u < r.1.x - 0.1 {
                let a = L.flat(SIMD2<Float>(u, r.0.y)), b = L.flat(SIMD2<Float>(u, r.1.y))
                iron.wall(SIMD3<Float>(a.x, y, a.y), SIMD3<Float>(b.x, y, b.y), y0: -0.03, y1: 0, u0: 0, u1: 1)
                if lineMode { lines.stroke(SIMD3<Float>(a.x, y - 0.03, a.y), SIMD3<Float>(b.x, y - 0.03, b.y), width: 0.006) }
                u += 0.55
            }
        }
        if let e = g.entity("cafeBeams", lineMode ? Ink.paper(0) : Tex.unlit("planks_dark", tint: wood * 0.7)) { local.addChild(e) }
        if let e = iron.entity("cafeMuntins", lineMode ? Ink.paper(0) : ink(SIMD3<Float>(0.13, 0.13, 0.13))) { local.addChild(e) }
        if let e = lines.entity("cafeBeamLines", Ink.line) { local.addChild(e) }
    }

    // MARK: 하늘 세계
    private static var skyMesh: MeshResource?
    /// 밤하늘 별·달 (밤·새벽·해질녘, 비·눈이 아닐 때)
    private(set) var stars: SkyStars?
    /// 장소마다의 특징: 바다 해파리 · 계곡 방 안 물길과 물고기 · 도시 네온사인
    private(set) var jelly: JellySea?
    private(set) var creek: ValleyCreek?
    private(set) var neon: NeonCity?
    private var cityNear: [NeonCity.Box] = []
    private var cityFar: [NeonCity.Box] = []

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
        // 밤·새벽·해질녘: 또렷한 별(그림에 그리지 않고 점으로)·달, 숲이면 별자리
        if ["night", "dusk", "dawn"].contains(room.time) {
            let st = SkyStars(room: room, center: center, look: look, constellations: room.place == "forest")
            if st.visible {
                world.addChild(st.root)
                stars = st
            }
        }
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
        if lineMode && !dc.sea && !dc.city {
            var hl = Geo()
            let segN = 128
            for i in 0..<segN {
                let a0 = Float(i) / Float(segN) * 2 * .pi, a1 = Float(i + 1) / Float(segN) * 2 * .pi
                hl.stroke(SIMD3<Float>(center.x + cos(a0) * 320, farY, center.z + sin(a0) * 320),
                          SIMD3<Float>(center.x + cos(a1) * 320, farY, center.z + sin(a1) * 320), width: 0.6)
            }
            if let e = hl.entity("horizon", Ink.line) { world.addChild(e) }
        }
        if dc.sea {
            var w = Geo()
            w.disc(center: SIMD3<Float>(center.x, floorY - 0.35, center.z), radius: 420, tile: 6, segments: 48)
            if let e = w.entity("sea", Tex.unlit("water", tint: tint)) {
                world.addChild(e)
                water = e
            }
            if lineMode {
                var hl = Geo()
                let segN = 128
                for i in 0..<segN {
                    let a0 = Float(i) / Float(segN) * 2 * .pi, a1 = Float(i + 1) / Float(segN) * 2 * .pi
                    hl.stroke(SIMD3<Float>(center.x + cos(a0) * 300, floorY - 0.35, center.z + sin(a0) * 300),
                              SIMD3<Float>(center.x + cos(a1) * 300, floorY - 0.35, center.z + sin(a1) * 300), width: 0.6)
                }
                if let e = hl.entity("horizon", Ink.line) { world.addChild(e) }
                return
            }
            // 수평선 안개 띠: 먼 바다의 잔물결 무늬가 자글자글해지는 곳과 하늘이 만나는 선을 부드럽게 덮음
            var hz = Geo()
            hz.ring(center: SIMD3<Float>(center.x, floorY - 2, center.z), radius: 230, y0: 0, y1: 16, repeats: 1, segments: 96)
            var hm = UnlitMaterial(color: Tex.color(Worlds.haze(room.time, weather: room.weather)))
            if let mask = Tex.get("haze_a", folder: "tex", raw: true) {
                var p = MaterialParameters.Texture(mask)
                p.sampler = Tex.band
                hm.blending = .transparent(opacity: .init(scale: 1, texture: p))
                hm.writesDepth = false                 // 반투명 판이 뒤의 나무·물건을 네모나게 지우지 않게
                if let e = hz.entity("seaHaze", hm) {
                    layer(e, 3)
                    world.addChild(e)
                }
            }
        }
    }

    /// 숲의 별이 보이는 밤: 별자리가 나무·나무 띠에 가리지 않게 숲 속 빈터처럼 (나무 꼭대기가 눈높이에서 19도 아래로 보이게)
    private var forestSkyOpen: Bool {
        room.place == "forest" && ["night", "dusk", "dawn"].contains(room.time) && ["clear", "cloudy", "wind"].contains(room.weather)
    }

    private func addBands(_ dc: Decor, R: Float, floorY: Float) {
        let haze = Worlds.haze(room.time, weather: room.weather)
        let fog = ["rain", "storm", "heavysnow", "snow"].contains(room.weather)
        var g = SeededRNG(seed: UInt64(room.id * 131 + 7))
        for b in dc.bands {
            if fog && b.layer == 0 { continue }                      // 비·눈이면 먼 산은 안 보임
            var r = b.relative ? R + b.radius : b.radius
            if forestSkyOpen && b.layer == 2 { r = max(r, (b.base + b.height) * 3.4) }      // 가까운 숲 띠도 19도 아래로
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
            // aspect 0 = 한 바퀴짜리 실사 풍경 띠 (되풀이하지 않음)
            let reps: Float = b.aspect == 0 ? 1 : max(1, (2 * .pi * r / (b.height * b.aspect)).rounded())
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

    // MARK: 계곡 개울
    /// 개울 물길: 먼 절벽의 폭포에서 시작해 방 옆 5~6m를 굽이쳐 지나 반대편 절벽 밑으로 사라짐.
    /// 집 안(걸을 수 있는 곳)에 걸치면 그 자리만 바깥으로 밀어냄
    private func planRiver(_ L: Layout, _ rec: SpaceRec, floorY: Float) {
        var g = SeededRNG(seed: UInt64(room.id * 613 + 77))
        let f0 = Float(g.next() % 1000) / 1000
        let span: Float = 0.32
        let n = 64
        let wig = Float(g.next() % 100) / 100 * 6
        func clear(_ p: SIMD3<Float>, _ r: Float) -> Bool {
            for k in 0..<12 {
                let a = Float(k) / 12 * 2 * .pi
                for f: Float in [0, 0.5, 1] where !(f == 0 && k > 0) {
                    let q = p + SIMD3<Float>(cos(a), 0, sin(a)) * r * f
                    if L.walkable(L.plane(q.x, q.z)) { return false }
                }
            }
            return true
        }
        var pts: [SIMD3<Float>] = []
        var ws: [Float] = []
        for i in 0...n {
            let u = Float(i) / Float(n)
            var d: Float = 5.5 + 27 * pow(abs(2 * u - 1), 1.7) + 0.9 * sin(u * 11 + wig)
            let w: Float = 2.4 + 1.2 * sin(u * .pi) + 0.4 * sin(u * 17 + wig)
            var p = around(f0 + span * u, d, rec, floorY)
            while d < 36 && !clear(p, w / 2 + 1.2) { d += 0.8; p = around(f0 + span * u, d, rec, floorY) }
            pts.append(p)
            ws.append(w)
        }
        // 네모 둘레를 따라 꺾인 곳을 둥글게
        for _ in 0..<4 {
            var q = pts
            for i in 1..<(pts.count - 1) { q[i] = (pts[i - 1] + pts[i] * 2 + pts[i + 1]) / 4 }
            pts = q
        }
        // 둥글게 하다 집 안으로 들어온 곳은 다시 밀어냄
        for i in pts.indices where !clear(pts[i], ws[i] / 2 + 1.0) {
            var dir = pts[i] - center
            dir.y = 0
            dir = simd_length(dir) > 0.01 ? simd_normalize(dir) : SIMD3<Float>(1, 0, 0)
            var k = 0
            while k < 30 && !clear(pts[i], ws[i] / 2 + 1.0) { pts[i] += dir * 0.5; k += 1 }
        }
        riverPts = pts
        riverW = ws
    }

    /// 물길 가장자리까지 거리 (물 위면 음수)
    private func riverGap(_ p: SIMD3<Float>) -> Float {
        guard riverPts.count > 1 else { return 1e9 }
        var best: Float = 1e9
        let q = SIMD2<Float>(p.x, p.z)
        for i in 0..<(riverPts.count - 1) {
            let a = SIMD2<Float>(riverPts[i].x, riverPts[i].z), b = SIMD2<Float>(riverPts[i + 1].x, riverPts[i + 1].z)
            let ab = b - a
            let t = max(0, min(1, simd_dot(q - a, ab) / max(1e-6, simd_length_squared(ab))))
            best = min(best, simd_distance(q, a + ab * t) - (riverW[i] + (riverW[i + 1] - riverW[i]) * t) / 2)
        }
        return best
    }

    private func addRiver<G: RandomNumberGenerator>(floorY: Float, using g: inout G) {
        let pts = riverPts, ws = riverW
        guard pts.count > 2 else { return }
        var water = Geo(), bank = Geo(), stones = Geo(), lines = Geo()
        var vAcc: Float = 0
        var prevL = SIMD3<Float>(0, 0, 0), prevR = SIMD3<Float>(0, 0, 0), prevBL = SIMD3<Float>(0, 0, 0), prevBR = SIMD3<Float>(0, 0, 0)
        var prevV: Float = 0
        let wy = floorY - 0.012, by = floorY - 0.022
        for i in pts.indices {
            let a = pts[max(0, i - 1)], b = pts[min(pts.count - 1, i + 1)]
            var t = b - a
            t.y = 0
            t = simd_normalize(t)
            let nrm = SIMD3<Float>(-t.z, 0, t.x)
            let p = SIMD3<Float>(pts[i].x, 0, pts[i].z)
            let hw = ws[i] / 2
            let l = p + nrm * hw, r = p - nrm * hw
            let bl = p + nrm * (hw + 1.1), br = p - nrm * (hw + 1.1)
            if i > 0 {
                vAcc += simd_distance(pts[i], pts[i - 1])
                let v0 = prevV, v1 = vAcc / 3.5
                water.quad(SIMD3<Float>(prevL.x, wy, prevL.z), SIMD3<Float>(prevR.x, wy, prevR.z), SIMD3<Float>(r.x, wy, r.z), SIMD3<Float>(l.x, wy, l.z),
                           SIMD2<Float>(0, v0), SIMD2<Float>(1, v0), SIMD2<Float>(1, v1), SIMD2<Float>(0, v1))
                bank.quad(SIMD3<Float>(prevBL.x, by, prevBL.z), SIMD3<Float>(prevBR.x, by, prevBR.z), SIMD3<Float>(br.x, by, br.z), SIMD3<Float>(bl.x, by, bl.z),
                          SIMD2<Float>(0, v0 * 2.5), SIMD2<Float>(ws[i] / 1.4 + 1.6, v0 * 2.5), SIMD2<Float>(ws[i] / 1.4 + 1.6, v1 * 2.5), SIMD2<Float>(0, v1 * 2.5))
                if lineMode {
                    lines.stroke(SIMD3<Float>(prevL.x, wy + 0.02, prevL.z), SIMD3<Float>(l.x, wy + 0.02, l.z), width: 0.06)
                    lines.stroke(SIMD3<Float>(prevR.x, wy + 0.02, prevR.z), SIMD3<Float>(r.x, wy + 0.02, r.z), width: 0.06)
                    if i % 3 == 0 {                                            // 물살 선
                        let o = Float.random(in: -0.25...0.25, using: &g)
                        let c0 = (prevL + prevR) / 2 + nrm * o * hw, c1 = (l + r) / 2 + nrm * o * hw
                        lines.stroke(SIMD3<Float>(c0.x, wy + 0.02, c0.z), SIMD3<Float>(c0.x + (c1.x - c0.x) * 0.6, wy + 0.02, c0.z + (c1.z - c0.z) * 0.6), width: 0.035)
                    }
                }
                prevV = v1
            }
            prevL = l; prevR = r; prevBL = bl; prevBR = br
            // 물가 돌 (양쪽 번갈아), 가끔 물속 바위
            if i % 2 == 0 && i > 2 && i < pts.count - 2 {
                let side: Float = (i / 2) % 2 == 0 ? 1 : -1
                let sz = Float.random(in: 0.25...0.8, using: &g)
                let off = hw + Float.random(in: 0.1...0.9, using: &g)
                let along = Float.random(in: -0.6...0.6, using: &g)
                let at = SIMD3<Float>(p.x, floorY - 0.05, p.z) + nrm * side * off + t * along
                stones.rock(at: at, size: sz, using: &g)
                if Float.random(in: 0...1, using: &g) < 0.22 {
                    let across = Float.random(in: -hw * 0.6...hw * 0.6, using: &g)
                    let bs = Float.random(in: 0.25...0.5, using: &g)
                    stones.rock(at: SIMD3<Float>(p.x, floorY - 0.12, p.z) + nrm * across, size: bs, using: &g)
                }
            }
        }
        // 폭포: 물길 시작 바로 뒤, 물길 쪽을 향해 선 물줄기 (높이 26m)
        let p0 = pts[0]
        var t0 = pts[1] - pts[0]
        t0.y = 0
        t0 = simd_normalize(t0)
        let n0 = SIMD3<Float>(-t0.z, 0, t0.x)
        let fw = max(ws[0] * 1.3, 5.5)                               // 폭포 폭 (실제 폭포처럼 높이에 비해 너무 가늘지 않게)
        let fH: Float = 26
        let fb = SIMD3<Float>(p0.x, floorY - 0.3, p0.z) - t0 * 0.8
        let lip = fb + SIMD3<Float>(0, fH, 0) - t0 * 1.5            // 폭포가 떨어지기 시작하는 절벽 끝 (가운데)
        // 물줄기 세 겹: 절벽 끝에서 앞으로 튀어 나가며(포물선) 떨어지고 아래로 갈수록 넓게 퍼짐. 겹마다 폭·튀어 나가는 거리·빠르기가 달라 두툼한 물줄기로 보임
        func sheet(_ wt: Float, _ wb: Float, out: Float, z: Float, u0: Float, u1: Float, tile: Float) -> Geo {
            var g2 = Geo()
            let n = 14
            func at(_ s: Float, _ side: Float) -> SIMD3<Float> {
                let w = wt + (wb - wt) * s
                return lip + t0 * (out * sqrt(s) + z) - SIMD3<Float>(0, fH * s, 0) + n0 * (side * w / 2)
            }
            for i in 0..<n {
                let s0 = Float(i) / Float(n), s1 = Float(i + 1) / Float(n)
                let v0 = fH * (1 - s0) / tile, v1 = fH * (1 - s1) / tile
                g2.quad(at(s1, 1), at(s1, -1), at(s0, -1), at(s0, 1), SIMD2<Float>(u0, v1), SIMD2<Float>(u1, v1), SIMD2<Float>(u1, v0), SIMD2<Float>(u0, v0))
            }
            // 절벽 위에서 끝으로 흘러와 넘어가는 물 (윗면)
            g2.quad(lip - t0 * 1.6 + n0 * (wt / 2) + t0 * z, lip - t0 * 1.6 - n0 * (wt / 2) + t0 * z, lip - n0 * (wt / 2) + t0 * z, lip + n0 * (wt / 2) + t0 * z,
                    SIMD2<Float>(u0, fH / tile + 1.6 / tile), SIMD2<Float>(u1, fH / tile + 1.6 / tile), SIMD2<Float>(u1, fH / tile), SIMD2<Float>(u0, fH / tile))
            return g2
        }
        let fall = sheet(fw, fw * 1.1, out: 1.1, z: 0, u0: 0, u1: 1, tile: 7)
        let fallMid = sheet(fw * 0.88, fw * 1.22, out: 1.5, z: 0.14, u0: 0.08, u1: 0.92, tile: 5.5)
        let fallFront = sheet(fw * 0.66, fw * 1.34, out: 1.9, z: 0.3, u0: 0.15, u1: 0.85, tile: 4.2)
        addCliff(behind: fb, lip: lip, t0: t0, n0: n0, fw: fw, fH: fH, floorY: floorY, using: &g)
        // 폭포 양옆과 물길 끝을 큰 바위로 감쌈
        for side: Float in [-1, 1] {
            let bs = Float.random(in: 1.6...2.6, using: &g)
            stones.rock(at: fb + n0 * side * (fw / 2 + 1.4) + t0 * 0.4, size: bs, using: &g)
        }
        let pe = pts[pts.count - 1]
        var te = pts[pts.count - 1] - pts[pts.count - 2]
        te.y = 0
        te = simd_normalize(te)
        let ne = SIMD3<Float>(-te.z, 0, te.x)
        for k in -1...1 {
            let bs = Float.random(in: 1.3...2.2, using: &g)
            stones.rock(at: SIMD3<Float>(pe.x, floorY - 0.2, pe.z) + ne * Float(k) * 1.6 + te * 0.6, size: bs, using: &g)
        }
        let rockTint = Worlds.safe(tint * 0.85, min: 0.25)
        if let e = bank.entity("riverBank", Tex.unlit("pebble", tint: Worlds.safe(tint * 0.55, min: 0.2))) {
            layer(e, 5)
            world.addChild(e)
        }
        let night = room.time == "night"
        let wTint: SIMD3<Float> = night ? tint * 0.55 : tint
        let wm = Tex.unlit("river", tint: Worlds.safe(wTint, min: 0.2))
        if let e = water.entity("river", wm) {
            layer(e, 5)
            world.addChild(e)
            flows.append((e, wm, 0.45, 0))
        }
        if !lineMode {
            let hiTint: SIMD3<Float> = night ? SIMD3<Float>(0.6, 0.65, 0.75) : SIMD3<Float>(1, 1, 1)
            var hm = Tex.unlit("river_hi", tint: hiTint)
            if let mk = Tex.get("river_hi_a", raw: true) {
                var tp = MaterialParameters.Texture(mk); tp.sampler = Tex.tiling
                hm.blending = .transparent(opacity: .init(scale: night ? 0.5 : 0.85, texture: tp))
                hm.writesDepth = false                 // 반투명 판이 뒤의 나무·물건을 네모나게 지우지 않게
            }
            var hg = water
            hg.pos = hg.pos.map { SIMD3<Float>($0.x, $0.y + 0.004, $0.z) }
            hg.uv = hg.uv.map { SIMD2<Float>($0.x * 0.7, $0.y * 1.3) }
            if let e = hg.entity("riverHi", hm) {
                layer(e, 6)
                world.addChild(e)
                flows.append((e, hm, 0.9, 0.3))
            }
        }
        if let e = stones.entity("riverRocks", Tex.unlit("rock", tint: rockTint)) {
            layer(e, 5)
            world.addChild(e)
        }
        // 물줄기 빛깔: 하얗게 부서지는 물 (밤엔 달빛에 은회색) — 하늘빛으로 파랗게 물들지 않게 밝기만 따름
        let lum = (tint.x + tint.y + tint.z) / 3
        let fallTint: SIMD3<Float> = night ? SIMD3<Float>(0.5, 0.54, 0.6) : SIMD3<Float>(repeating: min(1.1, 0.55 + lum * 0.5)) * SIMD3<Float>(0.98, 1, 1.02)
        func fallMat(_ k: Float, _ op: Float) -> UnlitMaterial {
            var m = Tex.unlit("fall", tint: fallTint * k)
            if let mk = Tex.get("fall_a", raw: true) {
                var tp = MaterialParameters.Texture(mk); tp.sampler = Tex.tiling
                m.blending = .transparent(opacity: .init(scale: op, texture: tp))
            } else {
                m.blending = .transparent(opacity: .init(floatLiteral: op * 0.6))
            }
            m.writesDepth = false
            return m
        }
        if !lineMode {
            let sheets: [(Geo, Float, Float, Float)] = [(fall, 0.92, 0.95, -2.4), (fallMid, 1.0, 0.7, -3.1), (fallFront, 1.06, 0.5, -3.9)]
            for (i, sh) in sheets.enumerated() {
                let (geo, k, op, sp) = sh
                let m = fallMat(k, op)
                if let e = geo.entity("waterfall\(i)", m) {
                    layer(e, 6 + i)
                    world.addChild(e)
                    flows.append((e, m, sp, Float(i) * 0.3))
                }
            }
            // 물줄기 가장자리에서 흩날리는 물보라 가닥 (길게 늘어진 부드러운 물방울, 중력으로 점점 빨라짐)
            var dr = ParticleEmitterComponent()
            dr.emitterShape = .box
            dr.emitterShapeSize = [fw * 0.95, 0.3, 0.5]
            dr.birthLocation = .volume
            dr.birthDirection = .world
            dr.emissionDirection = [0, -1, 0]
            dr.speed = 2.0
            dr.speedVariation = 0.8
            dr.mainEmitter.birthRate = 70
            dr.mainEmitter.lifeSpan = 2.3
            dr.mainEmitter.lifeSpanVariation = 0.2
            dr.mainEmitter.acceleration = [0, -9.8, 0]
            dr.mainEmitter.size = 0.09
            dr.mainEmitter.sizeVariation = 0.04
            dr.mainEmitter.sizeMultiplierAtEndOfLifespan = 2.4
            dr.mainEmitter.stretchFactor = 6
            dr.mainEmitter.spreadingAngle = 0.08
            dr.mainEmitter.color = .constant(.single(Tex.color([0.95, 0.97, 1], alpha: night ? 0.14 : 0.28)))
            dr.mainEmitter.opacityCurve = .gradualFadeInOut
            if let puff = Tex.particle("smoke_puff") { dr.mainEmitter.image = puff }
            let de = Entity()
            de.components.set(dr)
            de.position = lip + t0 * 0.5 - SIMD3<Float>(0, 0.4, 0)
            de.orientation = simd_quatf(angle: atan2(-n0.z, n0.x), axis: [0, 1, 0])          // 상자 x = 폭포 폭 방향
            layer(de, 18)
            world.addChild(de)
            emitters.append(de)
            // 폭포 밑 하얀 물거품 (떨어진 물이 부딪혀 튀어 오름)
            var fo = ParticleEmitterComponent()
            fo.emitterShape = .box
            fo.emitterShapeSize = [fw * 1.2, 0.2, 1.8]
            fo.birthLocation = .volume
            fo.birthDirection = .world
            fo.emissionDirection = [0, 1, 0]
            fo.speed = 1.2
            fo.speedVariation = 0.7
            fo.mainEmitter.spreadingAngle = 0.7
            fo.mainEmitter.acceleration = [0, -3, 0]
            fo.mainEmitter.birthRate = 60
            fo.mainEmitter.lifeSpan = 1.6
            fo.mainEmitter.size = 0.3
            fo.mainEmitter.sizeVariation = 0.12
            fo.mainEmitter.sizeMultiplierAtEndOfLifespan = 3
            fo.mainEmitter.color = .constant(.single(Tex.color([0.97, 0.98, 1], alpha: night ? 0.16 : 0.36)))
            fo.mainEmitter.opacityCurve = .quickFadeInOut
            if let puff = Tex.particle("smoke_puff") { fo.mainEmitter.image = puff }
            let foe = Entity()
            foe.components.set(fo)
            foe.position = fb + t0 * 1.0 + SIMD3<Float>(0, 0.1, 0)
            foe.orientation = de.orientation
            layer(foe, 18)
            world.addChild(foe)
            emitters.append(foe)
        } else {
            // 선 그림: 물줄기 윤곽 + 떨어지는 물살 선 몇 가닥 + 바닥에 퍼지는 물결
            for k in 0..<9 {
                let side = -1 + 2 * Float(k) / 8
                var prev: SIMD3<Float>? = nil
                for i in 0...14 {
                    let s2 = Float(i) / 14
                    let w = fw + (fw * 1.1 - fw) * s2
                    let p = lip + t0 * (1.1 * sqrt(s2)) - SIMD3<Float>(0, fH * s2, 0) + n0 * (side * w / 2)
                    if let q = prev, k == 0 || k == 8 || i % 2 == (k % 2) { lines.stroke(q, p, width: (k == 0 || k == 8) ? 0.12 : 0.06) }
                    prev = p
                }
            }
            for r in [Float(1.2), 2.0, 2.9] {
                for i in 0..<20 {
                    let a0 = Float(i) / 20 * .pi, a1 = Float(i + 1) / 20 * .pi
                    let c = fb + t0 * 1.0 + SIMD3<Float>(0, 0.32, 0)
                    lines.stroke(c + n0 * (cos(a0) * fw * 0.5 * r / 1.2) + t0 * (sin(a0) * r), c + n0 * (cos(a1) * fw * 0.5 * r / 1.2) + t0 * (sin(a1) * r), width: 0.05)
                }
            }
            if let e = lines.entity("riverLines", Ink.line) { layer(e, 7); world.addChild(e) }
        }
        // 폭포 밑 물보라 (하얀 물안개가 피어오름)
        var mist = ParticleEmitterComponent()
        mist.emitterShape = .box
        mist.emitterShapeSize = [fw, 0.6, 1.5]
        mist.birthLocation = .volume
        mist.birthDirection = .world
        mist.emissionDirection = [0, 1, 0]
        mist.speed = 0.7
        mist.speedVariation = 0.4
        mist.mainEmitter.birthRate = 14
        mist.mainEmitter.lifeSpan = 4
        mist.mainEmitter.size = 1.2
        mist.mainEmitter.sizeMultiplierAtEndOfLifespan = 3
        mist.mainEmitter.color = .constant(.single(lineMode ? UIColor(white: 0.5, alpha: 0.12) : Tex.color([0.95, 0.97, 1], alpha: night ? 0.1 : 0.22)))
        if lineMode { mist.mainEmitter.blendMode = .alpha }
        mist.mainEmitter.opacityCurve = .gradualFadeInOut
        if let puff = Tex.particle("smoke_puff") { mist.mainEmitter.image = puff }
        let me = Entity()
        me.components.set(mist)
        me.position = fb + SIMD3<Float>(0, 0.4, 0) + t0 * 0.8
        layer(me, 18)
        world.addChild(me)
        emitters.append(me)
        fallSpot = fb + SIMD3<Float>(0, 2, 0)
        riverNear = pts.min { simd_distance($0, center) < simd_distance($1, center) }
    }

    /// 폭포 뒤 절벽: 실사 암벽 무늬를 입힌 울퉁불퉁한 바위 벽 (폭이 46m, 폭포 높이보다 조금 높게).
    /// 가운데 폭포 자리는 깎여 들어가 있고, 양끝은 물길 쪽으로 휘어 감싸며, 꼭대기 윤곽은 들쭉날쭉. 먼 절벽 띠 앞에서 폭포가 바위에 붙어 떨어지게 보임
    private func addCliff<G: RandomNumberGenerator>(behind fb: SIMD3<Float>, lip: SIMD3<Float>, t0: SIMD3<Float>, n0: SIMD3<Float>,
                                                    fw: Float, fH: Float, floorY: Float, using g: inout G) {
        let cw: Float = 46, nx = 46, ny = 26
        let H0 = fH + 2.5
        let back = fb - t0 * 0.4
        let s1 = Float.random(in: 0...10, using: &g), s2 = Float.random(in: 0...10, using: &g)
        func nz(_ x: Float, _ y: Float) -> Float {
            (sin(x * 0.31 + s1) * cos(y * 0.27 + s2) * 0.55 + sin(x * 0.83 + y * 0.41 + s2) * 0.3 + sin(x * 2.1 - y * 1.7 + s1) * 0.12 + sin(x * 4.7 + y * 3.9) * 0.05)
        }
        func topH(_ x: Float) -> Float {
            let notch = max(0, 1 - abs(x) / (fw * 0.7))                  // 폭포 자리는 살짝 낮게 패임
            return H0 + 2.2 * nz(x * 0.7, 3.1) + 1.2 * sin(x * 0.45 + s1) - notch * 1.6
        }
        var geo = Geo(), lines = Geo()
        var grid: [SIMD3<Float>] = []
        for j in 0...ny {
            for i in 0...nx {
                let x = -cw / 2 + cw * Float(i) / Float(nx)
                let hTop = topH(x)
                let y = hTop * Float(j) / Float(ny)
                let curve = x * x / 70                                        // 양끝이 물길 쪽으로 휨
                let near = min(1, abs(x) / (fw * 1.2))                          // 폭포 바로 뒤는 고르게 (바위가 물줄기 앞으로 튀어나오지 않게)
                let recess = max(0, 1 - abs(x) / (fw * 0.9)) * 0.3             // 폭포 뒤는 깎여 들어감
                let lean = (y / H0) * 1.4                                       // 위로 갈수록 조금 뒤로 기움 (폭포 물줄기와 나란히)
                let d = nz(x, y) * (0.2 + 1.1 * near) - recess - lean
                grid.append(back + n0 * x + t0 * (curve + d) + SIMD3<Float>(0, y - 0.6, 0))
            }
        }
        let W = nx + 1
        for j in 0..<ny {
            for i in 0..<nx {
                let a = grid[j * W + i], b = grid[j * W + i + 1], c = grid[(j + 1) * W + i + 1], d = grid[(j + 1) * W + i]
                func uv(_ p: SIMD3<Float>) -> SIMD2<Float> { SIMD2<Float>(simd_dot(p - back, n0) / 7, p.y / 7) }
                geo.quad(a, b, c, d, uv(a), uv(b), uv(c), uv(d))
            }
        }
        if lineMode {
            for i in 0..<nx { lines.stroke(grid[ny * W + i], grid[ny * W + i + 1], width: 0.12) }
            for i in stride(from: 0, through: nx, by: 4) { lines.stroke(grid[i], grid[ny * W + i], width: 0.06) }
            if let e = lines.entity("cliffLines", Ink.line) { layer(e, 5); world.addChild(e) }
        }
        let tx = Tex.get("cliff") != nil ? "cliff" : "rock"
        if let e = geo.entity("fallCliff", Tex.unlit(tx, tint: Worlds.safe(tint * 0.92, min: 0.22))) {
            layer(e, 4)
            world.addChild(e)
        }
    }

    /// 장소마다의 특징 만들기
    private func addFeature(_ L: Layout, segs: [WallSeg], floorY: Float, ceilY: Float) {
        switch room.place {
        case "sea":
            let j = JellySea(center: center, halfSize: halfSize, floorY: floorY, ceilY: ceilY, layout: L, room: room, look: look)
            layerAll(j.root, 30)
            world.addChild(j.root)
            jelly = j
        case "valley":
            let c = ValleyCreek(room: room, layout: L, floorY: floorY, blocked: blocked, riverNear: riverNear,
                                riverWidth: riverW.min() ?? 2.4, look: look, tint: tint)
            if c.ok {
                local.addChild(c.local)
                world.addChild(c.world)
                creek = c
            }
        case "city":
            let n = NeonCity(room: room, layout: L, floorY: floorY, segs: segs, near: cityNear, far: cityFar, center: center, look: look)
            layerAll(n.world, 30)
            world.addChild(n.world)
            neon = n
        default: break
        }
    }

    /// 나무·바위·텐트·건물.
    /// 집 안(어느 방이든 걸을 수 있는 곳)에 걸치는 자리는 피함: 포털 너머 세계의 물건은 방 안에 있어도
    /// 다른 방 포털(문 너머 벽 등)을 통해 그려져서, 복도·문 앞에 나무·덤불이 떠 있는 것처럼 보임
    private func addThings(_ dc: Decor, rec: SpaceRec, _ L: Layout, floorY: Float) {
        var g = SeededRNG(seed: UInt64(room.id * 7919 + room.place.count * 31 + 3))
        func free(_ pts: [SIMD3<Float>]) -> Bool { !pts.contains { L.walkable(L.plane($0.x, $0.z)) } }
        if room.place == "valley" { planRiver(L, rec, floorY: floorY) }
        // 십자 나무의 두 판 자리 (판 양옆 25cm까지)
        func treeFree(_ p: SIMD3<Float>, _ w: Float, _ yaw: Float) -> Bool {
            var pts: [SIMD3<Float>] = []
            for k in 0..<2 {
                let a = yaw + Float(k) * .pi / 2
                let d = SIMD3<Float>(cos(a), 0, sin(a)), q = SIMD3<Float>(-sin(a), 0, cos(a))
                var t = -w / 2
                while t <= w / 2 + 1e-3 {
                    for o: Float in [-0.25, 0, 0.25] { pts.append(p + d * t + q * o) }
                    t += 0.25
                }
            }
            return free(pts)
        }
        func roundFree(_ p: SIMD3<Float>, _ r: Float) -> Bool {
            var pts = [p]
            for k in 0..<12 {
                let a = Float(k) / 12 * 2 * .pi
                for f: Float in [0.5, 1] { pts.append(p + SIMD3<Float>(cos(a), 0, sin(a)) * r * f) }
            }
            return free(pts)
        }
        // 나무: 그림마다 그물 하나, 먼 것부터 (겹칠 때 가까운 것이 위에)
        // 숲의 밤(별이 보이는 시간): 별자리가 나무에 가리지 않게 숲 속 빈터처럼 — 나무 꼭대기가 눈높이에서 19도 아래로 보이도록 멀리
        let skyOpen = forestSkyOpen
        for set in dc.trees {
            var list: [(SIMD3<Float>, Float, Float, Float)] = []
            for i in 0..<set.count {
                for _ in 0..<6 {                                          // 집 안에 걸치면 다른 자리로 (6번까지)
                    let h = Float.random(in: set.h, using: &g)
                    var dd = Float.random(in: set.d, using: &g)
                    if skyOpen { dd = max(dd, (h - 1.6) * 2.9 + Float.random(in: 0...5, using: &g)) }
                    let p = around((Float(i) + Float.random(in: 0...0.8, using: &g)) / Float(set.count), dd, rec, floorY - 0.1)
                    let w = h * set.aspect * Float.random(in: 0.85...1.15, using: &g)
                    let yaw = Float.random(in: 0...3.14, using: &g)
                    if treeFree(p, w, yaw) && riverGap(p) > 1.2 { list.append((p, h, w, yaw)); break }
                }
            }
            list.sort { simd_distance($0.0, center) > simd_distance($1.0, center) }
            // 입체 나무: 둥근 줄기·가지(나무껍질 무늬) + 사방으로 꽂은 잎 판 (어느 쪽에서 봐도 부피가 있음)
            var trunks = Geo(), leaves = Geo()
            let leafTex: String
            for (p, h, w, _) in list {
                switch set.tex {
                case "tree_pine": Geo.pineTree(&trunks, &leaves, at: p, height: h, width: w, using: &g)
                case "tree_twisted": Geo.palmTree(&trunks, &leaves, at: p, height: h, width: w, using: &g)
                default: Geo.broadTree(&trunks, &leaves, at: p, height: h, width: w, using: &g)
                }
            }
            switch set.tex {
            case "tree_pine": leafTex = "pine_branch"
            case "tree_twisted": leafTex = "palm_frond"
            default: leafTex = "leaf_clump"
            }
            if let e = trunks.entity("trunks_\(set.tex)", lineMode ? Ink.line : Tex.unlit("bark", tint: Worlds.safe(tint * 0.8, min: 0.2))) {      // 선 그림: 줄기는 먹으로 채움
                layer(e, 5)
                world.addChild(e)
            }
            if let e = leaves.entity("leaves_\(set.tex)", Tex.cutout(leafTex, tint: Worlds.safe(tint, min: 0.22), sampler: Tex.clamp)) {
                layer(e, 5)
                world.addChild(e)
            }
        }
        if let rk = dc.rocks {
            var geo = Geo()
            for i in 0..<rk.count {
                for _ in 0..<6 {
                    let p = around((Float(i) + Float.random(in: 0...0.9, using: &g)) / Float(rk.count), Float.random(in: rk.d, using: &g), rec, floorY)
                    let size = Float.random(in: rk.size, using: &g)
                    if roundFree(p, size * 1.2 + 0.15) && riverGap(p) > size * 0.7 { geo.rock(at: p, size: size, using: &g); break }
                }
            }
            if let e = geo.entity("rocks", Tex.unlit(rk.tex, tint: Worlds.safe(tint * shades[1], min: 0.25))) { world.addChild(e) }
        }
        if !riverPts.isEmpty { addRiver(floorY: floorY, using: &g) }
        var tentLines = Geo()
        defer { if let e = tentLines.entity("tentLines", Ink.line) { world.addChild(e) } }
        if dc.tents {
            var orange = Geo(), olive = Geo(), bulbs = Geo()
            for i in 0..<3 {
                let p = around(Float(i) / 3 + Float.random(in: 0...0.2, using: &g), Float.random(in: 3...8, using: &g), rec, floorY - 0.05)
                let yaw = Float.random(in: 0...6.28, using: &g)
                guard roundFree(p, 1.9) else { continue }
                if i % 2 == 0 { orange.tent(base: p, w: 2.2, l: 2.6, h: 1.5, yaw: yaw) } else { olive.tent(base: p, w: 2.0, l: 2.4, h: 1.4, yaw: yaw) }
            if lineMode { tentLines.tentOutline(base: p, w: 2.1, l: 2.5, h: 1.45, yaw: yaw) }
                bulbs.bulb(at: p + SIMD3<Float>(0, 1.0, 0) + SIMD3<Float>(sin(yaw), 0, cos(yaw)) * -1.5, r: 0.07)
            }
            if let e = orange.entity("tents", Tex.unlit("canvas", tint: SIMD3<Float>(0.95, 0.55, 0.3) * Worlds.safe(tint, min: 0.3))) { world.addChild(e) }
            if let e = olive.entity("tents2", Tex.unlit("canvas", tint: SIMD3<Float>(0.55, 0.62, 0.4) * Worlds.safe(tint, min: 0.3))) { world.addChild(e) }
            if dc.lanterns && (dark || room.time == "dusk"),
               let e = bulbs.entity("lanterns", lineMode ? Ink.line : UnlitMaterial(color: Tex.color(SIMD3<Float>(1, 0.78, 0.45)))) {
                world.addChild(e)
            }
        }
        if dc.city {
            // 옥상 둘레의 빌딩들 (거리는 30m 아래): 실제 도심처럼 길을 사이에 두고 띄엄띄엄 — 가까운 줄은 낮고 좁게, 먼 줄일수록 높게.
            // 서로 겹치지 않게(길 폭 8m 넘게 띄움) 고리 네 줄에 28채쯤. 그 너머 하늘선은 먼 도시 띠가 이어 줌
            var geo = Geo()
            let R = simd_length(halfSize)
            // 옥상 바로 옆에 솟은 건물 몇 채 (가까운 벽 — 네온 간판이 눈높이에 걸려 공간감이 생김)
            var tries = 0
            while cityNear.count < 3 && tries < 40 {
                tries += 1
                let a = Float.random(in: 0...(2 * .pi), using: &g)
                let bw = Float.random(in: 8...14, using: &g), bd = Float.random(in: 8...12, using: &g)
                let d = R + Float.random(in: 4.5...8, using: &g) + bd / 2
                let p = SIMD3<Float>(center.x + cos(a) * d, floorY - 30, center.z + sin(a) * d)
                // 집 안(어느 방이든)에 걸치거나 이미 세운 옆 건물과 겹치면 다른 자리
                let pc = SIMD2<Float>(p.x, p.z)
                var bad = cityNear.contains { simd_distance(SIMD2<Float>($0.base.x, $0.base.z), pc) < 14 }
                for dx in [-bw / 2, 0, bw / 2] { for dz in [-bd / 2, 0, bd / 2] where L.walkable(L.plane(p.x + dx, p.z + dz)) { bad = true } }
                if bad { continue }
                let h = 30 + Float.random(in: 7...16, using: &g)
                let to = SIMD3<Float>(center.x - p.x, 0, center.z - p.z)
                let byaw = atan2(to.x, to.z) - .pi / 2
                geo.box(base: p, w: bw, d: bd, h: h, yaw: byaw, tile: 12)
                if lineMode { tentLines.boxOutline(base: p, w: bw, d: bd, h: h, yaw: byaw, width: 0.2) }
                cityNear.append(NeonCity.Box(base: p, w: bw, d: bd, h: h, yaw: byaw))
            }
            func clear(_ p: SIMD3<Float>, _ r: Float) -> Bool {
                for b in cityNear + cityFar where simd_distance(SIMD2<Float>(b.base.x, b.base.z), SIMD2<Float>(p.x, p.z)) < r + max(b.w, b.d) * 0.72 + 8 { return false }
                return true
            }
            let rings: [(Float, Int, ClosedRange<Float>)] = [(22, 6, 18...42), (46, 8, 26...60), (82, 8, 40...90), (130, 6, 60...130)]
            for (ringD, count, hr) in rings {
                let off = Float.random(in: 0...1, using: &g)
                for i in 0..<count {
                    for _ in 0..<6 {
                        let a = (Float(i) + off + Float.random(in: -0.25...0.25, using: &g)) / Float(count) * 2 * .pi
                        let d = R + ringD + Float.random(in: -6...6, using: &g)
                        let p = SIMD3<Float>(center.x + cos(a) * d, floorY - 30, center.z + sin(a) * d)
                        let bw = Float.random(in: 12...24, using: &g), bd = Float.random(in: 12...22, using: &g)
                        guard clear(p, max(bw, bd) * 0.72) else { continue }
                        let h = Float.random(in: hr, using: &g)
                        let byaw = -angle + (i % 3 == 0 ? 0.3 : 0)
                        geo.box(base: p, w: bw, d: bd, h: h, yaw: byaw, tile: 12)
                        if lineMode { tentLines.boxOutline(base: p, w: bw, d: bd, h: h, yaw: byaw, width: 0.25 + d * 0.004) }
                        cityFar.append(NeonCity.Box(base: p, w: bw, d: bd, h: h, yaw: byaw))
                        break
                    }
                }
            }
            let face = dark ? "facade_night" : "facade"
            if let e = geo.entity("city", Tex.unlit(face, tint: dark ? SIMD3<Float>(repeating: 0.95) : tint * shades[1])) { layer(e, 4); world.addChild(e) }
        }
    }

    /// 포켓 갤러리 보관함 그림 파일 (탐험 시작 때 채움) — 전시관 방마다 한 점씩
    static var pgArt: [URL] = []

    /// 앱에 담긴 명화 (빌드할 때 tools/fetch_art.py 가 받은 저작권 끝난 유명 화가 그림, 앱 안 art/)
    static let artNames: [String] = {
        let urls = Bundle.main.urls(forResourcesWithExtension: "jpg", subdirectory: "art") ?? []
        return urls.map { $0.deletingPathExtension().lastPathComponent }.sorted()
    }()

    /// 그림 걸 자리 하나: 벽 위 가운데(저장 좌표), 벽에서 방 쪽 방향, 벽 따라 오른쪽, 이 자리 폭, 크기 변화(0.82~1)
    struct PaintSlot { let mid: SIMD2<Float>; let n: SIMD3<Float>; let right: SIMD3<Float>; let width: Float; let k: Float }
    /// 걸린 그림 하나 (설명 창 자리·방 물들이기에 씀)
    struct Hung {
        let pick: ArtPick
        let center: SIMD3<Float>          // 저장 좌표
        let normal: SIMD3<Float>
        let right: SIMD3<Float>
        let size: SIMD2<Float>
        let palette: [SIMD3<Float>]       // 그림의 색 (밝은 색, 가운데 색, 어두운 색)
        let badge: Entity                 // 오른쪽 위 i / ? 버튼
        let group: Entity                 // 그림·액자·버튼 묶음
        let tex: TextureResource
        /// 설명 창 자리: 그림 오른쪽 옆 (저장 좌표)
        var side: SIMD3<Float> { center + right * (size.x / 2 + 0.3) + normal * 0.1 }
    }
    private(set) var paintSlots: [PaintSlot] = []
    private(set) var hungArts: [Hung] = []
    private let paintRoot = Entity()
    private var paintFloor: Float = 0
    private var paintSegs: [WallSeg] = []
    private var paintLayout: Layout?
    var hasPaintings: Bool { paintLayout != nil }

    /// 전시관: 창이 아닌 벽 중 '평평하게 비어 있는 곳'마다 그림 자리를 정함 (그림은 탐험 세션이 골라 hang 으로 걺).
    /// blocked: 그림 높이(1.0~2.2m)에 가구 블록이 있는 10cm 칸 — 벽 앞 15~65cm에 그런 칸이 있으면 피함 (보이는 가구와 겹치지 않게).
    /// 벽에 붙은 것(액자·콘센트·TV)은 블록으로 그리지 않으므로 그림을 막지 않음. 문 자리 30cm 안도 피함.
    /// 남은 빈 구간을 1.4m 안팎마다 나눠 한 자리씩
    func planSlots(blocked: Set<Int64>) {
        guard let L = paintLayout else { return }
        var g = SeededRNG(seed: UInt64(room.id * 977 + 5))
        var doorEnds: [SIMD2<Float>] = []
        for ds in L.doors where ds.roomA == room.id || ds.roomB == room.id {
            let (ea, eb, _) = ds.edge(for: room.id)
            doorEnds += [ea, eb]
        }
        var out: [PaintSlot] = []
        for s in paintSegs {
            let len = simd_distance(s.a, s.b)
            guard len >= 0.7 else { continue }
            let dir = (s.b - s.a) / len
            let step: Float = 0.05
            let n = Int(len / step)
            var free = [Bool](repeating: true, count: n)
            for i in 0..<n {
                let q = s.a + dir * ((Float(i) + 0.5) * step)
                if doorEnds.contains(where: { simd_distance($0, q) < 0.3 }) { free[i] = false; continue }
                var off: Float = 0.15
                while off <= 0.65 {
                    if blocked.contains(Self.clutterKey(q + s.n * off)) { free[i] = false; break }
                    off += 0.1
                }
            }
            let n2 = L.flat(s.n) - L.flat(SIMD2<Float>(0, 0))
            let nn = SIMD3<Float>(n2.x, 0, n2.y)
            let right = simd_cross(-nn, SIMD3<Float>(0, 1, 0))
            var i = 0
            while i < n {
                guard free[i] else { i += 1; continue }
                var j = i
                while j < n && free[j] { j += 1 }
                let t0 = Float(i) * step + 0.1, t1 = Float(j) * step - 0.1
                i = j
                let span = t1 - t0
                guard span >= 0.5 else { continue }
                let count = max(1, Int((span + 0.3) / 1.4))
                let slot = span / Float(count)
                for c in 0..<count {
                    out.append(PaintSlot(mid: L.flat(s.a + dir * (t0 + slot * (Float(c) + 0.5))), n: nn, right: right,
                                         width: slot, k: Float.random(in: 0.82...1.0, using: &g)))
                }
            }
        }
        paintSlots = out
    }

    /// 고른 그림들을 자리마다 걺 (그림 비율 그대로, 자리 폭에 맞게 최대 1.3×1.25m). 예전 그림은 내림.
    /// 그림은 표시 방식과 상관없이 늘 컬러. 오른쪽 위에 해설 버튼(i: 해설 있음, ?: 가져오는 중, 없으면 안 보임)
    func hang(_ arts: [(ArtPick, TextureResource, [SIMD3<Float>])]) {
        for c in Array(paintRoot.children) { c.removeFromParent() }
        hungArts = []
        guard !arts.isEmpty, !paintSlots.isEmpty else { return }
        let lit: SIMD3<Float> = look == .color ? Worlds.safe(tint, min: 0.55) : SIMD3<Float>(repeating: 0.95)
        let litColor = UIColor(red: CGFloat(min(1, lit.x)), green: CGFloat(min(1, lit.y)), blue: CGFloat(min(1, lit.z)), alpha: 1)
        let frameMat = ink(SIMD3<Float>(0.3, 0.22, 0.14) * lit)
        let top = room.ceil
        for (i, sl) in paintSlots.enumerated() where i < arts.count {
            let (pick, t, pal) = arts[i]
            let ar = Float(t.width) / Float(max(1, t.height))
            let maxW = min(1.3, sl.width * 0.72) * sl.k
            let maxH = min(1.25, top - 1.2)
            var w = maxW, h = w / ar
            if h > maxH { h = maxH; w = h * ar }
            guard w >= 0.3, h >= 0.3 else { continue }
            let cy = min(max(1.5, 0.95 + h / 2), top - 0.15 - h / 2)        // 아래 끝 0.95m 위, 위 끝은 천장 15cm 아래
            let ctr = SIMD3<Float>(sl.mid.x, paintFloor + cy, sl.mid.y)
            let pp = ctr + sl.n * 0.035, ff = ctr + sl.n * 0.025
            let hw = sl.right * (w / 2), hh = SIMD3<Float>(0, h / 2, 0)
            // 그림 한 점 = 그림 + 액자 + 해설 버튼 (그림 속으로 들어갈 때 다른 그림만 따로 흐리게)
            let group = Entity()
            var art = Geo()
            art.quad(pp - hw - hh, pp + hw - hh, pp + hw + hh, pp - hw + hh,
                     SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(1, 1), SIMD2<Float>(0, 1))
            var m = UnlitMaterial(color: litColor)
            var tp = MaterialParameters.Texture(t)
            tp.sampler = Tex.clamp
            m.color = .init(tint: litColor, texture: tp)
            if let e = art.entity("art\(i)", m) { group.addChild(e) }
            var frame = Geo()
            let fw = sl.right * (w / 2 + 0.05), fh = SIMD3<Float>(0, h / 2 + 0.05, 0)
            frame.quad(ff - fw - fh, ff + fw - fh, ff + fw + fh, ff - fw + fh, .zero, .zero, .zero, .zero)
            if let e = frame.entity("frame\(i)", frameMat) { group.addChild(e) }
            // 해설 버튼: 액자 오른쪽 위 모서리 바로 안쪽, 그림보다 2cm 앞
            let badge = Self.makeBadge(name: "art-\(room.id)-\(i)")
            badge.position = ctr + sl.right * (w / 2 - 0.02) + SIMD3<Float>(0, h / 2 - 0.02, 0) + sl.n * 0.06
            badge.orientation = simd_quatf(angle: atan2(sl.n.x, sl.n.z), axis: [0, 1, 0])
            badge.isEnabled = false
            group.addChild(badge)
            paintRoot.addChild(group)
            hungArts.append(Hung(pick: pick, center: ctr + sl.n * 0.035, normal: sl.n, right: sl.right, size: SIMD2<Float>(w, h),
                                 palette: pal, badge: badge, group: group, tex: t))
        }
    }

    /// 누른 버튼 이름으로 걸린 그림 찾기
    func hung(named name: String) -> Hung? {
        guard name.hasPrefix("art-\(room.id)-"), let i = Int(name.split(separator: "-").last ?? "") else { return nil }
        return hungArts.first { $0.badge.name == "art-\(room.id)-\(i)" }
    }

    /// 해설 버튼 모양 바꾸기: 해설 있음 i / 가져오는 중 ? / 없음(숨김)
    func refreshBadges(_ state: (String) -> Docent.Status?) {
        for h in hungArts {
            let st = state(h.pick.id)
            let want: String? = st == .ready ? "i" : (st == .loading ? "?" : nil)
            let on = want != nil
            if h.badge.isEnabled != on { h.badge.isEnabled = on }
            guard let w = want else { continue }
            for c in h.badge.children { c.isEnabled = c.name == "glyph-" + w }
        }
    }

    /// 둥근 버튼 (어두운 유리 원판 + 흰 글자 i 또는 ?) — 바라보면 빛나고 누를 수 있음
    static func makeBadge(name: String) -> Entity {
        let e = Entity()
        e.name = name
        let disc = ModelEntity(mesh: .generateCylinder(height: 0.008, radius: 0.04),
                               materials: [UnlitMaterial(color: UIColor(white: 0.08, alpha: 0.85))])
        disc.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        e.addChild(disc)
        let ring = ModelEntity(mesh: .generateCylinder(height: 0.006, radius: 0.044), materials: [gold(rough: 0.3, glow: 0.5)])
        ring.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        ring.position = [0, 0, -0.002]
        e.addChild(ring)
        for g in ["i", "?"] {
            let mesh = MeshResource.generateText(g, extrusionDepth: 0.002, font: .systemFont(ofSize: 0.05, weight: .bold),
                                                 containerFrame: .zero, alignment: .center, lineBreakMode: .byWordWrapping)
            let t = ModelEntity(mesh: mesh, materials: [UnlitMaterial(color: .white)])
            let b = mesh.bounds
            t.position = SIMD3<Float>(-b.center.x, -b.center.y, 0.005)
            t.name = "glyph-" + g
            e.addChild(t)
        }
        e.components.set(InputTargetComponent())
        e.components.set(CollisionComponent(shapes: [.generateSphere(radius: 0.06)]))
        e.components.set(HoverEffectComponent(.highlight(.init(color: UIColor(red: 1, green: 0.85, blue: 0.5, alpha: 1), strength: 2))))
        return e
    }

    /// 그림의 색 세 가지 (밝은 쪽·전체·어두운 쪽 평균) — 그림 속으로 들어갈 때 방을 물들이는 색
    nonisolated static func palette(_ cg: CGImage) -> [SIMD3<Float>] {
        let n = 24
        var px = [UInt8](repeating: 0, count: n * n * 4)
        guard let ctx = CGContext(data: &px, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            return [SIMD3<Float>(0.9, 0.85, 0.75), SIMD3<Float>(0.6, 0.55, 0.5), SIMD3<Float>(0.3, 0.27, 0.25)]
        }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: n, height: n))
        var cols: [SIMD3<Float>] = []
        for i in 0..<(n * n) {
            cols.append(SIMD3<Float>(Float(px[i * 4]), Float(px[i * 4 + 1]), Float(px[i * 4 + 2])) / 255)
        }
        func lum(_ c: SIMD3<Float>) -> Float { c.x * 0.3 + c.y * 0.59 + c.z * 0.11 }
        cols.sort { lum($0) < lum($1) }
        func avg(_ s: ArraySlice<SIMD3<Float>>) -> SIMD3<Float> { s.reduce(SIMD3<Float>(0, 0, 0), +) / Float(max(1, s.count)) }
        let k = cols.count / 3
        // 색이 너무 바래지 않게 채도를 조금 올림
        func vivid(_ c: SIMD3<Float>) -> SIMD3<Float> { let l = lum(c); return simd_clamp(SIMD3<Float>(repeating: l) + (c - SIMD3<Float>(repeating: l)) * 1.35, .zero, SIMD3<Float>(1, 1, 1)) }
        return [vivid(avg(cols[(cols.count - k)...])), vivid(avg(cols[...])), vivid(avg(cols[..<k]))]
    }

    // MARK: 그림 속으로 (도슨트)
    /// 물들일 엔티티: (엔티티, 무늬, 원래 색, 바닥인지)
    private var tinted: [(ModelEntity, String, SIMD3<Float>, Bool)] = []
    private var immerseTarget: [SIMD3<Float>]?
    private var immerseCur: [SIMD3<Float>]?
    private var immerseAmt: Float = 0
    private var immerseGoal: Float = 0
    private var motes: Entity?

    /// 그림 속으로 (컬러 모드만): 방을 그 그림의 색으로 칠함 — 벽은 그림의 밝은·가운데 색을 진하게, 바닥은 그림의 어두운 색,
    /// 그림 색의 빛 알갱이가 방 안 가득 떠다님. nil이면 원래대로. 흑백·선 그림에서는 아무것도 바꾸지 않음
    func immerse(_ h: Hung?) {
        if let h, look == .color, h.palette.count >= 3 {
            immerseTarget = h.palette
            if immerseCur == nil || immerseAmt < 0.02 { immerseCur = h.palette }
            immerseGoal = 1
            setMotes(h.palette)
        } else {
            immerseGoal = 0
            if var m = motes?.components[ParticleEmitterComponent.self] { m.isEmitting = false; motes?.components.set(m) }
        }
    }

    func tickImmerse(_ dt: Float) {
        guard !tinted.isEmpty, immerseGoal != 0 || immerseAmt > 0 else { return }
        let before = immerseAmt
        immerseAmt += (immerseGoal - immerseAmt) * min(1, dt * 2.2)
        if abs(immerseAmt - immerseGoal) < 0.01 { immerseAmt = immerseGoal }
        if let tg = immerseTarget, var cur = immerseCur {
            for k in 0..<min(cur.count, tg.count) { cur[k] += (tg[k] - cur[k]) * min(1, dt * 2.5) }
            immerseCur = cur
        }
        guard abs(before - immerseAmt) > 0.0005 || immerseGoal > 0, let pal = immerseCur else { return }
        func lum(_ c: SIMD3<Float>) -> Float { c.x * 0.3 + c.y * 0.59 + c.z * 0.11 }
        // 채도를 한 번 더 올림 (그림의 색이 방 전체에 선명하게)
        func rich(_ c: SIMD3<Float>, _ k: Float) -> SIMD3<Float> {
            let l = SIMD3<Float>(repeating: lum(c))
            return simd_clamp(l + (c - l) * k, .zero, SIMD3<Float>(repeating: 1.2))
        }
        let wallC = rich(pal[0] * 0.55 + pal[1] * 0.6, 1.6)
        let floorC = rich(pal[2], 1.4) * 0.75 + SIMD3<Float>(repeating: 0.03)
        Tex.with(look) {
            for (e, tex, base, floor) in tinted {
                // 벽은 원래 밝기 차이(해 쪽·그늘)를 살려 같은 색으로 — 벽 무늬가 거의 안 보일 만큼 진하게
                let shade = max(0.55, min(1.15, lum(base) / max(0.05, lum(Worlds.safe(tint, min: 0.36)))))
                let target = floor ? floorC : wallC * shade
                let c = base + (target - base) * immerseAmt
                e.model?.materials = [Tex.unlit(tex, tint: c)]
            }
        }
    }

    private func setMotes(_ p: [SIMD3<Float>]) {
        if motes == nil {
            var pe = ParticleEmitterComponent()
            pe.emitterShape = .box
            pe.emitterShapeSize = SIMD3<Float>(max(0.5, halfSize.x * 2 - 0.6), 2.0, max(0.5, halfSize.y * 2 - 0.6))
            pe.birthLocation = .volume
            pe.speed = 0.04
            pe.speedVariation = 0.03
            pe.mainEmitter.birthRate = min(260, 18 * halfSize.x * halfSize.y * 4)
            pe.mainEmitter.lifeSpan = 7
            pe.mainEmitter.size = 0.018
            pe.mainEmitter.sizeVariation = 0.01
            pe.mainEmitter.noiseStrength = 0.06
            pe.mainEmitter.noiseScale = 1
            pe.mainEmitter.noiseAnimationSpeed = 0.2
            pe.mainEmitter.blendMode = .additive
            pe.mainEmitter.opacityCurve = .gradualFadeInOut
            let e = Entity()
            e.components.set(pe)
            e.position = center + SIMD3<Float>(0, 1.2, 0)
            e.orientation = simd_quatf(angle: -angle, axis: [0, 1, 0])
            layer(e, 20)
            local.addChild(e)
            motes = e
        }
        guard let e = motes, var pe = e.components[ParticleEmitterComponent.self] else { return }
        let a = Tex.with(look) { Tex.color(p[0]) }, b = Tex.with(look) { Tex.color(p[1]) }
        pe.mainEmitter.color = .evolving(start: .single(a), end: .single(b))
        pe.isEmitting = true
        e.components.set(pe)
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
        if let e = g.entity("bulbs", lineMode ? Ink.line : UnlitMaterial(color: Tex.color(SIMD3<Float>(1, 0.84, 0.55)))) { local.addChild(e) }
    }

    private func addClouds(ceilY: Float) {
        let n = Worlds.cloudCount(room.weather)
        guard n > 0 else { return }
        let dim: Float = room.weather == "storm" ? 0.45 : (["rain", "drizzle"].contains(room.weather) ? 0.7 : 1)
        let wind: Float = room.weather == "wind" || room.weather == "storm" ? 6 : 2
        let dir = simd_normalize(SIMD3<Float>(Float.random(in: -1...1), 0, Float.random(in: -1...1)) + SIMD3<Float>(0.01, 0, 0))
        let lit = Worlds.haze(room.time, weather: room.weather) * 0.4 + tint * 0.6
        // 구름 모양 여섯 가지 (뭉게·층적운·새털·비구름) 중 날씨에 맞는 것을 섞어 씀 — 모양·크기·방향이 다 다르게
        let kinds: [Int]
        switch room.weather {
        case "storm", "rain": kinds = [5, 5, 3, 0, 5, 2]
        case "wind": kinds = [4, 3, 4, 1, 0, 4]
        case "cloudy": kinds = [0, 1, 2, 3, 5, 1]
        default: kinds = [0, 3, 1, 4, 2, 0]
        }
        for i in 0..<n {
            var m = UnlitMaterial(color: .white)
            if let t = Tex.get("cloud_\(kinds[i % kinds.count])", folder: "sky") {
                m.color = .init(tint: Tex.color(lit * dim, alpha: 1), texture: .init(t))
            }
            m.blending = .transparent(opacity: .init(floatLiteral: 0.92))
            m.writesDepth = false                 // 반투명 판이 뒤의 나무·물건을 네모나게 지우지 않게
            let wdt = Float.random(in: 70...160)
            let e = ModelEntity(mesh: .generatePlane(width: wdt, depth: wdt * Float.random(in: 0.42...0.6)), materials: [m])
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
            // 하늘 세계에도 (천장·벽 너머로 내려오는 게 보이게). 천장 높이에서 사라짐 —
            // 더 내려오면 포털 앞(옆방 자리)에서도 그려져 옆방에 비가 내리는 것처럼 보임
            let e = Self.precip(w, size: SIMD3<Float>(halfSize.x * 2 + 8, 0.1, halfSize.y * 2 + 8), height: 7, look: look)
            e.position = SIMD3<Float>(center.x, ceilY + 7, center.z)
            layer(e, 20)
            e.orientation = simd_quatf(angle: -angle, axis: [0, 1, 0])
            world.addChild(e)
            emitters.append(e)
        }
        guard outdoor else { return }
        for r in rects.sorted(by: { ($0.1.x - $0.0.x) * ($0.1.y - $0.0.y) > ($1.1.x - $1.0.x) * ($1.1.y - $1.0.y) }).prefix(5) {
            let c = L.flat((r.0 + r.1) / 2)
            // 벽에서 35cm 안쪽에서만 (눈송이가 흩날려도 벽 너머로 넘어가지 않게)
            let sx = r.1.x - r.0.x - 0.7, sz = r.1.y - r.0.y - 0.7
            guard sx > 0.3, sz > 0.3, sx * sz > 0.4 else { continue }
            var list: [Entity] = []
            if wet {
                // 눈·비는 1m 안팎 칸으로 나눠 뿌리고, 머리 근처 칸은 끔 — 눈앞을 스치는 눈송이가 크게 번쩍이며
                // 깜빡이던 것(눈높이 1~2m에서 심했음)을 없앰
                let lo = r.0 + SIMD2<Float>(0.35, 0.35)
                let nx = max(1, Int((sx / 1.0).rounded())), nz = max(1, Int((sz / 1.0).rounded()))
                let tx = sx / Float(nx), tz = sz / Float(nz)
                for ix in 0..<nx {
                    for iz in 0..<nz {
                        let a = lo + SIMD2<Float>(Float(ix) * tx, Float(iz) * tz)
                        let b = a + SIMD2<Float>(tx, tz)
                        let tc = L.flat((a + b) / 2)
                        let e = Self.precip(w, size: SIMD3<Float>(tx, 0.05, tz), height: room.ceil, look: look)
                        e.position = SIMD3<Float>(tc.x, ceilY - 0.08, tc.y)
                        list.append(e)
                        precipTiles.append((e, a, b))
                    }
                }
            }
            if w == "wind" {
                let e = Self.windBits(room.place, size: SIMD3<Float>(sx, 1.6, sz), look: look)
                e.position = SIMD3<Float>(c.x, floorY + 1.1, c.y)
                list.append(e)
            }
            if room.time == "night" || room.time == "dusk",
               ["camp", "forest", "valley", "village"].contains(room.place), ["clear", "cloudy", "wind"].contains(w) {
                let e = Self.fireflies(size: SIMD3<Float>(sx, 1.2, sz), look: look)
                e.position = SIMD3<Float>(c.x, floorY + 0.9, c.y)
                list.append(e)
            }
            for e in list {
                e.orientation = simd_quatf(angle: -angle, axis: [0, 1, 0])
                // 방 안 입자는 하늘 세계의 나무·울타리(반투명 오려 내기)보다 늘 나중에 그림 — 그리는 순서가 프레임마다 바뀌면
                // 그 앞을 지나는 눈·비가 깜빡임 (1~2m 높이: 뒤에 울타리·나무·먼 산이 있는 높이)
                layer(e, 20)
                local.addChild(e)
                roomEmitters.append(e)
            }
        }
    }

    /// 방 안 눈·비 칸 (엔티티, 평면 좌표 사각형)
    private var precipTiles: [(Entity, SIMD2<Float>, SIMD2<Float>)] = []
    private var roomOn = false

    /// 머리(평면 좌표) 50cm 안에 걸친 눈·비 칸은 새로 뿌리지 않음 (지금 방만, 매 프레임)
    func avoidHead(_ p: SIMD2<Float>) {
        guard roomOn else { return }
        for (e, a, b) in precipTiles {
            let d = simd_length(simd_max(simd_max(a - p, p - b), SIMD2<Float>(0, 0)))
            let on = d > 0.8                  // 머리 둘레 80cm 안에서는 내리지 않음 (눈앞 깜빡임)
            if var pe = e.components[ParticleEmitterComponent.self], pe.isEmitting != on {
                pe.isEmitting = on
                e.components.set(pe)
            }
        }
    }

    /// 입자를 뿜을지. sky: 하늘 세계 쪽(지금 방과 이웃 방 — 문 너머로 이미 내리고 있게), room: 방 안(지금 방만)
    func setActive(sky: Bool, room: Bool) {
        roomOn = room
        for (list, on) in [(emitters, sky), (roomEmitters, room)] {
            for e in list {
                if var pe = e.components[ParticleEmitterComponent.self], pe.isEmitting != on {
                    pe.isEmitting = on
                    e.components.set(pe)
                }
                if !on { e.isEnabled = false } else if !e.isEnabled { e.isEnabled = true }
            }
        }
    }

    /// 매 프레임: 구름 흐름, 물결, 번개
    func tick(_ dt: Float, active: Bool) {
        guard active else { return }
        scenery?.tick(dt)
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
        jelly?.tick(dt)
        neon?.tick(dt)
        for i in flows.indices {
            var f = flows[i]
            f.3 = (f.3 + f.2 * dt / 3.5).truncatingRemainder(dividingBy: 1)        // 물길 시작(폭포) → 끝 쪽으로 흐름, 폭포는 아래로
            f.1.textureCoordinateTransform.offset = SIMD2<Float>(0, f.3)
            f.0.model?.materials = [f.1]
            flows[i] = f
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
    static func precip(_ w: String, size: SIMD3<Float>, height: Float, look: LookMode = .color) -> Entity {
        let snow = w == "snow" || w == "heavysnow"
        var pe = snow ? ParticleEmitterComponent.Presets.snow : ParticleEmitterComponent.Presets.rain
        if look == .line {
            // 선 그림: 흰 바탕에 더해지는(additive) 빛은 보이지 않음 → 보통 섞기로, 눈은 작은 동그라미 선, 비는 짧은 세로 선
            pe.mainEmitter.blendMode = .alpha
            pe.mainEmitter.color = .constant(.single(UIColor(white: 0.12, alpha: snow ? 0.9 : 0.6)))
            if let t = snow ? Dots.ring : Dots.dash { pe.mainEmitter.image = t }
        } else if look == .mono && !snow {
            pe.mainEmitter.color = .constant(.single(UIColor(white: 0.8, alpha: 0.6)))
        }
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
        if look == .line { pe.mainEmitter.size *= snow ? 2.2 : 1.4 }      // 동그라미 선이 보일 만큼
        let e = Entity()
        e.components.set(pe)
        return e
    }

    /// 바람: 나뭇잎(자연)이나 먼지(도시·바다)가 옆으로 날림
    static func windBits(_ place: String, size: SIMD3<Float>, look: LookMode = .color) -> Entity {
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
        let c: UIColor = look == .line ? UIColor(white: 0.25, alpha: 1)
            : (look == .mono ? UIColor(white: nature ? 0.5 : 0.8, alpha: nature ? 1 : 0.6)
               : (nature ? UIColor(red: 0.62, green: 0.48, blue: 0.22, alpha: 1) : UIColor(red: 0.85, green: 0.82, blue: 0.75, alpha: 0.6)))
        pe.mainEmitter.color = .constant(.single(c))
        pe.mainEmitter.opacityCurve = .gradualFadeInOut
        let e = Entity()
        e.components.set(pe)
        return e
    }

    /// 반딧불 (밤·해질녘의 자연)
    static func fireflies(size: SIMD3<Float>, look: LookMode = .color) -> Entity {
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
        pe.mainEmitter.color = .constant(.single(look == .line ? UIColor(white: 0.2, alpha: 1)
                                                 : (look == .mono ? UIColor(white: 0.95, alpha: 1) : UIColor(red: 0.85, green: 1, blue: 0.45, alpha: 1))))
        pe.mainEmitter.blendMode = look == .line ? .alpha : .additive
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
        let seg = 160, rings = 80                // 촘촘하게 (꼭대기 쪽 그림이 늘어나 보이지 않게)
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
