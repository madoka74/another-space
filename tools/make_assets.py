"""어나더 스페이스 그림 재료 만들기 — 빌드(GitHub Actions)할 때마다 새로 만들어 앱에 담음
- tex/  : 바닥·벽·물건 무늬(jpg, 반복), 담장·울타리(png, 위가 뚫림), 나무(png), 지평선 띠(png), 물·그림 등
- sky/  : 하늘 (시간 5 × 날씨 4, 2048×512 jpg — 맨 위 줄 = 하늘 꼭대기, 맨 아래 줄 = 지평선)
          구름은 '하늘 높이의 평면'에 그려 원근이 맞게(지평선 쪽으로 납작하게 모임) 굽고, 해 쪽은 밝게 비춤
- sfx/  : 효과음 (열쇠 문 나타남·열쇠 돌림·문 열림·탐험 시작 스캔), 48kHz 모노 wav
사용: python3 tools/make_assets.py   →  ios/AnotherSpace/Resources/{tex,sky,sfx}/"""
import os, sys, math
import numpy as np
from PIL import Image, ImageFilter, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'ios', 'AnotherSpace', 'Resources')
SUN_AZ = 135.0          # 해·달 방위 (앱의 Worlds.sunDir 와 같아야 함)


# ───────────── 공통 ─────────────
def rng(seed):
    return np.random.default_rng(seed)


def noise(beta=2.0, size=512, seed=0, aniso=(1.0, 1.0), h=None, lowcut=0):
    """가장자리가 이어지는 잡음 (1/f^beta). 0~1. h를 주면 size×h"""
    hh = h or size
    w = rng(seed).standard_normal((hh, size))
    f = np.fft.fft2(w)
    ky = np.fft.fftfreq(hh)[:, None] * aniso[1] * (size / hh)
    kx = np.fft.fftfreq(size)[None, :] * aniso[0]
    k = np.sqrt(kx ** 2 + ky ** 2)
    k[0, 0] = 1
    f = f / k ** (beta / 2)
    f[0, 0] = 0
    if lowcut:
        f[k < lowcut / size] = 0          # 너무 큰 덩어리(한쪽에 몰림)는 뺌
    v = np.real(np.fft.ifft2(f))
    return (v - v.min()) / (v.max() - v.min() + 1e-9)


def noise1(n, beta=2.0, seed=0):
    """이어지는 1차원 잡음 (길이 n), 0~1"""
    w = rng(seed).standard_normal(n)
    f = np.fft.rfft(w)
    k = np.fft.rfftfreq(n)
    k[0] = 1
    f = f / k ** (beta / 2)
    f[0] = 0
    v = np.fft.irfft(f, n)
    return (v - v.min()) / (v.max() - v.min() + 1e-9)


def colorize(v, stops):
    out = np.zeros(v.shape + (3,))
    xs = [s[0] for s in stops]
    for c in range(3):
        out[..., c] = np.interp(v, xs, [s[1][c] for s in stops])
    return out


def lerp(a, b, t):
    t = np.asarray(t, dtype=float)
    if t.ndim and np.ndim(a) and np.shape(a)[-1:] == (3,):
        t = t[..., None]
    return a * (1 - t) + b * t


def smooth(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def save_jpg(name, rgb, folder='tex', q=88):
    os.makedirs(os.path.join(OUT, folder), exist_ok=True)
    Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8)).save(os.path.join(OUT, folder, name + '.jpg'), quality=q, optimize=True)


def save_png(name, rgb, alpha, folder='tex'):
    """투명 그림. 투명한 곳의 색은 가까운 불투명 색으로 채워 둠 (가장자리에 검은 테가 안 생기게)"""
    os.makedirs(os.path.join(OUT, folder), exist_ok=True)
    rgb = np.clip(rgb, 0, 255)
    a = np.clip(alpha, 0, 1)
    fill = rgb.copy()
    m = a > 0.5
    if m.any() and (~m).any():
        avg = rgb[m].mean(axis=0)
        cur = np.where(m[..., None], rgb, 0.0)
        wgt = m.astype(float)
        for _ in range(6):        # 불투명 색을 바깥으로 번지게
            img = Image.fromarray(np.clip(cur, 0, 255).astype(np.uint8))
            wim = Image.fromarray((wgt * 255).astype(np.uint8))
            cb = np.asarray(img.filter(ImageFilter.BoxBlur(4))).astype(float)
            wb = np.asarray(wim.filter(ImageFilter.BoxBlur(4))).astype(float) / 255
            nm = (wgt == 0) & (wb > 0.01)
            cur[nm] = cb[nm] / np.maximum(wb[nm][:, None], 1e-3)
            wgt = np.where(nm, 1.0, wgt)
        cur[wgt == 0] = avg
        fill = np.where(m[..., None], rgb, cur)
    im = np.concatenate([fill, (a * 255)[..., None]], axis=-1).astype(np.uint8)
    Image.fromarray(im, 'RGBA').save(os.path.join(OUT, folder, name + '.png'), optimize=True)
    # 오려 내기용 가림 그림 (흰색 = 보임). 앱의 재질은 투명도를 이 그림에서 읽음
    Image.fromarray((a * 255).astype(np.uint8), 'L').save(os.path.join(OUT, folder, name + '_a.png'), optimize=True)


def shade(rgb, k):
    return rgb * np.asarray(k)[..., None]


def voronoi(N, cells, seed, Hh=None):
    """이어지는 보로노이: (가까운 점 거리, 두 번째 거리, 점 번호)"""
    Hh = Hh or N
    r = rng(seed)
    pts = r.random((cells, 2)) * [N, Hh]
    yy, xx = np.mgrid[0:Hh, 0:N].astype(np.float32)
    d1 = np.full((Hh, N), 1e9, np.float32); d2 = d1.copy(); idx = np.zeros((Hh, N), int)
    for i, (px, py) in enumerate(pts):
        dx = np.abs(xx - px); dx = np.minimum(dx, N - dx)
        dy = np.abs(yy - py); dy = np.minimum(dy, Hh - dy)
        d = np.hypot(dx, dy)
        closer = d < d1
        d2 = np.where(closer, d1, np.minimum(d2, d))
        idx = np.where(closer, i, idx)
        d1 = np.where(closer, d, d1)
    return d1, d2, idx


def bilinear(tex, x, y):
    """이어지는 그림을 0~1 좌표로 부드럽게 읽기"""
    N = tex.shape[0]
    fx = (x * N) % N; fy = (y * N) % N
    x0 = np.floor(fx).astype(int); y0 = np.floor(fy).astype(int)
    tx = fx - x0; ty = fy - y0
    x1 = (x0 + 1) % N; y1 = (y0 + 1) % N
    return (tex[y0, x0] * (1 - tx) * (1 - ty) + tex[y0, x1] * tx * (1 - ty) +
            tex[y1, x0] * (1 - tx) * ty + tex[y1, x1] * tx * ty)


# ───────────── 하늘 ─────────────
# 시간: 꼭대기, 중간, 지평선, 해 고도, 해 색, 빛무리 크기, 별
SKY = {
    'dawn':      dict(top=(14, 20, 58), mid=(88, 72, 138), hor=(255, 168, 138), el=1.5, sun=(255, 196, 150), glow=26, stars=0.45,
                      lit=(255, 176, 160), dark=(78, 70, 116), ocol=(108, 100, 130)),
    'morning':   dict(top=(58, 118, 204), mid=(118, 166, 226), hor=(246, 226, 196), el=20, sun=(255, 242, 214), glow=12, stars=0,
                      lit=(255, 246, 228), dark=(142, 150, 172), ocol=(168, 172, 182)),
    'afternoon': dict(top=(30, 88, 190), mid=(86, 148, 226), hor=(198, 222, 244), el=58, sun=(255, 253, 244), glow=8, stars=0,
                      lit=(255, 255, 255), dark=(150, 162, 182), ocol=(176, 182, 192)),
    'dusk':      dict(top=(30, 30, 86), mid=(160, 70, 112), hor=(255, 118, 40), el=2.5, sun=(255, 150, 60), glow=30, stars=0.12,
                      lit=(255, 136, 76), dark=(70, 44, 82), ocol=(118, 82, 96)),
    'night':     dict(top=(3, 5, 16), mid=(8, 14, 36), hor=(26, 38, 70), el=34, sun=(226, 232, 255), glow=6, stars=1.0,
                      lit=(70, 78, 104), dark=(14, 17, 28), ocol=(24, 28, 40)),
}
CONDS = ('clear', 'cloudy', 'overcast', 'storm')
SW, SH = 2048, 512


_BLUR = {}


def _cloud_blur(tex):
    k = id(tex)
    if k not in _BLUR:
        im = Image.fromarray((np.clip(tex, 0, 1) * 255).astype(np.uint8))
        _BLUR[k] = np.asarray(im.filter(ImageFilter.GaussianBlur(5))).astype(np.float32) / 255
    return _BLUR[k]


