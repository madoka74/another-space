"""카페 벽 그림 — 칠판 메뉴판과 커피·디저트 포스터 (그림 아이콘 + 알아볼 수 없는 글씨).
- menu_board: 칠판에 분필로 쓴 메뉴 (글씨처럼 보이지만 읽히지 않는 흘림 + 컵·크루아상·케이크 조각 분필 그림)
- cafe_poster_0~3: 라테 아트 잔 · 크루아상 · 딸기 케이크 · 원두와 핸드드립 — 색 바탕 인쇄 포스터 느낌 (종이 결, 가장자리 바램)
각 그림마다 선 그림용 <이름>_ln (흰 바탕에 검은 윤곽선만)도 만듦 — 앱은 선 그림 방에서 _ln 을 읽음.
글씨는 일부러 읽히지 않게: 글자 크기의 둥근 획을 이어 쓴 '흘림 낱말' (실제 글자 X)"""
import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

SS = 2          # 두 배로 그린 뒤 줄여 매끄럽게


class Pad:
    """색 그림과 선 그림을 같은 붓질로 함께 그림 (선 그림은 채우기 대신 윤곽선)"""

    def __init__(self, w, h, bg, line_bg=(255, 255, 255)):
        self.w, self.h = w, h
        self.c = Image.new('RGB', (w * SS, h * SS), bg)
        self.l = Image.new('RGB', (w * SS, h * SS), line_bg)
        self.dc = ImageDraw.Draw(self.c)
        self.dl = ImageDraw.Draw(self.l)

    def _p(self, pts):
        return [(x * SS, y * SS) for x, y in pts]

    def poly(self, pts, fill, outline=None, lw=3.0, line=True):
        p = self._p(pts)
        self.dc.polygon(p, fill=fill)
        if outline is not None:
            self.dc.line(p + [p[0]], fill=outline, width=int(lw * SS), joint='curve')
        if line:
            self.dl.line(p + [p[0]], fill=(20, 20, 20), width=int(3.2 * SS), joint='curve')

    def ellipse(self, c, rx, ry, fill, outline=None, lw=3.0, line=True, ang=0.0, n=64):
        a = math.radians(ang)
        pts = []
        for k in range(n):
            t = k / n * 2 * math.pi
            x, y = rx * math.cos(t), ry * math.sin(t)
            pts.append((c[0] + x * math.cos(a) - y * math.sin(a), c[1] + x * math.sin(a) + y * math.cos(a)))
        self.poly(pts, fill, outline, lw, line)
        return pts

    def stroke(self, pts, col, w, line=True, lcol=(20, 20, 20), lw=None):
        self.dc.line(self._p(pts), fill=col, width=max(1, int(w * SS)), joint='curve')
        if line:
            self.dl.line(self._p(pts), fill=lcol, width=max(1, int((lw or min(w, 3.2)) * SS)), joint='curve')

    def rect(self, x0, y0, x1, y1, fill, line=True):
        self.poly([(x0, y0), (x1, y0), (x1, y1), (x0, y1)], fill, line=line)

    def done(self):
        c = self.c.resize((self.w, self.h), Image.LANCZOS)
        l = self.l.resize((self.w, self.h), Image.LANCZOS)
        return c, l


def scribble_word(pad, x, y, length, h, col, w, rnd, line=True, lcol=(20, 20, 20)):
    """알아볼 수 없는 흘림 낱말: 글자 높이 h 의 둥근 오르내림을 이어 씀 (가끔 위로 솟는 획)"""
    pts = []
    t = 0.0
    step = h * 0.32
    while t < length:
        k = len(pts)
        up = h * (0.5 + 0.5 * math.sin(k * 1.7 + rnd.random() * 2))
        if rnd.random() < 0.12:
            up = h * 1.35                       # 솟는 획 (l·h 같은)
        pts.append((x + t, y - up))
        pts.append((x + t + step * 0.5, y - rnd.uniform(0, h * 0.15)))
        t += step
    for _ in range(2):                          # 모서리를 둥글게 (붓글씨처럼)
        sm = [pts[0]]
        for a, b in zip(pts, pts[1:]):
            sm += [(a[0] * 0.75 + b[0] * 0.25, a[1] * 0.75 + b[1] * 0.25), (a[0] * 0.25 + b[0] * 0.75, a[1] * 0.25 + b[1] * 0.75)]
        sm.append(pts[-1])
        pts = sm
    pad.stroke(pts, col, w, line=line, lcol=lcol, lw=min(w, 2.4))


