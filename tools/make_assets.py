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
SW, SH = 4096, 1024                     # 하늘 반구 (가로 360°, 세로 지평선~꼭대기)


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
    glow = np.exp(-ang / P['glow']) * (0.9 if time != 'night' else 0.0)          # 밤: 달은 앱이 따로 띄움
    halo = np.exp(-ang / (P['glow'] * 5)) * (0.25 if time != 'night' else 0.0)
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
    if False:            # 별·달은 그림에 그리지 않음 — 앱이 별(또렷한 점)·달(따로 된 판)을 하늘에 직접 띄움 (그림에 그리면 꼭대기 쪽이 늘어나 보임)
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
    if cond in ('clear', 'cloudy') and sel > 0 and time != 'night':
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
    """하늘 20장 (시간 5 × 상태 4): Poly Haven 실사 하늘을 받아 두었으면 그것으로, 없으면 직접 그림"""
    cloud_tex = noise(2.6, 1024, 77, lowcut=6) * 0.6 + noise(2.0, 1024, 78, lowcut=6) * 0.4
    for t in SKY:
        for c in CONDS:
            img = photo_sky(t, c)
            if img is None:
                img = sky(t, c, cloud_tex)
                print('  하늘(직접 그림):', t, c, flush=True)
            save_jpg(f'sky_{t}_{c}', img, folder='sky', q=90)


def _ph_sky(t, c):
    """받아 둔 실사 하늘 → 위쪽 반(하늘 반구)만 4096×1024 (없으면 None)"""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import fetch_env
    i = fetch_env.SKIES.get((t, c))
    if i is None:
        return None
    path = fetch_env.sky_path(i)
    if not os.path.exists(path):
        return None
    im = Image.open(path).convert('RGB')
    im = im.crop((0, 0, im.width, im.height // 2)).resize((SW, SH), Image.LANCZOS)
    return np.asarray(im).astype(np.float32)


def _lum(a):
    return a[..., 0] * 0.299 + a[..., 1] * 0.587 + a[..., 2] * 0.114


def _night_from(a, target=11.0):
    """밤하늘 사진: 별 점은 지우고(앱이 또렷한 별을 따로 띄움) 어둡고 푸르게"""
    im = Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).filter(ImageFilter.MedianFilter(7))
    b = np.asarray(im).astype(np.float32)
    up = b[: int(SH * 0.85)]
    k = target / max(1.0, float(_lum(up).mean()))
    return np.clip(b * k * np.array([0.92, 0.98, 1.12]), 0, 255)


def photo_sky(t, c):
    """실사 하늘 고르기·다듬기. 받은 하늘이 없는 조합은 가까운 하늘을 어둡게·흐리게 바꿔 씀"""
    a = _ph_sky(t, c)
    if a is not None:
        if t == 'night':
            return _night_from(a)
        return a
    if c == 'storm':
        base = _ph_sky(t, 'overcast') if t != 'night' else None
        if base is None:
            base = _ph_sky('afternoon', 'storm')
        if base is None:
            return None
        g = _lum(base)[..., None]
        out = (base * 0.55 + g * 0.45) * (0.5 if t in ('morning', 'afternoon') else 0.36)
        if t == 'night':
            out = out * 0.18
        return np.clip(out * np.array([0.94, 0.98, 1.06]), 0, 255)
    if t == 'night':
        over = _ph_sky('afternoon', 'overcast')
        clear = _ph_sky('night', 'clear')
        if over is None:
            return None
        dark = np.clip(over * np.array([0.06, 0.07, 0.1]), 0, 255)
        if c == 'overcast' or clear is None:
            return dark
        n = _night_from(clear)
        m = np.clip((_lum(over) - 120) / 90, 0, 1)[..., None]           # 구름이 짙은 곳일수록 구름으로
        return n * (1 - m) + dark * m
    return None


def moon_art():
    """달: 바다(크고 부드러운 어두운 무늬)·작은 크레이터·밝은 광조·가장자리 어두워짐이 있는 보름달 (투명 바탕) — 앱이 밤하늘에 따로 띄움"""
    S = 512
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    cx = cy = S / 2
    R = S * 0.46
    d = np.hypot(xx - cx, yy - cy) / R
    disc = np.clip((1 - d) * R / 1.5, 0, 1)
    maria = noise(3.8, S, 1901, lowcut=2)
    maria = np.asarray(Image.fromarray((maria * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(6))) / 255.0
    mar = np.clip((maria - 0.5) * 3.2, 0, 1)
    fine = noise(1.6, S, 1902)
    v = 0.84 - 0.26 * mar + 0.05 * (fine - 0.5)
    r = rng(1903)
    for _ in range(45):
        px, py = r.uniform(-0.85, 0.85, 2) * R + cx
        if np.hypot(px - cx, py - cy) > R * 0.92:
            continue
        rr = R * r.uniform(0.012, 0.04)
        dd = np.hypot(xx - px, yy - py) / rr
        inner = np.clip(1 - dd, 0, 1) ** 0.6
        rim = np.exp(-((dd - 1) / 0.25) ** 2)
        side = ((xx - px) * -0.6 + (yy - py) * -0.8) / rr
        v = v - inner * 0.05 + rim * 0.035 * np.clip(side, -1, 1)
    # 밝은 광조 크레이터 하나 (티코처럼): 가운데 밝은 점 + 부드럽게 퍼지는 줄
    tx, ty = cx - R * 0.12, cy + R * 0.58
    ang = np.arctan2(yy - ty, xx - tx)
    dist = np.hypot(xx - tx, yy - ty)
    rays = np.clip(np.cos(ang * 7 + noise(2.0, S, 1904) * 3) * 0.5 + 0.5, 0, 1) ** 4 * np.exp(-dist / (R * 0.35)) * np.clip(dist / (R * 0.05), 0, 1)
    rays = np.asarray(Image.fromarray((np.clip(rays, 0, 1) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2))) / 255.0
    v = v + rays * 0.035 + np.exp(-(dist / (R * 0.025)) ** 2) * 0.12
    limb = 1 - 0.3 * np.clip(d, 0, 1) ** 2.6
    v = np.clip(v * limb, 0, 1)
    rgb = np.stack([v * 248, v * 244, v * 232], axis=-1)
    save_png('moon', rgb, disc)
    # 달의 모양 일곱 가지 (차는 초승달·상현·차는 반달 넘은 달·보름·기우는 달·하현·그믐달): 해가 비추는 쪽만 밝고,
    # 어두운 쪽은 지구빛으로 아주 희미하게. 앱이 방마다 하나를 고름 (moon_ph0~6)
    nx = (xx - cx) / R; ny = (yy - cy) / R
    nz = np.sqrt(np.clip(1 - nx ** 2 - ny ** 2, 0, 1))
    for k, (e, wane) in enumerate([(0.75, False), (math.pi / 2, False), (2.3, False), (math.pi, False), (2.3, True), (math.pi / 2, True), (0.75, True)]):
        sx = math.sin(e) * (-1 if wane else 1)
        lit = nx * sx - nz * math.cos(e)
        lit = np.clip((lit + 0.04) / 0.1, 0, 1)
        lit = lit * lit * (3 - 2 * lit)
        vv = v * (0.07 + 0.93 * lit)
        rgbk = np.stack([vv * 248, vv * 244, vv * 232], axis=-1)
        save_png(f'moon_ph{k}', rgbk, disc * (0.05 + 0.95 * lit))


# 먼 풍경 띠의 위·아래 끝 (방 바닥 기준 높이 / 반지름 → 고도각) — RoomWorld Decor 의 pano 띠와 같은 값
PANO_SPEC = {'pano_hills': (270.0, 68.0, -7.0), 'pano_peaks': (270.0, 92.0, -6.0)}


def photo_band(name):
    """360° 실사 풍경에서 땅·산만 오려 낸 지평선 띠 (가로 8192, 한 바퀴 그대로). 받지 못했거나 오려 내기가 미덥지 않으면
    직접 그린 산 띠를 한 바퀴로 이어 붙여 같은 이름으로"""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import fetch_env
    r, h, base = PANO_SPEC[name]
    el_lo = math.degrees(math.atan2(base, r)); el_hi = math.degrees(math.atan2(base + h, r))
    full_id, pure_id = fetch_env.PANOS[name]
    fp, pp = fetch_env.sky_path(full_id), fetch_env.sky_path(pure_id)
    ok = False
    if os.path.exists(fp) and os.path.exists(pp):
        fi = Image.open(fp).convert('RGB')
        pi = Image.open(pp).convert('RGB').resize(fi.size, Image.LANCZOS)
        W0, H0 = fi.size
        y0 = int((0.5 - el_hi / 180.0) * H0); y1 = int((0.5 - el_lo / 180.0) * H0)
        f = np.asarray(fi.crop((0, y0, W0, y1))).astype(np.float32)
        q = np.asarray(pi.crop((0, y0, W0, y1))).astype(np.float32)
        diff = np.abs(f - q).max(axis=2)
        diff = np.asarray(Image.fromarray(np.clip(diff * 4, 0, 255).astype(np.uint8)).filter(ImageFilter.MedianFilter(5))).astype(np.float32) / 4
        hh, ww = diff.shape
        m = diff > 14
        # 열마다 위에서부터 처음으로 땅이 4줄 넘게 이어지는 곳 = 능선, 그 아래는 다 땅
        run = np.zeros_like(m, dtype=np.int32)
        for yv in range(hh - 1, -1, -1):
            run[yv] = np.where(m[yv], (run[yv + 1] + 1) if yv + 1 < hh else 1, 0)
        first = np.argmax(run >= 4, axis=0)
        none = ~(run >= 4).any(axis=0)
        first[none] = hh - 1
        pad = np.concatenate([first[-4:], first, first[:4]]).astype(np.float32)
        first = np.median(np.lib.stride_tricks.sliding_window_view(pad, 9), axis=1)        # 능선을 고르게 (한 바퀴 이어지게)
        sky_frac = float((first > hh * 0.3).mean())
        if sky_frac > 0.6:
            yy = np.arange(hh)[:, None].astype(np.float32)
            a = np.clip(yy - first[None, :] + 1.0, 0, 1)
            rgb = f
            W1 = 8192
            if ww != W1:
                im = Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8)).resize((W1, int(hh * W1 / ww)), Image.LANCZOS)
                am = Image.fromarray((a * 255).astype(np.uint8)).resize(im.size, Image.LANCZOS)
                rgb = np.asarray(im).astype(np.float32); a = np.asarray(am).astype(np.float32) / 255
            save_png(name, rgb, a)
            print('  실사 풍경 띠:', name, '←', full_id, rgb.shape, flush=True)
            ok = True
        else:
            print('  실사 풍경 띠 오려 내기 실패 → 직접 그림:', name, sky_frac, flush=True)
    if not ok:
        # 직접 그린 먼 산을 한 바퀴 길이로 이어 붙임 (가로·세로 비율을 실제 띠에 맞게)
        reps = max(1, round(2 * math.pi * r / (h * 4)))
        src = 'far_peaks' if name == 'pano_peaks' else 'far_mtn'
        rgb = np.asarray(Image.open(os.path.join(OUT, 'tex', src + '.png')).convert('RGB')).astype(np.float32)
        a = np.asarray(Image.open(os.path.join(OUT, 'tex', src + '_a.png')).convert('L')).astype(np.float32) / 255
        rgb = np.tile(rgb, (1, reps, 1)); a = np.tile(a, (1, reps))
        save_png(name, rgb, a)


def photo_textures():
    """받아 둔 실사 무늬로 바닥·벽·바위·나무껍질 그림을 바꿈 (밝기는 앱 재질에 맞게 맞춤)"""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import fetch_env
    target = {'grass': 92, 'moss': 82, 'pebble': 132, 'sand': 182, 'dirt': 118, 'planks': 128, 'planks_dark': 78,
              'brick': 118, 'plaster': 218, 'rock': 124, 'mossrock': 100, 'bark': 86, 'cliff': 112,
              'fabric': 150, 'walnut': 92, 'concrete': 138, 'oak': 168}
    for name, i in fetch_env.TEXTURES.items():
        path = fetch_env.tex_path(i)
        if not os.path.exists(path):
            continue
        a = np.asarray(Image.open(path).convert('RGB').resize((2048, 2048), Image.LANCZOS)).astype(np.float32)
        k = target.get(name, 120) / max(1.0, float(_lum(a).mean()))
        save_jpg(name, np.clip(a * k, 0, 255), q=90)
        print('  실사 무늬:', name, '←', i, flush=True)


