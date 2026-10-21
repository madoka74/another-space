import Foundation

/// 포켓 갤러리 보관함 그림 (전시관에 먼저 걺).
/// 포켓 갤러리가 두 앱이 같이 쓰는 폴더(앱 그룹 group.com.blankishworks.shared)의 pocket-gallery/library.json 에
/// 보관함 목록을 써 두면 읽고, 그림은 같은 폴더 pocket-gallery/art/<id>.jpg 가 있으면 그대로, 없으면 주소에서 한 번 받아
/// 이 앱 안(Application Support/pgart/)에 저장해 둠
enum PGLibrary {
    static let group = "group.com.blankishworks.shared"

    struct Work: Decodable {
        let id: String
        let a: String?
        let t: String?
        let img: String?
        let th: String?
    }
    private struct File: Decodable { let works: [Work] }

    private static var shared: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?.appendingPathComponent("pocket-gallery", isDirectory: true)
    }

    private static var cacheDir: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("pgart", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    static func safe(_ id: String) -> String {
        String(id.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) || "-_".unicodeScalars.contains($0) ? Character($0) : "_" })
    }

    static func works() -> [Work] {
        guard let f = shared?.appendingPathComponent("library.json"),
              let d = try? Data(contentsOf: f),
              let o = try? JSONDecoder().decode(File.self, from: d) else { return [] }
        return o.works
    }

    /// 그림 파일 이름(안전한 id) → 작품 정보 (해설을 받을 때 씀)
    nonisolated(unsafe) private static var bySafe: [String: Work] = [:]

    /// 보관함 그림 파일 → 전시관에 걸 그림 정보
    static func pick(_ url: URL) -> ArtPick {
        let stem = url.deletingPathExtension().lastPathComponent
        let w = bySafe[stem]
        return ArtPick(url: url, id: w?.id ?? stem, title: w?.t ?? "", artist: w?.a ?? "", thumb: w?.th ?? w?.img, pocket: true)
    }

    /// 지금 바로 쓸 수 있는 그림 파일 (공유 폴더에 있거나 이미 받아 둔 것)
    static func ready(_ w: Work) -> URL? {
        let fm = FileManager.default
        if let s = shared?.appendingPathComponent("art/\(safe(w.id)).jpg"), fm.fileExists(atPath: s.path) { return s }
        let c = cacheDir.appendingPathComponent("\(safe(w.id)).jpg")
        return fm.fileExists(atPath: c.path) ? c : nil
    }

    /// 보관함 그림 파일들. 없는 그림은 받으며, 최대 wait초까지만 기다리고(그 뒤로도 계속 받아 다음 번에 씀) 준비된 것만 돌려줌
    static func prepare(wait: Double) async -> [URL] {
        let list = works()
        bySafe = Dictionary(list.map { (safe($0.id), $0) }, uniquingKeysWith: { a, _ in a })
        guard !list.isEmpty else { return [] }
        let missing = list.filter { ready($0) == nil }
        if !missing.isEmpty {
            let job = Task.detached(priority: .utility) {
                await withTaskGroup(of: Void.self) { g in
                    var running = 0
                    for w in missing {
                        if running >= 4 { _ = await g.next(); running -= 1 }
                        g.addTask { await download(w) }
                        running += 1
                    }
                }
            }
            if wait > 0 {
                let deadline = Date().addingTimeInterval(wait)
                while Date() < deadline && list.contains(where: { ready($0) == nil }) {
                    try? await Task.sleep(for: .milliseconds(250))
                }
            }
            _ = job
        }
        return list.compactMap { ready($0) }
    }

    private static func download(_ w: Work) async {
        guard let s = w.img ?? w.th, let u = URL(string: s) else { return }
        var req = URLRequest(url: u, timeoutInterval: 30)
        req.setValue("AnotherSpace/1.0 (Blankish works)", forHTTPHeaderField: "User-Agent")
        guard let (d, r) = try? await URLSession.shared.data(for: req),
              (r as? HTTPURLResponse)?.statusCode == 200, d.count > 5_000 else { return }
        try? d.write(to: cacheDir.appendingPathComponent("\(safe(w.id)).jpg"), options: .atomic)
    }
}
