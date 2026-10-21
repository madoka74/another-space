import Foundation
import UIKit
import RealityKit
import simd

/// 집 테마의 고양이 '방울이': 선 그림 카툰 고양이(납작한 그림 한 장이 늘 나를 바라봄)가 내 근처를 따라다니며 놂.
/// - 늘 내 시야 안: 시야 밖으로 벗어나면 보이는 자리로 뛰어 들어옴. 내가 걸으면 앞쪽 옆을 종종걸음으로 따라옴
/// - 가구와 놀기: 평평한 가구 위로 폴짝 올라가 앉거나 식빵 굽거나 잠, 가구 옆면을 긁기
/// - 나와 놀기: 가만히 서 있으면 발치에 와서 부비부비(그르릉), 앉으면 옆에 와서 식빵·잠, 손을 내밀면 머리를 비빔,
///   손을 빠르게 흔들면 냥냥펀치, 오래 바라보면 올려다보며 야옹, 톡 치면(탭) 뒹굴며 짹
/// - 혼자서: 앉아 꼬리 살랑·눈 깜빡, 그루밍, 기지개, 식빵, 뒹굴기, 야옹
@MainActor
final class HomeCat {
    /// 매 프레임 알려 주는 것 (모두 저장 좌표)
    struct Ctx {
        var head: SIMD3<Float>
        var fwd: SIMD2<Float>                    // 바라보는 쪽 (수평, 단위)
        var gaze: SIMD3<Float>                   // 바라보는 쪽 (3차원, 단위)
        var floorY: Float
        var userSpeed: Float
        var still: Float                         // 가만히 서 있은 시간
        var seated: Bool
        var hands: [SIMD3<Float>]
        var free: (SIMD2<Float>) -> Bool         // 고양이가 설 수 있는 바닥 (집 방 안, 가구·문 자리 아님)
        var top: (SIMD2<Float>) -> Float?        // 올라앉을 수 있는 가구 윗면 높이 (바닥에서)
        var height: (SIMD2<Float>) -> Float      // 그 자리 가구 높이 (없으면 0)
    }

    let root = Entity()                          // 고양이 자리 (저장 좌표, 발밑)
    private(set) var done = false
    private let card = ModelEntity()
    private let flip = Entity()
    private var shadow: ModelEntity?
    private let look: LookMode
    private var mats: [String: UnlitMaterial] = [:]
    private var pending: [String] = []

    private enum Act { case sit, walk, jumpUp, onTop, jumpDown, groom, stretch, loaf, sleep, scratch, roll, swat, rub, meow, look, enter, leave }
    private var act: Act = .enter
    private var actT: Float = 0
    private var actDur: Float = 1
    private var pos: SIMD2<Float>
    private var elev: Float = 0                  // 바닥에서 높이 (가구 위면 그 높이)
    private var face: Float = 1                  // 그림 방향 (1 오른쪽, -1 왼쪽)
    private var goal: SIMD2<Float>?
    private var running = false
    private var then: Act = .sit                 // 걸어가서 할 일
    private var thenDur: Float = 3
    private var jumpFrom = SIMD3<Float>(0, 0, 0), jumpTo = SIMD3<Float>(0, 0, 0)
    private var topH: Float = 0
    private var t: Float = 0
    private var frameT: Float = 0
    private var blinkT: Float = 3
    private var hidden: Float = 0                // 시야 밖에 있은 시간
    private var gazeT: Float = 0
    private var meowCool: Float = 4
    private var followT: Float = 0
    private var lastHands: [SIMD3<Float>] = []
    private var purr: AudioPlaybackController?
    private var purrOn = false
    private var opacity: Float = 0
    private var scratchDir: SIMD2<Float> = SIMD2<Float>(1, 0)
    private var floorY: Float = 0

    private static let walkFrames = (0..<6).map { "cat_walk\($0)" }
    private static let runFrames = (0..<4).map { "cat_run\($0)" }
    private static let all: [String] = ["cat_sit0", "cat_sit1", "cat_blink", "cat_meow", "cat_look", "cat_lookmeow", "cat_groom0", "cat_groom1",
                                        "cat_swat0", "cat_swat1", "cat_loaf0", "cat_loaf1", "cat_sleep0", "cat_sleep1", "cat_stretch0", "cat_stretch1",
                                        "cat_jump0", "cat_jump1", "cat_scratch0", "cat_scratch1", "cat_roll0", "cat_roll1", "cat_rub0", "cat_rub1"]
                                       + walkFrames + runFrames

