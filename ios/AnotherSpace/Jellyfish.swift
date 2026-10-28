import Foundation
import UIKit
import RealityKit
import simd

/// 바다 테마의 특징: 공중을 천천히 유영하는 해파리들.
/// - 투명한 갓(가장자리 띠·방사형 관·네 잎 무늬가 은은하게 비침)이 숨 쉬듯 오므라들 때마다 위로 조금씩 밀려 오르고, 촉수·입팔은 뒤로 늘어져 물결침
/// - 갓 속 빛과 둘레 빛무리가 은은하게 발광 (밤일수록 또렷), 공기 중엔 작은 빛 알갱이(바다눈)가 천천히 떠다님
/// - 방 안: 가구보다 높은 곳(1.35m~천장 22cm 아래)에 손바닥만 한 해파리 2~4마리 — 이리저리·위아래로 천천히 헤엄치고, 머리에 가까워지면 비켜 감
/// - 방 밖 바다 위: 몇 마리(갓 지름 50cm~1m)가 2~10m 거리에서 천천히 오르내리며 떠다님
/// - 반투명 재질은 깊이를 쓰지 않음(writesDepth = false) → 뒤의 나무·바위가 네모나게 잘리지 않음
/// 하늘 세계(포털 너머)에 두어 반투명이어도 현실이 비치지 않고, 방 안 자리여도 포털 너머로 그려짐 (가구보다 높이 떠 있어 겹치지 않음)
@MainActor
final class JellySea {
    let root = Entity()          // 방 밖 바다 위 (하늘 세계)
    /// 방 안 해파리 (실제 방 쪽, 저장 좌표): 가구 블록과 같은 공간에 있어야 앞뒤가 정확함 —
    /// 하늘 세계(포털 너머)에 두면 방 안 가구와 앞뒤를 비교할 수 없어 보는 각도마다 앞에 있다 뒤에 있다 했음.
    /// 반투명 재질은 깊이를 쓰지 않으므로(writesDepth = false) 방 안에 있어도 뒤의 하늘·벽 너머가 가려지지 않음
    let localRoot = Entity()

    private final class Jelly {
        let e = Entity()                 // 자리 (저장 좌표)
        let body = Entity()              // 기울기·숨쉬기
        var bell: ModelEntity?
        var halo: ModelEntity?
        var core: ModelEntity?
        var tentacles: [[Entity]] = []   // 촉수마다 마디 (위 → 아래)
        var arms: [[Entity]] = []
        var size: Float = 0.2
        var pos = SIMD3<Float>(0, 0, 0)
        var vel = SIMD3<Float>(0, 0, 0)
        var target = SIMD3<Float>(0, 0, 0)
        var retarget: Float = 0
        var phase: Float = 0
        var period: Float = 3
        var inside = true
        var up = SIMD3<Float>(0, 1, 0)
    }

    private var jellies: [Jelly] = []
    private var t: Float = 0
    private let L: Layout
    private let roomId: Int
    private let floorY: Float
    private let ceilY: Float
    private let center: SIMD3<Float>
    private let reach: Float
    private var worldC = SIMD3<Float>(0, 0, 0)       // 바다 위 해파리가 떠다니는 둘레의 가운데·반지름 (같은 세계 무리 전체)
    private var worldR: Float = 1
    private let look: LookMode
    private let glowK: Float
    var head: SIMD3<Float>?

    private static let palette: [SIMD3<Float>] = [[0.55, 0.85, 1.0], [0.78, 0.62, 1.0], [1.0, 0.62, 0.86], [0.5, 1.0, 0.9],
                                                  [1.0, 0.78, 0.62], [0.72, 0.8, 1.0]]

