import Foundation
import UIKit
import RealityKit
import simd

/// 도시 테마의 특징: 네온사인.
/// 세 겹으로 공간감을 줌 — ① 옥상 난간에 붙은 작은 간판(눈높이, 손 닿을 듯 가까이) ② 옥상 바로 옆에 솟은 건물 벽의 큰 간판
/// ③ 아래 거리·먼 빌딩 벽에 가로·세로로 촘촘한 간판들.
/// 간판은 읽을 수 없는 글자와 그림 사이의 기호를 유리관으로 그린 것 — 관 가운데는 하얗게 타고 둘레로 색 빛이 번지며, 벽에도 빛이 번짐.
/// 켜지는 방식: 처음엔 하나씩 지직거리며 켜지고, 그 뒤로 늘 켜진 것(가끔 웅·지직 하고 떨림)·깜빡이는 것·두 장이 번갈아 켜지는 것(화살표가 움직임)·숨 쉬듯 밝아졌다 어두워지는 것.
/// 밤에 가장 밝고, 해질녘·새벽은 조금, 낮엔 옅게. 가까운 간판에선 낮게 웅웅거리는 소리, 지직거릴 때 소리.
@MainActor
final class NeonCity {
    let world = Entity()

    struct Box { let base: SIMD3<Float>; let w: Float; let d: Float; let h: Float; let yaw: Float }

    private final class Sign {
        let e: ModelEntity
        var p = SIMD3<Float>(0, 0, 0)  // 간판 가운데 (소리 자리)
        let a: UnlitMaterial
        let b: UnlitMaterial
        let spill: ModelEntity?
        let mode: Int                  // 0 늘 켜짐(가끔 떨림) 1 깜빡임 2 번갈아 3 숨쉬기
        let period: Float
        let phase: Float
        var startAt: Float
        var stutter: Float = -1        // 지직거리는 중 (남은 시간)
        var nextStutter: Float
        let near: Bool
        var level: Float = 0
        var frameB = false
        init(e: ModelEntity, a: UnlitMaterial, b: UnlitMaterial, spill: ModelEntity?, mode: Int, period: Float, phase: Float, startAt: Float, nextStutter: Float, near: Bool) {
            self.e = e; self.a = a; self.b = b; self.spill = spill; self.mode = mode; self.period = period; self.phase = phase
            self.startAt = startAt; self.nextStutter = nextStutter; self.near = near
        }
    }

    private var signs: [Sign] = []
    private var t: Float = 0
    private let look: LookMode
    private let k: Float                      // 시간대 밝기
    private static let colors: [SIMD3<Float>] = [[1, 0.24, 0.67], [0.16, 0.9, 1], [1, 0.27, 0.24], [0.67, 0.35, 1],
                                                 [1, 0.75, 0.16], [0.27, 1, 0.47], [0.24, 0.47, 1], [1, 0.94, 0.86]]