    init(at p: SIMD2<Float>, floorY: Float, look: LookMode) {
        self.look = look
        self.pos = p
        self.floorY = floorY
        // 그림 판: 55cm 정사각, 발밑(그림의 바닥 줄 470/512)이 바닥에 닿게
        let s: Float = 0.55
        var g = Geo()
        let y0: Float = -s * (42.0 / 512.0)
        g.quad(SIMD3<Float>(-s / 2, y0, 0), SIMD3<Float>(s / 2, y0, 0), SIMD3<Float>(s / 2, y0 + s, 0), SIMD3<Float>(-s / 2, y0 + s, 0),
               SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(1, 1), SIMD2<Float>(0, 1))
        if let m = g.mesh("cat") { card.model = ModelComponent(mesh: m, materials: [UnlitMaterial(color: .clear)]) }
        card.name = "homecat"
        card.components.set(CollisionComponent(shapes: [ShapeResource.generateBox(size: [0.42, 0.36, 0.12]).offsetBy(translation: [0, 0.18, 0])]))
        card.components.set(InputTargetComponent())
        flip.addChild(card)
        root.addChild(flip)
        // 발밑 그림자 (부드러운 타원)
        var sg = Geo()
        sg.quad(SIMD3<Float>(-0.26, 0.012, -0.12), SIMD3<Float>(0.26, 0.012, -0.12), SIMD3<Float>(0.26, 0.012, 0.12), SIMD3<Float>(-0.26, 0.012, 0.12),
                SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(1, 1), SIMD2<Float>(0, 1))
        var sm = UnlitMaterial(color: UIColor(white: 0, alpha: 1))
        if let mask = Tex.get("glow_a", raw: true) {
            var mp = MaterialParameters.Texture(mask); mp.sampler = Tex.clamp
            sm.blending = .transparent(opacity: .init(scale: 0.3, texture: mp))
        } else {
            sm.blending = .transparent(opacity: .init(floatLiteral: 0.15))
        }
        if let e = sg.entity("catShadow", sm) { shadow = e; root.addChild(e) }
        root.position = SIMD3<Float>(p.x, floorY, p.y)
        root.components.set(OpacityComponent(opacity: 0))
        pending = Self.all
        show("cat_walk0")
        Sfx.play("cat_trill", in: root, at: [0, 0.25, 0], gain: -4)
    }

    // MARK: 그림
    private func mat(_ n: String) -> UnlitMaterial {
        if let m = mats[n] { return m }
        var m = UnlitMaterial(color: .white)
        let mode: LookMode = look == .color ? .color : .mono          // 선 그림·흑백에선 목줄도 무채색
        if let tx = Tex.with(mode, { Tex.get(n) }) {
            var p = MaterialParameters.Texture(tx); p.sampler = Tex.clamp
            m.color = .init(tint: .white, texture: p)
        }
        if let a = Tex.get(n + "_a", raw: true) {
            var p = MaterialParameters.Texture(a); p.sampler = Tex.clamp
            m.blending = .transparent(opacity: .init(scale: 1, texture: p))
        }
        m.opacityThreshold = 0.5
        mats[n] = m
        return m
    }

    private var shown = ""
    private func show(_ n: String) {
        guard n != shown else { return }
        shown = n
        card.model?.materials = [mat(n)]
    }

    private func loop(_ frames: [String], fps: Float) -> String {
        let i = Int(frameT * fps) % max(1, frames.count)
        return frames[i]
    }

    // MARK: 소리
    private let meowNames = ["cat_meow1", "cat_meow2", "cat_meow3"]
    private func meow(_ name: String? = nil, gain: Double = -2) {
        guard meowCool <= 0 || name != nil else { return }
        meowCool = Float.random(in: 5...10)
        Sfx.play(name ?? (meowNames.randomElement() ?? "cat_meow1"), in: root, at: [0, 0.3, 0], gain: gain)
    }

