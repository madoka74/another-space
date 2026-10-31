import Foundation
import UIKit
import RealityKit
import simd

/// 블랭키씨 (Blanky C Works 캐릭터) — 테마마다 숨어 있는 이스터에그.
/// 모습(사용자 피규어 사진 기준): 머리부터 몸통까지 목·어깨·허리 없이 하나로 이어진 세로로 긴 알약(캡슐) 몸 — 머리 쪽이 조금 좁고
/// 배·엉덩이 쪽이 조금 넓음, 아래 끝은 다리로 좁아지며 이어짐. 몸 옆에서 바로 뻗어 나온 가늘고 긴 팔(무릎 아래까지), 몸 아래에서 바로 이어진
/// 가는 다리와 앞으로 뻗은 발. 마디가 드러나지 않음. 매트한 딥 다크 차콜, 머리 쪽 정면에 점 눈 둘 + 사이 작은 일자.
/// 배 가운데 앞뒤로 뚫린 세로 타원 구멍, 그 안에 떠 있는 빛 구슬 0~여러 개.
/// (0.5.46 첫 모습은 목·어깨·허리가 따로 있는 로봇 같은 모양이라 사진과 전혀 달랐음 → 0.5.47에서 몸통을 한 덩어리로 다시 만듦)
/// 움직임은 천천히 흐느적 (골반·등·고개가 느리게 기울고, 팔뚝이 한 박자 늦게 따라옴).
/// - 바깥(하늘 세계): BlankyCrowd — 세계마다 2~3명, 실제 크기(멀면 작게). 집(어느 방이든) 밖 1.5m 넘게만 다님(기준서 1·5-0)
/// - 실내(방 안): BlankyIndoor — 지금 방 하나에 1명, 방 크기에 맞춘 키 (카페·도시·전시관)
/// 그늘은 빛 계산 없이 그물 uv 에 미리 구운 밝기(차콜 그라데이션 그림)로 — 세계·방 안·흑백 어디서나 같은 질감. 선 그림은 흰 몸 + 외곽선

// MARK: - 공통 계산
@MainActor
enum BK {
    static func rx(_ a: Float) -> simd_quatf { simd_quatf(angle: a, axis: [1, 0, 0]) }
    static func ry(_ a: Float) -> simd_quatf { simd_quatf(angle: a, axis: [0, 1, 0]) }
    static func rz(_ a: Float) -> simd_quatf { simd_quatf(angle: a, axis: [0, 0, 1]) }
    /// a - b 를 -π~π 로
    static func adiff(_ a: Float, _ b: Float) -> Float {
        var d = a - b
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        return d
    }
    /// 0→1→0 부드러운 올림 (x0~x1 오름, x1~x2 머묾, x2~x3 내림)
    static func bump(_ x: Float, _ x0: Float, _ x1: Float, _ x2: Float, _ x3: Float) -> Float {
        func ss(_ v: Float) -> Float { let c = min(1, max(0, v)); return c * c * (3 - 2 * c) }
        if x < x0 || x > x3 { return 0 }
        if x < x1 { return ss((x - x0) / max(1e-3, x1 - x0)) }
        if x <= x2 { return 1 }
        return 1 - ss((x - x2) / max(1e-3, x3 - x2))
    }
    /// 빛 구슬 개수 (비어 있음 0개도 — 공허함)
    static func orbCount<G: RandomNumberGenerator>(_ g: inout G) -> Int {
        let r = Float.random(in: 0...1, using: &g)
        return r < 0.12 ? 0 : (r < 0.42 ? 1 : (r < 0.75 ? 2 : 3))
    }
}

// MARK: - 그물
/// 블랭키씨 모양 (키 1 기준 — 엔티티 크기로 키를 맞춤). 몸 윤곽·구멍·팔다리 굵기는 사용자가 준 블랭키씨 정면 그림에서 줄마다 잰 값
/// (그림 키 3363픽셀 = 1, 가운데 x = 0). 머리~몸통은 한 덩어리 그물(모든 블랭키씨가 같이 씀), 팔다리는 매 화면 휘는 그물(BlankyLimb)
@MainActor
enum BlankyMesh {
    static let hipY: Float = 0.44                               // 엉덩이 마디 (다리 뿌리, 몸 아래 끝 0.40 위)
    static let legX: Float = 0.0455                             // 다리 가운데 (그림: 가랑이에서 두 다리가 거의 붙어 내려와 곧게)
    static let armRoot = SIMD2<Float>(0.046, 0.765)             // 팔 뿌리 (어깨 비탈 속 — 바닥에서)
    static let hollowY: Float = 0.199                           // 배 구멍 가운데 (등뼈 = 엉덩이 마디 기준, 바닥에서 0.639)
    // 정면 반폭 (팔 포함 바깥 윤곽, 바닥에서 높이 y): 머리 0.0645(곧은 기둥) → 0.83부터 어깨 비탈로 퍼져 0.6에서 0.127
    private static let outer: [(Float, Float)] = [(0.6, 0.127), (0.6075, 0.1252), (0.6164, 0.1234), (0.6253, 0.1213), (0.6343, 0.1192), (0.6432, 0.1172),
        (0.6521, 0.1148), (0.661, 0.1124), (0.6699, 0.1097), (0.6789, 0.107), (0.6878, 0.1041), (0.6967, 0.1011), (0.7056, 0.0978), (0.7145, 0.0946),
        (0.7235, 0.091), (0.7324, 0.0874), (0.7413, 0.0839), (0.7502, 0.0803), (0.7591, 0.0767), (0.7681, 0.074), (0.777, 0.0717), (0.7859, 0.0699),
        (0.7948, 0.0684), (0.8037, 0.0669), (0.8127, 0.066), (0.8216, 0.0651), (0.8305, 0.0645), (0.92, 0.0645), (0.9286, 0.0642), (0.9376, 0.0633),
        (0.9465, 0.0616), (0.9554, 0.0586), (0.9643, 0.0544), (0.9732, 0.0491), (0.9822, 0.0413), (0.9911, 0.0303), (1.0, 0)]
    // 팔 사이 몸통 반폭 (0.604 아래 — 그림에서 팔과 몸통이 갈라지는 틈 안쪽), 다리 사이로 둥글게 끝남
    private static let torso: [(Float, Float)] = [(0.40, 0), (0.405, 0.05), (0.42, 0.072), (0.45, 0.081), (0.5, 0.086), (0.604, 0.0853)]
    // 앞뒤 반두께 (그림에 없음 — 피규어 사진처럼 머리는 둥글고 몸은 조금 납작, 아래 끝은 다리 굵기로 좁아져 다리와 이어짐)
    private static let depth: [(Float, Float)] = [(0.40, 0), (0.405, 0.03), (0.42, 0.04), (0.45, 0.048), (0.5, 0.058), (0.55, 0.065), (0.68, 0.066), (0.8, 0.061), (0.92, 0.059)]
    private static let holeC = SIMD2<Float>(0, 0.639), holeA = SIMD2<Float>(0.0535, 0.104)       // 배 구멍 (그림에서 잼)
    // 팔: 뿌리에서 손목까지 길이 s 마다 몸 바깥쪽 기울기(라디안)와 반지름 — 그림처럼 어깨 비탈을 따라 벌어졌다 손 쪽에서 살짝 안으로
    static let armLen: Float = 0.357
    static let armS: [Float] = [0, 0.072, 0.176, 0.227, 0.277, 0.317, 0.357]
    static let armTh: [Float] = [0.42, 0.33, 0.285, 0.2, 0.09, 0.04, 0.005]
    static let armR: [Float] = [0.024, 0.023, 0.0198, 0.0164, 0.014, 0.0136, 0.0143]
    // 다리: 엉덩이 마디에서 발목까지, 허벅지는 굵게 몸에 묻히고 발목으로 가늘어졌다 발 쪽에서 조금 굵어짐
    static let legLen: Float = 0.405
    static let legS: [Float] = [0, 0.04, 0.06, 0.09, 0.111, 0.167, 0.223, 0.279, 0.334, 0.405]
    static let legR: [Float] = [0.042, 0.039, 0.0326, 0.0284, 0.0262, 0.0207, 0.0167, 0.015, 0.0153, 0.019]
    static let thigh: Float = 0.21, shin: Float = 0.23           // 앉기 계산용 (무릎이 휘는 곳 가운데까지 / 그 아래 발바닥까지)

    static func lerp(_ t: [(Float, Float)], _ y: Float) -> Float {
        guard let f = t.first, let l = t.last else { return 0 }
        if y <= f.0 { return f.1 }
        if y >= l.0 { return l.1 }
        var i = 0
        while i + 1 < t.count && t[i + 1].0 < y { i += 1 }
        let a = t[i], b = t[i + 1]
        return a.1 + (b.1 - a.1) * (y - a.0) / max(1e-6, b.0 - a.0)
    }
    static func lerp(_ xs: [Float], _ vs: [Float], _ x: Float) -> Float {
        if x <= xs[0] { return vs[0] }
        var i = 0
        while i + 2 < xs.count && xs[i + 1] < x { i += 1 }
        return vs[i] + (vs[i + 1] - vs[i]) * min(1, (x - xs[i]) / max(1e-6, xs[i + 1] - xs[i]))
    }
    static func ss(_ t: Float) -> Float { let c = min(1, max(0, t)); return c * c * (3 - 2 * c) }
    /// 몸 정면 반폭: 0.604 위는 바깥 윤곽에서 팔 굵기만큼 뺀 몸 (팔은 따로, 그 비탈에 반쯤 묻힘), 아래는 팔 사이 몸통
    static func bodyW(_ y: Float) -> Float {
        if y <= 0.40 || y >= 1.0 { return 0 }
        if y < 0.604 { return lerp(torso, y) }
        return lerp(outer, y) - 0.036 * ss((0.78 - y) / 0.16)
    }
    static func bodyD(_ y: Float) -> Float { y > 0.92 ? 0.059 * bodyW(y) / 0.0645 : lerp(depth, y) }
    /// 몸 앞면 깊이 (정면 x, y) — 단면은 모서리가 둥근 네모(초타원 3제곱)
    static func zf(_ x: Float, _ y: Float) -> Float {
        let w = bodyW(y)
        guard w > 1e-6 else { return 0 }
        return bodyD(y) * pow(max(0, 1 - pow(abs(x / w), 3)), 1 / 3)
    }

    struct Parts { let body: MeshResource, face: MeshResource }
    private static var cache: Parts?
    private static var tried = false
    static var parts: Parts? {
        if !tried { tried = true; cache = build() }
        return cache
    }

    static func shade(_ n: SIMD3<Float>) -> Float {
        let l = simd_dot(n, light)
        return 0.14 + 0.86 * pow(max(0, (l + 0.4) / 1.4), 1.25)
    }
    static let light = simd_normalize(SIMD3<Float>(0.35, 0.85, 0.45))

