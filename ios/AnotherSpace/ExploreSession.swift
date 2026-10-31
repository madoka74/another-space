import SwiftUI
import RealityKit
import ARKit
import QuartzCore

/// 탐험: 저장한 공간을 다시 알아본 뒤, 방마다 다른 세계를 입힘.
/// - 바닥·벽·천장(하늘)·창: 사각형으로 구성한 집 모양에서 반듯하게 만듦 (유리·거울·스캔이 빈 곳도 빈틈없이)
/// - 가구·물건: 10cm 블록 (스캔·탐험하며 알아낸 것을 저장해 두고 처음부터 보임, 지금 보이는 그물로 고쳐 감)
struct ExploreView: View {
    let spaceId: String
    @State private var s: ExploreSession

    init(spaceId: String) {
        self.spaceId = spaceId
        _s = State(initialValue: ExploreSession(spaceId: spaceId))
    }

    var body: some View {
        RealityView { content, attachments in
            content.add(s.root)
            if let hud = attachments.entity(for: "hud") { s.attachHud(hud) }
            if let card = attachments.entity(for: "docent") { s.attachDocent(card) }
            if let tp = attachments.entity(for: "theme") { s.attachTheme(tp) }
            if let sc = attachments.entity(for: "stars") { s.attachStars(sc) }
            if let fp = attachments.entity(for: "furn") { s.attachFurn(fp) }
            s.updateSub = content.subscribe(to: SceneEvents.Update.self) { e in s.tick(Float(e.deltaTime)) }
        } attachments: {
            Attachment(id: "hud") { ExploreHud(s: s) }
            Attachment(id: "docent") { DocentCard(s: s) }
            Attachment(id: "theme") { ThemePanel(s: s) }
            Attachment(id: "stars") { StarCard(s: s) }
            Attachment(id: "furn") { FurnPanel(s: s) }
        }
        // 탭은 손짓 하나에 한 번씩만 받고(시스템 탭·손 추적 짝짓기), 싱글·더블은 앱이 가름: 두 번째 탭이 0.45초 안에 오면 더블탭, 안 오면 그때 싱글탭.
        // 보는 곳 어디든 받도록 머리 둘레에 보이지 않는 '탭 받는 상자'를 둠. 열쇠·그림 버튼은 바로 처리
        .gesture(SpatialTapGesture().targetedToAnyEntity().onEnded { v in
            s.tapped(v.entity, at: v.convert(v.location3D, from: .local, to: .scene))
        })
        // 창(안내판·테마 판·해설·별자리 정보) 아래 막대를 잡고 끌면 창을 옮김
        .simultaneousGesture(DragGesture().targetedToEntity(where: .has(GrabTag.self)).onChanged { v in
            s.dragPanel(v.entity, to: v.convert(v.location3D, from: .local, to: .scene))
        })
        // 장난감(털실 공·막대)을 집어 옮기고 놓으면 던짐
        .simultaneousGesture(DragGesture(minimumDistance: 0.01).targetedToEntity(where: .has(ToyTag.self)).onChanged { v in
            s.dragToy(v.entity, to: v.convert(v.location3D, from: .local, to: .scene))
        }.onEnded { v in
            s.dropToy(v.entity)
        })
        // 가구 맞추기: 상자를 집어 끌면 옮김, 두 손으로 집어 벌리거나 좁히면 크기를 바꿈
        .simultaneousGesture(DragGesture(minimumDistance: 0.01).targetedToEntity(where: .has(FurnTag.self)).onChanged { v in
            s.dragFurn(v.entity, to: v.convert(v.location3D, from: .local, to: .scene))
        }.onEnded { _ in
            s.dropFurn()
        })
        .simultaneousGesture(MagnifyGesture().targetedToEntity(where: .has(FurnTag.self)).onChanged { v in
            s.scaleFurn(v.entity, Float(v.gestureValue.magnification))
        }.onEnded { _ in
            s.scaleFurnEnd()
        })
        .task { await s.start() }
        .onDisappear { s.stop() }
    }
}

/// 안내판: 알림판(방이 바뀌거나 알릴 말이 있을 때 시선 아래쪽에 잠깐) / 메뉴판(싱글탭 — 눈앞, 테마 바꾸기·나가기)
private struct ExploreHud: View {
    let s: ExploreSession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    if let r = s.room {
                        Text(r.title).font(.title3.weight(.semibold))
                        Text(r.name).font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Button {
                    s.closeHud()
                } label: {
                    Image(systemName: "xmark").font(.body.weight(.semibold)).frame(width: 30, height: 30)
                }
                .buttonBorderShape(.circle)
            }
            if let p = s.loadProgress {
                LoadBar(value: p).frame(width: 300)
            }
            if let m = s.message {
                Text(m).font(.headline).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 360, alignment: .leading)
            }
            if s.hudMenu {
                HStack(spacing: 14) {
                    if s.room != nil {
                        Button {
                            if s.menuReady() { s.toggleTheme() }
                        } label: {
                            Label(s.unified ? "모든 방 테마 바꾸기" : "테마 바꾸기", systemImage: "paintpalette")
                        }
                    }
                    Button {
                        if s.menuReady() { s.startFurn() }
                    } label: {
                        Label("가구 맞추기", systemImage: "cube.transparent")
                    }
                    Button {
                        if s.menuReady() { s.exit() }
                    } label: {
                        Label("현실로 돌아가기", systemImage: "arrow.uturn.backward")
                    }
                }
                .font(.body)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .fixedSize()                                    // 내용에 맞는 크기 (좌우로 길게 늘어나지 않게)
        .glassBackgroundEffect()
        .transaction { $0.animation = nil }
        .simultaneousGesture(TapGesture().onEnded { s.uiTouched() })     // 안내판을 누른 탭은 싱글탭으로 치지 않음
    }
}

/// 불러오는 중 막대: 0→100% 차오름 (글 설명 없이)
private struct LoadBar: View {
    let value: Double

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18))
                Capsule().fill(.white.opacity(0.9))
                    .frame(width: max(8, g.size.width * min(1, max(0, value))))
            }
        }
        .frame(height: 8)
        .padding(.vertical, 4)
    }
}

/// 끌 수 있는 막대 표시 (창 옮기기) — panel: 어느 창의 막대인지
struct GrabTag: Component { var panel: String = "" }
/// 집어서 던질 수 있는 장난감 (고양이 털실 공·강아지 막대)
struct ToyTag: Component {}
/// 가구 맞추기의 상자 (넣은 가구 번호)
struct FurnTag: Component { var index: Int = 0 }

/// 가구 맞추기 판. 두 상태로만 움직임:
/// - 고르기: 하는 법 · 되돌리기 · 처음 스캔대로(확인) · 끝내기. 가구·빈 바닥을 탭하면 그 가구 편집을 시작
/// - 편집 중(가구 하나): 폭·깊이·높이 · 돌리기 · 이 가구 완료 / 취소. 완료나 취소를 눌러야 다른 가구를 고르거나 끝낼 수 있음.
///   지우기는 판 맨 위 오른쪽에 따로, 한 번 더 확인
private struct FurnPanel: View {
    let s: ExploreSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let b = s.furnSelBox {
                HStack(spacing: 12) {
                    Label(s.furnIsNew ? "새 가구 편집 중" : "가구 편집 중", systemImage: "cube.transparent").font(.title3.weight(.semibold))
                    Spacer(minLength: 8)
                    if s.furnConfirm == "delete" {
                        Text("이 가구를 지울까요?").font(.callout)
                        Button("지우기", role: .destructive) { s.deleteFurn() }.buttonStyle(.borderedProminent).tint(.red)
                        Button("아니요") { s.setFurnConfirm(nil) }
                    } else {
                        Button(role: .destructive) { s.setFurnConfirm("delete") } label: { Image(systemName: "trash") }
                            .buttonBorderShape(.circle)
                    }
                }
                Text("이 가구만 끌어서 옮기고, 두 손으로 집어 크기를 바꿀 수 있어요").font(.callout).foregroundStyle(.secondary)
                SwiftUI.Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                    row("폭", b.w, { s.resizeFurn(dw: $0) })
                    row("깊이", b.d, { s.resizeFurn(dd: $0) })
                    row("높이", b.h, { s.resizeFurn(dh: $0) })
                }
                Button { s.rotateFurn() } label: { Label("90° 돌리기", systemImage: "rotate.right") }
                Divider()
                HStack(spacing: 12) {
                    Button { s.cancelFurnEdit() } label: { Text("취소") }
                    Spacer(minLength: 0)
                    Button { s.commitFurnEdit() } label: { Label("이 가구 완료", systemImage: "checkmark") }.buttonStyle(.borderedProminent)
                }
            } else {
                HStack(spacing: 12) {
                    Label("가구 맞추기", systemImage: "cube.transparent").font(.title3.weight(.semibold))
                    Spacer(minLength: 8)
                    Button("끝내기") { s.endFurn() }.buttonStyle(.borderedProminent)
                }
                Text("고칠 가구를 탭하세요 (탭한 곳의 평평한 면만 상자가 돼요).\n빈 바닥을 탭하면 새 가구를 놓아요.").font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button { s.undoFurn() } label: { Label("되돌리기", systemImage: "arrow.uturn.backward") }
                        .disabled(!s.furnCanUndo)
                    Spacer(minLength: 0)
                    if s.furnConfirm == "reset" {
                        Text("손으로 고친 것을 모두 지울까요?").font(.caption)
                        Button("모두 지우기", role: .destructive) { s.resetFurn() }.tint(.red)
                        Button("아니요") { s.setFurnConfirm(nil) }
                    } else {
                        Button(role: .destructive) { s.setFurnConfirm("reset") } label: { Label("처음 스캔대로", systemImage: "arrow.counterclockwise") }
                            .disabled(s.furnEdits.adds.isEmpty && s.furnEdits.erases.isEmpty)
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 460)
        .glassBackgroundEffect()
        .transaction { $0.animation = nil }
        .simultaneousGesture(TapGesture().onEnded { s.furnTouched() })      // 판을 누른 탭 (알림판을 띄우지 않음)
    }

    @ViewBuilder
    private func row(_ name: String, _ v: Float, _ change: @escaping (Float) -> Void) -> some View {
        SwiftUI.GridRow {
            Text(name).frame(width: 44, alignment: .leading)
            Button { change(-0.1) } label: { Image(systemName: "minus") }.buttonBorderShape(.circle)
            Text("\(Int((v * 100).rounded()))cm").monospacedDigit().frame(width: 70)
            Button { change(0.1) } label: { Image(systemName: "plus") }.buttonBorderShape(.circle)
        }
    }
}

/// 테마 판: 크기가 늘 같은 판 (칩 9개가 딱 들어가는 폭, 좌우 여백 같게)
private struct ThemePanel: View {
    let s: ExploreSession

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    if let r = s.room {
                        Text(r.title).font(.title2.weight(.semibold))
                        Text(r.name).font(.headline).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Button {
                    s.closeHud()
                } label: {
                    Image(systemName: "xmark").font(.title3).frame(width: 36, height: 36)
                }
                .buttonBorderShape(.circle)
            }
            if let r = s.room {
                ThemePicker(room: r, compact: true) { p, w, t, l in s.setTheme(place: p, weather: w, time: t, look: l) }
            }
            // (테마 판에는 진행 막대를 넣지 않음 — 판 크기가 바뀌어 보기 안 좋음. 닫기는 오른쪽 위 X)
        }
        .padding(24)
        .frame(width: 652)                              // 칩 60×9 + 사이 8×8 = 604, 좌우 여백 24씩
        .glassBackgroundEffect()
        .transaction { $0.animation = nil }
        .simultaneousGesture(TapGesture().onEnded { s.uiTouched() })
    }
}

@MainActor @Observable
final class ExploreSession {
    var room: RoomRec?
    var message: String? = nil
    /// 불러오는 중 진행 막대 (0~1, 없으면 숨김) — 탐험 시작·테마 바꾸기. 글 설명 대신 막대가 0→100% 차오름
    var loadProgress: Double? = 0
    var themeOpen = false
    var unified = false             // 모든 방이 같은 세계 (테마를 바꾸면 모든 방이 같이 바뀜)
    var hudMenu = false             // 싱글탭으로 띄운 메뉴판 (아니면 알림판)
    var docent: DocentState?        // 지금 펼친 그림 설명
    var starPick: Constellation?    // 지금 펼친 별자리 정보판

    let root = Entity()
    @ObservationIgnored var updateSub: EventSubscription?
    @ObservationIgnored private let spaceId: String
    @ObservationIgnored private let spaceRoot = Entity()      // 저장 좌표 → 지금 좌표
    @ObservationIgnored private var vox: VoxelWorld?          // 가구·물건 (10cm 블록, 저장 좌표)
    @ObservationIgnored private var seedTask: Task<Void, Never>?
    @ObservationIgnored private var voxSaveT: Float = 0
    @ObservationIgnored private var ready = false             // 모든 방 세계를 다 만들었는지
    @ObservationIgnored private var themeProg: Float?          // 테마 바꾸는 중 진행 (0~1)
    @ObservationIgnored private var progShown: Float = 0
    @ObservationIgnored private var progDoneAt: Float?
    // 문
    @ObservationIgnored private var doorOpen: Set<Int> = []   // 열쇠로 연 문 (다른 세계 사이)
    @ObservationIgnored private var doorShow: [Int: Float] = [:]    // 열쇠 문 보이는 정도
    @ObservationIgnored private var doorSide: [Int: Float] = [:]    // 문을 열 때 서 있던 쪽 (지나가면 닫음)
    @ObservationIgnored private var lastSide: [Int: Float] = [:]    // 문 밖에서 마지막으로 서 있던 쪽
    @ObservationIgnored private var nearDoors: Set<Int> = []        // 1m 안 (1.2m 밖으로 나가야 빠짐 — 경계에서 깜빡이지 않게)
    @ObservationIgnored private var realHits: [Int: [UUID: Set<Int>]] = [:]   // 문 → 그물 덩어리마다 막힌 칸
    @ObservationIgnored private var cover: [Int: Float] = [:]       // 문틀 안쪽이 막힌 비율
    @ObservationIgnored private var closeSince: [Int: Float] = [:]  // 닫힘 증거가 시작된 때 (1초 이어지면 닫힘)
    @ObservationIgnored private var doorSeenAt: [Int: Float] = [:]  // 그 문 자리를 그물·평면으로 마지막에 새로 본 때
    @ObservationIgnored private var nearAt: [Int: Float] = [:]      // 그 문 1m 안에 들어온 때
    @ObservationIgnored private var openHold: [Int: Float] = [:]    // 이때까지는 다시 닫힘으로 치지 않음 (방금 문 자리를 지남)
    @ObservationIgnored private var realClosed: Set<Int> = []       // 실제 문이 닫혀 있는 문
    @ObservationIgnored private var doorPlanes: [UUID: (Int, Bool)] = [:]   // 문으로 알아본 평면 → (문 번호, 문 자리를 가로막고 있는지)
    @ObservationIgnored private var doorPlaneW: [UUID: Float] = [:]  // 그때 그 평면의 폭
    @ObservationIgnored private var doorPlaneS: [UUID: Float] = [:]  // 문 자리를 가로막던 평면의 가운데 (문 폭 방향 자리) — 미닫이가 밀려났는지 보려고
    @ObservationIgnored private var passedAt: [Int: Float] = [:]     // 열린 문을 마지막으로 건너간 때
    @ObservationIgnored private var heldHits: [Int: [UUID: Set<Int>]] = [:]   // 열림 판단 때 치워 둔 그물 기록 (그 덩어리가 새로 오면 버림) — 지금 그물 전체 모양
    @ObservationIgnored private var viewT: [Int: Float] = [:]       // 실제 문이 열린 뒤(3초 넘어) 곁에서 문 자리를 바라본 시간
    @ObservationIgnored private var hands: HandTrackingProvider?
    @ObservationIgnored private var grip: [Int: (Float, Float, Float, Float)] = [:]   // 문 → (손이 문짝에 가장 가까웠던 거리, 처음 닿은 때, 마지막으로 닿아 있던 때, 닿은 쪽)
    @ObservationIgnored private var coverPeak: [Int: Float] = [:]   // 닫혀 있는 동안 가장 많이 막혔던 비율
    @ObservationIgnored private var leafLookAt: [Int: Float] = [:]   // 닫힌 실제 문짝을 마지막으로 바라본 때
    @ObservationIgnored private var closedAt: [Int: Float] = [:]    // 실제 문이 닫힘으로 바뀐 때
    @ObservationIgnored private var openedAt: [Int: Float] = [:]    // 실제 문이 마지막으로 열린 때 (그 뒤 3초 넘어 온 그물만 닫힘 증거)
    @ObservationIgnored private var justOpened: [Int: Float] = [:]  // 이번에 열린 문 → 그 전에 닫혀 있던 시간 (문 판정이 한 번 읽고 지움)
    @ObservationIgnored private var hitsAt: [Int: [UUID: Float]] = [:]   // 문 → 그물 덩어리마다 막힌 칸을 받은 때
    @ObservationIgnored private var coverFresh: [Int: Float] = [:]  // 열린 뒤 새로 온 그물만으로 문틀 안쪽이 막힌 비율
    @ObservationIgnored private var planeAcrossAt: [Int: Float] = [:]   // 문 면(평면)이 문 자리를 가로막은 것을 마지막으로 본 때
    @ObservationIgnored private var solidDoors: Set<Int> = []       // 지금 막혀 보이는 문 (벽 또는 닫힌 실제 문)
    @ObservationIgnored private var leafDoor: Int?                  // 가장 가까이 보이는 닫힌 실제 문
    @ObservationIgnored private var doorUrgent = false        // 실제 닫힌 문 앞 → 문 자리 그물을 더 자주 다시 봄
    @ObservationIgnored private var doorAnchors: Set<UUID> = []
    @ObservationIgnored private var openProg: [Int: Float] = [:]    // 여는 움직임 진행 (0~1)
    @ObservationIgnored private var animRoom: [Int: Int] = [:]      // 열기 시작한 쪽 방
    @ObservationIgnored private var passed: Set<Int> = []           // 방금 지나온 문: 1m 밖으로 멀어지거나 문 쪽을 볼 때까지 열쇠 문을 안 보임
    @ObservationIgnored private var lastWant: [Int: Float] = [:]    // 열쇠 문이 막 나타났는지 (효과음)
    // 바닥
    @ObservationIgnored private var floorSamples: [UUID: (Float, Int)] = [:]
    @ObservationIgnored private var floorFitY: Float?
    @ObservationIgnored private var floorTimer: Float = 0
    @ObservationIgnored private var fitAt: Float?
    // 현실 창
    @ObservationIgnored private let peek = ModelEntity()
    @ObservationIgnored private var peekAmt: Float = 0
    @ObservationIgnored private var freePeek = false          // 더블탭으로 연 현실 창
    @ObservationIgnored private var peekDismissed: Int?       // 더블탭으로 닫은 닫힌 문 현실 창 (그 문에서 벗어나면 다시 자동)
    // 탭
    @ObservationIgnored private let tapCatcher = Entity()
    @ObservationIgnored private var pendingTap: Float?        // 한 번 탭한 때 — 0.45초 안에 또 오면 더블탭
    @ObservationIgnored private var menuShownAt: Float = -9   // 메뉴판을 띄운 때 (막 뜬 메뉴판 버튼은 잠깐 받지 않음 — menuReady)
    @ObservationIgnored private var lastUITap: Float = -9
    // 안내판
    @ObservationIgnored private var hud: Entity?
    @ObservationIgnored private var hudYaw: Float = 0
    @ObservationIgnored private var hudShow: Float = 0
    @ObservationIgnored private var hudUntil: Float = 0       // 이때까지 보임 (알림 4초, 메뉴판은 마지막으로 만진 뒤 4초)
    @ObservationIgnored private var hudAlert = false          // 안전 알림 (방 밖·너무 빠름) — 계속 보임
    @ObservationIgnored private var hudWasMenu = false
    @ObservationIgnored private var themePanel: Entity?
    // 그림 설명
    @ObservationIgnored private var docentCard: Entity?
    @ObservationIgnored private var bars: [String: Entity] = [:]     // 창마다 아래 옮기기 막대
    @ObservationIgnored private var pinchClosed = [false, false]
    @ObservationIgnored private var pendingSystem = true
    @ObservationIgnored private var lastFwd: SIMD3<Float>?
    @ObservationIgnored private var turnSpeed: Float = 0
    @ObservationIgnored private var pinchOpenAt: [Float] = [-9, -9]
    @ObservationIgnored private var pinchCloseAt: [Float] = [-9, -9]
    /// 손 추적으로 본 '집었다 놓기' 하나하나 (놓은 때, 눈앞에서 빠르게 한 손짓인지, 상태 0 = 아직 / 1 = 시스템 탭과 짝지음 / 2 = 손 탭으로 넣음)
    @ObservationIgnored private var pinchRel: [(t: Float, ok: Bool, state: Int)] = []
    /// 시스템 탭 중 아직 손 추적 놓기와 짝짓지 못한 것 (시스템 탭이 손 추적보다 먼저 온 경우)
    @ObservationIgnored private var sysTaps: [Float] = []
    @ObservationIgnored private var secondHandAt: Float?    // 더블탭인지 시스템 확인을 기다리는 두 번째 손 탭 (손 놓은 때)
    @ObservationIgnored private var hudPinned = false
    // 가구 맞추기 (세계를 걷고 현실 위에 가구 블록을 반투명하게 보이며, 탭·끌기·두 손 집기·판 버튼으로 넣고 빼고 줄이고 키움)
    var furnMode = false
    @ObservationIgnored private var furnHidden = false
    @ObservationIgnored private var furnHiddenList: [Entity] = []
    var furnSel: Int?                                   // 고른 상자 (furnEdits.adds 번호)
    var furnEdits = FurnEdits()
    var furnCanUndo = false
    var furnIsNew = false                               // 편집 중인 가구가 이번에 새로 놓은 것
    var furnConfirm: String?                            // 한 번 더 확인 중 ("delete" 지우기 / "reset" 처음 스캔대로)
    @ObservationIgnored private var furnBefore: FurnEdits?          // 편집을 시작하기 전 (취소하면 이리로)
    var furnSelBox: FurnBox? { furnSel.flatMap { $0 >= 0 && $0 < furnEdits.adds.count ? furnEdits.adds[$0] : nil } }
    @ObservationIgnored private var furnUndo: [FurnEdits] = []
    @ObservationIgnored private var furnPanel: Entity?
    @ObservationIgnored private let furnRoot = Entity()              // 저장 좌표 (공간 뿌리와 같은 자리 — 세계를 가린 동안에도 보임)
    @ObservationIgnored private var furnPreview: ModelEntity?
    @ObservationIgnored private var furnBoxes: [ModelEntity] = []
    @ObservationIgnored private let furnGuide = Entity()             // 고치는 상자 둘레 거리 표시 (저장 좌표)
    @ObservationIgnored private var guideBox: FurnBox?               // 거리 표시를 마지막으로 계산한 상자
    @ObservationIgnored private var guideAt: Float = -9
    @ObservationIgnored private var guideText: [String: MeshResource] = [:]
    @ObservationIgnored private var furnGrab: SIMD2<Float>?           // 끌기 시작할 때 상자 가운데 - 손 자리 (평면 좌표)
    @ObservationIgnored private var furnScale0: FurnBox?
    @ObservationIgnored private var furnApplyAt: Float?               // 끄는 동안 블록·미리보기 다시 그릴 때 (0.15초마다)
    @ObservationIgnored private var tip: String?                     // 잠깐 알려 줄 사용법 (처음 한 번)
    @ObservationIgnored private var tipUntil: Float = 0
    @ObservationIgnored private var seenRooms: Set<Int> = []
    @ObservationIgnored private var tipsShown = Set<String>()              // 안내판·테마 판을 옮겨 두었으면 그 자리에 둠 (닫힐 때까지)
    @ObservationIgnored private var toyTrail: [(Float, SIMD3<Float>)] = []   // 장난감을 끄는 동안의 자리 (던지는 빠르기)
    @ObservationIgnored private var docentShow: Float = 0
    @ObservationIgnored private var themeQuiet: Float = 0     // 테마를 바꾼 직후엔 알림판을 띄우지 않음
    @ObservationIgnored private var badgeT: Float = 0
    @ObservationIgnored private var decorT: Float = 0
    @ObservationIgnored private let ar = ARKitSession()
    @ObservationIgnored private var world: WorldTrackingProvider?
    @ObservationIgnored private var data: SpaceData?
    @ObservationIgnored private var layout: Layout?
    @ObservationIgnored private var info: SkinInfo?
    @ObservationIgnored private var worlds: [Int: RoomWorld] = [:]
    @ObservationIgnored private var neighbors: [Int: Set<Int>] = [:]
    /// 같은 세계 무리: 방 번호 → 무리 방 번호들(작은 순, 첫째가 대표). 문(한 방 안 문 제외)으로 이어진 같은 테마 방끼리 —
    /// 대표 방이 하늘 세계를 무리 전체 둘레에 하나만 만들고 나머지는 함께 씀 (같은 테마 옆방이 한 공간으로 이어져 보이게)
    @ObservationIgnored private var groups: [Int: [Int]] = [:]
    @ObservationIgnored private var themeTask: Task<Void, Never>?
    @ObservationIgnored private var saved: [String: AnchorRec] = [:]
    @ObservationIgnored private var allIds: Set<String> = []
    @ObservationIgnored private var poses: [String: simd_float4x4] = [:]
    @ObservationIgnored private var fit: Fit?
    @ObservationIgnored private var fitTarget: Fit?
    @ObservationIgnored private var skinFit: Fit?
    @ObservationIgnored private var meshes: [UUID: MeshAnchor] = [:]
    @ObservationIgnored private var builtAt: [UUID: Double] = [:]
    @ObservationIgnored private var dirty: Set<UUID> = []
    @ObservationIgnored private var building: Set<UUID> = []
    @ObservationIgnored private var mats: [Int: RealityKit.Material] = [:]
    @ObservationIgnored private var head = SIMD3<Float>(0, 1.5, 0)
    @ObservationIgnored private var fwd = SIMD3<Float>(0, 0, -1)
    @ObservationIgnored private var headUp = SIMD3<Float>(0, 1, 0)
    @ObservationIgnored private var lastHead: SIMD3<Float>?
    @ObservationIgnored private var lastHeadT: Float?
    @ObservationIgnored private var fastT: Float = 0             // 빠르게 걸은 시간 (잠깐 튄 값으로 현실을 보이지 않게)
    @ObservationIgnored private var speed: Float = 0
    @ObservationIgnored private var current = 0
    @ObservationIgnored private var candidate = 0
    @ObservationIgnored private var candidateT: Float = 0
    @ObservationIgnored private var outsideT: Float = 0
    @ObservationIgnored private var fade: Float = 0
    @ObservationIgnored private var appliedFade: Float = -1
    @ObservationIgnored private var t: Float = 0
    @ObservationIgnored private var buildTimer: Float = 0
    @ObservationIgnored private var nextEvent: Float = 6
    @ObservationIgnored private var nextThunder: Float = 8
    @ObservationIgnored private var ended = false
    @ObservationIgnored private var intro: ScanIntro?
    @ObservationIgnored private var introDone = false
    @ObservationIgnored private var aligning = false
    @ObservationIgnored private var nextAlign: Float = 8
    @ObservationIgnored private var alignMap: Align.Map?
    @ObservationIgnored private let player = AmbientPlayer()
    @ObservationIgnored private var hanging: Set<Int> = []
    // 불멍 (캠핑장에서 앉으면)
    @ObservationIgnored private var fire: Campfire?
    @ObservationIgnored private var standH: Float = 0         // 서 있을 때 머리 높이 (바닥에서)
    @ObservationIgnored private var sitT: Float = 0
    @ObservationIgnored private var standT: Float = 0
    @ObservationIgnored private var seated = false
    // 시골 밤하늘 별자리 · 카페 음악·테이블
    @ObservationIgnored private var stars: SkyStars?
    @ObservationIgnored private var starCard: Entity?
    @ObservationIgnored private let music = CafeMusic()
    @ObservationIgnored private let waterSound = WaterSound()
    @ObservationIgnored private var cafeSets: [Int: (String, CafeTables)] = [:]   // 카페 방마다 차림 (그 방 테마가 바뀔 때만 새로)
    // 집 고양이
    @ObservationIgnored private var cat: HomeCat?
    @ObservationIgnored private var dog: HomeDog?
    @ObservationIgnored private var dogLook: LookMode?
    @ObservationIgnored private var catLook: LookMode?
    @ObservationIgnored private var stillT: Float = 0
    @ObservationIgnored private var handPts: [SIMD3<Float>] = []        // 손바닥 가운데 (저장 좌표)

