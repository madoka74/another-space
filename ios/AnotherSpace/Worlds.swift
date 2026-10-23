import Foundation
import simd

/// 엠비언트와 같은 장소·날씨·시간 (id·이름이 엠비언트 카탈로그와 같아야 소리를 그대로 가져옴)
struct AxisItem: Hashable {
    let id: String
    let label: String
}

/// 장소마다 어떻게 보일지
struct WorldStyle {
    let floor: String               // 방 바닥 무늬 (tex)
    let floorTile: Float            // 무늬 한 장이 덮는 길이(m)
    let wall: String                // 실내 장소의 벽 무늬 (바깥 장소는 벽이 트인 풍경 + 울타리)
    let wallTile: Float
    let prop: String                // 가구·물건 무늬
    let propTile: Float
    let propTint: SIMD3<Float>
    let open: Bool                  // 바깥 장소: 벽 자리에 울타리·덤불·바위를 세우고 그 너머 풍경이 보임
    let barrier: String             // 울타리 그림 (open일 때)
    let barrierH: Float             // 울타리 높이(m)
    let ground: String              // 바깥 땅 무늬 (창·벽 너머)
    let groundTile: Float
    let groundFar: SIMD3<Float>     // 멀리 땅 색
    let skylight: Bool              // 실내 장소: 천장에 유리 지붕 틀
}

enum Worlds {
    static let places: [AxisItem] = [
        .init(id: "camp", label: "캠핑장"), .init(id: "forest", label: "숲"), .init(id: "valley", label: "계곡"),
        .init(id: "sea", label: "바다"), .init(id: "village", label: "시골"), .init(id: "city", label: "도시"),
        .init(id: "cafe", label: "카페"), .init(id: "gallery", label: "전시관"), .init(id: "home", label: "집"),
    ]
    static let weathers: [AxisItem] = [
        .init(id: "clear", label: "맑음"), .init(id: "cloudy", label: "구름"), .init(id: "wind", label: "바람"),
        .init(id: "drizzle", label: "가랑비"), .init(id: "rain", label: "비"), .init(id: "storm", label: "폭우"),
        .init(id: "snow", label: "눈"), .init(id: "heavysnow", label: "함박눈"),
    ]
    static let times: [AxisItem] = [
        .init(id: "dawn", label: "새벽"), .init(id: "morning", label: "아침"), .init(id: "afternoon", label: "오후"),
        .init(id: "dusk", label: "해질녘"), .init(id: "night", label: "밤"),
    ]
    private static let adj: [String: String] = [
        "clear": "맑은", "cloudy": "구름 낀", "wind": "바람 부는", "drizzle": "가랑비 내리는", "rain": "비 내리는",
        "storm": "폭우 쏟아지는", "snow": "눈 내리는", "heavysnow": "함박눈 내리는",
    ]

    static func label(_ list: [AxisItem], _ id: String) -> String { list.first { $0.id == id }?.label ?? id }

    /// 칩에 쓰는 기호 (SF Symbols)
    static func icon(_ id: String) -> String {
        switch id {
        case "camp": return "tent"
        case "forest": return "tree"
        case "valley": return "mountain.2"
        case "sea": return "water.waves"
        case "village": return "leaf"
        case "city": return "building.2"
        case "cafe": return "cup.and.saucer"
        case "gallery": return "photo.artframe"
        case "home": return "house"
        case "clear": return "sun.max"
        case "cloudy": return "cloud"
        case "wind": return "wind"
        case "drizzle": return "cloud.drizzle"
        case "rain": return "cloud.rain"
        case "storm": return "cloud.heavyrain"
        case "snow": return "cloud.snow"
        case "heavysnow": return "snowflake"
        case "dawn": return "sunrise"
        case "morning": return "sun.horizon"
        case "afternoon": return "sun.max.fill"
        case "dusk": return "sunset"
        case "night": return "moon.stars"
        default: return "circle"
        }
    }

    /// "구름 낀 오후의 캠핑장"
    static func title(place: String, weather: String, time: String) -> String {
        "\(adj[weather] ?? label(weathers, weather)) \(label(times, time))의 \(label(places, place))"
    }

    /// 엠비언트의 날씨 소리 층 구분 (실내·도시·자연·물가·텐트)
    static func surface(_ place: String) -> String {
        switch place {
        case "home", "cafe", "gallery": return "indoor"
        case "city": return "urban"
        case "sea": return "water"
        case "camp": return "tent"
        default: return "nature"
        }
    }

