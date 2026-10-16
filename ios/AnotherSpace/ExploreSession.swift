import SwiftUI
import RealityKit
import ARKit
import QuartzCore

/// 탐험: 저장한 공간을 다시 알아본 뒤, 방마다 다른 세계를 입힘.
/// 바닥·천장(하늘)은 저장한 방 모양으로, 벽·가구는 지금 비전프로가 보고 있는 실제 그물로 → 의자를 옮겨도 그 자리에 다시 입혀짐
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
        .task { await s.start() }
        .onDisappear { s.stop() }
    }
}

/// 아래를 내려다보면 보이는 작은 안내판: 지금 세계 이름 + 나가기
private struct ExploreHud: View {
    let s: ExploreSession

    var body: some View {
        VStack(spacing: 10) {
            if !s.title.isEmpty {
                Text(s.title).font(.title2.weight(.semibold))
                if !s.sub.isEmpty { Text(s.sub).font(.headline).foregroundStyle(.secondary) }
            }
            if let m = s.message {
                Text(m).font(.headline).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            Button {
                s.exit()
            } label: {
                Label("현실로 돌아가기", systemImage: "arrow.uturn.backward").font(.title3)
            }
        }
        .padding(22)
        .frame(width: 460)
        .glassBackgroundEffect()
    }
}

/// 격자에서 방 찾기 (다른 스레드에서도 쓰도록 값만 복사)
struct RoomLookup: Sendable {
    let w: Int, h: Int
    let cell: Float, ox: Float, oz: Float
    let ex: SIMD2<Float>, ez: SIMD2<Float>
    let floorY: Float
    let room: [UInt8]
    let ceil: [Float]                // 방 id → 천장 높이(바닥에서)
    let wallTile: [Float]
    let propTile: [Float]
    let sun: [SIMD3<Float>]          // 방 id → 해 방향 (저장 좌표)

    init(_ d: SpaceData) {
        w = d.rec.w; h = d.rec.h; cell = d.rec.cell; ox = d.rec.ox; oz = d.rec.oz
        ex = d.rec.ex; ez = d.rec.ez; floorY = d.rec.floorY
        room = d.room
        var c = [Float](repeating: 2.4, count: 256), wt = [Float](repeating: 2, count: 256), pt = [Float](repeating: 1, count: 256)
        var sn = [SIMD3<Float>](repeating: SIMD3<Float>(0, 1, 0), count: 256)
        for r in d.rec.rooms where r.id < 256 {
            c[r.id] = r.ceil
            let st = Worlds.style(r.place, time: r.time)
            wt[r.id] = st.wallTile; pt[r.id] = st.propTile
            sn[r.id] = Worlds.sunDir(r.time)
        }
        ceil = c; wallTile = wt; propTile = pt; sun = sn
    }