    init(spaceId: String) {
        self.spaceId = spaceId
    }

    func start() async {
        guard let d = SpaceStore.load(spaceId), !d.rec.rooms.isEmpty, !d.shapes.isEmpty else {
            message = "공간을 불러오지 못했어요. 메인 창에서 방 구성을 확인해 주세요."
            return
        }
        data = d
        unified = d.rec.isUnified
        let L = Layout(d)
        layout = L
        info = SkinInfo(d, L)
        neighbors = L.neighbors()
        groups = Self.makeGroups(d, L)
        for a in d.rec.anchors { saved[a.a] = a }
        allIds = SpaceStore.allAnchorIds()
        root.addChild(spaceRoot)
        root.addChild(player.root)
        spaceRoot.addChild(music.root)
        spaceRoot.addChild(waterSound.root)
        let v = VoxelWorld(L)
        v.material = { [unowned self] r, s in self.material(r, s) }
        v.sun = { [unowned self] r in self.info?.sun[min(255, max(0, r))] ?? SIMD3<Float>(0, 1, 0) }
        v.tile = { [unowned self] r in self.info?.propTile[min(255, max(0, r))] ?? 1 }
        v.lines = { [unowned self] r in self.data?.rec.room(r)?.lookMode == .line }
        v.fallbackRoom = d.rec.rooms.first?.id ?? 1
        spaceRoot.addChild(v.root)
        vox = v
        furnEdits = FurnStore.load(spaceId)                // 손으로 맞춘 가구 (처음부터 적용)
        v.setEdits(furnEdits)
        Sfx.preload()
        // 현실 창: 가려 주는 재질(OcclusionMaterial)은 그 뒤의 가상 물체를 지워 현실이 보이게 함
        peek.model = ModelComponent(mesh: .generateCylinder(height: 0.002, radius: 1), materials: [OcclusionMaterial()])
        var ring = Geo()
        let segs = 64
        for k in 0..<segs {
            let a0 = Float(k) / Float(segs) * 2 * .pi, a1 = Float(k + 1) / Float(segs) * 2 * .pi
            let i0 = SIMD3<Float>(cos(a0), 0.004, sin(a0)), i1 = SIMD3<Float>(cos(a1), 0.004, sin(a1))
            ring.quad(i0, i0 * SIMD3<Float>(1.1, 1, 1.1), i1 * SIMD3<Float>(1.1, 1, 1.1), i1, .zero, .zero, .zero, .zero)
        }
        if let r = ring.entity("peekRing", RoomWorld.gold(rough: 0.25, glow: 1.4)) { peek.addChild(r) }
        peek.isEnabled = false
        root.addChild(peek)
        spaceRoot.setOpacity(0)

        // 탭 받는 상자: 머리를 둘러싼 상자의 여섯 면(얇은 판) — 어디를 보고 집어도 탭이 들어옴 (열쇠·안내판이 더 가까우면 그쪽이 먼저)
        let wallT: Float = 0.05, half: Float = 4
        var shapes: [ShapeResource] = []
        for ax in 0..<3 {
            for sgn: Float in [-1, 1] {
                var size = SIMD3<Float>(repeating: half * 2)
                size[ax] = wallT
                var off = SIMD3<Float>(repeating: 0)
                off[ax] = sgn * half
                shapes.append(ShapeResource.generateBox(size: size).offsetBy(translation: off))
            }
        }
        tapCatcher.name = "tap-catcher"
        tapCatcher.components.set(CollisionComponent(shapes: shapes))
        tapCatcher.components.set(InputTargetComponent())
        root.addChild(tapCatcher)

        let auth = await ar.requestAuthorization(for: [.worldSensing, .handTracking])
        guard auth[.worldSensing] == .allowed else {
            message = "주변 공간 알아보기를 허락해야 다른 세계를 입힐 수 있어요. 설정 > 개인정보 보호 및 보안에서 켜 주세요."
            return
        }
        let w = WorldTrackingProvider()
        let m = SceneReconstructionProvider(modes: [.classification])
        world = w
        var providers: [any DataProvider] = [w, m]
        // 세운 평면(문으로 알아본 면): 그물보다 빨리 바뀌어 실제 문이 열리고 닫히는 걸 바로 알 수 있음.
        // 누운 평면 중 '탁자'로 알아본 면: 카페 차림을 정확한 높이에 올림
        let planes = PlaneDetectionProvider.isSupported ? PlaneDetectionProvider(alignments: [.vertical]) : nil
        if let planes { providers.append(planes) }
        // 손: 닫힌 문짝을 잡고 당기거나 미는 순간을 바로 알아챔 (그물·평면은 문이 다 열리고도 몇 초 늦음)
        if HandTrackingProvider.isSupported && auth[.handTracking] == .allowed {
            let hp = HandTrackingProvider()
            hands = hp
            providers.append(hp)
        }
        do { try await ar.run(providers) } catch {
            message = "공간 인식을 시작하지 못했어요. 나갔다가 다시 들어와 주세요."
            return
        }
        Task { await self.watchMeshes(m) }
        if let planes { Task { await self.watchPlanes(planes) } }
        Task { await self.watchWorld(w) }
        // 가구 블록: 지난 탐험에서 알아낸 것(없으면 스캔 그물)을 다른 스레드에서 읽어 처음부터 보이게
        let sid = spaceId
        guard let I = info else { return }
        seedTask = Task {
            let res = await Task.detached(priority: .userInitiated) { () -> [Int64: UInt8] in
                if let learned = VoxStore.load(sid) { return learned }            // 지난 탐험에서 확인한 가구
                guard let m = SpaceStore.loadMesh(sid) else { return [:] }       // 처음: 스캔 그물에서
                let r = Skin.build(Skin.weld(m.0, m.1), I, Fit(), saved: true)
                var out: [Int64: UInt8] = [:]
                for (k, top) in r.cols { out[k] = UInt8(min(21, max(2, Int((top / Vox.size).rounded(.up))))) }
                return out
            }.value
            guard !ended else { return }
            // 문이 쓸고 지나가는 자리의 기둥은 버림 (예전에 저장된 반쯤 열린 문짝 등)
            var clean: [Int64: UInt8] = [:]
            for (k, h) in res {
                let half: Int64 = 1 << 20
                let mask: Int64 = (1 << 21) - 1
                let ku: Int64 = (k >> 21) & mask
                let kv: Int64 = k & mask
                let pu: Float = (Float(ku - half) + 0.5) * Vox.size
                let pv: Float = (Float(kv - half) + 0.5) * Vox.size
                if !Skin.inSwing(L, SIMD2<Float>(pu, pv)) { clean[k] = h }
            }
            vox?.seed(clean)
        }
        // 포켓 갤러리 보관함 그림 (전시관이 있으면 처음 받는 그림을 최대 6초 기다림, 없으면 받아만 둠)
        let hasGallery = d.rec.rooms.contains { $0.place == "gallery" }
        RoomWorld.pgArt = await PGLibrary.prepare(wait: hasGallery ? 6 : 0)
        // 공간을 알아보는 동안 방 세계를 하나씩 미리 만듦 → 문턱을 넘을 때 기다리지 않음
        await buildWorlds()
    }

    /// 아직 안 만든 방 중 '지금 있는 방 → 이웃 방 → 나머지' 순서로 하나씩
    private func buildWorlds() async {
        await seedTask?.value                       // 가구 자리를 알아야 벽난로·선반·그림을 가구 없는 곳에 둠
        while !ended {
            guard let d = data, let L = layout else { return }
            let todo = d.rec.rooms.filter { worlds[$0.id] == nil }
            guard !todo.isEmpty else {
                // 가구 블록까지 다 그린 뒤에 보여 줌 (들어서자마자 가구가 있게)
                await seedTask?.value
                vox?.restyle()
                await vox?.rebuildAll()
                ready = true
                return
            }
            let near = neighbors[current] ?? []
            let next = todo.first { $0.id == current } ?? todo.first { near.contains($0.id) } ?? todo[0]
            await Tex.preload(RoomWorld.textures(next), look: next.lookMode)
            guard !ended, worlds[next.id] == nil, let d2 = data, let r = d2.rec.room(next.id) else { continue }
            let nw = addWorld(d2, r, L)
            await hangGallery(nw)                                       // 전시관이면 그림까지 걸고 다음 방으로 (보일 때 이미 걸려 있게)
            refreshActive()
            try? await Task.sleep(for: .milliseconds(30))
        }
    }

    /// 같은 세계 무리 나누기 (문으로 이어진 같은 테마 방끼리)
    static func makeGroups(_ d: SpaceData, _ L: Layout) -> [Int: [Int]] {
        var parent: [Int: Int] = [:]
        for r in d.rec.rooms { parent[r.id] = r.id }
        func find(_ x: Int) -> Int {
            var x = x
            while let p = parent[x], p != x { x = p }
            return x
        }
        for ds in L.doors where !ds.single {
            guard let a = d.rec.room(ds.roomA), let b = d.rec.room(ds.roomB), sameTheme(a, b) else { continue }
            let ra = find(a.id), rb = find(b.id)
            if ra != rb { parent[max(ra, rb)] = min(ra, rb) }
        }
        var members: [Int: [Int]] = [:]
        for r in d.rec.rooms { members[find(r.id), default: []].append(r.id) }
        var out: [Int: [Int]] = [:]
        for (_, m) in members {
            let sorted = m.sorted()
            for id in sorted { out[id] = sorted }
        }
        return out
    }

    /// 방 세계 만들기. 같은 세계 무리의 다른 방이면 대표 방 세계를 먼저 (없거나 무리가 바뀌었으면 새로) 만들고 그 세계를 함께 씀
    @discardableResult
    private func addWorld(_ d: SpaceData, _ r: RoomRec, _ L: Layout) -> RoomWorld {
        let g = groups[r.id] ?? [r.id]
        var host: RoomWorld? = nil
        if let lead = g.first, lead != r.id, let lr = d.rec.room(lead) {
            if let lw = worlds[lead], lw.ownsWorld, lw.groupIds == g {
                host = lw
            } else {
                removeWorld(lead)
                let lw = addWorld(d, lr, L)
                Task { await hangGallery(lw) }
                host = lw
            }
        }
        let w = RoomWorld(d, r, layout: L, blocked: vox?.blockedCells(minH: 0.2) ?? [], tall: vox?.blockedCells(minH: 1.0) ?? [], group: g, host: host)
        if w.ownsWorld { spaceRoot.addChild(w.world) }
        spaceRoot.addChild(w.local)
        spaceRoot.addChild(w.doorsRoot)
        w.local.isEnabled = roomShown(r.id)
        worlds[r.id] = w
        vox?.restyle()
        return w
    }

    /// 무리·테마가 지금과 어긋난 방 세계 (테마를 바꾸다 그만뒀거나, 빌려 쓰는 대표 방 세계가 새로 바뀐 방)
    private func staleRooms() -> Set<Int> {
        guard let d = data else { return [] }
        var out = Set<Int>()
        for (id, w) in worlds {
            let g = groups[id] ?? [id]
            if w.groupIds != g { out.insert(id); continue }
            if let rr = d.rec.room(id), !Self.sameTheme(rr, w.room) { out.insert(id); continue }
            if let lead = g.first, lead != id, w.host !== worlds[lead] { out.insert(id) }
        }
        return out
    }

    /// 방 세계 치우기 (하늘 세계는 직접 만든 방만 치움 — 무리의 다른 방은 대표 방 것을 빌려 씀)
    private func removeWorld(_ id: Int) {
        guard let old = worlds[id] else { return }
        if old.ownsWorld { old.world.removeFromParent() }
        old.local.removeFromParent()
        old.doorsRoot.removeFromParent()
        worlds[id] = nil
    }

    // MARK: 전시관 그림
    /// 그림 자리: 벽 앞(그림 높이)에 보이는 가구 블록이 없는 평평한 벽마다.
    /// 그림: 포켓 갤러리 보관함에서 1점(무작위) + 나머지는 앱에 담긴 명화(무작위, 겹치지 않게).
    /// 그림은 다른 스레드에서 읽고 다 읽은 뒤 한 번에 바꿔 걺. 탐험 시작 때와, 그 방에서 나갈 때마다 다시 골라 둠 → 들어갈 때마다 새 그림
    private func hangGallery(_ w: RoomWorld) async {
        guard w.hasPaintings, !hanging.contains(w.room.id) else { return }
        hanging.insert(w.room.id)
        defer { hanging.remove(w.room.id) }
        await seedTask?.value                                        // 가구 블록을 알아야 자리를 고름
        guard !ended, worlds[w.room.id] === w else { return }
        w.planSlots(blocked: vox?.blockedCells(minH: 1.0) ?? [])
        let n = w.paintSlots.count
        guard n > 0 else { w.hang([]); return }
        var picks: [ArtPick] = []
        let bundled = RoomWorld.artNames.shuffled().compactMap { name -> ArtPick? in
            guard let u = Bundle.main.url(forResource: name, withExtension: "jpg", subdirectory: "art") else { return nil }
            return ArtIndex.pick(name, u)
        }
        if let mine = RoomWorld.pgArt.randomElement() { picks.append(PGLibrary.pick(mine)) }
        picks += bundled.prefix(max(0, n - picks.count))
        if picks.count < n {                                         // 명화가 없을 때만 보관함으로 채움
            picks += RoomWorld.pgArt.shuffled().prefix(n - picks.count).map { PGLibrary.pick($0) }
        }
        picks.shuffle()
        var arts: [(ArtPick, TextureResource, [SIMD3<Float>])] = []
        for p in picks {
            let got = await Task.detached(priority: .utility) { () -> (CGImage, [SIMD3<Float>])? in
                guard let cg = UIImage(contentsOfFile: p.url.path)?.cgImage else { return nil }
                return (cg, RoomWorld.palette(cg))
            }.value
            guard let got, !ended else { continue }
            if let tx = try? await TextureResource(image: got.0, withName: nil, options: .init(semantic: .color)) { arts.append((p, tx, got.1)) }
        }
        guard !ended, worlds[w.room.id] === w else { return }
        w.hang(arts)
        if w.room.id == current { Docent.shared.prefetch(arts.map { $0.0 }) }     // 지금 방에 걸린 그림 중 해설이 없는 것을 먼저 받아 저장
    }

    /// 비·눈·반딧불은 지금 방과 이웃 방만 (문턱을 넘을 때 이미 내리고 있게)
    /// 지금 방이 속한 같은 세계 무리 (혼자면 지금 방)
    private var currentGroup: Set<Int> { Set(groups[current] ?? [current]) }

    /// 방 안(local: 바닥·가구 꾸밈·들보·포털 면 등)을 그리는 방: 지금 방(무리)과, 그 방들에서 '열린 문'(뚫린 통로·열쇠로 연 문)으로
    /// 바로 이어진 방(과 그 무리)만. 나머지 방의 방 안은 그리지 않음.
    /// 포털 면(벽)은 그 뒤의 다른 방 물건을 가리지 못해, 예전엔 벽 너머 옆방의 들보·꾸밈이 벽을 뚫고 지금 방 풍경 위에 보였음
    /// (옆방 테마를 바꿔야 사라짐). 닫힌 문(벽·열쇠 문·실제 문짝) 너머 방은 어차피 보이지 않으므로 끔
    @ObservationIgnored private var openDoorSet: Set<Int> = []
    private func roomShown(_ id: Int) -> Bool { shownRooms().contains(id) }
    /// 몸(목 뒤)이 있는 방·몸이 서 있는 문 자리 (방 판정은 0.5초 늦게 바뀌므로 그 사이에도 몸이 있는 곳은 그려야 함)
    @ObservationIgnored private var bodyRoom = 0
    @ObservationIgnored private var bodyDoors: [Int] = []
    @ObservationIgnored private var bodyNearDoors: [Int] = []
    /// 방마다 그만 그려도 되는 때 — 조건에서 빠진 뒤 0.8초 더 켜 둠 (문턱에서 켜고 끄기를 오가며 한 프레임씩 비지 않게)
    @ObservationIgnored private var shownUntil: [Int: Float] = [:]
    private func shownRooms() -> Set<Int> {
        var vis = currentGroup
        guard let L = layout else { return vis }
        // 문턱을 넘는 동안: 지금 방(판정)은 아직 예전 방인데 문은 '건너감'으로 닫혀(벽) 몸이 있는 새 방이 꺼져 현실이 비쳤음 →
        // 몸이 있는 방과 몸이 서 있는 문 양쪽 방은 늘 그림
        if bodyRoom != 0 { vis.insert(bodyRoom); vis.formUnion(groups[bodyRoom] ?? []) }
        for i in bodyDoors where i < L.doors.count {
            for r in [L.doors[i].roomA, L.doors[i].roomB] { vis.insert(r); vis.formUnion(groups[r] ?? []) }
        }
        let base = vis
        for i in openDoorSet where i < L.doors.count {
            let ds = L.doors[i]
            for (from, to) in [(ds.roomA, ds.roomB), (ds.roomB, ds.roomA)] where base.contains(from) && !vis.contains(to) {
                vis.insert(to)
                vis.formUnion(groups[to] ?? [])
            }
        }
        return vis
    }
    private func updateRoomVisibility() {
        let now = shownRooms()
        for id in now { shownUntil[id] = t + 0.8 }
        let vis = Set(shownUntil.filter { $0.value > t }.keys)
        // 내가 있는 방(지금 방·몸이 있는 방·몸이 선 문 양쪽 방): 다른 세계 방들이 이 방과 맞댄 벽 뒤에 세운 울타리는 이 방 자리에 있으므로 끔
        // (열린 열쇠 문 너머 옆방 포털에 내 곁의 그 울타리가 크게·엉뚱한 각도로 비쳤음 — RoomWorld.barrierToward)
        var here: Set<Int> = [current, bodyRoom]
        // 문간 35cm 안이면 그 문 양쪽 방 모두 (문간을 지나는 동안 양쪽 울타리 조각이 눈 바로 곁에 있음)
        if let L = layout { for i in bodyNearDoors where i < L.doors.count { here.insert(L.doors[i].roomA); here.insert(L.doors[i].roomB) } }
        for (id, w) in worlds {
            let on = vis.contains(id)
            if w.local.isEnabled != on { w.local.isEnabled = on }
            w.hideBarriers(near: here)
        }
        for (id, c) in cafeSets {
            let on = vis.contains(id) && !furnHidden                 // 가구 맞추기 중엔 끔 (furnHideScene)
            if c.1.root.isEnabled != on { c.1.root.isEnabled = on }
        }
    }

