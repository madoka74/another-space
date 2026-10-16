import SwiftUI
import CoreGraphics

/// 방 편집: 위에서 본 지도에서 방을 고르고 → 합치기 · 나누기(선 긋기) · 빼기 · 이름 · 세계(장소·날씨·시간) 정하기.
/// 바꿀 때마다 바로 저장됨.
struct MapEditView: View {
    let spaceId: String
    @State private var data: SpaceData?
    @State private var selected: Int?
    @State private var tool: Tool = .select
    @State private var dragA: CGPoint?
    @State private var dragB: CGPoint?
    @State private var undo: [SpaceData] = []
    @State private var renaming = false
    @State private var nameText = ""
    @State private var spaceName = ""
    @State private var toast: String?
    @State private var mapImage: CGImage?
    @State private var labels: [MapLabel] = []

    enum Tool { case select, merge, split }
    struct MapLabel: Identifiable { let id: Int; let p: CGPoint }

    var body: some View {
        Group {
            if let d = data {
                HStack(spacing: 0) {
                    mapArea(d)
                    Divider()
                    panel(d).frame(width: 380)
                }
            } else {
                Text("공간을 불러오지 못했어요.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle(spaceName.isEmpty ? "방 편집" : spaceName)
        .onAppear(perform: load)
        .alert("방 이름", isPresented: $renaming) {
            TextField("이름", text: $nameText)
            ForEach(["거실", "주방", "안방", "침실", "작은방", "서재", "화장실", "드레스룸", "베란다", "현관", "복도"], id: \.self) { n in
                Button(n) { rename(n) }
            }
            Button("이대로") { rename(nameText) }
            Button("취소", role: .cancel) {}
        }
    }

    // MARK: 지도
    private func mapArea(_ d: SpaceData) -> some View {
        GeometryReader { geo in
            let s = min(geo.size.width / CGFloat(d.w), geo.size.height / CGFloat(d.h))
            let ox = (geo.size.width - CGFloat(d.w) * s) / 2, oy = (geo.size.height - CGFloat(d.h) * s) / 2
            ZStack(alignment: .topLeading) {
                if let img = mapImage {
                    Image(decorative: img, scale: 1)
                        .resizable()
                        .interpolation(.none)
                        .frame(width: CGFloat(d.w) * s, height: CGFloat(d.h) * s)
                        .offset(x: ox, y: oy)
                }
                ForEach(labels) { item in
                    if let r = d.rec.room(item.id) {
                        VStack(spacing: 2) {
                            Text(r.name).font(.headline)
                            Text(r.title).font(.caption)
                        }
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.7), radius: 3)
                        .fixedSize()
                        .position(x: ox + item.p.x * s, y: oy + item.p.y * s)
                        .allowsHitTesting(false)
                    }
                }
                if let a = dragA, let b = dragB {
                    Path { p in p.move(to: a); p.addLine(to: b) }
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [10, 8]))
                        .allowsHitTesting(false)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { loc in
                tap(CGPoint(x: (loc.x - ox) / s, y: (loc.y - oy) / s))
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 12, coordinateSpace: .local)
                    .onChanged { v in
                        guard tool == .split else { return }
                        dragA = v.startLocation; dragB = v.location
                    }
                    .onEnded { v in
                        guard tool == .split else { return }
                        let a = SIMD2<Float>(Float((v.startLocation.x - ox) / s), Float((v.startLocation.y - oy) / s))
                        let b = SIMD2<Float>(Float((v.location.x - ox) / s), Float((v.location.y - oy) / s))
                        dragA = nil; dragB = nil
                        split(a, b)
                    }
            )
        }
        .padding(24)
        .background(Color.black.opacity(0.25))
    }

