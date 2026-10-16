import Foundation
import UIKit
import RealityKit
import simd

/// 방 하나의 다른 세계.
/// - 하늘 세계(WorldComponent): 하늘 구, 땅, 구름, 벽 너머로 솟은 숲·절벽·건물. 천장(포털)과 창문(포털)으로만 보임
/// - 방 안(실제 공간): 바닥, 실내 장소의 유리 지붕 틀, 비·눈·바람·반딧불
@MainActor
final class RoomWorld {
    let room: RoomRec
    let style: WorldStyle
    let world = Entity()            // 포털 너머 세계
    let local = Entity()            // 방 안 효과 (저장 좌표)
    private(set) var tint: SIMD3<Float>
    private var skyEntity: ModelEntity?
    private var skyMat: UnlitMaterial?
    private var flashMat: UnlitMaterial?
    private var clouds: [(Entity, SIMD3<Float>)] = []
    private var emitters: [Entity] = []
    private var flashLeft: Float = 0
    private(set) var center = SIMD3<Float>(0, 0, 0)         // 방 가운데 바닥 (저장 좌표)
    private(set) var halfSize = SIMD2<Float>(1, 1)           // 방 반 크기 (격자 방향, m)
    let angle: Float

    var outdoor: Bool { !style.skylight }

    typealias PRect = (SIMD2<Float>, SIMD2<Float>)

    init(_ d: SpaceData, _ r: RoomRec, layout: Layout) {
        room = r
        style = Worlds.style(r.place, time: r.time)
        angle = d.rec.angle
        // 밤·폭우라도 벽과 가구가 알아볼 수 있을 만큼은 밝게 (안전)
        tint = simd_max(Worlds.timeTint(r.time, indoor: Worlds.indoor(r.place)) * Worlds.weatherDim(r.weather), SIMD3<Float>(0.32, 0.33, 0.4))
        world.components.set(WorldComponent())
        build(d, layout)
    }

    // MARK: 만들기
    private func build(_ d: SpaceData, _ L: Layout) {
        let rec = d.rec
        let floorY = rec.floorY
        let ceilY = floorY + room.ceil
        let rects = L.rects(room.id)                 // 이 방이 차지하는 곳 (문·통로 포함, 평면 좌표 m)
        if let f = rects.first {
            var lo = f.0, hi = f.1
            for r in rects { lo = simd_min(lo, r.0); hi = simd_max(hi, r.1) }
            let c = L.flat((lo + hi) / 2)
            center = SIMD3<Float>(c.x, floorY, c.y)
            halfSize = (hi - lo) / 2
        }

        // 바닥 (바닥 위 6mm)
        if let m = Self.flatMesh(rects, L, y: floorY + 0.006, tile: style.floorTile) {
            local.addChild(ModelEntity(mesh: m, materials: [Tex.unlit(style.floor, tint: style.floorTint * tint)]))
        }
        // 천장 = 하늘 세계로 열린 창 (천장보다 2cm 아래)
        if let m = Self.flatMesh(rects, L, y: ceilY - 0.02, tile: 1) {
            let p = ModelEntity(mesh: m, materials: [PortalMaterial()])
            p.components.set(PortalComponent(target: world))
            local.addChild(p)
        }
        // 벽 (사각형 둘레에 반듯하게) + 창 (하늘 세계로 열린 창)
        addWalls(L.walls.filter { $0.room == room.id }, L, floorY: floorY, ceilY: ceilY)
        if style.skylight { addSkylightFrame(rects, L, y: ceilY - 0.06) }

        // 하늘 세계
        let skyTex = Worlds.skyName(time: room.time, weather: room.weather)
        if let sphere = Self.skySphere(radius: 300) {
            let wd = Worlds.weatherDim(room.weather)
            let base = Tex.unlit(skyTex, tint: [1, 1, 1] * max(0.75, wd), folder: "sky", tiled: false)
            let bright = Tex.unlit(skyTex, tint: [2.4, 2.4, 2.6], folder: "sky", tiled: false)
            let s = ModelEntity(mesh: sphere, materials: [base])
            s.position = center
            world.addChild(s)
            skyEntity = s; skyMat = base; flashMat = bright
        }
        let ground = ModelEntity(mesh: .generatePlane(width: 900, depth: 900), materials: [UnlitMaterial(color: Tex.color(style.ground * tint))])
        ground.position = center + SIMD3<Float>(0, -0.05, 0)
        world.addChild(ground)
        addClouds(ceilY: ceilY)
        addSkyline(rec: rec, floorY: floorY)

        // 날씨 효과
        let w = room.weather
        if ["drizzle", "rain", "storm", "snow", "heavysnow"].contains(w) {
            // 하늘 세계에도 (천장 너머로 내려오는 게 보이게)
            let e = Self.precip(w, size: SIMD3<Float>(halfSize.x * 2 + 4, 0.1, halfSize.y * 2 + 4), height: 8)
            e.position = SIMD3<Float>(center.x, ceilY + 8, center.z)
            e.orientation = simd_quatf(angle: -angle, axis: [0, 1, 0])
            world.addChild(e)
        }
        if outdoor {
            for r in rects.sorted(by: { ($0.1.x - $0.0.x) * ($0.1.y - $0.0.y) > ($1.1.x - $1.0.x) * ($1.1.y - $1.0.y) }).prefix(5) {
                let c = L.flat((r.0 + r.1) / 2)
                let sx = r.1.x - r.0.x, sz = r.1.y - r.0.y
                guard sx * sz > 0.4 else { continue }
                var list: [Entity] = []
                if ["drizzle", "rain", "storm", "snow", "heavysnow"].contains(w) {
                    let e = Self.precip(w, size: SIMD3<Float>(sx, 0.05, sz), height: room.ceil)
                    e.position = SIMD3<Float>(c.x, ceilY - 0.08, c.y)
                    list.append(e)
                }
                if w == "wind" {
                    let e = Self.windBits(room.place, size: SIMD3<Float>(sx, 1.6, sz))
                    e.position = SIMD3<Float>(c.x, floorY + 1.1, c.y)
                    list.append(e)
                }
                if room.time == "night" || room.time == "dusk",
                   ["camp", "forest", "valley", "village"].contains(room.place), ["clear", "cloudy", "wind"].contains(w) {
                    let e = Self.fireflies(size: SIMD3<Float>(sx, 1.2, sz))
                    e.position = SIMD3<Float>(c.x, floorY + 0.9, c.y)
                    list.append(e)
                }
                for e in list {
                    e.orientation = simd_quatf(angle: -angle, axis: [0, 1, 0])
                    local.addChild(e)
                    emitters.append(e)
                }
            }
        }
        setActive(false)
    }