def sky(time, cond, cloud_tex):
    P = SKY[time]
    yy, xx = np.mgrid[0:SH, 0:SW].astype(np.float32)
    el = (1 - (yy + 0.5) / SH) * 90.0                      # 고도(°)
    az = (xx + 0.5) / SW * 360.0                           # 방위(°)
    e = el / 90.0
    top, mid, hor = (np.array(P[k], float) for k in ('top', 'mid', 'hor'))
    col = lerp(hor, mid, smooth(0.0, 0.32, e))
    col = lerp(col, top, smooth(0.22, 1.0, e))
    # 해 쪽과 반대쪽
    daz = np.abs(((az - SUN_AZ) + 180) % 360 - 180)
    sel = P['el']
    # 각거리
    a1, a2 = np.radians(el), np.radians(sel)
    cosd = np.sin(a1) * np.sin(a2) + np.cos(a1) * np.cos(a2) * np.cos(np.radians(daz))
    ang = np.degrees(np.arccos(np.clip(cosd, -1, 1)))
    sun = np.array(P['sun'], float)
    low = time in ('dawn', 'dusk')
    if low:
        # 해 쪽 지평선이 넓게 타오르고, 반대쪽은 푸른 그림자 띠
        band = np.exp(-(daz / 70) ** 2) * np.exp(-el / 14)
        col = col + (sun - col) * (band * 0.85)[..., None]
        anti = np.exp(-((180 - daz) / 80) ** 2) * np.exp(-((el - 4) / 6) ** 2)
        col = col * (1 - 0.35 * anti)[..., None] + np.array([60, 70, 130.0]) * (0.35 * anti)[..., None]
    if time == 'night':
        # 은하수 띠
        mw = np.exp(-((((az + el * 1.4) % 360) - 230) / 26) ** 2) * smooth(5, 40, el)
        n = noise(1.4, SW, 3, h=SH)
        col = col + np.array([60, 66, 92.0]) * (mw * (0.35 + 0.65 * n) * 0.55)[..., None]
    glow = np.exp(-ang / P['glow']) * (0.9 if time != 'night' else 0.35)
    halo = np.exp(-ang / (P['glow'] * 5)) * (0.25 if time != 'night' else 0.1)
    col = col + sun[None, None, :] * (glow + halo)[..., None] * 0.6

    # 구름: 높이 1의 평면에 그린 잡음을 원근으로 (지평선 쪽은 납작하고 촘촘)
    cov = {'clear': 0.0, 'cloudy': 0.5, 'overcast': 0.9, 'storm': 1.0}[cond]
    cloud_a = np.zeros_like(el)
    if cov > 0:
        t = np.tan(np.radians(np.maximum(el, 0.6)))
        dist = 1.0 / t
        dist = np.minimum(dist, 40)                      # (지평선 몇 줄은 같은 값이 되므로 아래에서 옅게 지움)
        px = dist * np.cos(np.radians(az)) * 0.11
        pz = dist * np.sin(np.radians(az)) * 0.11
        # 먼 구름(지평선 쪽)은 흐린 무늬로 읽어 자글자글한 점무늬가 안 생기게 (거리에 따라 섞음)
        blur = _cloud_blur(cloud_tex)
        far = np.clip((dist - 3.0) / 12.0, 0, 1)
        n = bilinear(cloud_tex, px, pz) * (1 - far) + bilinear(blur, px, pz) * far
        # 해 쪽으로 조금 옮겨 읽어 그늘 계산 (해 쪽이 밝음)
        sx = np.cos(np.radians(SUN_AZ)) * 0.006
        sz = np.sin(np.radians(SUN_AZ)) * 0.006
        n2 = bilinear(cloud_tex, px + sx, pz + sz) * (1 - far) + bilinear(blur, px + sx, pz + sz) * far
        thr, soft = {'cloudy': (0.5, 0.16), 'overcast': (0.2, 0.5), 'storm': (0.15, 0.45)}[cond]
        dens = np.clip((n - thr) / soft, 0, 1)
        lightk = np.clip(0.55 + (n - n2) * (14 if cond == 'cloudy' else 6), 0, 1)
        lit, dark = np.array(P['lit'], float), np.array(P['dark'], float)
        if cond == 'storm':
            lit = lit * 0.42; dark = dark * 0.38
        elif cond == 'overcast':
            lit = lerp(lit, np.array(P['ocol'], float), 0.55); dark = dark * 0.8
        ccol = lerp(dark, lit, lightk)
        # 해 가까이 구름 가장자리가 빛남
        rim = np.exp(-ang / (P['glow'] * 2.5)) * (1 - dens) * dens * 4
        ccol = ccol + sun[None, None, :] * np.clip(rim, 0, 1)[..., None] * (0.7 if cond == 'cloudy' else 0.25)
        # 지평선 근처는 구름을 지우고 안개로 (아주 납작해진 구름이 세로 줄무늬처럼 늘어나 보이던 것)
        hz = smooth(1.2, 10.0, el)
        cloud_a = dens * hz
        if cond in ('overcast', 'storm'):
            base = np.array(P['ocol'], float) * (0.45 if cond == 'storm' else 0.9)
            col = lerp(col, base, 0.82 if cond == 'storm' else 0.62)
        col = lerp(col, ccol, cloud_a)
    # 지평선 안개: 지평선 가까이(0~6°)는 지평선 색으로 부드럽게 (바다·평원과 하늘이 매끈하게 만나게)
    hazek = smooth(6.0, 0.0, el) * (0.55 if cond in ('clear', 'cloudy') else 0.75)
    hcol = hor * 1.05 + (sun * 0.25 if low and cond in ('clear', 'cloudy') else 0)
    if cond == 'storm':
        hcol = hcol * 0.55
    col = lerp(col, np.clip(hcol, 0, 255), hazek)
    # 별 (구름 뒤로 가려짐)
    if P['stars'] > 0 and cond != 'storm':
        r = rng(31)
        k = int(5200 * P['stars'])
        ys = (r.random(k) ** 1.25 * SH * 0.94).astype(int)
        xs = r.integers(0, SW, k)
        b = (r.random(k) ** 3.2) * P['stars']
        star = np.zeros((SH, SW))
        np.maximum.at(star, (ys, xs), b)
        star = star * (1 - np.clip(cloud_a * 1.6, 0, 1)) * smooth(2, 20, el)
        col = col + 255 * star[..., None] * np.array([0.95, 0.97, 1.0])
    # 해·달 원반
    if cond in ('clear', 'cloudy') and sel > 0:
        rad = 0.85 if time != 'night' else 1.1
        disc = smooth(rad, rad * 0.75, ang)
        if time == 'night':
            n = noise(2.0, 256, 9)
            crater = n[(yy.astype(int)) % 256, (xx.astype(int)) % 256]
            dcol = np.array([232, 236, 248.0]) * (0.82 + 0.18 * crater)[..., None]
        else:
            dcol = np.array([255, 255, 248.0]) if not low else sun * 1.15
        vis = disc * (1 - np.clip(cloud_a * 1.3, 0, 1))
        col = lerp(col, dcol, vis)
    return np.clip(col, 0, 255)


def skies():
    cloud_tex = noise(2.6, 1024, 77, lowcut=6) * 0.6 + noise(2.0, 1024, 78, lowcut=6) * 0.4
    for t in SKY:
        for c in CONDS:
            save_jpg(f'sky_{t}_{c}', sky(t, c, cloud_tex), folder='sky', q=86)


def cloud_sprites():
    """하늘을 천천히 흐르는 구름 한 장 (투명, 아래쪽이 조금 어두움)"""
    W = 512
    for i in range(3):
        n = noise(2.1, W, 40 + i)
        yy, xx = np.mgrid[0:W, 0:W]
        d = np.hypot((xx - W / 2) / (W / 2), (yy - W / 2) / (W / 2.4))
        mask = np.clip(1 - d, 0, 1) ** 0.7
        a = np.clip((n * 1.35 - 0.4) * mask * 2.6, 0, 1)
        s = 0.72 + 0.28 * noise(1.4, W, 50 + i)
        rgb = np.stack([s * 255] * 3, axis=-1)
        a = np.asarray(Image.fromarray((a * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2))) / 255
        save_png(f'cloud_{i}', rgb, a, folder='sky')


# ───────────── 지평선 띠 (원기둥에 둘러 붙임, 위는 투명) ─────────────
def ridge(W, seed, base, amp, beta=2.2, sharp=0.0):
    """윗선 높이 (0=그림 맨 위, 1=맨 아래) — x마다"""
    v = noise1(W, beta, seed)
    if sharp:
        v = v ** (1 + sharp)
    return np.clip(base - amp * (v - 0.5) * 2, 0.02, 0.98)


def band_far_mountains(name, seed, col, snow=False):
    W, H = 2048, 512
    top = ridge(W, seed, 0.55, 0.42, beta=2.4)
    top2 = ridge(W, seed + 1, 0.72, 0.22, beta=2.0)
    yy = np.mgrid[0:H, 0:W][0] / H
    a = (yy >= top[None, :]).astype(float)
    a2 = (yy >= top2[None, :])
    n = noise(1.8, W, seed + 2, h=H)
    base = np.array(col, float)
    rgb = base * (0.92 + 0.12 * n)[..., None]
    # 해 쪽 비탈이 밝게 (능선 기울기를 부드럽게 해서), 위쪽일수록 옅게
    sm = np.convolve(np.concatenate([top[-40:], top, top[:40]]), np.ones(41) / 41, 'same')[40:-40]
    slope = np.gradient(sm)[None, :] * W * 0.02
    depth = np.clip((yy - top[None, :]) * 4, 0, 1)
    rgb = rgb * (1 + np.clip(slope, -0.15, 0.15) * (1 - depth) * 1.5)[..., None]
    rgb = rgb * (1.04 - 0.1 * depth)[..., None]
    if snow:
        depth = yy - top[None, :]
        s = (depth < 0.08 + 0.06 * n) & (top[None, :] < 0.45)
        rgb[s] = lerp(rgb[s], np.array([250, 252, 255.0]), 0.85)
    rgb[a2] = rgb[a2] * 0.86          # 앞 능선은 조금 진하게
    save_png(name, rgb, a)


def tree_line(W, H, seed, count, hmin, hmax, kind, col_dark, col_lit, ground=0.97):
    """나무 줄 (윤곽 + 잎 질감 + 나무마다 해 쪽이 밝은 입체감). kind: pine / broad"""
    r = rng(seed)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    a = np.zeros((H, W))
    light = np.zeros((H, W))
    depth = np.zeros((H, W))        # 0 뒤 → 1 앞 (앞 나무일수록 진함)
    leaf = noise(0.8, W, seed + 3, h=H)
    order = np.sort(r.random(count))
    for d in order:
        cx = r.random() * W
        h = r.uniform(hmin, hmax) * H * (0.8 + 0.25 * d)
        top = ground * H - h
        w = h * (0.3 if kind == 'pine' else 0.5) * r.uniform(0.8, 1.2)
        x0 = int(cx - w * 1.1); x1 = int(cx + w * 1.1) + 1
        xs = np.arange(x0, x1) % W
        sub_x = (np.arange(x0, x1) - cx)[None, :]
        sub_y = yy[:, :1]
        lf = leaf[:, xs]
        if kind == 'pine':
            t = (sub_y - top) / h                                   # 0 꼭대기 → 1 밑
            tiers = 0.6 + 0.4 * ((t * 8 + lf * 0.6) % 1)            # 가지 층 톱니
            half = np.clip(t, 0, 1) * w * tiers * (0.8 + 0.4 * lf)
            crown = (t >= 0) & (t <= 0.86) & (np.abs(sub_x) <= half)
            lk = 0.55 - 0.45 * sub_x / np.maximum(half, 1) + 0.25 * ((t * 8) % 1) - 0.2 * t
        else:
            # 잎 덩어리 여러 개가 모인 수관
            crown = np.zeros((H, len(xs)), bool)
            lk = np.zeros((H, len(xs)))
            for _ in range(6):
                bx = r.uniform(-0.55, 0.55) * w; by = top + h * r.uniform(0.12, 0.45)
                br = h * r.uniform(0.13, 0.22)
                nx = (sub_x - bx) / br; ny = (sub_y - by) / br
                dd = np.hypot(nx, ny)
                blob = dd < (0.8 + 0.4 * lf)
                bl = 0.62 - 0.3 * nx - 0.45 * ny + 0.35 * (lf - 0.5)
                lk = np.where(blob & ~crown, bl, np.where(blob, np.maximum(lk, bl * 0.9), lk))
                crown |= blob
        trunk = (sub_y > top + h * (0.75 if kind == 'pine' else 0.55)) & (np.abs(sub_x) < max(2, w * 0.07)) & (sub_y < ground * H)
        m = crown | trunk
        lk = np.where(trunk & ~crown, 0.15 - 0.3 * sub_x / max(2, w * 0.07) * 0.3, lk)
        a[:, xs] = np.where(m, 1, a[:, xs])
        light[:, xs] = np.where(m, np.clip(lk, 0, 1), light[:, xs])
        depth[:, xs] = np.where(m, d, depth[:, xs])
    # 아래쪽 덤불 (사이로 하늘이 안 보이게)
    bush = ground * H - (0.08 + 0.1 * noise1(W, 1.6, seed + 9)) * H
    under = yy >= bush[None, :]
    a[under] = 1
    light[under] = 0.25 + 0.3 * leaf[under]
    depth[under] = 1
    tex = noise(0.6, W, seed + 5, h=H)
    k = np.clip(light * 0.75 + 0.25 * tex, 0, 1) * (1 - 0.35 * depth)
    rgb = lerp(np.array(col_dark, float), np.array(col_lit, float), k)
    trunkish = (light < 0.2) & (a > 0)
    rgb[trunkish] = lerp(rgb[trunkish], np.array([40, 30, 24.0]), 0.5)
    return rgb, a


