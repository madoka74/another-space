"""집 테마의 고양이 '방울이' 그림 (선 그림 카툰). 이 앱만의 고양이: 동그란 얼굴을 정면으로 하고 작은 점 눈,
이마의 세 줄 무늬, 꼬리의 줄무늬 고리, 빨간 목줄에 금색 방울.
몸은 옆모습(오른쪽을 봄)이라 앱이 왼쪽으로 갈 땐 좌우를 뒤집어 씀.
동작마다 몇 장씩: 앉기·걷기·뛰기·그루밍·기지개·식빵·잠·점프·긁기·뒹굴기·냥냥펀치·부비기·야옹·올려다보기.
512×512, 바닥 줄 y=470. 흰 몸(종이) + 검은 선, 투명 배경 (<이름>.png + 가림 그림 <이름>_a.png)"""
import math
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

S = 4                    # 4배로 그려서 줄임 (매끈한 선)
N = 512
W_LINE = 6.0             # 윤곽선 굵기 (512 기준)
GROUND = 470
RED = (204, 58, 58)
GOLD = (236, 186, 64)
INK = (24, 22, 22)
PAPER = (252, 250, 246)


# ───────── 모양 (512 기준 좌표, grow 만큼 부풀린 다각형) ─────────
def ellipse(c, rx, ry, ang=0.0):
    def poly(g):
        a = math.radians(ang)
        pts = []
        for k in range(72):
            t = k / 72 * 2 * math.pi
            x, y = (rx + g) * math.cos(t), (ry + g) * math.sin(t)
            pts.append((c[0] + x * math.cos(a) - y * math.sin(a), c[1] + x * math.sin(a) + y * math.cos(a)))
        return pts
    return poly


def capsule(p0, p1, r0, r1):
    def poly(g):
        (x0, y0), (x1, y1) = p0, p1
        dx, dy = x1 - x0, y1 - y0
        L = math.hypot(dx, dy) or 1e-3
        a = math.atan2(dy, dx)
        R0, R1 = r0 + g, r1 + g
        pts = []
        for k in range(19):           # 끝 반원 (p1)
            t = a - math.pi / 2 + k / 18 * math.pi
            pts.append((x1 + R1 * math.cos(t), y1 + R1 * math.sin(t)))
        for k in range(19):           # 시작 반원 (p0)
            t = a + math.pi / 2 + k / 18 * math.pi
            pts.append((x0 + R0 * math.cos(t), y0 + R0 * math.sin(t)))
        return pts
    return poly


def blob(pts, r):
    """여러 점을 잇는 굵은 관 (꼬리): 이웃한 캡슐들의 합"""
    rs = r if isinstance(r, (list, tuple)) else [r] * len(pts)
    return [capsule(pts[i], pts[i + 1], rs[i], rs[i + 1]) for i in range(len(pts) - 1)]


def ear(base_c, ang, size):
    """둥근 세모 귀: 머리 가운데에서 ang 방향(도, 0=오른쪽, -90=위)으로"""
    a = math.radians(ang)
    tip = (base_c[0] + math.cos(a) * size * 1.0, base_c[1] + math.sin(a) * size * 1.0)
    side = (math.cos(a + math.pi / 2), math.sin(a + math.pi / 2))
    root = (base_c[0] - math.cos(a) * size * 0.35, base_c[1] - math.sin(a) * size * 0.35)
    b1 = (root[0] + side[0] * size * 0.55, root[1] + side[1] * size * 0.55)
    b2 = (root[0] - side[0] * size * 0.55, root[1] - side[1] * size * 0.55)
    def poly(g):
        cx = (tip[0] + b1[0] + b2[0]) / 3
        cy = (tip[1] + b1[1] + b2[1]) / 3
        out = []
        for p in (tip, b1, b2):
            dx, dy = p[0] - cx, p[1] - cy
            d = math.hypot(dx, dy) or 1
            k = (d + g * 1.4) / d
            out.append((cx + dx * k, cy + dy * k))
        # 모서리를 둥글게: 세 꼭짓점 사이를 곡선으로
        res = []
        for i in range(3):
            p, q, r = out[i - 1], out[i], out[(i + 1) % 3]
            for k in range(7):
                t = k / 6
                a1 = (p[0] + (q[0] - p[0]) * (0.75 + 0.25 * t), p[1] + (q[1] - p[1]) * (0.75 + 0.25 * t))
                a2 = (q[0] + (r[0] - q[0]) * (0.25 * t), q[1] + (r[1] - q[1]) * (0.25 * t))
                res.append((a1[0] + (a2[0] - a1[0]) * t, a1[1] + (a2[1] - a1[1]) * t))
        return res
    return poly, tip, (b1, b2)