    static func indoor(_ place: String) -> Bool { surface(place) == "indoor" }

    static func style(_ place: String, time: String) -> WorldStyle {
        let w: SIMD3<Float> = [1, 1, 1]
        switch place {
        case "camp":
            return WorldStyle(floor: "grass", floorTile: 1.8, wall: "", wallTile: 1, prop: "bark", propTile: 0.8, propTint: w,
                              open: true, barrier: "barrier_camp", barrierH: 1.3, ground: "grass", groundTile: 2.2,
                              groundFar: [0.20, 0.30, 0.14], skylight: false)
        case "forest":
            return WorldStyle(floor: "moss", floorTile: 1.6, wall: "", wallTile: 1, prop: "mossrock", propTile: 0.9, propTint: w,
                              open: true, barrier: "barrier_forest", barrierH: 1.7, ground: "moss", groundTile: 2.0,
                              groundFar: [0.13, 0.20, 0.10], skylight: false)
        case "valley":
            return WorldStyle(floor: "pebble", floorTile: 1.4, wall: "", wallTile: 1, prop: "rock", propTile: 0.9, propTint: w,
                              open: true, barrier: "barrier_valley", barrierH: 1.4, ground: "pebble", groundTile: 1.8,
                              groundFar: [0.40, 0.37, 0.32], skylight: false)
        case "sea":
            return WorldStyle(floor: "sand", floorTile: 2.0, wall: "", wallTile: 1, prop: "driftwood", propTile: 0.9, propTint: w,
                              open: true, barrier: "barrier_sea", barrierH: 1.1, ground: "sand", groundTile: 2.4,
                              groundFar: [0.12, 0.30, 0.40], skylight: false)
        case "village":
            return WorldStyle(floor: "dirt", floorTile: 1.8, wall: "", wallTile: 1, prop: "hay", propTile: 0.8, propTint: w,
                              open: true, barrier: "barrier_village", barrierH: 1.5, ground: "grass", groundTile: 2.2,
                              groundFar: [0.30, 0.38, 0.18], skylight: false)
        case "city":
            return WorldStyle(floor: "roof", floorTile: 2.4, wall: "", wallTile: 1, prop: "concrete", propTile: 1.0, propTint: w,
                              open: true, barrier: "barrier_city", barrierH: 1.15, ground: "roof", groundTile: 2.4,
                              groundFar: [0.16, 0.16, 0.18], skylight: false)
        case "cafe":
            return WorldStyle(floor: "planks_dark", floorTile: 1.6, wall: "brick", wallTile: 1.6, prop: "walnut", propTile: 0.8,
                              propTint: [0.95, 0.9, 0.86], open: false, barrier: "", barrierH: 0, ground: "asphalt", groundTile: 2.4,
                              groundFar: [0.20, 0.20, 0.22], skylight: true)
        case "gallery":
            return WorldStyle(floor: "marble", floorTile: 2.0, wall: "plaster", wallTile: 2.0, prop: "marble", propTile: 1.0, propTint: w,
                              open: false, barrier: "", barrierH: 0, ground: "grass", groundTile: 2.2,
                              groundFar: [0.26, 0.32, 0.20], skylight: true)
        default:   // home: 숲속 통나무집
            return WorldStyle(floor: "planks", floorTile: 1.6, wall: "timber", wallTile: 1.8, prop: "oak", propTile: 0.9, propTint: w,
                              open: false, barrier: "", barrierH: 0, ground: "moss", groundTile: 2.0,
                              groundFar: [0.14, 0.22, 0.11], skylight: true)
        }
    }

    /// 시간에 따른 빛 색·밝기 — 새벽은 푸르스름한 보랏빛, 아침은 금빛, 해질녘은 짙은 주황, 밤은 달빛(바깥)·등불(실내)
    static func timeTint(_ time: String, indoor: Bool) -> SIMD3<Float> {
        switch time {
        case "dawn": return indoor ? [0.66, 0.58, 0.58] : [0.58, 0.55, 0.80]
        case "morning": return [1.06, 0.94, 0.78]
        case "dusk": return indoor ? [1.0, 0.70, 0.50] : [1.06, 0.62, 0.40]
        case "night": return indoor ? [0.66, 0.50, 0.34] : [0.30, 0.37, 0.62]
        default: return [1.02, 1.0, 0.96]
        }
    }

