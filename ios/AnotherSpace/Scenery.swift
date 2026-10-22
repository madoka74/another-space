import Foundation
import UIKit
import RealityKit
import simd

/// 장소마다 자연스럽게 움직이는 것들과 실내 꾸밈.
/// - far(하늘 세계, 벽·창·천장 너머로만 보임): 새·갈매기, 돛단배, 자동차 불빛, 비행기 불빛, 굴뚝·모닥불 연기, 낙엽, 계곡 물안개, 카페 창밖 행인
/// - near(방 안, 실제 공간): 카페 벽 선반·컵·메뉴판·펜던트 조명·김, 통나무집 벽난로, 전시관 먼지 빛
/// 하늘 세계의 물건은 방 안 자리에 있으면 벽 너머로 비쳐 보이므로 집 안(걸을 수 있는 곳)에는 두지 않음.
/// 방 안 꾸밈은 벽에 붙이거나(15cm 안) 머리 위(2m 위)에만 둠 — 걸어 다니는 곳을 막지 않게
@MainActor
final class Scenery {
    let far = Entity()
    let near = Entity()

    private final class Flyer {
        let root = Entity()
        var wings: [Entity] = []
        var ang: Float = 0
        var radius: Float = 20
        var height: Float = 15
        var speed: Float = 6
        var flap: Float = 9
        var phase: Float = 0
        var center = SIMD3<Float>(0, 0, 0)
        var dir: Float = 1
    }
    private var flyers: [Flyer] = []
    private struct Mover { let e: Entity; let a: SIMD3<Float>; let d: SIMD3<Float>; let len: Float; let speed: Float; var s: Float; let bob: Float }
    private var movers: [Mover] = []
    private var boats: [(Entity, SIMD3<Float>, Float, Float, Float)] = []     // 배, 가운데, 각도, 반지름, 각속도
    private var blinkers: [(ModelEntity, Float)] = []                       // 깜빡이는 불빛, 주기
    private var flames: [(Entity, Float)] = []                              // 흔들리는 불빛 (벽난로)
    // 카페: 에스프레소 머신 스팀·잔 소리
    private var cafeSteam: Entity?
    private var cafeSpot: SIMD3<Float>?
    private var nextSteam: Float = 12
    private var steamOff: Float = -1
    private var nextClink: Float = 8
    private var t: Float = 0

    private let look: LookMode
    private let center: SIMD3<Float>
    private let halfSize: SIMD2<Float>
    private let L: Layout
    private let ex: SIMD3<Float>
    private let ez: SIMD3<Float>
    private let sortGroup: ModelSortGroup
    private var blocked: Set<Int64>          // 가구 기둥이 있는 10cm 칸 (벽 꾸밈은 그 앞을 피함)
    /// 벽 꾸밈(벽난로·선반·메뉴판) 앞 칸 — 나중에 이곳에 가구가 생기면 다른 빈 벽으로 옮김
    private(set) var decorCells: Set<Int64> = []
    private let roomRec: RoomRec
    private let segsAll: [WallSeg]
    private let floorY0: Float
    private let ceilY0: Float

    init(room: RoomRec, look: LookMode, tint: SIMD3<Float>, center: SIMD3<Float>, halfSize: SIMD2<Float>, angle: Float,
         floorY: Float, ceilY: Float, segs: [WallSeg], layout: Layout, sortGroup: ModelSortGroup, blocked: Set<Int64> = []) {
        self.blocked = blocked
        self.roomRec = room
        self.segsAll = segs
        self.floorY0 = floorY
        self.ceilY0 = ceilY
        self.look = look
        self.center = center
        self.halfSize = halfSize
        self.L = layout
        self.sortGroup = sortGroup
        ex = SIMD3<Float>(layout.ex.x, 0, layout.ex.y)
        ez = SIMD3<Float>(layout.ez.x, 0, layout.ez.y)
        var g = SeededRNG(seed: UInt64(room.id * 4241 + room.place.count * 17 + 11))
        let night = room.time == "night"
        let wet = ["rain", "storm", "heavysnow"].contains(room.weather)
        let R = simd_length(halfSize)
        switch room.place {
        case "camp":
            if !night && !wet { addBirds(6, R: R, floorY: floorY, color: [0.12, 0.12, 0.14], using: &g) }
            addCampfire(R: R, floorY: floorY, night: night || room.time == "dusk", using: &g)
        case "forest":
            if !night && !wet { addBirds(5, R: R, floorY: floorY, color: [0.1, 0.1, 0.1], using: &g) }
            addLeaves(R: R, floorY: floorY, tint: tint, using: &g)
        case "valley":
            if !night && !wet { addBirds(2, R: R, floorY: floorY, color: [0.16, 0.12, 0.1], big: true, using: &g) }
            addMist(R: R, floorY: floorY, using: &g)
        case "sea":
            if !night && !wet { addBirds(7, R: R, floorY: floorY, color: [0.95, 0.95, 0.95], using: &g) }
            addBoats(R: R, floorY: floorY, night: night, using: &g)
        case "village":
            if !night && !wet { addBirds(6, R: R, floorY: floorY, color: [0.12, 0.12, 0.12], using: &g) }
            addChimneys(R: R, floorY: floorY, using: &g)
        case "city":
            if !night && !wet { addBirds(4, R: R, floorY: floorY, color: [0.35, 0.35, 0.38], using: &g) }
            addCars(R: R, floorY: floorY, night: night || room.time == "dusk", using: &g)
            addPlane(floorY: floorY, using: &g)
        case "cafe":
            addCafe(segs, floorY: floorY, ceilY: ceilY, night: night, using: &g)
            addPassersby(segs, floorY: floorY, using: &g)
        case "gallery":
            if !night && !wet { addBirds(3, R: R, floorY: floorY, color: [0.15, 0.15, 0.15], using: &g) }
            addDust(floorY: floorY)
        default:   // 집 (숲속 통나무집)
            if !night && !wet { addBirds(4, R: R, floorY: floorY, color: [0.1, 0.1, 0.1], using: &g) }
            addFireplace(segs, floorY: floorY, ceilY: ceilY, using: &g)
        }
    }

    /// 벽 꾸밈 앞에 가구가 새로 보이면(탐험하며 알게 된 가구) 가구 없는 다른 벽으로 옮김. 옮겼으면 true
    @discardableResult
    func relocate(blocked nb: Set<Int64>) -> Bool {
        guard !decorCells.isEmpty, !decorCells.isDisjoint(with: nb) else { return false }
        blocked = nb
        for c in Array(near.children) { c.removeFromParent() }
        flames.removeAll()
        decorCells.removeAll()
        var g = SeededRNG(seed: UInt64(roomRec.id * 4241 + 77))
        Tex.with(look) {
            if roomRec.place == "cafe" {
                addCafe(segsAll, floorY: floorY0, ceilY: ceilY0, night: roomRec.time == "night", using: &g)
            } else if roomRec.place == "home" {
                addFireplace(segsAll, floorY: floorY0, ceilY: ceilY0, using: &g)
            }
        }
        return true
    }

    /// 벽 s 의 점 mid(평면 좌표) 앞, 폭 width·깊이 depth 안의 10cm 칸
    private func frontCells(_ s: WallSeg, mid: SIMD2<Float>, width: Float, depth: Float) -> Set<Int64> {
        let dir = (s.b - s.a) / max(0.01, simd_distance(s.a, s.b))
        var out = Set<Int64>()
        var t = -width / 2
        while t <= width / 2 + 1e-3 {
            var o: Float = 0.05
            while o <= depth + 1e-3 { out.insert(RoomWorld.clutterKey(mid + dir * t + s.n * o)); o += 0.1 }
            t += 0.1
        }
        return out
    }

    // MARK: 공통
    /// 표시 방식에 맞는 단색 재질 (선 그림이면 검정)
    private func solid(_ c: SIMD3<Float>) -> UnlitMaterial {
        look == .line ? Ink.line : UnlitMaterial(color: Tex.color(c))
    }
    /// 입자 색 (선 그림이면 짙은 회색)
    private func pcolor(_ c: SIMD3<Float>, _ a: CGFloat = 1) -> UIColor {
        look == .line ? UIColor(white: 0.3, alpha: a) : Tex.color(c, alpha: a)
    }
    /// 집 안(걸을 수 있는 곳)에 걸치지 않는지 (반지름 r)
    private func free(_ p: SIMD3<Float>, _ r: Float) -> Bool {
        for k in 0..<9 {
            let a = Float(k) / 8 * 2 * .pi
            let q = k == 8 ? p : p + SIMD3<Float>(cos(a), 0, sin(a)) * r
            if L.walkable(L.plane(q.x, q.z)) { return false }
        }
        return true
    }
    private func ring(_ d: Float, _ a: Float) -> SIMD3<Float> { center + SIMD3<Float>(cos(a), 0, sin(a)) * d }
    private func emitter(_ pe: ParticleEmitterComponent, at p: SIMD3<Float>, into parent: Entity) {
        let e = Entity()
        e.components.set(pe)
        e.position = p
        e.components.set(ModelSortGroupComponent(group: sortGroup, order: 18))
        parent.addChild(e)
    }

