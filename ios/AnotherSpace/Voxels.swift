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
            for (di, ds) in L.doors.enumerated() where ds.zone(pp, margin: 0.3, side: 0.15) {
                if hgt > 0.12 { inDoor = true }
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

/// 가구 = 바닥에서 솟은 10cm 기둥들 (마인크래프트처럼 반듯한 덩어리).
/// - 기둥마다 점수: 그물에 가구로 보이면 +2, 바닥이 보이면(그 위가 비었음) -1. 3점이 되어야 보이고, 0점 밑으로 떨어져야 사라짐 →
///   그물이 한두 번 흔들려도 생겼다 사라졌다 하지 않음. 비전프로가 그물을 치워도(멀어져서) 그대로 둠
/// - 늘 바닥에서 솟은 기둥이라 허공에 뜬 블록이 생길 수 없음. 둘레 8칸 중 기둥이 2개 넘게 있어야 그림(외톨이 기둥 없음)
/// - 높이는 최근 4번 본 값의 가운데 값, 20cm 넘게 바뀌거나 세 번 연속 같을 때만 바꿈
@MainActor
final class VoxelWorld {
    private struct Col {
        var score: Int8 = 0
        var shown = false
        var h: UInt8 = 0                    // 보이는 높이 (10cm 단위)
        var hist: [UInt8] = []              // 최근 본 높이
        var seen: UInt8 = 0                 // 가구로 본 횟수
    }
    let root = Entity()                                 // 저장 좌표 (공간 뿌리 아래)
    private let L: Layout
    private var cols: [Int64: Col] = [:]
    private var byChunk: [Int64: Set<Int64>] = [:]      // 1m 칸 → 보이는 기둥
    private var dirty: Set<Int64> = []
    private var ents: [Int64: ModelEntity] = [:]
    private var lineEnts: [Int64: ModelEntity] = [:]
    private var colRoom: [Int64: Int] = [:]
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

    // MARK: 기둥 넣고 빼기
    /// 지난 탐험에서 확인한 기둥(또는 스캔 그물에서 만든 기둥) — 처음부터 보임
    func seed(_ list: [Int64: UInt8]) {
        for (k, h) in list where h >= 2 {
            var c = Col()
            c.score = 4; c.shown = true; c.h = h; c.hist = [h, h, h]; c.seen = 3
            cols[k] = c
            byChunk[Self.chunkOfCol(k), default: []].insert(k)
            markDirty(k)
        }
    }

    /// 그물 한 덩어리를 새로 읽음 (좌표가 자리를 잡은 뒤에만 부름)
    func update(cols obs: [Int64: Float], floor: Set<Int64>) {
        for (k, top) in obs {
            var c = cols[k] ?? Col()
            c.score = min(6, c.score + 2)
            c.seen = c.seen < 250 ? c.seen + 1 : c.seen
            c.hist.append(UInt8(min(21, max(2, Int((top / Vox.size).rounded(.up))))))
            if c.hist.count > 4 { c.hist.removeFirst() }
            apply(k, c)
        }
        for k in floor where obs[k] == nil {
            guard var c = cols[k] else { continue }
            c.score = max(-4, c.score - 1)
            apply(k, c)
        }
    }

    private func median(_ a: [UInt8]) -> UInt8 {
        guard !a.isEmpty else { return 0 }
        let s = a.sorted()
        return s[s.count / 2]
    }

    private func apply(_ k: Int64, _ c0: Col) {
        var c = c0
        let med = median(c.hist)
        if !c.shown && c.score >= 3 {
            c.shown = true
            c.h = med
            byChunk[Self.chunkOfCol(k), default: []].insert(k)
            markDirty(k)
            changed = true
        } else if c.shown && c.score <= 0 {
            c.shown = false
            byChunk[Self.chunkOfCol(k)]?.remove(k)
            markDirty(k)
            changed = true
        } else if c.shown && med != c.h {
            let steady = c.hist.count >= 3 && c.hist.suffix(3).allSatisfy { $0 == med }
            if abs(Int(med) - Int(c.h)) >= 2 || steady {
                c.h = med
                markDirty(k)
                changed = true
            }
        }
        if !c.shown && c.score <= -4 { cols[k] = nil; return }
        cols[k] = c
    }

    /// 그 기둥의 칸 (칸 가장자리면 옆 칸도 — 옆면·외톨이 판단이 이웃에 따라 바뀜)
    private func markDirty(_ k: Int64) {
        let (u, v) = Self.uv(k)
        for du in -1...1 { for dv in -1...1 { dirty.insert(Vox.chunkKey(Vox.fdiv(u + du), Vox.fdiv(v + dv))) } }
    }

    /// 매 프레임: 바뀐 칸 다시 그리기 (한 번에 budget개)
    func tick(budget: Int = 6) {
        guard !dirty.isEmpty else { return }
        for c in Array(dirty.prefix(budget)) { rebuild(c) }
    }

    func restyle() {
        dirty.formUnion(byChunk.keys)
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
        for (k, c) in cols where c.shown && c.seen >= 3 { out[k] = c.h }
        return out
    }

    /// 높이가 minH(m) 넘는 보이는 기둥의 10cm 칸 (그림·벽 꾸밈 자리 고르기)
    func blockedCells(minH: Float) -> Set<Int64> {
        var out = Set<Int64>()
        for (k, c) in cols where c.shown && Float(c.h) * Vox.size >= minH {
            let (u, v) = Self.uv(k)
            out.insert(Vox.planeCell(u, v))
        }
        return out
    }

    // MARK: 그물 만들기
    /// 그려지는 높이 (외톨이 기둥은 0)
    private func shownH(_ u: Int, _ v: Int) -> Int {
        guard let c = cols[Vox.chunkKey(u, v)], c.shown else { return 0 }
        var n = 0
        for du in -1...1 { for dv in -1...1 where du != 0 || dv != 0 {
            if let o = cols[Vox.chunkKey(u + du, v + dv)], o.shown { n += 1; if n >= 2 { return Int(c.h) } }
        } }
        return 0
    }

    private func roomAt(_ u: Int, _ v: Int) -> Int {
        let ck = Vox.chunkKey(u, v)
        if let r = colRoom[ck] { return r }
        let p = L.flat(SIMD2<Float>((Float(u) + 0.5) * Vox.size, (Float(v) + 0.5) * Vox.size))
        var r = L.at(x: p.x, z: p.y).room
        if r == 0 { r = L.roomNear(x: p.x, z: p.y, radius: 0.3) }
        if r == 0 { r = fallbackRoom }
        colRoom[ck] = r
        return r
    }

    private func rebuild(_ c: Int64) {
        dirty.remove(c)
        let keys = byChunk[c] ?? []
        if keys.isEmpty { byChunk[c] = nil }
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
        let lw: Float = 0.012
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
                    if s.lo == 0 { lg.stroke(p[0], p[1], width: lw) }  // 바닥에 닿는 선
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