    private func setPurr(_ on: Bool) {
        guard on != purrOn else { return }
        purrOn = on
        if on {
            if purr == nil, let u = Bundle.main.url(forResource: "cat_purr", withExtension: "wav", subdirectory: "sfx") {
                let cfg = AudioFileResource.Configuration(loadingStrategy: .preload, shouldLoop: true)
                if let r = try? AudioFileResource.load(contentsOf: u, withName: nil, configuration: cfg) {
                    let e = Entity()
                    var sa = SpatialAudioComponent()
                    sa.gain = 0
                    e.components.set(sa)
                    e.position = [0, 0.2, 0]
                    root.addChild(e)
                    let c = e.playAudio(r)
                    c.gain = -60
                    purr = c
                }
            }
            purr?.fade(to: -1, duration: 1.2)
        } else {
            purr?.fade(to: -60, duration: 1.5)
        }
    }

    // MARK: 동작 바꾸기
    private func start(_ a: Act, _ dur: Float) {
        act = a
        actT = 0
        actDur = dur
        frameT = 0
        if a != .rub && a != .loaf && a != .sleep { setPurr(false) }
    }

    /// 걸어가서(멀면 뛰어서) 그 일을 함
    private func go(_ to: SIMD2<Float>, then a: Act, _ dur: Float, run: Bool = false) {
        goal = to
        then = a
        thenDur = dur
        running = run || simd_distance(to, pos) > 1.6
        start(.walk, 30)
    }

    /// 톡 침: 뒹굴며 짹 (가구 위면 야옹)
    func poke() {
        guard act != .jumpUp && act != .jumpDown && act != .leave else { return }
        goal = nil
        if elev > 0.05 {
            meow("cat_meow2", gain: 0)
            start(.meow, 1.2)
        } else {
            Sfx.play("cat_chirp", in: root, at: [0, 0.25, 0], gain: 0)
            start(.roll, 2.4)
        }
    }

    /// 집이 아닌 방으로 가면 사라짐
    func leave() {
        guard act != .leave else { return }
        setPurr(false)
        start(.leave, 0.6)
    }

    func remove() {
        purr?.stop()
        root.removeFromParent()
        done = true
    }