def scribble_line(pad, x, y, width, h, col, w, rnd, line=True, lcol=(20, 20, 20)):
    """낱말 몇 개로 한 줄"""
    cx = x
    while cx < x + width - h:
        L = rnd.uniform(h * 2.0, h * 5.5)
        L = min(L, x + width - cx)
        scribble_word(pad, cx, y, L, h, col, w, rnd, line, lcol)
        cx += L + h * rnd.uniform(0.8, 1.3)


def paper_tone(img, seed, amt=10, fade=0.0):
    """인쇄 종이 결 + 가장자리 바램"""
    a = np.asarray(img).astype(float)
    h, w = a.shape[:2]
    rng = np.random.default_rng(seed)
    n = rng.standard_normal((h // 4 + 1, w // 4 + 1))
    n = np.asarray(Image.fromarray(((n - n.min()) / (n.max() - n.min()) * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)).astype(float) / 255
    a += (n[..., None] - 0.5) * amt
    if fade:
        yy, xx = np.mgrid[0:h, 0:w]
        d = np.minimum(np.minimum(xx, w - 1 - xx), np.minimum(yy, h - 1 - yy)) / (0.12 * min(w, h))
        k = np.clip(d, 0, 1)[..., None]
        a = a * (1 - fade * (1 - k)) + 235 * fade * (1 - k)
    return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))


# ───────── 그림 아이콘 ─────────
def cup(pad, c, s, cup_col, saucer_col, coffee_col, art_col, outline, steam=True, lw=3.0, line=True):
    """옆에서 본 잔 + 받침 + 김 (라테 아트는 위에서 보이게 살짝 기울인 타원)"""
    x, y = c
    pad.ellipse((x, y + s * 0.62), s * 0.95, s * 0.16, saucer_col, outline, lw, line)
    body = []
    for k in range(25):                       # 아래가 둥근 잔 몸통 (위 가장자리 → 둥근 바닥 → 위 가장자리)
        th = math.pi - k / 24 * math.pi
        body.append((x + s * 0.62 * math.cos(th) * (1 - 0.12 * math.sin(th)), y - s * 0.12 + s * 0.66 * math.sin(th)))
    pad.poly(body, cup_col, outline, lw, line)
    # 손잡이
    hp = []
    for k in range(25):
        t = -math.pi / 2 + k / 24 * math.pi
        hp.append((x + s * 0.62 + math.cos(t) * s * 0.26, y + s * 0.14 + math.sin(t) * s * 0.2))
    pad.stroke(hp, outline or cup_col, s * 0.09, line=line)
    pad.stroke(hp, cup_col, s * 0.05, line=False)
    top = pad.ellipse((x, y - s * 0.12), s * 0.62, s * 0.17, coffee_col, outline, lw, line)
    if art_col is not None:                      # 하트 라테 아트
        hx, hy = x, y - s * 0.12
        heart = []
        for k in range(40):
            t = k / 40 * 2 * math.pi
            px = 16 * math.sin(t) ** 3
            py = -(13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t))
            heart.append((hx + px * s * 0.018, hy + py * s * 0.0075))
        pad.poly(heart, art_col, None, line=line)
    if steam:
        for k in (-1, 0, 1):
            st = []
            for j in range(20):
                t = j / 19
                st.append((x + k * s * 0.24 + math.sin(t * 6 + k) * s * 0.07, y - s * 0.32 - t * s * 0.6))
            pad.stroke(st, outline or (255, 255, 255), s * 0.035, line=line)
    _ = top


def croissant(pad, c, s, col, dark, outline, lw=3.0, line=True):
    """초승달 모양으로 겹친 다섯 마디"""
    x, y = c
    segs = [(-0.78, 0.14, 0.26, 0.2, -30), (-0.42, -0.02, 0.36, 0.3, -14), (0, -0.08, 0.42, 0.36, 0), (0.42, -0.02, 0.36, 0.3, 14), (0.78, 0.14, 0.26, 0.2, 30)]
    for dx, dy, rx, ry, a in segs:
        pad.ellipse((x + dx * s, y + dy * s), rx * s, ry * s, col, outline, lw, line, ang=a)
    for dx, dy, rx, ry, a in segs[1:-1]:
        pad.stroke([(x + (dx - rx * 0.5) * s, y + (dy - ry * 0.7) * s), (x + (dx + rx * 0.1) * s, y + (dy + ry * 0.75) * s)], dark, s * 0.03, line=line)


