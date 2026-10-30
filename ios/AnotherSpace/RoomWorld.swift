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
            d.bands = [Band(tex: "pano_peaks", radius: 270, height: 92, base: -6, aspect: 0, layer: 0)]     // 둘레 절벽은 입체로 (addCliffRing)
            d.trees = [Trees(tex: "tree_pine", count: 6, h: 6...11, d: 4...22)]
            d.rocks = Rocks(tex: "rock", count: 16, size: 0.6...3, d: 1...24)
        case "sea":
            d.bands = [Band(tex: "far_islands", radius: 280, height: 16, base: -1.5, aspect: 8, layer: 0)]
            d.trees = [Trees(tex: "tree_twisted", count: 5, h: 6...10, d: 1.5...6)]
            d.rocks = Rocks(tex: "basalt", count: 8, size: 0.5...2.2, d: 5...26)
            d.sea = true
        case "village":
            d.bands = [Band(tex: "pano_hills", radius: 270, height: 68, base: -7, aspect: 0, layer: 0),
                       Band(tex: "mid_village", night: "mid_village_night", radius: 100, height: 36, base: -4, aspect: 8, layer: 1)]
            d.trees = [Trees(tex: "tree_broad", count: 8, h: 7...12, d: 4...25)]
        case "city":
            d.bands = [Band(tex: "far_city", night: "far_city_night", radius: 260, height: 160, base: -30, aspect: 2, layer: 1)]
            d.city = true
        case "cafe":
            // 창밖: 보도·차도·맞은편 입체 거리 건물(1층 가게)은 addCafeStreet, 그 뒤로 먼 도시 띠
            d.bands = [Band(tex: "far_city", night: "far_city_night", radius: 70, relative: true, height: 90, base: -2, aspect: 2, layer: 1)]
            // 보도 위 가로수
            d.trees = [Trees(tex: "tree_broad", count: 6, h: 4.5...7, d: 1.0...2.2, aspect: 0.55)]
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
    let world: Entity               // 포털 너머 세계 (같은 세계 무리면 대표 방의 것을 함께 씀)
    let local = Entity()            // 방 안 (저장 좌표). 지금 방·열린 문으로 보이는 방만 켬 (ExploreSession.updateRoomVisibility)
    let doorsRoot = Entity()        // 실제 문짝 (저장 좌표) — 문 양쪽 방 어디서든 보여야 해서 local 과 따로, 늘 켬
    /// 같은 세계 무리(문으로 이어진 같은 테마 방들)의 대표 방 세계. nil이면 이 방이 대표(세계를 직접 만듦).
    /// 무리는 하늘·땅·풍경·날씨 하늘 쪽을 대표 방이 무리 전체 둘레에 하나만 만들고, 나머지 방은 그 세계를 포털 너머로 함께 봄 —
    /// 예전엔 방마다 따로 만들어 같은 테마 옆방끼리 창밖 풍경·요트·해파리 자리가 달라 문 너머로 겹치거나 엉뚱한 곳(내 쪽 방 자리)에 크게 보였음
    private(set) var host: RoomWorld?
    /// 무리 방 번호들 (혼자면 [이 방])
    let groupIds: [Int]
    var ownsWorld: Bool { host == nil }
    /// 이 방이 세계를 빌려 쓰는 대표 방 번호 (혼자거나 대표면 자기 번호)
    var hostId: Int { host?.room.id ?? room.id }
    private(set) var tint: SIMD3<Float>
    private(set) var shades: [Float]
    private var skyEntity: ModelEntity?
    private var skyMat: UnlitMaterial?
    private var flashMat: UnlitMaterial?
    private var clouds: [(Entity, SIMD3<Float>)] = [] { didSet { cloudLeft = clouds.map { _ in 0 }; cloudAt = clouds.map { _ in nil } } }
    private var cloudLeft: [Float] = []                 // 구름마다 지금 맡긴 이동이 끝나기까지 남은 시간
    private var cloudAt: [SIMD3<Float>?] = []           // 구름마다 지금 맡긴 이동의 끝 자리
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
    private(set) var center = SIMD3<Float>(0, 0, 0)         // 세계 가운데 바닥 (저장 좌표) — 같은 세계 무리 전체의 가운데
    private(set) var halfSize = SIMD2<Float>(1, 1)           // 세계 반 크기 (격자 방향, m) — 무리 전체
    private(set) var roomCenter = SIMD3<Float>(0, 0, 0)     // 이 방 가운데 바닥
    private(set) var roomHalf = SIMD2<Float>(1, 1)           // 이 방 반 크기
    let angle: Float
    private var sortGroup: ModelSortGroup { Sorting.group }       // 모든 방이 같은 묶음 (포털 0번 → 방 안 반투명 25~30번)
    /// 문 번호 → 이 방 쪽 문짝 (닫히면 이 방 벽처럼 보임). 열 때 가로로 오므라듦
    private(set) var doorPanels: [Int: [Entity]] = [:]
    /// 다른 세계 옆방과 맞댄 벽 뒤 울타리 (옆방 번호 → 엔티티). 그 울타리는 벽 너머 = 옆방 자리(또는 벽 두께 속)에 섬 →
    /// 그 옆방에 서서 열린 문 너머로 이 방을 볼 때 내 앞(옆방 쪽)에 있는 세계 것이 이 방 포털에 크게·엉뚱한 각도로 비침 (포털은 자르지 않으므로).
    /// 그래서 내가 그 옆방(또는 그 사이 문 자리)에 있는 동안은 끔 — 그때는 어차피 이 방 쪽에서 그 벽 뒤를 볼 일이 없음
    private(set) var barrierToward: [Int: [Entity]] = [:]
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

    private let tallCells: Set<Int64>        // 1m 넘는 가구 칸 (카페 포스터 자리)
    init(_ d: SpaceData, _ r: RoomRec, layout: Layout, blocked: Set<Int64> = [], tall: Set<Int64> = [], group: [Int] = [], host: RoomWorld? = nil) {
        tallCells = tall
        self.blocked = blocked
        room = r
        groupIds = group.isEmpty ? [r.id] : group
        if let h = host {
            self.host = h
            world = h.world
        } else {
            world = Entity()
        }
        look = r.lookMode
        style = Worlds.style(r.place, time: r.time)
        angle = d.rec.angle
        tint = Worlds.timeTint(r.time, indoor: Worlds.indoor(r.place)) * Worlds.weatherDim(r.weather)
        shades = Worlds.contrast(r.time, weather: r.weather)
        if host == nil { world.components.set(WorldComponent()) }
        Tex.with(look) { build(d, layout) }
    }

    /// 벽 꾸밈 앞에 새로 가구가 보이면 다른 빈 벽으로 옮김
    func recheckDecor(blocked: Set<Int64>, tall: Set<Int64>) {
        // 탐험 중에 다시 만드는 것은 모두 이 방 표시 방식으로 (선 그림·흑백 방에 컬러가 섞이지 않게)
        Tex.with(look) {
            scenery?.relocate(blocked: blocked, tall: tall)
            creek?.refresh(blocked: blocked)          // 계곡 물: 새로 알게 된 가구 자리는 비우고 다시 그림
        }
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
        if r.place == "valley" { l += [("river", "tex"), ("river_hi", "tex"), ("fall", "tex"), ("pebble", "tex"), ("rock", "tex"), ("cliff", "tex"), ("ripple", "tex"), ("grass", "tex"), ("pine_branch", "tex"), ("bark", "tex")] }
        if r.place == "valley" { for i in 0..<6 { l.append(("fish_\(i)", "tex")) } }
        if r.place == "cafe" { l += [("menu_board", "tex"), ("cafe_poster_0", "tex"), ("cafe_poster_1", "tex"), ("cafe_poster_2", "tex"), ("cafe_poster_3", "tex"),
                                     ("speaker_metal", "tex"), ("speaker_grille", "tex"), ("concrete", "tex"), ("plaster", "tex"), ("canvas", "tex"),
                                     (night ? "townhouse_night" : "townhouse", "tex"), (night ? "shopfront_night" : "shopfront", "tex")] }
        if r.place == "village" { l += [("house_stucco", "tex"), ("house_plaster", "tex"), ("house_stone", "tex"), ("house_wood", "tex"), ("brick", "tex"), ("roof_tile", "tex")] }
        if r.place == "sea" { l += [("jelly_bell", "tex"), ("jelly_tent", "tex"), ("jelly_arm", "tex"), ("glow", "tex"), ("spark_dot", "tex")] }
        if r.place == "city" { for i in 0..<16 { l += [(String(format: "neon_%02da", i), "tex"), (String(format: "neon_%02db", i), "tex")] } }
        if Worlds.cloudCount(r.weather) > 0 { for i in 0..<6 { l.append(("cloud_\(i)", "sky")) } }
        return l
    }

    // MARK: 포털 그리는 순서
    /// 이 방의 포털 면(천장·벽·창·문 자리 판·문 위 벽). 지금 방 것을 가장 나중에, 이웃 방, 먼 방 순서로 그림 — 'portalTier'.
    /// v0.5.18에서 공간 뿌리의 OpacityComponent를 뺀 뒤로는 포털 면끼리 먼 것→가까운 것 순서가 보장되지 않아,
    /// 다른 테마 방에 들어가 문 쪽을 돌아보면 지금 방의 문 자리 판(지금 방 풍경)보다 지나온 방의 벽·천장 포털이 나중에 그려져
    /// 지나온 방 풍경이 그대로 보이곤 했음
    private var portals: [ModelEntity] = []
    private var portalTierNow = -1
    private func addPortal(_ e: ModelEntity) {
        portals.append(e)
        e.components.set(ModelSortGroupComponent(group: sortGroup, order: -30))
    }
    /// 0: 먼 방, 1: 지금 방의 이웃 방, 2: 지금 방
    func setPortalTier(_ k: Int) {
        guard k != portalTierNow else { return }
        portalTierNow = k
        let order = Int32(-30 + 10 * min(2, max(0, k)))
        for e in portals { e.components.set(ModelSortGroupComponent(group: sortGroup, order: order)) }
    }

    /// 선 그림 외곽선 굵기: 멀리 있을수록 굵게 (눈에 보이는 굵기가 실내·소품과 비슷하게)
    private func inkW(_ p: SIMD3<Float>) -> Float { Ink.width(at: simd_distance(p, center)) }

    private func layer(_ e: Entity, _ order: Int) {
        e.components.set(ModelSortGroupComponent(group: sortGroup, order: Int32(order)))
    }

    /// 불빛 둘레 은은한 빛무리 (나를 향하지 않아도 둥글게 보이도록 십자로 세 장, 깊이를 쓰지 않고 맨 나중에 그림)
    @discardableResult
    private func glowSprite(at c: SIMD3<Float>, size: Float, color: SIMD3<Float>) -> Entity? {
        guard let tx = Tex.get("glow", color: look == .color), let mk = Tex.get("glow_a", raw: true) else { return nil }
        var m = UnlitMaterial(color: Tex.color(color))
        var tp = MaterialParameters.Texture(tx); tp.sampler = Tex.clamp
        m.color = .init(tint: Tex.color(color), texture: tp)
        var mp = MaterialParameters.Texture(mk); mp.sampler = Tex.clamp
        m.blending = .transparent(opacity: .init(scale: 0.5, texture: mp))
        m.writesDepth = false
        var q = Geo()
        for k in 0..<3 {
            let a = Float(k) / 3 * .pi
            q.card(c, SIMD3<Float>(cos(a), 0, sin(a)), SIMD3<Float>(0, 1, 0), w: size, h: size)
        }
        q.card(c, SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 0, 1), w: size, h: size)
        guard let e = q.entity("glow", m) else { return nil }
        layer(e, 30); world.addChild(e)
        return e
    }

    /// 안의 모든 그림에 그리는 순서를 줌. 반투명(깊이를 쓰지 않는) 것은 나무·바위·건물보다 나중에(큰 순서) 그려야
    /// 앞에 있을 땐 그 위에, 뒤에 있을 땐 그 뒤로 자연스럽게 보임 (먼저 그리면 뒤의 나무가 덮어써서 네모나게 깨져 보였음)
    private func layerAll(_ e: Entity, _ order: Int) {
        if e is ModelEntity { layer(e, order) }
        for c in e.children { layerAll(c, order) }
    }

    // MARK: 만들기
    private func build(_ d: SpaceData, _ L: Layout) {
        defer { Geo.inkEye = nil }
        let rec = d.rec
        let floorY = rec.floorY
        let ceilY = floorY + room.ceil
        let rects = L.rects(room.id)                 // 이 방이 차지하는 곳 (문·통로 포함, 평면 좌표 m)
        // 세계 가운데·크기 = 같은 세계 무리 전체 (혼자면 이 방) — 하늘·땅·풍경·나무가 무리 둘레에 하나로 놓임.
        // 방 안 것(먼지·그림 빛 입자 등)은 이 방 자체 가운데·크기(roomCenter·roomHalf)
        func box(_ rs: [PRect]) -> (SIMD3<Float>, SIMD2<Float>)? {
            guard let f = rs.first else { return nil }
            var lo = f.0, hi = f.1
            for r in rs { lo = simd_min(lo, r.0); hi = simd_max(hi, r.1) }
            let c = L.flat((lo + hi) / 2)
            return (SIMD3<Float>(c.x, floorY, c.y), (hi - lo) / 2)
        }
        if let b = box(rects) { roomCenter = b.0; roomHalf = b.1 }
        if let b = box(groupIds.flatMap { L.rects($0) }) { center = b.0; halfSize = b.1 } else { center = roomCenter; halfSize = roomHalf }
        // 선 그림: 모든 선을 이 방 가운데 눈높이에서 본 거리에 맞춘 같은 펜 굵기로 (Geo.stroke)
        Geo.inkEye = lineMode ? roomCenter + SIMD3<Float>(0, 1.5, 0) : nil
        let R = simd_length(halfSize)
        // 실내 장소(카페·집)는 바깥벽에 창을 냄 (카페는 바닥 가까이부터 천장 밑까지 통유리, 집은 벽마다 한두 개 창)
        // 벽 너머 45cm 안 옆방이 같은 테마(같은 세계)면 그 벽엔 창을 내지 않음 (두 방이 한 공간으로 이어져 보여 창이 겹쳐 보임).
        // 옆방이 다른 테마면 보통 바깥벽처럼 창을 냄 (v0.5.23은 테마와 상관없이 막아, 다른 방에 둘러싸인 거실이 카페·집이면 창이 하나도 없었음)
        // 벽 너머(2m 안)에 이 방 자신이 있으면(ㄱ자 방·같은 방 통로) 늘 창을 내지 않음 → -1 도 '같음'에 넣음
        var mySegs = L.walls.filter { $0.room == room.id }
        var sameNear: Set<Int> = [-1]
        for s in mySegs {
            for id in [s.nearRoom, s.behind] where id > 0 && !sameNear.contains(id) {
                if groupIds.contains(id) { sameNear.insert(id); continue }
                if let o = d.rec.room(id), o.place == room.place, o.weather == room.weather, o.time == room.time, o.lookMode == room.lookMode { sameNear.insert(id) }
            }
        }
        func shut(_ s: WallSeg) -> Bool { sameNear.contains(s.nearRoom) || (s.behind != 0 && sameNear.contains(s.behind)) }
        for i in mySegs.indices where mySegs[i].window && shut(mySegs[i]) { mySegs[i].window = false }
        let segs = Self.withWindows(mySegs, place: room.place, doors: L.doors, roomId: room.id, nearSame: sameNear)
        // 계곡: 바깥 강 물길과 방 안 개울을 먼저 정함 (개울이 드나드는 벽 자리는 울타리를 비워야 해서 벽보다 먼저)
        let shared = host != nil                    // 같은 세계 무리의 다른 방: 하늘 세계 쪽은 대표 방이 이미 만들어 둠
        if room.place == "valley" {
            if !shared { planRiver(L, rec, floorY: floorY) }
            // 무리의 다른 방: 대표 방이 만든 바깥 강에서 가장 가까운 이 방 벽으로 물이 갈라져 들어옴
            let near = shared ? host?.riverNear : (riverFeedsRoom ? riverPts.last : riverPts.min { simd_distance($0, center) < simd_distance($1, center) })
            let c = ValleyCreek(room: room, layout: L, floorY: floorY, blocked: blocked, riverNear: near, entryHint: riverFeedsRoom ? riverEntry : nil,
                                riverWidth: (shared ? host?.riverW.min() : riverW.min()) ?? 2.4, look: look, tint: tint,
                                // 무리의 다른 방: 대표 방 절벽(무리 둘레 +40m)에 닿기 전에 바위 틈으로 (협곡은 대표 방 물길에만 냄)
                                streamLen: shared ? 24 : simd_length(halfSize) + 235, endInRocks: shared)
            if c.ok {
                creek = c
                if riverFeedsRoom, let e = c.entry { waterGaps.append(e.0) }
                if let x = c.exitPt { waterGaps.append(x.0) }
            }
        }

        // 바닥 (바닥 위 6mm)
        if let m = Self.flatMesh(rects, L, y: floorY + 0.006, tile: style.floorTile) {
            let e = ModelEntity(mesh: m, materials: [Tex.unlit(style.floor, tint: Worlds.safe(tint, min: 0.4))])
            local.addChild(e)
            tinted.append((e, style.floor, Worlds.safe(tint, min: 0.4), true))
        }
        // 천장 = 하늘 세계로 열린 창 (천장보다 2cm 아래)
        if let m = Self.flatMesh(rects, L, y: ceilY - 0.02, tile: 1) {
            portalEntity(m, clipAt: SIMD3<Float>(roomCenter.x, ceilY - 0.02, roomCenter.z), normal: SIMD3<Float>(0, -1, 0))
        }
        if style.open {
            openWalls(segs, L, floorY: floorY, ceilY: ceilY)
        } else {
            solidWalls(segs, L, floorY: floorY, ceilY: ceilY)
            if room.place == "cafe" { addCafeCeiling(rects, L, y: ceilY - 0.03) } else { addSkylightFrame(rects, L, y: ceilY - 0.06) }
        }
        addDoors(L, floorY: floorY, ceilY: ceilY)

        let dc = Decor.of(room.place)
        if !shared {
            addSky()
            addGround(dc, R: R, floorY: floorY)
            addBands(dc, R: R, floorY: floorY)
            addThings(dc, rec: rec, L, floorY: floorY)
        }
        addFeature(L, segs: segs, floorY: floorY, ceilY: ceilY)
        if dc.paintings {
            paintSegs = segs.filter { !$0.window }
            paintLayout = L
            paintFloor = floorY
            local.addChild(paintRoot)
        }
        if dc.stringLights { addStringLights(segs, L, ceilY: ceilY) }
        if !shared { addClouds(ceilY: ceilY) }       // 선 그림이면 구름 윤곽선 그림(cloud_n_ln)으로
        addWeather(rects, L, rec: rec, floorY: floorY, ceilY: ceilY, sky: !shared)
        if lineMode { addOutlines(segs, L, floorY: floorY, ceilY: ceilY) }
        let sc = Scenery(room: room, look: look, tint: tint, center: center, halfSize: halfSize, angle: angle,
                         floorY: floorY, ceilY: ceilY, segs: segs, layout: L, sortGroup: sortGroup, blocked: blocked, tall: tallCells,
                         far: !shared, roomCenter: roomCenter, roomHalf: roomHalf)
        world.addChild(sc.far)
        local.addChild(sc.near)
        scenery = sc
        setActive(sky: false, room: false)
    }

    // MARK: 선 그림
    /// 선 그림: 방의 꺾이는 곳만 검은 선으로 — 바닥·천장과 벽이 만나는 줄, 벽 모서리(방향이 바뀌거나 벽이 끝나는 곳), 창 테두리, 문 위 가로대
    private func addOutlines(_ segs: [WallSeg], _ L: Layout, floorY: Float, ceilY: Float) {
        var g = Geo()
        let w: Float = 0.011
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
                let (w0, w1) = Self.windowBand(place: room.place, top: top)
                if room.place == "cafe" {
                    let n = max(1, Int((len / 1.1).rounded()))
                    for i in 1..<n { let q = s.a + dir * (len * Float(i) / Float(n)) + s.n * off; g.stroke(p3(q, w0), p3(q, w1), width: w) }
                } else if room.place == "home" {
                    let q = (inA + inB) / 2
                    g.stroke(p3(q, w0), p3(q, w1), width: w)
                    g.stroke(p3(inA, (w0 + w1) / 2), p3(inB, (w0 + w1) / 2), width: w)
                }
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

    // MARK: 포털 면
    /// 포털 엔티티는 방마다 천장 하나·벽 하나·창 하나(+ 문 자리 판)만 — 기준서 7.
    /// 포털 엔티티 하나마다 렌더러가 그 너머 세계 전체를 한 번씩 더 그림(그림 수가 포털 수만큼 곱해짐). '모두 같게'면 모든 방 포털이
    /// 한 세계를 보므로 그 곱이 가장 큼 — 무거운 세계(도시 네온·바다·숲 나무)에서 기기가 다시 켜지고, 고개를 돌리면 그림이 늦어 현실이 겹쳤음.
    /// (v0.5.30이 벽을 평면마다 따로 자르는 포털(clippingMode) 수십~수백 개로 나눈 뒤부터 생김. v0.5.33의 '방향마다 2묶음'도 방마다 10개 남짓이라
    ///  그대로였음. v0.5.29까지처럼 벽 전체를 한 엔티티로)
    /// 벽·창 포털은 자르지 않음(평면이 여럿이라 하나로 못 자름) → '세계 것은 어느 포털 앞(방 쪽)에도 놓지 않는다'로 맞춤:
    /// 나무·바위는 걸을 수 있는 곳을 피하고(addThings), 울타리는 벽 평면 뒤(openWalls), 눈·비는 다른 세계 방·실내 방 자리를 비움(addWeather)
    private struct PortalPlanes {
        var geo = Geo()
        var isEmpty = true
        mutating func face(_ a: SIMD3<Float>, _ b: SIMD3<Float>, toward n: SIMD3<Float>, y0: Float, y1: Float) {
            geo.face(a, b, toward: n, y0: y0, y1: y1, u0: 0, u1: 1)
            isEmpty = false
        }
    }

    /// 포털 면 엔티티 하나. clip: 평면 하나로 된 면(천장)만 — 그 평면의 normal 쪽(방 쪽) 세계 것은 그리지 않음
    @discardableResult
    private func portalEntity(_ m: MeshResource, clipAt point: SIMD3<Float>? = nil, normal: SIMD3<Float> = .zero) -> ModelEntity {
        let e = ModelEntity(mesh: m, materials: [PortalMaterial()])
        var pc = PortalComponent(target: world)
        if let pt = point { pc.clippingMode = .plane(PortalComponent.Plane(position: pt, normal: normal)) }
        e.components.set(pc)
        addPortal(e)
        local.addChild(e)
        return e
    }

    private func addPortalPlanes(_ pp: PortalPlanes, name: String) {
        if !pp.isEmpty, let m = pp.geo.mesh(name) { portalEntity(m) }
    }

    // MARK: 벽
    /// 바깥 장소: 벽 자리 전체가 하늘 세계로 열린 창(포털 하나). 그 너머에 테마마다 입체 울타리(통나무 울타리·덤불·돌무더기·말뚝 밧줄·돌담·옥상 난간)를
    /// 둘러 세워 '막힌 곳'으로 보이게 — 기준서 2.
    /// 울타리 자리는 벽 조각(스캔 5cm 계단)마다가 아니라, 같은 방향·가까운 줄(15cm 안)의 벽을 모은 '곧은 줄'마다 정함:
    /// 조각마다 따로 세우고 양끝을 늘리면 계단마다 울타리가 5cm 어긋나 겹쳐(같은 높이 윗면이 겹쳐 끊임없이 깜빡임), 모서리엔 말뚝이 둘씩 섰음.
    /// 자리 규칙 (포털은 자르지 않으므로, 세계 것은 방 쪽에 두지 않음):
    ///  · 너머가 바깥: 울타리 앞면이 벽 평면 1cm 뒤 (튀어나오는 만큼 barrierProt 더 뒤로) — 방 바닥에 가려 잘려 보이지 않게
    ///  · 너머 45cm 안이 같은 세계 옆방: 번호가 작은 방만, 두 벽 사이 한가운데에 얇게 하나 (양쪽 방이 같은 세계라 둘 다 보임 → 두 줄로 겹치지 않게)
    ///  · 너머가 이 방 자신(ㄱ자·ㄷ자 방의 맞은편): 방향으로 한쪽만, 한가운데에 얇게 하나
    ///  · 너머가 다른 세계 옆방·문 칸: 내 벽 평면 뒤에 얇게 (그 방에선 그 방 세계가 보이므로 안 보임)
    /// 줄 끝은 모서리에서 다른 줄과 만나도록 띄운 거리만큼만 늘림 (걸을 수 있는 곳·문 자리로는 늘리지 않음)
    private func openWalls(_ segs: [WallSeg], _ L: Layout, floorY: Float, ceilY: Float) {
        var portal = PortalPlanes()
        /// 울타리 줄 위 한 점 (평면 좌표): 방향 n(방 안쪽), 줄 따라 좌표 u, 줄 자리 c(= n·점), 세울 두께, 얇게, 한가운데 공유 줄인지
        struct Sample { let n: SIMD2<Float>; let u: Float; let c: Float; let depth: Float; let thin: Bool; let shared: Bool; let outside: Bool; let toward: Int }
        var samples: [Sample] = []
        let base = barrierProt + 0.01                                      // 울타리 앞면이 벽 평면 1cm 뒤
        let step: Float = 0.05
        for s in segs {
            let a2 = L.flat(s.a), b2 = L.flat(s.b)
            let a = SIMD3<Float>(a2.x, floorY, a2.y), b = SIMD3<Float>(b2.x, floorY, b2.y)
            let len = simd_distance(a2, b2)
            guard len > 0.01 else { continue }
            let n = L.flat(s.n) - L.flat(SIMD2<Float>(0, 0))           // 방 안쪽
            portal.face(a, b, toward: SIMD3<Float>(n.x, 0, n.y), y0: 0, y1: ceilY - floorY)
            let pd = (s.b - s.a) / max(1e-4, simd_distance(s.a, s.b))      // 평면 좌표 방향
            let perp = SIMD2<Float>(-s.n.y, s.n.x)
            /// 벽 너머 45cm 안에 처음 만나는 걸을 수 있는 곳: (방 — 이 방 자신 포함·방을 모르면 -1·없으면 0, 그 칸까지 거리)
            func across(_ p: SIMD2<Float>) -> (Int, Float) {
                for k in 0..<9 {
                    let o = 0.025 + Float(k) * 0.05
                    let q = p - s.n * o
                    if L.walkable(q) { let f = L.flat(q); let r = L.roomNear(x: f.x, z: f.y, radius: 0.05); return (r == 0 ? -1 : r, o) }
                }
                return (0, 0)
            }
            /// 방 m 의 벽 중 이 자리 맞은편(반대 방향, 너머 g 언저리)에 선 것이 있는지
            func facing(_ m: Int, _ p: SIMD2<Float>, _ g: Float) -> Bool {
                let up = simd_dot(perp, p)
                return L.walls.contains { o in
                    guard o.room == m, simd_dot(o.n, s.n) < -0.9 else { return false }
                    let x = simd_dot(s.n, p - o.a)
                    guard x > g - 0.1 && x < g + 0.05 else { return false }
                    let ua = simd_dot(perp, o.a), ub = simd_dot(perp, o.b)
                    return up > min(ua, ub) - 0.03 && up < max(ua, ub) + 0.03
                }
            }
            var t = step / 2
            while t < len {
                let p = s.a + pd * t
                t += step
                if waterGaps.contains(where: { simd_distance($0, p) < 0.6 }) { continue }
                let (m, g) = across(p)
                var off = base, depth: Float = 0.08, thin = true, shared = false
                if m == 0 {
                    let q = p - s.n * base
                    var d: Float = 0
                    while d < 0.55 && !L.walkable(q - s.n * (d + 0.05)) { d += 0.05 }
                    depth = max(d, 0.08); thin = d < 0.1
                } else if m > 0 && (m == room.id || groupIds.contains(m)) && facing(m, p, g) {
                    // 맞은편 벽(같은 세계)이 있으면 한쪽만(작은 번호 방, 같은 방이면 방향으로) 한가운데에 — 맞은편 벽이 없으면(문 칸 등) 내 벽 뒤에
                    if m < room.id || (m == room.id && !(s.n.x > 0.5 || s.n.y > 0.5)) { continue }
                    off = (g - 0.05) / 2 - 0.04                              // 두 벽 사이 한가운데 (얇은 울타리 두께 8cm의 가운데)
                    shared = true
                }
                let q = p - s.n * off
                // 너머가 다른 세계 옆방이면 그 방 번호 (그 방에 있을 때 끌 울타리).
                // 문 곁(문틀 옆)은 너머 칸이 문 자리라 방을 이 방·모름으로 잡기도 함 → 울타리 자리가 문 자리 30cm 안이면 그 문 건너편 방
                // (문간을 지날 때 눈 바로 곁에 이 조각이 남아 크게 비쳤음)
                var toward = m > 0 && m != room.id && !groupIds.contains(m) ? m : 0
                if toward == 0 && !shared {
                    let bq = p - s.n * (off + 0.04)
                    for ds in L.doors where !ds.single && ds.zone(bq, margin: 0.3, side: 0.3) {
                        let o = ds.roomA == room.id || groupIds.contains(ds.roomA) ? ds.roomB : ds.roomA
                        if o != room.id && !groupIds.contains(o) { toward = o; break }
                    }
                }
                samples.append(Sample(n: s.n, u: simd_dot(q, perp), c: simd_dot(q, s.n), depth: depth, thin: thin, shared: shared, outside: m == 0, toward: toward))
            }
        }
        addPortalPlanes(portal, name: "walls")
        // 같은 방향·같은 종류의 점을 줄 자리(c)가 15cm 안인 것끼리 한 줄로: 바깥은 가장 뒤(작은 c — 모든 벽 조각의 평면 뒤), 공유 줄은 가운데(평균)
        var spans: [BarrierSpan] = []
        var keys: [String: [Sample]] = [:]
        for sm in samples { keys["\(Int(sm.n.x.rounded()))_\(Int(sm.n.y.rounded()))_\(sm.shared)", default: []].append(sm) }
        for k in keys.keys.sorted() {
            guard let list = keys[k], let f = list.first else { continue }
            let n = f.n, perp = SIMD2<Float>(-n.y, n.x), shared = f.shared
            let byC = list.sorted { $0.c < $1.c }
            var clusters: [[Sample]] = []
            for sm in byC {
                // 묶음의 첫 점에서 15cm 안까지만 (비스듬한 스캔 벽의 계단이 끝없이 이어 묶여 줄이 벽에서 멀어지지 않게)
                if let first = clusters.last?.first, sm.c - first.c <= 0.15 { clusters[clusters.count - 1].append(sm) } else { clusters.append([sm]) }
            }
            for cl in clusters {
                let c = shared ? cl.map(\.c).reduce(0, +) / Float(cl.count) : cl[0].c
                func pt(_ u: Float) -> SIMD2<Float> { perp * u + n * c }
                /// 줄 끝 u 자리 울타리 몸통(말뚝 반폭 6cm·두께)이 문·통로 자리(바깥 줄이면 걸을 수 있는 곳 모두)·개울 드나드는 곳에 걸치지 않는지 —
                /// 걸치면 문간 쪽에서 볼 때 그 부분이 문간 바닥(방 안)에 가려 말뚝이 반쯤 잘려 보였음.
                /// sign: 줄 바깥쪽(+1 끝은 u 증가 쪽), walk: 걸을 수 있는 곳도 피함(바깥 줄 — 방 사이 줄은 옆방 자리와 겹칠 수 있어 문 자리만)
                func clearAt(_ u: Float, _ sign: Float, walk: Bool) -> Bool {
                    for da: Float in [0, 0.04, 0.08] {
                        for o: Float in [-0.06, 0, 0.06, 0.12] {
                            let q = pt(u + sign * da) - n * o
                            if L.doors.contains(where: { q.x > $0.lo.x - 0.03 && q.x < $0.hi.x + 0.03 && q.y > $0.lo.y - 0.03 && q.y < $0.hi.y + 0.03 }) { return false }
                            if (walk && o >= 0 && L.walkable(q)) || waterGaps.contains(where: { simd_distance($0, q) < 0.6 }) { return false }
                        }
                    }
                    return true
                }
                let ext = base + 0.04
                let byU = cl.sorted { $0.u < $1.u }
                var i = 0
                while i < byU.count {
                    var j = i
                    var dep = byU[i].depth - (byU[i].c - c)
                    while j + 1 < byU.count && byU[j + 1].u - byU[j].u <= step * 1.6 && byU[j + 1].thin == byU[i].thin && byU[j + 1].outside == byU[i].outside && byU[j + 1].toward == byU[i].toward {
                        j += 1
                        dep = min(dep, byU[j].depth - (byU[j].c - c))
                    }
                    var u0 = byU[i].u - step / 2, u1 = byU[j].u + step / 2
                    // 모서리: 바깥 줄은 다른 줄과 만나도록 띄운 거리만큼 늘림 / 문간·통로: 몸통이 걸치지 않게 줄임 (모든 줄)
                    let walk = byU[i].outside
                    if walk {
                        var e: Float = 0
                        while e < ext && clearAt(u0 - 0.025, -1, walk: true) { u0 -= 0.025; e += 0.025 }
                        e = 0
                        while e < ext && clearAt(u1 + 0.025, 1, walk: true) { u1 += 0.025; e += 0.025 }
                    }
                    while u1 - u0 > 0.1 && !clearAt(u0, -1, walk: walk) { u0 += 0.025 }
                    while u1 - u0 > 0.1 && !clearAt(u1, 1, walk: walk) { u1 -= 0.025 }
                    if u1 - u0 > 0.06 && clearAt(u0, -1, walk: walk) && clearAt(u1, 1, walk: walk) {
                        let wa = L.flat(pt(u0)), wb = L.flat(pt(u1))
                        let o2 = L.flat(-n) - L.flat(SIMD2<Float>(0, 0))
                        spans.append(BarrierSpan(a: SIMD3<Float>(wa.x, floorY, wa.y), b: SIMD3<Float>(wb.x, floorY, wb.y),
                                                 out: simd_normalize(SIMD3<Float>(o2.x, 0, o2.y)), depth: max(0.08, dep), thin: byU[i].thin, toward: byU[i].toward))
                    }
                    i = j + 1
                }
            }
        }
        addBarriers(spans)
    }

    /// 테마 울타리가 토막 줄(span a→b)보다 방 쪽으로 튀어나오는 최대 거리 (m) — 그만큼 벽 평면에서 더 뒤로 (방 바닥에 가려 잘려 보이지 않게).
    /// addBarriers 모양에서 잼:
    /// 통나무 말뚝(반지름 7.5cm, 가운데가 줄에서 4cm 뒤) 3.5cm, 덤불 둥근 앞면(울퉁불퉁 16%) 5cm, 돌무더기(22%·겹쳐 쌓음) 10cm,
    /// 말뚝 밧줄(밧줄이 말뚝보다 6.5cm 앞, 굵기 1.8cm) 5cm, 돌담 갓돌 9cm, 옥상 난간 0 (여유를 더함)
    private var barrierProt: Float {
        switch room.place {
        case "camp": return 0.045
        case "forest": return 0.06
        case "valley": return 0.1
        case "sea": return 0.06
        case "village": return 0.1
        default: return 0.01
        }
    }

    /// 울타리 한 토막: 바닥 a→b (벽에서 off 뒤), 바깥 방향 out, 세울 수 있는 두께, 방과 방 사이(얇게)인지
    struct BarrierSpan { let a: SIMD3<Float>; let b: SIMD3<Float>; let out: SIMD3<Float>; let depth: Float; let thin: Bool; var toward: Int = 0 }

    /// 테마마다 입체 울타리 (선 그림: 흰 면 + 같은 펜 굵기 외곽선, 흑백: 무늬 색을 뺌 — Tex 가 표시 방식대로)
    private func addBarriers(_ spans: [BarrierSpan]) {
        guard !spans.isEmpty else { return }
        var g = SeededRNG(seed: UInt64(room.id * 271 + 9))
        let H = style.barrierH
        let up = SIMD3<Float>(0, 1, 0)
        var solidA = Geo(), solidB = Geo(), solidC = Geo(), lumps = Geo(), lines = Geo(), hulls = Geo()
        /// 길이 방향 a→b, 바깥 out, 바닥 높이 y0~y1, 바깥으로 o0~o1 의 상자 (선 그림이면 모서리 선)
        func slab(_ geo: inout Geo, _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ out: SIMD3<Float>, o0: Float, o1: Float, y0: Float, y1: Float, tile: Float) {
            let p = [a + out * o0, b + out * o0, b + out * o1, a + out * o1]
            let L2 = simd_distance(a, b), D = o1 - o0
            let lo = up * y0, hi = up * y1
            let lens = [L2, D, L2, D]
            for k in 0..<4 {
                let q0 = p[k], q1 = p[(k + 1) % 4]
                geo.quad(q0 + lo, q1 + lo, q1 + hi, q0 + hi, SIMD2<Float>(0, y0 / tile), SIMD2<Float>(lens[k] / tile, y0 / tile),
                         SIMD2<Float>(lens[k] / tile, y1 / tile), SIMD2<Float>(0, y1 / tile))
            }
            geo.quad(p[0] + hi, p[1] + hi, p[2] + hi, p[3] + hi, .zero, SIMD2<Float>(L2 / tile, 0), SIMD2<Float>(L2 / tile, D / tile), SIMD2<Float>(0, D / tile))
            if lineMode {
                for k in 0..<4 {
                    lines.stroke(p[k] + lo, p[(k + 1) % 4] + lo, width: 0.01)
                    lines.stroke(p[k] + hi, p[(k + 1) % 4] + hi, width: 0.01)
                    lines.stroke(p[k] + lo, p[k] + hi, width: 0.01)
                }
            }
        }
        /// 둥근 기둥(통나무·밧줄) a→b, 반지름 r (선 그림이면 외곽선 껍데기)
        func pole(_ geo: inout Geo, _ a: SIMD3<Float>, _ b: SIMD3<Float>, r: Float, bend: SIMD3<Float> = .zero) {
            geo.trunk(from: a, to: b, r0: r, r1: r * 0.92, sides: 8, segs: bend == .zero ? 1 : 4, bend: bend)
            if lineMode { hulls.trunkHull(from: a, to: b, r0: r, r1: r * 0.92, width: inkW((a + b) / 2), sides: 8, segs: bend == .zero ? 1 : 4, bend: bend) }
        }
        let tk = Worlds.safe(tint * shades[1], min: 0.3)
        var matA: RealityKit.Material = Ink.paper(1), matB: RealityKit.Material = Ink.paper(0), matC: RealityKit.Material = Ink.paper(1)
        var lumpMat: RealityKit.Material = Ink.paper(0)
        // 모서리에서 두 줄이 만나는 곳의 말뚝은 하나만 (이미 선 말뚝 18cm 안이면 그 자리를 같이 씀)
        var postsMade: [SIMD3<Float>] = []
        func postAt(_ p: SIMD3<Float>) -> (SIMD3<Float>, Bool) {
            if let q = postsMade.first(where: { simd_distance(SIMD2<Float>($0.x, $0.z), SIMD2<Float>(p.x, p.z)) < 0.18 }) { return (q, false) }
            postsMade.append(p)
            return (p, true)
        }
        // 줄마다 담을 그물 묶음: 다른 세계 옆방 쪽 줄은 그 방 번호별로 따로 (그 방에 있을 때 끄려고). 말뚝 나눠 쓰기·높이 차이는 모든 줄이 같이 셈
        var bank: [Int: [Geo]] = [:]
        var curKey = 0
        func useKey(_ k: Int) {
            guard k != curKey else { return }
            bank[curKey] = [solidA, solidB, solidC, lumps, lines, hulls]
            let n = bank[k] ?? [Geo(), Geo(), Geo(), Geo(), Geo(), Geo()]
            solidA = n[0]; solidB = n[1]; solidC = n[2]; lumps = n[3]; lines = n[4]; hulls = n[5]
            curKey = k
        }
        for (si, sp) in spans.enumerated() {
            let L2 = simd_distance(sp.a, sp.b)
            guard L2 > 0.06 else { continue }
            useKey(sp.toward)
            let dir = (sp.b - sp.a) / L2
            let out = sp.out
            let D = sp.thin ? 0.08 : min(sp.depth, 0.5)
            // 겹치는 두 줄(모서리·안쪽으로 들어간 벽)의 같은 높이 윗면이 깜빡이지 않게, 줄마다 높이를 4mm씩 다르게 (바깥 방향 넷 × 3)
            let dirK = (Int(((atan2(out.z, out.x) + .pi) / (.pi / 2)).rounded()) % 4 + 4) % 4
            let lift = Float(dirK * 3 + si % 3) * 0.004
            switch room.place {
            case "camp":
                // 통나무 울타리: 1.8m 안팎마다 굵은 말뚝 + 가로 통나무 둘 (조금 처짐)
                let n = max(1, Int((L2 / 1.8).rounded()))
                let mid = out * min(D * 0.5, 0.09)
                var posts: [SIMD3<Float>] = []
                for i in 0...n {
                    let (p, fresh) = postAt(sp.a + dir * (L2 * Float(i) / Float(n)) + mid)
                    posts.append(p)
                    let ht = H + Float.random(in: -0.06...0.08, using: &g)
                    if fresh { pole(&solidA, p - up * 0.1, p + up * ht, r: 0.075) }
                }
                for i in 0..<n {
                    for y in [H * 0.42, H * 0.8] {
                        let a = posts[i] + up * y + out * 0.04, b = posts[i + 1] + up * (y + Float.random(in: -0.04...0.04, using: &g)) + out * 0.04
                        pole(&solidA, a, b, r: 0.055, bend: -up * 0.03)
                    }
                }
            case "forest":
                // 덤불 울타리: 겹쳐 선 둥근 덤불 (아래 넓고 위로 둥글게) + 사이사이 키 작은 덤불
                var x: Float = 0
                while x < L2 {
                    let w = Float.random(in: 0.5...0.85, using: &g)
                    let h = H * Float.random(in: 0.75...1.05, using: &g)
                    let rz = max(0.04, min(D * 0.5, 0.3))
                    let c = sp.a + dir * min(L2, x + w * 0.4) + out * rz + up * (h * 0.42)
                    lumps.blob(at: c, rx: w * 0.62, rz: rz, up: h * 0.58, down: h * 0.42, lumpy: 0.16,
                               yaw: atan2(-dir.z, dir.x), using: &g)
                    x += w * 0.7
                }
            case "valley":
                // 돌무더기 둑: 아래 큰 돌 줄 + 그 위 작은 돌 (둥글넓적, 겹쳐 쌓음)
                var x: Float = 0
                while x < L2 {
                    let s = Float.random(in: 0.28...0.46, using: &g)
                    let rz0 = max(0.04, min(s, D * 0.5))
                    let c = sp.a + dir * min(L2, x + s * 0.5) + out * rz0 + up * (s * 0.35)
                    lumps.blob(at: c, rx: s, rz: rz0, up: s * 0.7, down: s * 0.35, lumpy: 0.22, yaw: Float.random(in: 0...6.28, using: &g), using: &g)
                    if Float.random(in: 0...1, using: &g) < 0.8 {
                        let s2 = s * Float.random(in: 0.55...0.8, using: &g)
                        let c2 = c + dir * Float.random(in: -0.1...0.2, using: &g) + up * (s * 0.55 + s2 * 0.4)
                        lumps.blob(at: c2, rx: s2, rz: max(0.04, min(s2, D * 0.45)), up: s2 * 0.6, down: s2 * 0.4, lumpy: 0.22, yaw: Float.random(in: 0...6.28, using: &g), using: &g)
                        if c2.y - sp.a.y + s2 < H * 0.8, Float.random(in: 0...1, using: &g) < 0.5 {
                            let s3 = s2 * 0.7
                            lumps.blob(at: c2 + up * (s2 * 0.5 + s3 * 0.35), rx: s3, rz: max(0.04, min(s3, D * 0.4)), up: s3 * 0.6, down: s3 * 0.4, lumpy: 0.22,
                                       yaw: Float.random(in: 0...6.28, using: &g), using: &g)
                        }
                    }
                    x += s * 1.25
                }
            case "sea":
                // 바닷가 말뚝 밧줄 울타리: 1.6m마다 네모 말뚝(나무) + 처진 굵은 밧줄 둘 + 아래 현무암 몇 개
                let n = max(1, Int((L2 / 1.6).rounded()))
                let mid = out * min(D * 0.45, 0.08)
                var posts: [SIMD3<Float>] = []
                for i in 0...n {
                    let (p, fresh) = postAt(sp.a + dir * (L2 * Float(i) / Float(n)) + mid)
                    posts.append(p)
                    if fresh { slab(&solidA, p - dir * 0.06, p + dir * 0.06, out, o0: -0.06, o1: 0.06, y0: -0.05, y1: H + 0.05 + lift, tile: 0.8) }
                }
                for i in 0..<n {
                    for y in [H * 0.5, H * 0.92] {
                        pole(&solidB, posts[i] + up * y - out * 0.065, posts[i + 1] + up * y - out * 0.065, r: 0.018, bend: -up * 0.09)
                    }
                    if !sp.thin && Float.random(in: 0...1, using: &g) < 0.6 {
                        let s = Float.random(in: 0.15...0.3, using: &g)
                        let c = (posts[i] + posts[i + 1]) / 2 + dir * Float.random(in: -0.4...0.4, using: &g) + out * (0.1 + min(s, D * 0.4)) + up * (s * 0.3)
                        lumps.blob(at: c, rx: s, rz: min(s, D * 0.4), up: s * 0.6, down: s * 0.3, lumpy: 0.2, using: &g)
                    }
                }
            case "village":
                // 돌담: 두께 있는 돌 벽(위가 살짝 좁음) + 위에 납작한 갓돌
                let wall = min(D, 0.42)
                let hh = H * 0.82
                slab(&solidA, sp.a, sp.b, out, o0: 0, o1: wall, y0: -0.05, y1: hh + lift, tile: 1.4)
                var x: Float = 0
                while x < L2 {
                    let s = Float.random(in: 0.22...0.34, using: &g)
                    let c = sp.a + dir * min(L2, x + s * 0.5) + out * (wall * 0.5) + up * (hh + s * 0.15)
                    lumps.blob(at: c, rx: s, rz: max(0.04, wall * 0.62), up: s * 0.4, down: s * 0.15, lumpy: 0.15, yaw: atan2(-dir.z, dir.x), using: &g)
                    x += s * 1.6
                }
            default:
                // 옥상 난간: 콘크리트 턱 + 1.2m마다 철제 기둥 + 위·가운데 가로대
                let curb = min(D, 0.24)
                slab(&solidA, sp.a, sp.b, out, o0: 0, o1: curb, y0: -0.05, y1: 0.2 + lift, tile: 1.2)
                let n = max(1, Int((L2 / 1.2).rounded()))
                let mid = out * (curb * 0.5)
                for i in 0...n {
                    let (p, fresh) = postAt(sp.a + dir * (L2 * Float(i) / Float(n)) + mid)
                    if fresh { slab(&solidB, p - dir * 0.022, p + dir * 0.022, out, o0: -0.022, o1: 0.022, y0: 0.2, y1: H, tile: 1) }
                }
                for (y, hgt) in [(H - 0.05, Float(0.05)), (H * 0.58, Float(0.03))] {
                    slab(&solidB, sp.a + mid, sp.b + mid, out, o0: -0.025, o1: 0.025, y0: y + lift, y1: y + hgt + lift, tile: 1)
                }
            }
        }
        if !lineMode {
            switch room.place {
            case "camp":
                matA = Tex.unlit("bark", tint: Worlds.safe(tint * 0.75, min: 0.25))
            case "forest":
                lumpMat = Tex.unlit("moss", tint: Worlds.safe(tint * SIMD3<Float>(0.62, 0.8, 0.55), min: 0.2))
            case "valley":
                lumpMat = Tex.unlit("rock", tint: Worlds.safe(tint * 0.85, min: 0.25))
            case "sea":
                matA = Tex.unlit("bark", tint: Worlds.safe(tint * SIMD3<Float>(0.85, 0.78, 0.7), min: 0.25))      // 이 테마가 이미 읽어 둔 그림만 씀 (큰 그림을 더 읽지 않게)
                matB = UnlitMaterial(color: Tex.color(SIMD3<Float>(0.78, 0.7, 0.55) * tk))
                lumpMat = Tex.unlit("basalt", tint: Worlds.safe(tint * 0.8, min: 0.2))
            case "village":
                matA = Tex.unlit("house_stone", tint: Worlds.safe(tint * 0.92, min: 0.25))
                lumpMat = Tex.unlit("house_stone", tint: Worlds.safe(tint * 0.8, min: 0.25))
            default:
                matA = Tex.unlit(style.ground, tint: Worlds.safe(tint * 0.9, min: 0.25))
                matB = UnlitMaterial(color: Tex.color(SIMD3<Float>(0.16, 0.17, 0.19) * Worlds.safe(tint, min: 0.5)))
            }
        } else {
            matC = Ink.paper(2)
        }
        bank[curKey] = [solidA, solidB, solidC, lumps, lines, hulls]
        for k in bank.keys.sorted() {
            guard let gs = bank[k] else { continue }
            var made: [Entity] = []
            for (geo, m, nm) in [(gs[0], matA, "barrierA"), (gs[1], matB, "barrierB"), (gs[2], matC, "barrierC"), (gs[3], lumpMat, "barrierLumps")] {
                if let e = geo.entity(nm, m) { layer(e, 6); world.addChild(e); made.append(e) }
            }
            if lineMode {
                if let e = gs[3].inkHull("barrierLumpLines", width: { inkW($0) }) { layer(e, 6); world.addChild(e); made.append(e) }
                if let e = gs[5].entity("barrierLogLines", Ink.hullMat) { layer(e, 6); world.addChild(e); made.append(e) }
                if let e = gs[4].entity("barrierLines", Ink.line) { layer(e, 7); world.addChild(e); made.append(e) }
            }
            if k != 0 { barrierToward[k, default: []] += made }
        }
    }

    /// 내가 있는 방들(지금 방·몸이 있는 방·몸이 선 문 양쪽 방)에 맞댄 벽 뒤 울타리는 끔 (barrierToward 참고)
    func hideBarriers(near rooms: Set<Int>) {
        for (k, list) in barrierToward {
            let on = !rooms.contains(k)
            for e in list where e.isEnabled != on { e.isEnabled = on }
        }
    }

    /// 실내 장소: 바닥부터 천장까지 반듯한 벽 (해를 보는 쪽은 밝게). 창: 0.85m~2.15m를 하늘 세계로 열린 창으로
    private func solidWalls(_ segs: [WallSeg], _ L: Layout, floorY: Float, ceilY: Float) {
        let sun = Worlds.sunDir(room.time)
        var parts = [Geo(), Geo(), Geo()]
        var win = PortalPlanes(), frame = Geo()
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
                let (w0, w1) = Self.windowBand(place: room.place, top: top)
                let n3 = SIMD3<Float>(nw.x, 0, nw.y)
                parts[k].face(a, b, toward: n3, y0: 0, y1: w0, u0: u0, u1: u1, v0: 0, v1: w0 / tile)
                parts[k].face(a, b, toward: n3, y0: w1, y1: top, u0: u0, u1: u1, v0: w1 / tile, v1: top / tile)
                win.face(a, b, toward: n3, y0: w0, y1: w1)
                let inn = SIMD3<Float>(nw.x, 0, nw.y) * 0.02
                let d3 = simd_normalize(b - a)
                // 창틀: 위·아래 가로대 + 양옆 세로대, 카페는 1.1m 안팎마다 세로 살(통창), 집은 가운데 십자 살 + 창턱
                let fw: Float = room.place == "cafe" ? 0.035 : 0.045
                for y in [w0, w1] { frame.wall(a + inn, b + inn, y0: y - fw, y1: y + fw, u0: 0, u1: 1) }
                func post(_ p: SIMD3<Float>, _ hw: Float, _ y0: Float, _ y1: Float) {
                    frame.wall(p - d3 * hw + inn, p + d3 * hw + inn, y0: y0, y1: y1, u0: 0, u1: 1)
                }
                post(a + d3 * fw, fw, w0, w1)
                post(b - d3 * fw, fw, w0, w1)
                if room.place == "cafe" {
                    let n = max(1, Int((len / 1.1).rounded()))
                    for i in 1..<n { post(a + d3 * (len * Float(i) / Float(n)), 0.025, w0, w1) }
                    if w1 - w0 > 1.9 { frame.wall(a + inn, b + inn, y0: w1 - 0.42, y1: w1 - 0.39, u0: 0, u1: 1) }   // 위 채광창 가로살
                } else {
                    post((a + b) / 2, 0.018, w0, w1)
                    frame.wall(a + inn, b + inn, y0: (w0 + w1) / 2 - 0.018, y1: (w0 + w1) / 2 + 0.018, u0: 0, u1: 1)
                    // 창턱: 방 안쪽으로 8cm 나온 판
                    let o = n3 * 0.08
                    frame.quad(a + SIMD3<Float>(0, w0 - 0.02, 0), b + SIMD3<Float>(0, w0 - 0.02, 0), b + o + SIMD3<Float>(0, w0 - 0.02, 0), a + o + SIMD3<Float>(0, w0 - 0.02, 0),
                               SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(1, 0.1), SIMD2<Float>(0, 0.1))
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
        if !win.isEmpty {
            addPortalPlanes(win, name: "window")
            let frameCol: SIMD3<Float> = room.place == "cafe" ? SIMD3<Float>(0.09, 0.09, 0.1) : SIMD3<Float>(0.36, 0.26, 0.17)     // 카페: 검은 철제 창틀, 집: 나무 창틀
            if let f = frame.entity("frame", ink(frameCol * Worlds.safe(tint))) {
                local.addChild(f)
            }
        }
    }

    /// 창 높이 (바닥에서 m): 카페는 낮은 창턱(45cm)부터 천장 밑까지 통유리, 집은 허리 높이 창, 그 밖(스캔에서 창으로 본 벽)은 0.85~2.15
    nonisolated static func windowBand(place: String, top: Float) -> (Float, Float) {
        switch place {
        case "cafe": return (0.45, top - 0.18)
        case "home": return (0.85, min(2.05, top - 0.2))
        default: return (0.85, min(2.15, top - 0.15))
        }
    }

    /// 카페·집: 바깥벽(옆방과 맞닿지 않은 벽)을 [벽 | 창 | 벽] 조각으로 나눔 (창 조각 window = true).
    /// 가장 긴 벽 하나는 그대로 둠 (카페 메뉴판·바 카운터, 집 벽난로 자리). 문 끝에서는 35cm 띄움.
    /// 카페는 벽 거의 전체가 통창(모서리 기둥만 남김), 집은 벽 길이에 따라 창 하나(1.5m까지) 또는 둘
    nonisolated static func withWindows(_ segs: [WallSeg], place: String, doors: [DoorSeg], roomId: Int, nearSame: Set<Int>) -> [WallSeg] {
        guard place == "cafe" || place == "home" else { return segs }
        func len(_ s: WallSeg) -> Float { simd_distance(s.a, s.b) }
        let reserve = segs.filter { !$0.window }.max { len($0) < len($1) }
        var doorEnds: [SIMD2<Float>] = []
        for ds in doors where ds.roomA == roomId || ds.roomB == roomId {
            let (a, b, _) = ds.edge(for: roomId)
            doorEnds += [a, b]
        }
        let cafe = place == "cafe"
        var out: [WallSeg] = []
        for s in segs {
            let L0 = len(s)
            if s.inner || nearSame.contains(s.nearRoom) || (s.behind != 0 && nearSame.contains(s.behind)) || s.window || L0 < 1.1 || (reserve.map { simd_distance($0.a, s.a) < 1e-3 && simd_distance($0.b, s.b) < 1e-3 } ?? false) {
                out.append(s); continue
            }
            let dir = (s.b - s.a) / L0
            let nearA = doorEnds.contains { simd_distance($0, s.a) < 0.12 }, nearB = doorEnds.contains { simd_distance($0, s.b) < 0.12 }
            let e0: Float = nearA ? 0.35 : (cafe ? 0.12 : 0.3), e1: Float = nearB ? 0.35 : (cafe ? 0.12 : 0.3)
            let usable = L0 - e0 - e1
            var spans: [(Float, Float)] = []
            if cafe {
                if usable >= 0.7 { spans = [(e0, L0 - e1)] }
            } else if usable >= 0.9 {
                let n = usable > 3.6 ? 2 : 1
                let w = min(n == 1 ? 1.5 : 1.3, usable / Float(n) - 0.3)
                if w >= 0.6 {
                    for i in 0..<n {
                        let c = e0 + usable * (Float(i) + 0.5) / Float(n)
                        spans.append((c - w / 2, c + w / 2))
                    }
                }
            }
            guard !spans.isEmpty else { out.append(s); continue }
            func piece(_ t0: Float, _ t1: Float, _ w: Bool) -> WallSeg {
                var p = s
                p.a = s.a + dir * t0; p.b = s.a + dir * t1; p.window = w
                return p
            }
            var t: Float = 0
            for (a, b) in spans {
                if a - t > 0.005 { out.append(piece(t, a, false)) }
                out.append(piece(a, b, true))
                t = b
            }
            if L0 - t > 0.005 { out.append(piece(t, L0, false)) }
        }
        return out
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
                        var pc = PortalComponent(target: world)
                        pc.clippingMode = .plane(.positiveZ)          // 문 자리 판 앞(이 방 쪽)의 세계 것은 잘라 냄 (포털 면 참고)
                        e.components.set(pc)
                        place(e, 0)
                        addPortal(e)
                        local.addChild(e)
                        list.append(e)
                    }
                    if header {
                        var hd = Geo()
                        hd.face(pa, pb, toward: front, y0: dh, y1: top, u0: 0, u1: 1)
                        if let m = hd.mesh("header\(i)") {
                            let e = ModelEntity(mesh: m, materials: [PortalMaterial()])
                            var pc = PortalComponent(target: world)
                            pc.clippingMode = .plane(.positiveZ)
                            e.components.set(pc)
                            place(e, 0)
                            addPortal(e)
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
                let gold = Self.gold(rough: 0.3, mono: look == .mono)
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
                ui.setOpacity(0)
                ui.isEnabled = false
                local.addChild(ui)
                doorView[i] = DoorView(root: ui, left: left, right: right, lock: lock, keyRoot: keyRoot, key: key, parts: parts, hl: hl)
            }

            // 실제 문이 닫혀 있을 때(비전프로가 '문'으로 알아본 면이 문 자리를 막을 때)만 보이는 실제 문짝 (방 A 세계가 하나만 만듦)
            if room.id == ds.roomA {
                let c2 = L.flat(ds.mid)                                   // 두 입구 줄 사이 가운데
                let lit = Worlds.safe(tint, min: 0.6)
                let woodLight = Tex.unlit("planks", tint: lit * 0.95, folder: "tex", sampler: Tex.clamp)
                let gold = Self.gold(rough: 0.3, mono: look == .mono)
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
                doorsRoot.addChild(real)                 // 옆방에 있을 때도 보여야 함 → 방 안(local)이 아니라 늘 켜진 묶음에
                doorLeaf[i] = real
            }
        }
    }

    /// 빛을 받는 황금 (실제 방의 빛이 비쳐 반짝임)
    static func gold(rough: Float, glow: Float = 0.35, mono: Bool = false) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        if mono {                                         // 흑백: 은빛 (색 없이)
            m.baseColor = .init(tint: UIColor(white: 0.85, alpha: 1))
            m.metallic = .init(floatLiteral: 1)
            m.roughness = .init(floatLiteral: rough)
            m.emissiveColor = .init(color: UIColor(white: 0.9, alpha: 1))
            m.emissiveIntensity = glow
            m.baseColor = .init(tint: UIColor(white: 0.85, alpha: 1))
            return m
        }
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
        addCafeSpeaker(rects, L, y: y)
    }

    /// 카페 음악이 나오는 스피커: 방 가운데에서 가장 가까운 천장 들보 아랫면에 바로 붙은 둥근 천장 스피커 (아래를 향함).
    /// 음악이 나오는 동안 울림판이 은근히 떨림
    private(set) var speakerSpot: SIMD3<Float>?
    private var speakerCone: Entity?
    private var speakerBody: Entity?
    private var spT: Float = 0
    var musicOn = false

    private func addCafeSpeaker(_ rects: [PRect], _ L: Layout, y: Float) {
        let cp = L.plane(roomCenter.x, roomCenter.z)
        var best: (SIMD2<Float>, Float)? = nil
        for r in rects where r.1.x - r.0.x > 0.6 && r.1.y - r.0.y > 0.6 {
            var v = (r.0.y).rounded(.down) + 0.55
            while v < r.1.y - 0.2 {
                let u = min(r.1.x - 0.4, max(r.0.x + 0.4, cp.x))
                let p = SIMD2<Float>(u, v)
                let d = simd_distance(p, cp)
                if best == nil || d < best!.1 { best = (p, d) }
                v += 1.1
            }
        }
        guard let b = best else { return }
        let w2 = L.flat(b.0)
        let beamBottom = y - 0.12
        let root = Entity()
        root.position = SIMD3<Float>(w2.x, beamBottom, w2.y)
        // 들보를 따라가는 방향과 직각(방 가운데 쪽)으로 향함
        let beamDir = simd_normalize(L.flat(SIMD2<Float>(1, 0)) - L.flat(SIMD2<Float>(0, 0)))
        var face = SIMD2<Float>(-beamDir.y, beamDir.x)
        let toC = SIMD2<Float>(roomCenter.x - w2.x, roomCenter.z - w2.y)
        if simd_dot(face, toC) < 0 { face = -face }
        root.orientation = simd_quatf(angle: atan2(face.x, face.y), axis: [0, 1, 0])
        // 천장(들보 아랫면)에 바로 붙인 둥근 천장 스피커: 아래를 향함 — 카페 철제 살·나무 들보에 어울리는 무광 검은 금속 통
        // (헤어라인 결) + 아래쪽 촘촘한 타공 철망 + 망 너머 울림판. 흰 플라스틱처럼 튀지 않게 실내 조명 빛깔만 은은히 받음
        let lit = Worlds.safe(tint, min: 0.55)
        let rimM = lineMode ? Ink.paper(0) : Tex.unlit("speaker_metal", tint: lit * 0.95)
        let gridM: RealityKit.Material
        if lineMode {
            gridM = Ink.paper(1)
        } else {
            var m = Tex.unlit("speaker_grille", tint: lit)
            if let t = Tex.get("speaker_grille") {
                var tp = MaterialParameters.Texture(t); tp.sampler = Tex.tiling
                m.color = .init(tint: Tex.color(lit), texture: tp)
            }
            gridM = m
        }
        let coneM = lineMode ? Ink.line : ink(SIMD3<Float>(0.05, 0.05, 0.05))
        let body = Entity()
        root.addChild(body)
        let can = ModelEntity(mesh: .generateCylinder(height: 0.075, radius: 0.12), materials: [rimM])
        can.position = [0, -0.0375, 0]
        body.addChild(can)
        let flange = ModelEntity(mesh: .generateCylinder(height: 0.01, radius: 0.135), materials: [rimM])
        flange.position = [0, -0.005, 0]
        body.addChild(flange)
        let lip = ModelEntity(mesh: .generateCylinder(height: 0.008, radius: 0.124), materials: [rimM])      // 아래 테두리 (살짝 넓게)
        lip.position = [0, -0.074, 0]
        body.addChild(lip)
        var gd = Geo()
        gd.disc(center: SIMD3<Float>(0, -0.079, 0), radius: 0.112, tile: 0.12, segments: 40)
        if let grille = gd.entity("speakerGrille", gridM) { body.addChild(grille) }
        let cone = Entity()
        cone.position = [0, -0.08, 0]                      // 망 가운데 작은 검은 돔 (울림판 덮개)
        let cap = ModelEntity(mesh: .generateSphere(radius: 0.028), materials: [coneM])
        cap.scale = [1, 0.35, 1]
        cone.addChild(cap)
        body.addChild(cone)
        if lineMode {
            var l = Geo()
            for (rr, y) in [(Float(0.135), Float(-0.004)), (0.124, -0.078), (0.03, -0.082)] {
                for k in 0..<28 {
                    let a0 = Float(k) / 28 * 2 * .pi, a1 = Float(k + 1) / 28 * 2 * .pi
                    l.stroke(SIMD3<Float>(cos(a0) * rr, y, sin(a0) * rr), SIMD3<Float>(cos(a1) * rr, y, sin(a1) * rr), width: 0.005)
                }
            }
            if let e = l.entity("speakerLines", Ink.line) { body.addChild(e) }
            Ink.hull(can); Ink.hull(flange)                     // 옆에서 본 외곽선
        }
        local.addChild(root)
        speakerCone = cone
        speakerBody = body
        speakerSpot = root.convert(position: SIMD3<Float>(0, -0.1, 0), to: local)
    }

    /// 스피커: 음악이 나오는 동안 울림판이 은근히 떨림 (소리 물결은 그리지 않음)
    private func tickSpeaker(_ dt: Float) {
        guard let cone = speakerCone, let body = speakerBody else { return }
        spT += dt
        let t = spT
        if musicOn {
            // 오르골에 맞게 아주 살짝: 울림판이 은근히 떨리고 통이 미세하게 울림
            let beat = pow(max(0, sin(t * 2 * .pi * 1.2)), 4) * 0.025 + 0.004 * sin(t * 37)
            cone.scale = SIMD3<Float>(1 + beat * 0.6, 0.35 + beat * 2, 1 + beat * 0.6)
            body.position = SIMD3<Float>(0, 0.00025 * sin(t * 53), 0)
        } else {
            cone.scale = SIMD3<Float>(1, 0.35, 1)
        }
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
        let farY: Float = dc.city ? floorY - 30 : floorY - 0.4         // 가까운 땅(무늬)과 충분히 떨어뜨려 멀리서 두 땅이 번갈아 비치지 않게
        far.disc(center: SIMD3<Float>(center.x, farY, center.z), radius: 600, tile: 50, segments: 32)
        let farCol = dc.city ? SIMD3<Float>(0.13, 0.13, 0.15) : style.groundFar
        if !dc.sea, let e = far.entity("farGround", UnlitMaterial(color: Tex.color(farCol * tint))) { world.addChild(e) }
        // 가까운 땅 (무늬): 도시는 옥상 끝까지만, 바다는 모래사장만
        let nearR: Float = dc.city ? R + 3 : (dc.sea ? R + 9 : 80)
        var near = Geo()
        // 카페: 차도(바닥 16cm 아래)가 땅에 묻히지 않게 땅을 더 낮게
        near.disc(center: SIMD3<Float>(center.x, floorY - (room.place == "cafe" ? 0.3 : 0.03), center.z), radius: nearR, tile: style.groundTile)
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
    /// 방으로 흘러드는 곳 (평면 좌표 벽 점, 방 안쪽 방향) — 바깥 강이 여기서 벽 밑으로 들어와 방 안 개울이 됨
    private(set) var riverEntry: (SIMD2<Float>, SIMD2<Float>)?
    /// 개울이 벽 너머로 들어오고 나가는 벽 점 (평면 좌표) — 이 자리는 울타리를 비워 물이 이어져 보이게
    private var waterGaps: [SIMD2<Float>] = []

    /// 개울 물길: 먼 절벽의 폭포에서 시작해 굽이치며 다가와, 이 방 바깥벽 한 곳으로 곧장 흘러듦 (방 안 개울로 이어짐).
    /// 바깥으로 곧게 30m 넘게 트인(다른 방이 없는) 벽을 고름. 그런 벽이 없으면 예전처럼 방 옆을 지나가는 물길
    private func planRiver(_ L: Layout, _ rec: SpaceRec, floorY: Float) {
        var g = SeededRNG(seed: UInt64(room.id * 613 + 77))
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
        // 흘러들 벽 점 후보: 바깥벽(옆방 아닌 벽)을 30cm 간격으로, 바깥으로 곧게 30m가 트여 있는 곳만
        var cands: [(SIMD2<Float>, SIMD2<Float>, Float)] = []
        for s in L.walls where s.room == room.id && !s.inner {
            let len = simd_distance(s.a, s.b)
            guard len > 0.9 else { continue }
            let dir = (s.b - s.a) / len
            var k: Float = 0.4
            while k <= len - 0.4 + 1e-3 {
                let q = s.a + dir * k
                if L.doors.contains(where: { $0.zone(q, margin: 0.5) }) { k += 0.3; continue }
                let qs = L.flat(q), os = L.flat(q - s.n) - qs
                var ok = true
                var d: Float = 1.2
                while d <= 32 && ok {
                    let side = SIMD2<Float>(-os.y, os.x) * (d > 6 ? 3.2 : 1.2)
                    for o in [SIMD2<Float>(0, 0), side, -side] {
                        let p = qs + os * d + o
                        if L.walkable(L.plane(p.x, p.y)) { ok = false; break }
                    }
                    d += 0.8
                }
                // 벽 가운데쯤일수록, 긴 벽일수록 좋음
                if ok { cands.append((q, s.n, min(k, len - k) + len * 0.3)) }
                k += 0.3
            }
        }
        if let best = cands.max(by: { $0.2 < $1.2 }) {
            // 좋은 후보들 중 무작위 (방마다 다르게)
            let good = cands.filter { $0.2 > best.2 * 0.75 }
            let pick = good[Int(g.next() % UInt64(good.count))]
            riverEntry = (pick.0, pick.1)
            let qs = L.flat(pick.0)
            let os = simd_normalize(L.flat(pick.0 - pick.1) - qs)          // 벽에서 바깥쪽 (저장 좌표)
            let side = SIMD2<Float>(-os.y, os.x)
            let D: Float = 30
            let lat = Float.random(in: -3...3, using: &g)                   // 폭포가 정면에서 조금 비켜 있게
            let amp = Float.random(in: 1.4...2.4, using: &g) * (g.next() % 2 == 0 ? Float(1) : Float(-1))
            let ph = Float.random(in: 0...1, using: &g)
            let n = 56
            var pts: [SIMD3<Float>] = [], ws: [Float] = []
            for i in 0...n {
                let u = Float(i) / Float(n)                                 // 0 폭포 → 1 벽
                let d = D * (1 - u) + 0.02
                // 굽이침: 멀리서는 크게, 벽 3m 앞부터는 곧게 벽으로 들어옴
                let straight = max(0, min(1, (d - 0.5) / 3.5))
                let o = (lat * (1 - u) + amp * sin(u * .pi * 1.6 + ph * 6) * (1 - u)) * straight * straight
                let p2 = qs + os * d + side * o
                pts.append(SIMD3<Float>(p2.x, floorY, p2.y))
                // 폭: 폭포 밑은 넓고(3m 안팎) 방에 가까워질수록 개울 폭(1m)으로 좁아짐
                let k = max(0, min(1, (u - 0.45) / 0.5))
                let sm = k * k * (3 - 2 * k)
                ws.append((3.1 + 0.4 * sin(u * 13 + ph * 5)) * (1 - sm) + 0.95 * sm)
            }
            riverPts = pts
            riverW = ws
            riverFeedsRoom = true
            return
        }
        planRiverAround(L, rec, floorY: floorY, clear: clear)
    }

    /// 바깥 강이 방으로 흘러드는지 (아니면 방 옆을 지나가는 물길)
    private(set) var riverFeedsRoom = false

    /// 예전 물길: 폭포에서 시작해 방 옆 5~6m를 굽이쳐 지나 반대편 절벽 밑으로 사라짐 (흘러들 벽이 없을 때)
    private func planRiverAround(_ L: Layout, _ rec: SpaceRec, floorY: Float, clear: (SIMD3<Float>, Float) -> Bool) {
        var g = SeededRNG(seed: UInt64(room.id * 613 + 77))
        let f0 = Float(g.next() % 1000) / 1000
        let span: Float = 0.32
        let n = 64
        let wig = Float(g.next() % 100) / 100 * 6
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

    // MARK: 시골 마을
    private var treeSpots: [(SIMD3<Float>, Float)] = []          // 세운 나무 (자리, 폭) — 집이 나무와 겹치지 않게
    private var crowns: [(SIMD3<Float>, Float, Float)] = []      // 세운 나무 (뿌리, 높이, 폭) — 카페 가로수 낙엽
    private var villageWins: [(e: ModelEntity, next: Float, on: Bool)] = []
    private var winOnMat: RealityKit.Material?
    private var winOffMat: RealityKit.Material?
    private var villageT: Float = 0
    private var lamps: [(head: ModelEntity, glow: Entity?, on: Bool, wantOn: Bool, startT: Float, flick: Float, flickT: Float, next: Float)] = []
    private var lampOn: RealityKit.Material?
    private var lampOff: RealityKit.Material?
    private var cafeT: Float = 0
    private var plumes: [SmokePlume] = []                         // 굴뚝·모닥불 연기 (그림 판)

    /// 시골: 들 건너 34~60m에 띄엄띄엄 선 입체 시골집 네 채 (서로·나무와 넉넉히 떨어져, 집마다 크기·층수·벽·지붕 색·방향이 다름).
    /// 디테일: 돌 기단, 벽 모서리 띠, 처마 끝막이판·박공 널·용마루, 창마다 창틀·십자 살·창턱·덧창, 문틀·문 위 차양·돌계단·문 옆 등,
    /// 벽돌 굴뚝과 굴뚝 덮개. 면마다 해 방향에 따라 밝기가 달라 입체로 보임.
    /// 해질녘·밤·새벽엔 창 불빛이 가끔 켜졌다 꺼지고, 문 옆 등이 켜지며, 몇 집 굴뚝에선 가는 연기가 오름 (연기는 그림 판 — SmokePlume)
    private func addVillageHouses<G: RandomNumberGenerator>(_ rec: SpaceRec, _ L: Layout, floorY: Float, using g: inout G) {
        // 벽: 실사 사진 무늬 (베이지 회벽·칠한 회벽·돌·벽돌·나무 판자) — 집마다 빛깔을 조금씩 달리
        let wallKinds: [(String, SIMD3<Float>, Float)] = [("house_stucco", [1, 0.97, 0.92], 2.5), ("house_stucco", [1, 0.9, 0.78], 2.5),
                                                          ("house_plaster", [0.94, 0.97, 1], 2.5), ("house_stone", [1, 1, 1], 2.5),
                                                          ("brick", [0.85, 0.78, 0.74], 1.6), ("house_wood", [1, 1, 1], 2.0)]
        let roofCols: [SIMD3<Float>] = [[0.62, 0.26, 0.18], [0.34, 0.38, 0.44], [0.4, 0.28, 0.2], [0.3, 0.4, 0.3], [0.5, 0.2, 0.16]]
        let shutterCols: [SIMD3<Float>] = [[0.24, 0.36, 0.28], [0.22, 0.3, 0.42], [0.42, 0.26, 0.18], [0.6, 0.55, 0.45]]
        let sun = Worlds.sunDir(room.time)
        func shadeK(_ n: SIMD3<Float>) -> Int { let l = simd_dot(n, sun); return l > 0.25 ? 0 : (l > -0.25 ? 1 : 2) }
        // 재질 묶음: 벽(종류×그늘), 지붕(색×그늘), 나무 장식(흰 판·짙은 나무), 덧창(색), 기단, 굴뚝
        var walls = [[Geo]](repeating: [Geo(), Geo(), Geo()], count: wallKinds.count)
        var roofs = [[Geo]](repeating: [Geo(), Geo(), Geo()], count: roofCols.count)
        var whiteTrim = Geo(), darkWood = Geo(), plinth = Geo(), chim = Geo(), lines = Geo(), lampGlass = Geo()
        var shutters = [Geo](repeating: Geo(), count: shutterCols.count)
        var winQuads: [Geo] = []
        var lamps: [SIMD3<Float>] = []
        var smokeAt: [SIMD3<Float>] = []
        var houses: [(SIMD3<Float>, Float)] = []
        let lit = dark || room.time == "dusk"
        let up = SIMD3<Float>(0, 1, 0)
        var g2 = g
        let n = 4
        let a0 = Float.random(in: 0...1, using: &g2)
        for i in 0..<n {
            for _ in 0..<12 {
                let W = Float.random(in: 6...9.5, using: &g2), D = Float.random(in: 5...7, using: &g2)
                let floors = Float.random(in: 0...1, using: &g2) < 0.4 ? 2 : 1
                let Hw: Float = floors == 2 ? Float.random(in: 5.2...5.8, using: &g2) : Float.random(in: 2.9...3.3, using: &g2)
                let dd = Float.random(in: 34...60, using: &g2)
                let p = around(a0 + (Float(i) + Float.random(in: 0.15...0.85, using: &g2)) / Float(n), dd, rec, floorY - 0.05)
                let r = simd_length(SIMD2<Float>(W, D)) / 2 + 1.0
                var ok = true
                for k in 0..<12 where ok {
                    let a = Float(k) / 12 * 2 * .pi
                    for f: Float in [0.5, 1] {
                        let q = p + SIMD3<Float>(cos(a), 0, sin(a)) * r * f
                        if L.walkable(L.plane(q.x, q.z)) { ok = false; break }
                    }
                }
                if !ok { continue }
                if treeSpots.contains(where: { simd_distance($0.0.xz, p.xz) < r + $0.1 / 2 + 1.5 }) { continue }
                if houses.contains(where: { simd_distance($0.0.xz, p.xz) < r + $0.1 + 12 }) { continue }
                if riverGap(p) < r + 2 { continue }
                houses.append((p, r))
                let to = center - p
                let yaw = atan2(to.x, to.z) + Float.random(in: -0.45...0.45, using: &g2)
                let fwd = SIMD3<Float>(sin(yaw), 0, cos(yaw)), side = SIMD3<Float>(cos(yaw), 0, -sin(yaw))
                let hw = W / 2, hd = D / 2
                let c = [p - side * hw - fwd * hd, p + side * hw - fwd * hd, p + side * hw + fwd * hd, p - side * hw + fwd * hd]   // 뒤왼·뒤오·앞오·앞왼
                let normals = [-fwd, side, fwd, -side]                                                                      // c[k]→c[k+1] 면의 바깥쪽
                let wk = Int(g2.next() % UInt64(wallKinds.count)), rk = Int(g2.next() % UInt64(roofCols.count))
                let sk = Int(g2.next() % UInt64(shutterCols.count))
                let tile = wallKinds[wk].2
                let pitch = Float.random(in: 0.55...0.8, using: &g2)
                let rh = hd * pitch
                let base: Float = 0.45                                          // 돌 기단 높이
                // 기단 (조금 내밀어)
                plinth.box(base: p, w: W + 0.12, d: D + 0.12, h: base, yaw: yaw, tile: 1.2)
                // 벽 네 면 (기단 위) + 옆면 박공 삼각형 — 면마다 해 방향 그늘
                for k in 0..<4 {
                    let a = c[k], b = c[(k + 1) % 4]
                    let L2 = simd_distance(a, b)
                    walls[wk][shadeK(normals[k])].wall(a, b, y0: base, y1: Hw, u0: 0, u1: L2 / tile, v0: base / tile, v1: Hw / tile)
                    // 모서리 띠 (회벽 집만, 흰 나무 판)
                    if wallKinds[wk].0 == "house_stucco" || wallKinds[wk].0 == "house_plaster" {
                        let d = simd_normalize(b - a)
                        whiteTrim.wall(a + normals[k] * 0.02, a + d * 0.16 + normals[k] * 0.02, y0: base, y1: Hw, u0: 0, u1: 1)
                        whiteTrim.wall(b - d * 0.16 + normals[k] * 0.02, b + normals[k] * 0.02, y0: base, y1: Hw, u0: 0, u1: 1)
                    }
                }
                for (a, b, nn) in [(c[0], c[3], -side), (c[1], c[2], side)] {
                    let m = (a + b) / 2 + up * (Hw + rh)
                    walls[wk][shadeK(nn)].quad(a + up * Hw, b + up * Hw, m, m, SIMD2<Float>(0, Hw / tile), SIMD2<Float>(D / tile, Hw / tile),
                                               SIMD2<Float>(D / 2 / tile, (Hw + rh) / tile), SIMD2<Float>(D / 2 / tile, (Hw + rh) / tile))
                }
                // 지붕: 처마 40cm·양옆 30cm 내밀고 두께(끝막이판) + 용마루
                let ov: Float = 0.4, sv: Float = 0.3
                let ridgeL = p - side * (hw + sv) + up * (Hw + rh), ridgeR = p + side * (hw + sv) + up * (Hw + rh)
                for s2: Float in [-1, 1] {
                    let eave = fwd * s2 * (hd + ov)
                    let drop = up * (Hw - ov * pitch)
                    let e0 = p - side * (hw + sv) + eave + drop, e1 = p + side * (hw + sv) + eave + drop
                    let slope = simd_distance(e0, ridgeL)
                    let rn = simd_normalize(fwd * s2 + up * (1 / max(0.3, pitch)))
                    roofs[rk][shadeK(rn)].quad(e0, e1, ridgeR, ridgeL, SIMD2<Float>(0, 0), SIMD2<Float>((W + 2 * sv) / 1.6, 0),
                                               SIMD2<Float>((W + 2 * sv) / 1.6, slope / 1.6), SIMD2<Float>(0, slope / 1.6))
                    darkWood.wall(e0, e1, y0: -0.16, y1: 0, u0: 0, u1: 1)                   // 처마 끝막이판
                    for (ea, ra) in [(e0, ridgeL), (e1, ridgeR)] {                              // 박공 널 (지붕 옆 끝을 따라)
                        darkWood.quad(ea, ra, ra - up * 0.18, ea - up * 0.18, .zero, .zero, .zero, .zero)
                    }
                    if lineMode {
                        lines.stroke(e0, e1, width: 0.05); lines.stroke(e0, ridgeL, width: 0.05); lines.stroke(e1, ridgeR, width: 0.05)
                    }
                }
                roofs[rk][0].wall(ridgeL, ridgeR, y0: -0.02, y1: 0.12, u0: 0, u1: W / 1.6, v0: 0, v1: 0.1)          // 용마루
                if lineMode {
                    lines.stroke(ridgeL, ridgeR, width: 0.05)
                    for k in 0..<4 {
                        lines.stroke(c[k] + up * base, c[(k + 1) % 4] + up * base, width: 0.04)
                        lines.stroke(c[k], c[k] + up * Hw, width: 0.05)
                    }
                }
                // 굴뚝 + 덮개
                let cx = Float.random(in: -hw * 0.55...hw * 0.55, using: &g2)
                let cz = Float.random(in: 0.2...0.45, using: &g2) * hd
                let cBase = p + side * cx - fwd * cz + up * (Hw + rh * (1 - cz / hd) - 0.3)
                let cH = rh * (cz / hd) + 1.2
                chim.box(base: cBase, w: 0.6, d: 0.6, h: cH, yaw: yaw, tile: 1.6)
                darkWood.box(base: cBase + up * cH, w: 0.76, d: 0.76, h: 0.08, yaw: yaw, tile: 1)
                if lineMode { lines.boxOutline(base: cBase, w: 0.6, d: 0.6, h: cH, yaw: yaw, width: 0.04) }
                if smokeAt.count < 2 && Float.random(in: 0...1, using: &g2) < 0.7 { smokeAt.append(cBase + up * (cH + 0.15)) }
                // 문: 문틀·문짝·문 위 작은 차양·돌계단·문 옆 등
                let fo = fwd * (hd + 0.03)
                let dx = Float.random(in: -hw * 0.35...hw * 0.35, using: &g2)
                let dc = p + fo + side * dx
                let dW: Float = 0.95, dH: Float = 2.05
                darkWood.quad(dc - side * (dW / 2) + up * base, dc + side * (dW / 2) + up * base, dc + side * (dW / 2) + up * (base + dH), dc - side * (dW / 2) + up * (base + dH),
                              .zero, .zero, .zero, .zero)
                for sx: Float in [-1, 1] {
                    whiteTrim.quad(dc + side * sx * (dW / 2) + up * base + fwd * 0.01, dc + side * sx * (dW / 2 + 0.1) + up * base + fwd * 0.01,
                                   dc + side * sx * (dW / 2 + 0.1) + up * (base + dH + 0.1) + fwd * 0.01, dc + side * sx * (dW / 2) + up * (base + dH + 0.1) + fwd * 0.01,
                                   .zero, .zero, .zero, .zero)
                }
                whiteTrim.quad(dc - side * (dW / 2 + 0.1) + up * (base + dH) + fwd * 0.01, dc + side * (dW / 2 + 0.1) + up * (base + dH) + fwd * 0.01,
                               dc + side * (dW / 2 + 0.1) + up * (base + dH + 0.12) + fwd * 0.01, dc - side * (dW / 2 + 0.1) + up * (base + dH + 0.12) + fwd * 0.01,
                               .zero, .zero, .zero, .zero)
                let canopy = up * (base + dH + 0.3)
                roofs[rk][0].quad(dc - side * 0.75 + canopy, dc + side * 0.75 + canopy, dc + side * 0.75 + canopy + fwd * 0.7 - up * 0.3, dc - side * 0.75 + canopy + fwd * 0.7 - up * 0.3,
                                  SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(1, 0.5), SIMD2<Float>(0, 0.5))
                plinth.box(base: dc + fwd * 0.35, w: 1.4, d: 0.7, h: 0.3, yaw: yaw, tile: 1)
                plinth.box(base: dc + fwd * 0.75, w: 1.4, d: 0.5, h: 0.15, yaw: yaw, tile: 1)
                let lampP = dc + side * (dW / 2 + 0.35) + up * (base + 1.85) + fwd * 0.12
                lampGlass.box(base: lampP - up * 0.12, w: 0.14, d: 0.14, h: 0.22, yaw: yaw, tile: 1)
                darkWood.box(base: lampP + up * 0.1, w: 0.2, d: 0.2, h: 0.04, yaw: yaw, tile: 1)
                lamps.append(lampP)
                if lineMode {
                    let a = dc - side * (dW / 2) + up * base, b = dc + side * (dW / 2) + up * base
                    lines.stroke(a, a + up * dH, width: 0.035); lines.stroke(b, b + up * dH, width: 0.035); lines.stroke(a + up * dH, b + up * dH, width: 0.035)
                }
                // 창: 층마다 벽 길이에 맞춰 2~4개 (앞면은 다, 뒷면은 듬성듬성, 옆면 하나씩) — 창틀·십자 살·창턱·덧창
                let wW: Float = 0.9, wH: Float = 1.15
                func window(_ wc: SIMD3<Float>, _ ax: SIMD3<Float>, _ nrm: SIMD3<Float>, _ y0: Float) {
                    let o = nrm * 0.03
                    let a = wc - ax * (wW / 2) + up * y0 + o, b = wc + ax * (wW / 2) + up * y0 + o
                    var q = Geo()
                    q.quad(a, b, b + up * wH, a + up * wH, SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(1, 1), SIMD2<Float>(0, 1))
                    winQuads.append(q)
                    let fw: Float = 0.07, f2 = nrm * 0.01
                    for (p0, p1) in [(a, b), (a + up * wH, b + up * wH)] { whiteTrim.quad(p0 - ax * fw + f2, p1 + ax * fw + f2, p1 + ax * fw + up * fw + f2, p0 - ax * fw + up * fw + f2, .zero, .zero, .zero, .zero) }
                    for p0 in [a, b] { whiteTrim.quad(p0 - ax * (fw / 2) + f2, p0 + ax * (fw / 2) + f2, p0 + ax * (fw / 2) + up * wH + f2, p0 - ax * (fw / 2) + up * wH + f2, .zero, .zero, .zero, .zero) }
                    let mid = (a + b) / 2
                    whiteTrim.quad(mid - ax * 0.025 + f2, mid + ax * 0.025 + f2, mid + ax * 0.025 + up * wH + f2, mid - ax * 0.025 + up * wH + f2, .zero, .zero, .zero, .zero)
                    whiteTrim.quad(a + up * (wH * 0.55) + f2, b + up * (wH * 0.55) + f2, b + up * (wH * 0.55 + 0.05) + f2, a + up * (wH * 0.55 + 0.05) + f2, .zero, .zero, .zero, .zero)
                    // 창턱 (앞으로 12cm)
                    whiteTrim.quad(a - ax * 0.1 - up * 0.03, b + ax * 0.1 - up * 0.03, b + ax * 0.1 - up * 0.03 + nrm * 0.12, a - ax * 0.1 - up * 0.03 + nrm * 0.12, .zero, .zero, .zero, .zero)
                    // 덧창 (회벽 집)
                    if wallKinds[wk].0 == "house_stucco" || wallKinds[wk].0 == "house_plaster" {
                        for (p0, sx) in [(a, Float(-1)), (b, Float(1))] {
                            shutters[sk].quad(p0 + ax * sx * 0.08, p0 + ax * sx * 0.5, p0 + ax * sx * 0.5 + up * wH, p0 + ax * sx * 0.08 + up * wH,
                                              SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(1, 1), SIMD2<Float>(0, 1))
                        }
                    }
                    if lineMode {
                        lines.stroke(a, b, width: 0.03); lines.stroke(b, b + up * wH, width: 0.03); lines.stroke(b + up * wH, a + up * wH, width: 0.03); lines.stroke(a + up * wH, a, width: 0.03)
                        lines.stroke(mid, mid + up * wH, width: 0.02)
                    }
                }
                for fl in 0..<floors {
                    let y0: Float = base + (fl == 0 ? 0.5 : 2.95)
                    let cnt = max(2, min(4, Int(W / 2.3)))
                    for k in 0..<cnt {
                        let x = -hw + W * (Float(k) + 0.5) / Float(cnt)
                        if fl == 0 && abs(x - dx) < 1.25 { continue }                  // 문·등 자리 피함
                        window(p + side * x + fwd * hd, side, fwd, y0)
                        if Float.random(in: 0...1, using: &g2) < 0.5 { window(p + side * x - fwd * hd, -side, -fwd, y0) }
                    }
                    window(p + side * hw, fwd, side, y0)
                    if fl == 0 { window(p - side * hw, -fwd, -side, y0) }
                }
                break
            }
        }
        g = g2
        let tk = Worlds.safe(tint, min: 0.2)
        for (i, set) in walls.enumerated() {
            for (k, geo) in set.enumerated() {
                let (tx, col, _) = wallKinds[i]
                if let e = geo.entity("houseWalls\(i)_\(k)", lineMode ? Ink.paper(k) : Tex.unlit(tx, tint: Worlds.safe(tint * col * shades[k], min: 0.18))) { layer(e, 5); world.addChild(e) }
            }
        }
        for (i, set) in roofs.enumerated() {
            for (k, geo) in set.enumerated() {
                if let e = geo.entity("houseRoof\(i)_\(k)", lineMode ? Ink.paper(min(2, k + 1)) : Tex.unlit("roof_tile", tint: Worlds.safe(tint * roofCols[i] * 1.5 * shades[k], min: 0.12))) { layer(e, 5); world.addChild(e) }
            }
        }
        for (i, geo) in shutters.enumerated() {
            if let e = geo.entity("houseShutters\(i)", lineMode ? Ink.paper(1) : Tex.unlit("planks", tint: Worlds.safe(tint * shutterCols[i] * 1.6, min: 0.15))) { layer(e, 6); world.addChild(e) }
        }
        if let e = plinth.entity("housePlinth", lineMode ? Ink.paper(2) : Tex.unlit("rock", tint: Worlds.safe(tint * 0.8, min: 0.2))) { layer(e, 5); world.addChild(e) }
        if let e = chim.entity("houseChimneys", lineMode ? Ink.paper(1) : Tex.unlit("brick", tint: Worlds.safe(tint * 0.75, min: 0.2))) { layer(e, 5); world.addChild(e) }
        if let e = whiteTrim.entity("houseTrimWhite", lineMode ? Ink.paper(0) : UnlitMaterial(color: Tex.color(SIMD3<Float>(0.9, 0.88, 0.84) * tk))) { layer(e, 6); world.addChild(e) }
        // 선 그림: 짙은 나무(문짝·처마 끝막이·박공 널·굴뚝 덮개)도 흰 종이 면 + 윤곽선 (예전엔 검게 칠해 집 벽에 검은 무늬처럼 보였음)
        if let e = darkWood.entity("houseTrimDark", lineMode ? Ink.paper(2) : Tex.unlit("planks_dark", tint: Worlds.safe(tint * 0.75, min: 0.15))) { layer(e, 6); world.addChild(e) }
        let lampM: RealityKit.Material = lineMode ? Ink.paper(0) : UnlitMaterial(color: Tex.color(lit ? [1, 0.82, 0.5] : SIMD3<Float>(0.7, 0.72, 0.7) * tk))
        if let e = lampGlass.entity("houseLamps", lampM) { layer(e, 6); world.addChild(e) }
        if lit && !lineMode { for c in lamps { glowSprite(at: c, size: 0.9, color: [1, 0.76, 0.45]) } }
        if lineMode, let e = lines.entity("houseLines", Ink.line) { layer(e, 7); world.addChild(e) }
        // 창: 낮엔 하늘이 비친 어두운 유리, 해질녘·밤·새벽엔 켜진 창(따뜻한 불빛)과 꺼진 창이 섞여 있고 가끔씩 바뀜
        let onM: RealityKit.Material = lineMode ? Ink.paper(0) : UnlitMaterial(color: Tex.color([1, 0.78, 0.46]))
        let offM: RealityKit.Material = lineMode ? Ink.paper(0) : UnlitMaterial(color: Tex.color(SIMD3<Float>(0.18, 0.22, 0.27) * Worlds.safe(tint, min: 0.35)))
        winOnMat = onM; winOffMat = offM
        for (i, q) in winQuads.enumerated() {
            let on = lit && Float.random(in: 0...1, using: &g) < 0.5
            guard let e = q.entity("houseWin\(i)", on ? onM : offM) else { continue }
            layer(e, 6)
            world.addChild(e)
            villageWins.append((e: e, next: Float.random(in: 8...50, using: &g), on: on))
        }
        // 굴뚝 연기: 가늘게 오르며 퍼지는 옅은 연기 (그림 판 — 먼 산 띠에 가려 깨지지 않게)
        let sc: SIMD3<Float> = dark ? [0.42, 0.42, 0.46] : [0.86, 0.86, 0.88]
        for c in smokeAt {
            let pl = SmokePlume(at: c, size: 0.35, height: 5, alpha: 0.32, color: sc, look: look, sortGroup: sortGroup)
            world.addChild(pl.root)
            plumes.append(pl)
        }
    }

    /// 마을 창 불빛이 가끔 켜지고 꺼짐 (해질녘·밤·새벽)
    private func tickVillage(_ dt: Float) {
        guard !villageWins.isEmpty, dark || room.time == "dusk", let onM = winOnMat, let offM = winOffMat else { return }
        villageT += dt
        for i in villageWins.indices where villageT > villageWins[i].next {
            villageWins[i].on.toggle()
            // 켜진 창은 오래(30~120초), 꺼진 창은 조금(15~70초) 있다가 바뀜
            villageWins[i].next = villageT + (villageWins[i].on ? Float.random(in: 30...120) : Float.random(in: 15...70))
            villageWins[i].e.model?.materials = [villageWins[i].on ? onM : offM]
        }
    }

    /// 카페 통창 밖 거리: 보도(3m, 바닥과 같은 높이) → 연석 → 2차선 차도(7m, 가운데 점선·양쪽 실선) → 맞은편 보도 → 맞은편 3~5층 건물 줄.
    /// 건물마다 폭·층수·벽 색이 다르고 1층은 가게(진열창·유리문·간판 띠, 몇 곳은 천 차양), 위층은 흰 창틀 창. 지붕 끝 돌림띠.
    /// 해질녘·밤엔 가게 진열창과 위층 창 일부에 불이 켜짐
    private func addCafeStreet<G: RandomNumberGenerator>(_ rec: SpaceRec, floorY: Float, using g: inout G) {
        let hx = halfSize.x, hz = halfSize.y
        let ex3 = SIMD3<Float>(rec.ex.x, 0, rec.ex.y), ez3 = SIMD3<Float>(rec.ez.x, 0, rec.ez.y)
        let lit = dark || room.time == "dusk"
        func P(_ u: Float, _ v: Float, _ y: Float) -> SIMD3<Float> { SIMD3<Float>(center.x, floorY + y, center.z) + ex3 * u + ez3 * v }
        func uvOf(_ p: SIMD3<Float>, _ t: Float) -> SIMD2<Float> { SIMD2<Float>(p.x, p.z) / t }
        let corners: [(Float, Float)] = [(-1, -1), (1, -1), (1, 1), (-1, 1)]
        func ring(_ geo: inout Geo, _ d0: Float, _ d1: Float, _ y: Float, _ t: Float) {
            for k in 0..<4 {
                let (ax, az) = corners[k], (bx, bz) = corners[(k + 1) % 4]
                let a0 = P(ax * (hx + d0), az * (hz + d0), y), b0 = P(bx * (hx + d0), bz * (hz + d0), y)
                let a1 = P(ax * (hx + d1), az * (hz + d1), y), b1 = P(bx * (hx + d1), bz * (hz + d1), y)
                geo.quad(a0, b0, b1, a1, uvOf(a0, t), uvOf(b0, t), uvOf(b1, t), uvOf(a1, t))
            }
        }
        func curb(_ geo: inout Geo, _ d: Float) {
            for k in 0..<4 {
                let (ax, az) = corners[k], (bx, bz) = corners[(k + 1) % 4]
                let a = P(ax * (hx + d), az * (hz + d), -0.16), b = P(bx * (hx + d), bz * (hz + d), -0.16)
                geo.wall(a, b, y0: 0, y1: 0.15, u0: 0, u1: simd_distance(a, b) / 1.2, v0: 0, v1: 0.12)
            }
        }
        var walk = Geo(), road = Geo(), curbs = Geo(), paint = Geo(), lines = Geo()
        ring(&walk, 0, 3.0, -0.015, 1.6)
        ring(&walk, 10, 12.6, -0.015, 1.6)
        ring(&road, 3.0, 10, -0.16, 4)
        curb(&curbs, 3.0); curb(&curbs, 10)
        if lineMode {                                     // 선 그림: 연석 윗선·아랫선
            for d in [Float(3.0), 10] {
                for k in 0..<4 {
                    let (ax, az) = corners[k], (bx, bz) = corners[(k + 1) % 4]
                    for y in [Float(-0.01), -0.16] { lines.stroke(P(ax * (hx + d), az * (hz + d), y), P(bx * (hx + d), bz * (hz + d), y), width: 0.02) }
                }
            }
        }
        // 차선: 가운데 흰 점선(2m 칠·3m 빔), 양쪽 가장자리 실선
        for k in 0..<4 {
            let (ax, az) = corners[k], (bx, bz) = corners[(k + 1) % 4]
            for (d, dash, w) in [(Float(6.5), true, Float(0.12)), (3.35, false, 0.1), (9.65, false, 0.1)] {
                let a = P(ax * (hx + d), az * (hz + d), -0.155), b = P(bx * (hx + d), bz * (hz + d), -0.155)
                let len = simd_distance(a, b), dir = (b - a) / len
                let nrm = SIMD3<Float>(-dir.z, 0, dir.x) * (w / 2)
                var t: Float = 1.5
                while t < len - 1.5 {
                    let t1 = dash ? min(len - 1.5, t + 2) : len - 1.5
                    let p0 = a + dir * t, p1 = a + dir * t1
                    paint.quad(p0 - nrm, p1 - nrm, p1 + nrm, p0 + nrm, .zero, .zero, .zero, .zero)
                    if lineMode { lines.stroke(p0, p1, width: 0.03) }
                    t = dash ? t + 5 : len
                }
            }
        }
        if let e = walk.entity("sidewalk", lineMode ? Ink.paper(0) : Tex.unlit("concrete", tint: Worlds.safe(tint * 0.95, min: 0.25))) { layer(e, 4); world.addChild(e) }
        if let e = road.entity("road", lineMode ? Ink.paper(1) : Tex.unlit("asphalt", tint: Worlds.safe(tint * 0.75, min: 0.18))) { layer(e, 4); world.addChild(e) }
        if let e = curbs.entity("curbs", lineMode ? Ink.paper(1) : Tex.unlit("concrete", tint: Worlds.safe(tint * 0.8, min: 0.22))) { layer(e, 4); world.addChild(e) }
        if let e = paint.entity("roadPaint", lineMode ? Ink.line : UnlitMaterial(color: Tex.color(SIMD3<Float>(0.85, 0.85, 0.8) * Worlds.safe(tint, min: 0.4)))) { layer(e, 5); world.addChild(e) }
        // 맞은편 건물 줄: 네 방향, 앞면이 거리를 봄
        let wallCols: [SIMD3<Float>] = [[1, 0.97, 0.9], [0.98, 0.9, 0.72], [0.9, 0.66, 0.54], [0.78, 0.86, 0.8], [0.8, 0.84, 0.92], [0.94, 0.94, 0.94]]
        let signCols: [SIMD3<Float>] = [[0.25, 0.35, 0.3], [0.5, 0.2, 0.18], [0.2, 0.26, 0.4], [0.75, 0.62, 0.3], [0.3, 0.3, 0.32]]
        var upper = [Geo](repeating: Geo(), count: wallCols.count)
        var shops = [Geo](repeating: Geo(), count: signCols.count)
        var plain = Geo(), roofG = Geo(), awn = [Geo](repeating: Geo(), count: signCols.count)
        let up = SIMD3<Float>(0, 1, 0)
        let sides: [(SIMD3<Float>, SIMD3<Float>, Float, Float)] = [(ez3, ex3, hz, hx + 21.6), (-ez3, -ex3, hz, hx + 21.6), (ex3, -ez3, hx, hz + 12.6), (-ex3, ez3, hx, hz + 12.6)]
        for (nOut, along, hN, hL) in sides {
            var x = -hL
            while x < hL - 3 {
                let w = min(hL - x, Float.random(in: 6...9, using: &g))
                guard w > 3 else { break }
                let floors = Int.random(in: 2...4, using: &g)
                let H: Float = 3.4 + Float(floors) * 3
                let D: Float = 9
                let f0 = SIMD3<Float>(center.x, floorY - 0.015, center.z) + nOut * (hN + 12.6) + along * x       // 앞면 왼쪽 아래
                let f1 = f0 + along * w
                let b0 = f0 + nOut * D, b1 = f1 + nOut * D
                let wc = Int(g.next() % UInt64(wallCols.count)), sc = Int(g.next() % UInt64(signCols.count))
                // 위층 (앞·옆·뒤): 3층마다 9m 그림
                for (a, b) in [(f0, f1), (f1, b1), (b1, b0), (b0, f0)] {
                    let L2 = simd_distance(a, b)
                    upper[wc].wall(a, b, y0: 3.4, y1: H, u0: 0, u1: L2 / 6, v0: 0, v1: (H - 3.4) / 9)
                }
                // 1층: 앞은 가게, 옆·뒤는 벽
                shops[sc].wall(f0 - nOut * 0.02, f1 - nOut * 0.02, y0: 0, y1: 3.4, u0: 0, u1: max(1, (w / 6).rounded()), v0: 0, v1: 1)
                for (a, b) in [(f1, b1), (b1, b0), (b0, f0)] {
                    plain.wall(a, b, y0: 0, y1: 3.4, u0: 0, u1: simd_distance(a, b) / 2, v0: 0, v1: 3.4 / 2)
                }
                // 지붕 + 끝 돌림띠
                roofG.quad(f0 + up * H, f1 + up * H, b1 + up * H, b0 + up * H, .zero, SIMD2<Float>(1, 0), SIMD2<Float>(1, 1), SIMD2<Float>(0, 1))
                roofG.wall(f0 - nOut * 0.2 + up * H, f1 - nOut * 0.2 + up * H, y0: -0.05, y1: 0.35, u0: 0, u1: w / 2, v0: 0, v1: 0.2)
                // 차양 (가게 절반쯤)
                if Float.random(in: 0...1, using: &g) < 0.55 {
                    let ia = f0 + along * 0.3, ib = f1 - along * 0.3
                    let out = -nOut * 1.3
                    awn[sc].quad(ia + up * 3.15, ib + up * 3.15, ib + out + up * 2.65, ia + out + up * 2.65,
                                 SIMD2<Float>(0, 0), SIMD2<Float>(w / 0.6, 0), SIMD2<Float>(w / 0.6, 1), SIMD2<Float>(0, 1))
                    awn[sc].quad(ia + out + up * 2.65, ib + out + up * 2.65, ib + out + up * 2.4, ia + out + up * 2.4,
                                 SIMD2<Float>(0, 0), SIMD2<Float>(w / 0.6, 0), SIMD2<Float>(w / 0.6, 0.3), SIMD2<Float>(0, 0.3))
                }
                if lineMode {
                    for (a, b) in [(f0, f1), (f1, b1), (b1, b0), (b0, f0)] {
                        lines.stroke(a + up * H, b + up * H, width: 0.05); lines.stroke(a + up * 3.4, b + up * 3.4, width: 0.04)
                        lines.stroke(a, a + up * H, width: 0.05)
                    }
                }
                x += w
            }
        }
        for (i, geo) in upper.enumerated() {
            let litTint: SIMD3<Float> = wallCols[i] * Float(0.9) + SIMD3<Float>(repeating: 0.1)
            let dayTint: SIMD3<Float> = Worlds.safe(tint * wallCols[i], min: 0.3)
            let m: RealityKit.Material = lineMode ? Ink.paper(0) : Tex.unlit(lit ? "townhouse_night" : "townhouse", tint: lit ? litTint : dayTint)
            if let e = geo.entity("streetHouses\(i)", m) { layer(e, 5); world.addChild(e) }
        }
        for (i, geo) in shops.enumerated() {
            let litTint: SIMD3<Float> = signCols[i] * Float(0.25) + SIMD3<Float>(repeating: 0.8)
            let mix: SIMD3<Float> = signCols[i] * Float(0.3) + SIMD3<Float>(repeating: 0.75)
            let dayTint: SIMD3<Float> = Worlds.safe(tint * mix, min: 0.3)
            let m: RealityKit.Material = lineMode ? Ink.paper(1) : Tex.unlit(lit ? "shopfront_night" : "shopfront", tint: lit ? litTint : dayTint)
            if let e = geo.entity("streetShops\(i)", m) { layer(e, 5); world.addChild(e) }
        }
        for (i, geo) in awn.enumerated() {
            if let e = geo.entity("streetAwning\(i)", lineMode ? Ink.paper(2) : Tex.unlit("canvas", tint: Worlds.safe(tint * signCols[i] * 1.8, min: 0.2))) { layer(e, 6); world.addChild(e) }
        }
        if let e = plain.entity("streetPlain", lineMode ? Ink.paper(1) : Tex.unlit("plaster", tint: Worlds.safe(tint * 0.8, min: 0.25))) { layer(e, 5); world.addChild(e) }
        if let e = roofG.entity("streetRoofs", lineMode ? Ink.paper(2) : Tex.unlit("concrete", tint: Worlds.safe(tint * 0.55, min: 0.15))) { layer(e, 5); world.addChild(e) }
        if lineMode, let e = lines.entity("streetLines", Ink.line) { layer(e, 6); world.addChild(e) }
    }

    /// 카페 통창 밖 보도의 가로등: 검은 철제 기둥 + 등갓 달린 등. 낮엔 꺼져 있고 해질녘·밤·새벽엔 켜짐.
    /// 해질녘엔 들어온 뒤 하나씩 켜지고(켜질 때 잠깐 깜빡), 켜진 등 하나가 아주 가끔 짧게 깜빡임 — tickCafe
    private func addStreetLamps<G: RandomNumberGenerator>(_ rec: SpaceRec, _ L: Layout, floorY: Float, using g: inout G) {
        var pole = Geo(), lines = Geo()
        let lit = dark || room.time == "dusk"
        let onM: RealityKit.Material = lineMode ? Ink.paper(0) : UnlitMaterial(color: Tex.color([1, 0.86, 0.6]))
        let offM: RealityKit.Material = lineMode ? Ink.paper(0) : UnlitMaterial(color: Tex.color(SIMD3<Float>(0.6, 0.62, 0.62) * Worlds.safe(tint, min: 0.5)))
        lampOn = onM; lampOff = offM
        let n = 5
        for i in 0..<n {
            for _ in 0..<5 {
                let p = around((Float(i) + Float.random(in: 0.2...0.8, using: &g)) / Float(n), Float.random(in: 2.5...2.7, using: &g), rec, floorY)      // 보도 끝(차도 쪽)
                var ok = true
                for k in 0..<8 {
                    let a = Float(k) / 8 * 2 * .pi
                    let q = p + SIMD3<Float>(cos(a), 0, sin(a)) * 0.6
                    if L.walkable(L.plane(q.x, q.z)) { ok = false; break }
                }
                guard ok else { continue }
                let H: Float = 3.6
                pole.trunk(from: p, to: p + SIMD3<Float>(0, H, 0), r0: 0.055, r1: 0.04, sides: 10, segs: 1)
                pole.trunk(from: p, to: p + SIMD3<Float>(0, 0.35, 0), r0: 0.09, r1: 0.07, sides: 10, segs: 1)       // 받침
                let c = p + SIMD3<Float>(0, H + 0.12, 0)
                var head = Geo()
                head.trunk(from: c - SIMD3<Float>(0, 0.16, 0), to: c + SIMD3<Float>(0, 0.06, 0), r0: 0.11, r1: 0.09, sides: 10, segs: 1)   // 유리 등
                pole.trunk(from: c + SIMD3<Float>(0, 0.06, 0), to: c + SIMD3<Float>(0, 0.16, 0), r0: 0.17, r1: 0.03, sides: 10, segs: 1)  // 등갓
                if lineMode {
                    lines.stroke(p, p + SIMD3<Float>(0, H, 0), width: 0.03)
                    lines.boxOutline(base: c - SIMD3<Float>(0, 0.16, 0), w: 0.2, d: 0.2, h: 0.22, yaw: 0, width: 0.012)
                }
                guard let he = head.entity("lampHead\(i)", offM) else { break }
                layer(he, 5); world.addChild(he)
                var glow: Entity? = nil
                if lit && !lineMode {
                    glow = glowSprite(at: c, size: 0.9, color: [1, 0.78, 0.48])
                    glow?.isEnabled = false
                }
                // 밤·새벽: 처음부터 켜짐. 해질녘: 3~16초 사이에 하나씩 켜짐
                let start: Float = room.time == "dusk" ? Float.random(in: 3...16, using: &g) : 0
                lamps.append((head: he, glow: glow, on: false, wantOn: lit, startT: start, flick: 0, flickT: 0,
                              next: Float.random(in: 25...80, using: &g)))
                break
            }
        }
        if let e = pole.entity("lampPoles", lineMode ? Ink.line : UnlitMaterial(color: Tex.color(SIMD3<Float>(0.08, 0.08, 0.09) * Worlds.safe(tint, min: 0.5)))) { layer(e, 5); world.addChild(e) }
        if lineMode, let e = lines.entity("lampLines", Ink.line) { layer(e, 6); world.addChild(e) }
        if room.time != "dusk" { for i in lamps.indices where lamps[i].wantOn { setLamp(i, true) } }
    }

    private func setLamp(_ i: Int, _ on: Bool) {
        guard lamps[i].on != on, let onM = lampOn, let offM = lampOff else { return }
        lamps[i].on = on
        lamps[i].head.model?.materials = [on ? onM : offM]
        lamps[i].glow?.isEnabled = on
    }

    /// 카페 거리 등 (켜짐·깜빡임) + 가로수 낙엽
    private func tickCafe(_ dt: Float) {
        guard room.place == "cafe" else { return }
        cafeT += dt
        for i in lamps.indices where lamps[i].wantOn {
            if lamps[i].flick > 0 {
                // 깜빡이는 중: 0.05~0.14초마다 꺼졌다 켜졌다, 끝나면 켜진 채로
                lamps[i].flick -= dt
                lamps[i].flickT -= dt
                if lamps[i].flick <= 0 { setLamp(i, true) }
                else if lamps[i].flickT <= 0 {
                    setLamp(i, !lamps[i].on)
                    lamps[i].flickT = Float.random(in: 0.05...0.14)
                }
            } else if !lamps[i].on {
                if cafeT > lamps[i].startT { lamps[i].flick = Float.random(in: 0.5...1.2); lamps[i].flickT = 0 }     // 켜질 때 잠깐 깜빡
            } else if cafeT > lamps[i].next {
                lamps[i].next = cafeT + Float.random(in: 40...120)
                if Float.random(in: 0...1) < 0.5 { lamps[i].flick = Float.random(in: 0.3...0.9); lamps[i].flickT = 0 }
            }
        }
        tickLeaves(dt)
    }

    // MARK: 카페 가로수 낙엽 (그림 판 몇 장 — 나뭇가지 높이에서 흔들리며 천천히 떨어져 보도에 내려앉았다가 사라짐)
    private struct FallLeaf {
        var e: ModelEntity
        var p: SIMD3<Float>
        var ground: Float
        var phase: Float
        var spin: Float
        var sway: Float
        var drift: SIMD3<Float>  // 바람에 밀리는 쪽 (늘 방 바깥쪽 — 창 안으로 들어오지 않게)
        var wait: Float          // > 0: 쉬는 중(안 보임)
        var rest: Float          // > 0: 땅에 누워 있음
    }
    private var leaves: [FallLeaf] = []
    private var leafWind: Float = 0.15
    private var leafAxes = (SIMD2<Float>(1, 0), SIMD2<Float>(0, 1))

    /// 방 벽 바깥으로 얼마나 나가 있는지 (안이면 음수)와 바깥쪽 방향
    private func outside(_ p: SIMD3<Float>) -> (Float, SIMD3<Float>) {
        let d = p.xz - center.xz
        let u = simd_dot(d, leafAxes.0), v = simd_dot(d, leafAxes.1)
        let du = abs(u) - halfSize.x, dv = abs(v) - halfSize.y
        let n2 = du > dv ? leafAxes.0 * (u < 0 ? -1 : 1) : leafAxes.1 * (v < 0 ? -1 : 1)
        return (max(du, dv), SIMD3<Float>(n2.x, 0, n2.y))
    }

    private func addFallingLeaves<G: RandomNumberGenerator>(_ rec: SpaceRec, floorY: Float, using g: inout G) {
        leafAxes = (rec.ex, rec.ez)
        guard !crowns.isEmpty, !["snow", "heavysnow"].contains(room.weather) else { return }
        let cols: [SIMD3<Float>] = [[0.86, 0.56, 0.2], [0.72, 0.36, 0.16], [0.84, 0.72, 0.3], [0.56, 0.6, 0.26]]
        var mats: [RealityKit.Material] = []
        for c in cols {
            var m = Tex.cutout("leaf_bit", tint: lineMode ? SIMD3<Float>(0.25, 0.25, 0.25) : Worlds.safe(tint * c, min: 0.15), sampler: Tex.clamp)
            m.faceCulling = .none
            mats.append(m)
        }
        var q = Geo()
        q.card(.zero, SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 0, 1), w: 0.075, h: 0.075)     // 눕힌 잎 (흔들리며 기울어짐)
        guard let mesh = q.mesh("fallLeaf") else { return }
        leafWind = room.weather == "wind" || room.weather == "storm" ? 0.6 : 0.12
        let n = min(10, crowns.count * 2)
        for k in 0..<n {
            let e = ModelEntity(mesh: mesh, materials: [mats[k % mats.count]])
            e.isEnabled = false
            layer(e, 6)
            world.addChild(e)
            leaves.append(FallLeaf(e: e, p: .zero, ground: floorY - 0.012, phase: 0, spin: 0, sway: 0, drift: .zero,
                                   wait: Float.random(in: 0.5...14, using: &g), rest: 0))
        }
    }

    private func tickLeaves(_ dt: Float) {
        for i in leaves.indices {
            var f = leaves[i]
            if f.wait > 0 {
                f.wait -= dt
                if f.wait <= 0, let c = crowns.randomElement() {
                    let a = Float.random(in: 0...(2 * .pi)), r = c.2 * Float.random(in: 0.1...0.42)
                    f.p = c.0 + SIMD3<Float>(cos(a) * r, c.1 * Float.random(in: 0.5...0.75), sin(a) * r)
                    let (od, nOut) = outside(f.p)
                    guard od > 0.6 else { f.wait = 0.5; leaves[i] = f; continue }      // 창에 너무 가까우면 다음에
                    f.drift = nOut * leafWind
                    f.phase = Float.random(in: 0...6.3)
                    f.spin = Float.random(in: -1.6...1.6)
                    f.sway = Float.random(in: 0.12...0.3)
                    f.rest = 0
                    f.e.isEnabled = true
                }
            } else if f.rest > 0 {
                f.rest -= dt
                if f.rest <= 0 { f.e.isEnabled = false; f.wait = Float.random(in: 3...16) }
            } else {
                // 떨어지는 중: 천천히(초속 0.4~0.55m) 내려오며 좌우로 흔들리고 빙글 돎
                f.phase += dt
                let fall = 0.42 + 0.12 * sin(f.phase * 1.7)
                f.p.y -= fall * dt
                f.p += f.drift * dt
                let s = sin(f.phase * 2.2) * f.sway
                let side = SIMD3<Float>(cos(f.phase * 0.4), 0, sin(f.phase * 0.4))
                var pos = f.p + side * s
                var tilt = simd_quatf(angle: sin(f.phase * 2.2 + 1.2) * 0.9, axis: side)
                if f.p.y <= f.ground {
                    pos.y = f.ground
                    tilt = simd_quatf(angle: 0, axis: [0, 1, 0])
                    f.rest = Float.random(in: 4...10)        // 내려앉아 잠시 머묾
                }
                f.e.position = pos
                f.e.orientation = tilt * simd_quatf(angle: f.phase * f.spin, axis: [0, 1, 0])
            }
            leaves[i] = f
        }
    }

    /// 물길 가장자리까지 거리 (물 위면 음수)
    private func riverGap(_ p: SIMD3<Float>) -> Float {
        var best: Float = 1e9
        let q = SIMD2<Float>(p.x, p.z)
        // 방에서 나가는 냇물 (개울 → 협곡 → 지평선)
        if let c = creek, c.exitPath.count > 1 {
            let ps = c.exitPath, ws = c.exitPathW
            for i in 0..<(ps.count - 1) {
                let a = ps[i], b = ps[i + 1], ab = b - a
                let t = max(0, min(1, simd_dot(q - a, ab) / max(1e-6, simd_length_squared(ab))))
                best = min(best, simd_distance(q, a + ab * t) - (ws[i] + (ws[i + 1] - ws[i]) * t) / 2)
            }
        }
        guard riverPts.count > 1 else { return best }
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
                if Float.random(in: 0...1, using: &g) < 0.22 && !(riverFeedsRoom && i > pts.count - 12) {
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
        if !riverFeedsRoom {                                             // 방으로 흘러드는 물길은 끝을 막지 않음
            for k in -1...1 {
                let bs = Float.random(in: 1.3...2.2, using: &g)
                stones.rock(at: SIMD3<Float>(pe.x, floorY - 0.2, pe.z) + ne * Float(k) * 1.6 + te * 0.6, size: bs, using: &g)
            }
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
            // 물살 반짝임: 멀리서 비스듬히 보면 무늬가 겹쳐 하얀 띠처럼 보였음 → 은은하게 (물빛이 비쳐 보이게)
            let hiTint: SIMD3<Float> = night ? SIMD3<Float>(0.42, 0.46, 0.55) : Worlds.safe(tint, min: 0.5) * 0.85
            var hm = Tex.unlit("river_hi", tint: hiTint)
            if let mk = Tex.get("river_hi_a", raw: true) {
                var tp = MaterialParameters.Texture(mk); tp.sampler = Tex.tiling
                hm.blending = .transparent(opacity: .init(scale: night ? 0.18 : 0.32, texture: tp))
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
        if lineMode, let h = stones.inkHull("riverRocksInk", width: inkW) { layer(h, 5); world.addChild(h) }
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
        fallSpot = fb + SIMD3<Float>(0, 2, 0)
        riverNear = riverFeedsRoom ? pts.last : pts.min { simd_distance($0, center) < simd_distance($1, center) }
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

    /// 계곡 둘레 절벽: 얇은 그림 띠 대신 두께가 있는 입체 암벽 — 울퉁불퉁 앞뒤로 튀어나온 바위 면(실사 암벽 무늬),
    /// 위로 갈수록 조금 뒤로 기울고, 꼭대기는 들쭉날쭉한 능선에서 바깥으로 이어진 평평한 윗면(풀·흙)이라 옆에서 봐도 종이처럼 얇지 않음
    private func addCliffRing(R: Float, floorY: Float) {
        let N = 140, M = 14
        let base = R + 40
        var g = SeededRNG(seed: UInt64(room.id * 389 + 21))
        let s1 = Float.random(in: 0...10, using: &g), s2 = Float.random(in: 0...10, using: &g)
        func nz(_ a: Float, _ y: Float) -> Float {
            sin(a * 7 + s1) * 0.5 + sin(a * 17 + y * 0.13 + s2) * 0.3 + sin(a * 41 - y * 0.27 + s1) * 0.14 + sin(a * 93 + y * 0.6) * 0.06
        }
        func topH(_ a: Float) -> Float { 34 + 9 * sin(a * 3 + s2) + 6 * nz(a, 40) }
        func pt(_ a: Float, _ y: Float, _ H: Float) -> SIMD3<Float> {
            let k = y / H
            let r = base + 3.2 * nz(a, y) + 5 * k * k + (k > 0.92 ? (k - 0.92) * 20 : 0)      // 위로 갈수록 뒤로, 맨 위는 둥글게 넘어감
            return SIMD3<Float>(center.x + cos(a) * r, floorY - 2 + y, center.z + sin(a) * r)
        }
        var wall = Geo(), top = Geo(), lines = Geo()
        // 방에서 나간 냇물이 절벽을 지나는 곳: 절벽을 갈라 협곡을 냄 (냇물이 협곡 사이로 지평선 쪽까지 이어져 보임)
        var gapA: Float? = nil
        if let c = creek, c.exitPath.count > 1 {
            for i in 0..<(c.exitPath.count - 1) {
                let p0 = c.exitPath[i] - center.xz, p1 = c.exitPath[i + 1] - center.xz
                if simd_length(p0) < base && simd_length(p1) >= base { gapA = atan2(p1.y, p1.x); break }
            }
        }
        let gapHalf: Float = 7.5 / base                                    // 협곡 폭 약 15m
        func inGap(_ a: Float) -> Bool {
            guard let ga = gapA else { return false }
            var d = a - ga
            d = atan2(sin(d), cos(d))
            return abs(d) < gapHalf
        }
        var arc: Float = 0
        for i in 0..<N {
            let a0 = Float(i) / Float(N) * 2 * .pi, a1 = Float(i + 1) / Float(N) * 2 * .pi
            if inGap(a0) || inGap(a1) || inGap((a0 + a1) / 2) { arc += base * (a1 - a0); continue }
            let H0 = topH(a0), H1 = topH(a1)
            let seg = base * (a1 - a0)
            for j in 0..<M {
                let f0 = Float(j) / Float(M), f1 = Float(j + 1) / Float(M)
                let p00 = pt(a0, H0 * f0, H0), p10 = pt(a1, H1 * f0, H1), p11 = pt(a1, H1 * f1, H1), p01 = pt(a0, H0 * f1, H0)
                wall.quad(p00, p10, p11, p01, SIMD2<Float>(arc / 9, H0 * f0 / 9), SIMD2<Float>((arc + seg) / 9, H1 * f0 / 9),
                          SIMD2<Float>((arc + seg) / 9, H1 * f1 / 9), SIMD2<Float>(arc / 9, H0 * f1 / 9))
            }
            // 윗면: 능선에서 바깥으로 14m 이어지는 거의 평평한 땅
            let t0 = pt(a0, H0, H0), t1 = pt(a1, H1, H1)
            let o0 = SIMD3<Float>(center.x + cos(a0) * (base + 22), t0.y + 1.5, center.z + sin(a0) * (base + 22))
            let o1 = SIMD3<Float>(center.x + cos(a1) * (base + 22), t1.y + 1.5, center.z + sin(a1) * (base + 22))
            top.quad(t0, t1, o1, o0, SIMD2<Float>(t0.x, t0.z) / 4, SIMD2<Float>(t1.x, t1.z) / 4, SIMD2<Float>(o1.x, o1.z) / 4, SIMD2<Float>(o0.x, o0.z) / 4)
            if lineMode {
                lines.stroke(t0, t1, width: 0.22)
                if i % 7 == 0 {
                    var prev = pt(a0, 0, H0)
                    for j in 1...M {
                        let p = pt(a0 + 0.004 * sin(Float(j) * 1.7), H0 * Float(j) / Float(M), H0)
                        if j % 3 != 0 { lines.stroke(prev, p, width: 0.12) }
                        prev = p
                    }
                }
            }
            arc += seg
        }
        // 협곡 양쪽 벽: 갈라진 절벽 끝에서 바깥으로 30m, 위로 갈수록 뒤로 물러나는 바위벽 (끝은 절벽 윗면 높이)
        if let ga = gapA {
            for sd: Float in [-1, 1] {
                let a = ga + sd * gapHalf
                let H = topH(a)
                let radial = SIMD3<Float>(cos(a), 0, sin(a)), side = SIMD3<Float>(-sin(a), 0, cos(a)) * (-sd)      // 협곡 안쪽 방향
                let K = 10, J = 8
                for k in 0..<K {
                    for j in 0..<J {
                        func gp(_ kk: Int, _ jj: Int) -> SIMD3<Float> {
                            let r = base - 1 + 32 * Float(kk) / Float(K)
                            let y = H * Float(jj) / Float(J)
                            let back = 3.5 * (y / H) * (y / H) + 1.2 * sin(Float(kk) * 1.3 + Float(jj) * 0.7 + s1)      // 위로 갈수록 뒤로, 울퉁불퉁
                            return SIMD3<Float>(center.x, floorY - 2, center.z) + radial * r - side * back + SIMD3<Float>(0, y, 0)
                        }
                        let p00 = gp(k, j), p10 = gp(k + 1, j), p11 = gp(k + 1, j + 1), p01 = gp(k, j + 1)
                        let u0 = Float(k) * 3.2 / 9, u1 = Float(k + 1) * 3.2 / 9
                        wall.quad(p00, p10, p11, p01, SIMD2<Float>(u0, p00.y / 9), SIMD2<Float>(u1, p10.y / 9), SIMD2<Float>(u1, p11.y / 9), SIMD2<Float>(u0, p01.y / 9))
                    }
                }
                if lineMode {
                    let t0 = SIMD3<Float>(center.x, floorY - 2, center.z) + radial * (base - 1) - side * 3.5 + SIMD3<Float>(0, H, 0)
                    lines.stroke(t0, t0 + radial * 32, width: 0.22)
                }
            }
        }
        // 절벽 밑 너덜 비탈: 절벽에서 무너져 내린 돌 비탈(높이 2.5m→바닥, 폭 5m 안팎)과 큰 바위들 — 절벽과 땅이 만나는 곳이 자연스럽게
        var talus = Geo(), boulders = Geo()
        for i in 0..<N {
            let a0 = Float(i) / Float(N) * 2 * .pi, a1 = Float(i + 1) / Float(N) * 2 * .pi
            if inGap(a0) || inGap(a1) { continue }
            func inner(_ a: Float) -> SIMD3<Float> {
                let r = base - 5.5 + 1.6 * sin(a * 11 + s1) + 0.8 * sin(a * 29 + s2)
                return SIMD3<Float>(center.x + cos(a) * r, floorY - 0.02, center.z + sin(a) * r)
            }
            let o0 = pt(a0, 4.5, topH(a0)), o1 = pt(a1, 4.5, topH(a1))
            let i0 = inner(a0), i1 = inner(a1)
            talus.quad(i0, i1, o1, o0, SIMD2<Float>(i0.x, i0.z) / 3, SIMD2<Float>(i1.x, i1.z) / 3, SIMD2<Float>(o1.x, o1.z) / 3 + SIMD2<Float>(0, 0.8),
                       SIMD2<Float>(o0.x, o0.z) / 3 + SIMD2<Float>(0, 0.8))
        }
        for _ in 0..<90 {
            let a = Float.random(in: 0...(2 * .pi), using: &g)
            let r = base - Float.random(in: 2...7, using: &g)
            let bp = SIMD3<Float>(center.x + cos(a) * r, floorY - 0.1, center.z + sin(a) * r)
            let bs = Float.random(in: 0.5...1.8, using: &g)
            if riverGap(bp) > bs + 0.6 { boulders.rock(at: bp, size: bs, using: &g) }
        }
        if let e = talus.entity("cliffTalus", Tex.unlit("rock", tint: Worlds.safe(tint * 0.7, min: 0.18))) { layer(e, 2); world.addChild(e) }
        if let e = boulders.entity("cliffBoulders", Tex.unlit("rock", tint: Worlds.safe(tint * 0.8, min: 0.2))) { layer(e, 3); world.addChild(e) }
        if lineMode, let h = boulders.inkHull("cliffBouldersInk", width: inkW) { layer(h, 3); world.addChild(h) }
        let tx = Tex.get("cliff") != nil ? "cliff" : "rock"
        if let e = wall.entity("cliffRing", Tex.unlit(tx, tint: Worlds.safe(tint * 0.85, min: 0.2))) { layer(e, 2); world.addChild(e) }
        if let e = top.entity("cliffTop", Tex.unlit("grass", tint: Worlds.safe(tint * 0.7, min: 0.2))) { layer(e, 2); world.addChild(e) }
        if lineMode, let e = lines.entity("cliffRingLines", Ink.line) { layer(e, 3); world.addChild(e) }
        // 능선 위 듬성듬성 소나무 (입체)
        var tr = Geo(), lv = Geo()
        var inkPaper = Geo(), inkHullG = Geo()
        for _ in 0..<26 {
            let a = Float.random(in: 0...(2 * .pi), using: &g)
            if inGap(a) { continue }                                 // 협곡 위엔 땅이 없음
            let H = topH(a)
            let p = pt(a, H, H) + SIMD3<Float>(cos(a), 0, sin(a)) * Float.random(in: 2...10, using: &g) + SIMD3<Float>(0, 0.6, 0)
            let h = Float.random(in: 7...13, using: &g)
            if lineMode {
                Geo.inkTree("tree_pine", &inkPaper, &inkHullG, at: p, height: h, width: h * 0.45, pen: inkW(p), using: &g)      // 선 그림: 같은 펜 굵기 외곽선
            } else {
                Geo.pineTree(&tr, &lv, at: p, height: h, width: h * 0.45, using: &g)
            }
        }
        if lineMode {
            if let e = inkPaper.entity("ridgeInkPines", Ink.paper(0)) { layer(e, 3); world.addChild(e) }
            if let e = inkHullG.entity("ridgeInkTrunks", Ink.hullMat) { layer(e, 3); world.addChild(e) }
            if let e = inkPaper.inkHull("ridgeInkPineLines", width: { inkW($0) }) { layer(e, 3); world.addChild(e) }
            return
        }
        if let e = tr.entity("ridgeTrunks", lineMode ? Ink.line : Tex.unlit("bark", tint: Worlds.safe(tint * 0.7, min: 0.2))) { layer(e, 3); world.addChild(e) }
        if let e = lv.entity("ridgePines", Tex.cutout("pine_branch", tint: Worlds.safe(tint * 0.85, min: 0.2), sampler: Tex.clamp)) { layer(e, 3); world.addChild(e) }
    }

    /// 장소마다의 특징 만들기
    private func addFeature(_ L: Layout, segs: [WallSeg], floorY: Float, ceilY: Float) {
        switch room.place {
        case "sea":
            // 방 안 해파리는 이 방 크기로, 바다 위 큰 해파리는 대표 방만 (무리 전체 둘레에)
            let j = JellySea(center: roomCenter, halfSize: roomHalf, floorY: floorY, ceilY: ceilY, layout: L, room: room, look: look,
                             outside: host == nil, worldCenter: center, worldHalf: halfSize)
            layerAll(j.root, 30)
            if host == nil { world.addChild(j.root) }
            Sorting.apply(j.localRoot, 30)                   // 포털(0번)보다 나중에 — 하늘 쪽에서 지워지지 않게
            local.addChild(j.localRoot)                      // 방 안 해파리는 실제 방 쪽 (가구와 앞뒤가 맞게)
            jelly = j
        case "valley":
            if let c = creek {                                   // 벽보다 먼저 만들어 둔 개울 (build 처음)
                local.addChild(c.local)
                world.addChild(c.world)
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
        if room.place == "valley" { addCliffRing(R: simd_length(halfSize), floorY: floorY) }      // 물길은 build 처음에 정함
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
                    // 머리 위(눈높이에서 55도 넘게)는 나무가 덮지 않게: 꼭대기까지 높이 × 0.7 보다 집에서 멀리.
                    // 가까이 선 10~20m 나무의 잎 판이 머리 위를 가득 덮으면, 올려다보며 고개를 돌릴 때 가까운 만큼 크게 움직여
                    // 그림이 조금만 늦어도 흔들리고 초점이 안 맞는 것처럼 보였고(울렁거림), 겹친 잎 판이 화면을 가득 채워 그리기도 무거웠음
                    dd = max(dd, (h - 1.6) * 0.7)
                    let p = around((Float(i) + Float.random(in: 0...0.8, using: &g)) / Float(set.count), dd, rec, floorY - 0.1)
                    let w = h * set.aspect * Float.random(in: 0.85...1.15, using: &g)
                    let yaw = Float.random(in: 0...3.14, using: &g)
                    if treeFree(p, w, yaw) && riverGap(p) > 1.2 { list.append((p, h, w, yaw)); break }
                }
            }
            list.sort { simd_distance($0.0, center) > simd_distance($1.0, center) }
            treeSpots += list.map { ($0.0, $0.2) }
            crowns += list.map { ($0.0, $0.1, $0.2) }
            // 선 그림: 잎 판 대신 흰 덩어리 수관·줄기 + 다른 물체와 같은 펜 굵기 외곽선 (잎 판 윤곽 그림은 멀면 너무 가늘고 굵기가 제각각이었음)
            if lineMode {
                var paperG = Geo(), hullG = Geo()
                for (p, h, w, _) in list {
                    Geo.inkTree(set.tex, &paperG, &hullG, at: p, height: h, width: w, pen: inkW(p + SIMD3<Float>(0, h * 0.5, 0)), using: &g)
                }
                if let e = paperG.entity("inkTrees_\(set.tex)", Ink.paper(0)) { layer(e, 5); world.addChild(e) }
                if let e = hullG.entity("inkTreeTrunkLines_\(set.tex)", Ink.hullMat) { layer(e, 5); world.addChild(e) }
                if let e = paperG.inkHull("inkTreeLines_\(set.tex)", width: { inkW($0) }) { layer(e, 5); world.addChild(e) }
                continue
            }
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
        if room.place == "cafe" {
            addStreetLamps(rec, L, floorY: floorY, using: &g)
            addCafeStreet(rec, floorY: floorY, using: &g)
            addFallingLeaves(rec, floorY: floorY, using: &g)
        }
        if room.place == "village" { addVillageHouses(rec, L, floorY: floorY, using: &g) }
        if let rk = dc.rocks {
            var geo = Geo()
            for i in 0..<rk.count {
                for _ in 0..<6 {
                    let dd = Float.random(in: rk.d, using: &g)
                    let p = around((Float(i) + Float.random(in: 0...0.9, using: &g)) / Float(rk.count), dd, rec, floorY)
                    var size = Float.random(in: rk.size, using: &g)
                    if room.place == "valley" { size = min(size, 0.35 + dd * 0.12) }      // 계곡: 가까운 바위는 낮게 (낮춘 둑 너머 풍경을 가리지 않게)
                    if roundFree(p, size * 1.2 + 0.15) && riverGap(p) > size * 0.7 { geo.rock(at: p, size: size, using: &g); break }
                }
            }
            if let e = geo.entity("rocks", Tex.unlit(rk.tex, tint: Worlds.safe(tint * shades[1], min: 0.25))) { world.addChild(e) }
            if lineMode, let h = geo.inkHull("rocksInk", width: inkW) { world.addChild(h) }
        }
        if !riverPts.isEmpty { addRiver(floorY: floorY, using: &g) }
        var tentLines = Geo()
        defer { if let e = tentLines.entity("tentLines", Ink.line) { world.addChild(e) } }
        if dc.tents {
            // 캠핑장: 모양이 다른 텐트 넷 (돔·터널·벨 텐트·A형) — 색도 저마다, 문은 캠프 가운데(방) 쪽을 봄.
            // 텐트 사이 나무 기둥에 걸린 알전구 줄(가운데가 처진 줄에 전구가 줄지어)과 텐트 앞 갈고리 기둥에 매단 캠핑 랜턴
            let palette: [SIMD3<Float>] = [[0.92, 0.5, 0.22], [0.3, 0.46, 0.3], [0.22, 0.4, 0.66], [0.9, 0.74, 0.26], [0.7, 0.22, 0.18], [0.62, 0.58, 0.44]]
            var cols = palette
            cols.shuffle(using: &g)
            let lit = dark || room.time == "dusk"
            let kinds = [0, 1, 2, 3].shuffled(using: &g)
            var spots: [SIMD3<Float>] = []
            for i in 0..<4 {
                for _ in 0..<6 {
                    let p = around(Float(i) / 4 + Float.random(in: 0...0.15, using: &g), Float.random(in: 3...8.5, using: &g), rec, floorY - 0.05)
                    let kind = kinds[i]
                    let rad: Float = kind == 2 ? 2.2 : 1.7
                    guard roundFree(p, rad + 0.6), !spots.contains(where: { simd_distance($0, p) < 4.2 }) else { continue }
                    let to = center - p
                    let yaw = atan2(to.x, to.z) + Float.random(in: -0.3...0.3, using: &g)
                    var parts = Geo.TentParts()
                    switch kind {
                    case 0: Geo.domeTent(&parts, at: p, w: Float.random(in: 2.0...2.6, using: &g), l: Float.random(in: 2.0...2.4, using: &g), h: Float.random(in: 1.1...1.35, using: &g), yaw: yaw)
                    case 1: Geo.tunnelTent(&parts, at: p, w: 2.0, l: Float.random(in: 3.0...3.8, using: &g), h: 1.25, yaw: yaw)
                    case 2: Geo.bellTent(&parts, at: p, r: Float.random(in: 1.9...2.2, using: &g), h: Float.random(in: 2.6...2.9, using: &g), yaw: yaw)
                    default: Geo.ridgeTent(&parts, at: p, w: 2.0, l: 2.4, h: 1.4, yaw: yaw + .pi)
                    }
                    let col = kind == 2 ? SIMD3<Float>(0.9, 0.86, 0.74) : cols[i % cols.count]          // 벨 텐트는 생지 캔버스
                    let fab = lineMode ? Ink.paper(0) : Tex.unlit("canvas", tint: col * Worlds.safe(tint, min: 0.3))
                    let drk = lineMode ? Ink.paper(2) : Tex.unlit("canvas", tint: col * 0.38 * Worlds.safe(tint, min: 0.3))
                    let pol = lineMode ? Ink.line : UnlitMaterial(color: Tex.color(SIMD3<Float>(0.22, 0.22, 0.24) * Worlds.safe(tint, min: 0.4)))
                    if let e = parts.fabric.entity("tent\(i)", fab) { layer(e, 5); world.addChild(e) }
                    if let e = parts.dark.entity("tentDoor\(i)", drk) { layer(e, 5); world.addChild(e) }
                    if let e = parts.poles.entity("tentPoles\(i)", pol) { layer(e, 5); world.addChild(e) }
                    if lineMode, let e = parts.lines.entity("tentLines\(i)", Ink.line) { layer(e, 6); world.addChild(e) }
                    spots.append(p)
                    // 텐트 앞 랜턴: 갈고리 기둥 + 매달린 랜턴 (밤엔 불빛)
                    if dc.lanterns {
                        let side = SIMD3<Float>(cos(yaw), 0, -sin(yaw)), fwdT = SIMD3<Float>(sin(yaw), 0, cos(yaw))
                        let lp = p + fwdT * (rad + 0.5) + side * 0.9
                        var hook = Geo(), lamp = Geo()
                        hook.stroke(lp, lp + SIMD3<Float>(0, 1.5, 0), width: 0.025)
                        hook.stroke(lp + SIMD3<Float>(0, 1.5, 0), lp + SIMD3<Float>(0, 1.55, 0) + side * 0.22, width: 0.02)
                        let lc = lp + side * 0.24 + SIMD3<Float>(0, 1.3, 0)
                        hook.stroke(lp + SIMD3<Float>(0, 1.55, 0) + side * 0.22, lc + SIMD3<Float>(0, 0.12, 0), width: 0.006)
                        lamp.trunk(from: lc - SIMD3<Float>(0, 0.1, 0), to: lc + SIMD3<Float>(0, 0.08, 0), r0: 0.06, r1: 0.05, sides: 10, segs: 1)
                        var cap = Geo()
                        cap.trunk(from: lc + SIMD3<Float>(0, 0.08, 0), to: lc + SIMD3<Float>(0, 0.13, 0), r0: 0.07, r1: 0.03, sides: 10, segs: 1)
                        cap.trunk(from: lc - SIMD3<Float>(0, 0.13, 0), to: lc - SIMD3<Float>(0, 0.1, 0), r0: 0.065, r1: 0.07, sides: 10, segs: 1)
                        if let e = hook.entity("lanternHook\(i)", lineMode ? Ink.line : UnlitMaterial(color: Tex.color([0.12, 0.12, 0.13]))) { layer(e, 5); world.addChild(e) }
                        if let e = cap.entity("lanternCap\(i)", lineMode ? Ink.line : UnlitMaterial(color: Tex.color([0.16, 0.3, 0.22]))) { layer(e, 5); world.addChild(e) }
                        let glass = lineMode ? Ink.paper(0) : UnlitMaterial(color: Tex.color(lit ? [1, 0.84, 0.55] : [0.82, 0.84, 0.82]))
                        if let e = lamp.entity("lanternGlass\(i)", glass) { layer(e, 5); world.addChild(e) }
                        if lit && !lineMode { glowSprite(at: lc, size: 0.9, color: [1, 0.72, 0.4]) }
                    }
                    break
                }
            }
            // 알전구 줄: 나무 기둥 셋 (텐트 사이 빈 곳) — 기둥 꼭대기를 잇는 줄이 가운데로 처지고 45cm마다 전구
            if dc.lanterns {
                var posts: [SIMD3<Float>] = []
                for k in 0..<12 where posts.count < 3 {
                    let p = around(Float(k) / 12 + 0.04, Float.random(in: 2.2...3.4, using: &g), rec, floorY)
                    guard roundFree(p, 0.4), !spots.contains(where: { simd_distance($0, p) < 2.8 }), posts.allSatisfy({ simd_distance($0, p) > 3 && simd_distance($0, p) < 9 }) else { continue }
                    posts.append(p)
                }
                var wood = Geo(), wire = Geo(), bulbs = Geo()
                for p in posts { wood.trunk(from: p - SIMD3<Float>(0, 0.1, 0), to: p + SIMD3<Float>(0, 2.5, 0), r0: 0.06, r1: 0.05, sides: 8, segs: 1) }
                var bulbAt: [SIMD3<Float>] = []
                for k in 0..<max(0, posts.count - 1) {
                    let a = posts[k] + SIMD3<Float>(0, 2.4, 0), b = posts[k + 1] + SIMD3<Float>(0, 2.4, 0)
                    let span = simd_distance(a, b)
                    let n = max(4, Int(span / 0.45))
                    var prev = a
                    for j in 1...n {
                        let t2 = Float(j) / Float(n)
                        let p = a + (b - a) * t2 - SIMD3<Float>(0, 0.45 * 4 * t2 * (1 - t2), 0)
                        wire.stroke(prev, p, width: 0.008)
                        if j < n { bulbAt.append(p - SIMD3<Float>(0, 0.06, 0)); wire.stroke(p, p - SIMD3<Float>(0, 0.04, 0), width: 0.006) }
                        prev = p
                    }
                }
                for c in bulbAt { bulbs.bulb(at: c, r: 0.035) }
                if let e = wood.entity("lightPosts", lineMode ? Ink.line : Tex.unlit("bark", tint: Worlds.safe(tint * 0.7, min: 0.2))) { layer(e, 5); world.addChild(e) }
                if let e = wire.entity("lightWire", lineMode ? Ink.line : UnlitMaterial(color: Tex.color([0.1, 0.1, 0.1]))) { layer(e, 5); world.addChild(e) }
                let bm = lineMode ? Ink.line : UnlitMaterial(color: Tex.color(lit ? [1, 0.82, 0.52] : [0.86, 0.86, 0.8]))
                if let e = bulbs.entity("lightBulbs", bm) { layer(e, 5); world.addChild(e) }
                if lit && !lineMode { for c in bulbAt { glowSprite(at: c, size: 0.32, color: [1, 0.74, 0.42]) } }
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
            pe.mainEmitter.image = Tex.particle("spark_dot")      // 기본 동그라미(둥근 원반) 대신 부드러운 그림
            pe.emitterShape = .box
            pe.emitterShapeSize = SIMD3<Float>(max(0.5, roomHalf.x * 2 - 0.6), 2.0, max(0.5, roomHalf.y * 2 - 0.6))
            pe.birthLocation = .volume
            pe.speed = 0.04
            pe.speedVariation = 0.03
            pe.mainEmitter.birthRate = min(260, 18 * roomHalf.x * roomHalf.y * 4)
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
            e.position = roomCenter + SIMD3<Float>(0, 1.2, 0)
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
        // 구름 빛깔: 밝기만 하늘·시간에서 가져오고 색은 살짝 푸른 회색 (예전엔 시간 빛깔을 그대로 곱해 밤·흐린 날 먹구름이 갈색 얼룩처럼 보였음)
        let lit0 = Worlds.haze(room.time, weather: room.weather) * 0.4 + tint * 0.6
        let lit = SIMD3<Float>(0.9, 0.93, 1.0) * (lit0.x * 0.3 + lit0.y * 0.59 + lit0.z * 0.11)
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

    /// 날씨 (비·눈·바람·반딧불) — 기준서 4·7.
    /// - 하늘 세계 쪽(같은 세계 무리에선 대표 방만): 집 전체 둘레 6m까지, 천장 위 3m부터 땅까지 한 줄기로 고르게.
    ///   바깥 장소 방 자리도 비우지 않음 — 벽 너머 옆방 자리(가까운 바깥)가 비면 가운데만 빈 것처럼 보였음.
    ///   지붕 있는 방(실내 장소: 카페·집·전시관 — 어느 세계든) 자리만 지붕(그 높이)까지: 포털은 자르지 않아, 그 자리에 내리면
    ///   창·문 너머로 실내에 눈이 내리는 것처럼 보임. 1m 칸으로 나눠 큰 사각형으로 묶음(입자 묶음 수는 몇 개)
    /// - 양: 세계 하나에 떠 있는 입자 수를 정해 두고(눈 5000·비 4000) 부피로 나눈 밀도를 어디서나 똑같이.
    ///   지금 있는 세계만 다 내리고, 이웃 세계는 1/4만
    /// - 방 안(바깥 장소만): 천장에서 바닥까지 같은 밀도의 절반 (하늘 세계 눈이 방 자리에도 내려 벽 앞에서 겹쳐 보이므로),
    ///   머리 둘레 칸만 잠깐 멈춤. 실내 장소는 방 안엔 내리지 않음
    private func addWeather(_ rects: [PRect], _ L: Layout, rec: SpaceRec, floorY: Float, ceilY: Float, sky: Bool) {
        let w = room.weather
        let wet = ["drizzle", "rain", "storm", "snow", "heavysnow"].contains(w)
        let dens = Self.precipDensity(w, L, floorY: floorY, ceilY: ceilY)
        if wet && sky, let wb = L.walkBounds() {
            let lo = wb.0 - SIMD2<Float>(repeating: 6), hi = wb.1 + SIMD2<Float>(repeating: 6)
            let top = ceilY + 3
            let cell: Float = 1
            let nx = max(1, Int(((hi.x - lo.x) / cell).rounded(.up))), nz = max(1, Int(((hi.y - lo.y) / cell).rounded(.up)))
            var roofed = [Bool](repeating: false, count: nx * nz)
            for r in rec.rooms where !Worlds.style(r.place, time: r.time).open {
                for q in L.rects(r.id) {
                    let i0 = max(0, Int(((q.0.x - 0.15 - lo.x) / cell).rounded(.down))), i1 = min(nx - 1, Int(((q.1.x + 0.15 - lo.x) / cell).rounded(.down)))
                    let j0 = max(0, Int(((q.0.y - 0.15 - lo.y) / cell).rounded(.down))), j1 = min(nz - 1, Int(((q.1.y + 0.15 - lo.y) / cell).rounded(.down)))
                    guard i0 <= i1, j0 <= j1 else { continue }
                    for j in j0...j1 { for i in i0...i1 { roofed[j * nx + i] = true } }
                }
            }
            /// 같은 값 칸을 큰 사각형으로 묶음 (평면 좌표)
            func merge(_ want: Bool) -> [PRect] {
                var used = [Bool](repeating: false, count: nx * nz)
                var out: [PRect] = []
                for j in 0..<nz {
                    var i = 0
                    while i < nx {
                        guard roofed[j * nx + i] == want && !used[j * nx + i] else { i += 1; continue }
                        var i1 = i
                        while i1 < nx && roofed[j * nx + i1] == want && !used[j * nx + i1] { i1 += 1 }
                        var j1 = j + 1
                        while j1 < nz {
                            var full = true
                            for k in i..<i1 where roofed[j1 * nx + k] != want || used[j1 * nx + k] { full = false; break }
                            if !full { break }
                            j1 += 1
                        }
                        for jj in j..<j1 { for k in i..<i1 { used[jj * nx + k] = true } }
                        out.append((lo + SIMD2<Float>(Float(i), Float(j)) * cell, lo + SIMD2<Float>(Float(i1), Float(j1)) * cell))
                        i = i1
                    }
                }
                return out
            }
            for (want, bottom) in [(false, floorY), (true, ceilY)] {
                for r in merge(want) {
                    let c = L.flat((r.0 + r.1) / 2)
                    let e = Self.precip(w, size: SIMD3<Float>(r.1.x - r.0.x, 0.05, r.1.y - r.0.y), height: top - bottom, look: look, density: dens)
                    e.position = SIMD3<Float>(c.x, top, c.y)
                    e.orientation = simd_quatf(angle: -angle, axis: [0, 1, 0])
                    layer(e, 20)
                    world.addChild(e)
                    emitters.append(e)
                }
            }
        }
        guard outdoor else { return }
        // 방 안: 5cm 칸 사각형 대신 50cm 칸(벽에서 15cm 안쪽까지 모두 이 방인 칸)을 묶은 큰 사각형 — 방마다 입자 묶음 수가 넓이(m²) 정도로
        for r in coarseRects(L, cell: 0.5, inset: 0.15) {
            let c = L.flat((r.0 + r.1) / 2)
            let sx = r.1.x - r.0.x, sz = r.1.y - r.0.y
            guard sx > 0.2, sz > 0.2 else { continue }
            var list: [Entity] = []
            if wet {
                // 1m 안팎 칸으로 나눠 뿌리고, 머리 근처 칸만 끔 — 눈앞을 스치는 눈송이가 크게 번쩍이며 깜빡이던 것을 없앰
                let lo = r.0
                let nx = max(1, Int((sx / 1.0).rounded())), nz = max(1, Int((sz / 1.0).rounded()))
                let tx = sx / Float(nx), tz = sz / Float(nz)
                for ix in 0..<nx {
                    for iz in 0..<nz {
                        let a = lo + SIMD2<Float>(Float(ix) * tx, Float(iz) * tz)
                        let b = a + SIMD2<Float>(tx, tz)
                        let tc = L.flat((a + b) / 2)
                        let e = Self.precip(w, size: SIMD3<Float>(tx, 0.05, tz), height: room.ceil, look: look, density: dens * 0.5)
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

    /// 이 방 바닥을 cell m 칸으로 나눠, 칸과 그 둘레 inset m 가 모두 이 방 바닥인 칸들을 큰 사각형으로 묶음 (평면 좌표)
    private func coarseRects(_ L: Layout, cell: Float, inset: Float) -> [PRect] {
        var lo = SIMD2<Float>(repeating: .greatestFiniteMagnitude), hi = -lo
        for r in L.rects(room.id) { lo = simd_min(lo, r.0); hi = simd_max(hi, r.1) }
        guard lo.x < hi.x, lo.y < hi.y else { return [] }
        let nx = Int(((hi.x - lo.x) / cell).rounded(.up)), nz = Int(((hi.y - lo.y) / cell).rounded(.up))
        guard nx > 0, nz > 0, nx * nz < 40_000 else { return [] }
        func mine(_ p: SIMD2<Float>) -> Bool { let f = L.flat(p); return L.at(x: f.x, z: f.y).room == room.id }
        var free = [Bool](repeating: false, count: nx * nz)
        for j in 0..<nz {
            for i in 0..<nx {
                let a = lo + SIMD2<Float>(Float(i), Float(j)) * cell
                var ok = true
                var v: Float = -inset
                outer: while v <= cell + inset + 1e-3 {
                    var u: Float = -inset
                    while u <= cell + inset + 1e-3 {
                        if !mine(a + SIMD2<Float>(u, v)) { ok = false; break outer }
                        u += 0.1
                    }
                    v += 0.1
                }
                free[j * nx + i] = ok
            }
        }
        var used = [Bool](repeating: false, count: nx * nz)
        var out: [PRect] = []
        for j in 0..<nz {
            var i = 0
            while i < nx {
                guard free[j * nx + i] && !used[j * nx + i] else { i += 1; continue }
                var i1 = i
                while i1 < nx && free[j * nx + i1] && !used[j * nx + i1] { i1 += 1 }
                var j1 = j + 1
                while j1 < nz {
                    var full = true
                    for k in i..<i1 where !free[j1 * nx + k] || used[j1 * nx + k] { full = false; break }
                    if !full { break }
                    j1 += 1
                }
                for jj in j..<j1 { for k in i..<i1 { used[jj * nx + k] = true } }
                out.append((lo + SIMD2<Float>(Float(i), Float(j)) * cell, lo + SIMD2<Float>(Float(i1), Float(j1)) * cell))
                i = i1
            }
        }
        return out
    }

    /// 방 안 눈·비 칸 (엔티티, 평면 좌표 사각형)
    private var precipTiles: [(Entity, SIMD2<Float>, SIMD2<Float>)] = []
    private var roomOn = false

    /// 머리(평면 좌표) 50cm 안에 걸친 눈·비 칸은 새로 뿌리지 않음 (지금 방만, 매 프레임)
    func avoidHead(_ p: SIMD2<Float>) {
        guard roomOn else { return }
        for (e, a, b) in precipTiles {
            let d = simd_length(simd_max(simd_max(a - p, p - b), SIMD2<Float>(0, 0)))
            let on = d > 0.9                  // 머리 둘레 40cm 안 칸만 내리지 않음 (눈앞 깜빡임 — 예전 80cm는 둘레가 넓게 비어 일부에만 내리는 것처럼 보였음)
            if var pe = e.components[ParticleEmitterComponent.self], pe.isEmitting != on {
                pe.isEmitting = on
                e.components.set(pe)
            }
        }
    }

    /// 입자를 뿜을지. sky: 하늘 세계 쪽(지금 방과 이웃 방 — 문 너머로 이미 내리고 있게), room: 방 안(지금 방만)
    /// full: 하늘 쪽 눈·비를 다 내릴지 (지금 있는 세계) — 아니면 1/4만 (이웃 세계: 열린 문 너머로 보일 만큼)
    private var baseRates: [ObjectIdentifier: Float] = [:]
    private var skyFull: Bool?
    func setActive(sky: Bool, room: Bool, full: Bool = true) {
        roomOn = room
        scenery?.setSound(room)                       // 벽난로 장작 소리
        for (list, on) in [(emitters, sky), (roomEmitters, room)] {
            for e in list {
                if var pe = e.components[ParticleEmitterComponent.self], pe.isEmitting != on {
                    pe.isEmitting = on
                    e.components.set(pe)
                }
                if !on { e.isEnabled = false } else if !e.isEnabled { e.isEnabled = true }
            }
        }
        if sky && skyFull != full {
            skyFull = full
            for e in emitters {
                guard var pe = e.components[ParticleEmitterComponent.self] else { continue }
                let id = ObjectIdentifier(e)
                if baseRates[id] == nil { baseRates[id] = pe.mainEmitter.birthRate }
                pe.mainEmitter.birthRate = (baseRates[id] ?? pe.mainEmitter.birthRate) * (full ? 1 : 0.25)
                e.components.set(pe)
            }
        }
    }

    /// 매 프레임: 구름 흐름, 물결, 번개
    func tick(_ dt: Float, active: Bool) {
        guard active else { return }
        scenery?.tick(dt)
        tickSpeaker(dt)
        tickVillage(dt)
        tickCafe(dt)
        for p in plumes { p.tick(dt) }
        // 구름: 매 화면 앱이 옮기지 않고 20초짜리 곧은 이동(move)을 RealityKit에 맡김 — 앱 갱신이 화면 주사율보다 느리면
        // 하늘에서 움직이는 구름이 띄엄띄엄 옮겨져 흐릿하게(초점이 안 맞는 것처럼) 보였음 (새와 같은 까닭)
        for i in clouds.indices {
            cloudLeft[i] -= dt
            guard cloudLeft[i] <= 0, let par = clouds[i].0.parent else { continue }
            let (e, v) = clouds[i]
            var p = cloudAt[i] ?? e.position
            let off = p - center
            var jump = false
            if abs(off.x) > 180 { p.x = center.x - copysign(170, off.x); jump = true }
            if abs(off.z) > 180 { p.z = center.z - copysign(170, off.z); jump = true }
            if jump || cloudAt[i] == nil { e.position = p }
            let dur: Float = 20
            var tr = e.transform
            tr.translation = p + v * dur
            _ = e.move(to: tr, relativeTo: par, duration: TimeInterval(dur), timingFunction: .linear)
            cloudAt[i] = tr.translation
            cloudLeft[i] = dur
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

    /// 하늘 세계 쪽 것 (같은 세계 무리면 대표 방 것): 밤하늘 별, 바깥 강·폭포 물소리 자리
    var skyStars: SkyStars? { host?.stars ?? stars }
    var streamSpot: SIMD3<Float>? { host?.riverNear ?? riverNear }
    var fallSound: SIMD3<Float>? { host?.fallSpot ?? fallSpot }

    /// 번개: 하늘이 잠깐 밝아짐
    func flash() {
        if let h = host { h.flash(); return }
        guard let s = skyEntity, let f = flashMat else { return }
        s.model?.materials = [f]
        flashLeft = Float.random(in: 0.08...0.18)
    }

    // MARK: 입자
    /// 공기 1m³당 입자 수(밀도 1일 때)·떨어지는 빠르기(m/s)
    static func precipN(_ w: String) -> (Float, Float) {
        switch w {
        case "drizzle": return (7, 3.2)
        case "rain": return (12, 5)
        case "storm": return (20, 7)
        case "heavysnow": return (18, 0.55)
        default: return (12, 0.75)
        }
    }

    /// 세계 하나의 눈·비 밀도: 집 둘레 6m 상자(천장 위 3m~땅) 부피에 떠 있는 입자가 눈 5000·비 4000개가 되게. 많아야 0.8
    static func precipDensity(_ w: String, _ L: Layout, floorY: Float, ceilY: Float) -> Float {
        guard let wb = L.walkBounds() else { return 0.5 }
        let sz = wb.1 - wb.0 + SIMD2<Float>(repeating: 12)
        let vol = sz.x * sz.y * (ceilY + 3 - floorY)
        let budget: Float = (w == "snow" || w == "heavysnow") ? 5000 : 4000
        return min(0.8, budget / max(1, precipN(w).0 * vol))
    }

    /// 비·눈 (위에서 아래로, 바닥 근처에서 사라짐)
    static func precip(_ w: String, size: SIMD3<Float>, height: Float, look: LookMode = .color, density: Float = 1) -> Entity {
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
        // 입자 수 = 공기 1m³ 안에 떠 있는 수(n × density)로 정함 → 내뿜는 수 = n × 넓이 × density × 떨어지는 빠르기.
        // 높이·빠르기와 상관없이 같은 밀도라 하늘에서 땅까지 긴 줄기도 방 안과 같은 촘촘함 (예전 '넓이당 초당 수'는
        // 느린 함박눈·높은 줄기일수록 수십만 개로 불어났음)
        let vol = max(0.05, size.x * size.z) * density
        let (n, speed) = precipN(w)
        // 밀도가 낮을수록 송이를 조금 크게 (보이는 양을 맞춤, 2배까지)
        let grow = min(2, max(1, (0.5 / max(0.05, density)).squareRoot()))
        switch w {
        case "heavysnow": pe.mainEmitter.size = 0.02 * grow
        case "snow": pe.mainEmitter.size = 0.012 * grow
        default: break
        }
        pe.mainEmitter.birthRate = n * vol * speed
        pe.speed = speed
        pe.speedVariation = speed * 0.08
        // 처음 빠르기 그대로 곧게 떨어지게: 기본 눈·비 설정의 끌림(damping)·소용돌이·끌어당김·퍼짐을 모두 0으로 —
        // 수명은 '높이 ÷ 빠르기'로 정하므로, 끌림이 남아 있으면 느려진 입자가 땅에 닿기 전에 위쪽에서 사라져 아래(가운데 높이)가 비었음
        pe.mainEmitter.acceleration = [0, 0, 0]
        pe.mainEmitter.dampingFactor = 0
        pe.mainEmitter.vortexStrength = 0
        pe.mainEmitter.attractionStrength = 0
        pe.mainEmitter.spreadingAngle = 0
        // 일렁임 없애기: 기본 눈·비 설정에 든 흔들림(잡음)·회전·빛 받음·뒤따르는 작은 입자를 모두 끔 —
        // 눈앞 가득한 작은 점들이 제각각 흔들리고 반짝여 아지랑이처럼 어른거리며 어지러웠음. 곧게 떨어지게
        pe.mainEmitter.noiseStrength = 0
        pe.mainEmitter.angularSpeed = 0
        pe.mainEmitter.angularSpeedVariation = 0
        pe.mainEmitter.isLightingEnabled = false
        pe.spawnedEmitter = nil
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
        pe.mainEmitter.image = Tex.particle(["camp", "forest", "valley", "village", "home", "gallery"].contains(place) ? "leaf_bit" : "spark_dot")      // 기본 동그라미 대신
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
        pe.mainEmitter.image = Tex.particle("spark_dot")      // 기본 동그라미(둥근 원반) 대신 부드러운 그림
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
