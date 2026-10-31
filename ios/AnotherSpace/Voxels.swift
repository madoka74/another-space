import Foundation
import UIKit
import RealityKit
import simd

/// 가구·물건을 10cm 블록(복셀)으로 다룸.
/// 그물 조각을 그대로 그리면 비전프로가 그물을 고칠 때마다 조각이 생겼다 사라졌다 하고 허공에 뜬 조각도 남음 →
/// 평면 좌표(벽과 나란한 격자)의 10cm 블록에 담아 두고, 한 번 생긴 블록은 그 자리를 잘 보고 있는데도 3초 넘게
/// 아무 그물에도 없을 때만 지움. 블록은 저장 좌표에 있어 위치를 다시 맞춰도 다시 그리지 않음
enum Vox {
    static let size: Float = 0.1
    private static let off: Int64 = 1 << 20
    private static let mask: Int64 = (1 << 21) - 1

    /// (u칸, v칸, 높이칸) → 키
    static func key(_ u: Int, _ v: Int, _ y: Int) -> Int64 {
        ((Int64(u) + off) << 42) | ((Int64(v) + off) << 21) | (Int64(y) + off)
    }
    static func unpack(_ k: Int64) -> (Int, Int, Int) {
        (Int(((k >> 42) & mask) - off), Int(((k >> 21) & mask) - off), Int((k & mask) - off))
    }
    /// 1m 칸 (블록 10×10 기둥)
    static func chunkKey(_ cu: Int, _ cv: Int) -> Int64 { ((Int64(cu) + off) << 21) | (Int64(cv) + off) }
    static func fdiv(_ a: Int) -> Int { a >= 0 ? a / 10 : (a - 9) / 10 }
    static func chunk(_ k: Int64) -> Int64 { let (u, v, _) = unpack(k); return chunkKey(fdiv(u), fdiv(v)) }
    /// 평면 좌표(m)가 든 1m 칸
    static func chunkOf(_ p: SIMD2<Float>) -> Int64 { chunkKey(Int(p.x.rounded(.down)), Int(p.y.rounded(.down))) }
    /// 그림 자리 고르기에 쓰는 10cm 칸 키 (RoomWorld.clutterKey 와 같음)
    static func planeCell(_ u: Int, _ v: Int) -> Int64 { (Int64(u) + 100_000) << 20 | (Int64(v) + 100_000) }
}

