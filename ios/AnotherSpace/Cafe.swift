import Foundation
import UIKit
import RealityKit
import simd

/// 카페 배경 재즈: 앱에 담긴 재즈 조각들(저작권이 끝난 스탠다드·전통곡을 앱이 연주해 만든 것)을
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
    static let gain: Double = -13

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

/// 카페 테이블: 실제 가구 중 평평한 윗면(탁자·책상, 45cm~1.15m)에 커피잔·케이크·크루아상·촛불·화분·책을 올려 둠.
/// 내 둘레 3.5m 안을 2초마다 살펴 새로 알게 된 탁자에 차림을 놓고, 가구가 사라지면 치움. 따뜻한 음료는 김이 남, 해질녘·밤엔 촛불
@MainActor
final class CafeTables {
    let root = Entity()
    private var sets: [(SIMD2<Float>, Entity)] = []
    private var flames: [(Entity, Float)] = []
    private var scanT: Float = 1
    private var t: Float = 0
    private let look: LookMode
    private let time: String

    init(look: LookMode, time: String) {
        self.look = look
        self.time = time
    }

    private func mat(_ c: SIMD3<Float>) -> RealityKit.Material {
        look == .line ? Ink.paper(0) : UnlitMaterial(color: Tex.with(look) { Tex.color(c) })
    }

    func tick(_ dt: Float, head: SIMD3<Float>, floorY: Float, top: (SIMD2<Float>) -> Float?, inRoom: (SIMD2<Float>) -> Bool) {
        t += dt
        for (e, ph) in flames {
            let k = 0.85 + 0.15 * sin(t * 13 + ph) * sin(t * 7.1 + ph * 2)
            e.scale = SIMD3<Float>(1, k, 1)
        }
        scanT -= dt
        guard scanT <= 0 else { return }
        scanT = 2
        // 사라진 가구 위 차림은 치움
        sets.removeAll { s in
            if top(s.0) == nil { s.1.removeFromParent(); return true }
            return false
        }
        guard sets.count < 6 else { return }
        let me = SIMD2<Float>(head.x, head.z)
        var cands: [(SIMD2<Float>, Float, Float)] = []
        var dx: Float = -3.5
        while dx <= 3.5 {
            var dz: Float = -3.5
            while dz <= 3.5 {
                let p = me + SIMD2<Float>(dx, dz)
                let d = simd_length(SIMD2<Float>(dx, dz))
                if d < 3.5, inRoom(p), let h = top(p), h >= 0.45, h <= 1.15 { cands.append((p, h, d)) }
                dz += 0.2
            }
            dx += 0.2
        }
        cands.sort { $0.2 < $1.2 }
        for c in cands where sets.count < 6 {
            if sets.contains(where: { simd_distance($0.0, c.0) < 0.85 }) { continue }
            let e = makeSet()
            e.position = SIMD3<Float>(c.0.x, floorY + c.1, c.0.y)
            e.orientation = simd_quatf(angle: Float.random(in: 0...(2 * .pi)), axis: [0, 1, 0])
            root.addChild(e)
            sets.append((c.0, e))
        }
    }

    private func cyl(_ r: Float, _ h: Float, _ y: Float, _ x: Float, _ z: Float, _ m: RealityKit.Material, into p: Entity, lines: inout Geo) {
        let e = ModelEntity(mesh: .generateCylinder(height: h, radius: r), materials: [m])
        e.position = [x, y + h / 2, z]
        p.addChild(e)
        if look == .line {
            for yy in [y, y + h] {
                for k in 0..<14 {
                    let a0 = Float(k) / 14 * 2 * .pi, a1 = Float(k + 1) / 14 * 2 * .pi
                    lines.stroke(SIMD3<Float>(x + cos(a0) * r, yy, z + sin(a0) * r), SIMD3<Float>(x + cos(a1) * r, yy, z + sin(a1) * r), width: 0.003)
                }
            }
        }
    }