    // MARK: 새
    private func addBirds<G: RandomNumberGenerator>(_ n: Int, R: Float, floorY: Float, color: SIMD3<Float>, big: Bool = false, using g: inout G) {
        let mat = solid(color)
        let wingMat = solid(color * (color.x > 0.8 ? 0.82 : 1))          // 갈매기: 날개 위는 옅은 회색
        let span: Float = big ? 1.8 : 0.6
        // 날개 (머리 = -z, 오른쪽 날개 = +x): 몸 쪽은 넓고 끝으로 갈수록 좁게, 앞 가장자리는 둥글게 뒤로 젖힘. 큰 새는 끝 깃이 손가락처럼 갈라짐
        var wing = Geo()
        let s2 = span / 2
        wing.quad(SIMD3<Float>(0.02 * span, 0, -0.08 * span), SIMD3<Float>(s2 * 0.45, 0.01 * span, -0.07 * span),
                  SIMD3<Float>(s2 * 0.45, 0.01 * span, 0.09 * span), SIMD3<Float>(0.02 * span, 0, 0.11 * span), .zero, .zero, .zero, .zero)
        if big {
            for k in 0..<5 {
                let z0 = -0.07 * span + Float(k) * 0.032 * span
                wing.quad(SIMD3<Float>(s2 * 0.45, 0.01 * span, z0), SIMD3<Float>(s2 * (0.92 + 0.04 * Float(k % 2)), 0.0, z0 + 0.03 * span - 0.025 * span * Float(k) / 4),
                          SIMD3<Float>(s2 * (0.92 + 0.04 * Float(k % 2)), 0.0, z0 + 0.045 * span - 0.025 * span * Float(k) / 4), SIMD3<Float>(s2 * 0.45, 0.01 * span, z0 + 0.032 * span),
                          .zero, .zero, .zero, .zero)
            }
        } else {
            wing.quad(SIMD3<Float>(s2 * 0.45, 0.01 * span, -0.07 * span), SIMD3<Float>(s2, -0.005 * span, 0.0),
                      SIMD3<Float>(s2 * 0.98, -0.005 * span, 0.03 * span), SIMD3<Float>(s2 * 0.45, 0.01 * span, 0.09 * span), .zero, .zero, .zero, .zero)
        }
        guard let wm = wing.mesh("wing") else { return }
        // 몸: 꼬리에서 가슴으로 굵어졌다 머리·부리로 가늘어지는 둥근 몸 + 부채꼴 꼬리깃
        var bodyG = Geo()
        bodyG.trunk(from: SIMD3<Float>(0, 0, 0.16 * span), to: SIMD3<Float>(0, 0.005 * span, -0.05 * span), r0: 0.018 * span, r1: 0.042 * span, sides: 8, segs: 2)
        bodyG.trunk(from: SIMD3<Float>(0, 0.005 * span, -0.05 * span), to: SIMD3<Float>(0, 0.02 * span, -0.15 * span), r0: 0.042 * span, r1: 0.022 * span, sides: 8, segs: 2)
        bodyG.trunk(from: SIMD3<Float>(0, 0.02 * span, -0.15 * span), to: SIMD3<Float>(0, 0.015 * span, -0.2 * span), r0: 0.01 * span, r1: 0.001, sides: 6, segs: 1)
        bodyG.quad(SIMD3<Float>(-0.015 * span, 0, 0.14 * span), SIMD3<Float>(0.015 * span, 0, 0.14 * span), SIMD3<Float>(0.05 * span, 0, 0.26 * span),
                   SIMD3<Float>(-0.05 * span, 0, 0.26 * span), .zero, .zero, .zero, .zero)
        guard let body = bodyG.mesh("birdBody") else { return }
        let flock = ring(R + Float.random(in: 15...40, using: &g), Float.random(in: 0...(2 * .pi), using: &g))
        for i in 0..<n {
            let f = Flyer()
            f.center = big ? center : flock
            f.radius = big ? R + Float.random(in: 30...60, using: &g) : Float.random(in: 8...26, using: &g)
            f.height = floorY + (big ? Float.random(in: 30...45, using: &g) : Float.random(in: 10...28, using: &g))
            f.speed = big ? Float.random(in: 5...7, using: &g) : Float.random(in: 6...10, using: &g)
            f.flap = big ? 2.5 : Float.random(in: 8...12, using: &g)
            f.ang = Float(i) / Float(n) * 2 * .pi + Float.random(in: 0...0.6, using: &g)
            f.phase = Float.random(in: 0...6, using: &g)
            f.dir = big || i % 3 != 0 ? 1 : -1
            f.root.addChild(ModelEntity(mesh: body, materials: [mat]))
            for s: Float in [1, -1] {
                let w = ModelEntity(mesh: wm, materials: [wingMat])
                w.scale = SIMD3<Float>(s, 1, 1)
                f.root.addChild(w)
                f.wings.append(w)
            }
            far.addChild(f.root)
            flyers.append(f)
        }
    }

    // MARK: 바다
    private func addBoats<G: RandomNumberGenerator>(R: Float, floorY: Float, night: Bool, using g: inout G) {
        for i in 0..<4 {
            let L: Float = [Float.random(in: 7...9, using: &g), Float.random(in: 10...13, using: &g), Float.random(in: 14...17, using: &g), Float.random(in: 8...12, using: &g)][i]
            let b = makeYacht(L: L, night: night, variant: i, using: &g)
            let rad = R + Float.random(in: 60...220, using: &g)
            let a = Float.random(in: 0...(2 * .pi), using: &g)
            let w = Float.random(in: 0.6...1.4, using: &g) / rad * (Bool.random(using: &g) ? 1 : -1)
            far.addChild(b)
            boats.append((b, SIMD3<Float>(center.x, floorY - 0.4, center.z), a, rad, w))
        }
    }

