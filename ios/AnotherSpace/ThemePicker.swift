import SwiftUI

extension View {
    /// 직접 그린 둥근 사각 버튼: 누르는 자리와 바라볼 때 빛나는 모양을 그 둥근 사각 그대로 (기본은 원·캡슐 모양으로 빛남)
    func tileHover(_ radius: CGFloat) -> some View {
        self.contentShape(.interaction, RoundedRectangle(cornerRadius: radius))
            .contentShape(.hoverEffect, RoundedRectangle(cornerRadius: radius))
            .hoverEffect(.highlight)
    }
}

/// 방의 세계(장소·날씨·시간)를 칩 한 번 누르기로 바꾸는 판. 메인 메뉴·편집·탐험 중 안내판에서 같이 씀
struct ThemePicker: View {
    let room: RoomRec
    var compact = false
    /// (장소, 날씨, 시간, 표시 방식)
    let set: (String, String, String, String) -> Void

    private var look: String { room.lookMode.rawValue }
    private static let looks = LookMode.allCases.map { AxisItem(id: $0.rawValue, label: $0.label) }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 10 : 14) {
            row("장소", Worlds.places, room.place) { set($0, room.weather, room.time, look) }
            row("날씨", Worlds.weathers, room.weather) { set(room.place, $0, room.time, look) }
            row("시간", Worlds.times, room.time) { set(room.place, room.weather, $0, look) }
            lookRow
        }
    }

    private var chipW: CGFloat { compact ? 60 : 64 }
    private var chipH: CGFloat { compact ? 54 : 60 }
    /// 장소 줄 폭 (칩 9개) — 표시 줄의 '아무 세계나' 버튼 오른쪽 끝을 이 폭에 맞춤
    private var fullW: CGFloat { CGFloat(Worlds.places.count) * chipW + CGFloat(max(0, Worlds.places.count - 1)) * 8 }

    /// 표시 줄: 컬러·흑백·선 그림 칩 + 오른쪽 끝에 '아무 세계나' (칩과 같은 높이, 장소 줄 오른쪽 끝에 맞춤)
    private var lookRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("표시").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(Self.looks, id: \.id) { it in
                    chip(it, on: it.id == look) { set(room.place, room.weather, room.time, it.id) }
                }
                Spacer(minLength: 8)
                Button {
                    var g = SystemRandomNumberGenerator()
                    let (p, w, t) = Worlds.random(using: &g, avoid: [room.place])
                    set(p, w, t, look)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "dice").font(.system(size: 20))
                        Text("아무 세계나").font(.callout)
                    }
                    .padding(.horizontal, 14)
                    .frame(height: chipH)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    .tileHover(14)
                }
                .buttonStyle(.plain)
            }
            .frame(width: fullW)
            .padding(.vertical, 2)
        }
    }

    private func chip(_ it: AxisItem, on: Bool, _ pick: @escaping () -> Void) -> some View {
        Button {
            pick()
        } label: {
            VStack(spacing: 4) {
                PlaceIcon(id: it.id, symbol: LookMode(rawValue: it.id)?.icon, size: 26)
                Text(it.label).font(.caption)
            }
            .frame(width: chipW, height: chipH)
            .background(on ? Color.accentColor.opacity(0.45) : Color.white.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 14))
            .tileHover(14)
        }
        .buttonStyle(.plain)
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
                                PlaceIcon(id: it.id, symbol: LookMode(rawValue: it.id)?.icon, size: 26)
                                Text(it.label).font(.caption)
                            }
                            .frame(width: compact ? 60 : 64, height: compact ? 54 : 60)
                            .background(on ? Color.accentColor.opacity(0.45) : Color.white.opacity(0.08),
                                        in: RoundedRectangle(cornerRadius: 14))
                            .tileHover(14)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}