    /// 격자 점(줄 × 칸, 칸은 둘레로 이어짐)을 삼각형으로. 점마다 바깥 방향(inside 에서 멀어지는 쪽) 법선을 맞추고 빛 받는 정도를 uv.x 에 구움.
    /// 삼각형 감김은 법선 쪽이 앞면이 되게 하나씩 맞춤. nOut: 점마다 법선 (손·발처럼 매 화면 다시 돌려 그늘을 다시 낼 때)
    static func emit(_ g: inout Geo, _ rows: [[SIMD3<Float>]], wrapRows: Bool, inside: (Int, Int) -> SIMD3<Float>,
                     dim: (Int, Int) -> Float = { _, _ in 1 }, nOut: inout [SIMD3<Float>]) {
        let nr = rows.count
        guard nr > 1, let nc = rows.first?.count, nc > 2 else { return }
        let base = g.pos.count
        var nrm = [SIMD3<Float>](repeating: .zero, count: nr * nc)
        for i in 0..<nr {
            for j in 0..<nc {
                let p = rows[i][j]
                let du = rows[i][(j + 1) % nc] - rows[i][(j + nc - 1) % nc]
                let i0 = wrapRows ? (i + nr - 1) % nr : max(0, i - 1)
                let i1 = wrapRows ? (i + 1) % nr : min(nr - 1, i + 1)
                let dv = rows[i1][j] - rows[i0][j]
                let out = p - inside(i, j)
                var n = simd_cross(du, dv)
                if simd_length(n) < 1e-9 { n = out }
                n = simd_length(n) > 1e-9 ? simd_normalize(n) : SIMD3<Float>(0, 1, 0)
                if simd_dot(n, out) < 0 { n = -n }
                nrm[i * nc + j] = n
                g.pos.append(p)
                g.uv.append(SIMD2<Float>(min(0.98, max(0.02, shade(n) * dim(i, j))), 0.5))
            }
        }
        nOut += nrm
        let pairs = wrapRows ? nr : nr - 1
        for i in 0..<pairs {
            let i2 = (i + 1) % nr
            for j in 0..<nc {
                let j2 = (j + 1) % nc
                let a = i * nc + j, b = i * nc + j2, c = i2 * nc + j2, d = i2 * nc + j
                for (x, y, z) in [(a, b, c), (a, c, d)] {
                    let px = g.pos[base + x], py = g.pos[base + y], pz = g.pos[base + z]
                    let fn = simd_cross(py - px, pz - px)
                    if simd_length(fn) < 1e-12 { continue }
                    let vn = nrm[x] + nrm[y] + nrm[z]
                    let ux = UInt32(base + x), uy = UInt32(base + y), uz = UInt32(base + z)
                    if simd_dot(fn, vn) >= 0 { g.idx += [ux, uy, uz] } else { g.idx += [ux, uz, uy] }
                }
            }
        }
    }

    /// 타원체 (rot: 돌림)
    static func ellipsoid(_ g: inout Geo, c: SIMD3<Float>, r: SIMD3<Float>, lat: Int = 12, lon: Int = 20,
                          rot: simd_quatf = simd_quatf(angle: 0, axis: [0, 1, 0]), nOut: inout [SIMD3<Float>]) {
        var rows: [[SIMD3<Float>]] = []
        for i in 0...lat {
            let v = Float.pi / 2 - Float.pi * Float(i) / Float(lat)
            var row: [SIMD3<Float>] = []
            for j in 0..<lon {
                let u = 2 * Float.pi * Float(j) / Float(lon)
                row.append(c + rot.act(SIMD3<Float>(r.x * cos(v) * cos(u), r.y * sin(v), r.z * cos(v) * sin(u))))
            }
            rows.append(row)
        }
        emit(&g, rows, wrapRows: false, inside: { _, _ in c }, nOut: &nOut)
    }

    /// 아래(-y)로 뻗은 끝이 둥근 막대 (손 — 앞뒤로 납작 fz). prof: (y, 반지름, 옆 어긋남 x) 위에서 아래로
    static func tube(_ g: inout Geo, _ prof: [(Float, Float, Float)], sides: Int, fz: Float, nOut: inout [SIMD3<Float>]) {
        guard let top = prof.first, let bot = prof.last else { return }
        var ring: [(Float, Float, Float)] = []
        for k in 0..<3 {
            let a = Float.pi / 2 * (1 - Float(k) / 3)
            ring.append((top.0 + top.1 * sin(a) * fz, top.1 * cos(a), top.2))
        }
        ring += prof
        for k in 1...3 {
            let a = Float.pi / 2 * Float(k) / 3
            ring.append((bot.0 - bot.1 * sin(a) * 0.8, bot.1 * cos(a), bot.2))
        }
        var rows: [[SIMD3<Float>]] = []
        for (y, r, x0) in ring {
            rows.append((0..<sides).map { j in
                let u = 2 * Float.pi * Float(j) / Float(sides)
                return SIMD3<Float>(x0 + r * cos(u), y, r * fz * sin(u))
            })
        }
        emit(&g, rows, wrapRows: false, inside: { i, _ in SIMD3<Float>(ring[i].2, min(top.0, max(bot.0, ring[i].0)), 0) }, nOut: &nOut)
    }

    private static func build() -> Parts? {
        // 머리~몸통 한 덩어리 + 배 구멍: 정면 몸 윤곽 둘레를 고르게 112칸으로 나누고, 칸마다 구멍 가운데에서 윤곽 점으로 그은 줄 위에
        // 구멍 가장자리 → 윤곽을 잇는 앞면·뒷면(깊이 zf, 구멍 가까이는 둥근 비탈로 들어감)과 구멍 속 벽을 하나로 감싼 고리 그물
        let half = 4000
        var poly: [SIMD2<Float>] = []
        for k in 0..<half {
            let y = 0.40 + 0.6 * Float(k) / Float(half - 1)
            poly.append(SIMD2<Float>(bodyW(y), y))
        }
        for k in stride(from: half - 2, through: 1, by: -1) { poly.append(SIMD2<Float>(-poly[k].x, poly[k].y)) }
        var cum: [Float] = [0]
        for k in 0..<poly.count { cum.append(cum[k] + simd_distance(poly[k], poly[(k + 1) % poly.count])) }
        let nC = 112
        var O: [SIMD2<Float>] = [], Hp: [SIMD2<Float>] = [], Rd: [SIMD2<Float>] = [], sr: [Float] = []
        var seg = 0
        for k in 0..<nC {
            let d = cum[poly.count] * Float(k) / Float(nC)
            while seg + 1 < poly.count && cum[seg + 1] < d { seg += 1 }
            let a = poly[seg], b = poly[(seg + 1) % poly.count]
            let o = a + (b - a) * ((d - cum[seg]) / max(1e-9, cum[seg + 1] - cum[seg]))
            O.append(o)
            let v = o - holeC
            let an = atan2(v.y / holeA.y, v.x / holeA.x)
            let h = holeC + holeA * SIMD2<Float>(cos(an), sin(an))
            Hp.append(h)
            Rd.append(simd_normalize(h - holeC))
            let hb = holeC + (holeA + SIMD2<Float>(repeating: 0.02)) * SIMD2<Float>(cos(an), sin(an))     // 둥근 비탈 끝
            sr.append(min(0.6, simd_distance(hb, h) / max(1e-6, simd_distance(o, h))))
        }
        var sF: [Float] = []
        let n = 16
        for k in 0...n { let u = 1 - Float(k) / Float(n); sF.append(1 - (1 - u) * (1 - u)) }
        sF[n] = 0
        var rows: [[SIMD3<Float>]] = [], kind: [Int] = [], dims: [Float] = []       // kind 0 앞·뒷면, 1 구멍 속
        func sheet(_ s: Float, _ sign: Float) -> [SIMD3<Float>] {
            (0..<nC).map { j in
                let p = Hp[j] + (O[j] - Hp[j]) * s
                let dip = 0.62 + 0.38 * ss(s / max(1e-4, sr[j]))
                return SIMD3<Float>(p.x, p.y, sign * zf(p.x, p.y) * dip)
            }
        }
        for s in sF { rows.append(sheet(s, 1)); kind.append(s > 0.001 ? 0 : 2); dims.append(s > 0.02 ? 1 : 0.8) }
        for c: Float in [0.45, 0.15, -0.15, -0.45] {
            rows.append((0..<nC).map { j in SIMD3<Float>(Hp[j].x, Hp[j].y, c * 0.62 * zf(Hp[j].x, Hp[j].y)) })
            kind.append(1); dims.append(0.42)                                                   // 구멍 속은 어둡게 (깊이)
        }
        for s in sF.reversed().dropLast() { rows.append(sheet(s, -1)); kind.append(s > 0.001 ? 0 : 2); dims.append(s > 0.02 ? 1 : 0.8) }
        let off = SIMD3<Float>(0, -hipY, 0)                                                     // 등뼈(엉덩이 마디) 기준으로
        var body = Geo()
        var nn: [SIMD3<Float>] = []
        emit(&body, rows.map { $0.map { $0 + off } }, wrapRows: true,
             inside: { i, j in
                 let p = rows[i][j]
                 if kind[i] == 0 { return SIMD3<Float>(p.x, p.y, 0) + off }
                 return SIMD3<Float>(Hp[j].x + Rd[j].x * 0.03, Hp[j].y + Rd[j].y * 0.03, kind[i] == 1 ? p.z * 0.3 : 0) + off
             },
             dim: { i, _ in dims[i] }, nOut: &nn)
        // 얼굴: 머리 쪽 앞면에 점 눈 둘 + 두 눈 사이 작은 일자 (그림에서 잰 자리)
        var face = Geo()
        for sx: Float in [1, -1] {
            let x = sx * 0.0268, y: Float = 0.9097
            ellipsoid(&face, c: SIMD3<Float>(x, y, zf(x, y) - 0.002) + off, r: SIMD3<Float>(0.0055, 0.0055, 0.0035), lat: 6, lon: 10, nOut: &nn)
        }
        ellipsoid(&face, c: SIMD3<Float>(0, 0.9097, zf(0, 0.9097) - 0.0006) + off, r: SIMD3<Float>(0.0065, 0.0011, 0.0022), lat: 4, lon: 10, nOut: &nn)
        guard let b = body.mesh("bkBody"), let fc = face.mesh("bkFace") else { return nil }
        return Parts(body: b, face: fc)
    }

    /// 매트한 딥 다크 차콜 그라데이션 (그늘 → 빛 받는 쪽). 무채색이라 흑백에서도 그대로
    private static var rampTex: TextureResource?
    static func ramp() -> TextureResource? {
        if let r = rampTex { return r }
        let w = 64
        guard let ctx = CGContext(data: nil, width: w, height: 1, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data else { return nil }
        let px = data.bindMemory(to: UInt8.self, capacity: w * 4)
        for i in 0..<w {
            let s = Float(i) / Float(w - 1)
            let v = UInt8(min(255, max(0, (0.04 + 0.3 * s) * 255)))
            px[i * 4] = v; px[i * 4 + 1] = v; px[i * 4 + 2] = v; px[i * 4 + 3] = 255
        }
        guard let cg = ctx.makeImage() else { return nil }
        rampTex = try? TextureResource.generate(from: cg, options: .init(semantic: .color))
        return rampTex
    }

    static func bodyMat(_ look: LookMode, tint: SIMD3<Float>) -> RealityKit.Material {
        if look == .line { return Ink.paper(0) }
        let tc = Tex.with(look) { Tex.color(Worlds.safe(tint, min: 0.45)) }
        var m = UnlitMaterial(color: tc)
        if let t = ramp() {
            var p = MaterialParameters.Texture(t)
            p.sampler = Tex.clamp
            m.color = .init(tint: tc, texture: p)
        }
        return m
    }
}

// MARK: - 휘는 팔다리
/// 팔·다리 하나: 마디(꺾이는 점) 없이 뿌리에서 끝까지 휘는 굵기 있는 관 + 끝(손·발). 매 화면 곡선을 따라 점을 다시 놓음 (LowLevelMesh).
/// 굽힘(팔꿈치·무릎)은 한 점이 아니라 긴 구간(팔 0.12~0.33, 다리 0.14~0.28)에 고르게 나눠 둥글게 휨 — 캐릭터의 '관절이 도드라지지 않는 유연한 몸'
private struct BKVert {
    var p: SIMD3<Float>
    var uv: SIMD2<Float>
}

@MainActor
final class BlankyLimb {
    let entity: ModelEntity
    let arm: Bool
    let side: Float                 // 1 왼쪽(+x), -1 오른쪽
    private let mesh: LowLevelMesh
    private let grow: Float         // 선 그림 외곽선 껍데기: 바깥으로 부풀릴 두께 (0이면 몸)
    private static let M = 24, sides = 12
    private let endPos: [SIMD3<Float>], endNrm: [SIMD3<Float>]      // 손·발 (끝 자리 기준)
    private let tubeCount: Int
    private(set) var endP = SIMD3<Float>(0, 0, 0)                  // 끝(손바닥 가운데·발목) — 뿌리 기준
    private let cosT: [Float], sinT: [Float]

