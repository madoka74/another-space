import Foundation
import UIKit
import RealityKit
import simd

/// 집 테마의 고양이 '방울이': 선 그림 카툰 고양이(그림 판이 늘 나를 바라봄)가 내 근처를 따라다니며 놂.
/// - 보는 방향에 맞는 그림: 나에게 걸어오면 정면, 멀어지면 뒷모습, 옆으로 가면 옆모습. 방향을 바꿀 땐 정면을 거쳐 돌아섬
/// - 늘 내 시야 안: 시야 밖으로 벗어나면 보이는 자리로 뛰어 들어옴. 내가 걸으면 앞쪽 옆을 종종걸음으로 따라옴
/// - 가구와 놀기: 평평한 가구 위로 폴짝 올라가 앉거나 식빵 굽거나 잠, 가구 옆면을 긁기
/// - 털실 공: 혼자 꺼내 와서 사냥하듯 노려보다 덮치고 굴리며 놂. 공을 톡 치면 멀리 굴러가고 쫓아감
/// - 나와 놀기: 가만히 서 있으면 발치에 와서 부비부비(그르릉), 앉으면 옆에 와서 꾹꾹이·식빵·잠, 손을 내밀면 머리를 비빔,
///   손을 빠르게 흔들면 냥냥펀치, 오래 바라보면 올려다보며 야옹
/// - 톡 치면(바라보고 탭): 그때그때 다르게 — 뒹굴며 짹, 지그시 눈 감고 그르릉, 고개 갸웃, 깜짝 폴짝, 다가와 부비, 덮치기, 야옹.
///   자고 있으면 하품하며 깸, 너무 자꾸 치면 털을 세우고 하악 한 뒤 토라져 멀어짐
/// - 머리 위 말풍선(♥ ? ! z ♪ 💢)과 여러 목소리(야옹 9가지·므릅·짹·하품·채터링·하악·그르릉), 걸을 때 목줄 방울 딸랑
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
        var pass: (SIMD2<Float>) -> Bool         // 지나갈 수 있는 바닥 (free 에 문이 쓸고 지나가는 자리까지 — 문을 지나 옆방으로 갈 때)
        var top: (SIMD2<Float>) -> Float?        // 올라앉을 수 있는 가구 윗면 높이 (바닥에서)
        var height: (SIMD2<Float>) -> Float      // 그 자리 가구 높이 (없으면 0)
        var room: (SIMD2<Float>) -> Bool         // 장난감이 날아다닐 수 있는 곳 (이 테마 방 안, 벽에서 6cm 넘게)
        var ceil: Float                          // 천장 높이 (바닥에서)
    }

    /// 그 자리가 내 시야 안인지 (앞 53° 안, 4.2m 안 — 강아지·고양이가 '보이는 곳'을 고를 때와 같은 기준)
    static func inView(_ p: SIMD2<Float>, _ c: Ctx) -> Bool {
        let v = p - SIMD2<Float>(c.head.x, c.head.z)
        let d = simd_length(v)
        return d < 4.2 && (d < 0.3 || simd_dot(v / d, c.fwd) > 0.6)
    }

    /// 날아가는 장난감이 벽·천장·가구에 부딪히는지 (가구는 그 윗면보다 낮을 때만)
    static func toyHit(_ p: SIMD3<Float>, _ c: Ctx, radius r: Float) -> Bool {
        let q = SIMD2<Float>(p.x, p.z)
        if !c.room(q) { return true }
        return c.height(q) > p.y - c.floorY - r
    }

    /// 날아가는 장난감 한 걸음: 중력, 천장에서 튕겨 내려옴, 벽·가구 옆면에 부딪히면 그 면에서 튕겨 나옴(방 밖으로 나가지 않음).
    /// 가구 윗면에 떨어지면 거기서 한 번 통 튀고 내 쪽으로 미끄러져 내려옴 (예전엔 윗면에서 계속 튕기며 공중 상태로 남아
    /// 빙글빙글 돌기만 하고 강아지·고양이가 쫓아가지 않았음). 벽 속에 끼면 내 쪽으로 빼냄.
    /// 반환: 새 자리, 부딪혔는지
    static func toyStep(_ p: SIMD3<Float>, _ v: inout SIMD3<Float>, _ dt: Float, _ c: Ctx, radius r: Float) -> (SIMD3<Float>, Bool) {
        // 빠르게 던지면 한 프레임에 10cm 넘게 날아가 벽을 건너뛸 수 있음 → 4cm씩 나눠서 확인
        let n = max(1, min(12, Int((simd_length(v) * dt / 0.04).rounded(.up))))
        var q = inside(p, c, radius: r)
        var hit = false
        for _ in 0..<n {
            let st = toyStep1(q, &v, dt / Float(n), c, radius: r)
            q = st.0
            hit = hit || st.1
        }
        // 그래도 방 밖(벽 너머)이면 방 안 가장 가까운 자리로 되돌림 — 벽 너머에 떨어져 보이지 않게 되고 강아지가 그쪽에 붙박이던 문제
        let fixed = inside(q, c, radius: r)
        if fixed != q { hit = true; v.x = -v.x * 0.3; v.z = -v.z * 0.3 }
        return (fixed, hit)
    }

    /// 길 찾기: 10cm 칸 위에서 설 수 있는 바닥(c.free)만 지나 a → (b에서 reach 안의 아무 칸)까지 가는 길 (경유점, 30cm 간격).
    /// 가구가 가로막아 곧장 못 가는 장난감도 돌아서 감 (예전엔 앞만 보고 비켜 가다 막힌 구석에서 멈춰 섰음). 못 가면 nil
    /// 찾는 칸 범위: 두 점을 감싼 사각형 + 둘레 2.5m (가구를 크게 돌아가는 길도), 칸이 160×160을 넘으면 칸을 키움.
    /// (예전엔 둘레 2m·90×90칸(9m)까지만 봐서, 5m 넘게 떨어졌거나 크게 돌아가야 하는 곳은 길이 없다고 보고 먼 곳에 멈춰 있었음)
    /// 지금 자리가 가구·벽에 조금 걸쳐 있으면(지나갈 수 없는 칸) 둘레 20cm 안은 지나갈 수 있는 것으로 쳐서 빠져나오게
    static func plan(from a: SIMD2<Float>, to b: SIMD2<Float>, reach: Float, _ c: Ctx) -> [SIMD2<Float>]? {
        let lo = simd_min(a, b) - SIMD2<Float>(repeating: 2.5), hi = simd_max(a, b) + SIMD2<Float>(repeating: 2.5)
        let cs: Float = max(0.1, max(hi.x - lo.x, hi.y - lo.y) / 160)
        let nx = min(160, Int(((hi.x - lo.x) / cs).rounded(.up))), nz = min(160, Int(((hi.y - lo.y) / cs).rounded(.up)))
        guard nx > 1, nz > 1 else { return nil }
        func cp(_ i: Int, _ j: Int) -> SIMD2<Float> { lo + SIMD2<Float>((Float(i) + 0.5) * cs, (Float(j) + 0.5) * cs) }
        func cell(_ p: SIMD2<Float>) -> (Int, Int) { (min(nx - 1, max(0, Int((p.x - lo.x) / cs))), min(nz - 1, max(0, Int((p.y - lo.y) / cs)))) }
        var ok = [Int8](repeating: -1, count: nx * nz)          // -1 모름, 0 막힘, 1 빈 바닥
        let (si, sj) = cell(a)
        let esc = c.pass(a) ? -1 : Int((0.2 / cs).rounded(.up))      // 지금 자리가 막힌 칸일 때만 둘레 20cm를 빠져나갈 길로 침
        func free(_ i: Int, _ j: Int) -> Bool {
            let k = j * nx + i
            if ok[k] < 0 { ok[k] = (c.pass(cp(i, j)) || (abs(i - si) <= esc && abs(j - sj) <= esc)) ? 1 : 0 }
            return ok[k] == 1
        }
        var prev = [Int32](repeating: -1, count: nx * nz)
        let s0 = sj * nx + si
        prev[s0] = Int32(s0)
        var q = [s0], qi = 0, goal = -1
        // 도착 칸: reach 안의 칸, 또는 목표가 든 칸 — reach 가 칸 크기(10cm)보다 작으면 칸 가운데가 그 안에 들지 않아
        // 길이 없다고 보는 일이 많았음 (v0.5.36: 앞발·입 자리처럼 5cm로 찾으면 대부분 실패 → 동물이 제자리에서 물음표·포기)
        let (bi, bj) = cell(b)
        let bk = bj * nx + bi
        let near = max(reach, cs * 0.75)
        while qi < q.count {
            let k = q[qi]; qi += 1
            let i = k % nx, j = k / nx
            if k == bk || simd_distance(cp(i, j), b) <= near { goal = k; break }
            for (di, dj) in [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)] {
                let x = i + di, y = j + dj
                guard x >= 0, y >= 0, x < nx, y < nz else { continue }
                let n = y * nx + x
                guard prev[n] < 0, free(x, y) else { continue }
                if di != 0 && dj != 0 && (!free(i + di, j) || !free(i, j + dj)) { continue }     // 모서리를 비스듬히 뚫지 않게
                prev[n] = Int32(k)
                q.append(n)
            }
        }
        guard goal >= 0 else { return nil }
        var cells: [Int] = []
        var k = goal
        while k != s0 { cells.append(k); k = Int(prev[k]) }
        cells.reverse()
        // 경유점: 곧장 가도 막히지 않는 데까지 건너뜀 (5cm마다 c.free 확인). 예전엔 칸 셋마다 하나씩 골라 가구 모서리를 돌 때
        // 경유점 사이 직선이 가구 모서리를 지나 '막힘' → 같은 길을 다시 찾고 또 막혀, 제자리에서 발만 구르는 일이 있었음
        let pts = cells.map { cp($0 % nx, $0 / nx) }
        func clear(_ p: SIMD2<Float>, _ q: SIMD2<Float>) -> Bool {
            let n = max(1, Int((simd_distance(p, q) / 0.05).rounded(.up)))
            for i in 1...n where !c.pass(p + (q - p) * (Float(i) / Float(n))) { return false }
            return true
        }
        var out: [SIMD2<Float>] = []
        var anchor = a
        var i = 0
        while i < pts.count {
            var j = i
            while j + 1 < pts.count && clear(anchor, pts[j + 1]) { j += 1 }
            out.append(pts[j])
            anchor = pts[j]
            i = j + 1
        }
        // 마지막 칸 가운데에서 목표 자리까지 (갈 수 있으면) — 앞발·입이 장난감에 정확히 닿게
        if c.pass(b) && clear(anchor, b) && simd_distance(anchor, b) > 0.005 { out.append(b) }
        return out
    }

    /// 방 안(장난감이 다닐 수 있는 곳)이면 그대로, 아니면 둘레를 넓혀 가며 찾은 가장 가까운 방 안 자리 (못 찾으면 내 쪽으로)
    static func inside(_ p: SIMD3<Float>, _ c: Ctx, radius r: Float) -> SIMD3<Float> {
        let q = SIMD2<Float>(p.x, p.z)
        if c.room(q) { return p }
        for d in stride(from: Float(0.05), through: 2.0, by: 0.05) {
            for k in 0..<16 {
                let a = Float(k) / 16 * 2 * .pi
                let t = q + SIMD2<Float>(cos(a), sin(a)) * d
                if c.room(t) && c.height(t) < 0.05 { return SIMD3<Float>(t.x, max(p.y, c.floorY + r), t.y) }
            }
        }
        return SIMD3<Float>(c.head.x, max(p.y, c.floorY + r), c.head.z)
    }

    private static func toyStep1(_ p: SIMD3<Float>, _ v: inout SIMD3<Float>, _ dt: Float, _ c: Ctx, radius r: Float) -> (SIMD3<Float>, Bool) {
        v.y -= 9.8 * dt
        var np = p + v * dt
        var hit = false
        let top = c.floorY + c.ceil - 0.06 - r
        if np.y > top { np.y = top; v.y = -abs(v.y) * 0.35; hit = true }
        let q = SIMD2<Float>(np.x, np.z)
        var toMe = SIMD2<Float>(c.head.x - np.x, c.head.z - np.z)
        toMe = simd_length(toMe) > 0.01 ? simd_normalize(toMe) : SIMD2<Float>(0, 0)
        // 가구 윗면에 위에서 떨어짐
        let fh = c.room(q) ? c.height(q) : 0
        if fh > 0.05 && np.y - r <= c.floorY + fh && p.y - r >= c.floorY + fh - 0.04 {
            np.y = c.floorY + fh + r
            v.y = v.y < -1.6 ? -v.y * 0.3 : 0
            v.x = v.x * 0.55 + toMe.x * 0.55
            v.z = v.z * 0.55 + toMe.y * 0.55
            return (np, v.y > 0)
        }
        if toyHit(np, c, radius: r) {
            let tx = SIMD3<Float>(np.x, np.y, p.z), tz = SIMD3<Float>(p.x, np.y, np.z)
            var any = false
            if toyHit(tx, c, radius: r) { v.x = -v.x * 0.45; any = true }
            if toyHit(tz, c, radius: r) { v.z = -v.z * 0.45; any = true }
            if !any { v.x = -v.x * 0.45; v.z = -v.z * 0.45 }
            np.x = p.x; np.z = p.z
            hit = true
            // 그래도 벽·가구 속이면 내 쪽으로 조금씩 빼냄
            if toyHit(np, c, radius: r) {
                np.x += toMe.x * 0.06; np.z += toMe.y * 0.06
                v.x = toMe.x * 0.4; v.z = toMe.y * 0.4
            }
        }
        return (np, hit)
    }

    let root = Entity()                          // 고양이 자리 (저장 좌표, 발밑)
    let ballRoot = Entity()                      // 털실 공 (저장 좌표)
    private(set) var done = false
    private let card = ModelEntity()
    private let bubble = ModelEntity()
    private var shadow: ModelEntity?
    private let look: LookMode
    private var mats: [String: UnlitMaterial] = [:]
    private var pending: [String] = []

    private enum Act {
        case sit, walk, jumpUp, onTop, jumpDown, groom, stretch, loaf, sleep, flop, scratch, roll, swat, rub, meow, look,
             tilt, love, knead, yawn, pounce, puff, chase, hop, enter, leave,
             weave,                                      // 내 발치를 빙 돌며 다리에 몸을 비빔
             spin                                        // 제 꼬리를 쫓아 빙글빙글
    }
    private var act: Act = .enter
    private var actT: Float = 0
    private var actDur: Float = 1
    private var pos: SIMD2<Float>
    private var elev: Float = 0                  // 바닥에서 높이 (가구 위면 그 높이)
    private var face: Float = 1                  // 옆모습 방향 (1 오른쪽, -1 왼쪽)
    private var turnFrom: Float = 1
    private var turnT: Float = -1                // 돌아서는 중 (0~0.26초)
    private var frontal = false                  // 앉을 때 나를 마주 봄
    private var moveDir = SIMD2<Float>(1, 0)
    private var goal: SIMD2<Float>?
    private var running = false
    private var then: Act = .sit                 // 걸어가서 할 일
    private var thenDur: Float = 3
    private var jumpFrom = SIMD3<Float>(0, 0, 0), jumpTo = SIMD3<Float>(0, 0, 0)
    private var t: Float = 0
    private var frameT: Float = 0
    private var blinkT: Float = 3
    private var hidden: Float = 0                // 시야 밖에 있은 시간
    private var playUntil: Float = 0             // 이때까지는 내가 공으로 놀아 주는 중 (집기·던지기·차기) — 그동안은 공을 쫓느라 시야 밖에 있어도 됨
    private var gazeT: Float = 0
    private var meowCool: Float = 4
    private var talkT: Float = 8                 // 다음 혼잣말
    private var bellT: Float = 0
    private var followT: Float = 0
    private var lastHands: [SIMD3<Float>] = []
    private var purr: AudioPlaybackController?
    private var purrOn = false
    private var opacity: Float = 0
    private var scratchDir: SIMD2<Float> = SIMD2<Float>(1, 0)
    private var floorY: Float = 0
    private var yaw: Float = 0
    private var lastHead = SIMD3<Float>(0, 1.5, 0)
    private var lastDt: Float = 1 / 90
    private var taps: [Float] = []
    private var sulkUntil: Float = 0
    // 덮치기
    private var pounceTo = SIMD2<Float>(0, 0)
    private var pounceFrom = SIMD2<Float>(0, 0)
    // 털실 공
    private var ball: ModelEntity?
    private var ballPos = SIMD2<Float>(0, 0)
    private var ballVel = SIMD2<Float>(0, 0)
    private var ballSpin = simd_quatf(angle: 0, axis: [0, 1, 0])
    private var hits = 0
    private var hitsMax = 4
    private var ballHeld = false                 // 내가 손으로 집고 있음
    private var nav = PetNav()                    // 공까지 돌아가는 길
    private var heldAt = SIMD3<Float>(0, 0, 0)
    private var ballAir: (SIMD3<Float>, SIMD3<Float>)?    // 던져서 날아가는 중 (자리, 빠르기)
    private var wantChase = false                // 가구 위에서 공을 보면 내려와서 쫓음
    private var seekAt: Float = 0                // 이때까지는 '시야 밖 → 보이는 자리로'를 다시 고르지 않음 (갈 곳이 없거나 막혔을 때)
    private var weaveA: Float = 0                // 발치 돌기: 나를 중심으로 한 각도
    private var weaveDir: Float = 1
    private var weaveLeft: Float = 0             // 남은 각도
    private var spinT: Float = 0                 // 꼬리 쫓기: 다음에 돌아서는 때까지
    private var inviteMe = false                 // 공을 내 쪽으로 쳐서 보냄 (같이 놀자)
    private var landT: Float = -10               // 뛰어내려 앉은 때 (내려앉으며 살짝 눌리는 모습)
    private var reachCache: PetReach?
    private var reachT: Float = -10
    // 말풍선
    private var bubbleT: Float = -1
    private var bubbleDur: Float = 1.4

    private static let walkFrames = (0..<6).map { "cat_walk\($0)" }
    private static let runFrames = (0..<4).map { "cat_run\($0)" }
    private static let fwalkFrames = (0..<4).map { "cat_fwalk\($0)" }
    private static let bwalkFrames = (0..<4).map { "cat_bwalk\($0)" }
    private static let all: [String] = ["cat_sit0", "cat_sit1", "cat_blink", "cat_meow", "cat_look", "cat_lookmeow", "cat_groom0", "cat_groom1",
                                        "cat_swat0", "cat_swat1", "cat_loaf0", "cat_loaf1", "cat_sleep0", "cat_sleep1", "cat_stretch0", "cat_stretch1",
                                        "cat_jump0", "cat_jump1", "cat_scratch0", "cat_scratch1", "cat_roll0", "cat_roll1", "cat_rub0", "cat_rub1",
                                        "cat_fsit0", "cat_fsit1", "cat_fblink", "cat_fmeow", "cat_ftilt", "cat_flove", "cat_bsit",
                                        "cat_yawn", "cat_tilt", "cat_slowblink", "cat_knead0", "cat_knead1", "cat_pounce0", "cat_pounce1", "cat_pounce2",
                                        "cat_flop0", "cat_flop1", "cat_puff"]
                                       + walkFrames + runFrames + fwalkFrames + bwalkFrames

    init(at p: SIMD2<Float>, floorY: Float, look: LookMode) {
        self.look = look
        self.pos = p
        self.floorY = floorY
        // 그림 판: 55cm 정사각, 발 맨 아래(그림의 481/512 줄 — 그려진 그림에서 잰 값)가 바닥에 닿게
        // (예전엔 470으로 잡아 발이 6mm쯤 바닥에 묻혔고, 방 바닥 판이 6mm 위에 있어 더 묻혀 보였음 → 판 전체를 8mm 띄움 — show)
        let s: Float = 0.55
        var g = Geo()
        let y0: Float = -s * (31.0 / 512.0)
        g.quad(SIMD3<Float>(-s / 2, y0, 0), SIMD3<Float>(s / 2, y0, 0), SIMD3<Float>(s / 2, y0 + s, 0), SIMD3<Float>(-s / 2, y0 + s, 0),
               SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(1, 1), SIMD2<Float>(0, 1))
        if let m = g.mesh("cat") { card.model = ModelComponent(mesh: m, materials: [UnlitMaterial(color: .clear)]) }
        card.name = "homecat"
        // 탭 판은 그림 판 두께만큼 얇게 (2cm): 예전 18cm 두께 상자는 앞면이 그림보다 9cm 앞에 있어, 앞발 곁의 털실 공을 집으려 해도
        // 시선이 고양이 상자에 먼저 닿아 고양이 탭이 되고 공이 안 잡혔음 → 그림 판 자리 언저리의 장난감(둘레 9cm 구)이 먼저 잡힘
        card.components.set(CollisionComponent(shapes: [ShapeResource.generateBox(size: [0.48, 0.42, 0.02]).offsetBy(translation: [0, 0.2, 0])]))
        card.components.set(InputTargetComponent())
        root.addChild(card)
        // 말풍선 판 (16cm)
        var bq = Geo()
        let b: Float = 0.16
        bq.quad(SIMD3<Float>(-b / 2, 0, 0), SIMD3<Float>(b / 2, 0, 0), SIMD3<Float>(b / 2, b, 0), SIMD3<Float>(-b / 2, b, 0),
                SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(1, 1), SIMD2<Float>(0, 1))
        if let m = bq.mesh("bubble") { bubble.model = ModelComponent(mesh: m, materials: [UnlitMaterial(color: .clear)]) }
        bubble.isEnabled = false
        root.addChild(bubble)
        // 발밑 그림자 (부드러운 타원)
        var sg = Geo()
        sg.quad(SIMD3<Float>(-0.26, 0.012, -0.12), SIMD3<Float>(0.26, 0.012, -0.12), SIMD3<Float>(0.26, 0.012, 0.12), SIMD3<Float>(-0.26, 0.012, 0.12),
                SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(1, 1), SIMD2<Float>(0, 1))
        var sm = UnlitMaterial(color: UIColor(white: 0, alpha: 1))
        if let mask = Tex.get("glow_a", raw: true) {
            var mp = MaterialParameters.Texture(mask); mp.sampler = Tex.clamp
            sm.blending = .transparent(opacity: .init(scale: 0.42, texture: mp))      // 발밑이 바닥에 닿아 보이게 조금 짙게
            sm.writesDepth = false                 // 반투명 판이 뒤의 나무·물건을 네모나게 지우지 않게
        } else {
            sm.blending = .transparent(opacity: .init(floatLiteral: 0.15))
            sm.writesDepth = false                 // 반투명 판이 뒤의 나무·물건을 네모나게 지우지 않게
        }
        if let e = sg.entity("catShadow", sm) { shadow = e; root.addChild(e) }
        root.position = SIMD3<Float>(p.x, floorY, p.y)
        // 그리는 순서: 포털(0번) 뒤에 그림자 → 몸 → 말풍선 (하늘·풍경 쪽에서 지워지지 않게)
        if let sh = shadow { Sorting.apply(sh, 27) }
        Sorting.apply(card, 28)
        Sorting.apply(bubble, 29)
        root.setOpacity(0)
        pending = Self.all
        show("cat_fwalk0")
        Sfx.play("cat_trill", in: root, at: [0, 0.25, 0], gain: -4)
        emote("heart")
    }

    // MARK: 그림
    private func mat(_ n: String) -> UnlitMaterial {
        if let m = mats[n] { return m }
        var m = UnlitMaterial(color: .white)
        let mode: LookMode = look == .color ? .color : .mono          // 선 그림·흑백에선 목줄·말풍선도 무채색
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
    /// 그림마다 몸 맨 아래가 기본(481)보다 더 아래로 그려진 장(누운 자세) — 그만큼 판을 올려 바닥에 딱 닿게 (픽셀)
    private static let footPx: [String: Float] = ["cat_loaf0": 7, "cat_loaf1": 5, "cat_roll0": 3, "cat_roll1": 3, "cat_sleep0": 30, "cat_sleep1": 30]
    private func show(_ n: String) {
        guard n != shown else { return }
        shown = n
        card.model?.materials = [mat(n)]
        card.position.y = 0.003 + (Self.footPx[n] ?? 0) * 0.55 / 512      // 발 끝이 방 바닥 판(6mm 위)에 3mm 닿아 묻히게 — 떠 보이지 않게 (보이는 묻힘은 1mm 남짓)
    }

    private func loop(_ frames: [String], fps: Float) -> String {
        let i = Int(frameT * fps) % max(1, frames.count)
        return frames[i]
    }

    /// 머리 위 말풍선 (♥ ? ! z ♪ 💢)
    private func emote(_ name: String, _ dur: Float = 1.5) {
        bubble.model?.materials = [mat("emote_" + name)]
        bubble.isEnabled = true
        bubbleT = 0
        bubbleDur = dur
    }

    // MARK: 소리
    /// 소리마다 재생 빠르기를 조금씩 달리 (0.96~1.12배 — 같은 녹음도 매번 조금 다른 높이로, 살짝 높게 해서 귀엽게)
    private func say(_ name: String, _ gain: Double = -3) {
        meowCool = Float.random(in: 7...14)          // 스스로 내는 소리 사이 (탭엔 늘 바로 대답)
        Sfx.play(name, in: root, at: [0, 0.3, 0], gain: min(0, gain), rolloff: 0.6, speed: Double.random(in: 0.96...1.12))      // 실제 고양이 녹음, 거리에 따라 덜 줄게
    }
    /// 야옹: 아기 고양이 미야(7가지)·짧은 냥(11가지)을 자주, 어른 고양이 야옹(14가지)은 가끔 — 실제 녹음 중 앱에 들어 있는 것에서 고름
    private func meow(_ gain: Double = -3) {
        let r = Float.random(in: 0...1)
        let pool: [String] = r < 0.4 ? (1...7).map { "cat_kitten\($0)" } : (r < 0.75 ? (1...11).map { "cat_mew\($0)" } : (1...14).map { "cat_meow\($0)" })
        say(Sfx.pick(pool) ?? "cat_meow\(Int.random(in: 1...9))", gain)
    }
    /// 므릅·인사: 짧은 냥·트릴
    private func mrrp(_ gain: Double = -4) {
        say(Sfx.pick((1...11).map { "cat_mew\($0)" } + ["cat_mrrp1", "cat_mrrp2", "cat_mrrp3", "cat_trill"]) ?? "cat_trill", gain)
    }
    private func chirp(_ gain: Double = -4) {
        say(Sfx.pick(["cat_chirp", "cat_chirp2", "cat_chirp3"] + (7...11).map { "cat_mew\($0)" }) ?? "cat_chirp", gain)
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
        nav.reset()
        act = a
        actT = 0
        actDur = dur
        frameT = 0
        if a != .chase && a != .swat { inviteMe = false }
        reachSide = nil
        reachFlipped = false
        switch a {
        case .rub, .loaf, .sleep, .flop, .knead, .love, .weave: break
        default: setPurr(false)
        }
    }

    /// 걸어가서(멀면 뛰어서) 그 일을 함
    private func go(_ to: SIMD2<Float>, then a: Act, _ dur: Float, run: Bool = false) {
        goal = to
        then = a
        thenDur = dur
        running = run || simd_distance(to, pos) > 1.6
        start(.walk, 30)
    }

    /// 톡 침 (바라보고 탭)
    /// 탭할 때마다 꼭 소리로 대답함 (멀리서도 또렷하게 — say는 거리에 따라 덜 줄어듦)
    func poke() {
        guard act != .leave && act != .enter else { return }
        if act == .jumpUp || act == .jumpDown { mrrp(0); emote("exclaim"); return }     // 뛰는 중엔 대답만
        taps = taps.filter { t - $0 < 6 } + [t]
        goal = nil
        // 너무 자꾸 치면 토라짐
        if taps.count >= 4 {
            taps.removeAll()
            say("cat_growl", -1)
            emote("anger")
            frontal = false
            start(.puff, 1.3)
            sulkUntil = t + 12
            return
        }
        if elev > 0.05 {
            mrrp(0)
            emote("question")
            start(.tilt, 1.8)
            return
        }
        switch act {
        case .sleep, .flop, .loaf, .knead:
            say("cat_yawn", -1)
            emote("question")
            start(.yawn, 1.6)
            return
        case .chase, .pounce:
            chirp(0)
            emote("exclaim")
            return
        default: break
        }
        let me = SIMD2<Float>(lastHead.x, lastHead.z)
        switch Int.random(in: 0...6) {
        case 0:
            chirp(0); emote("heart"); start(.roll, 2.4)
        case 1:
            mrrp(0); setPurr(true); emote("heart"); frontal = true; start(.love, 3.5)
        case 2:
            mrrp(0); emote("question"); start(.tilt, 1.8)
        case 3:
            say("cat_mew", 0); emote("exclaim"); start(.hop, 0.55)
        case 4:
            let s = me + simd_normalize(pos - me) * 0.45
            if simd_distance(pos, me) > 0.7 {
                say("cat_trill", 0); emote("heart"); go(s, then: .rub, 3)
            } else {
                say("cat_trill", 0); emote("heart"); start(.rub, 3); setPurr(true)
            }
        case 5:
            say("cat_chatter", -1); emote("exclaim")
            let d = simd_length(me - pos) > 0.01 ? simd_normalize(me - pos) : moveDir
            pounceFrom = pos
            pounceTo = pos + d * 0.35
            faceToward(pounceTo)
            start(.pounce, 1.6)
        default:
            meow(0); emote("note"); start(.meow, 1.4)
        }
    }

    /// 털실 공을 톡 침: 나에게서 먼 쪽으로 굴러가고 고양이가 쫓아감
    func kickBall(from head: SIMD3<Float>) {
        guard ball != nil else { return }
        playUntil = t + 12
        let me = SIMD2<Float>(head.x, head.z)
        var d = ballPos - me
        d = simd_length(d) > 0.01 ? simd_normalize(d) : SIMD2<Float>(0, 1)
        ballVel = d * 1.6
        if let b = ball { Sfx.play("cup_clink1", in: b, at: .zero, gain: -30) }
        if act != .jumpUp && act != .jumpDown && elev < 0.05 {
            hits = 0
            hitsMax = Int.random(in: 3...6)
            chirp(-2)
            emote("exclaim")
            start(.chase, 12)
        }
    }

    /// 털실 공을 손으로 집음: 공이 손을 따라오고, 고양이는 다가와 엉덩이를 씰룩이며 노림
    func holdBall(at p: SIMD3<Float>) {
        guard ball != nil else { return }
        playUntil = t + 12
        if !ballHeld {
            ballHeld = true
            ballAir = nil
            ballVel = .zero
            if let b = ball { Sfx.play("cat_chirp", in: b, at: .zero, gain: -12) }
            if elev > 0.05 { wantChase = true } else if act != .jumpUp && act != .jumpDown && act != .leave && act != .enter {
                hits = 0
                hitsMax = Int.random(in: 3...6)
                emote("exclaim", 1)
                start(.chase, 30)
            }
        }
        heldAt = p
        ballPos = SIMD2<Float>(p.x, p.z)
    }

    /// 놓음: 손의 빠르기 그대로 날아가 떨어져 통통 튀고 굴러감 → 쫓아가 덮침
    func releaseBall(vel: SIMD3<Float>) {
        guard ballHeld else { return }
        playUntil = t + 12
        ballHeld = false
        var v = vel
        let sp = simd_length(v)
        if sp > 7 { v *= 7 / sp }
        ballAir = (heldAt, v)
        if elev > 0.05 { wantChase = true } else if act != .leave && act != .enter {
            chirp(-2)
            start(.chase, 14)
        }
    }

    /// 가구 위에서 가까운 다른 가구 윗면으로 폴짝 (높이 차 50cm 안)
    private func hopTop(_ c: Ctx) -> Bool {
        var found: [(SIMD2<Float>, Float)] = []
        for k in 0..<16 {
            let a = Float(k) / 16 * 2 * .pi
            for r in [Float(0.4), 0.6, 0.85, 1.1] {
                let p = pos + SIMD2<Float>(cos(a), sin(a)) * r
                guard let h = c.top(p), h >= 0.3, h <= 1.2, abs(h - elev) < 0.5 else { continue }
                found.append((p, h))
            }
        }
        guard let pick = found.randomElement() else { return false }
        jumpFrom = SIMD3<Float>(pos.x, elev, pos.y)
        jumpTo = SIMD3<Float>(pick.0.x, pick.1, pick.0.y)
        faceToward(pick.0)
        start(.jumpUp, 0.5)
        return true
    }

    /// 집이 아닌 방으로 가면 사라짐
    /// 장난감이 나와 있음 (사용법 알림용)
    var hasToy: Bool { ball != nil }

    func leave() {
        guard act != .leave else { return }
        setPurr(false)
        start(.leave, 0.6)
    }

    func remove() {
        purr?.stop()
        root.removeFromParent()
        ballRoot.removeFromParent()
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
        talkT -= dt
        floorY = c.floorY
        if let n = pending.first { _ = mat(n); pending.removeFirst() }            // 그림을 한 프레임에 하나씩 미리 읽음
        unstick(c)
        settle(dt, c)

        // 나와의 관계
        let me = SIMD2<Float>(c.head.x, c.head.z)
        let to = pos - me
        let dist = simd_length(to)
        let dir = dist > 0.01 ? to / dist : c.fwd
        let inView = dist > 0.25 && dist < 4.2 && simd_dot(dir, c.fwd) > 0.74
        hidden = inView ? 0 : hidden + dt

        // 바라보고 있나 (고양이 쪽 3m 안에서 시선이 8도 안)
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

        let busy = act == .jumpUp || act == .jumpDown || act == .leave || act == .enter || act == .puff || act == .hop || act == .weave || act == .spin
        if !busy {
            if let h = handNear, act != .roll && act != .chase {
                faceToward(SIMD2<Float>(h.x, h.z))
                if handFast {
                    if act != .swat { goal = nil; start(.swat, 1.0); chirp(-3); emote("exclaim", 1) }
                } else if act != .rub && act != .swat {
                    goal = nil
                    start(.rub, 3)
                    setPurr(true)
                    emote("heart")
                    if meowCool <= 0 { say("cat_trill", -3) }
                }
            } else if hidden > 1.4 && t >= seekAt && (act != .chase || t > playUntil) && (act != .walk || (hidden > 2.4 && !running)) {
                // (혼자 공놀이하다 시야 밖으로 벗어났으면 공은 두고 내가 보는 쪽으로 — 예전엔 공 곁에만 머물렀음)
                // 시야 밖 → 보이는 자리로 (걸어서 갈 수 있는 곳만 — PetReach). 갈 곳이 없으면 그 자리에서 나를 부르고 2초 뒤 다시 봄
                if elev > 0.05 { jumpDownNear(c, prefer: me + c.fwd * 1.4) } else if let s = viewSpot(c, near: 1.5), simd_distance(s, pos) > 0.3 { go(s, then: .sit, 4, run: true) } else {
                    seekAt = t + 2
                    if act != .meow { meow(-4); frontal = true; start(.meow, 1.4) }
                }
            } else if c.userSpeed > 0.35 && act != .walk && act != .chase && elev < 0.05 {
                // 내가 걸으면 앞쪽 옆을 따라옴
                followT -= dt
                if followT <= 0, let s = viewSpot(c, near: 1.3) { followT = 0.6; go(s, then: .sit, 2.5) }
            } else if gazeT > 2.5 && (act == .sit || act == .loaf || act == .onTop || act == .groom) && meowCool <= 0 {
                gazeT = 0
                meow()
                emote("note", 1.2)
                start(.look, 2.2)
            }
        }

        // 혼잣말 (자는 중엔 가끔 그르릉만)
        if talkT <= 0 {
            talkT = Float.random(in: 20...45)          // 진짜 고양이처럼 가끔만 (예전 7~16초는 너무 잦았음)
            switch act {
            case .sleep, .flop: if Bool.random() { emote("zzz", 2) }
            case .chase, .pounce: say("cat_chatter", -6)
            case .walk: if Bool.random() { mrrp(-6) }
            case .leave, .enter, .puff: break
            default:
                let r = Int.random(in: 0...3)
                if r == 0 { meow(-6) } else if r == 1 { mrrp(-6) } else if r == 2 { chirp(-7) } else if dist < 1.5 { say("cat_trill", -6) }
            }
        }

        switch act {
        case .enter:
            opacity = min(1, opacity + dt * 2.5)
            root.setOpacity(opacity)
            if opacity >= 1 { frontal = true; start(.sit, 1.5) }
            show("cat_fsit0")
        case .leave:
            opacity = max(0, opacity - dt * 2)
            root.setOpacity(opacity)
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
                landT = t
                if act == .jumpUp {
                    start(.onTop, Float.random(in: 5...11))
                } else if wantChase && ball != nil {
                    wantChase = false
                    start(.chase, 12)
                } else {
                    start(.sit, 2)
                }
            }
        case .onTop:
            // 가구 위: 앉아 있다가 그루밍·식빵·잠을 번갈아
            let phase = actT / actDur
            if phase < 0.3 { sitFrame() } else if phase < 0.55 { show(loop(["cat_groom0", "cat_groom1"], fps: 3)) } else { show(loop(["cat_loaf0", "cat_loaf1"], fps: 0.4)) }
            if wantChase { jumpDownNear(c, prefer: ballPos) } else if actT > actDur {
                // 옆 가구로 폴짝 건너가거나(가구 위를 돌아다님) 내려옴
                if !(Float.random(in: 0...1) < 0.55 && hopTop(c)) { jumpDownNear(c, prefer: me + c.fwd * 1.3) }
            }
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
        case .sleep, .flop:
            show(act == .sleep ? loop(["cat_sleep0", "cat_sleep1"], fps: 0.45) : loop(["cat_flop0", "cat_flop1"], fps: 0.4))
            setPurr(c.seated)
            if (actT > actDur && !c.seated) || c.userSpeed > 0.4 {
                say("cat_yawn", -6)
                start(.yawn, 1.4)
            }
        case .yawn:
            show("cat_yawn")
            if actT > actDur { start(.stretch, 1.8) }
        case .knead:
            show(loop(["cat_knead0", "cat_knead1"], fps: 2.2))
            setPurr(true)
            if actT > actDur { start(c.seated ? (Bool.random() ? .sleep : .loaf) : .loaf, Float.random(in: 12...25)) }
        case .scratch:
            faceToward(pos + scratchDir)
            show(loop(["cat_scratch0", "cat_scratch1"], fps: 5))
            if actT > actDur { start(.sit, 2) }
        case .roll:
            show(loop(["cat_roll0", "cat_roll1"], fps: 3))
            if actT > actDur { start(.sit, 2) }
        case .swat:
            show(loop(["cat_swat0", "cat_swat1"], fps: 6))
            if actT > actDur {
                if inviteMe {
                    // 공을 내 쪽으로 보냈음: 나를 올려다보며 야옹 (다시 던져 달라는 듯)
                    inviteMe = false
                    frontal = true
                    meow(-3)
                    emote("note", 1.4)
                    start(.meow, 1.6)
                } else if ball != nil && hits > 0 && hits < hitsMax { start(.chase, 10) } else { start(.sit, 1.5) }
            }
        case .weave:
            // 내 발치를 한 바퀴 빙 돌며 다리에 몸을 비빔: 내 앞을 지날 땐 부비 그림, 옆·뒤는 걷는 그림, 그르릉
            if actT <= lastDt + 1e-4 { weaveA = atan2(pos.y - me.y, pos.x - me.x); weaveLeft = 2 * .pi }
            let rr: Float = 0.36
            let da = 0.3 * dt / rr
            weaveA += weaveDir * da
            weaveLeft -= da
            let p = me + SIMD2<Float>(cos(weaveA), sin(weaveA)) * rr
            if c.pass(p) && simd_distance(p, pos) < 0.2 {
                let v = p - pos
                if simd_length(v) > 1e-4 { moveDir = simd_normalize(v) }
                pos = p
            } else {
                weaveLeft = 0                                         // 가구·벽에 막히면 그만
            }
            let toCat = simd_length(pos - me) > 0.01 ? simd_normalize(pos - me) : c.fwd
            faceToward(pos + moveDir)
            show(simd_dot(toCat, c.fwd) > 0.55 ? loop(["cat_rub0", "cat_rub1"], fps: 2.2) : walkFrame(moveDir))
            setPurr(true)
            if weaveLeft <= 0 || c.userSpeed > 0.35 {
                setPurr(false)
                frontal = true
                say("cat_trill", -4)
                emote("heart", 1.2)
                start(.sit, 2.5)
            }
        case .spin:
            // 제 꼬리를 쫓아 빙글빙글: 좌우로 재빨리 돌아서며 종종걸음, 끝나면 어지러운 듯 갸웃
            spinT -= dt
            if spinT <= 0 { spinT = 0.24; turnFrom = face; face = -face; turnT = 0 }
            show(loop(Self.runFrames, fps: 12))
            if actT > actDur { frontal = true; emote("question", 1.2); start(.tilt, 1.4) }
        case .rub:
            show(loop(["cat_rub0", "cat_rub1"], fps: 2.2))
            if actT > actDur || (handNear == nil && c.userSpeed > 0.3) {
                setPurr(false)
                if c.still > 3 && Bool.random() { start(.knead, 4) } else { frontal = true; start(.sit, 2) }
            }
        case .meow:
            show(actT < 0.9 ? (frontal ? "cat_fmeow" : "cat_meow") : (frontal ? "cat_fsit0" : "cat_sit0"))
            if actT > actDur { start(elev > 0.05 ? .onTop : .sit, elev > 0.05 ? 6 : 2) }
        case .look:
            show(actT < 0.9 ? "cat_lookmeow" : "cat_look")
            if actT > actDur { start(elev > 0.05 ? .onTop : .sit, elev > 0.05 ? 6 : 2.5) }
        case .tilt:
            show(frontal ? "cat_ftilt" : "cat_tilt")
            if actT > actDur { start(elev > 0.05 ? .onTop : .sit, elev > 0.05 ? 6 : 2) }
        case .love:
            show(frontal ? (actT.truncatingRemainder(dividingBy: 2.2) < 1.6 ? "cat_flove" : "cat_fsit0") : "cat_slowblink")
            if actT > actDur { setPurr(false); start(.sit, 2) }
        case .hop:
            // 깜짝 놀라 제자리에서 폴짝
            let k = min(1, actT / actDur)
            elev = 4 * k * (1 - k) * 0.16
            show("cat_jump0")
            if k >= 1 { elev = 0; landT = t; start(.sit, 1.5) }
        case .puff:
            show("cat_puff")
            if actT > actDur {
                // 토라져서 멀어진 곳으로 가서 그루밍
                if let s = viewSpot(c, near: 2.3) { go(s, then: .groom, 3) } else { start(.groom, 3) }
            }
        case .pounce:
            // 엉덩이 씰룩 → 휙 덮침
            if actT < actDur * 0.65 {
                // 노려보며 몸을 낮추고 살금살금 다가감 (덮칠 자리에서 35cm 앞까지), 그 자리에서 휙
                let v = pounceTo - pos
                if simd_length(v) > 0.35 {
                    let np = pos + simd_normalize(v) * min(simd_length(v) - 0.35, 0.16 * lastDt)
                    if c.free(np) { pos = np }
                }
                pounceFrom = pos
                show(loop(["cat_pounce0", "cat_pounce1"], fps: 7))
            } else {
                let k = min(1, (actT - actDur * 0.65) / (actDur * 0.35))
                let p = pounceFrom + (pounceTo - pounceFrom) * k
                if c.free(p) { pos = p }
                elev = 4 * k * (1 - k) * 0.1
                show("cat_pounce2")
            }
            if actT > actDur {
                elev = 0
                if ball != nil && pawTouch(ballPos) { faceToward(ballPos); hitBall(); start(.swat, 0.5) } else { start(.roll, 1.6) }
            }
        case .chase:
            stepChase(dt, c)
        }
        tickBall(dt, c)
        tickBubble(dt)
        place(c)
    }

    private func sitFrame() {
        blinkT -= lastDt
        if blinkT < 0 { blinkT = Float.random(in: 2.5...6) }
        if blinkT < 0.15 { show(frontal ? "cat_fblink" : "cat_blink"); return }
        show(frontal ? loop(["cat_fsit0", "cat_fsit1"], fps: 1.1) : loop(["cat_sit0", "cat_sit1"], fps: 1.1))
    }

    /// 그림 판을 나에게 향하게(부드럽게), 돌아설 땐 정면을 거쳐 좌우가 바뀜, 그림자·말풍선
    private func place(_ c: Ctx) {
        let p3 = SIMD3<Float>(pos.x, floorY + elev, pos.y)
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
        let pitch = min(0.95, max(0, atan2(d.y - 0.2, flat))) * 0.5      // 많이 젖히면 바닥에서 일어선 판처럼 떠 보여 덜 젖힘
        card.orientation = q * simd_quatf(angle: -pitch, axis: [1, 0, 0])
        bubble.orientation = q * simd_quatf(angle: -pitch, axis: [1, 0, 0])
        // 돌아서기: 0.26초 동안 정면 그림을 거침 (가로로 살짝 좁아졌다 넓어짐)
        var sx = face
        if turnT >= 0 {
            turnT += lastDt
            let k = min(1, turnT / 0.26)
            let w = 0.82 + 0.18 * abs(cos(k * .pi))
            sx = (k < 0.5 ? turnFrom : face) * w
            if k >= 1 { turnT = -1 }
        }
        // 숨쉬기: 가만히 앉거나 누워 있을 땐 몸이 아주 조금 오르내림 / 뛰어내려 앉을 땐 잠깐 살짝 눌렸다 펴짐
        var sy: Float = 1
        switch act {
        case .sit, .loaf, .onTop, .knead, .look, .love, .tilt: sy = 1 + 0.012 * sin(t * 2.4)
        case .sleep, .flop: sy = 1 + 0.018 * sin(t * 1.4)
        default: break
        }
        let lk = (t - landT) / 0.18
        if lk >= 0 && lk < 1 { let q = sin(lk * .pi) * 0.07; sy -= q; sx *= 1 + q * 0.6 }
        card.scale = SIMD3<Float>(sx, sy, 1)
        if let sh = shadow {
            if act == .jumpUp || act == .jumpDown {
                sh.position = [0, min(0, min(jumpTo.y, jumpFrom.y) - elev), 0]       // 뛰는 동안 그림자는 바닥(또는 가구 위)에 남음
            } else if act == .hop || act == .pounce {
                sh.position = [0, -elev, 0]
            } else {
                sh.position = [0, 0, 0]
            }
        }
    }

    private func tickBubble(_ dt: Float) {
        guard bubbleT >= 0 else { return }
        bubbleT += dt
        let k = bubbleT
        // 톡 튀어나와(살짝 커졌다) 둥실 떠 있다가 사라짐
        let pop: Float = k < 0.18 ? (k / 0.18) * 1.15 : (k < 0.3 ? 1.15 - (k - 0.18) / 0.12 * 0.15 : 1)
        let fade: Float = k > bubbleDur - 0.3 ? max(0, (bubbleDur - k) / 0.3) : 1
        bubble.scale = SIMD3<Float>(repeating: max(0.01, pop * fade))
        let top: Float = (act == .sleep || act == .flop || act == .loaf || act == .knead) ? 0.32 : 0.48
        bubble.position = [0.08 * face, top + 0.02 * sin(t * 3), 0]
        if k > bubbleDur { bubble.isEnabled = false; bubbleT = -1 }
    }

    /// 그림의 오른쪽(+X)이 가리키는 수평 방향 (나를 보는 판 기준)
    private func cardRight() -> SIMD2<Float> {
        let d = SIMD2<Float>(lastHead.x - pos.x, lastHead.z - pos.y)
        let y = atan2(d.x, d.y)
        return SIMD2<Float>(cos(y), -sin(y))
    }

    /// 옆모습 방향 정하기 — 바뀌면 정면을 거쳐 돌아섬
    private func faceToward(_ p: SIMD2<Float>) {
        let v = p - pos
        guard simd_length(v) > 0.02 else { return }
        // 나를 향해·등지고 거의 곧게 움직일 땐(옆 성분 25% 안) 지금 방향 그대로 — 좌우가 매 프레임 바뀌며 돌아서는 그림(정면)이
        // 끼어들어 여러 자세가 겹쳐 보이지 않게
        let side = simd_dot(simd_normalize(v), cardRight())
        guard abs(side) > 0.25 else { return }
        let nf: Float = side >= 0 ? 1 : -1
        if nf != face {
            turnFrom = face
            face = nf
            turnT = 0
        }
    }

    /// 걷는 방향이 나를 향하면 정면, 멀어지면 뒷모습, 옆이면 옆모습
    private func walkFrame(_ v: SIMD2<Float>) -> String {
        let toMe = SIMD2<Float>(lastHead.x - pos.x, lastHead.z - pos.y)
        let c = simd_length(toMe) > 0.01 ? simd_dot(simd_normalize(v), simd_normalize(toMe)) : 0
        if turnT >= 0 { return running ? "cat_fwalk0" : "cat_fwalk1" }
        if c > 0.6 { return loop(Self.fwalkFrames, fps: running ? 10 : 6) }
        if c < -0.6 { return loop(Self.bwalkFrames, fps: running ? 10 : 6) }
        return running ? loop(Self.runFrames, fps: 11) : loop(Self.walkFrames, fps: 8)
    }

    private func jingle(_ dt: Float) {
        bellT -= dt
        if bellT <= 0 {
            bellT = running ? Float.random(in: 0.45...0.8) : Float.random(in: 1.1...2.0)
            Sfx.play("bell\(Int.random(in: 1...3))", in: root, at: [0.1, 0.22, 0], gain: running ? -10 : -15)
        }
    }

    /// 받침 확인: 뛰어오르내리는 중이 아닌데 발밑 높이(가구 윗면 또는 바닥)보다 떠 있으면 바로 내려앉음.
    /// (가구 위에 있다가 장난감·손짓 등으로 다른 일을 시작하면 그 높이 그대로 공중을 걸어 다니는 경우가 있었음)
    private func settle(_ dt: Float, _ c: Ctx) {
        guard ![Act.jumpUp, .jumpDown, .enter, .leave].contains(act), elev > 0.005 else { return }
        let ground = c.height(pos)
        if ground < elev - 0.05 {
            elev = max(ground, elev - dt * 2.5)                  // 가장자리를 벗어나면 짧게 뛰어내리듯
            if elev < 0.01 { elev = 0 }
        } else if act != .onTop && ground > 0.05 {
            elev = ground                                         // 가구 위를 걸을 땐 그 윗면 높이에 딱 붙어서
        }
    }

    /// 바닥에 있는데 그림 판이 가구·벽에 파고드는 자리면(가구가 새로 보였거나 밀려 들어감) 가장 가까운 넉넉한 빈자리로 비켜남
    private func unstick(_ c: Ctx) {
        // 걸어 지나가는 중(길 따라 걷기·막대/공 쫓기)엔 지나갈 수 있는 곳(문이 쓸고 지나가는 자리 포함)이면 그대로 — 문간에서 밀려나 멈추지 않게
        let moving = goal != nil || nav.isActive
        guard elev < 0.02, ![Act.jumpUp, .onTop, .jumpDown, .enter, .leave].contains(act), !(moving ? c.pass(pos) : c.free(pos)) else { return }
        for r in stride(from: Float(0.1), through: 1.2, by: 0.1) {
            for k in 0..<16 {
                let a = Float(k) / 16 * 2 * .pi
                let q = pos + SIMD2<Float>(cos(a), sin(a)) * r
                if c.free(q) { pos += (q - pos) * min(1, lastDt * 3); return }
            }
        }
    }

    private func stepWalk(_ dt: Float, _ c: Ctx) {
        guard let g = goal else { start(.sit, 2); return }
        let v = g - pos
        let d = simd_length(v)
        let speed: Float = running ? 1.35 : 0.5
        if d > 0.001 { moveDir = v / d }
        show(walkFrame(moveDir))
        jingle(dt)
        if d < 0.06 {
            goal = nil
            // 나를 향해 오다가 멈추면 마주 보고 앉음
            let toMe = SIMD2<Float>(lastHead.x - pos.x, lastHead.z - pos.y)
            frontal = simd_length(toMe) > 0.01 && simd_dot(moveDir, simd_normalize(toMe)) > 0.3 ? true : Float.random(in: 0...1) < 0.35
            if then == .jumpUp {
                faceToward(SIMD2<Float>(jumpTo.x, jumpTo.z))
                start(.jumpUp, 0.55)
            } else {
                start(then, thenDur)
                switch then {
                case .rub: setPurr(true); say("cat_trill", -3); emote("heart")
                case .scratch: faceToward(pos + scratchDir)
                default: break
                }
            }
            return
        }
        // 길을 찾아 돌아서 감 (가구를 돌고 문을 지나 옆방으로도). 갈 길이 없거나 막히면 다른 일
        // (예전엔 곧장만 걷다 가구·문이 쓸고 지나가는 자리에 막히면 그대로 앉아, 가구 뒤에 걸려 있거나 다른 방으로 따라오지 않았음)
        switch nav.step(from: pos, to: g, reach: 0.05, speed: speed, dt, c) {
        case .move(let np):
            if simd_length(np - pos) > 1e-4 { moveDir = simd_normalize(np - pos) }
            faceToward(pos + moveDir)
            pos = np
        case .hold:
            break
        case .arrived:
            pos = c.free(g) ? g : pos
        case .blocked:
            // 길이 막힘: 1.5초 동안은 '보이는 자리로'를 다시 고르지 않음 (예전엔 앉기 → 다시 고르기 → 막힘을 매 프레임 되풀이해
            // 걷기·앉기 그림이 번갈아 겹쳐 보였음)
            goal = nil
            seekAt = t + 1.5
            start(.sit, 1.5)
        }
    }

    /// 걸어갈 수 있는 바닥 (0.7초 또는 20cm 움직이면 새로 셈)
    private func reachNow(_ c: Ctx) -> PetReach {
        if let r = reachCache, t - reachT < 0.7, simd_distance(r.from, pos) < 0.2 { return r }
        let r = PetReach(from: pos, c)
        reachCache = r
        reachT = t
        return r
    }

    // MARK: 털실 공
    private func makeBall(near p: SIMD2<Float>, _ c: Ctx) -> Bool {
        if ball != nil { return true }
        var spot: SIMD2<Float>? = nil
        for k in 0..<12 {
            let a = Float(k) / 12 * 2 * .pi
            let q = p + SIMD2<Float>(cos(a), sin(a)) * 0.45
            if c.free(q) { spot = q; break }
        }
        guard let s = spot else { return false }
        let m: RealityKit.Material
        if look == .line {
            m = Ink.paper(0)
        } else {
            var um = UnlitMaterial(color: look == .color ? UIColor(red: 0.8, green: 0.2, blue: 0.24, alpha: 1) : UIColor(white: 0.55, alpha: 1))
            if let tx = Tex.with(look == .color ? .color : .mono, { Tex.get("yarn") }) {
                var tp = MaterialParameters.Texture(tx); tp.sampler = Tex.tiling
                um.color = .init(tint: .white, texture: tp)
            }
            m = um
        }
        let e = ModelEntity(mesh: .generateSphere(radius: 0.045), materials: [m])
        e.name = "catball"
        e.components.set(CollisionComponent(shapes: [ShapeResource.generateSphere(radius: 0.09)]))
        e.components.set(InputTargetComponent())
        e.components.set(ToyTag())
        if look == .line {
            var l = Geo()
            for k in 0..<16 {
                let a0 = Float(k) / 16 * 2 * .pi, a1 = Float(k + 1) / 16 * 2 * .pi
                l.stroke(SIMD3<Float>(cos(a0) * 0.046, sin(a0) * 0.046, 0), SIMD3<Float>(cos(a1) * 0.046, sin(a1) * 0.046, 0), width: 0.004)
                l.stroke(SIMD3<Float>(0, sin(a0) * 0.046, cos(a0) * 0.046), SIMD3<Float>(0, sin(a1) * 0.046, cos(a1) * 0.046), width: 0.004)
            }
            if let le = l.entity("ballLines", Ink.line) { e.addChild(le) }
            Ink.hull(e, width: 0.005)                       // 공 외곽선
        }
        ballRoot.addChild(e)
        ball = e
        ballPos = s
        ballVel = .zero
        return true
    }

    private func tickBall(_ dt: Float, _ c: Ctx) {
        guard let b = ball else { return }
        if ballHeld {
            heldAt = HomeDog.heldSpot(heldAt, c, radius: 0.047)       // 바닥 아래·벽 너머로 사라지지 않게
            ballPos = SIMD2<Float>(heldAt.x, heldAt.z)
            b.position = heldAt
            ballSpin = simd_quatf(angle: dt * 1.5, axis: [0, 1, 0]) * ballSpin
            b.orientation = ballSpin
            return
        }
        if var air = ballAir {
            // 날아감: 중력, 벽·가구에 부딪히면 튕겨 나옴, 바닥에 닿으면 통통 튀다 굴러감
            var vel = air.1
            let st = Self.toyStep(air.0, &vel, dt, c, radius: 0.047)
            var np = st.0
            air.1 = vel
            if st.1 && simd_length(vel) > 1 { Sfx.play("cup_clink1", in: b, at: .zero, gain: -36) }
            if np.y <= floorY + 0.047 {
                np.y = floorY + 0.047
                if air.1.y < -1.2 {
                    air.1.y = -air.1.y * 0.35
                    air.1.x *= 0.7; air.1.z *= 0.7
                    Sfx.play("cup_clink1", in: b, at: .zero, gain: -34)
                } else {
                    ballPos = SIMD2<Float>(np.x, np.z)
                    ballVel = SIMD2<Float>(air.1.x, air.1.z) * 0.6
                    ballAir = nil
                    b.position = np
                    return
                }
            }
            air.0 = np
            ballAir = air
            ballPos = SIMD2<Float>(np.x, np.z)
            let hv = SIMD3<Float>(air.1.x, 0, air.1.z)
            if simd_length(hv) > 0.05 { ballSpin = simd_quatf(angle: simd_length(hv) * dt / 0.045, axis: simd_normalize(SIMD3<Float>(hv.z, 0, -hv.x))) * ballSpin }
            b.position = np
            b.orientation = ballSpin
            return
        }
        if !c.room(ballPos) {                                   // 방 밖(벽 너머)에 놓였으면 방 안 가장 가까운 자리로
            let q = Self.inside(SIMD3<Float>(ballPos.x, floorY + 0.047, ballPos.y), c, radius: 0.047)
            ballPos = SIMD2<Float>(q.x, q.z)
        }
        let sp = simd_length(ballVel)
        if sp > 0.01 {
            var np = ballPos + ballVel * dt
            func rollHit(_ q: SIMD2<Float>) -> Bool { Self.toyHit(SIMD3<Float>(q.x, floorY + 0.047, q.y), c, radius: 0.047) }
            if rollHit(np) {                                    // 벽·가구에 부딪히면 튕김 (방 밖으로 나가지 않음)
                let tx = SIMD2<Float>(ballPos.x + ballVel.x * dt, ballPos.y)
                let tz = SIMD2<Float>(ballPos.x, ballPos.y + ballVel.y * dt)
                var any = false
                if rollHit(tx) { ballVel.x = -ballVel.x * 0.6; any = true }
                if rollHit(tz) { ballVel.y = -ballVel.y * 0.6; any = true }
                if !any { ballVel = -ballVel * 0.6 }
                np = ballPos
            }
            ballPos = np
            ballVel *= max(0, 1 - dt * 1.4)                    // 바닥 마찰
            let axis = simd_normalize(SIMD3<Float>(ballVel.y, 0, -ballVel.x))
            ballSpin = simd_quatf(angle: sp * dt / 0.045, axis: axis) * ballSpin
        } else {
            ballVel = .zero
        }
        b.position = SIMD3<Float>(ballPos.x, floorY + 0.047, ballPos.y)
        b.orientation = ballSpin
    }

    /// 그 자리를 보려면 어느 쪽 옆모습이어야 하는지 (faceToward 와 같은 기준 — 옆 성분 25% 안이면 지금 방향 그대로)
    private func sideFor(_ b: SIMD2<Float>) -> Float {
        let v = b - pos
        guard simd_length(v) > 0.02 else { return face }
        let side = simd_dot(simd_normalize(v), cardRight())
        return abs(side) > 0.25 ? (side >= 0 ? 1 : -1) : face
    }
    /// 앞발이 공에 닿는지: 옆모습 그림에서 앞발은 몸 가운데에서 보는 쪽으로 17cm 앞 (공 반지름 4.5cm + 발 크기 안)
    private func pawTouch(_ b: SIMD2<Float>) -> Bool {
        simd_distance(pos + cardRight() * sideFor(b) * 0.17, b) < 0.12
    }
    /// 앞발이 그 자리에 닿도록 몸이 설 자리: 공의 어느 쪽에 설지는 쫓기 시작할 때 한 번 정함(가는 동안 목표가 오락가락하지 않게), 막혔으면 한 번 반대쪽
    private var reachSide: Float?
    private var reachFlipped = false
    private func pawSpot(_ b: SIMD2<Float>) -> SIMD2<Float> {
        let f = reachSide ?? sideFor(b)
        reachSide = f
        return b - cardRight() * f * 0.17
    }

    private func hitBall() {
        guard ball != nil else { return }
        hits += 1
        let me = SIMD2<Float>(lastHead.x, lastHead.z)
        // 대체로 내 앞쪽 시야 안으로 굴러가게
        var d = ballPos - pos
        d = simd_length(d) > 0.01 ? simd_normalize(d) : moveDir
        let side = SIMD2<Float>(-d.y, d.x) * Float.random(in: -0.7...0.7)
        var v = simd_normalize(d + side)
        if simd_distance(ballPos + v * 1.0, me) > 3.0 { v = simd_normalize(me - ballPos + side) }
        ballVel = v * Float.random(in: 0.8...1.5)
        if inviteMe {
            // 같이 놀자: 내 발치(50cm 앞)에서 멈출 만큼 내 쪽으로 (바닥 마찰로 굴러가는 거리 ≈ 빠르기 ÷ 1.4)
            let to = me - ballPos
            let dd = simd_length(to)
            if dd > 0.6 { ballVel = simd_normalize(to) * min(2.4, max(0.5, (dd - 0.5) * 1.4)) }
        }
        if Int.random(in: 0...2) == 0 { chirp(-6) }
    }

    private func stepChase(_ dt: Float, _ c: Ctx) {
        guard ball != nil else { start(.sit, 1); return }
        let v = ballPos - pos
        let d = simd_length(v)
        running = d > 0.5
        if d > 0.001 { moveDir = v / d }
        if ballHeld {
            // 손에 든 공을 노림: 60cm까지 다가와(가구는 돌아서) 엉덩이 씰룩. 더 못 다가가면 그 자리에서 씰룩
            actT = 0
            if d > 0.6, case .move(let np) = nav.step(from: pos, to: ballPos, reach: 0.58, speed: 1.3, dt, c) {
                moveDir = simd_length(np - pos) > 1e-4 ? simd_normalize(np - pos) : moveDir
                show(walkFrame(moveDir))
                pos = np
            } else {
                show(loop(["cat_pounce0", "cat_pounce1"], fps: 6))
            }
            faceToward(ballPos)
            return
        }
        if ballAir != nil {
            // 날아가는 공: 떨어질 쪽으로 따라감 (못 가면 그 자리에서 지켜봄)
            if case .move(let np) = nav.step(from: pos, to: ballPos, reach: 0.25, speed: 1.5, dt, c) {
                moveDir = simd_length(np - pos) > 1e-4 ? simd_normalize(np - pos) : moveDir
                show(walkFrame(moveDir))
                pos = np
            } else {
                show("cat_sit0")
            }
            faceToward(ballPos)
            return
        }
        if simd_length(ballVel) < 0.6 && pawTouch(ballPos) {       // 앞발(그림의 앞발 자리)이 공에 닿을 때만 침
            faceToward(ballPos)
            hitBall()
            start(.swat, 0.45)
            return
        }
        if actT > actDur { start(.sit, 2); return }
        // 공까지 길을 찾아 돌아서 감 (공이 굴러가도 따라감). 더 다가갈 수 없으면: 가까우면 앞발을 길게 뻗어 쳐 내고, 멀면 포기하고 앉음
        let speed: Float = running ? 1.5 : 0.6
        // 몸 가운데가 아니라 앞발이 공에 닿는 자리(공 옆 17cm, 나에게 보이는 옆모습 기준)로 감
        switch nav.step(from: pos, to: pawSpot(ballPos), reach: 0.05, far: 0.2, speed: speed, dt, c) {
        case .move(let np):
            moveDir = simd_length(np - pos) > 1e-4 ? simd_normalize(np - pos) : moveDir
            show(walkFrame(moveDir))
            jingle(dt)
            pos = np
            faceToward(np + moveDir)
        case .hold:
            show(walkFrame(moveDir))
        case .arrived, .blocked:
            // 더 다가갈 수 없음: 앞발이 닿으면 치고, 닿지 않으면(가구 틈 등) 갸웃하고 포기 — 닿지 않는데 공이 튀지 않게
            if pawTouch(ballPos) { faceToward(ballPos); hitBall(); start(.swat, 0.45) } else if !reachFlipped {
                reachFlipped = true                                 // 이쪽이 막혔으면 공 반대쪽으로 돌아가 봄
                reachSide = -(reachSide ?? face)
                nav.reset()
            } else { emote("question", 1); start(.sit, 2) }
        }
    }

    // MARK: 무엇을 할지
    private func decide(_ c: Ctx) {
        let me = SIMD2<Float>(c.head.x, c.head.z)
        let dist = simd_distance(pos, me)
        // 토라진 동안은 혼자 놂
        let sulking = t < sulkUntil
        // 내가 앉아 있으면 옆에 와서 꾹꾹이·식빵·잠
        if c.seated && !sulking {
            if dist > 1.0, let s = sideSpot(c, 0.7) { go(s, then: .knead, 4); return }
            let r = Int.random(in: 0...2)
            start(r == 0 ? .knead : (r == 1 ? .loaf : .sleep), r == 0 ? 4 : Float.random(in: 15...30))
            return
        }
        // 가만히 서 있으면 발치에 와서 부비부비
        if !sulking, c.still > 4, dist > 0.55, Float.random(in: 0...1) < 0.45 {
            let s = me + c.fwd * 0.42 + SIMD2<Float>(-c.fwd.y, c.fwd.x) * Float.random(in: -0.15...0.15)
            if c.free(s) && pathOK(pos, s, c) { go(s, then: .rub, 3.5); return }
        }
        var opts: [(Float, () -> Bool)] = []
        opts.append((1.3, { [unowned self] in start(.sit, Float.random(in: 1.5...3.5)); return true }))
        // 이곳저곳 돌아다니기: 내 앞쪽 넓게(양옆 75도까지) 아무 데나
        opts.append((2.8, { [unowned self] in
            guard let s = roamSpot(c) else { return false }
            go(s, then: Bool.random() ? .sit : .groom, Float.random(in: 1.5...3)); return true
        }))
        opts.append((1.4, { [unowned self] in start(.groom, Float.random(in: 2.5...4.5)); return true }))
        opts.append((1.0, { [unowned self] in start(.loaf, Float.random(in: 5...10)); return true }))
        opts.append((0.8, { [unowned self] in start(.stretch, 1.8); return true }))
        opts.append((0.5, { [unowned self] in say("cat_yawn", -6); start(.yawn, 1.4); return true }))
        opts.append((0.7, { [unowned self] in start(.roll, 2.4); chirp(-6); return true }))
        opts.append((0.9, { [unowned self] in meow(-4); emote("note", 1.2); start(.meow, 1.4); return true }))
        opts.append((0.6, { [unowned self] in emote("question", 1.2); start(.tilt, 1.6); return true }))
        if !sulking { opts.append((0.7, { [unowned self] in frontal = true; emote("heart", 1.2); start(.love, 3); return true })) }
        opts.append((2.4, { [unowned self] in
            guard let s = viewSpot(c, near: Float.random(in: 1.1...2.2)) else { return false }
            go(s, then: .sit, Float.random(in: 2...4)); return true
        }))
        opts.append((2.4, { [unowned self] in jumpUpSomewhere(c) }))
        opts.append((1.0, { [unowned self] in scratchSomewhere(c) }))
        // 털실 공 놀이: 공이 보이면 노려보다 덮침, 없으면 꺼내 옴
        opts.append((ball == nil ? 3.2 : 4.5, { [unowned self] in          // 털실 공 놀이는 자주 (공이 있으면 더 자주)
            guard makeBall(near: pos, c) else { return false }
            // 혼자 하는 공놀이는 공이 내 시야(앞 4m 안) 안에 있을 때만 — 내가 다른 쪽을 보는데 뒤쪽 공에만 붙어 있지 않게
            guard t < playUntil || Self.inView(SIMD2<Float>(ballPos.x, ballPos.y), c) else { return false }
            if simd_distance(pawSpot(ballPos), pos) > 0.9 || !pathOK(pos, pawSpot(ballPos), c) { hits = 0; hitsMax = Int.random(in: 2...5); start(.chase, 10); return true }
            pounceFrom = pos
            pounceTo = pawSpot(ballPos)                                // 덮쳐 내려앉는 자리 = 앞발이 공에 닿는 자리
            faceToward(ballPos)
            hits = 0
            hitsMax = Int.random(in: 2...5)
            say("cat_chatter", -6)
            start(.pounce, 1.8)
            return true
        }))
        // 발치를 빙 돌며 부비부비 (가만히 서 있는 나에게)
        if !sulking && c.still > 2.5 && dist < 2.4 {
            opts.append((1.4, { [unowned self] in
                let d0 = simd_length(pos - me) > 0.05 ? simd_normalize(pos - me) : -c.fwd
                let s = me + d0 * 0.36
                guard c.pass(s), reachNow(c).reach(s) else { return false }
                weaveDir = Bool.random() ? 1 : -1
                say("cat_trill", -5)
                go(s, then: .weave, 30)
                return true
            }))
        }
        // 제 꼬리 쫓기
        opts.append((0.45, { [unowned self] in say("cat_chatter", -6); start(.spin, 1.8); return true }))
        // 공을 내 쪽으로 쳐서 보내고 올려다봄 (같이 놀자)
        if !sulking, ball != nil, c.still > 1.5, simd_distance(ballPos, me) > 1.0, simd_distance(ballPos, me) < 4, Self.inView(ballPos, c) {
            opts.append((1.6, { [unowned self] in inviteMe = true; hits = 0; hitsMax = 1; start(.chase, 10); return true }))
        }
        // 우다다: 보이는 곳 이곳저곳을 신나게 뜀
        opts.append((0.5, { [unowned self] in
            guard let s = viewSpot(c, near: Float.random(in: 1.4...2.5)) else { return false }
            go(s, then: .hop, 0.55, run: true); return true
        }))
        if c.still > 20 { opts.append((1.0, { [unowned self] in start(Bool.random() ? .sleep : .flop, Float.random(in: 12...25)); return true })) }
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
        reachNow(c).seek(c, near: near, spread: 0.5, dmin: 0.8, dmax: 2.6, pos: pos)
    }

    /// 돌아다닐 곳: 내 앞쪽 넓게(양옆 75도, 0.8~3.2m) 빈 바닥 중 지금 자리에서 50cm 넘게 떨어지고 바로 갈 수 있는 곳 아무 데나
    private func roamSpot(_ c: Ctx) -> SIMD2<Float>? {
        let me = SIMD2<Float>(c.head.x, c.head.z)
        for _ in 0..<24 {
            let a = Float.random(in: -1.3...1.3), dd = Float.random(in: 0.8...3.2)
            let v = SIMD2<Float>(c.fwd.x * cos(a) - c.fwd.y * sin(a), c.fwd.x * sin(a) + c.fwd.y * cos(a))
            let p = me + v * dd
            if c.free(p) && simd_distance(p, pos) > 0.5 && pathOK(pos, p, c) { return p }
        }
        return nil
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


/// 강아지·고양이 길 따라 걷기 (가구를 돌아서) — 한 프레임에 한 걸음.
/// 막히면 축 방향으로 미끄러져 보고, 0.6초 넘게 못 움직이면 '막힘'으로 알려 줌 (부르는 쪽이 물기·포기·놀자 자세 등으로 넘어감).
/// (예전엔 막힌 걸음을 그대로 버리고 같은 길을 다시 찾기만 해, 막대·공이 바로 옆에 있어도 제자리에서 발만 굴렀음)
@MainActor
struct PetNav {
    enum Step { case move(SIMD2<Float>), hold, arrived, blocked }
    private var path: [SIMD2<Float>] = []
    private var goal: SIMD2<Float>? = nil
    private var planT: Float = 0
    private var stuckT: Float = 0
    private var noPath = false                  // 마지막으로 찾은 길이 없었음 / 막혀 그만둠 (다음에 다시 찾을 때까지 '막힘')

    mutating func reset() { path = []; goal = nil; planT = 0; stuckT = 0; noPath = false }
    /// 길을 따라 가는 중인지 (찾은 길이 남아 있음)
    var isActive: Bool { !path.isEmpty }

    /// reach 안에 들면 arrived. 그만큼 다가갈 길이 없으면 far(있으면) 안까지라도. 길이 끝났으면(가장 가까이 갈 수 있는 곳) arrived
    mutating func step(from pos: SIMD2<Float>, to target: SIMD2<Float>, reach: Float, far: Float? = nil,
                       speed: Float, _ dt: Float, _ c: HomeCat.Ctx) -> Step {
        if simd_distance(pos, target) <= reach { path = []; stuckT = 0; return .arrived }
        planT -= dt
        let moved = goal.map { simd_distance($0, target) > 0.15 } ?? true
        if goal == nil || planT <= 0 || (moved && planT < 0.55) {
            planT = 0.8
            goal = target
            if let p = HomeCat.plan(from: pos, to: target, reach: reach, c) {
                path = p; noPath = false
            } else if let f = far, let p = HomeCat.plan(from: pos, to: target, reach: f, c) {
                path = p; noPath = false
            } else {
                path = []; noPath = true
            }
        }
        if noPath { return .blocked }
        while let w = path.first, simd_distance(pos, w) < 0.04 { path.removeFirst() }
        guard let aim = path.first else { stuckT = 0; return .arrived }
        let v = aim - pos
        let d = simd_length(v)
        guard d > 1e-4 else { path.removeFirst(); return .hold }
        let np = pos + v / d * min(d, speed * dt)
        if c.pass(np) || !c.pass(pos) { stuckT = 0; return .move(np) }
        for q in [SIMD2<Float>(np.x, pos.y), SIMD2<Float>(pos.x, np.y)] where simd_distance(q, pos) > 1e-4 && c.pass(q) {
            stuckT = 0
            return .move(q)
        }
        stuckT += dt
        planT = 0                                   // 가구가 새로 보였을 수 있음 → 다음 프레임에 다시 찾음
        if stuckT > 0.6 { stuckT = 0; path = []; noPath = true; planT = 0.8; return .blocked }
        return .hold
    }
}


/// 강아지·고양이가 지금 자리에서 걸어서(가구를 돌고 문을 지나) 갈 수 있는 바닥 — 15cm 칸, 둘레 6m.
/// 시야 밖에서 내 쪽으로 올 자리를 고를 때 '실제로 갈 수 있는 곳'만 고르려고 씀
/// (예전엔 곧은 줄로 막히지 않는지만 보고 골라, 가구 너머 갈 수 없는 자리를 고르면 길 찾기가 실패 → 앉음 → 다시 고름을 매 프레임
///  되풀이해 걷기·앉기 그림이 번갈아 겹쳐 보였고(글리치), 먼 곳에서 사물에 막혀 오지 못했음)
@MainActor
struct PetReach {
    let lo: SIMD2<Float>
    let cs: Float = 0.15
    let n: Int
    private(set) var ok: [Bool]
    let from: SIMD2<Float>

    init(from a: SIMD2<Float>, radius: Float = 6, _ c: HomeCat.Ctx) {
        from = a
        lo = a - SIMD2<Float>(repeating: radius)
        let cnt = Int((2 * radius / 0.15).rounded(.up))
        n = cnt
        ok = [Bool](repeating: false, count: cnt * cnt)
        var known = [Int8](repeating: -1, count: cnt * cnt)
        let s = Self.cellOf(a, lo, 0.15, cnt)
        let lo0 = lo, n0 = cnt
        let esc = c.pass(a) ? -1 : 1                         // 지금 자리가 막힌 칸이면 둘레 한 칸(15cm)은 빠져나갈 길로 침
        func cp(_ i: Int, _ j: Int) -> SIMD2<Float> { lo0 + SIMD2<Float>((Float(i) + 0.5) * 0.15, (Float(j) + 0.5) * 0.15) }
        func pass(_ i: Int, _ j: Int) -> Bool {
            let k = j * n0 + i
            if known[k] < 0 { known[k] = (c.pass(cp(i, j)) || (abs(i - s.0) <= esc && abs(j - s.1) <= esc)) ? 1 : 0 }
            return known[k] == 1
        }
        var q = [s.1 * cnt + s.0]
        ok[q[0]] = true
        var qi = 0
        while qi < q.count {
            let k = q[qi]; qi += 1
            let i = k % cnt, j = k / cnt
            for (di, dj) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                let x = i + di, y = j + dj
                guard x >= 0, y >= 0, x < cnt, y < cnt else { continue }
                let m = y * cnt + x
                guard !ok[m], pass(x, y) else { continue }
                ok[m] = true
                q.append(m)
            }
        }
    }

    private static func cellOf(_ p: SIMD2<Float>, _ lo: SIMD2<Float>, _ cs: Float, _ n: Int) -> (Int, Int) {
        (min(n - 1, max(0, Int((p.x - lo.x) / cs))), min(n - 1, max(0, Int((p.y - lo.y) / cs))))
    }

    /// 그 자리까지 걸어갈 수 있는지
    func reach(_ p: SIMD2<Float>) -> Bool {
        let x = (p.x - lo.x) / cs, y = (p.y - lo.y) / cs
        guard x >= 0, y >= 0, x < Float(n), y < Float(n) else { return false }
        return ok[Int(y) * n + Int(x)]
    }

    /// 갈 수 있는 칸 가운데들
    var cells: [SIMD2<Float>] {
        var out: [SIMD2<Float>] = []
        for k in ok.indices where ok[k] { out.append(lo + SIMD2<Float>((Float(k % n) + 0.5) * cs, (Float(k / n) + 0.5) * cs)) }
        return out
    }

    /// 내 시야 안(near m쯤 앞, 조금 옆)의 설 수 있고 걸어갈 수 있는 바닥. 시야 안에 그런 곳이 없으면
    /// 갈 수 있는 곳 중 시야에 가장 가까운 곳(나를 향해 오다 막히는 곳 말고, 내가 보는 쪽에서 가장 덜 벗어난 곳)
    func seek(_ c: HomeCat.Ctx, near: Float, spread: Float = 0.5, dmin: Float = 0.8, dmax: Float = 2.6, pos: SIMD2<Float>) -> SIMD2<Float>? {
        let me = SIMD2<Float>(c.head.x, c.head.z)
        var best: (SIMD2<Float>, Float)? = nil
        var dd = dmin
        while dd <= dmax + 1e-3 {
            var a = -spread
            while a <= spread + 1e-3 {
                let v = SIMD2<Float>(c.fwd.x * cos(a) - c.fwd.y * sin(a), c.fwd.x * sin(a) + c.fwd.y * cos(a))
                let p = me + v * dd
                if reach(p) && c.free(p) {
                    let score = abs(dd - near) + abs(abs(a) - spread * 0.5) * 0.6 + simd_distance(p, pos) * 0.15
                    if best == nil || score < best!.1 { best = (p, score) }
                }
                a += 0.125
            }
            dd += 0.2
        }
        if let b = best { return b.0 }
        // 시야 안에 갈 곳이 없음: 갈 수 있는 곳 중 내 시야 쪽에 가장 가까운 곳
        var list: [(SIMD2<Float>, Float)] = []
        for p in cells {
            let v = p - me
            let d = simd_length(v)
            guard d > 0.5, d < 4.5 else { continue }
            let off = acos(max(-1, min(1, simd_dot(v / d, c.fwd))))
            list.append((p, off * 1.6 + abs(d - near) * 0.5))
        }
        list.sort { $0.1 < $1.1 }
        for (p, _) in list.prefix(60) where c.free(p) { return p }
        return nil
    }
}
