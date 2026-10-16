import Foundation
import simd

/// 방(영역) 하나: 이름 + 엠비언트 장소·날씨·시간 + 천장 높이(바닥에서 m)
struct RoomRec: Codable, Identifiable, Equatable, Hashable {
    var id: Int
    var name: String
    var place: String
    var weather: String
    var time: String
    var ceil: Float

    var title: String { Worlds.title(place: place, weather: weather, time: time) }
}

/// 저장한 월드 앵커 (비전프로가 기억했다가 같은 자리로 알려 줌) — p: 저장 좌표
struct AnchorRec: Codable, Equatable {
    var a: String
    var p: [Float]
    var pos: SIMD3<Float> { SIMD3<Float>(p[0], p[1], p[2]) }
}

/// 집을 이루는 사각형 하나 (벽과 나란한 '평면 좌표', 단위 m).
/// room > 0: 그 방(영역)에 속한 바닥, room == 0: 문·통로 (방 사이를 이어 주는 걸을 수 있는 곳, 벽이 생기지 않음)
struct ShapeRec: Codable, Identifiable, Equatable, Hashable {
    var id: Int
    var room: Int
    var u0: Float
    var v0: Float
    var u1: Float
    var v1: Float

    var isDoor: Bool { room == 0 }
    var width: Float { u1 - u0 }
    var depth: Float { v1 - v0 }
    var area: Float { max(0, width) * max(0, depth) }
    var center: SIMD2<Float> { SIMD2<Float>((u0 + u1) / 2, (v0 + v1) / 2) }

    func contains(_ u: Float, _ v: Float) -> Bool { u >= u0 && u < u1 && v >= v0 && v < v1 }

    /// 모서리 순서: 0 왼쪽 위(u0,v0) · 1 오른쪽 위(u1,v0) · 2 오른쪽 아래(u1,v1) · 3 왼쪽 아래(u0,v1)
    func corner(_ i: Int) -> SIMD2<Float> {
        switch i {
        case 0: return SIMD2<Float>(u0, v0)
        case 1: return SIMD2<Float>(u1, v0)
        case 2: return SIMD2<Float>(u1, v1)
        default: return SIMD2<Float>(u0, v1)
        }
    }

    /// 두 점으로 만든 사각형 (순서 상관없음)
    static func span(id: Int, room: Int, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> ShapeRec {
        ShapeRec(id: id, room: room, u0: min(a.x, b.x), v0: min(a.y, b.y), u1: max(a.x, b.x), v1: max(a.y, b.y))
    }
}

/// 공간 하나.
/// 평면 좌표 (u, v) m: 저장 좌표 (x, z) = (ox, oz) + u·ex + v·ez  — 벽과 나란하게 angle만큼 돌려 둠
/// 스캔 격자(한 칸 cell m)도 같은 원점·방향: 칸 (i, j) = 평면 좌표 (i·cell, j·cell)
struct SpaceRec: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var at: Double
    var cell: Float
    var angle: Float
    var ox: Float
    var oz: Float
    var w: Int
    var h: Int
    var floorY: Float
    var anchors: [AnchorRec]
    var rooms: [RoomRec]
    var shapes: [ShapeRec]?          // v0.2부터: 집을 이루는 사각형들 (없으면 예전 공간 → 스캔에서 다시 제안)

    var ex: SIMD2<Float> { SIMD2<Float>(cos(angle), sin(angle)) }
    var ez: SIMD2<Float> { SIMD2<Float>(-sin(angle), cos(angle)) }

    /// 저장 좌표 (x, z) → 스캔 격자 좌표 (칸 단위, 소수)
    func local(_ x: Float, _ z: Float) -> SIMD2<Float> { plane(x, z) / cell }
    /// 스캔 격자 좌표 → 저장 좌표 (x, z)
    func world(_ u: Float, _ v: Float) -> SIMD2<Float> { flat(u * cell, v * cell) }

    /// 저장 좌표 (x, z) → 평면 좌표 (m)
    func plane(_ x: Float, _ z: Float) -> SIMD2<Float> {
        let d = SIMD2<Float>(x - ox, z - oz)
        return SIMD2<Float>(simd_dot(d, ex), simd_dot(d, ez))
    }
    /// 평면 좌표 (m) → 저장 좌표 (x, z)
    func flat(_ u: Float, _ v: Float) -> SIMD2<Float> { SIMD2<Float>(ox, oz) + ex * u + ez * v }

