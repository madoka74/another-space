import Foundation
import RealityKit

/// 계곡 물소리: 방 옆을 지나는 개울(졸졸, 가까이) + 먼 폭포(쏴아, 멀리). 계곡 방에 있을 때만 천천히 커지고, 나가면 천천히 줄어듦
@MainActor
final class WaterSound {
    let root = Entity()                          // 저장 좌표
    private var loops: [String: (Entity, AudioPlaybackController)] = [:]
    private var on = false

    func set(_ active: Bool, stream: SIMD3<Float>?, fall: SIMD3<Float>?) {
        if active {
            if let p = stream { play("stream_loop", at: p, gain: -4) }
            if let p = fall { play("fall_loop", at: p, gain: 4) }
        }
        guard active != on else { return }
        on = active
        for (_, l) in loops { l.1.fade(to: active ? (l.0.name == "fall_loop" ? 4 : -4) : -60, duration: active ? 2.5 : 1.5) }
    }

    private func play(_ name: String, at p: SIMD3<Float>, gain: Double) {
        if let l = loops[name] { l.0.position = p; return }
        guard let u = Bundle.main.url(forResource: name, withExtension: "wav", subdirectory: "sfx") else { return }
        let cfg = AudioFileResource.Configuration(loadingStrategy: .preload, shouldLoop: true)
        guard let r = try? AudioFileResource.load(contentsOf: u, withName: nil, configuration: cfg) else { return }
        let e = Entity()
        e.name = name
        var sa = SpatialAudioComponent()
        sa.gain = 0
        sa.distanceAttenuation = .rolloff(factor: name == "fall_loop" ? 0.35 : 0.8)
        e.components.set(sa)
        e.position = p
        root.addChild(e)
        let c = e.playAudio(r)
        c.gain = -60
        c.fade(to: gain, duration: 2.5)
        loops[name] = (e, c)
    }

    func remove() {
        for (_, l) in loops { l.1.stop() }
        loops.removeAll()
        root.removeFromParent()
    }
}