    private func refreshActive() {
        // 같은 세계 무리는 한 공간: 무리 전체가 '지금 방'(방 안 눈·비도 함께), 무리 방들의 이웃이 '이웃 방'
        let cur = currentGroup
        var on = cur
        for id in cur { on.formUnion(neighbors[id] ?? []) }
        var skyOn = on
        for id in on { if let lead = groups[id]?.first { skyOn.insert(lead) } }      // 하늘 세계 쪽 눈·비는 그 세계를 만든 대표 방에 있음
        for (id, w) in worlds {
            // 방 안 눈·비·바람·반딧불은 지금 방만 (같은 테마 방이 모두 켜지면 방 수만큼 입자가 늘어 크게 느려졌음)
            // 하늘 쪽 눈·비는 지금 방이 보는 세계(무리 대표 방)만 다 내리고, 이웃 세계는 1/4 (기준서 4·7)
            w.setActive(sky: skyOn.contains(id), room: id == current, full: id == (groups[current]?.first ?? current))
            w.setPortalTier(cur.contains(id) ? 2 : (on.contains(id) ? 1 : 0))      // 포털 면은 지금 방 → 이웃 방 → 먼 방 순으로 나중에 그림
        }
    }

    func stop() {
        fire?.remove(); fire = nil
        music.remove()
        waterSound.remove()
        for (_, c) in cafeSets { c.1.remove() }
        cafeSets.removeAll()
        cat?.remove(); cat = nil
        dog?.remove(); dog = nil
        updateSub?.cancel()
        ar.stop()
        player.stopAll()
        saveVox()
        if furnMode { FurnStore.save(spaceId, furnEdits) }
        if !ended { ended = true; AppModel.shared.disappeared() }
    }

    func exit() {
        guard !ended else { return }
        saveVox()
        ended = true
        fire?.remove(); fire = nil
        cat?.remove(); cat = nil
        dog?.remove(); dog = nil
        music.remove()
        waterSound.remove()
        for (_, c) in cafeSets { c.1.remove() }
        cafeSets.removeAll()
        player.stopAll()
        AppModel.shared.finish()
    }

    /// 알아낸 가구 블록 저장 (다음 탐험에서 처음부터 보이게)
    private func saveVox() {
        guard let v = vox, v.changed, ready else { return }
        let list = v.saveList(), id = spaceId
        v.markSaved()
        Task.detached(priority: .utility) { VoxStore.save(id, list) }
    }

    func attachHud(_ e: Entity) {
        hud = e
        e.isEnabled = false
        root.addChild(e)
        makeBar("hud")
    }

    func attachTheme(_ e: Entity) {
        themePanel = e
        e.isEnabled = false
        root.addChild(e)
        makeBar("theme")
    }

    func attachDocent(_ e: Entity) {
        docentCard = e
        e.isEnabled = false
        root.addChild(e)
        makeBar("docent")
    }

    /// 창 아래 옮기기 막대 (visionOS 창 막대처럼): 잡고 끌면 창이 따라오고 늘 나를 향함
    private func makeBar(_ panel: String) {
        GrabTag.registerComponent()
        ToyTag.registerComponent()
        let bar = ModelEntity(mesh: .generateBox(width: 0.13, height: 0.012, depth: 0.012, cornerRadius: 0.006),
                              materials: [UnlitMaterial(color: UIColor(white: 0.92, alpha: 1))])
        bar.name = panel + "-grab"
        bar.components.set(GrabTag(panel: panel))
        bar.components.set(InputTargetComponent())
        bar.components.set(CollisionComponent(shapes: [.generateBox(size: [0.26, 0.08, 0.08])]))
        bar.components.set(HoverEffectComponent())
        bar.isEnabled = false
        root.addChild(bar)
        bars[panel] = bar
    }

    private func panel(_ name: String) -> Entity? {
        switch name {
        case "hud": return hud
        case "theme": return themePanel
        case "docent": return docentCard
        case "stars": return starCard
        case "furn": return furnPanel
        default: return nil
        }
    }

    /// 막대를 끌어 창을 옮김 (창은 늘 나를 향함). 안내판·테마 판은 옮긴 자리에 머묾
    func dragPanel(_ e: Entity, to p: SIMD3<Float>) {
        lastUITap = t
        guard let tag = e.components[GrabTag.self], let card = panel(tag.panel), card.isEnabled else { return }
        let b = card.visualBounds(relativeTo: card)
        let below = b.min.y - 0.035
        card.position = p - card.orientation.act(SIMD3<Float>(b.center.x, below, 0) * card.scale)
        faceDocent(card)
        if tag.panel == "hud" || tag.panel == "theme" {
            hudPinned = true
            hudUntil = max(hudUntil, t + 6)
            if let h = hud { h.position = card.position; h.orientation = card.orientation }
        }
    }

    /// 창마다 막대를 창 아래 가운데에 붙임 (창이 보일 때만)
    private func syncBars() {
        for (name, bar) in bars {
            guard let card = panel(name) else { continue }
            let on = card.isEnabled
            if bar.isEnabled != on { bar.isEnabled = on }
            guard on else { continue }
            let b = card.visualBounds(relativeTo: card)
            bar.position = card.convert(position: SIMD3<Float>(b.center.x, b.min.y - 0.035, 0), to: root)
            bar.orientation = card.orientation
            bar.scale = SIMD3<Float>(repeating: max(0.5, card.scale.x))
            if let o = card.components[OpacityComponent.self] { bar.components.set(o) } else { bar.components.remove(OpacityComponent.self) }
        }
    }

    // MARK: 장난감 집어 던지기
    func dragToy(_ e: Entity, to p: SIMD3<Float>) {
        lastUITap = t
        guard let f = fit else { return }
        let sp = f.toSaved(p)
        toyTrail.append((t, sp))
        if toyTrail.count > 12 { toyTrail.removeFirst() }
        if e.name == "catball" { cat?.holdBall(at: sp) } else if e.name == "dogstick" { dog?.holdStick(at: sp) }
    }

    func dropToy(_ e: Entity) {
        lastUITap = t
        // 놓기 직전 0.12초 동안 움직인 빠르기로 던짐
        var v = SIMD3<Float>(0, 0, 0)
        if let last = toyTrail.last, let first = toyTrail.last(where: { last.0 - $0.0 >= 0.1 }) ?? toyTrail.first, last.0 - first.0 > 0.01 {
            v = (last.1 - first.1) / (last.0 - first.0)
        }
        toyTrail.removeAll()
        if e.name == "catball" { cat?.releaseBall(vel: v) } else if e.name == "dogstick" { dog?.releaseStick(vel: v) }
    }