    init?(arm: Bool, side: Float, material: RealityKit.Material, grow: Float = 0) {
        self.arm = arm
        self.side = side
        self.grow = grow
        var g = Geo()
        var nn: [SIMD3<Float>] = []
        if arm {
            // 손: 손목에서 넓어졌다 손가락 끝으로 좁아지는 납작한 손바닥 + 안쪽 엄지 (그림에서 잰 폭)
            BlankyMesh.tube(&g, [(0, 0.0143, 0), (-0.035, 0.019, 0), (-0.05, 0.0205, 0), (-0.063, 0.017, 0), (-0.08, 0.014, 0), (-0.1, 0.011, 0), (-0.112, 0.007, 0)],
                            sides: 14, fz: 0.62, nOut: &nn)
            BlankyMesh.tube(&g, [(-0.028, 0.009, -side * 0.013), (-0.05, 0.0078, -side * 0.021), (-0.07, 0.006, -side * 0.025)], sides: 10, fz: 0.8, nOut: &nn)
        } else {
            // 발: 발목에서 둥글게 넓어지는 뒤꿈치 + 앞으로 길고 납작한 발, 발끝은 바깥·아래로 (그림처럼 물방울 모양)
            BlankyMesh.ellipsoid(&g, c: SIMD3<Float>(0, -0.012, 0.004), r: SIMD3<Float>(0.02, 0.022, 0.024), lat: 10, lon: 14, nOut: &nn)
            BlankyMesh.ellipsoid(&g, c: SIMD3<Float>(side * 0.014, -0.02, 0.03), r: SIMD3<Float>(0.021, 0.017, 0.052), lat: 10, lon: 16,
                                 rot: simd_quatf(angle: side * 0.5, axis: [0, 1, 0]) * simd_quatf(angle: -side * 0.25, axis: [0, 0, 1]), nOut: &nn)
        }
        endPos = g.pos
        endNrm = nn
        let sides = Self.sides
        cosT = (0..<sides).map { cos(2 * Float.pi * Float($0) / Float(sides)) }
        sinT = (0..<sides).map { sin(2 * Float.pi * Float($0) / Float(sides)) }
        let rings = 3 + (Self.M + 1) + 3
        let tc = rings * sides
        tubeCount = tc
        var idx: [UInt32] = []
        for i in 0..<(rings - 1) {
            for j in 0..<sides {
                let j2 = (j + 1) % sides
                let a = UInt32(i * sides + j), b = UInt32(i * sides + j2), c = UInt32((i + 1) * sides + j2), d = UInt32((i + 1) * sides + j)
                idx += [a, b, c, a, c, d]
            }
        }
        idx += g.idx.map { $0 + UInt32(tc) }
        let vCount = tc + g.pos.count
        let attrs = [LowLevelMesh.Attribute(semantic: .position, format: .float3, offset: MemoryLayout<BKVert>.offset(of: \BKVert.p) ?? 0),
                     LowLevelMesh.Attribute(semantic: .uv0, format: .float2, offset: MemoryLayout<BKVert>.offset(of: \BKVert.uv) ?? 16)]
        let desc = LowLevelMesh.Descriptor(vertexCapacity: vCount, vertexAttributes: attrs,
                                           vertexLayouts: [LowLevelMesh.Layout(bufferIndex: 0, bufferStride: MemoryLayout<BKVert>.stride)],
                                           indexCapacity: idx.count)
        guard let m = try? LowLevelMesh(descriptor: desc) else { return nil }
        mesh = m
        let ids = idx
        m.withUnsafeMutableIndices { raw in
            ids.withUnsafeBytes { src in raw.copyMemory(from: UnsafeRawBufferPointer(rebasing: src[0..<min(src.count, raw.count)])) }
        }
        // 그리기에서 빼지 않게 넉넉한 범위 (키 1 기준 — 팔다리가 어디로 휘어도 들어감)
        m.parts.replaceAll([LowLevelMesh.Part(indexCount: idx.count, topology: .triangle,
                                              bounds: BoundingBox(min: SIMD3<Float>(repeating: -0.8), max: SIMD3<Float>(repeating: 0.8)))])
        guard let res = try? MeshResource(from: m) else { return nil }
        entity = ModelEntity(mesh: res, materials: [material])
        update(f: 0, o: 0, bend: 0, twist: 0)
    }

    /// f: 뿌리에서 앞으로, o: 몸 바깥으로, bend: 팔꿈치(앞으로)·무릎(뒤로) 굽힘, twist: 굽는 면을 돌림 (팔)
    func update(f: Float, o: Float, bend: Float, twist: Float) {
        let M = Self.M, sides = Self.sides
        let L = arm ? BlankyMesh.armLen : BlankyMesh.legLen
        let qo = simd_quatf(angle: side * o, axis: [0, 0, 1]), qf = simd_quatf(angle: -f, axis: [1, 0, 0])
        let base = qo * qf * simd_quatf(angle: side * twist, axis: [0, 1, 0])
        var frames: [(SIMD3<Float>, simd_float3x3, Float)] = []
        frames.reserveCapacity(M + 1)
        var p = SIMD3<Float>(0, 0, 0)
        var prevDir = SIMD3<Float>(0, -1, 0)
        for i in 0...M {
            let s = L * Float(i) / Float(M)
            let q: simd_quatf
            let r: Float
            if arm {
                let th = BlankyMesh.lerp(BlankyMesh.armS, BlankyMesh.armTh, s)
                let b = -bend * BlankyMesh.ss((s - 0.12) / 0.21)
                q = base * simd_quatf(angle: side * th, axis: [0, 0, 1]) * simd_quatf(angle: b, axis: [1, 0, 0])
                r = BlankyMesh.lerp(BlankyMesh.armS, BlankyMesh.armR, s)
            } else {
                let b = bend * BlankyMesh.ss((s - 0.14) / 0.14)
                q = base * simd_quatf(angle: b, axis: [1, 0, 0])
                r = BlankyMesh.lerp(BlankyMesh.legS, BlankyMesh.legR, s)
            }
            let R = simd_matrix3x3(q)
            let dir = R * SIMD3<Float>(0, -1, 0)
            if i > 0 { p += (prevDir + dir) * (0.5 * L / Float(M)) } else { prevDir = dir }
            prevDir = dir
            frames.append((p, R, r + grow))
        }
        let (pe, Re, _) = frames[M]
        let Rh = arm ? Re * simd_matrix3x3(simd_quatf(angle: -side * 0.1, axis: [0, 0, 1])) : Re
        endP = pe + Rh * SIMD3<Float>(0, arm ? -0.05 : 0, 0)
        // 점은 여기(메인 액터)에서 다 계산해 두고, 그물 버퍼에는 복사만 — 버퍼를 여는 클로저는 액터 밖이라 그 안에서 앱 함수·속성을 쓰면 빌드 오류(0.5.48)
        let gw = grow
        var verts: [BKVert] = []
        verts.reserveCapacity(tubeCount + endPos.count)
        func ring(_ c: SIMD3<Float>, _ R: simd_float3x3, _ rr: Float, _ ny: Float) {
            // ny: 끝 반구에서 법선이 위·아래로 기우는 정도
            let axisV = R * SIMD3<Float>(0, 1, 0)
            for j in 0..<sides {
                let radial = R * SIMD3<Float>(cosT[j], 0, sinT[j])
                let n = simd_normalize(radial * sqrt(max(0, 1 - ny * ny)) + axisV * ny)
                verts.append(BKVert(p: c + radial * rr, uv: SIMD2<Float>(min(0.98, max(0.02, BlankyMesh.shade(n))), 0.5)))
            }
        }
        let (p0, R0, r0) = frames[0]
        for c in 0..<3 {
            let a = Float.pi / 2 * (1 - Float(c) / 3)
            ring(p0 + R0 * SIMD3<Float>(0, r0 * sin(a), 0), R0, r0 * cos(a), sin(a))
        }
        for (fp, fR, fr) in frames { ring(fp, fR, fr, 0) }
        let (pz, Rz, rz) = frames[M]
        for c in 1...3 {
            let a = Float.pi / 2 * Float(c) / 3
            ring(pz + Rz * SIMD3<Float>(0, -rz * sin(a) * 0.6, 0), Rz, rz * cos(a), -sin(a))
        }
        for (q, n) in zip(endPos, endNrm) {
            verts.append(BKVert(p: pe + Rh * (q + n * gw), uv: SIMD2<Float>(min(0.98, max(0.02, BlankyMesh.shade(Rh * n))), 0.5)))
        }
        let vs = verts
        mesh.withUnsafeMutableBytes(bufferIndex: 0) { raw in
            vs.withUnsafeBytes { src in
                raw.copyMemory(from: UnsafeRawBufferPointer(rebasing: src[0..<min(src.count, raw.count)]))
            }
        }
    }
}

// MARK: - 한 명
@MainActor
final class BlankyFigure {
    let root = Entity()                 // 발바닥 자리, 바라보는 쪽(+z)
    let H: Float                        // 키 (m)
    private let pelvis = Entity(), spine = Entity()
    private var arms: [[BlankyLimb]] = [[], []]            // 0 왼쪽(+x), 1 오른쪽 — [몸, (선 그림) 외곽선]
    private var legs: [[BlankyLimb]] = [[], []]
    private let armMount = [Entity(), Entity()], legMount = [Entity(), Entity()]
    let hand = Entity()                 // 오른손 쥐는 자리 (자리만 따라감 — 잔·담배는 몸과 같은 방향으로 바로 섬)
    let chest = Entity()                // 가슴 앞 (펼친 책)
    private var orbs: [(e: Entity, base: SIMD3<Float>, amp: Float, period: Float)] = []
    private var orbsGo = false
    private let look: LookMode
    private let tint: SIMD3<Float>
    private let pen: Float
    private let order: Int32
    private(set) var ember: Entity?

