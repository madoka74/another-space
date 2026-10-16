import Foundation
import UIKit
import RealityKit
import simd

/// 방 하나의 다른 세계.
/// - 하늘 세계(WorldComponent): 하늘 구, 땅, 구름, 벽 너머로 솟은 숲·절벽·건물. 천장(포털)과 창문(포털)으로만 보임
/// - 방 안(실제 공간): 바닥, 실내 장소의 유리 지붕 틀, 비·눈·바람·반딧불
@MainActor
final class RoomWorld {
    let room: RoomRec
    let style: WorldStyle
    let world = Entity()            // 포털 너머 세계
    let local = Entity()            // 방 안 효과 (저장 좌표)
    private(set) var tint: SIMD3<Float>
    private var skyEntity: ModelEntity?
    private var skyMat: UnlitMaterial?
    private var flashMat: UnlitMaterial?
    private var clouds: [(Entity, SIMD3<Float>)] = []
    private var emitters: [Entity] = []
    private var flashLeft: Float = 0
    private(set) var center = SIMD3<Float>(0, 0, 0)         // 방 가운데 바닥 (저장 좌표)
    private(set) var halfSize = SIMD2<Float>(1, 1)           // 방 반 크기 (격자 방향, m)
    let angle: Float

    var outdoor: Bool { !style.skylight }

    init(_ d: SpaceData, _ r: RoomRec) {
        room = r
        style = Worlds.style(r.place, time: r.time)
        angle = d.rec.angle
        // 밤·폭우라도 벽과 가구가 알아볼 수 있을 만큼은 밝게 (안전)
        tint = simd_max(Worlds.timeTint(r.time, indoor: Worlds.indoor(r.place)) * Worlds.weatherDim(r.weather), SIMD3<Float>(0.32, 0.33, 0.4))
        world.components.set(WorldComponent())
        build(d)
    }