    init(room: RoomRec, layout L: Layout, floorY: Float, segs: [WallSeg], near: [Box], far: [Box], center: SIMD3<Float>, look: LookMode) {
        self.look = look
        switch room.time {
        case "night": k = 1
        case "dusk", "dawn": k = 0.82
        default: k = 0.5
        }
        var g = SeededRNG(seed: UInt64(room.id * 6151 + 29))
        // ① 난간 간판: 가장 긴 바깥 벽 몇 곳, 벽 22cm 너머 난간 위 (방 쪽을 봄)
        let outer = segs.filter { !$0.inner && simd_distance($0.a, $0.b) > 1.2 }.sorted { simd_distance($0.a, $0.b) > simd_distance($1.a, $1.b) }
        for s in outer.prefix(3) {
            let len = simd_distance(s.a, s.b)
            let dir = (s.b - s.a) / len
            let at = s.a + dir * len * Float.random(in: 0.3...0.7, using: &g) - s.n * 0.32
            guard !L.walkable(at) else { continue }
            let w = L.flat(at)
            let vert = Float.random(in: 0...1, using: &g) < 0.3
            let sw: Float = vert ? 0.32 : Float.random(in: 0.9...1.3, using: &g)
            let sh: Float = vert ? sw * 4 : sw / 4
            let y = floorY + (vert ? 1.0 : Float.random(in: 1.3...1.6, using: &g))
            let n3 = SIMD3<Float>(L.ex.x * s.n.x + L.ez.x * s.n.y, 0, L.ex.y * s.n.x + L.ez.y * s.n.y)
            add(at: SIMD3<Float>(w.x, y, w.y), normal: simd_normalize(n3), width: sw, height: sh, vert: vert, near: true, &g)
        }
        // ② 옥상 옆 건물 벽: 눈높이 근처에 큰 간판 (가로·세로 섞어)
        for b in near {
            let (c, n, tng, fw) = face(b, toward: center)
            let count = fw > 9 ? 2 : 1
            for i in 0..<count {
                let vert = (i == 1) || Float.random(in: 0...1, using: &g) < 0.35
                let sw: Float = vert ? Float.random(in: 1.0...1.6, using: &g) : Float.random(in: 3.0...max(3.1, min(6.5, fw * 0.7)), using: &g)
                let sh: Float = vert ? sw * 4 : sw / 4
                let along = Float.random(in: -0.3...0.3, using: &g) * max(0, fw - sw)
                let y = floorY + (vert ? Float.random(in: 0.5...3.0, using: &g) : Float.random(in: 1.8...5.5, using: &g))
                add(at: SIMD3<Float>(c.x, y, c.z) + tng * along + n * 0.15, normal: n, width: sw, height: sh, vert: vert, near: true, &g)
            }
        }
        // ③ 아래 거리·먼 빌딩 벽: 가까운 빌딩부터 가로·세로 간판 여러 개
        let sorted = far.sorted { simd_distance($0.base, center) < simd_distance($1.base, center) }
        for b in sorted.prefix(22) {
            let (c, n, tng, fw) = face(b, toward: center)
            let dist = simd_distance(SIMD2<Float>(b.base.x, b.base.z), SIMD2<Float>(center.x, center.z))
            let count = Int.random(in: 1...3, using: &g)
            let top = b.base.y + b.h
            for _ in 0..<count {
                let vert = Float.random(in: 0...1, using: &g) < 0.45
                let scale: Float = dist < 50 ? 1 : 1.6
                let sw: Float = vert ? Float.random(in: 2.0...3.4, using: &g) * scale : min(fw * 0.8, Float.random(in: 5...11, using: &g) * scale)
                let sh: Float = vert ? sw * 4 : sw / 4
                let yLo = b.base.y + 3 + sh / 2, yHi = min(top - sh / 2 - 2, floorY + 30)
                guard yHi > yLo else { continue }
                let y = Float.random(in: yLo...yHi, using: &g)
                let along = Float.random(in: -0.45...0.45, using: &g) * max(0, fw - sw)
                add(at: SIMD3<Float>(c.x, y, c.z) + tng * along + n * 0.3, normal: n, width: sw, height: sh, vert: vert, near: false, &g)
            }
        }
    }

    /// 건물 상자에서 그 쪽을 보는 면: (면 가운데(바닥 높이), 바깥 방향, 면을 따라가는 방향, 면 폭)
    private func face(_ b: Box, toward c: SIMD3<Float>) -> (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>, Float) {
        let ax = SIMD3<Float>(cos(b.yaw), 0, -sin(b.yaw)), az = SIMD3<Float>(sin(b.yaw), 0, cos(b.yaw))
        var to = c - b.base
        to.y = 0
        to = simd_length(to) > 0.01 ? simd_normalize(to) : SIMD3<Float>(1, 0, 0)
        let cand: [(SIMD3<Float>, SIMD3<Float>, Float, Float)] = [(ax, az, b.w / 2, b.d), (-ax, az, b.w / 2, b.d), (az, ax, b.d / 2, b.w), (-az, ax, b.d / 2, b.w)]
        let best = cand.max { simd_dot($0.0, to) < simd_dot($1.0, to) } ?? cand[0]
        return (b.base + best.0 * best.2, best.0, best.1, best.3)
    }

    private func mat(_ name: String, _ alpha: Float) -> UnlitMaterial {
        var m = UnlitMaterial(color: look == .line ? UIColor(white: 0.12, alpha: 1) : .white)
        if look != .line, let tx = Tex.with(look == .color ? .color : .mono, { Tex.get(name) }) {
            var tp = MaterialParameters.Texture(tx); tp.sampler = Tex.clamp
            m.color = .init(tint: UIColor(white: CGFloat(0.55 + 0.45 * k), alpha: 1), texture: tp)
        }
        if let mk = Tex.get(name + "_a", raw: true) {
            var mp = MaterialParameters.Texture(mk); mp.sampler = Tex.clamp
            m.blending = .transparent(opacity: .init(scale: look == .line ? 1 : alpha, texture: mp))
            if look == .line { m.opacityThreshold = 0.75 }          // 선 그림: 유리관만 검은 선으로
        }
        return m
    }