    /// 지금 이 방에 있을 때만 입자를 뿜음 (다른 방은 쉼)
    func setActive(_ on: Bool) {
        for e in emitters {
            if var pe = e.components[ParticleEmitterComponent.self], pe.isEmitting != on {
                pe.isEmitting = on
                e.components.set(pe)
            }
        }
    }

    /// 매 프레임: 구름 흐름, 번개
    func tick(_ dt: Float, active: Bool) {
        guard active else { return }
        for (e, v) in clouds {
            e.position += v * dt
            let off = e.position - center
            if abs(off.x) > 180 { e.position.x = center.x - copysign(170, off.x) }
            if abs(off.z) > 180 { e.position.z = center.z - copysign(170, off.z) }
        }
        if flashLeft > 0 {
            flashLeft -= dt
            if flashLeft <= 0, let s = skyEntity, let m = skyMat { s.model?.materials = [m] }
        }
    }

    /// 번개: 하늘이 잠깐 밝아짐
    func flash() {
        guard let s = skyEntity, let f = flashMat else { return }
        s.model?.materials = [f]
        flashLeft = Float.random(in: 0.08...0.18)
    }

    // MARK: 하늘 세계 꾸미기
    private func addClouds(ceilY: Float) {
        let n = Worlds.cloudCount(room.weather)
        let dark: Float = room.weather == "storm" ? 0.45 : (["rain", "drizzle"].contains(room.weather) ? 0.7 : 1)
        let wind: Float = room.weather == "wind" || room.weather == "storm" ? 6 : 2
        let dir = simd_normalize(SIMD3<Float>(Float.random(in: -1...1), 0, Float.random(in: -1...1)) + SIMD3<Float>(0.01, 0, 0))
        for i in 0..<n {
            var m = UnlitMaterial(color: .white)
            if let t = Tex.get("cloud_\(i % 3)", folder: "sky") {
                m.color = .init(tint: Tex.color(SIMD3<Float>(repeating: 1) * tint * dark, alpha: 1), texture: .init(t))
            }
            m.blending = .transparent(opacity: .init(floatLiteral: room.weather == "clear" ? 0.65 : 0.9))
            let e = ModelEntity(mesh: .generatePlane(width: Float.random(in: 60...130), depth: Float.random(in: 40...80)), materials: [m])
            e.orientation = simd_quatf(angle: .pi, axis: [1, 0, 0]) * simd_quatf(angle: Float.random(in: 0...(2 * .pi)), axis: [0, 1, 0])
            e.position = center + SIMD3<Float>(Float.random(in: -160...160), ceilY - center.y + Float.random(in: 55...110), Float.random(in: -160...160))
            world.addChild(e)
            clouds.append((e, dir * wind * Float.random(in: 0.7...1.3)))
        }
    }

