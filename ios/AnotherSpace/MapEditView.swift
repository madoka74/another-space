import SwiftUI
import CoreGraphics

/// 방 구성 편집: 위에서 본 스캔 지도 위에 사각형을 놓아 집을 구성함.
/// - 사각형 그리기: 누른 곳에 점이 바로 보이고, 끌거나 두 번째 점을 누르면 사각형. 다른 사각형·스캔 벽 가까이에서는 착 붙음
/// - 고르기: 누르면 고름(여러 개 고르기 켜면 계속 더함), 모서리 점 4개를 끌어 크기 조절, 몸통을 끌어 옮기기
/// - 결합: 고른 사각형들을 한 방으로 / 분리: 고른 사각형을 하나씩 다른 방으로
/// - 다른 방끼리 맞닿은 곳에는 벽이 섬. 문 그리기로 그 경계에 걸쳐 그린 문·통로 사각형 자리만 뚫림 (틈이 있으면 틈도 메움)
/// - 바라보는 사각형·모서리 점은 빛나서 무엇을 잡을지 미리 보임
/// 바꿀 때마다 바로 저장됨
struct MapEditView: View {
    let spaceId: String
    @State private var data: SpaceData?
    @State private var sel: [Int] = []
    @State private var tool: Tool = .select
    @State private var multi = false
    @State private var zoom: CGFloat = 1
    @State private var zoomBase: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var drag: DragKind?
    @State private var dragStart: SpaceData?
    @State private var dragMoved = false
    @State private var pin: SIMD2<Float>?
    @State private var cursor: SIMD2<Float>?
    @State private var preview: ShapeRec?
    @State private var guides: [Guide] = []
    @State private var undo: [SpaceData] = []
    @State private var bg: CGImage?
    @State private var scanU: [Float] = []
    @State private var scanV: [Float] = []
    @State private var renaming = false
    @State private var nameText = ""
    @State private var spaceName = ""
    @State private var toast: String?
    @State private var unifyRoom: RoomRec?
    @State private var step: Float = 0.05

    enum Tool: Hashable { case select, draw, door }
    enum Guide: Hashable { case u(Float), v(Float) }
    enum DragKind {
        case corner(Int, Int, ShapeRec)        // 사각형 id, 모서리 번호, 끌기 전 모양
        case body(Int, ShapeRec, SIMD2<Float>) // 사각형 id, 끌기 전 모양, 누른 곳(평면 좌표)
        case create(SIMD2<Float>, Bool)        // 시작점, 이미 첫 점이 있었는지(두 번째 점 누르기)
        case pan(CGSize)
        case none
    }

    var body: some View {
        Group {
            if let d = data {
                HStack(spacing: 0) {
                    GeometryReader { geo in mapArea(d, geo.size) }
                        .background(Color.black.opacity(0.3))
                    Divider()
                    panel(d).frame(width: 400)
                }
            } else {
                Text("공간을 불러오지 못했어요.").foregroundStyle(.secondary)
            }
        }
        .navigationTitle(spaceName.isEmpty ? "방 구성" : spaceName)
        .onAppear(perform: load)
        .sheet(item: $unifyRoom) { r in unifySheet(r) }
        .alert("방 이름", isPresented: $renaming) {
            TextField("이름", text: $nameText)
            Button("이대로") { rename(nameText) }
            Button("취소", role: .cancel) {}
        }
    }

    // MARK: 화면 ↔ 평면 좌표
    private struct View2 {
        let scale: CGFloat
        let c: SIMD2<Float>         // 화면 가운데의 평면 좌표
        let size: CGSize
        let pan: CGSize
        func screen(_ p: SIMD2<Float>) -> CGPoint {
            CGPoint(x: size.width / 2 + pan.width + CGFloat(p.x - c.x) * scale, y: size.height / 2 + pan.height + CGFloat(p.y - c.y) * scale)
        }
        func plane(_ q: CGPoint) -> SIMD2<Float> {
            SIMD2<Float>(c.x + Float((q.x - size.width / 2 - pan.width) / scale), c.y + Float((q.y - size.height / 2 - pan.height) / scale))
        }
    }

    private func view2(_ d: SpaceData, _ size: CGSize) -> View2 {
        var lo = SIMD2<Float>(0, 0), hi = d.rec.size
        for s in d.shapes { lo = simd_min(lo, SIMD2<Float>(s.u0, s.v0)); hi = simd_max(hi, SIMD2<Float>(s.u1, s.v1)) }
        let ext = simd_max(hi - lo, SIMD2<Float>(2, 2))
        let base = min(size.width / CGFloat(ext.x), size.height / CGFloat(ext.y)) * 0.92
        return View2(scale: max(4, base * zoom), c: (lo + hi) / 2, size: size, pan: pan)
    }

