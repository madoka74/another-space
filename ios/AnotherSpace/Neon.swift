import Foundation
import UIKit
import RealityKit
import simd

/// 도시 테마의 특징: 네온사인 — 실제 거리처럼 '있을 법한 자리'에만, 많지 않게.
/// - 옥상 위 간판: 건물 꼭대기 가장자리에 세운 가로 간판 (방 쪽을 봄)
/// - 돌출 간판: 건물 모서리에서 벽과 직각으로 튀어나온 세로 간판 (앞뒤 두 면, 어느 쪽에서 봐도 글자가 뒤집히지 않음)
/// - 가게 간판: 거리(30m 아래) 1층 출입구 위 가로 간판
/// - 벽 세로 간판: 위층 모서리 가까이 벽에 붙은 세로 간판
/// - 옥상 바(우리 옥상) 난간에 작은 간판 하나
/// 간판끼리 겹치지 않게(둘레 여유), 다른 건물 속에 묻히는 자리는 피함. 크기·색·켜지는 방식이 다양함.
/// 간판은 읽을 수 없는 글자와 그림 사이의 기호를 유리관으로 그린 것 — 관 가운데는 하얗게 타고 둘레로 색 빛이 번지며, 벽에도 빛이 번짐.
/// 켜지는 방식: 처음엔 하나씩 지직거리며 켜지고, 그 뒤로 늘 켜진 것(가끔 떨림)·깜빡이는 것·두 장이 번갈아 켜지는 것·숨 쉬듯 밝아졌다 어두워지는 것.
/// 밤에 가장 밝고, 해질녘·새벽은 조금, 낮엔 옅게. 가까운 간판에선 낮게 웅웅거리는 소리, 지직거릴 때 소리.
@MainActor
final class NeonCity {
    let world = Entity()

    struct Box { let base: SIMD3<Float>; let w: Float; let d: Float; let h: Float; let yaw: Float }

    private final class Sign {
        let ents: [ModelEntity]
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
        init(ents: [ModelEntity], a: UnlitMaterial, b: UnlitMaterial, spill: ModelEntity?, mode: Int, period: Float, phase: Float, startAt: Float, nextStutter: Float, near: Bool) {
            self.ents = ents; self.a = a; self.b = b; self.spill = spill; self.mode = mode; self.period = period; self.phase = phase
            self.startAt = startAt; self.nextStutter = nextStutter; self.near = near
        }
    }

    private var signs: [Sign] = []
    private var t: Float = 0
    private let look: LookMode
    private let k: Float                      // 시간대 밝기
    private var taken: [(SIMD3<Float>, SIMD3<Float>)] = []      // 세운 간판이 차지한 상자 (겹치지 않게)
    private var all: [Box] = []
    private var hPool: [Int] = []
    private var vPool: [Int] = []
    private static let colors: [SIMD3<Float>] = [[1, 0.24, 0.67], [0.16, 0.9, 1], [1, 0.27, 0.24], [0.67, 0.35, 1],
                                                 [1, 0.75, 0.16], [0.27, 1, 0.47], [0.24, 0.47, 1], [1, 0.94, 0.86]]

