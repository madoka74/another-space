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
    var vox: [Int64: Float] = [:]         // 10cm 블록 → 그 안에 든 가구 면 넓이
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
            guard fi < keep.count, keep[fi] else { continue }
            let n = cr / len
            let cls: UInt8 = fi < m.c.count ? m.c[fi] : 0
            if !saved && cls == MeshClass.floor && n.y > 0.9 { floors.append((a.y + b.y + c.y) / 3) }
            let ns = fit.dirToSaved(n)
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
            if cls == MeshClass.floor || (ns.y > 0.8 && hgt < 0.06) || hgt < -0.05 { continue }
            // 10cm 블록으로: 삼각형 위를 5cm 간격으로 찍어 그 점이 든 블록에 넓이를 나눠 담음
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
                    let key = Vox.key(Int((p.x / Vox.size).rounded(.down)), Int((p.z / Vox.size).rounded(.down)), Int((p.y / Vox.size).rounded(.down)))
                    out.vox[key, default: 0] += per
                }
            }
        }
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

/// 탐험하며 알아낸 블록을 공간 폴더에 저장 (다음 탐험에선 처음부터 가구가 있게). 다시 스캔하면 지움
enum VoxStore {
    static func url(_ id: String) -> URL { SpaceStore.folder(id).appendingPathComponent("vox.bin") }

    static func save(_ id: String, _ keys: Set<Int64>) {
        var arr = Array(keys)
        let data = arr.withUnsafeMutableBufferPointer { Data(buffer: $0) }
        try? data.write(to: url(id), options: .atomic)
    }

    static func load(_ id: String) -> Set<Int64>? {
        guard let data = try? Data(contentsOf: url(id)), data.count >= 8, data.count % 8 == 0 else { return nil }
        var out = Set<Int64>()
        data.withUnsafeBytes { raw in
            for i in 0..<(data.count / 8) { out.insert(raw.loadUnaligned(fromByteOffset: i * 8, as: Int64.self)) }
        }
        return out
    }

    static func clear(_ id: String) { try? FileManager.default.removeItem(at: url(id)) }
}

/// 블록 세계: 블록을 1m 칸마다 그물 하나로 (같은 방향·같은 재질로 맞닿은 면은 큰 사각형 하나로 합침)
@MainActor
final class VoxelWorld {
    let root = Entity()                                 // 저장 좌표 (공간 뿌리 아래)
    private let L: Layout
    private(set) var known: Set<Int64> = []             // 보이는 블록
    private var byChunk: [Int64: Set<Int64>] = [:]
    private var support: [Int64: Int] = [:]             // 지금 그물 몇 덩어리가 이 블록을 보고 있는지
    private var anchorKeys: [UUID: Set<Int64>] = [:]
    private var anchorCells: [UUID: [Int64: Float]] = [:]
    private var cellLive: [Int64: Float] = [:]          // 1m 칸별 지금 그물 넓이
    private var cellSaved: [Int64: Float] = [:]         // 1m 칸별 스캔 그물 넓이
    private var missing: [Int64: Float] = [:]           // 블록이 그물에서 사라진 때
    private var dirty: Set<Int64> = []
    private var ents: [Int64: ModelEntity] = [:]
    private var lineEnts: [Int64: ModelEntity] = [:]
    private var colRoom: [Int64: Int] = [:]
    private var pruneT: Float = 0
    private(set) var changed = false                    // 마지막 저장 뒤 바뀜
    /// (방, 그늘 0~2) → 재질
    var material: (Int, Int) -> RealityKit.Material = { _, _ in UnlitMaterial(color: .gray) }
    /// 방 → 해 방향 (저장 좌표)
    var sun: (Int) -> SIMD3<Float> = { _ in SIMD3<Float>(0, 1, 0) }
    /// 방 → 무늬 한 장 길이(m)
    var tile: (Int) -> Float = { _ in 1 }
    /// 방 → 선 그림 모드인지 (블록 테두리를 검은 선으로)
    var lines: (Int) -> Bool = { _ in false }
    var fallbackRoom = 1

    init(_ L: Layout) { self.L = L }

    var isEmpty: Bool { known.isEmpty }