    // MARK: 만들기
    private func build(_ d: SpaceData) {
        let rec = d.rec
        let floorY = rec.floorY
        let ceilY = floorY + room.ceil
        if let b = d.bounds(of: room.id) {
            let cu = Float(b.0 + b.2) / 2, cv = Float(b.1 + b.3) / 2
            let c = rec.world(cu, cv)
            center = SIMD3<Float>(c.x, floorY, c.y)
            halfSize = SIMD2<Float>(Float(b.2 - b.0), Float(b.3 - b.1)) * rec.cell / 2
        }
        let rects = d.rects(of: room.id)
        let wide = d.rects(mask: d.mask(room.id, grow: 2))     // 벽 밑까지 20cm 더 (틈으로 현실이 보이지 않게)

        // 바닥 (방 모양, 바닥 위 6mm)
        if let m = Self.flatMesh(wide, rec: rec, y: floorY + 0.006, tile: style.floorTile) {
            let e = ModelEntity(mesh: m, materials: [Tex.unlit(style.floor, tint: style.floorTint * tint)])
            local.addChild(e)
        }
        // 천장 = 하늘 세계로 열린 창 (천장보다 3cm 아래)
        if let m = Self.flatMesh(wide, rec: rec, y: ceilY - 0.03, tile: 1) {
            let p = ModelEntity(mesh: m, materials: [PortalMaterial()])
            p.components.set(PortalComponent(target: world))
            local.addChild(p)
        }
        if style.skylight { addSkylightFrame(rects, rec: rec, y: ceilY - 0.06) }

        // 하늘 세계
        let skyTex = Worlds.skyName(time: room.time, weather: room.weather)
        if let sphere = Self.skySphere(radius: 300) {
            let wd = Worlds.weatherDim(room.weather)
            let base = Tex.unlit(skyTex, tint: [1, 1, 1] * max(0.75, wd), folder: "sky", tiled: false)
            let bright = Tex.unlit(skyTex, tint: [2.4, 2.4, 2.6], folder: "sky", tiled: false)
            let s = ModelEntity(mesh: sphere, materials: [base])
            s.position = center
            world.addChild(s)
            skyEntity = s; skyMat = base; flashMat = bright
        }
        let ground = ModelEntity(mesh: .generatePlane(width: 900, depth: 900), materials: [UnlitMaterial(color: Tex.color(style.ground * tint))])
        ground.position = center + SIMD3<Float>(0, -0.05, 0)
        world.addChild(ground)
        addClouds(ceilY: ceilY)
        addSkyline(rec: rec, floorY: floorY)

        // 날씨 효과
        let w = room.weather
        if ["drizzle", "rain", "storm", "snow", "heavysnow"].contains(w) {
            // 하늘 세계에도 (천장 너머로 내려오는 게 보이게)
            let e = Self.precip(w, size: SIMD3<Float>(halfSize.x * 2 + 4, 0.1, halfSize.y * 2 + 4), height: 8)
            e.position = SIMD3<Float>(center.x, ceilY + 8, center.z)
            e.orientation = simd_quatf(angle: -angle, axis: [0, 1, 0])
            world.addChild(e)
        }
        if outdoor {
            for r in rects.sorted(by: { ($0.2 - $0.0) * ($0.3 - $0.1) > ($1.2 - $1.0) * ($1.3 - $1.1) }).prefix(5) {
                let cu = Float(r.0 + r.2) / 2, cv = Float(r.1 + r.3) / 2
                let c = rec.world(cu, cv)
                let sx = Float(r.2 - r.0) * rec.cell, sz = Float(r.3 - r.1) * rec.cell
                guard sx * sz > 0.4 else { continue }
                var list: [Entity] = []
                if ["drizzle", "rain", "storm", "snow", "heavysnow"].contains(w) {
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
        setActive(false)
    }

    /// 지금 이 방에 있을 때만 입자를 뿜음 (다른 방은 쉼)
    func setActive(_ on: Bool) {
        for e in emitters {
            if var pe = e.components[ParticleEmitterComponent.self], pe.isEmitting != on {
                pe.isEmitting = on
                e.components.set(pe)
            }
        }
    }

    /// 매 프레임: 구름 흐름, 번개
    func tick(_ dt: Float, active: Bool) {
        guard active else { return }
        for (e, v) in clouds {
            e.position += v * dt
            let off = e.position - center
            if abs(off.x) > 180 { e.position.x = center.x - copysign(170, off.x) }
            if abs(off.z) > 180 { e.position.z = center.z - copysign(170, off.z) }
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

    // MARK: 하늘 세계 꾸미기
    private func addClouds(ceilY: Float) {
        let n = Worlds.cloudCount(room.weather)
        let dark: Float = room.weather == "storm" ? 0.45 : (["rain", "drizzle"].contains(room.weather) ? 0.7 : 1)
        let wind: Float = room.weather == "wind" || room.weather == "storm" ? 6 : 2
        let dir = simd_normalize(SIMD3<Float>(Float.random(in: -1...1), 0, Float.random(in: -1...1)) + SIMD3<Float>(0.01, 0, 0))
        for i in 0..<n {
            var m = UnlitMaterial(color: .white)
            if let t = Tex.get("cloud_\(i % 3)", folder: "sky") {
                m.color = .init(tint: Tex.color(SIMD3<Float>(repeating: 1) * tint * dark, alpha: 1), texture: .init(t))
            }
            m.blending = .transparent(opacity: .init(floatLiteral: room.weather == "clear" ? 0.65 : 0.9))
            let e = ModelEntity(mesh: .generatePlane(width: Float.random(in: 60...130), depth: Float.random(in: 40...80)), materials: [m])
            e.orientation = simd_quatf(angle: .pi, axis: [1, 0, 0]) * simd_quatf(angle: Float.random(in: 0...(2 * .pi)), axis: [0, 1, 0])
            e.position = center + SIMD3<Float>(Float.random(in: -160...160), ceilY - center.y + Float.random(in: 55...110), Float.random(in: -160...160))
            world.addChild(e)
            clouds.append((e, dir * wind * Float.random(in: 0.7...1.3)))
        }
    }

    /// 벽 너머로 솟은 것들 (천장·창으로 보임). 방 둘레를 바깥으로 둘러 배치
    private func addSkyline(rec: SpaceRec, floorY: Float) {
        var g = SeededRNG(seed: UInt64(room.id * 7919 + room.place.count * 31))
        let ex = rec.ex, ez = rec.ez
        let c2 = center.xz
        /// 방 둘레 바깥 d m 지점 (둘레를 t(0~1)로 한 바퀴)
        func around(_ t: Float, _ d: Float) -> SIMD3<Float> {
            let hx = halfSize.x + d, hz = halfSize.y + d
            let per = 4 * (hx + hz)
            var s = t * per
            var lu: Float = 0, lv: Float = 0
            if s < 2 * hx { lu = -hx + s; lv = -hz }
            else if s < 2 * hx + 2 * hz { s -= 2 * hx; lu = hx; lv = -hz + s }
            else if s < 4 * hx + 2 * hz { s -= 2 * hx + 2 * hz; lu = hx - s; lv = hz }
            else { s -= 4 * hx + 2 * hz; lu = -hx; lv = hz - s }
            let p = c2 + ex * lu + ez * lv
            return SIMD3<Float>(p.x, floorY, p.y)
        }
        let k = tint
        func mat(_ col: SIMD3<Float>) -> UnlitMaterial { UnlitMaterial(color: Tex.color(col * k)) }
        switch style.skyline {
        case .pines:
            let trunk = mat([0.22, 0.16, 0.11]), needles = mat([0.10, 0.20, 0.12]), needles2 = mat([0.13, 0.25, 0.14])
            for i in 0..<34 {
                let p = around(Float(i) / 34 + Float.random(in: 0...0.02, using: &g), Float.random(in: 0.8...7, using: &g))
                let h = Float.random(in: 9...17, using: &g)
                pine(at: p, h: h, trunk: trunk, needles: i % 2 == 0 ? needles : needles2)
            }
        case .trees:
            let trunk = mat([0.25, 0.18, 0.12]), leaf = mat([0.17, 0.30, 0.13]), leaf2 = mat([0.22, 0.36, 0.16])
            for i in 0..<26 {
                let p = around(Float(i) / 26 + Float.random(in: 0...0.03, using: &g), Float.random(in: 1...8, using: &g))
                let h = Float.random(in: 7...13, using: &g)
                let t = ModelEntity(mesh: .generateCylinder(height: h, radius: 0.3), materials: [trunk])
                t.position = p + SIMD3<Float>(0, h / 2, 0)
                world.addChild(t)
                let r = Float.random(in: 2.5...4.2, using: &g)
                let c = ModelEntity(mesh: .generateSphere(radius: r), materials: [i % 2 == 0 ? leaf : leaf2])
                c.position = p + SIMD3<Float>(0, h + r * 0.4, 0)
                c.scale = [1, 0.85, 1]
                world.addChild(c)
            }
        case .cliffs:
            let rock = Tex.unlit("cliff", tint: style.wallTint * k, tiled: false)
            for i in 0..<16 {
                let p = around(Float(i) / 16 + Float.random(in: 0...0.04, using: &g), Float.random(in: 1.5...9, using: &g))
                let h = Float.random(in: 16...38, using: &g)
                let b = ModelEntity(mesh: .generateBox(width: Float.random(in: 6...14, using: &g), height: h,
                                                         depth: Float.random(in: 4...9, using: &g)), materials: [rock])
                b.position = p + SIMD3<Float>(0, h / 2, 0)
                b.orientation = simd_quatf(angle: Float.random(in: 0...(2 * .pi), using: &g), axis: [0, 1, 0])
                world.addChild(b)
            }
        case .hills:
            let hill = mat([0.20, 0.30, 0.16]), far = mat([0.30, 0.38, 0.40])
            for i in 0..<9 {
                let a = Float(i) / 9 * 2 * .pi + Float.random(in: 0...0.3, using: &g)
                let r = Float.random(in: 60...110, using: &g)
                let d = Float.random(in: 150...230, using: &g)
                let s = ModelEntity(mesh: .generateSphere(radius: r), materials: [i % 3 == 0 ? far : hill])
                s.position = center + SIMD3<Float>(cos(a) * d, -r * 0.55, sin(a) * d)
                s.scale = [1, 0.55, 1]
                world.addChild(s)
            }
            let trunk = mat([0.25, 0.18, 0.12]), leaf = mat([0.20, 0.32, 0.14])
            for i in 0..<8 {
                let p = around(Float(i) / 8 + Float.random(in: 0...0.06, using: &g), Float.random(in: 2...9, using: &g))
                let h = Float.random(in: 6...9, using: &g)
                let t = ModelEntity(mesh: .generateCylinder(height: h, radius: 0.28), materials: [trunk])
                t.position = p + SIMD3<Float>(0, h / 2, 0)
                world.addChild(t)
                let c = ModelEntity(mesh: .generateSphere(radius: 3), materials: [leaf])
                c.position = p + SIMD3<Float>(0, h + 1.2, 0)
                world.addChild(c)
            }
        case .city, .lowCity:
            let night = room.time == "night" || room.time == "dawn"
            let face = Tex.unlit(night ? "facade_night" : "facade", tint: (night ? SIMD3<Float>(1, 1, 1) : k), tiled: false)
            let low = style.skyline == .lowCity
            for i in 0..<22 {
                let p = around(Float(i) / 22 + Float.random(in: 0...0.03, using: &g), Float.random(in: 3...22, using: &g))
                let h = low ? Float.random(in: 8...18, using: &g) : Float.random(in: 18...75, using: &g)
                let b = ModelEntity(mesh: .generateBox(width: Float.random(in: 8...18, using: &g), height: h,
                                                         depth: Float.random(in: 8...18, using: &g)), materials: [face])
                b.position = p + SIMD3<Float>(0, h / 2, 0)
                b.orientation = simd_quatf(angle: -angle + (i % 2 == 0 ? 0 : 0.1), axis: [0, 1, 0])
                world.addChild(b)
            }
        case .sea:
            // 탁 트인 바다: 멀리 섬 몇 개만
            let isle = mat([0.16, 0.22, 0.20])
            for i in 0..<3 {
                let a = Float.random(in: 0...(2 * .pi), using: &g) + Float(i)
                let r = Float.random(in: 20...45, using: &g)
                let s = ModelEntity(mesh: .generateSphere(radius: r), materials: [isle])
                s.position = center + SIMD3<Float>(cos(a) * 220, -r * 0.7, sin(a) * 220)
                s.scale = [1.6, 0.5, 1]
                world.addChild(s)
            }
        case .none:
            break
        }
    }

    private func pine(at p: SIMD3<Float>, h: Float, trunk: UnlitMaterial, needles: UnlitMaterial) {
        let t = ModelEntity(mesh: .generateCylinder(height: h * 0.45, radius: 0.28), materials: [trunk])
        t.position = p + SIMD3<Float>(0, h * 0.225, 0)
        world.addChild(t)
        for (k, (y, r, hh)) in [(0.3, 2.6, 0.45), (0.55, 2.0, 0.38), (0.78, 1.3, 0.3)].enumerated() {
            let c = ModelEntity(mesh: .generateCone(height: h * Float(hh), radius: Float(r) * (0.8 + Float(k) * 0.05)), materials: [needles])
            c.position = p + SIMD3<Float>(0, h * Float(y) + h * Float(hh) / 2, 0)
            world.addChild(c)
        }
    }

    /// 실내 장소: 유리 지붕 틀 (1m 간격 가는 들보)
    private func addSkylightFrame(_ rects: [(Int, Int, Int, Int)], rec: SpaceRec, y: Float) {
        let m = UnlitMaterial(color: Tex.color(SIMD3<Float>(0.18, 0.15, 0.12) * tint))
        let q = simd_quatf(angle: -angle, axis: [0, 1, 0])
        let step = 10
        for r in rects {
            // u 방향 들보 (v가 10칸마다)
            for v in stride(from: (r.1 / step + 1) * step, to: r.3, by: step) {
                let len = Float(r.2 - r.0) * rec.cell
                guard len > 0.3 else { continue }
                let c = rec.world(Float(r.0 + r.2) / 2, Float(v))
                let b = ModelEntity(mesh: .generateBox(width: len, height: 0.07, depth: 0.05), materials: [m])
                b.position = SIMD3<Float>(c.x, y, c.y)
                b.orientation = q
                local.addChild(b)
            }
            // v 방향 들보 (u가 10칸마다)
            for u in stride(from: (r.0 / step + 1) * step, to: r.2, by: step) {
                let len = Float(r.3 - r.1) * rec.cell
                guard len > 0.3 else { continue }
                let c = rec.world(Float(u), Float(r.1 + r.3) / 2)
                let b = ModelEntity(mesh: .generateBox(width: 0.05, height: 0.07, depth: len), materials: [m])
                b.position = SIMD3<Float>(c.x, y, c.y)
                b.orientation = q
                local.addChild(b)
            }
        }
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
    static func flatMesh(_ rects: [(Int, Int, Int, Int)], rec: SpaceRec, y: Float, tile: Float) -> MeshResource? {
        guard !rects.isEmpty else { return nil }
        var pos: [SIMD3<Float>] = [], uv: [SIMD2<Float>] = [], idx: [UInt32] = []
        for r in rects {
            let corners = [rec.world(Float(r.0), Float(r.1)), rec.world(Float(r.2), Float(r.1)),
                           rec.world(Float(r.2), Float(r.3)), rec.world(Float(r.0), Float(r.3))]
            let b = UInt32(pos.count)
            for c in corners {
                pos.append(SIMD3<Float>(c.x, y, c.y))
                uv.append(SIMD2<Float>(c.x / tile, c.y / tile))
            }
            idx += [b, b + 1, b + 2, b, b + 2, b + 3, b, b + 2, b + 1, b, b + 3, b + 2]
        }
        var d = MeshDescriptor(name: "flat")
        d.positions = MeshBuffers.Positions(pos)
        d.textureCoordinates = MeshBuffers.TextureCoordinates(uv)
        d.primitives = .triangles(idx)
        return try? MeshResource.generate(from: [d])
    }

    /// 안쪽에서 보는 하늘 구 (등장방형 그림, 양면)
    static func skySphere(radius: Float) -> MeshResource? {
        let seg = 48, rings = 24
        var pos: [SIMD3<Float>] = [], uv: [SIMD2<Float>] = [], idx: [UInt32] = []
        for r in 0...rings {
            let el = Float.pi / 2 - Float.pi * Float(r) / Float(rings)
            for s in 0...seg {
                let az = 2 * Float.pi * Float(s) / Float(seg)
                pos.append(radius * SIMD3<Float>(cos(el) * cos(az), sin(el), cos(el) * sin(az)))
                uv.append(SIMD2<Float>(Float(s) / Float(seg), 0.5 + el / Float.pi))
            }
        }
        for r in 0..<rings {
            for s in 0..<seg {
                let a = UInt32(r * (seg + 1) + s), b = a + UInt32(seg + 1)
                idx += [a, b, a + 1, a + 1, b, b + 1]          // 안쪽 면
                idx += [a, a + 1, b, a + 1, b + 1, b]          // 바깥 면 (방향이 뒤집혀도 보이게)
            }
        }
        var d = MeshDescriptor(name: "sky")
        d.positions = MeshBuffers.Positions(pos)
        d.textureCoordinates = MeshBuffers.TextureCoordinates(uv)
        d.primitives = .triangles(idx)
        return try? MeshResource.generate(from: [d])
    }
}
