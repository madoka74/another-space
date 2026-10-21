import SwiftUI

/// 메인 창: 공간 목록 · 스캔 · 편집 · 탐험 시작
struct HomeView: View {
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @State private var path: [String] = []
    @State private var safetyFor: String?
    @State private var theming: ThemeTarget?
    private var model: AppModel { AppModel.shared }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    header
                    if let n = model.notice {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "info.circle")
                            Text(n).frame(maxWidth: .infinity, alignment: .leading)
                            Button { model.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
                        }
                        .padding(16)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                    }
                    if !AppModel.supported {
                        Text("이 기기에서는 공간을 알아볼 수 없어요. 비전프로 실기기에서 실행해 주세요.")
                            .foregroundStyle(.secondary)
                    }
                    if model.spaces.isEmpty { intro } else { list }
                }
                .padding(40)
                .frame(maxWidth: 980, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .overlay(alignment: .bottom) {
                Text(Self.version).font(.caption.monospacedDigit()).foregroundStyle(.tertiary).padding(.bottom, 14)
            }
            .navigationDestination(for: String.self) { id in MapEditView(spaceId: id) }
        }
        .onAppear {
            AppModel.shared.mainOpen = true
            let open = openImmersiveSpace, close = dismissImmersiveSpace
            AppModel.shared.openAction = {
                switch await open(id: "space") {
                case .opened: return true
                default: return false
                }
            }
            AppModel.shared.closeAction = { await close() }
            CloudBackup.start()
            model.reload()
            jumpToEdit()
        }
        .onChange(of: model.editId) { _, _ in jumpToEdit() }
        .sheet(item: Binding(get: { safetyFor.map { SheetId(id: $0) } }, set: { safetyFor = $0?.id })) { s in
            SafetySheet {
                safetyFor = nil
                model.start(.explore(s.id))
            } cancel: { safetyFor = nil }
        }
        .sheet(item: $theming) { t in ThemeSheet(target: t) { theming = nil } }
    }

    private func jumpToEdit() {
        if let id = model.editId {
            model.editId = nil
            path = [id]
        }
    }

    /// 앱 버전 (빌드할 때 version.json 값이 들어감)
    static var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "v\(v) (\(b))"
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("어나더 스페이스").font(.system(size: 44, weight: .bold))
            HStack {
                Text("문을 열 때마다 다른 세계").font(.title3).foregroundStyle(.secondary)
                Spacer()
                Button {
                    model.start(.scan(replace: nil))
                } label: {
                    Label("새 공간 스캔", systemImage: "viewfinder")
                }
                .disabled(!AppModel.supported)
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("모든 방을 천천히 걸으며 바닥·벽을 골고루", systemImage: "figure.walk")
            Label("문턱을 넘어 방 안쪽까지", systemImage: "door.left.hand.open")
            Label("끝나면 방 구성에서 사각형으로 다듬기", systemImage: "square.split.2x2")
        }
        .font(.title3)
        .foregroundStyle(.secondary)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(model.spaces) { s in
                SpaceCard(space: s) {
                    safetyFor = s.id
                } theme: { r in
                    theming = ThemeTarget(space: s.id, room: r)
                } edit: {
                    path = [s.id]
                }
            }
        }
    }
}

private struct SheetId: Identifiable { let id: String }

/// 메인 메뉴에서 방 하나의 세계 바꾸기
struct ThemeTarget: Identifiable, Hashable {
    let space: String
    let room: Int
    var id: String { "\(space)#\(room)" }
}