def cloud_sprites():
    """하늘을 천천히 흐르는 구름 여섯 가지 (아래에서 올려다본 구름 밑면, 투명):
    0~2 뭉게구름, 3 조각조각 흩어진 층적운, 4 길게 쓸린 새털구름, 5 넓게 덮인 비구름.
    큰 덩어리 모양(부드러운 잡음)을 문턱값으로 잘라 윤곽이 실제 구름처럼 불규칙하고, 두꺼운 가운데는 그늘져 어둡고 얇은 가장자리는 밝게 비침"""
    W, H = 1024, 512
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    u, v = xx / W - 0.5, yy / H - 0.5
    def env(rx, ry, seed, warp=0.25):
        wx = (noise(3.2, W, seed, h=H) - 0.5) * warp
        wy = (noise(3.2, W, seed + 1, h=H) - 0.5) * warp
        return np.clip(1 - np.sqrt(((u + wx) / rx) ** 2 + ((v + wy) / ry) ** 2), 0, 1)
    def finish(i, d, lo, hi, base_dark=0.36):
        a = np.clip((d - lo) / (hi - lo), 0, 1)
        a = a * a * (3 - 2 * a)
        thick = np.clip((d - hi) / max(0.05, (d.max() - hi)), 0, 1)
        lit = 0.98 - base_dark * thick ** 0.8 + 0.04 * (noise(2.0, W, 90 + i, h=H) - 0.5)
        rgb = np.stack([lit * 244, lit * 247, lit * 252], axis=-1)
        save_png(f'cloud_{i}', rgb, a, folder='sky')
    for i, (rx, ry, sd) in enumerate([(0.42, 0.36, 11), (0.46, 0.3, 12), (0.36, 0.42, 13)]):
        big = noise(3.0, W, sd + 100, h=H)
        mid = noise(2.2, W, sd + 200, h=H)
        d = env(rx, ry, sd) * 1.6 * (0.55 * big + 0.3 * mid + 0.15)
        finish(i, d, 0.42, 0.75)
    # 층적운: 넓게 퍼진 잡음을 촘촘히 잘라 조각조각
    cells = noise(2.4, W, 301, h=H, aniso=(1.0, 0.7))
    d = np.clip(env(0.5, 0.46, 300, 0.15) * 2.2, 0, 1) * (0.25 + 1.0 * cells)
    finish(3, d, 0.6, 0.85, base_dark=0.25)
    # 새털구름: 바람에 길게 쓸린 결
    st = noise(2.0, W, 311, h=H, aniso=(1.0, 0.07))
    d = np.clip(env(0.48, 0.34, 310, 0.3) * 2.0, 0, 1) * (0.2 + 1.1 * st)
    finish(4, d, 0.55, 0.95, base_dark=0.06)
    # 비구름: 넓게 덮인 무거운 덩어리
    big = noise(2.8, W, 321, h=H)
    mid = noise(2.0, W, 322, h=H)
    d = np.clip(env(0.5, 0.48, 320, 0.3) * 2.0, 0, 1) * (0.7 * big + 0.3 * mid)
    finish(5, d, 0.3, 0.62, base_dark=0.5)


# ───────────── 지평선 띠 (원기둥에 둘러 붙임, 위는 투명) ─────────────
def ridge(W, seed, base, amp, beta=2.2, sharp=0.0):
    """윗선 높이 (0=그림 맨 위, 1=맨 아래) — x마다"""
    v = noise1(W, beta, seed)
    if sharp:
        v = v ** (1 + sharp)
    return np.clip(base - amp * (v - 0.5) * 2, 0.02, 0.98)


def band_far_mountains(name, seed, col, snow=False):
    W, H = 4096, 1024                     # 고해상도 (먼 산도 가장자리가 또렷하게)
    top = ridge(W, seed, 0.55, 0.42, beta=2.4)
    top2 = ridge(W, seed + 1, 0.72, 0.22, beta=2.0)
    yy = np.mgrid[0:H, 0:W][0] / H
    a = (yy >= top[None, :]).astype(float)
    a2 = (yy >= top2[None, :])
    n = noise(1.8, W, seed + 2, h=H)
    base = np.array(col, float)
    rgb = base * (0.92 + 0.12 * n)[..., None]
    # 해 쪽 비탈이 밝게 (능선 기울기를 부드럽게 해서), 위쪽일수록 옅게
    sm = np.convolve(np.concatenate([top[-80:], top, top[:80]]), np.ones(81) / 81, 'same')[80:-80]
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
        ya = max(0, int(top - h * 0.25)); yb = min(H, int(ground * H) + 1)     # 이 나무가 차지하는 줄만 계산 (빠르게)
        sub_y = yy[ya:yb, :1]
        lf = leaf[ya:yb][:, xs]
        if kind == 'pine':
            t = (sub_y - top) / h                                   # 0 꼭대기 → 1 밑
            tiers = 0.6 + 0.4 * ((t * 8 + lf * 0.6) % 1)            # 가지 층 톱니
            half = np.clip(t, 0, 1) * w * tiers * (0.8 + 0.4 * lf)
            crown = (t >= 0) & (t <= 0.86) & (np.abs(sub_x) <= half)
            lk = 0.55 - 0.45 * sub_x / np.maximum(half, 1) + 0.25 * ((t * 8) % 1) - 0.2 * t
        else:
            # 잎 덩어리 여러 개가 모인 수관
            crown = np.zeros((yb - ya, len(xs)), bool)
            lk = np.zeros((yb - ya, len(xs)))
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
        a[ya:yb, xs] = np.where(m, 1, a[ya:yb][:, xs])
        light[ya:yb, xs] = np.where(m, np.clip(lk, 0, 1), light[ya:yb][:, xs])
        depth[ya:yb, xs] = np.where(m, d, depth[ya:yb][:, xs])
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


def band_trees(name, seed, kind, H=2048, count=90, hmin=0.45, hmax=0.92, dark=(18, 34, 26), lit=(70, 104, 64)):
    rgb, a = tree_line(4096, H, seed, count, hmin, hmax, kind, dark, lit)
    save_png(name, rgb, a)


def band_ridge_pines(name, seed, col):
    """먼 능선 + 위에 바늘처럼 솟은 소나무들"""
    W, H = 4096, 1024
    top = ridge(W, seed, 0.62, 0.28, beta=2.6)
    r = rng(seed + 1)
    spikes = np.zeros(W)
    for _ in range(1400):
        cx = r.random() * W; h = r.uniform(0.04, 0.12); w = r.uniform(4, 10)
        xs = np.arange(int(cx - w), int(cx + w) + 1)
        v = h * (1 - np.abs(xs - cx) / w)
        spikes[xs % W] = np.maximum(spikes[xs % W], v)
    top = np.clip(top - spikes, 0.02, 0.98)
    yy = np.mgrid[0:H, 0:W][0] / H
    a = (yy >= top[None, :]).astype(float)
    n = noise(1.2, W, seed + 2, h=H)
    rgb = np.array(col, float) * (0.85 + 0.25 * n)[..., None]
    save_png(name, rgb, a)


def _photo_cliff():
    """받아 둔 실사 암벽 사진 (없으면 None)"""
    try:
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        import fetch_env
        p = fetch_env.tex_path(fetch_env.TEXTURES['cliff'])
        if os.path.exists(p):
            return np.asarray(Image.open(p).convert('RGB')).astype(np.float32)
    except Exception as e:
        print('  암벽 사진 읽기 실패:', e, flush=True)
    return None


def band_cliffs(name, seed, H=2048):
    W = 4096
    top = ridge(W, seed, 0.3, 0.26, beta=1.8)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    a = (yy / H >= top[None, :]).astype(float)
    photo = _photo_cliff()
    if photo is not None:
        # 실사 암벽 사진을 띠에 이어 붙임: 사진 한 장 = 띠 높이의 45% (가로·세로 비율 그대로), 이음새는 좌우 뒤집어 이어 보이지 않게
        tile = int(H * 0.45)
        im = Image.fromarray(np.clip(photo, 0, 255).astype(np.uint8)).resize((tile, tile), Image.LANCZOS)
        t = np.asarray(im).astype(np.float32)
        t2 = np.concatenate([t, t[:, ::-1]], axis=1)
        t4 = np.concatenate([t2, t2[::-1]], axis=0)
        reps_x = W // t4.shape[1] + 2
        reps_y = H // t4.shape[0] + 2
        big = np.tile(t4, (reps_y, reps_x, 1))
        # 줄마다 조금씩 옆으로 밀어 같은 무늬가 줄지어 보이지 않게
        off = (noise1(H, 2.6, seed + 9) * tile * 0.6).astype(int)
        rgb = np.stack([big[y, off[y]:off[y] + W] for y in range(H)])
        lum = _lum(rgb).mean()
        rgb = rgb * (128.0 / max(1.0, lum))
        # 큰 바위 기둥 그늘 + 아래로 갈수록 어둡게 (골짜기 안쪽) + 꼭대기 풀
        cols = noise1(W, 2.2, seed + 6)
        g = np.gradient(np.convolve(np.concatenate([cols[-80:], cols, cols[:80]]), np.ones(121) / 121, 'same')[80:-80]) * W * 0.03
        rgb = rgb * (0.92 + np.clip(g, -0.16, 0.16))[None, :, None]
        depth = yy / H - top[None, :]
        rgb = rgb * (1 - 0.28 * np.clip(depth / 0.7, 0, 1))[..., None]
        fine = noise(1.3, W, seed + 5, h=H)
        grass = (depth < 0.025 + 0.03 * fine) & (a > 0)
        rgb[grass] = lerp(rgb[grass], np.array([66, 88, 48.0]), 0.7)
        save_png(name, rgb, a)
        print('  실사 절벽 띠:', name, flush=True)
        return
    warp = noise(2.8, W, seed + 3, h=H) * 9
    strata = np.sin(yy / H * 2 * np.pi * 9 + warp) * 0.5 + 0.5
    big = noise(3.0, W, seed + 4, h=H)
    fine = noise(1.3, W, seed + 5, h=H)
    base = 0.5 * big + 0.2 * fine + 0.3 * strata
    rgb = colorize(base, [(0, (84, 70, 58)), (0.45, (140, 116, 92)), (0.8, (184, 160, 128)), (1, (206, 186, 154))])
    # 큰 바위 기둥: 해 쪽 면은 밝고 반대는 그늘
    cols = noise1(W, 2.2, seed + 6)
    g = np.gradient(np.convolve(np.concatenate([cols[-80:], cols, cols[:80]]), np.ones(121) / 121, 'same')[80:-80]) * W * 0.03
    rgb = rgb * (0.94 + np.clip(g, -0.14, 0.14))[None, :, None]
    cracks = np.abs(noise(1.6, W, seed + 7, h=H, aniso=(1, 0.25)) - 0.5) < 0.008
    rgb[cracks] *= 0.55
    # 꼭대기 근처에 풀·작은 나무
    depth = yy / H - top[None, :]
    grass = (depth < 0.03 + 0.03 * fine) & (a > 0)
    rgb[grass] = lerp(rgb[grass], np.array([70, 92, 50.0]), 0.75)
    save_png(name, rgb, a)


