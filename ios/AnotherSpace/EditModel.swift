import SwiftUI

/// 방 구성 편집 상태 — 공간설정 화면(지도)과 따로 띄우는 조정 창이 함께 씀
@MainActor @Observable
final class EditModel {
    static let shared = EditModel()

    var spaceId: String?
    var data: SpaceData?
    var sel: [Int] = []
    var multi = false
    var step: Float = 0.05
    var toast: String?
    var undo: [SpaceData] = []

    func load(_ id: String) {
        spaceId = id
        data = SpaceStore.load(id)
        sel = []
        undo = []
        toast = nil
    }

    func close() {
        sel = []
        undo = []
    }

    /// 바꾸고 저장 (되돌리기에 쌓음)
    func change(_ f: (inout SpaceData) -> Void) {
        guard var d = data else { return }
        let before = d
        f(&d)
        guard d != before else { return }
        push(before)
        data = d
        sel = sel.filter { id in d.shapes.contains { $0.id == id } }
        persist()
    }

    func push(_ d: SpaceData) {
        undo.append(d)
        if undo.count > 30 { undo.removeFirst() }
    }

    func doUndo() {
        guard let last = undo.popLast() else { return }
        data = last
        sel = sel.filter { id in last.shapes.contains { $0.id == id } }
        persist()
    }

    func persist() {
        guard let d = data else { return }
        try? SpaceStore.save(d)
        AppModel.shared.reload()
    }

    func flash(_ s: String) {
        toast = s
        Task {
            try? await Task.sleep(for: .seconds(3))
            if toast == s { toast = nil }
        }
    }

    // MARK: 고른 것
    var picked: [ShapeRec] { data?.shapes.filter { sel.contains($0.id) } ?? [] }
    /// 고른 사각형들의 방 (문 제외)
    var pickedRooms: Set<Int> { Set(picked.filter { !$0.isDoor }.map(\.room)) }

    func canSeparate() -> Bool {
        guard let d = data else { return false }
        return picked.contains { s in !s.isDoor && d.shapes.contains { $0.room == s.room && $0.id != s.id } }
    }

    func rename(_ n: String) {
        let t = n.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty, let rid = pickedRooms.first else { return }
        change { d in d.updateRoom(rid) { rr in rr.name = t } }
    }

    /// 고른 것 모두 위아래좌우로
    func nudge(_ du: Float, _ dv: Float) {
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
    func resize(_ id: Int, w: Float?, d dd: Float?) {
        change { d in
            guard var t = d.shapes.first(where: { $0.id == id }) else { return }
            if let w { t.u1 = t.u0 + w }
            if let dd { t.v1 = t.v0 + dd }
            d.updateShape(t)
        }
    }
}
