import Foundation
import simd

/// 스캔하는 동안 본 공간 그물을 '줄지 않게' 모아 두는 곳 (세계 좌표).
///
/// 비전프로의 그물 덩어리(MeshAnchor)는 사람이 멀어지면 지워질 뿐 아니라, 남아 있는 덩어리도
/// 다시 보낼 때 멀리 있는 부분이 빠진(줄어든) 모양으로 옴 → 덩어리를 통째로 바꿔 끼우면 벽 일부가 사라짐.
/// 그래서 삼각형을 4cm 칸(복셀)마다 나눠 보관하고:
///  - 새로 온 삼각형은 그 칸에 넣음(더 정확한 최신 모양으로 바뀜)
///  - 예전 삼각형은 '바로 옆(8cm 안)에 새 삼각형이 왔을 때만' 지움 → 새 모양이 대신한 곳만 바뀌고,
///    새 데이터에 빠진 곳(멀어서 안 보낸 곳)은 그대로 남음. 한 번 본 곳은 끝까지 남음
/// (스캔 중 움직이는 사람·물건은 지나간 자국이 남을 수 있음 — 스캔은 가구를 그대로 둔 채로)
@MainActor
final class MeshStore {
    struct Tri {
        var a: SIMD3<Float>, b: SIMD3<Float>, c: SIMD3<Float>
        var cls: UInt8
        var owner: UUID
    }
    static let vox: Float = 0.04
    static let chunkShift: Int64 = 5                 // 덩어리 = 32칸 (1.28m) — 화면에 그릴 때 이 단위로 다시 만듦

    private(set) var tris: [Int64: [Tri]] = [:]          // 칸마다 그 칸에 중심이 있는 삼각형들
    private(set) var count = 0
    private var owned: [UUID: Set<Int64>] = [:]
    private var chunks: [Int64: Set<Int64>] = [:]
    private(set) var dirty: Set<Int64> = []
    private(set) var version = 0

    static func key(_ p: SIMD3<Float>) -> Int64 {
        let x = Int64((p.x / vox).rounded(.down)) + (1 << 20)
        let y = Int64((p.y / vox).rounded(.down)) + (1 << 20)
        let z = Int64((p.z / vox).rounded(.down)) + (1 << 20)
        return (x << 42) | (y << 21) | z
    }
    static func chunk(_ k: Int64) -> Int64 {
        let x = (k >> 42) & 0x1FFFFF, y = (k >> 21) & 0x1FFFFF, z = k & 0x1FFFFF
        return ((x >> chunkShift) << 42) | ((y >> chunkShift) << 21) | (z >> chunkShift)
    }

    /// 그물 덩어리 하나의 새 모양을 받아 넣음
    func ingest(_ m: MeshCopy) {
        let wv = m.v.map { simd_make_float3(m.m * SIMD4<Float>($0, 1)) }
        var fresh: [Int64: [Tri]] = [:]
        var i = 0, fi = 0
        while i + 2 < m.f.count {
            defer { i += 3; fi += 1 }
            let a = Int(m.f[i]), b = Int(m.f[i + 1]), c = Int(m.f[i + 2])
            guard a < wv.count, b < wv.count, c < wv.count else { continue }
            let t = Tri(a: wv[a], b: wv[b], c: wv[c], cls: fi < m.c.count ? m.c[fi] : 0, owner: m.id)
            fresh[Self.key((t.a + t.b + t.c) / 3), default: []].append(t)
        }
        guard !fresh.isEmpty else { return }
        // 예전 것 중 새 삼각형이 바로 옆에 온 것만 지움 (새 모양이 대신함)
        let old = owned[m.id] ?? []
        var keep = Set<Int64>()
        for k in old {
            guard let t = tris[k]?.first, t.owner == m.id else { continue }
            if fresh[k] != nil { continue }
            var replaced = false
            outer: for dx in -1...1 {
                for dy in -1...1 {
                    for dz in -1...1 where !(dx == 0 && dy == 0 && dz == 0) {
                        let n = k + (Int64(dx) << 42) + (Int64(dy) << 21) + Int64(dz)
                        if fresh[n] != nil { replaced = true; break outer }
                    }
                }
            }
            if replaced { remove(k) } else { keep.insert(k) }
        }
        for (k, ts) in fresh {
            if let prev = tris[k] {
                if let o = prev.first?.owner, o != m.id { owned[o]?.remove(k) }
                count -= prev.count
            }
            tris[k] = ts
            count += ts.count
            let ch = Self.chunk(k)
            chunks[ch, default: []].insert(k)
            dirty.insert(ch)
            keep.insert(k)
        }
        owned[m.id] = keep
        version += 1
    }

    private func remove(_ k: Int64) {
        if let prev = tris.removeValue(forKey: k) { count -= prev.count }
        let ch = Self.chunk(k)
        chunks[ch]?.remove(k)
        dirty.insert(ch)
    }

    /// 다시 그릴 덩어리들을 꺼냄 (최대 n개)
    func takeDirty(_ n: Int) -> [Int64] {
        let list = Array(dirty.prefix(n))
        for c in list { dirty.remove(c) }
        return list
    }

    func trisIn(_ chunk: Int64) -> [Tri] { (chunks[chunk] ?? []).flatMap { tris[$0] ?? [] } }

    /// 모은 것 전체를 그물 하나로 (방 나누기·지도 계산용)
    func snapshot() -> MeshCopy {
        var v: [SIMD3<Float>] = [], f: [UInt32] = [], c: [UInt8] = []
        v.reserveCapacity(count * 3); f.reserveCapacity(count * 3); c.reserveCapacity(count)
        for list in tris.values {
          for t in list {
            let b = UInt32(v.count)
            v += [t.a, t.b, t.c]
            f += [b, b + 1, b + 2]
            c.append(t.cls)
          }
        }
        return MeshCopy(id: UUID(), m: matrix_identity_float4x4, v: v, f: f, c: c)
    }
}