    /// 벽 너머로 솟은 것들 (천장·창으로 보임). 방 둘레를 바깥으로 둘러 배치
    private func addSkyline(rec: SpaceRec, floorY: Float) {
        var g = SeededRNG(seed: UInt64(room.id * 7919 + room.place.count * 31))
        let ex = rec.ex, ez = rec.ez
        let c2 = center.xz
        /// 방 둘레 바깥 d m 지점 (둘레를 t(0~1)로 한 바퀴)
        func around(_ t: Float, _ d: Float) -> SIMD3<Float> {
            let hx = halfSize.x + d, hz = halfSize.y + d
            let per = 4 * (hx + hz)
            var s = t * per
            var lu: Float = 0, lv: Float = 0
            if s < 2 * hx { lu = -hx + s; lv = -hz }
            else if s < 2 * hx + 2 * hz { s -= 2 * hx; lu = hx; lv = -hz + s }
            else if s < 4 * hx + 2 * hz { s -= 2 * hx + 2 * hz; lu = hx - s; lv = hz }
            else { s -= 4 * hx + 2 * hz; lu = -hx; lv = hz - s }
            let p = c2 + ex * lu + ez * lv
            return SIMD3<Float>(p.x, floorY, p.y)
        }
        let k = tint
        func mat(_ col: SIMD3<Float>) -> UnlitMaterial { UnlitMaterial(color: Tex.color(col * k)) }
        switch style.skyline {
        case .pines:
            let trunk = mat([0.22, 0.16, 0.11]), needles = mat([0.10, 0.20, 0.12]), needles2 = mat([0.13, 0.25, 0.14])
            for i in 0..<34 {
                let p = around(Float(i) / 34 + Float.random(in: 0...0.02, using: &g), Float.random(in: 0.8...7, using: &g))
                let h = Float.random(in: 9...17, using: &g)
                pine(at: p, h: h, trunk: trunk, needles: i % 2 == 0 ? needles : needles2)
            }
        case .trees:
            let trunk = mat([0.25, 0.18, 0.12]), leaf = mat([0.17, 0.30, 0.13]), leaf2 = mat([0.22, 0.36, 0.16])
            for i in 0..<26 {
                let p = around(Float(i) / 26 + Float.random(in: 0...0.03, using: &g), Float.random(in: 1...8, using: &g))
                let h = Float.random(in: 7...13, using: &g)
                let t = ModelEntity(mesh: .generateCylinder(height: h, radius: 0.3), materials: [trunk])
                t.position = p + SIMD3<Float>(0, h / 2, 0)
                world.addChild(t)
                let r = Float.random(in: 2.5...4.2, using: &g)
                let c = ModelEntity(mesh: .generateSphere(radius: r), materials: [i % 2 == 0 ? leaf : leaf2])
                c.position = p + SIMD3<Float>(0, h + r * 0.4, 0)
                c.scale = [1, 0.85, 1]
                world.addChild(c)
            }
        case .cliffs:
            let rock = Tex.unlit("cliff", tint: style.wallTint * k, tiled: false)
            for i in 0..<16 {
                let p = around(Float(i) / 16 + Float.random(in: 0...0.04, using: &g), Float.random(in: 1.5...9, using: &g))
                let h = Float.random(in: 16...38, using: &g)
                let b = ModelEntity(mesh: .generateBox(width: Float.random(in: 6...14, using: &g), height: h,
                                                         depth: Float.random(in: 4...9, using: &g)), materials: [rock])
                b.position = p + SIMD3<Float>(0, h / 2, 0)
                b.orientation = simd_quatf(angle: Float.random(in: 0...(2 * .pi), using: &g), axis: [0, 1, 0])
                world.addChild(b)
            }
        case .hills:
            let hill = mat([0.20, 0.30, 0.16]), far = mat([0.30, 0.38, 0.40])
            for i in 0..<9 {
                let a = Float(i) / 9 * 2 * .pi + Float.random(in: 0...0.3, using: &g)
                let r = Float.random(in: 60...110, using: &g)
                let d = Float.random(in: 150...230, using: &g)
                let s = ModelEntity(mesh: .generateSphere(radius: r), materials: [i % 3 == 0 ? far : hill])
                s.position = center + SIMD3<Float>(cos(a) * d, -r * 0.55, sin(a) * d)
                s.scale = [1, 0.55, 1]
                world.addChild(s)
            }
            let trunk = mat([0.25, 0.18, 0.12]), leaf = mat([0.20, 0.32, 0.14])
            for i in 0..<8 {
                let p = around(Float(i) / 8 + Float.random(in: 0...0.06, using: &g), Float.random(in: 2...9, using: &g))
                let h = Float.random(in: 6...9, using: &g)
                let t = ModelEntity(mesh: .generateCylinder(height: h, radius: 0.28), materials: [trunk])
                t.position = p + SIMD3<Float>(0, h / 2, 0)
                world.addChild(t)
                let c = ModelEntity(mesh: .generateSphere(radius: 3), materials: [leaf])
                c.position = p + SIMD3<Float>(0, h + 1.2, 0)
                world.addChild(c)
            }
        case .city, .lowCity:
            let night = room.time == "night" || room.time == "dawn"
            let face = Tex.unlit(night ? "facade_night" : "facade", tint: (night ? SIMD3<Float>(1, 1, 1) : k), tiled: false)
            let low = style.skyline == .lowCity
            for i in 0..<22 {
                let p = around(Float(i) / 22 + Float.random(in: 0...0.03, using: &g), Float.random(in: 3...22, using: &g))
                let h = low ? Float.random(in: 8...18, using: &g) : Float.random(in: 18...75, using: &g)
                let b = ModelEntity(mesh: .generateBox(width: Float.random(in: 8...18, using: &g), height: h,
                                                         depth: Float.random(in: 8...18, using: &g)), materials: [face])
                b.position = p + SIMD3<Float>(0, h / 2, 0)
                b.orientation = simd_quatf(angle: -angle + (i % 2 == 0 ? 0 : 0.1), axis: [0, 1, 0])
                world.addChild(b)
            }
        case .sea:
            // 탁 트인 바다: 멀리 섬 몇 개만
            let isle = mat([0.16, 0.22, 0.20])
            for i in 0..<3 {
                let a = Float.random(in: 0...(2 * .pi), using: &g) + Float(i)
                let r = Float.random(in: 20...45, using: &g)
                let s = ModelEntity(mesh: .generateSphere(radius: r), materials: [isle])
                s.position = center + SIMD3<Float>(cos(a) * 220, -r * 0.7, sin(a) * 220)
                s.scale = [1.6, 0.5, 1]
                world.addChild(s)
            }
        case .none:
            break
        }
    }

