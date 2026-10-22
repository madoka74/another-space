import SwiftUI

extension Worlds {
    /// 장소마다의 특별한 것 (아이콘 오른쪽 위 작은 색 표시). 새 장소 효과가 생기면 여기에 함께 넣음
    static func special(_ place: String) -> (symbol: String, color: Color)? {
        switch place {
        case "cafe": return ("music.note", Color(red: 0.98, green: 0.72, blue: 0.35))          // 오르골 음악
        case "camp": return ("flame.fill", Color(red: 1.0, green: 0.48, blue: 0.2))            // 모닥불
        case "forest": return ("sparkles", Color(red: 0.62, green: 0.78, blue: 1.0))           // 별자리
        case "village": return ("dog.fill", Color(red: 0.78, green: 0.84, blue: 0.95))         // 강아지
        case "home": return ("cat.fill", Color(red: 1.0, green: 0.8, blue: 0.55))              // 고양이
        case "gallery": return ("paintpalette.fill", Color(red: 0.95, green: 0.55, blue: 0.7))  // 그림
        case "valley": return ("drop.fill", Color(red: 0.45, green: 0.82, blue: 0.95))         // 개울·폭포
        default: return nil
        }
    }
}

/// 장소 아이콘 + 오른쪽 위 작은 색 표시 (그 장소의 특별한 것). 장소가 아닌 기호(날씨·시간)는 표시 없이 그대로
struct PlaceIcon: View {
    let id: String
    var symbol: String? = nil

    var body: some View {
        Image(systemName: symbol ?? Worlds.icon(id))
            .overlay(alignment: .topTrailing) {
                if let sp = Worlds.special(id) {
                    Image(systemName: sp.symbol)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(sp.color)
                        .frame(width: 15, height: 15)
                        .background(Circle().fill(Color.black.opacity(0.6)))
                        .offset(x: 9, y: -8)
                        .accessibilityHidden(true)
                }
            }
    }
}
