import SwiftUI
import RealityKit
import ARKit
import QuartzCore

/// 탐험: 저장한 공간을 다시 알아본 뒤, 방마다 다른 세계를 입힘.
/// - 바닥·벽·천장(하늘)·창: 사각형으로 구성한 집 모양에서 반듯하게 만듦 (유리·거울·스캔이 빈 곳도 빈틈없이)
/// - 가구·물건: 지금 비전프로가 보고 있는 실제 그물로 → 의자를 옮겨도 그 자리에 다시 입혀짐
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
            s.updateSub = content.subscribe(to: SceneEvents.Update.self) { e in s.tick(Float(e.deltaTime)) }
        } attachments: {
            Attachment(id: "hud") { ExploreHud(s: s) }
        }
        .gesture(SpatialTapGesture().targetedToAnyEntity().onEnded { v in s.tapped(v.entity) })
        .task { await s.start() }
        .onDisappear { s.stop() }
    }
}

/// 아래를 내려다보면 보이는 안내판: 지금 세계 이름 · 테마 바꾸기 · 나가기
private struct ExploreHud: View {
    let s: ExploreSession

    var body: some View {
        VStack(spacing: 12) {
            if let r = s.room {
                Text(r.title).font(.title2.weight(.semibold))
                Text(r.name).font(.headline).foregroundStyle(.secondary)
            }
            if let m = s.message {
                Text(m).font(.headline).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            if s.themeOpen, let r = s.room {
                ThemePicker(room: r, compact: true) { p, w, t in s.setTheme(place: p, weather: w, time: t) }
                    .padding(.top, 4)
            }
            HStack(spacing: 14) {
                if s.room != nil {
                    Button {
                        s.themeOpen.toggle()
                    } label: {
                        Label(s.themeOpen ? "테마 닫기" : (s.unified ? "모든 방 테마 바꾸기" : "테마 바꾸기"),
                              systemImage: s.themeOpen ? "chevron.down" : "paintpalette")
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
        .padding(22)
        .frame(width: s.themeOpen ? 640 : 480)
        .glassBackgroundEffect()
    }
}

/// 가구 입히기에 필요한 값 (다른 스레드로 넘김)
struct SkinInfo: Sendable {
    let layout: Layout
    let sun: [SIMD3<Float>]          // 방 id → 해 방향 (저장 좌표)
    let propTile: [Float]

    init(_ d: SpaceData, _ L: Layout) {
        layout = L
        var sn = [SIMD3<Float>](repeating: SIMD3<Float>(0, 1, 0), count: 256)
        var pt = [Float](repeating: 1, count: 256)
        for r in d.rec.rooms where r.id > 0 && r.id < 256 {
            sn[r.id] = Worlds.sunDir(r.time)
            pt[r.id] = Worlds.style(r.place, time: r.time).propTile
        }
        sun = sn; propTile = pt
    }
}

/// 그물 한 덩어리를 방·그늘별로 나눈 결과 (가구·물건만)
struct SkinGroup: Sendable {
    let room: Int
    let shade: Int       // 0 해 쪽, 1 옆, 2 그늘
    var cell: Int64 = 0  // 미리 그려 두는 스캔 그물: 1m 칸 (실제 그물이 그 칸을 덮으면 숨김)
    var pos: [SIMD3<Float>] = []
    var uv: [SIMD2<Float>] = []
    var idx: [UInt32] = []
}

struct SkinResult: Sendable {
    var groups: [SkinGroup] = []
    var cells: Set<Int64> = []     // 이 그물이 덮는 1m 칸 (저장 좌표) — 그 칸의 미리 그린 가구는 숨김
}

enum Skin {
    static func cellKey(_ x: Float, _ z: Float) -> Int64 {
        (Int64((x).rounded(.down)) + 100_000) << 20 | (Int64((z).rounded(.down)) + 100_000)
    }

    /// 허공에 뜬 조각 걸러내기: 꼭짓점을 함께 쓰는 삼각형끼리 묶어서, 아주 작은 묶음이나
    /// 바닥에서 떠 있는 작고 얇은 묶음(사람·반사·스캔 찌꺼기)은 버림. 삼각형마다 남길지
    static func keepMask(_ wv: [SIMD3<Float>], _ f: [UInt32], floorY: Float) -> [Bool] {
        let nt = f.count / 3
        var parent = Array(0..<wv.count)
        func find(_ x: Int) -> Int {
            var x = x
            while parent[x] != x { parent[x] = parent[parent[x]]; x = parent[x] }
            return x
        }
        for t in 0..<nt {
            let a = Int(f[t * 3]), b = Int(f[t * 3 + 1]), c = Int(f[t * 3 + 2])
            guard a < wv.count, b < wv.count, c < wv.count else { continue }
            let ra = find(a), rb = find(b), rc = find(c)
            if ra != rb { parent[rb] = ra }
            let r2 = find(rc)
            let r1 = find(a)
            if r1 != r2 { parent[r2] = r1 }
        }
        struct Comp { var n = 0; var area: Float = 0; var lo = SIMD3<Float>(repeating: .infinity); var hi = SIMD3<Float>(repeating: -.infinity) }
        var comps: [Int: Comp] = [:]
        var root = [Int](repeating: -1, count: nt)
        for t in 0..<nt {
            let a = Int(f[t * 3]), b = Int(f[t * 3 + 1]), c = Int(f[t * 3 + 2])
            guard a < wv.count, b < wv.count, c < wv.count else { continue }
            let r = find(a)
            root[t] = r
            var cp = comps[r] ?? Comp()
            cp.n += 1
            cp.area += simd_length(simd_cross(wv[b] - wv[a], wv[c] - wv[a])) / 2
            cp.lo = simd_min(cp.lo, simd_min(wv[a], simd_min(wv[b], wv[c])))
            cp.hi = simd_max(cp.hi, simd_max(wv[a], simd_max(wv[b], wv[c])))
            comps[r] = cp
        }
        var keep = [Bool](repeating: false, count: nt)
        for t in 0..<nt {
            guard root[t] >= 0, let cp = comps[root[t]] else { continue }
            let ext = cp.hi - cp.lo
            let size = max(ext.x, max(ext.y, ext.z))
            if cp.n < 10 || cp.area < 0.03 { continue }                                  // 부스러기
            if cp.lo.y - floorY > 0.3 && cp.area < 0.12 && size < 0.6 { continue }      // 허공에 뜬 작은 조각
            keep[t] = true
        }
        return keep
    }

    /// 실제 그물 → 방 안 가구·물건만 골라 입힐 조각들.
    /// 벽은 사각형에서 반듯하게 세우므로 벽 가까이(15cm)의 면은 버림. 방 밖(거울 속·창밖·구성하지 않은 곳)·천장·바닥 면도 버림.
    /// 벽에서 떨어져 있는 실제 벽면(구성을 넓게 잡았을 때)은 물건처럼 입혀서 보이게 함 (부딪히지 않게)
    /// chunked: 미리 그려 두는 스캔 그물 — 1m 칸마다 나눔
    static func build(_ m: MeshCopy, _ I: SkinInfo, _ fit: Fit, chunked: Bool = false) -> SkinResult {
        let L = I.layout
        var out = SkinResult()
        var groups: [Int64: SkinGroup] = [:]
        let wv = m.v.map { simd_make_float3(m.m * SIMD4<Float>($0, 1)) }
        let keep = keepMask(wv, m.f, floorY: L.floorY + fit.y)
        var i = 0, fi = 0
        while i + 2 < m.f.count {
            defer { i += 3; fi += 1 }
            let ia = Int(m.f[i]), ib = Int(m.f[i + 1]), ic = Int(m.f[i + 2])
            guard ia < wv.count, ib < wv.count, ic < wv.count else { continue }
            let a = wv[ia], b = wv[ib], c = wv[ic]
            let ctr = fit.toSaved((a + b + c) / 3)
            let ck = cellKey(ctr.x, ctr.z)
            if !chunked { out.cells.insert(ck) }
            guard fi < keep.count, keep[fi] else { continue }
            let cr = simd_cross(b - a, c - a)
            let len = simd_length(cr)
            guard len > 1e-9 else { continue }
            let n = cr / len
            let cls: UInt8 = fi < m.c.count ? m.c[fi] : 0
            let ns = fit.dirToSaved(n)
            let hgt = ctr.y - L.floorY
            let here = L.at(x: ctr.x, z: ctr.z)
            let r = here.room
            if r == 0 || r >= 256 { continue }                       // 방 밖
            if here.wall < 0.15 { continue }                         // 반듯한 벽이 덮는 곳
            if cls == MeshClass.ceiling || hgt > L.ceil[r] - 0.1 { continue }
            if cls == MeshClass.floor || (ns.y > 0.8 && hgt < 0.06) || hgt < -0.05 { continue }
            let l = simd_dot(ns, I.sun[r])
            let shade = l > 0.35 ? 0 : (l > -0.15 ? 1 : 2)
            let cell: Int64 = chunked ? ck : 0
            let key = (cell << 12) | Int64(r * 4 + shade)
            var g = groups[key] ?? SkinGroup(room: r, shade: shade, cell: cell)
            let base = UInt32(g.pos.count)
            g.pos += [a, b, c]
            let tile = I.propTile[r]
            for p in [a, b, c] {
                let q = fit.toSaved(p)
                let uv: SIMD2<Float>
                if abs(ns.y) > 0.7 { uv = SIMD2<Float>(q.x, q.z) }
                else if abs(ns.x) > abs(ns.z) { uv = SIMD2<Float>(q.z, -q.y) }
                else { uv = SIMD2<Float>(q.x, -q.y) }
                g.uv.append(uv / tile)
            }
            g.idx += [base, base + 1, base + 2, base, base + 2, base + 1]      // 양면
            groups[key] = g
        }
        out.groups = Array(groups.values)
        return out
    }

    /// 저장한 스캔 그물 → 꼭짓점을 합친(이어진 면을 알 수 있게) 그물 하나
    static func weld(_ pts: [SIMD3<Float>], _ cls: [UInt8]) -> MeshCopy {
        var index: [Int64: UInt32] = [:]
        index.reserveCapacity(pts.count / 2)
        var v: [SIMD3<Float>] = []
        var f: [UInt32] = []
        f.reserveCapacity(pts.count)
        for p in pts {
            let k = (Int64((p.x * 200).rounded()) + 1_000_000) << 42 | (Int64((p.y * 200).rounded()) + 1_000_000) << 21 | (Int64((p.z * 200).rounded()) + 1_000_000)
            if let i = index[k] { f.append(i) } else {
                let i = UInt32(v.count)
                v.append(p); index[k] = i; f.append(i)
            }
        }
        return MeshCopy(id: UUID(), m: matrix_identity_float4x4, v: v, f: f, c: cls)
    }
}

@MainActor @Observable
final class ExploreSession {
    var room: RoomRec?
    var message: String? = "공간을 알아보는 중이에요. 스캔했던 곳을 천천히 둘러봐 주세요."
    var themeOpen = false
    var unified = false             // 모든 방이 같은 세계 (테마를 바꾸면 모든 방이 같이 바뀜)

    let root = Entity()
    @ObservationIgnored var updateSub: EventSubscription?
    @ObservationIgnored private let spaceId: String
    @ObservationIgnored private let spaceRoot = Entity()      // 저장 좌표 → 지금 좌표
    @ObservationIgnored private let skinRoot = Entity()       // 실제 그물 (지금 좌표)
    @ObservationIgnored private let savedRoot = Entity()      // 스캔 때 저장한 그물로 미리 그린 가구 (저장 좌표)
    @ObservationIgnored private var savedChunks: [Int64: (ModelEntity, [Int])] = [:]   // 1m 칸 → (엔티티, 재질 키들)
    @ObservationIgnored private var liveCells: [UUID: Set<Int64>] = [:]
    @ObservationIgnored private var cellCount: [Int64: Int] = [:]
    @ObservationIgnored private var savedTask: Task<Void, Never>?
    @ObservationIgnored private var ready = false             // 모든 방 세계를 다 만들었는지
    @ObservationIgnored private var doorOpen: Set<Int> = []   // 손잡이를 눌러 연 문 (다른 세계 사이)
    @ObservationIgnored private var doorState: [Int: Float] = [:]   // 1 닫힘(벽) → 0 열림
    @ObservationIgnored private var doorShow: [Int: Float] = [:]    // 문틀·열쇠 보이는 정도
    @ObservationIgnored private var doorSide: [Int: Float] = [:]    // 문을 열 때 서 있던 쪽 (지나가면 닫음)
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
    @ObservationIgnored private var poses: [String: simd_float4x4] = [:]   // 다시 찾은 앵커의 마지막 위치 (잠깐 놓쳐도 지우지 않음)
    @ObservationIgnored private var fit: Fit?                 // 지금 쓰는 좌표 맞춤 (목표 쪽으로 부드럽게 따라감)
    @ObservationIgnored private var fitTarget: Fit?
    @ObservationIgnored private var skinFit: Fit?             // 가구를 마지막으로 다시 입힐 때의 맞춤
    @ObservationIgnored private var meshes: [UUID: MeshAnchor] = [:]
    @ObservationIgnored private var meshEnts: [UUID: ModelEntity] = [:]
    @ObservationIgnored private var builtAt: [UUID: Double] = [:]
    @ObservationIgnored private var dirty: Set<UUID> = []
    @ObservationIgnored private var building: Set<UUID> = []
    @ObservationIgnored private var mats: [Int: UnlitMaterial] = [:]
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
    @ObservationIgnored private var hud: Entity?
    @ObservationIgnored private var hudYaw: Float = 0
    @ObservationIgnored private var hudPlaced = false
    @ObservationIgnored private var hudShow: Float = 1
    @ObservationIgnored private var t: Float = 0
    @ObservationIgnored private var buildTimer: Float = 0
    @ObservationIgnored private var nextEvent: Float = 6
    @ObservationIgnored private var nextThunder: Float = 8
    @ObservationIgnored private var ended = false
    @ObservationIgnored private let player = AmbientPlayer()

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
        spaceRoot.addChild(savedRoot)
        root.addChild(skinRoot)
        root.addChild(player.root)
        spaceRoot.components.set(OpacityComponent(opacity: 0))
        skinRoot.components.set(OpacityComponent(opacity: 0))

        let auth = await ar.requestAuthorization(for: [.worldSensing])
        guard auth[.worldSensing] == .allowed else {
            message = "주변 공간 알아보기를 허락해야 다른 세계를 입힐 수 있어요. 설정 > 개인정보 보호 및 보안에서 켜 주세요."
            return
        }
        let w = WorldTrackingProvider()
        let m = SceneReconstructionProvider(modes: [.classification])
        world = w
        do { try await ar.run([w, m]) } catch {
            message = "공간 인식을 시작하지 못했어요. 나갔다가 다시 들어와 주세요."
            return
        }
        Task { await self.watchMeshes(m) }
        Task { await self.watchWorld(w) }
        // 공간을 알아보는 동안 방 세계를 하나씩 미리 만듦 (그림도 미리 읽어 둠) → 문턱을 넘을 때 기다리지 않음
        await buildWorlds()
    }

    /// 아직 안 만든 방 중 '지금 있는 방 → 이웃 방 → 나머지' 순서로 하나씩
    private func buildWorlds() async {
        while !ended {
            guard let d = data, let L = layout else { return }
            let todo = d.rec.rooms.filter { worlds[$0.id] == nil }
            guard !todo.isEmpty else {
                ready = true
                buildSaved()
                return
            }
            let near = neighbors[current] ?? []
            let next = todo.first { $0.id == current } ?? todo.first { near.contains($0.id) } ?? todo[0]
            await Tex.preload(RoomWorld.textures(next))
            guard !ended, worlds[next.id] == nil, let d2 = data, let r = d2.rec.room(next.id) else { continue }
            addWorld(d2, r, L)
            refreshActive()
            if !meshEnts.isEmpty { dirty.formUnion(meshes.keys) }      // 그 방 가구 색을 새 세계에 맞게
            try? await Task.sleep(for: .milliseconds(30))
        }
    }

    private func addWorld(_ d: SpaceData, _ r: RoomRec, _ L: Layout) {
        let w = RoomWorld(d, r, layout: L)
        spaceRoot.addChild(w.world)
        spaceRoot.addChild(w.local)
        worlds[r.id] = w
    }

    /// 비·눈·반딧불은 지금 방과 이웃 방만 (문턱을 넘을 때 이미 내리고 있게)
    private func refreshActive() {
        let on = (neighbors[current] ?? []).union([current])
        for (id, w) in worlds { w.setActive(on.contains(id)) }
    }

    func stop() {
        updateSub?.cancel()
        ar.stop()
        player.stopAll()
        if !ended { ended = true; AppModel.shared.disappeared() }
    }

    func exit() {
        guard !ended else { return }
        ended = true
        player.stopAll()
        AppModel.shared.finish()
    }

    func attachHud(_ e: Entity) {
        hud = e
        e.position = [0, 1.1, -0.7]
        root.addChild(e)
    }

    // MARK: 테마 바꾸기 (지금 방)
    func setTheme(place: String, weather: String, time: String) {
        guard var d = data, let L = layout, current != 0 else { return }
        let id = current
        d.setTheme(id, place: place, weather: weather, time: time)       // '모든 방 같게'면 모든 방이 바뀜
        data = d
        unified = d.rec.isUnified
        try? SpaceStore.save(d)
        guard let r = d.rec.room(id) else { return }
        room = r
        info = SkinInfo(d, L)
        player.enter(r, force: true)
        let targets = d.rec.isUnified ? d.rec.rooms.map(\.id) : [id]
        // 새 그림을 미리 읽은 뒤 바꿔 끼움 (지금 방 먼저, 읽는 동안은 예전 세계가 그대로 보임)
        themeTask?.cancel()
        let snapshot = d
        themeTask = Task {
            await Tex.preload(RoomWorld.textures(r))
            for rid in [id] + targets.filter({ $0 != id }) {
                guard !Task.isCancelled, !ended else { return }
                let dd = data ?? snapshot
                guard let rr = dd.rec.room(rid) else { continue }
                if let old = worlds[rid] {
                    old.world.removeFromParent()
                    old.local.removeFromParent()
                }
                addWorld(dd, rr, L)
                for k in 0..<4 { mats[rid * 4 + k] = nil }
                refreshActive()
                await Task.yield()
            }
            guard !Task.isCancelled, !ended else { return }
            dirty.formUnion(meshes.keys)
            buildSaved()
        }
    }

    // MARK: 미리 그려 두는 가구 (스캔 때 저장한 그물)
    /// 모든 방의 가구를 처음부터 그려 둠. 비전프로가 지금 보고 있는 실제 그물이 그 1m 칸을 덮으면
    /// 미리 그린 것은 숨기고 실제 그물을 씀 → 옮긴 의자도 가까이 가면 제자리에 다시 입혀짐
    private func buildSaved() {
        guard let I = info else { return }
        let id = spaceId
        savedTask?.cancel()
        savedTask = Task {
            let res = await Task.detached(priority: .utility) { () -> SkinResult? in
                guard let m = SpaceStore.loadMesh(id) else { return nil }
                return Skin.build(Skin.weld(m.0, m.1), I, Fit(), chunked: true)
            }.value
            guard !Task.isCancelled, !ended, let res else { return }
            for (_, v) in savedChunks { v.0.removeFromParent() }
            savedChunks = [:]
            var byCell: [Int64: [SkinGroup]] = [:]
            for g in res.groups where !g.idx.isEmpty { byCell[g.cell, default: []].append(g) }
            var n = 0
            for (cell, list) in byCell {
                guard !Task.isCancelled, !ended else { return }
                var descs: [MeshDescriptor] = []
                var keys: [Int] = []
                for g in list {
                    var md = MeshDescriptor(name: "s\(g.room)_\(g.shade)")
                    md.positions = MeshBuffers.Positions(g.pos)
                    md.textureCoordinates = MeshBuffers.TextureCoordinates(g.uv)
                    md.primitives = .triangles(g.idx)
                    md.materials = .allFaces(UInt32(keys.count))
                    descs.append(md)
                    keys.append(g.room * 4 + g.shade)
                }
                guard let mesh = try? MeshResource.generate(from: descs) else { continue }
                let ms: [RealityKit.Material] = keys.map { material($0 / 4, $0 % 4) }
                let e = ModelEntity(mesh: mesh, materials: ms)
                e.isEnabled = (cellCount[cell] ?? 0) == 0
                savedRoot.addChild(e)
                savedChunks[cell] = (e, keys)
                n += 1
                if n % 8 == 0 { await Task.yield() }          // 한꺼번에 만들어 화면이 멈추지 않게
            }
        }
    }

    /// 실제 그물이 덮는 칸이 바뀌면 미리 그린 가구를 숨기거나 다시 보임
    private func setLiveCells(_ id: UUID, _ cells: Set<Int64>) {
        let old = liveCells[id] ?? []
        for c in old.subtracting(cells) {
            let k = (cellCount[c] ?? 1) - 1
            if k <= 0 {
                cellCount[c] = nil
                if let e = savedChunks[c]?.0 { e.isEnabled = true }
            } else {
                cellCount[c] = k
            }
        }
        for c in cells.subtracting(old) {
            cellCount[c, default: 0] += 1
            if let e = savedChunks[c]?.0 { e.isEnabled = false }
        }
        liveCells[id] = cells.isEmpty ? nil : cells
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
                meshEnts.removeValue(forKey: a.id)?.removeFromParent()
                setLiveCells(a.id, [])
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
        fitTarget = f
        if fit == nil {                        // 처음: 바로 맞춤
            fit = f
            skinFit = f
            spaceRoot.transform = f.transform
            dirty.formUnion(meshes.keys)
            message = nil
        }
    }

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

        // 좌표 맞춤이 조금 바뀌면 순간 이동하지 않고 부드럽게 따라감 (크게 틀어졌을 때만 바로)
        if let tg = fitTarget, let cur = fit, tg != cur {
            let nf = tg.differs(cur, meters: 0.6, radians: 0.3) ? tg : cur.lerp(tg, min(1, dt * 2.5))
            fit = nf
            spaceRoot.transform = nf.transform
            if let sf = skinFit, nf.differs(sf, meters: 0.12, radians: 0.04) {
                skinFit = nf
                dirty.formUnion(meshes.keys)          // 많이 바뀌었을 때만 가구를 새 좌표로 다시 입힘
            }
        }

        if let fit, let L = layout, let I = info {
            // 지금 있는 방 (0.5초 넘게 머물러야 바뀜). 문틀·벽 사이를 지날 때는 25cm 안의 방으로
            let hs = fit.toSaved(head)
            let r = L.roomNear(x: hs.x, z: hs.z, radius: 0.25)
            if r != candidate { candidate = r; candidateT = 0 } else { candidateT += dt }
            if candidate != current && (candidateT > 0.5 || current == 0) && candidate != 0 { enterRoom(candidate) }
            outsideT = r == 0 ? outsideT + dt : 0
            updateDoors(dt, hs, L)
            buildTimer += dt
            if buildTimer > 0.1 { buildTimer = 0; buildSome(fit, I) }
        }

        // 안전: 공간을 아직 못 찾았거나, 구성한 방 밖이거나, 너무 빠르면 현실이 보이게
        var target: Float = 1
        var why: String?
        if fit == nil || !ready { target = 0 }
        else if outsideT > 0.6 { target = 0; why = "구성한 방 밖이에요. 현실이 보이게 했어요." }
        else if speed > 1.4 { target = 0; why = "천천히 걸어 주세요. 잠시 현실이 보여요." }
        let rate: Float = target < fade ? 3 : 1.1
        fade += (target - fade) * min(1, dt * rate)
        if abs(fade - appliedFade) > 0.01 || (target == 1 && fade > 0.99 && appliedFade < 1) {
            let v = fade > 0.99 ? 1 : fade
            spaceRoot.components.set(OpacityComponent(opacity: v))
            skinRoot.components.set(OpacityComponent(opacity: v))
            appliedFade = v
        }
        if fit != nil {
            let total = data?.rec.rooms.count ?? 0
            let msg = ready ? (why ?? player.status) : "다른 세계를 준비하는 중이에요 (\(worlds.count)/\(total))"
            if msg != message { message = msg }
        }

        for (id, wld) in worlds { wld.tick(dt, active: id == current) }
        soundTick(dt)
        placeHud(dt)
    }

    private func enterRoom(_ r: Int) {
        current = r
        doorOpen.removeAll()                                // 넘어오면 뒤의 문은 다시 닫힘 (이 방 벽처럼)
        guard let d = data, let L = layout, let rm = d.rec.room(r) else { return }
        if worlds[r] == nil {                               // 아직 못 만든 방이면 바로 만듦
            addWorld(d, rm, L)
            dirty.formUnion(meshes.keys)
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

    // MARK: 문 (다른 세계 사이)
    /// 기준은 모두 1m: 같은 세계끼리는 늘 열림. 다른 세계 사이는 평소 지금 방의 벽처럼 닫혀 있고,
    /// 1m 안으로 다가가면 문틀·열쇠 구멍·떠 있는 황금 열쇠가 보이며 그 열쇠를 누르면 열림.
    /// 열린 문을 지나가면 바로 닫히고(반대편에서도 1m 안이라 닫힌 문이 보임), 지나가지 않고 1m 밖으로 멀어져도 닫힘
    static let doorReach: Float = 1.0

    private func updateDoors(_ dt: Float, _ hs: SIMD3<Float>, _ L: Layout) {
        guard let d = data else { return }
        let p = L.plane(hs.x, hs.z)
        for (i, ds) in L.doors.enumerated() {
            var same = false
            if let ra = d.rec.room(ds.roomA), let rb = d.rec.room(ds.roomB) {
                same = ra.place == rb.place && ra.weather == rb.weather && ra.time == rb.time
            }
            let dist = Self.segDist(p, ds.a, ds.b)
            let side = simd_dot(p - ds.a, ds.n)                     // + 면 roomA 쪽
            let here = side >= 0 ? ds.roomA : ds.roomB             // 지금 서 있는 쪽 방
            if doorOpen.contains(i) {
                let crossed = (doorSide[i] ?? side) * side < 0 && abs(side) > 0.1
                if crossed || dist > Self.doorReach { doorOpen.remove(i) }
            }
            let target: Float = (same || doorOpen.contains(i)) ? 0 : 1
            var st = doorState[i] ?? target
            if st != target {
                st += (target - st) * min(1, dt * 6)
                if abs(st - target) < 0.01 { st = target }
            }
            doorState[i] = st
            for rid in [ds.roomA, ds.roomB] {
                for e in worlds[rid]?.doorPanels[i] ?? [] {
                    e.isEnabled = st > 0.01
                    e.scale = SIMD3<Float>(max(0.001, st), 1, 1)
                }
            }
            let want: Float = (!same && dist < Self.doorReach && !doorOpen.contains(i)) ? 1 : 0
            var sh = doorShow[i] ?? 0
            sh += (want - sh) * min(1, dt * 4)
            if abs(sh - want) < 0.01 { sh = want }
            doorShow[i] = sh
            for rid in [ds.roomA, ds.roomB] {
                guard let ui = worlds[rid]?.doorUI[i] else { continue }
                let v: Float = rid == here ? sh : 0
                ui.root.isEnabled = v > 0.02
                if ui.root.isEnabled {
                    ui.root.components.set(OpacityComponent(opacity: v))
                    let breath = 0.5 + 0.5 * sin(t * 2.4)                                     // 숨 쉬듯
                    ui.glow.components.set(OpacityComponent(opacity: 0.25 + 0.6 * breath))
                    ui.key.position = [0, 0.012 * sin(t * 1.3), 0]                           // 둥실둥실
                    ui.key.orientation = simd_quatf(angle: 0.35 * sin(t * 0.7), axis: [0, 1, 0])
                }
            }
        }
    }

    static func segDist(_ p: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        let ab = b - a
        let k = simd_clamp(simd_dot(p - a, ab) / max(simd_dot(ab, ab), 1e-6), 0, 1)
        return simd_distance(p, a + ab * k)
    }

    /// 떠 있는 열쇠를 누름 (바라보고 손가락 집기 · 직접 누르기)
    func tapped(_ e: Entity) {
        var cur: Entity? = e
        while let c = cur {
            if c.name.hasPrefix("door-"), let i = Int(c.name.dropFirst(5)) {
                if (doorShow[i] ?? 0) > 0.3, let L = layout, let f = fit, i < L.doors.count {
                    let hs = f.toSaved(head)
                    let p = L.plane(hs.x, hs.z)
                    let ds = L.doors[i]
                    if Self.segDist(p, ds.a, ds.b) < Self.doorReach {
                        doorSide[i] = simd_dot(p - ds.a, ds.n)
                        doorOpen.insert(i)
                    }
                }
                return
            }
            cur = c.parent
        }
    }

    // MARK: 실제 그물(가구·물건) 입히기
    /// 가까운 그물부터 (방에 들어서면 그 방 가구가 먼저 입혀짐), 동시에 4개까지
    private func buildSome(_ fit: Fit, _ I: SkinInfo) {
        let now = CACurrentMediaTime()
        guard building.count < 4 else { return }
        var cand: [(UUID, Float)] = []
        for id in dirty where !building.contains(id) {
            guard let a = meshes[id] else { dirty.remove(id); continue }
            let fresh = meshEnts[id] == nil
            if !fresh, let last = builtAt[id], now - last < 1.0 { continue }
            let p = simd_make_float3(a.originFromAnchorTransform.columns.3)
            cand.append((id, simd_distance(p.xz, head.xz) - (fresh ? 3 : 0)))     // 아직 한 번도 안 입힌 것 먼저
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
                apply(id, res.groups)
                setLiveCells(id, res.cells)
            }
        }
    }

    private func apply(_ id: UUID, _ groups: [SkinGroup]) {
        var descs: [MeshDescriptor] = []
        var ms: [RealityKit.Material] = []
        for g in groups where !g.idx.isEmpty {
            var d = MeshDescriptor(name: "g\(g.room)_\(g.shade)")
            d.positions = MeshBuffers.Positions(g.pos)
            d.textureCoordinates = MeshBuffers.TextureCoordinates(g.uv)
            d.primitives = .triangles(g.idx)
            d.materials = .allFaces(UInt32(ms.count))
            descs.append(d)
            ms.append(material(g.room, g.shade))
        }
        let e: ModelEntity
        if let old = meshEnts[id] { e = old } else { e = ModelEntity(); skinRoot.addChild(e); meshEnts[id] = e }
        if !descs.isEmpty, let mesh = try? MeshResource.generate(from: descs) {
            e.model = ModelComponent(mesh: mesh, materials: ms)
        } else {
            e.model = nil
        }
    }

    private func material(_ room: Int, _ shade: Int) -> UnlitMaterial {
        let key = room * 4 + shade
        if let m = mats[key] { return m }
        let m: UnlitMaterial
        if let wld = worlds[room] {
            let st = wld.style
            let k = wld.shades[min(2, shade)]
            // 가구·물건은 둘레보다 조금 밝게 (부딪히지 않게 눈에 잘 띄도록)
            m = Tex.unlit(st.prop, tint: Worlds.safe(st.propTint * wld.tint * k * 1.15, min: 0.4))
        } else {
            return UnlitMaterial(color: .gray)          // 방 세계를 아직 만드는 중: 다음에 다시 만듦
        }
        mats[key] = m
        return m
    }

    // MARK: 안내판
    /// 내려다볼 때만 보이는 안내판 (공간을 찾는 중이거나, 알릴 말이 있거나, 테마를 고르는 중이면 늘 보임)
    private func placeHud(_ dt: Float) {
        guard let hud else { return }
        var f = SIMD3<Float>(fwd.x, 0, fwd.z)
        if simd_length(f) > 0.15 {
            f = simd_normalize(f)
            let yaw = atan2(-f.x, -f.z)
            var dy = yaw - hudYaw
            while dy > .pi { dy -= 2 * .pi }
            while dy < -.pi { dy += 2 * .pi }
            let follow: Float = themeOpen ? 0.9 : 0.45                 // 테마를 고르는 동안은 덜 따라옴 (손을 뻗을 수 있게)
            if !hudPlaced { hudYaw = yaw; hudPlaced = true } else if abs(dy) > follow { hudYaw += dy * min(1, dt * 2.5) }
        }
        let q = simd_quatf(angle: hudYaw, axis: [0, 1, 0])
        let target = head + q.act(themeOpen ? SIMD3<Float>(0, -0.4, -0.6) : SIMD3<Float>(0, -0.55, -0.5))
        hud.position = hud.position + (target - hud.position) * min(1, dt * 5)
        hud.orientation = q * simd_quatf(angle: themeOpen ? -0.3 : -0.5, axis: [1, 0, 0])
        let want: Float = (message != nil || themeOpen || fwd.y < -0.45) ? 1 : 0
        hudShow += (want - hudShow) * min(1, dt * 5)
        hud.components.set(OpacityComponent(opacity: hudShow))
        hud.isEnabled = hudShow > 0.02
    }
}
