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
        case "sea": return ("bubbles.and.sparkles", Color(red: 0.62, green: 0.72, blue: 1.0))         // 해파리
        case "valley": return ("fish.fill", Color(red: 1.0, green: 0.55, blue: 0.3))                 // 물고기
        case "city": return ("lightbulb.fill", Color(red: 1.0, green: 0.35, blue: 0.8))              // 네온사인
        default: return nil
        }
    }
}

/// 장소 아이콘 + 오른쪽 위 작은 색 표시 (그 장소의 특별한 것). 어디서 쓰든 같은 모양:
/// 아이콘은 size×size 칸 가운데, 표시는 그 칸의 오른쪽 위 모서리에 칸 크기에 비례해 (기호 모양·글자 크기와 상관없이 늘 같은 자리).
/// 장소가 아닌 기호(날씨·시간·표시 방식)는 표시 없이 같은 칸에
struct PlaceIcon: View {
    let id: String
    var symbol: String? = nil
    var size: CGFloat = 26

    var body: some View {
        ZStack {
            Image(systemName: symbol ?? Worlds.icon(id))
                .font(.system(size: size * 0.72, weight: .regular))
                .frame(width: size, height: size)
            if let sp = Worlds.special(id) {
                Image(systemName: sp.symbol)
                    .font(.system(size: size * 0.4, weight: .bold))
                    .foregroundStyle(sp.color)
                    .shadow(color: .black.opacity(0.55), radius: 1)
                    .frame(width: size * 0.5, height: size * 0.5)
                    .position(x: size * 0.98, y: size * 0.04)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: size, height: size)
    }
}