    /// outside: 바다 위 큰 해파리도 만들지 (같은 세계 무리에선 대표 방만), worldCenter·worldHalf: 무리 전체 가운데·크기 (바다 위 해파리 자리)
    init(center: SIMD3<Float>, halfSize: SIMD2<Float>, floorY: Float, ceilY: Float, layout: Layout, room: RoomRec, look: LookMode,
         outside: Bool = true, worldCenter: SIMD3<Float>? = nil, worldHalf: SIMD2<Float>? = nil) {
        self.L = layout
        self.roomId = room.id
        self.floorY = floorY
        self.ceilY = ceilY
        self.center = center
        self.reach = simd_length(halfSize)
        self.look = look
        switch room.time {
        case "night": glowK = 1
        case "dusk", "dawn": glowK = 0.7
        default: glowK = 0.38
        }
        var g = SeededRNG(seed: UInt64(room.id * 4447 + 19))
        // 방 안: 바닥 넓이에 따라 2~4마리 (손바닥만 한 크기)
        let area = halfSize.x * halfSize.y * 4
        let nIn = max(2, min(4, Int(area / 5)))
        for i in 0..<nIn {
            guard let p = insideSpot(&g) else { continue }
            add(inside: true, at: p, size: Float.random(in: 0.08...0.14, using: &g), color: Self.palette[i % Self.palette.count], &g)
        }
        // 방 밖 바다 위: 몇 마리만, 너무 크지 않게 (갓 지름 50cm~1m), 방에서 2~10m
        // (집 안 어디에도 1.5m 안으로 다가오지 않게 — 포털 너머 세계 것은 내 앞(옆방·문간 자리)에 있어도 그려져, 문 너머로 크게 보였음)
        let wc = worldCenter ?? center
        let wr = worldHalf.map { simd_length($0) } ?? reach
        worldC = wc; worldR = wr
        for i in 0..<(outside ? 4 : 0) {
            for _ in 0..<12 {
                let a = Float.random(in: 0...(2 * .pi), using: &g)
                let d = wr + Float.random(in: 3...11, using: &g)
                let p = SIMD3<Float>(wc.x + cos(a) * d, floorY + Float.random(in: 1.4...4.5, using: &g), wc.z + sin(a) * d)
                guard !nearHouse(p) else { continue }
                add(inside: false, at: p, size: Float.random(in: 0.25...0.5, using: &g), color: Self.palette[(i + 2) % Self.palette.count], &g)
                break
            }
        }
        addPlankton()
    }

    // MARK: 자리
    /// 집 안(어느 방이든 걸을 수 있는 곳) 1.5m 안인지 — 바다 위 해파리는 늘 그 밖에서만
    private func nearHouse(_ p: SIMD3<Float>) -> Bool {
        for k in 0..<9 {
            let a = Float(k) / 8 * 2 * .pi
            let q = k == 8 ? p : p + SIMD3<Float>(cos(a), 0, sin(a)) * 1.5
            if L.walkable(L.plane(q.x, q.z)) { return true }
        }
        return false
    }
    private var lo: Float { floorY + min(1.35, ceilY - floorY - 0.7) }       // 가구보다 높이 (뒤가 벽·천장 창이라 또렷이 그려짐)
    // 빛무리(갓 크기의 3배 넘는 판)까지 천장 창 아래에 들게: 천장을 넘으면 그 면에서 곧게 잘려 보였음
    private var hi: Float { max(lo + 0.1, ceilY - 0.66) }

    /// 가구 높이 (저장 좌표 xz → 바닥에서 m). 탐험이 채워 줌 — 키 큰 가구(책장 등) 위·옆을 지날 때 촉수까지 닿지 않게
    var furnitureH: ((SIMD2<Float>) -> Float)?

    private func insideOK(_ p: SIMD3<Float>) -> Bool {
        let c = L.at(x: p.x, z: p.z)
        guard c.room == roomId && c.wall > 0.55 else { return false }          // 빛무리까지 벽(창) 앞에 들게
        // 문 자리 앞뒤 1m 안엔 가지 않음 (문간을 빛무리가 가득 채워 보였음)
        let pl = L.plane(p.x, p.z)
        if L.doors.contains(where: { !$0.single && $0.dist(pl) < 1.0 }) { return false }
        if let fh = furnitureH {
            let offs: [SIMD2<Float>] = [[0, 0], [0.3, 0], [-0.3, 0], [0, 0.3], [0, -0.3]]
            for o in offs where floorY + fh(SIMD2<Float>(p.x, p.z) + o) + 0.6 > p.y { return false }      // 갓 아래 촉수(약 50cm)까지 여유
        }
        return true
    }

