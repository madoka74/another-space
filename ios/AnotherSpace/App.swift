import SwiftUI
import ARKit

/// 어나더 스페이스: 메인 창(공간 목록·편집) + 몰입 공간(스캔 / 탐험)
@main
struct AnotherSpaceApp: App {
    var body: some Scene {
        WindowGroup(id: "main") {
            HomeView()
        }
        .defaultSize(width: 1180, height: 780)

        // 공간설정에서 고른 방·문 조정 창 (옮길 수 있는 따로 된 창, 처음엔 메인 창 오른쪽)
        WindowGroup(id: "inspector", for: String.self) { _ in
            ShapeInspector()
        }
        .defaultSize(width: 520, height: 760)
        .defaultWindowPlacement { _, context in
            if let main = context.windows.first(where: { $0.id == "main" }) {
                return WindowPlacement(.trailing(main))
            }
            return WindowPlacement()
        }

        // 현실 위에 다른 세계를 덮는 공간. 걸어 다녀야 하므로 '섞인 모드'로 열고(완전 몰입은 1.5m를 못 벗어남),
        // 현실이 보일 틈은 앱이 직접 바닥·벽·하늘로 덮음. 스캔하지 않은 곳·그물이 없는 곳은 현실이 그대로 보임(안전)
        ImmersiveSpace(id: "space") {
            ImmersiveRoot()
        }
    }
}

/// 몰입 공간을 무엇으로 열지, 끝나면 어디로 돌아갈지
@MainActor @Observable
final class AppModel {
    static let shared = AppModel()

    enum Mode: Equatable {
        case scan(replace: String?)       // 새로 스캔하거나 기존 공간을 다시 스캔
        case explore(String)              // 이 공간 탐험
    }

    var mode: Mode?
    var spaces: [SpaceRec] = []
    var editId: String?                   // 스캔을 마치면 바로 이 공간 편집 화면으로
    @ObservationIgnored var returnEdit: String?    // 공간설정에서 탐험을 시작했으면 끝난 뒤 그 화면으로
    var notice: String?                   // 메인 창에 띄울 안내 한 줄
    @ObservationIgnored var openAction: (@MainActor () async -> Bool)?
    @ObservationIgnored var closeAction: (@MainActor () async -> Void)?
    @ObservationIgnored var openMain: (@MainActor () -> Void)?
    @ObservationIgnored var mainOpen = true
    @ObservationIgnored private var isOpen = false
    @ObservationIgnored private var busy = false

    /// 공간 인식이 되는 기기인지 (시뮬레이터는 안 됨)
    static var supported: Bool { WorldTrackingProvider.isSupported && SceneReconstructionProvider.isSupported }

    func reload() { spaces = SpaceStore.list() }

    /// 몰입 공간 열기
    func start(_ m: Mode, returnTo: String? = nil) {
        guard !busy else { return }
        busy = true
        returnEdit = returnTo
        Task {
            if isOpen, let closeAction { await closeAction(); isOpen = false }
            mode = m
            let ok = await openAction?() ?? false
            isOpen = ok
            busy = false
            if !ok {
                mode = nil
                notice = "다른 세계를 열지 못했어요. 다른 앱의 몰입 화면이 열려 있으면 닫고 다시 해 주세요."
                reopenMain()
            }
        }
    }

    /// 몰입 공간 닫기 (메인 창을 지금 있는 자리 앞에 다시 띄움). savedId: 방금 저장한 공간 → 편집 화면으로
    func finish(savedId: String? = nil, message: String? = nil) {
        Task {
            editId = savedId ?? returnEdit
            returnEdit = nil
            if let message { notice = message }
            reload()
            reopenMain()
            if isOpen, let closeAction { await closeAction() }
            isOpen = false
            mode = nil
        }
    }

    /// 사용자가 시스템 쪽(디지털 크라운 등)에서 몰입 공간을 닫았을 때
    func disappeared() {
        if editId == nil { editId = returnEdit }
        returnEdit = nil
        isOpen = false
        mode = nil
        reload()
        reopenMain()
    }

    func reopenMain() {
        guard !mainOpen, let openMain else { return }
        mainOpen = true
        openMain()
    }
}

/// 몰입 공간 안: 모드에 따라 스캔 / 탐험
struct ImmersiveRoot: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some View {
        Group {
            switch AppModel.shared.mode {
            case .scan(let replace)?: ScanView(replace: replace)
            case .explore(let id)?: ExploreView(spaceId: id)
            case nil: Color.clear
            }
        }
        .onAppear {
            // 다른 세계에 있는 동안 메인 창은 닫아 둠 (끝나면 그때 내 앞에 다시 띄움)
            let ow = openWindow
            AppModel.shared.openMain = { ow(id: "main") }
            AppModel.shared.mainOpen = false
            dismissWindow(id: "main")
        }
    }
}