def band_trees(name, seed, kind, H=1024, count=90, hmin=0.45, hmax=0.92, dark=(18, 34, 26), lit=(70, 104, 64)):
    rgb, a = tree_line(2048, H, seed, count, hmin, hmax, kind, dark, lit)
    save_png(name, rgb, a)


def band_ridge_pines(name, seed, col):
    """먼 능선 + 위에 바늘처럼 솟은 소나무들"""
    W, H = 2048, 512
    top = ridge(W, seed, 0.62, 0.28, beta=2.6)
    r = rng(seed + 1)
    spikes = np.zeros(W)
    for _ in range(700):
        cx = r.random() * W; h = r.uniform(0.04, 0.12); w = r.uniform(2, 5)
        xs = np.arange(int(cx - w), int(cx + w) + 1)
        v = h * (1 - np.abs(xs - cx) / w)
        spikes[xs % W] = np.maximum(spikes[xs % W], v)
    top = np.clip(top - spikes, 0.02, 0.98)
    yy = np.mgrid[0:H, 0:W][0] / H
    a = (yy >= top[None, :]).astype(float)
    n = noise(1.2, W, seed + 2, h=H)
    rgb = np.array(col, float) * (0.85 + 0.25 * n)[..., None]
    save_png(name, rgb, a)


def band_cliffs(name, seed, H=1024):
    W = 2048
    top = ridge(W, seed, 0.3, 0.26, beta=1.8)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    a = (yy / H >= top[None, :]).astype(float)
    warp = noise(2.8, W, seed + 3, h=H) * 9
    strata = np.sin(yy / H * 2 * np.pi * 9 + warp) * 0.5 + 0.5
    big = noise(3.0, W, seed + 4, h=H)
    fine = noise(1.3, W, seed + 5, h=H)
    base = 0.5 * big + 0.2 * fine + 0.3 * strata
    rgb = colorize(base, [(0, (84, 70, 58)), (0.45, (140, 116, 92)), (0.8, (184, 160, 128)), (1, (206, 186, 154))])
    # 큰 바위 기둥: 해 쪽 면은 밝고 반대는 그늘
    cols = noise1(W, 2.2, seed + 6)
    g = np.gradient(np.convolve(np.concatenate([cols[-40:], cols, cols[:40]]), np.ones(61) / 61, 'same')[40:-40]) * W * 0.03
    rgb = rgb * (0.94 + np.clip(g, -0.14, 0.14))[None, :, None]
    cracks = np.abs(noise(1.6, W, seed + 7, h=H, aniso=(1, 0.25)) - 0.5) < 0.008
    rgb[cracks] *= 0.55
    # 꼭대기 근처에 풀·작은 나무
    depth = yy / H - top[None, :]
    grass = (depth < 0.03 + 0.03 * fine) & (a > 0)
    rgb[grass] = lerp(rgb[grass], np.array([70, 92, 50.0]), 0.75)
    save_png(name, rgb, a)


def band_village(name, seed, night=False):
    W, H = 2048, 512
    top = ridge(W, seed, 0.6, 0.25, beta=3.0)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    a = (yy / H >= top[None, :]).astype(float)
    # 밭: 언덕을 따라 기운 줄무늬 조각
    d1, d2, idx = voronoi(W, 120, seed + 1, Hh=H)
    tones = rng(seed + 2).random(120)[idx]
    fields = colorize(tones, [(0, (70, 104, 46)), (0.4, (112, 140, 58)), (0.7, (168, 160, 84)), (1, (190, 170, 100))])
    rows = np.sin((xx * 0.6 + yy * 2.4) * 0.25 + idx) * 0.5 + 0.5
    rgb = fields * (0.85 + 0.15 * rows)[..., None]
    rgb[(d2 - d1) < 1.5] *= 0.75                                 # 밭둑
    # 집: 언덕 위 작은 집들 (벽 + 기와 지붕), 밤엔 창에 불
    r = rng(seed + 3)
    for _ in range(46):
        cx = int(r.random() * W)
        gy = int(top[cx] * H + r.uniform(8, 110))
        w = int(r.uniform(14, 30)); h = int(w * 0.55)
        x0, x1 = cx - w // 2, cx + w // 2
        xs = np.arange(x0, x1) % W
        y0 = max(0, gy - h)
        rgb[y0:gy, xs] = [200, 190, 172] if not night else [70, 64, 60]
        a[y0:gy, xs] = 1
        # 지붕 (처마가 살짝 튀어나온 사다리꼴)
        rh = int(h * 0.7)
        for k in range(rh):
            yv = y0 - rh + k
            if yv < 0:
                continue
            ext = int((k / rh) * 4)
            ra = np.arange(x0 - ext, x1 + ext) % W
            rgb[yv, ra] = [62, 60, 66]
            a[yv, ra] = 1
        if night:
            for wx in range(x0 + 3, x1 - 3, 6):
                if r.random() < 0.7:
                    rgb[gy - h + 3:gy - 3, np.arange(wx, wx + 3) % W] = [255, 200, 120]
    if night:
        lit = (rgb[..., 0] > 250) & (rgb[..., 2] < 130)
        rgb = rgb * np.array([0.32, 0.36, 0.5])
        rgb[lit] = [255, 205, 128]
    save_png(name, rgb, a)


