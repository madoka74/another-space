import SwiftUI
import RealityKit
import simd

/// 별자리 하나: 별(이름, 적경 시, 적위 도, 등급, 색), 잇는 선, 해설
struct Constellation {
    let id: String
    let name: String
    let latin: String
    let season: String
    let stars: [(String, Double, Double, Float, SIMD3<Float>)]
    let lines: [(Int, Int)]
    let story: [String]
    let find: [String]
    let starNote: String

    static let white = SIMD3<Float>(1, 1, 1)
    static let blue = SIMD3<Float>(0.78, 0.86, 1)
    static let orange = SIMD3<Float>(1, 0.74, 0.5)
    static let red = SIMD3<Float>(1, 0.55, 0.42)
    static let gold = SIMD3<Float>(1, 0.9, 0.7)

    static let all: [Constellation] = [
        Constellation(id: "dipper", name: "북두칠성", latin: "큰곰자리 · Ursa Major", season: "봄 저녁 북쪽 하늘 높이 (우리나라에선 거의 일 년 내내)",
                      stars: [("두베", 11.062, 61.75, 1.8, orange), ("메라크", 11.031, 56.38, 2.4, white), ("페크다", 11.897, 53.69, 2.4, white),
                              ("메그레즈", 12.257, 57.03, 3.3, white), ("알리오스", 12.900, 55.96, 1.8, white), ("미자르", 13.399, 54.93, 2.2, white),
                              ("알카이드", 13.792, 49.31, 1.9, blue), ("알코르", 13.420, 54.99, 4.0, white)],
                      lines: [(0, 1), (1, 2), (2, 3), (3, 0), (3, 4), (4, 5), (5, 6)],
                      story: ["국자 모양의 일곱 별로, 큰곰자리의 엉덩이와 꼬리에 해당해요.",
                              "그리스 신화에서는 제우스가 사랑한 님프 칼리스토가 헤라의 질투로 곰이 되었고, 제우스가 그 곰을 하늘에 올렸다고 해요.",
                              "우리 조상들은 이 일곱 별을 '칠성'이라 부르며 수명과 복을 비는 별로 여겼어요."],
                      find: ["국자 끝의 두 별(메라크 → 두베)을 이은 선을 그 길이의 5배쯤 늘이면 북극성이 있어요.",
                             "손잡이 둘째 별 미자르 바로 옆에 작은 별 알코르가 붙어 있어요. 둘을 나눠 보면 눈이 좋다는 옛이야기가 있어요."],
                      starNote: "두베 · 메라크 · 페크다 · 메그레즈 · 알리오스 · 미자르 · 알카이드"),
        Constellation(id: "orion", name: "오리온자리", latin: "Orion", season: "겨울 저녁 남쪽 하늘",
                      stars: [("베텔게우스", 5.919, 7.41, 0.5, orange), ("벨라트릭스", 5.419, 6.35, 1.6, blue), ("알니탁", 5.679, -1.94, 1.8, blue),
                              ("알닐람", 5.604, -1.20, 1.7, blue), ("민타카", 5.533, -0.30, 2.2, blue), ("사이프", 5.796, -9.67, 2.1, blue),
                              ("리겔", 5.242, -8.20, 0.1, blue), ("메이사", 5.585, 9.93, 3.4, blue)],
                      lines: [(7, 0), (7, 1), (0, 2), (1, 4), (2, 3), (3, 4), (2, 5), (4, 6)],
                      story: ["그리스 신화의 사냥꾼 오리온이에요. 전갈에 찔려 죽었다는 이야기가 있어, 전갈자리가 떠오르면 오리온은 서쪽으로 져서 둘은 하늘에 함께 보이지 않아요.",
                              "왼쪽 위의 붉은 별 베텔게우스는 늙은 적색 초거성이고, 오른쪽 아래 푸르게 흰 리겔은 젊고 뜨거운 별이에요.",
                              "동양에서는 허리띠 세 별과 둘레 네 별을 '삼수(參宿)'라 불렀어요."],
                      find: ["가운데 나란한 세 별(허리띠)을 먼저 찾고, 그 위아래의 밝은 네 별을 이으면 큰 사각형이 돼요.",
                             "허리띠 아래로 늘어진 '칼' 부분에 오리온 대성운(M42)이 있어, 어두운 곳에서는 맨눈에도 뿌옇게 보여요."],
                      starNote: "베텔게우스 · 리겔 · 벨라트릭스 · 사이프 · 허리띠(알니탁 · 알닐람 · 민타카)"),
        Constellation(id: "cassiopeia", name: "카시오페이아자리", latin: "Cassiopeia", season: "가을 저녁 북쪽 하늘 (우리나라에선 일 년 내내 지지 않아요)",
                      stars: [("카프", 0.153, 59.15, 2.3, white), ("시르", 0.675, 56.54, 2.2, orange), ("나비", 0.945, 60.72, 2.2, blue),
                              ("루크바", 1.430, 60.24, 2.7, white), ("세긴", 1.907, 63.67, 3.4, blue)],
                      lines: [(0, 1), (1, 2), (2, 3), (3, 4)],
                      story: ["에티오피아의 왕비 카시오페이아예요. 딸 안드로메다의 아름다움을 지나치게 자랑하다 바다의 신 포세이돈의 노여움을 샀다고 해요.",
                              "그 벌로 의자에 앉은 채 북극 둘레를 돌며, 때로는 거꾸로 매달린 모습이 된다는 이야기가 전해져요."],
                      find: ["W(또는 M) 모양의 다섯 별이라 금방 눈에 띄어요.",
                             "북극성을 사이에 두고 북두칠성의 반대편에 있어, 북두칠성이 낮게 내려갔을 때 북극성을 찾는 길잡이가 돼요."],
                      starNote: "카프 · 시르 · 나비 · 루크바 · 세긴"),
        Constellation(id: "cygnus", name: "백조자리", latin: "Cygnus", season: "여름~가을 저녁 머리 위",
                      stars: [("데네브", 20.690, 45.28, 1.25, white), ("사드르", 20.370, 40.26, 2.2, gold), ("기에나", 20.770, 33.97, 2.5, orange),
                              ("델타", 19.750, 45.13, 2.9, blue), ("알비레오", 19.512, 27.96, 3.1, gold)],
                      lines: [(0, 1), (1, 4), (3, 1), (1, 2)],
                      story: ["은하수 한가운데를 날아가는 백조예요. 큰 십자 모양이라 '북십자성'이라고도 불러요.",
                              "꼬리의 데네브는 거문고자리 베가, 독수리자리 알타이르와 함께 '여름의 대삼각형'을 이뤄요. 데네브는 아주 멀리 있는데도 밝게 보이는 초거성이에요.",
                              "그리스 신화에서는 제우스가 백조로 변한 모습이라고도 해요."],
                      find: ["여름밤 머리 위의 가장 밝은 세 별(대삼각형) 중 하나가 데네브예요. 거기서 은하수를 따라 십자를 그려 보세요.",
                             "부리 끝 알비레오는 망원경으로 보면 노란 별과 파란 별이 나란히 붙은 아름다운 이중별이에요."],
                      starNote: "데네브 · 사드르 · 기에나 · 델타 · 알비레오"),
        Constellation(id: "lyra", name: "거문고자리", latin: "Lyra", season: "여름 저녁 머리 위",
                      stars: [("베가(직녀성)", 18.616, 38.78, 0.0, blue), ("엡실론", 18.739, 39.67, 4.7, white), ("제타", 18.746, 37.61, 4.3, white),
                              ("델타", 18.908, 36.90, 4.3, orange), ("셸리악", 18.835, 33.36, 3.5, white), ("술라파트", 18.982, 32.69, 3.2, blue)],
                      lines: [(0, 1), (0, 2), (2, 3), (3, 5), (5, 4), (4, 2)],
                      story: ["가장 밝은 별 베가가 바로 우리 옛이야기의 직녀성이에요. 은하수 건너편 독수리자리의 알타이르(견우성)와 칠월 칠석에 까치와 까마귀가 놓은 오작교에서 만난다고 해요.",
                              "그리스 신화에서는 음악가 오르페우스가 타던 거문고(리라)예요.",
                              "베가는 약 25광년 떨어져 있고, 지구 자전축이 천천히 돌기 때문에 약 1만 2천 년 뒤에는 베가가 북극성 노릇을 하게 돼요."],
                      find: ["여름밤 머리 위에서 가장 밝게 빛나는 푸르스름한 별이 베가예요.",
                             "베가 옆의 작은 평행사변형 네 별이 거문고의 몸통이에요."],
                      starNote: "베가 · 셸리악 · 술라파트 · 제타 · 델타"),
        Constellation(id: "leo", name: "사자자리", latin: "Leo", season: "봄 저녁 남쪽 하늘 높이",
                      stars: [("레굴루스", 10.140, 11.97, 1.4, blue), ("에타", 10.122, 16.76, 3.5, white), ("알기에바", 10.333, 19.84, 2.0, orange),
                              ("아다페라", 10.278, 23.42, 3.4, white), ("라살라스", 9.879, 26.01, 3.9, orange), ("엡실론", 9.764, 23.77, 3.0, gold),
                              ("조스마", 11.235, 20.52, 2.6, white), ("케르탄", 11.237, 15.43, 3.3, white), ("데네볼라", 11.818, 14.57, 2.1, white)],
                      lines: [(0, 1), (1, 2), (2, 3), (3, 4), (4, 5), (2, 6), (6, 8), (8, 7), (7, 0)],
                      story: ["사자의 머리와 가슴은 물음표를 뒤집은 듯한 '낫' 모양이고, 그 아래 끝의 밝은 별이 레굴루스('작은 왕')예요.",
                              "그리스 신화에서 헤라클레스가 맨손으로 물리친 네메아의 사자라고 해요.",
                              "해마다 11월 중순에는 이 별자리 쪽에서 별똥별이 쏟아지는 사자자리 유성우가 있어요."],
                      find: ["봄밤 남쪽 하늘 높이 뒤집힌 물음표를 찾고, 그 왼쪽 끝 삼각형(꼬리)의 데네볼라까지 이어 보세요.",
                             "레굴루스는 해와 달이 지나는 길(황도) 바로 위에 있어서 가끔 달에 가려지기도 해요."],
                      starNote: "레굴루스 · 알기에바 · 데네볼라 · 조스마"),
        Constellation(id: "scorpius", name: "전갈자리", latin: "Scorpius", season: "여름 저녁 남쪽 하늘 낮게",
                      stars: [("안타레스", 16.490, -26.43, 1.0, red), ("아크라브", 16.091, -19.81, 2.6, blue), ("드슈바", 16.006, -22.62, 2.3, blue),
                              ("파이", 15.981, -26.11, 2.9, blue), ("시그마", 16.353, -25.59, 2.9, blue), ("타우", 16.598, -28.22, 2.8, blue),
                              ("엡실론", 16.836, -34.29, 2.3, orange), ("뮤", 16.864, -38.05, 3.0, blue), ("제타", 16.910, -42.36, 3.6, orange),
                              ("에타", 17.202, -43.24, 3.3, white), ("사르가스", 17.622, -43.00, 1.9, white), ("이오타", 17.793, -40.13, 3.0, white),
                              ("카파", 17.708, -39.03, 2.4, blue), ("샤울라", 17.560, -37.10, 1.6, blue)],
                      lines: [(1, 2), (2, 3), (2, 4), (4, 0), (0, 5), (5, 6), (6, 7), (7, 8), (8, 9), (9, 10), (10, 11), (11, 12), (12, 13)],
                      story: ["붉게 빛나는 안타레스는 전갈의 심장이에요. 이름은 '화성의 맞수'라는 뜻으로, 색이 화성과 닮았어요. 태양보다 수백 배나 큰 적색 초거성이에요.",
                              "그리스 신화에서 사냥꾼 오리온을 찔러 죽인 전갈이라, 오리온이 서쪽으로 져야 동쪽에서 떠오른다고 해요.",
                              "동양 별자리에서는 안타레스 둘레를 '심수(心宿)'라 했고, 안타레스를 '대화(大火)'라고도 불렀어요."],
                      find: ["여름밤 남쪽 지평선 위에서 붉은 별 안타레스를 찾고, 거기서 아래로 S자처럼 휘어 올라간 꼬리를 따라가 보세요.",
                             "꼬리 끝의 두 별(샤울라 · 레사트)이 전갈의 독침이에요. 우리나라에선 지평선에 가까워 탁 트인 곳에서 잘 보여요."],
                      starNote: "안타레스 · 샤울라 · 사르가스 · 드슈바 · 아크라브"),
        Constellation(id: "ursaminor", name: "작은곰자리", latin: "Ursa Minor", season: "일 년 내내 북쪽 하늘",
                      stars: [("북극성(폴라리스)", 2.530, 89.26, 2.0, gold), ("일둔", 17.537, 86.59, 4.4, white), ("엡실론", 16.766, 82.04, 4.2, gold),
                              ("제타", 15.734, 77.79, 4.3, white), ("에타", 16.292, 75.76, 5.0, white), ("페르카드", 15.346, 71.83, 3.0, white),
                              ("코카브", 14.845, 74.16, 2.1, orange)],
                      lines: [(0, 1), (1, 2), (2, 3), (3, 6), (6, 5), (5, 4), (4, 3)],
                      story: ["작은 국자 모양으로, 손잡이 끝의 별이 북극성이에요.",
                              "북극성은 지구 자전축의 북쪽 방향에 거의 있어서 밤새 거의 움직이지 않아요. 그래서 옛날부터 방향을 찾는 길잡이였어요.",
                              "북극성은 약 430광년 떨어진 2등성이라 생각보다 아주 밝지는 않아요. 그리스 신화에선 칼리스토의 아들 아르카스가 작은곰이 되었다고 해요."],
                      find: ["북두칠성 국자 끝 두 별을 이어 5배쯤 늘이면 북극성이에요.",
                             "밝은 별은 북극성과 코카브 · 페르카드 정도라, 도시에서는 국자 모양을 다 보기 어려워요."],
                      starNote: "북극성 · 코카브 · 페르카드"),
    ]
}