def cake(pad, c, s, sponge, cream, berry, outline, plate, lw=3.0, line=True):
    """세모 조각 딸기 쇼트케이크 (옆에서 비스듬히)"""
    x, y = c
    pad.ellipse((x, y + s * 0.55), s * 1.0, s * 0.18, plate, outline, lw, line)
    front = [(x - s * 0.75, y - s * 0.1), (x + s * 0.55, y + s * 0.1), (x + s * 0.55, y + s * 0.5), (x - s * 0.75, y + s * 0.3)]
    side = [(x + s * 0.55, y + s * 0.1), (x + s * 0.8, y - s * 0.22), (x + s * 0.8, y + s * 0.2), (x + s * 0.55, y + s * 0.5)]
    topf = [(x - s * 0.75, y - s * 0.1), (x + s * 0.5, y - s * 0.55), (x + s * 0.8, y - s * 0.22), (x + s * 0.55, y + s * 0.1)]
    pad.poly(side, cream, outline, lw, line)
    pad.poly(front, cream, outline, lw, line)
    for k in range(2):                       # 스펀지 층
        yy = y + s * (0.0 + k * 0.22)
        pad.poly([(x - s * 0.73, yy - s * 0.02), (x + s * 0.53, yy + s * 0.18), (x + s * 0.53, yy + s * 0.27), (x - s * 0.73, yy + s * 0.07)], sponge, None, line=line)
    pad.poly(topf, cream, outline, lw, line)
    # 딸기 (꼭지)
    bx, by = x + s * 0.18, y - s * 0.45
    pad.poly([(bx - s * 0.16, by), (bx + s * 0.16, by), (bx, by + s * 0.26)], berry, outline, lw, line)
    pad.ellipse((bx, by - s * 0.01), s * 0.16, s * 0.08, berry, outline, lw, line)
    pad.stroke([(bx - s * 0.08, by - s * 0.06), (bx, by - s * 0.14), (bx + s * 0.08, by - s * 0.06)], (60, 130, 60), s * 0.04, line=line)


def bean(pad, c, s, col, outline, ang, line=True):
    pad.ellipse(c, s * 0.5, s * 0.34, col, outline, 2.5, line, ang=ang)
    a = math.radians(ang)
    d = (math.cos(a), math.sin(a))
    n = (-d[1], d[0])
    pts = []
    for k in range(9):
        t = k / 8 - 0.5
        pts.append((c[0] + d[0] * t * s * 0.8 + n[0] * math.sin(t * 6) * s * 0.06, c[1] + d[1] * t * s * 0.8 + n[1] * math.sin(t * 6) * s * 0.06))
    pad.stroke(pts, outline, s * 0.07, line=line)


def dripper(pad, c, s, col, outline, line=True):
    """핸드드립 깔때기 + 서버 (유리 주전자)"""
    x, y = c
    pad.poly([(x - s * 0.55, y - s * 0.55), (x + s * 0.55, y - s * 0.55), (x + s * 0.16, y - s * 0.05), (x - s * 0.16, y - s * 0.05)], col, outline, 3, line)
    pad.rect(x - s * 0.3, y - s * 0.05, x + s * 0.3, y + s * 0.02, col, line)
    pad.poly([(x - s * 0.42, y + s * 0.05), (x + s * 0.42, y + s * 0.05), (x + s * 0.5, y + s * 0.62), (x - s * 0.5, y + s * 0.62)], (210, 225, 230), outline, 3, line)
    pad.poly([(x - s * 0.47, y + s * 0.36), (x + s * 0.47, y + s * 0.36), (x + s * 0.5, y + s * 0.62), (x - s * 0.5, y + s * 0.62)], (92, 56, 36), None, line=False)