    init(room: RoomRec, layout L: Layout, floorY: Float, segs: [WallSeg], near: [Box], far: [Box], center: SIMD3<Float>, look: LookMode) {
        self.look = look
        switch room.time {
        case "night": k = 1
        case "dusk", "dawn": k = 0.82
        default: k = 0.5
        }
        all = near + far
        var g = SeededRNG(seed: UInt64(room.id * 6151 + 29))
        hPool = Array(0...9).shuffled(using: &g)
        vPool = Array(10...15).shuffled(using: &g)
        // ① 우리 옥상 바: 가장 긴 바깥 벽 난간에 작은 가로 간판 하나 (방 쪽을 봄)
        if let s = segs.filter({ !$0.inner && simd_distance($0.a, $0.b) > 1.6 }).max(by: { simd_distance($0.a, $0.b) < simd_distance($1.a, $1.b) }) {
            let len = simd_distance(s.a, s.b)
            let dir = (s.b - s.a) / len
            let at = s.a + dir * len * Float.random(in: 0.35...0.65, using: &g) - s.n * 0.32
            if !L.walkable(at) {
                let w = L.flat(at)
                let n3 = simd_normalize(SIMD3<Float>(L.ex.x * s.n.x + L.ez.x * s.n.y, 0, L.ex.y * s.n.x + L.ez.y * s.n.y))
                let sw = Float.random(in: 0.7...1.0, using: &g)
                place(SIMD3<Float>(w.x, floorY + 1.25, w.y), normal: n3, width: sw, height: sw / 4, vert: false, near: true, wallBehind: false, &g)
            }
        }
        // ② 옥상 바로 옆 건물: 한 채에 하나 — 눈높이쯤 돌출 간판 또는 옥상 위 간판
        for (i, b) in near.enumerated() {
            let f = face(b, toward: center)
            if i % 2 == 0 {
                blade(b, f, yLo: floorY - 1, yHi: floorY + 3.5, scale: 1, near: true, &g)
            } else {
                roof(b, f, scale: 1, near: true, &g)
            }
        }
        // ③ 먼 빌딩: 가까운 것부터 12채, 한 채에 한두 개 (옥상·돌출·가게·벽 세로 중 그 건물에 맞는 것)
        let sorted = far.sorted { simd_distance($0.base, center) < simd_distance($1.base, center) }
        var used = 0
        for b in sorted where used < 12 {
            let f = face(b, toward: center)
            let dist = simd_distance(SIMD2<Float>(b.base.x, b.base.z), SIMD2<Float>(center.x, center.z))
            let sc: Float = dist < 45 ? 1 : (dist < 90 ? 1.5 : 2.2)
            let before = signs.count
            let r = Float.random(in: 0...1, using: &g)
            if r < 0.3 { roof(b, f, scale: sc, near: false, &g) }
            else if r < 0.6 { blade(b, f, yLo: b.base.y + 6, yHi: b.base.y + min(b.h - 4, 26), scale: sc, near: false, &g) }
            else if r < 0.8 { shop(b, f, scale: sc, &g) }
            else { upright(b, f, scale: sc, &g) }
            if Float.random(in: 0...1, using: &g) < 0.3 { shop(b, f, scale: sc, &g) }        // 1층 가게 간판을 하나 더
            if signs.count > before { used += 1 }
        }
    }

    typealias Face = (c: SIMD3<Float>, n: SIMD3<Float>, tng: SIMD3<Float>, fw: Float)

    /// 옥상 위 간판: 꼭대기 가장자리에서 1m 안쪽에 세움, 아래 끝이 지붕 위 40cm
    private func roof<G: RandomNumberGenerator>(_ b: Box, _ f: Face, scale: Float, near: Bool, _ g: inout G) {
        let sw = min(f.fw * Float.random(in: 0.45...0.7, using: &g), 7 * scale)
        let sh = sw / 4
        let top = b.base.y + b.h
        let along = Float.random(in: -0.15...0.15, using: &g) * max(0, f.fw - sw)
        let p = SIMD3<Float>(f.c.x, top + 0.4 + sh / 2, f.c.z) - f.n * 1.0 + f.tng * along
        place(p, normal: f.n, width: sw, height: sh, vert: false, near: near, wallBehind: false, &g)
    }

    /// 돌출 간판: 모서리에서 1~1.5m 안쪽, 벽과 직각으로 튀어나옴 (앞뒤 두 면)
    private func blade<G: RandomNumberGenerator>(_ b: Box, _ f: Face, yLo: Float, yHi: Float, scale: Float, near: Bool, _ g: inout G) {
        let sw = Float.random(in: 0.9...1.4, using: &g) * scale
        let sh = sw * 4
        let lo = max(yLo, b.base.y + 4 + sh / 2), hi = min(yHi, b.base.y + b.h - 2 - sh / 2)
        guard hi > lo else { return }
        let side: Float = Float.random(in: 0...1, using: &g) < 0.5 ? -1 : 1
        let along = side * (f.fw / 2 - Float.random(in: 1.0...1.6, using: &g) * scale)
        let p = SIMD3<Float>(f.c.x, Float.random(in: lo...hi, using: &g), f.c.z) + f.tng * along + f.n * (sw / 2 + 0.25 * scale)
        place(p, normal: f.tng, width: sw, height: sh, vert: true, near: near, wallBehind: false, twoSided: true, facade: f.n, &g)
    }