def curve(p0, p1, p2, p3, n=14):
    pts = []
    for k in range(n + 1):
        t = k / n
        u = 1 - t
        pts.append((u ** 3 * p0[0] + 3 * u * u * t * p1[0] + 3 * u * t * t * p2[0] + t ** 3 * p3[0],
                    u ** 3 * p0[1] + 3 * u * u * t * p1[1] + 3 * u * t * t * p2[1] + t ** 3 * p3[1]))
    return pts


# ───────── 그리기 ─────────
class Canvas:
    def __init__(self):
        self.rgb = Image.new('RGB', (N * S, N * S), PAPER)
        self.a = Image.new('L', (N * S, N * S), 0)
        self.d = ImageDraw.Draw(self.rgb)
        self.da = ImageDraw.Draw(self.a)

    def _p(self, pts):
        return [(x * S, y * S) for x, y in pts]

    def layer(self, shapes):
        """몸통 덩어리 한 겹: 모두 검게 부풀려 그린 뒤 하얗게 채움 → 바깥 윤곽선만 남음"""
        for sh in shapes:
            p = self._p(sh(W_LINE))
            self.d.polygon(p, fill=INK)
            self.da.polygon(p, fill=255)
        for sh in shapes:
            self.d.polygon(self._p(sh(0)), fill=PAPER)

    def fill(self, shape, col):
        self.d.polygon(self._p(shape(0)), fill=col)

    def line(self, pts, w=W_LINE * 0.75, col=INK):
        p = self._p(pts)
        self.d.line(p, fill=col, width=int(w * S), joint='curve')
        r = w * S / 2
        for x, y in (p[0], p[-1]):
            self.d.ellipse([x - r, y - r, x + r, y + r], fill=col)

    def dot(self, c, r, col=INK):
        x, y = c[0] * S, c[1] * S
        self.d.ellipse([x - r * S, y - r * S, x + r * S, y + r * S], fill=col)

    def ring(self, c, r, fillc, w=W_LINE * 0.8):
        x, y = c[0] * S, c[1] * S
        R = (r + w / 2) * S
        self.d.ellipse([x - R, y - R, x + R, y + R], fill=INK)
        self.da.ellipse([x - R, y - R, x + R, y + R], fill=255)
        R = (r - w / 2) * S
        self.d.ellipse([x - R, y - R, x + R, y + R], fill=fillc)

    def save(self, out, name):
        rgb = self.rgb.resize((N, N), Image.LANCZOS)
        a = self.a.resize((N, N), Image.LANCZOS)
        rgba = Image.merge('RGBA', (*rgb.split(), a))
        rgba.save(os.path.join(out, name + '.png'), optimize=True)
        a.save(os.path.join(out, name + '_a.png'), optimize=True)


