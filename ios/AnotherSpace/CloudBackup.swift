import Foundation

/// 공간을 iCloud(키-값 저장소)에 같이 저장해 두고, 이 기기에 없으면 되살림 → 앱을 지웠다 다시 깔아도 방 구성·세계가 남음.
/// 스캔 격자와 방 구성만 담음(압축해서 공간 하나에 보통 수십 KB). 스캔 그물(mesh.bin)은 커서 담지 않음 — 가구는 탐험 중 실제 그물로 입혀짐.
/// 위치 기억(월드 앵커)은 기기가 지우므로, 되살린 공간은 탐험을 시작할 때 벽 모양으로 다시 맞춤(Align)
enum CloudBackup {
    private static var kv: NSUbiquitousKeyValueStore { .default }
    private static let prefix = "space."
    private static var watching = false

    private struct Pack: Codable {
        let rec: SpaceRec
        let kind: Data
        let room: Data
        let win: Data
    }

    /// 앱이 켜질 때 한 번: iCloud 값을 받아 오고, 바뀌면(다른 곳에서 들어오면) 되살림
    @MainActor static func start() {
        guard !watching else { return }
        watching = true
        NotificationCenter.default.addObserver(forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: kv, queue: .main) { _ in
            Task { @MainActor in
                if restore() > 0 { AppModel.shared.reload() }
            }
        }
        kv.synchronize()
        if restore() > 0 { AppModel.shared.reload() }
        // 아직 iCloud에 없는 공간(이 기능 전에 만든 공간)은 지금 올림
        for r in SpaceStore.list() where kv.object(forKey: prefix + r.id) == nil {
            if let s = SpaceStore.load(r.id) { push(s) }
        }
    }

    static func push(_ s: SpaceData) {
        let p = Pack(rec: s.rec, kind: Data(s.kind), room: Data(s.room), win: Data(s.win))
        guard let json = try? JSONEncoder().encode(p),
              let z = try? (json as NSData).compressed(using: .lzfse) as Data,
              z.count < 900_000 else { return }
        kv.set(z, forKey: prefix + s.rec.id)
    }

    static func remove(_ id: String) {
        kv.removeObject(forKey: prefix + id)
        kv.synchronize()
    }

    /// 이 기기에 없는 공간을 iCloud에서 되살림 → 되살린 개수
    @discardableResult
    static func restore() -> Int {
        let local = Set((try? FileManager.default.contentsOfDirectory(atPath: SpaceStore.dir.path)) ?? [])
        var n = 0
        for (k, v) in kv.dictionaryRepresentation where k.hasPrefix(prefix) {
            let id = String(k.dropFirst(prefix.count))
            guard !local.contains(id), let z = v as? Data,
                  let json = try? (z as NSData).decompressed(using: .lzfse) as Data,
                  let p = try? JSONDecoder().decode(Pack.self, from: json),
                  p.kind.count == p.rec.w * p.rec.h, p.room.count == p.kind.count else { continue }
            let win = p.win.count == p.kind.count ? [UInt8](p.win) : [UInt8](repeating: 0, count: p.kind.count)
            let s = SpaceData(rec: p.rec, kind: [UInt8](p.kind), room: [UInt8](p.room), win: win)
            if (try? SpaceStore.save(s, backup: false)) != nil { n += 1 }
        }
        return n
    }
}