    private func pine(at p: SIMD3<Float>, h: Float, trunk: UnlitMaterial, needles: UnlitMaterial) {
        let t = ModelEntity(mesh: .generateCylinder(height: h * 0.45, radius: 0.28), materials: [trunk])
        t.position = p + SIMD3<Float>(0, h * 0.225, 0)
        world.addChild(t)
        for (k, (y, r, hh)) in [(0.3, 2.6, 0.45), (0.55, 2.0, 0.38), (0.78, 1.3, 0.3)].enumerated() {
            let c = ModelEntity(mesh: .generateCone(height: h * Float(hh), radius: Float(r) * (0.8 + Float(k) * 0.05)), materials: [needles])
            c.position = p + SIMD3<Float>(0, h * Float(y) + h * Float(hh) / 2, 0)
            world.addChild(c)
        }
    }

    /// 실내 장소: 유리 지붕 틀 (1m 간격 가는 들보)
    private func addSkylightFrame(_ rects: [PRect], _ L: Layout, y: Float) {
        let m = UnlitMaterial(color: Tex.color(SIMD3<Float>(0.18, 0.15, 0.12) * tint))
        let q = simd_quatf(angle: -angle, axis: [0, 1, 0])
        for r in rects {
            // u 방향 들보 (v가 1m마다)
            var v = (r.0.y).rounded(.down) + 1
            while v < r.1.y {
                let len = r.1.x - r.0.x
                if len > 0.3 {
                    let c = L.flat(SIMD2<Float>((r.0.x + r.1.x) / 2, v))
                    let b = ModelEntity(mesh: .generateBox(width: len, height: 0.07, depth: 0.05), materials: [m])
                    b.position = SIMD3<Float>(c.x, y, c.y)
                    b.orientation = q
                    local.addChild(b)
                }
                v += 1
            }
            // v 방향 들보 (u가 1m마다)
            var u = (r.0.x).rounded(.down) + 1
            while u < r.1.x {
                let len = r.1.y - r.0.y
                if len > 0.3 {
                    let c = L.flat(SIMD2<Float>(u, (r.0.y + r.1.y) / 2))
                    let b = ModelEntity(mesh: .generateBox(width: 0.05, height: 0.07, depth: len), materials: [m])
                    b.position = SIMD3<Float>(c.x, y, c.y)
                    b.orientation = q
                    local.addChild(b)
                }
                u += 1
            }
        }
    }