# ───────── 얼굴·무늬 ─────────
def face(cv, hc, hr, look=(0.0, 0.0), eyes='open', mouth='w', tilt=0.0):
    """정면 얼굴: 점 눈 + 하이라이트, 작은 코, ω 입, 수염. look: 눈동자가 쏠리는 방향(-1~1)"""
    a = math.radians(tilt)
    def P(dx, dy):
        return (hc[0] + dx * math.cos(a) - dy * math.sin(a), hc[1] + dx * math.sin(a) + dy * math.cos(a))
    ex = hr * 0.38
    ey = -hr * 0.02
    for s in (-1, 1):
        c = P(s * ex + look[0] * 4, ey + look[1] * 4)
        if eyes == 'open':
            cv.dot(c, hr * 0.13)
            cv.dot((c[0] + hr * 0.04, c[1] - hr * 0.05), hr * 0.045, PAPER)
        elif eyes == 'happy':          # ^ ^
            cv.line([P(s * ex - hr * 0.14, ey + hr * 0.05), P(s * ex, ey - hr * 0.08), P(s * ex + hr * 0.14, ey + hr * 0.05)])
        elif eyes == 'closed':         # ‿ ‿ (잠)
            cv.line([P(s * ex - hr * 0.14, ey), P(s * ex, ey + hr * 0.08), P(s * ex + hr * 0.14, ey)])
        elif eyes == 'big':            # 동그랗게 놀람·집중
            cv.ring(c, hr * 0.17, PAPER, w=W_LINE * 0.7)
            cv.dot((c[0] + look[0] * 3, c[1] + look[1] * 3), hr * 0.11)
            cv.dot((c[0] + hr * 0.05, c[1] - hr * 0.06), hr * 0.04, PAPER)
    # 코
    n0 = P(0, hr * 0.2)
    cv.d.polygon([(x * S, y * S) for x, y in (P(-hr * 0.08, hr * 0.15), P(hr * 0.08, hr * 0.15), n0)], fill=INK)
    # 입
    if mouth == 'w':
        cv.line([P(-hr * 0.17, hr * 0.27), P(-hr * 0.08, hr * 0.33), n0, P(hr * 0.08, hr * 0.33), P(hr * 0.17, hr * 0.27)], w=W_LINE * 0.6)
    elif mouth == 'open':
        cv.line([n0, P(0, hr * 0.26)], w=W_LINE * 0.6)
        m = ellipse(P(0, hr * 0.36), hr * 0.13, hr * 0.12, tilt)
        cv.d.polygon(cv._p(m(W_LINE * 0.5)), fill=INK)
        cv.d.polygon(cv._p(m(0)), fill=(196, 84, 92))
    elif mouth == 'small':
        cv.line([P(-hr * 0.1, hr * 0.3), n0, P(hr * 0.1, hr * 0.3)], w=W_LINE * 0.6)
    # 수염
    for s in (-1, 1):
        for k, dy in enumerate((0.16, 0.26, 0.36)):
            cv.line([P(s * hr * 0.55, hr * dy), P(s * hr * 1.08, hr * (dy - 0.12 + k * 0.1))], w=W_LINE * 0.42)
    # 이마 세 줄 무늬
    for k, dx in enumerate((-0.22, 0, 0.22)):
        top = -hr * 0.92 + (abs(dx) * hr * 0.25)
        cv.line([P(dx * hr, top), P(dx * hr * 0.9, top + hr * (0.26 if k == 1 else 0.2))], w=W_LINE * 0.75)


def ears(hc, hr, tilt=0.0, perk=0.0):
    """귀 두 개 (머리 기울기 tilt, perk: 쫑긋(+)/눕힘(-))"""
    out = []
    for s in (-1, 1):
        ang = -90 + s * (38 + perk * -12) + tilt
        base = (hc[0] + math.cos(math.radians(ang)) * hr * 0.78, hc[1] + math.sin(math.radians(ang)) * hr * 0.78)
        out.append(ear(base, ang, hr * 0.62))
    return out