    /// 가게 간판: 거리 1층 출입구 위 (지면에서 3.5~5m), 벽에 붙음
    private func shop<G: RandomNumberGenerator>(_ b: Box, _ f: Face, scale: Float, _ g: inout G) {
        let sw = min(f.fw * 0.5, Float.random(in: 3.0...5.5, using: &g) * min(scale, 1.4))
        let along = Float.random(in: -0.3...0.3, using: &g) * max(0, f.fw - sw)
        let p = SIMD3<Float>(f.c.x, b.base.y + Float.random(in: 3.5...5.0, using: &g), f.c.z) + f.tng * along + f.n * 0.25
        place(p, normal: f.n, width: sw, height: sw / 4, vert: false, near: false, wallBehind: true, &g)
    }

    /// 벽 세로 간판: 위층, 모서리 가까이 벽에 붙음
    private func upright<G: RandomNumberGenerator>(_ b: Box, _ f: Face, scale: Float, _ g: inout G) {
        let sw = Float.random(in: 1.6...2.6, using: &g) * scale
        let sh = sw * 4
        let topY = b.base.y + b.h - 2 - sh / 2
        guard topY > b.base.y + 8 + sh / 2 else { return }
        let side: Float = Float.random(in: 0...1, using: &g) < 0.5 ? -1 : 1
        let along = side * max(0, f.fw / 2 - sw / 2 - 1.2)
        let p = SIMD3<Float>(f.c.x, topY - Float.random(in: 0...4, using: &g), f.c.z) + f.tng * along + f.n * 0.25
        place(p, normal: f.n, width: sw, height: sh, vert: true, near: false, wallBehind: true, &g)
    }

    /// 자리 검사: 다른 간판과 겹치지 않고(둘레 여유), 다른 건물 속에 묻히지 않을 때만 세움
    /// lo·hi: 둘레 여유까지 넣은 상자, pts: 간판의 실제 네 귀퉁이·가운데
    private func free(_ lo: SIMD3<Float>, _ hi: SIMD3<Float>, pts: [SIMD3<Float>]) -> Bool {
        for (a, b) in taken where lo.x < b.x && hi.x > a.x && lo.y < b.y && hi.y > a.y && lo.z < b.z && hi.z > a.z { return false }
        for bx in all {
            let ax = SIMD3<Float>(cos(bx.yaw), 0, -sin(bx.yaw)), az = SIMD3<Float>(sin(bx.yaw), 0, cos(bx.yaw))
            for q in pts {
                let d = q - bx.base
                if abs(simd_dot(d, ax)) < bx.w / 2 + 0.05 && abs(simd_dot(d, az)) < bx.d / 2 + 0.05 && d.y > -0.1 && d.y < bx.h + 0.05 { return false }
            }
        }
        return true
    }