# ───────── 메뉴판 ─────────
def menu_board(out):
    W, H = 600, 700
    rnd = random.Random(771)
    base_noise = np.random.default_rng(771).standard_normal((H // 8 + 1, W // 8 + 1))
    pad = Pad(W, H, (34, 44, 40))
    chalk = (236, 232, 220)
    chalk2 = (232, 210, 150)
    # 머리 글씨 (크게, 두 낱말) + 밑줄
    scribble_word(pad, 170, 92, 110, 42, chalk, 6, rnd)
    scribble_word(pad, 300, 92, 130, 42, chalk2, 6, rnd)
    pad.stroke([(150, 118), (450, 116)], chalk, 3)
    # 메뉴 줄: 낱말 + 점선 + 값
    y = 180
    for i in range(8):
        scribble_line(pad, 70, y, rnd.uniform(160, 230), 18, chalk, 3.2, rnd)
        for k in range(10):
            pad.stroke([(330 + k * 14, y - 2), (334 + k * 14, y - 2)], chalk, 2.5, line=False)
        scribble_word(pad, W - 120, y, 56, 18, chalk2, 3.2, rnd)
        y += 52
    # 아래 분필 그림: 잔 · 크루아상 · 케이크 (선만)
    cup(pad, (150, 620), 46, (34, 44, 40), (34, 44, 40), (34, 44, 40), None, chalk, steam=True)
    croissant(pad, (300, 628), 52, (34, 44, 40), chalk, chalk)
    cake(pad, (455, 618), 44, (34, 44, 40), (34, 44, 40), (34, 44, 40), chalk, (34, 44, 40))
    c, l = pad.done()
    a = np.asarray(c).astype(float)
    nz = np.asarray(Image.fromarray(((base_noise - base_noise.min()) / np.ptp(base_noise) * 255).astype(np.uint8)).resize((W, H), Image.BICUBIC)).astype(float) / 255
    a += (nz[..., None] - 0.5) * 16                     # 칠판 얼룩
    a += np.random.default_rng(773).standard_normal(a.shape[:2])[..., None] * 3     # 분필 가루
    Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).save(os.path.join(out, 'menu_board.jpg'), quality=88, optimize=True)
    l.save(os.path.join(out, 'menu_board_ln.png'), optimize=True)


# ───────── 포스터 ─────────
POSTERS = [
    # (바탕, 글씨 색, 무늬)
    ((236, 222, 196), (70, 44, 30), 'latte'),
    ((222, 128, 64), (255, 244, 224), 'croissant'),
    ((242, 196, 196), (120, 40, 52), 'cake'),
    ((40, 70, 58), (236, 220, 180), 'beans'),
]


def poster(out, i):
    W, H = 512, 704
    bg, ink, kind = POSTERS[i]
    rnd = random.Random(900 + i)
    pad = Pad(W, H, bg)
    ol = (50, 34, 26)
    # 테두리 띠
    pad.rect(22, 22, W - 22, 30, ink, line=True)
    pad.rect(22, H - 30, W - 22, H - 22, ink, line=True)
    # 큰 머리 글씨 두 줄
    scribble_word(pad, 70, 120, 220, 54, ink, 9, rnd)
    scribble_word(pad, 120, 196, 260, 46, ink, 8, rnd)
    cx, cy = W / 2, 420
    if kind == 'latte':
        pad.ellipse((cx, cy + 10), 170, 170, (214, 190, 156), None, line=False)
        cup(pad, (cx, cy - 10), 150, (250, 248, 242), (244, 240, 230), (150, 96, 60), (246, 236, 220), ol)
    elif kind == 'croissant':
        pad.ellipse((cx, cy + 10), 175, 175, (240, 160, 92), None, line=False)
        croissant(pad, (cx, cy + 20), 150, (214, 150, 70), (150, 90, 40), ol)
    elif kind == 'cake':
        pad.ellipse((cx, cy + 10), 175, 175, (250, 222, 222), None, line=False)
        cake(pad, (cx, cy + 10), 140, (238, 206, 140), (252, 248, 240), (214, 40, 60), ol, (244, 244, 244))
    else:
        dripper(pad, (cx + 40, cy - 10), 150, (240, 240, 236), ol)
        for k in range(9):
            a = rnd.uniform(0, 360)
            bean(pad, (cx - 150 + rnd.uniform(-40, 60), cy + 60 + rnd.uniform(-90, 110)), 46, (96, 58, 34), (40, 24, 16), a)
    # 아래 작은 글씨 세 줄 + 값 동그라미
    y = 620
    for k in range(3):
        scribble_line(pad, 70, y + k * 26, W - 200 if k < 2 else W - 260, 13, ink, 2.6, rnd)
    pad.ellipse((W - 90, 640), 44, 44, ink, None, line=True)
    scribble_word(pad, W - 118, 650, 54, 20, bg, 4.5, rnd, line=False)
    c, l = pad.done()
    c = paper_tone(c, 950 + i, amt=10, fade=0.18)
    c.save(os.path.join(out, f'cafe_poster_{i}.jpg'), quality=88, optimize=True)
    l.save(os.path.join(out, f'cafe_poster_{i}_ln.png'), optimize=True)


def cafe_boards(out):
    os.makedirs(out, exist_ok=True)
    menu_board(out)
    for i in range(len(POSTERS)):
        poster(out, i)


if __name__ == '__main__':
    import sys
    o = sys.argv[1] if len(sys.argv) > 1 else '.'
    cafe_boards(o)