    func room(_ id: Int) -> RoomRec? { rooms.first { $0.id == id } }

    var size: SIMD2<Float> { SIMD2<Float>(Float(w), Float(h)) * cell }
}

/// 공간 + 스캔 격자 (kind: 0 없음·1 바닥·2 벽, win: 창으로 알아본 칸이면 1, room: 스캔에서 자동으로 나눈 방 — 제안에만 씀)
struct SpaceData: Equatable {
    var rec: SpaceRec
    var kind: [UInt8]
    var room: [UInt8]
    var win: [UInt8]

    var w: Int { rec.w }
    var h: Int { rec.h }
    var shapes: [ShapeRec] { rec.shapes ?? [] }

    func scanRoomAt(_ u: Int, _ v: Int) -> Int {
        guard u >= 0, v >= 0, u < w, v < h else { return 0 }
        return Int(room[v * w + u])
    }
    func kindAt(_ u: Int, _ v: Int) -> UInt8 {
        guard u >= 0, v >= 0, u < w, v < h else { return 0 }
        return kind[v * w + u]
    }
    func windowAt(_ u: Int, _ v: Int) -> Bool {
        guard u >= 0, v >= 0, u < w, v < h, win.count == w * h else { return false }
        return win[v * w + u] != 0
    }

    /// 평면 좌표의 방 (사각형 기준, 나중에 그린 것이 위). 문·통로면 0
    func shapeAt(_ p: SIMD2<Float>) -> ShapeRec? { shapes.last { $0.contains(p.x, p.y) } }

    func area(of r: Int) -> Float { shapes.filter { $0.room == r }.reduce(0) { $0 + $1.area } }

    var nextShapeId: Int { (shapes.map(\.id).max() ?? 0) + 1 }
    var nextRoomId: Int { (rec.rooms.map(\.id).max() ?? 0) + 1 }

    // MARK: 편집 (사각형)
    /// 새 방(영역)을 만들어 그 방의 사각형으로 넣음. 새 사각형 id
    @discardableResult
    mutating func addShape(_ a: SIMD2<Float>, _ b: SIMD2<Float>, door: Bool = false) -> Int? {
        var s = ShapeRec.span(id: nextShapeId, room: 0, a, b)
        guard s.width >= 0.2, s.depth >= 0.2 else { return nil }
        if !door {
            guard nextRoomId < 250 else { return nil }
            let r = newRoom()
            s.room = r
        }
        rec.shapes = shapes + [s]
        return s.id
    }

    mutating func updateShape(_ s: ShapeRec) {
        guard var list = rec.shapes, let i = list.firstIndex(where: { $0.id == s.id }) else { return }
        list[i] = s
        rec.shapes = list
    }

    mutating func deleteShapes(_ ids: Set<Int>) {
        rec.shapes = shapes.filter { !ids.contains($0.id) }
        cleanupRooms()
    }

    /// 고른 사각형들을 한 방으로 (첫 번째로 고른 방의 이름·세계 유지)
    mutating func combine(_ ids: [Int]) {
        let picked = shapes.filter { ids.contains($0.id) && !$0.isDoor }
        guard let keep = ids.compactMap({ id in picked.first { $0.id == id }?.room }).first else { return }
        rec.shapes = shapes.map { s in
            var t = s
            if ids.contains(s.id) && !s.isDoor { t.room = keep }
            return t
        }
        cleanupRooms()
    }

    /// 고른 사각형을 하나씩 다른 방으로. 한 방의 사각형을 전부 골랐으면 첫 사각형은 그 방에 남고 나머지가 새 방이 됨
    mutating func separate(_ ids: [Int]) {
        let all = shapes
        var kept = Set<Int>()
        for id in ids {
            guard let s = all.first(where: { $0.id == id }), !s.isDoor else { continue }
            let mates = all.filter { $0.room == s.room }.map(\.id)
            if mates.allSatisfy({ ids.contains($0) }) && !kept.contains(s.room) { kept.insert(s.room); continue }
            guard nextRoomId < 250 else { break }
            var t = s
            t.room = newRoom(copyFrom: s.room)
            updateShape(t)
        }
        cleanupRooms()
    }