def band_city(name, seed, night=False, H=1024):
    W = 2048
    r = rng(seed)
    rgb = np.zeros((H, W, 3)); a = np.zeros((H, W))
    yy, xx = np.mgrid[0:H, 0:W]
    for layer in range(2):      # 0 뒤(옅게), 1 앞
        x = 0
        while x < W:
            w = int(r.uniform(30, 110)); h = int(r.uniform(0.15, 0.85 if layer == 0 else 0.6) * H)
            xs = np.arange(x, x + w) % W
            y0 = H - h
            base = np.array([118, 128, 146.0]) if layer == 0 else np.array([86, 92, 106.0])
            base = base * r.uniform(0.8, 1.15)
            if night:
                base = base * 0.3
            rgb[y0:, xs] = base
            a[y0:, xs] = 1
            # 창: 격자
            cw, chh = int(r.uniform(6, 10)), int(r.uniform(9, 14))
            sub_y = np.arange(y0, H)[:, None]; sub_x = np.arange(x, x + w)[None, :]
            win = ((sub_x - x) % cw > 2) & ((sub_y - y0) % chh > 3) & ((sub_x - x) > 2) & ((x + w - sub_x) > 2)
            if night:
                on = rng(seed * 7 + x).random(((H - y0) // chh + 1, w // cw + 1))
                lit = on[(sub_y - y0) // chh, (sub_x - x) // cw] > 0.55
                wc = np.where((win & lit)[..., None], np.array([255, 208, 140.0]) * (0.75 + 0.25 * layer), base * 0.6)
            else:
                wc = np.where(win[..., None], base * 0.75 + np.array([40, 50, 70.0]), base)
            rgb[y0:, xs] = np.where(win[..., None], wc, rgb[y0:, xs])
            # 옥상 안테나
            if r.random() < 0.25 and y0 > 30:
                ax = (x + w // 2) % W
                rgb[y0 - 26:y0, ax] = base; a[y0 - 26:y0, ax] = 1
            x += w + int(r.uniform(-10, 14))
    if not night:
        rgb = rgb * (0.9 + 0.1 * noise(1.0, W, seed + 3, h=H))[..., None]
    save_png(name, rgb, a)


def band_islands(name, seed):
    W, H = 2048, 256
    r = rng(seed)
    top = np.ones(W)
    for _ in range(5):
        cx = r.random() * W; w = r.uniform(60, 220); h = r.uniform(0.2, 0.7)
        xs = np.arange(int(cx - w), int(cx + w))
        v = 1 - h * np.sqrt(np.clip(1 - ((xs - cx) / w) ** 2, 0, 1)) * (0.8 + 0.2 * noise1(len(xs), 2, int(cx)))
        top[xs % W] = np.minimum(top[xs % W], v)
    yy = np.mgrid[0:H, 0:W][0] / H
    a = (yy >= top[None, :]).astype(float) * (yy < 0.995)
    rgb = np.ones((H, W, 3)) * np.array([150, 166, 180.0]) * (0.9 + 0.15 * noise(1.5, W, seed, h=H))[..., None]
    save_png(name, rgb, a)


# ───────────── 담장·울타리 (벽 바로 뒤에 둘러 세움, 1024×512, 가로로 이어짐) ─────────────
BW, BH = 1024, 512


def grass_tufts(seed, base_y, hmin, hmax, col_dark, col_lit, count=900):
    """풀·덤불 포기 (아래에서 위로 솟은 잎). 높이 맵(0=위)과 색"""
    r = rng(seed)
    yy, xx = np.mgrid[0:BH, 0:BW].astype(np.float32)
    a = np.zeros((BH, BW)); k = np.zeros((BH, BW))
    for _ in range(count):
        cx = r.random() * BW; h = r.uniform(hmin, hmax) * BH; lean = r.uniform(-0.5, 0.5)
        w = r.uniform(2, 5)
        y0 = int(base_y * BH - h)
        ys = np.arange(max(0, y0), min(BH, int(base_y * BH)))
        if len(ys) == 0:
            continue
        t = (base_y * BH - ys) / h                      # 1 끝 → 0 밑
        xc = cx + lean * h * t ** 1.5
        width = w * (1 - np.clip(t, 0, 1)) + 0.6
        for yi, y in enumerate(ys):
            x0 = int(xc[yi] - width[yi]); x1 = int(xc[yi] + width[yi]) + 1
            xsel = np.arange(x0, x1) % BW
            a[y, xsel] = 1
            k[y, xsel] = np.maximum(k[y, xsel], 0.3 + 0.7 * np.clip(t[yi], 0, 1))
    rgb = lerp(np.array(col_dark, float), np.array(col_lit, float), k * (0.75 + 0.25 * noise(0.8, BW, seed + 1, h=BH)))
    return rgb, a


def bushes(seed, base_y, hmin, hmax, col_dark, col_lit, count=40):
    r = rng(seed)
    yy, xx = np.mgrid[0:BH, 0:BW].astype(np.float32)
    a = np.zeros((BH, BW)); light = np.zeros((BH, BW))
    lf = noise(0.7, BW, seed + 2, h=BH)
    for _ in range(count):
        cx = r.random() * BW; rr = r.uniform(hmin, hmax) * BH
        cy = base_y * BH - rr * 0.55
        dx = np.minimum(np.abs(xx - cx), BW - np.abs(xx - cx)) * np.sign(xx - cx)
        nx = dx / (rr * 1.3); ny = (yy - cy) / rr
        blob = (np.hypot(nx, ny) < 0.85 + 0.35 * lf) & (yy < base_y * BH + 4)
        bl = 0.6 - 0.3 * nx - 0.5 * ny + 0.3 * (lf - 0.5)
        light = np.where(blob, np.clip(bl, 0, 1), light)
        a = np.where(blob, 1, a)
    rgb = lerp(np.array(col_dark, float), np.array(col_lit, float), light)
    return rgb, a


def over(dst_rgb, dst_a, src_rgb, src_a):
    m = src_a > 0.5
    dst_rgb[m] = src_rgb[m]
    return dst_rgb, np.maximum(dst_a, src_a)


def wood(seed, H=BH, W=BW, dark=(70, 50, 34), lit=(150, 116, 80), vertical=False):
    g = noise(1.6, W, seed, h=H, aniso=(0.12, 3.0) if not vertical else (3.0, 0.12))
    return colorize(g, [(0, dark), (1, lit)])


def barrier_camp():
    """통나무 울타리 + 앞의 덤불·풀 (높이 1.3m 기준)"""
    yy, xx = np.mgrid[0:BH, 0:BW]
    rgb = np.zeros((BH, BW, 3)); a = np.zeros((BH, BW))
    # 뒤 덤불
    b_rgb, b_a = bushes(201, 0.98, 0.18, 0.32, (24, 40, 22), (82, 112, 56), count=34)
    rgb, a = over(rgb, a, b_rgb, b_a)
    # 통나무 기둥 (2.5칸) + 가로대 2줄
    w = wood(202)
    wv = wood(203, vertical=True)
    posts = ((xx % 340) < 26) & (yy > BH * 0.18)
    round_p = np.clip(np.sin(np.clip((xx % 340) / 26, 0, 1) * np.pi), 0, 1) ** 0.5
    rails = [(0.32, 0.42), (0.6, 0.7)]
    for y0, y1 in rails:
        m = (yy > BH * y0 + 6 * np.sin(xx / 80)) & (yy < BH * y1 + 6 * np.sin(xx / 80))
        t = (yy - BH * y0) / (BH * (y1 - y0))
        rgb[m] = shade(w, 0.45 + 0.55 * np.sin(np.clip(t, 0, 1) * np.pi) ** 0.5)[m]; a[m] = 1
    rgb[posts] = shade(wv, 0.4 + 0.6 * round_p)[posts]; a[posts] = 1
    cap = posts & (yy < BH * 0.2 + 6)
    rgb[cap] = [176, 146, 104]
    # 앞 풀
    g_rgb, g_a = grass_tufts(204, 1.0, 0.08, 0.3, (40, 62, 28), (128, 160, 74), count=500)
    rgb, a = over(rgb, a, g_rgb, g_a)
    save_png('barrier_camp', rgb, a)


def barrier_forest():
    """고사리·덤불 (1.6m)"""
    rgb = np.zeros((BH, BW, 3)); a = np.zeros((BH, BW))
    b_rgb, b_a = bushes(211, 1.0, 0.3, 0.55, (14, 30, 16), (64, 98, 46), count=30)
    rgb, a = over(rgb, a, b_rgb, b_a)
    f_rgb, f_a = grass_tufts(212, 1.0, 0.25, 0.7, (22, 46, 22), (98, 140, 62), count=700)
    rgb, a = over(rgb, a, f_rgb, f_a)
    b2, a2 = bushes(213, 1.02, 0.15, 0.3, (20, 36, 18), (90, 120, 58), count=24)
    rgb, a = over(rgb, a, b2, a2)
    save_png('barrier_forest', rgb, a)


def barrier_valley():
    """들쭉날쭉한 바위 벽 (3m)"""
    yy, xx = np.mgrid[0:BH, 0:BW].astype(np.float32)
    top = 0.04 + 0.22 * noise1(BW, 1.9, 221)
    a = (yy / BH >= top[None, :]).astype(float)
    d1, d2, idx = voronoi(BW, 26, 222, Hh=BH)
    tone = rng(223).random(26)[idx]
    n = noise(1.5, BW, 224, h=BH)
    v = 0.35 * tone + 0.45 * noise(2.4, BW, 225, h=BH) + 0.2 * n
    rgb = colorize(v, [(0, (74, 66, 58)), (0.5, (128, 116, 100)), (1, (178, 166, 146))])
    edge = np.clip((d2 - d1) / 14, 0, 1)
    gx = np.gradient(d1, axis=1); gy = np.gradient(d1, axis=0)
    lightk = np.clip(0.75 - 0.25 * gx - 0.3 * gy, 0.4, 1.1)
    rgb = shade(rgb, (0.45 + 0.55 * edge ** 0.5) * lightk)
    moss = (noise(2.2, BW, 226, h=BH) > 0.7) & (yy / BH > 0.6)
    rgb[moss] = lerp(rgb[moss], np.array([70, 90, 50.0]), 0.5)
    save_png('barrier_valley', rgb, a)


def barrier_sea():
    """나무 난간 + 모래언덕 풀 (1.1m)"""
    yy, xx = np.mgrid[0:BH, 0:BW]
    rgb = np.zeros((BH, BW, 3)); a = np.zeros((BH, BW))
    g_rgb, g_a = grass_tufts(231, 1.0, 0.2, 0.55, (110, 104, 66), (196, 186, 128), count=600)
    rgb, a = over(rgb, a, g_rgb, g_a)
    w = wood(232, dark=(110, 104, 96), lit=(186, 178, 164))
    wv = wood(233, dark=(110, 104, 96), lit=(186, 178, 164), vertical=True)
    posts = ((xx % 256) < 22) & (yy > BH * 0.1)
    rail = (yy > BH * 0.08) & (yy < BH * 0.16)
    mid = (yy > BH * 0.45) & (yy < BH * 0.5)
    for m, tex in ((rail, w), (mid, w), (posts, wv)):
        rgb[m] = tex[m]; a[m] = 1
    save_png('barrier_sea', rgb, a)


def barrier_village():
    """돌담 + 위에 풀·꽃 (1.5m)"""
    yy, xx = np.mgrid[0:BH, 0:BW]
    rgb = np.zeros((BH, BW, 3)); a = np.zeros((BH, BW))
    d1, d2, idx = voronoi(BW, 70, 241, Hh=BH)
    tone = rng(242).random(70)[idx]
    v = 0.3 + 0.5 * tone + 0.2 * noise(0.9, BW, 243, h=BH)
    stone = colorize(v, [(0, (86, 80, 70)), (0.5, (138, 128, 110)), (1, (186, 176, 156))])
    stone = shade(stone, 0.35 + 0.65 * np.clip((d2 - d1) / 9, 0, 1) ** 0.6)
    top = 0.32 + 0.04 * noise1(BW, 2.2, 244)
    wall = yy / BH >= top[None, :]
    rgb[wall] = stone[wall]; a[wall] = 1
    g_rgb, g_a = grass_tufts(245, 0.36, 0.05, 0.2, (46, 70, 30), (124, 156, 70), count=400)
    rgb, a = over(rgb, a, g_rgb, g_a)
    r = rng(246)
    for _ in range(40):          # 꽃
        cx, cy = int(r.random() * BW), int(BH * r.uniform(0.18, 0.34))
        c = [(236, 220, 90), (240, 160, 180), (250, 250, 250), (200, 120, 220)][r.integers(0, 4)]
        rr = r.uniform(3, 6)
        m = (np.hypot(np.minimum(np.abs(xx - cx), BW - np.abs(xx - cx)), yy - cy) < rr)
        rgb[m] = c; a[m] = 1
    save_png('barrier_village', rgb, a)


def barrier_city():
    """옥상 난간: 콘크리트 턱 + 쇠 난간 (1.15m)"""
    yy, xx = np.mgrid[0:BH, 0:BW]
    rgb = np.zeros((BH, BW, 3)); a = np.zeros((BH, BW))
    con = colorize(0.6 * noise(0.5, BW, 251, h=BH) + 0.4 * noise(2.2, BW, 252, h=BH), [(0, (120, 118, 114)), (1, (176, 174, 168))])
    wall = yy > BH * 0.42
    rgb[wall] = con[wall]; a[wall] = 1
    lip = (yy > BH * 0.42) & (yy < BH * 0.47)
    rgb[lip] = con[lip] * 1.15
    joint = wall & ((xx % 256) < 3)
    rgb[joint] *= 0.7
    stain = wall & (noise(2.0, BW, 253, h=BH, aniso=(3, 0.3)) > 0.7)
    rgb[stain] *= 0.85
    metal = np.array([70, 74, 80.0])
    for m in (((yy > BH * 0.02) & (yy < BH * 0.05)), ((xx % 128) < 6) & (yy < BH * 0.42), ((yy > BH * 0.2) & (yy < BH * 0.22))):
        rgb[m] = metal * (0.9 + 0.2 * (xx[m] % 128 < 3)[:, None]); a[m] = 1
    save_png('barrier_city', rgb, a)


# ───────────── 나무 한 그루 (십자로 세워 씀, 512×1024) ─────────────
def tree_single(name, kind, seed, dark, lit):
    W, H = 512, 1024
    rgb, a = tree_line_single(W, H, seed, kind, dark, lit)
    save_png(name, rgb, a)


def tree_line_single(W, H, seed, kind, dark, lit):
    r = rng(seed)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    cx = W / 2
    lf = noise(0.9, W, seed + 1, h=H)
    a = np.zeros((H, W)); k = np.zeros((H, W))
    nx = (xx - cx)
    if kind == 'pine':
        top = H * 0.02; h = H * 0.96
        t = (yy - top) / h
        tiers = 0.55 + 0.45 * ((t * 9 + lf * 0.5) % 1)
        half = np.clip(t, 0, 1) * W * 0.47 * tiers * (0.8 + 0.4 * lf)
        crown = (t >= 0) & (t < 0.88) & (np.abs(nx) <= half)
        kk = 0.55 - 0.45 * nx / np.maximum(half, 1) + 0.3 * ((t * 9) % 1) - 0.25 * t
        trunk = (t > 0.6) & (np.abs(nx) < W * 0.035)
    elif kind == 'twisted':      # 바닷가 해송: 기운 줄기 + 납작한 잎 덩어리
        sway = (H - yy) / H
        cxs = cx + 60 * np.sin(sway * 2.4)
        trunk = (np.abs(xx - cxs) < 16 + 10 * (1 - sway)) & (yy > H * 0.3)
        crown = np.zeros((H, W), bool); kk = np.zeros((H, W))
        for i in range(13):
            by = H * r.uniform(0.06, 0.45); bx = cx + 60 * np.sin((H - by) / H * 2.4) + r.uniform(-160, 160)
            rx, ry = r.uniform(70, 140), r.uniform(30, 56)
            dd = np.hypot((xx - bx) / rx, (yy - by) / ry)
            blob = dd < 0.85 + 0.3 * lf
            bl = 0.6 - 0.25 * (xx - bx) / rx - 0.55 * (yy - by) / ry + 0.3 * (lf - 0.5)
            kk = np.where(blob, np.clip(bl, 0, 1), kk); crown |= blob
    else:
        crown = np.zeros((H, W), bool); kk = np.zeros((H, W))
        for i in range(22):
            bx = cx + r.uniform(-170, 170); by = H * r.uniform(0.1, 0.62); br = r.uniform(70, 125)
            dd = np.hypot((xx - bx) / br, (yy - by) / br)
            blob = dd < 0.8 + 0.35 * lf
            bl = 0.62 - 0.3 * (xx - bx) / br - 0.45 * (yy - by) / br + 0.3 * (lf - 0.5)
            kk = np.where(blob & ~crown, np.clip(bl, 0, 1), np.where(blob, np.maximum(kk, np.clip(bl, 0, 1) * 0.92), kk))
            crown |= blob
        trunk = (yy > H * 0.45) & (np.abs(xx - cx - 8 * np.sin(yy / 90)) < 20 + 10 * (yy / H - 0.45))
        for i in range(4):     # 가지
            y0 = H * r.uniform(0.42, 0.6); dirx = r.choice([-1, 1])
            t = (y0 - yy) / 140
            m = (t > 0) & (t < 1) & (np.abs(xx - (cx + dirx * t * 120)) < 6 * (1 - t) + 2)
            trunk |= m
    m = crown | trunk
    a[m] = 1
    bark = colorize(noise(1.4, W, seed + 3, h=H, aniso=(3, 0.2)), [(0, (46, 34, 26)), (1, (112, 88, 64))])
    bark = shade(bark, 0.5 + 0.5 * np.clip(0.6 - (xx - cx) / 30, 0, 1))
    tex = noise(0.6, W, seed + 4, h=H)
    leaf = lerp(np.array(dark, float), np.array(lit, float), np.clip(kk * 0.8 + tex * 0.25, 0, 1))
    rgb = np.where(crown[..., None], leaf, bark)
    return rgb, a


# ───────────── 바닥·벽·물건 무늬 (1024, jpg) ─────────────
N = 1024


def floor_grass():
    base = noise(2.4, N, 301); fine = noise(0.9, N, 302); blades = noise(1.1, N, 303, aniso=(5.0, 0.5))
    v = 0.45 * base + 0.2 * fine + 0.35 * blades
    rgb = colorize(v, [(0, (30, 52, 20)), (0.45, (62, 98, 36)), (0.75, (100, 136, 52)), (1, (150, 168, 82))])
    dirt = noise(2.8, N, 304) > 0.8
    rgb[dirt] = rgb[dirt] * 0.35 + np.array([104, 84, 56]) * 0.65
    flowers = noise(0.3, N, 305) > 0.985
    rgb[flowers] = [236, 230, 190]
    save_jpg('grass', rgb)


def floor_moss():
    v = 0.55 * noise(2.5, N, 311) + 0.45 * noise(1.0, N, 312)
    rgb = colorize(v, [(0, (26, 40, 20)), (0.5, (58, 88, 34)), (0.8, (92, 118, 48)), (1, (136, 146, 76))])
    d1, d2, idx = voronoi(N, 260, 313)
    leaves = (rng(314).random(260)[idx] > 0.55) & (d1 < 14) & (noise(1.8, N, 315) > 0.45)
    lc = colorize(rng(316).random(260)[idx], [(0, (110, 64, 30)), (0.5, (150, 98, 40)), (1, (182, 140, 60))])
    rgb[leaves] = lc[leaves] * (0.7 + 0.3 * np.clip(1 - d1[leaves] / 14, 0, 1))[:, None]
    roots = np.abs(noise(2.0, N, 317) - 0.5) < 0.01
    rgb[roots] = [70, 52, 36]
    save_jpg('moss', rgb)


def floor_pebble():
    d1, d2, idx = voronoi(N, 380, 321)
    tone = rng(322).random(380)[idx]
    v = 0.2 + 0.6 * tone + 0.2 * noise(0.9, N, 323)
    rgb = colorize(v, [(0, (74, 76, 78)), (0.4, (122, 118, 110)), (0.7, (164, 154, 138)), (1, (200, 194, 182))])
    edge = np.clip((d2 - d1) / 12, 0, 1)
    rgb = shade(rgb, 0.3 + 0.7 * edge ** 0.5)
    hl = np.clip(1 - d1 / 9, 0, 1) * 0.25
    rgb = rgb + 255 * hl[..., None] * 0.4
    save_jpg('pebble', rgb)


def floor_sand():
    yy = np.mgrid[0:N, 0:N][0]
    ripples = np.sin(yy / N * 2 * np.pi * 18 + noise(2.6, N, 331) * 9) * 0.5 + 0.5
    v = 0.5 * noise(0.5, N, 332) + 0.25 * noise(2.3, N, 333) + 0.25 * ripples
    rgb = colorize(v, [(0, (176, 154, 114)), (0.5, (212, 190, 150)), (1, (238, 224, 190))])
    r = rng(334)
    for _ in range(60):                         # 조개·조약돌
        cx, cy = r.integers(0, N, 2); rr = r.uniform(2, 5)
        yy2, xx2 = np.ogrid[0:N, 0:N]
        m = (xx2 - cx) ** 2 + (yy2 - cy) ** 2 < rr * rr
        rgb[m] = [236, 228, 214] if r.random() < 0.5 else [130, 120, 108]
    save_jpg('sand', rgb)


def floor_roof():
    """옥상 바닥: 큰 콘크리트 판석 (줄눈)"""
    yy, xx = np.mgrid[0:N, 0:N]
    v = 0.6 * noise(0.5, N, 341) + 0.4 * noise(2.2, N, 342)
    rgb = colorize(v, [(0, (104, 102, 98)), (1, (160, 156, 148))])
    cell = (yy // 256) * 4 + (xx // 256)
    tone = rng(343).random(16)[cell]
    rgb = rgb * (0.9 + 0.12 * tone)[..., None]
    joint = ((xx % 256) < 4) | ((yy % 256) < 4)
    rgb[joint] = rgb[joint] * 0.55
    save_jpg('roof', rgb)


def floor_dirt():
    v = 0.5 * noise(2.4, N, 351) + 0.3 * noise(0.8, N, 352) + 0.2 * noise(1.6, N, 353, aniso=(0.3, 3))
    rgb = colorize(v, [(0, (72, 54, 38)), (0.5, (122, 96, 66)), (1, (166, 140, 102))])
    straw = np.abs(noise(1.2, N, 354, aniso=(4, 0.3)) - 0.5) < 0.006
    rgb[straw] = [196, 170, 100]
    stones = noise(0.7, N, 355) > 0.93
    rgb[stones] = rgb[stones] * 0.6 + np.array([160, 150, 136]) * 0.4
    save_jpg('dirt', rgb)


def floor_planks(name, stops, rows=8, seed=361):
    r = rng(seed)
    yy, xx = np.mgrid[0:N, 0:N]
    h = N // rows
    row = yy // h
    grain = noise(1.8, N, seed, aniso=(0.12, 3.5))
    off = r.integers(0, N, rows)[row]
    L = N // 2
    seg = ((xx + off) % N) // L
    tone = (r.random((rows, 4))[row, seg] - 0.5) * 0.3
    knots = noise(2.2, N, seed + 1) > 0.86
    v = np.clip(0.5 + tone + (grain - 0.5) * 0.75, 0, 1)
    rgb = colorize(v, stops)
    rgb[knots] *= 0.8
    gap = ((yy % h) < 3) | (((xx + off) % L) < 3)
    rgb[gap] = rgb[gap] * 0.4
    bevel = ((yy % h) < 7) & ~gap
    rgb[bevel] = rgb[bevel] * 1.08
    save_jpg(name, rgb)


def floor_marble():
    xx = np.mgrid[0:N, 0:N][1]
    v = noise(2.2, N, 371)
    veins = np.abs(np.sin(xx / N * 2 * np.pi * 2 + noise(1.7, N, 372) * 10)) ** 0.12
    veins2 = np.abs(np.sin(xx / N * 2 * np.pi * 3 + noise(1.5, N, 373) * 12)) ** 0.25
    rgb = colorize(v * 0.4 + 0.6, [(0, (206, 204, 200)), (1, (244, 242, 238))])
    rgb = shade(rgb, 0.72 + 0.16 * veins + 0.12 * veins2)
    yy = np.mgrid[0:N, 0:N][0]
    tile = ((xx % 512) < 2) | ((yy % 512) < 2)
    rgb[tile] = rgb[tile] * 0.8
    save_jpg('marble', rgb)


def wall_plaster():
    v = 0.7 * noise(0.5, N, 381) + 0.3 * noise(2.4, N, 382)
    save_jpg('plaster', colorize(v, [(0, (222, 218, 210)), (1, (246, 244, 238))]))


def wall_brick():
    yy, xx = np.mgrid[0:N, 0:N]
    bh, bw = 64, 192
    row = yy // bh
    off = (row % 2) * (bw // 2)
    col = (xx + off) // bw
    tone = rng(391).random((N // bh + 1, N // bw + 2))[row, col]
    v = 0.25 + 0.5 * tone + 0.25 * noise(0.9, N, 392)
    rgb = colorize(v, [(0, (98, 48, 36)), (0.5, (146, 74, 52)), (1, (188, 112, 82))])
    mortar = ((yy % bh) < 7) | (((xx + off) % bw) < 7)
    rgb[mortar] = np.array([176, 168, 152]) * (0.75 + 0.25 * noise(0.5, N, 393)[mortar])[:, None]
    soot = noise(2.6, N, 394)
    rgb = shade(rgb, 0.85 + 0.2 * soot)
    save_jpg('brick', rgb)


def wall_timber():
    yy = np.mgrid[0:N, 0:N][0]
    h = N // 8
    t = (yy % h) / h
    round_ = np.sin(t * np.pi) ** 0.6
    grain = noise(1.6, N, 401, aniso=(0.1, 3.5))
    v = 0.2 + 0.55 * grain + 0.25 * noise(2.4, N, 402)
    rgb = colorize(v, [(0, (84, 52, 30)), (0.5, (134, 90, 52)), (1, (176, 128, 80))])
    rgb = shade(rgb, 0.4 + 0.6 * round_)
    chink = t > 0.94
    rgb[chink] = [196, 186, 160]
    save_jpg('timber', rgb)


def prop_rock(name, stops, seed):
    v = 0.5 * noise(2.6, N, seed) + 0.3 * noise(1.4, N, seed + 1) + 0.2 * noise(0.8, N, seed + 2)
    rgb = colorize(v, stops)
    crack = np.abs(noise(1.1, N, seed + 4) - 0.5) < 0.008
    rgb[crack] *= 0.5
    save_jpg(name, rgb)


def prop_simple(name, stops, seed, aniso=(1, 1), beta=1.5):
    v = 0.6 * noise(beta, N, seed, aniso=aniso) + 0.4 * noise(2.2, N, seed + 1)
    save_jpg(name, colorize(v, stops))


def facade(night=False):
    """빌딩 벽 (창 격자 4×4칸 = 12m): 낮엔 하늘이 비친 창, 밤엔 일부 창에 불"""
    S = 512
    yy, xx = np.mgrid[0:S, 0:S]
    v = 0.6 * noise(0.6, S, 461) + 0.4 * noise(2.0, S, 462)
    rgb = colorize(v, [(0, (78, 80, 86)), (1, (124, 126, 132))])
    lit = rng(463).random((S // 32, S // 32))
    win = ((xx % 32) > 5) & ((xx % 32) < 27) & ((yy % 32) > 7) & ((yy % 32) < 26)
    if night:
        rgb = rgb * 0.3
        on = lit[yy // 32, xx // 32] > 0.5
        warm = np.array([255, 210, 140.0]) * (0.75 + 0.25 * noise(0.5, S, 464)[..., None])
        rgb[win & on] = warm[win & on]
        rgb[win & ~on] = [16, 20, 28]
    else:
        sky_ = np.array([150, 172, 196.0]) * (0.8 + 0.2 * lit[yy // 32, xx // 32])[..., None]
        sky_ = sky_ * (0.9 + 0.15 * (yy % 32) / 32)[..., None]
        rgb[win] = sky_[win]
    save_jpg('facade_night' if night else 'facade', rgb)


def water():
    """잔물결 바다 (반복)"""
    v = 0.55 * noise(2.2, N, 421, aniso=(0.5, 2.0)) + 0.45 * noise(1.2, N, 422, aniso=(0.4, 2.5))
    rgb = colorize(v, [(0, (16, 52, 78)), (0.5, (30, 84, 110)), (0.85, (70, 130, 150)), (1, (190, 220, 226))])
    spark = v > 0.9
    rgb[spark] = [230, 240, 240]
    save_jpg('water', rgb)


def canvas():
    v = 0.6 * noise(0.4, 512, 431) + 0.4 * noise(2.0, 512, 432)
    yy, xx = np.mgrid[0:512, 0:512]
    weave = ((xx % 4) < 2) ^ ((yy % 4) < 2)
    rgb = colorize(v, [(0, (200, 196, 186)), (1, (240, 236, 226))]) * (0.95 + 0.05 * weave)[..., None]
    seam = (xx % 256) < 3
    rgb[seam] *= 0.8
    save_jpg('canvas', rgb)


def paintings():
    """전시관에 거는 그림 6점 (추상·풍경)"""
    W, H = 512, 640
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    n = noise(1.2, W, 441, h=H)
    # 0 색면 (로스코풍)
    rgb = np.zeros((H, W, 3)) + [120, 30, 34]
    rgb[(yy > 60) & (yy < 300) & (xx > 50) & (xx < 462)] = [196, 70, 40]
    rgb[(yy > 340) & (yy < 590) & (xx > 50) & (xx < 462)] = [60, 20, 30]
    save_jpg('art_0', rgb * (0.88 + 0.2 * n)[..., None])
    # 1 해질녘 풍경
    sky_ = lerp(np.array([250, 180, 90.0]), np.array([60, 60, 130.0]), np.clip(1 - yy / (H * 0.6), 0, 1))
    hill = yy > H * (0.62 + 0.08 * np.sin(xx / 70))
    sky_[hill] = [40, 50, 50]
    sun = np.hypot(xx - 330, yy - H * 0.52) < 40
    sky_[sun] = [255, 230, 170]
    save_jpg('art_1', sky_ * (0.9 + 0.15 * n)[..., None])
    # 2 기하 (몬드리안풍)
    rgb = np.zeros((H, W, 3)) + 236
    for c, (x0, y0, x1, y1) in zip([(200, 40, 40), (30, 60, 150), (240, 200, 40)], [(0, 0, 220, 300), (300, 380, 512, 640), (300, 0, 400, 140)]):
        rgb[y0:y1, x0:x1] = c
    for x in (220, 300, 400):
        rgb[:, x - 6:x + 6] = 20
    for y in (140, 300, 380):
        rgb[y - 6:y + 6, :] = 20
    save_jpg('art_2', rgb)
    # 3 물결 (호쿠사이풍 색)
    w = np.sin(xx / 40 + np.sin(yy / 60) * 2 + n * 4)
    rgb = colorize(w * 0.5 + 0.5, [(0, (20, 40, 90)), (0.6, (60, 110, 160)), (1, (236, 232, 214))])
    save_jpg('art_3', rgb)
    # 4 꽃밭 (점묘)
    rgb = colorize(noise(2.0, W, 445, h=H), [(0, (60, 100, 50)), (1, (150, 180, 90))])
    r = rng(446)
    for _ in range(900):
        cx, cy = r.integers(0, W), r.integers(int(H * 0.35), H)
        rgb[max(0, cy - 4):cy + 4, max(0, cx - 4):cx + 4] = [(230, 80, 90), (250, 220, 90), (240, 240, 240), (170, 90, 200)][r.integers(0, 4)]
    rgb[:int(H * 0.3)] = lerp(np.array([170, 200, 230.0]), np.array([230, 236, 240.0]), (yy[:int(H * 0.3)] / (H * 0.3)))
    save_jpg('art_4', rgb)
    # 5 추상 붓질
    rgb = colorize(noise(1.6, W, 447, h=H, aniso=(3, 0.4)), [(0, (24, 24, 28)), (0.4, (60, 80, 120)), (0.7, (220, 170, 60)), (1, (245, 240, 230))])
    save_jpg('art_5', rgb)


def haze():
    """바다 지평선 안개 띠: 아래(수평선)는 짙고 위로 갈수록 투명"""
    H = 256
    y = (np.arange(H) / (H - 1))[:, None] * np.ones((1, 16))
    a = y ** 2.2
    save_png('haze', np.ones((H, 16, 3)) * 255, a)


def glow():
    S = 128
    yy, xx = np.mgrid[0:S, 0:S]
    d = np.hypot(xx - S / 2, yy - S / 2) / (S / 2)
    a = np.clip(1 - d, 0, 1) ** 2
    rgb = np.zeros((S, S, 3)) + [255, 214, 150]
    save_png('glow', rgb, a)


# ───────────── 효과음 (sfx/, 48kHz 모노 wav) ─────────────
SR = 48000


def save_wav(name, x, peak_db):
    import wave
    os.makedirs(os.path.join(OUT, 'sfx'), exist_ok=True)
    x = np.asarray(x, dtype=float)
    x = x / (np.max(np.abs(x)) + 1e-9) * (10 ** (peak_db / 20))
    # 앞뒤 2ms 살짝 열고 닫기 (딸깍 소리 방지)
    k = int(SR * 0.002)
    x[:k] *= np.linspace(0, 1, k)
    x[-k:] *= np.linspace(1, 0, k)
    with wave.open(os.path.join(OUT, 'sfx', name + '.wav'), 'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype('<i2').tobytes())


def _t(sec):
    return np.arange(int(SR * sec)) / SR


def _bell(f, sec, decay, partials=((1, 1), (2.76, 0.32), (5.4, 0.12), (8.93, 0.05))):
    t = _t(sec)
    out = np.zeros_like(t)
    for m, a in partials:
        out += a * np.sin(2 * np.pi * f * m * t) * np.exp(-t * decay * (1 + 0.6 * m))
    return out * (1 - np.exp(-t * 900))


def _lowpass(x, cut, order=4):
    """저역 통과 (주파수 영역에서 부드럽게 깎음: 차단 주파수 위로 옥타브마다 order×6dB)"""
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    X *= 1 / np.sqrt(1 + (f / cut) ** (2 * order))
    return np.fft.irfft(X, len(x))


def _place(buf, x, at):
    i = int(at * SR)
    n = min(len(x), len(buf) - i)
    if n > 0:
        buf[i:i + n] += x[:n]


def sfx():
    r = rng(901)
    # 열쇠 문이 나타날 때: 유리 같은 작은 종 두 음 + 아주 옅은 바람 (짧고 조용하게)
    buf = np.zeros(int(SR * 1.8))
    air = _lowpass(r.standard_normal(int(SR * 0.6)), 1800) * np.sin(np.linspace(0, np.pi, int(SR * 0.6))) ** 2 * 0.08
    _place(buf, air, 0)
    _place(buf, _bell(1567.98, 1.5, 3.2), 0.18)
    _place(buf, _bell(2093.0, 1.4, 3.6) * 0.6, 0.30)
    save_wav('key_appear', buf, -18)

    # 열쇠를 돌릴 때: 금속 딸깍 두 번 + 낮은 '툭' + 반짝이는 오름 음
    buf = np.zeros(int(SR * 1.6))
    def click(sec=0.018, cut=5000):
        n = r.standard_normal(int(SR * sec))
        hp = n - _lowpass(n, 1800)
        return hp * np.exp(-_t(sec) * 260)
    _place(buf, click(), 0.0)
    _place(buf, click() * 0.8, 0.22)
    t = _t(0.25)
    _place(buf, np.sin(2 * np.pi * 95 * t) * np.exp(-t * 26) * 0.9, 0.22)
    for i, f in enumerate((1046.5, 1318.5, 1568.0, 2093.0)):
        _place(buf, _bell(f, 0.9, 4.5) * (0.35 - i * 0.04), 0.32 + i * 0.07)
    save_wav('key_turn', buf, -12)

    # 문짝이 벽 속으로 밀려 들어갈 때: 묵직한 나무 미끄러짐(낮게 거른 잡음) + 바람 + 끝에 부드러운 '쿵'
    dur = 1.0
    buf = np.zeros(int(SR * (dur + 0.4)))
    n = r.standard_normal(int(SR * dur))
    env = np.interp(_t(dur), [0, 0.15, 0.55, dur], [0, 1, 0.8, 0])
    rumble = _lowpass(n, 300) * env
    grain = _lowpass(n - _lowpass(n, 900), 2500) * env * 0.05 * (1 + 0.5 * np.sin(2 * np.pi * 17 * _t(dur)))
    _place(buf, rumble + grain, 0)
    t = _t(0.35)
    _place(buf, np.sin(2 * np.pi * 62 * t) * np.exp(-t * 14) * 0.7, dur - 0.08)
    save_wav('door_open', buf, -14)

    # 탐험 시작: 공간을 훑는 스캔 — 낮은 울림으로 시작해 오르는 소리, 점점 빨라지는 디지털 신호, 쓸고 지나가는 바람, 맑은 화음으로 끝
    dur = 3.6
    buf = np.zeros(int(SR * dur))
    t = _t(dur)
    boom = np.sin(2 * np.pi * 48 * t) * np.exp(-t * 1.6) * 0.9
    f = 110 * (8 ** np.clip(t / 2.2, 0, 1))                       # 110 → 880Hz
    ph = 2 * np.pi * np.cumsum(f) / SR
    rise = (np.sin(ph) + 0.35 * np.sin(2 * ph) + 0.18 * np.sin(3 * ph)) * np.interp(t, [0, 0.3, 2.1, 2.5], [0, 0.35, 0.5, 0])
    sweep = _lowpass(r.standard_normal(len(t)), 2400)
    sweep = sweep - _lowpass(sweep, 300)
    sweep *= np.interp(t, [0, 0.6, 1.6, 2.6], [0, 0.08, 0.3, 0])
    buf += boom + rise + sweep
    at = 0.15
    while at < 2.3:                                              # 디지털 신호: 처음엔 드문드문, 갈수록 촘촘히
        fq = r.choice([1760, 2093, 2349, 2637, 3136])
        bt = _t(0.035)
        _place(buf, np.sign(np.sin(2 * np.pi * fq * bt)) * np.exp(-bt * 90) * 0.12, at)
        at += max(0.035, 0.22 * (1 - at / 2.4))
    for fq in (523.25, 783.99, 1046.5, 1567.98):                 # 끝 화음 (C·G·C·G)
        _place(buf, _bell(fq, 1.4, 2.2) * 0.22, 2.3)
    save_wav('scan', buf, -8)
    fire_sounds(r)


def _loop(x, fade_sec=1.0):
    """끝 1초를 앞 1초와 겹쳐 이어 붙임 → 되풀이해도 이음매가 들리지 않음"""
    k = int(SR * fade_sec)
    w = np.linspace(0, 1, k)
    head = x[:k] * w + x[-k:] * (1 - w)
    return np.concatenate([head, x[k:-k]])


def fire_sounds(r):
    """모닥불 (불멍): 장작 타는 소리 되풀이 · 비에 젖은 불의 치익 소리 되풀이 · 불이 꺼지며 연기가 오르는 소리"""
    # 장작 타는 소리 12초: 낮게 일렁이는 불길 + 타닥타닥(짧고 높은 딱 소리, 가끔 크게 '탁') + 옅은 쉬익
    dur = 13.0
    n = int(SR * dur)
    t = _t(dur)
    b = np.cumsum(r.standard_normal(n)) * 0.02
    b -= _lowpass(b, 8)                                            # 아주 느린 흔들림은 뺌
    roar = _lowpass(b, 260) * (0.75 + 0.25 * np.sin(2 * np.pi * 0.23 * t) * np.sin(2 * np.pi * 0.071 * t + 1))
    air = _lowpass(r.standard_normal(n), 5000)
    air = (air - _lowpass(air, 1200)) * 0.035 * (0.7 + 0.3 * np.sin(2 * np.pi * 0.37 * t))
    buf = roar / (np.std(roar) + 1e-9) * 0.12 + air * 2
    at = 0.0
    while at < dur - 0.05:
        at += r.exponential(1 / 11)                                 # 1초에 11번쯤
        big = r.random() < 0.08
        ln = r.uniform(0.002, 0.007) * (2.5 if big else 1)
        c = r.standard_normal(int(SR * ln))
        c = c - _lowpass(c, 1500 if big else 2500)
        c *= np.exp(-_t(ln) * (900 if big else 1400))
        amp = (r.uniform(0.5, 1.0) if big else r.uniform(0.08, 0.45))
        _place(buf, c * amp, at)
        if r.random() < 0.25:                                      # 작은 연달음 (타다닥)
            for k in range(r.integers(1, 4)):
                _place(buf, c * amp * r.uniform(0.3, 0.7), at + 0.012 * (k + 1) + r.uniform(0, 0.01))
    buf = np.tanh(buf * 3.0)                                       # 큰 '탁'만 튀지 않게 눌러서 전체가 또렷이 들리게
    save_wav('fire_loop', _loop(buf), -6)

    # 비에 젖은 불: 치익 하는 김 소리 (높은 잡음이 불규칙하게 부풀었다 가라앉음) 9초
    dur = 10.0
    n = int(SR * dur)
    t = _t(dur)
    h = r.standard_normal(n)
    h = _lowpass(h - _lowpass(h, 2500), 9000)
    env = np.zeros(n)
    at = 0.0
    while at < dur:
        ln = r.uniform(0.3, 1.4)
        k0 = int(at * SR); k1 = min(n, int((at + ln) * SR))
        if k1 > k0:
            env[k0:k1] += np.sin(np.linspace(0, np.pi, k1 - k0)) * r.uniform(0.3, 1.0)
        at += r.uniform(0.2, 0.9)
    env = _lowpass(env, 6) + 0.15
    save_wav('fire_hiss', _loop(h * env), -16)

    # 불이 꺼질 때: 치이익 + 낮은 '후우' (연기가 오르는 바람) 3.5초
    dur = 3.5
    n = int(SR * dur)
    t = _t(dur)
    h = r.standard_normal(n)
    hiss = _lowpass(h - _lowpass(h, 2000), 8000) * np.interp(t, [0, 0.08, 1.2, dur], [0, 1, 0.35, 0])
    w = _lowpass(r.standard_normal(n), 500) * np.interp(t, [0, 0.4, 2.0, dur], [0, 1, 0.6, 0]) * 4
    save_wav('fire_out', hiss + w, -14)


def scan_grid():
    """탐험 시작 스캔 격자: 50cm 칸에 밝은 선 + 가는 10cm 보조선 + 군데군데 빛나는 점"""
    S = 256
    yy, xx = np.mgrid[0:S, 0:S]
    def line(c, w):
        d = np.minimum(c % (S // 1), S - c % S)
        return np.clip(1 - d / w, 0, 1)
    main = np.maximum(line(xx, 3.0), line(yy, 3.0))
    fine = np.maximum(np.clip(1 - np.minimum(xx % (S / 5), S / 5 - xx % (S / 5)) / 1.0, 0, 1),
                      np.clip(1 - np.minimum(yy % (S / 5), S / 5 - yy % (S / 5)) / 1.0, 0, 1)) * 0.45
    r = rng(733)
    dots = np.zeros((S, S))
    for _ in range(14):
        cx, cy = r.integers(0, 5) * S // 5, r.integers(0, 5) * S // 5
        dots = np.maximum(dots, np.clip(1 - np.hypot(xx - cx, yy - cy) / 5, 0, 1))
    a = np.clip(np.maximum(np.maximum(main, fine), dots), 0, 1)
    rgb = np.zeros((S, S, 3)) + [120, 255, 170]
    rgb = rgb * (0.7 + 0.3 * a[..., None])
    save_png('scan_grid', rgb, a)


def people():
    """카페 창밖을 지나가는 사람 실루엣 4가지 (앱이 색을 입힘). 투명 그림 + 가림 그림"""
    W, H = 256, 600
    kinds = [dict(coat=0.0, bag=False, hat=False), dict(coat=0.35, bag=True, hat=False),
             dict(coat=0.15, bag=False, hat=True), dict(coat=0.5, bag=False, hat=False)]
    for k, kd in enumerate(kinds):
        m = Image.new('L', (W, H), 0)
        d = ImageDraw.Draw(m)
        cx = W // 2
        head = 34
        d.ellipse([cx - head, 18, cx + head, 18 + head * 2], fill=255)                  # 머리
        if kd['hat']:
            d.rectangle([cx - head - 14, 30, cx + head + 14, 40], fill=255)
            d.rectangle([cx - head + 4, 0, cx + head - 4, 34], fill=255)
        d.rectangle([cx - 14, 84, cx + 14, 100], fill=255)                           # 목
        sh = 66                                                                        # 어깨 반폭
        body_bottom = int(330 + kd['coat'] * 160)
        d.polygon([(cx - sh, 104), (cx + sh, 104), (cx + sh - 10 + int(kd['coat'] * 30), body_bottom),
                   (cx - sh + 10 - int(kd['coat'] * 30), body_bottom)], fill=255)          # 몸 (외투면 길게)
        d.ellipse([cx - sh, 96, cx - sh + 30, 130], fill=255)
        d.ellipse([cx + sh - 30, 96, cx + sh, 130], fill=255)
        for s in (-1, 1):                                                              # 팔
            d.polygon([(cx + s * sh, 112), (cx + s * (sh + 14), 120), (cx + s * (sh + 18), 320), (cx + s * (sh - 6), 322)], fill=255)
        for s in (-1, 1):                                                              # 다리
            x0 = cx + s * 10 if s > 0 else cx - 46
            d.polygon([(x0, body_bottom - 20), (x0 + 36, body_bottom - 20), (x0 + 32 + s * 4, H - 22), (x0 + 6 + s * 4, H - 22)], fill=255)
            d.ellipse([x0 + s * 6 - 4, H - 36, x0 + 44 + s * 6, H - 6], fill=255)         # 신발
        if kd['bag']:
            d.rectangle([cx + sh + 2, 250, cx + sh + 40, 330], fill=255)
            d.line([(cx + sh - 10, 120), (cx + sh + 20, 250)], fill=255, width=6)
        a = np.asarray(m.filter(ImageFilter.GaussianBlur(1.2))).astype(float) / 255
        yy = np.linspace(0, 1, H)[:, None] * np.ones((1, W))
        shade_v = 0.85 + 0.15 * (1 - yy)
        rgb = np.stack([np.full((H, W), 150.0)] * 3, axis=-1) * shade_v[..., None]
        save_png(f'person_{k}', rgb, a)


def flame():
    """벽난로 불꽃 한 갈래 (아래가 둥글고 위가 뾰족한 물방울 모양, 안쪽은 노랗고 바깥은 주황·빨강)"""
    W, H = 128, 256
    yy, xx = np.mgrid[0:H, 0:W].astype(float)
    y = 1 - yy / (H - 1)                          # 0 아래 ~ 1 위
    x = (xx - W / 2) / (W / 2)
    half = np.where(y < 0.25, np.sqrt(np.clip(1 - ((0.25 - y) / 0.25) ** 2, 0, 1)), (1 - (y - 0.25) / 0.75) ** 1.4)
    half = half * (0.9 + 0.1 * np.sin(y * 9))
    d = np.abs(x) / np.maximum(half, 1e-3)
    a = np.clip((1 - d) * 3, 0, 1) * (y < 0.98)
    core = np.clip(1 - d * 1.4, 0, 1) * np.clip(1.2 - y, 0, 1)
    rgb = np.stack([255 * np.ones_like(y), 120 + 120 * core, 30 + 160 * core ** 2], axis=-1)
    rgb = rgb * (0.85 + 0.15 * (1 - y))[..., None]
    a = np.asarray(Image.fromarray((a * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2))) / 255
    save_png('flame', rgb, a)


def menu_board():
    """카페 메뉴판 (칠판에 분필 글씨)"""
    W, H = 600, 700
    base = noise(beta=1.2, size=1024, seed=771)[:H, :W]
    rgb = np.stack([28 + base * 10, 38 + base * 12, 34 + base * 10], axis=-1)
    im = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8))
    d = ImageDraw.Draw(im)
    def font(sz):
        try:
            return ImageFont.load_default(size=sz)
        except Exception:
            return ImageFont.load_default()
    chalk = (236, 232, 220)
    d.text((W // 2, 70), 'MENU', fill=chalk, font=font(64), anchor='mm')
    d.line([(150, 112), (450, 112)], fill=chalk, width=3)
    items = [('Espresso', '4.0'), ('Americano', '4.5'), ('Cafe Latte', '5.0'), ('Flat White', '5.0'),
             ('Cappuccino', '5.0'), ('Vanilla Latte', '5.5'), ('Hot Chocolate', '5.0'), ('Black Tea', '4.5')]
    y = 160
    for n, pr in items:
        d.text((70, y), n, fill=chalk, font=font(34), anchor='lm')
        d.text((W - 70, y), pr, fill=chalk, font=font(34), anchor='rm')
        y += 56
    # 작은 컵 그림
    d.arc([W // 2 - 40, H - 120, W // 2 + 40, H - 50], 0, 180, fill=chalk, width=4)
    d.line([(W // 2 - 40, H - 85), (W // 2 + 40, H - 85)], fill=chalk, width=4)
    d.arc([W // 2 + 30, H - 105, W // 2 + 60, H - 75], 270, 90, fill=chalk, width=4)
    for k in range(3):
        x = W // 2 - 20 + k * 20
        d.arc([x - 8, H - 150, x + 8, H - 110], 90, 270, fill=chalk, width=3)
    arr = np.asarray(im).astype(float)
    arr += (noise(beta=0.5, size=1024, seed=773)[:H, :W, None] - 0.5) * 18     # 분필 가루
    save_jpg('menu_board', arr)


def line_art():
    """선 그림 모드용: 오려 내기 그림(<이름>_a.png 가 있는 나무·울타리·지평선 띠·사람)마다
    흰 바탕에 윤곽선만 검게 그린 <이름>_ln.png — 안쪽 무늬는 그리지 않음(선이 지저분해지지 않게)"""
    for sub in ('tex', 'sky'):
        line_folder(os.path.join(OUT, sub), sky=(sub == 'sky'))


def line_folder(folder, sky=False):
    for fn in sorted(os.listdir(folder)):
        if not fn.endswith('_a.png') or fn.endswith('_lna.png') or fn.startswith('haze') or fn.startswith('scan_grid'):
            continue
        name = fn[:-6]
        m = Image.open(os.path.join(folder, fn)).convert('L')
        W = m.width
        r = max(3, int(round(W / 512 * 2.6)))
        # 가장자리 잔털(나뭇잎·풀 끝)을 먼저 뭉개서 윤곽선이 매끄럽게
        soft = m.filter(ImageFilter.GaussianBlur(r * 1.5))
        mask = soft.point(lambda v: 255 if v > 110 else 0).filter(ImageFilter.MedianFilter(7))
        eroded = mask.filter(ImageFilter.MinFilter(2 * r + 1))
        edge = (np.asarray(mask) > 0) & ~(np.asarray(eroded) > 0)
        out = np.full((m.height, m.width, 3), 255, np.uint8)
        out[edge] = (22, 22, 22)
        if sky:      # 구름: 그림 자체의 투명도로 그려지므로 윤곽선 그림에 투명도를 같이 담음
            rgba = np.concatenate([out, np.asarray(mask)[..., None]], axis=-1)
            Image.fromarray(rgba.astype(np.uint8), 'RGBA').save(os.path.join(folder, name + '_ln.png'), optimize=True)
            continue
        Image.fromarray(out).save(os.path.join(folder, name + '_ln.png'), optimize=True)
        mask.save(os.path.join(folder, name + '_lna.png'), optimize=True)      # 선 그림에서 쓰는 매끄러운 가림 그림


def _fetch_art():
    """전시관 명화 받기 (인터넷이 안 되면 건너뜀 — 그때는 만든 그림 art_0~5를 씀)"""
    try:
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import fetch_art
        fetch_art.main()
    except Exception as e:
        print('명화 받기 건너뜀:', e, flush=True)


def main():
    only = sys.argv[1:] if len(sys.argv) > 1 else None
    jobs = {
        'sky': lambda: (skies(), cloud_sprites()),
        'bands': lambda: (
            band_far_mountains('far_mtn', 101, (176, 190, 210)),
            band_far_mountains('far_peaks', 111, (160, 172, 190), snow=True),
            band_ridge_pines('mid_ridge', 121, (70, 92, 96)),
            band_trees('near_pines', 131, 'pine'),
            band_trees('near_broad', 141, 'broad', count=110, dark=(22, 38, 20), lit=(86, 120, 56)),
            band_cliffs('mid_cliffs', 151),
            band_village('mid_village', 161), band_village('mid_village_night', 161, night=True),
            band_city('far_city', 171), band_city('far_city_night', 171, night=True),
            band_islands('far_islands', 181)),
        'barriers': lambda: (barrier_camp(), barrier_forest(), barrier_valley(), barrier_sea(), barrier_village(), barrier_city()),
        'trees': lambda: (
            tree_single('tree_pine', 'pine', 501, (16, 36, 24), (72, 110, 64)),
            tree_single('tree_broad', 'broad', 502, (24, 44, 20), (110, 148, 64)),
            tree_single('tree_twisted', 'twisted', 503, (20, 40, 28), (78, 112, 70))),
        'floors': lambda: (
            floor_grass(), floor_moss(), floor_pebble(), floor_sand(), floor_roof(), floor_dirt(),
            floor_planks('planks', [(0, (96, 62, 36)), (0.5, (142, 98, 58)), (1, (184, 136, 88))]),
            floor_planks('planks_dark', [(0, (52, 32, 22)), (0.5, (86, 56, 36)), (1, (126, 86, 56))], rows=16, seed=365),
            floor_marble(), wall_plaster(), wall_brick(), wall_timber(),
            prop_rock('rock', [(0, (66, 64, 60)), (0.5, (116, 110, 102)), (1, (166, 160, 150))], 411),
            prop_rock('mossrock', [(0, (40, 56, 34)), (0.5, (88, 104, 70)), (1, (140, 150, 116))], 413),
            prop_rock('basalt', [(0, (28, 30, 34)), (0.5, (58, 60, 64)), (1, (98, 100, 102))], 415),
            prop_simple('bark', [(0, (52, 38, 28)), (0.5, (98, 74, 52)), (1, (140, 110, 80))], 417, aniso=(3, 0.2)),
            prop_simple('driftwood', [(0, (100, 96, 88)), (0.5, (150, 144, 132)), (1, (196, 190, 176))], 419, aniso=(0.2, 3)),
            prop_simple('hay', [(0, (150, 120, 60)), (0.5, (196, 164, 92)), (1, (232, 206, 140))], 423, aniso=(0.3, 2.5)),
            prop_simple('concrete', [(0, (116, 114, 110)), (1, (172, 170, 164))], 425, beta=0.6),
            facade(), facade(night=True), water(), canvas(), paintings(), glow(), scan_grid(), haze(),
            people(), menu_board(), flame()),
        'sfx': lambda: sfx(),
        'art': lambda: _fetch_art(),
        'lines': lambda: line_art(),          # 오려 내기 그림을 다 만든 뒤에
    }
    for k, f in jobs.items():
        if only and k not in only:
            continue
        f()
        print('만듦:', k, flush=True)


if __name__ == '__main__':
    main()