/// 시골 테마 밤하늘의 별자리 3~4개: 실제 별 위치로 모양을 만들어 하늘 곳곳에 띄엄띄엄 띄움.
/// 바라보면 별이 밝아지며 옅은 선이 비치고(포커스), 탭하면 별을 잇는 선이 차례로 그려지고 이름이 뜸.
/// 밤에 가장 또렷하고, 새벽·해질녘엔 밝은 별만 흐리게, 낮엔 안 보임. 구름이 끼면 흐려졌다 또렷해졌다, 비·눈이면 가려짐
@MainActor
final class SkyStars {
    private final class Group {
        let c: Constellation
        let dir: SIMD3<Float>
        let radius: Float
        var stars: [(ModelEntity, Float, Float, Float)] = []     // 별, 기본 크기, 반짝임 빠르기, 위상
        var lines: [ModelEntity] = []
        var label: Entity?
        var focus: Float = 0
        var reveal: Float = 0
        var picked = false
        let cloudPh: Float
        init(c: Constellation, dir: SIMD3<Float>, radius: Float, cloudPh: Float) {
            self.c = c; self.dir = dir; self.radius = radius; self.cloudPh = cloudPh
        }
    }

    let root = Entity()
    private var groups: [Group] = []
    private let vis: Float
    private let dimOnly: Bool
    private let cloudy: Bool
    private let windy: Bool
    private let look: LookMode
    private var t: Float = 0
    private let R: Float = 200