    /// 세일링 요트 (길이 L, 뱃머리 = +z): 뾰족한 뱃머리에서 넓어졌다 고물에서 조금 좁아지는 흰 선체(현호가 앞으로 살짝 솟음) +
    /// 물에 닿는 짙은 띠 + 나무 갑판 + 작은 선실(창 띠) + 돛대·붐 + 바람에 부푼 큰 돛(메인)·앞 돛(지브) + 앞뒤 버팀줄.
    /// 밤: 돛대 꼭대기 흰 등, 왼쪽 빨강·오른쪽 초록 항해등, 선실 창 불빛. 선 그림: 흰 면 + 검은 윤곽선
    private func makeYacht<G: RandomNumberGenerator>(L: Float, night: Bool, variant: Int, using g: inout G) -> Entity {
        let root = Entity()
        let line = look == .line
        // 배마다 다르게: 선체 색(흰·남색·짙은 초록·빨강·크림·하늘색), 줄무늬 색, 돛 빛깔(흰·크림·옛 갈색 돛·연회색), 돛대(알루미늄·니스 칠한 나무),
        // 돛 모양(한 돛대 슬루프 / 뒤에 작은 돛대가 하나 더 있는 케치), 폭(날씬한·통통한)
        let hulls: [(SIMD3<Float>, SIMD3<Float>)] = [([0.95, 0.95, 0.93], [0.12, 0.2, 0.42]), ([0.1, 0.16, 0.32], [0.86, 0.78, 0.5]),
                                                     ([0.1, 0.26, 0.2], [0.9, 0.86, 0.72]), ([0.62, 0.12, 0.1], [0.95, 0.95, 0.92]),
                                                     ([0.93, 0.89, 0.8], [0.45, 0.16, 0.12]), ([0.62, 0.78, 0.86], [0.95, 0.95, 0.95])]
        let sails: [SIMD3<Float>] = [[0.97, 0.96, 0.93], [0.95, 0.92, 0.84], [0.72, 0.42, 0.28], [0.86, 0.87, 0.88], [0.97, 0.96, 0.93]]
        let hc = hulls[Int.random(in: 0..<hulls.count, using: &g)]
        let sc = sails[Int.random(in: 0..<sails.count, using: &g)]
        let woodMast = Float.random(in: 0...1, using: &g) < 0.3
        let ketch = L > 11 && Float.random(in: 0...1, using: &g) < 0.5
        let B = L * Float.random(in: 0.15...0.19, using: &g)       // 반폭
        let hullM = line ? Ink.paper(0) : UnlitMaterial(color: Tex.color(hc.0))
        let stripeM = line ? Ink.line : UnlitMaterial(color: Tex.color(hc.1))
        let deckM = line ? Ink.paper(1) : UnlitMaterial(color: Tex.color([0.6, 0.46, 0.3]))
        let sailM = line ? Ink.paper(0) : UnlitMaterial(color: Tex.color(sc))
        let seamM = line ? Ink.line : UnlitMaterial(color: Tex.color(sc * 0.82))
        let rigM = line ? Ink.line : UnlitMaterial(color: Tex.color(woodMast ? [0.5, 0.33, 0.18] : [0.72, 0.74, 0.77]))
        let wireM = line ? Ink.line : UnlitMaterial(color: Tex.color([0.32, 0.33, 0.35]))
        let winM = line ? Ink.line : UnlitMaterial(color: night ? Tex.color([1, 0.82, 0.5]) : Tex.color([0.12, 0.15, 0.2]))
        let canvasM = line ? Ink.paper(1) : UnlitMaterial(color: Tex.color(hc.1 * 0.8 + SIMD3<Float>(repeating: 0.05)))
        // 선체: 고물(-L/2) → 뱃머리(+L/2) 단면들
        let n = 12
        func half(_ t: Float) -> Float { t < 0.6 ? B * (0.82 + 0.18 * sin(t / 0.6 * .pi / 2)) : B * cos((t - 0.6) / 0.4 * .pi / 2) }
        func sheer(_ t: Float) -> Float { L * (0.075 + 0.04 * t * t) }
        func zAt(_ t: Float) -> Float { -L / 2 + L * t }
        var hull = Geo(), deck = Geo(), stripe = Geo(), lines = Geo()
        for i in 0..<n {
            let t0 = Float(i) / Float(n), t1 = Float(i + 1) / Float(n)
            for side: Float in [-1, 1] {
                let a0 = SIMD3<Float>(side * half(t0), sheer(t0), zAt(t0)), a1 = SIMD3<Float>(side * half(t1), sheer(t1), zAt(t1))
                let c0 = SIMD3<Float>(side * half(t0) * 0.75, -L * 0.01, zAt(t0)), c1 = SIMD3<Float>(side * half(t1) * 0.75, -L * 0.01, zAt(t1))
                let k0 = SIMD3<Float>(0, -L * 0.05, zAt(t0)), k1 = SIMD3<Float>(0, -L * 0.05, zAt(t1))
                hull.quad(a0, a1, c1, c0, .zero, .zero, .zero, .zero)
                hull.quad(c0, c1, k1, k0, .zero, .zero, .zero, .zero)
                // 물에 닿는 짙은 띠 (옆면 아래쪽, 살짝 바깥)
                let s0 = c0 + (a0 - c0) * 0.18 + SIMD3<Float>(side * 0.01, 0, 0), s1 = c1 + (a1 - c1) * 0.18 + SIMD3<Float>(side * 0.01, 0, 0)
                stripe.quad(c0 + SIMD3<Float>(side * 0.01, 0, 0), c1 + SIMD3<Float>(side * 0.01, 0, 0), s1, s0, .zero, .zero, .zero, .zero)
                if line { lines.stroke(a0, a1, width: L * 0.006); lines.stroke(c0, c1, width: L * 0.004) }
            }
            let l0 = SIMD3<Float>(-half(t0), sheer(t0) - L * 0.004, zAt(t0)), r0 = SIMD3<Float>(half(t0), sheer(t0) - L * 0.004, zAt(t0))
            let l1 = SIMD3<Float>(-half(t1), sheer(t1) - L * 0.004, zAt(t1)), r1 = SIMD3<Float>(half(t1), sheer(t1) - L * 0.004, zAt(t1))
            deck.quad(l0, r0, r1, l1, .zero, .zero, .zero, .zero)
        }
        // 고물 판 (뒤를 막음)
        let tl = SIMD3<Float>(-half(0), sheer(0), zAt(0)), tr = SIMD3<Float>(half(0), sheer(0), zAt(0))
        hull.quad(tl, tr, SIMD3<Float>(half(0) * 0.75, -L * 0.01, zAt(0)), SIMD3<Float>(-half(0) * 0.75, -L * 0.01, zAt(0)), .zero, .zero, .zero, .zero)
        if line { lines.stroke(tl, tr, width: L * 0.006) }
        if let e = hull.entity("yachtHull", hullM) { root.addChild(e) }
        if let e = stripe.entity("yachtStripe", stripeM) { root.addChild(e) }
        if let e = deck.entity("yachtDeck", deckM) { root.addChild(e) }
        // 선실: 갑판 가운데 뒤쪽, 앞이 비스듬한 낮은 집 + 창 띠
        let cab = Entity()
        let cw = B * 1.1, ch = L * 0.055, cl = L * 0.3
        let cabin = ModelEntity(mesh: .generateBox(width: cw, height: ch, depth: cl, cornerRadius: ch * 0.3), materials: [hullM])
        cab.addChild(cabin)
        let win = ModelEntity(mesh: .generateBox(width: cw * 1.01, height: ch * 0.28, depth: cl * 0.7), materials: [winM])
        win.position = [0, ch * 0.08, 0]
        cab.addChild(win)
        cab.position = [0, sheer(0.35) + ch / 2, -L * 0.08]
        root.addChild(cab)
        // 선실 앞 바람막이 천(도저) + 선체 옆 둥근 창 + 갑판 둘레 난간 줄
        let dodger = ModelEntity(mesh: .generateBox(width: cw * 0.95, height: ch * 0.9, depth: cl * 0.22, cornerRadius: ch * 0.4), materials: [canvasM])
        dodger.position = [0, sheer(0.3) + ch * 1.1, -L * 0.08 - cl * 0.55]
        root.addChild(dodger)
        var dots = Geo(), rails = Geo()
        for side: Float in [-1, 1] {
            for k in 0..<3 {
                let t = 0.36 + Float(k) * 0.07
                dots.bulb(at: SIMD3<Float>(side * half(t) * 1.002, sheer(t) * 0.55, zAt(t)), r: L * 0.008)
            }
            var prev: SIMD3<Float>? = nil
            for k in 0...8 {
                let t = 0.08 + Float(k) / 8 * 0.8
                let p = SIMD3<Float>(side * half(t) * 0.96, sheer(t) + L * 0.045, zAt(t))
                if let q = prev { rails.stroke(q, p, width: L * 0.0015) }
                rails.stroke(p - SIMD3<Float>(0, L * 0.045, 0), p, width: L * 0.002)          // 난간 기둥
                prev = p
            }
        }
        if let e = dots.entity("yachtPorts", winM) { root.addChild(e) }
        if let e = rails.entity("yachtRails", wireM) { root.addChild(e) }
        // 돛대·붐
        let mastH = L * 1.25
        let mz = L * 0.08
        let deckY = sheer(0.58)
        let mast = ModelEntity(mesh: .generateCylinder(height: mastH, radius: L * 0.007), materials: [rigM])
        mast.position = [0, deckY + mastH / 2, mz]
        root.addChild(mast)
        let boomY = deckY + L * 0.13, boomL = L * 0.42
        let tack = Float.random(in: -0.35...0.35, using: &g)                // 바람 받는 쪽으로 돌린 붐
        let boomEnd = SIMD3<Float>(sin(tack) * boomL, boomY, mz - cos(tack) * boomL)
        var rig = Geo()
        rig.stroke(SIMD3<Float>(0, boomY, mz), boomEnd, width: L * 0.012)
        // 버팀줄: 뱃머리 → 돛대 꼭대기 → 고물
        let headT = SIMD3<Float>(0, deckY + mastH * 0.98, mz), bow = SIMD3<Float>(0, sheer(1), L / 2)
        var wires = Geo()
        wires.stroke(bow, headT, width: L * 0.003)
        wires.stroke(SIMD3<Float>(0, sheer(0), -L / 2), headT, width: L * 0.003)
        for side: Float in [-1, 1] { wires.stroke(SIMD3<Float>(side * half(0.58), deckY, mz), headT, width: L * 0.002) }   // 옆 버팀줄
        if let e = rig.entity("yachtRig", rigM) { root.addChild(e) }
        if let e = wires.entity("yachtWires", wireM) { root.addChild(e) }
        // 돛: 바람에 부푼 면 (가운데가 바깥으로 불룩) — 메인(돛대·붐 사이 세모), 지브(앞 버팀줄 쪽 세모)
        func sail(_ a: SIMD3<Float>, _ top: SIMD3<Float>, _ clew: SIMD3<Float>, belly: SIMD3<Float>) -> Geo {
            var s2 = Geo()
            let rows = 6
            for r in 0..<rows {
                let v0 = Float(r) / Float(rows), v1 = Float(r + 1) / Float(rows)
                // 아래 변(a→clew)에서 꼭대기로 좁아짐
                let l0 = a + (top - a) * v0, l1 = a + (top - a) * v1
                let e0 = clew + (top - clew) * v0, e1 = clew + (top - clew) * v1
                let m0 = (l0 + e0) / 2 + belly * (1 - v0) * 0.9, m1 = (l1 + e1) / 2 + belly * (1 - v1) * 0.9
                s2.quad(l0, m0, m1, l1, .zero, .zero, .zero, .zero)
                s2.quad(m0, e0, e1, m1, .zero, .zero, .zero, .zero)
            }
            return s2
        }
        let side = SIMD3<Float>(cos(tack), 0, sin(tack)) * (tack >= 0 ? -1 : 1)
        let main = sail(SIMD3<Float>(0, boomY + 0.05, mz), SIMD3<Float>(0, deckY + mastH * 0.95, mz - L * 0.02), boomEnd + SIMD3<Float>(0, 0.05, 0),
                        belly: side * L * 0.06)
        let jib = sail(bow + SIMD3<Float>(0, L * 0.02, -L * 0.03), headT - SIMD3<Float>(0, mastH * 0.18, -L * 0.01),
                       SIMD3<Float>(side.x * B * 0.9, deckY + L * 0.06, mz - L * 0.12), belly: side * L * 0.05)
        if let e = main.entity("yachtMain", sailM) { root.addChild(e) }
        if let e = jib.entity("yachtJib", sailM) { root.addChild(e) }
        // 돛 이음매 (가로 천 조각 선) — 실제 돛처럼
        var seams = Geo()
        let mainTop = SIMD3<Float>(0, deckY + mastH * 0.95, mz - L * 0.02), tackP = SIMD3<Float>(0, boomY + 0.05, mz)
        for k in 1..<6 {
            let v = Float(k) / 6
            let a2 = tackP + (mainTop - tackP) * v, b2 = (boomEnd + SIMD3<Float>(0, 0.05, 0)) + (mainTop - boomEnd) * v
            let m2 = (a2 + b2) / 2 + side * L * 0.06 * (1 - v) * 0.9
            seams.stroke(a2 + side * 0.01, m2 + side * 0.012, width: L * 0.002)
            seams.stroke(m2 + side * 0.012, b2 + side * 0.01, width: L * 0.002)
        }
        if let e = seams.entity("yachtSeams", seamM) { root.addChild(e) }
        // 케치: 고물 쪽에 작은 돛대와 돛 하나 더
        if ketch {
            let mzz = -L * 0.32, mh = mastH * 0.55
            let mm = ModelEntity(mesh: .generateCylinder(height: mh, radius: L * 0.005), materials: [rigM])
            mm.position = [0, sheer(0.18) + mh / 2, mzz]
            root.addChild(mm)
            let mb = SIMD3<Float>(sin(tack) * L * 0.2, sheer(0.18) + L * 0.1, mzz - cos(tack) * L * 0.2)
            let miz = sail(SIMD3<Float>(0, sheer(0.18) + L * 0.1, mzz), SIMD3<Float>(0, sheer(0.18) + mh * 0.95, mzz), mb, belly: side * L * 0.035)
            if let e = miz.entity("yachtMizzen", sailM) { root.addChild(e) }
            var r2 = Geo()
            r2.stroke(SIMD3<Float>(0, sheer(0.18) + L * 0.1, mzz), mb, width: L * 0.008)
            if let e = r2.entity("yachtMizBoom", rigM) { root.addChild(e) }
        }
        if line {
            let mt = SIMD3<Float>(0, deckY + mastH * 0.95, mz - L * 0.02)
            for (p, q) in [(SIMD3<Float>(0, boomY + 0.05, mz), mt), (mt, boomEnd), (bow, headT - SIMD3<Float>(0, mastH * 0.18, -L * 0.01))] {
                lines.stroke(p, q, width: L * 0.005)
            }
            if let e = lines.entity("yachtLines", Ink.line) { root.addChild(e) }
        }
        if night && !line {
            let top = ModelEntity(mesh: .generateSphere(radius: L * 0.018), materials: [UnlitMaterial(color: Tex.color([1, 0.97, 0.9]))])
            top.position = headT + SIMD3<Float>(0, L * 0.02, 0)
            root.addChild(top)
            for (x, c) in [(Float(-1), SIMD3<Float>(1, 0.15, 0.1)), (1, SIMD3<Float>(0.2, 1, 0.35))] {
                let l = ModelEntity(mesh: .generateSphere(radius: L * 0.014), materials: [UnlitMaterial(color: Tex.color(c))])
                l.position = [x * half(0.8), sheer(0.8) + L * 0.01, zAt(0.8)]
                root.addChild(l)
            }
            blinkers.append((top, 0))
        }
        return root
    }