    // MARK: 매 프레임
    func tick(_ dt: Float, _ c: Ctx) {
        guard !done else { return }
        t += dt
        lastDt = dt
        lastHead = c.head
        actT += dt
        frameT += dt
        meowCool -= dt
        floorY = c.floorY
        if let n = pending.first { _ = mat(n); pending.removeFirst() }            // 그림을 한 프레임에 하나씩 미리 읽음

        // 나와의 관계
        let me = SIMD2<Float>(c.head.x, c.head.z)
        let to = pos - me
        let dist = simd_length(to)
        let dir = dist > 0.01 ? to / dist : c.fwd
        let inView = dist > 0.25 && dist < 4.2 && simd_dot(dir, c.fwd) > 0.74
        hidden = inView ? 0 : hidden + dt

        // 바라보고 있나 (고양이 쪽 2m 안에서 시선이 8도 안)
        let eye = SIMD3<Float>(pos.x, floorY + elev + 0.2, pos.y) - c.head
        let looking = simd_length(eye) < 3 && simd_dot(simd_normalize(eye), c.gaze) > 0.99
        gazeT = looking ? gazeT + dt : 0

        // 손: 가까이 오면 비비고, 빠르게 휘두르면 냥냥펀치
        var handNear: SIMD3<Float>? = nil
        var handFast = false
        for h in c.hands {
            let hp = SIMD2<Float>(h.x, h.z)
            guard simd_distance(hp, pos) < 0.38, h.y - (floorY + elev) < 0.7 else { continue }
            handNear = h
            if let l = lastHands.min(by: { simd_distance($0, h) < simd_distance($1, h) }), dt > 0 {
                if simd_distance(l, h) / dt > 0.9 { handFast = true }
            }
        }
        lastHands = c.hands

        let busy = act == .jumpUp || act == .jumpDown || act == .leave || act == .enter
        if !busy {
            if let h = handNear, act != .roll {
                faceToward(SIMD2<Float>(h.x, h.z))
                if handFast {
                    if act != .swat { goal = nil; start(.swat, 1.0); Sfx.play("cat_chirp", in: root, at: [0, 0.25, 0], gain: -3) }
                } else if act != .rub && act != .swat {
                    goal = nil
                    start(.rub, 3)
                    setPurr(true)
                    if meowCool <= 0 { meow("cat_trill", gain: -3) }
                }
            } else if hidden > 0.7 && (act != .walk || (hidden > 1.6 && !running)) {
                // 시야 밖 → 보이는 자리로
                if elev > 0.05 { jumpDownNear(c, prefer: me + c.fwd * 1.4) } else if let s = viewSpot(c, near: 1.5) { go(s, then: .sit, 4, run: true) }
            } else if c.userSpeed > 0.35 && act != .walk && elev < 0.05 {
                // 내가 걸으면 앞쪽 옆을 따라옴
                followT -= dt
                if followT <= 0, let s = viewSpot(c, near: 1.3) { followT = 0.6; go(s, then: .sit, 2.5) }
            } else if gazeT > 1.2 && (act == .sit || act == .loaf || act == .onTop || act == .groom) && meowCool <= 0 {
                gazeT = 0
                meow()
                start(.look, 2.2)
            }
        }

        switch act {
        case .enter:
            opacity = min(1, opacity + dt * 2.5)
            root.components.set(OpacityComponent(opacity: opacity))
            if opacity >= 1 { start(.sit, 1.5) }
            show("cat_sit0")
        case .leave:
            opacity = max(0, opacity - dt * 2)
            root.components.set(OpacityComponent(opacity: opacity))
            if opacity <= 0 { remove(); return }
        case .walk:
            stepWalk(dt, c)
        case .jumpUp, .jumpDown:
            let k = min(1, actT / actDur)
            let p = jumpFrom + (jumpTo - jumpFrom) * k
            let arc = 4 * k * (1 - k) * 0.28
            pos = SIMD2<Float>(p.x, p.z)
            elev = p.y + arc
            show(k < 0.18 ? "cat_jump0" : (k < 0.85 ? "cat_jump1" : "cat_jump0"))
            if k >= 1 {
                elev = jumpTo.y
                if act == .jumpUp {
                    topH = jumpTo.y
                    start(.onTop, Float.random(in: 8...16))
                } else {
                    start(.sit, 2)
                }
            }
        case .onTop:
            // 가구 위: 앉아 있다가 식빵·그루밍·잠을 번갈아
            let phase = actT / actDur
            if phase < 0.3 { sitFrame() } else if phase < 0.55 { show(loop(["cat_groom0", "cat_groom1"], fps: 3)) } else { show(loop(["cat_loaf0", "cat_loaf1"], fps: 0.4)) }
            if actT > actDur { jumpDownNear(c, prefer: me + c.fwd * 1.3) }
        case .sit:
            sitFrame()
            if actT > actDur { decide(c) }
        case .groom:
            show(loop(["cat_groom0", "cat_groom1"], fps: 3))
            if actT > actDur { start(.sit, 2) }
        case .stretch:
            show(actT < actDur * 0.5 ? "cat_stretch0" : "cat_stretch1")
            if actT > actDur { start(.sit, 1.5) }
        case .loaf:
            show(loop(["cat_loaf0", "cat_loaf1"], fps: 0.35))
            if c.seated && dist < 1.4 { setPurr(true) }
            if actT > actDur || (c.userSpeed > 0.4 && actT > 1) { start(.stretch, 1.6) }
        case .sleep:
            show(loop(["cat_sleep0", "cat_sleep1"], fps: 0.45))
            setPurr(c.seated)
            if (actT > actDur && !c.seated) || c.userSpeed > 0.4 { start(.stretch, 2); meow("cat_meow2", gain: -6) }
        case .scratch:
            faceToward(pos + scratchDir)
            show(loop(["cat_scratch0", "cat_scratch1"], fps: 5))
            if actT > actDur { start(.sit, 2) }
        case .roll:
            show(loop(["cat_roll0", "cat_roll1"], fps: 3))
            if actT > actDur { start(.sit, 2) }
        case .swat:
            show(loop(["cat_swat0", "cat_swat1"], fps: 6))
            if actT > actDur { start(.sit, 1.5) }
        case .rub:
            show(loop(["cat_rub0", "cat_rub1"], fps: 2.2))
            if actT > actDur || (handNear == nil && c.userSpeed > 0.3) { setPurr(false); start(.sit, 2) }
        case .meow:
            show(actT < 0.9 ? "cat_meow" : "cat_sit0")
            if actT > actDur { start(elev > 0.05 ? .onTop : .sit, elev > 0.05 ? 6 : 2) }
        case .look:
            show(actT < 0.9 ? "cat_lookmeow" : "cat_look")
            if actT > actDur { start(elev > 0.05 ? .onTop : .sit, elev > 0.05 ? 6 : 2.5) }
        }
        place(c)
    }

