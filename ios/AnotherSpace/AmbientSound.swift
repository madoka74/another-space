import Foundation
import AVFoundation
import RealityKit

/// 엠비언트 서비스의 소리 한 개 (manifest.json 항목)
struct AmbientEntry: Sendable, Hashable {
    let file: String          // 예: beds/camp.afternoon.v1.r2.mp3
    let samples: Int          // 이어 붙일 길이(표본 수)
    let delay: Int            // 앞쪽 인코더 지연(표본 수)
    let dur: Double
    let place: String?
    let times: [String]?
    let weathers: [String]?
    let tag: String?
}

/// 엠비언트 소리 목록·파일. 엠비언트 Worker 에서 받아 기기에 보관(한 번 받으면 인터넷 없이도 재생)
actor AmbientLibrary {
    static let shared = AmbientLibrary()
    static let base = URL(string: "https://ambient.madoka74.workers.dev")!

    private var beds: [String: [AmbientEntry]] = [:]
    private var weather: [String: [AmbientEntry]] = [:]
    private var events: [String: [AmbientEntry]] = [:]
    private var audioBase = "/audio/"
    private var loaded = false
    private var inflight: [String: Task<URL?, Never>] = [:]

    private var dir: URL {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("ambient", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    /// 목록 받기 (실패하면 지난번에 받아 둔 목록)
    /// 앱에 담은 소리 폴더 (빌드할 때 엠비언트 저장소의 목록·소리를 그대로 담음)
    static var bundled: URL { Bundle.main.bundleURL.appendingPathComponent("Sounds", isDirectory: true) }

    /// 목록 읽기: 앱에 담은 목록 → (없으면) 서버 → 지난번에 받아 둔 목록
    func load() async -> Bool {
        if loaded { return true }
        let cached = dir.appendingPathComponent("manifest.json")
        var data: Data? = try? Data(contentsOf: Self.bundled.appendingPathComponent("manifest.json"))
        if data == nil {
            var req = URLRequest(url: Self.base.appendingPathComponent("manifest.json"))
            req.timeoutInterval = 8
            if let res = try? await URLSession.shared.data(for: req), (res.1 as? HTTPURLResponse)?.statusCode == 200 {
                data = res.0
                try? res.0.write(to: cached, options: .atomic)
            } else {
                data = try? Data(contentsOf: cached)
            }
        }
        guard let data, let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        audioBase = (j["audioBase"] as? String) ?? "/audio/"
        beds = Self.parse(j["beds"])
        weather = Self.parse(j["weather"])
        events = Self.parse(j["events"])
        loaded = !beds.isEmpty
        return loaded
    }

    private static func parse(_ v: Any?) -> [String: [AmbientEntry]] {
        guard let d = v as? [String: Any] else { return [:] }
        var out: [String: [AmbientEntry]] = [:]
        for (k, list) in d {
            guard let arr = list as? [[String: Any]] else { continue }
            out[k] = arr.compactMap { e in
                guard let f = e["file"] as? String else { return nil }
                return AmbientEntry(file: f, samples: (e["samples"] as? Int) ?? 0, delay: (e["delay"] as? Int) ?? 0,
                                    dur: (e["dur"] as? Double) ?? 0, place: e["place"] as? String,
                                    times: e["times"] as? [String], weathers: e["weathers"] as? [String], tag: e["tag"] as? String)
            }
        }
        return out
    }

    private static let timeFallback: [String: [String]] = [
        "dawn": ["night", "morning"], "morning": ["afternoon", "dawn"], "afternoon": ["morning", "dusk"],
        "dusk": ["afternoon", "night"], "night": ["dusk", "dawn"],
    ]
    private static let placeFallback: [String: [String]] = [
        "cafe": ["home"], "gallery": ["home"], "city": ["home"], "village": ["forest"], "forest": ["valley"],
        "valley": ["forest"], "sea": ["valley"], "camp": ["forest"],
    ]

    /// 장소·시간 바탕 소리 (없으면 엠비언트와 같은 순서로 비슷한 것)
    func bed(_ place: String, _ time: String) -> AmbientEntry? {
        for p in [place] + (Self.placeFallback[place] ?? []) {
            for t in [time] + (Self.timeFallback[time] ?? []) {
                if let e = beds["\(p).\(t)"]?.randomElement() { return e }
            }
        }
        return nil
    }

    /// 날씨 소리 층 (장소의 겉면: 실내·도시·자연·물가·텐트)
    func weatherLayer(_ w: String, place: String) -> AmbientEntry? {
        let ws: [String]
        switch w {
        case "heavysnow": ws = ["heavysnow", "snow"]
        case "storm": ws = ["storm", "rain"]
        case "drizzle": ws = ["drizzle", "rain"]
        default: ws = [w]
        }
        let s = Worlds.surface(place)
        let ss: [String]
        switch s {
        case "tent": ss = ["tent", "nature"]
        case "water": ss = ["water", "nature"]
        case "urban": ss = ["urban", "nature"]
        default: ss = [s]
        }
        for x in ws {
            for y in ss { if let e = weather["\(x).\(y)"]?.randomElement() { return e } }
            if let e = weather[x]?.randomElement() { return e }
        }
        return nil
    }

    /// 이 장소·날씨·시간에 날 수 있는 사건 소리들 (새·주전자·스쿠터…)
    func eventPool(_ place: String, _ w: String, _ time: String) -> [AmbientEntry] {
        events.values.compactMap { $0.randomElement() }.filter { e in
            let p = e.place ?? "*"
            guard p == place || p == "*" else { return false }
            if let t = e.times, !t.contains(time) { return false }
            if let ws = e.weathers, !ws.contains(w) { return false }
            if p == "*" && e.weathers == nil { return false }
            return true
        }
    }

    /// 이어 재생용 파일 (받아서 앞 지연을 잘라 끊김 없이 이어지는 WAV로)
    func loopFile(_ e: AmbientEntry) async -> URL? {
        let out = dir.appendingPathComponent(e.file.replacingOccurrences(of: "/", with: "_") + ".loop2.wav")      // loop2: 넘친 소리를 줄여 다시 만든 것 (예전 파일은 깨진 채 남아 있을 수 있어 이름을 바꿈)
        if FileManager.default.fileExists(atPath: out.path) { return out }
        guard let mp3 = await download(e.file) else { return nil }
        let tmp = dir.appendingPathComponent(UUID().uuidString + ".wav")
        do {
            try Self.makeLoop(src: mp3, dst: tmp, samples: e.samples, delay: e.delay)
            try? FileManager.default.removeItem(at: out)
            try FileManager.default.moveItem(at: tmp, to: out)
            return out
        } catch {
            try? FileManager.default.removeItem(at: tmp)
            return mp3                                  // 변환이 안 되면 원본 그대로 (이음새에 작은 틈이 있을 수 있음)
        }
    }

    /// 한 번 나는 소리 파일
    func oneShot(_ e: AmbientEntry) async -> URL? { await download(e.file) }

    /// 소리 파일: 앱에 담은 것 → 받아 둔 것 → (둘 다 없을 때만) 서버
    private func download(_ rel: String) async -> URL? {
        let inApp = Self.bundled.appendingPathComponent(rel)
        if FileManager.default.fileExists(atPath: inApp.path) { return inApp }
        let out = dir.appendingPathComponent(rel.replacingOccurrences(of: "/", with: "_"))
        if FileManager.default.fileExists(atPath: out.path) { return out }
        if let t = inflight[rel] { return await t.value }
        let base = Self.base, ab = audioBase
        let t = Task<URL?, Never> {
            guard let url = URL(string: ab + rel, relativeTo: base) else { return nil }
            var req = URLRequest(url: url)
            req.timeoutInterval = 30
            guard let res = try? await URLSession.shared.download(for: req),
                  (res.1 as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            try? FileManager.default.removeItem(at: out)
            do { try FileManager.default.moveItem(at: res.0, to: out) } catch { return nil }
            return out
        }
        inflight[rel] = t
        let v = await t.value
        inflight[rel] = nil
        return v
    }

    /// mp3 → 앞 지연을 잘라 정확히 samples 길이의 16비트 WAV (반복 재생 때 이음새가 맞게)
    private static func makeLoop(src: URL, dst: URL, samples: Int, delay: Int) throws {
        let f = try AVAudioFile(forReading: src)
        let fmt = f.processingFormat
        guard let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(f.length)) else { throw CocoaError(.fileReadCorruptFile) }
        try f.read(into: buf)
        let L = Int(buf.frameLength)
        var start = 0, n = L
        if samples > 1000 && samples <= L {
            n = samples
            // 디코더가 앞 지연을 이미 뺐으면 길이가 거의 samples, 안 뺐으면 delay만큼 더 김
            if delay > 0 && L - samples >= delay - 64 { start = min(delay, L - samples) }
        }
        guard n > 0, let out = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(n)),
              let sp = buf.floatChannelData, let dp = out.floatChannelData else { throw CocoaError(.fileReadCorruptFile) }
        out.frameLength = AVAudioFrameCount(n)
        for ch in 0..<Int(fmt.channelCount) { dp[ch].update(from: sp[ch].advanced(by: start), count: n) }
        // mp3를 풀면 큰 파도 소리 같은 곳은 ±1을 넘는 값이 나오는데, 그대로 16비트로 쓰면 그 부분이 잘려 '지지직' 깨져 들렸음 (바다)
        // → 가장 큰 값이 -1dB(0.89)를 넘으면 전체를 그만큼 줄여서 씀
        var peak: Float = 0
        for ch in 0..<Int(fmt.channelCount) {
            for i in 0..<n { peak = max(peak, abs(dp[ch][i])) }
        }
        if peak > 0.89 {
            let k = 0.89 / peak
            for ch in 0..<Int(fmt.channelCount) {
                for i in 0..<n { dp[ch][i] *= k }
            }
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: fmt.sampleRate, AVNumberOfChannelsKey: fmt.channelCount,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
        ]
        let w = try AVAudioFile(forWriting: dst, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try w.write(from: out)
    }

    /// 폭우 때 멀리서 울리는 천둥 (합성, 한 번 만들어 둠)
    func thunderFile() -> URL? {
        let url = dir.appendingPathComponent("thunder.wav")
        if FileManager.default.fileExists(atPath: url.path) { return url }
        let sr = 44100.0, dur = 5.0
        let n = Int(sr * dur)
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 1),
              let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: AVAudioFrameCount(n)),
              let ch = buf.floatChannelData?[0] else { return nil }
        buf.frameLength = AVAudioFrameCount(n)
        var b = 0.0, lp = 0.0
        for i in 0..<n {
            let t = Double(i) / sr
            b = (b + Double.random(in: -1...1) * 0.02) * 0.998        // 갈색 잡음 (낮게 웅웅)
            lp += 0.03 * (b - lp)
            let crack = t < 0.25 ? Double.random(in: -1...1) * exp(-t * 18) * 0.25 : 0
            let env = min(1, t / 0.08) * exp(-t * 0.75) * (1 + 0.35 * sin(t * 7.3) * sin(t * 2.1))
            ch[i] = Float((lp * 9 + crack) * env)
        }
        do {
            let w = try AVAudioFile(forWriting: url, settings: fmt.settings)
            try w.write(from: buf)
        } catch { return nil }
        return url
    }
}

