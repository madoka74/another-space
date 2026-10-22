import Foundation
import UIKit
import RealityKit
import simd

/// 시골 테마의 강아지 '설이' (갈색 곱슬 토이 푸들 느낌의 선 그림 카툰 — 큰 머리·늘어진 귀, 다리는 몸과 한 덩어리). 고양이 방울이와 같은 방식(그림 판이 늘 나를 바라보고,
/// 가까이서 내려다볼 땐 판이 내 눈 쪽으로 젖혀짐)이지만 성격이 다름:
/// - 활발하게 이곳저곳 돌아다니고(킁킁 냄새 맡으며), 소파·침대처럼 낮은 가구(30~65cm)엔 폴짝 올라가 엎드리기도 함. 늘 내 시야 근처
/// - 혼자서: 앉아 꼬리 흔들기, 헥헥, 땅 파기, 벌러덩, 엎드리기, 놀자 자세(엉덩이 들기), 우다다, 가끔 아우우 하울링
/// - 막대 놀이: 막대를 엄지·검지로 집으면(손에 붙어 따라옴) 설이가 앞에 와서 놀자 자세로 들썩이며 기다림 →
///   던지면(손을 휘두른 빠르기 그대로) 막대가 날아가 떨어지고, 달려가 물어 와 발치에 놓음. 막대를 톡 치면 물어서 가져다줌
/// - 나와 놀기: 가만히 서 있으면 발치에 와서 마주 보고 앉아 헥헥, 앉으면 옆에 엎드렸다 잠, 손을 내밀면 킁킁 냄새 맡음(♥),
///   손을 빠르게 흔들면 신나서 뛰어오름, 오래 바라보면 고개를 갸웃하며 낑
/// - 톡 치면: 꼬리 흔들며 헥헥(♥), 손 주기, 벌러덩, 폴짝, 놀자 자세+멍, 고개 갸웃, 아우우. 자꾸 치면 화내지 않고 신나서 우다다
@MainActor
final class HomeDog {
    typealias Ctx = HomeCat.Ctx

    let root = Entity()
    let propRoot = Entity()                      // 막대 (저장 좌표)
    private(set) var done = false
    private let card = ModelEntity()
    private let bubble = ModelEntity()
    private var shadow: ModelEntity?
    private let look: LookMode
    private var mats: [String: UnlitMaterial] = [:]
    private var pending: [String] = []
    private static let size: Float = 0.72        // 그림 판 크기 (강아지는 고양이보다 조금 큼)

    private enum Act {
        case sit, walk, lie, sleep, sniff, dig, roll, bow, jump, bark, howl, pant, tilt, paw, love, fetch, bring, wait,
             jumpUp, onTop, jumpDown, enter, leave
    }
    private var act: Act = .enter
    private var actT: Float = 0
    private var actDur: Float = 1
    private var pos: SIMD2<Float>
    private var elev: Float = 0                  // 가구 위면 그 높이
    private var hop: Float = 0
    private var face: Float = 1
    private var turnFrom: Float = 1
    private var turnT: Float = -1
    private var frontal = false
    private var moveDir = SIMD2<Float>(1, 0)
    private var goal: SIMD2<Float>?
    private var running = false
    private var then: Act = .sit
    private var thenDur: Float = 3
    private var sniffing = false
    private var jumpFrom = SIMD3<Float>(0, 0, 0), jumpTo = SIMD3<Float>(0, 0, 0)
    private var t: Float = 0
    private var frameT: Float = 0
    private var blinkT: Float = 3
    private var hidden: Float = 0
    private var gazeT: Float = 0
    private var voiceCool: Float = 3
    private var talkT: Float = 9
    private var tagT: Float = 0
    private var followT: Float = 0
    private var panting: Float = 0               // 뛰고 나면 한동안 헥헥
    private var lastHands: [SIMD3<Float>] = []
    private var pantLoop: AudioPlaybackController?
    private var pantOn = false
    private var opacity: Float = 0
    private var floorY: Float = 0
    private var yaw: Float = 0
    private var lastHead = SIMD3<Float>(0, 1.5, 0)
    private var lastDt: Float = 1 / 90
    private var taps: [Float] = []
    private var lastCtx: Ctx?
    // 막대
    private var stick: ModelEntity?
    private var stickPos = SIMD2<Float>(0, 0)               // 바닥에 놓인 자리
    private var stickYaw: Float = 0.6
    private var carrying = false
    private var stickHeld = false                           // 내가 손으로 집고 있음
    private var heldAt = SIMD3<Float>(0, 0, 0)
    private var stickAir: (SIMD3<Float>, SIMD3<Float>)?     // 날아가는 중 (자리, 빠르기)
    private var stickSpin: Float = 0
    private var wantFetch = false                           // 가구 위에서 막대를 보면 내려와서 가져옴
    // 말풍선
    private var bubbleT: Float = -1
    private var bubbleDur: Float = 1.4

    private static let walkFrames = (0..<6).map { "dog_walk\($0)" }
    private static let runFrames = (0..<4).map { "dog_run\($0)" }
    private static let fwalkFrames = (0..<4).map { "dog_fwalk\($0)" }
    private static let bwalkFrames = (0..<4).map { "dog_bwalk\($0)" }
    private static let all: [String] = ["dog_sit0", "dog_sit1", "dog_blink", "dog_pant0", "dog_pant1", "dog_howl", "dog_paw", "dog_bark",
                                        "dog_sniff0", "dog_sniff1", "dog_lie0", "dog_lie1", "dog_sleep0", "dog_sleep1", "dog_bow0", "dog_bow1",
                                        "dog_jump0", "dog_jump1", "dog_roll0", "dog_roll1", "dog_dig0", "dog_dig1", "dog_stand0", "dog_stand1",
                                        "dog_fsit0", "dog_fsit1", "dog_fblink", "dog_ftilt", "dog_fhappy", "dog_bsit"]
                                       + walkFrames + runFrames + fwalkFrames + bwalkFrames