    // MARK: 블록 넣고 빼기
    func seed(_ keys: Set<Int64>, cells: [Int64: Float]) {
        cellSaved = cells
        for k in keys where !known.contains(k) { insert(k) }
    }

    private func insert(_ k: Int64) {
        known.insert(k)
        byChunk[Vox.chunk(k), default: []].insert(k)
        markDirty(k)
    }

    private func erase(_ k: Int64) {
        known.remove(k)
        byChunk[Vox.chunk(k)]?.remove(k)
        markDirty(k)
    }

    /// 그 블록의 칸 (칸 가장자리면 옆 칸도 — 맞닿은 면을 다시 정해야 함)
    private func markDirty(_ k: Int64) {
        let (u, v, _) = Vox.unpack(k)
        let cu = Vox.fdiv(u), cv = Vox.fdiv(v)
        dirty.insert(Vox.chunkKey(cu, cv))
        let mu = u - cu * 10, mv = v - cv * 10
        if mu == 0 { dirty.insert(Vox.chunkKey(cu - 1, cv)) }
        if mu == 9 { dirty.insert(Vox.chunkKey(cu + 1, cv)) }
        if mv == 0 { dirty.insert(Vox.chunkKey(cu, cv - 1)) }
        if mv == 9 { dirty.insert(Vox.chunkKey(cu, cv + 1)) }
    }

    /// 그 1m 칸을 지금 잘 보고 있는지 (스캔 때 그물의 60% 넘게 지금 그물이 채움)
    private func observed(_ c: Int64) -> Bool {
        let live = cellLive[c] ?? 0
        return live >= max(0.1, (cellSaved[c] ?? 0) * 0.6)
    }

    /// 그물 한 덩어리를 새로 읽음: 새 블록은 바로 보이고, 잘 보고 있는 칸에서 아무 그물에도 없는 블록은 사라질 후보
    func update(_ id: UUID, vox: [Int64: Float], cells: [Int64: Float], now: Float) {
        var keys = Set<Int64>()
        for (k, a) in vox where a >= Skin.voxMin { keys.insert(k) }
        let old = anchorKeys[id] ?? []
        for k in keys.subtracting(old) { support[k, default: 0] += 1 }
        for k in old.subtracting(keys) { drop(k, now) }
        anchorKeys[id] = keys.isEmpty ? nil : keys
        let oc = anchorCells[id] ?? [:]
        for c in Set(oc.keys).union(cells.keys) {
            let v = (cellLive[c] ?? 0) - (oc[c] ?? 0) + (cells[c] ?? 0)
            cellLive[c] = v > 1e-4 ? v : nil
        }
        anchorCells[id] = cells.isEmpty ? nil : cells
        for k in keys {
            missing[k] = nil
            if !known.contains(k) { insert(k); changed = true }
        }
        for c in cells.keys where observed(c) {
            for k in byChunk[c] ?? [] where (support[k] ?? 0) == 0 && missing[k] == nil { missing[k] = now }
        }
    }

    private func drop(_ k: Int64, _ now: Float) {
        let n = (support[k] ?? 0) - 1
        if n <= 0 {
            support[k] = nil
            if known.contains(k) && missing[k] == nil { missing[k] = now }
        } else {
            support[k] = n
        }
    }

    /// 비전프로가 그물 덩어리를 치움 (멀어져서) — 지운다는 뜻이 아니므로 블록은 남음
    func remove(_ id: UUID, now: Float) {
        for k in anchorKeys.removeValue(forKey: id) ?? [] {
            let n = (support[k] ?? 0) - 1
            support[k] = n > 0 ? n : nil
        }
        if let oc = anchorCells.removeValue(forKey: id) {
            for (c, a) in oc {
                let v = (cellLive[c] ?? 0) - a
                cellLive[c] = v > 1e-4 ? v : nil
            }
        }
    }