    /// 먼 풍경이 물드는 지평선 빛 (하늘 그림의 지평선 색과 맞춤). 비·눈·흐림이면 잿빛으로
    static func haze(_ time: String, weather: String) -> SIMD3<Float> {
        var h: SIMD3<Float>
        switch time {
        case "dawn": h = [0.95, 0.70, 0.66]
        case "morning": h = [1.0, 0.92, 0.80]
        case "dusk": h = [1.0, 0.56, 0.32]
        case "night": h = [0.16, 0.22, 0.38]
        default: h = [0.80, 0.88, 0.98]
        }
        let gray: Float
        switch weather {
        case "cloudy": gray = 0.3
        case "drizzle", "snow": gray = 0.6
        case "rain", "heavysnow": gray = 0.75
        case "storm": gray = 0.9
        default: gray = 0
        }
        let lum = (h.x + h.y + h.z) / 3
        let g = SIMD3<Float>(repeating: lum * 0.85) * (weather == "storm" ? 0.6 : 1)
        return h * (1 - gray) + g * gray
    }

    /// 해를 받는 정도별 밝기 (해 쪽, 옆, 그늘). 해가 낮은 새벽·해질녘은 대비가 크고, 밤·흐린 날은 작음
    static func contrast(_ time: String, weather: String) -> [Float] {
        var lv: [Float]
        switch time {
        case "dawn", "dusk": lv = [1.0, 0.70, 0.48]
        case "morning": lv = [1.0, 0.80, 0.60]
        case "night": lv = [1.0, 0.90, 0.80]
        default: lv = [1.0, 0.84, 0.68]
        }
        if !["clear", "wind"].contains(weather) { lv = lv.map { 1 - (1 - $0) * 0.45 } }
        return lv
    }

    /// 안전: 밤·폭우라도 바닥·울타리·가구는 알아볼 만큼 밝게
    static func safe(_ c: SIMD3<Float>, min m: Float = 0.34) -> SIMD3<Float> {
        let l = max(c.x, max(c.y, c.z))
        return l >= m ? c : c * (m / max(l, 0.01))
    }

    static func weatherDim(_ w: String) -> Float {
        switch w {
        case "wind": return 0.97
        case "cloudy": return 0.86
        case "drizzle": return 0.78
        case "rain": return 0.7
        case "storm": return 0.52
        case "snow": return 0.92
        case "heavysnow": return 0.84
        default: return 1
        }
    }

    /// 하늘 그림 이름 (sky/)
    static func skyName(time: String, weather: String) -> String {
        let cond: String
        switch weather {
        case "clear", "wind": cond = "clear"
        case "cloudy": cond = "cloudy"
        case "storm": cond = "storm"
        default: cond = "overcast"
        }
        return "sky_\(time)_\(cond)"
    }

    /// 하늘을 흐르는 구름 조각 수 (하늘 그림에 구름이 이미 있어서 움직임만 더함)
    static func cloudCount(_ w: String) -> Int {
        switch w {
        case "clear": return 0
        case "wind": return 4
        case "cloudy": return 6
        case "storm": return 6
        default: return 4
        }
    }

    /// 하늘 그림의 해·달 방향 (tools/make_assets.py 와 같음: 방위 135°, 고도도 같게) — 면 밝기(그늘)에 씀
    static func sunDir(_ time: String) -> SIMD3<Float> {
        let el: Float
        switch time {
        case "dawn": el = 4
        case "morning": el = 20
        case "afternoon": el = 58
        case "dusk": el = 5
        default: el = 34
        }
        let az: Float = 135 * .pi / 180, e = el * .pi / 180
        return simd_normalize(SIMD3<Float>(cos(e) * cos(az), sin(e), cos(e) * sin(az)))
    }

    /// 무작위 세계 (seed 있으면 같은 결과)
    static func random<G: RandomNumberGenerator>(using g: inout G, avoid: Set<String> = []) -> (String, String, String) {
        let pool = places.map(\.id).filter { !avoid.contains($0) }
        let p = (pool.isEmpty ? places.map(\.id) : pool).randomElement(using: &g) ?? "camp"
        let w = weathers.randomElement(using: &g)?.id ?? "clear"
        let t = times.randomElement(using: &g)?.id ?? "afternoon"
        return (p, w, t)
    }
}