    // MARK: 지도
    private func mapArea(_ d: SpaceData, _ size: CGSize) -> some View {
        let V = view2(d, size)
        return ZStack(alignment: .bottomTrailing) {
            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in draw(ctx, d, V) }
                hoverLayer(d, V)
            }
                .frame(width: size.width, height: size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { v in dragChanged(v, d, V) }
                        .onEnded { v in dragEnded(v, V) }
                )
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { v in zoom = min(8, max(0.5, zoomBase * v.magnification)) }
                        .onEnded { _ in zoomBase = zoom }
                )
            HStack(spacing: 8) {
                Button { setZoom(zoom / 1.4) } label: { Image(systemName: "minus.magnifyingglass") }
                Button { setZoom(1); pan = .zero } label: { Image(systemName: "arrow.up.left.and.down.right.magnifyingglass") }
                Button { setZoom(zoom * 1.4) } label: { Image(systemName: "plus.magnifyingglass") }
            }
            .padding(14)
        }
    }

    private func setZoom(_ z: CGFloat) { zoom = min(8, max(0.5, z)); zoomBase = zoom }

    /// 바라보는 곳 알려 주기: 사각형·모서리 점마다 보이지 않는 판을 얹어, 시선이 닿으면 시스템이 빛나게 해 줌
    /// (손동작은 이 판들을 감싼 지도 전체가 받음. 겹친 곳은 위에 있는 것 = 잡히는 것이 빛남)
    private func hoverLayer(_ d: SpaceData, _ V: View2) -> some View {
        let picked = Set(sel)
        let rooms = d.shapes.filter { !$0.isDoor && !picked.contains($0.id) }
        let doors = d.shapes.filter { $0.isDoor && !picked.contains($0.id) }
        let chosen = d.shapes.filter { picked.contains($0.id) }
        let order = tool == .select ? rooms + doors + chosen : []
        // 고르기: 고른 사각형의 모서리 / 그리기: 모든 사각형의 모서리 (거기서 시작하면 착 붙음)
        let pts: [CGPoint] = (tool == .select ? chosen : d.shapes).flatMap { s in (0..<4).map { V.screen(s.corner($0)) } }
        let dot: CGFloat = tool == .select ? 52 : 34
        return ZStack(alignment: .topLeading) {
            ForEach(order, id: \.id) { s in
                let r = rect(s, V)
                Rectangle()
                    .fill(Color.white.opacity(0.001))
                    .frame(width: max(2, r.width), height: max(2, r.height))
                    .contentShape(.hoverEffect, Rectangle())
                    .hoverEffect(.highlight)
                    .position(x: r.midX, y: r.midY)
            }
            ForEach(Array(pts.enumerated()), id: \.offset) { _, p in
                Circle()
                    .fill(Color.white.opacity(0.001))
                    .frame(width: dot, height: dot)
                    .contentShape(.hoverEffect, Circle())
                    .hoverEffect(.highlight)
                    .position(p)
            }
        }
    }

    private func draw(_ ctx: GraphicsContext, _ d: SpaceData, _ V: View2) {
        // 스캔 지도 (바닥 어두운 회색, 벽 밝게, 창 하늘색)
        if let bg {
            let a = V.screen(SIMD2<Float>(0, 0)), b = V.screen(d.rec.size)
            var c = ctx
            c.opacity = 0.85
            c.draw(Image(decorative: bg, scale: 1).interpolation(.none), in: CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y))
        }
        // 1m 눈금 (작게)
        if V.scale > 30 {
            var grid = Path()
            let p0 = V.plane(.zero), p1 = V.plane(CGPoint(x: V.size.width, y: V.size.height))
            var u = p0.x.rounded(.down)
            while u <= p1.x { let x = V.screen(SIMD2<Float>(u, 0)).x; grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: V.size.height)); u += 1 }
            var v = p0.y.rounded(.down)
            while v <= p1.y { let y = V.screen(SIMD2<Float>(0, v)).y; grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: V.size.width, y: y)); v += 1 }
            ctx.stroke(grid, with: .color(.white.opacity(0.06)), lineWidth: 1)
        }
        // 사각형 (방 먼저, 문·통로는 그 위에)
        let picked = Set(sel)
        for s in d.shapes.filter({ !$0.isDoor }) + d.shapes.filter(\.isDoor) {
            let r = rect(s, V)
            let path = Path(r)
            if s.isDoor {
                ctx.fill(path, with: .color(.white.opacity(picked.contains(s.id) ? 0.55 : 0.28)))
                ctx.stroke(path, with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            } else {
                let c = RoomColor.of(s.room)
                ctx.fill(path, with: .color(c.opacity(picked.contains(s.id) ? 0.78 : 0.5)))
                ctx.stroke(path, with: .color(c), lineWidth: 2)
            }
        }
        // 방 이름 (방마다 가장 큰 사각형 가운데)
        for room in d.rec.rooms {
            guard let big = d.shapes.filter({ $0.room == room.id }).max(by: { $0.area < $1.area }) else { continue }
            let p = V.screen(big.center)
            ctx.draw(Text(room.name).font(.headline).foregroundColor(.white), at: CGPoint(x: p.x, y: p.y - 9))
            ctx.draw(Text(room.title).font(.caption).foregroundColor(.white.opacity(0.85)), at: CGPoint(x: p.x, y: p.y + 10))
        }
        // 고른 사각형: 굵은 테두리 + 모서리 점 + 크기
        for s in d.shapes where picked.contains(s.id) {
            let r = rect(s, V)
            ctx.stroke(Path(r), with: .color(.white), lineWidth: 3)
            for i in 0..<4 {
                let p = V.screen(s.corner(i))
                let dot = Path(ellipseIn: CGRect(x: p.x - 11, y: p.y - 11, width: 22, height: 22))
                ctx.fill(dot, with: .color(.white))
                ctx.stroke(dot, with: .color(.accentColor), lineWidth: 3)
            }
            if sel.count == 1 {
                ctx.draw(Text(String(format: "%.2f × %.2f m", s.width, s.depth)).font(.caption.weight(.semibold)).foregroundColor(.yellow),
                         at: CGPoint(x: r.midX, y: r.maxY + 14))
            }
        }
        // 정리가 필요한 사각형 (애매한 틈·겹침, 경계에 안 맞는 문): 노란 점선
        let bad = Self.issues(d)
        for s in d.shapes where bad.contains(s.id) {
            ctx.stroke(Path(rect(s, V).insetBy(dx: -3, dy: -3)), with: .color(.yellow), style: StrokeStyle(lineWidth: 2.5, dash: [7, 5]))
        }
        // 붙는 선
        for g in guides {
            var p = Path()
            switch g {
            case .u(let u): let x = V.screen(SIMD2<Float>(u, 0)).x; p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: V.size.height))
            case .v(let v): let y = V.screen(SIMD2<Float>(0, v)).y; p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: V.size.width, y: y))
            }
            ctx.stroke(p, with: .color(.yellow.opacity(0.8)), style: StrokeStyle(lineWidth: 1.2, dash: [6, 5]))
        }
        // 만드는 중인 사각형
        if let pv = preview {
            let r = rect(pv, V)
            ctx.fill(Path(r), with: .color(.yellow.opacity(0.18)))
            ctx.stroke(Path(r), with: .color(.yellow), style: StrokeStyle(lineWidth: 2.5, dash: [8, 6]))
            ctx.draw(Text(String(format: "%.2f × %.2f m", pv.width, pv.depth)).font(.caption.weight(.semibold)).foregroundColor(.yellow),
                     at: CGPoint(x: r.midX, y: r.maxY + 14))
        }
        // 첫 점 / 지금 가리키는 점 (그리기)
        for (p, big) in [(pin, true), (tool != .select ? cursor : nil, false)] {
            guard let p else { continue }
            let q = V.screen(p)
            let r: CGFloat = big ? 12 : 7
            ctx.stroke(Path(ellipseIn: CGRect(x: q.x - r - 6, y: q.y - r - 6, width: 2 * r + 12, height: 2 * r + 12)), with: .color(.yellow.opacity(0.6)), lineWidth: 2)
            ctx.fill(Path(ellipseIn: CGRect(x: q.x - r, y: q.y - r, width: 2 * r, height: 2 * r)), with: .color(.yellow))
        }
    }

    private func rect(_ s: ShapeRec, _ V: View2) -> CGRect {
        let a = V.screen(SIMD2<Float>(s.u0, s.v0)), b = V.screen(SIMD2<Float>(s.u1, s.v1))
        return CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
    }

    // MARK: 붙이기
    private func lines(excluding id: Int?) -> ([Float], [Float]) {
        var us = scanU, vs = scanV
        for s in data?.shapes ?? [] where s.id != id { us += [s.u0, s.u1]; vs += [s.v0, s.v1] }
        return (us, vs)
    }

    /// 가까운 선(다른 사각형 변·스캔 벽)에 붙이고, 없으면 5cm 단위로
    private func snap(_ p: SIMD2<Float>, _ V: View2, excluding id: Int?) -> (SIMD2<Float>, [Guide]) {
        let th = Float(16 / V.scale)
        let (us, vs) = lines(excluding: id)
        var out = p
        var gs: [Guide] = []
        if let u = us.min(by: { abs($0 - p.x) < abs($1 - p.x) }), abs(u - p.x) < th { out.x = u; gs.append(.u(u)) }
        else { out.x = (p.x / 0.05).rounded() * 0.05 }
        if let v = vs.min(by: { abs($0 - p.y) < abs($1 - p.y) }), abs(v - p.y) < th { out.y = v; gs.append(.v(v)) }
        else { out.y = (p.y / 0.05).rounded() * 0.05 }
        return (out, gs)
    }

    /// 사각형을 옮길 때: 네 변 중 선에 가장 가까운 변을 붙임
    private func snapMove(_ s: ShapeRec, _ V: View2) -> (ShapeRec, [Guide]) {
        let th = Float(16 / V.scale)
        let (us, vs) = lines(excluding: s.id)
        var t = s
        var gs: [Guide] = []
        var bu: (Float, Float, Float)?        // (거리, 옮길 양, 붙은 선)
        for e in [s.u0, s.u1] { for u in us { let dd = abs(u - e); if dd < th && dd < (bu?.0 ?? .infinity) { bu = (dd, u - e, u) } } }
        if let b = bu { t.u0 += b.1; t.u1 += b.1; gs.append(.u(b.2)) }
        else { let k = (s.u0 / 0.05).rounded() * 0.05 - s.u0; t.u0 += k; t.u1 += k }
        var bv: (Float, Float, Float)?
        for e in [s.v0, s.v1] { for v in vs { let dd = abs(v - e); if dd < th && dd < (bv?.0 ?? .infinity) { bv = (dd, v - e, v) } } }
        if let b = bv { t.v0 += b.1; t.v1 += b.1; gs.append(.v(b.2)) }
        else { let k = (s.v0 / 0.05).rounded() * 0.05 - s.v0; t.v0 += k; t.v1 += k }
        return (t, gs)
    }

    // MARK: 손동작
    private func dragChanged(_ v: DragGesture.Value, _ d: SpaceData, _ V: View2) {
        let p = V.plane(v.location)
        if drag == nil {
            dragMoved = false
            dragStart = data
            let start = V.plane(v.startLocation)
            if let hit = cornerHit(v.startLocation, d, V), let s = d.shapes.first(where: { $0.id == hit.0 }) {
                drag = .corner(hit.0, hit.1, s)
            } else if tool != .select {
                let sp = snap(start, V, excluding: nil).0
                drag = .create(pin ?? sp, pin != nil)
            } else if let s = shapeHit(start, d) {
                drag = .body(s.id, s, start)
            } else {
                drag = .pan(pan)
            }
        }
        if hypot(v.translation.width, v.translation.height) > 8 { dragMoved = true }
        switch drag {
        case .corner(let id, let i, let s)?:
            guard dragMoved else { return }
            let (q, gs) = snap(p, V, excluding: id)
            let opp = s.corner((i + 2) % 4)
            var t = ShapeRec.span(id: s.id, room: s.room, opp, q)
            if t.width < 0.2 { if q.x < opp.x { t.u0 = opp.x - 0.2 } else { t.u1 = opp.x + 0.2 } }
            if t.depth < 0.2 { if q.y < opp.y { t.v0 = opp.y - 0.2 } else { t.v1 = opp.y + 0.2 } }
            guides = gs
            data?.updateShape(t)
        case .create(let a, let hadPin)?:
            let (q, gs) = snap(p, V, excluding: nil)
            cursor = q
            guides = gs
            if dragMoved || hadPin { preview = ShapeRec.span(id: -1, room: 0, a, q) }
            if !hadPin { pin = a }                     // 누른 곳에 점이 바로 보이게
        case .body(let id, let s, let start)?:
            guard dragMoved else { return }
            var t = s
            let dd = p - start
            t.u0 += dd.x; t.u1 += dd.x; t.v0 += dd.y; t.v1 += dd.y
            let (u, gs) = snapMove(t, V)
            guides = gs
            if !sel.contains(id) { sel = [id] }
            data?.updateShape(u)
        case .pan(let p0)?:
            pan = CGSize(width: p0.width + v.translation.width, height: p0.height + v.translation.height)
        default:
            break
        }
    }

    private func dragEnded(_ v: DragGesture.Value, _ V: View2) {
        defer { drag = nil; guides = []; preview = nil; dragStart = nil }
        switch drag {
        case .corner?, .body?:
            if dragMoved {
                commitDrag()
            } else if case .body(let id, _, _)? = drag {
                tapShape(id)
            }
        case .create(let a, let hadPin)?:
            let q = snap(V.plane(v.location), V, excluding: nil).0
            if dragMoved || hadPin {
                if simd_distance(a, q) > 0.15 { create(a, q) }    // 끌어서 만들기 / 두 번째 점
                pin = nil
            } else {
                pin = a                                          // 첫 점: 보이게 남겨 두고 두 번째 점을 기다림
            }
        case .pan?:
            if !dragMoved { sel = []; pin = nil }
        default:
            break
        }
    }

    private func cornerHit(_ q: CGPoint, _ d: SpaceData, _ V: View2) -> (Int, Int)? {
        for s in d.shapes where sel.contains(s.id) {
            for i in 0..<4 {
                let p = V.screen(s.corner(i))
                if hypot(p.x - q.x, p.y - q.y) < 26 { return (s.id, i) }
            }
        }
        return nil
    }

    /// 고른 것 → 문·통로 → 방 순서 (빛나는 것과 같은 순서)
    private func shapeHit(_ p: SIMD2<Float>, _ d: SpaceData) -> ShapeRec? {
        if let s = d.shapes.last(where: { sel.contains($0.id) && $0.contains(p.x, p.y) }) { return s }
        if let s = d.shapes.last(where: { $0.isDoor && $0.contains(p.x, p.y) }) { return s }
        return d.shapes.last { $0.contains(p.x, p.y) }
    }

    private func tapShape(_ id: Int) {
        if multi {
            if let i = sel.firstIndex(of: id) { sel.remove(at: i) } else { sel.append(id) }
        } else {
            sel = sel == [id] ? [] : [id]
        }
    }

    private func create(_ a: SIMD2<Float>, _ b: SIMD2<Float>) {
        let door = tool == .door
        change { d in
            if let id = d.addShape(a, b, door: door) { sel = [id] }
            d.tidy(full: false)
        }
        tool = .select
        flash(door ? "문·통로를 만들었어요. 이 자리는 벽이 뚫려 양쪽 방이 이어져요." : "새 방을 만들었어요. 이름과 세계를 정해 주세요.")
    }

    private func commitDrag() {
        guard let before = dragStart, var d = data, d != before else { return }
        d.tidy(full: false)                    // 끌기를 마치면 틈·겹침과 문 자리를 저절로 정리
        data = d
        push(before)
        persist()
    }

    // MARK: 오른쪽 판
    private func panel(_ d: SpaceData) -> some View {
        let picked = d.shapes.filter { sel.contains($0.id) }
        let rooms = Set(picked.filter { !$0.isDoor }.map(\.room))
        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TextField("공간 이름 (예: 우리 집)", text: $spaceName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { saveName() }
                Picker("도구", selection: $tool) {
                    Label("고르기", systemImage: "hand.point.up.left").tag(Tool.select)
                    Label("방 그리기", systemImage: "rectangle.dashed").tag(Tool.draw)
                    Label("문 그리기", systemImage: "door.left.hand.open").tag(Tool.door)
                }
                .pickerStyle(.segmented)
                .onChange(of: tool) { _, t in pin = nil; cursor = nil; if t != .select { sel = [] } }
                Toggle("여러 개 고르기", isOn: $multi)
                let bad = Self.issues(d)
                if !bad.isEmpty {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                        Text("틈·겹침이 애매하거나 문이 경계에 안 맞는 사각형 \(bad.count)개 (노란 점선) — 탐험 때 틈이 보일 수 있어요")
                            .font(.callout).fixedSize(horizontal: false, vertical: true)
                        Button("정리") { change { $0.tidy(full: false) }; flash("붙이고 문을 경계에 맞췄어요") }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(12)
                    .background(Color.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                }
                guide
                Text(hint(d)).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

                if !picked.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("사각형 \(picked.count)개 고름").font(.headline)
                        HStack(spacing: 8) {
                            Button { change { $0.combine(sel) }; flash("한 방으로 합쳤어요") } label: { Label("결합", systemImage: "rectangle.3.group") }
                                .disabled(rooms.count < 2)
                            Button { change { $0.separate(sel) }; flash("각각 다른 방으로 나눴어요") } label: { Label("분리", systemImage: "rectangle.split.2x1") }
                                .disabled(!canSeparate(d, picked))
                        }
                        HStack(spacing: 8) {
                            if picked.allSatisfy(\.isDoor) {
                                Button { change { $0.setDoor(sel, false) } } label: { Label("방으로", systemImage: "square") }
                            } else {
                                Button { change { $0.setDoor(sel, true) }; flash("문·통로가 덮은 자리는 벽이 뚫려 양쪽 방을 이어 줘요") } label: {
                                    Label("문·통로로", systemImage: "door.left.hand.open")
                                }
                            }
                            Button(role: .destructive) { let ids = Set(sel); change { $0.deleteShapes(ids) }; sel = [] } label: {
                                Label("지우기", systemImage: "trash")
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    fineBox(picked)
                    if rooms.count == 1, let rid = rooms.first, let r = d.rec.room(rid) { roomBox(r, d) }
                }

                Divider()
                Text("방 목록").font(.headline)
                ForEach(d.rec.rooms) { r in
                    Button {
                        sel = d.shapes.filter { $0.room == r.id }.map(\.id)
                    } label: {
                        HStack(spacing: 10) {
                            Circle().fill(RoomColor.of(r.id)).frame(width: 12, height: 12)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(r.name).font(.headline)
                                Text(r.title).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(String(format: "%.1f㎡", d.area(of: r.id))).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
                Divider()
                Text("세계 정하는 방식").font(.headline)
                Text(d.rec.isUnified ? "지금: 모든 방이 같은 세계 (탐험 중에 바꿔도 모든 방이 같이 바뀜)"
                                     : "지금: 방마다 다른 세계 (탐험 중에 바꾸면 그 방만 바뀜)")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button { change { $0.shuffleAll() }; flash("방마다 다른 세계로 새로 섞었어요") } label: { Label("방마다 무작위", systemImage: "shuffle") }
                    Button { unifyRoom = d.rec.rooms.first } label: { Label("모든 방 같게", systemImage: "square.on.square") }
                        .disabled(d.rec.rooms.isEmpty)
                }
                .buttonStyle(.bordered)
                Button { change { $0.tidy(full: true) }; flash("틈·겹침을 붙이고, 거의 한 줄인 벽을 맞추고, 문을 경계에 맞췄어요") } label: {
                    Label("이음새 자동 정리", systemImage: "wand.and.stars")
                }
                Button { change { $0.proposeShapes(keepRooms: true); $0.tidy(full: true) }; sel = []; flash("스캔을 바탕으로 다시 구성했어요") } label: {
                    Label("스캔에서 다시 구성", systemImage: "arrow.counterclockwise")
                }
                Button { doUndo() } label: { Label("되돌리기", systemImage: "arrow.uturn.backward") }
                    .disabled(undo.isEmpty)
                if let t = toast { Text(t).font(.callout).foregroundStyle(.secondary) }
            }
            .padding(22)
        }
    }

    /// 정밀 조정: 위아래좌우 한 칸씩 옮기기(고른 것 모두), 폭·깊이 숫자 입력(하나 골랐을 때)
    private func fineBox(_ picked: [ShapeRec]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("정밀 조정").font(.headline)
                Spacer()
                Picker("한 번에", selection: $step) {
                    Text("1cm").tag(Float(0.01)); Text("5cm").tag(Float(0.05)); Text("10cm").tag(Float(0.1))
                }
                .pickerStyle(.segmented)
                .frame(width: 210)
            }
            HStack(spacing: 8) {
                Text("옮기기").frame(width: 56, alignment: .leading)
                Button { nudge(-step, 0) } label: { Image(systemName: "arrow.left").frame(width: 34, height: 26) }
                Button { nudge(0, -step) } label: { Image(systemName: "arrow.up").frame(width: 34, height: 26) }
                Button { nudge(0, step) } label: { Image(systemName: "arrow.down").frame(width: 34, height: 26) }
                Button { nudge(step, 0) } label: { Image(systemName: "arrow.right").frame(width: 34, height: 26) }
            }
            if picked.count == 1, let s = picked.first {
                sizeRow("폭", Int((s.width * 100).rounded())) { cm in resize(s.id, w: Float(cm) / 100, d: nil) }
                sizeRow("깊이", Int((s.depth * 100).rounded())) { cm in resize(s.id, w: nil, d: Float(cm) / 100) }
            }
        }
        .buttonStyle(.bordered)
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func sizeRow(_ title: String, _ cm: Int, _ set: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 8) {
            Text(title).frame(width: 56, alignment: .leading)
            Button { set(max(20, cm - Int((step * 100).rounded()))) } label: { Image(systemName: "minus").frame(width: 30, height: 26) }
            TextField("cm", value: Binding(get: { cm }, set: { v in set(max(20, min(3000, v))) }), format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 90)
                .multilineTextAlignment(.trailing)
            Text("cm").foregroundStyle(.secondary)
            Button { set(min(3000, cm + Int((step * 100).rounded()))) } label: { Image(systemName: "plus").frame(width: 30, height: 26) }
        }
    }

    private func nudge(_ du: Float, _ dv: Float) {
        let ids = Set(sel)
        change { d in
            for s in d.shapes where ids.contains(s.id) {
                var t = s
                t.u0 += du; t.u1 += du; t.v0 += dv; t.v1 += dv
                d.updateShape(t)
            }
        }
    }

    /// 왼쪽 위 모서리는 그대로 두고 폭·깊이를 바꿈
    private func resize(_ id: Int, w: Float?, d dd: Float?) {
        change { d in
            guard var t = d.shapes.first(where: { $0.id == id }) else { return }
            if let w { t.u1 = t.u0 + w }
            if let dd { t.v1 = t.v0 + dd }
            d.updateShape(t)
        }
    }

    /// 자동 정리를 하면 2.5cm 넘게 바뀔 사각형들 = 지금 틈·겹침이 애매하거나 문이 경계에 안 맞는 곳
    static func issues(_ d: SpaceData) -> Set<Int> {
        var t = d
        t.tidy(full: false)
        var out = Set<Int>()
        for a in d.shapes {
            guard let b = t.shapes.first(where: { $0.id == a.id }) else { continue }
            if abs(a.u0 - b.u0) > 0.025 || abs(a.u1 - b.u1) > 0.025 || abs(a.v0 - b.v0) > 0.025 || abs(a.v1 - b.v1) > 0.025 { out.insert(a.id) }
        }
        return out
    }

    /// 방·문 구성 원칙 (편집 화면 안내)
    private var guide: some View {
        DisclosureGroup("방·문 구성 원칙") {
            VStack(alignment: .leading, spacing: 8) {
                Text("① 방 사각형 = 실제로 걸을 수 있는 바닥. 가구가 놓인 곳도 포함하고, 벽 속까지 넓히지 마세요.")
                Text("② 옆방과는 '딱 붙이기'가 기본이에요(실제 벽 두께의 가운데 선). 붙은 곳엔 벽이 한 장 서요. 2~25cm쯤 애매하게 떨어지거나 겹치면 노란 점선으로 알려 드려요.")
                Text("③ 한 방을 여러 사각형으로 만들 땐 서로 딱 붙이거나 겹치게 하고 '결합'으로 같은 방으로.")
                Text("④ 문은 실제 문이 있는 곳에만, 폭은 실제 문 폭(문틀 안쪽)과 같게, 두 방 경계를 가로질러 그리세요. 앞뒤 깊이는 아무렇게나 그려도 경계에 맞춰져요. 문은 그 두 방 사이만 뚫어요(옆의 다른 방 벽에 살짝 걸쳐도 그 벽은 그대로).")
                Text("④-1 방을 나누지 않은 곳의 실제 문(예: 드레스룸 안 화장실 문)도 같은 방 안에 문 사각형을 문 자리에 맞춰 그리면 돼요. 평소엔 통로처럼 보이고, 실제 문이 닫혀 있으면 1m 안에서 닫힌 문으로 보여요.")
                Text("⑤ 벽 없이 트인 곳(거실-주방 등)은 같은 방으로 결합하거나, 트인 길이 전체에 통로를 그리세요.")
                Text("⑥ 다 그린 뒤 '이음새 자동 정리'를 한 번 누르면 틈·겹침을 붙이고 거의 한 줄인 벽을 맞추고 문을 경계에 맞춰요.")
                Text("⑦ 탐험 중 다른 세계와 이어진 문은 멀리선 지금 방의 벽(숲이면 덤불, 바다면 난간)으로 보이고, 1m 안에서 문과 열쇠가 나타나요.")
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 6)
        }
    }

    private func canSeparate(_ d: SpaceData, _ picked: [ShapeRec]) -> Bool {
        picked.contains { s in !s.isDoor && d.shapes.contains { $0.room == s.room && $0.id != s.id } }
    }

    private func roomBox(_ r: RoomRec, _ d: SpaceData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Circle().fill(RoomColor.of(r.id)).frame(width: 12, height: 12)
                Text(r.name).font(.title3.weight(.semibold))
                Spacer()
                Menu("이름") {
                    ForEach(["거실", "주방", "거실·주방", "안방", "침실", "작은방", "서재", "화장실", "욕실", "드레스룸", "베란다", "현관", "복도"], id: \.self) { n in
                        Button(n) { rename(n) }
                    }
                    Button("직접 입력…") { nameText = r.name; renaming = true }
                }
            }
            Text(r.title).font(.headline)
            if d.rec.isUnified {
                Text("모든 방 같은 세계예요 — 여기서 바꾸면 모든 방이 같이 바뀌어요.").font(.caption).foregroundStyle(.secondary)
            }
            ThemePicker(room: r) { p, w, t in
                change { d in d.setTheme(r.id, place: p, weather: w, time: t) }
            }
            Stepper(value: Binding(get: { Double(r.ceil) }, set: { v in change { d in d.updateRoom(r.id) { rr in rr.ceil = Float(v) } } }),
                    in: 2.0...3.6, step: 0.05) {
                Text(String(format: "천장 높이 %.2fm", r.ceil))
            }
        }
        .padding(16)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    /// '모든 방 같게': 세계 하나를 골라 모든 방에 적용
    private func unifySheet(_ r: RoomRec) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("모든 방을 같은 세계로").font(.title2.weight(.bold))
                Spacer()
                Button("완료") { unifyRoom = nil }.buttonStyle(.borderedProminent)
            }
            Text(r.title).font(.title3)
            ThemePicker(room: r) { p, w, t in
                change { $0.setAll(place: p, weather: w, time: t) }
                var nr = r
                nr.place = p; nr.weather = w; nr.time = t
                unifyRoom = nr
            }
        }
        .padding(30)
        .frame(width: 720)
        .onAppear {
            // 시트를 열자마자 지금 세계로 모든 방을 맞춤
            change { $0.setAll(place: r.place, weather: r.weather, time: r.time) }
        }
    }

    private func hint(_ d: SpaceData) -> String {
        if tool == .door {
            return "실제 문이 있는 자리에, 두 방의 경계를 가로지르도록 사각형을 그리세요(방끼리 떨어져 있으면 틈을 덮게). 그 자리만 벽이 뚫려 이어져요. 바라보는 모서리 점이 빛나요."
        }
        if tool == .draw {
            return pin == nil ? "새 사각형의 한 모서리를 누르세요(점이 보여요). 그대로 끌거나, 맞은편 모서리를 한 번 더 누르면 만들어져요. 다른 사각형 변이나 스캔 벽(흰 선) 가까이에서는 착 붙어요."
                : "맞은편 모서리를 누르세요. 다른 곳을 고르려면 도구를 '고르기'로 바꾸세요."
        }
        if sel.isEmpty { return "바라보는 사각형이 빛나요. 누르면 골라지고, 모서리의 흰 점을 끌면 크기가, 사각형을 끌면 위치가 바뀌어요. 다른 방끼리 붙이면 사이에 벽이 서고, 문 그리기로 문 자리만 뚫을 수 있어요." }
        return multi ? "계속 눌러 더 고르세요. 여러 방을 고르고 '결합'하면 한 방이, '분리'하면 각각 다른 방이 돼요."
            : "'여러 개 고르기'를 켜면 사각형 여러 개를 한 번에 결합·분리할 수 있어요."
    }

    // MARK: 저장·되돌리기
    private func load() {
        guard let d = SpaceStore.load(spaceId) else { return }
        data = d
        spaceName = d.rec.name
        bg = Self.background(d)
        let lines = Self.wallLines(d)
        scanU = lines.0
        scanV = lines.1
    }

    private func rename(_ n: String) {
        let t = n.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, let d = data, let rid = Set(d.shapes.filter { sel.contains($0.id) && !$0.isDoor }.map(\.room)).first else { return }
        change { d in d.updateRoom(rid) { rr in rr.name = t } }
    }

    private func change(_ f: (inout SpaceData) -> Void) {
        guard var d = data else { return }
        let before = d
        f(&d)
        guard d != before else { return }
        push(before)
        data = d
        sel = sel.filter { id in d.shapes.contains { $0.id == id } }
        persist()
    }

    private func push(_ d: SpaceData) {
        undo.append(d)
        if undo.count > 30 { undo.removeFirst() }
    }

    private func doUndo() {
        guard let last = undo.popLast() else { return }
        data = last
        sel = sel.filter { id in last.shapes.contains { $0.id == id } }
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
    }

    private func flash(_ s: String) {
        toast = s
        Task {
            try? await Task.sleep(for: .seconds(3))
            if toast == s { toast = nil }
        }
    }

    // MARK: 스캔 지도
    /// 한 칸 = 한 점: 알아본 바닥 어두운 회색, 벽 밝은 회색, 창 하늘색
    static func background(_ d: SpaceData) -> CGImage? {
        let n = d.w * d.h
        var px = [UInt8](repeating: 0, count: n * 4)
        for i in 0..<n {
            var c: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0)
            if d.win.count == n && d.win[i] != 0 { c = (110, 170, 230, 255) }
            else if d.kind[i] == RoomSegment.WALL { c = (210, 210, 214, 255) }
            else if d.kind[i] == RoomSegment.FLOOR { c = (52, 54, 58, 255) }
            px[i * 4] = c.0; px[i * 4 + 1] = c.1; px[i * 4 + 2] = c.2; px[i * 4 + 3] = c.3
        }
        guard let prov = CGDataProvider(data: Data(px) as CFData) else { return nil }
        return CGImage(width: d.w, height: d.h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: d.w * 4,
                       space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: prov, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    /// 스캔에서 벽이 길게 이어진 줄 (사각형 변을 붙일 후보). 벽 칸 줄의 양쪽 가장자리
    static func wallLines(_ d: SpaceData) -> ([Float], [Float]) {
        var col = [Int](repeating: 0, count: d.w), row = [Int](repeating: 0, count: d.h)
        for v in 0..<d.h { for u in 0..<d.w where d.kind[v * d.w + u] == RoomSegment.WALL { col[u] += 1; row[v] += 1 } }
        var us: [Float] = [], vs: [Float] = []
        for u in 0..<d.w where col[u] >= 8 && (u == 0 || col[u] >= col[u - 1]) && (u == d.w - 1 || col[u] >= col[u + 1]) {
            us += [Float(u) * d.rec.cell, Float(u + 1) * d.rec.cell]
        }
        for v in 0..<d.h where row[v] >= 8 && (v == 0 || row[v] >= row[v - 1]) && (v == d.h - 1 || row[v] >= row[v + 1]) {
            vs += [Float(v) * d.rec.cell, Float(v + 1) * d.rec.cell]
        }
        return (us, vs)
    }
}