    private func faceDocent(_ card: Entity) {
        let to = head - card.position
        let yaw = atan2(to.x, to.z)
        let pitch = atan2(to.y, max(0.05, simd_length(SIMD2<Float>(to.x, to.z))))
        card.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0]) * simd_quatf(angle: -pitch, axis: [1, 0, 0])
    }

    // MARK: 테마 바꾸기 (지금 방)
    func setTheme(place: String, weather: String, time: String, look: String) {
        lastUITap = t
        hudUntil = t + 4
        guard var d = data, let L = layout, current != 0 else { return }
        let id = current
        let oldGroups = groups
        d.setTheme(id, place: place, weather: weather, time: time, look: look)       // '모든 방 같게'면 모든 방이 바뀜
        data = d
        unified = d.rec.isUnified
        try? SpaceStore.save(d)
        guard let r = d.rec.room(id) else { return }
        room = r
        info = SkinInfo(d, L)
        player.enter(r, force: true)
        themeQuiet = t + 3
        let targets = d.rec.isUnified ? d.rec.rooms.map(\.id) : [id]
        // 같은 세계 무리가 바뀜: 바뀐 방의 예전 무리·새 무리 방도 모두 다시 만듦 (대표 방 먼저 — 나머지가 그 세계를 함께 씀)
        groups = Self.makeGroups(d, L)
        var affected = Set(targets)
        for tg in targets { affected.formUnion(oldGroups[tg] ?? []); affected.formUnion(groups[tg] ?? []) }
        // 벽 하나를 사이에 둔 옆방(45cm 안): 두 방이 같은 테마인지가 이번에 바뀌었으면 그 옆방도 다시 만듦 (그 벽의 창이 생기거나 없어짐)
        for ws in L.walls {
            for other in [ws.nearRoom, ws.behind] where other > 0 && (targets.contains(ws.room) || targets.contains(other)) {
                guard let a0 = worlds[ws.room]?.room, let b0 = worlds[other]?.room,
                      let a1 = d.rec.room(ws.room), let b1 = d.rec.room(other) else { continue }
                if Self.sameTheme(a0, b0) != Self.sameTheme(a1, b1) { affected.insert(ws.room); affected.insert(other) }
            }
        }
        let affectedRooms = affected
        closeDocent()
        fire?.remove(); fire = nil                                // 테마가 바뀌면 불도 새로 (다시 앉아 있으면 그 테마에 맞게 피어남)
        seated = false; sitT = 0
        // 새 그림을 미리 읽은 뒤 바꿔 끼움 (지금 방 먼저, 읽는 동안은 예전 세계가 그대로 보임)
        themeTask?.cancel()
        let snapshot = d
        themeProg = 0.02
        themeTask = Task {
            await Tex.preload(RoomWorld.textures(r), look: r.lookMode)
            themeProg = 0.45
            // 대표 방 먼저, 그다음 지금 방, 나머지 (앞서 바꾸다 그만둔 방·무리가 어긋난 방도 함께)
            let order = affectedRooms.union(staleRooms()).sorted { a, b in
                let la = self.groups[a]?.first == a, lb = self.groups[b]?.first == b
                if la != lb { return la }
                if (a == id) != (b == id) { return a == id }
                return a < b
            }
            defer { themeProg = nil }
            var done = Set<Int>()
            for (k, rid) in order.enumerated() {
                themeProg = 0.45 + 0.55 * Float(k) / Float(max(1, order.count))
                guard !Task.isCancelled, !ended else { return }
                let dd = data ?? snapshot
                guard let rr = dd.rec.room(rid) else { continue }
                // 대표 방을 새로 만들며 함께 만든 방(addWorld가 대표 방을 먼저 만듦)은 건너뜀
                if done.contains(rid), let w = worlds[rid], w.groupIds == (groups[rid] ?? [rid]) { continue }
                removeWorld(rid)
                let nw = addWorld(dd, rr, L)
                done.insert(rid)
                if let h = nw.host { done.insert(h.room.id) }
                Task { await hangGallery(nw) }
                refreshActive()
                await Task.yield()
            }
            // 바뀐 뒤 어느 방도 쓰지 않는 예전 테마 그림은 놓아 줌 (메모리)
            if let dd = data {
                var keep = Set<String>()
                for rr in dd.rec.rooms { for (n, f) in RoomWorld.textures(rr) { keep.insert(f + "/" + n) } }
                Tex.release(keeping: keep)
            }
        }
    }

    func toggleTheme() {
        lastUITap = t
        if themeOpen { closeHud() } else { themeOpen = true }       // 테마를 닫으면 메뉴판도 닫음 (할 일을 마쳤으니)
    }

    /// 안내판 닫기 (X 버튼·테마 닫기)
    func closeHud() {
        lastUITap = t
        hudMenu = false
        themeOpen = false
        hudUntil = 0
    }

    // MARK: 비전프로가 알려 주는 것
    private func watchWorld(_ w: WorldTrackingProvider) async {
        for await u in w.anchorUpdates {
            let a = u.anchor
            let key = a.id.uuidString
            switch u.event {
            case .removed:
                poses[key] = nil
            default:
                // 잠깐 놓친(추적 안 됨) 앵커도 마지막 위치를 그대로 씀: 놓칠 때마다 다른 앵커들로 다시 맞추면 공간이 튀어 깜빡임
                if saved[key] != nil {
                    if a.isTracked { poses[key] = a.originFromAnchorTransform; updateFit() }
                } else if !allIds.contains(key) {
                    try? await w.removeAnchor(forID: a.id)          // 지운 공간의 앵커 정리
                }
            }
        }
    }

    private func watchMeshes(_ p: SceneReconstructionProvider) async {
        for await u in p.anchorUpdates {
            let a = u.anchor
            switch u.event {
            case .removed:
                meshes[a.id] = nil
                dirty.remove(a.id)
                setDoorHits(a.id, [:], touched: [])
                floorSamples[a.id] = nil
                doorAnchors.remove(a.id)
            default:
                meshes[a.id] = a
                dirty.insert(a.id)
            }
        }
    }

    /// 문으로 알아본 세운 평면: 문 자리를 가로막고 서 있으면 '닫힘', 그 면이 돌아가거나(열리며 젖혀짐) 자리를 벗어나거나 사라지면 바로 '열림'.
    /// 문은 천천히 열리지만 평면은 그물보다 훨씬 빨리 따라오므로, 문짝이 조금만 젖혀져도 알아챔.
    /// 평면으로 열림을 알면 6초 동안은 늦게 오는 그물(아직 예전 닫힌 문짝이 남은)로 다시 닫지 않음
    private func watchPlanes(_ p: PlaneDetectionProvider) async {
        for await u in p.anchorUpdates {
            let a = u.anchor
            guard a.classification == .door || doorPlanes[a.id] != nil else { continue }
            guard let f = fit, let L = layout else { continue }
            let was = doorPlanes[a.id]
            var now: (Int, Bool)? = nil
            if u.event != .removed && a.classification == .door {
                let m = a.originFromAnchorTransform * a.geometry.extent.anchorFromExtentTransform
                let c = f.toSaved(simd_make_float3(m.columns.3))
                // 세운 평면의 법선 = 평면 안의 세로축이 아닌 나머지 축 (가로로 누운 축)
                let ay = simd_make_float3(m.columns.1), az = simd_make_float3(m.columns.2)
                let n = f.dirToSaved(simd_normalize(abs(ay.y) < abs(az.y) ? ay : az))
                let pp = L.plane(c.x, c.z)
                let np = SIMD2<Float>(simd_dot(SIMD2<Float>(n.x, n.z), L.ex), simd_dot(SIMD2<Float>(n.x, n.z), L.ez))
                let big = a.geometry.extent.width > 0.4 && a.geometry.extent.height > 0.9
                for (i, ds) in L.doors.enumerated() where ds.zone(pp, margin: 0.2, side: 0.05) {
                    let across = abs(ds.alongU ? np.x : np.y) > 0.8
                    now = (i, across && big)
                    break
                }
            }
            // 가로막고 있던 문 면이 '열렸다'는 것은 문 면 그대로(문으로 분류된 채) 문 자리 곁에서 젖혀지거나(여닫이) 옆으로 밀려났을 때만.
            // 분류가 벽 등으로 바뀌거나, 작아지거나, 이웃 면과 합쳐져 가운데가 멀리 튀거나, 사라지는 것은 비전프로가 평면을 다시 정리하는 일 —
            // 예전엔 이것도 바로 '열림'으로 쳐서, 닫힌 문이 코앞에서 열려 보였음 (그 뒤 그물이 바뀌지 않으면 닫힘 증거가 다시 오지 않아 계속 열림)
            if let w = was, w.1, u.event == .updated, now.map({ !$0.1 }) ?? true {
                var moved = false
                if a.classification == .door, w.0 < L.doors.count {
                    let ds = L.doors[w.0]
                    let m = a.originFromAnchorTransform * a.geometry.extent.anchorFromExtentTransform
                    let c = f.toSaved(simd_make_float3(m.columns.3))
                    let ay = simd_make_float3(m.columns.1), az = simd_make_float3(m.columns.2)
                    let n = f.dirToSaved(simd_normalize(abs(ay.y) < abs(az.y) ? ay : az))
                    let pp = L.plane(c.x, c.z)
                    let np = SIMD2<Float>(simd_dot(SIMD2<Float>(n.x, n.z), L.ex), simd_dot(SIMD2<Float>(n.x, n.z), L.ez))
                    let across = abs(ds.alongU ? np.x : np.y)
                    let sNow: Float = ds.alongU ? pp.y : pp.x
                    if ds.zone(pp, margin: 0.9, side: 0.3) {
                        if across < 0.7 { moved = true }                                            // 젖혀짐 (45° 넘게)
                        // 미닫이처럼 옆으로 밀림: 면 크기는 그대로인데 자리만 25cm 넘게 (처음 작게 잡힌 평면이 커지며 가운데가 옮겨 가는 것은 아님 —
                        // 예전엔 그것도 '밀림'으로 쳐서 닫힌 문 앞에서 열림·닫힘이 오갔음)
                        else if let s0 = doorPlaneS[a.id], abs(sNow - s0) > 0.25, let w0 = doorPlaneW[a.id],
                                abs(a.geometry.extent.width - w0) < 0.2 * w0 { moved = true }
                    }
                }
                if moved {
                    doorPlanes[a.id] = nil
                    doorPlaneS[a.id] = nil
                    planeAcrossAt[w.0] = nil
                    realOpen(w.0, hold: 6)
                    shelveHits(w.0)
                    coverFresh[w.0] = 0
                } else {
                    doorPlanes[a.id] = w                // 열린 증거가 아님 → 예전 기록 그대로 (다음 갱신에서 젖혀지는지 계속 봄)
                }
                continue
            }
            if u.event == .removed { doorPlanes[a.id] = nil; doorPlaneS[a.id] = nil; continue }
            if let n = now { doorPlanes[a.id] = n; doorSeenAt[n.0] = t } else if was == nil || !(was!.1) { doorPlanes[a.id] = nil; doorPlaneS[a.id] = nil }
            if let n = now, n.1 {
                // 문 자리를 가로막은 문 면 → 닫힘 증거 (문 판정이 그물과 함께 따져 1초 이어지면 닫음 — closingEvidence)
                planeAcrossAt[n.0] = t
            }
            if let n = now, n.1, !(was?.1 ?? false) {
                // 처음 가로막은 자리만 기억 (조금씩 다듬어지며 옮겨지는 것과 섞이지 않게)
                let m = a.originFromAnchorTransform * a.geometry.extent.anchorFromExtentTransform
                let c = f.toSaved(simd_make_float3(m.columns.3))
                let pp = L.plane(c.x, c.z)
                doorPlaneS[a.id] = L.doors[n.0].alongU ? pp.y : pp.x
                doorPlaneW[a.id] = a.geometry.extent.width
            }
        }
    }

    /// 다시 찾은 앵커로 저장 좌표 → 지금 좌표 계산 (2개 이상이면 위치들을 맞추고, 1개면 그 앵커의 방향까지 씀)
    private func updateFit() {
        var A: [SIMD2<Float>] = [], B: [SIMD2<Float>] = []
        var dy: Float = 0
        for (k, m) in poses {
            guard let r = saved[k] else { continue }
            A.append(r.pos.xz); B.append(SIMD2<Float>(m.columns.3.x, m.columns.3.z))
            dy += m.columns.3.y - r.pos.y
        }
        guard !A.isEmpty else { return }
        var f = Fit()
        f.y = dy / Float(A.count)
        if A.count >= 2 {
            let ca = A.reduce(SIMD2<Float>(0, 0), +) / Float(A.count), cb = B.reduce(SIMD2<Float>(0, 0), +) / Float(B.count)
            var dot: Float = 0, crs: Float = 0
            for i in A.indices {
                let a = A[i] - ca, b = B[i] - cb
                dot += a.x * b.x + a.y * b.y
                crs += a.x * b.y - a.y * b.x
            }
            let th = atan2(crs, dot)
            f.c = cos(th); f.s = sin(th)
            f.t = cb - SIMD2<Float>(ca.x * f.c - ca.y * f.s, ca.x * f.s + ca.y * f.c)
        } else if let one = poses.first, let r = saved[one.key] {
            let m = one.value
            let ax = SIMD2<Float>(m.columns.0.x, m.columns.0.z)
            let l = simd_length(ax)
            guard l > 0.1 else { return }
            f.c = ax.x / l; f.s = ax.y / l
            let p = r.pos.xz
            f.t = SIMD2<Float>(m.columns.3.x, m.columns.3.z) - SIMD2<Float>(p.x * f.c - p.y * f.s, p.x * f.s + p.y * f.c)
        }
        if let fy = floorFitY { f.y = fy }     // 높이는 실제 바닥으로 맞춘 값을 씀 (앵커 높이가 틀어져 공간이 가라앉지 않게)
        // 앵커 위치는 올 때마다 조금씩 흔들림 → 작은 변화는 부드럽게 걸러서 목표로 (큰 변화는 그대로)
        if let old = fitTarget, !f.differs(old, meters: 0.3, radians: 0.1) { f = old.lerp(f, 0.3) }
        fitTarget = f
        if fit == nil {                        // 처음: 바로 맞춤
            fitAt = t
            fit = f
            skinFit = f
            spaceRoot.transform = f.transform
            dirty.formUnion(meshes.keys)
            message = nil
        }
    }

    // MARK: 벽 모양으로 맞추기
    private func startAlign(_ d: SpaceData) {
        aligning = true
        let copies = meshes.values.map { MeshCopy($0) }
        let fb = head.y - 1.6
        let cached = alignMap
        Task {
            let res = await Task.detached(priority: .userInitiated) { () -> (Align.Map?, Align.Result?) in
                guard let M = cached ?? Align.map(d) else { return (nil, nil) }
                return (M, Align.solve(M, Align.live(copies), liveFloorFallback: fb))
            }.value
            aligning = false
            nextAlign = t + 3
            alignMap = res.0
            guard !ended, fit == nil, poses.isEmpty, let r = res.1 else { return }
            applyAligned(r.fit)
        }
    }

    /// 맞춘 좌표를 쓰고, 다음부터는 바로 찾도록 그 자리에 새 위치 기억(월드 앵커)을 만들어 저장
    private func applyAligned(_ f: Fit) {
        fitAt = t
        fitTarget = f
        fit = f
        skinFit = f
        spaceRoot.transform = f.transform
        dirty.formUnion(meshes.keys)
        message = nil
        guard let w = world, let d0 = data else { return }
        let old = d0.rec.anchors
        Task {
            var recs: [AnchorRec] = []
            for r in old {
                var m = matrix_identity_float4x4
                let p = f.toCurrent(r.pos)
                m.columns.3 = SIMD4<Float>(p.x, p.y, p.z, 1)
                let a = WorldAnchor(originFromAnchorTransform: m)
                let rec = AnchorRec(a: a.id.uuidString, p: r.p)
                saved[rec.a] = rec
                allIds.insert(rec.a)
                do { try await w.addAnchor(a); recs.append(rec) } catch { saved[rec.a] = nil }
            }
            guard !recs.isEmpty, !ended, var d = data else { return }
            for r in old { saved[r.a] = nil }
            d.rec.anchors = recs
            data = d
            try? SpaceStore.save(d)
        }
    }

    // MARK: 바닥 높이
    private var floorOK: Bool { floorFitY != nil || (fitAt.map { t - $0 > 8 } ?? false) }

    /// 좌표가 자리를 잡았는지: 바닥 높이를 확인했고, 공간을 찾은 지 2초가 지났고, 맞춤이 거의 움직이지 않음
    private var fitStable: Bool {
        guard floorFitY != nil, let f = fit, let tg = fitTarget, let a = fitAt, t - a > 2 else { return false }
        return !tg.differs(f, meters: 0.04, radians: 0.015)
    }

    /// 머리 근처(4m) 그물들의 '바닥' 면 높이 가운데 값으로 저장 바닥과의 높이 차이를 맞춤
    private func updateFloor(_ L: Layout) {
        var list: [(Float, Int)] = []
        for (id, smp) in floorSamples {
            guard let a = meshes[id] else { continue }
            let p = simd_make_float3(a.originFromAnchorTransform.columns.3)
            guard simd_distance(p.xz, head.xz) < 4, smp.0 < head.y - 0.8 else { continue }
            list.append(smp)
        }
        let total = list.reduce(0) { $0 + $1.1 }
        guard total >= 60 else { return }
        list.sort { $0.0 < $1.0 }
        var acc = 0
        var lf = list[0].0
        for (y, n) in list { acc += n; if acc * 2 >= total { lf = y; break } }
        let want = lf - L.floorY
        floorFitY = want
        if var tg = fitTarget, abs(tg.y - want) > 0.03 {
            tg.y = want
            fitTarget = tg
        }
    }

    // MARK: 앞이 얼마나 트였는지
    /// 눈에서 dir(지금 좌표) 방향으로 벽·막힌 문까지 거리 (최대 1.5m). 바닥·천장에 닿아도 멈춤.
    /// 가장 가까운 벽이 아니라 '바라보는 쪽'으로 잼 → 뒤나 옆에 벽이 있어도 현실 창·메뉴판이 가까이 당겨지지 않음
    private func clearance(_ dir: SIMD3<Float>) -> Float {
        guard let f = fit, let L = layout, simd_length(dir) > 0.01 else { return 1.5 }
        let hs = f.toSaved(head), ds = f.dirToSaved(simd_normalize(dir))
        var s: Float = 0.05
        while s < 1.5 {
            let q = hs + ds * s
            let h = q.y - L.floorY
            let pl = L.plane(q.x, q.z)
            if !L.walkable(pl) { return s }
            let here = L.at(x: q.x, z: q.z)
            if here.wall < 0.04 && h > 0.05 { return s }
            if h < 0.05 || h > L.ceil[min(255, max(1, here.room))] - 0.05 { return s }
            for i in solidDoors where i < L.doors.count && L.doors[i].zone(pl, margin: 0.02, side: -0.02) { return s }
            s += 0.03
        }
        return 1.5
    }

    // MARK: 현실 창
    /// 안내판 버튼을 누름 (SwiftUI가 따로 받으므로 탭 받는 상자와 겹치지 않음 — 기록만, 메뉴판 4초 연장)
    func uiTouched() {
        lastUITap = t
        hudUntil = max(hudUntil, t + 4)
    }

    /// 시선 정면 60cm(벽·닫힌 문이 더 가까우면 그 앞)에 현실을 보여 주는 원. 크기는 거리에 맞춰 보이는 크기가 같게.
    /// 더블탭으로 켜고 끔. 닫힌 실제 문 앞(1m 안)이면 저절로 켜지고, 문이 열리거나 문에서 벗어나면 꺼짐
    private func placePeek(_ dt: Float) {
        // 닫힌 실제 문 앞에서 저절로 여는 현실 창은 문 쪽을 '바라볼 때'만 — 고개를 숙여 바닥·소파를 볼 땐 열지 않음
        // (예전엔 수평 방향만 따져서, 문 근처에서 아래를 보면 바닥 위에 현실 창이 떠 현실이 겹쳐 보였음)
        // (문 쪽을 바라보는지는 updateDoors에서 시선이 문짝에 닿는지로 판단 — 손잡이를 내려다봐도 유지, 바닥을 보면 꺼짐)
        let auto = leafDoor != nil && leafDoor != peekDismissed
        // 가구 맞추기 중엔 끔: 현실 창(가려 주는 재질)이 시선 앞에서 가구 상자를 둥글게 지워 '투명하게 가려지는 곳'이 생겼음
        let target: Float = (freePeek || auto) && !furnMode ? 1 : 0
        peekAmt += (target - peekAmt) * min(1, dt * (target > peekAmt ? 6 : 16))
        let on = peekAmt > 0.01
        if peek.isEnabled != on { peek.isEnabled = on }
        guard on else { return }
        let g = simd_length(fwd) > 0.1 ? simd_normalize(fwd) : SIMD3<Float>(0, 0, -1)
        let d = min(0.6, max(0.18, clearance(g) - 0.08))
        let goal = head + g * d
        peek.position = peekAmt < 0.05 ? goal : peek.position + (goal - peek.position) * min(1, dt * 30)   // 시선에 거의 붙어서 따라감
        let toHead = head - peek.position
        if simd_length(toHead) > 0.01 { peek.orientation = simd_quatf(from: SIMD3<Float>(0, 1, 0), to: simd_normalize(toHead)) }
        let e = peekAmt * peekAmt * (3 - 2 * peekAmt)
        let r = d * 0.25 * max(0.001, e)
        peek.scale = SIMD3<Float>(r, 1, r)
    }

    var peekVisible: Bool { peekAmt > 0.5 }

    // MARK: 매 프레임
    func tick(_ dt: Float) {
        t += dt
        guard let w = world, w.state == .running,
              let dev = w.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) else { return }
        let m = dev.originFromAnchorTransform
        head = simd_make_float3(m.columns.3)
        fwd = -simd_make_float3(m.columns.2)
        headUp = simd_make_float3(m.columns.1)
        // 몸 자리 = 목 뒤(눈에서 9cm 뒤·7cm 아래): 고개를 숙이거나 돌리면 눈(기기)은 앞뒤로 10~15cm 움직이지만 몸은 그대로.
        // 걷는 빠르기·지금 방 판정은 이 자리로 함 — 예전엔 눈 자리로 해서, 아래를 내려다보면 '빨리 움직임'이나 '방 밖(벽 가까이)'으로
        // 잘못 알아 안전 장치가 세계 전체를 흐리게 하고 현실이 겹쳐 보였음
        let pivot = head - fwd * 0.09 - headUp * 0.07
        // 빠르기: 바로 앞 자리와 '실제로 지난 시간'으로 잼. 바닥처럼 무늬 없는 곳을 내려다보면 추적이 잠깐 끊기거나(프레임 건너뜀)
        // 머리 자리가 한 번 튀는데, 예전엔 그 사이 움직인 거리를 한 프레임 시간으로 나눠 '너무 빠름'으로 알고 세계를 잠깐 흐렸음
        // → 추적이 안 될 때·0.25초 넘게 끊겼을 때·한 프레임에 15cm 넘게 튄 값은 버림
        if dev.isTracked {
            if let lh = lastHead, let lt = lastHeadT, t - lt > 0.001, t - lt < 0.25 {
                let d = simd_distance(lh.xz, pivot.xz)
                if d < 0.15 { speed += (min(3, d / (t - lt)) - speed) * min(1, dt * 3) }
            }
            lastHead = pivot
            lastHeadT = t
        } else {
            lastHeadT = nil
        }
        fastT = speed > 1.6 ? fastT + dt : 0

        if fit == nil, poses.isEmpty, !aligning, t > nextAlign, let d = data { startAlign(d) }

        // 고개 돌리는 빠르기 (도/초) — 좌표 맞춤 보정을 언제 할지 정하는 데 씀
        if let lf = lastFwd, dt > 0 {
            let a = acos(min(1, max(-1, simd_dot(simd_normalize(lf), simd_normalize(fwd))))) / dt * 180 / .pi
            turnSpeed += (a - turnSpeed) * min(1, dt * 10)
        }
        lastFwd = fwd
        // 좌표 맞춤 보정: 크게 틀어졌을 때만 바로. 작은 보정은 고개를 돌리는 동안에만 조금씩 (눈이 알아채지 못할 때) —
        // 가만히 보거나 걸어가는 동안 세계 전체가 미세하게 미끄러지면 초점이 안 맞거나 겹쳐 보이고 어지러웠음. 1cm·0.3도 안의 차이는 무시
        // 1.5cm·0.5도 안의 차이는 무시 (먼 산·하늘은 아주 작은 회전에도 크게 움직여 흔들려 보임)
        if dev.isTracked, let tg = fitTarget, let cur = fit, tg != cur, tg.differs(cur, meters: 0.015, radians: 0.009) {
            var k = min(1, max(0, (turnSpeed - 25) / 60))                // 25도/초 넘게 돌릴 때부터, 85도/초면 최대
            if tg.differs(cur, meters: 0.08, radians: 0.03) { k = max(k, 0.25) }    // 8cm 넘게 어긋났으면 가만히 있어도 천천히
            let nf = tg.differs(cur, meters: 0.6, radians: 0.3) ? tg : cur.lerp(tg, min(1, dt * 4 * k))
            fit = nf
            spaceRoot.transform = nf.transform
            if let sf = skinFit, nf.differs(sf, meters: 0.12, radians: 0.04) {
                skinFit = nf
                dirty.formUnion(meshes.keys)          // 많이 바뀌었을 때만 그물을 새 좌표로 다시 읽음
            }
        }

        if let fit, let L = layout, let I = info {
            let hs = fit.toSaved(head)
            let bs = fit.toSaved(head - fwd * 0.09 - headUp * 0.07)             // 몸 자리 (방 판정용)
            let r = L.roomNear(x: bs.x, z: bs.z, radius: 0.3)
            if r != candidate { candidate = r; candidateT = 0 } else { candidateT += dt }
            // 문 자리(문턱 앞뒤 15cm)에 서 있는 동안은 방을 바꾸지 않음 — 문턱에서 지금 방이 오락가락하면
            // 그때마다 문 상태가 처음으로 돌아가 열쇠 문이 나타났다 사라지기를 반복했음
            let pb = L.plane(bs.x, bs.z)
            let inDoorway = current != 0 && L.doors.contains { $0.zone(pb, margin: 0.15) }
            if candidate != current && (candidateT > 0.5 || current == 0) && candidate != 0 && !inDoorway { enterRoom(candidate) }
            let atDoor = L.doors.contains { $0.zone(pb, margin: 0.3) }
            bodyRoom = r
            bodyDoors = L.doors.indices.filter { L.doors[$0].inside(pb) }      // 문 자리 안 (닫힌 문 앞에선 켜지 않음 — 문짝 판 너머로 옆방이 비치지 않게)
            bodyNearDoors = L.doors.indices.filter { L.doors[$0].zone(pb, margin: 0.35, side: 0.1) }      // 문간 35cm 안 (눈은 몸보다 앞서 문간에 들어감)
            outsideT = (r == 0 && !atDoor) ? outsideT + dt : 0          // 문 자리를 지나는 동안은 '방 밖'으로 치지 않음 (현실이 비치지 않게)
            handDoors(L, fit)
            updateDoors(dt, hs, bs, fit.dirToSaved(fwd), L)
            floorTimer += dt
            if floorTimer > 0.5 { floorTimer = 0; updateFloor(L) }
            buildTimer += dt
            if buildTimer > 0.05 { buildTimer = 0; buildSome(fit, I) }
        }
        vox?.tick(now: t)
        if fade > 0.95 && vox?.revealed == false { vox?.revealed = true }
        voxSaveT += dt
        if voxSaveT > 20 { voxSaveT = 0; saveVox() }

        // 탐험 시작 스캔 연출: 공간을 찾고 모든 방 세계가 준비되면 한 번
        if !introDone, intro == nil, ready, floorOK, let f = fit, let L = layout, let d = data {
            let hs = f.toSaved(head)
            let ii = ScanIntro(L, head: L.plane(hs.x, hs.z), floorY: d.rec.floorY, current: current)
            root.addChild(ii.root)
            ii.root.transform = spaceRoot.transform
            intro = ii
            Sfx.playHead("scan", in: root, gain: -4)
        }
        if let ii = intro {
            ii.root.transform = spaceRoot.transform
            ii.tick(dt)
            if ii.done {
                ii.root.removeFromParent()
                intro = nil
                introDone = true
            }
        }

        // 안전: 공간을 아직 못 찾았거나, 구성한 방 밖이거나, 너무 빠르면 현실이 보이게
        var target: Float = 1
        var why: String?
        if fit == nil || !ready || !floorOK || furnMode { target = 0 }      // 가구 맞추기: 현실 위에 가구 블록만
        else if outsideT > 1.0 { target = 0; why = "방 밖이에요" }
        else if fastT > 0.4 { target = 0; why = "천천히 걸어 주세요" }
        let rate: Float = target < fade ? 3 : 1.1
        if let ii = intro {
            fade = min(target, ii.world)
        } else {
            fade += (target - fade) * min(1, dt * rate)
        }
        if abs(fade - appliedFade) > 0.01 || (target == 1 && fade > 0.99 && appliedFade < 1) {
            let v = fade > 0.99 ? 1 : fade
            spaceRoot.setOpacity(v)
            appliedFade = v
        }
        furnHideScene(furnMode && fade < 0.02)
        // 불러오는 중: 글 대신 진행 막대 (공간 찾기 → 방 세계 만들기 → 바닥 맞추기 / 테마 바꾸기)
        let total = max(1, data?.rec.rooms.count ?? 1)
        var goal: Float? = nil
        if fit == nil { goal = min(0.15, 0.02 + t * 0.012) }
        else if !ready { goal = 0.15 + 0.75 * Float(worlds.count) / Float(total) }
        else if !floorOK { goal = 0.93 }
        else if let tp = themeProg { goal = tp }
        if let g = goal {
            progDoneAt = nil
            if loadProgress == nil { progShown = 0 }
            progShown += (max(progShown, g) - progShown) * min(1, dt * 4)
            hudUntil = max(hudUntil, t + 0.5)
        } else if loadProgress != nil {
            progShown += (1 - progShown) * min(1, dt * 8)
            if progShown > 0.995 {
                progShown = 1
                if progDoneAt == nil { progDoneAt = t }
            }
        }
        var keep = goal != nil
        if !keep {
            if let d0 = progDoneAt { keep = t - d0 < 0.4 } else { keep = loadProgress != nil }
        }
        let shownP: Double? = keep ? Double(progShown) : nil
        var changed = false
        if let a = shownP, let b = loadProgress { changed = abs(a - b) > 0.004 } else { changed = (shownP == nil) != (loadProgress == nil) }
        if changed { loadProgress = shownP }
        if fit != nil || goal == nil {
            // 글은 꼭 필요할 때만 짧게 (오래 걸릴 때의 한마디, 안전 경고, 소리 문제)
            var msg: String? = why ?? (t < tipUntil ? tip : nil) ?? player.status
            if fit != nil && ready && !floorOK, let fa = fitAt, t - fa > 3 { msg = "발밑을 한 번 봐 주세요" }
            if goal != nil && msg == player.status { msg = nil }
            if msg != message {
                message = msg
                if msg != nil && t > themeQuiet { hudUntil = max(hudUntil, t + 4) }      // 새 알림은 4초 보여 주고 사라짐
            }
        } else if t > 8 && message == nil {
            message = "스캔한 곳을 둘러봐 주세요"
        }
        hudAlert = why != nil
        tapCatcher.position = head

        placePeek(dt)
        if let wld = worlds[current], let f = fit, let L = layout {
            let hs = f.toSaved(head)
            wld.avoidHead(L.plane(hs.x, hs.z))
        }
        // 움직임 계산은 지금 방과, 지금 방이 빌려 쓰는 하늘 세계의 대표 방만 (같은 테마 방 전체를 매 프레임 돌리지 않게)
        let hostNow = worlds[current]?.hostId ?? current
        for (id, wld) in worlds { wld.tick(dt, active: id == current || id == hostNow) }
        soundTick(dt)
        placeHud(dt)
        placeDocent(dt)
        furnTick()
        syncBars()
        tapTick()
        campTick(dt)
        catTick(dt)
        dogTick(dt)
        themeFeatures(dt)
    }

    // MARK: 테마마다의 특별한 것 (시골: 별자리, 카페: 재즈·테이블 차림)
    func attachStars(_ e: Entity) {
        starCard = e
        e.isEnabled = false
        root.addChild(e)
        makeBar("stars")
    }

    func closeStars() {
        lastUITap = t
        starPick = nil
        stars?.unpick()
        starCard?.isEnabled = false
    }

    /// 정보판 자리: 별자리 바로 아래 (같은 방위, 판 윗변이 가장 낮은 별 조금 아래) — 별자리를 보며 탭하면 그 시선 그대로 아래에 읽을 판이 있음.
    /// 판은 늘 나를 정면으로 보고(기울어짐), 네 귀퉁이·옮기기 막대까지 모두 방 안(천장·벽·문·가구에서 떨어짐)인 자리만.
    /// 높이 올려다보면 천장에 걸리므로 들어갈 때까지 가까이(그만큼 작게 — 보이는 크기는 같음), 그래도 안 되면 조금씩 낮추고 마지막에야 옆으로
    private func placeStarCard(away cdir: SIMD3<Float>, lowElev: Float) {
        guard let card = starCard else { return }
        card.isEnabled = true
        var hz = SIMD3<Float>(cdir.x, 0, cdir.z)
        if simd_length(hz) < 0.05 { hz = SIMD3<Float>(fwd.x, 0, fwd.z) }
        hz = simd_length(hz) > 0.01 ? simd_normalize(hz) : SIMD3<Float>(0, 0, -1)
        let full: Float = 0.95
        var hw: Float = 0.25, hh: Float = 0.28
        card.scale = SIMD3<Float>(repeating: 1)
        let bb = card.visualBounds(relativeTo: card)
        if bb.extents.x > 0.05 && bb.extents.y > 0.05 { hw = bb.extents.x / 2; hh = bb.extents.y / 2 }
        let halfAng = atan((hh + 0.06) / full)                                   // 판 반 높이 + 막대가 차지하는 각도
        let elev0 = min(0.9, lowElev - 0.05 - halfAng)                           // 판 가운데 = 가장 낮은 별 바로 아래
        var best: (SIMD3<Float>, Float)? = nil
        search: for yaw: Float in [0, 0.2, -0.2, 0.4, -0.4] {
            for drop: Float in [0, 0.12, 0.24, 0.36, 0.5] {
                let elev = max(-0.2, elev0 - drop)
                let h2 = simd_normalize(simd_quatf(angle: yaw, axis: [0, 1, 0]).act(hz))
                let d = simd_normalize(h2 * cos(elev) + SIMD3<Float>(0, sin(elev), 0))
                let cr = simd_normalize(simd_cross(d, SIMD3<Float>(0, 1, 0)))       // 판의 가로
                let cu = simd_normalize(simd_cross(cr, d))                            // 판의 세로 (나를 향해 기운 판)
                var dist = full
                while dist >= 0.36 {
                    let k = dist / full
                    let c = head + d * dist
                    var ok = clearance(d) > dist + 0.04
                    if ok {
                        pts: for sx: Float in [-1, -0.5, 0, 0.5, 1] {
                            for sy: Float in [-1.25, -1, 0, 1] {                   // -1.25 = 아래 옮기기 막대
                                let q = c + cr * (sx * (hw + 0.04) * k) + cu * (sy * (hh + 0.04) * k)
                                if !spaceFree(q) { ok = false; break pts }
                            }
                        }
                    }
                    if ok { best = (c, k); break search }
                    dist -= 0.04
                }
            }
        }
        var g = fwd; g.y = 0
        g = simd_length(g) > 0.01 ? simd_normalize(g) : hz
        let spot = best ?? (head + g * 0.4 + SIMD3<Float>(0, -0.05, 0), 0.4 / full)
        card.scale = SIMD3<Float>(repeating: spot.1)
        card.position = spot.0
        faceDocent(card)
    }

    /// 지금 좌표의 점이 방 안 빈 곳인지 (벽·천장·바닥·닫힌 문·가구에서 떨어짐)
    private func spaceFree(_ p: SIMD3<Float>) -> Bool {
        guard let f = fit, let L = layout else { return true }
        let q = f.toSaved(p)
        let h = q.y - L.floorY
        let pl = L.plane(q.x, q.z)
        guard L.walkable(pl) else { return false }
        let here = L.at(x: q.x, z: q.z)
        if here.room == 0 || here.wall < 0.06 { return false }
        if h < 0.08 || h > L.ceil[min(255, max(1, here.room))] - 0.07 { return false }
        for i in solidDoors where i < L.doors.count && L.doors[i].zone(pl, margin: 0.04, side: -0.02) { return false }
        if let v = vox {
            let offs: [SIMD2<Float>] = [[0, 0], [0.06, 0], [-0.06, 0], [0, 0.06], [0, -0.06]]
            for o in offs where v.heightAt(pl + o) + 0.05 > h { return false }
        }
        return true
    }

    private func themeFeatures(_ dt: Float) {
        guard let f = fit, let L = layout, let d = data, ready, let rm = d.rec.room(current), let wld = worlds[current] else {
            music.set(false)
            waterSound.set(false, stream: nil, fall: nil)
            return
        }
        let gaze = f.dirToSaved(fwd)
        // 계곡: 개울·폭포 물소리
        waterSound.set(rm.place == "valley" && fade > 0.5, stream: wld.streamSpot, fall: wld.fallSound)
        // 밤하늘 (모든 장소: 별·달, 숲은 별자리까지) — 방 세계가 만들어 둔 것. 지금 방 것만 반짝임·포커스를 계산
        let sky = wld.skyStars
        if stars !== sky {
            if starPick != nil { closeStars() }
            stars = sky
        }
        stars?.tick(dt, gaze: gaze)
        // 바다 해파리: 머리 자리(가까이 오면 비켜 감) · 계곡 물고기: 손(물에 대면 흩어짐)
        wld.jelly?.head = f.toSaved(head)
        wld.jelly?.hands = handPts                                   // 손 (저장 좌표) — 톡 건드리면 놀라 밀려 감
        if wld.jelly?.furnitureH == nil, let v = vox { wld.jelly?.furnitureH = { p in v.heightAt(L.plane(p.x, p.y)) } }
        wld.creek?.tick(dt, hands: handPts, feet: f.toSaved(head - fwd * 0.09 - headUp * 0.07))      // 몸(목 뒤) 자리 — 고개만 돌려도 걸은 걸로 치지 않게
        // 같은 세계 무리의 다른 방 개울도 물이 흐르게 (벽 너머로 그 방 물길·나가는 물길이 보임 — 지금 방 것만 흘러 나머지는 그림처럼 멈춰 있었음)
        for id in currentGroup where id != rm.id { worlds[id]?.creek?.flowTick(dt) }
        // 카페: 천장 스피커에서 오르골, 탁자 위 차림
        if rm.place == "cafe" && fade > 0.5 {
            music.set(true, at: wld.speakerSpot ?? wld.center + SIMD3<Float>(0, rm.ceil - 0.35, 0))      // 천장 들보에 매단 스피커에서
            wld.musicOn = true
            let key = "\(rm.time)-\(rm.lookMode.rawValue)"
            if cafeSets[rm.id]?.0 != key {
                cafeSets[rm.id]?.1.remove()
                let tb = Tex.with(rm.lookMode) { CafeTables(look: rm.lookMode, time: rm.time, room: rm.id) }
                spaceRoot.addChild(tb.root)
                cafeSets[rm.id] = (key, tb)
            }
            if let v = vox, let tb = cafeSets[rm.id]?.1 {
                tb.tick(dt, head: f.toSaved(head), L: L, cellH: { u, w in v.cellH(u, w) })
            }
        } else {
            music.set(false)
            wld.musicOn = false
        }
        // 다른 방 테마가 카페가 아니게 바뀌었으면 그 방 차림은 치움
        for (id, c) in cafeSets where d.rec.room(id)?.place != "cafe" {
            c.1.remove()
            cafeSets[id] = nil
        }
        music.tick(dt)
    }

    // MARK: 집 고양이
    /// 집 테마 방에 있으면 고양이가 따라다님 (집이 아닌 방으로 가면 사라지고, 다시 오면 시야 가장자리로 들어옴)
    private func catTick(_ dt: Float) {
        stillT = speed < 0.08 ? stillT + dt : 0
        guard let f = fit, let L = layout, let d = data else { return }
        let rm = d.rec.room(current)
        let home = ready && introDone && fade > 0.5 && rm?.place == "home"
        let homeRooms = Set(d.rec.rooms.filter { $0.place == "home" }.map(\.id))
        let hs = f.toSaved(head)
        var fw = f.dirToSaved(fwd)
        let gaze = simd_length(fw) > 0.01 ? simd_normalize(fw) : SIMD3<Float>(0, 0, -1)
        fw.y = 0
        let fwd2 = simd_length(fw) > 0.01 ? simd_normalize(SIMD2<Float>(fw.x, fw.z)) : SIMD2<Float>(0, -1)
        // 테마(표시 방식)가 바뀌면 새로
        if let c = cat, let rm, catLook != rm.lookMode, home { c.remove(); cat = nil }
        if home && cat == nil {
            // 시야 가장자리에서 걸어 들어오게: 앞 1.6m 옆쪽 빈 바닥
            let me = SIMD2<Float>(hs.x, hs.z)
            for a in [Float(0.55), -0.55, 0.3, -0.3, 0] {
                let v = SIMD2<Float>(fwd2.x * cos(a) - fwd2.y * sin(a), fwd2.x * sin(a) + fwd2.y * cos(a))
                let p = me + v * 1.6
                if catFree(p, L, homeRooms) {
                    let c = Tex.with(rm?.lookMode ?? .color) { HomeCat(at: p, floorY: L.floorY, look: rm?.lookMode ?? .color) }      // 선 굵기 등 그 방 표시 방식으로
                    spaceRoot.addChild(c.root)
                    spaceRoot.addChild(c.ballRoot)
                    cat = c
                    catLook = rm?.lookMode
                    break
                }
            }
        }
        guard let c = cat else { return }
        if !home { c.leave() }
        let blocked = vox
        let cur = current
        let ctx = HomeCat.Ctx(head: hs, fwd: fwd2, gaze: gaze, floorY: L.floorY, userSpeed: speed, still: stillT, seated: seated, hands: handPts,
                              free: { [unowned self] p in self.catFree(p, L, homeRooms) },
                              pass: { [unowned self] p in self.catFree(p, L, homeRooms, wallR: 0.2, swing: false) },
                              top: { p in blocked?.flatTop(L.plane(p.x, p.y)) },
                              height: { p in blocked?.heightAt(L.plane(p.x, p.y)) ?? 0 },
                              room: { p in let a = L.at(x: p.x, z: p.y); return a.room != 0 && a.room == cur && a.wall > 0.06 },      // 장난감은 지금 방 안에서만 (옆방 벽을 뚫고 나가지 않게)
                              ceil: L.ceil[min(255, max(1, current))])
        c.tick(dt, ctx)
        if c.done { cat = nil }
    }

    // MARK: 시골 강아지
    /// 시골 테마 방에 있으면 복슬복슬한 갈색 강아지가 따라다님 (고양이와 같은 방식, 시골이 아닌 방으로 가면 사라짐)
    private func dogTick(_ dt: Float) {
        guard let f = fit, let L = layout, let d = data else { return }
        let rm = d.rec.room(current)
        let here = ready && introDone && fade > 0.5 && rm?.place == "village"
        let rooms = Set(d.rec.rooms.filter { $0.place == "village" }.map(\.id))
        let hs = f.toSaved(head)
        var fw = f.dirToSaved(fwd)
        let gaze = simd_length(fw) > 0.01 ? simd_normalize(fw) : SIMD3<Float>(0, 0, -1)
        fw.y = 0
        let fwd2 = simd_length(fw) > 0.01 ? simd_normalize(SIMD2<Float>(fw.x, fw.z)) : SIMD2<Float>(0, -1)
        if let g = dog, let rm, dogLook != rm.lookMode, here { g.remove(); dog = nil }
        if here && dog == nil {
            let me = SIMD2<Float>(hs.x, hs.z)
            for a in [Float(0.5), -0.5, 0.3, -0.3, 0] {
                let v = SIMD2<Float>(fwd2.x * cos(a) - fwd2.y * sin(a), fwd2.x * sin(a) + fwd2.y * cos(a))
                let p = me + v * 1.8
                if catFree(p, L, rooms, r: 0.34) {
                    let g = Tex.with(rm?.lookMode ?? .color) { HomeDog(at: p, floorY: L.floorY, look: rm?.lookMode ?? .color) }
                    spaceRoot.addChild(g.root)
                    spaceRoot.addChild(g.propRoot)
                    dog = g
                    dogLook = rm?.lookMode
                    break
                }
            }
        }
        guard let g = dog else { return }
        if !here { g.leave() }
        let blocked = vox
        let cur = current
        let ctx = HomeCat.Ctx(head: hs, fwd: fwd2, gaze: gaze, floorY: L.floorY, userSpeed: speed, still: stillT, seated: seated, hands: handPts,
                              free: { [unowned self] p in self.catFree(p, L, rooms, r: 0.34) },
                              pass: { [unowned self] p in self.catFree(p, L, rooms, r: 0.34, wallR: 0.24, swing: false) },
                              top: { p in blocked?.flatTop(L.plane(p.x, p.y)) },
                              height: { p in blocked?.heightAt(L.plane(p.x, p.y)) ?? 0 },
                              room: { p in let a = L.at(x: p.x, z: p.y); return a.room != 0 && a.room == cur && a.wall > 0.06 },      // 장난감은 지금 방 안에서만 (옆방 벽을 뚫고 나가지 않게)
                              ceil: L.ceil[min(255, max(1, current))])
        g.tick(dt, ctx)
        if g.done { dog = nil }
    }

    /// 사용법 알림 (탐험마다 한 번씩, 5초)
    private func showTip(_ key: String, _ text: String) {
        guard !tipsShown.contains(key) else { return }
        tipsShown.insert(key)
        tip = text
        tipUntil = t + 5
    }

    /// 고양이가 설 수 있는 바닥: 집 테마 방 안, 벽에서 12cm 넘게, 둘레 12cm에 가구 없음, 문이 쓸고 지나가는 자리 아님
    /// r: 그림 판이 어느 쪽을 향해도(늘 나를 봄) 가구·벽 속으로 파고들지 않을 만큼의 여유 (판 반폭 + 6cm쯤)
    /// swing: 문이 쓸고 지나가는 자리도 막힌 곳으로 칠지 (머물 자리 고를 때는 막고, 지나갈 때는 열어 둠 — 문을 지나 옆방으로 따라오게)
    /// wallR: 벽까지 띄울 거리 (없으면 r) — 지나갈 때는 좁은 문(폭 70cm 안팎)도 지나도록 작게
    private func catFree(_ p: SIMD2<Float>, _ L: Layout, _ homeRooms: Set<Int>, r: Float = 0.27, wallR: Float? = nil, swing: Bool = true) -> Bool {
        let a = L.at(x: p.x, z: p.y)
        guard a.room != 0, homeRooms.contains(a.room), a.wall > (wallR ?? r) else { return false }
        let pl = L.plane(p.x, p.y)
        if swing && Skin.inSwing(L, pl) { return false }
        guard let v = vox else { return true }
        if v.heightAt(pl) > 0.05 { return false }
        for ring in [r * 0.55, r] {
            for k in 0..<12 {
                let ang = Float(k) / 12 * 2 * .pi
                if v.heightAt(pl + SIMD2<Float>(cos(ang), sin(ang)) * ring) > 0.05 { return false }
            }
        }
        return true
    }

    // MARK: 불멍
    /// 캠핑장에서 앉으면(머리가 서 있을 때보다 35cm 넘게 낮아져 0.8초 머묾) 앞 1~1.8m 평평한 빈 바닥에 모닥불.
    /// 의자든 바닥이든 머리 높이로 알아봄. 일어나면(머리가 다시 올라오거나 걷기 시작) 불이 사그라들고 연기로 흩어짐
    private func campTick(_ dt: Float) {
        if let fr = fire {
            fr.tick(dt)
            if fr.done { fire = nil }
        }
        guard let f = fit, let L = layout, ready, introDone, fade > 0.5 else { return }
        let hs = f.toSaved(head)
        let h: Float = hs.y - L.floorY
        // 서 있는 높이: 더 높아지면 바로, 걷는 동안엔 천천히 따라감 (앉아 있을 땐 그대로)
        // (처음부터 앉아서 시작하면 서 있는 높이를 모르므로 처음 값은 적어도 1.55m로 잡음)
        if standH == 0 { standH = max(h, 1.55) } else if h > standH { standH = h } else if speed > 0.3 && !seated { standH += (h - standH) * min(1, dt * 0.4) }
        // 앉음: 서 있을 때보다 머리가 28cm 넘게 낮아짐 (소파·의자·바닥 어디든, 키와 상관없이 — 예전엔 '바닥에서 1.35m 아래'도 따져 키 큰 사람은 아래를 봐야만 됐음)
        // 또는 바닥에서 눈까지 1.25m 아래 — 의자·소파에 앉은 높이 (처음부터 앉아서 시작해도 알아봄)
        let low = (h < standH - 0.28 || h < 1.25) && h > 0.3
        if !seated {
            sitT = (low && speed < 0.15) ? sitT + dt : 0
            if sitT > 0.8 {                                     // 앉고 1초쯤이면 불이 피어남 (어디를 보고 있든)
                seated = true
                standT = 0
                sitDown(hs, L)
            }
        } else {
            standT = (h > standH - 0.16 || speed > 0.5) ? standT + dt : 0
            if standT > 0.4 {
                seated = false
                sitT = 0
                fire?.die()
            }
        }
    }

    private func sitDown(_ hs: SIMD3<Float>, _ L: Layout) {
        guard let d = data, let rm = d.rec.room(current), rm.place == "camp", let w = worlds[current], let f = fit else { return }
        let me = SIMD2<Float>(hs.x, hs.z)
        if let fr = fire {
            let fp = SIMD2<Float>(fr.root.position.x, fr.root.position.z)
            if fr.dying && simd_distance(fp, me) < 2.5 { fr.revive(); return }
            if !fr.dying { return }
            fr.remove()
            fire = nil
        }
        let fs = f.dirToSaved(fwd + headUp * (fwd.y < 0 ? 1 : -1))   // 바닥을 내려다보거나 올려다봐도 몸이 향한 앞쪽
        var dir = SIMD2<Float>(fs.x, fs.z)
        dir = simd_length(dir) > 0.05 ? simd_normalize(dir) : SIMD2<Float>(0, -1)
        let blocked = vox?.blockedCells(minH: 0.05) ?? []
        func free(_ p: SIMD2<Float>, _ r: Float) -> Bool {
            let c = L.at(x: p.x, z: p.y)
            guard c.room == current, c.wall > r + 0.05 else { return false }
            for ring in [Float(0), r * 0.33, r * 0.66, r] {
                let n = ring == 0 ? 1 : 16
                for k in 0..<n {
                    let a = Float(k) / Float(n) * 2 * .pi
                    let q = p + SIMD2<Float>(cos(a), sin(a)) * ring
                    let pl = L.plane(q.x, q.y)
                    if L.at(x: q.x, z: q.y).room != current { return false }
                    if blocked.contains(RoomWorld.clutterKey(pl)) { return false }
                    if Skin.inSwing(L, pl) { return false }
                }
            }
            return true
        }
        // 모닥불 크기는 앞 빈 바닥에 맞춰 여러 단계 (돌 둘레 반지름 75cm ~ 18cm): 넓으면 크게, 좁으면 작게.
        // 큰 불일수록 조금 더 떨어진 곳(앉은 자리에서 불 반지름 + 45cm 넘게, 2.3m 안)
        // (예전엔 가장 커도 55cm에 둘레 여유 22cm·1.9m 안만 봐서, 넓은 공간에서도 작은 불만 피었음)
        var cands: [(SIMD2<Float>, Float, Float)] = []         // 자리, 점수, 반지름
        for r: Float in [0.75, 0.65, 0.55, 0.46, 0.37, 0.28, 0.18] {
            var dd: Float = max(0.55, r + 0.45)
            while dd <= 2.3 {
                for a in [Float(0), 0.2, -0.2, 0.4, -0.4, 0.65, -0.65, 1.0, -1.0, 1.4, -1.4, 1.9, -1.9, 2.5, -2.5, 3.14] {   // 앞이 막혔으면 옆·뒤에라도
                    let v = SIMD2<Float>(dir.x * cos(a) - dir.y * sin(a), dir.x * sin(a) + dir.y * cos(a))
                    let p = me + v * dd
                    cands.append((p, abs(dd - (r + 0.75)) + abs(a) * 0.8 + (0.75 - r) * 3, r))
                }
                dd += 0.1
            }
        }
        cands.sort { $0.1 < $1.1 }
        // 불 자리 = 모래 바닥 원(돌 둘레의 1.1배, 눈 오면 1.45배) + 연기·불꽃 여유 14cm 안에 가구·벽·문이 없어야 (사물과 겹치지 않게)
        let snowy = ["snow", "heavysnow"].contains(rm.weather)
        guard let pick = cands.first(where: { free($0.0, $0.2 * (snowy ? 1.45 : 1.1) + 0.14) }) else { return }      // 들어갈 자리가 없으면 피우지 않음
        let wd = simd_quatf(angle: -w.angle, axis: [0, 1, 0]).act(SIMD3<Float>(1, 0, 0.35))
        let cf = Tex.with(rm.lookMode) { Campfire(at: SIMD3<Float>(pick.0.x, L.floorY, pick.0.y), room: rm, look: rm.lookMode, windDir: wd, ceilH: rm.ceil, sky: w.world,
                          scale: pick.2 / 0.55) }
        spaceRoot.addChild(cf.root)
        fire = cf
    }

    private func enterRoom(_ r: Int) {
        // 나온 방이 전시관이면 그림을 새로 골라 둠 (다시 들어가면 다른 그림)
        if let prev = worlds[current], prev.hasPaintings, current != r {
            Task { await hangGallery(prev) }
        }
        if docent != nil { closeDocent() }
        if starPick != nil { closeStars() }
        if current != r { fire?.die(); seated = false; sitT = 0 }
        current = r
        // 처음 들어가는 방만 알림판으로 잠깐 알려 줌 (한 번 본 방은 다시 띄우지 않음)
        if t > themeQuiet && !seenRooms.contains(r) { hudUntil = max(hudUntil, t + 4) }
        seenRooms.insert(r)
        // 열린 문 기록은 지금 곁에 있는 문(지나온 문 포함)만 남김 — 곁에 있는 문은 건너감·멀어짐 판정이 알아서 닫음
        doorOpen = doorOpen.filter { nearDoors.contains($0) }
        guard let d = data, let L = layout, let rm = d.rec.room(r) else { return }
        if worlds[r] == nil {                               // 아직 못 만든 방이면 바로 만듦 (그림도 걺)
            let nw = addWorld(d, rm, L)
            Task { await hangGallery(nw) }
        }
        refreshActive()
        if let w = worlds[r], !w.hungArts.isEmpty { Docent.shared.prefetch(w.hungArts.map(\.pick)) }
        room = rm
        player.enter(rm)
        nextEvent = t + Float.random(in: 3...8)
        nextThunder = t + Float.random(in: 4...10)
    }

    /// 사건 소리(새·주전자·스쿠터…)는 방 둘레 바깥 곳곳에서, 폭우면 번개·천둥
    private func soundTick(_ dt: Float) {
        guard current != 0, let wld = worlds[current], fade > 0.5 else { return }
        if t > nextEvent {
            nextEvent = t + Float.random(in: 14...34)          // 가끔 (예전 8~22초는 잦아 어수선했음)
            player.playEvent(in: spaceRoot, center: wld.center, extent: max(wld.halfSize.x, wld.halfSize.y), floorY: wld.center.y)
        }
        if wld.room.weather == "storm", t > nextThunder {
            nextThunder = t + Float.random(in: 12...28)
            wld.flash()
            let a = Float.random(in: 0...(2 * .pi))
            let p = wld.center + SIMD3<Float>(cos(a) * 30, 12, sin(a) * 30)
            let delay = Double.random(in: 0.4...2.0)
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard let self else { return }
                self.player.thunder(in: self.spaceRoot, at: p)
            }
        }
    }

    // MARK: 문
    /// 문 하나마다 상태 하나 — 매 프레임 아래 두 가지만 보고 '보이는 모양'을 하나로 정함 (예전처럼 경우마다 덧댄 깃발이 서로 엇갈려
    /// 문이 나타났다 사라졌다 하지 않게).
    ///
    /// ① 실제 문 (realClosed): 닫힘은 '새 증거'로만, 천천히 / 열림은 바로.
    ///   - 열림: 손으로 당기거나 밂, 문 면(평면)이 젖혀짐, 그물에서 막힘이 크게 줄어듦, 문 자리에 섬 → 바로 열림 (realOpen)
    ///   - 닫힘: 열린 뒤 3초 넘어 새로 온 그물이 문틀을 55% 넘게 덮거나, 문 면(평면)이 문 자리를 가로막고 그물도 40% 넘게 덮을 때,
    ///     그 상태가 1초 이어지고, 방금 열린 뒤 몇 초(openHold)가 지났고, 내가 문 자리에 서 있지 않을 때만.
    ///     (예전엔 문을 연 뒤에도 늦게 오는 그물·평면이 아직 닫힌 문짝을 담고 있어 닫힘으로 되돌렸다가 다시 열림을 반복 →
    ///      문을 연 뒤 열린 공간과 닫힌 문이 번갈아 보였고, 같은 테마에서도 문짝이 나타났다 사라졌음)
    /// ② 열쇠 (doorOpen, 다른 세계 사이만): 열쇠를 누르거나, 문 자리에 들어서거나, 1초 넘게 보이던 닫힌 실제 문을 곁에서 열면 열림.
    ///   건너가면(12cm 넘게) 또는 같은 쪽으로 1.2m 넘게 멀어지면 다시 잠김.
    ///
    /// 보이는 모양 (위에서부터 먼저 맞는 것):
    ///   닫힌 실제 문이 1m 안 → 실제 문짝(손잡이 문) / 같은 세계 → 늘 뚫린 통로 / 여는 중 → 열쇠 움직임 /
    ///   열쇠로 열림 → 뚫린 통로 / 1m 안(문 밖, 막 지나오지 않음) → 열쇠 문 / 그 밖 → 지금 방의 벽
    static let doorReach: Float = 1.0

    private enum DoorLook { case leaf, open, opening, key, wall }

    /// 같은 세계 (장소·날씨·시간·표시 방식이 모두 같음) — 같은 세계 무리로 묶이고, 사이 문은 늘 뚫린 통로
    static func sameTheme(_ a: RoomRec, _ b: RoomRec) -> Bool {
        a.place == b.place && a.weather == b.weather && a.time == b.time && a.lookMode == b.lookMode
    }

    /// 실제 문이 열렸다고 알게 됨. hold 초 동안은 다시 닫힘으로 치지 않음 (늦게 오는 그물·평면 무시)
    private func realOpen(_ i: Int, hold: Float) {
        if realClosed.contains(i) {
            realClosed.remove(i)
            justOpened[i] = t - (closedAt[i] ?? t)          // 얼마 동안 닫혀 있었는지 (곁에서 1초 넘게 보던 문을 열면 열쇠 없이 열린 것으로)
        }
        closedAt[i] = nil
        closeSince[i] = nil
        coverPeak[i] = nil
        cover[i] = 0                     // 예전 막힘 비율은 버림 — 새 그물이 오기 전엔 문 면(평면)만으로 다시 닫지 않게
        coverFresh[i] = 0
        openedAt[i] = t
        viewT[i] = 0
        openHold[i] = max(openHold[i] ?? 0, t + hold)
    }

    private func realClose(_ i: Int) {
        guard !realClosed.contains(i) else { return }
        realClosed.insert(i)
        closedAt[i] = t
        closeSince[i] = nil
    }

    /// 열림을 알았을 때 그 문의 그물 기록을 '열림 판단'에서 빼 둠 (지우지는 않음 — 그 덩어리가 새로 오면 그때 버림).
    /// 예전엔 지웠음 → 잘못 열림으로 안 경우(문 자리에 선 것처럼 잡힘 등) 문이 그대로라 그물이 다시 오지 않으면 닫힘으로 돌아올 근거가 없었음
    private func shelveHits(_ i: Int) {
        for (k, e) in realHits[i] ?? [:] { heldHits[i, default: [:]][k] = e }
        realHits[i] = [:]
        hitsAt[i] = [:]
    }

    /// 지금 그물 전체(새로 온 것 + 치워 둔 것 중 아직 새로 오지 않은 덩어리)가 문틀 안쪽을 덮은 비율
    private func coverNow(_ i: Int, _ ds: DoorSeg) -> Float {
        var all = Set<Int>()
        for (_, e) in realHits[i] ?? [:] { all.formUnion(e) }
        for (k, e) in heldHits[i] ?? [:] where realHits[i]?[k] == nil { all.formUnion(e) }
        let cols = max(1, Int(((ds.width - 0.16) / 0.1).rounded(.up)))
        return Float(all.count) / Float(cols * 16)
    }

    /// 닫힘 후보인지:
    /// - 열린 뒤 새로 온 그물이 문틀을 55% 넘게 덮음
    /// - 3초 안에 문 면이 가로막았고 그물도 45% 넘게 덮음(그물이 아직 없으면 평면만으로) — 열림 기준(45% 밑)과 겹치지 않게 (예전 40%: 40~45%에서 닫힘·열림이 번갈아 남)
    /// - 열린 뒤 3초 넘어 곁에서 문 자리를 2.5초 넘게 바라봤는데도 지금 그물 전체가 55% 넘게 덮음:
    ///   정말 열렸다면 바라보는 동안 비전프로가 그물을 고쳐 보냄. 그대로라면 문은 닫혀 있는 것 (잘못 열림으로 안 것을 되돌림)
    private func closingEvidence(_ i: Int, _ ds: DoorSeg) -> Bool {
        if (coverFresh[i] ?? 0) > 0.55 { return true }
        // 문 면(평면)이 지금 문 자리를 가로막고 있고(마지막 열림 뒤에 가로막은 것을 봄), 그물이 '문 자리가 비었다'고 하지 않으면 닫힘.
        // 예전엔 '3초 안에 평면이 갱신됨 + 그물 45%'여야 해서: 가만히 있는 닫힌 문은 평면이 갱신되지 않고, 문짝 그물은 구멍이 많아
        // 닫힘을 끝내 몰랐음 → 다른 테마 사이 닫힌 문에 열쇠 문이 나왔고, 열쇠로 연 뒤에야 닫힘을 알아 바로 현실 원이 떴음
        if planeAcrossNow(i) && !meshSaysOpen(i) { return true }
        if (viewT[i] ?? 0) > 2.5 && coverNow(i, ds) > 0.55 { return true }
        return false
    }

    /// 문으로 분류된 평면이 지금 문 자리를 가로막고 있음 (마지막 열림 1초 뒤 넘어서 가로막은 것을 봤을 때만 — 열기 전의 평면 기록은 안 셈)
    private func planeAcrossNow(_ i: Int) -> Bool {
        guard let pa = planeAcrossAt[i], pa > (openedAt[i] ?? -100) + 1 else { return false }
        // 이번 탐험에서 한 번이라도 열린 문은 평면이 3초 안에 새로 가로막아야 (열린 뒤 남아 있는 예전 평면으로 다시 닫지 않게 —
        // 문을 건너온 뒤 닫힘↔열림이 오갔음). 한 번도 안 열린 문은 가만있는 평면도 믿음 (닫힌 문은 평면이 거의 갱신되지 않음)
        if openedAt[i] != nil && (t - pa) > 3 { return false }
        return doorPlanes.values.contains { $0.0 == i && $0.1 }
    }

    /// 그물이 문 자리를 보고 '비었다'고 함 (그 문을 지나는 그물 기록이 있고 막힌 비율 30% 밑)
    private func meshSaysOpen(_ i: Int) -> Bool {
        guard let m = realHits[i], !m.isEmpty else { return false }
        return (cover[i] ?? 0) < 0.3
    }

    /// hs: 눈(기기) 자리 — 시선 판정용, bs: 몸(목 뒤) 자리 — 문까지 거리·문 안에 섰는지·어느 쪽인지 판정용.
    /// (눈 자리로 판정하면 돌아서거나 고개만 숙여도 눈이 10~15cm 움직여 '문 자리 안'으로 잘못 알았음)
    private func updateDoors(_ dt: Float, _ hs: SIMD3<Float>, _ bs: SIMD3<Float>, _ fs: SIMD3<Float>, _ L: Layout) {
        guard let d = data else { return }
        let p = L.plane(bs.x, bs.z)
        let pe = L.plane(hs.x, hs.z)
        var look = SIMD2<Float>(simd_dot(SIMD2<Float>(fs.x, fs.z), L.ex), simd_dot(SIMD2<Float>(fs.x, fs.z), L.ez))
        look = simd_length(look) > 0.1 ? simd_normalize(look) : .zero
        let breath = 0.5 + 0.5 * sin(t * 2.4)
        var urgent = false
        var solid = Set<Int>()
        var leaf: (Int, Float)? = nil
        var anyLeaf = false
        var opened = Set<Int>()
        for (i, ds) in L.doors.enumerated() {
            var same = ds.single
            if !same, let ra = d.rec.room(ds.roomA), let rb = d.rec.room(ds.roomB) { same = Self.sameTheme(ra, rb) }
            // ── 곁에 있는지 (1m 안, 1.2m 밖으로 나가야 멀어짐)
            let dist = ds.dist(p)
            if dist < Self.doorReach {
                if !nearDoors.contains(i) { nearAt[i] = t }
                nearDoors.insert(i)
            } else if dist > Self.doorReach + 0.2 { nearDoors.remove(i) }
            let near = nearDoors.contains(i)
            let inside = ds.inside(p)
            let side = ds.side(p)
            let here = side >= 0 ? ds.roomA : ds.roomB
            if !inside { lastSide[i] = side }

            // ── ① 실제 문
            // 문 자리 한가운데 = 실제 문은 열려 있음 (닫힌 문 자리엔 설 수 없음). 몸(목 뒤)이 벽 두께 안 깊숙이(앞뒤 2cm 안쪽) 들어서야 —
            // 예전엔 벽 면 5cm 밖까지 쳐서, 닫힌 문 바로 앞에서 고개를 숙이거나 스캔 오차가 조금만 있어도 '문 자리에 섬 → 열림'이 되어
            // 같은 테마에서 닫힌 문과 열린 공간이 오갔음. 얇은 벽(10cm 밑)은 문 면 앞뒤 3cm 안
            let thick = abs(ds.pA - ds.pB)
            let standing = ds.zone(p, margin: thick >= 0.1 ? -0.02 : (0.1 - thick) / 2 - 0.02, side: -0.1)
            if standing { realOpen(i, hold: 2) }
            // 열린 뒤 3초 넘어 곁(1m)에서 문 자리를 바라본 시간 (지금 그물이 정말 열린 모양으로 바뀌었는지 볼 수 있었던 시간)
            if !realClosed.contains(i) && near && t - (openedAt[i] ?? -100) > 3 && gazeHitsDoor(ds, pe, fs, headY: hs.y - L.floorY, L) {
                viewT[i, default: 0] += dt
            }
            if closingEvidence(i, ds) && !realClosed.contains(i) {
                if closeSince[i] == nil { closeSince[i] = t }
                if let c0 = closeSince[i], t - c0 > 1.0, t > (openHold[i] ?? 0), !standing { realClose(i) }
            } else {
                closeSince[i] = nil
            }
            // 통창·유리문(방 구성에서 표시): 유리는 그물·평면에 잡히지 않아 열림·닫힘을 알 수 없음 → 문 자리에 들어서 있을 때 말고는
            // 테마가 같든 다르든 늘 닫힌 실제 문으로 (다가가 문 쪽을 보면 현실 원으로 실제 문을 보게)
            let real = realClosed.contains(i) || (ds.glass && !standing && !inside)

            // ── ② 열쇠 (다른 세계 사이만)
            if same {
                doorOpen.remove(i)
            } else {
                // (방금 건너온 문은 아님: 건너온 뒤 닫힘↔열림 판정이 한 번 오가면 '곁에서 연 문'으로 쳐서, 돌아봐도 문이 생기지 않고
                //  1m 밖으로 나갈 때까지 열린 채 반대편이 보였음)
                if let dur = justOpened[i], near, dur > 1.0, !doorOpen.contains(i), openProg[i] == nil, !passed.contains(i), t - (passedAt[i] ?? -100) > 8 {
                    doorOpen.insert(i); doorSide[i] = lastSide[i] ?? side          // 곁에서 보던 닫힌 실제 문을 열었음 → 열쇠 없이 열린 공간
                }
                if inside {
                    if !doorOpen.contains(i) && openProg[i] == nil { doorOpen.insert(i); doorSide[i] = lastSide[i] ?? side }
                } else if doorOpen.contains(i) {
                    let crossed = (doorSide[i] ?? side) * side < 0 && abs(side) > 0.12      // 12cm 넘게 건너가야 (문턱에서 오락가락하지 않게)
                    if crossed {
                        doorOpen.remove(i)
                        doorShow[i] = 0
                        passed.insert(i)
                        passedAt[i] = t
                        openHold[i] = max(openHold[i] ?? 0, t + 6)          // 방금 지나온 문은 6초 동안 '닫힘'으로 바뀌지 않음
                    } else if !near {
                        doorOpen.remove(i)
                    }
                }
            }
            justOpened[i] = nil
            if passed.contains(i) {
                let to = ds.mid - p
                let facing = simd_length(to) > 0.05 && simd_dot(simd_normalize(to), look) > 0.8
                if !near || facing { passed.remove(i) }
            }

            // ── 열쇠 움직임 (1.1초): 열쇠가 구멍으로 → 돌고 → 문짝이 양옆 벽 속으로
            var prog = openProg[i]
            if var pr = prog {
                let before = pr
                pr += dt / 1.1
                if before < 0.4 && pr >= 0.4, let v = worlds[animRoom[i] ?? ds.roomA]?.doorView[i], let par = v.root.parent {
                    Sfx.play("door_open", in: par, at: v.root.position + v.root.orientation.act([0, 1.0, 0.1]), gain: -8)
                }
                if pr >= 1 {
                    openProg[i] = nil
                    prog = nil
                    doorOpen.insert(i)
                    doorShow[i] = 0
                } else {
                    openProg[i] = pr
                    prog = pr
                }
            }

            // ── 보이는 모양 하나로
            // 열쇠 문은 다가온 뒤 그 문 자리를 새로 본 기록(그물·평면)이 있어야 — 닫힌 문을 아직 못 알아본 채로 열쇠가 먼저 나오지 않게
            // (새 기록이 2.5초 안 오면 띄움. 기다리는 동안은 문 자리 그물을 자주 다시 봄)
            let fresh = (doorSeenAt[i] ?? -100) > (nearAt[i] ?? 0) - 0.3 || t - (nearAt[i] ?? 0) > 2.5
            let shape: DoorLook
            if real && near { shape = .leaf }
            else if same { shape = .open }
            else if prog != nil { shape = .opening }
            else if doorOpen.contains(i) { shape = .open }
            // 닫힘 증거가 들어와 굳히는 중(1초)이면 열쇠 문을 띄우지 않음 (곧 실제 문짝이 될 문에 열쇠 문이 잠깐 번쩍이지 않게)
            else if near && !inside && !passed.contains(i) && fresh && closeSince[i] == nil { shape = .key }
            else { shape = .wall }
            if !same && near && !inside && !real && !fresh && !doorOpen.contains(i) && prog == nil { urgent = true }

            let panelsOn = shape == .wall || shape == .key || (shape == .opening && (prog ?? 1) < 0.4)
            if !panelsOn && shape != .leaf { opened.insert(i) }
            for rid in [ds.roomA, ds.roomB] {
                for e in worlds[rid]?.doorPanels[i] ?? [] where e.isEnabled != panelsOn { e.isEnabled = panelsOn }
            }
            let leafOn = shape == .leaf
            if let lf = worlds[ds.roomA]?.doorLeaf[i], lf.isEnabled != leafOn { lf.isEnabled = leafOn }
            if leafOn {
                urgent = true
                anyLeaf = true
                // 현실 원은 그 닫힌 문을 '바라볼 때'만 — 시선(3D)이 문짝 자리(양옆 35cm 여유, 바닥 5cm~2.3m)에 닿는지로 봄.
                // 문짝을 한 번 보면 0.7초 동안은 시선이 잠깐 벗어나도 유지(깜빡이지 않게). 바닥을 보면 시선이 문보다 바닥에 먼저 닿아 켜지지 않음
                if gazeHitsDoor(ds, pe, fs, headY: hs.y - L.floorY, L) { leafLookAt[i] = t }
                let facing = t - (leafLookAt[i] ?? -100) < 0.7
                if facing && (leaf == nil || dist < leaf!.1) { leaf = (i, dist) }
            }
            if panelsOn || leafOn { solid.insert(i) }

            // 열쇠 문 (서 있는 쪽 방에만, 여는 중이면 연 쪽 방)
            let want: Float = shape == .key || shape == .opening ? 1 : 0
            var sh = doorShow[i] ?? 0
            sh += (want - sh) * min(1, dt * 4)
            if abs(sh - want) < 0.01 { sh = want }
            if prog != nil { sh = 1 }
            doorShow[i] = sh
            let showRoom = prog != nil ? (animRoom[i] ?? here) : here
            if want == 1 && (lastWant[i] ?? 0) == 0 && prog == nil, let v = worlds[showRoom]?.doorView[i], let par = v.root.parent {
                Sfx.play("key_appear", in: par, at: v.root.position + v.root.orientation.act([0, DoorView.keyY, DoorView.keyZ]), gain: -6)
            }
            lastWant[i] = want
            for rid in [ds.roomA, ds.roomB] {
                guard let v = worlds[rid]?.doorView[i] else { continue }
                let o: Float = rid == showRoom ? sh : 0
                if v.root.isEnabled != (o > 0.02) { v.root.isEnabled = o > 0.02 }
                guard v.root.isEnabled else { continue }
                v.root.setOpacity(o)
                let gm = RoomWorld.gold(rough: 0.22, glow: 0.2 + 2.2 * breath, mono: worlds[rid]?.look == .mono)      // 흑백 방이면 은빛 열쇠
                for e in v.parts { e.model?.materials = [gm] }
                Self.pose(v, prog: rid == showRoom ? prog : nil, t: t)
            }
        }
        doorUrgent = urgent
        solidDoors = solid
        openDoorSet = opened
        updateRoomVisibility()
        leafDoor = leaf?.0
        if !anyLeaf { peekDismissed = nil }        // 닫힌 문에서 벗어나면 더블탭으로 닫은 것도 풂
    }

    /// 시선(머리 → 앞, 3D)이 문 자리 상자(문 폭 양옆 35cm·앞뒤 15cm 여유)에 들어가는 곳의 높이가 바닥 5cm~2.3m 사이인지.
    /// p: 머리 평면 좌표, fs: 앞 방향(저장 좌표), headY: 바닥에서 머리까지
    private func gazeHitsDoor(_ ds: DoorSeg, _ p: SIMD2<Float>, _ fs: SIMD3<Float>, headY: Float, _ L: Layout) -> Bool {
        guard simd_length(fs) > 0.01 else { return false }
        let f = simd_normalize(fs)
        let h = SIMD2<Float>(simd_dot(f.xz, L.ex), simd_dot(f.xz, L.ez))     // 평면 방향 (길이 = cos 숙인 각)
        let mw: Float = 0.35, md: Float = 0.15
        var lo = ds.lo, hi = ds.hi
        if ds.alongU { lo += SIMD2<Float>(-md, -mw); hi += SIMD2<Float>(md, mw) } else { lo += SIMD2<Float>(-mw, -md); hi += SIMD2<Float>(mw, md) }
        var t0: Float = 0, t1: Float = 6
        for k in 0..<2 {
            let o = k == 0 ? p.x : p.y, d = k == 0 ? h.x : h.y
            let a = k == 0 ? lo.x : lo.y, b = k == 0 ? hi.x : hi.y
            if abs(d) < 1e-5 {
                if o < a || o > b { return false }
            } else {
                var ta = (a - o) / d, tb = (b - o) / d
                if ta > tb { swap(&ta, &tb) }
                t0 = max(t0, ta); t1 = min(t1, tb)
                if t0 > t1 { return false }
            }
        }
        // 상자 안을 지나는 동안 시선 높이가 문짝 높이에 걸치면 바라보는 것
        let y0 = headY + f.y * t0, y1 = headY + f.y * t1
        return max(y0, y1) > 0.05 && min(y0, y1) < 2.3
    }

    /// 문 모양 맞추기: prog nil = 닫혀서 열쇠가 떠 있음, 0~1 = 열쇠로 여는 중
    static func pose(_ v: DoorView, prog: Float?, t: Float) {
        func ease(_ x: Float) -> Float { let c = min(1, max(0, x)); return c * c * (3 - 2 * c) }
        v.left.position = [-v.hl, 0, 0]; v.right.position = [v.hl, 0, 0]
        guard let p = prog else {
            v.left.scale = [1, 1, 1]; v.right.scale = [1, 1, 1]
            v.keyRoot.position = [0, DoorView.keyY, DoorView.keyZ]
            v.keyRoot.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
            v.keyRoot.setOpacity(1)
            v.lock.setOpacity(1)
            v.key.position = [0, 0.012 * sin(t * 1.3), 0]
            v.key.orientation = simd_quatf(angle: 0.3 * sin(t * 0.7), axis: [0, 1, 0])
            return
        }
        v.key.position = .zero
        v.key.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
        let insertZ: Float = 0.045 + 0.075
        let a = ease(p / 0.25), b = ease((p - 0.25) / 0.15), c = ease((p - 0.4) / 0.6)
        v.keyRoot.position = [0, DoorView.keyY, DoorView.keyZ + (insertZ - DoorView.keyZ) * a]
        v.keyRoot.orientation = simd_quatf(angle: .pi / 2 * b, axis: [0, 0, 1]) * simd_quatf(angle: .pi / 2 * a, axis: [0, 1, 0])
        let fade = 1 - c
        v.keyRoot.setOpacity(fade)
        v.lock.setOpacity(fade)
        let k = max(0.001, 1 - c)
        v.left.scale = [k, 1, 1]; v.right.scale = [k, 1, 1]
    }

    /// 실제 문 그물: 그물 덩어리마다 가장 최근에 본 '문 자리를 가로막은 칸'(과 그 때)을 합쳐 문틀 안쪽을 덮은 비율로.
    /// - cover: 모든 기록 — 열림 판단 (40% 밑이거나, 한 덩어리가 보던 막힌 칸이 크게 줄면 바로 열림)
    /// - coverFresh: 마지막으로 열린 뒤 3초 넘어 새로 온 기록만 — 닫힘 판단 (늦게 오는 그물이 아직 닫힌 문짝을 담고 있어도 닫힘으로 되돌리지 않게)
    private func setDoorHits(_ id: UUID, _ hits: [Int: Set<Int>], touched seen: Set<Int>) {
        guard let L = layout else { return }
        var touched = seen.union(hits.keys)
        for (i, m) in realHits where m[id] != nil && !touched.contains(i) {
            realHits[i]?[id] = nil
            hitsAt[i]?[id] = nil
            touched.insert(i)
        }
        for (i, m) in heldHits where m[id] != nil && !seen.union(hits.keys).contains(i) { heldHits[i]?[id] = nil }
        for i in seen.union(hits.keys) {
            let nh = hits[i] ?? []
            let old = realHits[i]?[id] ?? []
            if old.count >= 6 && nh.count * 10 <= old.count * 7 {
                shelveHits(i)                                       // 문이 움직였음 → 다른 덩어리의 예전 기록은 열림 판단에 쓰지 않음
            }
            heldHits[i]?[id] = nil                                  // 이 덩어리는 지금 모양이 새로 왔음
            realHits[i, default: [:]][id] = nh
            hitsAt[i, default: [:]][id] = t
        }
        for i in touched where i < L.doors.count {
            doorSeenAt[i] = t
            var all = Set<Int>(), fresh = Set<Int>()
            let since = (openedAt[i] ?? -100) + 3
            for (k, e) in realHits[i] ?? [:] {
                all.formUnion(e)
                if (hitsAt[i]?[k] ?? -100) > since { fresh.formUnion(e) }
            }
            let cols = max(1, Int(((L.doors[i].width - 0.16) / 0.1).rounded(.up)))
            let cv = Float(all.count) / Float(cols * 16)
            cover[i] = cv
            coverFresh[i] = Float(fresh.count) / Float(cols * 16)
            // 닫혀 있던 문의 막힌 비율이 가장 많던 때보다 15% 넘게 줄면(문짝이 움직이기 시작) 바로 열림
            if realClosed.contains(i) { coverPeak[i] = max(coverPeak[i] ?? 0, cv) }
            let dropped = realClosed.contains(i) && (coverPeak[i] ?? 0) > 0.55 && cv < (coverPeak[i] ?? 0) - 0.15
            // 문 면이 지금 가로막고 있으면(평면이 닫힘을 말함) 그물 막힘이 낮다는 것만으로는 열지 않음 — 문짝 그물은 구멍이 많아
            // 닫혀 있어도 45% 밑일 수 있음(닫힘↔열림이 번갈아 났음). 그때는 그물이 줄어듦(닫혀 있는 동안 가장 많던 때보다 15% 넘게)·거의 빔(15% 밑)일 때만
            let lowOpen = planeAcrossNow(i) ? (cv < 0.15 || ((coverPeak[i] ?? 0) > 0.3 && cv < (coverPeak[i] ?? 0) - 0.15)) : cv < 0.45
            if realClosed.contains(i) && (lowOpen || dropped) {
                realOpen(i, hold: 5)
                shelveHits(i)
                coverFresh[i] = 0
            }
        }
    }

    /// 손으로 실제 문 열기 알아채기 (닫혀 있다고 아는 문만):
    /// - 손(손바닥 가운데)이 문짝 15cm 안, 손잡이 자리(높이 0.7~1.35m, 한짝 문은 가운데 빼고)에 0.2초 넘게 닿았다가
    /// - 문짝에서 20cm 넘게 멀어지며 당기거나(손잡이 높이 그대로, 문 폭 안), 문짝 너머 반대편으로 8cm 넘게 밀고 들어가면 → 바로 열림.
    /// 잘못 알아챈 경우(손만 대고 뗌)는 3.5초 뒤 그물·평면이 다시 닫힘으로 돌려놓음 (그물은 문이 다 열리고도 몇 초 늦게 따라오므로 그 전엔 닫지 않음)
    /// 탭 보조: 시스템 탭이 가끔 안 들어와서, 손 추적으로 '빠르게 집었다 놓는' 손짓도 탭으로 받음.
    /// 손을 편히 둘 때 손가락이 붙어 있는 것과 구별하려고: 2.5cm 넘게 벌어져 있다가 0.3초 안에 0.9cm 안으로 집고, 0.5초 안에 다시 2cm 넘게 벌림.
    /// 같은 손짓을 시스템도 알아채면 한 번만 — 놓기 하나하나를 시스템 탭과 짝지음 (claimSystemTap·tapTick)
    private func pinchWatch(_ a: HandAnchor?, _ i: Int) {
        guard let a, a.isTracked, let sk = a.handSkeleton else { pinchClosed[i] = false; return }
        let tj = sk.joint(.thumbTip), ij = sk.joint(.indexFingerTip)
        guard tj.isTracked, ij.isTracked else { return }
        let tp = simd_make_float3((a.originFromAnchorTransform * tj.anchorFromJointTransform).columns.3)
        let ip = simd_make_float3((a.originFromAnchorTransform * ij.anchorFromJointTransform).columns.3)
        let d = simd_distance(tp, ip)
        if !pinchClosed[i] {
            if d > 0.025 { pinchOpenAt[i] = t }
            if d < 0.009 && t - pinchOpenAt[i] < 0.3 { pinchClosed[i] = true; pinchCloseAt[i] = t }
        } else if d > 0.02 {
            pinchClosed[i] = false
            // 눈앞(시선 60도 안, 허리보다 위)에서 한 손짓만 — 무릎·소파 위에 둔 손가락이 저절로 붙었다 떨어지는 것은 탭이 아님
            let toH = tp - head
            let g = simd_length(fwd) > 0.01 ? simd_normalize(fwd) : SIMD3<Float>(0, 0, -1)
            let inView = simd_length(toH) > 0.05 && simd_dot(simd_normalize(toH), g) > 0.5 && tp.y > head.y - 0.7
            // 놓은 손짓 하나 = 기록 하나. 바로 전(0.2초 안)에 시스템 탭이 왔으면 그 탭과 같은 손짓
            var st = 0
            if let k = sysTaps.lastIndex(where: { t - $0 < 0.3 }) { sysTaps.remove(at: k); st = 1 }
            pinchRel.append((t: t, ok: inView && t - pinchCloseAt[i] < 0.5, state: st))
        }
    }

    private func handDoors(_ L: Layout, _ f: Fit) {
        guard let hp = hands, hp.state == .running else { return }
        let la = hp.latestAnchors
        var pts: [SIMD3<Float>] = []
        for a in [la.leftHand, la.rightHand] {
            guard let a, a.isTracked, let sk = a.handSkeleton else { continue }
            let j = sk.joint(.middleFingerKnuckle)
            guard j.isTracked else { continue }
            let w = a.originFromAnchorTransform * j.anchorFromJointTransform
            pts.append(f.toSaved(simd_make_float3(w.columns.3)))
        }
        handPts = pts
        pinchWatch(la.leftHand, 0)
        pinchWatch(la.rightHand, 1)
        for (i, ds) in L.doors.enumerated() {
            guard realClosed.contains(i) else { grip[i] = nil; continue }
            let lo: Float = min(ds.pA, ds.pB), hi: Float = max(ds.pA, ds.pB)
            var touch: (Float, Float)? = nil          // (문짝까지 거리, 쪽)
            var far: Float = 0                         // 닿았던 쪽에서 문짝까지 가장 먼 손
            var through = false
            for sp in pts {
                let pp = L.plane(sp.x, sp.z)
                let hgt: Float = sp.y - L.floorY
                let a: Float = ds.alongU ? pp.x : pp.y
                let s: Float = ds.alongU ? pp.y : pp.x
                guard hgt > 0.7, hgt < 1.35, s > ds.s0 - 0.1, s < ds.s1 + 0.1 else { continue }
                // 손잡이 자리만: 한짝 문은 가운데 40%를 뺌 (문 앞에서 메뉴·열쇠를 누르는 손짓을 문 여는 걸로 착각하지 않게)
                let wd: Float = ds.s1 - ds.s0
                if wd <= 1.2 && abs(s - (ds.s0 + ds.s1) / 2) < wd * 0.2 { continue }
                let side: Float = a < (lo + hi) / 2 ? -1 : 1
                let gap: Float = a < lo ? lo - a : (a > hi ? a - hi : 0)
                if gap < 0.15 && (touch == nil || gap < touch!.0) { touch = (gap, side) }
                if let g = grip[i] {
                    if side == g.3 { far = max(far, gap) }
                    else if gap > 0.08 { through = true }          // 닫힌 문을 손이 뚫고 지나갈 수는 없음 → 밀어서 열었음
                }
            }
            if var g = grip[i] {
                if let tc = touch, tc.1 == g.3 { g.0 = min(g.0, tc.0); g.2 = t }
                let held = g.2 - g.1 >= 0.2
                if held && (through || (g.0 < 0.1 && far - g.0 > 0.2 && t - g.2 < 1.5)) {
                    realOpen(i, hold: 6)
                    shelveHits(i)
                    coverFresh[i] = 0
                    grip[i] = nil
                } else if t - g.2 > 1.5 {
                    grip[i] = nil
                } else {
                    grip[i] = g
                }
            } else if let tc = touch {
                grip[i] = (tc.0, t, t, tc.1)
            }
        }
    }

    /// 바라보는 방향에 있는 반려동물을 톡 (가장 가운데에 가까운 아이). 톡했으면 true
    private func pokeGazedPet(_ dir: SIMD3<Float>) -> Bool {
        var best: Float = cos(8 * Float.pi / 180)
        var pick = 0
        let pets: [(Entity?, Int, Float)] = [(cat?.root, 1, 0.18), (dog?.root, 2, 0.24)]
        for (r, k, up) in pets {
            guard let r, r.isEnabledInHierarchy else { continue }
            let c = r.position(relativeTo: nil) + SIMD3<Float>(0, up, 0)
            let d = simd_distance(c, head)
            guard d > 0.1, d < 7 else { continue }
            // 탭한 방향이 몸에서 35cm 안으로 지날 때만 (멀리 있는 아이는 8도가 70cm 넘게 넓어져, 그쪽을 보며 메뉴판을 띄우려던 탭을 가로챘음)
            let along = simd_dot(c - head, dir)
            guard simd_length((c - head) - dir * along) < 0.35 else { continue }
            let cs = simd_dot(simd_normalize(c - head), dir)
            if cs > best { best = cs; pick = k }
        }
        if pick == 1 { cat?.poke(); return true }
        if pick == 2 { dog?.poke(); return true }
        return false
    }

    // MARK: 가구 맞추기
    func attachFurn(_ e: Entity) {
        furnPanel = e
        e.isEnabled = false
        root.addChild(e)
        makeBar("furn")
    }

    func startFurn() {
        lastUITap = t
        guard ready, vox != nil, layout != nil, !furnMode else { return }
        FurnTag.registerComponent()
        hudMenu = false; themeOpen = false; hudUntil = 0
        closeDocent()
        if starPick != nil { closeStars() }
        furnMode = true
        furnSel = nil
        furnUndo = []
        furnCanUndo = false
        if furnRoot.parent == nil { root.addChild(furnRoot) }
        furnRoot.isEnabled = true
        furnRoot.transform = spaceRoot.transform
        rebuildFurnView(preview: true)
        if let p = furnPanel {
            var fw = fwd; fw.y = 0
            fw = simd_length(fw) > 0.01 ? simd_normalize(fw) : SIMD3<Float>(0, 0, -1)
            p.position = head + fw * 0.7 - SIMD3<Float>(0, 0.28, 0)
            faceDocent(p)
            p.isEnabled = true
        }
    }

    func endFurn() {
        lastUITap = t
        guard furnMode else { return }
        if furnSel != nil { commitFurnEdit() }
        applyFurn()
        furnMode = false
        furnConfirm = nil
        furnSel = nil
        furnPanel?.isEnabled = false
        furnRoot.isEnabled = false
        FurnStore.save(spaceId, furnEdits)
    }

    /// 가구 맞추기 중(공간이 다 흐려진 뒤): 가구 블록·반려동물·카페 차림을 끔.
    /// 흐림(투명도 0)으로만 숨기면 그리지는 않아도 깊이는 써서, 그 뒤·속에 놓인 고칠 상자가 곳곳에 투명하게 지워져 보였음.
    /// 소리를 내는 것(세계·방 안·모닥불)은 끄지 않음 (끄면 소리가 멈춘 채 돌아오지 않을 수 있음) — 그것들은 포털 너머이거나 가구 위가 아님
    private func furnHideScene(_ hide: Bool) {
        guard hide != furnHidden else { return }
        furnHidden = hide
        var list: [Entity] = []
        if let v = vox { list.append(v.root) }
        if let c = cat { list.append(c.root); list.append(c.ballRoot) }
        if let g = dog { list.append(g.root); list.append(g.propRoot) }
        for (_, c) in cafeSets { list.append(c.1.root) }
        if hide {
            for e in list where e.isEnabled { e.isEnabled = false; furnHiddenList.append(e) }
        } else {
            for e in furnHiddenList { e.isEnabled = true }
            furnHiddenList = []
            updateRoomVisibility()                                   // 카페 차림은 보이는 방 기준으로 다시
        }
    }

    /// 매 프레임: 상자·미리보기를 공간 자리에 맞추고, 끄는 동안 모아 둔 바뀜을 0.15초마다 블록에 적용
    private func furnTick() {
        guard furnMode else { return }
        furnRoot.transform = spaceRoot.transform
        if let at = furnApplyAt, t >= at { furnApplyAt = nil; vox?.setEdits(furnEdits) }
        updateFurnGuide()
    }

    /// 고치는 상자의 네 옆면에서 1.5m 안 가장 가까운 가구·벽까지 거리(줄 + cm 글자), 다른 가구·벽과 겹치면 상자를 빨갛게 + '겹침'.
    /// 가구 = 알아낸 기둥(비운 곳 빼고) + 다른 넣은 상자. 바닥 평면에서 잼 (높이와 상관없이 놓을 자리가 맞닿는지)
    private func updateFurnGuide() {
        guard furnMode, let i = furnSel, i < furnEdits.adds.count, let L = layout, let v = vox else {
            if guideBox != nil || !furnGuide.children.isEmpty { furnGuide.children.removeAll(); guideBox = nil }
            return
        }
        let b = furnEdits.adds[i]
        guard b != guideBox, t - guideAt > 0.1 else { return }
        guideBox = b
        guideAt = t
        if furnGuide.parent == nil { furnRoot.addChild(furnGuide) }
        furnGuide.children.removeAll()
        let others = furnEdits.adds.enumerated().filter { $0.offset != i }.map(\.element)
        /// 0 = 빈 곳, 1 = 가구, 2 = 벽(걸을 수 없는 곳)
        func what(_ p: SIMD2<Float>) -> Int {
            if !L.walkable(p) { return 2 }
            if v.scanH(Int((p.x / Vox.size).rounded(.down)), Int((p.y / Vox.size).rounded(.down))) > 0.05 { return 1 }
            for o in others where abs(p.x - o.cx) < o.w / 2 && abs(p.y - o.cz) < o.d / 2 { return 1 }
            return 0
        }
        // 겹침: 상자 안쪽(가장자리 3cm 안) 5cm 간격
        var overlap = false
        var x = b.cx - b.w / 2 + 0.03
        outer: while x <= b.cx + b.w / 2 - 0.03 {
            var z = b.cz - b.d / 2 + 0.03
            while z <= b.cz + b.d / 2 - 0.03 {
                if what(SIMD2<Float>(x, z)) != 0 { overlap = true; break outer }
                z += 0.05
            }
            x += 0.05
        }
        let y = L.floorY + max(0.04, min(b.h, 1.2) - 0.03)
        func world(_ p: SIMD2<Float>) -> SIMD3<Float> { let f = L.flat(p); return SIMD3<Float>(f.x, y, f.y) }
        // 네 옆면: (바깥 방향, 면 가운데, 면을 따라가는 방향, 면 반폭)
        let sides: [(SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, Float)] = [
            (SIMD2<Float>(1, 0), SIMD2<Float>(b.cx + b.w / 2, b.cz), SIMD2<Float>(0, 1), b.d / 2),
            (SIMD2<Float>(-1, 0), SIMD2<Float>(b.cx - b.w / 2, b.cz), SIMD2<Float>(0, 1), b.d / 2),
            (SIMD2<Float>(0, 1), SIMD2<Float>(b.cx, b.cz + b.d / 2), SIMD2<Float>(1, 0), b.w / 2),
            (SIMD2<Float>(0, -1), SIMD2<Float>(b.cx, b.cz - b.d / 2), SIMD2<Float>(1, 0), b.w / 2)]
        for (n, c, tdir, half) in sides {
            let m = max(2, Int((2 * half / 0.1).rounded(.up)))
            let offs = (0...m).map { -half + 0.02 + (2 * half - 0.04) * Float($0) / Float(m) }
            var hit: (Float, Int, Float)? = nil              // (거리, 무엇, 면을 따라 닿은 자리)
            var d: Float = 0
            march: while d <= 1.5 {
                for o in offs {
                    let k = what(c + tdir * o + n * (d + 0.01))
                    if k != 0 { hit = (d, k, o); break march }
                }
                d += 0.02
            }
            guard let h = hit, h.0 > 0.01 || !overlap else { continue }
            let a = c + tdir * h.2, e = a + n * h.0
            if h.0 > 0.015 { addGuideLine(world(a), world(e)) }
            let cm = Int((h.0 * 100).rounded())
            let label = h.0 < 0.025 ? (h.1 == 2 ? "벽에 붙음" : "붙음") : (h.1 == 2 ? "벽 \(cm)cm" : "\(cm)cm")
            addGuideLabel(label, at: world(a + n * (h.0 / 2)) + SIMD3<Float>(0, 0.05, 0), warn: false)
        }
        if overlap {
            let f = L.flat(SIMD2<Float>(b.cx, b.cz))
            addGuideLabel("겹침", at: SIMD3<Float>(f.x, L.floorY + b.h + 0.1, f.y), warn: true)
        }
        if i < furnBoxes.count {
            let col = overlap ? UIColor(red: 1, green: 0.25, blue: 0.2, alpha: 1) : UIColor(red: 1, green: 0.85, blue: 0.2, alpha: 1)
            furnBoxes[i].model?.materials = [Self.furnMat(col, 0.55)]
        }
    }

    private func addGuideLine(_ a: SIMD3<Float>, _ b: SIMD3<Float>) {
        let len = simd_distance(a, b)
        guard len > 0.005 else { return }
        var m = UnlitMaterial(color: UIColor(red: 1, green: 1, blue: 1, alpha: 1))
        m.writesDepth = false
        let line = ModelEntity(mesh: .generateBox(width: len, height: 0.006, depth: 0.006), materials: [m])
        line.position = (a + b) / 2
        line.orientation = simd_quatf(from: SIMD3<Float>(1, 0, 0), to: (b - a) / len)
        furnGuide.addChild(line)
        for p in [a, b] {
            let dot = ModelEntity(mesh: .generateSphere(radius: 0.009), materials: [m])
            dot.position = p
            furnGuide.addChild(dot)
        }
    }

    private func addGuideLabel(_ s: String, at p: SIMD3<Float>, warn: Bool) {
        let mesh: MeshResource
        if let m = guideText[s] { mesh = m } else {
            let m = MeshResource.generateText(s, extrusionDepth: 0.001, font: .systemFont(ofSize: 0.032, weight: .semibold))
            guideText[s] = m
            mesh = m
        }
        let holder = Entity()
        holder.position = p
        holder.components.set(BillboardComponent())
        let ext = mesh.bounds.extents, ctr = mesh.bounds.center
        var tm = UnlitMaterial(color: .white)
        tm.blending = .transparent(opacity: .init(floatLiteral: 1))
        tm.writesDepth = false
        let text = ModelEntity(mesh: mesh, materials: [tm])
        text.position = SIMD3<Float>(-ctr.x, -ctr.y, 0.002)
        // 글자는 바탕 판 다음에 그림 (둘 다 깊이를 쓰지 않으므로 순서로)
        let sg = ModelSortGroup(depthPass: nil)
        text.components.set(ModelSortGroupComponent(group: sg, order: 1))
        var pm = UnlitMaterial(color: warn ? UIColor(red: 0.75, green: 0.1, blue: 0.08, alpha: 1) : UIColor(white: 0.08, alpha: 1))
        pm.blending = .transparent(opacity: .init(floatLiteral: 0.75))
        pm.writesDepth = false
        let plate = ModelEntity(mesh: .generatePlane(width: ext.x + 0.024, height: ext.y + 0.014, cornerRadius: 0.008), materials: [pm])
        plate.components.set(ModelSortGroupComponent(group: sg, order: 0))
        holder.addChild(plate)
        holder.addChild(text)
        furnGuide.addChild(holder)
    }

    /// 바뀐 가구를 블록(세계 쪽)에 적용하고 상자·미리보기를 다시 그림
    private func applyFurn(preview: Bool = true) {
        vox?.setEdits(furnEdits)
        rebuildFurnView(preview: preview)
        furnCanUndo = !furnUndo.isEmpty
    }

    private static func furnMat(_ c: UIColor, _ a: Float) -> UnlitMaterial {
        var m = UnlitMaterial(color: c)
        m.blending = .transparent(opacity: .init(floatLiteral: a))
        m.writesDepth = false
        return m
    }

    /// 상자 자리 (저장 좌표 가운데·방향): 평면 좌표의 가로축(ex)에 폭, 세로축에 깊이
    private func furnTransform(_ b: FurnBox, _ L: Layout) -> Transform {
        let c = L.flat(SIMD2<Float>(b.cx, b.cz))
        let ex3 = simd_normalize(SIMD3<Float>(L.ex.x, 0, L.ex.y))
        return Transform(scale: .one, rotation: simd_quatf(from: SIMD3<Float>(1, 0, 0), to: ex3), translation: SIMD3<Float>(c.x, L.floorY + b.h / 2, c.y))
    }

    private func rebuildFurnView(preview: Bool) {
        guard let L = layout else { return }
        if preview {
            furnPreview?.removeFromParent()
            furnPreview = nil
            if let m = vox?.previewMesh() {
                let e = ModelEntity(mesh: m, materials: [Self.furnMat(UIColor(red: 0.35, green: 0.85, blue: 1, alpha: 1), 0.3)])
                furnRoot.addChild(e)
                furnPreview = e
            }
        }
        for e in furnBoxes { e.removeFromParent() }
        furnBoxes = []
        for (i, b) in furnEdits.adds.enumerated() {
            let sel = i == furnSel
            let e = ModelEntity(mesh: .generateBox(width: b.w, height: b.h, depth: b.d, cornerRadius: 0.01),
                                materials: [Self.furnMat(sel ? UIColor(red: 1, green: 0.85, blue: 0.2, alpha: 1) : UIColor(red: 1, green: 0.55, blue: 0.2, alpha: 1), sel ? 0.55 : 0.38)])
            e.transform = furnTransform(b, L)
            e.name = "furn-\(i)"
            e.components.set(FurnTag(index: i))
            e.components.set(InputTargetComponent())
            e.components.set(CollisionComponent(shapes: [.generateBox(width: b.w, height: max(0.05, b.h), depth: b.d)]))
            e.components.set(HoverEffectComponent())
            furnRoot.addChild(e)
            furnBoxes.append(e)
        }
        guideBox = nil                                      // 상자를 다시 만들었음 → 거리 표시·겹침 색을 다시
        guideAt = -9
    }

    /// 편집 시작: 고른 가구 하나만 고칠 수 있음 (완료·취소 전까지 다른 가구를 고르거나 끝낼 수 없음)
    private func beginFurnEdit(_ i: Int, before: FurnEdits, isNew: Bool) {
        furnBefore = before
        furnIsNew = isNew
        furnSel = i
        furnConfirm = nil
        rebuildFurnView(preview: false)
    }

    /// 판을 누른 탭 (알림판을 띄우지 않음 — 예전엔 판을 누를 때마다 방 이름 알림판이 떴음)
    func furnTouched() { lastUITap = t }

    func setFurnConfirm(_ c: String?) {
        lastUITap = t
        furnConfirm = c
    }

    /// 이 가구 완료: 편집 전 모습을 되돌리기에 쌓고 저장
    func commitFurnEdit() {
        lastUITap = t
        guard furnSel != nil else { return }
        if let b = furnBefore, b != furnEdits { furnUndo.append(b); if furnUndo.count > 40 { furnUndo.removeFirst() } }
        furnBefore = nil
        furnSel = nil
        furnConfirm = nil
        applyFurn()
        FurnStore.save(spaceId, furnEdits)
    }

    /// 취소: 이 가구를 고르기 전으로 (새로 놓은 가구는 없어지고, 상자로 바꾼 가구는 원래 블록으로)
    func cancelFurnEdit() {
        lastUITap = t
        guard furnSel != nil else { return }
        if let b = furnBefore { furnEdits = b }
        furnBefore = nil
        furnSel = nil
        furnConfirm = nil
        applyFurn()
        FurnStore.save(spaceId, furnEdits)
    }

    /// 가구 맞추기 중 탭.
    /// - 편집 중: 아무것도 고르지 않음 (완료·취소를 눌러야 다른 가구로) — 예전엔 보이는 대로 바로 골라져 엉뚱한 가구가 바뀌었음
    /// - 고르기: 상자 → 그 상자 편집 / 가구 블록 → 탭한 곳의 평평한 면만 상자로 바꿔 편집 / 빈 바닥 → 새 가구 편집.
    /// 탭한 곳은 머리에서 탭한 방향으로 나아가며 처음 만나는 가구 블록 또는 바닥
    private func furnTap(_ e: Entity, _ point: SIMD3<Float>?) {
        if t - lastUITap < 0.25 { return }
        guard furnSel == nil else { return }
        var cur: Entity? = e
        while let c = cur {
            if let tag = c.components[FurnTag.self] { beginFurnEdit(tag.index, before: furnEdits, isNew: false); return }
            if c === furnPanel || c === hud || c.components[GrabTag.self] != nil { return }      // 판·막대를 누른 탭
            cur = c.parent
        }
        guard e === tapCatcher else { return }      // 빈 곳(머리 둘레 탭 받는 상자)을 탭했을 때만 그 방향의 가구·바닥을 고름
        guard let p = point, let f = fit, let L = layout, let v = vox, simd_distance(p, head) > 0.05 else { return }
        let o = f.toSaved(head), d = f.dirToSaved(simd_normalize(p - head))
        var s: Float = 0.15
        while s < 6 {
            let q = o + d * s
            let pl = L.plane(q.x, q.z)
            let h = v.heightAt(pl)
            if h > 0 && q.y - L.floorY <= h + 0.02 {
                if let i = furnEdits.adds.firstIndex(where: { abs(pl.x - $0.cx) <= $0.w / 2 + 0.05 && abs(pl.y - $0.cz) <= $0.d / 2 + 0.05 }) {
                    beginFurnEdit(i, before: furnEdits, isNew: false)
                } else {
                    pieceToBox(pl)
                }
                return
            }
            if q.y <= L.floorY + 0.01 {
                if L.walkable(pl) { addFurn(at: pl) }
                return
            }
            s += 0.025
        }
    }

    /// 알아낸 가구에서 탭한 곳의 평평한 면(높이 차 10cm 안, 탭한 곳에서 1.2m 안) → 같은 자리·크기의 상자 (그 자리 블록은 비움)
    /// (예전엔 붙어 있는 덩어리 전체를 한 상자로 바꿔, 주방 가구처럼 이어진 가구가 통째로 큰 상자가 되었음)
    private func pieceToBox(_ pl: SIMD2<Float>) {
        guard let v = vox, let pc = v.pieceAt(pl) else { return }
        let before = furnEdits
        let (lo, hi, h) = pc
        furnEdits.erases.append(FurnRect(x0: lo.x - 0.05, z0: lo.y - 0.05, x1: hi.x + 0.05, z1: hi.y + 0.05))
        furnEdits.adds.append(FurnBox(cx: (lo.x + hi.x) / 2, cz: (lo.y + hi.y) / 2, w: max(0.1, hi.x - lo.x), d: max(0.1, hi.y - lo.y), h: max(0.1, h)))
        applyFurn()
        beginFurnEdit(furnEdits.adds.count - 1, before: before, isNew: false)
    }

    /// 빈 바닥에 새 가구 (50×50cm, 높이 45cm)
    private func addFurn(at pl: SIMD2<Float>) {
        let before = furnEdits
        furnEdits.adds.append(FurnBox(cx: pl.x, cz: pl.y, w: 0.5, d: 0.5, h: 0.45))
        applyFurn()
        beginFurnEdit(furnEdits.adds.count - 1, before: before, isNew: true)
    }

    /// 끌기·두 손 집기는 지금 편집 중인 가구에만
    private func editing(_ e: Entity) -> Int? {
        guard furnMode, let tag = e.components[FurnTag.self], let i = furnSel, tag.index == i, i < furnEdits.adds.count else { return nil }
        return i
    }

    func dragFurn(_ e: Entity, to p: SIMD3<Float>) {
        lastUITap = t
        guard let i = editing(e), let f = fit, let L = layout else { return }
        let q = f.toSaved(p)
        let pl = L.plane(q.x, q.z)
        if furnGrab == nil {
            let b = furnEdits.adds[i]
            furnGrab = SIMD2<Float>(b.cx, b.cz) - pl
        }
        guard let g = furnGrab else { return }
        furnEdits.adds[i].cx = pl.x + g.x
        furnEdits.adds[i].cz = pl.y + g.y
        if i < furnBoxes.count { furnBoxes[i].transform = furnTransform(furnEdits.adds[i], L) }
        if furnApplyAt == nil { furnApplyAt = t + 0.15 }
    }

    func dropFurn() {
        guard furnGrab != nil else { return }
        furnGrab = nil
        applyFurn(preview: false)
    }

    func scaleFurn(_ e: Entity, _ mag: Float) {
        lastUITap = t
        guard let i = editing(e), let L = layout else { return }
        if furnScale0 == nil { furnScale0 = furnEdits.adds[i] }
        guard let b0 = furnScale0 else { return }
        let k = max(0.2, min(5, mag))
        furnEdits.adds[i].w = max(0.1, min(4, b0.w * k))
        furnEdits.adds[i].d = max(0.1, min(4, b0.d * k))
        if i < furnBoxes.count {
            let b = furnEdits.adds[i]
            furnBoxes[i].transform = furnTransform(b, L)
            furnBoxes[i].scale = SIMD3<Float>(b.w / b0.w, 1, b.d / b0.d)
        }
        if furnApplyAt == nil { furnApplyAt = t + 0.15 }
    }

    func scaleFurnEnd() {
        guard furnScale0 != nil else { return }
        furnScale0 = nil
        applyFurn(preview: false)
    }

    func resizeFurn(dw: Float = 0, dd: Float = 0, dh: Float = 0) {
        lastUITap = t
        guard let i = furnSel, i < furnEdits.adds.count else { return }
        furnEdits.adds[i].w = max(0.1, min(4, furnEdits.adds[i].w + dw))
        furnEdits.adds[i].d = max(0.1, min(4, furnEdits.adds[i].d + dd))
        furnEdits.adds[i].h = max(0.1, min(2.1, furnEdits.adds[i].h + dh))
        applyFurn(preview: false)
    }

    func rotateFurn() {
        lastUITap = t
        guard let i = furnSel, i < furnEdits.adds.count else { return }
        let b = furnEdits.adds[i]
        furnEdits.adds[i].w = b.d
        furnEdits.adds[i].d = b.w
        applyFurn(preview: false)
    }

    /// 지우기 (판에서 한 번 더 확인한 뒤): 상자를 없앰 — 상자로 바꾼 가구 자리는 빈 곳으로 남음. 편집을 마침
    func deleteFurn() {
        lastUITap = t
        guard let i = furnSel, i < furnEdits.adds.count else { return }
        furnEdits.adds.remove(at: i)
        furnSel = 0                                         // commit 이 편집 중으로 보게
        commitFurnEdit()
    }

    func undoFurn() {
        lastUITap = t
        guard furnSel == nil, let last = furnUndo.popLast() else { return }
        furnEdits = last
        applyFurn()
        FurnStore.save(spaceId, furnEdits)
    }

    /// 처음 스캔대로 (판에서 한 번 더 확인한 뒤): 손으로 고친 것을 모두 지움 — 알아낸 가구 블록은 따로 저장되어 그대로 돌아옴
    func resetFurn() {
        lastUITap = t
        guard furnSel == nil else { return }
        furnUndo.append(furnEdits)
        furnEdits = FurnEdits()
        furnConfirm = nil
        applyFurn()
        FurnStore.save(spaceId, furnEdits)
    }

    // MARK: 탭
    /// 탭 하나: 열쇠·그림 버튼이면 바로 처리, 그 밖(탭 받는 상자)이면 0.4초 안에 또 오는지 기다림
    func tapped(_ e: Entity, at point: SIMD3<Float>? = nil, system: Bool = true, when: Float? = nil) {
        if system && !claimSystemTap() { return }
        let now = when ?? t                                         // 손 추적 탭은 실제로 손을 놓은 때 (싱글·더블 간격을 손짓 시각으로 잼)
        if furnMode { furnTap(e, point); return }
        var cur: Entity? = e
        while let c = cur {
            if c.name.hasPrefix("door-"), let i = Int(c.name.dropFirst(5)) {
                pendingTap = nil
                openKey(i)
                return
            }
            if c.name == "homecat" {
                pendingTap = nil
                cat?.poke()
                return
            }
            if c.name == "homedog" {
                pendingTap = nil
                dog?.poke()
                return
            }
            if c.name == "dogstick" {
                pendingTap = nil
                dog?.tapStick()
                return
            }
            if c.name == "catball" {
                pendingTap = nil
                if let f = fit { cat?.kickBall(from: f.toSaved(head)) }
                return
            }
            if c.name.hasPrefix("art-") {
                pendingTap = nil
                openDocent(c.name)
                return
            }
            cur = c.parent
        }
        if t - lastUITap < 0.25 { return }                         // 안내판을 누른 탭
        // 고양이·강아지: 그림 판이 작아 조금만 멀어도 시선이 판을 빗나가 탭이 안 먹혔음 →
        // 탭한 방향(머리 → 탭한 곳)이 아이 몸 가운데에서 8도 안이면 (7m 안) 그 아이를 톡
        if let p = point, simd_distance(p, head) > 0.05, pokeGazedPet(simd_normalize(p - head)) {
            pendingTap = nil
            return
        }
        // 밤하늘 별자리: 탭한 방향(머리 → 탭한 곳)에 별자리가 있으면 그 별자리를 이어 보여 주고 정보판을 띄움
        if let p = point, let st = stars, st.visible, let f = fit, simd_distance(p, head) > 0.05 {
            let dir = f.dirToSaved(simd_normalize(p - head))
            if let r = st.pick(dir, viewUp: f.dirToSaved(headUp)) {
                pendingTap = nil
                starPick = r.0
                placeStarCard(away: f.dirToCurrent(r.1), lowElev: r.2)
                return
            }
        }
        // 싱글·더블 가르기: 싱글탭은 0.45초 안에 두 번째 탭이 오지 않을 때 처리 (tapTick).
        // 예전엔 싱글탭을 바로 처리하고 더블탭이면 되돌렸음 → 더블탭 때 메뉴판이 먼저 눈앞에 떴고, 두 번째 탭이 막 뜬 메뉴판 버튼
        // ('현실로 돌아가기' 등)에 눌려 현실로 나가 버리기도 했음. 이제 더블탭이면 싱글탭 일은 아예 하지 않음
        if let p = pendingTap, now - p <= 0.45 {
            if system || pendingSystem {
                pendingTap = nil
                secondHandAt = nil
                doubleTapped()
            } else {
                // 손 추적으로만 받은 탭 둘: 시스템이 둘 중 하나라도 늦게 알아주면(claimSystemTap) 더블탭, 끝내 안 오면 첫 탭의 싱글탭만
                // (손 탭 둘만으로는 현실 창을 열지 않음 — 무릎 위 손가락). 예전엔 바로 버려서, 시스템 탭이 손 추적보다 늦게 오는 날엔
                // 더블탭이 늘 싱글탭(메뉴판)으로 바뀌었음
                secondHandAt = now
            }
        } else {
            pendingTap = now
            pendingSystem = system                                    // 손 추적으로만 받은 탭 둘로는 현실 창(더블탭)을 열지 않음
            secondHandAt = nil
        }
    }

    /// 시스템 탭 하나를 손 추적 '놓기'와 짝지음. 같은 손짓을 손 추적 탭으로 이미 넣었으면 false (두 번 받지 않게).
    /// 예전엔 '손 탭 뒤 0.5초 안의 시스템 탭은 모두 버림'이라, 더블탭의 첫 탭을 손 추적이 받으면 두 번째 시스템 탭이 버려져
    /// 더블탭이 싱글탭 둘이 되거나 탭이 안 먹혔음 → 시간 간격이 아니라 손짓 하나하나로 짝지음
    private func claimSystemTap() -> Bool {
        if let k = pinchRel.lastIndex(where: { $0.state == 0 && abs(t - $0.t) < 0.3 }) {
            pinchRel[k].state = 1
            return true
        }
        // 손 추적 탭으로 이미 넣은 놓기가 가장 최근 손짓이면(그 뒤 새로 집은 적 없음) 같은 손짓 → 새 탭으로는 버리되,
        // 그 손짓이 시스템도 알아본 '진짜 탭'임을 반영: 기다리는 두 번째 손 탭이 있으면 더블탭, 아니면 기다리는 첫 탭을 시스템 탭으로 올림
        if let k = pinchRel.lastIndex(where: { $0.state == 2 }), t - pinchRel[k].t < 0.8, max(pinchCloseAt[0], pinchCloseAt[1]) < pinchRel[k].t {
            if let sh = secondHandAt, pendingTap != nil, t - sh < 0.8 {
                pendingTap = nil
                secondHandAt = nil
                doubleTapped()
            } else if pendingTap != nil {
                pendingSystem = true
            }
            return false
        }
        sysTaps.append(t)                                           // 손 추적이 곧 놓기를 알아채면 그것과 짝지음
        return true
    }

    /// 매 프레임: 시스템 탭과 짝짓지 못한 눈앞 손짓은 0.22초 뒤 손 탭으로 넣고, 기다리던 싱글탭은 0.45초가 지나면 처리
    private func tapTick() {
        for k in pinchRel.indices where pinchRel[k].state == 0 && t - pinchRel[k].t > 0.3 {
            pinchRel[k].state = 2
            if pinchRel[k].ok {
                let g = simd_length(fwd) > 0.01 ? simd_normalize(fwd) : SIMD3<Float>(0, 0, -1)
                tapped(tapCatcher, at: head + g * 2, system: false, when: pinchRel[k].t)
            }
        }
        pinchRel.removeAll { t - $0.t > 1.5 }
        sysTaps.removeAll { t - $0 > 0.5 }
        // 싱글탭: 첫 탭 뒤 0.45초 + 손 추적 탭이 손을 놓은 때로 찍히므로 그 기다림(0.3초)만큼 더. 두 번째 손 탭이 시스템 확인을 기다리는 중이면 그만큼 더
        let wait: Float = pendingSystem ? 0.45 : 0.75
        if let p = pendingTap, t - p > wait, t - (secondHandAt ?? -100) > 0.8 {
            pendingTap = nil
            secondHandAt = nil
            if lastUITap < p - 0.05 { singleTapped() }              // 그 사이 안내판을 누른 탭이었으면 메뉴판을 건드리지 않음
        }
    }

    /// 막 뜬 메뉴판의 버튼은 0.4초 동안 받지 않음 (메뉴판을 띄운 탭에 이어 바로 온 탭이 버튼에 눌리지 않게)
    func menuReady() -> Bool { t - menuShownAt > 0.4 }

    /// 더블탭: 현실 창 열기/닫기 (닫힌 문 앞에서 저절로 열린 창도 닫을 수 있음)
    private func doubleTapped() {
        if peekVisible {
            freePeek = false
            if let l = leafDoor { peekDismissed = l }
        } else {
            freePeek = true
        }
    }

    /// 싱글탭: 메뉴판 띄우기/닫기. 열쇠 문이 보이는 동안 빈 곳을 탭하면 아무 일도 안 함 (열쇠가 우선)
    private func singleTapped() {
        // 떠 있는 메뉴판·테마 판은 닫음 (closeHud 를 쓰지 않음 — 안내판 버튼을 누른 것으로 기록되면 바로 이어지는 두 번째 탭이 무시됨)
        if themeOpen || (hudMenu && hudShow > 0.3) {
            hudMenu = false; themeOpen = false; hudUntil = 0
            return
        }
        guard !keyInView() else { return }
        hudMenu = true
        menuShownAt = t
        themeOpen = false
        hudUntil = t + 4
        hudShow = 0                                                 // 새 자리에 바로 나타나게
    }

    /// 열쇠 문이 떠 있고 그 열쇠가 시선 앞(55도 안)에 있는지 — 그때만 빈 곳 탭을 열쇠에 양보.
    /// (예전엔 떠 있기만 하면 막아, 열쇠 문을 등지고 서 있으면 아무리 탭해도 메뉴판이 안 나왔음)
    private func keyInView() -> Bool {
        for (i, sh) in doorShow where sh > 0.3 {
            for w in worlds.values {
                guard let v = w.doorView[i], v.root.isEnabled else { continue }
                let kp = v.root.convert(position: [0, DoorView.keyY, 0], to: nil)
                let to = kp - head
                if simd_length(to) > 0.05 && simd_dot(simd_normalize(to), fwd) > cos(Float.pi * 55 / 180) { return true }
            }
        }
        return false
    }

    private func openKey(_ i: Int) {
        guard (doorShow[i] ?? 0) > 0.3, openProg[i] == nil, !doorOpen.contains(i), let L = layout, let f = fit, i < L.doors.count else { return }
        let hs = f.toSaved(head)
        let p = L.plane(hs.x, hs.z)
        let ds = L.doors[i]
        guard ds.dist(p) < Self.doorReach + 0.2 else { return }
        let side = ds.side(p)
        doorSide[i] = side
        animRoom[i] = side >= 0 ? ds.roomA : ds.roomB
        openProg[i] = 0
        if let v = worlds[animRoom[i] ?? ds.roomA]?.doorView[i], let par = v.root.parent {
            Sfx.play("key_turn", in: par, at: v.root.position + v.root.orientation.act([0, DoorView.keyY, 0.1]), gain: -4)
        }
    }

    // MARK: 그림 설명 (도슨트)
    /// 그림 오른쪽 위 i 를 누르면: 그 옆에 설명 창이 뜨고, 방이 그 그림의 색으로 잠시 물듦 (그림 속에 들어가 설명을 듣는 느낌).
    /// 설명 창을 닫으면 원래 전시관으로
    private func openDocent(_ name: String) {
        guard let w = worlds[current], let hung = w.hung(named: name) else { return }
        if docent?.entity == name { closeDocent(); return }
        docent = DocentState(entity: name, pick: hung.pick)
        docentShow = 0
        if let card = docentCard {
            let sp = docentSpot(hung).0
            // 저장 좌표 → 지금 좌표, 그리고 내 눈을 향하게 (좌우로 돌리고 위아래로 기울임)
            card.position = spaceRoot.convert(position: sp, to: root)
            faceDocent(card)
        }
        w.immerse(hung)
    }

    /// 해설 창 자리 (저장 좌표): 그림 오른쪽·왼쪽 옆 중 벽 끝·가구에 걸리지 않고 나에게 가까운 쪽.
    /// 양쪽 다 막혔으면 그림과 나 사이, 그림 앞쪽에. 높이는 그림 가운데(1.1~1.6m)
    private func docentSpot(_ h: RoomWorld.Hung) -> (SIMD3<Float>, Bool) {
        guard let f = fit, let L = layout else { return (h.side, false) }
        let hs = f.toSaved(head)
        let blocked = vox?.blockedCells(minH: 0.2) ?? []
        let y = min(max(h.center.y, L.floorY + 1.1), L.floorY + 1.6)
        let tall = vox?.blockedCells(minH: 1.0) ?? []
        func inDoor(_ pl: SIMD2<Float>) -> Bool { L.doors.contains { $0.zone(pl, margin: 0.45, side: 0.25) } }
        func ok(_ c: SIMD3<Float>) -> Bool {
            // 창 자리(폭 약 45cm)와 그 앞: 방 안·가구 없음·다른 벽·문(열쇠 문·문짝)에서 떨어져 있어야
            for s: Float in [-0.25, 0, 0.25] {
                for o: Float in [0, 0.15, 0.3] {
                    let q = c + h.right * s + h.normal * o
                    let pl = L.plane(q.x, q.z)
                    let here = L.at(x: q.x, z: q.z)
                    if here.room == 0 || here.wall < 0.05 || blocked.contains(RoomWorld.clutterKey(pl)) || inDoor(pl) { return false }
                }
            }
            // 내 눈에서 창까지 가로막는 것(벽·키 큰 가구·문)이 없어야 — 가려 보이지 않는 자리에 띄우지 않음
            let a = hs.xz, b = c.xz
            let n = max(2, Int(simd_distance(a, b) / 0.08))
            for k in 1..<n {
                let q2 = a + (b - a) * (Float(k) / Float(n))
                let pl = L.plane(q2.x, q2.y)
                let here = L.at(x: q2.x, z: q2.y)
                if here.room == 0 || here.wall < 0.02 || tall.contains(RoomWorld.clutterKey(pl)) || inDoor(pl) { return false }
            }
            return true
        }
        var best: (SIMD3<Float>, Float)? = nil
        for side: Float in [1, -1] {
            var c = h.center + h.right * side * (h.size.x / 2 + 0.3) + h.normal * 0.12
            c.y = y
            guard ok(c) else { continue }
            let d = simd_distance(c.xz, hs.xz)
            if best == nil || d < best!.1 { best = (c, d) }
        }
        if let b = best { return (b.0, true) }
        // 양옆이 다 막혔으면: 내 앞 70cm, 그림 쪽을 보는 방향에서 옆으로 비켜 (그림을 덜 가리게, 늘 보이는 자리)
        let toArt = simd_normalize(SIMD3<Float>(h.center.x - hs.x, 0, h.center.z - hs.z))
        let side = simd_cross(toArt, SIMD3<Float>(0, 1, 0))
        var c = hs + toArt * 0.7 + side * 0.3
        let pl = L.plane(c.x, c.z)
        if L.at(x: c.x, z: c.z).room == 0 || tall.contains(RoomWorld.clutterKey(pl)) { c = hs + toArt * 0.7 - side * 0.3 }
        c.y = min(y, hs.y - 0.15)
        return (c, false)
    }

    func closeDocent() {
        guard docent != nil else { return }
        docent = nil
        for (_, w) in worlds { w.immerse(nil) }
    }

    private func placeDocent(_ dt: Float) {
        guard let card = docentCard else { return }
        let want: Float = docent != nil ? 1 : 0
        docentShow += (want - docentShow) * min(1, dt * 6)
        card.setOpacity(docentShow)
        card.isEnabled = docentShow > 0.02
        for (_, w) in worlds { w.tickImmerse(dt) }
        decorT += dt
        if decorT > 3, let w = worlds[current], let v = vox {
            decorT = 0
            w.recheckDecor(blocked: v.blockedCells(minH: 0.2), tall: v.blockedCells(minH: 1.0))
        }
        badgeT += dt
        if badgeT > 0.4, let w = worlds[current] {
            badgeT = 0
            let dc = Docent.shared
            w.refreshBadges { dc.state($0) }
        }
    }

    // MARK: 블록(가구·물건) 읽기
    /// 가까운 그물부터, 닫힌 실제 문 앞이면 문 자리를 지나는 그물을 가장 먼저 (동시에 4개까지)
    private func buildSome(_ fit: Fit, _ I: SkinInfo) {
        let now = CACurrentMediaTime()
        guard building.count < 4 else { return }
        var cand: [(UUID, Float)] = []
        for id in dirty where !building.contains(id) {
            guard let a = meshes[id] else { dirty.remove(id); continue }
            let fresh = builtAt[id] == nil
            let p = simd_make_float3(a.originFromAnchorTransform.columns.3)
            let dd = simd_distance(p.xz, head.xz)
            let door = doorAnchors.contains(id) && dd < 4
            let wait = door && doorUrgent ? 0.05 : (dd < 3 ? 0.3 : 1.0)
            if !fresh, let last = builtAt[id], now - last < wait { continue }
            cand.append((id, dd - (fresh ? 3 : 0) - (door ? 6 : 0)))
        }
        cand.sort { $0.1 < $1.1 }
        for (id, _) in cand.prefix(4 - building.count) {
            guard let a = meshes[id] else { continue }
            dirty.remove(id)
            building.insert(id)
            builtAt[id] = now
            let copy = MeshCopy(a)
            Task {
                let res = await Task.detached(priority: .userInitiated) { Skin.build(copy, I, fit) }.value
                building.remove(id)
                guard !ended, meshes[id] != nil else { return }
                // 좌표가 자리를 잡은 뒤에만 가구를 고침 (자리 잡는 중의 어긋난 그물이 엉뚱한 곳에 가구를 만들지 않게)
                if fitStable { vox?.update(cols: res.cols, floor: res.floorSeen, now: t) }
                if res.doorTouched.isEmpty && res.doorHits.isEmpty { doorAnchors.remove(id) } else { doorAnchors.insert(id) }
                setDoorHits(id, res.doorHits, touched: res.doorTouched)
                if let fy = res.floorY { floorSamples[id] = (fy, res.floorN) } else { floorSamples[id] = nil }
            }
        }
    }

    /// 가구 재질: 그 방의 지금 세계에서 매번 받음 (예전 세계의 재질이 남아 선 그림 방에 색이 입혀지지 않게)
    private func material(_ room: Int, _ shade: Int) -> RealityKit.Material {
        guard let wld = worlds[room] else { return UnlitMaterial(color: .gray) }   // 방 세계를 아직 만드는 중: 다 만든 뒤 다시 칠함
        return wld.propMaterial(shade)
    }

    // MARK: 안내판
    /// 알림판: 시선 아래쪽 70cm 앞 (거슬리지 않게), 메뉴판: 눈높이 조금 아래 85cm 앞 (현실 창처럼, 벽이 가까우면 그 앞).
    /// 나타날 때는 바로 그 자리에 (가까이 나타났다 멀어지지 않게), 그 뒤엔 고개를 크게 돌릴 때만 천천히 따라옴
    private func placeHud(_ dt: Float) {
        guard let hud else { return }
        // 테마 판은 따로 된 판(크기가 늘 같음) — 메뉴판이 커지며 버튼이 미끄러지듯 움직이지 않게, 메뉴판 자리에 바로 바꿔 보임
        if let tp = themePanel {
            if tp.isEnabled != themeOpen { tp.isEnabled = themeOpen }
            if themeOpen {
                tp.position = hud.position
                tp.orientation = hud.orientation
                tp.scale = hud.scale
            }
        }
        let want: Float = (hudAlert || (t < hudUntil && !themeOpen && !furnMode)) ? 1 : 0      // 가구 맞추기 중엔 알림판을 띄우지 않음
        if themeOpen { hudShow = 0.03 }                         // 메뉴판 자리는 계속 계산하되 보이지는 않게
        let appearing = hudShow < 0.02 && want > 0
        if hudMenu != hudWasMenu { hudWasMenu = hudMenu; if hudShow > 0.02 { hudShow = 0.03 } }
        var f = SIMD3<Float>(fwd.x, 0, fwd.z)
        if simd_length(f) > 0.15 {
            f = simd_normalize(f)
            let yaw = atan2(-f.x, -f.z)
            var dy = yaw - hudYaw
            while dy > .pi { dy -= 2 * .pi }
            while dy < -.pi { dy += 2 * .pi }
            let follow: Float = themeOpen ? 0.9 : 0.45
            if appearing { hudYaw = yaw } else if abs(dy) > follow { hudYaw += dy * min(1, dt * 2.5) }
        }
        let q = simd_quatf(angle: hudYaw, axis: [0, 1, 0])
        let base: SIMD3<Float> = hudMenu ? SIMD3<Float>(0, -0.12, -0.85) : SIMD3<Float>(0, -0.45, -0.7)
        let full = simd_length(base)
        let dir = q.act(base / full)
        let d = min(full, max(0.3, clearance(dir) - 0.1))
        let k = d / full
        let target = head + dir * d
        // 막대로 옮겨 둔 판은 닫힐 때까지 그 자리 (나를 향하게만)
        if hudPinned && want == 0 && hudShow < 0.03 && !themeOpen { hudPinned = false }
        if hudPinned {
            faceDocent(hud)
        } else {
            hud.scale = SIMD3<Float>(repeating: k)
            if appearing || hudShow < 0.05 { hud.position = target } else { hud.position += (target - hud.position) * min(1, dt * 5) }
            // 눈을 향해 기울임
            let toEye = head - hud.position
            let pitch = atan2(toEye.y, simd_length(SIMD2<Float>(toEye.x, toEye.z)))
            hud.orientation = q * simd_quatf(angle: -pitch, axis: [1, 0, 0])
        }
        hudShow += (want - hudShow) * min(1, dt * 6)
        if want == 0 && hudShow < 0.02 { hudShow = 0 }
        hud.setOpacity(hudShow)
        hud.isEnabled = hudShow > 0.02
        if !hud.isEnabled && hudMenu && want == 0 && !themeOpen { hudMenu = false }
        if themeOpen { hud.isEnabled = false }
    }
}