    private var lastDt: Float = 1 / 90
    private func sitFrame() {
        blinkT -= lastDt
        if blinkT < 0 { blinkT = Float.random(in: 2.5...6) }
        if blinkT < 0.15 { show("cat_blink"); return }
        show(loop(["cat_sit0", "cat_sit1"], fps: 1.1))
    }

    /// 그림 판을 나에게 향하게, 좌우 뒤집기, 그림자
    private func place(_ c: Ctx) {
        let p3 = SIMD3<Float>(pos.x, floorY + elev, pos.y)
        root.position = p3
        let d = c.head - p3
        let yaw = atan2(d.x, d.z)
        card.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        card.scale = SIMD3<Float>(face, 1, 1)
        if let sh = shadow {
            if act == .jumpUp || act == .jumpDown {
                // 뛰는 동안 그림자는 바닥(또는 가구 위)에 남음
                sh.position = [0, min(0, (jumpTo.y > jumpFrom.y ? jumpFrom.y : jumpTo.y) - elev), 0]
            } else {
                sh.position = [0, 0, 0]
            }
        }
    }

    /// 그림의 오른쪽(+X)이 가리키는 수평 방향 (나를 보는 판 기준)
    private func cardRight(_ head: SIMD3<Float>) -> SIMD2<Float> {
        let d = SIMD2<Float>(head.x - pos.x, head.z - pos.y)
        let yaw = atan2(d.x, d.y)
        return SIMD2<Float>(cos(yaw), -sin(yaw))
    }
    private var lastHead = SIMD3<Float>(0, 1.5, 0)
    private func faceToward(_ p: SIMD2<Float>) {
        let v = p - pos
        guard simd_length(v) > 0.02 else { return }
        face = simd_dot(v, cardRight(lastHead)) >= 0 ? 1 : -1
    }

    private func stepWalk(_ dt: Float, _ c: Ctx) {
        lastHead = c.head
        guard let g = goal else { start(.sit, 2); return }
        let v = g - pos
        let d = simd_length(v)
        let speed: Float = running ? 1.35 : 0.5
        show(running ? loop(Self.runFrames, fps: 11) : loop(Self.walkFrames, fps: 8))
        if d < 0.06 {
            goal = nil
            if then == .jumpUp {
                faceToward(SIMD2<Float>(jumpTo.x, jumpTo.z))
                start(.jumpUp, 0.55)
            } else {
                start(then, thenDur)
                switch then {
                case .rub: setPurr(true); meow("cat_trill", gain: -3)
                case .scratch: faceToward(pos + scratchDir)
                default: break
                }
            }
            return
        }
        let step = min(d, speed * dt)
        let np = pos + v / d * step
        if !c.free(np) && c.free(pos) {
            goal = nil                                          // 길이 막힘 → 다른 일
            start(.sit, 1)
            return
        }
        faceToward(g)
        pos = np
    }