    /// 매 프레임: 사라질 후보 정리(0.25초마다) + 바뀐 칸 다시 그리기(한 번에 budget개)
    func tick(now: Float, budget: Int = 8) {
        if now - pruneT > 0.25 {
            pruneT = now
            var gone: [Int64] = []
            for (k, t0) in missing where now - t0 > 3 { gone.append(k) }
            for k in gone {
                missing[k] = nil
                guard (support[k] ?? 0) == 0, known.contains(k), observed(Vox.chunk(k)) else { continue }
                erase(k)
                changed = true
            }
        }
        guard !dirty.isEmpty else { return }
        for c in Array(dirty.prefix(budget)) { rebuild(c) }
    }

    /// 테마가 바뀜 → 모든 칸을 새 재질로
    func restyle() {
        dirty.formUnion(byChunk.keys)
        dirty.formUnion(ents.keys)
    }

    /// 처음 한 번에 모두 그림 (보이기 전에)
    func rebuildAll() async {
        var n = 0
        while let c = dirty.first {
            rebuild(c)
            n += 1
            if n % 24 == 0 { await Task.yield() }
        }
    }

    func markSaved() { changed = false }

    /// 그림 높이(1.0~2.2m)에 블록이 있는 10cm 칸 — 전시관 그림 자리 고르기
    func blockedCells() -> Set<Int64> {
        var out = Set<Int64>()
        for k in known {
            let (u, v, y) = Vox.unpack(k)
            if y >= 10 && y <= 21 { out.insert(Vox.planeCell(u, v)) }
        }
        return out
    }

    // MARK: 그물 만들기
    private func roomAt(_ u: Int, _ v: Int) -> Int {
        let ck = Vox.chunkKey(u, v)          // 블록 기둥 키로 재사용
        if let r = colRoom[ck] { return r }
        let p = L.flat(SIMD2<Float>((Float(u) + 0.5) * Vox.size, (Float(v) + 0.5) * Vox.size))
        var r = L.at(x: p.x, z: p.y).room
        if r == 0 { r = L.roomNear(x: p.x, z: p.y, radius: 0.3) }
        if r == 0 { r = fallbackRoom }
        colRoom[ck] = r
        return r
    }

    private static let dirs: [(Int, Int, Int)] = [(1, 0, 0), (-1, 0, 0), (0, 1, 0), (0, -1, 0), (0, 0, 1), (0, 0, -1)]

    private func neighborCount(_ k: Int64) -> Int {
        let (u, v, y) = Vox.unpack(k)
        var n = 0
        for du in -1...1 { for dv in -1...1 { for dy in -1...1 where du != 0 || dv != 0 || dy != 0 {
            if known.contains(Vox.key(u + du, v + dv, y + dy)) { n += 1; if n >= 2 { return n } }
        } } }
        return n
    }

    /// 면 하나의 꼭짓점 (블록 단위 좌표: x=u, y=높이, z=v)
    private static func corner(_ d: Int, _ layer: Int, _ a: Int, _ b: Int) -> SIMD3<Float> {
        switch d {
        case 0: return SIMD3<Float>(Float(layer + 1), Float(b), Float(a))
        case 1: return SIMD3<Float>(Float(layer), Float(b), Float(a))
        case 2: return SIMD3<Float>(Float(a), Float(layer + 1), Float(b))
        case 3: return SIMD3<Float>(Float(a), Float(layer), Float(b))
        case 4: return SIMD3<Float>(Float(a), Float(b), Float(layer + 1))
        default: return SIMD3<Float>(Float(a), Float(b), Float(layer))
        }
    }