    /// 문·통로로 바꾸기 (on) / 다시 방으로 (off: 새 방)
    mutating func setDoor(_ ids: [Int], _ on: Bool) {
        for id in ids {
            guard var s = shapes.first(where: { $0.id == id }) else { continue }
            if on { s.room = 0 }
            else if s.isDoor { guard nextRoomId < 250 else { break }; s.room = newRoom() }
            else { continue }
            updateShape(s)
        }
        cleanupRooms()
    }

    /// 사각형이 하나도 없는 방은 지움
    mutating func cleanupRooms() {
        let used = Set(shapes.map(\.room))
        rec.rooms.removeAll { !used.contains($0.id) }
    }

    /// 새 방 기록을 만들고 id를 돌려줌 (세계는 무작위, 이름은 '공간 n')
    private mutating func newRoom(copyFrom: Int? = nil) -> Int {
        let id = nextRoomId
        var g = SystemRandomNumberGenerator()
        let used = Set(rec.rooms.map(\.place))
        let (p, w, t) = Worlds.random(using: &g, avoid: used)
        let base = copyFrom.flatMap { rec.room($0) }
        let n = rec.rooms.count + 1
        rec.rooms.append(RoomRec(id: id, name: "공간 \(n)", place: p, weather: w, time: t, ceil: base?.ceil ?? defaultCeil))
        return id
    }

    var defaultCeil: Float {
        let c = rec.rooms.map(\.ceil).sorted()
        return c.isEmpty ? 2.4 : c[c.count / 2]
    }

    // MARK: 편집 (방)
    mutating func updateRoom(_ id: Int, _ f: (inout RoomRec) -> Void) {
        guard let i = rec.rooms.firstIndex(where: { $0.id == id }) else { return }
        f(&rec.rooms[i])
    }

    /// 모든 방에 세계를 새로 섞어 배정 (장소는 되도록 겹치지 않게)
    mutating func shuffleAll() {
        var g = SystemRandomNumberGenerator()
        var used = Set<String>()
        for i in rec.rooms.indices {
            let (p, w, t) = Worlds.random(using: &g, avoid: used)
            used.insert(p)
            if used.count >= Worlds.places.count { used.removeAll() }
            rec.rooms[i].place = p; rec.rooms[i].weather = w; rec.rooms[i].time = t
        }
    }

    mutating func shuffle(_ r: Int) {
        var g = SystemRandomNumberGenerator()
        let used = Set(rec.rooms.filter { $0.id != r }.map(\.place))
        let (p, w, t) = Worlds.random(using: &g, avoid: used)
        updateRoom(r) { $0.place = p; $0.weather = w; $0.time = t }
    }

    // MARK: 스캔에서 사각형 제안
    /// 스캔에서 자동으로 나눈 방(room 격자)을 사각형 몇 개로 덮고, 방 사이 벽이 없는 곳은 문·통로 사각형으로 이음.
    /// keepRooms: 예전 방 기록(이름·세계)을 같은 id로 이어 씀
    mutating func proposeShapes(keepRooms: Bool) {
        let cell = rec.cell
        var shapes: [ShapeRec] = []
        var nid = 1
        let ids = Set(room.map { Int($0) }).subtracting([0]).sorted()
        for r in ids {
            var m = [Bool](repeating: false, count: w * h)
            for i in 0..<(w * h) where Int(room[i]) == r { m[i] = true }
            m = Grid.close(m, w, h, 2)
            let total = m.reduce(0) { $0 + ($1 ? 1 : 0) }
            var covered = 0
            for _ in 0..<6 {
                guard let rc = Grid.largestRect(m, w, h), rc.area >= 50 else { break }
                shapes.append(ShapeRec(id: nid, room: r, u0: Float(rc.u0) * cell, v0: Float(rc.v0) * cell,
                                       u1: Float(rc.u1) * cell, v1: Float(rc.v1) * cell))
                nid += 1
                for v in rc.v0..<rc.v1 { for u in rc.u0..<rc.u1 { m[v * w + u] = false } }
                covered += rc.area
                if Float(covered) >= 0.92 * Float(total) { break }
            }
        }
        shapes += Grid.doors(shapes, self, startId: nid)
        rec.shapes = shapes
        let used = Set(shapes.map(\.room)).subtracting([0])
        if keepRooms {
            rec.rooms.removeAll { !used.contains($0.id) }
        }
        var g = SystemRandomNumberGenerator()
        var places = Set(rec.rooms.map(\.place))
        for r in used.sorted() where rec.room(r) == nil {
            let (p, wth, t) = Worlds.random(using: &g, avoid: places)
            places.insert(p)
            rec.rooms.append(RoomRec(id: r, name: "공간 \(r)", place: p, weather: wth, time: t, ceil: defaultCeil))
        }
        rec.rooms.sort { $0.id < $1.id }
    }
}

