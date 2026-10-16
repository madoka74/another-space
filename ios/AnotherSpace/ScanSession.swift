import SwiftUI
import RealityKit
import ARKit
import QuartzCore

/// 공간 스캔: 집 안을 걸어 다니면 비전프로가 알아본 바닥(청록)·벽과 물건(금빛)이 반투명하게 덮임 → 저장하면 방 자동 구분
struct ScanView: View {
    let replace: String?
    @State private var s: ScanSession

    init(replace: String?) {
        self.replace = replace
        _s = State(initialValue: ScanSession(replace: replace))
    }

    var body: some View {
        RealityView { content, attachments in
            content.add(s.root)
            if let hud = attachments.entity(for: "hud") { s.attachHud(hud) }
            s.updateSub = content.subscribe(to: SceneEvents.Update.self) { e in s.tick(Float(e.deltaTime)) }
        } attachments: {
            Attachment(id: "hud") { ScanHud(s: s) }
        }
        .task { await s.start() }
        .onDisappear { s.stop() }
    }
}

private struct ScanHud: View {
    let s: ScanSession

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("공간 스캔").font(.title.weight(.bold))
            Text(s.guide).font(.title3).fixedSize(horizontal: false, vertical: true)
            Text(s.stat).font(.headline).foregroundStyle(.secondary)
            if let m = s.message { Text(m).font(.headline).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true) }
            HStack(spacing: 14) {
                Button("취소") { s.cancel() }
                Spacer()
                Button {
                    s.save()
                } label: {
                    if s.saving { ProgressView() } else { Text("저장하고 방 나누기").font(.title3.weight(.semibold)) }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!s.canSave || s.saving)
            }
        }
        .padding(28)
        .frame(width: 560)
        .glassBackgroundEffect()
    }
}

@MainActor @Observable
final class ScanSession {
    var guide = "집 안의 모든 방을 천천히 걸어 다니며 바닥과 벽을 골고루 바라봐 주세요. 문턱을 넘어 방 안쪽까지 들어가야 그 방이 생겨요."
    var stat = "공간을 알아보는 중…"
    var canSave = false
    var saving = false
    var message: String?

    let root = Entity()
    @ObservationIgnored var updateSub: EventSubscription?
    @ObservationIgnored private let replace: String?
    @ObservationIgnored private let ar = ARKitSession()
    @ObservationIgnored private var world: WorldTrackingProvider?
    @ObservationIgnored private var anchors: [UUID: MeshAnchor] = [:]
    @ObservationIgnored private var viz: [UUID: ModelEntity] = [:]
    @ObservationIgnored private var vizAt: [UUID: Double] = [:]
    @ObservationIgnored private var floorArea: [UUID: Float] = [:]
    @ObservationIgnored private var path: [SIMD3<Float>] = []
    @ObservationIgnored private var walked: Float = 0
    @ObservationIgnored private var head = SIMD3<Float>(0, 1.5, 0)
    @ObservationIgnored private var fwd = SIMD3<Float>(0, 0, -1)
    @ObservationIgnored private var hud: Entity?
    @ObservationIgnored private var hudYaw: Float = 0
    @ObservationIgnored private var hudPlaced = false
    @ObservationIgnored private var statTimer: Float = 0
    @ObservationIgnored private var ended = false
    @ObservationIgnored private var floorMat: UnlitMaterial
    @ObservationIgnored private var otherMat: UnlitMaterial

    init(replace: String?) {
        self.replace = replace
        var f = UnlitMaterial(color: UIColor(red: 0.35, green: 0.85, blue: 0.82, alpha: 1))
        f.blending = .transparent(opacity: .init(floatLiteral: 0.28))
        var o = UnlitMaterial(color: UIColor(red: 0.95, green: 0.78, blue: 0.45, alpha: 1))
        o.blending = .transparent(opacity: .init(floatLiteral: 0.16))
        floorMat = f
        otherMat = o
    }