    private func rebuild(_ c: Int64) {
        dirty.remove(c)
        let keys = byChunk[c] ?? []
        // 외톨이 블록(둘레 26칸에 블록이 하나뿐인 것)은 그리지 않음 — 허공에 뜬 점
        var show: [Int64] = []
        for k in keys where neighborCount(k) >= 2 || Vox.unpack(k).2 <= 1 { show.append(k) }
        if show.isEmpty {
            ents.removeValue(forKey: c)?.removeFromParent()
            lineEnts.removeValue(forKey: c)?.removeFromParent()
            if keys.isEmpty { byChunk[c] = nil }
            return
        }
        // 면 모으기: (방향, 층, 재질) → 그 층의 2D 칸들
        struct G: Hashable { let d: Int; let layer: Int; let mat: Int }
        var groups: [G: Set<SIMD2<Int32>>] = [:]
        let ex3 = SIMD3<Float>(L.ex.x, 0, L.ex.y), ez3 = SIMD3<Float>(L.ez.x, 0, L.ez.y)
        let normals: [SIMD3<Float>] = [ex3, -ex3, SIMD3<Float>(0, 1, 0), SIMD3<Float>(0, -1, 0), ez3, -ez3]
        var lineRooms = Set<Int>()
        for k in show {
            let (u, v, y) = Vox.unpack(k)
            let room = roomAt(u, v)
            if lines(room) { lineRooms.insert(room) }
            for (d, o) in Self.dirs.enumerated() where !known.contains(Vox.key(u + o.0, v + o.2, y + o.1)) {
                let l = simd_dot(normals[d], sun(room))
                let shade = l > 0.35 ? 0 : (l > -0.15 ? 1 : 2)
                let layer: Int, a: Int, b: Int
                switch d {
                case 0, 1: layer = u; a = v; b = y
                case 2, 3: layer = y; a = u; b = v
                default: layer = v; a = u; b = y
                }
                groups[G(d: d, layer: layer, mat: room * 4 + shade), default: []].insert(SIMD2<Int32>(Int32(a), Int32(b)))
            }
        }
        // 같은 층·같은 재질 칸들을 큰 사각형으로 합침 (그리는 면 수가 줄고 선 그림도 깔끔)
        var geos: [Int: Geo] = [:]
        let floorY = L.floorY
        func world(_ p: SIMD3<Float>) -> SIMD3<Float> {
            let f = L.flat(SIMD2<Float>(p.x * Vox.size, p.z * Vox.size))
            return SIMD3<Float>(f.x, floorY + p.y * Vox.size, f.y)
        }
        for (g, cells) in groups {
            var left = cells
            let sorted = cells.sorted { $0.y != $1.y ? $0.y < $1.y : $0.x < $1.x }
            let room = g.mat / 4
            let t = max(0.2, tile(room))
            for s in sorted where left.contains(s) {
                var a1 = s.x
                while left.contains(SIMD2<Int32>(a1 + 1, s.y)) { a1 += 1 }
                var b1 = s.y
                rows: while true {
                    for a in s.x...a1 where !left.contains(SIMD2<Int32>(a, b1 + 1)) { break rows }
                    b1 += 1
                }
                for b in s.y...b1 { for a in s.x...a1 { left.remove(SIMD2<Int32>(a, b)) } }
                let c0 = Self.corner(g.d, g.layer, Int(s.x), Int(s.y)), c1 = Self.corner(g.d, g.layer, Int(a1) + 1, Int(s.y))
                let c2 = Self.corner(g.d, g.layer, Int(a1) + 1, Int(b1) + 1), c3 = Self.corner(g.d, g.layer, Int(s.x), Int(b1) + 1)
                let pts = [c0, c1, c2, c3].map(world)
                let uvs: [SIMD2<Float>] = [c0, c1, c2, c3].map { c in
                    switch g.d {
                    case 0, 1: return SIMD2<Float>(c.z, -c.y) * (Vox.size / t)
                    case 2, 3: return SIMD2<Float>(c.x, c.z) * (Vox.size / t)
                    default: return SIMD2<Float>(c.x, -c.y) * (Vox.size / t)
                    }
                }
                geos[g.mat, default: Geo()].quad(pts[0], pts[1], pts[2], pts[3], uvs[0], uvs[1], uvs[2], uvs[3])
            }
        }
        var descs: [MeshDescriptor] = []
        var ms: [RealityKit.Material] = []
        for (mk, geo) in geos where !geo.isEmpty {
            var md = MeshDescriptor(name: "v\(mk)")
            md.positions = MeshBuffers.Positions(geo.pos)
            md.textureCoordinates = MeshBuffers.TextureCoordinates(geo.uv)
            md.primitives = .triangles(geo.idx)
            md.materials = .allFaces(UInt32(ms.count))
            descs.append(md)
            ms.append(material(mk / 4, mk % 4))
        }
        let e: ModelEntity
        if let old = ents[c] { e = old } else { e = ModelEntity(); root.addChild(e); ents[c] = e }
        if !descs.isEmpty, let mesh = try? MeshResource.generate(from: descs) {
            e.model = ModelComponent(mesh: mesh, materials: ms)
        } else {
            e.model = nil
        }
        // 선 그림 모드: 블록 덩어리의 모서리(꺾이는 곳)만 검은 선으로
        if !lineRooms.isEmpty, let lg = outline(show.filter { lineRooms.contains(roomAt(Vox.unpack($0).0, Vox.unpack($0).1)) }, world) {
            let le: ModelEntity
            if let old = lineEnts[c] { le = old } else { le = ModelEntity(); root.addChild(le); lineEnts[c] = le }
            le.model = ModelComponent(mesh: lg, materials: [Ink.line])
        } else {
            lineEnts.removeValue(forKey: c)?.removeFromParent()
        }
    }