    var visible: Bool { vis > 0.05 }

    init(room: RoomRec, center: SIMD3<Float>, look: LookMode) {
        self.look = look
        let tm = room.time, w = room.weather
        var v: Float = 0
        if tm == "night" { v = 1 } else if tm == "dusk" || tm == "dawn" { v = 0.5 }
        switch w {
        case "clear", "wind": break
        case "cloudy": v *= 0.7
        default: v = 0
        }
        vis = v
        dimOnly = tm != "night"
        cloudy = w == "cloudy"
        windy = w == "wind"
        root.position = center + SIMD3<Float>(0, 1.6, 0)
        guard v > 0 else { root.isEnabled = false; return }
        // 3~4개를 하늘 둘레에 띄엄띄엄 (방위는 고르게 나누고 조금씩 흔듦, 높이 32~60도)
        let n = Int.random(in: 3...4)
        let picks = Constellation.all.shuffled().prefix(n)
        let a0 = Float.random(in: 0...(2 * .pi))
        for (k, c) in picks.enumerated() {
            let az = a0 + Float(k) / Float(n) * 2 * .pi + Float.random(in: -0.25...0.25)
            let alt = Float.random(in: 0.56...1.05)
            let d = SIMD3<Float>(cos(alt) * sin(az), sin(alt), cos(alt) * cos(az))
            build(c, dir: simd_normalize(d))
        }
        root.components.set(OpacityComponent(opacity: v))
    }