    func start() async {
        let auth = await ar.requestAuthorization(for: [.worldSensing])
        guard auth[.worldSensing] == .allowed else {
            message = "주변 공간 알아보기를 허락해야 스캔할 수 있어요. 설정 > 개인정보 보호 및 보안에서 이 앱을 켜 주세요."
            return
        }
        let w = WorldTrackingProvider()
        let m = SceneReconstructionProvider(modes: [.classification])
        world = w
        do { try await ar.run([w, m]) } catch {
            message = "공간 인식을 시작하지 못했어요. 닫았다가 다시 열어 주세요."
            return
        }
        for await u in m.anchorUpdates {
            let a = u.anchor
            switch u.event {
            case .removed:
                anchors[a.id] = nil
                floorArea[a.id] = nil
                viz.removeValue(forKey: a.id)?.removeFromParent()
            default:
                anchors[a.id] = a
                show(a)
            }
        }
    }

    func stop() {
        updateSub?.cancel()
        ar.stop()
        if !ended { ended = true; AppModel.shared.disappeared() }
    }

    func attachHud(_ e: Entity) {
        hud = e
        e.position = [0, 1.2, -0.8]
        root.addChild(e)
    }

    /// 알아본 그물을 반투명하게 보여 줌 (0.6초에 한 번만 다시 만듦): 바닥은 청록, 나머지는 금빛
    private func show(_ a: MeshAnchor) {
        let now = CACurrentMediaTime()
        if let e = viz[a.id], let last = vizAt[a.id], now - last < 0.6 {
            e.transform = Transform(matrix: a.originFromAnchorTransform)
            return
        }
        vizAt[a.id] = now
        let v = MeshRead.vertices(a.geometry.vertices)
        let f = MeshRead.indices(a.geometry.faces)
        let cls = MeshRead.classes(a.geometry.classifications, faces: f.count / 3)
        guard v.count >= 3, f.count >= 3 else { return }
        var fl: [UInt32] = [], ot: [UInt32] = []
        var area: Float = 0
        var i = 0, fi = 0
        let up = simd_normalize(simd_make_float3(simd_inverse(a.originFromAnchorTransform) * SIMD4<Float>(0, 1, 0, 0)))
        while i + 2 < f.count {
            let ia = Int(f[i]), ib = Int(f[i + 1]), ic = Int(f[i + 2])
            if ia < v.count, ib < v.count, ic < v.count {
                if cls[fi] == MeshClass.floor {
                    fl += [f[i], f[i + 1], f[i + 2]]
                    let cr = simd_cross(v[ib] - v[ia], v[ic] - v[ia])
                    area += abs(simd_dot(cr, up)) * 0.5
                } else if cls[fi] != MeshClass.ceiling {
                    ot += [f[i], f[i + 1], f[i + 2]]
                }
            }
            i += 3; fi += 1
        }
        floorArea[a.id] = area
        var descs: [MeshDescriptor] = []
        var mats: [RealityKit.Material] = []
        if !fl.isEmpty {
            var d = MeshDescriptor(name: "floor")
            d.positions = MeshBuffers.Positions(v)
            d.primitives = .triangles(fl)
            d.materials = .allFaces(UInt32(mats.count))
            descs.append(d); mats.append(floorMat)
        }
        if !ot.isEmpty {
            var d = MeshDescriptor(name: "other")
            d.positions = MeshBuffers.Positions(v)
            d.primitives = .triangles(ot)
            d.materials = .allFaces(UInt32(mats.count))
            descs.append(d); mats.append(otherMat)
        }
        guard !descs.isEmpty, let mesh = try? MeshResource.generate(from: descs) else { return }
        let e: ModelEntity
        if let old = viz[a.id] { e = old } else { e = ModelEntity(); root.addChild(e); viz[a.id] = e }
        e.model = ModelComponent(mesh: mesh, materials: mats)
        e.transform = Transform(matrix: a.originFromAnchorTransform)
    }