    // MARK: 무엇을 할지
    private func decide(_ c: Ctx) {
        lastHead = c.head
        let me = SIMD2<Float>(c.head.x, c.head.z)
        let dist = simd_distance(pos, me)
        // 내가 앉아 있으면 옆에 와서 식빵·잠
        if c.seated {
            if dist > 1.0, let s = sideSpot(c, 0.7) { go(s, then: Bool.random() ? .loaf : .sleep, Float.random(in: 20...40)); return }
            start(Bool.random() ? .loaf : .sleep, Float.random(in: 15...30))
            return
        }
        // 가만히 서 있으면 발치에 와서 부비부비
        if c.still > 4, dist > 0.55, Float.random(in: 0...1) < 0.45 {
            let s = me + c.fwd * 0.42 + SIMD2<Float>(-c.fwd.y, c.fwd.x) * Float.random(in: -0.15...0.15)
            if c.free(s) && pathOK(pos, s, c) { go(s, then: .rub, 3.5); return }
        }
        var opts: [(Float, () -> Bool)] = []
        opts.append((3, { [unowned self] in start(.sit, Float.random(in: 2.5...5)); return true }))
        opts.append((1.6, { [unowned self] in start(.groom, Float.random(in: 2.5...4.5)); return true }))
        opts.append((1.2, { [unowned self] in start(.loaf, Float.random(in: 5...10)); return true }))
        opts.append((0.8, { [unowned self] in start(.stretch, 1.8); return true }))
        opts.append((0.7, { [unowned self] in start(.roll, 2.4); Sfx.play("cat_chirp", in: root, at: [0, 0.25, 0], gain: -5); return true }))
        opts.append((0.8, { [unowned self] in meow(); start(.meow, 1.4); return true }))
        opts.append((2.6, { [unowned self] in
            guard let s = viewSpot(c, near: Float.random(in: 1.1...2.2)) else { return false }
            go(s, then: .sit, Float.random(in: 2...4)); return true
        }))
        opts.append((1.8, { [unowned self] in jumpUpSomewhere(c) }))
        opts.append((1.1, { [unowned self] in scratchSomewhere(c) }))
        if c.still > 20 { opts.append((1.0, { [unowned self] in start(.sleep, Float.random(in: 12...25)); return true })) }
        // 가중치 뽑기 (안 되면 다음 것)
        var pool = opts
        while !pool.isEmpty {
            let total = pool.reduce(Float(0)) { $0 + $1.0 }
            var r = Float.random(in: 0..<max(0.001, total))
            var idx = 0
            for (i, o) in pool.enumerated() {
                r -= o.0
                if r <= 0 { idx = i; break }
            }
            if pool[idx].1() { return }
            pool.remove(at: idx)
        }
        start(.sit, 3)
    }

    private func pathOK(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: Ctx) -> Bool {
        let d = simd_distance(a, b)
        let n = max(1, Int(d / 0.1))
        for i in 1...n {
            let p = a + (b - a) * (Float(i) / Float(n))
            if !c.free(p) { return false }
        }
        return true
    }

    /// 내 시야 안의 빈 바닥 (near m쯤 앞, 조금 옆으로). 고양이가 걸어갈 수 있는 곳
    private func viewSpot(_ c: Ctx, near: Float) -> SIMD2<Float>? {
        let me = SIMD2<Float>(c.head.x, c.head.z)
        var best: (SIMD2<Float>, Float)? = nil
        for dd in stride(from: Float(0.8), through: Float(2.6), by: 0.2) {
            for a in stride(from: Float(-0.5), through: Float(0.5), by: 0.125) {
                let v = SIMD2<Float>(c.fwd.x * cos(a) - c.fwd.y * sin(a), c.fwd.x * sin(a) + c.fwd.y * cos(a))
                let p = me + v * dd
                guard c.free(p) else { continue }
                var score = abs(dd - near) + abs(abs(a) - 0.25) * 0.6 + simd_distance(p, pos) * 0.15
                if !pathOK(pos, p, c) { score += 2.5 }               // 바로 못 가는 곳은 되도록 피함
                if best == nil || score < best!.1 { best = (p, score) }
            }
        }
        return best?.0
    }

    /// 앉아 있는 나의 옆 (시야 안쪽으로)
    private func sideSpot(_ c: Ctx, _ r: Float) -> SIMD2<Float>? {
        let me = SIMD2<Float>(c.head.x, c.head.z)
        for a in [Float(0.6), -0.6, 0.35, -0.35, 0.9, -0.9] {
            let v = SIMD2<Float>(c.fwd.x * cos(a) - c.fwd.y * sin(a), c.fwd.x * sin(a) + c.fwd.y * cos(a))
            let p = me + v * r
            if c.free(p) { return p }
        }
        return nil
    }