    // MARK: 도시
    private func addCars<G: RandomNumberGenerator>(R: Float, floorY: Float, night: Bool, using g: inout G) {
        let y = floorY - 30
        let colors: [SIMD3<Float>] = [[0.72, 0.1, 0.1], [0.92, 0.92, 0.9], [0.12, 0.18, 0.34], [0.14, 0.14, 0.15], [0.62, 0.64, 0.66],
                                      [0.24, 0.34, 0.28], [0.95, 0.76, 0.12], [0.48, 0.5, 0.56]]
        for k in 0..<8 {
            let along = k % 2 == 0 ? ex : ez
            let side = k % 2 == 0 ? ez : ex
            let off = Float.random(in: 18...140, using: &g) * (Bool.random(using: &g) ? 1 : -1)
            let len: Float = 360
            let a = center + side * off - along * (len / 2) + SIMD3<Float>(0, y - center.y, 0)
            for c in 0..<4 {
                // 승용차·SUV·택시(노랑)·버스(가끔): 차체 + 유리창 둘레 + 바퀴 넷 + 앞 등·뒤 등 (밤엔 불빛이 또렷)
                let r = Float.random(in: 0...1, using: &g)
                let kind = r < 0.5 ? 0 : (r < 0.8 ? 1 : (r < 0.93 ? 2 : 3))
                let col = kind == 2 ? SIMD3<Float>(0.96, 0.78, 0.12) : (kind == 3 ? SIMD3<Float>(0.2, 0.42, 0.7) : colors[Int.random(in: 0..<colors.count, using: &g)])
                let car = makeCar(kind: kind, color: col, night: night)
                let dir = (k / 2) % 2 == 0 ? along : -along
                let lane: Float = dir == along ? 1.8 : -1.8
                let start = (dir == along ? a : a + along * len) + side * lane
                car.orientation = simd_quatf(angle: atan2(dir.x, dir.z), axis: [0, 1, 0])
                far.addChild(car)
                movers.append(Mover(e: car, a: start, d: dir, len: len, speed: kind == 3 ? 8 : Float.random(in: 9...16, using: &g),
                                    s: Float(c) * len / 4 + Float.random(in: 0...20, using: &g), bob: 0))
            }
        }
    }

    /// 자동차 한 대 (앞 = +z). kind 0 승용차 1 SUV 2 택시 3 버스
    private func makeCar(kind: Int, color: SIMD3<Float>, night: Bool) -> Entity {
        let car = Entity()
        let line = look == .line
        let specs: [(Float, Float, Float, Float)] = [(4.5, 1.8, 0.75, 0.62), (4.7, 1.9, 0.95, 0.75), (4.6, 1.8, 0.75, 0.6), (11, 2.5, 2.2, 0.75)]
        let (L, W, H, cab) = specs[kind]
        let dim: Float = night ? 0.35 : 1
        let bodyM = line ? Ink.paper(0) : UnlitMaterial(color: Tex.color(color * dim))
        let glassM = line ? Ink.line : UnlitMaterial(color: Tex.color(night ? [0.08, 0.09, 0.12] : [0.24, 0.3, 0.38]))
        let tireM = line ? Ink.line : UnlitMaterial(color: Tex.color([0.06, 0.06, 0.06]))
        let body = ModelEntity(mesh: .generateBox(width: W, height: H, depth: L, cornerRadius: min(0.3, H * 0.3)), materials: [bodyM])
        body.position = [0, 0.35 + H / 2, 0]
        car.addChild(body)
        if kind == 3 {
            // 버스: 옆 창 띠
            let win = ModelEntity(mesh: .generateBox(width: W * 1.01, height: H * 0.38, depth: L * 0.86), materials: [glassM])
            win.position = [0, 0.35 + H * 0.66, -0.2]
            car.addChild(win)
        } else {
            // 지붕(유리창 둘레): 앞뒤가 비스듬한 작은 상자 + 유리 띠
            let cl = L * 0.5
            let roof = ModelEntity(mesh: .generateBox(width: W * 0.86, height: cab * 0.5, depth: cl * 0.7, cornerRadius: 0.12), materials: [bodyM])
            roof.position = [0, 0.35 + H + cab * 0.75, -L * 0.06]
            car.addChild(roof)
            let gl = ModelEntity(mesh: .generateBox(width: W * 0.88, height: cab * 0.55, depth: cl, cornerRadius: 0.15), materials: [glassM])
            gl.position = [0, 0.35 + H + cab * 0.28, -L * 0.06]
            car.addChild(gl)
            if kind == 2 {
                let sign = ModelEntity(mesh: .generateBox(width: 0.5, height: 0.16, depth: 0.2), materials: [line ? Ink.paper(0) : UnlitMaterial(color: Tex.color(night ? [1, 0.9, 0.5] : [0.95, 0.95, 0.9]))])
                sign.position = [0, 0.35 + H + cab + 0.08, -L * 0.06]
                car.addChild(sign)
            }
        }
        for zx in [(L * 0.32, Float(1)), (L * 0.32, -1), (-L * 0.32, 1), (-L * 0.32, -1)] {
            let wh = ModelEntity(mesh: .generateCylinder(height: 0.22, radius: kind == 3 ? 0.5 : 0.34), materials: [tireM])
            wh.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
            wh.position = [zx.1 * (W / 2 - 0.08), kind == 3 ? 0.5 : 0.34, zx.0]
            car.addChild(wh)
        }
        let headM = line ? Ink.line : UnlitMaterial(color: Tex.color(night ? [1, 0.95, 0.8] : [0.9, 0.9, 0.86]))
        let tailM = line ? Ink.line : UnlitMaterial(color: Tex.color(night ? [1, 0.12, 0.08] : [0.6, 0.1, 0.08]))
        for x: Float in [-1, 1] {
            let h = ModelEntity(mesh: .generateBox(width: 0.32, height: 0.14, depth: 0.06, cornerRadius: 0.04), materials: [headM])
            h.position = [x * (W / 2 - 0.3), 0.35 + H * 0.65, L / 2 + 0.01]
            car.addChild(h)
            let tl = ModelEntity(mesh: .generateBox(width: 0.3, height: 0.12, depth: 0.06, cornerRadius: 0.03), materials: [tailM])
            tl.position = [x * (W / 2 - 0.3), 0.35 + H * 0.7, -L / 2 - 0.01]
            car.addChild(tl)
            if night && !line {
                // 밤: 앞 등 불빛 번짐
                let gl = ModelEntity(mesh: .generateSphere(radius: 0.3), materials: [UnlitMaterial(color: Tex.color([1, 0.95, 0.82]))])
                gl.scale = [1, 0.6, 0.4]
                gl.position = [x * (W / 2 - 0.3), 0.35 + H * 0.65, L / 2 + 0.08]
                car.addChild(gl)
            }
        }
        return car
    }

    /// 여객기 (앞 = +z): 둥근 몸통 + 뒤로 젖힌 날개·엔진 둘 + 꼬리 날개. 날개 끝 빨강(왼)·초록(오른) 등, 깜빡이는 흰 섬광등
    private func addPlane<G: RandomNumberGenerator>(floorY: Float, using g: inout G) {
        let p = Entity()
        let line = look == .line
        let skin = line ? Ink.paper(0) : solid([0.9, 0.91, 0.93])
        let dark = line ? Ink.line : solid([0.3, 0.32, 0.36])
        var body = Geo(), wings = Geo(), lines = Geo()
        body.trunk(from: SIMD3<Float>(0, 0, -18), to: SIMD3<Float>(0, 0.3, 14), r0: 0.9, r1: 2.0, sides: 12, segs: 2)      // 꼬리 쪽은 가늘게
        body.trunk(from: SIMD3<Float>(0, 0.3, 14), to: SIMD3<Float>(0, 0.1, 19), r0: 2.0, r1: 0.4, sides: 12, segs: 3)    // 둥근 기수
        for sx: Float in [-1, 1] {
            // 주날개: 뿌리 넓고 끝 좁게, 뒤로 젖힘
            wings.quad(SIMD3<Float>(sx * 1.6, -0.6, 4), SIMD3<Float>(sx * 17, 0.6, -6), SIMD3<Float>(sx * 17, 0.6, -8), SIMD3<Float>(sx * 1.6, -0.6, -2.5), .zero, .zero, .zero, .zero)
            // 꼬리 수평 날개
            wings.quad(SIMD3<Float>(sx * 0.6, 0.6, -13), SIMD3<Float>(sx * 6, 0.9, -17.5), SIMD3<Float>(sx * 6, 0.9, -18.8), SIMD3<Float>(sx * 0.6, 0.6, -17.5), .zero, .zero, .zero, .zero)
            body.trunk(from: SIMD3<Float>(sx * 6, -1.6, 4.2), to: SIMD3<Float>(sx * 6, -1.6, 0.4), r0: 1.0, r1: 0.85, sides: 10, segs: 1)   // 엔진
            if line {
                lines.stroke(SIMD3<Float>(sx * 1.6, -0.6, 4), SIMD3<Float>(sx * 17, 0.6, -6), width: 0.25)
                lines.stroke(SIMD3<Float>(sx * 17, 0.6, -6), SIMD3<Float>(sx * 17, 0.6, -8), width: 0.25)
                lines.stroke(SIMD3<Float>(sx * 17, 0.6, -8), SIMD3<Float>(sx * 1.6, -0.6, -2.5), width: 0.25)
            }
        }
        wings.quad(SIMD3<Float>(0, 1.5, -12.5), SIMD3<Float>(0, 7.5, -17.5), SIMD3<Float>(0, 7.5, -19.3), SIMD3<Float>(0, 1.5, -18), .zero, .zero, .zero, .zero)    // 수직 꼬리
        if let e = body.entity("planeBody", skin) { p.addChild(e) }
        if let e = wings.entity("planeWings", line ? Ink.paper(0) : solid([0.82, 0.84, 0.87])) { p.addChild(e) }
        if line, let e = lines.entity("planeLines", Ink.line) { p.addChild(e) }
        let win = ModelEntity(mesh: .generateBox(width: 4.05, height: 0.3, depth: 22), materials: [dark])
        win.position = [0, 0.6, -1]
        p.addChild(win)
        let red = ModelEntity(mesh: .generateSphere(radius: 0.5), materials: [solid([1, 0.2, 0.15])])
        let green = ModelEntity(mesh: .generateSphere(radius: 0.5), materials: [solid([0.2, 1, 0.35])])
        let white = ModelEntity(mesh: .generateSphere(radius: 0.6), materials: [solid([1, 1, 1])])
        red.position = [-17, 0.6, -7]; green.position = [17, 0.6, -7]; white.position = [0, 7.6, -18.8]
        p.addChild(red); p.addChild(green); p.addChild(white)
        blinkers.append((white, 1.3))
        let a = Float.random(in: 0...(2 * .pi), using: &g)
        let dir = SIMD3<Float>(cos(a), 0, sin(a))
        let len: Float = 1400
        let start = center - dir * (len / 2) + SIMD3<Float>(0, floorY - center.y + 160, 0) + SIMD3<Float>(-dir.z, 0, dir.x) * 120
        p.orientation = simd_quatf(angle: atan2(dir.x, dir.z), axis: [0, 1, 0])
        far.addChild(p)
        movers.append(Mover(e: p, a: start, d: dir, len: len, speed: 45, s: Float.random(in: 0...len, using: &g), bob: 0))
    }