    private func insideSpot<G: RandomNumberGenerator>(_ g: inout G) -> SIMD3<Float>? {
        for _ in 0..<30 {
            let p = SIMD3<Float>(center.x + Float.random(in: -reach...reach, using: &g), Float.random(in: lo...max(lo + 0.01, hi), using: &g),
                                 center.z + Float.random(in: -reach...reach, using: &g))
            if insideOK(p) { return p }
        }
        return nil
    }

    // MARK: 만들기
    private func add<G: RandomNumberGenerator>(inside: Bool, at p: SIMD3<Float>, size s: Float, color c: SIMD3<Float>, _ g: inout G) {
        let j = Jelly()
        j.inside = inside
        j.size = s
        j.pos = p
        j.target = p
        j.phase = Float.random(in: 0...1, using: &g)
        j.period = Float.random(in: 2.6...4.2, using: &g) * (inside ? 1 : 1.3)
        j.e.position = p
        j.e.addChild(j.body)
        let line = look == .line
        let col: SIMD3<Float> = look == .mono ? SIMD3<Float>(repeating: (c.x + c.y + c.z) / 3) : c
        func ui(_ v: SIMD3<Float>) -> UIColor { UIColor(red: CGFloat(min(1, v.x)), green: CGFloat(min(1, v.y)), blue: CGFloat(min(1, v.z)), alpha: 1) }

        // 빛무리 (나를 향한 판)
        if !line, let tx = Tex.get("glow", color: look == .color), let mk = Tex.get("glow_a", raw: true) {
            var q = Geo()
            let h = s * 3.2
            q.quad(SIMD3<Float>(-h, -h * 0.8, 0), SIMD3<Float>(h, -h * 0.8, 0), SIMD3<Float>(h, h * 1.2, 0), SIMD3<Float>(-h, h * 1.2, 0),
                   SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(1, 1), SIMD2<Float>(0, 1))
            var m = UnlitMaterial(color: ui(col))
            var tp = MaterialParameters.Texture(tx); tp.sampler = Tex.clamp
            m.color = .init(tint: ui(col), texture: tp)
            var mp = MaterialParameters.Texture(mk); mp.sampler = Tex.clamp
            m.blending = .transparent(opacity: .init(scale: 0.16 + 0.3 * glowK, texture: mp))
            m.writesDepth = false                 // 반투명 판이 뒤의 나무·물건을 네모나게 지우지 않게
            if let e = q.entity("jellyHalo", m) { j.e.addChild(e); j.halo = e }
        }
        // 갓: 둘레를 따라 돌린 반구 (안팎 다 보이게), 가장자리→꼭대기 무늬
        let prof: [SIMD2<Float>] = [[1.0, 0.0], [0.99, 0.1], [0.93, 0.3], [0.8, 0.48], [0.6, 0.62], [0.33, 0.71], [0.0, 0.74]]
        var bell = Geo()
        let seg = 28
        for k in 0..<(prof.count - 1) {
            for i in 0..<seg {
                let a0 = Float(i) / Float(seg) * 2 * .pi, a1 = Float(i + 1) / Float(seg) * 2 * .pi
                let p0 = prof[k] * s, p1 = prof[k + 1] * s
                let v0 = Float(k) / Float(prof.count - 1), v1 = Float(k + 1) / Float(prof.count - 1)
                let u0 = Float(i) / Float(seg), u1 = Float(i + 1) / Float(seg)
                bell.quad(SIMD3<Float>(cos(a0) * p0.x, p0.y, sin(a0) * p0.x), SIMD3<Float>(cos(a1) * p0.x, p0.y, sin(a1) * p0.x),
                          SIMD3<Float>(cos(a1) * p1.x, p1.y, sin(a1) * p1.x), SIMD3<Float>(cos(a0) * p1.x, p1.y, sin(a0) * p1.x),
                          SIMD2<Float>(u0, v0), SIMD2<Float>(u1, v0), SIMD2<Float>(u1, v1), SIMD2<Float>(u0, v1))
            }
        }
        if line {
            var l = Geo()
            for k in [0, 3] {
                for i in 0..<seg {
                    let a0 = Float(i) / Float(seg) * 2 * .pi, a1 = Float(i + 1) / Float(seg) * 2 * .pi
                    let p = prof[k] * s
                    l.stroke(SIMD3<Float>(cos(a0) * p.x, p.y, sin(a0) * p.x), SIMD3<Float>(cos(a1) * p.x, p.y, sin(a1) * p.x), width: s * 0.03)
                }
            }
            for i in 0..<6 {
                let a = Float(i) / 6 * 2 * .pi
                for k in 0..<(prof.count - 1) {
                    let p0 = prof[k] * s, p1 = prof[k + 1] * s
                    l.stroke(SIMD3<Float>(cos(a) * p0.x, p0.y, sin(a) * p0.x), SIMD3<Float>(cos(a) * p1.x, p1.y, sin(a) * p1.x), width: s * 0.02)
                }
            }
            if let e = l.entity("jellyLines", Ink.line) { j.body.addChild(e) }
        } else {
            var m = UnlitMaterial(color: ui(col))
            if let tx = Tex.get("jelly_bell", color: look == .color) {
                var tp = MaterialParameters.Texture(tx); tp.sampler = Tex.tiling
                m.color = .init(tint: ui(col * (0.75 + 0.35 * glowK)), texture: tp)
            }
            if let mk = Tex.get("jelly_bell_a", raw: true) {
                var mp = MaterialParameters.Texture(mk); mp.sampler = Tex.tiling
                m.blending = .transparent(opacity: .init(scale: 0.55 + 0.35 * glowK, texture: mp))
                m.writesDepth = false                 // 반투명 판이 뒤의 나무·물건을 네모나게 지우지 않게
            } else {
                m.blending = .transparent(opacity: .init(floatLiteral: 0.4))
                m.writesDepth = false                 // 반투명 판이 뒤의 나무·물건을 네모나게 지우지 않게
            }
            if let e = bell.entity("jellyBell", m) { j.body.addChild(e); j.bell = e }
            // 갓 속 빛 (속이 은은하게 빛남)
            var cm = UnlitMaterial(color: ui(col * 0.6 + SIMD3<Float>(repeating: 0.4)))
            cm.blending = .transparent(opacity: .init(scale: 0.25 + 0.4 * glowK))
            cm.writesDepth = false                 // 반투명 판이 뒤의 나무·물건을 네모나게 지우지 않게
            let core = ModelEntity(mesh: .generateSphere(radius: s * 0.32), materials: [cm])
            core.position = [0, s * 0.38, 0]
            core.scale = [1, 0.7, 1]
            j.body.addChild(core)
            j.core = core
        }
        // 촉수: 가장자리에서 아래로 길게 (마디마다 조금씩 늦게 흔들려 물결)
        let nT = j.inside ? 10 : 8
        let kT = j.inside ? 5 : 4
        let tentLen = s * Float.random(in: 3.2...5.0, using: &g)
        let tentMat = stripMat("jelly_tent", col, alpha: line ? 1 : 0.55 + 0.3 * glowK)
        for i in 0..<nT {
            let a = Float(i) / Float(nT) * 2 * .pi + Float.random(in: -0.1...0.1, using: &g)
            let start = SIMD3<Float>(cos(a) * s * 0.93, s * 0.04, sin(a) * s * 0.93)
            j.tentacles.append(chain(at: start, length: tentLen * Float.random(in: 0.75...1.1, using: &g), width: max(0.003, s * 0.035),
                                     parts: kT, mat: tentMat, tex: "jelly_tent", into: j.body))
        }
        // 입팔: 가운데에서 넓고 주름진 띠 4개
        let armMat = stripMat("jelly_arm", col * 0.9 + SIMD3<Float>(repeating: 0.1), alpha: line ? 1 : 0.6 + 0.25 * glowK)
        for i in 0..<4 {
            let a = Float(i) / 4 * 2 * .pi + 0.4
            let start = SIMD3<Float>(cos(a) * s * 0.12, s * 0.2, sin(a) * s * 0.12)
            j.arms.append(chain(at: start, length: s * Float.random(in: 1.6...2.6, using: &g), width: s * 0.22,
                                parts: j.inside ? 4 : 3, mat: armMat, tex: "jelly_arm", into: j.body))
        }
        if inside { localRoot.addChild(j.e) } else { root.addChild(j.e) }
        jellies.append(j)
    }