    init(at p: SIMD2<Float>, floorY: Float, look: LookMode) {
        self.look = look
        self.pos = p
        self.floorY = floorY
        let s = Self.size
        var g = Geo()
        let y0: Float = -s * (42.0 / 512.0)                 // 발밑(그림 바닥 줄)이 바닥에 닿게
        g.quad(SIMD3<Float>(-s / 2, y0, 0), SIMD3<Float>(s / 2, y0, 0), SIMD3<Float>(s / 2, y0 + s, 0), SIMD3<Float>(-s / 2, y0 + s, 0),
               SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(1, 1), SIMD2<Float>(0, 1))
        if let m = g.mesh("dog") { card.model = ModelComponent(mesh: m, materials: [UnlitMaterial(color: .clear)]) }
        card.name = "homedog"
        card.components.set(CollisionComponent(shapes: [ShapeResource.generateBox(size: [s * 0.74, s * 0.62, 0.14]).offsetBy(translation: [0, s * 0.31, 0])]))
        card.components.set(InputTargetComponent())
        root.addChild(card)
        var bq = Geo()
        let b: Float = 0.16
        bq.quad(SIMD3<Float>(-b / 2, 0, 0), SIMD3<Float>(b / 2, 0, 0), SIMD3<Float>(b / 2, b, 0), SIMD3<Float>(-b / 2, b, 0),
                SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(1, 1), SIMD2<Float>(0, 1))
        if let m = bq.mesh("bubble") { bubble.model = ModelComponent(mesh: m, materials: [UnlitMaterial(color: .clear)]) }
        bubble.isEnabled = false
        root.addChild(bubble)
        var sg = Geo()
        let sw = s * 0.44, sd = s * 0.17
        sg.quad(SIMD3<Float>(-sw, 0.012, -sd), SIMD3<Float>(sw, 0.012, -sd), SIMD3<Float>(sw, 0.012, sd), SIMD3<Float>(-sw, 0.012, sd),
                SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(1, 1), SIMD2<Float>(0, 1))
        var sm = UnlitMaterial(color: UIColor(white: 0, alpha: 1))
        if let mask = Tex.get("glow_a", raw: true) {
            var mp = MaterialParameters.Texture(mask); mp.sampler = Tex.clamp
            sm.blending = .transparent(opacity: .init(scale: 0.3, texture: mp))
            sm.writesDepth = false                 // 반투명 판이 뒤의 나무·물건을 네모나게 지우지 않게
        } else {
            sm.blending = .transparent(opacity: .init(floatLiteral: 0.15))
            sm.writesDepth = false                 // 반투명 판이 뒤의 나무·물건을 네모나게 지우지 않게
        }
        if let e = sg.entity("dogShadow", sm) { shadow = e; root.addChild(e) }
        root.position = SIMD3<Float>(p.x, floorY, p.y)
        root.components.set(OpacityComponent(opacity: 0))
        pending = Self.all
        show("dog_fwalk0")
        Sfx.play("dog_yip1", in: root, at: [0, 0.35, 0], gain: -4)
        emote("heart")
    }