    /// 블록 덩어리 모서리 선: 모서리를 둘러싼 네 칸 중 블록이 1·3칸이거나 대각선 2칸이면 꺾이는 곳(선), 나란한 2칸이면 평평한 면(선 없음).
    /// 한 줄로 이어지는 모서리는 긴 선 하나로 합침
    private func outline(_ list: [Int64], _ world: (SIMD3<Float>) -> SIMD3<Float>) -> MeshResource? {
        // 모서리 = (축, 시작 꼭짓점) — 축 0: u 방향, 1: 높이 방향, 2: v 방향
        var edges: [Int: Set<SIMD3<Int32>>] = [0: [], 1: [], 2: []]
        func has(_ u: Int, _ v: Int, _ y: Int) -> Bool { known.contains(Vox.key(u, v, y)) }
        for k in list {
            let (u, v, y) = Vox.unpack(k)
            // 이 블록의 모서리 12개
            for ax in 0..<3 {
                for i in 0..<2 { for j in 0..<2 {
                    var s = SIMD3<Int32>(Int32(u), Int32(y), Int32(v))      // x=u, y=높이, z=v (꼭짓점 좌표)
                    switch ax {
                    case 0: s.y += Int32(i); s.z += Int32(j)
                    case 1: s.x += Int32(i); s.z += Int32(j)
                    default: s.x += Int32(i); s.y += Int32(j)
                    }
                    edges[ax]?.insert(s)
                }}
            }
        }
        var g = Geo()
        let w: Float = 0.011
        for ax in 0..<3 {
            var keep = Set<SIMD3<Int32>>()
            for s in edges[ax] ?? [] {
                // 모서리 둘레 네 칸
                let x = Int(s.x), y = Int(s.y), z = Int(s.z)
                var occ: [Bool]
                switch ax {
                case 0: occ = [has(x, z - 1, y - 1), has(x, z - 1, y), has(x, z, y), has(x, z, y - 1)]
                case 1: occ = [has(x - 1, z - 1, y), has(x, z - 1, y), has(x, z, y), has(x - 1, z, y)]
                default: occ = [has(x - 1, z, y - 1), has(x, z, y - 1), has(x, z, y), has(x - 1, z, y)]
                }
                let n = occ.filter { $0 }.count
                let crease = n == 1 || n == 3 || (n == 2 && occ[0] == occ[2])
                if crease { keep.insert(s) }
            }
            // 한 줄로 이어 붙이기
            let step: SIMD3<Int32> = ax == 0 ? SIMD3<Int32>(1, 0, 0) : (ax == 1 ? SIMD3<Int32>(0, 1, 0) : SIMD3<Int32>(0, 0, 1))
            for s in keep where !keep.contains(s &- step) {
                var e = s
                while keep.contains(e &+ step) { e = e &+ step }
                // 블록 한 칸짜리 짧은 모서리(비스듬한 면의 계단)는 그리지 않음 — 선이 지저분해지지 않게, 곧은 큰 윤곽만
                let run = Int(e.x - s.x) + Int(e.y - s.y) + Int(e.z - s.z) + 1
                if run < 2 { continue }
                let a = world(SIMD3<Float>(Float(s.x), Float(s.y), Float(s.z)))
                let b = world(SIMD3<Float>(Float(e.x + step.x), Float(e.y + step.y), Float(e.z + step.z)))
                g.stroke(a, b, width: w)
            }
        }
        return g.mesh("outline")
    }
}
