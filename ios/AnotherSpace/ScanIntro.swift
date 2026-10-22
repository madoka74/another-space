import Foundation
import UIKit
import RealityKit
import simd

/// 효과음 (앱 안 sfx/ — 빌드할 때 tools/make_assets.py 가 만듦)
@MainActor
enum Sfx {
    private static var cache: [String: AudioFileResource] = [:]

    private static func res(_ name: String) -> AudioFileResource? {
        if let r = cache[name] { return r }
        guard let u = Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "sfx") else { return nil }
        let cfg = AudioFileResource.Configuration(loadingStrategy: .preload, shouldLoop: false)
        guard let r = try? AudioFileResource.load(contentsOf: u, withName: nil, configuration: cfg) else { return nil }
        cache[name] = r
        return r
    }

    /// 미리 읽어 둠 (처음 울릴 때 늦지 않게)
    static func preload() { for n in ["key_appear", "key_turn", "door_open", "scan", "fire_out", "cat_trill", "cat_chirp", "cat_meow1", "cat_meow2", "cat_meow3", "cat_mrrp1", "cat_mrrp2", "cat_mrrp3", "bell1", "bell2", "bell3", "star_chime", "fire_pop1", "dog_bark1", "dog_yip1", "dog_yip2", "dog_tag1", "dog_tag2", "dog_sniff"] { _ = res(n) } }

    /// 그 자리에서 나는 소리 (parent 기준 위치)
    static func play(_ name: String, in parent: Entity, at p: SIMD3<Float>, gain: Double) {
        guard let r = res(name) else { return }
        let e = Entity()
        var sa = SpatialAudioComponent()
        sa.gain = gain
        e.components.set(sa)
        e.position = p
        parent.addChild(e)
        e.playAudio(r)
        Task { try? await Task.sleep(for: .seconds(5)); e.removeFromParent() }
    }

    /// 머리에 붙은 소리 (공간 전체에 퍼지는 효과)
    static func playHead(_ name: String, in parent: Entity, gain: Double) {
        guard let r = res(name) else { return }
        let e = Entity()
        var ca = ChannelAudioComponent()
        ca.gain = gain
        e.components.set(ca)
        parent.addChild(e)
        e.playAudio(r)
        Task { try? await Task.sleep(for: .seconds(6)); e.removeFromParent() }
    }
}

/// 탐험 시작 연출: 서 있는 곳에서부터 집 전체의 바닥·벽·천장에 초록 격자가 파도처럼 퍼져 나가며 공간을 '스캔'하고,
/// 방 안에 데이터 비가 내린 뒤, 두 번째 파도가 지나가며 격자가 걷히고 그 자리에 다른 세계가 드러남 (약 3.5초)
@MainActor
final class ScanIntro {
    let root = Entity()                       // 저장 좌표 (탐험 세션이 지금 좌표로 옮겨 붙임)
    private var bands: [(ModelEntity, Float)] = []      // 띠(서 있는 곳에서 50cm씩 떨어진 거리), 거리(m)
    private var rain: [Entity] = []
    private(set) var t: Float = 0
    static let speed: Float = 5          // 파도 빠르기 (m/초)
    static let reveal: Float = 1.5       // 두 번째 파도(격자가 걷히고 세계가 드러남)가 시작하는 때

    var done: Bool { t > Self.reveal + maxDist / Self.speed + 0.8 }
    private var maxDist: Float = 0

    /// 세계가 보이는 정도 (0~1): 두 번째 파도와 함께 드러남
    var world: Float {
        let x = min(1, max(0, (t - Self.reveal) / 1.0))
        return x * x * (3 - 2 * x)
    }