    func roomAt(_ x: Float, _ z: Float, radius: Int = 0) -> Int {
        let d = SIMD2<Float>(x - ox, z - oz)
        let u = Int(floor(simd_dot(d, ex) / cell)), v = Int(floor(simd_dot(d, ez) / cell))
        func at(_ u: Int, _ v: Int) -> Int { (u >= 0 && v >= 0 && u < w && v < h) ? Int(room[v * w + u]) : 0 }
        let r0 = at(u, v)
        if r0 != 0 || radius == 0 { return r0 }
        var best = 0, bd = Int.max
        for dv in -radius...radius {
            for du in -radius...radius {
                let r = at(u + du, v + dv)
                if r != 0, du * du + dv * dv < bd { bd = du * du + dv * dv; best = r }
            }
        }
        return best
    }
}

/// 그물 한 덩어리를 방·종류(벽/물건/창)·그늘별로 나눈 결과
struct SkinGroup: Sendable {
    let room: Int
    let kind: Int        // 0 벽, 1 물건, 2 창(하늘로 열린 창)
    let shade: Int       // 0 해 쪽, 1 옆, 2 그늘
    var pos: [SIMD3<Float>] = []
    var uv: [SIMD2<Float>] = []
    var idx: [UInt32] = []
}

enum Skin {
    /// 실제 그물 → 방마다 입힐 조각들. 방 밖(스캔 안 한 곳·뺀 곳)·천장·바닥 면은 버림(바닥은 따로 깔고, 천장은 하늘)
    static func build(_ m: MeshCopy, _ L: RoomLookup, _ fit: Fit) -> [SkinGroup] {
        var groups: [Int: SkinGroup] = [:]
        let wv = m.v.map { simd_make_float3(m.m * SIMD4<Float>($0, 1)) }
        var i = 0, fi = 0
        while i + 2 < m.f.count {
            defer { i += 3; fi += 1 }
            let ia = Int(m.f[i]), ib = Int(m.f[i + 1]), ic = Int(m.f[i + 2])
            guard ia < wv.count, ib < wv.count, ic < wv.count else { continue }
            let a = wv[ia], b = wv[ib], c = wv[ic]
            let cr = simd_cross(b - a, c - a)
            let len = simd_length(cr)
            guard len > 1e-9 else { continue }
            let n = cr / len
            let cls: UInt8 = fi < m.c.count ? m.c[fi] : 0
            let ctr = fit.toSaved((a + b + c) / 3)
            let ns = fit.dirToSaved(n)
            let hgt = ctr.y - L.floorY
            if hgt < -0.3 { continue }                      // 바닥 아래 (창밖 땅 등)
            // 면이 바라보는 쪽의 방 (벽의 양면이 각자 자기 방으로)
            var r = 0
            let hz = SIMD2<Float>(ns.x, ns.z), hl = simd_length(hz)
            if hl > 0.3 { let dd = hz / hl; r = L.roomAt(ctr.x + dd.x * 0.2, ctr.z + dd.y * 0.2, radius: 1) }
            if r == 0 { r = L.roomAt(ctr.x, ctr.z, radius: 2) }
            if r == 0 || r >= 256 { continue }
            if cls == MeshClass.ceiling || hgt > L.ceil[r] - 0.02 { continue }
            if cls == MeshClass.floor || (ns.y > 0.8 && hgt < 0.07) { continue }
            let kind: Int
            if cls == MeshClass.window { kind = 2 }
            else if cls == MeshClass.wall || cls == MeshClass.door || (abs(ns.y) < 0.5 && hgt > 1.7) { kind = 0 }
            else { kind = 1 }
            let l = simd_dot(ns, L.sun[r])
            let shade = kind == 2 ? 0 : (l > 0.35 ? 0 : (l > -0.15 ? 1 : 2))
            let key = r * 16 + kind * 4 + shade
            var g = groups[key] ?? SkinGroup(room: r, kind: kind, shade: shade)
            let base = UInt32(g.pos.count)
            g.pos += [a, b, c]
            if kind != 2 {
                let tile = kind == 0 ? L.wallTile[r] : L.propTile[r]
                for p in [a, b, c] {
                    let q = fit.toSaved(p)
                    let uv: SIMD2<Float>
                    if abs(ns.y) > 0.7 { uv = SIMD2<Float>(q.x, q.z) }
                    else if abs(ns.x) > abs(ns.z) { uv = SIMD2<Float>(q.z, -q.y) }
                    else { uv = SIMD2<Float>(q.x, -q.y) }
                    g.uv.append(uv / tile)
                }
            } else {
                g.uv += [SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(0, 1)]
            }
            g.idx += [base, base + 1, base + 2, base, base + 2, base + 1]      // 양면
            groups[key] = g
        }
        return Array(groups.values)
    }
}

@MainActor @Observable
final class ExploreSession {
    var title = ""
    var sub = ""
    var message: String? = "공간을 알아보는 중이에요. 스캔했던 곳을 천천히 둘러봐 주세요."

    let root = Entity()
    @ObservationIgnored var updateSub: EventSubscription?
    @ObservationIgnored private let spaceId: String
    @ObservationIgnored private let spaceRoot = Entity()      // 저장 좌표 → 지금 좌표
    @ObservationIgnored private let skinRoot = Entity()       // 실제 그물 (지금 좌표)
    @ObservationIgnored private let ar = ARKitSession()
    @ObservationIgnored private var world: WorldTrackingProvider?
    @ObservationIgnored private var data: SpaceData?
    @ObservationIgnored private var lookup: RoomLookup?
    @ObservationIgnored private var worlds: [Int: RoomWorld] = [:]
    @ObservationIgnored private var saved: [String: AnchorRec] = [:]
    @ObservationIgnored private var allIds: Set<String> = []
    @ObservationIgnored private var live: [String: simd_float4x4] = [:]
    @ObservationIgnored private var fit: Fit?
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
    @ObservationIgnored private var startedAt: Float = 0
    @ObservationIgnored private var ended = false
    @ObservationIgnored private let player = AmbientPlayer()

