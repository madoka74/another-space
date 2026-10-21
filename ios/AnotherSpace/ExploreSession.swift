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
            s.updateSub = content.subscribe(to: SceneEvents.Update.self) { e in s.tick(Float(e.deltaTime)) }
        } attachments: {
            Attachment(id: "hud") { ExploreHud(s: s) }
            Attachment(id: "docent") { DocentCard(s: s) }
            Attachment(id: "theme") { ThemePanel(s: s) }
        }
        // 탭은 한 번씩만 받고, 싱글·더블은 앱이 시간으로 가름 (두 번째 탭이 0.4초 안에 오면 더블탭).
        // 보는 곳 어디든 받도록 머리 둘레에 보이지 않는 '탭 받는 상자'를 둠. 열쇠·그림 버튼은 바로 처리
        .gesture(SpatialTapGesture().targetedToAnyEntity().onEnded { v in s.tapped(v.entity) })
        .task { await s.start() }
        .onDisappear { s.stop() }
    }
}

/// 안내판: 알림판(방이 바뀌거나 알릴 말이 있을 때 시선 아래쪽에 잠깐) / 메뉴판(싱글탭 — 눈앞, 테마 바꾸기·나가기)
private struct ExploreHud: View {
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
            if let m = s.message {
                Text(m).font(.headline).fixedSize(horizontal: false, vertical: true)
            }
            if s.hudMenu {
                HStack(spacing: 14) {
                    if s.room != nil {
                        Button {
                            s.toggleTheme()
                        } label: {
                            Label(s.unified ? "모든 방 테마 바꾸기" : "테마 바꾸기", systemImage: "paintpalette")
                        }
                    }
                    Button {
                        s.exit()
                    } label: {
                        Label("현실로 돌아가기", systemImage: "arrow.uturn.backward")
                    }
                }
                .font(.title3)
            }
        }
        .padding(22)
        .frame(width: 480)
        .glassBackgroundEffect()
        .transaction { $0.animation = nil }
        .simultaneousGesture(TapGesture().onEnded { s.uiTouched() })     // 안내판을 누른 탭은 싱글탭으로 치지 않음
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
            HStack(spacing: 14) {
                Button {
                    s.toggleTheme()
                } label: {
                    Label("테마 닫기", systemImage: "chevron.down")
                }
                Button {
                    s.exit()
                } label: {
                    Label("현실로 돌아가기", systemImage: "arrow.uturn.backward")
                }
            }
            .font(.title3)
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
    var message: String? = "공간을 알아보는 중이에요. 스캔했던 곳을 천천히 둘러봐 주세요."
    var themeOpen = false
    var unified = false             // 모든 방이 같은 세계 (테마를 바꾸면 모든 방이 같이 바뀜)
    var hudMenu = false             // 싱글탭으로 띄운 메뉴판 (아니면 알림판)
    var docent: DocentState?        // 지금 펼친 그림 설명

    let root = Entity()
    @ObservationIgnored var updateSub: EventSubscription?
    @ObservationIgnored private let spaceId: String
    @ObservationIgnored private let spaceRoot = Entity()      // 저장 좌표 → 지금 좌표
    @ObservationIgnored private var vox: VoxelWorld?          // 가구·물건 (10cm 블록, 저장 좌표)
    @ObservationIgnored private var seedTask: Task<Void, Never>?
    @ObservationIgnored private var voxSaveT: Float = 0
    @ObservationIgnored private var ready = false             // 모든 방 세계를 다 만들었는지
    // 문
    @ObservationIgnored private var doorOpen: Set<Int> = []   // 열쇠로 연 문 (다른 세계 사이)
    @ObservationIgnored private var doorShow: [Int: Float] = [:]    // 열쇠 문 보이는 정도
    @ObservationIgnored private var doorSide: [Int: Float] = [:]    // 문을 열 때 서 있던 쪽 (지나가면 닫음)
    @ObservationIgnored private var lastSide: [Int: Float] = [:]    // 문 밖에서 마지막으로 서 있던 쪽
    @ObservationIgnored private var nearDoors: Set<Int> = []        // 1m 안 (1.2m 밖으로 나가야 빠짐 — 경계에서 깜빡이지 않게)
    @ObservationIgnored private var realHits: [Int: [UUID: Set<Int>]] = [:]   // 문 → 그물 덩어리마다 막힌 칸
    @ObservationIgnored private var cover: [Int: Float] = [:]       // 문틀 안쪽이 막힌 비율
    @ObservationIgnored private var closeSince: [Int: Float] = [:]  // 막힘이 시작된 때 (0.6초 이어지면 닫힘)
    @ObservationIgnored private var openHold: [Int: Float] = [:]    // 이때까지는 다시 닫힘으로 치지 않음 (방금 문 자리를 지남)
    @ObservationIgnored private var realClosed: Set<Int> = []       // 실제 문이 닫혀 있는 문
    @ObservationIgnored private var leafSeen: Set<Int> = []         // 닫힌 실제 문이 보이던 문 (그 문이 열리면 바로 열린 공간으로)
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
    @ObservationIgnored private var beforeTap: (Bool, Float, Bool)?   // 첫 탭 전 안내판 상태 (더블탭이면 되돌림)
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
    @ObservationIgnored private var lastHead: SIMD3<Float>?
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
        for a in d.rec.anchors { saved[a.a] = a }
        allIds = SpaceStore.allAnchorIds()
        root.addChild(spaceRoot)
        root.addChild(player.root)
        let v = VoxelWorld(L)
        v.material = { [unowned self] r, s in self.material(r, s) }
        v.sun = { [unowned self] r in self.info?.sun[min(255, max(0, r))] ?? SIMD3<Float>(0, 1, 0) }
        v.tile = { [unowned self] r in self.info?.propTile[min(255, max(0, r))] ?? 1 }
        v.lines = { [unowned self] r in self.data?.rec.room(r)?.lookMode == .line }
        v.fallbackRoom = d.rec.rooms.first?.id ?? 1
        spaceRoot.addChild(v.root)
        vox = v
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
        spaceRoot.components.set(OpacityComponent(opacity: 0))

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

        let auth = await ar.requestAuthorization(for: [.worldSensing])
        guard auth[.worldSensing] == .allowed else {
            message = "주변 공간 알아보기를 허락해야 다른 세계를 입힐 수 있어요. 설정 > 개인정보 보호 및 보안에서 켜 주세요."
            return
        }
        let w = WorldTrackingProvider()
        let m = SceneReconstructionProvider(modes: [.classification])
        world = w
        let providers: [any DataProvider] = [w, m]
        do { try await ar.run(providers) } catch {
            message = "공간 인식을 시작하지 못했어요. 나갔다가 다시 들어와 주세요."
            return
        }
        Task { await self.watchMeshes(m) }
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
            vox?.seed(res)
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

    @discardableResult
    private func addWorld(_ d: SpaceData, _ r: RoomRec, _ L: Layout) -> RoomWorld {
        let w = RoomWorld(d, r, layout: L, blocked: vox?.blockedCells(minH: 0.2) ?? [])
        spaceRoot.addChild(w.world)
        spaceRoot.addChild(w.local)
        worlds[r.id] = w
        vox?.restyle()
        return w
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
        Docent.shared.prefetch(arts.map { $0.0 })                        // 걸린 그림 중 설명이 없는 것은 미리 가져와 저장
    }

    /// 비·눈·반딧불은 지금 방과 이웃 방만 (문턱을 넘을 때 이미 내리고 있게)
    private func refreshActive() {
        let on = (neighbors[current] ?? []).union([current])
        for (id, w) in worlds { w.setActive(sky: on.contains(id), room: id == current) }
    }

    func stop() {
        updateSub?.cancel()
        ar.stop()
        player.stopAll()
        saveVox()
        if !ended { ended = true; AppModel.shared.disappeared() }
    }

    func exit() {
        guard !ended else { return }
        saveVox()
        ended = true
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
    }

    func attachTheme(_ e: Entity) {
        themePanel = e
        e.isEnabled = false
        root.addChild(e)
    }

    func attachDocent(_ e: Entity) {
        docentCard = e
        e.isEnabled = false
        root.addChild(e)
    }

    // MARK: 테마 바꾸기 (지금 방)
    func setTheme(place: String, weather: String, time: String, look: String) {
        lastUITap = t
        hudUntil = t + 4
        guard var d = data, let L = layout, current != 0 else { return }
        let id = current
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
        closeDocent()
        // 새 그림을 미리 읽은 뒤 바꿔 끼움 (지금 방 먼저, 읽는 동안은 예전 세계가 그대로 보임)
        themeTask?.cancel()
        let snapshot = d
        themeTask = Task {
            await Tex.preload(RoomWorld.textures(r), look: r.lookMode)
            for rid in [id] + targets.filter({ $0 != id }) {
                guard !Task.isCancelled, !ended else { return }
                let dd = data ?? snapshot
                guard let rr = dd.rec.room(rid) else { continue }
                if let old = worlds[rid] {
                    old.world.removeFromParent()
                    old.local.removeFromParent()
                }
                let nw = addWorld(dd, rr, L)
                Task { await hangGallery(nw) }
                refreshActive()
                await Task.yield()
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
        let auto = leafDoor != nil && leafDoor != peekDismissed
        let target: Float = (freePeek || auto) ? 1 : 0
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
        if let lh = lastHead, dt > 0 { speed += (simd_distance(lh.xz, head.xz) / dt - speed) * min(1, dt * 4) }
        lastHead = head

        if fit == nil, poses.isEmpty, !aligning, t > nextAlign, let d = data { startAlign(d) }

        // 좌표 맞춤이 조금 바뀌면 순간 이동하지 않고 부드럽게 따라감 (크게 틀어졌을 때만 바로)
        if let tg = fitTarget, let cur = fit, tg != cur {
            let nf = tg.differs(cur, meters: 0.6, radians: 0.3) ? tg : cur.lerp(tg, min(1, dt * 2.5))
            fit = nf
            spaceRoot.transform = nf.transform
            if let sf = skinFit, nf.differs(sf, meters: 0.12, radians: 0.04) {
                skinFit = nf
                dirty.formUnion(meshes.keys)          // 많이 바뀌었을 때만 그물을 새 좌표로 다시 읽음
            }
        }

        if let fit, let L = layout, let I = info {
            let hs = fit.toSaved(head)
            let r = L.roomNear(x: hs.x, z: hs.z, radius: 0.25)
            if r != candidate { candidate = r; candidateT = 0 } else { candidateT += dt }
            if candidate != current && (candidateT > 0.5 || current == 0) && candidate != 0 { enterRoom(candidate) }
            outsideT = r == 0 ? outsideT + dt : 0
            updateDoors(dt, hs, fit.dirToSaved(fwd), L)
            floorTimer += dt
            if floorTimer > 0.5 { floorTimer = 0; updateFloor(L) }
            buildTimer += dt
            if buildTimer > 0.05 { buildTimer = 0; buildSome(fit, I) }
        }
        vox?.tick()
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
        if fit == nil || !ready || !floorOK { target = 0 }
        else if outsideT > 0.6 { target = 0; why = "구성한 방 밖이에요. 현실이 보이게 했어요." }
        else if speed > 1.4 { target = 0; why = "천천히 걸어 주세요. 잠시 현실이 보여요." }
        let rate: Float = target < fade ? 3 : 1.1
        if let ii = intro {
            fade = min(target, ii.world)
        } else {
            fade += (target - fade) * min(1, dt * rate)
        }
        if abs(fade - appliedFade) > 0.01 || (target == 1 && fade > 0.99 && appliedFade < 1) {
            let v = fade > 0.99 ? 1 : fade
            spaceRoot.components.set(OpacityComponent(opacity: v))
            appliedFade = v
        }
        if fit != nil {
            let total = data?.rec.rooms.count ?? 0
            let msg: String? = !ready ? "다른 세계를 준비하는 중이에요 (\(worlds.count)/\(total))"
                : (!floorOK ? "바닥 높이를 맞추는 중이에요. 발밑을 한 번 내려다봐 주세요." : (why ?? player.status))
            if msg != message {
                message = msg
                if msg != nil && t > themeQuiet { hudUntil = max(hudUntil, t + 4) }      // 새 알림은 4초 보여 주고 사라짐
            }
        }
        hudAlert = why != nil
        tapCatcher.position = head

        placePeek(dt)
        if let wld = worlds[current], let f = fit, let L = layout {
            let hs = f.toSaved(head)
            wld.avoidHead(L.plane(hs.x, hs.z))
        }
        for (id, wld) in worlds { wld.tick(dt, active: id == current) }
        soundTick(dt)
        placeHud(dt)
        placeDocent(dt)
    }

    private func enterRoom(_ r: Int) {
        // 나온 방이 전시관이면 그림을 새로 골라 둠 (다시 들어가면 다른 그림)
        if let prev = worlds[current], prev.hasPaintings, current != r {
            Task { await hangGallery(prev) }
        }
        if docent != nil { closeDocent() }
        current = r
        if t > themeQuiet { hudUntil = max(hudUntil, t + 4) }      // 방이 바뀌면 알림판으로 잠깐 알려 줌
        doorOpen.removeAll()
        guard let d = data, let L = layout, let rm = d.rec.room(r) else { return }
        if worlds[r] == nil {                               // 아직 못 만든 방이면 바로 만듦 (그림도 걺)
            let nw = addWorld(d, rm, L)
            Task { await hangGallery(nw) }
        }
        refreshActive()
        room = rm
        player.enter(rm)
        nextEvent = t + Float.random(in: 3...8)
        nextThunder = t + Float.random(in: 4...10)
    }

    /// 사건 소리(새·주전자·스쿠터…)는 방 둘레 바깥 곳곳에서, 폭우면 번개·천둥
    private func soundTick(_ dt: Float) {
        guard current != 0, let wld = worlds[current], fade > 0.5 else { return }
        if t > nextEvent {
            nextEvent = t + Float.random(in: 8...22)
            let a = Float.random(in: 0...(2 * .pi))
            let d = max(wld.halfSize.x, wld.halfSize.y) + Float.random(in: 0.5...4)
            let p = wld.center + SIMD3<Float>(cos(a) * d, Float.random(in: 0.8...2.6), sin(a) * d)
            player.playEvent(in: spaceRoot, at: p)
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
    /// 기준은 모두 1m (1.2m 밖으로 나가야 멀어진 것으로 침 — 경계에서 깜빡이지 않게).
    /// - 실제 문이 닫혀 있으면: 같은 세계든 다른 세계든 1m 안에서 닫힌 문(손잡이 문)이 보이고, 현실 창이 저절로 열림
    /// - 실제 문이 열려 있으면: 같은 세계는 그대로 이어지고, 다른 세계는 1m 안에서 열쇠 문 → 열쇠를 누르면 열림
    /// - 멀리서는: 같은 세계는 뚫린 통로, 다른 세계는 지금 방의 벽
    static let doorReach: Float = 1.0

    private func updateDoors(_ dt: Float, _ hs: SIMD3<Float>, _ fs: SIMD3<Float>, _ L: Layout) {
        guard let d = data else { return }
        let p = L.plane(hs.x, hs.z)
        var look = SIMD2<Float>(simd_dot(SIMD2<Float>(fs.x, fs.z), L.ex), simd_dot(SIMD2<Float>(fs.x, fs.z), L.ez))
        look = simd_length(look) > 0.1 ? simd_normalize(look) : .zero
        let breath = 0.5 + 0.5 * sin(t * 2.4)
        var glowMat: PhysicallyBasedMaterial?
        var urgent = false
        var solid = Set<Int>()
        var leaf: (Int, Float)? = nil
        var anyLeaf = false
        for (i, ds) in L.doors.enumerated() {
            var same = ds.single
            if !same, let ra = d.rec.room(ds.roomA), let rb = d.rec.room(ds.roomB) {
                same = ra.place == rb.place && ra.weather == rb.weather && ra.time == rb.time && ra.lookMode == rb.lookMode
            }
            let dist = ds.dist(p)
            if dist < Self.doorReach { nearDoors.insert(i) } else if dist > Self.doorReach + 0.2 { nearDoors.remove(i) }
            let near = nearDoors.contains(i)
            let inside = ds.inside(p)
            let side = ds.side(p)
            let here = side >= 0 ? ds.roomA : ds.roomB
            // 문 자리 한가운데에 서 있으면 실제 문은 열려 있는 것 (닫힌 문 자리엔 설 수 없음)
            if ds.zone(p, margin: 0.05, side: -0.1) {
                openHold[i] = t + 2
                closeSince[i] = nil
                realClosed.remove(i)
            }
            // 막힘이 0.6초 넘게 이어지면 닫힘 (그물이 잠깐 흔들려 닫혔다 열렸다 하지 않게)
            if let c0 = closeSince[i], t - c0 > 0.6 {
                closeSince[i] = nil
                if (cover[i] ?? 0) > 0.55 && t > (openHold[i] ?? 0) { realClosed.insert(i) }
            }
            let real = realClosed.contains(i)
            let leafOn = real && near
            // 문은 한 번만: 닫힌 실제 문(손잡이 문)을 보고 있다가 실제 문을 열면 그대로 열린 공간 (열쇠 문을 또 보이지 않음)
            if leafOn {
                leafSeen.insert(i)
            } else if leafSeen.contains(i) {
                leafSeen.remove(i)
                if !real && near && !same && !doorOpen.contains(i) { doorOpen.insert(i); doorSide[i] = lastSide[i] ?? side }
            }
            if !same {
                if inside {
                    if !doorOpen.contains(i) && openProg[i] == nil { doorOpen.insert(i); doorSide[i] = lastSide[i] ?? side }
                } else {
                    lastSide[i] = side
                    if doorOpen.contains(i) {
                        let crossed = (doorSide[i] ?? side) * side < 0
                        if crossed {
                            doorOpen.remove(i)
                            doorShow[i] = 0
                            passed.insert(i)
                        } else if !near {
                            doorOpen.remove(i)
                        }
                    }
                }
            }
            // 열쇠 움직임 (1.1초): 열쇠가 구멍으로 → 돌고 → 문짝이 양옆 벽 속으로
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
            // 문 자리가 '이 방의 벽'으로 막혀 있는지: 다른 세계, 열쇠로 안 열었고, 닫힌 실제 문이 대신 보이지 않을 때
            let closed = !same && !doorOpen.contains(i) && (prog ?? 0) < 0.4 && !leafOn
            for rid in [ds.roomA, ds.roomB] {
                for e in worlds[rid]?.doorPanels[i] ?? [] where e.isEnabled != closed { e.isEnabled = closed }
            }
            if let lf = worlds[ds.roomA]?.doorLeaf[i], lf.isEnabled != leafOn { lf.isEnabled = leafOn }
            if leafOn {
                urgent = true
                anyLeaf = true
                // 현실 원은 그 닫힌 문 쪽을 바라볼 때만 (양쪽에 문이 있어도 보는 쪽 문만, 다른 데를 보면 바로 사라짐)
                let q = simd_clamp(p, ds.lo, ds.hi)
                var to = q - p
                if simd_length(to) < 0.25 { to = ds.mid - p }
                let facing = look != .zero && simd_length(to) > 0.01 && simd_dot(simd_normalize(to), look) > 0.72
                if facing && (leaf == nil || dist < leaf!.1) { leaf = (i, dist) }
            }
            if closed || leafOn { solid.insert(i) }
            if passed.contains(i) {
                let to = ds.mid - p
                let facing = simd_length(to) > 0.05 && simd_dot(simd_normalize(to), look) > 0.8
                if !near || facing { passed.remove(i) }
            }
            // 열쇠 문: 다른 세계 사이, 실제 문은 열려 있고, 아직 안 열었고, 문 밖 1m 안 — 서 있는 쪽 방에만
            let want: Float = (!same && !inside && near && !real && !doorOpen.contains(i) && !passed.contains(i)) || prog != nil ? 1 : 0
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
                v.root.components.set(OpacityComponent(opacity: o))
                if glowMat == nil { glowMat = RoomWorld.gold(rough: 0.22, glow: 0.2 + 2.2 * breath) }
                if let gm = glowMat { for e in v.parts { e.model?.materials = [gm] } }
                Self.pose(v, prog: rid == showRoom ? prog : nil, t: t)
            }
        }
        doorUrgent = urgent
        solidDoors = solid
        leafDoor = leaf?.0
        if !anyLeaf { peekDismissed = nil }        // 닫힌 문에서 벗어나면 더블탭으로 닫은 것도 풂
    }

    /// 문 모양 맞추기: prog nil = 닫혀서 열쇠가 떠 있음, 0~1 = 열쇠로 여는 중
    static func pose(_ v: DoorView, prog: Float?, t: Float) {
        func ease(_ x: Float) -> Float { let c = min(1, max(0, x)); return c * c * (3 - 2 * c) }
        v.left.position = [-v.hl, 0, 0]; v.right.position = [v.hl, 0, 0]
        guard let p = prog else {
            v.left.scale = [1, 1, 1]; v.right.scale = [1, 1, 1]
            v.keyRoot.position = [0, DoorView.keyY, DoorView.keyZ]
            v.keyRoot.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
            v.keyRoot.components.set(OpacityComponent(opacity: 1))
            v.lock.components.set(OpacityComponent(opacity: 1))
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
        v.keyRoot.components.set(OpacityComponent(opacity: fade))
        v.lock.components.set(OpacityComponent(opacity: fade))
        let k = max(0.001, 1 - c)
        v.left.scale = [k, 1, 1]; v.right.scale = [k, 1, 1]
    }

    /// 실제 문이 닫혔는지: 그물 덩어리마다 가장 최근에 본 '문 자리를 가로막은 칸'을 합쳐 문틀 안쪽을 덮은 비율로.
    /// - 열림은 바로: 40% 밑이거나, 한 덩어리가 보던 막힌 칸이 크게 줄면(문이 움직임) 다른 덩어리의 예전 기록도 버리고 바로 열림
    /// - 닫힘은 천천히: 55% 넘게 0.6초 이어질 때 (그물이 흔들려 닫힌 문이 나타났다 사라지지 않게)
    private func setDoorHits(_ id: UUID, _ hits: [Int: Set<Int>], touched seen: Set<Int>) {
        guard let L = layout else { return }
        var touched = seen.union(hits.keys)
        for (i, m) in realHits where m[id] != nil && !touched.contains(i) {
            realHits[i]?[id] = nil
            touched.insert(i)
        }
        for i in seen.union(hits.keys) {
            let nh = hits[i] ?? []
            let old = realHits[i]?[id] ?? []
            if old.count >= 8 && nh.count * 10 <= old.count * 4 {
                realHits[i] = [:]                                   // 문이 움직였음 → 다른 덩어리의 예전 기록은 믿지 않음
            }
            realHits[i, default: [:]][id] = nh
        }
        for i in touched where i < L.doors.count {
            var all = Set<Int>()
            for (_, e) in realHits[i] ?? [:] { all.formUnion(e) }
            let cols = max(1, Int(((L.doors[i].width - 0.16) / 0.1).rounded(.up)))
            let cv = Float(all.count) / Float(cols * 16)
            cover[i] = cv
            if cv < 0.4 {
                realClosed.remove(i)
                closeSince[i] = nil
            } else if cv > 0.55 && !realClosed.contains(i) && closeSince[i] == nil {
                closeSince[i] = t
            }
        }
    }

    // MARK: 탭
    /// 탭 하나: 열쇠·그림 버튼이면 바로 처리, 그 밖(탭 받는 상자)이면 0.4초 안에 또 오는지 기다림
    func tapped(_ e: Entity) {
        var cur: Entity? = e
        while let c = cur {
            if c.name.hasPrefix("door-"), let i = Int(c.name.dropFirst(5)) {
                pendingTap = nil
                openKey(i)
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
        // 싱글탭은 기다리지 않고 바로 반응 (탭이 먹혔는지 바로 보이게). 0.45초 안에 두 번째 탭이 오면
        // 첫 탭이 한 일을 되돌리고 더블탭으로 처리
        if let p = pendingTap, t - p <= 0.45 {
            pendingTap = nil
            if let s = beforeTap { hudMenu = s.0; hudUntil = s.1; themeOpen = s.2; hudShow = 0 }
            beforeTap = nil
            doubleTapped()
        } else {
            pendingTap = t
            beforeTap = (hudMenu, hudUntil, themeOpen)
            singleTapped()
        }
    }

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
        guard !doorShow.values.contains(where: { $0 > 0.3 }) else { return }
        hudMenu = true
        themeOpen = false
        hudUntil = t + 4
        hudShow = 0                                                 // 새 자리에 바로 나타나게
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
            let p = spaceRoot.convert(position: sp, to: root)
            card.position = p
            let to = head - p
            let yaw = atan2(to.x, to.z)
            let pitch = atan2(to.y, max(0.05, simd_length(SIMD2<Float>(to.x, to.z))))
            card.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0]) * simd_quatf(angle: -pitch, axis: [1, 0, 0])
        }
        w.immerse(in: hung.palette)
    }

    /// 해설 창 자리 (저장 좌표): 그림 오른쪽·왼쪽 옆 중 벽 끝·가구에 걸리지 않고 나에게 가까운 쪽.
    /// 양쪽 다 막혔으면 그림과 나 사이, 그림 앞쪽에. 높이는 그림 가운데(1.1~1.6m)
    private func docentSpot(_ h: RoomWorld.Hung) -> (SIMD3<Float>, Bool) {
        guard let f = fit, let L = layout else { return (h.side, false) }
        let hs = f.toSaved(head)
        let blocked = vox?.blockedCells(minH: 0.2) ?? []
        let y = min(max(h.center.y, L.floorY + 1.1), L.floorY + 1.6)
        func ok(_ c: SIMD3<Float>) -> Bool {
            // 창 폭(약 40cm) 양끝과 가운데, 벽에서 10~50cm 앞이 모두 방 안·가구 없음·다른 벽에서 5cm 넘게 떨어져 있어야
            for s: Float in [-0.22, 0, 0.22] {
                for o: Float in [0, 0.15, 0.3] {
                    let q = c + h.right * s + h.normal * o
                    let pl = L.plane(q.x, q.z)
                    let here = L.at(x: q.x, z: q.z)
                    if here.room == 0 || here.wall < 0.05 || blocked.contains(RoomWorld.clutterKey(pl)) { return false }
                }
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
        // 그림 앞: 그림에서 나 쪽으로 (벽에서 0.5~1m), 그림을 가리지 않게 내 쪽 옆으로 조금
        let toMe = hs - h.center
        let lateral: Float = simd_dot(toMe, h.right) >= 0 ? 1 : -1
        let away = min(1.0, max(0.5, simd_dot(toMe, h.normal) * 0.5))
        var c = h.center + h.normal * away + h.right * lateral * (h.size.x / 2 * 0.6)
        c.y = y
        return (c, false)
    }

    func closeDocent() {
        guard docent != nil else { return }
        docent = nil
        for (_, w) in worlds { w.immerse(in: nil) }
    }

    private func placeDocent(_ dt: Float) {
        guard let card = docentCard else { return }
        let want: Float = docent != nil ? 1 : 0
        docentShow += (want - docentShow) * min(1, dt * 6)
        card.components.set(OpacityComponent(opacity: docentShow))
        card.isEnabled = docentShow > 0.02
        for (_, w) in worlds { w.tickImmerse(dt) }
        decorT += dt
        if decorT > 3, let w = worlds[current], let v = vox {
            decorT = 0
            w.recheckDecor(blocked: v.blockedCells(minH: 0.2))
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
                if fitStable { vox?.update(cols: res.cols, floor: res.floorSeen) }
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
        let want: Float = (hudAlert || (t < hudUntil && !themeOpen)) ? 1 : 0
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
        hud.scale = SIMD3<Float>(repeating: k)
        if appearing || hudShow < 0.05 { hud.position = target } else { hud.position += (target - hud.position) * min(1, dt * 5) }
        // 눈을 향해 기울임
        let toEye = head - hud.position
        let pitch = atan2(toEye.y, simd_length(SIMD2<Float>(toEye.x, toEye.z)))
        hud.orientation = q * simd_quatf(angle: -pitch, axis: [1, 0, 0])
        hudShow += (want - hudShow) * min(1, dt * 6)
        if want == 0 && hudShow < 0.02 { hudShow = 0 }
        hud.components.set(OpacityComponent(opacity: hudShow))
        hud.isEnabled = hudShow > 0.02
        if !hud.isEnabled && hudMenu && want == 0 && !themeOpen { hudMenu = false }
        if themeOpen { hud.isEnabled = false }
    }
}