def ear_inner(cv, e):
    poly, tip, (b1, b2) = e
    mid = ((b1[0] + b2[0]) / 2, (b1[1] + b2[1]) / 2)
    cv.line([((b1[0] * 2 + tip[0]) / 3 * 0.5 + mid[0] * 0.5, (b1[1] * 2 + tip[1]) / 3 * 0.5 + mid[1] * 0.5),
             ((tip[0] * 2 + mid[0]) / 3, (tip[1] * 2 + mid[1]) / 3),
             ((b2[0] * 2 + tip[0]) / 3 * 0.5 + mid[0] * 0.5, (b2[1] * 2 + tip[1]) / 3 * 0.5 + mid[1] * 0.5)], w=W_LINE * 0.5)


def collar(cv, hc, hr, tilt=0.0, show=True):
    if not show:
        return
    a = math.radians(tilt)
    def P(dx, dy):
        return (hc[0] + dx * math.cos(a) - dy * math.sin(a), hc[1] + dx * math.sin(a) + dy * math.cos(a))
    pts = curve(P(-hr * 0.62, hr * 0.78), P(-hr * 0.25, hr * 0.98), P(hr * 0.25, hr * 0.98), P(hr * 0.62, hr * 0.78))
    cv.line(pts, w=W_LINE * 2.6, col=INK)
    cv.line(pts, w=W_LINE * 1.3, col=RED)
    cv.ring(P(0, hr * 1.08), hr * 0.13, GOLD, w=W_LINE * 0.7)
    b = P(0, hr * 1.12)
    cv.line([(b[0] - 2, b[1]), (b[0] + 2, b[1])], w=W_LINE * 0.5)


def tail_stripes(cv, pts, every=3, r=14):
    for i in range(every, len(pts) - 1, every):
        (x0, y0), (x1, y1) = pts[i - 1], pts[i + 1]
        dx, dy = x1 - x0, y1 - y0
        L = math.hypot(dx, dy) or 1
        nx, ny = -dy / L, dx / L
        c = pts[i]
        cv.line([(c[0] - nx * r * 0.8, c[1] - ny * r * 0.8), (c[0] + nx * r * 0.8, c[1] + ny * r * 0.8)], w=W_LINE * 0.7)


def paw(c, rx=22, ry=12):
    return ellipse(c, rx, ry)


def toes(cv, c, rx=22, up=False):
    for dx in (-0.35, 0.1):
        x = c[0] + dx * rx + rx * 0.2
        if up:
            cv.line([(x, c[1] + 4), (x, c[1] - 6)], w=W_LINE * 0.45)
        else:
            cv.line([(x, c[1] - 6), (x, c[1] + 4)], w=W_LINE * 0.45)


def tail_pts(base, ang, length, curl, wave=0.0, n=14):
    """꼬리 점들: base에서 ang(도) 방향으로 나가 curl(+면 끝이 앞쪽으로 말림)만큼 휘어짐, wave로 S자"""
    pts = []
    a = math.radians(ang)
    x, y = base
    step = length / n
    for k in range(n + 1):
        pts.append((x, y))
        t = k / n
        da = math.radians(curl) * (t ** 1.6) / n * 3 + math.radians(wave) * math.sin(t * math.pi * 2) / n * 2
        a += da
        x += math.cos(a) * step
        y += math.sin(a) * step
    return pts


# ───────── 자세 ─────────
def draw_stand(cv, legs, body=(232, 336, 122, 70, 0), head=(372, 252, 72), tail=(115, 320, -120, 190, 60, 0),
               eyes='open', mouth='w', htilt=0.0, look=(0, 0), perk=0.0):
    """선 자세 (걷기·뛰기·부비기의 바탕). legs: [(어깨/엉덩이, 발)] 순서: 뒷다리(먼), 앞다리(먼), 뒷다리(가까운), 앞다리(가까운)"""
    tp = tail_pts((tail[0], tail[1]), tail[2], tail[3], tail[4], tail[5])
    far = [capsule(legs[0][0], legs[0][1], 22, 17), paw(legs[0][1]), capsule(legs[1][0], legs[1][1], 20, 16), paw(legs[1][1])]
    cv.layer(far + blob(tp, [16 - 5 * k / len(tp) for k in range(len(tp))]))
    hc, hr = (head[0], head[1]), head[2]
    es = ears(hc, hr, htilt, perk)
    near = [ellipse(body[:2], body[2], body[3], body[4]),
            capsule(legs[2][0], legs[2][1], 26, 18), paw(legs[2][1]),
            capsule(legs[3][0], legs[3][1], 22, 17), paw(legs[3][1]),
            capsule((body[0] + body[2] * 0.7, body[1] - 20), hc, 44, 40),       # 목
            ellipse(hc, hr * 1.06, hr * 0.92, htilt)] + [e[0] for e in es]
    cv.layer(near)
    for e in es:
        ear_inner(cv, e)
    tail_stripes(cv, tp)
    for l in legs[2:]:
        toes(cv, l[1])
    collar(cv, hc, hr, htilt)
    face(cv, hc, hr, look, eyes, mouth, htilt)