    /// 시야 안 평평한 가구 위로: 가구 옆 바닥까지 걸어가서 폴짝
    private func jumpUpSomewhere(_ c: Ctx) -> Bool {
        let me = SIMD2<Float>(c.head.x, c.head.z)
        var found: [(SIMD2<Float>, SIMD2<Float>, Float)] = []       // 올라갈 곳, 뛰어오를 바닥, 높이
        for dd in stride(from: Float(0.8), through: Float(2.6), by: 0.2) {
            for a in stride(from: Float(-0.5), through: Float(0.5), by: 0.17) {
                let v = SIMD2<Float>(c.fwd.x * cos(a) - c.fwd.y * sin(a), c.fwd.x * sin(a) + c.fwd.y * cos(a))
                let p = me + v * dd
                guard let h = c.top(p), h >= 0.3, h <= 1.1 else { continue }
                // 고양이 쪽으로 걸어 나와 처음 만나는 빈 바닥
                let back = simd_normalize(pos - p)
                var q = p
                var ok: SIMD2<Float>? = nil
                for _ in 0..<7 {
                    q += back * 0.1
                    if c.free(q) { ok = q; break }
                }
                guard let f = ok, pathOK(pos, f, c) else { continue }
                // 올라앉을 자리: 가장자리에서 15cm 안쪽
                let land = f - back * (simd_distance(f, p) + 0.05)
                guard let lh = c.top(land), abs(lh - h) < 0.12 else { continue }
                found.append((land, f, lh))
            }
        }
        guard let pick = found.randomElement() else { return false }
        jumpFrom = SIMD3<Float>(pick.1.x, 0, pick.1.y)
        jumpTo = SIMD3<Float>(pick.0.x, pick.2, pick.0.y)
        go(pick.1, then: .jumpUp, 0.55)
        return true
    }

    /// 가구 위에서 내려옴: 보이는 쪽 가까운 빈 바닥으로 폴짝
    private func jumpDownNear(_ c: Ctx, prefer: SIMD2<Float>) {
        var best: (SIMD2<Float>, Float)? = nil
        for k in 0..<16 {
            let a = Float(k) / 16 * 2 * .pi
            for r in [Float(0.35), 0.5, 0.7] {
                let p = pos + SIMD2<Float>(cos(a), sin(a)) * r
                guard c.free(p) else { continue }
                let s = simd_distance(p, prefer)
                if best == nil || s < best!.1 { best = (p, s) }
            }
        }
        guard let b = best else { start(.onTop, 4); return }
        jumpFrom = SIMD3<Float>(pos.x, elev, pos.y)
        jumpTo = SIMD3<Float>(b.0.x, 0, b.0.y)
        faceToward(b.0)
        start(.jumpDown, 0.5)
    }

    /// 시야 안 가구 옆면 긁기
    private func scratchSomewhere(_ c: Ctx) -> Bool {
        let me = SIMD2<Float>(c.head.x, c.head.z)
        var found: [(SIMD2<Float>, SIMD2<Float>)] = []
        let dirs = [SIMD2<Float>(1, 0), SIMD2<Float>(-1, 0), SIMD2<Float>(0, 1), SIMD2<Float>(0, -1)]
        for dd in stride(from: Float(0.8), through: Float(2.4), by: 0.2) {
            for a in stride(from: Float(-0.45), through: Float(0.45), by: 0.15) {
                let v = SIMD2<Float>(c.fwd.x * cos(a) - c.fwd.y * sin(a), c.fwd.x * sin(a) + c.fwd.y * cos(a))
                let p = me + v * dd
                guard c.free(p), pathOK(pos, p, c) else { continue }
                for d in dirs where c.height(p + d * 0.2) >= 0.4 { found.append((p, d)) }
            }
        }
        guard let pick = found.randomElement() else { return false }
        scratchDir = pick.1
        go(pick.0, then: .scratch, Float.random(in: 2...3.5))
        return true
    }
}