    func tick(_ dt: Float) {
        guard let w = world, w.state == .running,
              let dev = w.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) else { return }
        let m = dev.originFromAnchorTransform
        head = simd_make_float3(m.columns.3)
        fwd = -simd_make_float3(m.columns.2)
        if let last = path.last {
            let d = simd_distance(last.xz, head.xz)
            if d >= 0.3 { path.append(head); walked += d }
        } else {
            path.append(head)
        }
        placeHud(dt)
        statTimer += dt
        if statTimer > 1 {
            statTimer = 0
            let a = floorArea.values.reduce(0, +)
            stat = String(format: "알아본 바닥 %.1f㎡ · 걸은 거리 %.0fm", a, walked)
            canSave = a >= 3 && path.count >= 4
        }
    }

    /// 안내판: 내 앞 조금 아래, 몸을 크게 돌릴 때만 느슨하게 따라옴
    private func placeHud(_ dt: Float) {
        guard let hud else { return }
        var f = SIMD3<Float>(fwd.x, 0, fwd.z)
        if simd_length(f) < 0.2 { return }
        f = simd_normalize(f)
        let yaw = atan2(-f.x, -f.z)
        var dy = yaw - hudYaw
        while dy > .pi { dy -= 2 * .pi }
        while dy < -.pi { dy += 2 * .pi }
        if !hudPlaced { hudYaw = yaw; hudPlaced = true } else if abs(dy) > 0.5 { hudYaw += dy * min(1, dt * 2.5) }
        let q = simd_quatf(angle: hudYaw, axis: [0, 1, 0])
        let target = head + q.act(SIMD3<Float>(0, -0.32, -0.85))
        hud.position = hud.position + (target - hud.position) * min(1, dt * 4)
        hud.orientation = q
    }

    func cancel() {
        guard !ended else { return }
        ended = true
        AppModel.shared.finish()
    }

    /// 저장: 그물 복사 → (다른 스레드) 격자·방 구분 → 월드 앵커 → 파일
    func save() {
        guard !saving, let w = world else { return }
        saving = true
        message = nil
        let input = RoomSegment.Input(meshes: anchors.values.map { MeshCopy($0) }, path: path, headY: head.y)
        let replaceId = replace
        let id = replaceId ?? UUID().uuidString
        let old = replaceId.flatMap { SpaceStore.load($0) }
        let name = old?.rec.name ?? (SpaceStore.list().isEmpty ? "우리 집" : "공간 \(SpaceStore.list().count + 1)")
        Task {
            let built = await Task.detached(priority: .userInitiated) { RoomSegment.build(input, id: id, name: name) }.value
            guard let built else {
                saving = false
                message = "방을 알아보지 못했어요. 바닥이 보이게 조금 더 걸어 다닌 뒤 다시 저장해 주세요."
                return
            }
            var data = built.0
            let pts = built.1
            var recs: [AnchorRec] = []
            for p in pts {
                var t = matrix_identity_float4x4
                t.columns.3 = SIMD4<Float>(p.x, p.y, p.z, 1)
                let a = WorldAnchor(originFromAnchorTransform: t)
                do {
                    try await w.addAnchor(a)
                    recs.append(AnchorRec(a: a.id.uuidString, p: [p.x, p.y, p.z]))
                } catch { continue }
            }
            guard !recs.isEmpty else {
                saving = false
                message = "위치 기억(월드 앵커)을 만들지 못했어요. 잠시 뒤 다시 저장해 주세요."
                return
            }
            data.rec.anchors = recs
            do {
                try SpaceStore.save(data)
            } catch {
                for r in recs { if let u = UUID(uuidString: r.a) { try? await w.removeAnchor(forID: u) } }
                saving = false
                message = "저장하지 못했어요. 다시 눌러 주세요."
                return
            }
            // 다시 스캔: 예전 앵커는 지움
            for r in old?.rec.anchors ?? [] { if let u = UUID(uuidString: r.a) { try? await w.removeAnchor(forID: u) } }
            ended = true
            AppModel.shared.finish(savedId: id, message: "방 \(data.rec.rooms.count)곳으로 나눴어요. 지도에서 합치기·나누기·이름 붙이기로 다듬어 주세요.")
        }
    }
}