    // MARK: 연기·불·낙엽·안개
    private func smoke(size: Float, rate: Float, dark: Float) -> ParticleEmitterComponent {
        var pe = ParticleEmitterComponent()
        pe.mainEmitter.image = Tex.particle("smoke_puff")      // 기본 동그라미(둥근 원반) 대신 부드러운 그림
        pe.emitterShape = .sphere
        pe.emitterShapeSize = SIMD3<Float>(repeating: size * 0.3)
        pe.birthDirection = .world
        pe.emissionDirection = [0.15, 1, 0.05]
        pe.speed = 0.7
        pe.speedVariation = 0.25
        pe.mainEmitter.birthRate = rate
        pe.mainEmitter.lifeSpan = 9
        pe.mainEmitter.size = size
        pe.mainEmitter.sizeMultiplierAtEndOfLifespan = 3.5
        pe.mainEmitter.noiseStrength = 0.15
        pe.mainEmitter.noiseScale = 2
        pe.mainEmitter.color = .constant(.single(pcolor(SIMD3<Float>(repeating: dark), 0.35)))
        pe.mainEmitter.opacityCurve = .gradualFadeInOut
        return pe
    }

    private func addChimneys<G: RandomNumberGenerator>(R: Float, floorY: Float, using g: inout G) {
        for _ in 0..<3 {
            for _ in 0..<6 {
                let p = ring(R + Float.random(in: 35...90, using: &g), Float.random(in: 0...(2 * .pi), using: &g))
                if free(p, 4) { emitter(smoke(size: 1.2, rate: 2.5, dark: 0.82), at: p + SIMD3<Float>(0, floorY - p.y + 6, 0), into: far); break }
            }
        }
    }

    private func addCampfire<G: RandomNumberGenerator>(R: Float, floorY: Float, night: Bool, using g: inout G) {
        for _ in 0..<8 {
            let p = ring(R + Float.random(in: 5...10, using: &g), Float.random(in: 0...(2 * .pi), using: &g))
            guard free(p, 1.5) else { continue }
            let base = SIMD3<Float>(p.x, floorY, p.z)
            var fire = ParticleEmitterComponent()
            fire.mainEmitter.image = Tex.particle("smoke_puff")      // 기본 동그라미(둥근 원반) 대신 부드러운 그림
            fire.emitterShape = .sphere
            fire.emitterShapeSize = [0.35, 0.1, 0.35]
            fire.birthDirection = .world
            fire.emissionDirection = [0, 1, 0]
            fire.speed = 0.6
            fire.speedVariation = 0.3
            fire.mainEmitter.birthRate = 70
            fire.mainEmitter.lifeSpan = 0.9
            fire.mainEmitter.size = 0.16
            fire.mainEmitter.sizeMultiplierAtEndOfLifespan = 0.2
            fire.mainEmitter.color = .evolving(start: .single(pcolor([1, 0.8, 0.35])), end: .single(pcolor([0.9, 0.25, 0.05])))
            fire.mainEmitter.blendMode = look == .line ? .alpha : .additive
            fire.mainEmitter.opacityCurve = .quickFadeInOut
            emitter(fire, at: base + SIMD3<Float>(0, 0.15, 0), into: far)
            emitter(smoke(size: 0.4, rate: 3, dark: 0.55), at: base + SIMD3<Float>(0, 1.0, 0), into: far)
            // 둘레 돌
            var stones = Geo()
            var rg = SeededRNG(seed: 99)
            for k in 0..<9 {
                let a = Float(k) / 9 * 2 * .pi
                stones.rock(at: base + SIMD3<Float>(cos(a) * 0.55, 0, sin(a) * 0.55), size: 0.13, using: &rg)
            }
            if let e = stones.entity("stones", solid([0.42, 0.4, 0.38])) { far.addChild(e) }
            return
        }
    }

    private func addLeaves<G: RandomNumberGenerator>(R: Float, floorY: Float, tint: SIMD3<Float>, using g: inout G) {
        var placed = 0
        for _ in 0..<20 where placed < 5 {
            let p = ring(R + Float.random(in: 4...12, using: &g), Float.random(in: 0...(2 * .pi), using: &g))
            guard free(p, 3.2) else { continue }
            var pe = ParticleEmitterComponent()
            pe.mainEmitter.image = Tex.particle("leaf_bit")      // 기본 동그라미(둥근 원반) 대신 부드러운 그림
            pe.emitterShape = .box
            pe.emitterShapeSize = [5, 0.5, 5]
            pe.birthLocation = .volume
            pe.birthDirection = .world
            pe.emissionDirection = [0.3, -1, 0.1]
            pe.speed = 0.5
            pe.speedVariation = 0.2
            pe.mainEmitter.birthRate = 4
            pe.mainEmitter.lifeSpan = 14
            pe.mainEmitter.size = 0.05
            pe.mainEmitter.sizeVariation = 0.015
            pe.mainEmitter.angularSpeed = 2
            pe.mainEmitter.angularSpeedVariation = 1.5
            pe.mainEmitter.noiseStrength = 0.4
            pe.mainEmitter.noiseScale = 1.5
            pe.mainEmitter.color = .constant(.random(a: pcolor(SIMD3<Float>(0.72, 0.5, 0.18) * tint), b: pcolor(SIMD3<Float>(0.5, 0.6, 0.2) * tint)))
            pe.mainEmitter.opacityCurve = .gradualFadeInOut
            emitter(pe, at: SIMD3<Float>(p.x, floorY + 8, p.z), into: far)
            placed += 1
        }
    }

    private func addMist<G: RandomNumberGenerator>(R: Float, floorY: Float, using g: inout G) {
        for _ in 0..<4 {
            let p = ring(R + Float.random(in: 25...70, using: &g), Float.random(in: 0...(2 * .pi), using: &g))
            guard free(p, 12) else { continue }
            var pe = ParticleEmitterComponent()
            pe.mainEmitter.image = Tex.particle("smoke_puff")      // 기본 동그라미(둥근 원반) 대신 부드러운 그림
            pe.emitterShape = .box
            pe.emitterShapeSize = [24, 2, 24]
            pe.birthLocation = .volume
            pe.speed = 0.25
            pe.speedVariation = 0.15
            pe.mainEmitter.birthRate = 3
            pe.mainEmitter.lifeSpan = 16
            pe.mainEmitter.size = 5
            pe.mainEmitter.sizeMultiplierAtEndOfLifespan = 1.6
            // 선 그림: 흰 종이 위 옅은 회색 안개 (빛을 더하는 방식이면 흰 바탕에서 안 보임)
            pe.mainEmitter.color = .constant(.single(look == .line ? UIColor(white: 0.55, alpha: 0.1) : pcolor([0.95, 0.96, 0.98], 0.18)))
            if look == .line { pe.mainEmitter.blendMode = .alpha }
            pe.mainEmitter.opacityCurve = .gradualFadeInOut
            emitter(pe, at: SIMD3<Float>(p.x, floorY + 1.5, p.z), into: far)
        }
    }

