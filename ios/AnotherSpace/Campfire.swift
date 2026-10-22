import Foundation
import UIKit
import RealityKit
import simd

/// 캠핑장 불멍: 앉으면 앞의 평평한 빈 바닥에 모닥불이 피어오르고, 일어나면 불이 사그라들며 연기가 하늘로 흩어지고 사라짐.
/// 시간·날씨에 따라 모습이 다름 —
/// - 밤: 불길이 크고 밝음, 불티가 많이 날리고 둘레 바닥이 주황빛으로 일렁임. 연기는 어둠에 거의 안 보임
/// - 해질녘·새벽: 그 중간 / 낮: 불빛은 약하고 연기가 잘 보임
/// - 가랑비·비·폭우: 불이 작아지고 숨이 가빠짐(폭우면 꺼질 듯 말 듯), 하얀 김이 피어오르고 치익 소리, 돌이 젖어 어두움
/// - 눈·함박눈: 불 둘레 눈이 녹아 흙이 드러나고, 옅은 김
/// - 바람·폭우: 불길·연기·불티가 바람 쪽으로 기울고 가끔 확 휘청임
/// 흑백은 밝기만, 선 그림은 흰 종이 위 검은 선·짙은 불꽃으로
@MainActor
final class Campfire {
    let root = Entity()
    private(set) var done = false
    private(set) var dying = false

    private let look: LookMode
    private let wind: SIMD3<Float>          // 바람 방향 (저장 좌표, 바람 없으면 0)
    private let windK: Float
    private let size: Float                 // 불 크기 (비면 작아짐)
    private let glowK: Float                // 바닥 불빛 세기 (밤일수록)
    private let sputter: Float              // 숨 가쁨 (비·폭우)
    private let storm: Bool

    private var flames: [(Entity, Float, Float)] = []    // 불꽃, 흔들림 위상, 크기
    private var flameCards: [(ModelEntity, Int)] = []      // 일렁이는 불길 그림 판, 시작 장
    private var frameMats: [UnlitMaterial] = []            // 불길 16장
    private var frameT: Float = 0
    private var logs: [ModelEntity] = []
    private var logT: Float = 0
    private var emberE = Entity()
    private var nextPop: Float = 3
    private var popT: Float = -1
    private let wetFire: Bool
    private let flameRoot = Entity()
    private var glow: ModelEntity?
    private var ember: ModelEntity?
    private let remains = Entity()          // 돌·장작·숯 (꺼질 때 천천히 사라짐)
    private var fireE = Entity(), sparkE = Entity(), smokeE = Entity(), steamE = Entity()
    /// 천장 너머(하늘 세계)로 이어 오르는 연기: 방 안 연기는 천장에 닿기 전에 옅어지고, 같은 자리 천장 위에서 다시 피어 하늘로 흩어짐
    private let skySmokeE = Entity()
    private var skyRate: Float = 0
    private var amt: Float = 0
    private var t: Float = 0
    private var dieT: Float = 0
    private var gust: Float = 0
    private var gustGoal: Float = 0
    private var nextGust: Float = 2
    private var loop: AudioPlaybackController?
    private var hiss: AudioPlaybackController?
    private var baseRates: (Float, Float, Float, Float) = (0, 0, 0, 0)  // 불·불티·연기·김 (처음 정한 양)

