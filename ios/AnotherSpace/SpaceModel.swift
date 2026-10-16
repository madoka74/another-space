import Foundation
import simd

/// 방 하나: 이름 + 엠비언트 장소·날씨·시간 + 천장 높이(바닥에서 m)
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

/// 공간 하나. 격자(한 칸 cell m)는 벽과 나란하게 angle만큼 돌려 둠:
/// 저장 좌표 (x, z) = (ox, oz) + u·cell·ex + v·cell·ez   (u: 열, v: 행)
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

    var ex: SIMD2<Float> { SIMD2<Float>(cos(angle), sin(angle)) }
    var ez: SIMD2<Float> { SIMD2<Float>(-sin(angle), cos(angle)) }

    /// 저장 좌표 (x, z) → 격자 좌표 (칸 단위, 소수)
    func local(_ x: Float, _ z: Float) -> SIMD2<Float> {
        let d = SIMD2<Float>(x - ox, z - oz)
        return SIMD2<Float>(simd_dot(d, ex), simd_dot(d, ez)) / cell
    }
    /// 격자 좌표 → 저장 좌표 (x, z)
    func world(_ u: Float, _ v: Float) -> SIMD2<Float> {
        SIMD2<Float>(ox, oz) + ex * (u * cell) + ez * (v * cell)
    }
    func room(_ id: Int) -> RoomRec? { rooms.first { $0.id == id } }
}

/// 공간 + 격자 (kind: 0 없음·1 바닥·2 벽, room: 칸마다 방 id, 0은 방 아님)
struct SpaceData: Equatable {
    var rec: SpaceRec
    var kind: [UInt8]
    var room: [UInt8]

    var w: Int { rec.w }
    var h: Int { rec.h }

    func roomAt(_ u: Int, _ v: Int) -> Int {
        guard u >= 0, v >= 0, u < w, v < h else { return 0 }
        return Int(room[v * w + u])
    }

    /// 저장 좌표 (x, z)가 속한 방. 벽 칸이면 반경 r칸 안의 가장 가까운 방
    func roomAt(x: Float, z: Float, radius: Int = 0) -> Int {
        let l = rec.local(x, z)
        let u = Int(floor(l.x)), v = Int(floor(l.y))
        let r0 = roomAt(u, v)
        if r0 != 0 || radius == 0 { return r0 }
        var best = 0, bestD = Int.max
        for dv in -radius...radius {
            for du in -radius...radius {
                let r = roomAt(u + du, v + dv)
                if r != 0, du * du + dv * dv < bestD { bestD = du * du + dv * dv; best = r }
            }
        }
        return best
    }

    func cells(of r: Int) -> Int { room.reduce(0) { $0 + (Int($1) == r ? 1 : 0) } }
    func area(of r: Int) -> Float { Float(cells(of: r)) * rec.cell * rec.cell }

    /// 방의 무게중심 (격자 좌표)
    func centroid(of r: Int) -> SIMD2<Float>? {
        var sx: Float = 0, sz: Float = 0, n: Float = 0
        for v in 0..<h { for u in 0..<w where Int(room[v * w + u]) == r { sx += Float(u) + 0.5; sz += Float(v) + 0.5; n += 1 } }
        return n > 0 ? SIMD2<Float>(sx / n, sz / n) : nil
    }

    /// 방 칸 표시 (grow: 방이 아닌 칸(벽 등)으로 몇 칸 더 넓힐지 — 바닥·하늘이 벽 밑까지 빈틈없이 닿게)
    func mask(_ r: Int, grow: Int = 0) -> [Bool] {
        var m = [Bool](repeating: false, count: w * h)
        for i in 0..<(w * h) where Int(room[i]) == r { m[i] = true }
        guard grow > 0 else { return m }
        var out = m
        for v in 0..<h {
            for u in 0..<w where m[v * w + u] {
                for dv in -grow...grow {
                    for du in -grow...grow {
                        let uu = u + du, vv = v + dv
                        if uu >= 0, vv >= 0, uu < w, vv < h, room[vv * w + uu] == 0 { out[vv * w + uu] = true }
                    }
                }
            }
        }
        return out
    }

    /// 칸 표시를 직사각형 여러 개로 (같은 줄 구간이 이어지면 아래로 늘림). [u0, v0, u1, v1) 칸 단위
    func rects(mask m: [Bool]) -> [(Int, Int, Int, Int)] {
        var used = [Bool](repeating: false, count: w * h)
        var out: [(Int, Int, Int, Int)] = []
        for v in 0..<h {
            var u = 0
            while u < w {
                let i = v * w + u
                if !m[i] || used[i] { u += 1; continue }
                var u1 = u
                while u1 < w, m[v * w + u1], !used[v * w + u1] { u1 += 1 }
                var v1 = v + 1
                while v1 < h {
                    var full = true
                    for k in u..<u1 where !m[v1 * w + k] || used[v1 * w + k] { full = false; break }
                    if !full { break }
                    v1 += 1
                }
                for vv in v..<v1 { for k in u..<u1 { used[vv * w + k] = true } }
                out.append((u, v, u1, v1))
                u = u1
            }
        }
        return out
    }

    func rects(of r: Int) -> [(Int, Int, Int, Int)] { rects(mask: mask(r)) }

    /// 방이 차지하는 범위 (격자)
    func bounds(of r: Int) -> (Int, Int, Int, Int)? {
        var u0 = Int.max, v0 = Int.max, u1 = -1, v1 = -1
        for v in 0..<h { for u in 0..<w where Int(room[v * w + u]) == r { u0 = min(u0, u); v0 = min(v0, v); u1 = max(u1, u + 1); v1 = max(v1, v + 1) } }
        return u1 < 0 ? nil : (u0, v0, u1, v1)
    }