    // MARK: 카페
    /// 창이 아닌 벽: 선반(컵·병·유리병)과 메뉴판, 천장엔 짧은 펜던트 조명, 컵 하나엔 김
    private func addCafe<G: RandomNumberGenerator>(_ segs: [WallSeg], floorY: Float, ceilY: Float, night: Bool, using g: inout G) {
        let top = ceilY - floorY
        var doorEnds: [SIMD2<Float>] = []
        for ds in L.doors {
            for r in [ds.roomA, ds.roomB] where segs.first?.room == r {
                let (a, b, _) = ds.edge(for: r)
                doorEnds += [a, b]
            }
        }
        // 쓸 벽: 창이 아니고 1.3m 넘는 벽, 긴 것부터
        var walls = segs.filter { !$0.window && simd_distance($0.a, $0.b) > 1.3 }.sorted { simd_distance($0.a, $0.b) > simd_distance($1.a, $1.b) }
        func p3(_ p: SIMD2<Float>, _ y: Float) -> SIMD3<Float> { let f = L.flat(p); return SIMD3<Float>(f.x, floorY + y, f.y) }
        func span(_ s: WallSeg) -> (SIMD2<Float>, SIMD2<Float>, SIMD2<Float>)? {
            // 문 끝에서 40cm 떨어지고, 벽 앞 60cm 안에 가구가 없는 가장 긴 구간
            let len = simd_distance(s.a, s.b), dir = (s.b - s.a) / len
            guard let bb = clearRun(s, doorEnds: doorEnds, depth: 0.6, minLen: 0.9) else { return nil }
            return (s.a + dir * bb.0, s.a + dir * bb.1, dir)
        }
        let wood = look == .line ? Ink.paper(0) : Tex.unlit("planks", tint: [0.9, 0.82, 0.74], folder: "tex", sampler: Tex.tiling)
        var lines = Geo()
        func paper(_ c: SIMD3<Float>) -> UnlitMaterial { look == .line ? Ink.paper(0) : UnlitMaterial(color: Tex.color(c)) }
        // 벽 아래쪽 나무 판벽(징두리) + 위 끝 몰딩: 붉은 벽돌 위아래로 나뉘어 아늑한 카페 벽
        var wain = Geo(), rail = Geo()
        for sg in segs {
            let a2 = L.flat(sg.a), b2 = L.flat(sg.b)
            let len = simd_distance(a2, b2)
            guard len > 0.1 else { continue }
            let nw = L.flat(sg.n) - L.flat(.zero)
            let n3 = SIMD3<Float>(nw.x, 0, nw.y)
            let h: Float = sg.window ? 0.84 : 0.9
            let a = SIMD3<Float>(a2.x, floorY, a2.y) + n3 * 0.012, b = SIMD3<Float>(b2.x, floorY, b2.y) + n3 * 0.012
            wain.face(a, b, toward: n3, y0: 0, y1: h, u0: 0, u1: len / 1.2, v0: 0, v1: h / 1.2)
            rail.face(a + n3 * 0.012, b + n3 * 0.012, toward: n3, y0: h - 0.02, y1: h + 0.035, u0: 0, u1: len / 0.8, v0: 0, v1: 0.05)
            if look == .line {
                lines.stroke(a + n3 * 0.03 + SIMD3<Float>(0, h + 0.035, 0), b + n3 * 0.03 + SIMD3<Float>(0, h + 0.035, 0), width: 0.01)
            }
        }
        if let e = wain.entity("wainscot", look == .line ? Ink.paper(1) : Tex.unlit("planks_dark", tint: [0.85, 0.72, 0.6], folder: "tex", sampler: Tex.tiling)) { near.addChild(e) }
        if let e = rail.entity("rail", wood) { near.addChild(e) }
        // 메뉴판 (가장 긴 벽 가운데)
        if let s = walls.first, let sp = span(s), top > 2.1 {
            let (a, b, dir) = sp
            walls.removeFirst()
            let mid = (a + b) / 2
            let w = min(1.0, simd_distance(a, b) - 0.2), h = min(1.15, top - 1.25)
            decorCells.formUnion(frontCells(s, mid: mid, width: w, depth: 0.6))
            let n = s.n
            let c = p3(mid + n * 0.025, 1.15 + h / 2)
            let n3 = SIMD3<Float>((L.flat(n) - L.flat(.zero)).x, 0, (L.flat(n) - L.flat(.zero)).y)
            let r3 = SIMD3<Float>((L.flat(dir) - L.flat(.zero)).x, 0, (L.flat(dir) - L.flat(.zero)).y)
            var board = Geo()
            let hw = r3 * (w / 2), hh = SIMD3<Float>(0, h / 2, 0)
            board.quad(c - hw - hh, c + hw - hh, c + hw + hh, c - hw + hh, SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(1, 1), SIMD2<Float>(0, 1))
            let bm: UnlitMaterial = look == .line ? Ink.paper(0) : {
                var m = UnlitMaterial(color: Tex.color([0.12, 0.14, 0.13]))
                if let t = Tex.get("menu_board") { var p = MaterialParameters.Texture(t); p.sampler = Tex.clamp; m.color = .init(tint: .white, texture: p) }
                return m
            }()
            if let e = board.entity("menu", bm) { near.addChild(e) }
            let frame = ModelEntity(mesh: .generateBox(width: w + 0.08, height: h + 0.08, depth: 0.03), materials: [wood])
            frame.position = c - n3 * 0.012
            frame.orientation = simd_quatf(angle: atan2(n3.x, n3.z), axis: [0, 1, 0])
            near.addChild(frame)
            if look == .line {
                let fw = r3 * (w / 2 + 0.04), fh = SIMD3<Float>(0, h / 2 + 0.04, 0), o = c + n3 * 0.01
                for (p, q) in [(o - fw - fh, o + fw - fh), (o + fw - fh, o + fw + fh), (o + fw + fh, o - fw + fh), (o - fw + fh, o - fw - fh)] {
                    lines.stroke(p, q, width: 0.012)
                }
            }
            // 메뉴판 아래 바 카운터 (깊이 42cm): 나무 앞판·대리석 상판, 에스프레소 머신·그라인더·케이크 진열
            let cw = min(2.4, simd_distance(a, b) - 0.2)
            if cw >= 1.2 {
                let yaw = atan2(n3.x, n3.z)
                let rot = simd_quatf(angle: yaw, axis: [0, 1, 0])
                let base = p3(mid, 0) + n3 * 0.21
                decorCells.formUnion(frontCells(s, mid: mid, width: cw + 0.2, depth: 0.9))
                func box(_ w: Float, _ h: Float, _ d: Float, _ at: SIMD3<Float>, _ m: RealityKit.Material, outline: Bool = true) {
                    let e = ModelEntity(mesh: .generateBox(width: w, height: h, depth: d), materials: [m])
                    e.position = at
                    e.orientation = rot
                    near.addChild(e)
                    if look == .line && outline {
                        lines.boxOutline(base: at - SIMD3<Float>(0, h / 2, 0), w: w, d: d, h: h, yaw: yaw, width: 0.008)
                    }
                }
                func cyl(_ r: Float, _ h: Float, _ at: SIMD3<Float>, _ m: RealityKit.Material) {
                    let e = ModelEntity(mesh: .generateCylinder(height: h, radius: r), materials: [m])
                    e.position = at
                    near.addChild(e)
                }
                let front = look == .line ? Ink.paper(1) : Tex.unlit("planks_dark", tint: [0.8, 0.66, 0.54], folder: "tex", sampler: Tex.tiling)
                box(cw, 0.93, 0.42, base + SIMD3<Float>(0, 0.465, 0), front)
                box(cw + 0.06, 0.04, 0.48, base + SIMD3<Float>(0, 0.95, 0.0) + n3 * 0.02, look == .line ? Ink.paper(0) : Tex.unlit("marble", tint: [0.95, 0.93, 0.9], folder: "tex", sampler: Tex.tiling))
                let topY: Float = 0.97
                // 에스프레소 머신 (스테인리스 몸통, 그룹 헤드 두 개, 포터필터 손잡이, 위에 잔)
                let mPos = base + r3 * (-cw / 4) + SIMD3<Float>(0, topY, 0) - n3 * 0.02
                let steel = paper([0.74, 0.76, 0.79]), darkM = paper([0.12, 0.12, 0.13]), cupW = paper([0.96, 0.95, 0.92])
                box(0.56, 0.36, 0.34, mPos + SIMD3<Float>(0, 0.18, 0), steel)
                box(0.56, 0.03, 0.34, mPos + SIMD3<Float>(0, 0.375, 0), darkM)
                box(0.5, 0.025, 0.12, mPos + SIMD3<Float>(0, 0.0125, 0) + n3 * 0.2, darkM)
                for k: Float in [-0.13, 0.13] {
                    cyl(0.036, 0.05, mPos + r3 * k + n3 * 0.19 + SIMD3<Float>(0, 0.14, 0), darkM)
                    box(0.022, 0.022, 0.13, mPos + r3 * k + n3 * 0.29 + SIMD3<Float>(0, 0.12, 0), darkM, outline: false)
                    cyl(0.03, 0.055, mPos + r3 * k + n3 * 0.2 + SIMD3<Float>(0, 0.053, 0), cupW)
                }
                for k in 0..<3 { cyl(0.035, 0.06, mPos + r3 * (Float(k) * 0.08 - 0.08) + SIMD3<Float>(0, 0.42, 0), cupW) }
                let wand = ModelEntity(mesh: .generateCylinder(height: 0.16, radius: 0.006), materials: [steel])
                wand.position = mPos + r3 * 0.31 + n3 * 0.17 + SIMD3<Float>(0, 0.13, 0)
                wand.orientation = simd_quatf(angle: 0.25, axis: simd_normalize(r3))
                near.addChild(wand)
                cafeSpot = mPos + r3 * 0.31 + n3 * 0.19 + SIMD3<Float>(0, 0.05, 0)
                var pe = ParticleEmitterComponent()
                pe.emitterShape = .point
                pe.birthDirection = .world
                pe.emissionDirection = [0, 1, 0]
                pe.speed = 0.25
                pe.speedVariation = 0.1
                pe.mainEmitter.birthRate = 60                                     // 작고 옅은 김을 많이 (큰 동그라미가 겹쳐 보이지 않게)
                pe.mainEmitter.lifeSpan = 1.4
                pe.mainEmitter.lifeSpanVariation = 0.4
                pe.mainEmitter.size = 0.01
                pe.mainEmitter.sizeMultiplierAtEndOfLifespan = 5
                pe.mainEmitter.noiseStrength = 0.06
                pe.mainEmitter.noiseScale = 3
                pe.mainEmitter.blendMode = .alpha
                pe.mainEmitter.color = .constant(.single(pcolor([1, 1, 1], 0.15)))
                pe.mainEmitter.opacityCurve = .gradualFadeInOut
                if let puff = Tex.particle("smoke_puff") { pe.mainEmitter.image = puff }
                pe.isEmitting = false
                let se = Entity()
                se.components.set(pe)
                se.position = cafeSpot ?? mPos
                se.components.set(ModelSortGroupComponent(group: sortGroup, order: 18))
                near.addChild(se)
                cafeSteam = se
                // 그라인더 (원두 통)
                let gPos = mPos + r3 * 0.42
                box(0.16, 0.3, 0.2, gPos + SIMD3<Float>(0, 0.15, 0), darkM)
                cyl(0.07, 0.13, gPos + SIMD3<Float>(0, 0.365, 0), paper([0.36, 0.22, 0.12]))
                // 케이크 진열: 접시 + 케이크 + 유리 덮개
                let cPos = base + r3 * (cw / 4) + SIMD3<Float>(0, topY, 0)
                cyl(0.15, 0.012, cPos + SIMD3<Float>(0, 0.006, 0), cupW)
                cyl(0.1, 0.07, cPos + SIMD3<Float>(0, 0.047, 0), paper([0.42, 0.24, 0.14]))
                cyl(0.1, 0.014, cPos + SIMD3<Float>(0, 0.089, 0), paper([0.96, 0.9, 0.78]))
                if look != .line {
                    var glass = UnlitMaterial(color: UIColor(white: 1, alpha: 1))
                    glass.blending = .transparent(opacity: .init(floatLiteral: 0.16))
                    glass.writesDepth = false                 // 반투명 판이 뒤의 나무·물건을 네모나게 지우지 않게
                    let dome = ModelEntity(mesh: .generateSphere(radius: 0.155), materials: [glass])
                    dome.position = cPos + SIMD3<Float>(0, 0.012, 0)
                    dome.scale = [1, 1.05, 1]
                    near.addChild(dome)
                }
                // 작은 화분
                let pPos = base + r3 * (cw / 2 - 0.15) + SIMD3<Float>(0, topY, 0) - n3 * 0.08
                cyl(0.055, 0.1, pPos + SIMD3<Float>(0, 0.05, 0), paper([0.72, 0.38, 0.24]))
                let leaf = ModelEntity(mesh: .generateSphere(radius: 0.085), materials: [paper([0.24, 0.46, 0.22])])
                leaf.position = pPos + SIMD3<Float>(0, 0.16, 0)
                leaf.scale = [1, 0.85, 1]
                near.addChild(leaf)
            }
        }
        // 선반 (다음 벽 두 개): 1.55m·1.9m, 깊이 14cm
        let cupM = solid([0.95, 0.93, 0.88]), bottleM = solid([0.16, 0.32, 0.22]), jarM = solid([0.78, 0.52, 0.22])
        var steamDone = false
        for s in walls.prefix(2) {
            guard let sp = span(s) else { continue }
            let (a, b, dir) = sp
            let len = min(1.8, simd_distance(a, b) - 0.1)
            let mid = (a + b) / 2
            decorCells.formUnion(frontCells(s, mid: mid, width: len, depth: 0.6))
            let n3 = SIMD3<Float>((L.flat(s.n) - L.flat(.zero)).x, 0, (L.flat(s.n) - L.flat(.zero)).y)
            let r3 = SIMD3<Float>((L.flat(dir) - L.flat(.zero)).x, 0, (L.flat(dir) - L.flat(.zero)).y)
            let yaw = atan2(n3.x, n3.z)
            for y: Float in [1.55, 1.9] where y < top - 0.25 {
                let c = p3(mid, y) + n3 * 0.07
                let shelf = ModelEntity(mesh: .generateBox(width: len, height: 0.025, depth: 0.14), materials: [wood])
                shelf.position = c
                shelf.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
                near.addChild(shelf)
                if look == .line {
                    lines.stroke(c - r3 * (len / 2) + n3 * 0.07 + SIMD3<Float>(0, 0.013, 0), c + r3 * (len / 2) + n3 * 0.07 + SIMD3<Float>(0, 0.013, 0), width: 0.01)
                    lines.stroke(c - r3 * (len / 2) + n3 * 0.07 - SIMD3<Float>(0, 0.013, 0), c + r3 * (len / 2) + n3 * 0.07 - SIMD3<Float>(0, 0.013, 0), width: 0.01)
                }
                var x = -len / 2 + 0.1
                while x < len / 2 - 0.08 {
                    let kind = Int.random(in: 0...5, using: &g)
                    let base = c + r3 * x + SIMD3<Float>(0, 0.0125, 0)
                    let e: ModelEntity
                    var h: Float = 0.08
                    switch kind {
                    case 0, 1, 2: e = ModelEntity(mesh: .generateCylinder(height: 0.08, radius: 0.035), materials: [cupM])
                    case 3: h = 0.24; e = ModelEntity(mesh: .generateCylinder(height: h, radius: 0.03), materials: [bottleM])
                    default: h = 0.14; e = ModelEntity(mesh: .generateCylinder(height: h, radius: 0.05), materials: [jarM])
                    }
                    e.position = base + SIMD3<Float>(0, h / 2, 0)
                    near.addChild(e)
                    if kind == 0 && !steamDone && y < 1.7 {
                        steamDone = true
                        var pe = ParticleEmitterComponent()
                        pe.mainEmitter.image = Tex.particle("smoke_puff")      // 기본 동그라미(둥근 원반) 대신 부드러운 그림
                        pe.emitterShape = .point
                        pe.birthDirection = .world
                        pe.emissionDirection = [0, 1, 0]
                        pe.speed = 0.06
                        pe.speedVariation = 0.02
                        pe.mainEmitter.birthRate = 6
                        pe.mainEmitter.lifeSpan = 2.5
                        pe.mainEmitter.size = 0.015
                        pe.mainEmitter.sizeMultiplierAtEndOfLifespan = 4
                        pe.mainEmitter.noiseStrength = 0.02
                        pe.mainEmitter.color = .constant(.single(pcolor([1, 1, 1], 0.35)))
                        pe.mainEmitter.opacityCurve = .gradualFadeInOut
                        emitter(pe, at: base + SIMD3<Float>(0, h + 0.01, 0), into: near)
                    }
                    x += Float.random(in: 0.11...0.2, using: &g)
                }
            }
        }
        // 펜던트 조명: 짧게(아래 끝이 천장 30cm 아래) — 머리에 닿지 않게 천장이 2.3m 넘을 때만, 벽에서 60cm 안쪽에 1.6m 간격
        if top >= 2.3 {
            let shadeM = solid([0.12, 0.12, 0.13]), bulbM = solid(night ? [1, 0.82, 0.5] : [1, 0.92, 0.75])
            var cone = Geo()
            let segN = 16
            for k in 0..<segN {
                let a0 = Float(k) / Float(segN) * 2 * .pi, a1 = Float(k + 1) / Float(segN) * 2 * .pi
                cone.quad(SIMD3<Float>(cos(a0) * 0.04, 0.14, sin(a0) * 0.04), SIMD3<Float>(cos(a1) * 0.04, 0.14, sin(a1) * 0.04),
                          SIMD3<Float>(cos(a1) * 0.15, 0, sin(a1) * 0.15), SIMD3<Float>(cos(a0) * 0.15, 0, sin(a0) * 0.15), .zero, .zero, .zero, .zero)
            }
            let coneMesh = cone.mesh("shade")
            var count = 0
            for r in L.rects(segs.first?.room ?? 0) where count < 8 {
                var u = r.0.x + 0.8
                while u < r.1.x - 0.6 && count < 8 {
                    var v = r.0.y + 0.8
                    while v < r.1.y - 0.6 && count < 8 {
                        let p = SIMD2<Float>(u, v)
                        if L.walkable(p), let cm = coneMesh {
                            let base = p3(p, top - 0.3)
                            let shadeE = ModelEntity(mesh: cm, materials: [shadeM])
                            shadeE.position = base
                            near.addChild(shadeE)
                            let cord = ModelEntity(mesh: .generateBox(width: 0.008, height: 0.16, depth: 0.008), materials: [shadeM])
                            cord.position = base + SIMD3<Float>(0, 0.22, 0)
                            near.addChild(cord)
                            let bulb = ModelEntity(mesh: .generateSphere(radius: 0.035), materials: [bulbM])
                            bulb.position = base + SIMD3<Float>(0, 0.02, 0)
                            near.addChild(bulb)
                            count += 1
                        }
                        v += 1.6
                    }
                    u += 1.6
                }
            }
        }
        if let e = lines.entity("cafeLines", Ink.line) { near.addChild(e) }
    }