def leg_pose(phase, stride=34, lift=16, run=False):
    """걷기 한 박자: 네 다리 발 위치 (phase 0~1)"""
    def foot(px, ph):
        s = math.sin(ph * 2 * math.pi)
        c = math.cos(ph * 2 * math.pi)
        return (px + s * stride, GROUND - 12 - max(0, c) * lift)
    sh_h = (150, 352) if not run else (140, 340)
    sh_f = (318, 352) if not run else (330, 334)
    # 걸음 순서: 뒤(가까움) 0, 앞(가까움) .25, 뒤(먼) .5, 앞(먼) .75
    return [((sh_h[0] - 22, sh_h[1] - 6), foot(sh_h[0] - 26, phase + 0.5)),
            ((sh_f[0] - 20, sh_f[1] - 6), foot(sh_f[0] - 12, phase + 0.75)),
            (sh_h, foot(sh_h[0] - 4, phase)),
            (sh_f, foot(sh_f[0] + 8, phase + 0.25))]


def draw_sit(cv, head=(300, 214, 72), htilt=0.0, eyes='open', mouth='w', look=(0, 0), paw_up=None, tail_wave=0.0, perk=0.0):
    """앉은 자세 (정면 얼굴, 옆으로 앉은 몸). paw_up: 가까운 앞발을 든 자리"""
    hc, hr = (head[0], head[1]), head[2]
    tp = tail_pts((190, 458), -2 - tail_wave * 0.1, 165, -40 - tail_wave * 1.2, tail_wave * 0.3)
    far = [capsule((282, 330), (288, 460), 19, 16), paw((292, 462), 20, 11)]
    cv.layer(far)
    es = ears(hc, hr, htilt, perk)
    near = [ellipse((248, 358), 78, 104, -14),
            ellipse((212, 424), 72, 50, 0),                      # 엉덩이·뒷다리
            paw((258, 462), 26, 12),
            capsule((262, 300), hc, 46, 40),
            ellipse(hc, hr * 1.06, hr * 0.92, htilt)] + [e[0] for e in es]
    if paw_up is None:
        near += [capsule((302, 330), (310, 460), 21, 17), paw((316, 462), 22, 12)]
    else:
        near += [capsule((300, 330), paw_up, 21, 17), ellipse(paw_up, 18, 15)]
    cv.layer(near)
    cv.layer(blob(tp, [14 - 4 * k / len(tp) for k in range(len(tp))]))       # 꼬리는 앞발 앞으로 감음
    for e in es:
        ear_inner(cv, e)
    tail_stripes(cv, tp)
    cv.line(curve((176, 410), (200, 440), (232, 452), (246, 456)), w=W_LINE * 0.6)     # 뒷다리 접힌 선
    toes(cv, (316, 462) if paw_up is None else paw_up, up=paw_up is not None)
    collar(cv, hc, hr, htilt)
    face(cv, hc, hr, look, eyes, mouth, htilt)