    private func add<G: RandomNumberGenerator>(at p: SIMD3<Float>, normal n: SIMD3<Float>, width w: Float, height h: Float, vert: Bool, near: Bool, _ g: inout G) {
        let idx = vert ? Int.random(in: 10...15, using: &g) : Int.random(in: 0...9, using: &g)
        let name = String(format: "neon_%02d", idx)
        let right = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), n))
        var q = Geo()
        let hr = right * (w / 2), hu = SIMD3<Float>(0, h / 2, 0)
        q.quad(p - hr - hu, p + hr - hu, p + hr + hu, p - hr + hu, SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(1, 1), SIMD2<Float>(0, 1))
        let alpha: Float = 0.55 + 0.45 * k
        let ma = mat(name + "a", alpha), mb = mat(name + "b", alpha)
        guard let e = q.entity("neon", ma) else { return }
        // 벽에 번지는 빛 (간판보다 넓게, 간판 색으로 옅게)
        var spill: ModelEntity? = nil
        if look != .line, let tx = Tex.get("glow", color: look == .color), let mk = Tex.get("glow_a", raw: true) {
            var sq = Geo()
            let sp = p - n * 0.05
            let shr = right * (w * 0.85), shu = SIMD3<Float>(0, h * 0.5 + w * 0.25, 0)
            sq.quad(sp - shr - shu, sp + shr - shu, sp + shr + shu, sp - shr + shu, SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(1, 1), SIMD2<Float>(0, 1))
            let c = Self.colors[idx % Self.colors.count]
            let ui = look == .mono ? UIColor(white: 0.8, alpha: 1) : UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1)
            var sm = UnlitMaterial(color: ui)
            var tp = MaterialParameters.Texture(tx); tp.sampler = Tex.clamp
            sm.color = .init(tint: ui, texture: tp)
            var mp = MaterialParameters.Texture(mk); mp.sampler = Tex.clamp
            sm.blending = .transparent(opacity: .init(scale: 0.1 + 0.22 * k, texture: mp))
            spill = sq.entity("neonSpill", sm)
            if let s = spill { world.addChild(s) }
        }
        world.addChild(e)
        let mode = Int.random(in: 0...9, using: &g)
        let s = Sign(e: e, a: ma, b: mb, spill: spill, mode: mode < 5 ? 0 : (mode < 7 ? 1 : (mode < 9 ? 2 : 3)),
                     period: Float.random(in: 0.6...1.6, using: &g), phase: Float.random(in: 0...6, using: &g),
                     startAt: Float.random(in: 0.2...3.5, using: &g), nextStutter: Float.random(in: 8...40, using: &g), near: near)
        s.p = p
        e.components.set(OpacityComponent(opacity: 0))
        spill?.components.set(OpacityComponent(opacity: 0))
        if near {
            // 가까운 간판: 낮은 웅웅 소리
            if let u = Bundle.main.url(forResource: "neon_hum", withExtension: "wav", subdirectory: "sfx") {
                let cfg = AudioFileResource.Configuration(loadingStrategy: .preload, shouldLoop: true)
                if let r = try? AudioFileResource.load(contentsOf: u, withName: nil, configuration: cfg) {
                    let se = Entity()
                    var sa = SpatialAudioComponent()
                    sa.gain = -16
                    se.components.set(sa)
                    se.position = p
                    world.addChild(se)
                    _ = se.playAudio(r)
                }
            }
        }
        signs.append(s)
    }

    // MARK: 매 프레임
    func tick(_ dt: Float) {
        t += dt
        for s in signs {
            var lv: Float
            if t < s.startAt {
                lv = 0
            } else if t < s.startAt + 0.7 {
                // 처음 켜질 때: 지직지직
                let x = (t - s.startAt) * 22 + s.phase
                lv = sin(x) * sin(x * 2.7) > 0.1 ? 1 : 0.1
                if s.near && s.level == 0 && lv > 0.5 { Sfx.play("neon_flick\(Int.random(in: 1...2))", in: world, at: s.p, gain: -14) }
            } else {
                switch s.mode {
                case 1: lv = (t * 1 / s.period + s.phase).truncatingRemainder(dividingBy: 1) < 0.62 ? 1 : 0.06
                case 3: lv = 0.55 + 0.45 * sin(t * 2 / s.period + s.phase)
                default: lv = 1
                }
                if s.mode == 2 {
                    let fb = (t / s.period + s.phase).truncatingRemainder(dividingBy: 1) < 0.5
                    if fb != s.frameB { s.frameB = fb; s.e.model?.materials = [fb ? s.b : s.a] }
                }
                // 가끔 지직거림 (늘 켜진 것도)
                if s.stutter < 0 && t > s.nextStutter {
                    s.stutter = Float.random(in: 0.25...0.6)
                    s.nextStutter = t + Float.random(in: 15...50)
                    if s.near { Sfx.play("neon_flick\(Int.random(in: 1...2))", in: world, at: s.p, gain: -12) }
                }
                if s.stutter >= 0 {
                    s.stutter -= dt
                    lv *= sin(t * 47 + s.phase) > -0.2 ? 1 : 0.15
                    if s.stutter < 0 { s.stutter = -1 }
                } else {
                    lv *= 0.94 + 0.06 * sin(t * 31 + s.phase * 3)            // 아주 미세한 떨림
                }
            }
            if abs(lv - s.level) > 0.02 || lv == 0 {
                s.level = lv
                s.e.components.set(OpacityComponent(opacity: max(0, min(1, lv))))
                s.spill?.components.set(OpacityComponent(opacity: max(0, min(1, lv))))
            }
        }
    }
}