    /// 카페 창밖 길을 지나가는 사람들 (창이 있는 벽 바깥 4~6m, 벽과 나란히 걸어감)
    private func addPassersby<G: RandomNumberGenerator>(_ segs: [WallSeg], floorY: Float, using g: inout G) {
        let wins = segs.filter { $0.window }
        guard !wins.isEmpty else { return }
        var made = 0
        for s in wins where made < 8 {
            let len = simd_distance(s.a, s.b)
            let dir = (s.b - s.a) / max(0.01, len)
            let mid = (s.a + s.b) / 2
            let dist = Float.random(in: 4...6, using: &g)
            let line0 = mid - s.n * dist - dir * 7, line1 = mid - s.n * dist + dir * 7
            // 길 전체가 집 밖이어야 함
            var ok = true
            for k in 0...14 {
                let q = line0 + (line1 - line0) * (Float(k) / 14)
                if L.walkable(q) || L.walkable(q + s.n * 0.6) || L.walkable(q - s.n * 0.6) { ok = false; break }
            }
            guard ok else { continue }
            let a3 = { () -> SIMD3<Float> in let f = L.flat(line0); return SIMD3<Float>(f.x, floorY, f.y) }()
            let b3 = { () -> SIMD3<Float> in let f = L.flat(line1); return SIMD3<Float>(f.x, floorY, f.y) }()
            let d3 = simd_normalize(b3 - a3)
            let n3 = SIMD3<Float>((L.flat(s.n) - L.flat(.zero)).x, 0, (L.flat(s.n) - L.flat(.zero)).y)
            for k in 0..<3 {
                let tex = "person_\(Int.random(in: 0...3, using: &g))"
                let h = Float.random(in: 1.55...1.85, using: &g)
                let w = h * 0.42
                var q = Geo()
                q.quad(SIMD3<Float>(-w / 2, 0, 0), SIMD3<Float>(w / 2, 0, 0), SIMD3<Float>(w / 2, h, 0), SIMD3<Float>(-w / 2, h, 0),
                       SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(1, 1), SIMD2<Float>(0, 1))
                let tint: SIMD3<Float> = [Float.random(in: 0.3...0.9, using: &g), Float.random(in: 0.3...0.8, using: &g), Float.random(in: 0.3...0.8, using: &g)]
                guard let e = q.entity("person", Tex.cutout(tex, tint: tint, sampler: Tex.clamp)) else { continue }
                e.orientation = simd_quatf(angle: atan2(n3.x, n3.z), axis: [0, 1, 0])
                e.components.set(ModelSortGroupComponent(group: sortGroup, order: 7))
                let forward = k % 2 == 0
                far.addChild(e)
                movers.append(Mover(e: e, a: forward ? a3 : b3, d: forward ? d3 : -d3, len: 14, speed: Float.random(in: 0.9...1.4, using: &g),
                                    s: Float.random(in: 0...14, using: &g), bob: 0.025))
                made += 1
            }
        }
    }

    /// 벽 s 를 따라 문 끝(margin 안)을 피하고, 벽 앞 depth m 안에 가구 기둥이 없는 가장 긴 구간 (벽 시작점에서 거리 t0, t1)
    private func clearRun(_ s: WallSeg, doorEnds: [SIMD2<Float>], depth: Float, minLen: Float) -> (Float, Float)? {
        let len = simd_distance(s.a, s.b)
        guard len > minLen else { return nil }
        let dir = (s.b - s.a) / len
        let step: Float = 0.05
        var best: (Float, Float)? = nil
        var start: Float? = nil
        var t: Float = 0.15
        while t <= len - 0.15 + 1e-3 {
            let q = s.a + dir * t
            var ok = !doorEnds.contains { simd_distance($0, q) < 0.5 }
            if ok {
                var o: Float = 0.05
                while o <= depth + 1e-3 {
                    if blocked.contains(RoomWorld.clutterKey(q + s.n * o)) { ok = false; break }
                    o += 0.1
                }
            }
            if ok && start == nil { start = t }
            let last = t + step > len - 0.15 + 1e-3
            if let st = start, !ok || last {
                let en = ok ? t : t - step
                if en - st >= minLen && (best == nil || en - st > best!.1 - best!.0) { best = (st, en) }
                start = nil
            }
            t += step
        }
        return best
    }