    private func stripMat(_ tex: String, _ col: SIMD3<Float>, alpha: Float) -> RealityKit.Material {
        if look == .line { return Ink.line }
        let c = UIColor(red: CGFloat(min(1, col.x)), green: CGFloat(min(1, col.y)), blue: CGFloat(min(1, col.z)), alpha: 1)
        var m = UnlitMaterial(color: c)
        if let tx = Tex.get(tex, color: look == .color) {
            var tp = MaterialParameters.Texture(tx); tp.sampler = Tex.clamp
            m.color = .init(tint: c, texture: tp)
        }
        if let mk = Tex.get(tex + "_a", raw: true) {
            var mp = MaterialParameters.Texture(mk); mp.sampler = Tex.clamp
            m.blending = .transparent(opacity: .init(scale: alpha, texture: mp))
            m.writesDepth = false                 // 반투명 판이 뒤의 나무·물건을 네모나게 지우지 않게
        } else {
            m.blending = .transparent(opacity: .init(scale: alpha * 0.6))
            m.writesDepth = false                 // 반투명 판이 뒤의 나무·물건을 네모나게 지우지 않게
        }
        return m
    }

    /// 마디가 이어진 띠 (위 끝이 매달린 곳). 마디마다 그림의 세로 구간을 나눠 씀
    private func chain(at start: SIMD3<Float>, length: Float, width: Float, parts: Int, mat: RealityKit.Material, tex: String, into parent: Entity) -> [Entity] {
        var out: [Entity] = []
        var holder: Entity = parent
        let segL = length / Float(parts)
        for k in 0..<parts {
            let pivot = Entity()
            pivot.position = k == 0 ? start : SIMD3<Float>(0, -segL, 0)
            var q = Geo()
            let v0 = 1 - Float(k) / Float(parts), v1 = 1 - Float(k + 1) / Float(parts)
            let w = width * (1 - 0.5 * Float(k) / Float(parts))
            for rot in [Float(0), .pi / 2] {
                let ax = SIMD3<Float>(cos(rot), 0, sin(rot)) * (w / 2)
                q.quad(-ax, ax, ax + SIMD3<Float>(0, -segL, 0), -ax + SIMD3<Float>(0, -segL, 0),
                       SIMD2<Float>(0, v0), SIMD2<Float>(1, v0), SIMD2<Float>(1, v1), SIMD2<Float>(0, v1))
            }
            if let e = q.entity("jellyStrip", mat) { pivot.addChild(e) }
            holder.addChild(pivot)
            out.append(pivot)
            holder = pivot
        }
        return out
    }