/// 그물 한 덩어리를 읽은 결과
struct SkinResult: Sendable {
    var cols: [Int64: Float] = [:]        // 10cm 기둥(평면 격자) → 그 기둥에 있는 가구 면의 가장 높은 곳 (바닥에서 m)
    var floorSeen: Set<Int64> = []        // 바닥이 보인 기둥 (그 위에 가구가 없다는 증거)
    var cellArea: [Int64: Float] = [:]    // 1m 칸마다 그물 넓이 (바닥 10cm~2m) — 그 칸을 지금 잘 보고 있는지
    var doorHits: [Int: Set<Int>] = [:]   // 문 번호 → 문 자리를 막고 있는 칸 (폭 10cm × 높이 10cm) — 실제 문이 닫혔는지 판단
    var doorTouched: Set<Int> = []        // 이 그물이 문 자리를 지나는 문
    var floorY: Float?                    // 이 그물에서 '바닥'으로 알아본 면의 높이 (가운데 값, 지금 좌표)
    var floorN = 0
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

enum Skin {
    /// 블록으로 칠 최소 넓이 (블록 한 면의 12%) — 스치기만 한 가는 조각은 블록이 되지 않음
    static let voxMin: Float = 0.0012

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
            let ra = find(a), rb = find(b)
            if ra != rb { parent[rb] = ra }
            let r2 = find(c), r1 = find(a)
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
            if cp.area < 0.25 && cp.area < 0.06 * size * size { continue }             // 가늘고 긴 조각 (케이블·문틀 끝·벽 가장자리 띠)
            keep[t] = true
        }
        return keep
    }

    /// 실제 그물 → 방 안 가구·물건만 골라 10cm 블록으로.
    /// 벽은 사각형에서 반듯하게 세우므로 벽 가까이의 면은 버림. 방 밖·천장·바닥 면, 2m 위도 버림.
    /// saved: 스캔 때 저장한 그물 (문·바닥 판단은 하지 않음)
    static func build(_ m: MeshCopy, _ I: SkinInfo, _ fit: Fit, saved: Bool = false) -> SkinResult {
        let L = I.layout
        var out = SkinResult()
        let wv = m.v.map { simd_make_float3(m.m * SIMD4<Float>($0, 1)) }
        let keep = keepMask(wv, m.f, floorY: L.floorY + fit.y)
        var floors: [Float] = []
        var colTop: [Int64: Float] = [:], colArea: [Int64: Float] = [:]
        var i = 0, fi = 0
        while i + 2 < m.f.count {
            defer { i += 3; fi += 1 }
            let ia = Int(m.f[i]), ib = Int(m.f[i + 1]), ic = Int(m.f[i + 2])
            guard ia < wv.count, ib < wv.count, ic < wv.count else { continue }
            let a = wv[ia], b = wv[ib], c = wv[ic]
            let cr = simd_cross(b - a, c - a)
            let len = simd_length(cr)
            guard len > 1e-9 else { continue }
            let sa = fit.toSaved(a), sb = fit.toSaved(b), sc = fit.toSaved(c)
            let ctr = (sa + sb + sc) / 3
            let pp = L.plane(ctr.x, ctr.z)
            let hgt = ctr.y - L.floorY
            if hgt > 0.1 && hgt < 2.0 { out.cellArea[Vox.chunkOf(pp), default: 0] += len / 2 }
            let n = cr / len
            let cls: UInt8 = fi < m.c.count ? m.c[fi] : 0
            let ns = fit.dirToSaved(n)
            // 바닥이 보이는 기둥: 그 위엔 가구가 없음 (예전에 생긴 기둥을 지우는 근거)
            if !saved && (cls == MeshClass.floor || ns.y > 0.85) && abs(hgt) < 0.08 {
                for s in [sa, sb, sc, ctr] {
                    let q = L.plane(s.x, s.z)
                    out.floorSeen.insert(Vox.chunkKey(Int((q.x / Vox.size).rounded(.down)), Int((q.y / Vox.size).rounded(.down))))
                }
            }
            guard fi < keep.count, keep[fi] else { continue }
            if !saved && cls == MeshClass.floor && n.y > 0.9 { floors.append((a.y + b.y + c.y) / 3) }
            // 문 자리(앞뒤 30cm, 양옆 15cm)는 문턱 높이(12cm) 위를 모두 비움 — 문틀·문짝·전선이 허공에 뜬 조각처럼 보이지 않게.
            // 실제 문이 닫혔는지는 '문 자리를 가로막고 선 면'만 셈: 건너가는 방향을 마주 보는 면이
            // 문틀 안쪽(양옆 8cm 뺀 폭 × 0.3~1.9m)을 얼마나 덮는지. 옆으로 젖혀진 문짝·문틀 옆면은 방향이 달라 안 셈
            var inDoor = false
            let np = SIMD2<Float>(simd_dot(SIMD2<Float>(ns.x, ns.z), L.ex), simd_dot(SIMD2<Float>(ns.x, ns.z), L.ez))
            if hgt > 0.12 && Skin.inSwing(L, pp) { inDoor = true }
            for (di, ds) in L.doors.enumerated() where ds.zone(pp, margin: 0.3, side: 0.15) {
                guard !saved else { continue }
                if hgt > 0.3 && hgt < 1.9 { out.doorTouched.insert(di) }
                let across = abs(ds.alongU ? np.x : np.y)
                let sx = ds.alongU ? pp.y : pp.x
                if cls != MeshClass.floor && cls != MeshClass.ceiling && hgt > 0.3 && hgt < 1.9 && across > 0.75
                    && sx > ds.s0 + 0.08 && sx < ds.s1 - 0.08 && ds.zone(pp, margin: 0.12) {
                    let col = Int((sx - ds.s0 - 0.08) / 0.1), row = Int((hgt - 0.3) / 0.1)
                    out.doorHits[di, default: []].insert(row * 1000 + col)
                }
            }
            if inDoor { continue }
            let here = L.at(x: ctr.x, z: ctr.z)
            let r = here.room
            if r == 0 || r >= 256 { continue }                       // 방 밖
            // 벽에 붙은 것(문틀·케이블·콘센트·액자·선반 끝·스캔이 덜 된 벽 조각):
            // 반듯한 벽에서 30cm 안은 모두, 60cm 안의 세운 면은 분류와 상관없이, '벽·창·문'으로 알아본 면은 1.2m 안이면 지움
            if here.wall < 0.3 { continue }
            let wallish = cls == MeshClass.wall || cls == MeshClass.window || cls == MeshClass.door
            if abs(ns.y) < 0.5 && (here.wall < 0.6 || (wallish && here.wall < 1.2)) { continue }
            if hgt > 2.0 { continue }                                // 머리 위 (천장 조명·커튼 레일)
            if cls == MeshClass.ceiling || hgt > L.ceil[r] - 0.1 { continue }
            // 바닥·바닥에 깔린 것(러그·바닥 얼룩)은 가구가 아님
            if cls == MeshClass.floor || (ns.y > 0.8 && hgt < 0.15) || hgt < -0.05 { continue }
            // 10cm 기둥으로: 삼각형 위를 5cm 간격으로 찍어 그 점이 든 기둥의 가장 높은 곳과 넓이를 모음
            func q(_ s: SIMD3<Float>) -> SIMD3<Float> { let p = L.plane(s.x, s.z); return SIMD3<Float>(p.x, s.y - L.floorY, p.y) }
            let qa = q(sa), qb = q(sb), qc = q(sc)
            let e = max(simd_distance(qa, qb), max(simd_distance(qb, qc), simd_distance(qc, qa)))
            let k = min(12, max(1, Int((e / 0.05).rounded(.up))))
            let per = (len / 2) / Float((k + 1) * (k + 2) / 2)
            for x in 0...k {
                for y in 0...(k - x) {
                    let w1 = Float(x) / Float(k), w2 = Float(y) / Float(k)
                    let p = qa + (qb - qa) * w1 + (qc - qa) * w2
                    guard p.y >= 0, p.y < 2.05 else { continue }
                    let key = Vox.chunkKey(Int((p.x / Vox.size).rounded(.down)), Int((p.z / Vox.size).rounded(.down)))
                    colArea[key, default: 0] += per
                    if p.y > (colTop[key] ?? 0) { colTop[key] = p.y }
                }
            }
        }
        // 넓이가 작은 기둥(스치기만 한 조각)과 15cm 밑(바닥에 놓인 납작한 것)은 버림
        for (k, top) in colTop where top >= 0.15 && (colArea[k] ?? 0) >= 0.0015 { out.cols[k] = top }
        if floors.count >= 20 {
            floors.sort()
            out.floorY = floors[floors.count / 2]
            out.floorN = floors.count
        }
        return out
    }

    /// 문이 열리고 닫히며 쓸고 지나가는 자리 (문 자리 + 양쪽 방으로 문 폭만큼, 최대 1m) — 실제 집에서도 늘 비어 있는 곳.
    /// 이 안의 그물(반쯤 열린 문짝·문틀)은 가구로 치지 않음 → 문짝이 뒤늦게 큰 기둥으로 생겨 문을 막지 않게
    static func inSwing(_ L: Layout, _ p: SIMD2<Float>) -> Bool {
        for ds in L.doors where ds.zone(p, margin: min(1.0, max(0.3, ds.width)) + 0.05, side: 0.15) { return true }
        return false
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

/// 탐험하며 확인한 가구 기둥을 공간 폴더에 저장 (다음 탐험에선 처음부터 가구가 있게). 다시 스캔하면 지움.
/// cols.bin: 기둥마다 Int64 하나 (아래 48비트 = 기둥 키, 위 = 높이 10cm 단위). 예전 블록 파일(vox.bin)은 쓰지 않고 지움
enum VoxStore {
    static func url(_ id: String) -> URL { SpaceStore.folder(id).appendingPathComponent("cols.bin") }
    private static let keyMask: Int64 = (1 << 48) - 1

    static func save(_ id: String, _ cols: [Int64: UInt8]) {
        var arr = cols.map { ($0.key & keyMask) | (Int64($0.value) << 48) }
        let data = arr.withUnsafeMutableBufferPointer { Data(buffer: $0) }
        try? data.write(to: url(id), options: .atomic)
    }

    static func load(_ id: String) -> [Int64: UInt8]? {
        try? FileManager.default.removeItem(at: SpaceStore.folder(id).appendingPathComponent("vox.bin"))
        guard let data = try? Data(contentsOf: url(id)), data.count >= 8, data.count % 8 == 0 else { return nil }
        var out: [Int64: UInt8] = [:]
        data.withUnsafeBytes { raw in
            for i in 0..<(data.count / 8) {
                let v = raw.loadUnaligned(fromByteOffset: i * 8, as: Int64.self)
                out[v & keyMask] = UInt8(truncatingIfNeeded: v >> 48)
            }
        }
        return out
    }

    static func clear(_ id: String) {
        try? FileManager.default.removeItem(at: url(id))
        try? FileManager.default.removeItem(at: SpaceStore.folder(id).appendingPathComponent("vox.bin"))
    }
}

/// 손으로 고친 가구 (탐험 중 '가구 맞추기'): 스캔·그물로 알아낸 기둥보다 늘 먼저 따름.
/// - erases: 비운 곳 (그 안의 알아낸 기둥은 없는 것으로) / adds: 넣은 상자 (그 안은 그 높이의 가구). 평면 좌표(m), 벽과 나란함
/// furni.json 에 저장 (다시 스캔하면 지움)
struct FurnBox: Codable, Equatable {
    var cx: Float; var cz: Float; var w: Float; var d: Float; var h: Float
    var y: Float? = nil                 // 밑면 높이(바닥에서 m) — 다른 가구 위에 올려 둔 상자. 예전 파일엔 없음(바닥)
    var base: Float { y ?? 0 }
}
struct FurnRect: Codable, Equatable { var x0: Float; var z0: Float; var x1: Float; var z1: Float }
struct FurnEdits: Codable, Equatable {
    var adds: [FurnBox] = []
    var erases: [FurnRect] = []
}

enum FurnStore {
    static func url(_ id: String) -> URL { SpaceStore.folder(id).appendingPathComponent("furni.json") }
    static func load(_ id: String) -> FurnEdits {
        guard let d = try? Data(contentsOf: url(id)), let e = try? JSONDecoder().decode(FurnEdits.self, from: d) else { return FurnEdits() }
        return e
    }
    static func save(_ id: String, _ e: FurnEdits) {
        if let d = try? JSONEncoder().encode(e) { try? d.write(to: url(id), options: .atomic) }
    }
    static func clear(_ id: String) { try? FileManager.default.removeItem(at: url(id)) }
}

/// 가구 = 바닥에서 솟은 10cm 기둥들 (마인크래프트처럼 반듯한 덩어리).
/// - 기둥마다 점수: 그물에 가구로 보이면 +2, 바닥이 보이면(그 위가 비었음) -1. 충분히 확인되어야 보이고,
///   한 번 보이면 이번 탐험이 끝날 때까지 그대로(높이도) — 생겼다 사라졌다 하지 않음. 잘못 생긴 기둥은 다음 탐험 저장에서 빠짐
/// - 늘 바닥에서 솟은 기둥이라 허공에 뜬 블록이 생길 수 없음. 둘레 8칸 중 기둥이 2개 넘게 있어야 그림(외톨이 기둥 없음)
/// - 높이는 처음 보일 때 최근 4번 본 값의 가운데 값으로 정하고 그 뒤로는 바꾸지 않음
@MainActor
final class VoxelWorld {
    private struct Col {
        var score: Int8 = 0
        var shown = false
        var h: UInt8 = 0                    // 보이는 높이 (10cm 단위)
        var hist: [UInt8] = []              // 최근 본 높이
        var seen: UInt8 = 0                 // 가구로 본 횟수
        var first: Float = -1               // 처음 본 때 (지난 탐험·스캔에서 온 기둥은 -1)
        var lastHit: Float = -100           // 마지막으로 점수를 올린 때
        var lastFloor: Float = -100         // 마지막으로 점수를 내린 때
        var ready = false                   // 보일 준비가 됨 (1m 칸마다 모아서 한 번에 다듬어 보임)
    }
    private var pendingChunks: [Int64: (Float, Float)] = [:]     // 1m 칸 → (처음 준비된 때, 마지막으로 준비된 때)
    /// 세계를 보여 주기 전(처음 몇 초)엔 지난 탐험에서 온 기둥도 바닥이 보이면 지움. 보여 준 뒤로는 고정
    var revealed = false
    private var floorAt: [Int64: Float] = [:]           // 이번 탐험에서 바닥이 보였던 칸 → 그때
    let root = Entity()                                 // 저장 좌표 (공간 뿌리 아래)
    private let L: Layout
    private var cols: [Int64: Col] = [:]
    private var byChunk: [Int64: Set<Int64>] = [:]      // 1m 칸 → 보이는 기둥
    private var dirty: Set<Int64> = []
    private var ents: [Int64: ModelEntity] = [:]
    private var lineEnts: [Int64: ModelEntity] = [:]
    private var colRoom: [Int64: Int] = [:]
    /// 손으로 고친 칸 → 높이(10cm 단위, 0 = 비움). 알아낸 기둥보다 먼저 (shownH 한 곳에서 따름)
    private var editH: [Int64: UInt8] = [:]
    private var editByChunk: [Int64: Set<Int64>] = [:]
    /// 손으로 넣은 상자 칸의 방 = 상자 가운데가 있는 방 (그 방 테마로 칠함). 옆 가구 덩어리와 섞어 정하지 않음
    private var editRoom: [Int64: Int] = [:]
    /// 손으로 비운 칸 (가구 맞추기 거리 표시에서 알아낸 기둥을 뺄 때)
    private var erased: Set<Int64> = []
    private(set) var changed = false
    var material: (Int, Int) -> RealityKit.Material = { _, _ in UnlitMaterial(color: .gray) }
    var sun: (Int) -> SIMD3<Float> = { _ in SIMD3<Float>(0, 1, 0) }
    var tile: (Int) -> Float = { _ in 1 }
    var lines: (Int) -> Bool = { _ in false }
    var fallbackRoom = 1

    init(_ L: Layout) { self.L = L }

    private static let off: Int64 = 1 << 20
    private static let mask: Int64 = (1 << 21) - 1
    private static func uv(_ k: Int64) -> (Int, Int) { (Int(((k >> 21) & mask) - off), Int((k & mask) - off)) }
    private static func chunkOfCol(_ k: Int64) -> Int64 { let (u, v) = uv(k); return Vox.chunkKey(Vox.fdiv(u), Vox.fdiv(v)) }

    // MARK: 손으로 고친 가구
    /// 칸 가운데가 사각형 안인 10cm 칸들
    private static func cells(_ x0: Float, _ z0: Float, _ x1: Float, _ z1: Float) -> [Int64] {
        let u0 = Int((min(x0, x1) / Vox.size - 0.5).rounded(.up)), u1 = Int((max(x0, x1) / Vox.size - 0.5).rounded(.down))
        let v0 = Int((min(z0, z1) / Vox.size - 0.5).rounded(.up)), v1 = Int((max(z0, z1) / Vox.size - 0.5).rounded(.down))
        guard u0 <= u1, v0 <= v1, (u1 - u0) * (v1 - v0) < 200_000 else { return [] }
        var out: [Int64] = []
        for u in u0...u1 { for v in v0...v1 { out.append(Vox.chunkKey(u, v)) } }
        return out
    }

    /// 손으로 고친 가구를 적용 (바뀐 칸만 다시 그림)
    func setEdits(_ e: FurnEdits) {
        var nh: [Int64: UInt8] = [:]
        for r in e.erases { for k in Self.cells(r.x0, r.z0, r.x1, r.z1) { nh[k] = 0 } }
        erased = Set(nh.keys)
        var nr: [Int64: Int] = [:]
        for b in e.adds {
            let h = UInt8(min(25, max(1, Int(((b.base + b.h) / Vox.size).rounded()))))      // 위에 올려 둔 상자는 밑면 높이까지 더한 윗면
            let c = L.flat(SIMD2<Float>(b.cx, b.cz))
            var room = L.at(x: c.x, z: c.y).room
            if room == 0 { room = L.roomNear(x: c.x, z: c.y, radius: 0.8) }
            if room == 0 { room = fallbackRoom }
            for k in Self.cells(b.cx - b.w / 2, b.cz - b.d / 2, b.cx + b.w / 2, b.cz + b.d / 2) { nh[k] = h; nr[k] = room }
        }
        var diff = Set<Int64>()
        for (k, h) in nh where editH[k] != h { diff.insert(k) }
        for k in editH.keys where nh[k] == nil { diff.insert(k) }
        for (k, r) in nr where editRoom[k] != r { diff.insert(k) }
        guard !diff.isEmpty else { return }
        editH = nh
        editRoom = nr
        editByChunk = [:]
        for k in nh.keys where nh[k] ?? 0 > 0 { editByChunk[Self.chunkOfCol(k), default: []].insert(k) }
        colRoom.removeAll()                                 // 덩어리가 바뀜 → 칠할 방을 다시 정함
        for k in diff { markDirty(k) }
    }

    /// 그 자리(평면 좌표)의 평평한 가구 면 (붙은 보이는 기둥 중 높이 차 10cm 안, 1.2m 안): 둘레 사각형(평면 좌표 m)과 가장 많은 높이(m)
    func pieceAt(_ p: SIMD2<Float>) -> (SIMD2<Float>, SIMD2<Float>, Float)? {
        /// 알아낸 기둥만 (손으로 고친 칸 — 넣은 상자·비운 곳 — 은 빼고: 옆에 놓은 상자와 한 덩어리로 묶이지 않게)
        func pieceH(_ u: Int, _ v: Int) -> Int { editH[Vox.chunkKey(u, v)] != nil ? 0 : shownH(u, v) }
        let u = Int((p.x / Vox.size).rounded(.down)), v = Int((p.y / Vox.size).rounded(.down))
        var start: (Int, Int)? = pieceH(u, v) > 0 ? (u, v) : nil
        if start == nil {
            outer: for du in -1...1 { for dv in -1...1 where pieceH(u + du, v + dv) > 0 { start = (u + du, v + dv); break outer } }
        }
        guard let s0 = start else { return nil }
        let h0 = pieceH(s0.0, s0.1)
        var seen: Set<Int64> = [Vox.chunkKey(s0.0, s0.1)]
        var q = [s0], qi = 0
        var lo = SIMD2<Int>(s0.0, s0.1), hi = lo
        var hist: [Int: Int] = [:]
        while qi < q.count && q.count < 6000 {
            let (cu, cv) = q[qi]; qi += 1
            hist[pieceH(cu, cv), default: 0] += 1
            lo = SIMD2<Int>(min(lo.x, cu), min(lo.y, cv)); hi = SIMD2<Int>(max(hi.x, cu), max(hi.y, cv))
            for du in -1...1 { for dv in -1...1 where du != 0 || dv != 0 {
                let k = Vox.chunkKey(cu + du, cv + dv)
                // 탭한 곳과 같은 평평한 면(높이 차 10cm 안)만, 탭한 곳에서 1.2m 안까지 — 이어진 가구 전체가 한 상자가 되지 않게
                let nh = pieceH(cu + du, cv + dv)
                guard !seen.contains(k), nh > 0, abs(nh - h0) <= 1, abs(cu + du - s0.0) <= 12, abs(cv + dv - s0.1) <= 12 else { continue }
                seen.insert(k)
                q.append((cu + du, cv + dv))
            } }
        }
        let h = hist.max { $0.value != $1.value ? $0.value < $1.value : $0.key < $1.key }?.key ?? 4
        return (SIMD2<Float>(Float(lo.x), Float(lo.y)) * Vox.size, SIMD2<Float>(Float(hi.x + 1), Float(hi.y + 1)) * Vox.size, Float(h) * Vox.size)
    }

    /// 가구 맞추기 거리 표시용: 그 칸(평면 좌표 10cm 칸)의 '알아낸' 가구 높이(m) — 손으로 비운 칸은 0, 손으로 넣은 상자는 셈하지 않음
    /// (넣은 상자는 가구 맞추기 쪽에서 상자 사각형으로 따로 셈 — 고치고 있는 상자 자신을 빼려고). 외톨이 기둥은 0 (shownH와 같은 규칙)
    func scanH(_ u: Int, _ v: Int) -> Float {
        let k = Vox.chunkKey(u, v)
        if erased.contains(k) { return 0 }
        guard let c = cols[k], c.shown else { return 0 }
        var n = 0
        for du in -1...1 { for dv in -1...1 where du != 0 || dv != 0 {
            let nk = Vox.chunkKey(u + du, v + dv)
            if let o = cols[nk], o.shown, !erased.contains(nk) { n += 1; if n >= 3 { return Float(c.h) * Vox.size } }
        } }
        return 0
    }

    /// 가구 맞추기 화면용: 알아낸 가구 기둥(손으로 넣은 상자 칸은 빼고)의 윗면·옆면 그물 (저장 좌표)
    func previewMesh() -> MeshResource? {
        var g = Geo()
        let floorY = L.floorY
        func w(_ u: Float, _ v: Float, _ h: Float) -> SIMD3<Float> {
            let f = L.flat(SIMD2<Float>(u * Vox.size, v * Vox.size))
            return SIMD3<Float>(f.x, floorY + h * Vox.size, f.y)
        }
        for k in cols.keys where (editH[k] ?? 0) == 0 {
            let (u, v) = Self.uv(k)
            let h = shownH(u, v)
            guard h > 0 else { continue }
            let fu = Float(u), fv = Float(v), fh = Float(h)
            g.quad(w(fu, fv, fh), w(fu + 1, fv, fh), w(fu + 1, fv + 1, fh), w(fu, fv + 1, fh), .zero, .zero, .zero, .zero)
            for (nu, nv, d) in [(u + 1, v, 0), (u - 1, v, 1), (u, v + 1, 2), (u, v - 1, 3)] {
                let nh = Float(shownH(nu, nv))
                guard nh < fh else { continue }
                let p: [SIMD3<Float>]
                switch d {
                case 0: p = [w(fu + 1, fv, nh), w(fu + 1, fv + 1, nh), w(fu + 1, fv + 1, fh), w(fu + 1, fv, fh)]
                case 1: p = [w(fu, fv + 1, nh), w(fu, fv, nh), w(fu, fv, fh), w(fu, fv + 1, fh)]
                case 2: p = [w(fu + 1, fv + 1, nh), w(fu, fv + 1, nh), w(fu, fv + 1, fh), w(fu + 1, fv + 1, fh)]
                default: p = [w(fu, fv, nh), w(fu + 1, fv, nh), w(fu + 1, fv, fh), w(fu, fv, fh)]
                }
                g.quad(p[0], p[1], p[2], p[3], .zero, .zero, .zero, .zero)
                g.quad(p[3], p[2], p[1], p[0], .zero, .zero, .zero, .zero)       // 양면 (어느 쪽에서 봐도)
            }
        }
        return g.mesh("furnPreview")
    }

    // MARK: 기둥 넣고 빼기
    /// 지난 탐험에서 확인한 기둥(또는 스캔 그물에서 만든 기둥) — 처음부터 보임
    func seed(_ list0: [Int64: UInt8]) {
        let list = Self.tidy(list0, fixed: [:])
        for (k, h) in list where h >= 2 {
            var c = Col()
            c.score = 4; c.shown = true; c.h = h; c.hist = [h, h, h]; c.seen = 3
            cols[k] = c
            byChunk[Self.chunkOfCol(k), default: []].insert(k)
            markDirty(k)
        }
    }

    /// 그물 한 덩어리를 새로 읽음 (좌표가 자리를 잡은 뒤에만 부름)
    /// 갑자기 나타난 큰 덩어리(지나간 사람·움직인 문·반사) 막기:
    /// - 점수는 0.6초에 한 번만 오름 (그물이 짧은 사이 여러 번 와도 한 번으로)
    /// - 처음 본 뒤 2.5초 넘게 계속 보여야 나타남. 이번 탐험에서 바닥이 보였던 칸(그 위가 비어 있던 곳)은 6초
    /// - 이번 탐험에서 새로 생긴 기둥은 바닥이 보이면 3점씩 깎여 빨리 사라짐 (지난 탐험에서 확인한 가구는 1점씩)
    func update(cols obs: [Int64: Float], floor: Set<Int64>, now: Float) {
        for (k, top) in obs {
            var c = cols[k] ?? Col()
            c.hist.append(UInt8(min(21, max(2, Int((top / Vox.size).rounded(.up))))))
            if c.hist.count > 4 { c.hist.removeFirst() }
            if now - c.lastHit >= 0.6 {
                c.lastHit = now
                c.score = min(8, c.score + 2)
                c.seen = c.seen < 250 ? c.seen + 1 : c.seen
                if c.first < 0 && !c.shown { c.first = now }
            }
            apply(k, c, now)
        }
        for k in floor where obs[k] == nil {
            floorAt[k] = now
            guard var c = cols[k], now - c.lastFloor >= 0.6 else { continue }
            c.lastFloor = now
            let fresh = c.first >= 0 && now - c.first < 180
            c.score = max(-4, c.score - (fresh ? 3 : 1))
            apply(k, c, now)
        }
    }

    private func median(_ a: [UInt8]) -> UInt8 {
        guard !a.isEmpty else { return 0 }
        let s = a.sorted()
        return s[s.count / 2]
    }

    private func apply(_ k: Int64, _ c0: Col, _ now: Float) {
        var c = c0
        let med = median(c.hist)
        let wasFloor = (floorAt[k].map { now - $0 < 90 }) ?? false
        let need: Float = wasFloor ? 6 : 2.5
        if !c.shown && !c.ready && c.score >= 5 && c.seen >= 3 && c.first >= 0 && now - c.first >= need {
            c.ready = true
            c.h = med
            let ch = Self.chunkOfCol(k)
            pendingChunks[ch] = (pendingChunks[ch]?.0 ?? now, now)
        } else if c.ready && c.score <= 0 {
            c.ready = false
        } else if !revealed && c.shown && c.score <= -2 {
            // 보여 주기 전: 지난 탐험에서 온 기둥인데 지금 그 자리 바닥이 보이면 치움
            c.shown = false
            byChunk[Self.chunkOfCol(k)]?.remove(k)
            markDirty(k)
            changed = true
        }
        // 한 번 보인 기둥은 이번 탐험이 끝날 때까지 그대로 (높이도 안 바꿈) — 가구가 생겼다 사라졌다·높이가 바뀌며
        // 그 위에 놓인 차림·동물이 뜨거나 묻히지 않게. 바닥이 보였다는 기록만 남겨 두고, 다음 탐험 저장에서 뺌
        if !c.shown && c.score <= 0 && c.first >= 0 && now - c.lastHit > 4 { c.first = -1 }   // 한동안 안 보이면 처음부터 다시 셈
        if !c.shown && c.score <= -4 { cols[k] = nil; return }
        cols[k] = c
    }

    /// 그 기둥의 칸 (칸 가장자리면 옆 칸도 — 옆면·외톨이 판단이 이웃에 따라 바뀜)
    private func markDirty(_ k: Int64) {
        let (u, v) = Self.uv(k)
        for du in -1...1 { for dv in -1...1 { dirty.insert(Vox.chunkKey(Vox.fdiv(u + du), Vox.fdiv(v + dv))) } }
    }

    /// 매 프레임: 바뀐 칸 다시 그리기 (한 번에 budget개)
    func tick(budget: Int = 3, now: Float = 0) {
        // 준비된 기둥은 1m 칸마다 모아 두었다가(1.2초 동안 더 안 늘거나 4초가 지나면) 한꺼번에 다듬어 보임
        for (ch, tt) in pendingChunks where now - tt.1 > 1.2 || now - tt.0 > 4 {
            pendingChunks[ch] = nil
            commit(ch)
        }
        guard !dirty.isEmpty else { return }
        for c in Array(dirty.prefix(budget)) { rebuild(c) }
    }

    /// 그 1m 칸의 준비된 기둥을 다듬어 보임: 이미 보이는 이웃 기둥(고정)에 높이를 맞추고, 작은 부스러기·삐죽한 기둥은 버림
    private func commit(_ ch: Int64) {
        var ready: [Int64: UInt8] = [:]
        var fixed: [Int64: UInt8] = [:]
        let (cu, cv) = Self.uv(ch)
        for (k, c) in cols {
            let (u, v) = Self.uv(k)
            let du = Vox.fdiv(u) - cu, dv = Vox.fdiv(v) - cv
            guard abs(du) <= 1 && abs(dv) <= 1 else { continue }
            if c.shown { fixed[k] = c.h } else if c.ready && du == 0 && dv == 0 { ready[k] = c.h }
        }
        guard !ready.isEmpty else { return }
        let out = Self.tidy(ready, fixed: fixed)
        for (k, _) in ready {
            guard var c = cols[k] else { continue }
            c.ready = false
            if let h = out[k] {
                c.shown = true
                c.h = h
                byChunk[Self.chunkOfCol(k), default: []].insert(k)
                markDirty(k)
                changed = true
            } else {
                c.score = min(c.score, 3)                     // 부스러기로 버린 것: 더 확인되면 다시 후보
            }
            cols[k] = c
        }
        // 메운 구멍
        for (k, h) in out where ready[k] == nil && cols[k]?.shown != true {
            var c = cols[k] ?? Col()
            c.shown = true; c.ready = false; c.h = h; c.score = 5; c.seen = 3
            cols[k] = c
            byChunk[Self.chunkOfCol(k), default: []].insert(k)
            markDirty(k)
            changed = true
        }
    }

    /// 기둥 모음 다듬기 (새 기둥 `list`, 이미 보이는 고정 기둥 `fixed` — 고정 기둥은 바꾸지 않음):
    /// 1) 서로 붙은 덩어리(대각선 포함)가 고정 기둥과 합쳐도 6칸(0.06㎡) 안 되면 버림 — 사람·반사·케이블 같은 부스러기
    /// 2) 높이 차 10cm 안으로 이어진 '평평한 면'마다 가장 많은 높이로 맞춤 (탁자·소파가 들쑥날쑥하지 않게, 고정 기둥이 있으면 그 높이)
    /// 3) 둘레보다 30cm 넘게 혼자 솟은 기둥은 둘레 높이로
    /// 4) 둘레 8칸 중 6칸 넘게 같은 면으로 둘러싸인 빈칸은 채움 (그물 구멍)
    static func tidy(_ list: [Int64: UInt8], fixed: [Int64: UInt8]) -> [Int64: UInt8] {
        func key(_ u: Int, _ v: Int) -> Int64 { Vox.chunkKey(u, v) }
        var all = fixed
        for (k, h) in list { all[k] = h }
        var out = list
        // 1) 덩어리 크기
        var comp: [Int64: Int] = [:]
        var sizes: [Int] = []
        for k0 in all.keys where comp[k0] == nil {
            let id = sizes.count
            var n = 0
            var stack = [k0]
            comp[k0] = id
            while let k = stack.popLast() {
                n += 1
                let (u, v) = uv(k)
                for du in -1...1 { for dv in -1...1 where du != 0 || dv != 0 {
                    let nk = key(u + du, v + dv)
                    if all[nk] != nil && comp[nk] == nil { comp[nk] = id; stack.append(nk) }
                } }
            }
            sizes.append(n)
        }
        for k in list.keys where sizes[comp[k] ?? 0] < 6 { out[k] = nil }
        // 1-2) 가늘게 솟은 것 깎기 (모폴로지 열기): 칸마다 '그 칸을 품은 창 안 가장 낮은 높이' 중 가장 큰 값까지만.
        //   20cm(2×2) 창: 10cm 두께로 삐죽 나온 띠·모서리는 둘레 높이로 / 1m 위는 30cm(3×3) 창: 문과 벽 사이 틈·문틀·커튼처럼
        //   가늘고 높게 솟은 판·기둥이 천장 쪽으로 서 있지 않고 둘레 가구 높이(또는 1m)로 낮아짐. 반듯한 가구 덩어리는 그대로
        do {
            var cur0 = fixed
            for (k, h) in out { cur0[k] = h }
            func opened(_ u: Int, _ v: Int, _ n: Int) -> UInt8 {
                var best: UInt8 = 0
                for a in (1 - n)...0 { for b in (1 - n)...0 {
                    var m: UInt8 = 255
                    for x in 0..<n { for y in 0..<n { m = min(m, cur0[key(u + a + x, v + b + y)] ?? 0); if m == 0 { break } } }
                    best = max(best, m)
                } }
                return best
            }
            for (k, h) in out {
                let (u, v) = uv(k)
                var nh = min(h, opened(u, v, 2))
                if nh > 10 { nh = max(10, min(nh, opened(u, v, 3))) }
                if nh < 2 { out[k] = nil } else if nh < h { out[k] = nh }
            }
        }
        // 1-3) 얇고 길쭉한 덩어리(평균 두께 22cm 이하, 또는 바닥 넓이 0.12㎡ 이하)인데 80cm 넘게 높은 것 = 벽 조각·문 틈·기둥 → 버림
        do {
            var cur1 = fixed
            for (k, h) in out { cur1[k] = h }
            var seen = Set<Int64>()
            for k0 in out.keys where !seen.contains(k0) {
                var members: [Int64] = []
                var stack = [k0]
                seen.insert(k0)
                var lo = SIMD2<Int>(Int.max, Int.max), hi = SIMD2<Int>(Int.min, Int.min)
                var top: UInt8 = 0
                while let k = stack.popLast() {
                    members.append(k)
                    let (u, v) = uv(k)
                    lo = SIMD2<Int>(min(lo.x, u), min(lo.y, v)); hi = SIMD2<Int>(max(hi.x, u), max(hi.y, v))
                    top = max(top, cur1[k] ?? 0)
                    for du in -1...1 { for dv in -1...1 where du != 0 || dv != 0 {
                        let nk = key(u + du, v + dv)
                        if cur1[nk] != nil && !seen.contains(nk) { seen.insert(nk); stack.append(nk) }
                    } }
                }
                let span = max(hi.x - lo.x, hi.y - lo.y) + 1
                let thin = Float(members.count) / Float(span) <= 2.2 || members.count <= 12
                if thin && top >= 8 { for k in members where list[k] != nil { out[k] = nil } }
            }
        }
        // 2) 평평한 면마다 높이 맞추기
        var cur = fixed
        for (k, h) in out { cur[k] = h }
        var plate: [Int64: Int] = [:]
        var plates: [[Int64]] = []
        for k0 in cur.keys where plate[k0] == nil {
            let id = plates.count
            var members: [Int64] = []
            var stack = [k0]
            plate[k0] = id
            while let k = stack.popLast() {
                members.append(k)
                let (u, v) = uv(k)
                let h = Int(cur[k] ?? 0)
                for (du, dv) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nk = key(u + du, v + dv)
                    if let nh = cur[nk], plate[nk] == nil, abs(Int(nh) - h) <= 1 { plate[nk] = id; stack.append(nk) }
                }
            }
            plates.append(members)
        }
        for members in plates where members.count >= 4 {
            var hist: [UInt8: Int] = [:]
            let fixedIn = members.filter { fixed[$0] != nil }
            for k in (fixedIn.isEmpty ? members : fixedIn) { if let h = cur[k] { hist[h, default: 0] += 1 } }
            guard let mode = hist.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key < $1.key })?.key else { continue }
            for k in members where out[k] != nil { out[k] = mode; cur[k] = mode }
        }
        // 3) 혼자 솟은 기둥
        for (k, h) in out {
            let (u, v) = uv(k)
            var mx: UInt8 = 0
            var n = 0
            for (du, dv) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                if let nh = cur[key(u + du, v + dv)] { mx = max(mx, nh); n += 1 }
            }
            if n >= 2 && Int(h) - Int(mx) >= 3 { out[k] = mx; cur[k] = mx }
        }
        // 4) 구멍 채우기 (새 기둥 둘레만)
        var holes: [Int64: UInt8] = [:]
        for k in out.keys {
            let (u, v) = uv(k)
            for du in -1...1 { for dv in -1...1 where du != 0 || dv != 0 {
                let hk = key(u + du, v + dv)
                guard cur[hk] == nil, holes[hk] == nil else { continue }
                let (hu, hv) = (u + du, v + dv)
                var hs: [UInt8] = []
                for a in -1...1 { for b in -1...1 where a != 0 || b != 0 { if let nh = cur[key(hu + a, hv + b)] { hs.append(nh) } } }
                if hs.count >= 6, let lo = hs.min(), let hi = hs.max(), hi - lo <= 1 { holes[hk] = hs.sorted()[hs.count / 2] }
            } }
        }
        for (k, h) in holes { out[k] = h }
        return out
    }

    func restyle() {
        dirty.formUnion(byChunk.keys)
        dirty.formUnion(editByChunk.keys)
        dirty.formUnion(ents.keys)
    }

    func rebuildAll() async {
        var n = 0
        while let c = dirty.first {
            rebuild(c)
            n += 1
            if n % 24 == 0 { await Task.yield() }
        }
    }

    func markSaved() { changed = false }

    /// 저장할 기둥: 보이고, 세 번 넘게 확인한 것만 (잘못 생긴 기둥이 다음 탐험으로 넘어가지 않게)
    func saveList() -> [Int64: UInt8] {
        var out: [Int64: UInt8] = [:]
        // 이번 탐험에서 그 위가 비어(바닥이) 보인 뒤로 다시 가구로 보이지 않은 기둥은 저장하지 않음 → 다음 탐험부터 사라짐
        for (k, c) in cols where c.shown && c.seen >= 3 && !(c.lastFloor > 0 && c.lastFloor > c.lastHit) { out[k] = c.h }
        return out
    }

    /// 높이가 minH(m) 넘는 보이는 기둥의 10cm 칸 (그림·벽 꾸밈 자리 고르기)
    func blockedCells(minH: Float) -> Set<Int64> {
        var out = Set<Int64>()
        for k in Set(cols.keys).union(editH.keys) {
            let (u, v) = Self.uv(k)
            if Float(shownH(u, v)) * Vox.size >= minH { out.insert(Vox.planeCell(u, v)) }
        }
        return out
    }

    /// 그 10cm 칸(평면 좌표)에 보이는 가구 높이 (m, 없으면 0)
    func heightAt(_ p: SIMD2<Float>) -> Float {
        let u = Int((p.x / Vox.size).rounded(.down)), v = Int((p.y / Vox.size).rounded(.down))
        return Float(shownH(u, v)) * Vox.size
    }

    /// 그 10cm 칸(평면 격자 번호)에 보이는 가구 높이 (10cm 단위, 없으면 0)
    func cellH(_ u: Int, _ v: Int) -> Int { shownH(u, v) }

    /// 고양이가 올라앉을 만한 평평한 가구 윗면 높이 (둘레 3×3 칸이 모두 보이고 높이 차가 10cm 안). 아니면 nil
    func flatTop(_ p: SIMD2<Float>) -> Float? {
        let u = Int((p.x / Vox.size).rounded(.down)), v = Int((p.y / Vox.size).rounded(.down))
        let h = shownH(u, v)
        guard h >= 3 else { return nil }
        for du in -1...1 {
            for dv in -1...1 {
                let o = shownH(u + du, v + dv)
                if o == 0 || abs(o - h) > 1 { return nil }
            }
        }
        return Float(h) * Vox.size
    }

    // MARK: 그물 만들기
    /// 그려지는 높이 (외톨이 기둥은 0)
    /// 그려지는 높이 — 가구 높이를 정하는 한 곳: 손으로 고친 칸(가구 맞추기)이면 그 높이(비운 곳은 0),
    /// 아니면 알아낸 기둥 (외톨이 기둥은 0)
    private func shownH(_ u: Int, _ v: Int) -> Int {
        let k = Vox.chunkKey(u, v)
        if let e = editH[k] { return Int(e) }
        guard let c = cols[k], c.shown else { return 0 }
        var n = 0
        for du in -1...1 { for dv in -1...1 where du != 0 || dv != 0 {
            let nk = Vox.chunkKey(u + du, v + dv)
            if let o = cols[nk], o.shown, editH[nk] != 0 { n += 1; if n >= 3 { return Int(c.h) } }
        } }
        return 0
    }

    /// 가구 기둥이 속한 방 (그 방 테마의 재질·선 그림으로 칠함).
    /// 가구 한 덩어리(서로 붙은 보이는 기둥들)는 모두 같은 방 — 덩어리 기둥들이 놓인 방 중 가장 많은 방으로 정함.
    /// (예전엔 기둥마다 그 자리의 방을 따로 봐서, 방 경계·문 자리에 걸친 가구 일부가 옆방 테마로 칠해져
    ///  선 그림 방에 컬러 무늬 가구가 섞여 보였음)
    private func roomAt(_ u: Int, _ v: Int) -> Int {
        let ck = Vox.chunkKey(u, v)
        if let r = editRoom[ck] { return r }                // 손으로 넣은 상자: 상자 가운데의 방
        if let r = colRoom[ck] { return r }
        func here(_ u: Int, _ v: Int) -> Int {
            let p = L.flat(SIMD2<Float>((Float(u) + 0.5) * Vox.size, (Float(v) + 0.5) * Vox.size))
            var r = L.at(x: p.x, z: p.y).room
            if r == 0 { r = L.roomNear(x: p.x, z: p.y, radius: 0.3) }
            return r
        }
        var members: [Int64] = [ck]
        var tally: [Int: Int] = [:]
        if shownH(u, v) > 0 {
            var seen: Set<Int64> = [ck]
            var queue: [(Int, Int)] = [(u, v)]
            var qi = 0
            while qi < queue.count && queue.count < 4000 {
                let (cu, cv) = queue[qi]; qi += 1
                let r = here(cu, cv)
                if r != 0 { tally[r, default: 0] += 1 }
                for du in -1...1 { for dv in -1...1 where du != 0 || dv != 0 {
                    let k = Vox.chunkKey(cu + du, cv + dv)
                    guard !seen.contains(k), editH[k] == nil, shownH(cu + du, cv + dv) > 0 else { continue }      // 손으로 고친 칸은 덩어리에 넣지 않음
                    seen.insert(k)
                    queue.append((cu + du, cv + dv))
                    members.append(k)
                } }
            }
        } else {
            let r = here(u, v)
            if r != 0 { tally[r] = 1 }
        }
        let r = tally.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key ?? fallbackRoom
        // 덩어리가 커지며(가구가 더 보임) 방이 바뀐 기둥은 그 조각을 다시 칠함
        for k in members {
            if let o = colRoom[k], o != r { dirty.insert(Self.chunkOfCol(k)) }
            colRoom[k] = r
        }
        return r
    }

    private func rebuild(_ c: Int64) {
        dirty.remove(c)
        let keys = (byChunk[c] ?? []).union(editByChunk[c] ?? [])
        if (byChunk[c] ?? []).isEmpty { byChunk[c] = nil }
        let floorY = L.floorY
        func world(_ u: Float, _ v: Float, _ h: Float) -> SIMD3<Float> {
            let f = L.flat(SIMD2<Float>(u * Vox.size, v * Vox.size))
            return SIMD3<Float>(f.x, floorY + h * Vox.size, f.y)
        }
        let ex3 = SIMD3<Float>(L.ex.x, 0, L.ex.y), ez3 = SIMD3<Float>(L.ez.x, 0, L.ez.y)
        func shade(_ n: SIMD3<Float>, _ room: Int) -> Int {
            let l = simd_dot(n, sun(room))
            return l > 0.35 ? 0 : (l > -0.15 ? 1 : 2)
        }
        // 윗면: (높이, 재질) → 칸들 / 옆면: (방향, 줄, 아래, 위, 재질) → 줄 따라 위치들
        struct T: Hashable { let h: Int; let mat: Int }
        struct S: Hashable { let d: Int; let line: Int; let lo: Int; let hi: Int; let mat: Int }
        var tops: [T: Set<SIMD2<Int32>>] = [:]
        var sides: [S: [Int]] = [:]
        var lineRooms = Set<Int>()
        for k in keys {
            let (u, v) = Self.uv(k)
            let h = shownH(u, v)
            guard h > 0 else { continue }
            let room = roomAt(u, v)
            if lines(room) { lineRooms.insert(room) }
            tops[T(h: h, mat: room * 4 + shade(SIMD3<Float>(0, 1, 0), room)), default: []].insert(SIMD2<Int32>(Int32(u), Int32(v)))
            let nb = [(u + 1, v, 0, ex3), (u - 1, v, 1, -ex3), (u, v + 1, 2, ez3), (u, v - 1, 3, -ez3)]
            for (nu, nv, d, n3) in nb {
                let nh = shownH(nu, nv)
                guard nh < h else { continue }
                let line = d == 0 ? u + 1 : (d == 1 ? u : (d == 2 ? v + 1 : v))
                let along = d < 2 ? v : u
                sides[S(d: d, line: line, lo: nh, hi: h, mat: room * 4 + shade(n3, room)), default: []].append(along)
            }
        }
        var geos: [Int: Geo] = [:]
        var lg = Geo()
        let lw: Float = 0.01                 // 선 그림: 가구 테두리 (배경·소품 선과 비슷한 굵기로)
        // 윗면: 같은 높이·재질 칸을 큰 사각형으로
        for (g, cells) in tops {
            var left = cells
            let sorted = cells.sorted { $0.y != $1.y ? $0.y < $1.y : $0.x < $1.x }
            let t = max(0.2, tile(g.mat / 4)) / Vox.size
            let hy = Float(g.h)
            for s in sorted where left.contains(s) {
                var a1 = s.x
                while left.contains(SIMD2<Int32>(a1 + 1, s.y)) { a1 += 1 }
                var b1 = s.y
                rows: while true {
                    for a in s.x...a1 where !left.contains(SIMD2<Int32>(a, b1 + 1)) { break rows }
                    b1 += 1
                }
                for b in s.y...b1 { for a in s.x...a1 { left.remove(SIMD2<Int32>(a, b)) } }
                let u0 = Float(s.x), u1 = Float(a1) + 1, v0 = Float(s.y), v1 = Float(b1) + 1
                geos[g.mat, default: Geo()].quad(world(u0, v0, hy), world(u1, v0, hy), world(u1, v1, hy), world(u0, v1, hy),
                                                 SIMD2<Float>(u0, v0) / t, SIMD2<Float>(u1, v0) / t, SIMD2<Float>(u1, v1) / t, SIMD2<Float>(u0, v1) / t)
            }
        }
        // 옆면: 같은 줄에서 이어진 칸을 한 장으로, 선 그림이면 윗모서리·양끝 세로선·바닥선
        for (s, list) in sides {
            let room = s.mat / 4
            let t = max(0.2, tile(room)) / Vox.size
            let drawLines = lineRooms.contains(room)
            let sorted = list.sorted()
            var i = 0
            while i < sorted.count {
                var j = i
                while j + 1 < sorted.count && sorted[j + 1] == sorted[j] + 1 { j += 1 }
                let a0 = Float(sorted[i]), a1 = Float(sorted[j]) + 1
                let ln = Float(s.line), lo = Float(s.lo), hi = Float(s.hi)
                let p: [SIMD3<Float>] = s.d < 2
                    ? [world(ln, a0, lo), world(ln, a1, lo), world(ln, a1, hi), world(ln, a0, hi)]
                    : [world(a0, ln, lo), world(a1, ln, lo), world(a1, ln, hi), world(a0, ln, hi)]
                geos[s.mat, default: Geo()].quad(p[0], p[1], p[2], p[3],
                                                 SIMD2<Float>(a0, -lo) / t, SIMD2<Float>(a1, -lo) / t, SIMD2<Float>(a1, -hi) / t, SIMD2<Float>(a0, -hi) / t)
                if drawLines {
                    lg.stroke(p[3], p[2], width: lw)                   // 윗모서리
                    if s.lo == 0 {                                     // 바닥에 닿는 선 (바닥 면보다 1.5cm 위 — 겹쳐 깜빡이지 않게)
                        let up = SIMD3<Float>(0, 0.015, 0)
                        lg.stroke(p[0] + up, p[1] + up, width: lw)
                    }
                    lg.stroke(p[0], p[3], width: lw)                   // 양끝 세로선
                    lg.stroke(p[1], p[2], width: lw)
                }
                i = j + 1
            }
        }
        var descs: [MeshDescriptor] = []
        var ms: [RealityKit.Material] = []
        for (mk, geo) in geos where !geo.isEmpty {
            var md = MeshDescriptor(name: "c\(mk)")
            md.positions = MeshBuffers.Positions(geo.pos)
            md.textureCoordinates = MeshBuffers.TextureCoordinates(geo.uv)
            md.primitives = .triangles(geo.idx)
            md.materials = .allFaces(UInt32(ms.count))
            descs.append(md)
            ms.append(material(mk / 4, mk % 4))
        }
        if descs.isEmpty {
            ents.removeValue(forKey: c)?.removeFromParent()
        } else {
            let e: ModelEntity
            if let old = ents[c] { e = old } else { e = ModelEntity(); root.addChild(e); ents[c] = e }
            if let mesh = try? MeshResource.generate(from: descs) { e.model = ModelComponent(mesh: mesh, materials: ms) }
        }
        if let m = lg.mesh("outline") {
            let le: ModelEntity
            if let old = lineEnts[c] { le = old } else { le = ModelEntity(); root.addChild(le); lineEnts[c] = le }
            le.model = ModelComponent(mesh: m, materials: [Ink.line])
        } else {
            lineEnts.removeValue(forKey: c)?.removeFromParent()
        }
    }
}