def draw_loaf(cv, eyes='open', breath=0.0, tail_wave=0.0):
    """식빵 자세: 다리를 몸 밑에 넣고 웅크림"""
    hc, hr = (352, 352), 70
    tp = tail_pts((132, 446), 170, 110, -60 - tail_wave * 0.6)
    es = ears(hc, hr)
    cv.layer(blob(tp, [15 - 4 * k / len(tp) for k in range(len(tp))]))
    cv.layer([ellipse((240, 412), 128, 62 + breath, 0), paw((330, 462), 24, 11), paw((292, 464), 22, 10),
              ellipse(hc, hr * 1.06, hr * 0.92)] + [e[0] for e in es])
    for e in es:
        ear_inner(cv, e)
    tail_stripes(cv, tp)
    collar(cv, hc, hr)
    face(cv, hc, hr, (0, 0), eyes, 'w')


def draw_sleep(cv, breath=0.0):
    """동그랗게 말고 잠"""
    hc, hr = (318, 404), 62
    tp = tail_pts((128, 440), 28, 240, -70)
    es = ears(hc, hr, 40, -0.6)
    cv.layer([ellipse((236, 420), 132, 54 + breath, 0)])
    cv.layer([ellipse(hc, hr * 1.06, hr * 0.92, 40)] + [e[0] for e in es])
    cv.layer(blob(tp, [16 - 4 * k / len(tp) for k in range(len(tp))]) + [paw((370, 462), 22, 10)])
    for e in es:
        ear_inner(cv, e)
    tail_stripes(cv, tp)
    face(cv, hc, hr, (0, 0), 'closed', 'small', 40)


def draw_stretch(cv, k=0.0):
    """기지개: 앞다리 쭉, 엉덩이 위로"""
    hc, hr = (392, 384 - k * 6), 64
    tp = tail_pts((112, 268), -70, 190, 30 - k * 20)
    es = ears(hc, hr, 10, -0.3)
    cv.layer([capsule((140, 300), (128, 458), 20, 16), paw((126, 462)), capsule((320, 396), (452 + k * 8, 456), 18, 15), paw((458 + k * 8, 462), 22, 10)]
             + blob(tp, [15 - 4 * j / len(tp) for j in range(len(tp))]))
    cv.layer([ellipse((228, 340), 124, 62, 20 + k * 3), capsule((160, 300), (158, 456), 24, 18), paw((160, 462)),
              capsule((330, 400), (440 + k * 8, 458), 20, 16), paw((446 + k * 8, 462)),
              capsule((320, 380), hc, 40, 36), ellipse(hc, hr * 1.06, hr * 0.92, 10)] + [e[0] for e in es])
    for e in es:
        ear_inner(cv, e)
    tail_stripes(cv, tp)
    collar(cv, hc, hr, 10)
    face(cv, hc, hr, (0, 0.3), 'happy', 'open' if k > 0.5 else 'small', 10)


def draw_jump(cv, k):
    """k=0 웅크림, k=1 뛰어오름"""
    if k == 0:
        legs = [((140, 400), (112, 458)), ((296, 396), (300, 458)), ((168, 404), (140, 458)), ((322, 400), (330, 458))]
        draw_stand(cv, legs, body=(232, 398, 118, 60, 4), head=(366, 330, 70), tail=(118, 392, -170, 170, 20, 0), eyes='big', look=(0.6, -0.6), perk=0.5)
    else:
        legs = [((150, 316), (84, 372)), ((322, 262), (408, 210)), ((170, 322), (100, 392)), ((338, 272), (424, 228))]
        draw_stand(cv, legs, body=(240, 284, 124, 60, -22), head=(380, 180, 68), tail=(122, 330, 175, 120, 60, 0), eyes='big', look=(0.6, -0.8), perk=0.8)


