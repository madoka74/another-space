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
        let span: Float = big ? 1.6 : 0.55
        var wing = Geo()
        wing.quad(SIMD3<Float>(0, 0, -0.06 * span), SIMD3<Float>(0, 0, 0.1 * span), SIMD3<Float>(span / 2, 0, 0.02 * span),
                  SIMD3<Float>(span / 2, 0, -0.02 * span), .zero, .zero, .zero, .zero)
        guard let wm = wing.mesh("wing") else { return }
        let body = MeshResource.generateBox(width: 0.06 * span, height: 0.05 * span, depth: 0.3 * span, cornerRadius: 0.02 * span)
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
                let w = ModelEntity(mesh: wm, materials: [mat])
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
        let hullM = solid([0.45, 0.32, 0.22]), sailM = solid([0.96, 0.94, 0.9])
        for _ in 0..<4 {
            let b = Entity()
            let L: Float = Float.random(in: 4...7, using: &g)
            let hull = ModelEntity(mesh: .generateBox(width: L * 0.28, height: L * 0.14, depth: L, cornerRadius: L * 0.05), materials: [hullM])
            hull.position = [0, L * 0.05, 0]
            b.addChild(hull)
            var sail = Geo()
            sail.quad(SIMD3<Float>(0, L * 0.12, -L * 0.3), SIMD3<Float>(0, L * 0.12, L * 0.25), SIMD3<Float>(0, L * 0.95, -L * 0.15),
                      SIMD3<Float>(0, L * 0.95, -L * 0.15), .zero, .zero, .zero, .zero)
            if let e = sail.entity("sail", sailM) { b.addChild(e) }
            if night {
                let lamp = ModelEntity(mesh: .generateSphere(radius: L * 0.05), materials: [solid([1, 0.85, 0.5])])
                lamp.position = [0, L * 0.6, 0]
                b.addChild(lamp)
                blinkers.append((lamp, 0))
            }
            let rad = R + Float.random(in: 70...230, using: &g)
            let a = Float.random(in: 0...(2 * .pi), using: &g)
            let w = Float.random(in: 0.6...1.4, using: &g) / rad * (Bool.random(using: &g) ? 1 : -1)
            far.addChild(b)
            boats.append((b, SIMD3<Float>(center.x, floorY - 0.4, center.z), a, rad, w))
        }
    }

    // MARK: 도시
    private func addCars<G: RandomNumberGenerator>(R: Float, floorY: Float, night: Bool, using g: inout G) {
        let y = floorY - 30 + 0.8
        let colors: [SIMD3<Float>] = [[0.8, 0.15, 0.12], [0.9, 0.9, 0.88], [0.15, 0.2, 0.35], [0.2, 0.2, 0.22], [0.85, 0.7, 0.2]]
        let head = solid([1, 0.92, 0.7]), tail = solid([1, 0.15, 0.1])
        for k in 0..<8 {
            let along = k % 2 == 0 ? ex : ez
            let side = k % 2 == 0 ? ez : ex
            let off = Float.random(in: 18...140, using: &g) * (Bool.random(using: &g) ? 1 : -1)
            let len: Float = 360
            let a = center + side * off - along * (len / 2) + SIMD3<Float>(0, y - center.y, 0)
            for c in 0..<4 {
                let car = Entity()
                if night {
                    for (m, z) in [(head, Float(-2.1)), (tail, Float(2.1))] {
                        for x: Float in [-0.7, 0.7] {
                            let l = ModelEntity(mesh: .generateSphere(radius: 0.35), materials: [m])
                            l.position = [x, 0, z]
                            car.addChild(l)
                        }
                    }
                } else {
                    car.addChild(ModelEntity(mesh: .generateBox(width: 1.9, height: 1.4, depth: 4.4, cornerRadius: 0.4),
                                             materials: [solid(colors[(k + c) % colors.count])]))
                }
                let dir = (k / 2) % 2 == 0 ? along : -along
                let start = dir == along ? a : a + along * len
                car.orientation = simd_quatf(angle: atan2(dir.x, dir.z), axis: [0, 1, 0])
                far.addChild(car)
                movers.append(Mover(e: car, a: start, d: dir, len: len, speed: Float.random(in: 9...16, using: &g),
                                    s: Float.random(in: 0...len, using: &g), bob: 0))
            }
        }
    }

    private func addPlane<G: RandomNumberGenerator>(floorY: Float, using g: inout G) {
        let p = Entity()
        let red = ModelEntity(mesh: .generateSphere(radius: 0.9), materials: [solid([1, 0.2, 0.15])])
        let white = ModelEntity(mesh: .generateSphere(radius: 0.9), materials: [solid([1, 1, 1])])
        red.position = [-6, 0, 0]; white.position = [6, 0, 0]
        p.addChild(red); p.addChild(white)
        blinkers.append((red, 1.1)); blinkers.append((white, 1.7))
        let a = Float.random(in: 0...(2 * .pi), using: &g)
        let dir = SIMD3<Float>(cos(a), 0, sin(a))
        let len: Float = 1400
        let start = center - dir * (len / 2) + SIMD3<Float>(0, floorY - center.y + 160, 0) + SIMD3<Float>(-dir.z, 0, dir.x) * 120
        far.addChild(p)
        movers.append(Mover(e: p, a: start, d: dir, len: len, speed: 45, s: Float.random(in: 0...len, using: &g), bob: 0))
    }

    // MARK: 연기·불·낙엽·안개
    private func smoke(size: Float, rate: Float, dark: Float) -> ParticleEmitterComponent {
        var pe = ParticleEmitterComponent()
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
        for (e, ph) in flames {
            let k = 0.8 + 0.2 * sin(t * 9 + ph) * sin(t * 5.3 + ph * 2)
            e.scale = SIMD3<Float>(1 + 0.08 * sin(t * 7 + ph), k, 1)
            e.orientation = simd_quatf(angle: 0.08 * sin(t * 3.1 + ph), axis: [0, 0, 1])
        }
    }
}