    private func makeSet() -> Entity {
        let root = Entity()
        var lines = Geo()
        let white = mat([0.97, 0.96, 0.93])
        let hot = time != "night" || Bool.random()
        let candle = time == "night" || time == "dusk" || time == "dawn"
        var kinds = ["latte", "espresso", "croissant", "cake", "plant", "book"].shuffled()
        if !kinds.prefix(2).contains("latte") && Bool.random() { kinds.insert("latte", at: 0) }
        var slots: [SIMD2<Float>] = [SIMD2<Float>(-0.1, 0), SIMD2<Float>(0.12, 0.05), SIMD2<Float>(0.02, -0.14)]
        if candle { kinds.insert("candle", at: 1) }
        for k in kinds.prefix(Int.random(in: 2...3)) {
            guard !slots.isEmpty else { break }
            let s = slots.removeFirst()
            switch k {
            case "latte", "espresso":
                let big = k == "latte"
                cyl(big ? 0.075 : 0.055, 0.008, 0, s.x, s.y, white, into: root, lines: &lines)
                cyl(big ? 0.042 : 0.03, big ? 0.065 : 0.045, 0.008, s.x, s.y, white, into: root, lines: &lines)
                let surf = ModelEntity(mesh: .generateCylinder(height: 0.002, radius: big ? 0.038 : 0.026), materials: [mat(big ? [0.62, 0.42, 0.28] : [0.28, 0.16, 0.09])])
                surf.position = [s.x, 0.008 + (big ? 0.065 : 0.045) - 0.004, s.y]
                root.addChild(surf)
                if big {
                    let art = ModelEntity(mesh: .generateCylinder(height: 0.002, radius: 0.016), materials: [mat([0.95, 0.9, 0.8])])
                    art.position = surf.position + [0, 0.001, 0]
                    art.scale = [1, 1, 1.4]
                    root.addChild(art)
                }
                let handle = ModelEntity(mesh: .generateBox(width: 0.008, height: 0.03, depth: 0.022), materials: [white])
                handle.position = [s.x + (big ? 0.05 : 0.036), 0.04, s.y]
                root.addChild(handle)
                if hot {
                    var pe = ParticleEmitterComponent()
                    pe.emitterShape = .point
                    pe.birthDirection = .world
                    pe.emissionDirection = [0, 1, 0]
                    pe.speed = 0.05
                    pe.speedVariation = 0.02
                    pe.mainEmitter.birthRate = 5
                    pe.mainEmitter.lifeSpan = 2.5
                    pe.mainEmitter.size = 0.015
                    pe.mainEmitter.sizeMultiplierAtEndOfLifespan = 4
                    pe.mainEmitter.noiseStrength = 0.02
                    pe.mainEmitter.color = .constant(.single(look == .line ? UIColor(white: 0.4, alpha: 0.25) : UIColor(white: 1, alpha: 0.3)))
                    pe.mainEmitter.opacityCurve = .gradualFadeInOut
                    if let puff = Tex.get("smoke_puff", color: true) { pe.mainEmitter.image = puff }
                    let se = Entity()
                    se.components.set(pe)
                    se.position = [s.x, 0.08, s.y]
                    root.addChild(se)
                }
            case "croissant", "cake":
                cyl(0.085, 0.01, 0, s.x, s.y, white, into: root, lines: &lines)
                if k == "croissant" {
                    let c = ModelEntity(mesh: .generateSphere(radius: 0.05), materials: [mat([0.82, 0.56, 0.26])])
                    c.position = [s.x, 0.03, s.y]
                    c.scale = [1.5, 0.55, 0.75]
                    root.addChild(c)
                } else {
                    let c = ModelEntity(mesh: .generateBox(width: 0.06, height: 0.06, depth: 0.09), materials: [mat([0.46, 0.27, 0.16])])
                    c.position = [s.x, 0.04, s.y]
                    root.addChild(c)
                    let cr = ModelEntity(mesh: .generateBox(width: 0.062, height: 0.012, depth: 0.092), materials: [mat([0.97, 0.92, 0.82])])
                    cr.position = [s.x, 0.076, s.y]
                    root.addChild(cr)
                    let berry = ModelEntity(mesh: .generateSphere(radius: 0.011), materials: [mat([0.82, 0.1, 0.16])])
                    berry.position = [s.x, 0.09, s.y]
                    root.addChild(berry)
                }
            case "candle":
                if look != .line {
                    var glass = UnlitMaterial(color: UIColor(white: 1, alpha: 1))
                    glass.blending = .transparent(opacity: .init(floatLiteral: 0.2))
                    let jar = ModelEntity(mesh: .generateCylinder(height: 0.08, radius: 0.035), materials: [glass])
                    jar.position = [s.x, 0.04, s.y]
                    root.addChild(jar)
                }
                cyl(0.026, 0.045, 0, s.x, s.y, mat([0.96, 0.92, 0.84]), into: root, lines: &lines)
                var fm = UnlitMaterial(color: look == .line ? UIColor(white: 0.15, alpha: 1) : Tex.with(look) { Tex.color([1, 0.8, 0.4]) })
                if let tx = Tex.get("flame", color: look == .color) {
                    var p = MaterialParameters.Texture(tx); p.sampler = Tex.clamp
                    fm.color = .init(tint: look == .line ? UIColor(white: 0.15, alpha: 1) : .white, texture: p)
                }
                if let mk = Tex.get("flame_a", raw: true) {
                    var p = MaterialParameters.Texture(mk); p.sampler = Tex.clamp
                    fm.blending = .transparent(opacity: .init(scale: 1, texture: p))
                }
                var q = Geo()
                q.crossTree(at: .zero, width: 0.016, height: 0.032, yaw: 0.3)
                if let f = q.entity("candleFlame", fm) {
                    let h = Entity()
                    h.position = [s.x, 0.047, s.y]
                    h.addChild(f)
                    root.addChild(h)
                    flames.append((h, Float.random(in: 0...6)))
                }
            case "plant":
                cyl(0.04, 0.07, 0, s.x, s.y, mat([0.72, 0.4, 0.26]), into: root, lines: &lines)
                let l = ModelEntity(mesh: .generateSphere(radius: 0.06), materials: [mat([0.26, 0.5, 0.24])])
                l.position = [s.x, 0.11, s.y]
                l.scale = [1, 0.8, 1]
                root.addChild(l)
            default:   // 책
                let colors: [SIMD3<Float>] = [[0.5, 0.16, 0.14], [0.14, 0.26, 0.42], [0.2, 0.36, 0.24]]
                let b = ModelEntity(mesh: .generateBox(width: 0.15, height: 0.028, depth: 0.21), materials: [mat(colors.randomElement() ?? [0.5, 0.2, 0.2])])
                b.position = [s.x, 0.014, s.y]
                b.orientation = simd_quatf(angle: Float.random(in: -0.4...0.4), axis: [0, 1, 0])
                root.addChild(b)
                if look == .line { lines.boxOutline(base: [s.x, 0, s.y], w: 0.15, d: 0.21, h: 0.028, yaw: 0, width: 0.003) }
            }
        }
        if let e = lines.entity("setLines", Ink.line) { root.addChild(e) }
        return root
    }

    func remove() {
        root.removeFromParent()
        sets.removeAll()
        flames.removeAll()
    }
}
