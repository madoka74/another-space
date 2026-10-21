import SwiftUI
import RealityKit

/// 전시관에 거는 그림 한 점 (어디서 왔는지 + 해설을 받을 때 쓸 정보)
struct ArtPick: Sendable {
    let url: URL            // 그림 파일
    let id: String          // 포켓 갤러리 작품 id (앱에 담긴 명화도 같은 목록에서 고른 것이라 id가 같음)
    let title: String
    let artist: String
    let thumb: String?      // 해설을 만들 때 서버가 볼 그림 주소
    let pocket: Bool        // 포켓 갤러리 보관함 그림
}

/// 앱에 담긴 명화 목록 (빌드할 때 tools/fetch_art.py 가 art/index.json 에 파일 이름 → 작품 정보를 적어 둠)
enum ArtIndex {
    struct Item: Decodable { let file: String; let id: String; let a: String?; let t: String?; let img: String? }

    static let byFile: [String: Item] = {
        guard let u = Bundle.main.url(forResource: "index", withExtension: "json", subdirectory: "art"),
              let d = try? Data(contentsOf: u),
              let list = try? JSONDecoder().decode([Item].self, from: d) else { return [:] }
        return Dictionary(list.map { ($0.file, $0) }, uniquingKeysWith: { a, _ in a })
    }()

    static func pick(_ name: String, _ url: URL) -> ArtPick {
        let it = byFile[name]
        return ArtPick(url: url, id: it?.id ?? "as-" + name, title: it?.t ?? "", artist: it?.a ?? "", thumb: it?.img, pocket: false)
    }
}

/// 도슨트 해설 — 포켓 갤러리와 같은 형식 (작품 이야기 · 이렇게 보세요 · 작가 이야기)
struct DocentDoc: Codable, Sendable {
    var titleKo: String?
    var story: [String]?
    var look: [String]?
    var artist: [String]?
    var ok: Bool { !(story ?? []).isEmpty }
}

/// 지금 펼친 해설 (탐험 화면이 씀)
struct DocentState: Equatable {
    let entity: String      // 누른 그림 버튼 이름 (art-<방>-<자리>)
    let pick: ArtPick

    static func == (a: DocentState, b: DocentState) -> Bool { a.entity == b.entity }
}

/// 해설 가져오기·저장.
/// 1) 이 앱에 저장해 둔 것 → 2) 포켓 갤러리가 같이 쓰는 폴더(앱 그룹)에 써 둔 것 → 3) 포켓 갤러리 서버(/api/docent, 서버에 있으면 바로, 없으면 새로 만듦)
/// 받은 해설은 이 앱(Application Support/docent/)에 저장 → 다음부터는 다시 받지 않음
@MainActor @Observable
final class Docent {
    static let shared = Docent()
    nonisolated static let api = URL(string: "https://pocket-gallery.madoka74.workers.dev/api/docent")!

    enum Status: Equatable { case ready, loading, failed }

    private(set) var status: [String: Status] = [:]
    @ObservationIgnored private var docs: [String: DocentDoc] = [:]
    @ObservationIgnored private var checked: Set<String> = []          // 파일을 찾아봤지만 없던 그림 (매번 다시 읽지 않게)
    @ObservationIgnored private var queue: [ArtPick] = []
    @ObservationIgnored private var running = false

    nonisolated private static var dir: URL {
        let d = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("docent", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    nonisolated static func file(_ id: String) -> URL { dir.appendingPathComponent(PGLibrary.safe(id) + ".json") }
    nonisolated private static func shared(_ id: String) -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: PGLibrary.group)?
            .appendingPathComponent("pocket-gallery/docent/\(PGLibrary.safe(id)).json")
    }

    func doc(_ id: String) -> DocentDoc? {
        if let d = docs[id] { return d }
        if checked.contains(id) { return nil }
        for u in [Self.file(id), Self.shared(id)].compactMap({ $0 }) {
            if let data = try? Data(contentsOf: u), let d = try? JSONDecoder().decode(DocentDoc.self, from: data), d.ok {
                docs[id] = d
                return d
            }
        }
        checked.insert(id)
        return nil
    }

    /// 그림 버튼에 쓸 상태: 해설 있음(i) / 가져오는 중(?) / 없음(표시 안 함)
    func state(_ id: String) -> Status? {
        if doc(id) != nil { return .ready }
        return status[id]
    }