    /// 몸 자세 (키 1 기준 거리, 라디안). 팔다리는 그림의 선 자세(팔이 어깨 비탈을 따라 벌어져 늘어진 모양)에서 더하는 값
    struct Pose {
        var lift: Float = 0                         // 엉덩이 마디 높이 더함
        var sway = SIMD2<Float>(0, 0)               // 골반 옆(x)·앞(z) 밀림
        var pelvisYaw: Float = 0, pelvisRoll: Float = 0
        var lean: Float = 0, twist: Float = 0, side: Float = 0          // 몸 숙임(앞 +)·비틂·옆 기울임
        var headPitch: Float = 0, headYaw: Float = 0, headRoll: Float = 0  // 머리가 몸과 한 덩어리 → 몸을 조금 더 숙이고·돌리고·기울여 나타냄
        var arm: [SIMD3<Float>] = [SIMD3<Float>(0, 0, 0.03), SIMD3<Float>(0, 0, 0.03)]   // 앞으로·바깥으로·팔꿈치 굽힘
        var armTwist: [Float] = [0, 0]                                                  // 팔 굽는 면 돌림
        var leg: [SIMD3<Float>] = [SIMD3<Float>(0, 0, 0), SIMD3<Float>(0, 0, 0)]      // 엉덩이 앞으로·옆으로·무릎 굽힘

        static func mix(_ a: Pose, _ b: Pose, _ k: Float) -> Pose {
            func l(_ x: Float, _ y: Float) -> Float { x + (y - x) * k }
            var p = Pose()
            p.lift = l(a.lift, b.lift); p.sway = a.sway + (b.sway - a.sway) * k
            p.pelvisYaw = l(a.pelvisYaw, b.pelvisYaw); p.pelvisRoll = l(a.pelvisRoll, b.pelvisRoll)
            p.lean = l(a.lean, b.lean); p.twist = l(a.twist, b.twist); p.side = l(a.side, b.side)
            p.headPitch = l(a.headPitch, b.headPitch); p.headYaw = l(a.headYaw, b.headYaw); p.headRoll = l(a.headRoll, b.headRoll)
            for i in 0..<2 {
                p.arm[i] = a.arm[i] + (b.arm[i] - a.arm[i]) * k
                p.armTwist[i] = l(a.armTwist[i], b.armTwist[i])
                p.leg[i] = a.leg[i] + (b.leg[i] - a.leg[i]) * k
            }
            return p
        }
    }

    /// height: 키(m), orbs: 배 구멍 빛 구슬 수, pen: 선 그림 외곽선 굵기(m), order: 그리는 순서 (세계 6, 방 안 26)
    init?(height: Float, look: LookMode, tint: SIMD3<Float>, orbs n: Int, seed: UInt64, pen: Float, order: Int32) {
        guard let P = BlankyMesh.parts else { return nil }
        H = height
        self.look = look
        self.tint = tint
        self.pen = pen
        self.order = order
        root.scale = SIMD3<Float>(repeating: height)
        let body = BlankyMesh.bodyMat(look, tint: tint)
        let eye: RealityKit.Material = look == .line ? Ink.line : UnlitMaterial(color: UIColor(white: 0.012, alpha: 1))
        pelvis.position = SIMD3<Float>(0, BlankyMesh.hipY, 0)
        root.addChild(pelvis)
        pelvis.addChild(spine)
        part(P.body, body, spine)                       // 머리~몸통 한 덩어리
        part(P.face, eye, spine, ink: false)
        let w = pen / height
        for k in 0..<2 {
            let s: Float = k == 0 ? 1 : -1
            armMount[k].position = SIMD3<Float>(s * BlankyMesh.armRoot.x, BlankyMesh.armRoot.y - BlankyMesh.hipY, 0)
            spine.addChild(armMount[k])
            legMount[k].position = SIMD3<Float>(s * BlankyMesh.legX, 0, 0)
            pelvis.addChild(legMount[k])
            for (isArm, mount) in [(true, armMount[k]), (false, legMount[k])] {
                var list: [BlankyLimb] = []
                if let l = BlankyLimb(arm: isArm, side: s, material: body) { list.append(l) }
                if look == .line, let l = BlankyLimb(arm: isArm, side: s, material: Ink.hullMat, grow: w) { list.append(l) }
                for l in list {
                    mount.addChild(l.entity)
                    Sorting.apply(l.entity, Int(order))
                }
                if isArm { arms[k] = list } else { legs[k] = list }
            }
        }
        spine.addChild(hand)
        chest.position = SIMD3<Float>(0, 0.225, 0.115)                  // 책: 읽는 자세(몸 0.33 숙임)에서 두 손(armBook)이 양쪽 가장자리를 쥐는 자리
        chest.orientation = BK.rx(0.9)
        spine.addChild(chest)
        // 배 구멍 속 빛 구슬: 저마다 다른 빛깔, 천천히 떠오르내림. 둘레 은은한 빛무리(반투명, 깊이 안 씀 — 몸에 가려 구멍 안만 보임)
        var g = SeededRNG(seed: seed)
        let cols: [SIMD3<Float>] = [[0.2, 0.78, 0.86], [0.84, 0.58, 0.16], [1.0, 0.36, 0.72], [0.62, 1.0, 0.38], [1.0, 0.88, 0.35], [0.45, 0.6, 1.0]]
        let ys: [Float] = [0.035, -0.035, 0.0, -0.065]
        let xs: [Float] = [-0.012, 0.014, 0.0, 0.006]
        let core = MeshResource.generateSphere(radius: 1)
        var used: [Int] = []
        for i in 0..<n {
            var ci = i < 2 && Float.random(in: 0...1, using: &g) < 0.6 ? i : Int(g.next() % UInt64(cols.count))      // 그림처럼 청록·주황이 먼저
            if used.contains(ci) { ci = (ci + 1 + i) % cols.count }
            used.append(ci)
            let c = cols[ci]
            let r = Float.random(in: 0.019...0.025, using: &g)
            let holder = Entity()
            let base = SIMD3<Float>(xs[i % xs.count] + Float.random(in: -0.004...0.004, using: &g), BlankyMesh.hollowY + ys[i % ys.count],
                                    Float.random(in: -0.008...0.008, using: &g))
            holder.position = base
            spine.addChild(holder)
            let mat: RealityKit.Material = look == .line ? Ink.paper(0) : Tex.with(look) { UnlitMaterial(color: Tex.color(c)) }
            let e = ModelEntity(mesh: core, materials: [mat])
            e.scale = SIMD3<Float>(repeating: r)
            holder.addChild(e)
            if look == .line { Ink.hull(e, width: pen / height) }
            Sorting.apply(e, Int(order))
            if look != .line {
                var hm = Tex.with(look) { UnlitMaterial(color: Tex.color(c)) }
                hm.blending = .transparent(opacity: .init(scale: 0.32))
                hm.writesDepth = false
                let h = ModelEntity(mesh: core, materials: [hm])
                h.scale = SIMD3<Float>(repeating: r * 1.45)
                Sorting.apply(h, 30)
                holder.addChild(h)
            }
            orbs.append((holder, base, Float.random(in: 0.006...0.012, using: &g), Float.random(in: 2.2...3.6, using: &g)))
        }
        apply(Pose())
    }

    private func part(_ m: MeshResource, _ mat: RealityKit.Material, _ parent: Entity, ink: Bool = true) {
        let e = ModelEntity(mesh: m, materials: [mat])
        parent.addChild(e)
        if look == .line && ink { Ink.hull(e, width: pen / H) }
        Sorting.apply(e, Int(order))
    }

    private func propMat(_ c: SIMD3<Float>) -> RealityKit.Material {
        look == .line ? Ink.paper(0) : Tex.with(look) { UnlitMaterial(color: Tex.color(c * Worlds.safe(tint, min: 0.5))) }
    }
    private func prop(_ m: MeshResource, _ mat: RealityKit.Material, _ parent: Entity, at p: SIMD3<Float>, rot: simd_quatf = simd_quatf(angle: 0, axis: [0, 1, 0])) -> ModelEntity {
        let e = ModelEntity(mesh: m, materials: [mat])
        e.position = p
        e.orientation = rot
        parent.addChild(e)
        if look == .line { Ink.hull(e, width: pen / H) }
        Sorting.apply(e, Int(order))
        return e
    }

    /// 오른손 머그잔 (몸과 같은 방향으로 바로 섬)
    func addCup() -> Entity {
        let k = 1 / H
        let holder = Entity()
        hand.addChild(holder)
        // 잔 옆면이 손바닥에 닿게: 손(오른손)보다 몸 안쪽(+x)으로 잔 반지름 + 손바닥 두께만큼 — 0.5.46은 잔 가운데를 손 자리에 둬 손이 잔에 파묻혔음
        holder.position = SIMD3<Float>(0.04 * k + 0.013, 0.008, 0.004)
        _ = prop(.generateCylinder(height: 0.095 * k, radius: 0.04 * k), propMat([0.93, 0.91, 0.87]), holder, at: .zero)
        let coffee: RealityKit.Material = look == .line ? Ink.paper(1) : Tex.with(look) { UnlitMaterial(color: Tex.color(SIMD3<Float>(0.24, 0.14, 0.07) * Worlds.safe(tint, min: 0.5))) }
        _ = prop(.generateCylinder(height: 0.004 * k, radius: 0.034 * k), coffee, holder, at: SIMD3<Float>(0, 0.046 * k, 0))
        return holder
    }

    /// 가슴 앞에 펼친 책 (양쪽 장이 V자로 벌어짐)
    func addBook<G: RandomNumberGenerator>(using g: inout G) -> Entity {
        let k = 1 / H
        let holder = Entity()
        chest.addChild(holder)
        let covers: [SIMD3<Float>] = [[0.55, 0.16, 0.14], [0.14, 0.28, 0.5], [0.2, 0.4, 0.26], [0.75, 0.6, 0.3]]
        let cover = propMat(covers[Int(g.next() % UInt64(covers.count))])
        let page = propMat([0.95, 0.92, 0.84])
        for s: Float in [1, -1] {
            let half = Entity()
            half.orientation = BK.ry(s * 0.28)
            holder.addChild(half)
            _ = prop(.generateBox(width: 0.13 * k, height: 0.19 * k, depth: 0.012 * k), page, half, at: SIMD3<Float>(s * 0.066 * k, 0, 0))
            _ = prop(.generateBox(width: 0.135 * k, height: 0.195 * k, depth: 0.004 * k), cover, half, at: SIMD3<Float>(s * 0.066 * k, 0, 0.008 * k))
        }
        return holder
    }

    /// 오른손 담배 (앞·바깥쪽으로 뻗고 끝에 빨간 불씨)
    func addCigarette() -> Entity {
        let k = 1 / H
        let holder = Entity()
        holder.orientation = BK.ry(-0.5) * BK.rx(.pi / 2 - 0.15)
        hand.addChild(holder)
        _ = prop(.generateCylinder(height: 0.085 * k, radius: 0.0045 * k), propMat([0.95, 0.94, 0.9]), holder, at: SIMD3<Float>(0, 0.04 * k, 0))
        let em: RealityKit.Material = look == .line ? Ink.line : Tex.with(look) { UnlitMaterial(color: Tex.color(SIMD3<Float>(1, 0.36, 0.08))) }
        let e = ModelEntity(mesh: .generateSphere(radius: 0.0058 * k), materials: [em])
        e.position = SIMD3<Float>(0, 0.083 * k, 0)
        holder.addChild(e)
        Sorting.apply(e, Int(order))
        ember = e
        return holder
    }