    /// 건물 상자에서 그 쪽을 보는 면: (면 가운데(바닥 높이), 바깥 방향, 면을 따라가는 방향, 면 폭)
    private func face(_ b: Box, toward c: SIMD3<Float>) -> Face {
        let ax = SIMD3<Float>(cos(b.yaw), 0, -sin(b.yaw)), az = SIMD3<Float>(sin(b.yaw), 0, cos(b.yaw))
        var to = c - b.base
        to.y = 0
        to = simd_length(to) > 0.01 ? simd_normalize(to) : SIMD3<Float>(1, 0, 0)
        let cand: [(SIMD3<Float>, SIMD3<Float>, Float, Float)] = [(ax, az, b.w / 2, b.d), (-ax, az, b.w / 2, b.d), (az, ax, b.d / 2, b.w), (-az, ax, b.d / 2, b.w)]
        let best = cand.max { simd_dot($0.0, to) < simd_dot($1.0, to) } ?? cand[0]
        return (c: b.base + best.0 * best.2, n: best.0, tng: best.1, fw: best.3)
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
            if look == .line { m.opacityThreshold = 0.75 } else { m.writesDepth = false }     // 선 그림: 유리관만 검은 선으로 / 빛 판이 뒤를 네모나게 지우지 않게
        }
        return m
    }

    /// 간판 하나: 가운데 p, 앞쪽 normal. twoSided 면 뒤쪽에도 글자가 바로 보이는 면을 하나 더 (돌출 간판).
    /// wallBehind: 벽에 붙은 간판 — 벽에 색 빛이 번짐. facade: 돌출 간판이 붙은 벽의 바깥 방향 (그 벽에 빛이 번짐)
    private func place<G: RandomNumberGenerator>(_ p: SIMD3<Float>, normal n: SIMD3<Float>, width w: Float, height h: Float, vert: Bool, near: Bool,
                                                 wallBehind: Bool, twoSided: Bool = false, facade: SIMD3<Float>? = nil, _ g: inout G) {
        let right = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), n))
        let hr = right * (w / 2), hu = SIMD3<Float>(0, h / 2, 0)
        let pad = max(0.4, w * 0.25)
        let ex = SIMD3<Float>(abs(hr.x), abs(hu.y), abs(hr.z)) + SIMD3<Float>(repeating: pad) + simd_abs(n) * 0.3
        guard free(p - ex, p + ex, pts: [p, p - hr - hu, p + hr - hu, p + hr + hu, p - hr + hu]) else { return }
        taken.append((p - ex, p + ex))
        let idx: Int
        if vert { idx = vPool.removeFirst(); vPool.append(idx) } else { idx = hPool.removeFirst(); hPool.append(idx) }      // 색·모양이 고르게 돌아가며
        let name = String(format: "neon_%02d", idx)
        let alpha: Float = 0.55 + 0.45 * k
        let ma = mat(name + "a", alpha), mb = mat(name + "b", alpha)
        var ents: [ModelEntity] = []
        for side in (twoSided ? [Float(1), -1] : [Float(1)]) {
            let nn = n * side
            let rr = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), nn)) * (w / 2)
            let c = p + nn * 0.02
            var q = Geo()
            q.quad(c - rr - hu, c + rr - hu, c + rr + hu, c - rr + hu, SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(1, 1), SIMD2<Float>(0, 1),
                   twoSided: false)                       // 앞면만 (뒤에서 글자가 뒤집혀 보이지 않게)
            if let e = q.entity("neon", ma) { ents.append(e) }
        }
        guard !ents.isEmpty else { return }
        // 벽에 번지는 빛 (간판 색으로 옅게): 붙은 벽 또는 돌출 간판이 매달린 벽
        var spill: ModelEntity? = nil
        let wallN: SIMD3<Float>? = wallBehind ? n : facade
        if look != .line, let wn = wallN, let tx = Tex.get("glow", color: look == .color), let mk = Tex.get("glow_a", raw: true) {
            var sq = Geo()
            let sr = simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), wn))
            // 벽 면 위: 벽에 붙은 간판은 바로 뒤, 돌출 간판은 매달린 자리
            let sp = wallBehind ? p - wn * 0.2 : p - wn * (w / 2 + 0.23)
            let span = wallBehind ? w * 0.85 : w * 1.6
            let shr = sr * span, shu = SIMD3<Float>(0, h * 0.5 + w * 0.3, 0)
            sq.quad(sp - shr - shu, sp + shr - shu, sp + shr + shu, sp - shr + shu, SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(1, 1), SIMD2<Float>(0, 1))
            let c = Self.colors[idx % Self.colors.count]
            let ui = look == .mono ? UIColor(white: 0.8, alpha: 1) : UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1)
            var sm = UnlitMaterial(color: ui)
            var tp = MaterialParameters.Texture(tx); tp.sampler = Tex.clamp
            sm.color = .init(tint: ui, texture: tp)
            var mp = MaterialParameters.Texture(mk); mp.sampler = Tex.clamp
            sm.blending = .transparent(opacity: .init(scale: 0.1 + 0.22 * k, texture: mp))
            sm.writesDepth = false                 // 반투명 판이 뒤의 건물을 네모나게 지우지 않게
            spill = sq.entity("neonSpill", sm)
            if let s = spill { world.addChild(s) }
        }
        for e in ents { world.addChild(e) }
        let mode = Int.random(in: 0...9, using: &g)
        let s = Sign(ents: ents, a: ma, b: mb, spill: spill, mode: mode < 5 ? 0 : (mode < 7 ? 1 : (mode < 9 ? 2 : 3)),
                     period: Float.random(in: 0.6...1.6, using: &g), phase: Float.random(in: 0...6, using: &g),
                     startAt: Float.random(in: 0.2...3.5, using: &g), nextStutter: Float.random(in: 8...40, using: &g), near: near)
        s.p = p
        for e in ents { e.components.set(OpacityComponent(opacity: 0)) }
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
                    if fb != s.frameB { s.frameB = fb; for e in s.ents { e.model?.materials = [fb ? s.b : s.a] } }
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
                for e in s.ents { e.components.set(OpacityComponent(opacity: max(0, min(1, lv)))) }
                s.spill?.components.set(OpacityComponent(opacity: max(0, min(1, lv))))
            }
        }
    }
}
