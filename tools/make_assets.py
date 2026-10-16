"""어나더 스페이스 그림 재료 만들기 (앱 안에 담는 PNG)
- tex/*.png : 바닥·벽·소품에 입히는 반복 무늬 (512×512, 가장자리가 이어지게 만듦)
- sky/*.png : 하늘 (시간 5 × 날씨 3, 1024×512 등장방형). 지평선 위아래를 거울처럼 맞춰 둬서 방향이 뒤집혀도 같아 보임
- sky/cloud_*.png : 구름 한 장 (투명 배경)
사용: python3 tools/make_assets.py   →  ios/AnotherSpace/Resources/ 에 저장"""
import os, math
import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'ios', 'AnotherSpace', 'Resources')
N = 512
rng = np.random.default_rng(7)


def noise(beta=2.0, size=N, seed=None, aniso=(1.0, 1.0)):
    """가장자리가 이어지는 잡음 (주파수 공간에서 1/f^beta). 0~1"""
    r = np.random.default_rng(seed) if seed is not None else rng
    w = r.standard_normal((size, size))
    f = np.fft.fft2(w)
    ky = np.fft.fftfreq(size)[:, None] * aniso[1]
    kx = np.fft.fftfreq(size)[None, :] * aniso[0]
    k = np.sqrt(kx ** 2 + ky ** 2)
    k[0, 0] = 1
    f = f / k ** (beta / 2)
    f[0, 0] = 0
    v = np.real(np.fft.ifft2(f))
    v = (v - v.min()) / (v.max() - v.min())
    return v


def colorize(v, stops):
    """v(0~1) → 색 (stops: [(위치, (r,g,b)), ...])"""
    out = np.zeros(v.shape + (3,))
    xs = [s[0] for s in stops]
    for c in range(3):
        out[..., c] = np.interp(v, xs, [s[1][c] for s in stops])
    return out


def save(name, rgb, folder='tex'):
    os.makedirs(os.path.join(OUT, folder), exist_ok=True)
    a = np.clip(rgb, 0, 255).astype(np.uint8)
    Image.fromarray(a).save(os.path.join(OUT, folder, name + '.png'), optimize=True)


def shade(rgb, k):
    return rgb * k[..., None]


# ───────────── 바닥 ─────────────
def grass():
    base = noise(2.2)
    fine = noise(0.9)
    blades = noise(1.2, aniso=(4.0, 0.6))
    v = 0.45 * base + 0.25 * fine + 0.3 * blades
    rgb = colorize(v, [(0, (34, 58, 24)), (0.45, (66, 104, 40)), (0.75, (104, 140, 58)), (1, (150, 170, 86))])
    dirt = noise(2.6) > 0.78
    rgb[dirt] = rgb[dirt] * 0.4 + np.array([96, 78, 52]) * 0.6
    save('grass', rgb)


def moss():
    v = 0.6 * noise(2.4) + 0.4 * noise(1.0)
    rgb = colorize(v, [(0, (28, 44, 22)), (0.5, (60, 92, 38)), (0.8, (96, 122, 52)), (1, (140, 150, 80))])
    leaves = noise(1.4) > 0.72
    rgb[leaves] = rgb[leaves] * 0.5 + np.array([120, 84, 44]) * 0.5
    save('moss', rgb)


def dirt():
    v = 0.55 * noise(2.3) + 0.45 * noise(0.8)
    rgb = colorize(v, [(0, (70, 52, 36)), (0.5, (118, 92, 64)), (1, (160, 134, 98))])
    save('dirt', rgb)


def pebbles(name, palette, cells=70, seed=3):
    r = np.random.default_rng(seed)
    pts = r.random((cells, 2)) * N
    yy, xx = np.mgrid[0:N, 0:N]
    d1 = np.full((N, N), 1e9); d2 = np.full((N, N), 1e9); idx = np.zeros((N, N), int)
    for i, (px, py) in enumerate(pts):
        for ox in (-N, 0, N):
            for oy in (-N, 0, N):
                d = np.hypot(xx - px - ox, yy - py - oy)
                closer = d < d1
                d2 = np.where(closer, d1, np.minimum(d2, d))
                idx = np.where(closer, i, idx)
                d1 = np.where(closer, d, d1)
    edge = np.clip((d2 - d1) / 10, 0, 1)
    tone = r.random(cells)[idx]
    v = 0.25 + 0.55 * tone + 0.2 * noise(0.9)
    rgb = colorize(v, palette)
    rgb = shade(rgb, 0.35 + 0.65 * edge ** 0.6)
    return rgb