    init(_ L: Layout, head: SIMD2<Float>, floorY: Float, current: Int) {
        let step: Float = 0.5
        var geos: [Int: Geo] = [:]
        func band(_ p: SIMD2<Float>) -> Int { Int(simd_distance(p, head) / step) }
        // 벽: 50cm 조각마다
        for s in L.walls {
            let len = simd_distance(s.a, s.b)
            guard len > 0.01 else { continue }
            let dir = (s.b - s.a) / len
            let top = L.ceil[min(255, max(0, s.room))]
            let n3 = { () -> SIMD3<Float> in let n = L.flat(s.n) - L.flat(SIMD2<Float>(0, 0)); return SIMD3<Float>(n.x, 0, n.y) }()
            var a: Float = 0
            while a < len - 1e-4 {
                let b = min(len, a + step)
                let pa = s.a + dir * a, pb = s.a + dir * b
                let wa = L.flat(pa), wb = L.flat(pb)
                let k = band((pa + pb) / 2)
                var g = geos[k] ?? Geo()
                let along0 = abs(s.a.x - s.b.x) > abs(s.a.y - s.b.y) ? s.a.x : s.a.y
                g.face(SIMD3<Float>(wa.x, floorY, wa.y), SIMD3<Float>(wb.x, floorY, wb.y), toward: n3, y0: 0.005, y1: top - 0.01,
                       u0: (along0 + a) / step, u1: (along0 + b) / step, v0: 0, v1: top / step)
                geos[k] = g
                a = b
            }
        }
        // 바닥·천장: 방마다 50cm 칸
        for rid in Set(L.walls.map(\.room)) where rid > 0 {
            let top = L.ceil[min(255, rid)]
            for r in L.rects(rid) {
                var u = r.0.x
                while u < r.1.x - 1e-4 {
                    let u1 = min(r.1.x, u + step)
                    var v = r.0.y
                    while v < r.1.y - 1e-4 {
                        let v1 = min(r.1.y, v + step)
                        let k = band(SIMD2<Float>((u + u1) / 2, (v + v1) / 2))
                        var g = geos[k] ?? Geo()
                        let c = [L.flat(SIMD2<Float>(u, v)), L.flat(SIMD2<Float>(u1, v)), L.flat(SIMD2<Float>(u1, v1)), L.flat(SIMD2<Float>(u, v1))]
                        let uv = [SIMD2<Float>(u, v), SIMD2<Float>(u1, v), SIMD2<Float>(u1, v1), SIMD2<Float>(u, v1)].map { $0 / step }
                        for y in [floorY + 0.01, floorY + top - 0.03] {
                            let p = c.map { SIMD3<Float>($0.x, y, $0.y) }
                            g.quad(p[0], p[1], p[2], p[3], uv[0], uv[1], uv[2], uv[3])
                        }
                        geos[k] = g
                        v = v1
                    }
                    u = u1
                }
            }
        }
        let mat = Self.material()
        for (k, g) in geos {
            guard let e = g.entity("scan\(k)", mat) else { continue }
            e.components.set(OpacityComponent(opacity: 0))
            e.isEnabled = false
            root.addChild(e)
            let d = Float(k) * step
            bands.append((e, d))
            maxDist = max(maxDist, d)
        }
        // 지금 방에 내리는 데이터 비 (초록 빛 알갱이가 빠르게 떨어짐)
        for r in L.rects(current) {
            let sx = r.1.x - r.0.x, sz = r.1.y - r.0.y
            guard sx > 0.3, sz > 0.3 else { continue }
            let c = L.flat((r.0 + r.1) / 2)
            let top = L.ceil[min(255, max(0, current))]
            var pe = ParticleEmitterComponent()
            pe.emitterShape = .box
            pe.emitterShapeSize = [sx, 0.05, sz]
            pe.birthLocation = .volume
            pe.birthDirection = .world
            pe.emissionDirection = [0, -1, 0]
            pe.speed = 2.6
            pe.speedVariation = 0.8
            pe.mainEmitter.birthRate = min(1500, 260 * sx * sz)
            pe.mainEmitter.lifeSpan = Double(top / 2.6)
            pe.mainEmitter.size = 0.007
            pe.mainEmitter.sizeVariation = 0.003
            pe.mainEmitter.color = .constant(.single(UIColor(red: 0.45, green: 1, blue: 0.6, alpha: 1)))
            pe.mainEmitter.blendMode = .additive
            pe.mainEmitter.opacityCurve = .gradualFadeInOut
            let e = Entity()
            e.components.set(pe)
            e.position = SIMD3<Float>(c.x, floorY + top - 0.05, c.y)
            e.orientation = simd_quatf(angle: -atan2(L.ex.y, L.ex.x), axis: [0, 1, 0])
            root.addChild(e)
            rain.append(e)
        }
    }

    /// 투명도를 그림에서 읽는 빛나는 격자 (선은 또렷하게, 가는 보조선은 반투명)
    private static func material() -> UnlitMaterial {
        let tint = SIMD3<Float>(0.6, 1, 0.75)
        var m = Tex.unlit("scan_grid", tint: tint, folder: "tex", sampler: Tex.tiling)
        if let mask = Tex.get("scan_grid_a", folder: "tex", raw: true) {
            var p = MaterialParameters.Texture(mask)
            p.sampler = Tex.tiling
            m.blending = .transparent(opacity: .init(scale: 1, texture: p))
        } else {
            m.blending = .transparent(opacity: .init(floatLiteral: 0.5))
        }
        return m
    }

    func tick(_ dt: Float) {
        t += dt
        for (e, d) in bands {
            let t0 = d / Self.speed                          // 첫 파도가 닿는 때
            let t1 = Self.reveal + d / Self.speed            // 두 번째 파도가 닿는 때
            var o: Float = 0
            if t >= t0 {
                let up = min(1, (t - t0) / 0.18)
                let flash = max(0, 1 - (t - t0) / 0.35) * 0.4   // 파도 앞머리는 잠깐 더 밝게
                let down = t > t1 ? max(0, 1 - (t - t1) / 0.5) : 1
                o = min(1, up * (0.6 + flash)) * down
            }
            let on = o > 0.01
            if e.isEnabled != on { e.isEnabled = on }
            if on { e.components.set(OpacityComponent(opacity: o)) }
        }
        if t > 2.2 {
            for e in rain {
                if var pe = e.components[ParticleEmitterComponent.self], pe.isEmitting {
                    pe.isEmitting = false
                    e.components.set(pe)
                }
            }
        }
    }
}