    /// 벽: 바닥부터 천장까지 반듯한 판. 해를 보는 쪽은 밝게, 반대쪽은 그늘지게.
    /// 창: 높이 0.85m~2.15m 부분을 하늘 세계로 열린 창으로 (위아래는 벽)
    private func addWalls(_ segs: [WallSeg], _ L: Layout, floorY: Float, ceilY: Float) {
        let sun = Worlds.sunDir(room.time)
        var parts: [[(SIMD3<Float>, SIMD3<Float>, Float, Float, Float, Float)]] = [[], [], []]   // 그늘 단계별: 아래 두 점·높이 범위·무늬 시작
        var windows: [(SIMD3<Float>, SIMD3<Float>, Float, Float)] = []
        for s in segs {
            let a2 = L.flat(s.a), b2 = L.flat(s.b)
            let a = SIMD3<Float>(a2.x, floorY, a2.y), b = SIMD3<Float>(b2.x, floorY, b2.y)
            let nw = L.flat(s.n) - L.flat(SIMD2<Float>(0, 0))               // 방 안쪽 방향 (저장 좌표)
            let l = simd_dot(SIMD3<Float>(nw.x, 0, nw.y), sun)
            let k = l > 0.25 ? 0 : (l > -0.25 ? 1 : 2)
            let along0 = abs(s.a.x - s.b.x) > abs(s.a.y - s.b.y) ? s.a.x : s.a.y
            let top = ceilY - floorY
            if s.window && top > 1.6 {
                let w0: Float = 0.85, w1 = min(2.15, top - 0.15)
                parts[k].append((a, b, 0, w0, along0, 0))
                parts[k].append((a, b, w1, top, along0, 0))
                windows.append((a, b, w0, w1))
            } else {
                parts[k].append((a, b, 0, top, along0, 0))
            }
        }
        let shade: [Float] = [1.0, 0.82, 0.66]
        for k in 0..<3 where !parts[k].isEmpty {
            var pos: [SIMD3<Float>] = [], uv: [SIMD2<Float>] = [], idx: [UInt32] = []
            let tile = style.wallTile
            for (a, b, y0, y1, along0, _) in parts[k] {
                let len = simd_distance(a, b)
                let base = UInt32(pos.count)
                pos += [a + SIMD3<Float>(0, y0, 0), b + SIMD3<Float>(0, y0, 0), b + SIMD3<Float>(0, y1, 0), a + SIMD3<Float>(0, y1, 0)]
                uv += [SIMD2<Float>(along0 / tile, -y0 / tile), SIMD2<Float>((along0 + len) / tile, -y0 / tile),
                       SIMD2<Float>((along0 + len) / tile, -y1 / tile), SIMD2<Float>(along0 / tile, -y1 / tile)]
                idx += [base, base + 1, base + 2, base, base + 2, base + 3, base, base + 2, base + 1, base, base + 3, base + 2]
            }
            var d = MeshDescriptor(name: "wall\(k)")
            d.positions = MeshBuffers.Positions(pos)
            d.textureCoordinates = MeshBuffers.TextureCoordinates(uv)
            d.primitives = .triangles(idx)
            if let m = try? MeshResource.generate(from: [d]) {
                local.addChild(ModelEntity(mesh: m, materials: [Tex.unlit(style.wall, tint: style.wallTint * tint * shade[k])]))
            }
        }
        if !windows.isEmpty {
            var pos: [SIMD3<Float>] = [], idx: [UInt32] = []
            for (a, b, y0, y1) in windows {
                let base = UInt32(pos.count)
                pos += [a + SIMD3<Float>(0, y0, 0), b + SIMD3<Float>(0, y0, 0), b + SIMD3<Float>(0, y1, 0), a + SIMD3<Float>(0, y1, 0)]
                idx += [base, base + 1, base + 2, base, base + 2, base + 3, base, base + 2, base + 1, base, base + 3, base + 2]
            }
            var d = MeshDescriptor(name: "window")
            d.positions = MeshBuffers.Positions(pos)
            d.primitives = .triangles(idx)
            if let m = try? MeshResource.generate(from: [d]) {
                let p = ModelEntity(mesh: m, materials: [PortalMaterial()])
                p.components.set(PortalComponent(target: world))
                local.addChild(p)
                // 창틀
                let frame = UnlitMaterial(color: Tex.color(SIMD3<Float>(0.22, 0.2, 0.18) * tint))
                for (a, b, y0, y1) in windows {
                    let len = simd_distance(a, b)
                    let mid = (a + b) / 2
                    let dir = simd_normalize(b - a)
                    let yaw = atan2(-dir.z, dir.x)
                    for y in [y0, y1] {
                        let bar = ModelEntity(mesh: .generateBox(width: len, height: 0.05, depth: 0.04), materials: [frame])
                        bar.position = mid + SIMD3<Float>(0, y, 0)
                        bar.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
                        local.addChild(bar)
                    }
                }
            }
        }
    }

