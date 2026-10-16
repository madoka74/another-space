import SwiftUI

/// 메인 창: 공간 목록 · 스캔 · 편집 · 탐험 시작
struct HomeView: View {
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @State private var path: [String] = []
    @State private var safetyFor: String?
    @State private var deleting: SpaceRec?
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
        .alert("이 공간을 지울까요?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("지우기", role: .destructive) {
                if let d = deleting { SpaceStore.delete(d.id); model.reload() }
                deleting = nil
            }
            Button("취소", role: .cancel) { deleting = nil }
        } message: {
            Text("스캔한 모양과 방 구분, 방마다 정한 세계가 모두 지워져요.")
        }
    }

    private func jumpToEdit() {
        if let id = model.editId {
            model.editId = nil
            path = [id]
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("어나더 스페이스").font(.system(size: 44, weight: .bold))
            Text("익숙한 집이, 문을 열 때마다 다른 세계가 돼요").font(.title3).foregroundStyle(.secondary)
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("먼저 집을 한 번 스캔해 주세요").font(.title2.weight(.semibold))
            VStack(alignment: .leading, spacing: 10) {
                Label("집 안의 모든 방을 천천히 걸어 다니며 바닥과 벽을 골고루 바라봐요.", systemImage: "figure.walk")
                Label("문턱을 넘어 방 안쪽까지 들어가야 그 방이 생겨요.", systemImage: "door.left.hand.open")
                Label("스캔이 끝나면 방이 자동으로 나뉘고, 합치기·나누기·이름 붙이기로 다듬을 수 있어요.", systemImage: "square.split.2x2")
            }
            .foregroundStyle(.secondary)
            Button {
                model.start(.scan(replace: nil))
            } label: {
                Label("공간 스캔 시작", systemImage: "viewfinder").font(.title3).padding(.horizontal, 12).padding(.vertical, 6)
            }
            .disabled(!AppModel.supported)
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(model.spaces) { s in
                SpaceCard(space: s) {
                    safetyFor = s.id
                } edit: {
                    path = [s.id]
                } rescan: {
                    model.start(.scan(replace: s.id))
                } delete: {
                    deleting = s
                }
            }
            Button {
                model.start(.scan(replace: nil))
            } label: {
                Label("새 공간 스캔", systemImage: "plus")
            }
            .disabled(!AppModel.supported)
        }
    }
}

private struct SheetId: Identifiable { let id: String }

/// 공간 카드: 방마다 정한 세계 미리 보기 + 탐험 시작
private struct SpaceCard: View {
    let space: SpaceRec
    let explore: () -> Void
    let edit: () -> Void
    let rescan: () -> Void
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(space.name.isEmpty ? "우리 집" : space.name).font(.title2.weight(.semibold))
                Text("방 \(space.rooms.count)곳").foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button("방 편집", systemImage: "square.split.2x2", action: edit)
                    Button("다시 스캔", systemImage: "viewfinder", action: rescan)
                    Button("지우기", systemImage: "trash", role: .destructive, action: delete)
                } label: { Image(systemName: "ellipsis").frame(width: 36, height: 36) }
                .buttonStyle(.borderless)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 10)], alignment: .leading, spacing: 10) {
                ForEach(space.rooms) { r in
                    HStack(spacing: 10) {
                        Circle().fill(RoomColor.of(r.id)).frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.name).font(.headline)
                            Text(r.title).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            HStack(spacing: 12) {
                Button(action: explore) {
                    Label("탐험 시작", systemImage: "sparkles").font(.title3).padding(.horizontal, 10).padding(.vertical, 4)
                }
                .disabled(!AppModel.supported || space.rooms.isEmpty)
                Button("방 편집", action: edit)
            }
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28))
    }
}

/// 탐험 전 안전 확인
private struct SafetySheet: View {
    let go: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("다른 세계로 들어가기 전에").font(.title.weight(.bold))
            VStack(alignment: .leading, spacing: 12) {
                Label("바닥에 걸려 넘어질 물건(가방·전선·장난감)을 치워 주세요. 낮고 작은 물건은 잘 안 보일 수 있어요.", systemImage: "shippingbox")
                Label("집에 혼자 있을 때 써 주세요. 움직이는 사람·반려동물은 다른 세계에 가려 안 보일 수 있어요.", systemImage: "person.2.slash")
                Label("천천히 걸어 주세요. 빠르게 움직이거나 스캔하지 않은 곳에 들어가면 현실이 다시 보여요.", systemImage: "figure.walk")
                Label("벽은 언제나 지나갈 수 없는 모양(숲·절벽·건물)으로 보여요. 열린 길처럼 보이는 곳만 걸어요.", systemImage: "rectangle.portrait.on.rectangle.portrait")
                Label("아래를 내려다보면 나가기 버튼이 있어요. 디지털 크라운을 눌러도 바로 나와요.", systemImage: "arrow.down.circle")
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