    /// 걸린 그림 중 해설이 없는 것을 하나씩 가져옴 (서버 하루 한도·인터넷 문제로 실패하면 그 그림은 표시 안 함)
    func prefetch(_ picks: [ArtPick]) {
        for p in picks where doc(p.id) == nil && status[p.id] != .loading && status[p.id] != .failed {
            status[p.id] = .loading
            queue.append(p)
        }
        run()
    }

    /// 실패했던 그림을 다시 (설명 창에서 '다시 시도')
    func retry(_ p: ArtPick) {
        status[p.id] = nil
        prefetch([p])
    }

    private func run() {
        guard !running, !queue.isEmpty else { return }
        running = true
        let p = queue.removeFirst()
        Task {
            let d = await Self.fetch(p)
            if let d {
                docs[p.id] = d
                status[p.id] = .ready
                let id = p.id
                Task.detached(priority: .utility) {
                    if let data = try? JSONEncoder().encode(d) { try? data.write(to: Docent.file(id), options: .atomic) }
                }
            } else {
                status[p.id] = .failed
            }
            running = false
            try? await Task.sleep(for: .milliseconds(800))
            run()
        }
    }

    nonisolated private static func fetch(_ p: ArtPick) async -> DocentDoc? {
        guard !p.title.isEmpty || !p.artist.isEmpty else { return nil }
        var req = URLRequest(url: api, timeoutInterval: 60)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        var body: [String: String] = ["id": p.id, "t": p.title, "a": p.artist]
        if let th = p.thumb { body["th"] = th }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, r) = try? await URLSession.shared.data(for: req),
              (r as? HTTPURLResponse)?.statusCode == 200,
              let d = try? JSONDecoder().decode(DocentDoc.self, from: data), d.ok else { return nil }
        return d
    }
}

/// 그림 옆에 뜨는 해설 창
struct DocentCard: View {
    let s: ExploreSession

    var body: some View {
        Group {
            if let st = s.docent {
                content(st.pick)
            } else {
                Color.clear.frame(width: 1, height: 1)
            }
        }
    }

    @ViewBuilder
    private func content(_ p: ArtPick) -> some View {
        let dc = Docent.shared
        let d = dc.doc(p.id)
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("도슨트 해설").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(d?.titleKo ?? p.title).font(.title2.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                    if !p.artist.isEmpty { Text(p.artist).font(.headline).foregroundStyle(.secondary) }
                }
                Spacer(minLength: 8)
                Button {
                    s.closeDocent()
                } label: {
                    Image(systemName: "xmark").font(.title3).frame(width: 36, height: 36)
                }
                .buttonBorderShape(.circle)
            }
            if let d {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        section("작품 이야기")
                        ForEach(Array((d.story ?? []).enumerated()), id: \.offset) { _, t in para(t) }
                        if let l = d.look, !l.isEmpty {
                            section("이렇게 보세요")
                            ForEach(Array(l.enumerated()), id: \.offset) { _, t in
                                HStack(alignment: .firstTextBaseline, spacing: 8) { Text("•"); para(t) }
                            }
                        }
                        if let a = d.artist, !a.isEmpty {
                            section("작가 이야기")
                            ForEach(Array(a.enumerated()), id: \.offset) { _, t in para(t) }
                        }
                        Text("작품 정보와 그림을 바탕으로 AI가 쓴 해설이에요. 세부 사실은 미술관 자료와 다를 수 있어요.")
                            .font(.caption).foregroundStyle(.secondary).padding(.top, 6)
                    }
                    .padding(.trailing, 6)
                }
            } else if dc.state(p.id) == .failed {
                VStack(spacing: 12) {
                    Text("해설을 불러오지 못했어요.").font(.headline)
                    Button("다시 시도") { dc.retry(p) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView("해설을 준비하고 있어요…").frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onAppear { dc.prefetch([p]) }
            }
        }
        .padding(24)
        .frame(width: 520, height: 640)
        .glassBackgroundEffect()
    }

    private func section(_ t: String) -> some View {
        Text(t).font(.title3.weight(.semibold)).padding(.top, 6)
    }

    private func para(_ t: String) -> some View {
        Text(t).font(.body).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
    }
}

/// 선 그림·전시관 공통 재질
@MainActor
enum Ink {
    /// 선 그림의 검은 선
    static let line: UnlitMaterial = UnlitMaterial(color: UIColor(white: 0.07, alpha: 1))
    /// 선 그림의 흰 면 (해 쪽·옆·그늘)
    static func paper(_ shade: Int) -> UnlitMaterial {
        UnlitMaterial(color: UIColor(white: [1.0, 0.93, 0.86][min(2, max(0, shade))], alpha: 1))
    }
}