def pebble():
    save('pebble', pebbles('pebble', [(0, (70, 72, 74)), (0.5, (128, 126, 120)), (1, (190, 186, 176))], cells=90))


def sand():
    ripples = np.sin((np.mgrid[0:N, 0:N][0] / N * 2 * np.pi * 9) + noise(2.5) * 6) * 0.5 + 0.5
    v = 0.55 * noise(0.6) + 0.25 * noise(2.2) + 0.2 * ripples
    rgb = colorize(v, [(0, (170, 150, 112)), (0.5, (206, 186, 146)), (1, (234, 220, 186))])
    save('sand', rgb)


def asphalt():
    v = 0.7 * noise(0.4) + 0.3 * noise(2.0)
    rgb = colorize(v, [(0, (44, 44, 46)), (0.5, (70, 70, 72)), (1, (104, 102, 100))])
    # 보도블록 줄눈
    yy, xx = np.mgrid[0:N, 0:N]
    tile = ((xx % 128) < 3) | (((yy + (xx // 128 % 2) * 64) % 128) < 3)
    rgb[tile] = rgb[tile] * 0.55
    save('asphalt', rgb)


def planks(name, base, rows=8, seed=5):
    r = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:N, 0:N]
    h = N // rows
    row = yy // h
    grain = noise(1.8, aniso=(0.15, 3.0), seed=seed)
    off = r.integers(0, N, rows)[row]
    plank_len = N // 2
    seg = ((xx + off) % N) // plank_len
    tone = (r.random((rows, 4))[row, seg] - 0.5) * 0.25
    v = np.clip(0.5 + tone + (grain - 0.5) * 0.7, 0, 1)
    rgb = colorize(v, base)
    gap = ((yy % h) < 3) | (((xx + off) % plank_len) < 3)
    rgb[gap] = rgb[gap] * 0.45
    save(name, rgb)


def marble():
    v = noise(2.0)
    veins = np.abs(np.sin((np.mgrid[0:N, 0:N][1] / N * 2 * np.pi * 2) + noise(1.6) * 9))
    veins = veins ** 0.15
    rgb = colorize(v * 0.4 + 0.6, [(0, (200, 198, 194)), (1, (240, 238, 234))])
    rgb = shade(rgb, 0.78 + 0.22 * veins)
    yy, xx = np.mgrid[0:N, 0:N]
    tile = ((xx % 256) < 2) | ((yy % 256) < 2)
    rgb[tile] = rgb[tile] * 0.8
    save('marble', rgb)


# ───────────── 벽 ─────────────
def rock(name, stops, layered=False, seed=11):
    v = 0.5 * noise(2.6, seed=seed) + 0.3 * noise(1.4, seed=seed + 1) + 0.2 * noise(0.8, seed=seed + 2)
    if layered:
        yy = np.mgrid[0:N, 0:N][0]
        strata = np.sin(yy / N * 2 * np.pi * 7 + noise(2.8, seed=seed + 3) * 5) * 0.5 + 0.5
        v = 0.65 * v + 0.35 * strata
    rgb = colorize(v, stops)
    cracks = noise(1.1, seed=seed + 4)
    crack = np.abs(cracks - 0.5) < 0.012
    rgb[crack] = rgb[crack] * 0.45
    save(name, rgb)


def stonewall():
    rgb = pebbles('stonewall', [(0, (78, 74, 66)), (0.5, (128, 120, 104)), (1, (176, 168, 150))], cells=36, seed=8)
    save('stonewall', rgb)


def brick():
    yy, xx = np.mgrid[0:N, 0:N]
    bh, bw = 32, 96
    row = yy // bh
    off = (row % 2) * (bw // 2)
    col = (xx + off) // bw
    r = np.random.default_rng(9)
    tone = r.random((N // bh + 1, N // bw + 2))[row, col]
    v = 0.3 + 0.5 * tone + 0.2 * noise(0.8)
    rgb = colorize(v, [(0, (110, 54, 40)), (0.5, (150, 78, 56)), (1, (186, 112, 82))])
    mortar = ((yy % bh) < 4) | (((xx + off) % bw) < 4)
    rgb[mortar] = np.array([168, 160, 146]) * (0.8 + 0.2 * noise(0.5)[mortar][:, None])
    save('brick', rgb)


def facade(night=False):
    yy, xx = np.mgrid[0:N, 0:N]
    v = 0.6 * noise(0.6) + 0.4 * noise(2.0)
    rgb = colorize(v, [(0, (74, 76, 82)), (1, (120, 122, 128))])
    r = np.random.default_rng(12)
    cw, ch = 64, 64
    lit = r.random((N // ch, N // cw))
    win = ((xx % cw) > 12) & ((xx % cw) < 52) & ((yy % ch) > 14) & ((yy % ch) < 50)
    if night:
        rgb = rgb * 0.35
        on = lit[yy // ch, xx // cw] > 0.55
        warm = np.array([255, 214, 140]) * (0.8 + 0.2 * noise(0.5)[..., None])
        rgb[win & on] = warm[win & on]
        rgb[win & ~on] = np.array([18, 22, 30])
    else:
        sky = np.array([150, 170, 190]) * (0.85 + 0.15 * lit[yy // ch, xx // cw])[..., None]
        rgb[win] = sky[win]
    save('facade_night' if night else 'facade', rgb)


def plaster():
    v = 0.7 * noise(0.5) + 0.3 * noise(2.2)
    rgb = colorize(v, [(0, (214, 210, 202)), (1, (240, 238, 232))])
    save('plaster', rgb)


def timber():
    """통나무 벽 (가로로 쌓은 통나무)"""
    yy, xx = np.mgrid[0:N, 0:N]
    h = N // 8
    t = (yy % h) / h
    round_ = np.sin(t * np.pi) ** 0.5
    grain = noise(1.6, aniso=(0.12, 3.0))
    v = 0.25 + 0.5 * grain
    rgb = colorize(v, [(0, (88, 56, 32)), (0.5, (132, 88, 52)), (1, (170, 122, 76))])
    rgb = shade(rgb, 0.45 + 0.55 * round_)
    save('timber', rgb)


def forest():
    """빽빽한 나무 줄기 벽 (세로 줄기 + 사이로 어두운 숲)"""
    yy, xx = np.mgrid[0:N, 0:N]
    dark = colorize(noise(2.0), [(0, (12, 22, 14)), (1, (30, 48, 30))])
    rgb = dark.copy()
    r = np.random.default_rng(21)
    bark = noise(1.5, aniso=(3.0, 0.2))
    for layer, (count, wmin, wmax, k) in enumerate([(9, 18, 34, 0.55), (6, 34, 60, 0.85)]):
        for _ in range(count):
            cx = r.random() * N
            w = r.uniform(wmin, wmax)
            d = np.minimum(np.minimum(np.abs(xx - cx), np.abs(xx - cx - N)), np.abs(xx - cx + N))
            m = d < w / 2
            roundness = np.sqrt(np.clip(1 - (d / (w / 2)) ** 2, 0, 1))
            col = colorize(bark, [(0, (46, 34, 26)), (1, (104, 84, 62))]) * k
            col = shade(col, 0.4 + 0.6 * roundness)
            rgb[m] = col[m]
    leaves = noise(1.3) > 0.8
    rgb[leaves] = rgb[leaves] * 0.5 + np.array([40, 70, 34]) * 0.5
    save('forest', rgb)


def bark():
    v = noise(1.5, aniso=(3.0, 0.2))
    rgb = colorize(v, [(0, (52, 38, 28)), (0.5, (96, 72, 50)), (1, (138, 108, 78))])
    save('bark', rgb)


def hay():
    v = 0.6 * noise(1.2, aniso=(0.3, 2.5)) + 0.4 * noise(0.8)
    rgb = colorize(v, [(0, (150, 120, 60)), (0.5, (196, 164, 92)), (1, (232, 206, 140))])
    save('hay', rgb)


def concrete():
    v = 0.6 * noise(0.5) + 0.4 * noise(2.3)
    rgb = colorize(v, [(0, (120, 118, 114)), (1, (170, 168, 162))])
    save('concrete', rgb)


# ───────────── 하늘 ─────────────
SKY = {   # 시간: (위, 지평선, 해/달 고도°, 해 색, 별)
    'dawn':      ((24, 30, 66), (196, 140, 150), -4, (255, 190, 160), 0.5),
    'morning':   ((92, 150, 214), (214, 226, 236), 24, (255, 246, 220), 0),
    'afternoon': ((58, 122, 206), (188, 214, 238), 58, (255, 252, 240), 0),
    'dusk':      ((52, 56, 112), (246, 150, 92), 4, (255, 170, 90), 0.15),
    'night':     ((6, 9, 22), (26, 36, 62), 38, (226, 230, 240), 1.0),
}
COND = {'clear': 0.0, 'overcast': 0.75, 'storm': 1.0}


def sky(time, cond):
    W, H = 1024, 512
    top, hor, el, sun, stars = SKY[time]
    oc = COND[cond]
    v = np.linspace(0, 1, H // 2)[:, None]          # 0 = 꼭대기, 1 = 지평선
    t = v ** 1.6
    col = np.array(top) * (1 - t)[..., None] + np.array(hor) * t[..., None]
    col = np.repeat(col, W, axis=1)
    if oc:
        gray = np.array([150, 154, 160]) if time in ('morning', 'afternoon') else np.array([70, 72, 82]) if time in ('dawn', 'dusk') else np.array([22, 24, 30])
        if cond == 'storm':
            gray = gray * 0.55
        col = col * (1 - oc) + gray * oc
        n = noise(2.4, size=W)[:H // 2, :]
        col = col * (0.88 + 0.24 * n[..., None])
    # 별
    if stars and cond != 'storm':
        r = np.random.default_rng(31)
        k = int(1600 * stars * (1 - oc * 0.85))
        ys = (r.random(k) ** 1.4 * (H // 2 * 0.92)).astype(int)
        xs = r.integers(0, W, k)
        b = r.random(k) ** 3
        for x, y, bb in zip(xs, ys, b):
            col[y, x] = np.maximum(col[y, x], 120 + 135 * bb)
    # 해·달 (방위 135°에 고정 — 앱도 같은 방향으로 그림자를 계산)
    if cond != 'storm':
        az = 135 / 360 * W
        ey = (1 - max(el, 0) / 90) * (H // 2)
        yy, xx = np.mgrid[0:H // 2, 0:W]
        d = np.hypot(np.minimum(np.abs(xx - az), W - np.abs(xx - az)), (yy - ey) * 1.0)
        rad = 9 if time != 'night' else 7
        glow = np.exp(-d / (60 if time in ('dawn', 'dusk') else 26)) * (1 - oc * 0.85)
        col = col + np.array(sun) * glow[..., None] * (0.55 if time != 'night' else 0.25)
        if el > 0:
            disc = d < rad
            if oc < 0.5:
                col[disc] = np.array(sun)
    top_half = np.clip(col, 0, 255)
    img = np.concatenate([top_half, top_half[::-1]], axis=0)     # 지평선 아래는 위와 거울 (방향이 뒤집혀도 같게)
    Image.fromarray(img.astype(np.uint8)).save(os.path.join(OUT, 'sky', f'sky_{time}_{cond}.png'), optimize=True)


def cloud(i):
    W = 512
    n = noise(2.2, size=W, seed=40 + i)
    yy, xx = np.mgrid[0:W, 0:W]
    d = np.hypot((xx - W / 2) / (W / 2), (yy - W / 2) / (W / 2.6))
    mask = np.clip(1 - d, 0, 1) ** 0.8
    a = np.clip((n * 1.3 - 0.35) * mask * 2.2, 0, 1)
    shade_ = 0.75 + 0.25 * noise(1.5, size=W, seed=50 + i)
    rgb = np.stack([shade_ * 255] * 3, axis=-1)
    im = np.concatenate([rgb, (a * 255)[..., None]], axis=-1).astype(np.uint8)
    Image.fromarray(im, 'RGBA').filter(ImageFilter.GaussianBlur(2)).save(os.path.join(OUT, 'sky', f'cloud_{i}.png'), optimize=True)


if __name__ == '__main__':
    os.makedirs(os.path.join(OUT, 'sky'), exist_ok=True)
    grass(); moss(); dirt(); pebble(); sand(); asphalt()
    planks('planks', [(0, (98, 66, 40)), (0.5, (142, 100, 62)), (1, (182, 136, 92))])
    marble()
    rock('rock', [(0, (66, 64, 60)), (0.5, (112, 108, 100)), (1, (160, 154, 144))])
    rock('cliff', [(0, (92, 70, 54)), (0.5, (146, 114, 86)), (1, (194, 162, 124))], layered=True, seed=15)
    rock('basalt', [(0, (30, 32, 36)), (0.5, (58, 60, 64)), (1, (96, 98, 100))], seed=19)
    stonewall(); brick(); facade(); facade(night=True); plaster(); timber(); forest(); bark(); hay(); concrete()
    for t in SKY:
        for c in COND:
            sky(t, c)
    for i in range(3):
        cloud(i)
    print('ok')