    private func vec(_ ra: Double, _ dec: Double) -> SIMD3<Double> {
        let a = ra / 24 * 2 * .pi, d = dec * .pi / 180
        return SIMD3<Double>(cos(d) * cos(a), cos(d) * sin(a), sin(d))
    }

    private func build(_ c: Constellation, dir: SIMD3<Float>) {
        // 별자리 가운데 (별 방향들의 평균) 기준 접평면 투영: x 동쪽, y 북쪽
        var m = SIMD3<Double>(0, 0, 0)
        for s in c.stars { m += vec(s.1, s.2) }
        m = simd_normalize(m)
        let ra0 = atan2(m.y, m.x), dec0 = asin(m.z)
        var pts: [SIMD2<Float>] = []
        for s in c.stars {
            let ra = s.1 / 24 * 2 * .pi, dec = s.2 * .pi / 180
            let cosc = sin(dec0) * sin(dec) + cos(dec0) * cos(dec) * cos(ra - ra0)
            let x = cos(dec) * sin(ra - ra0) / cosc
            let y = (cos(dec0) * sin(dec) - sin(dec0) * cos(dec) * cos(ra - ra0)) / cosc
            pts.append(SIMD2<Float>(Float(x), Float(y)))
        }
        // 하늘 안쪽에서 보면 동쪽이 왼쪽 → 화면 오른쪽은 -x. 조금 기울여 자연스럽게
        let roll = Float.random(in: -0.35...0.35)
        let up0 = simd_normalize(SIMD3<Float>(0, 1, 0) - dir * simd_dot(SIMD3<Float>(0, 1, 0), dir))
        let right0 = simd_normalize(simd_cross(dir, up0))
        let up = up0 * cos(roll) + right0 * sin(roll)
        let right = simd_normalize(simd_cross(dir, up))
        var radius: Float = 0
        var pos: [SIMD3<Float>] = []
        for p in pts {
            let v = simd_normalize(dir + right * (-p.x) + up * p.y)
            pos.append(v * R)
            radius = max(radius, acos(min(1, simd_dot(v, dir))))
        }
        let g = Group(c: c, dir: dir, radius: radius, cloudPh: Float.random(in: 0...6))
        let mask = Tex.get("glow_a", raw: true)
        for (i, s) in c.stars.enumerated() {
            let mag = s.3
            if dimOnly && mag > 2.3 { continue }
            let deg = max(0.24, 0.9 - 0.15 * mag)
            let size = R * deg * .pi / 180 * 2.4
            let col: SIMD3<Float> = look == .color ? s.4 : SIMD3<Float>(repeating: 1)
            var q = Geo()
            q.quad(SIMD3<Float>(-size / 2, -size / 2, 0), SIMD3<Float>(size / 2, -size / 2, 0), SIMD3<Float>(size / 2, size / 2, 0), SIMD3<Float>(-size / 2, size / 2, 0),
                   SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(1, 1), SIMD2<Float>(0, 1))
            var mt = UnlitMaterial(color: look == .line ? UIColor(white: 0.1, alpha: 1)
                                   : UIColor(red: CGFloat(col.x), green: CGFloat(col.y), blue: CGFloat(col.z), alpha: 1))
            if let mask {
                var mp = MaterialParameters.Texture(mask); mp.sampler = Tex.clamp
                mt.blending = .transparent(opacity: .init(scale: 1, texture: mp))
            }
            guard let e = q.entity("star", mt) else { continue }
            e.position = pos[i]
            e.look(at: .zero, from: pos[i], relativeTo: root)
            root.addChild(e)
            g.stars.append((e, 1, Float.random(in: 1.5...5) * (windy ? 1.8 : 1), Float.random(in: 0...6)))
        }
        // 잇는 선 (조금 안쪽, 별 둘레는 비움)
        let lineCol: UIColor = look == .line ? UIColor(white: 0.12, alpha: 1) : (look == .mono ? UIColor(white: 0.9, alpha: 1) : UIColor(red: 0.7, green: 0.82, blue: 1, alpha: 1))
        var lm = UnlitMaterial(color: lineCol)
        lm.blending = .transparent(opacity: .init(floatLiteral: 0.8))
        for (a, b) in c.lines {
            let pa = pos[a] * 0.99, pb = pos[b] * 0.99
            let d = simd_normalize(pb - pa)
            let gap: Float = R * 0.006
            var s = Geo()
            s.stroke(pa + d * gap, pb - d * gap, width: R * 0.0016)
            guard let e = s.entity("starLine", lm) else { continue }
            e.components.set(OpacityComponent(opacity: 0))
            root.addChild(e)
            g.lines.append(e)
        }
        // 이름 (별자리 아래쪽)
        let below = simd_normalize(dir - up * (radius + 0.06))
        let text = MeshResource.generateText(c.name, extrusionDepth: 0.05, font: .systemFont(ofSize: CGFloat(R * 0.022), weight: .medium), alignment: .center)
        let te = ModelEntity(mesh: text, materials: [UnlitMaterial(color: lineCol)])
        let bb = te.visualBounds(relativeTo: nil)
        te.position = SIMD3<Float>(-(bb.min.x + bb.max.x) / 2, -(bb.min.y + bb.max.y) / 2, 0)
        let holder = Entity()
        let lp = below * R * 0.98
        holder.look(at: .zero, from: lp, upVector: up, relativeTo: root)
        let flipE = Entity()
        flipE.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])          // 글자 앞면이 하늘 안쪽(나)을 보게
        flipE.addChild(te)
        holder.addChild(flipE)
        holder.components.set(OpacityComponent(opacity: 0))
        root.addChild(holder)
        g.label = holder
        groups.append(g)
    }

    /// 바라보는 별자리 (포커스) — 머리가 향한 쪽에서 별자리 반경 + 4도 안
    private func near(_ dir: SIMD3<Float>) -> Group? {
        var best: (Group, Float)? = nil
        for g in groups {
            let a = acos(min(1, max(-1, simd_dot(simd_normalize(dir), g.dir))))
            if a < g.radius + 0.07, best == nil || a < best!.1 { best = (g, a) }
        }
        return best?.0
    }

    func tick(_ dt: Float, gaze: SIMD3<Float>) {
        guard visible else { return }
        t += dt
        let f = near(gaze)
        for g in groups {
            let want: Float = g === f ? 1 : 0
            g.focus += (want - g.focus) * min(1, dt * 4)
            if g.picked { g.reveal = min(1, g.reveal + dt / 1.4) } else { g.reveal = max(0, g.reveal - dt * 0.8) }
            // 구름: 별자리마다 천천히 흐려졌다 또렷해짐
            let cl: Float = cloudy ? 0.45 + 0.55 * max(0, sin(t * 0.08 + g.cloudPh)) : 1
            for (e, base, sp, ph) in g.stars {
                let tw = 1 + (windy ? 0.22 : 0.12) * sin(t * sp + ph) * sin(t * sp * 0.37 + ph)
                e.scale = SIMD3<Float>(repeating: base * tw * (1 + 0.45 * g.focus + 0.25 * g.reveal) * (0.6 + 0.4 * cl))
            }
            let n = Float(max(1, g.lines.count))
            for (i, l) in g.lines.enumerated() {
                let k = min(1, max(0, g.reveal * n - Float(i) * 0.85))        // 하나씩 차례로 그려짐
                let o = max(0.22 * g.focus, k * 0.9) * cl
                l.components.set(OpacityComponent(opacity: o))
            }
            g.label?.components.set(OpacityComponent(opacity: g.reveal * cl))
        }
    }

    /// 탭: 그 방향의 별자리를 고름 (없으면 nil)
    func pick(_ dir: SIMD3<Float>) -> Constellation? {
        guard visible, let g = near(dir) else { return nil }
        for o in groups { o.picked = o === g }
        g.reveal = 0
        Sfx.play("star_chime", in: root, at: g.dir * 4, gain: -4)
        return g.c
    }

    func unpick() {
        for g in groups { g.picked = false }
    }
}

