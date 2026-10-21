import SwiftUI

/// 고른 방·문을 조정하는 창 (공간설정 화면 옆에 따로 떠서 옮길 수 있음)
struct ShapeInspector: View {
    @State private var renaming = false
    @State private var nameText = ""
    @FocusState private var typing: Int?           // 폭·깊이 숫자 입력 중 (다른 버튼을 누르면 키보드를 닫음)
    private var m: EditModel { EditModel.shared }

    var body: some View {
        Group {
            if let d = m.data, !m.picked.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header(d)
                        actions
                        fineBox
                        if m.pickedRooms.count == 1, let rid = m.pickedRooms.first, let r = d.rec.room(rid) {
                            world(r, d)
                        }
                    }
                    .padding(24)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "hand.tap").font(.largeTitle)
                    Text("지도나 방 목록에서 고르세요").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .alert("방 이름", isPresented: $renaming) {
            TextField("이름", text: $nameText)
            Button("이대로") { m.rename(nameText) }
            Button("취소", role: .cancel) {}
        }
    }

    @ViewBuilder
    private func header(_ d: SpaceData) -> some View {
        let picked = m.picked
        if m.pickedRooms.count == 1, let rid = m.pickedRooms.first, let r = d.rec.room(rid) {
            HStack(spacing: 10) {
                Circle().fill(RoomColor.of(r.id)).frame(width: 14, height: 14)
                Text(r.name).font(.title2.weight(.bold))
                Spacer()
                Menu {
                    ForEach(["거실", "주방", "거실·주방", "안방", "침실", "작은방", "서재", "화장실", "욕실", "드레스룸", "베란다", "현관", "복도"], id: \.self) { n in
                        Button(n) { m.rename(n) }
                    }
                    Button("직접 입력…") { nameText = r.name; renaming = true }
                } label: { Label("이름", systemImage: "pencil") }
            }
            if picked.count > 1 { Text("사각형 \(picked.count)개").foregroundStyle(.secondary) }
        } else if picked.allSatisfy(\.isDoor) {
            Label(picked.count == 1 ? "문·통로" : "문·통로 \(picked.count)개", systemImage: "door.left.hand.open").font(.title2.weight(.bold))
        } else {
            Label("사각형 \(picked.count)개", systemImage: "square.on.square").font(.title2.weight(.bold))
        }
    }

    private var actions: some View {
        let picked = m.picked
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            Button { m.change { $0.combine(m.sel) }; m.flash("한 방으로 합쳤어요") } label: { Label("결합", systemImage: "rectangle.3.group").frame(maxWidth: .infinity) }
                .disabled(m.pickedRooms.count < 2)
            Button { m.change { $0.separate(m.sel) }; m.flash("각각 다른 방으로 나눴어요") } label: { Label("분리", systemImage: "rectangle.split.2x1").frame(maxWidth: .infinity) }
                .disabled(!m.canSeparate())
            if picked.allSatisfy(\.isDoor) {
                Button { m.change { $0.setDoor(m.sel, false) } } label: { Label("방으로", systemImage: "square").frame(maxWidth: .infinity) }
            } else {
                Button { m.change { $0.setDoor(m.sel, true) } } label: { Label("문·통로로", systemImage: "door.left.hand.open").frame(maxWidth: .infinity) }
            }
            Button(role: .destructive) {
                let ids = Set(m.sel)
                m.change { $0.deleteShapes(ids) }
                m.sel = []
            } label: { Label("지우기", systemImage: "trash").frame(maxWidth: .infinity) }
        }
        .buttonStyle(.bordered)
    }

    /// 위아래좌우 한 칸씩 옮기기(고른 것 모두), 폭·깊이(하나 골랐을 때)
    private var fineBox: some View {
        let picked = m.picked
        let step = m.step
        return VStack(alignment: .leading, spacing: 12) {
            Picker("한 번에", selection: Binding(get: { m.step }, set: { m.step = $0 })) {
                Text("1cm").tag(Float(0.01)); Text("5cm").tag(Float(0.05)); Text("10cm").tag(Float(0.1))
            }
            .pickerStyle(.segmented)
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right").frame(width: 40)
                Button { typing = nil; m.nudge(-step, 0) } label: { Image(systemName: "arrow.left").frame(width: 34, height: 26) }
                Button { typing = nil; m.nudge(0, -step) } label: { Image(systemName: "arrow.up").frame(width: 34, height: 26) }
                Button { typing = nil; m.nudge(0, step) } label: { Image(systemName: "arrow.down").frame(width: 34, height: 26) }
                Button { typing = nil; m.nudge(step, 0) } label: { Image(systemName: "arrow.right").frame(width: 34, height: 26) }
            }
            if picked.count == 1, let s = picked.first {
                sizeRow("arrow.left.and.right", tag: 1, Int((s.width * 100).rounded())) { cm in m.resize(s.id, w: Float(cm) / 100, d: nil) }
                sizeRow("arrow.up.and.down", tag: 2, Int((s.depth * 100).rounded())) { cm in m.resize(s.id, w: nil, d: Float(cm) / 100) }
            }
        }
        .buttonStyle(.bordered)
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func sizeRow(_ icon: String, tag: Int, _ cm: Int, _ set: @escaping (Int) -> Void) -> some View {
        let st = Int((m.step * 100).rounded())
        return HStack(spacing: 8) {
            Image(systemName: icon).frame(width: 40)
            Button { typing = nil; set(max(20, cm - st)) } label: { Image(systemName: "minus").frame(width: 30, height: 26) }
            TextField("cm", value: Binding(get: { cm }, set: { v in set(max(20, min(3000, v))) }), format: .number)
                .textFieldStyle(.roundedBorder)
                .focused($typing, equals: tag)
                .frame(width: 90)
                .multilineTextAlignment(.trailing)
            Text("cm").foregroundStyle(.secondary)
            Button { typing = nil; set(min(3000, cm + st)) } label: { Image(systemName: "plus").frame(width: 30, height: 26) }
        }
    }

    /// 방의 세계·천장 높이
    private func world(_ r: RoomRec, _ d: SpaceData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(r.title).font(.headline)
                Spacer()
                if d.rec.isUnified { Label("모든 방", systemImage: "square.on.square").font(.caption).foregroundStyle(.secondary) }
            }
            ThemePicker(room: r) { p, w, t, l in
                m.change { d in d.setTheme(r.id, place: p, weather: w, time: t, look: l) }
            }
            Stepper(value: Binding(get: { Double(r.ceil) }, set: { v in m.change { d in d.updateRoom(r.id) { rr in rr.ceil = Float(v) } } }),
                    in: 2.0...3.6, step: 0.05) {
                Label(String(format: "천장 %.2fm", r.ceil), systemImage: "arrow.up.to.line")
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }
}