    func apply(_ p: Pose) {
        pelvis.position = SIMD3<Float>(p.sway.x, BlankyMesh.hipY + p.lift, p.sway.y)
        pelvis.orientation = BK.ry(p.pelvisYaw) * BK.rz(p.pelvisRoll)
        spine.orientation = BK.ry(p.twist + 0.4 * p.headYaw) * BK.rx(p.lean + 0.5 * p.headPitch) * BK.rz(p.side + 0.5 * p.headRoll)
        for k in 0..<2 {
            for l in arms[k] { l.update(f: p.arm[k].x, o: p.arm[k].y, bend: p.arm[k].z, twist: p.armTwist[k]) }
            for l in legs[k] { l.update(f: p.leg[k].x, o: p.leg[k].y, bend: p.leg[k].z, twist: 0) }
        }
        if let r = arms[1].first { hand.position = armMount[1].position + r.endP }
    }

    /// 빛 구슬 떠오르내림은 장면에 들어간 뒤 한 번 RealityKit 되풀이 움직임으로 맡김 (앱이 매 화면 옮기지 않게 — 기준서 5-0)
    func tick() {
        guard !orbsGo, root.scene != nil else { return }
        orbsGo = true
        for o in orbs {
            let a = Transform(scale: .one, rotation: simd_quatf(angle: 0, axis: [0, 1, 0]), translation: o.base - SIMD3<Float>(0, o.amp, 0))
            let b = Transform(scale: .one, rotation: simd_quatf(angle: 0, axis: [0, 1, 0]), translation: o.base + SIMD3<Float>(0, o.amp, 0))
            let anim = FromToByAnimation<Transform>(from: a, to: b, duration: TimeInterval(o.period), timing: .easeInOut,
                                                    bindTarget: .transform, repeatMode: .autoReverse)
            if let r = try? AnimationResource.generate(with: anim) { o.e.playAnimation(r) }
        }
    }

    // MARK: 자세
    /// 다리(무릎이 휘는 곳 가운데까지 0.21, 그 아래 발바닥까지 0.23)로 엉덩이 마디(바닥에서 h)에서 앞 z 의 바닥에 발을 둠 → (엉덩이 앞으로, 무릎 굽힘)
    static func legIK(h: Float, z: Float) -> (Float, Float) {
        let L1 = BlankyMesh.thigh, L2 = BlankyMesh.shin
        let d = min(L1 + L2 - 0.001, max(abs(L1 - L2) + 0.02, sqrt(h * h + z * z)))
        let th = atan2(z, h)
        let a = acos(min(1, max(-1, (L1 * L1 + d * d - L2 * L2) / (2 * L1 * d))))
        let b = acos(min(1, max(-1, (L1 * L1 + L2 * L2 - d * d) / (2 * L1 * L2))))
        return (th + a, Float.pi - b)
    }

    // 팔 자세 (손이 닿는 자리를 팔 길이로 풀어 둔 값 — 앞으로, 바깥으로, 굽힘, 굽는 면 돌림)
    static let armSip = SIMD4<Float>(1.1, -0.3, 2.6, -0.75)          // 손(잔)을 입 앞으로 — 몸을 0.25 숙인 채
    static let armLap = SIMD4<Float>(-0.111, -0.209, 1.379, 0)        // 앉아서 잔을 무릎 위에
    static let armKnee = SIMD4<Float>(0.222, -0.209, 0.776, 0)        // 앉아서 손을 무릎에
    static let armBook = SIMD4<Float>(-0.361, -0.282, 2.959, 0)       // 가슴 앞 책 (몸 0.33 숙임)
    static let armWarm = SIMD4<Float>(0.333, -0.5, 1.966, 0)          // 모닥불에 손 쬠 (몸 0.33 숙임)
    static let armWaist = SIMD4<Float>(-0.5, -0.082, 1.897, 0)        // 담배 든 손을 허리 앞에
    static let armGround = SIMD4<Float>(-1.2, 0.055, 1.241, 0)        // 뒤로 바닥 짚음 (몸 0.55 젖힘)
    static func setArm(_ p: inout Pose, _ k: Int, _ a: SIMD4<Float>) {
        p.arm[k] = SIMD3<Float>(a.x, a.y, a.z)
        p.armTwist[k] = a.w
    }
    static func mixArm(_ p: inout Pose, _ k: Int, _ a: SIMD4<Float>, _ b: SIMD4<Float>, _ t: Float) { setArm(&p, k, a + (b - a) * t) }

    /// 걷기: ph 걸음 위상(한 바퀴 = 두 걸음). 골반이 느리게 흔들리고 팔은 한 박자 늦게 둥글게 휘며 따라옴 (흐느적)
    static func walk(_ ph: Float, t: Float) -> Pose {
        var p = Pose()
        let s = sin(ph), c = cos(ph)
        p.leg[0] = SIMD3<Float>(0.3 * s, 0.01, 0.06 + 0.55 * max(0, c))
        p.leg[1] = SIMD3<Float>(-0.3 * s, 0.01, 0.06 + 0.55 * max(0, -c))
        p.lift = -0.012 + 0.01 * cos(2 * ph)
        p.pelvisYaw = 0.1 * s
        p.pelvisRoll = 0.04 * s
        p.sway = SIMD2<Float>(0.009 * s, 0)
        p.twist = -0.1 * s
        p.lean = 0.05
        p.side = -0.06 * s + 0.035 * sin(t * 0.37)
        let la = sin(ph - 0.6)
        p.arm[0] = SIMD3<Float>(-0.28 * la, 0.02 * s, 0.06 + 0.2 * (0.5 + 0.5 * sin(ph - 1.6)))
        p.arm[1] = SIMD3<Float>(0.28 * la, -0.02 * s, 0.06 + 0.2 * (0.5 - 0.5 * sin(ph - 1.6)))
        p.headPitch = 0.04 * sin(2 * ph - 0.9)
        p.headRoll = 0.1 * sin(t * 0.31) + 0.03 * s
        p.headYaw = 0.12 * sin(t * 0.23)
        return p
    }

    /// 서 있기: 무게를 이쪽저쪽으로 옮기며 느리게 기우뚱, 팔은 늘어져 흔들, 몸을 천천히 돌려 두리번
    static func idle(t: Float) -> Pose {
        var p = Pose()
        let w = sin(t * 0.55)
        p.sway = SIMD2<Float>(0.012 * w, 0)
        p.pelvisRoll = 0.03 * w
        p.leg[0] = SIMD3<Float>(0.02, 0.0, 0.04 + 0.1 * max(0, -w))
        p.leg[1] = SIMD3<Float>(0.02, 0.0, 0.04 + 0.1 * max(0, w))
        p.lift = -0.004 - 0.006 * abs(w)
        p.side = -0.05 * w + 0.03 * sin(t * 0.19)
        p.lean = 0.03 + 0.02 * sin(t * 0.21)
        // 팔은 편하게 펴서 늘어뜨림 (굽힘은 아주 조금 흔들릴 만큼만 — 서 있는데 팔꿈치를 굽히고 있으면 어색함)
        p.arm[0] = SIMD3<Float>(0.04 * sin(t * 0.6 + 1), 0.02 * sin(t * 0.4), 0.03 + 0.025 * sin(t * 0.5))
        p.arm[1] = SIMD3<Float>(0.04 * sin(t * 0.6 + 2.2), 0.02 * sin(t * 0.4 + 1), 0.03 + 0.025 * sin(t * 0.5 + 1))
        p.headYaw = 0.45 * sin(t * 0.13)
        p.headPitch = 0.05 * sin(t * 0.17)
        p.headRoll = 0.13 * sin(t * 0.11)
        return p
    }

    /// 앉기: seat 엉덩이 마디 높이(바닥에서), foot 발 놓는 앞 거리 (키 1 기준). 손은 무릎에
    static func sit(seat: Float, foot: Float, t: Float) -> Pose {
        var p = Pose()
        p.lift = seat - BlankyMesh.hipY
        let (a, b) = legIK(h: seat, z: foot)
        p.leg[0] = SIMD3<Float>(a, 0.07, b)
        p.leg[1] = SIMD3<Float>(a + 0.03 * sin(t * 0.2), 0.07, b)
        p.lean = 0.1 + 0.03 * sin(t * 0.23)
        p.side = 0.04 * sin(t * 0.17)
        setArm(&p, 0, armKnee)
        setArm(&p, 1, armKnee)
        p.headYaw = 0.3 * sin(t * 0.11)
        p.headPitch = 0.04 * sin(t * 0.15)
        p.headRoll = 0.12 * sin(t * 0.13)
        return p
    }
}

// MARK: - 바깥 (하늘 세계)
/// 세계 하나에 2~3명. 만들 때 바로 제자리에 두고(기준서 5-0), 움직임은 그 세계가 지금 방·대표 방일 때만(RoomWorld.tick)
@MainActor
final class BlankyCrowd {
    let root = Entity()
    struct Env {
        let place: String
        let center: SIMD3<Float>
        let ground: Float                                       // 땅 높이 (y)
        let look: LookMode
        let tint: SIMD3<Float>
        let time: String
        let ring: (Float, Float) -> SIMD3<Float>                // 무리 둘레 사각 띠 위 자리 (둘레 0~1, 벽에서 d m) — 땅 높이
        let free: (SIMD3<Float>, Float) -> Bool                 // 어느 방에서든 r m 넘게 밖 + 나무·바위·텐트·집·물길을 피함
        let freeWet: (SIMD3<Float>, Float) -> Bool              // 물길은 괜찮음 (냇물 걷기)
        var fire: SIMD3<Float>? = nil
        var river: [SIMD3<Float>] = []
        var doors: [(door: SIMD3<Float>, out: SIMD3<Float>)] = []           // 시골 집 문 (문간 바닥, 바깥쪽)
        var street: [(SIMD3<Float>, SIMD3<Float>, SIMD3<Float>)] = []       // 카페 맞은편 보도 (시작, 끝, 가게 쪽)
        var beachR: Float = 0
        var stars = false                                       // 숲 별자리가 보이는 하늘
        var roof: Float = 0                                     // 도시 옥상 반지름
    }
    private enum Kind { case wander(ClosedRange<Float>), beach, river, visitor, fire, gaze, smoker, street(Int) }
    private final class Agent {
        let fig: BlankyFigure
        let kind: Kind
        var pos: SIMD3<Float>
        var yaw: Float
        var path: [SIMD3<Float>] = []
        var speed: Float
        var wait: Float
        var phase: Float = 0
        var t: Float
        var blend: Float = 0                // 0 섬 → 1 걸음
        var hidden = false
        var face: Float? = nil              // 멈춰서 바라볼 쪽
        var house = 0
        var dir: Float = 1
        var seat: Float = 0, foot: Float = 0
        var lookDown = false
        init(_ f: BlankyFigure, _ k: Kind, at p: SIMD3<Float>, yaw y: Float, speed s: Float, t t0: Float, wait w: Float) {
            fig = f; kind = k; pos = p; yaw = y; speed = s; t = t0; wait = w
        }
    }
    private var agents: [Agent] = []
    private var plumes: [SmokePlume] = []
    private let env: Env
    private var g: SeededRNG
    private let margin: Float = 1.5

    init(_ env: Env, seed: UInt64) {
        self.env = env
        g = SeededRNG(seed: seed)
        switch env.place {
        case "camp":
            addFireSitter()
            addWanderers(2, 3...13)
        case "forest":
            // 별자리가 보이는 하늘(밤·새벽·해질녘, 맑음·흐림·바람)이면 한 명은 앉아서 별자리를 봄, 아니면 모두 숲을 거닒
            if env.stars { addGazer() }
            addWanderers(env.stars ? 2 : 3, 4...14)
        case "valley":
            addWader()
            addWanderers(agents.isEmpty ? 2 : 1, 4...16)
        case "sea":
            addBeach(3)
        case "village":
            addVisitor()
            addWanderers(2, 6...24)
        case "city":
            addSmoker()
        case "cafe":
            addStreet(2)
        case "home":
            addWanderers(2, 2.5...9)
        default:
            break
        }
    }