def band_village(name, seed, night=False):
    """먼 언덕 마을 띠 (가로 4096 — 둘레에 두 번만 되풀이): 언덕을 따라 기운 밭 + 띄엄띄엄 모인 집들.
    집마다 크기·벽 색(흰·크림·나무·돌)·지붕 색(붉은 기와·푸른 슬레이트·갈색·초록)·지붕 모양(박공·모임)이 다르고,
    밤엔 창마다 켜진 것과 꺼진 것이 섞임"""
    W, H = 4096, 512
    top = ridge(W, seed, 0.6, 0.25, beta=3.0)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    a = (yy / H >= top[None, :]).astype(float)
    d1, d2, idx = voronoi(W, 220, seed + 1, Hh=H)
    tones = rng(seed + 2).random(220)[idx]
    fields = colorize(tones, [(0, (70, 104, 46)), (0.4, (112, 140, 58)), (0.7, (168, 160, 84)), (1, (190, 170, 100))])
    rows = np.sin((xx * 0.6 + yy * 2.4) * 0.25 + idx) * 0.5 + 0.5
    rgb = fields * (0.85 + 0.15 * rows)[..., None]
    rgb[(d2 - d1) < 1.5] *= 0.75
    r = rng(seed + 3)
    walls_c = [(214, 206, 190), (226, 214, 180), (150, 112, 78), (170, 164, 150), (200, 204, 206)]
    roofs_c = [(150, 62, 44), (78, 86, 100), (96, 70, 52), (70, 94, 70), (120, 48, 36)]
    lit_mask = np.zeros((H, W), bool)
    rw = rng(seed + 9)                       # 창 불빛은 따로 (낮·밤 그림의 집 자리가 같게)
    # 마을 몇 곳에 집이 모여 있고 그 사이는 듬성듬성
    centers = [r.random() * W for _ in range(7)]
    for _ in range(60):
        cx = int((r.choice(centers) + r.normal(0, 110)) % W) if r.random() < 0.75 else int(r.random() * W)
        gy = int(top[cx] * H + r.uniform(10, 120))
        if gy >= H - 4:
            continue
        w = int(r.uniform(10, 34)); h = int(w * r.uniform(0.45, 0.75))
        x0, x1 = cx - w // 2, cx + w // 2
        xs = np.arange(x0, x1) % W
        y0 = max(0, gy - h)
        wc = np.array(walls_c[r.integers(len(walls_c))], float) * r.uniform(0.85, 1.08)
        rgb[y0:gy, xs] = wc
        rgb[y0:gy, xs[-max(1, w // 4):]] = wc * 0.72            # 그늘진 옆면
        a[y0:gy, xs] = 1
        rc = np.array(roofs_c[r.integers(len(roofs_c))], float) * r.uniform(0.85, 1.1)
        rh = int(h * r.uniform(0.45, 0.8))
        hip = r.random() < 0.35
        for k in range(rh):
            yv = y0 - rh + k
            if yv < 0:
                continue
            t = k / max(1, rh - 1)
            ext = int(t * 3)
            if hip:
                ra = np.arange(int(x0 + (1 - t) * w * 0.3) - ext, int(x1 - (1 - t) * w * 0.3) + ext) % W
            else:
                ra = np.arange(x0 - ext, x1 + ext) % W
            rgb[yv, ra] = rc * (0.8 + 0.2 * t)
            a[yv, ra] = 1
        # 굴뚝 (가끔)
        if r.random() < 0.4 and y0 - rh - 4 > 0:
            chx = np.arange(x0 + w // 4, x0 + w // 4 + 3) % W
            rgb[y0 - rh - 4:y0 - rh + 3, chx] = [110, 70, 56]; a[y0 - rh - 4:y0 - rh + 3, chx] = 1
        # 창: 낮엔 어두운 유리, 밤엔 일부만 켜짐
        for wx in range(x0 + 3, x1 - 4, 6):
            win = (slice(gy - h + 3, gy - h + 3 + max(2, h // 3)), np.arange(wx, wx + 3) % W)
            if rw.random() < 0.45 and night:
                lit_mask[win] = True
            else:
                rgb[win] = wc * 0.45
    if night:
        rgb = rgb * np.array([0.32, 0.36, 0.5])
        rgb[lit_mask] = [255, 205, 128]
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


def roof_tile():
    """시골집 지붕 기와 (밝은 회색 바탕 — 앱에서 집마다 붉은·푸른·갈색·초록으로 물들임): 가로 줄마다 엇갈린 둥근 기와,
    줄 아래쪽은 그늘, 기와마다 조금씩 다른 밝기와 얼룩"""
    N = 512
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)
    rows, cols = 16, 10
    ry = yy / (N / rows)
    row = np.floor(ry)
    fy = ry - row
    cx = (xx / (N / cols) + 0.5 * (row % 2))
    col = np.floor(cx)
    fx = cx - col
    curve = np.sin(fx * np.pi) ** 0.6                       # 둥근 기와 굴곡 (가운데 밝음)
    shade = 0.55 + 0.35 * curve
    shade = shade * (0.7 + 0.3 * np.clip(fy * 1.6, 0, 1))  # 위 줄 기와 밑 그늘
    tone = rng(711).random((rows + 1, cols + 2))[row.astype(int) % (rows + 1), col.astype(int) % (cols + 2)]
    v = shade * (0.82 + 0.3 * tone) * (0.9 + 0.2 * noise(1.8, N, 712))
    gap = (fx < 0.04) | (fx > 0.96)
    v[gap] *= 0.55
    save_jpg('roof_tile', colorize(np.clip(v / 1.2, 0, 1), [(0, (60, 58, 56)), (0.6, (168, 164, 158)), (1, (220, 216, 210))]), q=90)


def speaker_art():
    """카페 천장 스피커: 무광 검은 금속 통(가는 헤어라인 결) + 촘촘한 구멍 뚫린 철망(타공판)"""
    N = 256
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)
    hair = noise(1.4, N, 611, aniso=(0.08, 4.0))
    v = 0.55 + 0.3 * hair + 0.15 * noise(2.2, N, 612)
    save_jpg('speaker_metal', colorize(v, [(0, (26, 26, 28)), (0.6, (44, 44, 47)), (1, (66, 66, 70))]), q=90)
    # 타공판: 엇갈린 줄의 둥근 구멍 (구멍 속은 더 어둡고, 판은 짙은 회색)
    p = 16.0
    row = np.floor(yy / (p * 0.866))
    cx = (xx + (row % 2) * p / 2) % p - p / 2
    cy = yy % (p * 0.866) - p * 0.433
    d = np.hypot(cx, cy)
    hole = np.clip((5.2 - d) / 1.2, 0, 1)
    plate = 0.62 + 0.12 * noise(1.6, N, 613)
    v = plate * (1 - hole) + 0.08 * hole
    # 구멍 아래쪽 가장자리에 살짝 빛 (판의 두께)
    rim = np.clip(1 - np.abs(d - 5.6) / 1.0, 0, 1) * (cy > 0)
    v = v + 0.12 * rim
    save_jpg('speaker_grille', colorize(np.clip(v, 0, 1), [(0, (8, 8, 9)), (0.6, (52, 52, 55)), (1, (92, 92, 96))]), q=92)


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
    """냇가 바위 둑 (1m) — 크고 작은 둥근 바위가 겹겹이 놓이고 윗면엔 이끼, 틈엔 풀·고사리.
    낮게 깔려서 그 너머 계곡 풍경(폭포·절벽·강)이 잘 보임"""
    yy, xx = np.mgrid[0:BH, 0:BW].astype(np.float32)
    rgb = np.zeros((BH, BW, 3)); a = np.zeros((BH, BW))
    r = rng(221)
    grain = noise(2.3, BW, 222, h=BH)
    fine = noise(1.2, BW, 223, h=BH)
    crack = noise(1.8, BW, 227, h=BH, aniso=(0.4, 2.2))
    mossn = noise(2.0, BW, 226, h=BH)
    shape = noise(3.2, BW, 229, h=BH)          # 윤곽을 매끈하게 울퉁불퉁 (털처럼 보풀지 않게)
    # 뒤 줄(작고 높게) → 앞 줄(크고 낮게) 순으로 겹쳐 그림
    rows = [(0.8, 0.18, 0.34, 30), (0.93, 0.24, 0.46, 22), (1.06, 0.3, 0.56, 14)]
    for ri, (base, hmin, hmax, cnt) in enumerate(rows):
        for _ in range(cnt):
            cx = r.random() * BW
            h = r.uniform(hmin, hmax) * BH
            w = h * r.uniform(0.55, 0.95)
            cy = base * BH - h * 0.5
            tilt = r.uniform(-0.25, 0.25)
            dx = (xx - cx + BW / 2) % BW - BW / 2
            nx = dx / w; ny = (yy - cy) / (h * 0.5) + tilt * nx
            # 둥근 바위 윤곽 (모서리가 조금 각진 둥근 덩어리)
            rr = (np.abs(nx) ** 2.4 + np.abs(ny) ** 2.2) ** (1 / 2.3) + 0.22 * (shape - 0.5)
            m = rr < 1
            if not m.any():
                continue
            # 빛: 위·왼쪽이 밝고 아래·오른쪽이 그늘, 가장자리로 갈수록 둥글게 어두워짐
            nz = np.sqrt(np.clip(1 - rr ** 2, 0, 1))
            lit = np.clip(0.35 + 0.55 * nz - 0.28 * ny - 0.12 * nx, 0.12, 1.1)
            tone = r.uniform(0.75, 1.15)
            warm = r.uniform(-1, 1) * np.array([10, 4, -8.0])        # 바위마다 조금씩 다른 빛깔 (회색·누런 회색·푸른 회색)
            base_c = colorize(0.6 * grain + 0.4 * fine, [(0, (70, 68, 64)), (0.5, (118, 114, 106)), (1, (164, 158, 146))]) + warm
            c = shade(base_c, lit * tone * (0.82 + 0.18 * np.clip(crack * 1.6 - 0.3, 0, 1)))
            # 이끼: 윗면(빛 받는 쪽)에 얼룩덜룩
            mk = m & (ny < -0.15) & (mossn > 0.66 - 0.12 * (-ny))
            c[mk] = lerp(c[mk], np.array([66, 88, 44.0]) * lit[mk][:, None], 0.65)
            rgb[m] = c[m]; a[m] = 1
            # 바닥 그늘 (다음 줄 바위가 덮음)
    # 틈과 앞의 풀·고사리
    g_rgb, g_a = grass_tufts(228, 1.0, 0.04, 0.18, (30, 48, 24), (104, 132, 64), count=140)
    rgb, a = over(rgb, a, g_rgb, g_a)
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


def foliage_cards():
    """입체 나무용 잎 덩어리 그림 (투명): 넓은잎 덩이 leaf_clump, 소나무 가지 pine_branch, 야자 잎 palm_frond.
    나무 하나를 이런 잎 판 수십 장을 사방으로 엇갈려 꽂아 만들어, 어느 쪽에서 봐도 둥근 부피가 있는 나무로 보임"""
    S2 = 2
    def leafpoly(cx, cy, L, Wd, ang):
        pts = []
        for k in range(12):
            t = k / 11
            x = (t - 0.5) * L
            y = math.sin(t * math.pi) * Wd / 2
            pts.append((x, y))
        for k in range(10, 0, -1):
            t = k / 11
            pts.append(((t - 0.5) * L, -math.sin(t * math.pi) * Wd / 2))
        ca, sa = math.cos(ang), math.sin(ang)
        return [((cx + x * ca - y * sa) * S2, (cy + x * sa + y * ca) * S2) for x, y in pts]
    # 넓은잎 덩이: 둥근 덩어리 안에 잎 수백 장, 위(빛 쪽)는 밝고 아래·안쪽은 어둡게
    W = 512
    r = rng(2101)
    im = Image.new('RGBA', (W * S2, W * S2), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    for i in range(900):
        ang = r.uniform(0, 2 * math.pi); rad = (r.random() ** 0.6) * W * 0.4
        cx, cy = W / 2 + math.cos(ang) * rad, W / 2 + math.sin(ang) * rad * 0.9
        light = np.clip(0.55 - (cy - W / 2) / W * 0.9 + (rad / W) * 0.3 + r.normal(0, 0.12), 0, 1)
        col = tuple(int(c) for c in lerp(np.array([22, 44, 18.0]), np.array([118, 158, 62.0]), light)) + (255,)
        d.polygon(leafpoly(cx, cy, r.uniform(26, 44), r.uniform(12, 20), r.uniform(0, math.pi)), fill=col)
    im = im.resize((W, W), Image.LANCZOS)
    arr = np.asarray(im).astype(np.float32)
    save_png('leaf_clump', arr[..., :3], arr[..., 3] / 255)
    # 소나무 가지: 가운데 가는 가지에서 바늘잎이 양쪽으로, 끝으로 갈수록 짧게 (가지 끝이 오른쪽)
    Wb, Hb = 512, 256
    r = rng(2102)
    im = Image.new('RGBA', (Wb * S2, Hb * S2), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.line([(8 * S2, Hb / 2 * S2), ((Wb - 10) * S2, (Hb / 2 - 6) * S2)], fill=(70, 52, 36, 255), width=6 * S2)
    for i in range(1400):
        t = r.random()
        x = 10 + t * (Wb - 24); y = Hb / 2 - 6 * t
        L = (1 - t * 0.6) * r.uniform(40, 100)
        side = r.choice([-1, 1]); ang = side * r.uniform(0.5, 1.3) + 0.25
        x2, y2 = x + math.cos(ang) * L * 0.6, y + math.sin(ang) * L
        light = np.clip(0.5 - side * 0.2 + r.normal(0, 0.15), 0, 1)
        col = tuple(int(c) for c in lerp(np.array([14, 36, 22.0]), np.array([70, 112, 60.0]), light)) + (255,)
        d.line([(x * S2, y * S2), (x2 * S2, y2 * S2)], fill=col, width=2 * S2)
    im = im.resize((Wb, Hb), Image.LANCZOS)
    arr = np.asarray(im).astype(np.float32)
    save_png('pine_branch', arr[..., :3], arr[..., 3] / 255)
    # 야자 잎: 가운데 잎줄기에서 길쭉한 작은 잎이 빗살처럼 늘어짐 (잎 끝이 오른쪽)
    Wp, Hp = 1024, 256
    r = rng(2103)
    im = Image.new('RGBA', (Wp * S2, Hp * S2), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.line([(4 * S2, Hp / 2 * S2), ((Wp - 6) * S2, Hp / 2 * S2)], fill=(120, 110, 60, 255), width=7 * S2)
    for i in range(170):
        t = i / 170
        x = 20 + t * (Wp - 40)
        for side in (-1, 1):
            L = (math.sin(min(1, t * 1.15) * math.pi) * 0.85 + 0.15) * Hp * 0.48 * r.uniform(0.85, 1.05)
            ang = side * (1.0 + r.normal(0, 0.08)) + 0.35
            x2, y2 = x + math.cos(ang) * L * 0.45, Hp / 2 + math.sin(ang) * L
            light = np.clip(0.55 - side * 0.15 + r.normal(0, 0.1), 0, 1)
            col = tuple(int(c) for c in lerp(np.array([30, 62, 22.0]), np.array([120, 160, 64.0]), light)) + (255,)
            d.polygon([(x * S2, Hp / 2 * S2), ((x + 3) * S2, Hp / 2 * S2), (x2 * S2, y2 * S2), ((x2 - 4) * S2, (y2 - side * 2) * S2)], fill=col)
    im = im.resize((Wp, Hp), Image.LANCZOS)
    arr = np.asarray(im).astype(np.float32)
    save_png('palm_frond', arr[..., :3], arr[..., 3] / 255)
    # 바람에 날리는 낙엽 입자 (흰 잎 모양 — 입자 색으로 물듦, 가운데 잎맥)
    S3 = 64
    im = Image.new('RGBA', (S3 * S2, S3 * S2), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.polygon(leafpoly(S3 / 2, S3 / 2, S3 * 0.82, S3 * 0.44, 0.5), fill=(250, 250, 250, 255))
    ca, sa = math.cos(0.5), math.sin(0.5)
    d.line([((S3 / 2 - ca * S3 * 0.36) * S2, (S3 / 2 - sa * S3 * 0.36) * S2), ((S3 / 2 + ca * S3 * 0.36) * S2, (S3 / 2 + sa * S3 * 0.36) * S2)], fill=(200, 200, 200, 255), width=3)
    im = im.resize((S3, S3), Image.LANCZOS)
    arr = np.asarray(im).astype(np.float32)
    save_png('leaf_bit', arr[..., :3], arr[..., 3] / 255)


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
    """전시관 벽: 매끈한 흰 대리석 느낌 (아주 옅은 회색 결 + 가는 물결 무늬)"""
    v = 0.7 * noise(0.5, N, 381) + 0.3 * noise(2.4, N, 382)
    rgb = colorize(v, [(0, (230, 228, 222)), (1, (248, 247, 243))])
    warp = noise(2.6, N, 383) * 6
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)
    vein = np.abs(np.sin((xx * 0.004 + yy * 0.007) * 6 + warp)) < 0.035
    vein2 = np.abs(np.sin((xx * 0.006 - yy * 0.003) * 5 + warp * 1.3)) < 0.02
    rgb[vein] *= 0.9
    rgb[vein2] *= 0.94
    rgb = np.asarray(Image.fromarray(np.clip(rgb, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2))).astype(np.float32)
    save_jpg('plaster', rgb)


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
        # 밤: 불 켜진 창은 4분의 1쯤만, 창마다 밝기·빛깔(따뜻한 빛·형광등·커튼 너머 어스름)이 다름 → 네온이 돋보이게 차분히
        rgb = rgb * 0.22
        cell = lit[yy // 32, xx // 32]
        tone = rng(465).random((S // 32, S // 32))[yy // 32, xx // 32]
        on = cell > 0.74
        dimw = (cell > 0.62) & ~on
        warm = np.array([255, 204, 136.0]) * (0.55 + 0.45 * tone)[..., None]
        cool = np.array([196, 214, 236.0]) * (0.5 + 0.4 * tone)[..., None]
        col = np.where((tone > 0.7)[..., None], cool, warm)
        rgb[win] = [12, 15, 22]
        rgb[win & on] = col[win & on]
        rgb[win & dimw] = (np.array([96, 70, 48.0]) * (0.6 + 0.4 * tone)[..., None])[win & dimw]
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
    cat_sounds(r)
    dog_sounds(r)
    misc_sounds(r)
    water_sounds(r)
    neon_sounds(r)
    splash_sounds(r)


def _formant_voice(f0, F, amp, r, breath=0.06, nasal=None):
    """목소리 합성: f0(표본마다 음높이) 톱니파 + 숨소리 → 표본마다 바뀌는 공명(포먼트) 3개를 지남"""
    n = len(f0)
    ph = np.cumsum(f0 * (1 + 0.01 * _lowpass(r.standard_normal(n), 30))) / SR
    src = 2 * (ph % 1.0) - 1
    src = src - _lowpass(src, 120)                                  # 웅웅거림 빼기
    src += breath * r.standard_normal(n)
    out = np.zeros(n)
    for k, (fc, bw) in enumerate(F):
        y1 = y2 = 0.0
        y = np.zeros(n)
        R = np.exp(-np.pi * bw / SR)
        for i in range(n):
            c = 2 * R * np.cos(2 * np.pi * fc[i] / SR)
            v = src[i] * (1 - R) + c * y1 - R * R * y2
            y[i] = v
            y2, y1 = y1, v
        out += y * (1.0, 0.7, 0.35)[k]
    if nasal is not None:                                           # 입을 닫은 'ㅁ' 소리: 낮게 거른 소리로 시작
        low = _lowpass(src, 500)
        out = out * (1 - nasal) + low * nasal * 3
    return out * amp


def _contour(n, pts):
    """[(0~1 위치, 값)] 을 잇는 매끈한 곡선"""
    x = np.linspace(0, 1, n)
    xs, ys = zip(*pts)
    return _lowpass(np.interp(x, xs, ys), 40) if n > 4000 else np.interp(x, xs, ys)


def cat_sounds(r):
    """집 고양이 방울이 소리: 야옹(보통·짧은 냥·물음표 므르앙?) · 그르릉 되풀이 · 반가운 트릴(브르릉) · 짧은 짹(신남)"""
    def meow(name, dur, f0pts, f1, f2, f3, peak, roll=0.0, nas=0.15):
        n = int(SR * dur)
        f0 = _contour(n, f0pts)
        F = [(_contour(n, f1), 160), (_contour(n, f2), 220), (_contour(n, f3), 300)]
        env = np.interp(np.linspace(0, 1, n), [0, 0.08, 0.7, 1], [0, 1, 0.85, 0])
        if roll > 0:                                               # 혀를 굴리는 'ㄹㄹ' (빠르게 떨림)
            t = _t(dur)
            env *= 1 - roll * (0.5 + 0.5 * np.sin(2 * np.pi * 27 * t)) * np.interp(t / dur, [0, 0.35, 0.5, 1], [1, 1, 0, 0])
        nasal = np.interp(np.linspace(0, 1, n), [0, 0.12, 0.25, 1], [nas * 4, nas * 2, 0, 0]).clip(0, 0.8)
        x = _formant_voice(f0, F, env, r, nasal=nasal)
        save_wav(name, x, peak)
    # 보통 야옹 (미-아-옹)
    meow('cat_meow1', 0.72, [(0, 430), (0.3, 760), (0.6, 640), (1, 380)],
         [(0, 450), (0.2, 520), (0.45, 1050), (0.8, 900), (1, 560)], [(0, 1800), (0.2, 2600), (0.5, 1900), (0.85, 1300), (1, 1000)],
         [(0, 3400), (0.5, 3300), (1, 2900)], -10)
    # 짧고 높은 냥
    meow('cat_meow2', 0.32, [(0, 680), (0.4, 880), (1, 640)],
         [(0, 500), (0.3, 900), (1, 760)], [(0, 2400), (0.4, 2100), (1, 1600)], [(0, 3600), (1, 3200)], -12, nas=0.08)
    # 물음표 므르앙? (끝이 올라감)
    meow('cat_meow3', 0.62, [(0, 420), (0.3, 470), (0.7, 560), (1, 820)],
         [(0, 420), (0.35, 600), (0.7, 950), (1, 800)], [(0, 1400), (0.35, 1600), (0.7, 2000), (1, 2300)],
         [(0, 3000), (1, 3400)], -11, roll=0.8, nas=0.2)
    # 반가운 트릴 (브르릉↗)
    meow('cat_trill', 0.48, [(0, 500), (0.6, 560), (1, 690)],
         [(0, 450), (0.5, 520), (1, 620)], [(0, 1300), (1, 1700)], [(0, 2800), (1, 3000)], -13, roll=1.0, nas=0.3)
    # 짧은 짹 (신나서)
    meow('cat_chirp', 0.14, [(0, 900), (0.5, 1250), (1, 1000)],
         [(0, 700), (1, 800)], [(0, 2600), (1, 2400)], [(0, 3800), (1, 3600)], -15, nas=0.0)
    # 그르릉 되풀이 (들숨·날숨이 번갈아, 초당 26번쯤 떨림) 6초
    dur = 7.0
    n = int(SR * dur)
    t = _t(dur)
    rate = 26 + 2 * np.sign(np.sin(2 * np.pi * t / 3.0))
    ph = np.cumsum(rate) / SR
    pulse = (0.5 + 0.5 * np.cos(2 * np.pi * ph)) ** 3
    noise = _lowpass(r.standard_normal(n), 380)
    buzz = np.sin(2 * np.pi * np.cumsum(rate * 2) / SR) * 0.4
    breath = 0.55 + 0.45 * np.abs(np.sin(np.pi * t / 3.0))
    x = (noise / (np.std(noise) + 1e-9) * 0.5 + buzz) * pulse * breath
    save_wav('cat_purr', _loop(x, 0.5), -10)

    # ── 더 많은 목소리 (매번 다르게 들리도록 같은 종류도 여러 개) ──
    for i in range(4, 10):                                          # 야옹 4~9: 길이·높이·모음이 조금씩 다른 야옹
        dur = r.uniform(0.38, 0.95)
        base = r.uniform(380, 620)
        peak = base * r.uniform(1.25, 1.75)
        endp = base * r.uniform(0.7, 1.15)
        mid = r.uniform(0.2, 0.45)
        meow(f'cat_meow{i}', dur, [(0, base), (mid, peak), (min(0.9, mid + 0.3), peak * 0.85), (1, endp)],
             [(0, 450), (mid * 0.6, 560), (mid + 0.15, r.uniform(900, 1150)), (0.85, 800), (1, 520)],
             [(0, r.uniform(1700, 2300)), (mid, r.uniform(2300, 2700)), (0.7, r.uniform(1500, 1900)), (1, 1050)],
             [(0, 3400), (1, 3000)], -10 - r.uniform(0, 3), roll=r.choice([0, 0, 0.4]), nas=r.uniform(0.05, 0.25))
    for i in range(1, 4):                                           # 므릅 (짧게 굴리는 인사)
        dur = r.uniform(0.22, 0.34)
        b = r.uniform(420, 560)
        meow(f'cat_mrrp{i}', dur, [(0, b), (0.6, b * 1.15), (1, b * r.uniform(1.2, 1.5))],
             [(0, 420), (1, 640)], [(0, 1300), (1, 1800)], [(0, 2800), (1, 3100)], -12, roll=1.0, nas=0.35)
    for i in range(2, 4):                                           # 짹 (신남)
        b = r.uniform(850, 1150)
        meow(f'cat_chirp{i}', r.uniform(0.09, 0.15), [(0, b), (0.5, b * 1.3), (1, b * 1.05)],
             [(0, 700), (1, 820)], [(0, 2500), (1, 2300)], [(0, 3700), (1, 3500)], -14, nas=0.0)
    # 아기 고양이 같은 미야 (높고 가늘게)
    meow('cat_mew', 0.28, [(0, 900), (0.4, 1150), (1, 820)], [(0, 600), (0.4, 950), (1, 700)],
         [(0, 2600), (0.5, 2300), (1, 1900)], [(0, 3800), (1, 3500)], -13, nas=0.05)
    # 하품: 숨소리 섞인 높은 '아아앙' 끝이 내려감
    n = int(SR * 1.1)
    f0 = _contour(n, [(0, 520), (0.2, 900), (0.5, 760), (1, 300)])
    F = [(_contour(n, [(0, 700), (0.3, 1100), (1, 600)]), 200), (_contour(n, [(0, 1700), (1, 1100)]), 260), (_contour(n, [(0, 3000), (1, 2700)]), 320)]
    env = np.interp(np.linspace(0, 1, n), [0, 0.15, 0.6, 1], [0, 0.8, 0.6, 0])
    save_wav('cat_yawn', _formant_voice(f0, F, env, r, breath=0.35), -14)
    # 채터링 (창밖 새·장난감을 노려볼 때 '깍깍깍')
    buf = np.zeros(int(SR * 1.0))
    at = 0.05
    while at < 0.85:
        n = int(SR * 0.05)
        b = r.uniform(700, 900)
        f0 = np.full(n, b)
        F = [(np.full(n, 800.0), 200), (np.full(n, 2000.0), 260), (np.full(n, 3200.0), 320)]
        env = np.sin(np.linspace(0, np.pi, n)) ** 2
        _place(buf, _formant_voice(f0, F, env, r, breath=0.2), at)
        at += r.uniform(0.07, 0.1)
    save_wav('cat_chatter', buf, -15)
    # 하악 (화났을 때)
    n = int(SR * 0.7)
    h = r.standard_normal(n)
    h = _lowpass(h - _lowpass(h, 1800), 7000)
    env = np.interp(np.linspace(0, 1, n), [0, 0.05, 0.6, 1], [0, 1, 0.7, 0])
    save_wav('cat_hiss', h * env, -12)
    # 낮게 그르르 (불만)
    n = int(SR * 0.9)
    f0 = _contour(n, [(0, 160), (0.5, 180), (1, 150)])
    F = [(np.full(n, 500.0), 180), (np.full(n, 1200.0), 240), (np.full(n, 2500.0), 300)]
    t = _t(0.9)
    env = np.interp(np.linspace(0, 1, n), [0, 0.1, 0.8, 1], [0, 1, 0.8, 0]) * (0.6 + 0.4 * np.sin(2 * np.pi * 22 * t))
    save_wav('cat_growl', _formant_voice(f0, F, env, r, breath=0.15), -14)
    # 목줄 방울 딸랑 (걸을 때 가끔, 뛰면 자주)
    for i in range(1, 4):
        buf = np.zeros(int(SR * 0.9))
        for k in range(r.integers(2, 5)):
            f = r.uniform(4200, 5600)
            _place(buf, _bell(f, 0.6, 9, partials=((1, 1), (1.47, 0.4), (2.09, 0.2))) * r.uniform(0.4, 1), k * r.uniform(0.04, 0.09))
        save_wav(f'bell{i}', buf, -20)


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

    # 장작이 탁 튀는 소리 (불티가 확 오를 때) 3가지
    for i in range(1, 4):
        buf = np.zeros(int(SR * 0.5))
        c = r.standard_normal(int(SR * 0.012))
        c = c - _lowpass(c, 900)
        c *= np.exp(-_t(0.012) * 500)
        _place(buf, c, 0)
        for k in range(r.integers(2, 6)):                          # 뒤따르는 잔 타닥
            ln = r.uniform(0.002, 0.005)
            cc = r.standard_normal(int(SR * ln))
            cc = (cc - _lowpass(cc, 2500)) * np.exp(-_t(ln) * 1500)
            _place(buf, cc * r.uniform(0.15, 0.4), r.uniform(0.03, 0.35))
        t = _t(0.2)
        _place(buf, np.sin(2 * np.pi * 110 * t) * np.exp(-t * 40) * 0.3, 0)
        save_wav(f'fire_pop{i}', buf, -8)


def dog_sounds(r):
    """시골 강아지 설이 (허스키): 멍(짧고 굵게)·왈(높게)·아우우 하울링·낑낑·헥헥(되풀이)·킁킁·신난 낑·놀자 그르릉, 이름표 짤랑"""
    def voice(name, dur, f0pts, f1, f2, f3, peak, noise=0.2, nas=0.0, roll=0.0):
        n = int(SR * dur)
        f0 = _contour(n, f0pts)
        F = [(_contour(n, f1), 220), (_contour(n, f2), 280), (_contour(n, f3), 360)]
        env = np.interp(np.linspace(0, 1, n), [0, 0.06, 0.55, 1], [0, 1, 0.75, 0])
        if roll > 0:
            t = _t(dur)
            env *= 1 - roll * (0.5 + 0.5 * np.sin(2 * np.pi * 30 * t))
        nasal = np.full(n, nas)
        x = _formant_voice(f0, F, env, r, breath=noise, nasal=nasal if nas > 0 else None)
        save_wav(name, x, peak)
    # 멍 (짧고 굵은 짖음) 3가지
    for i in range(1, 4):
        b = r.uniform(240, 330)
        voice(f'dog_bark{i}', r.uniform(0.16, 0.22), [(0, b * 1.4), (0.25, b * 1.2), (1, b * 0.8)],
              [(0, 650), (0.3, 800), (1, 500)], [(0, 1300), (1, 1100)], [(0, 2500), (1, 2300)], -4, noise=0.45)
    # 왈 (높고 짧게, 신나서)
    for i in range(1, 3):
        b = r.uniform(520, 680)
        voice(f'dog_yip{i}', r.uniform(0.09, 0.13), [(0, b), (0.4, b * 1.25), (1, b * 0.9)],
              [(0, 700), (1, 800)], [(0, 1700), (1, 1500)], [(0, 3000), (1, 2800)], -8, noise=0.25)
    # 아우우 하울링 (길게 오르내림)
    voice('dog_howl', 2.6, [(0, 330), (0.25, 520), (0.55, 560), (0.8, 500), (1, 380)],
          [(0, 500), (0.2, 750), (0.6, 600), (1, 420)], [(0, 1100), (0.3, 1200), (0.7, 900), (1, 800)], [(0, 2500), (1, 2300)], -8, noise=0.08)
    # 낑낑 (높게 떨림)
    voice('dog_whine', 0.9, [(0, 900), (0.3, 1150), (0.6, 1000), (1, 1250)], [(0, 600), (1, 650)], [(0, 1800), (1, 2000)],
          [(0, 3200), (1, 3300)], -14, noise=0.12, nas=0.4)
    # 놀자 그르릉 (장난)
    voice('dog_playgrowl', 0.8, [(0, 140), (0.5, 170), (1, 130)], [(0, 500), (1, 520)], [(0, 1100), (1, 1000)], [(0, 2400), (1, 2300)],
          -12, noise=0.3, roll=0.9)
    # 헥헥 (되풀이 4초)
    dur = 4.0
    n = int(SR * dur)
    t = _t(dur)
    h = r.standard_normal(n)
    h = _lowpass(h - _lowpass(h, 700), 4000)
    rate = 3.2
    ph = (t * rate) % 1.0
    env = np.where(ph < 0.45, np.sin(ph / 0.45 * np.pi) ** 2, 0.35 * np.sin((ph - 0.45) / 0.55 * np.pi) ** 2)
    save_wav('dog_pant', _loop(h * env, 0.3), -18)
    # 킁킁 (냄새 맡기)
    buf = np.zeros(int(SR * 0.8))
    for k in range(3):
        nn = int(SR * 0.08)
        x = r.standard_normal(nn)
        x = _lowpass(x - _lowpass(x, 1500), 6000) * np.sin(np.linspace(0, np.pi, nn)) ** 2
        _place(buf, x, 0.05 + k * 0.17)
    save_wav('dog_sniff', buf, -16)
    # 이름표 짤랑 (걸을 때)
    for i in range(1, 3):
        buf = np.zeros(int(SR * 0.4))
        for k in range(r.integers(1, 3)):
            _place(buf, _bell(r.uniform(3000, 3800), 0.3, 16, partials=((1, 1), (2.7, 0.5), (5.2, 0.2))) * r.uniform(0.5, 1), k * r.uniform(0.03, 0.07))
        save_wav(f'dog_tag{i}', buf, -22)


def water_sounds(r):
    """계곡 물소리: 졸졸 흐르는 개울(되풀이) · 멀리 떨어지는 폭포(되풀이)"""
    dur = 10.0
    n = int(SR * dur)
    t = _t(dur)
    base = _lowpass(r.standard_normal(n), 1800)
    base = base - _lowpass(base, 200)
    base *= 0.35 * (0.8 + 0.2 * np.sin(2 * np.pi * 0.17 * t))
    buf = base.copy()
    at = 0.0
    while at < dur - 0.1:                                          # 보글보글 물방울 (짧게 오르는 음)
        at += r.exponential(1 / 22)
        ln = r.uniform(0.015, 0.05)
        tt = _t(ln)
        f = r.uniform(500, 1600)
        bub = np.sin(2 * np.pi * np.cumsum(f * (1 + 2.5 * tt / ln)) / SR) * np.exp(-tt * 70) * r.uniform(0.1, 0.4)
        _place(buf, bub, at)
    save_wav('stream_loop', _loop(buf, 1.0), -12)
    b = np.cumsum(r.standard_normal(n)) * 0.02
    b -= _lowpass(b, 6)
    roar = _lowpass(b, 900) + 0.3 * _lowpass(r.standard_normal(n), 3000)
    save_wav('fall_loop', _loop(roar, 1.0), -12)


def splash_sounds(r):
    """얕은 물을 걷는 첨벙 소리 네 가지: 발이 물을 차는 '촤'(넓은 잡음) + 물이 출렁이는 낮은 소리 + 떨어지는 물방울(오르는 짧은 음)"""
    for i in range(1, 5):
        dur = 0.9
        buf = np.zeros(int(SR * dur))
        # 차는 소리: 밝은 잡음이 빠르게 커졌다 사라짐
        ln = r.uniform(0.12, 0.2)
        n = r.standard_normal(int(SR * ln))
        hp = _lowpass(n - _lowpass(n, 700), 7000)
        env = np.interp(_t(ln), [0, 0.012, ln], [0, 1, 0]) ** 1.6
        _place(buf, hp * env * 0.9, 0.0)
        # 출렁임: 낮게 거른 잡음, 조금 늦게
        ln2 = r.uniform(0.25, 0.4)
        n2 = r.standard_normal(int(SR * ln2))
        env2 = np.interp(_t(ln2), [0, 0.06, ln2], [0, 1, 0])
        _place(buf, _lowpass(n2, 650) * env2 * 1.6, r.uniform(0.02, 0.06))
        # 물방울: 짧게 위로 미끄러지는 음 여러 개
        for k in range(r.integers(4, 9)):
            dl = r.uniform(0.02, 0.06)
            tt = _t(dl)
            f0 = r.uniform(700, 2200)
            ph = 2 * np.pi * np.cumsum(f0 * (1 + 2.2 * tt / dl)) / SR
            drop = np.sin(ph) * np.exp(-tt * r.uniform(60, 120)) * r.uniform(0.12, 0.35)
            _place(buf, drop, r.uniform(0.05, 0.5))
        save_wav(f'splash{i}', buf, -5)          # 또렷하게 (예전 -14는 물소리에 묻힘)


def neon_sounds(r):
    """네온사인: 낮게 웅웅거리는 변압기 소리(되풀이) · 깜빡일 때 지직 하는 소리 두 가지"""
    dur = 6.0
    n = int(SR * dur)
    t = _t(dur)
    hum = (np.sin(2 * np.pi * 120 * t) * 0.6 + np.sin(2 * np.pi * 240 * t) * 0.25 + np.sin(2 * np.pi * 360 * t) * 0.1)
    hum *= 0.8 + 0.2 * np.sin(2 * np.pi * 0.31 * t)
    buzz = _lowpass(r.standard_normal(n), 3000) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 120 * t))) * 0.06
    save_wav('neon_hum', _loop(hum * 0.5 + buzz, 1.0), -24)
    for i in range(1, 3):
        buf = np.zeros(int(SR * 0.5))
        at = 0.0
        for k in range(r.integers(3, 7)):
            ln = r.uniform(0.006, 0.03)
            x = r.standard_normal(int(SR * ln))
            x = (x - _lowpass(x, 1500)) * np.exp(-_t(ln) * 60)
            _place(buf, x * r.uniform(0.4, 1), at)
            at += r.uniform(0.02, 0.07)
        save_wav(f'neon_flick{i}', buf, -20)


def misc_sounds(r):
    """별자리 반짝(맑은 종 두 음), 카페 에스프레소 머신 스팀, 잔 부딪히는 소리"""
    buf = np.zeros(int(SR * 2.4))
    _place(buf, _bell(1318.5, 2.2, 1.6) * 0.6, 0)
    _place(buf, _bell(1975.5, 2.0, 1.8) * 0.45, 0.12)
    _place(buf, _bell(2637.0, 1.8, 2.2) * 0.25, 0.22)
    save_wav('star_chime', buf, -16)
    # 스팀 (우유 데우는 치이익 → 보글보글)
    dur = 3.2
    n = int(SR * dur)
    t = _t(dur)
    h = r.standard_normal(n)
    hiss = _lowpass(h - _lowpass(h, 3000), 9000) * np.interp(t, [0, 0.1, 2.6, dur], [0, 1, 0.8, 0])
    gurgle = _lowpass(r.standard_normal(n), 600) * (0.5 + 0.5 * np.sin(2 * np.pi * 9 * t)) * np.interp(t, [0, 1.2, 2.4, dur], [0, 0, 1, 0]) * 2
    save_wav('espresso_steam', hiss + gurgle, -22)
    # 잔·접시 달그락
    for i in range(1, 3):
        buf = np.zeros(int(SR * 0.8))
        for k in range(r.integers(1, 3)):
            _place(buf, _bell(r.uniform(2400, 3400), 0.5, 14, partials=((1, 1), (2.32, 0.5), (4.1, 0.25))), k * r.uniform(0.08, 0.2))
        save_wav(f'cup_clink{i}', buf, -24)


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


def fire_art():
    """모닥불: 일렁이는 불길 16장(이어 돌리면 끊김 없이 타오름), 연기 한 덩이, 숯이 된 장작 무늬"""
    W, H, F = 128, 256, 16
    n1 = noise(beta=2.6, size=256, seed=911, aniso=(1.0, 0.45))   # 위로 흘러가는 큰 불길 덩어리 (세로로 길쭉, 가장자리가 이어짐)
    n2 = noise(beta=2.2, size=256, seed=912, aniso=(1.0, 0.6))    # 작은 불혀
    n3 = noise(beta=3.0, size=256, seed=913)                      # 옆으로 흔들림
    yy, xx = np.mgrid[0:H, 0:W].astype(float)
    y = 1 - yy / (H - 1)                                # 0 아래 ~ 1 위
    x = (xx - W / 2) / (W / 2)
    for f in range(F):
        sh = int(f * 256 / F)
        a1 = np.roll(n1, sh, axis=0)[:H, :W]
        a2 = np.roll(n2, sh * 2, axis=0)[:H, :W]
        a3 = np.roll(n3, sh, axis=0)[:H, 64:64 + W]
        xd = x + (a3 - 0.5) * 0.9 * y ** 1.3           # 위로 갈수록 크게 흔들림
        width = 0.68 * (1 - y) ** 0.7 + 0.04
        shape = np.clip(1 - (np.abs(xd) / np.maximum(width, 1e-3)) ** 2, 0, 1)
        base = np.clip(y * 10, 0, 1)                    # 바닥은 부드럽게
        heat = shape * base * (1.15 - y * 0.8) * (1 - (a1 - 0.38) * 1.7 * y ** 0.7 - (a2 - 0.5) * 0.6 * y)
        heat = np.clip(heat, 0, 1)
        heat = np.asarray(Image.fromarray((heat * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.2))) / 255
        col = colorize(heat, [(0, (110, 16, 0)), (0.3, (196, 44, 6)), (0.55, (246, 108, 18)),
                              (0.78, (255, 178, 56)), (0.93, (255, 232, 160)), (1, (255, 250, 225))])
        alpha = np.clip((heat - 0.1) * 3.2, 0, 1)
        save_png(f'fire_{f:02d}', col, alpha)
    # 연기 한 덩이 (입자 그림: 흰색 + 투명도)
    S2 = 128
    yy, xx = np.mgrid[0:S2, 0:S2].astype(float)
    d = np.hypot(xx - S2 / 2, yy - S2 / 2) / (S2 / 2)
    nz = noise(beta=1.8, size=S2, seed=921)
    a = np.clip((1 - d) * 1.25 - (nz - 0.5) * 0.6, 0, 1) ** 1.8
    a = np.asarray(Image.fromarray((a * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(4))) / 255.0   # 가장자리 부드럽게 (덩어리 테두리가 안 보이게)
    a *= np.clip((1 - d) * 3, 0, 1)
    rgba = np.concatenate([np.full((S2, S2, 3), 245.0), (a * 255)[..., None]], axis=-1)
    os.makedirs(os.path.join(OUT, 'tex'), exist_ok=True)
    Image.fromarray(rgba.astype(np.uint8), 'RGBA').save(os.path.join(OUT, 'tex', 'smoke_puff.png'), optimize=True)
    # 불티·숯불 알갱이 (가운데가 밝은 작은 점)
    a = np.clip(1 - d, 0, 1) ** 2.5
    rgba = np.concatenate([np.full((S2, S2, 3), 255.0), (a * 255)[..., None]], axis=-1)
    Image.fromarray(rgba.astype(np.uint8), 'RGBA').save(os.path.join(OUT, 'tex', 'spark_dot.png'), optimize=True)
    # 숯이 된 장작: 검게 탄 나무결 + 갈라진 틈에 주황 불씨
    N2 = 256
    grain = noise(beta=1.4, size=N2, seed=931, aniso=(4, 0.25))
    crack = noise(beta=2.0, size=N2, seed=932, aniso=(1.5, 0.6))
    v = 0.6 * grain + 0.4 * crack
    rgb = colorize(v, [(0, (18, 14, 12)), (0.5, (44, 36, 30)), (1, (70, 58, 48))])
    sparse = noise(beta=2.4, size=N2, seed=933) > 0.55
    glow = np.clip((np.abs(crack - 0.5) < 0.022) * sparse * 1.0, 0, 1)
    glow = np.asarray(Image.fromarray((glow * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.6))) / 255
    rgb = rgb * (1 - glow[..., None]) + np.array([255, 110, 30]) * glow[..., None]
    save_jpg('charlog', rgb)


def stream_art():
    """계곡 개울·폭포: 흐르는 물(길이 방향 v로 이어짐), 물 위 반짝임(투명), 떨어지는 폭포 물줄기(세로로 이어짐, 양옆 투명)"""
    N = 512
    # 개울: 물길 방향(세로)으로 늘어진 물결 + 깊은 곳은 짙은 청록, 얕은 곳·물살은 밝게
    big = noise(beta=2.6, size=N, seed=1701, aniso=(0.35, 1.0))
    mid = noise(beta=2.0, size=N, seed=1702, aniso=(0.2, 1.0))
    fine = noise(beta=1.4, size=N, seed=1703, aniso=(0.15, 1.0))
    v = 0.5 * big + 0.32 * mid + 0.18 * fine
    rgb = colorize(v, [(0, (18, 52, 58)), (0.35, (34, 84, 88)), (0.6, (62, 122, 120)), (0.8, (118, 168, 160)), (0.92, (196, 222, 214)), (1, (236, 246, 242))])
    save_jpg('river', rgb)
    # 반짝이는 물살 (드문드문 흰 줄)
    st = noise(beta=1.8, size=N, seed=1704, aniso=(0.12, 1.0))
    a = np.clip((st - 0.68) * 5.5, 0, 1) ** 1.3
    save_png('river_hi', np.full((N, N, 3), 250.0), a * 0.9)
    # 폭포: 가로 512 × 세로 1024 (세로로 이어짐). 하얗게 부서지며 떨어지는 굵은 물줄기 여러 가닥 + 사이사이 가는 물줄기,
    # 가운데는 빽빽하고 양옆은 가닥이 갈라지며 투명하게 흩어짐. 물줄기 속은 공기 섞인 거품 결 + 그늘진 푸른 회색
    W, H = 512, 1024
    rope = noise(beta=2.2, size=W, h=H, seed=1711, aniso=(0.035, 1.0))
    thin = noise(beta=1.6, size=W, h=H, seed=1712, aniso=(0.02, 1.0))
    foam = noise(beta=1.1, size=W, h=H, seed=1713, aniso=(0.25, 1.0))
    sheet = noise(beta=2.8, size=W, h=H, seed=1714, aniso=(0.06, 1.0))
    x = np.linspace(-1, 1, W)[None, :]
    body = np.clip(1 - np.abs(x) ** 2.6, 0, 1)
    edge = np.clip((np.abs(x) - 0.45) / 0.55, 0, 1)                         # 0 가운데 → 1 가장자리
    strands = np.clip((rope - 0.42) * 3.2, 0, 1) * 0.7 + np.clip((thin - 0.5) * 4, 0, 1) * 0.5
    dens = body * (0.8 * (1 - edge) + strands * (0.4 + 0.8 * edge))
    dens = dens * (0.75 + 0.5 * sheet)
    a = np.clip(dens * 1.25, 0, 1) ** 1.15
    vv = np.clip(0.45 * rope + 0.25 * thin + 0.3 * foam, 0, 1)
    rgb = colorize(vv, [(0, (124, 150, 158)), (0.35, (178, 200, 206)), (0.6, (222, 234, 237)), (0.82, (244, 249, 250)), (1, (255, 255, 255))])
    hi = np.clip((foam - 0.6) * 3, 0, 1)[..., None]
    rgb = rgb * (1 - hi * 0.4) + 255 * hi * 0.4
    save_png('fall', rgb, a)
    # 걸을 때 발밑에 퍼지는 물결 고리 (가운데 투명, 고리 두 겹)
    S = 256
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    d = np.hypot(xx - S / 2 + 0.5, yy - S / 2 + 0.5) / (S / 2)
    wob = noise(beta=2.0, size=S, seed=1715) * 0.05
    ring = np.exp(-((d + wob - 0.82) / 0.05) ** 2) + 0.55 * np.exp(-((d + wob - 0.6) / 0.04) ** 2)
    save_png('ripple', np.full((S, S, 3), 250.0), np.clip(ring, 0, 1) * (d < 1))


def jelly_art():
    """해파리: 갓(가로 = 둘레, 세로 = 가장자리→꼭대기) — 가장자리 띠는 밝고, 방사형 관·네 잎 생식소 무늬, 꼭대기로 갈수록 투명.
    촉수(세로로 긴 띠, 아래로 갈수록 가늘고 옅게)·입팔(주름진 넓은 띠)"""
    W = H = 256
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    v = 1 - yy / (H - 1)                     # 0 가장자리 → 1 꼭대기 (그림 아래가 가장자리)
    u = xx / W
    canals = np.clip(np.cos(u * 2 * np.pi * 8) * 0.5 + 0.5, 0, 1) ** 30 * (1 - v) * 0.9
    lobes = np.clip(np.cos(u * 2 * np.pi * 4) * 0.5 + 0.5, 0, 1) ** 3 * np.exp(-((v - 0.62) / 0.12) ** 2)
    rim = np.exp(-(v / 0.06) ** 2)
    fine = noise(1.4, W, 2101)
    lum = np.clip(0.35 + 0.65 * rim + 0.55 * canals + 0.6 * lobes + 0.12 * (fine - 0.5), 0, 1)
    a = np.clip(0.22 + 0.5 * rim + 0.35 * canals + 0.45 * lobes - 0.12 * v, 0.08, 1)
    save_png('jelly_bell', np.stack([lum * 255] * 3, -1), a)
    # 촉수 (32×512): 가운데가 진하고 아래로 갈수록 옅어짐, 작은 마디
    Wt, Ht = 32, 512
    yy, xx = np.mgrid[0:Ht, 0:Wt].astype(np.float32)
    d = np.abs(xx - Wt / 2) / (Wt / 2)
    k = yy / Ht                              # 0 위 → 1 아래
    beads = 0.75 + 0.25 * np.cos(yy / Ht * 2 * np.pi * 26) ** 2
    a = np.clip((1 - d ** 1.5) * (1 - k ** 1.3) * beads, 0, 1)
    save_png('jelly_tent', np.full((Ht, Wt, 3), 245.0), a)
    # 입팔 (64×256): 물결치는 주름 가장자리
    Wo, Ho = 64, 256
    yy, xx = np.mgrid[0:Ho, 0:Wo].astype(np.float32)
    edge = 0.75 + 0.25 * np.sin(yy / Ho * 2 * np.pi * 9)
    d = np.abs(xx - Wo / 2) / (Wo / 2)
    a = np.clip((edge - d) * 4, 0, 1) * (1 - (yy / Ho) ** 2) * 0.85
    fr = np.clip(1 - np.abs(d - edge * 0.85) * 6, 0, 1)
    save_png('jelly_arm', np.stack([200 + 55 * fr] * 3, -1), a)


def fish_art():
    """물고기 무늬 6가지 (가로 = 머리→꼬리, 세로 = 등→배): 비단잉어(주홍·흰 얼룩), 금빛, 은빛 피라미(옆줄), 줄무늬,
    파랑·노랑, 검은 반점 붉은 물고기. 등은 진하고 배는 밝게"""
    W, H = 256, 128
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    u = xx / W; v = yy / H                    # v 0 등 → 1 배
    belly = np.clip((v - 0.45) * 2, 0, 1)
    back = np.clip((0.45 - v) * 2.2, 0, 1)
    specs = []
    n1 = noise(3.6, W, 2201, h=H)
    koi = np.where((n1 > 0.52)[..., None], np.array([236, 92, 34.0]), np.array([246, 240, 232.0]))
    specs.append(koi)
    gold = np.array([238, 170, 50.0]) * (0.9 + 0.2 * noise(1.5, W, 2202, h=H))[..., None]
    specs.append(gold)
    silver = np.array([176, 186, 196.0]) * (0.95 + 0.1 * np.sin(u * 60))[..., None]
    lat = np.exp(-((v - 0.5) / 0.05) ** 2)[..., None]
    silver = silver * (1 - 0.4 * lat) + np.array([90, 110, 160.0]) * 0.4 * lat
    specs.append(silver)
    stripes = (np.sin(u * 2 * np.pi * 5) > 0.35)[..., None]
    specs.append(np.where(stripes, np.array([40, 40, 46.0]), np.array([236, 214, 120.0])))
    by = np.where((v < 0.5)[..., None], np.array([40, 110, 210.0]), np.array([246, 214, 60.0]))
    specs.append(by)
    spots = (noise(3.4, W, 2203, h=H) > 0.62)[..., None]
    specs.append(np.where(spots, np.array([30, 24, 24.0]), np.array([214, 56, 46.0])))
    for i, base in enumerate(specs):
        rgb = base * (1 - 0.35 * back[..., None]) + 255 * 0.25 * belly[..., None]
        # 비늘 결
        scale = 0.94 + 0.06 * np.sin(u * 140 + np.sin(v * 30) * 2) * np.sin(v * 90)
        rgb = rgb * scale[..., None]
        save_jpg(f'fish_{i}', rgb, q=90)


NEON_COLORS = [(255, 60, 170), (40, 230, 255), (255, 70, 60), (170, 90, 255), (255, 190, 40), (70, 255, 120), (60, 120, 255), (255, 240, 220)]


def _neon_glyphs(d, r, x0, y0, x1, y1, lw):
    """글자 같기도 그림 같기도 한 모양 (알아볼 수 없는 기호): 칸마다 획 2~4개 — 곧은 획·둥근 획·점·고리"""
    def U(lo, hi):
        return r.uniform(min(lo, hi), max(lo, hi) + 1e-3)
    cells = max(1, int((x1 - x0) / max(1, (y1 - y0) * 0.8)))
    cw = (x1 - x0) / cells
    segs = []
    for c in range(cells):
        cx0 = x0 + c * cw + cw * 0.12; cx1 = x0 + (c + 1) * cw - cw * 0.12
        for _ in range(r.integers(2, 5)):
            kind = r.integers(0, 4)
            if kind == 0:
                ax, ay = U(cx0, cx1), U(y0, y1)
                bx, by = U(cx0, cx1), U(y0, y1)
                segs.append(('line', (ax, ay, bx, by)))
            elif kind == 1:
                rr = r.uniform(0.18, 0.45) * min(cw, y1 - y0)
                cx, cy = U(cx0 + rr, cx1 - rr), U(y0 + rr, y1 - rr)
                st = r.uniform(0, 360)
                segs.append(('arc', (cx - rr, cy - rr, cx + rr, cy + rr, st, st + r.uniform(120, 300))))
            elif kind == 2:
                rr = r.uniform(0.12, 0.3) * min(cw, y1 - y0)
                cx, cy = U(cx0 + rr, cx1 - rr), U(y0 + rr, y1 - rr)
                segs.append(('ring', (cx - rr, cy - rr, cx + rr, cy + rr)))
            else:
                ax = U(cx0, cx1)
                segs.append(('line', (ax, y0, ax + r.uniform(-0.2, 0.2) * cw, y1)))
    return segs


def _draw_segs(d, segs, lw):
    for k, p in segs:
        if k == 'line':
            d.line(p, fill=255, width=lw)
        elif k == 'arc':
            d.arc(p[:4], p[4], p[5], fill=255, width=lw)
        else:
            d.ellipse(p, outline=255, width=lw)


def neon_art():
    """네온사인 16개 (가로형 10, 세로형 6) × 두 장(번갈아 켜지는 부분): 유리관 가운데는 하얗게 타고 둘레로 색 빛이 번짐.
    읽을 수 없는 기호 + 테두리 관(일부는 끊긴 선)·화살표·심장·잔 같은 그림 조각"""
    S = 2                                     # 두 배로 그려 줄여 매끈하게
    for i in range(16):
        r = rng(2301 + i)
        vert = i >= 10
        W, H = (256, 1024) if vert else (1024, 256)
        col = np.array(NEON_COLORS[i % len(NEON_COLORS)], float)
        col2 = np.array(NEON_COLORS[(i * 3 + 2) % len(NEON_COLORS)], float)
        frames = []
        # 공통: 테두리 관
        pad = 18
        lw = int(r.uniform(9, 14)) * S
        border = Image.new('L', (W * S, H * S), 0)
        bd = ImageDraw.Draw(border)
        style = r.integers(0, 3)
        if style == 0:
            bd.rounded_rectangle((pad * S, pad * S, (W - pad) * S, (H - pad) * S), radius=40 * S, outline=255, width=lw // 2)
        elif style == 1:
            bd.rectangle((pad * S, pad * S, (W - pad) * S, (H - pad) * S), outline=255, width=lw // 2)
        # 글자 (가로형은 한 줄, 세로형은 세로로 쌓은 기호)
        g1 = Image.new('L', (W * S, H * S), 0)
        g2 = Image.new('L', (W * S, H * S), 0)
        d1 = ImageDraw.Draw(g1); d2 = ImageDraw.Draw(g2)
        if vert:
            n = r.integers(3, 6)
            ch = (H - 2 * pad - 30) / n
            for k in range(n):
                y0 = pad + 15 + k * ch
                segs = _neon_glyphs(d1, r, (pad + 30) * S, (y0 + ch * 0.12) * S, (W - pad - 30) * S, (y0 + ch * 0.88) * S, lw)
                _draw_segs(d1 if k % 2 == 0 or r.random() < 0.6 else d2, segs, lw)
        else:
            icon = r.random() < 0.55
            x_text0 = pad + 40 + (H if icon else 0)
            segs = _neon_glyphs(d1, r, x_text0 * S, (pad + 40) * S, (W - pad - 40) * S, (H - pad - 40) * S, lw)
            _draw_segs(d1, segs, lw)
            if icon:
                # 그림 조각: 잔·심장·화살표·별 비슷한 모양 (두 번째 장에서만 일부가 바뀌어 움직이는 느낌)
                cx, cy, rr = (pad + 40 + H / 2 - 20) * S, H / 2 * S, (H / 2 - pad - 34) * S
                k = r.integers(0, 4)
                if k == 0:     # 잔
                    d1.line((cx - rr, cy - rr * 0.7, cx + rr, cy - rr * 0.7), fill=255, width=lw)
                    d1.line((cx - rr, cy - rr * 0.7, cx, cy + rr * 0.2), fill=255, width=lw)
                    d1.line((cx + rr, cy - rr * 0.7, cx, cy + rr * 0.2), fill=255, width=lw)
                    d1.line((cx, cy + rr * 0.2, cx, cy + rr * 0.9), fill=255, width=lw)
                    d2.ellipse((cx + rr * 0.2, cy - rr * 1.1, cx + rr * 0.6, cy - rr * 0.7), outline=255, width=lw // 2)
                elif k == 1:   # 심장 비슷
                    d1.arc((cx - rr, cy - rr, cx, cy), 150, 360, fill=255, width=lw)
                    d1.arc((cx, cy - rr, cx + rr, cy), 180, 30, fill=255, width=lw)
                    d1.line((cx - rr * 0.93, cy - rr * 0.25, cx, cy + rr), fill=255, width=lw)
                    d1.line((cx + rr * 0.93, cy - rr * 0.25, cx, cy + rr), fill=255, width=lw)
                    d2.ellipse((cx - rr * 1.25, cy - rr * 1.25, cx + rr * 1.25, cy + rr * 1.25), outline=255, width=lw // 3)
                elif k == 2:   # 화살표 (두 장이 번갈아 → 움직임)
                    for kk, dd in ((0, d1), (1, d2)):
                        off = kk * rr * 0.5
                        dd.line((cx - rr + off, cy, cx + rr * 0.3 + off, cy), fill=255, width=lw)
                        dd.line((cx + rr * 0.3 + off, cy, cx - rr * 0.1 + off, cy - rr * 0.5), fill=255, width=lw)
                        dd.line((cx + rr * 0.3 + off, cy, cx - rr * 0.1 + off, cy + rr * 0.5), fill=255, width=lw)
                else:          # 별 비슷
                    pts = []
                    for q in range(10):
                        a = q / 10 * 2 * np.pi - np.pi / 2
                        rad = rr if q % 2 == 0 else rr * 0.45
                        pts.append((cx + np.cos(a) * rad, cy + np.sin(a) * rad))
                    d1.line(pts + [pts[0]], fill=255, width=lw, joint='curve')
                    d2.ellipse((cx - rr * 0.2, cy - rr * 0.2, cx + rr * 0.2, cy + rr * 0.2), outline=255, width=lw // 2)
        b = np.asarray(border.resize((W, H), Image.LANCZOS)).astype(np.float32) / 255
        a1 = np.asarray(g1.resize((W, H), Image.LANCZOS)).astype(np.float32) / 255
        a2 = np.asarray(g2.resize((W, H), Image.LANCZOS)).astype(np.float32) / 255
        for fi, tubes in enumerate([(a1, a2 * 0.0, b), (a1, a2, b)]):
            main = np.clip(tubes[0] + tubes[1], 0, 1)
            bord = tubes[2]
            def glow(m, rad):
                im = Image.fromarray((np.clip(m, 0, 1) * 255).astype(np.uint8))
                return np.asarray(im.filter(ImageFilter.GaussianBlur(rad))).astype(np.float32) / 255
            gm = np.clip(glow(main, 6) * 1.6 + glow(main, 22) * 1.4, 0, 1)
            gb = np.clip(glow(bord, 6) * 1.6 + glow(bord, 22) * 1.4, 0, 1)
            core_m = np.clip(main * 1.2, 0, 1); core_b = np.clip(bord * 1.2, 0, 1)
            rgb = col[None, None, :] * gm[..., None] + col2[None, None, :] * gb[..., None]
            hot = np.clip(core_m + core_b, 0, 1)
            rgb = rgb * (1 - hot[..., None] * 0.7) + 255 * hot[..., None] * 0.7 + (col * 0.3)[None, None, :] * hot[..., None]
            a = np.clip(np.maximum(hot, (gm + gb) * 0.85), 0, 1)
            save_png(f'neon_{i:02d}{"ab"[fi]}', np.clip(rgb, 0, 255), a)


def street_shops(night=False):
    """카페 창밖 맞은편 거리: 2~4층 건물이 늘어서고 1층은 차양 달린 가게(진열창·문·간판), 가로등.
    가로 2048 × 세로 512 (= 높이 9m 띠), 하늘은 투명. 밤엔 가게 창과 일부 위층 창, 가로등에 불"""
    W, H = 2048, 512
    r = rng(1501)
    rgb = np.zeros((H, W, 3))
    a = np.zeros((H, W))
    lit = np.zeros((H, W), bool)
    tex = noise(1.2, 512, 1502)
    ground = int(H * 0.98)                        # 길 높이 (띠 아래 끝 근처)
    m = 57                                        # 1m = 약 57px
    x = 0
    palettes = [(150, 84, 66), (196, 176, 140), (120, 128, 132), (86, 120, 116), (172, 120, 84), (210, 196, 170), (98, 86, 110)]
    awn = [((176, 40, 44), (240, 232, 220)), ((40, 96, 70), (236, 228, 210)), ((32, 60, 120), (232, 226, 210)), ((200, 140, 40), (90, 50, 30))]
    while x < W:
        bw = int(r.integers(int(4.5 * m), int(8 * m)))
        bw = min(bw, W - x) if W - x - bw < 2 * m else bw
        floors = int(r.integers(2, 4))
        fh = int(2.6 * m)
        top = ground - fh * floors - int(0.4 * m)
        x1 = min(W, x + bw)
        base = np.array(palettes[int(r.integers(len(palettes)))], float)
        t2 = np.tile(tex, (H // 512 + 1, W // 512 + 1))[:H, :W]
        rgb[top:ground, x:x1] = base * (0.85 + 0.25 * t2[top:ground, x:x1, None])
        a[top:ground, x:x1] = 1
        rgb[top:top + 10, x:x1] = base * 0.6                 # 지붕 처마 줄
        rgb[top + 10:top + 14, x:x1] = base * 1.15
        # 위층 창
        cols = max(2, (x1 - x) // int(1.6 * m))
        cw = (x1 - x) / cols
        for f in range(1, floors):
            y0 = ground - fh * (f + 1) + int(0.9 * m)
            for c in range(cols):
                wx0 = int(x + c * cw + cw * 0.28)
                wx1 = int(x + c * cw + cw * 0.72)
                wy1 = y0 + int(1.4 * m)
                if night:
                    on = r.random() < 0.45
                    col = np.array([255, 206, 130.0]) * r.uniform(0.75, 1) if on else np.array([18, 22, 30.0])
                else:
                    col = np.array([150, 170, 190.0]) * r.uniform(0.75, 1)
                rgb[y0:wy1, wx0:wx1] = col
                if night and col[0] > 100:
                    lit[y0:wy1, wx0:wx1] = True
                rgb[y0 - 4:y0, wx0 - 4:wx1 + 4] = base * 0.7          # 창 위 장식
                rgb[wy1:wy1 + 6, wx0 - 6:wx1 + 6] = base * 1.2         # 창턱
        # 1층 가게: 큰 진열창 + 문 + 차양 + 간판
        gy0 = ground - fh
        rgb[gy0:ground, x:x1] = base * 0.55
        sx0, sx1 = x + int(0.4 * m), x1 - int(1.6 * m)
        wy0, wy1 = gy0 + int(1.0 * m), ground - int(0.5 * m)
        if sx1 - sx0 > m:
            if night:
                glow = np.array([255, 196, 120.0])
                rgb[wy0:wy1, sx0:sx1] = glow * (0.85 + 0.1 * t2[wy0:wy1, sx0:sx1, None])
                lit[wy0:wy1, sx0:sx1] = True
            else:
                rgb[wy0:wy1, sx0:sx1] = np.array([70, 84, 96.0]) * (0.9 + 0.3 * t2[wy0:wy1, sx0:sx1, None])
                rgb[wy0:wy0 + int(0.4 * m), sx0:sx1] = np.array([150, 166, 180.0])      # 유리에 비친 하늘
            for mx in range(sx0, sx1, int(1.3 * m)):                                     # 창살
                rgb[wy0:wy1, mx:mx + 4] = base * 0.4
        dx0, dx1 = x1 - int(1.3 * m), x1 - int(0.4 * m)
        rgb[gy0 + int(0.8 * m):ground, dx0:dx1] = np.array([60, 40, 30.0]) if not night else np.array([200, 150, 90.0])
        if night:
            lit[gy0 + int(0.8 * m):ground, dx0:dx1] = True
        ac = awn[int(r.integers(len(awn)))]
        ay0, ay1 = gy0 + int(0.25 * m), gy0 + int(0.95 * m)
        for sx in range(x, x1, 18):                                                      # 줄무늬 차양
            col = np.array(ac[(sx // 18) % 2], float)
            rgb[ay0:ay1, sx:min(x1, sx + 18)] = col * (0.75 if night else 1)
        yy = np.arange(ay0, ay1)
        rgb[ay1 - 6:ay1, x:x1] = np.array(ac[0], float) * 0.6
        # 간판 (글자 대신 단순한 무늬)
        bx0, bx1 = x + (x1 - x) // 4, x + 3 * (x1 - x) // 4
        rgb[gy0 - int(0.45 * m):gy0 - 2, bx0:bx1] = np.array([40, 34, 30.0])
        for k in range(bx0 + 12, bx1 - 12, 22):
            rgb[gy0 - int(0.32 * m):gy0 - int(0.14 * m), k:k + 12] = np.array([236, 206, 140.0]) if night else np.array([214, 196, 160.0])
        x = x1
    # 가로등
    for lx in range(140, W, 520):
        rgb[ground - int(4.4 * m):ground, lx:lx + 8] = [30, 32, 34]
        a[ground - int(4.4 * m):ground, lx:lx + 8] = 1
        hy = ground - int(4.4 * m)
        rgb[hy - 26:hy, lx - 18:lx + 26] = [30, 32, 34]
        a[hy - 26:hy, lx - 18:lx + 26] = 1
        if night:
            rgb[hy - 18:hy - 4, lx - 10:lx + 18] = [255, 226, 160]
            lit[hy - 18:hy - 4, lx - 10:lx + 18] = True
    rgb[ground:, :] = [40, 40, 44]
    a[ground:, :] = 1
    if night:
        rgb = rgb * np.where(lit[..., None], 1.0, 0.42)                            # 불 켜진 곳만 밝게
    save_png('street_shops_night' if night else 'street_shops', rgb, a)


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
        if not fn.endswith('_a.png') or fn.endswith('_lna.png') or fn.startswith('haze') or fn.startswith('scan_grid') or fn.startswith('cat_') or fn.startswith('dog_') or fn.startswith('fire_') or fn.startswith('stream_') or fn.startswith('fall_') or fn.startswith('emote_') or fn.startswith('jelly_') or fn.startswith('neon_') or fn.startswith('moon'):
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


def _fetch_env():
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import fetch_env
    fetch_env.main()


def _jazz():
    """카페 배경 재즈 (tools/jazz.py) → sfx/jazz_XX.m4a + sfx/jazz.json"""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import jazz
    jazz.make_all(os.path.join(OUT, 'sfx'))


def _cat():
    """집 테마 고양이 그림 (tools/cat_art.py) → tex/cat_*.png"""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import cat_art
    cat_art.cat_sprites(os.path.join(OUT, 'tex'))
    import dog_art
    dog_art.dog_sprites(os.path.join(OUT, 'tex'))


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
        'env': lambda: _fetch_env(),          # 실사 하늘·무늬 받기 (캐시에 있으면 건너뜀)
        'sky': lambda: (skies(), cloud_sprites(), moon_art()),
        'bands': lambda: (
            band_far_mountains('far_mtn', 101, (176, 190, 210)),
            band_far_mountains('far_peaks', 111, (160, 172, 190), snow=True),
            band_ridge_pines('mid_ridge', 121, (70, 92, 96)),
            band_trees('near_pines', 131, 'pine'),
            band_trees('near_broad', 141, 'broad', count=110, dark=(22, 38, 20), lit=(86, 120, 56)),
            band_cliffs('mid_cliffs', 151),
            band_village('mid_village', 161), band_village('mid_village_night', 161, night=True),
            band_city('far_city', 171), band_city('far_city_night', 171, night=True),
            band_islands('far_islands', 181),
            photo_band('pano_hills'), photo_band('pano_peaks')),
        'barriers': lambda: (barrier_camp(), barrier_forest(), barrier_valley(), barrier_sea(), barrier_village(), barrier_city()),
        'trees': lambda: (
            tree_single('tree_pine', 'pine', 501, (16, 36, 24), (72, 110, 64)),
            tree_single('tree_broad', 'broad', 502, (24, 44, 20), (110, 148, 64)),
            tree_single('tree_twisted', 'twisted', 503, (20, 40, 28), (78, 112, 70)),
            foliage_cards()),
        'floors': lambda: (
            floor_grass(), floor_moss(), floor_pebble(), floor_sand(), floor_roof(), floor_dirt(),
            floor_planks('planks', [(0, (96, 62, 36)), (0.5, (142, 98, 58)), (1, (184, 136, 88))]),
            floor_planks('planks_dark', [(0, (52, 32, 22)), (0.5, (86, 56, 36)), (1, (126, 86, 56))], rows=16, seed=365),
            floor_marble(), wall_plaster(), wall_brick(), wall_timber(),
            prop_rock('rock', [(0, (66, 64, 60)), (0.5, (116, 110, 102)), (1, (166, 160, 150))], 411),
            prop_rock('mossrock', [(0, (40, 56, 34)), (0.5, (88, 104, 70)), (1, (140, 150, 116))], 413),
            prop_rock('basalt', [(0, (28, 30, 34)), (0.5, (58, 60, 64)), (1, (98, 100, 102))], 415),
            prop_simple('cliff', [(0, (60, 56, 50)), (0.5, (112, 104, 94)), (1, (160, 152, 140))], 427, aniso=(0.35, 1.6)),
            prop_simple('fabric', [(0, (120, 104, 88)), (0.5, (164, 148, 128)), (1, (196, 184, 166))], 429, beta=0.4),
            prop_simple('walnut', [(0, (52, 34, 22)), (0.5, (92, 62, 40)), (1, (136, 96, 62))], 431, aniso=(4, 0.2)),
            prop_simple('oak', [(0, (150, 140, 124)), (0.5, (184, 174, 156)), (1, (214, 206, 190))], 433, aniso=(4, 0.2)),
            prop_simple('bark', [(0, (52, 38, 28)), (0.5, (98, 74, 52)), (1, (140, 110, 80))], 417, aniso=(3, 0.2)),
            prop_simple('driftwood', [(0, (100, 96, 88)), (0.5, (150, 144, 132)), (1, (196, 190, 176))], 419, aniso=(0.2, 3)),
            prop_simple('hay', [(0, (150, 120, 60)), (0.5, (196, 164, 92)), (1, (232, 206, 140))], 423, aniso=(0.3, 2.5)),
            prop_simple('concrete', [(0, (116, 114, 110)), (1, (172, 170, 164))], 425, beta=0.6),
            facade(), facade(night=True), water(), canvas(), paintings(), glow(), scan_grid(), haze(),
            people(), menu_board(), flame(), fire_art(), stream_art(), street_shops(), street_shops(night=True),
            jelly_art(), fish_art(), neon_art(), speaker_art(), roof_tile(),
            photo_textures()),
        'sfx': lambda: sfx(),
        'cat': lambda: _cat(),
        'jazz': lambda: _jazz(),
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