    // MARK: 입자
    /// 비·눈 (위에서 아래로, 바닥 근처에서 사라짐)
    static func precip(_ w: String, size: SIMD3<Float>, height: Float) -> Entity {
        let snow = w == "snow" || w == "heavysnow"
        var pe = snow ? ParticleEmitterComponent.Presets.snow : ParticleEmitterComponent.Presets.rain
        pe.emitterShape = .box
        pe.emitterShapeSize = size
        pe.birthLocation = .volume
        pe.birthDirection = .world
        pe.emissionDirection = [0, -1, 0]
        let area = max(0.5, size.x * size.z)
        let speed: Float
        switch w {
        case "drizzle": speed = 3.2; pe.mainEmitter.birthRate = 60 * area
        case "rain": speed = 5; pe.mainEmitter.birthRate = 160 * area
        case "storm": speed = 7; pe.mainEmitter.birthRate = 320 * area
        case "heavysnow": speed = 0.55; pe.mainEmitter.birthRate = 45 * area; pe.mainEmitter.size = 0.022
        default: speed = 0.75; pe.mainEmitter.birthRate = 22 * area; pe.mainEmitter.size = 0.012
        }
        pe.speed = speed
        pe.speedVariation = speed * 0.15
        pe.mainEmitter.acceleration = [0, 0, 0]
        pe.mainEmitter.lifeSpan = Double(max(0.4, (height - 0.05) / speed))
        pe.mainEmitter.lifeSpanVariation = 0.05
        if snow { pe.mainEmitter.sizeMultiplierAtEndOfLifespan = 1 }
        let e = Entity()
        e.components.set(pe)
        return e
    }

    /// 바람: 나뭇잎(자연)이나 먼지(도시·바다)가 옆으로 날림
    static func windBits(_ place: String, size: SIMD3<Float>) -> Entity {
        var pe = ParticleEmitterComponent()
        pe.emitterShape = .box
        pe.emitterShapeSize = size
        pe.birthLocation = .volume
        pe.birthDirection = .world
        pe.emissionDirection = simd_normalize(SIMD3<Float>(1, 0.1, 0.35))
        pe.speed = 1.3
        pe.speedVariation = 0.5
        let nature = ["camp", "forest", "valley", "village"].contains(place)
        pe.mainEmitter.birthRate = nature ? 7 : 14
        pe.mainEmitter.lifeSpan = 3.5
        pe.mainEmitter.size = nature ? 0.022 : 0.006
        pe.mainEmitter.sizeVariation = nature ? 0.008 : 0.003
        pe.mainEmitter.acceleration = [0, -0.12, 0]
        pe.mainEmitter.sizeMultiplierAtEndOfLifespan = 1
        pe.mainEmitter.angularSpeed = nature ? 2.5 : 0
        pe.mainEmitter.angularSpeedVariation = nature ? 2 : 0
        pe.mainEmitter.color = .constant(.single(nature ? UIColor(red: 0.62, green: 0.48, blue: 0.22, alpha: 1)
                                                        : UIColor(red: 0.85, green: 0.82, blue: 0.75, alpha: 0.6)))
        pe.mainEmitter.opacityCurve = .gradualFadeInOut
        let e = Entity()
        e.components.set(pe)
        return e
    }