/// 격자 계산 도우미
enum Grid {
    struct Rect { let u0, v0, u1, v1: Int; var area: Int { (u1 - u0) * (v1 - v0) } }

    /// 모두 참인 칸으로 된 가장 큰 직사각형 (막대그래프 방식)
    static func largestRect(_ m: [Bool], _ W: Int, _ H: Int) -> Rect? {
        var hgt = [Int](repeating: 0, count: W)
        var best: Rect?
        var bestA = 0
        for v in 0..<H {
            for u in 0..<W { hgt[u] = m[v * W + u] ? hgt[u] + 1 : 0 }
            var st: [(Int, Int)] = []
            for u in 0...W {
                let hh = u < W ? hgt[u] : 0
                var start = u
                while let last = st.last, last.1 >= hh {
                    st.removeLast()
                    let a = last.1 * (u - last.0)
                    if a > bestA { bestA = a; best = Rect(u0: last.0, v0: v - last.1 + 1, u1: u, v1: v + 1) }
                    start = last.0
                }
                st.append((start, hh))
            }
        }
        return best
    }

    /// 넓혔다 줄이기 (구멍·톱니 메우기)
    static func close(_ m: [Bool], _ W: Int, _ H: Int, _ r: Int) -> [Bool] {
        var d = [Bool](repeating: false, count: W * H)
        for v in 0..<H { for u in 0..<W where m[v * W + u] {
            for dv in -r...r { for du in -r...r {
                let uu = u + du, vv = v + dv
                if uu >= 0, vv >= 0, uu < W, vv < H { d[vv * W + uu] = true }
            } }
        } }
        var e = [Bool](repeating: false, count: W * H)
        for v in 0..<H { for u in 0..<W where d[v * W + u] {
            var ok = true
            for dv in -r...r { for du in -r...r {
                let uu = u + du, vv = v + dv
                if uu < 0 || vv < 0 || uu >= W || vv >= H || !d[vv * W + uu] { ok = false }
            } }
            e[v * W + u] = ok
        } }
        return e
    }

    /// 두 방 사각형 사이 40cm 안쪽 틈에 벽이 없으면(스캔 기준) 그 구간을 문·통로 사각형으로
    static func doors(_ shapes: [ShapeRec], _ d: SpaceData, startId: Int) -> [ShapeRec] {
        let W = d.w, H = d.h, cell = d.rec.cell
        var own = [Int](repeating: 0, count: W * H)
        for s in shapes {
            let a = cellRange(s, cell, W, H)
            for v in a.v0..<a.v1 { for u in a.u0..<a.u1 { own[v * W + u] = s.room } }
        }
        var out: [ShapeRec] = []
        var nid = startId
        for s in shapes where !s.isDoor {
            let a = cellRange(s, cell, W, H)
            guard a.u1 > a.u0, a.v1 > a.v0 else { continue }
            // 네 변: 바깥 방향, 변을 따라가는 칸
            let edges: [((Int, Int), [(Int, Int)])] = [
                ((0, -1), (a.u0..<a.u1).map { ($0, a.v0) }), ((0, 1), (a.u0..<a.u1).map { ($0, a.v1 - 1) }),
                ((-1, 0), (a.v0..<a.v1).map { (a.u0, $0) }), ((1, 0), (a.v0..<a.v1).map { (a.u1 - 1, $0) }),
            ]
            for ((du, dv), cells) in edges {
                var hits: [(Int, Int)?] = []
                for (u, v) in cells {
                    var hit: (Int, Int)?
                    for k in 1...4 {
                        let uu = u + du * k, vv = v + dv * k
                        guard uu >= 0, vv >= 0, uu < W, vv < H else { break }
                        let o = own[vv * W + uu]
                        if o == s.room { break }
                        if o != 0 { hit = (o, k); break }
                        if d.kind[vv * W + uu] == RoomSegment.WALL { break }
                    }
                    hits.append(hit)
                }
                var i = 0
                while i < hits.count {
                    guard let hi = hits[i], hi.1 > 1 else { i += 1; continue }
                    let o = hi.0
                    var j = i, gap = 0
                    while j < hits.count, let hj = hits[j], hj.0 == o, hj.1 > 1 { gap = max(gap, hj.1 - 1); j += 1 }
                    if j - i >= 5 && s.room < o {
                        let c0 = cells[i], c1 = cells[j - 1]
                        let r: ShapeRec
                        if du == 0 {
                            let vv0 = dv < 0 ? a.v0 - gap : a.v1
                            r = ShapeRec(id: nid, room: 0, u0: Float(min(c0.0, c1.0)) * cell, v0: Float(vv0) * cell,
                                         u1: Float(max(c0.0, c1.0) + 1) * cell, v1: Float(vv0 + gap) * cell)
                        } else {
                            let uu0 = du < 0 ? a.u0 - gap : a.u1
                            r = ShapeRec(id: nid, room: 0, u0: Float(uu0) * cell, v0: Float(min(c0.1, c1.1)) * cell,
                                         u1: Float(uu0 + gap) * cell, v1: Float(max(c0.1, c1.1) + 1) * cell)
                        }
                        out.append(r)
                        nid += 1
                    }
                    i = j
                }
            }
        }
        return out
    }

