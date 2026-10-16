import SwiftUI

/// 방의 세계(장소·날씨·시간)를 칩 한 번 누르기로 바꾸는 판. 메인 메뉴·편집·탐험 중 안내판에서 같이 씀
struct ThemePicker: View {
    let room: RoomRec
    var compact = false
    /// (장소, 날씨, 시간)
    let set: (String, String, String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            row("장소", Worlds.places, room.place) { set($0, room.weather, room.time) }
            row("날씨", Worlds.weathers, room.weather) { set(room.place, $0, room.time) }
            row("시간", Worlds.times, room.time) { set(room.place, room.weather, $0) }
            Button {
                var g = SystemRandomNumberGenerator()
                let (p, w, t) = Worlds.random(using: &g, avoid: [room.place])
                set(p, w, t)
            } label: {
                Label("아무 세계나", systemImage: "dice")
            }
        }
    }

    private func row(_ title: String, _ items: [AxisItem], _ cur: String, _ pick: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items, id: \.id) { it in
                        let on = it.id == cur
                        Button {
                            pick(it.id)
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: Worlds.icon(it.id)).font(.title3)
                                Text(it.label).font(.caption)
                            }
                            .frame(width: compact ? 60 : 68, height: compact ? 54 : 60)
                            .background(on ? Color.accentColor.opacity(0.45) : Color.white.opacity(0.08),
                                        in: RoundedRectangle(cornerRadius: 14))
                            .contentShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .hoverEffect(.highlight)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}