    /// 반딧불 (밤·해질녘의 자연)
    static func fireflies(size: SIMD3<Float>) -> Entity {
        var pe = ParticleEmitterComponent()
        pe.emitterShape = .box
        pe.emitterShapeSize = size
        pe.birthLocation = .volume
        pe.speed = 0.06
        pe.speedVariation = 0.05
        pe.mainEmitter.birthRate = max(2, size.x * size.z * 0.4)
        pe.mainEmitter.lifeSpan = 4
        pe.mainEmitter.size = 0.012
        pe.mainEmitter.sizeMultiplierAtEndOfLifespan = 1
        pe.mainEmitter.noiseStrength = 0.12
        pe.mainEmitter.noiseScale = 1
        pe.mainEmitter.noiseAnimationSpeed = 0.3
        pe.mainEmitter.color = .constant(.single(UIColor(red: 0.85, green: 1, blue: 0.45, alpha: 1)))
        pe.mainEmitter.blendMode = .additive
        pe.mainEmitter.opacityCurve = .gradualFadeInOut
        let e = Entity()
        e.components.set(pe)
        return e
    }

    // MARK: 그물 만들기
    /// 방 칸 직사각형들로 평평한 판 (위아래 양면, 무늬는 저장 좌표 기준으로 tile m마다 반복)
    static func flatMesh(_ rects: [PRect], _ L: Layout, y: Float, tile: Float) -> MeshResource? {
        guard !rects.isEmpty else { return nil }
        var pos: [SIMD3<Float>] = [], uv: [SIMD2<Float>] = [], idx: [UInt32] = []
        for r in rects {
            let corners = [L.flat(r.0), L.flat(SIMD2<Float>(r.1.x, r.0.y)), L.flat(r.1), L.flat(SIMD2<Float>(r.0.x, r.1.y))]
            let b = UInt32(pos.count)
            for c in corners {
                pos.append(SIMD3<Float>(c.x, y, c.y))
                uv.append(SIMD2<Float>(c.x / tile, c.y / tile))
            }
            idx += [b, b + 1, b + 2, b, b + 2, b + 3, b, b + 2, b + 1, b, b + 3, b + 2]
        }
        var d = MeshDescriptor(name: "flat")
        d.positions = MeshBuffers.Positions(pos)
        d.textureCoordinates = MeshBuffers.TextureCoordinates(uv)
        d.primitives = .triangles(idx)
        return try? MeshResource.generate(from: [d])
    }

    /// 안쪽에서 보는 하늘 구 (등장방형 그림, 양면)
    static func skySphere(radius: Float) -> MeshResource? {
        let seg = 48, rings = 24
        var pos: [SIMD3<Float>] = [], uv: [SIMD2<Float>] = [], idx: [UInt32] = []
        for r in 0...rings {
            let el = Float.pi / 2 - Float.pi * Float(r) / Float(rings)
            for s in 0...seg {
                let az = 2 * Float.pi * Float(s) / Float(seg)
                pos.append(radius * SIMD3<Float>(cos(el) * cos(az), sin(el), cos(el) * sin(az)))
                uv.append(SIMD2<Float>(Float(s) / Float(seg), 0.5 + el / Float.pi))
            }
        }
        for r in 0..<rings {
            for s in 0..<seg {
                let a = UInt32(r * (seg + 1) + s), b = a + UInt32(seg + 1)
                idx += [a, b, a + 1, a + 1, b, b + 1]          // 안쪽 면
                idx += [a, a + 1, b, a + 1, b + 1, b]          // 바깥 면 (방향이 뒤집혀도 보이게)
            }
        }
        var d = MeshDescriptor(name: "sky")
        d.positions = MeshBuffers.Positions(pos)
        d.textureCoordinates = MeshBuffers.TextureCoordinates(uv)
        d.primitives = .triangles(idx)
        return try? MeshResource.generate(from: [d])
    }
}