def draw_scratch(cv, k):
    """뒷발로 서서 앞발로 긁기 (오른쪽 가구·벽을)"""
    hc, hr = (262, 150), 70
    tp = tail_pts((212, 446), 175, 130, 50 + k * 20)
    es = ears(hc, hr, 6, 0.2)
    up = 120 if k == 0 else 170
    cv.layer([capsule((290, 250), (352, up + 20), 18, 15), ellipse((356, up + 16), 16, 14), capsule((214, 400), (210, 458), 22, 17), paw((214, 462))]
             + blob(tp, [15 - 4 * j / len(tp) for j in range(len(tp))]))
    cv.layer([ellipse((250, 320), 66, 122, 4), capsule((246, 410), (252, 458), 24, 18), paw((258, 462)),
              capsule((292, 270), (362, up + 50), 20, 16), ellipse((366, up + 48), 17, 15),
              ellipse(hc, hr * 1.06, hr * 0.92, 6)] + [e[0] for e in es])
    for e in es:
        ear_inner(cv, e)
    tail_stripes(cv, tp)
    for j in range(3):       # 발톱 자국 느낌의 짧은 선
        cv.line([(382, up + 30 + j * 10), (392, up + 34 + j * 10)], w=W_LINE * 0.45)
    collar(cv, hc, hr, 6)
    face(cv, hc, hr, (0.4, 0), 'happy' if k else 'open', 'w', 6)


def draw_roll(cv, k):
    """배 보이고 뒹굴: 다리 넷이 위로"""
    hc, hr = (368, 420), 64
    tp = tail_pts((124, 436), 190, 100, 70 - k * 60)
    es = ears(hc, hr, 160, 0)
    wig = (k * 2 - 1) * 10
    legs = [((170, 390), (150 + wig, 316)), ((236, 384), (230 - wig, 304)), ((288, 386), (300 + wig, 308)), ((200, 388), (192 - wig, 330))]
    cv.layer(blob(tp, [15 - 4 * j / len(tp) for j in range(len(tp))]))
    cv.layer([ellipse((236, 420), 120, 54, 0), ellipse(hc, hr * 1.06, hr * 0.92, 160)] + [e[0] for e in es]
             + sum([[capsule(a, b, 18, 15), ellipse(b, 17, 14)] for a, b in legs], []))
    for e in es:
        ear_inner(cv, e)
    for a, b in legs:
        toes(cv, b, up=True)
    tail_stripes(cv, tp)
    cv.line(curve((180, 446), (220, 456), (270, 456), (310, 446)), w=W_LINE * 0.5)     # 배 털 선
    face(cv, hc, hr, (0, 0), 'happy', 'open' if k else 'w', 180)


def draw_rub(cv, k):
    """부비부비: 머리를 숙여 옆으로 비비고 꼬리는 바짝 세움"""
    legs = [((128, 346), (118, 458)), ((298, 352), (300, 458)), ((154, 352), (150, 458)), ((322, 356), (330, 458))]
    draw_stand(cv, legs, body=(232, 344, 120, 66, 2), head=(380, 300 + k * 8, 68), tail=(116, 300, -100, 200, 70 + k * 30, 0),
               eyes='happy', mouth='small', htilt=24 + k * 8, perk=-0.4)