    /// base: 불 자리 바닥 (저장 좌표), windDir: 바람이 부는 쪽 (저장 좌표 수평)
    init(at base: SIMD3<Float>, room: RoomRec, look: LookMode, windDir: SIMD3<Float>, ceilH: Float = 2.5, sky: Entity? = nil, scale k: Float = 1) {
        self.look = look
        let w = room.weather, tm = room.time
        wetFire = ["drizzle", "rain", "storm"].contains(w)
        let night = tm == "night"
        let twilight = tm == "dusk" || tm == "dawn"
        let wet = ["drizzle", "rain", "storm"].contains(w)
        let snowy = w == "snow" || w == "heavysnow"
        storm = w == "storm"
        switch w {
        case "storm": windK = 1
        case "wind": windK = 0.75
        default: windK = 0.12
        }
        wind = simd_length(windDir) > 0.01 ? simd_normalize(SIMD3<Float>(windDir.x, 0, windDir.z)) : SIMD3<Float>(1, 0, 0)
        switch w {
        case "drizzle": size = 0.82
        case "rain": size = 0.66
        case "storm": size = 0.55
        case "snow", "heavysnow": size = 0.9
        default: size = 1
        }
        switch w {
        case "storm": sputter = 0.45
        case "rain": sputter = 0.25
        case "drizzle": sputter = 0.12
        default: sputter = 0
        }
        var gk: Float = 0.16
        if night { gk = 0.8 } else if twilight { gk = 0.5 }
        glowK = look == .line ? 0 : gk
        let line = look == .line
        root.position = base

        // 둘레 돌 (젖으면 어둡게, 눈이면 밝게)
        var stones = Geo()
        var g = SeededRNG(seed: UInt64(abs(Int(base.x * 100)) * 31 + abs(Int(base.z * 100)) + 7))
        for k in 0..<11 {
            let a = Float(k) / 11 * 2 * .pi + Float.random(in: -0.1...0.1, using: &g)
            let r = Float.random(in: 0.38...0.44, using: &g)
            stones.rock(at: SIMD3<Float>(cos(a) * r, 0, sin(a) * r), size: Float.random(in: 0.08...0.12, using: &g), using: &g)
        }
        var stoneTint = SIMD3<Float>(0.82, 0.8, 0.76)
        if wet { stoneTint = SIMD3<Float>(0.5, 0.48, 0.46) } else if snowy { stoneTint = SIMD3<Float>(0.95, 0.95, 0.97) }
        let stoneM: RealityKit.Material = line ? Ink.paper(1) : Tex.with(look) { Tex.unlit("rock", tint: stoneTint, folder: "tex", sampler: Tex.tiling) }
        if let e = stones.entity("fireStones", stoneM) { remains.addChild(e) }
        // 눈: 불기운에 녹아 드러난 흙 / 비: 젖어 짙은 흙
        if snowy || wet {
            var d = Geo()
            d.disc(center: SIMD3<Float>(0, 0.011, 0), radius: snowy ? 0.8 : 0.6, tile: 0.8, segments: 40)
            let dirtTint = wet ? SIMD3<Float>(0.5, 0.45, 0.4) : SIMD3<Float>(0.75, 0.68, 0.6)
            let dm: RealityKit.Material = line ? Ink.paper(2) : Tex.with(look) { Tex.unlit("dirt", tint: dirtTint, folder: "tex", sampler: Tex.tiling) }
            if let e = d.entity("fireGround", dm) { remains.addChild(e) }
        }
        // 장작: 원뿔처럼 세운 네 개 + 밑에 엇갈려 누운 두 개
        // 장작: 겉은 검게 타고 갈라진 틈에 불씨가 숨 쉼 (밝기가 일렁임)
        let logM: RealityKit.Material = line ? Ink.paper(1) : Tex.with(look) { Tex.unlit("charlog", tint: [1, 1, 1], folder: "tex", sampler: Tex.tiling) }
        for k in 0..<4 {
            let a = Float(k) / 4 * 2 * .pi + 0.4
            let log = ModelEntity(mesh: .generateCylinder(height: 0.46 * size + 0.08, radius: 0.035), materials: [logM])
            let out = SIMD3<Float>(cos(a), 0, sin(a))
            log.position = out * 0.1 + SIMD3<Float>(0, 0.19 * size + 0.03, 0)
            log.orientation = simd_quatf(angle: -0.42, axis: simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), out)))
            remains.addChild(log)
            logs.append(log)
        }
        for (k, a) in [Float(0.3), Float(1.9)].enumerated() {
            let log = ModelEntity(mesh: .generateCylinder(height: 0.5, radius: 0.045), materials: [logM])
            log.orientation = simd_quatf(angle: a, axis: [0, 1, 0]) * simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
            log.position = [0, 0.045 + Float(k) * 0.05, 0]
            remains.addChild(log)
            logs.append(log)
        }
        if line {
            var l = Geo()
            for k in 0..<11 {
                let a0 = Float(k) / 11 * 2 * .pi, a1 = Float(k + 1) / 11 * 2 * .pi
                l.stroke(SIMD3<Float>(cos(a0) * 0.48, 0.01, sin(a0) * 0.48), SIMD3<Float>(cos(a1) * 0.48, 0.01, sin(a1) * 0.48), width: 0.008)
            }
            if let e = l.entity("fireLines", Ink.line) { remains.addChild(e) }
        }
        // 숯불 (장작 밑에서 붉게 숨 쉼)
        var em: ModelEntity? = nil
        if !line {
            var q = Geo()
            let R: Float = 0.28
            q.quad(SIMD3<Float>(-R, 0.022, -R), SIMD3<Float>(R, 0.022, -R), SIMD3<Float>(R, 0.022, R), SIMD3<Float>(-R, 0.022, R),
                   SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(1, 1), SIMD2<Float>(0, 1))
            var m = UnlitMaterial(color: Tex.with(look) { Tex.color([1, 0.38, 0.1]) })
            if let tx = Tex.get("glow", color: look == .color), let mask = Tex.get("glow_a", raw: true) {
                var p = MaterialParameters.Texture(tx); p.sampler = Tex.clamp
                m.color = .init(tint: Tex.with(look) { Tex.color([1, 0.45, 0.15]) }, texture: p)
                var mp = MaterialParameters.Texture(mask); mp.sampler = Tex.clamp
                m.blending = .transparent(opacity: .init(scale: 1, texture: mp))
            }
            em = q.entity("ember", m)
        }
        ember = em
        if let em { remains.addChild(em) }
        root.addChild(remains)

        // 바닥 불빛 (밤일수록 넓고 진하게 일렁임)
        var gl: ModelEntity? = nil
        if glowK > 0 {
            var q = Geo()
            let R: Float = 1.1 + 0.9 * glowK
            q.quad(SIMD3<Float>(-R, 0.016, -R), SIMD3<Float>(R, 0.016, -R), SIMD3<Float>(R, 0.016, R), SIMD3<Float>(-R, 0.016, R),
                   SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(1, 1), SIMD2<Float>(0, 1))
            var m = UnlitMaterial(color: Tex.with(look) { Tex.color([1, 0.6, 0.3]) })
            if let tx = Tex.get("glow", color: look == .color), let mask = Tex.get("glow_a", raw: true) {
                var p = MaterialParameters.Texture(tx); p.sampler = Tex.clamp
                m.color = .init(tint: Tex.with(look) { Tex.color([1, 0.7, 0.45]) }, texture: p)
                var mp = MaterialParameters.Texture(mask); mp.sampler = Tex.clamp
                m.blending = .transparent(opacity: .init(scale: 1, texture: mp))
            }
            gl = q.entity("fireGlow", m)
        }
        glow = gl
        if let gl { gl.components.set(OpacityComponent(opacity: 0)); root.addChild(gl) }

        // 불길: 일렁이는 불 그림 16장을 판마다 다른 장에서 시작해 넘김 (가운데 큰 불 + 둘레 작은 불혀). 그림이 없으면 예전 불꽃 모양
        let inkC = UIColor(white: 0.12, alpha: 1)
        for f in 0..<16 {
            let nm = String(format: "fire_%02d", f)
            guard let mask = Tex.get(nm + "_a", raw: true) else { break }
            var m = UnlitMaterial(color: line ? inkC : .white)
            if !line, let tx = Tex.with(look, { Tex.get(nm) }) {
                var p = MaterialParameters.Texture(tx); p.sampler = Tex.clamp
                m.color = .init(tint: .white, texture: p)
            }
            var mp = MaterialParameters.Texture(mask); mp.sampler = Tex.clamp
            m.blending = .transparent(opacity: .init(scale: line ? 0.85 : 1, texture: mp))
            frameMats.append(m)
        }
        var flameM = UnlitMaterial(color: line ? inkC : Tex.with(look) { Tex.color([1, 0.75, 0.35]) })
        if let tx = Tex.get("flame", color: look == .color) {
            var p = MaterialParameters.Texture(tx); p.sampler = Tex.clamp
            flameM.color = .init(tint: line ? inkC : .white, texture: p)
        }
        if let mask = Tex.get("flame_a", raw: true) {
            var p = MaterialParameters.Texture(mask); p.sampler = Tex.clamp
            flameM.blending = .transparent(opacity: .init(scale: 1, texture: p))
        }
        let spots: [(SIMD2<Float>, Float)] = [([0, 0], 0.78), ([0.02, 0.01], 0.66), ([0.09, 0.04], 0.46), ([-0.08, 0.06], 0.44),
                                               ([0.02, -0.09], 0.42), ([-0.06, -0.05], 0.34), ([0.11, -0.06], 0.3), ([-0.11, 0.0], 0.28)]
        for (k, sp) in spots.enumerated() {
            let h = sp.1 * size
            var q = Geo()
            q.crossTree(at: .zero, width: h * 0.5, height: h, yaw: Float(k) * 0.7)
            let start = (k * 5) % 16
            guard let fl = q.entity("flame", frameMats.isEmpty ? flameM : frameMats[start]) else { continue }
            let holder = Entity()
            holder.position = SIMD3<Float>(sp.0.x, 0.03, sp.0.y)
            holder.addChild(fl)
            holder.scale = SIMD3<Float>(repeating: 0.05)
            flameRoot.addChild(holder)
            flames.append((holder, Float(k) * 1.37 + Float.random(in: 0...1, using: &g), h))
            if !frameMats.isEmpty { flameCards.append((fl, start)) }
        }
        flameRoot.components.set(OpacityComponent(opacity: tm == "morning" || tm == "afternoon" ? 0.85 : 1))
        root.addChild(flameRoot)
        // 자리에 맞춘 크기 (좁으면 작은 모닥불): 돌·장작·숯·불길·바닥 불빛을 함께 줄임
        remains.scale = SIMD3<Float>(repeating: k)
        flameRoot.scale = SIMD3<Float>(repeating: k)
        glow?.scale = SIMD3<Float>(repeating: max(0.5, k))

        // 입자 크기도 불 크기(자리에 맞춘 단계)에 맞춤
        let ps = size * k
        // 입자: 불 알갱이 · 불티 · 연기 · 김
        let hot1 = Tex.with(look) { Tex.color([1, 0.85, 0.4]) }, hot2 = Tex.with(look) { Tex.color([0.95, 0.28, 0.05]) }
        let sp1 = Tex.with(look) { Tex.color([1, 0.9, 0.5]) }, sp2 = Tex.with(look) { Tex.color([1, 0.35, 0.08]) }
        let drift = wind * windK
        let fr: Float = 80 * ps
        var fire = ParticleEmitterComponent()
        fire.emitterShape = .box
        fire.emitterShapeSize = [0.26 * ps, 0.04, 0.26 * ps]
        fire.birthLocation = .volume
        fire.birthDirection = .world
        fire.emissionDirection = [0, 1, 0]
        fire.speed = 0.45 * ps + 0.1
        fire.speedVariation = 0.2
        fire.mainEmitter.birthRate = fr
        fire.mainEmitter.lifeSpan = 0.75
        fire.mainEmitter.size = 0.09 * ps
        fire.mainEmitter.sizeMultiplierAtEndOfLifespan = 0.15
        fire.mainEmitter.acceleration = drift * 0.9
        if line {
            fire.mainEmitter.color = .constant(.single(UIColor(white: 0.15, alpha: 0.8)))
            fire.mainEmitter.blendMode = .alpha
        } else {
            fire.mainEmitter.color = .evolving(start: .single(hot1), end: .single(hot2))
            fire.mainEmitter.blendMode = .additive
        }
        fire.mainEmitter.opacityCurve = .quickFadeInOut
        fire.isEmitting = false

        var sr: Float = 5
        if night { sr = 16 } else if twilight { sr = 10 }
        if wet { sr *= 0.4 }
        if windK > 0.5 { sr *= 1.5 }
        var spark = ParticleEmitterComponent()
        spark.emitterShape = .sphere
        spark.emitterShapeSize = [0.12, 0.05, 0.12]
        spark.birthDirection = .world
        spark.emissionDirection = [0, 1, 0]
        spark.speed = 0.9
        spark.speedVariation = 0.5
        spark.mainEmitter.birthRate = sr
        spark.mainEmitter.lifeSpan = 2.2
        spark.mainEmitter.lifeSpanVariation = 0.8
        spark.mainEmitter.size = line ? 0.01 : 0.007
        spark.mainEmitter.sizeMultiplierAtEndOfLifespan = 0.3
        spark.mainEmitter.acceleration = drift * 0.8 + SIMD3<Float>(0, 0.1, 0)
        spark.mainEmitter.noiseStrength = 0.35
        spark.mainEmitter.noiseScale = 1.5
        spark.mainEmitter.noiseAnimationSpeed = 0.6
        if line {
            spark.mainEmitter.color = .constant(.single(UIColor(white: 0.1, alpha: 1)))
            spark.mainEmitter.blendMode = .alpha
        } else {
            spark.mainEmitter.color = .evolving(start: .single(sp1), end: .single(sp2))
                spark.mainEmitter.blendMode = .additive
        }
        if let im = Tex.get("spark_dot", color: true) { spark.mainEmitter.image = im }
        spark.mainEmitter.opacityCurve = .linearFadeOut
        spark.isEmitting = false

        // 연기: 낮엔 잘 보이는 회색, 밤엔 불빛 받은 옅은 갈색, 비 오면 더 많고 하얗게
        var smokeA: CGFloat = 0.32
        if night { smokeA = 0.14 } else if twilight { smokeA = 0.22 }
        let smokeC: SIMD3<Float> = wet ? [0.82, 0.82, 0.84] : (night ? [0.42, 0.34, 0.3] : [0.55, 0.55, 0.57])
        var mr: Float = wet ? 7 : 4
        if w == "storm" { mr *= 1.3 }
        var smoke = ParticleEmitterComponent()
        smoke.emitterShape = .sphere
        smoke.emitterShapeSize = [0.1, 0.05, 0.1]
        smoke.birthDirection = .world
        smoke.emissionDirection = [0, 1, 0]
        smoke.speed = 0.34
        smoke.speedVariation = 0.1
        smoke.mainEmitter.birthRate = mr
        // 천장(하늘로 열린 창)에 닿기 전에 옅어지게: 천장 25cm 아래까지 오를 시간만큼만 삶 → 창에 걸려 잘리거나 뭉치지 않음
        let rise = max(0.6, ceilH - 0.55 - 0.25)
        smoke.mainEmitter.lifeSpan = Double(min(4.2, max(1.6, rise / 0.4)))
        smoke.mainEmitter.lifeSpanVariation = 0.4
        smoke.mainEmitter.size = 0.12
        smoke.mainEmitter.sizeMultiplierAtEndOfLifespan = 3.6
        smoke.mainEmitter.acceleration = drift * 0.45 + SIMD3<Float>(0, 0.02, 0)
        smoke.mainEmitter.noiseStrength = 0.16
        smoke.mainEmitter.noiseScale = 1.2
        smoke.mainEmitter.noiseAnimationSpeed = 0.25
        let smokeCol: UIColor = line ? UIColor(white: 0.45, alpha: 0.18) : Tex.with(look) { Tex.color(smokeC, alpha: smokeA) }
        smoke.mainEmitter.color = .constant(.single(smokeCol))
        smoke.mainEmitter.blendMode = .alpha
        smoke.mainEmitter.opacityCurve = .quickFadeInOut
        let puff = Tex.get("smoke_puff", color: true)
        if let puff {
            smoke.mainEmitter.image = puff
            smoke.mainEmitter.angularSpeed = 0.4
            smoke.mainEmitter.angularSpeedVariation = 0.6
        }
        // 하늘 쪽: 천장 바로 위에서 이어 피어 바람 따라 옅게 퍼지며 사라짐 (한곳에 뭉치지 않게 크게 퍼뜨리고 아주 옅게)
        if let sky {
            var ss = ParticleEmitterComponent()
            ss.emitterShape = .sphere
            ss.emitterShapeSize = [0.25, 0.1, 0.25]
            ss.birthDirection = .world
            ss.emissionDirection = [0, 1, 0]
            ss.speed = 0.4
            ss.speedVariation = 0.15
            skyRate = mr * 0.7
            ss.mainEmitter.birthRate = skyRate
            ss.mainEmitter.lifeSpan = 9
            ss.mainEmitter.lifeSpanVariation = 2
            ss.mainEmitter.size = 0.45
            ss.mainEmitter.sizeMultiplierAtEndOfLifespan = 7
            ss.mainEmitter.acceleration = drift * 0.9 + SIMD3<Float>(0, 0.015, 0)
            ss.mainEmitter.noiseStrength = 0.35
            ss.mainEmitter.noiseScale = 0.6
            ss.mainEmitter.noiseAnimationSpeed = 0.2
            let skyCol: UIColor = line ? UIColor(white: 0.45, alpha: 0.1) : Tex.with(look) { Tex.color(smokeC, alpha: smokeA * 0.55) }
            ss.mainEmitter.color = .constant(.single(skyCol))
            ss.mainEmitter.blendMode = .alpha
            ss.mainEmitter.opacityCurve = .gradualFadeInOut
            if let puff {
                ss.mainEmitter.image = puff
                ss.mainEmitter.angularSpeed = 0.25
                ss.mainEmitter.angularSpeedVariation = 0.4
            }
            ss.isEmitting = false
            skySmokeE.components.set(ss)
            skySmokeE.position = base + SIMD3<Float>(0, ceilH + 0.15, 0)
            sky.addChild(skySmokeE)
        }
        smoke.isEmitting = false

        // 김: 비·눈이 불에 닿아 하얗게 피어오름
        var tr: Float = 0
        if wet { tr = w == "storm" ? 18 : 12 } else if snowy { tr = 6 }
        var steam = ParticleEmitterComponent()
        steam.emitterShape = .box
        steam.emitterShapeSize = [0.5, 0.02, 0.5]
        steam.birthLocation = .volume
        steam.birthDirection = .world
        steam.emissionDirection = [0, 1, 0]
        steam.speed = 0.55
        steam.speedVariation = 0.2
        steam.mainEmitter.birthRate = tr
        steam.mainEmitter.lifeSpan = 1.6
        steam.mainEmitter.size = 0.05
        steam.mainEmitter.sizeMultiplierAtEndOfLifespan = 5
        steam.mainEmitter.acceleration = drift * 0.6
        steam.mainEmitter.color = .constant(.single(line ? UIColor(white: 0.5, alpha: 0.15) : UIColor(white: 0.95, alpha: 0.22)))
        steam.mainEmitter.blendMode = .alpha
        steam.mainEmitter.opacityCurve = .gradualFadeInOut
        if let puff { steam.mainEmitter.image = puff }

        // 숯불 알갱이: 장작 밑에서 작은 불씨가 살짝 떠올랐다 사라짐
        var emb = ParticleEmitterComponent()
        emb.emitterShape = .box
        emb.emitterShapeSize = [0.32 * ps, 0.02, 0.32 * ps]
        emb.birthLocation = .volume
        emb.birthDirection = .world
        emb.emissionDirection = [0, 1, 0]
        emb.speed = 0.05
        emb.speedVariation = 0.04
        var er: Float = night ? 30 : 14
        if wet { er *= 0.5 }
        emb.mainEmitter.birthRate = er
        emb.mainEmitter.lifeSpan = 1.4
        emb.mainEmitter.lifeSpanVariation = 0.6
        emb.mainEmitter.size = 0.005
        emb.mainEmitter.noiseStrength = 0.05
        if line {
            emb.mainEmitter.color = .constant(.single(UIColor(white: 0.15, alpha: 1)))
            emb.mainEmitter.blendMode = .alpha
        } else {
            emb.mainEmitter.color = .evolving(start: .single(sp1), end: .single(sp2))
            emb.mainEmitter.blendMode = .additive
        }
        if let im = Tex.get("spark_dot", color: true) { emb.mainEmitter.image = im }
        emb.mainEmitter.opacityCurve = .quickFadeInOut
        emb.isEmitting = false
        steam.isEmitting = false

        baseRates = (fr, sr, mr, tr)
        for (e, pe, y) in [(fireE, fire, Float(0.06)), (sparkE, spark, Float(0.25)), (smokeE, smoke, Float(0.55)), (steamE, steam, Float(0.15)),
                           (emberE, emb, Float(0.03))] {
            e.components.set(pe)
            e.position = [0, y * k, 0]
            root.addChild(e)
        }

        // 소리: 장작 타는 소리 (그 자리에서 또렷하게), 비 오면 치익 소리를 겹침
        loop = Self.playLoop("fire_loop", in: root, gain: wet ? -3 : 0)
        if wet || snowy {
            var hg: Double = -5
            if storm { hg = -2 } else if snowy { hg = -10 }
            hiss = Self.playLoop("fire_hiss", in: root, gain: hg)
        }
    }

    private static func playLoop(_ name: String, in e: Entity, gain: Double) -> AudioPlaybackController? {
        guard let u = Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "sfx") else { return nil }
        let cfg = AudioFileResource.Configuration(loadingStrategy: .preload, shouldLoop: true)
        guard let r = try? AudioFileResource.load(contentsOf: u, withName: nil, configuration: cfg) else { return nil }
        let holder = Entity()
        var sa = SpatialAudioComponent()
        sa.gain = 0
        holder.components.set(sa)
        holder.position = [0, 0.3, 0]
        e.addChild(holder)
        let c = holder.playAudio(r)
        c.gain = -60
        c.fade(to: gain, duration: 2.0)
        return c
    }

    private func setRate(_ e: Entity, _ rate: Float, on: Bool) {
        guard var pe = e.components[ParticleEmitterComponent.self] else { return }
        pe.mainEmitter.birthRate = rate
        pe.isEmitting = on && rate > 0
        e.components.set(pe)
    }

    /// 일어남: 불이 사그라들고 연기가 한 번 크게 오른 뒤 하늘로 흩어지며 사라짐
    func die() {
        guard !dying else { return }
        dying = true
        dieT = 0
        setRate(fireE, 0, on: false)
        setRate(sparkE, 0, on: false)
        if var pe = emberE.components[ParticleEmitterComponent.self] { pe.isEmitting = false; emberE.components.set(pe) }
        setRate(smokeE, baseRates.2 * 3 + 6, on: true)            // 꺼지며 연기가 확 오름
        setRate(skySmokeE, skyRate * 3 + 4, on: true)
        setRate(steamE, baseRates.3 > 0 ? baseRates.3 * 1.5 : 8, on: true)
        loop?.fade(to: -60, duration: 2.5)
        hiss?.fade(to: -60, duration: 2.5)
        Sfx.play("fire_out", in: root, at: [0, 0.3, 0], gain: -4)
    }

    /// 다시 앉음 (꺼지는 중이면 다시 살아남)
    func revive() {
        guard dying, !done else { return }
        dying = false
        remains.components.set(OpacityComponent(opacity: 1))
        setRate(smokeE, baseRates.2, on: true)
        setRate(skySmokeE, skyRate, on: true)
        setRate(steamE, baseRates.3, on: true)
        setRate(fireE, baseRates.0, on: true)
        setRate(sparkE, baseRates.1, on: true)
        if var pe = emberE.components[ParticleEmitterComponent.self] { pe.isEmitting = true; emberE.components.set(pe) }
        loop?.fade(to: 0, duration: 1.5)
        hiss?.fade(to: -5, duration: 1.5)
    }

    func tick(_ dt: Float) {
        guard !done else { return }
        t += dt
        if !dying {
            let before = amt
            amt = min(1, amt + dt / 1.4)                           // 바로 불씨가 보이고 1.4초쯤 걸려 커짐
            if before < 0.15 && amt >= 0.15 {
                setRate(fireE, baseRates.0, on: true)
                setRate(sparkE, baseRates.1, on: true)
                setRate(smokeE, baseRates.2, on: true)
                setRate(skySmokeE, skyRate, on: true)
                setRate(steamE, baseRates.3, on: true)
                if var pe = emberE.components[ParticleEmitterComponent.self] { pe.isEmitting = true; emberE.components.set(pe) }
            }
            // 장작이 탁 튐: 불티가 한 번에 확 오르고 '탁' 소리 (비 오면 드물게)
            if amt > 0.6 && t > nextPop {
                nextPop = t + Float.random(in: wetFire ? 6...14 : 2.5...7)
                popT = t
                setRate(sparkE, baseRates.1 * 10 + 30, on: true)
                Sfx.play("fire_pop\(Int.random(in: 1...3))", in: root, at: [Float.random(in: -0.1...0.1), 0.15, Float.random(in: -0.1...0.1)], gain: wetFire ? -10 : -4)
            }
            if popT > 0 && t - popT > 0.15 {
                popT = -1
                setRate(sparkE, baseRates.1, on: true)
            }
        } else {
            dieT += dt
            amt = max(0, amt - dt / 2.0)
            if dieT > 1.5 && dieT - dt <= 1.5 {
                setRate(smokeE, 0, on: false)                    // 남은 연기는 하늘로 올라가며 흩어짐
                setRate(steamE, 0, on: false)
            }
            let fadeR = max(0, 1 - max(0, dieT - 1.0) / 3.5)
            remains.components.set(OpacityComponent(opacity: fadeR))
            if dieT > 3.0 && dieT - dt <= 3.0 { setRate(skySmokeE, 0, on: false) }
            if dieT > 8.5 {
                loop?.stop(); hiss?.stop()
                root.removeFromParent()
                let sk = skySmokeE                                // 하늘 연기는 마저 흩어진 뒤 정리
                Task { try? await Task.sleep(for: .seconds(11)); sk.removeFromParent() }
                done = true
                return
            }
        }
        // 바람에 휘청 (폭우·바람: 가끔 확)
        if t > nextGust {
            nextGust = t + Float.random(in: 1.5...4.5)
            gustGoal = windK > 0.5 ? Float.random(in: 0.3...1) : Float.random(in: 0...0.3)
        }
        gust += (gustGoal - gust) * min(1, dt * 2.5)
        if abs(gust - gustGoal) < 0.05 { gustGoal *= 0.5 }
        let lean = windK * (0.25 + 0.35 * gust)
        let axis = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), wind))
        // 비가 세면 불이 숨 가쁘게 줄었다 커졌다
        let breath = 1 - sputter * (0.5 + 0.5 * sin(t * 1.7) * sin(t * 0.63 + 1.1))
        // 불길 그림 넘기기 (초당 18장) + 장작 불씨 밝기 일렁임
        frameT += dt
        if !frameMats.isEmpty && frameT > 1.0 / 18 {
            frameT = 0
            let step = Int(t * 18)
            for (card, start) in flameCards { card.model?.materials = [frameMats[(start + step) % frameMats.count]] }
        }
        logT += dt
        if look != .line && logT > 0.12 {
            logT = 0
            let k: Float = dying ? max(0.45, 1 - dieT / 4) : 0.85 + 0.3 * (0.5 + 0.5 * sin(t * 2.3) * sin(t * 0.9 + 1))
            let m = Tex.with(look) { Tex.unlit("charlog", tint: SIMD3<Float>(k, k * 0.95, k * 0.9), folder: "tex", sampler: Tex.tiling) }
            for l in logs { l.model?.materials = [m] }
        }
        for (e, ph, _) in flames {
            let k = (0.78 + 0.22 * sin(t * 9 + ph) * sin(t * 5.3 + ph * 2)) * breath * amt
            e.scale = SIMD3<Float>(max(0.001, amt) * (1 + 0.08 * sin(t * 7 + ph)), max(0.001, k), max(0.001, amt))
            e.orientation = simd_quatf(angle: lean + 0.07 * sin(t * 3.1 + ph), axis: axis) * simd_quatf(angle: 0.06 * sin(t * 2.3 + ph), axis: [1, 0, 0])
        }
        if let gl = glow {
            let f = 0.85 + 0.15 * sin(t * 11) * sin(t * 4.7 + 0.6)
            gl.components.set(OpacityComponent(opacity: glowK * amt * f * breath))
        }
        if let em = ember {
            let f: Float = dying ? max(0, 1 - dieT / 3) : 0.75 + 0.25 * sin(t * 1.3)
            em.components.set(OpacityComponent(opacity: f))
        }
    }

    /// 탐험을 끝낼 때
    func remove() {
        loop?.stop(); hiss?.stop()
        root.removeFromParent()
        skySmokeE.removeFromParent()
        done = true
    }
}
