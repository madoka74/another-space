import Foundation
import simd

/// 엠비언트와 같은 장소·날씨·시간 (id·이름이 엠비언트 카탈로그와 같아야 소리를 그대로 가져옴)
struct AxisItem: Hashable {
    let id: String
    let label: String
}

/// 장소마다 어떻게 보일지
struct WorldStyle {
    enum Skyline { case pines, trees, cliffs, sea, hills, city, lowCity, none }
    let floor: String               // 바닥 무늬 (Resources/tex)
    let wall: String                // 벽 무늬
    let prop: String                // 가구·물건 무늬
    let floorTint: SIMD3<Float>
    let wallTint: SIMD3<Float>
    let propTint: SIMD3<Float>
    let floorTile: Float            // 무늬 한 장이 덮는 길이(m)
    let wallTile: Float
    let propTile: Float
    let ground: SIMD3<Float>        // 창 너머·지평선 아래 땅 색
    let skyline: Skyline            // 벽 너머로 보이는 것 (천장·창으로)
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
            return WorldStyle(floor: "grass", wall: "forest", prop: "bark", floorTint: w, wallTint: w, propTint: w,
                              floorTile: 1.6, wallTile: 2.4, propTile: 0.8, ground: [0.18, 0.27, 0.13], skyline: .pines, skylight: false)
        case "forest":
            return WorldStyle(floor: "moss", wall: "forest", prop: "rock", floorTint: w, wallTint: [0.9, 1, 0.9], propTint: [0.75, 0.9, 0.7],
                              floorTile: 1.4, wallTile: 2.0, propTile: 0.9, ground: [0.14, 0.24, 0.11], skyline: .trees, skylight: false)
        case "valley":
            return WorldStyle(floor: "pebble", wall: "cliff", prop: "rock", floorTint: w, wallTint: w, propTint: [0.95, 0.92, 0.88],
                              floorTile: 1.2, wallTile: 3.0, propTile: 0.9, ground: [0.34, 0.31, 0.27], skyline: .cliffs, skylight: false)
        case "sea":
            return WorldStyle(floor: "sand", wall: "basalt", prop: "rock", floorTint: w, wallTint: w, propTint: [0.92, 0.9, 0.84],
                              floorTile: 1.8, wallTile: 2.2, propTile: 0.9, ground: [0.10, 0.22, 0.32], skyline: .sea, skylight: false)
        case "village":
            return WorldStyle(floor: "dirt", wall: "stonewall", prop: "hay", floorTint: w, wallTint: w, propTint: w,
                              floorTile: 1.6, wallTile: 1.6, propTile: 0.8, ground: [0.28, 0.34, 0.18], skyline: .hills, skylight: false)
        case "city":
            return WorldStyle(floor: "asphalt", wall: time == "night" || time == "dawn" ? "facade_night" : "facade", prop: "concrete",
                              floorTint: w, wallTint: w, propTint: w,
                              floorTile: 2.0, wallTile: 2.4, propTile: 1.0, ground: [0.22, 0.22, 0.24], skyline: .city, skylight: false)
        case "cafe":
            return WorldStyle(floor: "planks", wall: "brick", prop: "planks", floorTint: w, wallTint: w, propTint: [0.85, 0.8, 0.75],
                              floorTile: 1.6, wallTile: 1.4, propTile: 0.8, ground: [0.22, 0.22, 0.24], skyline: .lowCity, skylight: true)
        case "gallery":
            return WorldStyle(floor: "marble", wall: "plaster", prop: "marble", floorTint: w, wallTint: w, propTint: w,
                              floorTile: 2.0, wallTile: 2.0, propTile: 1.0, ground: [0.28, 0.30, 0.26], skyline: .none, skylight: true)
        default:   // home: 숲속 통나무집
            return WorldStyle(floor: "planks", wall: "timber", prop: "bark", floorTint: [0.95, 0.9, 0.85], wallTint: w, propTint: w,
                              floorTile: 1.6, wallTile: 1.8, propTile: 0.8, ground: [0.16, 0.26, 0.12], skyline: .trees, skylight: true)
        }
    }

    /// 시간에 따른 밝기·색 (실내 장소는 밤·새벽·해질녘에 따뜻한 등불 빛)
    static func timeTint(_ time: String, indoor: Bool) -> SIMD3<Float> {
        switch time {
        case "dawn": return indoor ? [0.62, 0.55, 0.5] : [0.6, 0.6, 0.8]
        case "morning": return [1.0, 0.95, 0.87]
        case "dusk": return indoor ? [0.92, 0.72, 0.55] : [0.95, 0.70, 0.55]
        case "night": return indoor ? [0.58, 0.46, 0.34] : [0.36, 0.39, 0.56]
        default: return [1, 1, 1]
        }
    }

    static func weatherDim(_ w: String) -> Float {
        switch w {
        case "wind": return 0.97
        case "cloudy": return 0.85
        case "drizzle": return 0.8
        case "rain": return 0.72
        case "storm": return 0.56
        case "snow": return 0.92
        case "heavysnow": return 0.86
        default: return 1
        }
    }

    /// 하늘 그림 이름 (Resources/sky)
    static func skyName(time: String, weather: String) -> String {
        let cond: String
        switch weather {
        case "clear", "wind": cond = "clear"
        case "storm": cond = "storm"
        default: cond = "overcast"
        }
        return "sky_\(time)_\(cond)"
    }

    /// 하늘에 띄울 구름 수
    static func cloudCount(_ w: String) -> Int {
        switch w {
        case "clear": return 2
        case "wind": return 6
        case "cloudy": return 12
        case "storm": return 14
        default: return 9
        }
    }

    /// 하늘 그림의 해·달 방향 (tools/make_assets.py 와 같음: 방위 135°) — 면 밝기(그늘)에 씀
    static func sunDir(_ time: String) -> SIMD3<Float> {
        let el: Float
        switch time {
        case "dawn": el = 10
        case "morning": el = 24
        case "afternoon": el = 58
        case "dusk": el = 8
        default: el = 38
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