    init(spaceId: String) {
        self.spaceId = spaceId
    }

    func start() async {
        guard let d = SpaceStore.load(spaceId), !d.rec.rooms.isEmpty else {
            message = "공간을 불러오지 못했어요. 메인 창에서 다시 스캔해 주세요."
            return
        }
        data = d
        lookup = RoomLookup(d)
        for a in d.rec.anchors { saved[a.a] = a }
        allIds = SpaceStore.allAnchorIds()
        root.addChild(spaceRoot)
        root.addChild(skinRoot)
        root.addChild(player.root)
        spaceRoot.components.set(OpacityComponent(opacity: 0))
        skinRoot.components.set(OpacityComponent(opacity: 0))
        for r in d.rec.rooms {
            let w = RoomWorld(d, r)
            spaceRoot.addChild(w.world)
            spaceRoot.addChild(w.local)
            worlds[r.id] = w
        }
        // 소리는 미리 받아 둠 (방에 들어갈 때 바로 나게)
        let rooms = d.rec.rooms
        Task.detached(priority: .utility) {
            let lib = AmbientLibrary.shared
            guard await lib.load() else { return }
            for r in rooms {
                if let b = await lib.bed(r.place, r.time) { _ = await lib.loopFile(b) }
                if let w = await lib.weatherLayer(r.weather, place: r.place) { _ = await lib.loopFile(w) }
            }
        }

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
        await watchWorld(w)
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

    // MARK: 비전프로가 알려 주는 것
    private func watchWorld(_ w: WorldTrackingProvider) async {
        for await u in w.anchorUpdates {
            let a = u.anchor
            let key = a.id.uuidString
            switch u.event {
            case .removed:
                live[key] = nil
            default:
                if saved[key] != nil {
                    if a.isTracked { live[key] = a.originFromAnchorTransform; updateFit() } else { live[key] = nil }
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
        for (k, m) in live {
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
        } else if let one = live.first, let r = saved[one.key] {
            let m = one.value
            let ax = SIMD2<Float>(m.columns.0.x, m.columns.0.z)
            let l = simd_length(ax)
            guard l > 0.1 else { return }
            f.c = ax.x / l; f.s = ax.y / l
            let p = r.pos.xz
            f.t = SIMD2<Float>(m.columns.3.x, m.columns.3.z) - SIMD2<Float>(p.x * f.c - p.y * f.s, p.x * f.s + p.y * f.c)
        }
        if let old = fit, !f.differs(old, meters: 0.08, radians: 0.03) { return }
        let first = fit == nil
        fit = f
        spaceRoot.transform = f.transform
        dirty.formUnion(meshes.keys)          // 그물을 새 좌표로 다시 입힘
        if first { message = nil }
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

        if let fit, let L = lookup {
            // 지금 있는 방 (0.5초 넘게 머물러야 바뀜)
            let hs = fit.toSaved(head)
            let r = L.roomAt(hs.x, hs.z, radius: 3)
            if r != candidate { candidate = r; candidateT = 0 } else { candidateT += dt }
            if candidate != current && (candidateT > 0.5 || current == 0) && candidate != 0 { enterRoom(candidate) }
            outsideT = r == 0 ? outsideT + dt : 0
            buildTimer += dt
            if buildTimer > 0.25 { buildTimer = 0; buildSome(fit, L) }
        }

        // 안전: 공간을 아직 못 찾았거나, 방 밖(스캔 안 한 곳·뺀 곳)이거나, 너무 빠르면 현실이 보이게
        var target: Float = 1
        var why: String?
        if fit == nil { target = 0 }
        else if outsideT > 0.6 { target = 0; why = "스캔한 방 밖이에요. 현실이 보이게 했어요." }
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
            let msg = why ?? player.status
            if msg != message { message = msg }
        }

        for (id, wld) in worlds { wld.tick(dt, active: id == current) }
        soundTick(dt)
        placeHud(dt)
    }

    private func enterRoom(_ r: Int) {
        worlds[current]?.setActive(false)
        current = r
        guard let room = data?.rec.room(r) else { return }
        worlds[r]?.setActive(true)
        title = room.title
        sub = room.name
        player.enter(room)
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

    // MARK: 실제 그물 입히기
    private func buildSome(_ fit: Fit, _ L: RoomLookup) {
        let now = CACurrentMediaTime()
        var started = 0
        for id in dirty where !building.contains(id) {
            if started >= 2 { break }
            if let last = builtAt[id], now - last < 1.5 { continue }
            guard let a = meshes[id] else { dirty.remove(id); continue }
            dirty.remove(id)
            building.insert(id)
            builtAt[id] = now
            started += 1
            let copy = MeshCopy(a)
            Task {
                let groups = await Task.detached(priority: .userInitiated) { Skin.build(copy, L, fit) }.value
                building.remove(id)
                guard !ended, meshes[id] != nil else { return }
                apply(id, groups)
            }
        }
    }

    private func apply(_ id: UUID, _ groups: [SkinGroup]) {
        var descs: [MeshDescriptor] = []
        var ms: [RealityKit.Material] = []
        var portals: [(Int, MeshDescriptor)] = []
        for g in groups where !g.idx.isEmpty {
            var d = MeshDescriptor(name: "g\(g.room)_\(g.kind)_\(g.shade)")
            d.positions = MeshBuffers.Positions(g.pos)
            d.textureCoordinates = MeshBuffers.TextureCoordinates(g.uv)
            d.primitives = .triangles(g.idx)
            if g.kind == 2 { portals.append((g.room, d)); continue }
            d.materials = .allFaces(UInt32(ms.count))
            descs.append(d)
            ms.append(material(g.room, g.kind, g.shade))
        }
        let e: ModelEntity
        if let old = meshEnts[id] { e = old } else { e = ModelEntity(); skinRoot.addChild(e); meshEnts[id] = e }
        for c in Array(e.children) { c.removeFromParent() }
        if !descs.isEmpty, let mesh = try? MeshResource.generate(from: descs) {
            e.model = ModelComponent(mesh: mesh, materials: ms)
        } else {
            e.model = nil
        }
        // 창문 = 그 방 하늘 세계로 열린 창
        for (r, d) in portals {
            guard let wld = worlds[r], let mesh = try? MeshResource.generate(from: [d]) else { continue }
            let p = ModelEntity(mesh: mesh, materials: [PortalMaterial()])
            p.components.set(PortalComponent(target: wld.world))
            e.addChild(p)
        }
    }

    private func material(_ room: Int, _ kind: Int, _ shade: Int) -> UnlitMaterial {
        let key = room * 16 + kind * 4 + shade
        if let m = mats[key] { return m }
        let k: Float = [1.0, 0.8, 0.62][min(2, shade)]
        let m: UnlitMaterial
        if let wld = worlds[room] {
            let st = wld.style
            // 가구·물건은 둘레보다 조금 밝게 (부딪히지 않게 눈에 잘 띄도록)
            m = kind == 0 ? Tex.unlit(st.wall, tint: st.wallTint * wld.tint * k) : Tex.unlit(st.prop, tint: st.propTint * wld.tint * k * 1.18)
        } else {
            m = UnlitMaterial(color: .gray)
        }
        mats[key] = m
        return m
    }

    // MARK: 안내판
    /// 내려다볼 때만 보이는 안내판 (공간을 찾는 중이거나 알릴 말이 있으면 늘 보임)
    private func placeHud(_ dt: Float) {
        guard let hud else { return }
        var f = SIMD3<Float>(fwd.x, 0, fwd.z)
        if simd_length(f) > 0.15 {
            f = simd_normalize(f)
            let yaw = atan2(-f.x, -f.z)
            var dy = yaw - hudYaw
            while dy > .pi { dy -= 2 * .pi }
            while dy < -.pi { dy += 2 * .pi }
            if !hudPlaced { hudYaw = yaw; hudPlaced = true } else if abs(dy) > 0.45 { hudYaw += dy * min(1, dt * 2.5) }
        }
        let q = simd_quatf(angle: hudYaw, axis: [0, 1, 0])
        let target = head + q.act(SIMD3<Float>(0, -0.55, -0.5))
        hud.position = hud.position + (target - hud.position) * min(1, dt * 5)
        hud.orientation = q * simd_quatf(angle: -0.5, axis: [1, 0, 0])
        let want: Float = (message != nil || fwd.y < -0.45) ? 1 : 0
        hudShow += (want - hudShow) * min(1, dt * 5)
        hud.components.set(OpacityComponent(opacity: hudShow))
        hud.isEnabled = hudShow > 0.02
    }
}