    // MARK: 만들기
    private func figure(at p: SIMD3<Float>) -> BlankyFigure? {
        let h = Float.random(in: 1.62...1.86, using: &g)
        let pen = Ink.width(at: simd_distance(p, env.center))
        let n = BK.orbCount(&g)
        return BlankyFigure(height: h, look: env.look, tint: env.tint, orbs: n, seed: g.next(), pen: pen, order: 6)
    }
    @discardableResult
    private func add(_ k: Kind, at p: SIMD3<Float>, yaw: Float, speed: Float) -> Agent? {
        guard let f = figure(at: p) else { return nil }
        let a = Agent(f, k, at: p, yaw: yaw, speed: speed, t: Float.random(in: 0...50, using: &g), wait: Float.random(in: 1...6, using: &g))
        f.root.position = p
        f.root.orientation = BK.ry(yaw)
        f.apply(BlankyFigure.idle(t: a.t))
        root.addChild(f.root)
        agents.append(a)
        return a
    }
    private func spot(_ d: ClosedRange<Float>, r: Float) -> SIMD3<Float>? {
        for _ in 0..<20 {
            let p = env.ring(Float.random(in: 0...1, using: &g), Float.random(in: d, using: &g))
            if env.free(p, r) { return p }
        }
        return nil
    }
    private func yawTo(_ v: SIMD3<Float>) -> Float { atan2(v.x, v.z) }

    private func addWanderers(_ n: Int, _ d: ClosedRange<Float>) {
        for _ in 0..<n {
            guard let p = spot(d, r: margin) else { continue }
            add(.wander(d), at: p, yaw: Float.random(in: -Float.pi...Float.pi, using: &g), speed: Float.random(in: 0.34...0.48, using: &g))
        }
    }

    /// 캠핑장: 모닥불 앞 통나무에 앉아 손을 쬠 (방에서 보면 불 너머에서 이쪽을 봄)
    private func addFireSitter() {
        guard let f = env.fire else { return }
        var out = f - env.center
        out.y = 0
        let d0 = simd_length(out) > 0.01 ? simd_normalize(out) : SIMD3<Float>(1, 0, 0)
        for a: Float in [0, 0.6, -0.6, 1.2, -1.2, 1.9, -1.9] {
            let d = BK.ry(a).act(d0)
            let p = SIMD3<Float>(f.x, env.ground, f.z) + d * 1.05
            guard env.free(p, 1.0) else { continue }
            guard let ag = add(.fire, at: p, yaw: yawTo(-d), speed: 0) else { return }
            ag.seat = 0.29 / ag.fig.H + 0.045                   // 엉덩이 마디는 앉는 면보다 몸 아래 끝까지(키의 4.5%)만큼 위
            ag.foot = 0.4 / ag.fig.H
            // 앉은 통나무 (불과 나란히 가로로)
            let side = SIMD3<Float>(-d.z, 0, d.x)
            var log = Geo()
            log.trunk(from: p - side * 0.6 + SIMD3<Float>(0, 0.14, 0) + d * 0.04, to: p + side * 0.6 + SIMD3<Float>(0, 0.14, 0) + d * 0.04,
                      r0: 0.15, r1: 0.13, sides: 10, segs: 1)
            let mat: RealityKit.Material = env.look == .line ? Ink.paper(1) : Tex.with(env.look) { Tex.unlit("bark", tint: Worlds.safe(env.tint * 0.85, min: 0.25)) }
            if let e = log.entity("blankyLog", mat) {
                Sorting.apply(e, 5)
                root.addChild(e)
                if env.look == .line { Ink.hull(e, width: Ink.width(at: simd_distance(p, env.center))); Sorting.apply(e, 5) }
            }
            ag.fig.apply(firePose(ag))
            return
        }
    }

    /// 숲: 별자리가 보일 때 풀밭에 앉아 몸을 뒤로 젖히고 별자리를 올려다봄
    private func addGazer() {
        guard let p = spot(5...10, r: margin) else { return }
        var to = env.center - p
        to.y = 0
        guard let ag = add(.gaze, at: p, yaw: yawTo(to) + Float.random(in: -0.6...0.6, using: &g), speed: 0) else { return }
        ag.fig.apply(gazePose(ag))
    }

    /// 계곡: 냇물 속을 천천히 거닒 (방에서 4m 넘게 떨어진 물길 토막을 오감)
    private func addWader() {
        let pts = env.river
        guard pts.count > 2 else { return }
        var best: (Int, Int)? = nil
        var i = 0
        while i < pts.count {
            guard env.freeWet(pts[i], 4) else { i += 1; continue }
            var j = i
            while j + 1 < pts.count && env.freeWet(pts[j + 1], 4) { j += 1 }
            if j > i, best.map({ j - i > $0.1 - $0.0 }) ?? true { best = (i, j) }
            i = j + 1
        }
        guard let bst = best else { return }
        let i0 = bst.0, i1 = bst.1
        // 10m 남짓 토막만
        var len: Float = 0
        var e = i0
        while e < i1 && len < 11 { len += simd_distance(pts[e], pts[e + 1]); e += 1 }
        guard len > 3 else { return }
        let seg = pts[i0...e].map { SIMD3<Float>($0.x, env.ground - 0.17, $0.z) }
        guard let first = seg.first, let ag = add(.river, at: first, yaw: yawTo(seg[1] - seg[0]), speed: 0.3) else { return }
        riverSeg = seg
        ag.path = Array(seg.dropFirst())
        ag.wait = 0
    }

    /// 바다: 모래사장 물가를 따라 거닒 (가끔 멈춰 바다를 봄)
    private func addBeach(_ n: Int) {
        let r = env.beachR
        guard r > 1 else { return }
        for _ in 0..<n {
            for _ in 0..<12 {
                let a = Float.random(in: -Float.pi...Float.pi, using: &g)
                let p = SIMD3<Float>(env.center.x + cos(a) * r, env.ground, env.center.z + sin(a) * r)
                guard env.free(p, margin) else { continue }
                if let ag = add(.beach, at: p, yaw: 0, speed: Float.random(in: 0.3...0.42, using: &g)) {
                    ag.dir = Bool.random(using: &g) ? 1 : -1
                    ag.yaw = yawTo(SIMD3<Float>(-sin(a), 0, cos(a)) * ag.dir)
                    ag.fig.root.orientation = BK.ry(ag.yaw)
                }
                break
            }
        }
    }

    /// 시골: 집 문으로 들어갔다(안 보임) 한참 뒤 나와서 다른 집으로
    private func addVisitor() {
        let ds = env.doors
        guard ds.count >= 2 else { return }
        let i = Int(g.next() % UInt64(ds.count))
        let p = ds[i].door + ds[i].out * 1.5
        guard let ag = add(.visitor, at: SIMD3<Float>(p.x, env.ground, p.z), yaw: yawTo(-ds[i].out), speed: 0.4) else { return }
        ag.house = i
        ag.path = [ds[i].door + ds[i].out * 0.75 + SIMD3<Float>(0, 0.15, 0), ds[i].door + ds[i].out * 0.35 + SIMD3<Float>(0, 0.3, 0), ds[i].door + SIMD3<Float>(0, 0.45, 0)]
    }

    /// 도시: 옥상 끝에 서서 밖(도시)을 보며 담배
    private func addSmoker() {
        for _ in 0..<24 {
            let p = env.ring(Float.random(in: 0...1, using: &g), Float.random(in: 1.4...2.4, using: &g))
            guard simd_distance(SIMD2<Float>(p.x, p.z), SIMD2<Float>(env.center.x, env.center.z)) < env.roof - 0.8, env.free(p, 1.2) else { continue }
            var out = p - env.center
            out.y = 0
            guard let ag = add(.smoker, at: p, yaw: yawTo(out) + Float.random(in: -0.5...0.5, using: &g), speed: 0) else { return }
            _ = ag.fig.addCigarette()
            ag.fig.apply(smokePose(ag, cyc: 6))
            if let em = ag.fig.ember {
                let at = em.position(relativeTo: root)
                let pl = SmokePlume(at: at + SIMD3<Float>(0, 0.02, 0), size: 0.035, height: 0.7, alpha: 0.22,
                                    color: [0.85, 0.85, 0.86], look: env.look, sortGroup: Sorting.group, wind: [0.02, 0, 0.01], count: 6, life: 3)
                root.addChild(pl.root)
                plumes.append(pl)
            }
            return
        }
    }

    /// 카페: 창밖 길 건너편 보도를 오가며 가끔 가게 창을 들여다봄
    private func addStreet(_ n: Int) {
        var lines = Array(env.street.indices)
        lines.shuffle(using: &g)
        var made = 0
        for k in lines where made < n {
            let (a, b, _) = env.street[k]
            guard segFree(a, b, r: 1.0) else { continue }
            let s = Float.random(in: 0.1...0.9, using: &g)
            let p = a + (b - a) * s
            if let ag = add(.street(k), at: p, yaw: 0, speed: Float.random(in: 0.36...0.5, using: &g)) {
                ag.dir = Bool.random(using: &g) ? 1 : -1
                ag.path = [ag.dir > 0 ? b : a]
                ag.yaw = yawTo((ag.dir > 0 ? b : a) - p)
                ag.fig.root.orientation = BK.ry(ag.yaw)
                ag.wait = 0
                made += 1
            }
        }
    }

    // MARK: 길
    private func segFree(_ a: SIMD3<Float>, _ b: SIMD3<Float>, r: Float? = nil, wet: Bool = false) -> Bool {
        let n = max(1, Int(simd_distance(a, b) / 0.5))
        for i in 0...n {
            let q = a + (b - a) * (Float(i) / Float(n))
            if !(wet ? env.freeWet(q, r ?? margin) : env.free(q, r ?? margin)) { return false }
        }
        return true
    }