    // MARK: 통나무집 벽난로
    private func addFireplace<G: RandomNumberGenerator>(_ segs: [WallSeg], floorY: Float, ceilY: Float, using g: inout G) {
        // 자리: 창이 아닌 벽 중 문 끝에서 50cm 떨어지고, 벽 앞 1m 안에 가구가 없는 1.5m 구간 (긴 벽부터)
        var doorEnds: [SIMD2<Float>] = []
        for ds in L.doors {
            for r in [ds.roomA, ds.roomB] where segs.first?.room == r {
                let (a, b, _) = ds.edge(for: r)
                doorEnds += [a, b]
            }
        }
        var pick: (WallSeg, SIMD2<Float>)? = nil
        for s in segs.filter({ !$0.window && simd_distance($0.a, $0.b) > 1.6 }).sorted(by: { simd_distance($0.a, $0.b) > simd_distance($1.a, $1.b) }) {
            guard let run = clearRun(s, doorEnds: doorEnds, depth: 1.0, minLen: 1.5) else { continue }
            let dir = (s.b - s.a) / simd_distance(s.a, s.b)
            pick = (s, s.a + dir * ((run.0 + run.1) / 2))
            break
        }
        guard let pk = pick else { return }
        let s = pk.0, mid = pk.1
        let f = L.flat(mid)
        let n3 = SIMD3<Float>((L.flat(s.n) - L.flat(.zero)).x, 0, (L.flat(s.n) - L.flat(.zero)).y)
        let yaw = atan2(n3.x, n3.z)
        let root = Entity()
        root.position = SIMD3<Float>(f.x, floorY, f.y)
        root.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        let stone = look == .line ? Ink.paper(0) : Tex.unlit("rock", tint: [0.85, 0.82, 0.78], folder: "tex", sampler: Tex.tiling)
        let dark = solid([0.05, 0.04, 0.04])
        // 둘레(양옆 기둥 + 위 선반) 깊이 22cm
        for x: Float in [-0.5, 0.5] {
            let p = ModelEntity(mesh: .generateBox(width: 0.24, height: 0.95, depth: 0.22), materials: [stone])
            p.position = [x, 0.475, 0.11]
            root.addChild(p)
        }
        let mantel = ModelEntity(mesh: .generateBox(width: 1.36, height: 0.12, depth: 0.28), materials: [stone])
        mantel.position = [0, 1.0, 0.14]
        root.addChild(mantel)
        let box = ModelEntity(mesh: .generateBox(width: 0.76, height: 0.8, depth: 0.04), materials: [dark])
        box.position = [0, 0.4, 0.02]
        root.addChild(box)
        if look == .line {
            var l = Geo()
            l.boxOutline(base: [-0.5, 0, 0.11], w: 0.24, d: 0.22, h: 0.95, yaw: 0, width: 0.012)
            l.boxOutline(base: [0.5, 0, 0.11], w: 0.24, d: 0.22, h: 0.95, yaw: 0, width: 0.012)
            l.boxOutline(base: [0, 0.94, 0.14], w: 1.36, d: 0.28, h: 0.12, yaw: 0, width: 0.012)
            if let e = l.entity("fireLines", Ink.line) { root.addChild(e) }
        }
        // 불: 주황빛 입자 + 깜빡이는 불빛
        var fire = ParticleEmitterComponent()
        fire.mainEmitter.image = Tex.particle("smoke_puff")      // 기본 동그라미(둥근 원반) 대신 부드러운 그림
        fire.emitterShape = .box
        fire.emitterShapeSize = [0.45, 0.05, 0.12]
        fire.birthLocation = .volume
        fire.birthDirection = .world
        fire.emissionDirection = [0, 1, 0]
        fire.speed = 0.35
        fire.speedVariation = 0.15
        fire.mainEmitter.birthRate = 60
        fire.mainEmitter.lifeSpan = 0.8
        fire.mainEmitter.size = 0.07
        fire.mainEmitter.sizeMultiplierAtEndOfLifespan = 0.2
        fire.mainEmitter.color = .evolving(start: .single(pcolor([1, 0.85, 0.4])), end: .single(pcolor([0.95, 0.3, 0.05])))
        fire.mainEmitter.blendMode = look == .line ? .alpha : .additive
        fire.mainEmitter.opacityCurve = .quickFadeInOut
        let fe = Entity()
        fe.components.set(fire)
        fe.position = [0, 0.08, 0.1]
        fe.components.set(ModelSortGroupComponent(group: sortGroup, order: 18))
        root.addChild(fe)
        // 장작 두 개 + 불꽃 세 갈래 (불꽃 모양 그림을 십자로 세워 흔들림)
        let logM = look == .line ? Ink.paper(1) : Tex.unlit("bark", tint: [0.6, 0.5, 0.42], folder: "tex", sampler: Tex.tiling)
        for (x, a) in [(Float(-0.06), Float(0.25)), (Float(0.07), Float(-0.3))] {
            let log = ModelEntity(mesh: .generateCylinder(height: 0.42, radius: 0.04), materials: [logM])
            log.orientation = simd_quatf(angle: .pi / 2, axis: [0, 0, 1]) * simd_quatf(angle: a, axis: [1, 0, 0])
            log.position = [x, 0.05, 0.1]
            root.addChild(log)
        }
        var flameM = UnlitMaterial(color: look == .line ? UIColor(white: 0.15, alpha: 1) : Tex.color([1, 0.75, 0.35]))
        if let t = Tex.get("flame", color: look == .color) {
            var p = MaterialParameters.Texture(t)
            p.sampler = Tex.clamp
            flameM.color = .init(tint: look == .line ? UIColor(white: 0.15, alpha: 1) : .white, texture: p)
        }
        if let mask = Tex.get("flame_a", raw: true) {
            var p = MaterialParameters.Texture(mask)
            p.sampler = Tex.clamp
            flameM.blending = .transparent(opacity: .init(scale: 1, texture: p))
            flameM.writesDepth = false                 // 반투명 판이 뒤의 나무·물건을 네모나게 지우지 않게
        }
        for (k, x) in [Float(-0.12), 0, 0.12].enumerated() {
            let h: Float = k == 1 ? 0.36 : 0.26
            var q = Geo()
            q.crossTree(at: .zero, width: h * 0.55, height: h, yaw: 0.4)
            guard let fl = q.entity("flame", flameM) else { continue }
            fl.position = [x, 0.07, 0.1]
            fl.components.set(ModelSortGroupComponent(group: sortGroup, order: 17))
            root.addChild(fl)
            flames.append((fl, Float(k) * 1.7 + Float.random(in: 0...1, using: &g)))
        }
        near.addChild(root)
        decorCells.formUnion(frontCells(s, mid: mid, width: 1.5, depth: 1.0))
    }

    // MARK: 전시관 먼지 빛
    private func addDust(floorY: Float) {
        var pe = ParticleEmitterComponent()
        pe.mainEmitter.image = Tex.particle("spark_dot")      // 기본 동그라미(둥근 원반) 대신 부드러운 그림
        pe.emitterShape = .box
        pe.emitterShapeSize = SIMD3<Float>(max(0.5, halfSize.x * 2 - 0.8), 1.4, max(0.5, halfSize.y * 2 - 0.8))
        pe.birthLocation = .volume
        pe.speed = 0.02
        pe.speedVariation = 0.02
        pe.mainEmitter.birthRate = min(30, 2.5 * halfSize.x * halfSize.y * 4)
        pe.mainEmitter.lifeSpan = 8
        pe.mainEmitter.size = 0.004
        pe.mainEmitter.noiseStrength = 0.03
        pe.mainEmitter.color = .constant(.single(pcolor([1, 0.95, 0.8], 0.8)))
        pe.mainEmitter.blendMode = look == .line ? .alpha : .additive
        pe.mainEmitter.opacityCurve = .gradualFadeInOut
        let e = Entity()
        e.components.set(pe)
        e.position = center + SIMD3<Float>(0, 1.4, 0)
        e.orientation = simd_quatf(angle: atan2(-ex.z, ex.x), axis: [0, 1, 0])
        e.components.set(ModelSortGroupComponent(group: sortGroup, order: 19))
        near.addChild(e)
    }

    // MARK: 매 프레임 (지금 방만)
    func tick(_ dt: Float) {
        t += dt
        for f in flyers {
            f.ang += f.dir * f.speed / max(4, f.radius) * dt
            let p = f.center + SIMD3<Float>(cos(f.ang) * f.radius, 0, sin(f.ang) * f.radius)
            f.root.position = SIMD3<Float>(p.x, f.height + 1.2 * sin(t * 0.35 + f.phase), p.z)
            let v = SIMD3<Float>(-sin(f.ang), 0, cos(f.ang)) * f.dir
            f.root.orientation = simd_quatf(angle: atan2(-v.x, -v.z), axis: [0, 1, 0])
            // 날갯짓 (가끔 미끄러지듯 쉼)
            let glide = sin(t * 0.5 + f.phase) > 0.6
            let a = glide ? 0.08 : 0.55 * sin(t * f.flap + f.phase)
            if f.wings.count == 2 {
                f.wings[0].orientation = simd_quatf(angle: a, axis: [0, 0, 1])
                f.wings[1].orientation = simd_quatf(angle: -a, axis: [0, 0, 1])
            }
        }
        for i in movers.indices {
            var m = movers[i]
            m.s += m.speed * dt
            if m.s > m.len { m.s -= m.len }
            m.e.position = m.a + m.d * m.s + SIMD3<Float>(0, m.bob * abs(sin(m.s * 3.2)), 0)
            movers[i] = m
        }
        for i in boats.indices {
            var b = boats[i]
            b.2 += b.4 * dt
            let p = b.1 + SIMD3<Float>(cos(b.2) * b.3, 0.12 * sin(t * 0.8 + Float(i)), sin(b.2) * b.3)
            b.0.position = p
            let v = SIMD3<Float>(-sin(b.2), 0, cos(b.2)) * (b.4 >= 0 ? 1 : -1)
            b.0.orientation = simd_quatf(angle: atan2(v.x, v.z), axis: [0, 1, 0]) * simd_quatf(angle: 0.04 * sin(t * 1.1 + Float(i)), axis: [0, 0, 1])
            boats[i] = b
        }
        for (e, period) in blinkers where period > 0 {
            let on = (t / period).truncatingRemainder(dividingBy: 1) < 0.15
            if e.isEnabled != on { e.isEnabled = on }
        }
        // 카페: 가끔 우유 스팀 (치이익 + 김), 잔 달그락
        if let spot = cafeSpot {
            if t > nextSteam {
                nextSteam = t + Float.random(in: 25...55)
                steamOff = t + 3
                if var pe = cafeSteam?.components[ParticleEmitterComponent.self] { pe.isEmitting = true; cafeSteam?.components.set(pe) }
                Sfx.play("espresso_steam", in: near, at: spot, gain: -6)
            }
            if steamOff > 0 && t > steamOff {
                steamOff = -1
                if var pe = cafeSteam?.components[ParticleEmitterComponent.self] { pe.isEmitting = false; cafeSteam?.components.set(pe) }
            }
            if t > nextClink {
                nextClink = t + Float.random(in: 10...28)
                Sfx.play("cup_clink\(Int.random(in: 1...2))", in: near, at: spot + SIMD3<Float>(Float.random(in: -0.6...0.6), 0, Float.random(in: -0.3...0.3)), gain: -4)
            }
        }
        for (e, ph) in flames {
            let k = 0.8 + 0.2 * sin(t * 9 + ph) * sin(t * 5.3 + ph * 2)
            e.scale = SIMD3<Float>(1 + 0.08 * sin(t * 7 + ph), k, 1)
            e.orientation = simd_quatf(angle: 0.08 * sin(t * 3.1 + ph), axis: [0, 0, 1])
        }
    }
}