def frames():
    f = {}
    def mk(name, fn):
        cv = Canvas()
        fn(cv)
        f[name] = cv
    # 앉기 (꼬리 살랑 2장 + 눈 깜빡)
    mk('cat_sit0', lambda cv: draw_sit(cv, tail_wave=0))
    mk('cat_sit1', lambda cv: draw_sit(cv, tail_wave=30))
    mk('cat_blink', lambda cv: draw_sit(cv, eyes='closed', tail_wave=10))
    mk('cat_meow', lambda cv: draw_sit(cv, eyes='happy', mouth='open', tail_wave=20, perk=0.3))
    mk('cat_look', lambda cv: draw_sit(cv, head=(304, 200, 72), htilt=-14, look=(-0.3, -0.9), eyes='big', perk=0.6))
    mk('cat_lookmeow', lambda cv: draw_sit(cv, head=(304, 200, 72), htilt=-14, look=(-0.3, -0.9), mouth='open', perk=0.6))
    mk('cat_groom0', lambda cv: draw_sit(cv, head=(316, 236, 70), htilt=18, eyes='closed', mouth='open', paw_up=(352, 272)))
    mk('cat_groom1', lambda cv: draw_sit(cv, head=(312, 230, 70), htilt=10, eyes='closed', mouth='small', paw_up=(346, 252)))
    mk('cat_swat0', lambda cv: draw_sit(cv, eyes='big', look=(1, 0.2), paw_up=(380, 320), perk=0.8))
    mk('cat_swat1', lambda cv: draw_sit(cv, eyes='big', look=(1, 0.4), mouth='small', paw_up=(424, 380), perk=0.8))
    # 걷기 6장, 뛰기 4장
    for i in range(6):
        ph = i / 6
        mk(f'cat_walk{i}', lambda cv, ph=ph: draw_stand(cv, leg_pose(ph), body=(232, 336 + 3 * math.sin(ph * 4 * math.pi), 122, 70, 0),
                                                        tail=(115, 320, -120, 190, 60, 18 * math.sin(ph * 2 * math.pi))))
    for i in range(4):
        ph = i / 4
        mk(f'cat_run{i}', lambda cv, ph=ph: draw_stand(cv, leg_pose(ph, stride=58, lift=30, run=True),
                                                       body=(236, 322 + 8 * math.sin(ph * 2 * math.pi), 132, 64, -3 + 6 * math.sin(ph * 2 * math.pi)),
                                                       head=(384, 248, 70), tail=(112, 310, -165, 150, 70, 0), perk=0.4))
    mk('cat_loaf0', lambda cv: draw_loaf(cv, breath=0))
    mk('cat_loaf1', lambda cv: draw_loaf(cv, eyes='closed', breath=2, tail_wave=20))
    mk('cat_sleep0', lambda cv: draw_sleep(cv, 0))
    mk('cat_sleep1', lambda cv: draw_sleep(cv, 4))
    mk('cat_stretch0', lambda cv: draw_stretch(cv, 0))
    mk('cat_stretch1', lambda cv: draw_stretch(cv, 1))
    mk('cat_jump0', lambda cv: draw_jump(cv, 0))
    mk('cat_jump1', lambda cv: draw_jump(cv, 1))
    mk('cat_scratch0', lambda cv: draw_scratch(cv, 0))
    mk('cat_scratch1', lambda cv: draw_scratch(cv, 1))
    mk('cat_roll0', lambda cv: draw_roll(cv, 0))
    mk('cat_roll1', lambda cv: draw_roll(cv, 1))
    mk('cat_rub0', lambda cv: draw_rub(cv, 0))
    mk('cat_rub1', lambda cv: draw_rub(cv, 1))
    return f


def cat_sprites(out):
    os.makedirs(out, exist_ok=True)
    for name, cv in frames().items():
        cv.save(out, name)


if __name__ == '__main__':
    import sys
    o = sys.argv[1] if len(sys.argv) > 1 else '.'
    cat_sprites(o)
    # 한눈에 보기
    names = sorted(n for n in os.listdir(o) if n.startswith('cat_') and n.endswith('.png') and not n.endswith('_a.png'))
    cols = 6
    rows = (len(names) + cols - 1) // cols
    sheet = Image.new('RGB', (cols * 256, rows * 280), (200, 200, 200))
    d = ImageDraw.Draw(sheet)
    for i, n in enumerate(names):
        im = Image.open(os.path.join(o, n)).convert('RGBA').resize((256, 256))
        bg = Image.new('RGBA', im.size, (210, 200, 185, 255))
        bg.alpha_composite(im)
        sheet.paste(bg.convert('RGB'), ((i % cols) * 256, (i // cols) * 280))
        d.text(((i % cols) * 256 + 6, (i // cols) * 280 + 258), n, fill=(0, 0, 0))
    sheet.save(os.path.join(o, 'sheet.jpg'), quality=85)