    /// a → b: 곧게 갈 수 없으면 무리 가운데를 둘레로 돌아가는 길 (집 안·옆방 자리를 지나지 않게)
    private func route(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> [SIMD3<Float>]? {
        if segFree(a, b) { return [b] }
        let c = env.center
        let va = a - c, vb = b - c
        let aa = atan2(va.z, va.x), ab = atan2(vb.z, vb.x)
        let da = BK.adiff(ab, aa)
        let r0 = max(simd_length(SIMD2<Float>(va.x, va.z)), simd_length(SIMD2<Float>(vb.x, vb.z)))
        for extra: Float in [0, 3, 8, 16] {
            for sgn: Float in [1, -1] {
                let span = sgn > 0 ? da : (da > 0 ? da - 2 * .pi : da + 2 * .pi)
                let rr = r0 + extra
                let n = max(2, Int(abs(span) * rr / 3))
                var pts: [SIMD3<Float>] = []
                for i in 1..<n {
                    let a1 = aa + span * Float(i) / Float(n)
                    pts.append(SIMD3<Float>(c.x + cos(a1) * rr, a.y, c.z + sin(a1) * rr))
                }
                pts.append(b)
                var prev = a, ok = true
                for q in pts {
                    if !segFree(prev, q) { ok = false; break }
                    prev = q
                }
                if ok { return pts }
            }
        }
        return nil
    }

    // MARK: 매 프레임
    func tick(_ dt: Float) {
        for p in plumes { p.tick(dt) }
        for a in agents { step(a, dt) }
    }

    private func step(_ a: Agent, _ dt: Float) {
        a.t += dt
        a.fig.tick()
        switch a.kind {
        case .fire: a.fig.apply(firePose(a)); return
        case .gaze: a.fig.apply(gazePose(a)); return
        case .smoker: a.fig.apply(smokePose(a, cyc: a.t.truncatingRemainder(dividingBy: 11))); return
        default: break
        }
        if a.hidden {
            a.wait -= dt
            if a.wait <= 0 { leaveHouse(a) }
            return
        }
        var walking = false
        if let w = a.path.first {
            var v = w - a.pos
            v.y = 0
            let d = simd_length(v)
            if d < 0.04 {
                a.pos = w
                a.path.removeFirst()
                if a.path.isEmpty { arrived(a) }
            } else {
                let want = atan2(v.x, v.z)
                turn(a, want, dt)
                if abs(BK.adiff(want, a.yaw)) < 0.7 {
                    let stepLen = min(d, a.speed * dt)
                    a.pos += (w - a.pos) * (stepLen / d)
                    a.phase += 2 * .pi * stepLen / (0.62 * a.fig.H)
                } else {
                    a.phase += dt * 2.2                     // 돌아서는 동안 제자리 걸음
                }
                walking = true
            }
        } else {
            if let f = a.face { turn(a, f, dt) }
            a.wait -= dt
            if a.wait <= 0 { plan(a) }
        }
        a.blend = min(1, max(0, a.blend + (walking ? dt : -dt) * 2.5))
        var p = BlankyFigure.Pose.mix(BlankyFigure.idle(t: a.t), BlankyFigure.walk(a.phase, t: a.t), a.blend)
        if a.lookDown && !walking { p.headPitch += 0.3; p.lean += 0.1 }
        a.fig.apply(p)
        a.fig.root.position = a.pos
        a.fig.root.orientation = BK.ry(a.yaw)
    }

    private func turn(_ a: Agent, _ want: Float, _ dt: Float) {
        let d = BK.adiff(want, a.yaw)
        a.yaw += max(-1.3 * dt, min(1.3 * dt, d))
    }

    private func arrived(_ a: Agent) {
        a.face = nil
        a.lookDown = false
        switch a.kind {
        case .wander:
            a.wait = Float.random(in: 3...11, using: &g)
            if Float.random(in: 0...1, using: &g) < 0.35 { a.face = yawTo(env.center - a.pos) }      // 가끔 이쪽(방)을 봄
        case .beach:
            a.wait = Float.random(in: 0...1, using: &g) < 0.4 ? Float.random(in: 4...10, using: &g) : 0.2
            if a.wait > 1 { var o = a.pos - env.center; o.y = 0; a.face = yawTo(o) }                     // 멈춰 바다를 봄
        case .river:
            a.wait = Float.random(in: 3...8, using: &g)
            a.lookDown = true                                                                          // 물속을 들여다봄
        case .visitor:
            if a.pos.y > env.ground + 0.3 {                                                            // 문간에 닿음 → 들어감
                a.hidden = true
                a.fig.root.isEnabled = false
                a.wait = Float.random(in: 15...45, using: &g)
            } else {
                a.wait = 0.5
            }
        case .street(let k):
            a.wait = Float.random(in: 2...6, using: &g)
            a.face = yawTo(env.street[k].2)                                                            // 가게 창을 들여다봄
        default:
            a.wait = 2
        }
    }

    private func plan(_ a: Agent) {
        switch a.kind {
        case .wander(let d):
            for _ in 0..<8 {
                guard let q = spot(d, r: margin), simd_distance(q, a.pos) > 2.5, simd_distance(q, a.pos) < 16 else { continue }
                if let r = route(a.pos, q) { a.path = r; return }
            }
            a.wait = 4
        case .beach:
            let r = env.beachR
            let c = env.center
            let a0 = atan2(a.pos.z - c.z, a.pos.x - c.x)
            for _ in 0..<2 {
                let span = a.dir * Float.random(in: 0.25...0.6, using: &g)
                let n = max(2, Int(abs(span) * r / 2))
                var pts: [SIMD3<Float>] = []
                var prev = a.pos, ok = true
                for i in 1...n {
                    let an = a0 + span * Float(i) / Float(n)
                    let q = SIMD3<Float>(c.x + cos(an) * r, env.ground, c.z + sin(an) * r)
                    if !segFree(prev, q) { ok = false; break }
                    pts.append(q)
                    prev = q
                }
                if ok { a.path = pts; return }
                a.dir = -a.dir                                                                         // 막히면 돌아섬
            }
            a.wait = 3
        case .river:
            a.path = riverLeg(a)                                    // 지금 끝에서 반대 끝으로 (처음 고른 토막을 되짚음)
            if a.path.isEmpty { a.wait = 5 }
        case .visitor:
            break
        case .street(let k):
            let (s, e, _) = env.street[k]
            a.dir = -a.dir
            a.path = [a.dir > 0 ? e : s]
        default:
            break
        }
    }

    private var riverSeg: [SIMD3<Float>] = []                   // 냇물 걷는 토막 (addWader)
    /// 냇물 걷는 토막을 지금 있는 끝에서 반대 끝으로
    private func riverLeg(_ a: Agent) -> [SIMD3<Float>] {
        guard riverSeg.count > 1 else { return [] }
        let dFirst = simd_distance(a.pos, riverSeg[0]), dLast = simd_distance(a.pos, riverSeg[riverSeg.count - 1])
        return dFirst < dLast ? Array(riverSeg.dropFirst()) : Array(riverSeg.reversed().dropFirst())
    }

    private func leaveHouse(_ a: Agent) {
        let ds = env.doors
        guard ds.count >= 2 else { a.wait = 30; return }
        let from = ds[a.house]
        var next = Int(g.next() % UInt64(ds.count))
        if next == a.house { next = (next + 1) % ds.count }
        let front0 = from.door + from.out * 1.5, front1 = ds[next].door + ds[next].out * 1.5
        let f0 = SIMD3<Float>(front0.x, env.ground, front0.z), f1 = SIMD3<Float>(front1.x, env.ground, front1.z)
        guard let mid = route(f0, f1) else { a.wait = 20; return }
        a.hidden = false
        a.fig.root.isEnabled = true
        a.pos = from.door + SIMD3<Float>(0, 0.45, 0)
        a.yaw = yawTo(from.out)
        a.house = next
        let to = ds[next]
        a.path = [from.door + from.out * 0.35 + SIMD3<Float>(0, 0.3, 0), from.door + from.out * 0.75 + SIMD3<Float>(0, 0.15, 0), f0]
            + mid
            + [to.door + to.out * 0.75 + SIMD3<Float>(0, 0.15, 0), to.door + to.out * 0.35 + SIMD3<Float>(0, 0.3, 0), to.door + SIMD3<Float>(0, 0.45, 0)]
        a.fig.root.position = a.pos
        a.fig.root.orientation = BK.ry(a.yaw)
    }

    // MARK: 머무는 자세
    private func firePose(_ a: Agent) -> BlankyFigure.Pose {
        var p = BlankyFigure.sit(seat: a.seat, foot: a.foot, t: a.t)
        let rub = BK.bump(a.t.truncatingRemainder(dividingBy: 14), 2, 3, 6, 7)                       // 가끔 손을 비빔
        let w = 0.04 * sin(a.t * 0.7)
        p.lean = 0.25 + 0.04 * sin(a.t * 0.21)
        BlankyFigure.setArm(&p, 0, BlankyFigure.armWarm + SIMD4<Float>(w, 0.06 * rub * sin(a.t * 7), 0.12 * rub, 0))
        BlankyFigure.setArm(&p, 1, BlankyFigure.armWarm + SIMD4<Float>(-w, -0.06 * rub * sin(a.t * 7), 0.12 * rub, 0))
        p.headPitch = 0.16 + 0.05 * sin(a.t * 0.17)
        p.headYaw = 0.2 * sin(a.t * 0.09)
        return p
    }

    private func gazePose(_ a: Agent) -> BlankyFigure.Pose {
        var p = BlankyFigure.sit(seat: 0.05, foot: 0.3, t: a.t)
        p.lean = -0.45 + 0.03 * sin(a.t * 0.2)
        BlankyFigure.setArm(&p, 0, BlankyFigure.armGround)                                           // 뒤로 짚은 두 손
        BlankyFigure.setArm(&p, 1, BlankyFigure.armGround)
        p.headPitch = -0.2 + 0.08 * sin(a.t * 0.07)
        p.headYaw = 0.55 * sin(a.t * 0.05)
        p.headRoll = 0.15 * sin(a.t * 0.09)
        p.leg[1] = SIMD3<Float>(p.leg[1].x - 0.25, 0.15, p.leg[1].z - 0.3)                               // 한쪽 다리는 조금 뻗음
        return p
    }

    /// cyc: 11초 한 바퀴 — 1~2초 담배를 입으로, 2~3.4초 빪, 3.4~4.6초 내림
    private func smokePose(_ a: Agent, cyc: Float) -> BlankyFigure.Pose {
        var p = BlankyFigure.idle(t: a.t)
        let r = BK.bump(cyc, 1, 2, 3.4, 4.6)
        BlankyFigure.mixArm(&p, 1, BlankyFigure.armWaist, BlankyFigure.armSip, r)
        p.arm[0] = SIMD3<Float>(-0.04, 0.0, 0.35)
        p.lean = 0.25 * r + 0.02 * sin(a.t * 0.2)
        p.headYaw = 0.3 * sin(a.t * 0.07) * (1 - r)
        p.headPitch = 0
        return p
    }
}

// MARK: - 실내 (방 안)
/// 지금 방 하나에 1명 (ExploreSession 이 지금 방이 카페·도시·전시관일 때 만듦). 키는 방 크기·천장에 맞춤.
/// - 카페: 앉을 만한 가구(윗면 35~62cm, 앞이 바닥)에 앉아 커피를 마시거나 책을 읽음. 앉을 데가 없으면 커피를 들고 서성임
/// - 도시: 방 안을 서성임 / 전시관: 그림 앞에 서서 감상하고 다른 그림으로
/// 처음 나타나는 자리는 내 시야 밖. 걷는 길은 동물과 같은 길찾기(PetNav — 가구·벽을 돌아서), 내 곁 70cm 안이면 멈춰서 나를 봄
@MainActor
final class BlankyIndoor {
    let root = Entity()
    let roomId: Int
    let place: String
    let look: LookMode
    private var fig: BlankyFigure?
    private let H: Float
    private let floorY: Float
    private let tint: SIMD3<Float>
    private var g: SeededRNG
    private var pos = SIMD2<Float>(0, 0)
    private var yaw: Float = 0
    private var target: SIMD2<Float>?
    private var path: [SIMD2<Float>] = []         // 찾아 둔 길 (경유점 — 곧장 가도 막히지 않는 데까지 건너뛴 점들)
    private var startTurn = false                 // 길을 떠나기 전 그 자리에서 먼저 돌아섬 (가는 중엔 멈추지 않고 돌면서 감)
    private var replans = 0
    private var face: Float?
    private var wait: Float = 0
    private var t: Float = 0
    private var phase: Float = 0
    private var blend: Float = 0
    private var seat: (p: SIMD2<Float>, dir: SIMD2<Float>, h: Float)?
    private var cup: Entity?
    private var book: Entity?
    private var reading = false
    private var actUntil: Float = 0
    private var art = -1
    private var artLook: Float = 0
    private var headYaw: Float = 0
    private var stopT: Float = 0
    private(set) var placed = false