    static func cellRange(_ s: ShapeRec, _ cell: Float, _ W: Int, _ H: Int) -> Rect {
        Rect(u0: max(0, Int((s.u0 / cell).rounded())), v0: max(0, Int((s.v0 / cell).rounded())),
             u1: min(W, Int((s.u1 / cell).rounded())), v1: min(H, Int((s.v1 / cell).rounded())))
    }
}

/// 공간 저장 (Application Support/spaces/<id>/ — space.json, kind.bin, room.bin, win.bin)
enum SpaceStore {
    static var dir: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("spaces")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    static func folder(_ id: String) -> URL { dir.appendingPathComponent(id, isDirectory: true) }

    static func list() -> [SpaceRec] {
        let ids = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        return ids.compactMap { id in
            guard let d = try? Data(contentsOf: folder(id).appendingPathComponent("space.json")) else { return nil }
            return try? JSONDecoder().decode(SpaceRec.self, from: d)
        }.sorted { $0.at > $1.at }
    }

    /// 불러오기. 사각형이 없는 예전(v0.1) 공간은 스캔에서 사각형을 제안해 채움
    static func load(_ id: String) -> SpaceData? {
        let f = folder(id)
        guard let d = try? Data(contentsOf: f.appendingPathComponent("space.json")),
              let rec = try? JSONDecoder().decode(SpaceRec.self, from: d),
              let k = try? Data(contentsOf: f.appendingPathComponent("kind.bin")),
              let r = try? Data(contentsOf: f.appendingPathComponent("room.bin")),
              k.count == rec.w * rec.h, r.count == rec.w * rec.h else { return nil }
        var win = [UInt8](repeating: 0, count: rec.w * rec.h)
        if let wd = try? Data(contentsOf: f.appendingPathComponent("win.bin")), wd.count == win.count { win = [UInt8](wd) }
        var s = SpaceData(rec: rec, kind: [UInt8](k), room: [UInt8](r), win: win)
        if rec.shapes == nil {
            s.proposeShapes(keepRooms: true)
            try? save(s)
        }
        return s
    }

    static func save(_ s: SpaceData) throws {
        let f = folder(s.rec.id)
        try FileManager.default.createDirectory(at: f, withIntermediateDirectories: true)
        try Data(s.kind).write(to: f.appendingPathComponent("kind.bin"), options: .atomic)
        try Data(s.room).write(to: f.appendingPathComponent("room.bin"), options: .atomic)
        try Data(s.win).write(to: f.appendingPathComponent("win.bin"), options: .atomic)
        try JSONEncoder().encode(s.rec).write(to: f.appendingPathComponent("space.json"), options: .atomic)
    }

    static func delete(_ id: String) { try? FileManager.default.removeItem(at: folder(id)) }

    /// 방 하나의 세계만 바꿔 저장 (메인 메뉴·탐험 중 테마 바꾸기)
    static func setTheme(_ id: String, room: Int, place: String, weather: String, time: String) {
        guard var s = load(id) else { return }
        s.updateRoom(room) { $0.place = place; $0.weather = weather; $0.time = time }
        try? save(s)
    }

    /// 모든 공간의 앵커 id (어느 공간에도 없는 앵커는 지운 공간의 것이라 정리함)
    static func allAnchorIds() -> Set<String> { Set(list().flatMap { $0.anchors.map(\.a) }) }
}