    // MARK: 그림
    private func mat(_ n: String) -> UnlitMaterial {
        if let m = mats[n] { return m }
        var m = UnlitMaterial(color: .white)
        let mode: LookMode = look == .color ? .color : .mono
        if let tx = look == .line ? Tex.inked(n) : Tex.with(mode, { Tex.get(n) }) {      // 선 그림: 윤곽선만 검게, 칠은 흰 종이
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
        frames[Int(frameT * fps) % max(1, frames.count)]
    }

    private func emote(_ name: String, _ dur: Float = 1.5) {
        bubble.model?.materials = [mat("emote_" + name)]
        bubble.isEnabled = true
        bubbleT = 0
        bubbleDur = dur
    }

    // MARK: 소리
    private func say(_ name: String, _ gain: Double = -3) {
        voiceCool = Float.random(in: 2.5...5)
        Sfx.play(name, in: root, at: [0.15 * face, 0.35, 0], gain: gain)
    }
    private func bark(_ gain: Double = -3) { say("dog_bark\(Int.random(in: 1...3))", gain) }
    private func yip(_ gain: Double = -4) { say("dog_yip\(Int.random(in: 1...2))", gain) }

    private func setPant(_ on: Bool) {
        guard on != pantOn else { return }
        pantOn = on
        if on {
            if pantLoop == nil, let u = Bundle.main.url(forResource: "dog_pant", withExtension: "wav", subdirectory: "sfx") {
                let cfg = AudioFileResource.Configuration(loadingStrategy: .preload, shouldLoop: true)
                if let r = try? AudioFileResource.load(contentsOf: u, withName: nil, configuration: cfg) {
                    let e = Entity()
                    var sa = SpatialAudioComponent()
                    sa.gain = 0
                    e.components.set(sa)
                    e.position = [0, 0.35, 0]
                    root.addChild(e)
                    let c = e.playAudio(r)
                    c.gain = -60
                    pantLoop = c
                }
            }
            pantLoop?.fade(to: -6, duration: 0.8)
        } else {
            pantLoop?.fade(to: -60, duration: 1.2)
        }
    }

    // MARK: 동작
    private func start(_ a: Act, _ dur: Float) {
        act = a
        actT = 0
        actDur = dur
        frameT = 0
    }

    private func go(_ to: SIMD2<Float>, then a: Act, _ dur: Float, run: Bool = false, sniff: Bool = false) {
        goal = to
        then = a
        thenDur = dur
        running = run || simd_distance(to, pos) > 1.4
        sniffing = sniff && !running
        start(.walk, 30)
    }

    private var onFurniture: Bool { elev > 0.05 }

    /// 톡 침 (바라보고 탭)
    func poke() {
        guard act != .leave && act != .enter && act != .jumpUp && act != .jumpDown else { return }
        taps = taps.filter { t - $0 < 6 } + [t]
        if carrying { dropStick(); yip(-2); emote("exclaim"); start(.bow, 1.5); return }
        goal = nil
        if taps.count >= 4 && !onFurniture {                   // 자꾸 치면 신나서 우다다
            taps.removeAll()
            yip(-1)
            emote("exclaim")
            if let c = lastCtx { zoomies(c) } else { start(.jump, 1.0) }
            return
        }
        switch act {
        case .sleep, .lie:
            say("dog_whine", -6); emote("question"); frontal = true; start(.tilt, 1.6); return
        case .fetch, .bring, .wait:
            yip(-3); emote("exclaim"); return
        default: break
        }
        if onFurniture {
            emote("heart"); panting = 4; frontal = true; start(.love, 2.5)
            return
        }
        switch Int.random(in: 0...6) {
        case 0: frontal = true; emote("heart"); panting = 4; start(.love, 3)
        case 1: emote("heart"); yip(-3); start(.paw, 2)
        case 2: emote("heart"); say("dog_playgrowl", -4); start(.roll, 2.4)
        case 3: yip(-2); emote("exclaim"); start(.jump, 1.2)
        case 4: bark(-2); emote("exclaim"); start(.bow, 1.8)
        case 5: say("dog_whine", -5); emote("question"); frontal = true; start(.tilt, 1.8)
        default: say("dog_howl", -5); emote("note", 2.4); start(.howl, 2.6)
        }
    }

    /// 막대를 톡 침: 설이가 물어서 내 앞에 가져다 놓음
    func tapStick() {
        guard stick != nil, !stickHeld, stickAir == nil, !carrying else { return }
        yip(-3)
        emote("exclaim", 1)
        if onFurniture { wantFetch = true } else { start(.fetch, 15) }
    }

    /// 막대를 손으로 집음: 막대가 손을 따라오고, 설이는 앞에 와서 놀자 자세로 들썩이며 기다림
    func holdStick(at p: SIMD3<Float>) {
        guard stick != nil else { return }
        if carrying { carrying = false }
        if !stickHeld {
            stickHeld = true
            stickAir = nil
            if act != .leave && act != .enter {
                yip(-3)
                emote("exclaim", 1)
                if onFurniture { wantFetch = true } else { goal = nil; start(.wait, 60) }
            }
        }
        heldAt = p
    }

    /// 놓음: 손의 빠르기 그대로 날아가 떨어짐 → 달려가 물어 옴
    func releaseStick(vel: SIMD3<Float>) {
        guard stickHeld else { return }
        stickHeld = false
        var v = vel
        let sp = simd_length(v)
        if sp > 8 { v *= 8 / sp }
        stickAir = (heldAt, v)
        stickSpin = 0
        if act != .leave && act != .enter {
            if onFurniture { wantFetch = true } else { bark(-4); start(.fetch, 15) }
        }
    }

    /// 장난감이 나와 있음 (사용법 알림용)
    var hasToy: Bool { stick != nil }

    func leave() {
        guard act != .leave else { return }
        setPant(false)
        start(.leave, 0.6)
    }

    func remove() {
        pantLoop?.stop()
        root.removeFromParent()
        propRoot.removeFromParent()
        done = true
    }

    // MARK: 매 프레임
    func tick(_ dt: Float, _ c: Ctx) {
        guard !done else { return }
        lastCtx = c
        t += dt
        lastDt = dt
        lastHead = c.head
        actT += dt
        frameT += dt
        voiceCool -= dt
        talkT -= dt
        panting -= dt
        floorY = c.floorY
        if let n = pending.first { _ = mat(n); pending.removeFirst() }
        unstick(c)

        let me = SIMD2<Float>(c.head.x, c.head.z)
        let to = pos - me
        let dist = simd_length(to)
        let dir = dist > 0.01 ? to / dist : c.fwd
        let inView = dist > 0.3 && dist < 4.2 && simd_dot(dir, c.fwd) > 0.6
        hidden = inView ? 0 : hidden + dt

        let eye = SIMD3<Float>(pos.x, floorY + elev + 0.3, pos.y) - c.head
        let looking = simd_length(eye) < 3.5 && simd_dot(simd_normalize(eye), c.gaze) > 0.985
        gazeT = looking ? gazeT + dt : 0

        var handNear: SIMD3<Float>? = nil
        var handFast = false
        if !stickHeld {
            for h in c.hands {
                let hp = SIMD2<Float>(h.x, h.z)
                guard simd_distance(hp, pos) < 0.4, h.y - (floorY + elev) < 0.9 else { continue }
                handNear = h
                if let l = lastHands.min(by: { simd_distance($0, h) < simd_distance($1, h) }), dt > 0, simd_distance(l, h) / dt > 0.9 { handFast = true }
            }
        }
        lastHands = c.hands

        let busy = act == .leave || act == .enter || act == .jump || act == .fetch || act == .bring || act == .wait
            || act == .jumpUp || act == .jumpDown
        if !busy {
            if let h = handNear {
                faceToward(SIMD2<Float>(h.x, h.z))
                if handFast && !onFurniture {
                    if act != .jump { goal = nil; yip(-3); emote("exclaim", 1); start(.jump, 1.0) }
                } else if act != .love && act != .sniff {
                    goal = nil
                    frontal = true
                    say("dog_sniff", -6)
                    emote("heart")
                    start(.love, 2.5)
                }
            } else if hidden > 1.3 && (act != .walk || (hidden > 2.2 && !running)) {
                if onFurniture { jumpDownNear(c, prefer: me + c.fwd * 1.3) } else if let s = viewSpot(c, near: 1.4) { go(s, then: .sit, 2.5, run: true) }
            } else if c.userSpeed > 0.3 && act != .walk && !onFurniture {
                followT -= dt
                if followT <= 0, let s = viewSpot(c, near: 1.1) { followT = 0.5; go(s, then: .sit, 2) }
            } else if gazeT > 1.2 && (act == .sit || act == .lie || act == .pant || act == .onTop) && voiceCool <= 0 {
                gazeT = 0
                say("dog_whine", -6)
                emote("question", 1.2)
                frontal = true
                start(.tilt, 1.8)
            }
        }

        // 혼잣말
        if talkT <= 0 {
            talkT = Float.random(in: 7...15)
            switch act {
            case .sleep: emote("zzz", 2)
            case .walk where sniffing: say("dog_sniff", -8)
            case .leave, .enter, .wait: break
            default:
                let r = Int.random(in: 0...5)
                if r == 0 { bark(-8) } else if r == 1 { yip(-9) } else if r == 2 { say("dog_whine", -12) } else if r == 3 { panting = 5 }
            }
        }
        setPant(panting > 0 && act != .sleep && act != .howl && act != .bark)

        switch act {
        case .enter:
            opacity = min(1, opacity + dt * 2.5)
            root.components.set(OpacityComponent(opacity: opacity))
            if opacity >= 1 { frontal = true; start(.sit, 1.5) }
            show("dog_fsit1")
        case .leave:
            opacity = max(0, opacity - dt * 2)
            root.components.set(OpacityComponent(opacity: opacity))
            if opacity <= 0 { remove(); return }
        case .walk:
            stepWalk(dt, c)
        case .sit:
            sitFrame()
            if actT > actDur { decide(c) }
        case .pant, .love:
            show(frontal ? loop(["dog_fhappy", "dog_fsit1"], fps: 2) : loop(["dog_pant0", "dog_pant1"], fps: 3))
            if actT > actDur { start(onFurniture ? .onTop : .sit, onFurniture ? 5 : 2) }
        case .lie:
            show(loop(["dog_lie0", "dog_lie1"], fps: 0.3))
            if actT > actDur || (c.userSpeed > 0.4 && actT > 1) { start(.sit, 1.5) }
        case .sleep:
            show(loop(["dog_sleep0", "dog_sleep1"], fps: 0.45))
            if (actT > actDur && !c.seated) || c.userSpeed > 0.4 {
                yip(-8)
                if onFurniture { start(.onTop, 2) } else { start(.bow, 1.4) }
            }
        case .sniff:
            show(loop(["dog_sniff0", "dog_sniff1"], fps: 3))
            if actT > actDur { start(.sit, 1.2) }
        case .dig:
            show(loop(["dog_dig0", "dog_dig1"], fps: 7))
            if actT > actDur { panting = 4; start(.sit, 1.5) }
        case .roll:
            show(loop(["dog_roll0", "dog_roll1"], fps: 3))
            if actT > actDur { start(.sit, 1.5) }
        case .bow:
            show(loop(["dog_bow0", "dog_bow1"], fps: 3))
            if actT > actDur { if Bool.random() { zoomies(c) } else { start(.sit, 1.5) } }
        case .jump:
            let k = min(1, actT / actDur)
            hop = abs(sin(k * .pi * 2)) * 0.1
            show(loop(["dog_jump0", "dog_jump1"], fps: 5))
            if k >= 1 { hop = 0; panting = 4; start(.sit, 1.2) }
        case .bark:
            show(actT.truncatingRemainder(dividingBy: 0.6) < 0.3 ? "dog_bark" : "dog_stand0")
            if actT > actDur { start(.sit, 1.5) }
        case .howl:
            show("dog_howl")
            if actT > actDur { start(onFurniture ? .onTop : .sit, 2) }
        case .tilt:
            show(frontal ? "dog_ftilt" : "dog_sit0")
            if actT > actDur { start(onFurniture ? .onTop : .sit, 2) }
        case .paw:
            show("dog_paw")
            if actT > actDur { start(.sit, 1.5) }
        case .wait:
            stepWait(dt, c)
        case .fetch:
            stepFetch(dt, c)
        case .bring:
            stepBring(dt, c)
        case .jumpUp, .jumpDown:
            let k = min(1, actT / actDur)
            let p = jumpFrom + (jumpTo - jumpFrom) * k
            pos = SIMD2<Float>(p.x, p.z)
            elev = p.y + 4 * k * (1 - k) * 0.25
            show(k < 0.2 ? "dog_jump0" : (k < 0.85 ? "dog_jump1" : "dog_jump0"))
            if k >= 1 {
                elev = jumpTo.y
                say("dog_tag\(Int.random(in: 1...2))", -12)
                if act == .jumpUp {
                    start(.onTop, Float.random(in: 5...10))
                } else if wantFetch && stick != nil {
                    wantFetch = false
                    start(stickHeld ? .wait : .fetch, stickHeld ? 60 : 15)
                } else {
                    start(.sit, 1.5)
                }
            }
        case .onTop:
            // 가구 위: 엎드려 쉬다가 헥헥, 가끔 잠 — 막대 놀이가 시작되면 내려옴
            let phase = actT / actDur
            if phase < 0.25 { sitFrame() } else { show(loop(["dog_lie0", "dog_lie1"], fps: 0.3)) }
            if c.seated && phase > 0.5 && actDur < 20 { start(.sleep, Float.random(in: 15...30)); break }
            if wantFetch { jumpDownNear(c, prefer: stickPos) } else if actT > actDur { jumpDownNear(c, prefer: me + c.fwd * 1.2) }
        }
        tickStick(dt, c)
        tickBubble(dt)
        place(c)
    }

    private func sitFrame() {
        blinkT -= lastDt
        if blinkT < 0 { blinkT = Float.random(in: 2.5...6) }
        if blinkT < 0.15 { show(frontal ? "dog_fblink" : "dog_blink"); return }
        if panting > 0 { show(frontal ? loop(["dog_fhappy", "dog_fsit1"], fps: 3) : loop(["dog_pant0", "dog_pant1"], fps: 3)); return }
        show(frontal ? loop(["dog_fsit0", "dog_fsit1"], fps: 0.6) : loop(["dog_sit0", "dog_sit1"], fps: 2.2))   // 꼬리 살랑
    }

    private func place(_ c: Ctx) {
        let p3 = SIMD3<Float>(pos.x, floorY + elev + hop, pos.y)
        root.position = p3
        let d = c.head - p3
        let want = atan2(d.x, d.z)
        var diff = want - yaw
        while diff > .pi { diff -= 2 * .pi }
        while diff < -.pi { diff += 2 * .pi }
        yaw += diff * min(1, lastDt * 8)
        let q = simd_quatf(angle: yaw, axis: [0, 1, 0])
        // 가까이서 내려다볼 때도 잘 보이게 그림 판을 내 눈 쪽으로 젖힘 (발밑을 축으로)
        let flat = max(0.2, simd_length(SIMD2<Float>(d.x, d.z)))
        let pitch = min(0.95, max(0, atan2(d.y - 0.3, flat))) * 0.8
        let tilt = simd_quatf(angle: -pitch, axis: [1, 0, 0])
        card.orientation = q * tilt
        bubble.orientation = q * tilt
        var sx = face
        if turnT >= 0 {
            turnT += lastDt
            let k = min(1, turnT / 0.3)
            let w = 0.8 + 0.2 * abs(cos(k * .pi))
            sx = (k < 0.5 ? turnFrom : face) * w
            if k >= 1 { turnT = -1 }
        }
        card.scale = SIMD3<Float>(sx, 1, 1)
        if act == .jumpUp || act == .jumpDown {
            shadow?.position = [0, min(0, min(jumpTo.y, jumpFrom.y) - elev), 0]
        } else {
            shadow?.position = [0, -hop, 0]
        }
        // 물고 있는 막대: 입 앞 (옆모습이면 주둥이 쪽, 정면·뒷모습이면 가운데) — 판이 젖혀진 만큼 같이
        if carrying, let s = stick {
            let r = cardRight()
            let frontish = shown.contains("fwalk") || shown.contains("bwalk") || shown.contains("fsit") || shown.contains("fhappy")
            let side: Float = frontish ? 0 : 0.27 * face
            let mouth = SIMD2<Float>(pos.x, pos.y) + r * side
            s.position = SIMD3<Float>(mouth.x, floorY + elev + hop + (frontish ? 0.31 : 0.35), mouth.y)
            s.orientation = simd_quatf(angle: atan2(r.x, r.y), axis: [0, 1, 0]) * simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
        }
    }

    private func tickBubble(_ dt: Float) {
        guard bubbleT >= 0 else { return }
        bubbleT += dt
        let k = bubbleT
        let pop: Float = k < 0.18 ? (k / 0.18) * 1.15 : (k < 0.3 ? 1.15 - (k - 0.18) / 0.12 * 0.15 : 1)
        let fade: Float = k > bubbleDur - 0.3 ? max(0, (bubbleDur - k) / 0.3) : 1
        bubble.scale = SIMD3<Float>(repeating: max(0.01, pop * fade))
        let top: Float = (act == .sleep || act == .lie || act == .onTop) ? 0.34 : 0.58
        bubble.position = [0.11 * face, top + hop + 0.02 * sin(t * 3), 0]
        if k > bubbleDur { bubble.isEnabled = false; bubbleT = -1 }
    }

    private func cardRight() -> SIMD2<Float> {
        let d = SIMD2<Float>(lastHead.x - pos.x, lastHead.z - pos.y)
        let y = atan2(d.x, d.y)
        return SIMD2<Float>(cos(y), -sin(y))
    }

    private func faceToward(_ p: SIMD2<Float>) {
        let v = p - pos
        guard simd_length(v) > 0.02 else { return }
        let nf: Float = simd_dot(v, cardRight()) >= 0 ? 1 : -1
        if nf != face { turnFrom = face; face = nf; turnT = 0 }
    }

    private func walkFrame(_ v: SIMD2<Float>) -> String {
        let toMe = SIMD2<Float>(lastHead.x - pos.x, lastHead.z - pos.y)
        let c = simd_length(toMe) > 0.01 ? simd_dot(simd_normalize(v), simd_normalize(toMe)) : 0
        if turnT >= 0 { return "dog_fwalk1" }
        if c > 0.6 { return loop(Self.fwalkFrames, fps: running ? 10 : 6) }
        if c < -0.6 { return loop(Self.bwalkFrames, fps: running ? 10 : 6) }
        if sniffing { return loop(["dog_sniff0", "dog_sniff1"], fps: 4) }
        return running ? loop(Self.runFrames, fps: 12) : loop(Self.walkFrames, fps: 8)
    }

    private func jingle(_ dt: Float) {
        tagT -= dt
        if tagT <= 0 {
            tagT = running ? Float.random(in: 0.4...0.7) : Float.random(in: 1.0...1.8)
            Sfx.play("dog_tag\(Int.random(in: 1...2))", in: root, at: [0.15 * face, 0.3, 0], gain: running ? -10 : -15)
        }
    }

    /// 바닥에 있는데 그림 판이 가구·벽에 파고드는 자리면(가구가 새로 보였거나 밀려 들어감) 가장 가까운 넉넉한 빈자리로 비켜남
    private func unstick(_ c: Ctx) {
        guard elev < 0.02, ![Act.jumpUp, .onTop, .jumpDown, .enter, .leave].contains(act), !c.free(pos) else { return }
        for r in stride(from: Float(0.1), through: 1.2, by: 0.1) {
            for k in 0..<16 {
                let a = Float(k) / 16 * 2 * .pi
                let q = pos + SIMD2<Float>(cos(a), sin(a)) * r
                if c.free(q) { pos += (q - pos) * min(1, lastDt * 3); return }
            }
        }
    }

    private func stepWalk(_ dt: Float, _ c: Ctx) {
        guard let g = goal else { start(.sit, 1.5); return }
        let v = g - pos
        let d = simd_length(v)
        let speed: Float = running ? 1.8 : (sniffing ? 0.4 : 0.75)
        if d > 0.001 { moveDir = v / d }
        show(walkFrame(moveDir))
        jingle(dt)
        if d < 0.06 {
            goal = nil
            if running { panting = 5 }
            let toMe = SIMD2<Float>(lastHead.x - pos.x, lastHead.z - pos.y)
            frontal = simd_length(toMe) > 0.01 && simd_dot(moveDir, simd_normalize(toMe)) > 0.2 ? true : Float.random(in: 0...1) < 0.5
            start(then, thenDur)
            return
        }
        let np = pos + v / d * min(d, speed * dt)
        if !c.free(np) && c.free(pos) { goal = nil; start(.sit, 1); return }
        faceToward(g)
        pos = np
    }

    private func zoomies(_ c: Ctx) {
        if let s = roamSpot(c, far: true) {
            go(s, then: .bow, 1.2, run: true)
        } else {
            start(.jump, 1.0)
        }
    }

    // MARK: 막대
    private func makeStick(near p: SIMD2<Float>) {
        guard stick == nil else { return }
        let m: RealityKit.Material
        if look == .line {
            m = Ink.paper(1)
        } else {
            var um = UnlitMaterial(color: UIColor(red: 0.48, green: 0.33, blue: 0.2, alpha: 1))
            if let tx = Tex.with(look == .color ? .color : .mono, { Tex.get("stick") }) {
                var tp = MaterialParameters.Texture(tx); tp.sampler = Tex.tiling
                um.color = .init(tint: .white, texture: tp)
            }
            m = um
        }
        let e = ModelEntity(mesh: .generateCylinder(height: 0.36, radius: 0.016), materials: [m])
        let twig = ModelEntity(mesh: .generateCylinder(height: 0.09, radius: 0.007), materials: [m])
        twig.position = [0.025, 0.07, 0]
        twig.orientation = simd_quatf(angle: -0.7, axis: [0, 0, 1])
        e.addChild(twig)
        if look == .line {
            var l = Geo()
            l.stroke([0, -0.18, 0], [0, 0.18, 0], width: 0.005)
            if let le = l.entity("stickLine", Ink.line) { e.addChild(le) }
        }
        e.name = "dogstick"
        e.components.set(CollisionComponent(shapes: [ShapeResource.generateBox(size: [0.14, 0.44, 0.14])]))
        e.components.set(InputTargetComponent())
        e.components.set(ToyTag())
        propRoot.addChild(e)
        stick = e
        stickPos = p
        carrying = true                          // 처음엔 물고 나타남
    }

    private func dropStick() {
        guard carrying else { return }
        carrying = false
        let r = cardRight()
        stickPos = pos + r * 0.3 * face
        if let c = lastCtx, !c.free(stickPos) { stickPos = pos }
        stickYaw = Float.random(in: 0...3)
        if onFurniture { stickAir = (SIMD3<Float>(stickPos.x, floorY + elev, stickPos.y), .zero) }    // 가구 위에서 놓으면 떨어짐
    }

    private func tickStick(_ dt: Float, _ c: Ctx) {
        guard let s = stick, !carrying else { return }
        if stickHeld {
            s.position = heldAt
            let r = cardRight()
            s.orientation = simd_quatf(angle: atan2(r.x, r.y), axis: [0, 1, 0]) * simd_quatf(angle: .pi / 2 - 0.3, axis: [0, 0, 1])
            stickPos = SIMD2<Float>(heldAt.x, heldAt.z)
            return
        }
        if var air = stickAir {
            var vel = air.1
            let st = HomeCat.toyStep(air.0, &vel, dt, c, radius: 0.05)
            var np = st.0
            if st.1 && simd_length(vel) > 1 { Sfx.play("fire_pop1", in: propRoot, at: np, gain: -26) }   // 벽·가구에 탁 부딪힘
            air.1 = vel
            stickSpin += dt * min(14, simd_length(air.1) * 2.2)
            if np.y <= floorY + 0.02 {
                np.y = floorY + 0.02
                if air.1.y < -2 {
                    air.1.y = -air.1.y * 0.25
                    air.1.x *= 0.5; air.1.z *= 0.5
                    Sfx.play("fire_pop1", in: propRoot, at: np, gain: -24)          // 나무 막대가 바닥에 탁
                } else {
                    stickPos = SIMD2<Float>(np.x, np.z)
                    stickYaw = atan2(air.1.x, air.1.z)
                    stickAir = nil
                    s.position = np
                    return
                }
            }
            air.0 = np
            stickAir = air
            stickPos = SIMD2<Float>(np.x, np.z)
            s.position = np
            let hv = SIMD2<Float>(air.1.x, air.1.z)
            let ax = simd_length(hv) > 0.05 ? simd_normalize(SIMD3<Float>(hv.y, 0, -hv.x)) : SIMD3<Float>(1, 0, 0)
            s.orientation = simd_quatf(angle: stickSpin, axis: ax) * simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
            return
        }
        s.position = SIMD3<Float>(stickPos.x, floorY + 0.016, stickPos.y)
        s.orientation = simd_quatf(angle: stickYaw, axis: [0, 1, 0]) * simd_quatf(angle: .pi / 2, axis: [0, 0, 1])
    }

    /// 막대를 든 나를 기다림: 내 앞 80cm 쯤에 와서 놀자 자세로 들썩, 가끔 멍
    private func stepWait(_ dt: Float, _ c: Ctx) {
        guard stickHeld else { start(.sit, 1); return }
        let me = SIMD2<Float>(c.head.x, c.head.z)
        var target = me + c.fwd * 0.85
        if !c.free(target) { target = viewSpot(c, near: 0.9) ?? pos }
        let v = target - pos
        let d = simd_length(v)
        if d > 0.15 {
            running = d > 0.8
            moveDir = v / d
            show(walkFrame(moveDir))
            jingle(dt)
            let np = pos + moveDir * min(d, (running ? 1.6 : 0.8) * dt)
            if c.free(np) { pos = np }
            faceToward(target)
        } else {
            faceToward(SIMD2<Float>(heldAt.x, heldAt.z))
            let k = actT.truncatingRemainder(dividingBy: 2.4)
            show(k < 1.6 ? loop(["dog_bow0", "dog_bow1"], fps: 4) : loop(["dog_fhappy", "dog_fsit1"], fps: 4))
            panting = 2
            if voiceCool <= 0 && Int.random(in: 0...90) == 0 { bark(-6) }
        }
    }

    private func stepFetch(_ dt: Float, _ c: Ctx) {
        guard stick != nil else { start(.sit, 1); return }
        if stickHeld { start(.wait, 60); return }
        running = true
        sniffing = false
        let target = stickPos
        let v = target - pos
        let d = simd_length(v)
        if d > 0.001 { moveDir = v / d }
        show(walkFrame(moveDir))
        jingle(dt)
        if d < 0.46 && stickAir == nil {                          // 가구 곁의 막대도 입이 닿게 (몸은 가구에서 여유를 둠)
            carrying = true
            say("dog_playgrowl", -8)
            start(.bring, 12)
            return
        }
        if actT > actDur { start(.sit, 2); return }
        // 곧장 못 가면(가구에 막힘) 옆으로 비켜 돌아감
        let step = min(max(0, d - 0.22), 1.9 * dt)
        for ang in [Float(0), 0.6, -0.6, 1.2, -1.2, 1.8, -1.8] {
            let dv = SIMD2<Float>(moveDir.x * cos(ang) - moveDir.y * sin(ang), moveDir.x * sin(ang) + moveDir.y * cos(ang))
            if c.free(pos + dv * step) { pos += dv * step; break }
        }
        faceToward(target)
    }

    private func stepBring(_ dt: Float, _ c: Ctx) {
        let me = SIMD2<Float>(c.head.x, c.head.z)
        var target = me + c.fwd * 0.6
        if !c.free(target) { target = viewSpot(c, near: 0.7) ?? pos }
        let v = target - pos
        let d = simd_length(v)
        running = d > 1.0
        if d > 0.001 { moveDir = v / d }
        show(walkFrame(moveDir))
        jingle(dt)
        if d < 0.12 || actT > actDur {
            dropStick()
            frontal = true
            panting = 6
            yip(-4)
            emote("heart")
            start(.bow, 1.6)
            return
        }
        let np = pos + moveDir * min(d, (running ? 1.6 : 0.75) * dt)
        if c.free(np) { pos = np } else { dropStick(); start(.sit, 2) }
        faceToward(target)
    }

    // MARK: 가구 오르내리기
    /// 시야 안 낮은 가구(30~65cm, 평평한 윗면) 위로: 가구 옆 바닥까지 걸어가서 폴짝
    private func jumpUpSomewhere(_ c: Ctx) -> Bool {
        let me = SIMD2<Float>(c.head.x, c.head.z)
        var found: [(SIMD2<Float>, SIMD2<Float>, Float)] = []
        for dd in stride(from: Float(0.8), through: Float(3.0), by: 0.2) {
            for a in stride(from: Float(-0.9), through: Float(0.9), by: 0.15) {
                let v = SIMD2<Float>(c.fwd.x * cos(a) - c.fwd.y * sin(a), c.fwd.x * sin(a) + c.fwd.y * cos(a))
                let p = me + v * dd
                guard let h = c.top(p), h >= 0.3, h <= 0.65 else { continue }
                let back = simd_normalize(pos - p)
                var q = p
                var ok: SIMD2<Float>? = nil
                for _ in 0..<8 {
                    q += back * 0.1
                    if c.free(q) { ok = q; break }
                }
                guard let f = ok, pathOK(pos, f, c) else { continue }
                let land = f - back * (simd_distance(f, p) + 0.12)
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

    private func jumpDownNear(_ c: Ctx, prefer: SIMD2<Float>) {
        var best: (SIMD2<Float>, Float)? = nil
        for k in 0..<16 {
            let a = Float(k) / 16 * 2 * .pi
            for r in [Float(0.4), 0.6, 0.8] {
                let p = pos + SIMD2<Float>(cos(a), sin(a)) * r
                guard c.free(p) else { continue }
                let s = simd_distance(p, prefer)
                if best == nil || s < best!.1 { best = (p, s) }
            }
        }
        guard let b = best else { start(.onTop, 3); return }
        jumpFrom = SIMD3<Float>(pos.x, elev, pos.y)
        jumpTo = SIMD3<Float>(b.0.x, 0, b.0.y)
        faceToward(b.0)
        start(.jumpDown, 0.5)
    }

    // MARK: 무엇을 할지
    private func decide(_ c: Ctx) {
        let me = SIMD2<Float>(c.head.x, c.head.z)
        let dist = simd_distance(pos, me)
        if c.seated {
            if dist > 0.9, let s = sideSpot(c, 0.65) { go(s, then: .lie, Float.random(in: 8...14)); return }
            start(Bool.random() ? .lie : .sleep, Float.random(in: 15...30))
            return
        }
        // 가만히 서 있으면 발치에 와서 마주 보고 앉음
        if c.still > 3, dist > 0.75, Float.random(in: 0...1) < 0.45 {
            let s = me + c.fwd * 0.6
            if c.free(s) && pathOK(pos, s, c) { go(s, then: .pant, 3); return }
        }
        var opts: [(Float, () -> Bool)] = []
        opts.append((1.2, { [unowned self] in start(.sit, Float.random(in: 1.5...3)); return true }))
        opts.append((0.8, { [unowned self] in start(.lie, Float.random(in: 4...8)); return true }))
        opts.append((0.7, { [unowned self] in panting = 5; start(.pant, 2.5); return true }))
        // 이곳저곳 킁킁거리며 돌아다니기
        opts.append((3.2, { [unowned self] in
            guard let s = roamSpot(c, far: false) else { return false }
            go(s, then: Bool.random() ? .sniff : .sit, Float.random(in: 1.2...2.5), sniff: Bool.random()); return true
        }))
        opts.append((1.6, { [unowned self] in jumpUpSomewhere(c) }))
        opts.append((0.8, { [unowned self] in start(.dig, Float.random(in: 2...3.5)); return true }))
        opts.append((0.7, { [unowned self] in say("dog_playgrowl", -8); start(.roll, 2.4); return true }))
        opts.append((0.8, { [unowned self] in bark(-6); start(.bow, 1.6); return true }))
        opts.append((0.5, { [unowned self] in bark(-7); start(.bark, 1.4); return true }))
        opts.append((0.25, { [unowned self] in say("dog_howl", -8); emote("note", 2.4); start(.howl, 2.6); return true }))
        opts.append((0.9, { [unowned self] in zoomies(c); return true }))
        // 막대를 물고 와서 발치에 놓음 (놀자는 뜻)
        opts.append((stick == nil ? 2.6 : 3.2, { [unowned self] in          // 막대 놀이는 자주
            if stick == nil { makeStick(near: pos) }
            start(carrying ? .bring : .fetch, 10)
            return true
        }))
        if c.still > 20 { opts.append((1.0, { [unowned self] in start(.sleep, Float.random(in: 12...25)); return true })) }
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
        start(.sit, 2)
    }

    private func pathOK(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: Ctx) -> Bool {
        let d = simd_distance(a, b)
        let n = max(1, Int(d / 0.1))
        for i in 1...n where !c.free(a + (b - a) * (Float(i) / Float(n))) { return false }
        return true
    }

    /// 돌아다닐 곳: 내 앞쪽 넓게(양옆 75도) 빈 바닥 중 지금 자리에서 떨어져 있고 바로 갈 수 있는 곳 아무 데나
    private func roamSpot(_ c: Ctx, far: Bool) -> SIMD2<Float>? {
        let me = SIMD2<Float>(c.head.x, c.head.z)
        for _ in 0..<24 {
            let a = Float.random(in: -1.3...1.3)
            let dd = far ? Float.random(in: 1.6...3.4) : Float.random(in: 0.9...3.2)
            let v = SIMD2<Float>(c.fwd.x * cos(a) - c.fwd.y * sin(a), c.fwd.x * sin(a) + c.fwd.y * cos(a))
            let p = me + v * dd
            if c.free(p) && simd_distance(p, pos) > (far ? 1.0 : 0.6) && pathOK(pos, p, c) { return p }
        }
        return nil
    }

    private func viewSpot(_ c: Ctx, near: Float) -> SIMD2<Float>? {
        let me = SIMD2<Float>(c.head.x, c.head.z)
        var best: (SIMD2<Float>, Float)? = nil
        for dd in stride(from: Float(0.7), through: Float(2.8), by: 0.2) {
            for a in stride(from: Float(-0.6), through: Float(0.6), by: 0.125) {
                let v = SIMD2<Float>(c.fwd.x * cos(a) - c.fwd.y * sin(a), c.fwd.x * sin(a) + c.fwd.y * cos(a))
                let p = me + v * dd
                guard c.free(p) else { continue }
                var score = abs(dd - near) + abs(abs(a) - 0.3) * 0.6 + simd_distance(p, pos) * 0.15
                if !pathOK(pos, p, c) { score += 2.5 }
                if best == nil || score < best!.1 { best = (p, score) }
            }
        }
        return best?.0
    }

    private func sideSpot(_ c: Ctx, _ r: Float) -> SIMD2<Float>? {
        let me = SIMD2<Float>(c.head.x, c.head.z)
        for a in [Float(0.6), -0.6, 0.35, -0.35, 0.9, -0.9] {
            let v = SIMD2<Float>(c.fwd.x * cos(a) - c.fwd.y * sin(a), c.fwd.x * sin(a) + c.fwd.y * cos(a))
            let p = me + v * r
            if c.free(p) { return p }
        }
        return nil
    }
}