private struct ThemeSheet: View {
    let target: ThemeTarget
    let done: () -> Void
    @State private var room: RoomRec?
    @State private var unified = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let r = room {
                HStack {
                    Circle().fill(RoomColor.of(r.id)).frame(width: 12, height: 12)
                    Text(r.name).font(.title2.weight(.bold))
                    Spacer()
                    Button("완료", action: done).buttonStyle(.borderedProminent)
                }
                Text(r.title).font(.title3)
                if unified {
                    Label("모든 방에 같이 적용", systemImage: "square.on.square").font(.callout).foregroundStyle(.secondary)
                }
                ThemePicker(room: r) { p, w, t, l in
                    SpaceStore.setTheme(target.space, room: r.id, place: p, weather: w, time: t, look: l)
                    room?.place = p; room?.weather = w; room?.time = t; room?.look = l
                    AppModel.shared.reload()
                }
            }
        }
        .padding(30)
        .frame(width: 720)
        .onAppear {
            let sp = SpaceStore.list().first { $0.id == target.space }
            room = sp?.room(target.room)
            unified = sp?.isUnified ?? false
        }
    }
}

/// 공간 카드: 방마다 정한 세계 미리 보기 + 탐험 시작
private struct SpaceCard: View {
    let space: SpaceRec
    let explore: () -> Void
    let theme: (Int) -> Void
    let edit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(space.name.isEmpty ? "우리 집" : space.name).font(.title2.weight(.semibold))
                Text("방 \(space.rooms.count)곳").foregroundStyle(.secondary)
                Spacer()
                Button(action: edit) { Label("방 구성", systemImage: "square.split.2x2") }
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(space.rooms) { r in
                    Button { theme(r.id) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: Worlds.icon(r.place)).frame(width: 28).foregroundStyle(RoomColor.of(r.id))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.name).font(.headline)
                                Text(r.title).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "paintpalette").foregroundStyle(.secondary)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                        .tileHover(14)
                    }
                    .buttonStyle(.plain)
                    .buttonBorderShape(.roundedRectangle(radius: 14))
                }
            }
            HStack {
                Spacer()
                Button(action: explore) {
                    Label("탐험 시작", systemImage: "sparkles").font(.title3).padding(.horizontal, 14).padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!AppModel.supported || space.rooms.isEmpty)
                Spacer()
            }
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
    }
}

/// 탐험 전 안전 확인
struct SafetySheet: View {
    let go: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("다른 세계로 들어가기 전에").font(.title.weight(.bold))
            VStack(alignment: .leading, spacing: 12) {
                Label("바닥의 가방·전선 같은 물건을 치워 주세요.", systemImage: "shippingbox")
                Label("혼자 있을 때 써 주세요. 사람·반려동물은 안 보일 수 있어요.", systemImage: "person.2.slash")
                Label("천천히 걸어요. 빠르거나 방 밖이면 현실이 보여요.", systemImage: "figure.walk")
                Label("탭: 메뉴판 · 더블탭: 현실 원", systemImage: "hand.tap")
                Label("닫힌 문 앞에선 현실 원이 저절로 열려요.", systemImage: "door.left.hand.closed")
                Label("나가기: 메뉴판 또는 디지털 크라운", systemImage: "arrow.uturn.backward")
            }
            .font(.title3)
            HStack {
                Button("취소", action: cancel)
                Spacer()
                Button(action: go) { Text("확인했어요, 들어가기").font(.title3.weight(.semibold)).padding(.horizontal, 10) }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.top, 8)
        }
        .padding(36)
        .frame(width: 720)
    }
}

/// 방 색 (지도·목록 공통)
enum RoomColor {
    static let palette: [(Double, Double, Double)] = [
        (0.95, 0.66, 0.42), (0.47, 0.75, 0.62), (0.52, 0.66, 0.92), (0.88, 0.56, 0.72), (0.92, 0.82, 0.45),
        (0.62, 0.55, 0.88), (0.45, 0.80, 0.85), (0.85, 0.50, 0.48), (0.70, 0.82, 0.45), (0.80, 0.68, 0.55),
    ]
    static func rgb(_ id: Int) -> (Double, Double, Double) { palette[(max(1, id) - 1) % palette.count] }
    static func of(_ id: Int) -> Color { let c = rgb(id); return Color(red: c.0, green: c.1, blue: c.2) }
}