    private var nextId: Int { (rec.rooms.map(\.id).max() ?? 0) + 1 }

    // MARK: 편집
    /// a를 b에 합침 (b의 이름·세계 유지)
    mutating func merge(_ a: Int, into b: Int) {
        guard a != b, a > 0, b > 0 else { return }
        for i in room.indices where Int(room[i]) == a { room[i] = UInt8(b) }
        if let ra = rec.room(a), let ib = rec.rooms.firstIndex(where: { $0.id == b }) {
            rec.rooms[ib].ceil = max(rec.rooms[ib].ceil, ra.ceil)
        }
        rec.rooms.removeAll { $0.id == a }
    }

    /// 방 r을 선(p0 → p1, 격자 좌표)으로 둘로 나눔. 나뉜 쪽의 새 방 id (나눌 수 없으면 nil)
    mutating func split(_ r: Int, _ p0: SIMD2<Float>, _ p1: SIMD2<Float>) -> Int? {
        guard nextId < 255, let base = rec.room(r) else { return nil }
        let d = p1 - p0
        guard simd_length(d) > 0.5 else { return nil }
        var side: [Int] = []
        var other = 0
        for v in 0..<h {
            for u in 0..<w where Int(room[v * w + u]) == r {
                let q = SIMD2<Float>(Float(u) + 0.5, Float(v) + 0.5) - p0
                if d.x * q.y - d.y * q.x > 0 { side.append(v * w + u) } else { other += 1 }
            }
        }
        guard side.count >= 20, other >= 20 else { return nil }
        let nid = nextId
        for i in side { room[i] = UInt8(nid) }
        var g = SystemRandomNumberGenerator()
        let used = Set(rec.rooms.map(\.place))
        let (p, wth, t) = Worlds.random(using: &g, avoid: used)
        rec.rooms.append(RoomRec(id: nid, name: base.name + " 2", place: p, weather: wth, time: t, ceil: base.ceil))
        return nid
    }

    /// 방에서 빼기 (거울 속 가짜 공간, 쓰지 않을 곳 등) — 이 칸들은 탐험 때 현실 그대로 보임
    mutating func exclude(_ r: Int) {
        for i in room.indices where Int(room[i]) == r { room[i] = 0 }
        rec.rooms.removeAll { $0.id == r }
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
        guard let i = rec.rooms.firstIndex(where: { $0.id == r }) else { return }
        var g = SystemRandomNumberGenerator()
        let used = Set(rec.rooms.filter { $0.id != r }.map(\.place))
        let (p, w, t) = Worlds.random(using: &g, avoid: used)
        rec.rooms[i].place = p; rec.rooms[i].weather = w; rec.rooms[i].time = t
    }

    /// 처음 자동 구분으로 되돌리기 (바닥·벽 격자는 그대로)
    mutating func resegment() {
        let ceilByCell = room.map { r -> Float in rec.room(Int(r))?.ceil ?? 0 }
        room = RoomSegment.segment(kind: &kind, w: w, h: h)
        let ids = Set(room.map { Int($0) }).subtracting([0]).sorted()
        var rooms: [RoomRec] = []
        var g = SystemRandomNumberGenerator()
        var used = Set<String>()
        for (k, id) in ids.enumerated() {
            var cs: [Float] = []
            for i in room.indices where Int(room[i]) == id && ceilByCell[i] > 0 { cs.append(ceilByCell[i]) }
            cs.sort()
            let ceil = cs.isEmpty ? 2.4 : cs[cs.count / 2]
            let (p, wth, t) = Worlds.random(using: &g, avoid: used)
            used.insert(p)
            if used.count >= Worlds.places.count { used.removeAll() }
            rooms.append(RoomRec(id: id, name: "공간 \(k + 1)", place: p, weather: wth, time: t, ceil: ceil))
        }
        rec.rooms = rooms
    }
}

/// 공간 저장 (Application Support/spaces/<id>/ — space.json, kind.bin, room.bin)
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

    static func load(_ id: String) -> SpaceData? {
        let f = folder(id)
        guard let d = try? Data(contentsOf: f.appendingPathComponent("space.json")),
              let rec = try? JSONDecoder().decode(SpaceRec.self, from: d),
              let k = try? Data(contentsOf: f.appendingPathComponent("kind.bin")),
              let r = try? Data(contentsOf: f.appendingPathComponent("room.bin")),
              k.count == rec.w * rec.h, r.count == rec.w * rec.h else { return nil }
        return SpaceData(rec: rec, kind: [UInt8](k), room: [UInt8](r))
    }

    static func save(_ s: SpaceData) throws {
        let f = folder(s.rec.id)
        try FileManager.default.createDirectory(at: f, withIntermediateDirectories: true)
        try Data(s.kind).write(to: f.appendingPathComponent("kind.bin"), options: .atomic)
        try Data(s.room).write(to: f.appendingPathComponent("room.bin"), options: .atomic)
        try JSONEncoder().encode(s.rec).write(to: f.appendingPathComponent("space.json"), options: .atomic)
    }

    static func delete(_ id: String) { try? FileManager.default.removeItem(at: folder(id)) }

    static func rename(_ id: String, _ name: String) {
        guard var s = load(id) else { return }
        s.rec.name = name
        try? save(s)
    }

    /// 모든 공간의 앵커 id (어느 공간에도 없는 앵커는 지운 공간의 것이라 정리함)
    static func allAnchorIds() -> Set<String> { Set(list().flatMap { $0.anchors.map(\.a) }) }
}