/// 방마다의 소리를 실제로 내는 곳 (RealityKit 오디오). 바탕·날씨는 머리에 붙은 소리, 사건 소리는 그 자리에서 나는 공간 소리
@MainActor
final class AmbientPlayer {
    let root = Entity()                                   // 장면에 붙임
    private(set) var status: String?
    private var current: Int?
    private var loops: [Int: [AudioPlaybackController]] = [:]
    private var loopEntities: [Int: [Entity]] = [:]
    private var pools: [Int: [AmbientEntry]] = [:]
    private var res: [URL: AudioFileResource] = [:]
    private var gen = 0

    static let bedGain: Double = -1
    static let weatherGain: Double = -2

    init() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, options: [.mixWithOthers])
        try? s.setActive(true)
    }

    /// 방이 바뀜: 이전 방 소리는 천천히 줄이고 새 방 소리를 키움
    func enter(_ r: RoomRec?, force: Bool = false) {
        guard force || current != r?.id else { return }
        if let old = current { fadeOut(old) }
        current = r?.id
        guard let r else { return }
        gen += 1
        let myGen = gen
        Task {
            guard await AmbientLibrary.shared.load() else {
                status = "소리 목록을 찾지 못했어요"
                return
            }
            status = nil
            let lib = AmbientLibrary.shared
            let b = await lib.bed(r.place, r.time)
            let w = await lib.weatherLayer(r.weather, place: r.place)
            pools[r.id] = await lib.eventPool(r.place, r.weather, r.time)
            var urls: [(URL, Double)] = []
            if let b, let u = await lib.loopFile(b) { urls.append((u, Self.bedGain)) }
            if let w, let u = await lib.loopFile(w) { urls.append((u, Self.weatherGain)) }
            guard myGen == gen, current == r.id else { return }       // 그사이 다른 방으로 감
            if urls.isEmpty { status = "이 방의 소리를 받지 못했어요"; return }
            startLoops(r.id, urls)
        }
    }

    private func startLoops(_ id: Int, _ urls: [(URL, Double)]) {
        var ctls: [AudioPlaybackController] = []
        var ents: [Entity] = []
        // 바탕 + 날씨 두 겹이 함께 크면 합쳐서 넘쳐 깨질 수 있어, 두 겹일 땐 각각 3dB 줄임
        let both: Double = urls.count > 1 ? -3 : 0
        for (u, g0) in urls {
            let g = g0 + both
            guard let r = resource(u, loop: true) else { continue }
            let e = Entity()
            e.components.set(ChannelAudioComponent())
            root.addChild(e)
            let c = e.playAudio(r)
            c.gain = -60
            c.fade(to: g, duration: 2.5)
            ctls.append(c); ents.append(e)
        }
        loops[id] = ctls
        loopEntities[id] = ents
    }

    private func fadeOut(_ id: Int) {
        let ctls = loops.removeValue(forKey: id) ?? []
        let ents = loopEntities.removeValue(forKey: id) ?? []
        for c in ctls { c.fade(to: -60, duration: 2.5) }
        Task {
            try? await Task.sleep(for: .seconds(2.8))
            for c in ctls { c.stop() }
            for e in ents { e.removeFromParent() }
        }
    }

    private func resource(_ u: URL, loop: Bool) -> AudioFileResource? {
        if let r = res[u] { return r }
        // 머리에 붙은 소리인지(ChannelAudioComponent) 그 자리 소리인지(SpatialAudioComponent)는 재생하는 엔티티 쪽에서 정함
        let cfg = AudioFileResource.Configuration(loadingStrategy: loop ? .stream : .preload, shouldLoop: loop)
        let r = try? AudioFileResource.load(contentsOf: u, withName: nil, configuration: cfg)
        if let r { res[u] = r }
        return r
    }

    /// 사건 소리 종류에 맞는 자리: (방 둘레에서 바깥으로 거리, 높이, 크기, 거리 줄어듦 정도). 이름·태그의 낱말로 가림.
    /// 예전엔 무엇이든 방 바로 바깥 0.5~4m·사람 키 높이에서 났음 → 자동차·개 짖는 소리가 창 바로 옆에서 나 어색했음
    static func spot(_ e: AmbientEntry) -> (d: ClosedRange<Float>, h: ClosedRange<Float>, gain: ClosedRange<Double>, roll: Double) {
        let k = ((e.tag ?? "") + " " + e.file).lowercased()
        func has(_ w: [String]) -> Bool { w.contains { k.contains($0) } }
        if has(["kettle", "cup", "clink", "spoon", "clock", "page", "dish", "chair", "steam", "pour", "kitchen", "fridge", "drawer", "typing"]) {
            return (-1.5 ... -0.3, 0.8...1.4, -12 ... -8, 1)                    // 방 안 (조용히)
        }
        if has(["car", "scooter", "bus", "truck", "horn", "siren", "train", "motor", "traffic", "tram", "bike", "plane", "jet", "heli"]) {
            return (18...45, 0.5...2, -6 ... -2, 0.35)                           // 멀리 길
        }
        if has(["dog", "bark", "rooster", "cow", "sheep", "goat", "horse", "bell", "church", "chime"]) {
            return (15...40, 0.5...3, -7 ... -3, 0.4)                           // 마을 건너
        }
        if has(["bird", "crow", "gull", "owl", "cuckoo", "pecker", "song", "chirp", "tweet", "cicada", "insect", "cricket", "frog"]) {
            return (5...16, 3...9, -9 ... -4, 0.6)                              // 나무 위·풀숲
        }
        if has(["wave", "water", "splash", "drip", "creak", "wind", "leaves", "branch"]) {
            return (3...10, 0.3...3, -9 ... -4, 0.7)
        }
        return (4...12, 1...4, -9 ... -4, 0.6)
    }

    /// 지금 방의 사건 소리 하나 (그 종류에 맞는 거리·높이·방향에서). center·extent: 방 가운데(parent 기준)·반 크기
    func playEvent(in parent: Entity, center: SIMD3<Float>, extent: Float, floorY: Float) {
        guard let id = current, let e = pools[id]?.randomElement() else { return }
        let sp = Self.spot(e)
        let a = Float.random(in: 0...(2 * .pi))
        let d = max(0.3, extent + Float.random(in: sp.d))
        let position = SIMD3<Float>(center.x + cos(a) * d, floorY + Float.random(in: sp.h), center.z + sin(a) * d)
        Task {
            guard let u = await AmbientLibrary.shared.oneShot(e), current == id, let r = resource(u, loop: false) else { return }
            let ent = Entity()
            var sa = SpatialAudioComponent()
            sa.gain = Double.random(in: sp.gain)
            sa.distanceAttenuation = .rolloff(factor: sp.roll)
            ent.components.set(sa)
            ent.position = position
            parent.addChild(ent)
            ent.playAudio(r)
            try? await Task.sleep(for: .seconds(max(3, e.dur + 1)))
            ent.removeFromParent()
        }
    }

    func thunder(in parent: Entity, at position: SIMD3<Float>) {
        Task {
            guard let u = await AmbientLibrary.shared.thunderFile(), let r = resource(u, loop: false) else { return }
            let ent = Entity()
            var sa = SpatialAudioComponent()
            sa.gain = Double.random(in: -6 ... 0)
            ent.components.set(sa)
            ent.position = position
            parent.addChild(ent)
            ent.playAudio(r)
            try? await Task.sleep(for: .seconds(6))
            ent.removeFromParent()
        }
    }

    func stopAll() {
        for (_, cs) in loops { for c in cs { c.stop() } }
        loops.removeAll()
        for (_, es) in loopEntities { for e in es { e.removeFromParent() } }
        loopEntities.removeAll()
        current = nil
    }
}