    /// area: 방 넓이(m²), ceil: 천장 높이(m)
    init(roomId: Int, place: String, look: LookMode, tint: SIMD3<Float>, floorY: Float, ceil: Float, area: Float, seed: UInt64) {
        self.roomId = roomId
        self.place = place
        self.look = look
        self.tint = tint
        self.floorY = floorY
        g = SeededRNG(seed: seed)
        H = max(1.3, min(1.74, ceil * 0.67, 1.25 + 0.06 * area))
    }

    func remove() { root.removeFromParent() }

    private func make() -> BlankyFigure? {
        if let f = fig { return f }
        guard let f = BlankyFigure(height: H, look: look, tint: tint, orbs: BK.orbCount(&g), seed: g.next(), pen: Ink.w, order: 26) else { return nil }
        root.addChild(f.root)
        fig = f
        if place == "cafe" {
            cup = f.addCup()
            book = f.addBook(using: &g)
            reading = Bool.random(using: &g)
            cup?.isEnabled = !reading
            book?.isEnabled = reading
            actUntil = Float.random(in: 40...80, using: &g)
        }
        return f
    }

    /// seats: 카페에서 앉을 만한 자리 (저장 좌표 xz, 바라보는 쪽, 앉는 면 높이), sample: 이 방 안 아무 자리, arts: 걸린 그림 (가운데, 앞쪽)
    func tick(_ dt: Float, _ c: HomeCat.Ctx, seats: [(SIMD2<Float>, SIMD2<Float>, Float)], sample: () -> SIMD2<Float>?,
              arts: [(SIMD3<Float>, SIMD3<Float>)]) {
        t += dt
        let me = SIMD2<Float>(c.head.x, c.head.z)
        if !placed {
            // 내 시야 밖에서 나타남 (눈앞에서 갑자기 생기지 않게)
            if place == "cafe", !seats.isEmpty {
                let ok = seats.filter { !HomeCat.inView($0.0, c) && simd_distance($0.0, me) > 1.0 }
                guard let s = ok.randomElement(using: &g) else { return }
                seat = (s.0, s.1, s.2)
                pos = s.0
                yaw = atan2(s.1.x, s.1.y)
            } else {
                var found: SIMD2<Float>? = nil
                for _ in 0..<12 {
                    guard let p = sample() else { continue }
                    if c.free(p) && !HomeCat.inView(p, c) && simd_distance(p, me) > 1.5 { found = p; break }
                }
                guard let p = found else { return }
                pos = p
                yaw = Float.random(in: -Float.pi...Float.pi, using: &g)
                wait = Float.random(in: 1...4, using: &g)
            }
            guard make() != nil else { return }
            placed = true
        }
        guard let f = fig else { return }
        f.tick()
        let toMe = me - pos
        let dMe = simd_length(toMe)
        var p: BlankyFigure.Pose
        if let s = seat {
            p = seatedPose(s, dt)
        } else {
            var walking = false
            if dMe < 0.7 && target != nil {                                 // 내가 가로막음 → 멈춰서 나를 봄
                target = nil
                path = []
                stopT = 2
            }
            if stopT > 0 {
                stopT -= dt
                face = atan2(toMe.x, toMe.y)
            }
            // 길 따라 걷기: 길은 떠날 때 한 번 찾고(동물과 같은 길찾기 — 가구·벽·모서리를 돌아 곧장 갈 수 있는 점만 경유),
            // 걷는 동안은 멈추지 않고 몸을 천천히 돌리며 꺾인 곳에서만 느려짐. 예전엔 매 순간 다음 한 걸음을 다시 받아
            // 방향이 크게 바뀔 때마다 서서 돌고 다시 걸어 구석·가구 곁에서 움찔움찔했음
            if let tg = target, let w = path.first {
                let v = w - pos
                let d = simd_length(v)
                if d < 0.03 {
                    pos = w
                    path.removeFirst()
                    if path.isEmpty { target = nil; arrivedIn(arts) }
                } else {
                    let dir = v / d
                    let want = atan2(dir.x, dir.y)
                    let diff = BK.adiff(want, yaw)
                    yaw += max(-1.8 * dt, min(1.8 * dt, diff))
                    if startTurn && abs(diff) > 0.35 {
                        phase += dt * 1.6                                   // 떠나기 전 제자리에서 천천히 돌아섬
                    } else {
                        startTurn = false
                        let sp: Float = 0.36 * max(0.35, cos(min(abs(diff), 1.2)))
                        let stepLen = min(d, sp * dt)
                        let np = pos + dir * stepLen
                        if c.pass(np) || !c.pass(pos) {
                            pos = np
                            phase += 2 * .pi * stepLen / (0.62 * H)
                        } else if replans < 2, let pth = HomeCat.plan(from: pos, to: tg, reach: 0.12, c), !pth.isEmpty {
                            replans += 1                                    // 그새 가구가 보여 길이 막힘 → 한 번 다시 찾음
                            path = pth
                        } else {
                            target = nil
                            path = []
                            wait = 1
                        }
                    }
                    walking = true
                }
            } else {
                if let fc = face { yaw += max(-1.3 * dt, min(1.3 * dt, BK.adiff(fc, yaw))) }
                wait -= dt
                if wait <= 0 && stopT <= 0 { planIn(c, me, sample: sample, arts: arts) }
            }
            blend = min(1, max(0, blend + (walking ? dt : -dt) * 2.5))
            p = BlankyFigure.Pose.mix(BlankyFigure.idle(t: t), BlankyFigure.walk(phase, t: t), blend)
            if place == "gallery" && !walking && art >= 0 {
                // 그림 감상: 팔은 편하게 늘어뜨리고 그림 높이를 봄, 고개(몸)를 천천히 갸웃
                p.headPitch = artLook + 0.03 * sin(t * 0.2)
                p.headRoll = 0.16 * sin(t * 0.13)
                p.headYaw = 0.1 * sin(t * 0.09)
            }
            if place == "cafe", cup != nil {                              // 앉을 데가 없는 카페: 커피를 들고 서성이다 가끔 마심
                let r = BK.bump(t.truncatingRemainder(dividingBy: 12), 2, 3, 4.2, 5.2) * (1 - blend)
                BlankyFigure.mixArm(&p, 1, BlankyFigure.armWaist, BlankyFigure.armSip, r)
                p.lean = p.lean * (1 - r) + 0.25 * r
                p.headPitch *= 1 - r
                cup?.isEnabled = true
                book?.isEnabled = false
            }
        }
        // 가까이(2.2m) 앞쪽에 있으면 가끔 고개를 돌려 나를 봄
        let rel = BK.adiff(atan2(toMe.x, toMe.y), yaw)
        let want: Float = (dMe < 2.2 && abs(rel) < 1.6 && sin(t * 0.21) > -0.2) ? max(-1.0, min(1.0, rel)) : 0
        headYaw += (want - headYaw) * min(1, dt * 1.5)
        p.headYaw = p.headYaw * (1 - min(1, abs(headYaw))) + headYaw
        f.apply(p)
        f.root.position = SIMD3<Float>(pos.x, floorY, pos.y)
        f.root.orientation = BK.ry(yaw)
    }

    private func seatedPose(_ s: (p: SIMD2<Float>, dir: SIMD2<Float>, h: Float), _ dt: Float) -> BlankyFigure.Pose {
        if t > actUntil {                                                  // 커피 ↔ 책을 가끔 바꿈
            reading.toggle()
            actUntil = t + Float.random(in: 40...90, using: &g)
            cup?.isEnabled = !reading
            book?.isEnabled = reading
        }
        var p = BlankyFigure.sit(seat: s.h / H + 0.045, foot: 0.36 / H, t: t)
        if reading {
            // 두 손으로 책을 가슴 앞에 들고 내려다봄. 가끔 장을 넘김
            let turn = BK.bump(t.truncatingRemainder(dividingBy: 17), 3, 3.6, 4.2, 4.8)
            BlankyFigure.setArm(&p, 0, BlankyFigure.armBook)
            BlankyFigure.setArm(&p, 1, BlankyFigure.armBook + SIMD4<Float>(0.15 * turn, 0.2 * turn, -0.4 * turn, 0))
            p.headPitch = 0.26 + 0.03 * sin(t * 0.3)
            p.headYaw = 0.05 * sin(t * 0.4)
            p.lean = 0.2
        } else {
            // 커피: 잔을 무릎 위에 들고 있다가 가끔 천천히 한 모금
            let r = BK.bump(t.truncatingRemainder(dividingBy: 11), 2, 3.2, 4.4, 5.6)
            BlankyFigure.mixArm(&p, 1, BlankyFigure.armLap, BlankyFigure.armSip, r)
            BlankyFigure.setArm(&p, 0, BlankyFigure.armKnee)
            p.lean = 0.1 + 0.15 * r
            p.headPitch *= 1 - r
        }
        return p
    }

    private func arrivedIn(_ arts: [(SIMD3<Float>, SIMD3<Float>)]) {
        if place == "gallery", art >= 0, art < arts.count {
            let (c, n) = arts[art]
            face = atan2(-n.x, -n.z)
            let eye = floorY + H * 0.88
            let d = max(0.5, simd_distance(SIMD2<Float>(c.x, c.z), pos))
            artLook = -atan2(c.y - eye, d) * 0.9
            wait = Float.random(in: 10...22, using: &g)
        } else {
            face = nil
            wait = Float.random(in: 2...6, using: &g)
        }
    }

    private func planIn(_ c: HomeCat.Ctx, _ me: SIMD2<Float>, sample: () -> SIMD2<Float>?, arts: [(SIMD3<Float>, SIMD3<Float>)]) {
        face = nil
        if place == "gallery", !arts.isEmpty {
            // 다른 그림 앞으로 (그림 앞 0.9~1.5m, 내 곁은 피함)
            var order = Array(arts.indices).filter { $0 != art }
            order.shuffle(using: &g)
            if order.isEmpty { order = [0] }
            for k in order {
                let (ac, n) = arts[k]
                for d: Float in [1.2, 1.5, 0.95] {
                    let q = SIMD2<Float>(ac.x + n.x * d, ac.z + n.z * d)
                    if c.free(q) && simd_distance(q, me) > 0.9 && go(q, c) { art = k; return }
                }
            }
        }
        art = -1
        // 서성임: 1.2~3m 떨어진 빈 바닥으로
        for _ in 0..<10 {
            guard let q = sample() else { continue }
            let d = simd_distance(q, pos)
            if d > 1.2 && d < 3.2 && c.free(q) && simd_distance(q, me) > 0.9 && go(q, c) { return }
        }
        wait = 2
    }

    /// q 까지 길이 있으면 떠남 (없으면 다른 곳을 고르게 false)
    private func go(_ q: SIMD2<Float>, _ c: HomeCat.Ctx) -> Bool {
        guard let pth = HomeCat.plan(from: pos, to: q, reach: 0.12, c), !pth.isEmpty else { return false }
        target = q
        path = pth
        startTurn = true
        replans = 0
        return true
    }
}