    /// 바다눈: 아주 작은 빛 알갱이가 천천히 떠다님 (방 안과 둘레)
    private func addPlankton() {
        for inRoom in [true, false] {
        var pe = ParticleEmitterComponent()
        pe.emitterShape = .box
        // 방 안: 방 크기만큼 (실제 공간 쪽) / 방 밖: 둘레 넓게 (하늘 세계)
        pe.emitterShapeSize = inRoom ? [reach * 0.9, max(0.6, ceilY - floorY - 0.3), reach * 0.9] : [reach * 2 + 14, max(0.6, ceilY - floorY) + 3, reach * 2 + 14]
        pe.birthLocation = .volume
        pe.birthDirection = .world
        pe.emissionDirection = [0, 1, 0]
        pe.speed = 0.015
        pe.speedVariation = 0.012
        pe.mainEmitter.birthRate = 30
        pe.mainEmitter.lifeSpan = 12
        pe.mainEmitter.size = 0.007
        pe.mainEmitter.sizeVariation = 0.004
        pe.mainEmitter.noiseStrength = 0.02
        pe.mainEmitter.noiseScale = 1.5
        pe.mainEmitter.noiseAnimationSpeed = 0.2
        if look == .line {
            pe.mainEmitter.color = .constant(.single(UIColor(white: 0.25, alpha: 0.6)))
            pe.mainEmitter.blendMode = .alpha
        } else {
            pe.mainEmitter.color = .constant(.single(look == .mono ? UIColor(white: 0.9, alpha: CGFloat(0.25 + 0.55 * glowK))
                                                     : UIColor(red: 0.7, green: 0.92, blue: 1, alpha: CGFloat(0.25 + 0.55 * glowK))))
            pe.mainEmitter.blendMode = .additive
        }
        pe.mainEmitter.opacityCurve = .gradualFadeInOut
        if let im = Tex.particle("spark_dot") { pe.mainEmitter.image = im }
        let e = Entity()
        e.components.set(pe)
        e.position = SIMD3<Float>(center.x, (floorY + ceilY) / 2, center.z)
        if inRoom { localRoot.addChild(e) } else { root.addChild(e) }
        }
    }