/// 별자리 정보판 (도슨트처럼)
struct StarCard: View {
    let s: ExploreSession

    var body: some View {
        Group {
            if let c = s.starPick {
                content(c)
            } else {
                Color.clear.frame(width: 1, height: 1)
            }
        }
    }

    @ViewBuilder
    private func content(_ c: Constellation) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("별자리").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(c.name).font(.title2.weight(.bold))
                    Text(c.latin).font(.headline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button {
                    s.closeStars()
                } label: {
                    Image(systemName: "xmark").font(.title3).frame(width: 36, height: 36)
                }
                .buttonBorderShape(.circle)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Label(c.season, systemImage: "calendar").font(.subheadline)
                    Label(c.starNote, systemImage: "sparkles").font(.subheadline)
                    Text("이야기").font(.title3.weight(.semibold)).padding(.top, 6)
                    ForEach(Array(c.story.enumerated()), id: \.offset) { _, t in para(t) }
                    Text("찾아보기").font(.title3.weight(.semibold)).padding(.top, 6)
                    ForEach(Array(c.find.enumerated()), id: \.offset) { _, t in
                        HStack(alignment: .firstTextBaseline, spacing: 8) { Text("•"); para(t) }
                    }
                    Text("하늘에 보이는 자리는 실제 방위와 다르게, 잘 보이도록 골라 띄운 거예요. 별의 배치(모양)는 실제와 같아요.")
                        .font(.caption).foregroundStyle(.secondary).padding(.top, 6)
                }
                .padding(.trailing, 6)
            }
        }
        .padding(24)
        .frame(width: 500, height: 600)
        .glassBackgroundEffect()
    }

    private func para(_ t: String) -> some View {
        Text(t).font(.body).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
    }
}