    // MARK: 오른쪽 판
    private func panel(_ d: SpaceData) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                TextField("공간 이름 (예: 우리 집)", text: $spaceName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { saveName() }
                Text(hint(d)).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let id = selected, let r = d.rec.room(id) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Circle().fill(RoomColor.of(id)).frame(width: 12, height: 12)
                            Text(r.name).font(.title2.weight(.semibold))
                            Spacer()
                            Button("이름") { nameText = r.name; renaming = true }
                        }
                        Text(String(format: "%.1f㎡ · 천장 %.1fm", d.area(of: id), r.ceil)).font(.subheadline).foregroundStyle(.secondary)
                        Text(r.title).font(.headline)
                        Picker("장소", selection: bind(id, \.place)) { ForEach(Worlds.places, id: \.id) { Text($0.label).tag($0.id) } }
                        Picker("날씨", selection: bind(id, \.weather)) { ForEach(Worlds.weathers, id: \.id) { Text($0.label).tag($0.id) } }
                        Picker("시간", selection: bind(id, \.time)) { ForEach(Worlds.times, id: \.id) { Text($0.label).tag($0.id) } }
                        Button { change { $0.shuffle(id) } } label: { Label("이 방 세계 다시 섞기", systemImage: "dice") }
                    }
                    .padding(16)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
                    HStack(spacing: 10) {
                        toolButton("합치기", "arrow.triangle.merge", .merge)
                        toolButton("나누기", "scissors", .split)
                        Button(role: .destructive) { exclude(id) } label: { Label("빼기", systemImage: "minus.circle") }
                    }
                }
                Divider()
                Button { change { $0.shuffleAll() }; flash("모든 방의 세계를 새로 섞었어요") } label: {
                    Label("모든 방 세계 섞기", systemImage: "shuffle")
                }
                Button { change { $0.resegment() }; selected = nil; flash("처음 자동 구분으로 되돌렸어요") } label: {
                    Label("방 구분 처음부터 다시", systemImage: "arrow.counterclockwise")
                }
                Button { doUndo() } label: { Label("되돌리기", systemImage: "arrow.uturn.backward") }
                    .disabled(undo.isEmpty)
                if let t = toast { Text(t).font(.callout).foregroundStyle(.secondary) }
            }
            .padding(24)
        }
    }

    private func toolButton(_ title: String, _ icon: String, _ t: Tool) -> some View {
        Button {
            tool = tool == t ? .select : t
        } label: {
            Label(title, systemImage: icon)
        }
        .buttonStyle(.bordered)
        .tint(tool == t ? Color.accentColor : nil)
    }

    private func hint(_ d: SpaceData) -> String {
        let name = selected.flatMap { d.rec.room($0)?.name } ?? ""
        switch tool {
        case .select:
            return selected == nil ? "지도에서 방을 눌러 고르세요. 방마다 장소·날씨·시간이 정해져 있고, 탐험할 때 그 방에 들어가면 그 세계가 펼쳐져요."
                : "다른 방을 누르면 그 방이 골라져요."
        case .merge: return "'\(name)'에 합칠 방을 누르세요. (한 공간이 둘로 나뉘었을 때)"
        case .split: return "'\(name)'을 가로지르게 지도 위에 선을 그으세요. (거실과 주방처럼 하나로 묶인 곳을 나눌 때)"
        }
    }

    // MARK: 동작
    private func load() {
        guard let d = SpaceStore.load(spaceId) else { return }
        data = d
        spaceName = d.rec.name
        refresh()
    }

    private func tap(_ p: CGPoint) {
        guard let d = data else { return }
        let r = d.roomAt(Int(floor(p.x)), Int(floor(p.y)))
        switch tool {
        case .merge:
            guard let to = selected, r != 0, r != to else { return }
            change { $0.merge(r, into: to) }
            tool = .select
            flash("합쳤어요")
        default:
            selected = r == 0 ? nil : r
            if tool == .split, r == 0 { tool = .select }
            refresh()
        }
    }

    private func split(_ a: SIMD2<Float>, _ b: SIMD2<Float>) {
        guard var d = data else { return }
        var target = selected ?? 0
        if target == 0 {
            let m = (a + b) / 2
            target = d.roomAt(Int(m.x), Int(m.y))
        }
        guard target != 0 else { return }
        let before = d
        if let nid = d.split(target, a, b) {
            push(before)
            data = d
            selected = nid
            tool = .select
            persist()
            flash("둘로 나눴어요. 새로 생긴 쪽 이름을 붙여 주세요.")
        } else {
            flash("선이 방을 가로질러야 나눌 수 있어요")
        }
    }

    private func exclude(_ id: Int) {
        change { $0.exclude(id) }
        selected = nil
        flash("뺀 곳은 탐험할 때 현실 그대로 보여요")
    }

    private func rename(_ n: String) {
        let t = n.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, let id = selected else { return }
        change { d in if let i = d.rec.rooms.firstIndex(where: { $0.id == id }) { d.rec.rooms[i].name = t } }
    }

    private func bind(_ id: Int, _ kp: WritableKeyPath<RoomRec, String>) -> Binding<String> {
        Binding(get: { data?.rec.room(id)?[keyPath: kp] ?? "" },
                set: { v in change { d in if let i = d.rec.rooms.firstIndex(where: { $0.id == id }) { d.rec.rooms[i][keyPath: kp] = v } } })
    }

    private func change(_ f: (inout SpaceData) -> Void) {
        guard var d = data else { return }
        let before = d
        f(&d)
        guard d != before else { return }
        push(before)
        data = d
        persist()
    }

    private func push(_ d: SpaceData) {
        undo.append(d)
        if undo.count > 20 { undo.removeFirst() }
    }

    private func doUndo() {
        guard let last = undo.popLast() else { return }
        data = last
        if let s = selected, last.rec.room(s) == nil { selected = nil }
        persist()
    }

    private func saveName() {
        guard var d = data else { return }
        d.rec.name = spaceName.trimmingCharacters(in: .whitespaces)
        data = d
        persist()
    }

    private func persist() {
        guard let d = data else { return }
        try? SpaceStore.save(d)
        AppModel.shared.reload()
        refresh()
    }

    private func flash(_ s: String) {
        toast = s
        Task {
            try? await Task.sleep(for: .seconds(3))
            if toast == s { toast = nil }
        }
    }

    /// 지도 그림·이름표 다시 만들기
    private func refresh() {
        guard let d = data else { return }
        mapImage = Self.render(d, selected: selected)
        labels = d.rec.rooms.compactMap { r in d.centroid(of: r.id).map { MapLabel(id: r.id, p: CGPoint(x: CGFloat($0.x), y: CGFloat($0.y))) } }
    }

    /// 한 칸 = 한 점인 지도 그림 (방 색, 고른 방은 밝게, 벽은 회색)
    static func render(_ d: SpaceData, selected: Int?) -> CGImage? {
        let n = d.w * d.h
        var px = [UInt8](repeating: 0, count: n * 4)
        for i in 0..<n {
            var c: (Double, Double, Double, Double) = (0, 0, 0, 0)
            let r = Int(d.room[i])
            if r > 0 {
                let k = RoomColor.rgb(r)
                let dim = selected == nil || selected == r ? 1.0 : 0.45
                c = (k.0 * dim, k.1 * dim, k.2 * dim, 1)
            } else if d.kind[i] == RoomSegment.WALL {
                c = (0.82, 0.82, 0.84, 1)
            } else if d.kind[i] == RoomSegment.FLOOR {
                c = (0.3, 0.3, 0.32, 0.6)
            }
            px[i * 4] = UInt8(c.0 * c.3 * 255)          // 미리 곱한 알파
            px[i * 4 + 1] = UInt8(c.1 * c.3 * 255)
            px[i * 4 + 2] = UInt8(c.2 * c.3 * 255)
            px[i * 4 + 3] = UInt8(c.3 * 255)
        }
        guard let prov = CGDataProvider(data: Data(px) as CFData) else { return nil }
        return CGImage(width: d.w, height: d.h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: d.w * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: prov, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