    // MARK: 매 프레임
    func tick(_ dt: Float) {
        t += dt
        var g = SystemRandomNumberGenerator()
        for j in jellies {
            // 숨쉬기: 오므라드는 동안(주기의 앞 30%) 갓이 좁아지고 길어지며 위로 밀려 오름
            let ph = (t / j.period + j.phase).truncatingRemainder(dividingBy: 1)
            let squeeze: Float = ph < 0.3 ? sin(ph / 0.3 * .pi) : 0
            let relax: Float = ph >= 0.3 ? sin((ph - 0.3) / 0.7 * .pi) * 0.25 : 0
            j.bell?.scale = SIMD3<Float>(1 - 0.16 * squeeze + 0.04 * relax, 1 + 0.12 * squeeze, 1 - 0.16 * squeeze + 0.04 * relax)
            j.core?.scale = SIMD3<Float>(1 - 0.1 * squeeze, 0.7 + 0.08 * squeeze, 1 - 0.1 * squeeze)
            // 길 찾기: 가끔 새 목표(높이도 새로) — 그쪽으로 천천히 헤엄쳐 감. 위로는 갓을 오므릴 때마다 밀려 오르고, 쉬는 동안 천천히 가라앉음
            j.retarget -= dt
            if j.retarget <= 0 || simd_distance(j.pos, j.target) < 0.2 {
                j.retarget = Float.random(in: 7...13, using: &g)
                if j.inside {
                    if let p = insideSpot(&g) { j.target = p }
                } else {
                    let a = Float.random(in: 0...(2 * .pi), using: &g)
                    var p = j.pos + SIMD3<Float>(cos(a) * 2.5, Float.random(in: -1.2...1.2, using: &g), sin(a) * 2.5)
                    let off = SIMD2<Float>(p.x - worldC.x, p.z - worldC.z)
                    let r = simd_length(off)
                    if r > worldR + 12 { p.x = worldC.x + off.x / r * (worldR + 10); p.z = worldC.z + off.y / r * (worldR + 10) }
                    if nearHouse(p) { p = j.pos }
                    p.y = min(floorY + 5, max(floorY + 1.2, p.y))
                    j.target = p
                }
            }
            let speed: Float = j.inside ? 0.075 : 0.2
            let to = j.target - j.pos
            let hd = SIMD3<Float>(to.x, 0, to.z)
            let hl = simd_length(hd)
            var want = hl > 0.001 ? hd / hl * speed * min(1, hl / 0.6) : SIMD3<Float>(0, 0, 0)
            // 위아래: 목표 높이 쪽으로 + 숨쉬기(오므릴 때 위로 밀림, 쉬면 가라앉음) — 늘 조금씩 오르내림
            want.y = max(-0.06, min(0.06, to.y * 0.12)) * (j.inside ? 1 : 2.2)
            want.y += (squeeze * 0.16 - 0.035) * (j.inside ? 1 : 2.4)
            if j.inside, let h = head {
                let away = j.pos - h
                let d = simd_length(away)
                if d < 0.9 {                                                // 머리 가까이 오면 비켜 감
                    want += simd_normalize(away + SIMD3<Float>(0, 0.0001, 0)) * (0.9 - d) * 0.5
                    if d < 0.65 { j.target = j.pos + simd_normalize(SIMD3<Float>(away.x, 0.2, away.z) + SIMD3<Float>(0.0001, 0, 0)) * 1.2 }
                }
            }
            j.vel += (want - j.vel) * min(1, dt * 0.9)
            var np = j.pos + j.vel * dt
            if j.inside {
                if !insideOK(np) { j.vel.x *= -0.4; j.vel.z *= -0.4; np.x = j.pos.x; np.z = j.pos.z; j.retarget = 0 }
                if np.y < lo || np.y > hi { j.vel.y *= -0.3 }
                np.y = min(hi, max(lo, np.y))
            } else if nearHouse(np) {
                np.x = j.pos.x; np.z = j.pos.z; j.retarget = 0
            }
            j.pos = np
            j.e.position = np
            // 갓은 가는 쪽으로 살짝 기울고(위가 앞), 천천히 돌아감
            let wantUp = simd_normalize(SIMD3<Float>(0, 1, 0) + SIMD3<Float>(j.vel.x, 0, j.vel.z) * 6)
            j.up = simd_normalize(j.up + (wantUp - j.up) * min(1, dt * 0.8))
            let tilt = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: j.up)
            j.body.orientation = tilt * simd_quatf(angle: t * 0.08 + j.phase * 6, axis: [0, 1, 0])
            // 촉수·입팔: 마디마다 늦게 따라오는 물결 + 움직임 반대쪽으로 끌림
            let drag = SIMD3<Float>(-j.vel.z, 0, j.vel.x) * 2.5
            for (ti, ch) in j.tentacles.enumerated() {
                let a = Float(ti) * 0.9 + j.phase * 7
                let axis = simd_normalize(SIMD3<Float>(cos(a), 0, sin(a)))
                for (k, seg) in ch.enumerated() {
                    let w = sin(t * 1.6 - Float(k) * 0.8 + a) * (0.12 + 0.05 * Float(k)) + squeeze * 0.18 * (k == 0 ? 1 : 0.3)
                    seg.orientation = simd_quatf(angle: w, axis: axis) * simd_quatf(angle: simd_length(drag) * 0.4, axis: simd_length(drag) > 0.001 ? simd_normalize(drag) : axis)
                }
            }
            for (ai, ch) in j.arms.enumerated() {
                let a = Float(ai) * 1.6 + j.phase * 5
                let axis = simd_normalize(SIMD3<Float>(cos(a), 0, sin(a)))
                for (k, seg) in ch.enumerated() {
                    seg.orientation = simd_quatf(angle: sin(t * 0.9 - Float(k) * 0.9 + a) * 0.18, axis: axis)
                }
            }
            // 빛무리는 나를 향하고, 숨쉴 때 조금 밝아짐
            if let h = j.halo, let hp = head {
                let to = hp - np
                h.orientation = simd_quatf(angle: atan2(to.x, to.z), axis: [0, 1, 0])
                h.scale = SIMD3<Float>(repeating: 0.88 + 0.22 * squeeze + 0.05 * sin(t * 0.7 + j.phase * 9))      // 오므릴 때 환해짐 + 느린 숨결
            }
        }
    }
}
