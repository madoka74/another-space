"""집 테마의 강아지 '설이' 그림 — 갈색 토이 푸들 (형선이 보내 준 푸들 그림 느낌):
초콜릿빛 갈색 곱슬 털, 머리 위 동그란 털 뭉치(탑노트), 얼굴 옆으로 길게 늘어진 복슬 귀, 짧고 둥근 주둥이·까만 코·작은 까만 눈,
곧고 굵은 다리와 둥근 털 발, 엉덩이에서 위로 선 짧은 꼬리 끝의 동그란 털 방울.
머리·목·몸·다리·꼬리를 한 덩어리 윤곽선으로 그려(따로 떨어져 보이지 않게) 귀만 따로 겹쳐 그림.
가장자리는 곱슬 털처럼 오돌토돌, 윤곽선은 짙은 밤색 (선 그림에서는 이 선만 검게 남고 털은 흰 종이가 되도록 털 밝기를 맞춤).
몸은 옆모습(오른쪽을 봄), 정면·뒷모습도 있음. 512×512, 발 맨 아래 ≈ 488줄 (앱 HomeDog 의 y0·footPx 와 맞춤)"""
import math
import os
from PIL import Image, ImageDraw

from cat_art import capsule, Canvas, W_LINE, GROUND

FUR = (172, 112, 74)           # 갈색 곱슬 털 (선 그림 변환에서 흰 종이가 되는 밝기)
FUR_D = (152, 98, 64)          # 그늘 (먼 다리·먼 귀)
FUR_L = (196, 136, 94)         # 빛 받는 털 (머리 위·등)
EAR = (158, 100, 66)           # 귀
OUTL = (64, 40, 26)            # 짙은 밤색 윤곽선
DARK = (40, 26, 22)            # 코·눈
TONGUE = (236, 120, 132)
MOUTH = (110, 48, 52)
DIRT = (120, 92, 64)
BARK = (150, 104, 62)
BARK_D = (118, 80, 46)
FOOT_Y = GROUND - 2            # 발 가운데 (발 아래 끝 ≈ 488줄)


# ───────── 모양 ─────────
def fluff(c, rx, ry, ang=0.0, n=14, amp=0.05, ph=0.0):
    """곱슬 털 덩어리: 가장자리가 둥근 털 방울로 오돌토돌한 타원"""
    def poly(g):
        a = math.radians(ang)
        pts = []
        for k in range(180):
            t = k / 180 * 2 * math.pi
            bump = 1.0 + amp * (abs(math.sin(n * t / 2 + ph)) - 0.6)
            x, y = (rx * bump + g) * math.cos(t), (ry * bump + g) * math.sin(t)
            pts.append((c[0] + x * math.cos(a) - y * math.sin(a), c[1] + x * math.sin(a) + y * math.cos(a)))
        return pts
    return poly


def oval(c, rx, ry, ang=0.0):
    return fluff(c, rx, ry, ang, amp=0.0)


def layer(cv, shapes, fill):
    """짙게 부풀려 그린 뒤 색으로 채움 → 겹친 모양들은 바깥 윤곽선 하나로 이어짐"""
    for sh in shapes:
        p = cv._p(sh(W_LINE * 0.75))
        cv.d.polygon(p, fill=OUTL)
        cv.da.polygon(p, fill=255)
    for sh in shapes:
        cv.d.polygon(cv._p(sh(0)), fill=fill)


def patch(cv, shapes, fill):
    for sh in shapes:
        cv.d.polygon(cv._p(sh(0)), fill=fill)


def curls(cv, c, rx, ry, n, seed, col=FUR_D):
    """곱슬 털 결: 작은 반달 몇 개 (과하지 않게)"""
    for k in range(n):
        t = (k * 2.399 + seed) % (2 * math.pi)
        r = 0.3 + 0.55 * ((k * 0.618 + seed * 0.37) % 1)
        x, y = c[0] + math.cos(t) * rx * r, c[1] + math.sin(t) * ry * r
        cv.line([(x - 6, y + 1), (x - 2, y - 4), (x + 4, y - 4), (x + 7, y + 1)], w=W_LINE * 0.32, col=col)


def mouth_stick(cv, p0, p1, r=9):
    """입에 문 나뭇가지"""
    layer(cv, [capsule(p0, p1, r, r * 0.85)], BARK)
    mx, my = (p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2
    layer(cv, [capsule((mx + (p1[0] - p0[0]) * 0.25, my + (p1[1] - p0[1]) * 0.25), (mx + (p1[0] - p0[0]) * 0.33, my - 22), 4, 3)], BARK)
    cv.line([(p0[0] + 10, p0[1] - 2), (p1[0] - 10, p1[1] - 2)], w=W_LINE * 0.3, col=BARK_D)


def eye(cv, c, kind='open', r=7.0):
    if kind == 'open':
        cv.dot(c, r, DARK)
        cv.dot((c[0] + r * 0.3, c[1] - r * 0.35), r * 0.36, (255, 255, 255))
    elif kind == 'closed':
        cv.line([(c[0] - 8, c[1] - 1), (c[0], c[1] + 4), (c[0] + 8, c[1] - 1)], w=W_LINE * 0.6, col=OUTL)
    elif kind == 'happy':
        cv.line([(c[0] - 8, c[1] + 3), (c[0], c[1] - 4), (c[0] + 8, c[1] + 3)], w=W_LINE * 0.6, col=OUTL)


def rot(hc, ang):
    a = math.radians(ang)
    def P(dx, dy):
        return (hc[0] + dx * math.cos(a) - dy * math.sin(a), hc[1] + dx * math.sin(a) + dy * math.cos(a))
    return P


# ───────── 옆얼굴 (오른쪽을 봄) ─────────
def side_head_shapes(hc, ang, mouth):
    """머리 실루엣 (몸과 같은 겹에 넣어 윤곽선이 하나로 이어짐): 둥근 머리 + 탑노트 + 짧고 둥근 주둥이"""
    P = rot(hc, ang)
    sh = [fluff(hc, 58, 54, ang, n=12, amp=0.06), fluff(P(-6, -36), 50, 36, ang, n=10, amp=0.08, ph=0.6),
          fluff(P(56, 18), 40, 25, ang - 4, n=8, amp=0.05)]
    if mouth in ('open', 'pant', 'howl'):
        sh.append(oval(P(50, 44), 26, 13, ang))                          # 벌린 아래턱
    return sh


def side_head_detail(cv, hc, ang, mouth='closed', eyek='open', ear_swing=0.0, tongue=0.0, carry=False):
    P = rot(hc, ang)
    patch(cv, [fluff(P(-4, -40), 36, 20, ang, n=8, amp=0.08)], FUR_L)     # 머리 위 빛
    if mouth in ('open', 'pant', 'howl'):
        if mouth == 'howl':
            cv.d.polygon(cv._p(oval(P(84, 32), 8, 10, ang)(0)), fill=MOUTH)
        else:
            cv.d.polygon(cv._p([P(44, 34), P(90, 30), P(80, 46 if mouth != 'pant' else 42), P(48, 46)]), fill=MOUTH)
            if mouth == 'pant' or tongue > 0:
                tg = oval(P(68, 48 + tongue), 10, 14, ang + 10)
                cv.d.polygon(cv._p(tg(W_LINE * 0.55)), fill=OUTL)
                cv.d.polygon(cv._p(tg(0)), fill=TONGUE)
    else:
        cv.line([P(60, 36), P(74, 38), P(88, 33)], w=W_LINE * 0.45, col=OUTL)
    # 코 · 눈
    cv.d.polygon(cv._p(oval(P(94, 12), 12, 10, ang)(0)), fill=DARK)
    cv.dot(P(90, 8), 2.6, (255, 255, 255))
    eye(cv, P(26, -6), eyek)
    # 가까운 귀: 머리 옆 위쪽에서 턱 아래까지 길게 늘어진 복슬 귀 (머리에 겹쳐 붙음)
    ea = ang + 6 + ear_swing
    layer(cv, [fluff(P(-16, 34), 28, 50, ea, n=10, amp=0.09, ph=0.3)], EAR)
    curls(cv, P(-16, 40), 18, 34, 3, 2.1, col=FUR_D)
    if carry:
        mouth_stick(cv, P(-20, 40), P(116, 34))


def far_ear(hc, ang, ear_swing=0.0):
    P = rot(hc, ang)
    return fluff(P(-40, 26), 22, 42, ang + 14 + ear_swing, n=8, amp=0.09)


# ───────── 옆모습 몸 ─────────
def gait(base, p, stride, lift):
    """발 하나의 걸음: 땅을 딛고 뒤로 미는 동안(62%)은 바닥에서 앞→뒤, 드는 동안(38%)은 들어 올려 앞으로.
    돌려줌: (발 자리, 굽힘 0~1 — 들어 올리는 동안 무릎·발목이 접히는 정도)"""
    p %= 1.0
    if stride == 0:
        return (base, FOOT_Y), 0.0
    if p < 0.62:
        u = p / 0.62
        return (base + stride * (1 - 2 * u), FOOT_Y), 0.0
    u = (p - 0.62) / 0.38
    sm = u * u * (3 - 2 * u)
    return (base - stride + 2 * stride * sm, FOOT_Y - lift * math.sin(math.pi * u)), math.sin(math.pi * u)


def legs_pose(ph, stride=18, lift=12):
    """걷는 발 네 개 (뒷다리 먼·가까운, 앞다리 먼·가까운): (발 자리, 굽힘)"""
    return [gait(198, ph + 0.5, stride, lift), gait(176, ph + 0.75, stride, lift),
            gait(284, ph, stride, lift), gait(304, ph + 0.25, stride, lift)]


def ik(a, t, l1, l2, bend):
    """두 마디 다리: 뿌리 a 에서 끝 t 까지 길이 l1·l2 마디의 관절 자리. bend > 0 이면 관절이 앞(+x)으로, < 0 이면 뒤로"""
    dx, dy = t[0] - a[0], t[1] - a[1]
    d = max(abs(l1 - l2) + 1.0, min(l1 + l2 - 0.5, math.hypot(dx, dy)))
    base = math.atan2(dy, dx)
    c = max(-1.0, min(1.0, (l1 * l1 + d * d - l2 * l2) / (2 * l1 * d)))
    A = math.acos(c)
    j1 = (a[0] + l1 * math.cos(base + A), a[1] + l1 * math.sin(base + A))
    j2 = (a[0] + l1 * math.cos(base - A), a[1] + l1 * math.sin(base - A))
    return j1 if (j1[0] - j2[0]) * bend > 0 else j2


def hind_leg(hip, foot, flex=0.0, k=1.0):
    """뒷다리: 굵은 털 허벅지 → 무릎(앞으로 굽음) → 정강이 → 뒤꿈치(뒤로 꺾임) → 발등 → 둥근 털 발.
    들어 올릴 때(flex) 뒤꿈치가 더 접혀 발이 몸 쪽으로 당겨짐"""
    hock = (foot[0] - 15 - 12 * flex, foot[1] - 40 + 8 * flex)
    stifle = ik(hip, hock, 62 * k, 56 * k, +1)
    paw = (foot[0] + 4 - 4 * flex, foot[1])
    return [capsule(hip, stifle, 33 * k, 25 * k), capsule(stifle, hock, 23 * k, 18 * k), fluff(stifle, 25 * k, 24 * k, 0, n=8, amp=0.07),
            capsule(hock, (paw[0] - 2, paw[1] - 8), 18 * k, 17 * k), fluff(paw, 25 * k, 15 * k, -10 * flex, n=8, amp=0.07)]


def front_leg(shoulder, foot, flex=0.0, k=1.0):
    """앞다리: 어깨 → 팔꿈치(뒤로 굽음) → 아래팔(곧음) → 앞발목(들 때 뒤로 접힘) → 둥근 털 발"""
    wrist = (foot[0] - 2 + 16 * flex, foot[1] - 24 + 6 * flex)
    elbow = ik(shoulder, wrist, 52 * k, 64 * k, -1)
    paw = (foot[0] + 3 - 6 * flex, foot[1])
    return [capsule(shoulder, elbow, 29 * k, 23 * k), capsule(elbow, wrist, 22 * k, 19 * k),
            capsule(wrist, (paw[0], paw[1] - 7), 19 * k, 17 * k), fluff(paw, 25 * k, 15 * k, 14 * flex, n=8, amp=0.07)]


def leg(top, foot, r0=24, r1=21):
    """곧은 다리 + 둥근 털 발 (앉은 자세·정면·뒷모습에서 씀)"""
    return [capsule(top, (foot[0], foot[1] - 8), r0, r1), fluff((foot[0] + 3, foot[1]), 25, 15, 0, n=8, amp=0.07)]


def _ff(f):
    """발 자리만 주면 굽힘 0"""
    if isinstance(f[0], tuple):
        return f
    return (f, 0.0)


def draw_stand(cv, feet, body=(240, 318, 98, 58, -3), head=(366, 200), hang=0.0, mouth='closed', eyek='open',
               tail=(0.0,), ear_swing=0.0, tongue=0.0, bob=0.0, carry=False):
    bx, by, brx, bry, bang = body
    by += bob
    (rf, rfx), (rn, rnx), (ff, ffx), (fn, fnx) = [_ff(f) for f in feet]
    hc = (head[0], head[1] + bob * 0.6)
    tw = tail[0]
    # 엉덩이·어깨 관절 자리 (몸이 기울면 같이): 뒷다리는 엉덩이 아래, 앞다리는 가슴 아래
    ca, sa = math.cos(math.radians(bang)), math.sin(math.radians(bang))
    def on_body(dx, dy):
        return (bx + dx * ca - dy * sa, by + dx * sa + dy * ca)
    hip_n, hip_f = on_body(-brx * 0.58, 14), on_body(-brx * 0.42, 10)
    sho_n, sho_f = on_body(brx * 0.62, 16), on_body(brx * 0.46, 12)
    # 먼 다리·먼 귀 (뒤에, 조금 그늘)
    layer(cv, hind_leg(hip_f, rf, rfx, 0.94) + front_leg(sho_f, ff, ffx, 0.94) + [far_ear(hc, hang, ear_swing)], FUR_D)
    # 한 덩어리: 몸 + 엉덩이 털 + 가슴 털 + 목 + 머리 + 가까운 다리 + 꼬리(방울)
    a = math.radians(tw)
    tb = (bx - brx * 0.86, by - bry * 0.55)                                 # 꼬리 밑동
    tt = (tb[0] - 22 + 48 * math.sin(a), tb[1] - 44 * math.cos(a))          # 꼬리 끝 (흔들림)
    shapes = [fluff((bx, by), brx, bry, bang, n=22, amp=0.04),
              fluff((bx - brx * 0.62, by + 6), 48, 56, 0, n=10, amp=0.06),           # 엉덩이 털
              fluff((bx + brx * 0.74, by - 10), 46, 54, 0, n=10, amp=0.06),          # 가슴 털
              capsule((bx + brx * 0.72, by - 18), (hc[0] - 8, hc[1] + 28), 40, 36),  # 목
              capsule(tb, tt, 11, 9), fluff(tt, 25, 23, 0, n=10, amp=0.1)]
    shapes += side_head_shapes(hc, hang, 'closed' if carry else mouth)
    shapes += hind_leg(hip_n, rn, rnx) + front_leg(sho_n, fn, fnx)
    layer(cv, shapes, FUR)
    patch(cv, [fluff((bx - 6, by - bry * 0.55), brx * 0.62, 16, bang, n=12, amp=0.08)], FUR_L)       # 등 빛
    curls(cv, (bx - 10, by + 4), brx * 0.7, bry * 0.55, 6, 1.3)
    curls(cv, (bx - brx * 0.62, by + 8), 30, 36, 3, 4.2)
    for f in (rn, fn):                                                       # 발가락 사이 가는 결
        cv.line([(f[0] - 2, f[1] - 2), (f[0] - 2, f[1] + 8)], w=W_LINE * 0.3, col=OUTL)
        cv.line([(f[0] + 10, f[1] - 2), (f[0] + 10, f[1] + 8)], w=W_LINE * 0.3, col=OUTL)
    side_head_detail(cv, hc, hang, 'closed' if carry else mouth, eyek, ear_swing, 0 if carry else tongue, carry=carry)


def draw_sit(cv, head=(338, 182), hang=-4, mouth='closed', eyek='open', tail_wave=0.0, paw=False, tongue=0.0, ear_swing=0.0):
    hc = head
    far = leg((268, 360), (272, FOOT_Y), 22, 19) + [far_ear(hc, hang, ear_swing)]
    layer(cv, far, FUR_D)
    tb, tt = (168, 410), (128 - tail_wave * 0.6, 396 - tail_wave)
    shapes = [fluff((232, 404), 74, 58, 0, n=16, amp=0.05),                  # 엉덩이 (앉음)
              fluff((262, 330), 58, 80, -14, n=18, amp=0.045),               # 세운 몸
              fluff((292, 300), 42, 50, 0, n=10, amp=0.06),                  # 가슴 털
              capsule((288, 276), (hc[0] - 10, hc[1] + 28), 38, 34),          # 목
              fluff((222, 438), 54, 30, 0, n=10, amp=0.07),                  # 뒷다리 허벅지
              fluff((266, FOOT_Y), 27, 15, 0, n=8, amp=0.07),                # 뒷발
              capsule(tb, tt, 10, 9), fluff(tt, 24, 22, 0, n=10, amp=0.1)]
    if paw:
        shapes += [capsule((300, 330), (362, 318), 22, 19), fluff((366, 318), 20, 16, 0, n=8, amp=0.07)]
    else:
        shapes += leg((300, 352), (304, FOOT_Y), 24, 21)
    shapes += side_head_shapes(hc, hang, mouth)
    layer(cv, shapes, FUR)
    curls(cv, (236, 396), 46, 34, 4, 0.7)
    curls(cv, (262, 330), 34, 50, 3, 2.9)
    cv.line([(236, 444), (258, 450)], w=W_LINE * 0.35, col=OUTL)
    side_head_detail(cv, hc, hang, mouth, eyek, ear_swing, tongue)


def draw_lie(cv, eyek='open', breath=0.0, head_down=False):
    hc = (392, 352) if not head_down else (398, 372)
    hang = 0 if not head_down else 10
    layer(cv, [far_ear(hc, hang, -30)], FUR_D)
    shapes = [fluff((236, 420), 122, 44 + breath, 0, n=24, amp=0.035),
              fluff((166, 418), 52, 44, 0, n=10, amp=0.06),                 # 뒷다리 허벅지
              capsule((320, 440), (404, FOOT_Y - 2), 20, 18), fluff((410, FOOT_Y - 2), 22, 14, 0, n=8, amp=0.07),
              capsule((300, 446), (378, FOOT_Y + 2), 21, 19), fluff((384, FOOT_Y + 2), 23, 14, 0, n=8, amp=0.07),
              capsule((330, 410), (hc[0] - 10, hc[1] + 28), 36, 32),
              capsule((118, 420), (98, 404), 9, 8), fluff((94, 400), 22, 20, 0, n=10, amp=0.1)]
    shapes += side_head_shapes(hc, hang, 'closed')
    layer(cv, shapes, FUR)
    patch(cv, [fluff((226, 388), 80, 12, 0, n=12, amp=0.08)], FUR_L)
    curls(cv, (226, 420), 90, 26, 6, 5.1)
    side_head_detail(cv, hc, hang, 'closed', eyek, ear_swing=-30)


def draw_sleep(cv, breath=0.0):
    hc = (372, 392)
    shapes = [fluff((246, 424), 116, 46 + breath, 0, n=24, amp=0.035),
              fluff((170, 424), 50, 42, 0, n=10, amp=0.06),
              capsule((320, 420), (hc[0] - 12, hc[1] + 18), 34, 30),
              fluff((138, 448), 22, 20, 0, n=10, amp=0.1)]                   # 꼬리 방울을 몸에 붙임
    shapes += side_head_shapes(hc, 16, 'closed')
    layer(cv, shapes, FUR)
    patch(cv, [fluff((236, 390), 76, 12, 0, n=12, amp=0.08)], FUR_L)
    curls(cv, (236, 424), 86, 26, 6, 6.3)
    side_head_detail(cv, hc, 16, 'closed', 'closed', ear_swing=-40)


def draw_playbow(cv, k):
    feet = [(212, FOOT_Y), (190, FOOT_Y), (318, FOOT_Y), (344, FOOT_Y)]
    draw_stand(cv, feet, body=(244, 320, 104, 58, 18), head=(386, 314), hang=-8, mouth='pant', tongue=3 * k,
               tail=(18 * (k * 2 - 1),), ear_swing=10 * k)


def draw_jump(cv, k):
    """신나서 뒷발로 서서 앞발을 듦"""
    hc = (306, 168)
    layer(cv, [far_ear(hc, -16, 20)] + [capsule((262, 302), (322, 280 - 6 * k), 20, 18), fluff((326, 278 - 6 * k), 19, 15, 0, n=8, amp=0.07)], FUR_D)
    shapes = [fluff((240, 330), 64, 98, 16, n=20, amp=0.04),
              fluff((214, 404), 50, 42, 0, n=10, amp=0.06),
              capsule((270, 252), (hc[0] - 6, hc[1] + 28), 36, 32),
              capsule((206, 420), (204, FOOT_Y - 6), 26, 22), fluff((208, FOOT_Y), 25, 15, 0, n=8, amp=0.07),
              capsule((246, 420), (250, FOOT_Y - 6), 26, 22), fluff((254, FOOT_Y), 25, 15, 0, n=8, amp=0.07),
              capsule((282, 292), (342, 260 - 10 * k), 22, 19), fluff((346, 258 - 10 * k), 20, 16, 0, n=8, amp=0.07),
              capsule((176, 360), (150, 330), 10, 9), fluff((146, 324), 23, 21, 0, n=10, amp=0.1)]
    shapes += side_head_shapes(hc, -16, 'pant')
    layer(cv, shapes, FUR)
    curls(cv, (240, 330), 40, 70, 5, 3.3)
    side_head_detail(cv, hc, -16, 'pant', 'happy', ear_swing=20, tongue=3)


def draw_roll(cv, k):
    """등을 대고 누워 네 발을 들고 꼼지락 (몸에 붙은 다리, 머리는 거꾸로 옆에)"""
    wig = (k * 2 - 1) * 8
    hc = (386, 392)
    feet = [(176 + wig, 320), (222 - wig, 312), (280 + wig, 316), (322 - wig, 326)]
    layer(cv, [capsule((f[0] + 6, 396), f, 17, 15) for f in feet[:2]] + [fluff(f, 17, 19, 0, n=8, amp=0.07) for f in feet[:2]], FUR_D)
    shapes = [fluff((246, 420), 112, 50, 0, n=22, amp=0.035),
              capsule((322, 420), (hc[0] - 20, hc[1] + 6), 36, 32),
              capsule((128, 430), (100, 420), 9, 8), fluff((94, 418), 22, 20, 0, n=10, amp=0.1)]
    for f in feet[2:]:
        shapes += [capsule((f[0] - 6, 400), f, 18, 16), fluff(f, 18, 20, 0, n=8, amp=0.07)]
    shapes += side_head_shapes(hc, -34, 'pant')
    layer(cv, shapes, FUR)
    patch(cv, [fluff((250, 402), 80, 22, 0, n=12, amp=0.06)], FUR_L)          # 배
    side_head_detail(cv, hc, -34, 'pant', 'happy', ear_swing=-30, tongue=3)


def draw_dig(cv, k):
    feet = [(214, FOOT_Y), (192, FOOT_Y), (330 - 18 * k, FOOT_Y - 8), (352 + 18 * k, FOOT_Y - 16 + 8 * k)]
    draw_stand(cv, feet, body=(240, 316, 104, 58, 14), head=(388, 318), hang=24, tail=(25 * (k * 2 - 1),))
    for i in range(6):                                                       # 튀는 흙
        x = 318 - i * 14 - 20 * k
        y = 430 - (i % 3) * 18 - 12 * k
        cv.dot((x, y), 5 - (i % 2), DIRT)


# ───────── 정면 ─────────
def front_head_shapes(hc, tilt):
    P = rot(hc, tilt)
    return [fluff(hc, 68, 62, tilt, n=14, amp=0.06), fluff(P(0, -44), 58, 38, tilt, n=12, amp=0.08, ph=0.4)]


def front_head_detail(cv, hc, tilt=0.0, eyek='open', mouth='closed', tongue=0.0, ear_swing=0.0, carry=False):
    P = rot(hc, tilt)
    patch(cv, [fluff(P(0, -50), 40, 20, tilt, n=10, amp=0.08)], FUR_L)
    # 주둥이 (조금 밝게) + 코 + 눈
    patch(cv, [fluff(P(0, 30), 34, 26, tilt, n=10, amp=0.06)], FUR_L)
    for sx in (-1, 1):
        eye(cv, P(sx * 28, -6), eyek, r=7.5)
    cv.d.polygon(cv._p(oval(P(0, 20), 13, 10, tilt)(0)), fill=DARK)
    cv.dot(P(-4, 16), 2.8, (255, 255, 255))
    if mouth == 'pant' or tongue > 0:
        cv.d.polygon(cv._p([P(-12, 34), P(12, 34), P(0, 46)]), fill=MOUTH)
        tg = oval(P(0, 48 + tongue), 9, 13, tilt)
        cv.d.polygon(cv._p(tg(W_LINE * 0.5)), fill=OUTL)
        cv.d.polygon(cv._p(tg(0)), fill=TONGUE)
    else:
        cv.line([P(0, 28), P(0, 36)], w=W_LINE * 0.4, col=OUTL)
        cv.line([P(-10, 40), P(-4, 43), P(0, 38), P(4, 43), P(10, 40)], w=W_LINE * 0.4, col=OUTL)
    # 양옆으로 길게 늘어진 복슬 귀 (얼굴 옆에 붙어 턱 아래까지)
    for sx in (-1, 1):
        layer(cv, [fluff(P(sx * 62, 22), 26, 56, tilt - sx * (6 + ear_swing), n=10, amp=0.09, ph=0.2 * sx)], EAR)
        curls(cv, P(sx * 62, 28), 14, 36, 3, 1.7 + sx)
    if carry:
        mouth_stick(cv, P(-128, 40), P(128, 34))


def front_body_shapes(lift_l=0.0, lift_r=0.0, sit=True):
    sh = [fluff((256, 368), 76, 70, 0, n=18, amp=0.05),                       # 가슴·몸
          fluff((256, 300), 54, 40, 0, n=12, amp=0.06)]                       # 목 (머리와 이어짐)
    for x, lift in ((226, lift_l), (286, lift_r)):
        sh += [capsule((x, 400), (x, FOOT_Y - 8 - lift), 25, 22), fluff((x, FOOT_Y - lift), 26, 15, 0, n=8, amp=0.07)]
    if sit:
        sh += [fluff((176, 440), 34, 30, 0, n=8, amp=0.07), fluff((336, 440), 34, 30, 0, n=8, amp=0.07)]   # 옆으로 보이는 뒷다리
    return sh


def draw_front(cv, sit=True, lift_l=0.0, lift_r=0.0, tail_wave=0.0, hc=(256, 214), tilt=0.0, eyek='open', mouth='closed',
               tongue=0.0, ear_swing=0.0, carry=False):
    # 몸 뒤로 살짝 보이는 꼬리 방울
    layer(cv, [fluff((318 + tail_wave, 306), 20, 18, 0, n=10, amp=0.1)], FUR_D)
    layer(cv, front_body_shapes(lift_l, lift_r, sit) + front_head_shapes(hc, tilt), FUR)
    cv.line([(256, 404), (256, FOOT_Y - 10)], w=W_LINE * 0.45, col=OUTL)       # 두 앞다리 사이
    cv.line([(hc[0] - 34, hc[1] + 56), (hc[0], hc[1] + 64), (hc[0] + 34, hc[1] + 56)], w=W_LINE * 0.35, col=FUR_D)   # 턱 아래
    curls(cv, (256, 372), 50, 40, 5, 2.2)
    for x, lift in ((226, lift_l), (286, lift_r)):
        f = (x, FOOT_Y - lift)
        cv.line([(f[0] - 7, f[1] - 2), (f[0] - 7, f[1] + 9)], w=W_LINE * 0.3, col=OUTL)
        cv.line([(f[0] + 7, f[1] - 2), (f[0] + 7, f[1] + 9)], w=W_LINE * 0.3, col=OUTL)
    front_head_detail(cv, hc, tilt, eyek, mouth, tongue, ear_swing, carry)


def draw_front_walk(cv, ph, carry=False):
    sw = math.sin(ph * 2 * math.pi)
    draw_front(cv, sit=False, lift_l=max(0, sw) * 10, lift_r=max(0, -sw) * 10, tail_wave=8 * sw,
               hc=(256, 216 + 4 * abs(sw)), tilt=3 * sw, mouth='closed' if carry else 'pant', tongue=0 if carry else 1,
               ear_swing=6 * sw, carry=carry)


def draw_back(cv, ph, sit=False, carry=False):
    sw = math.sin(ph * 2 * math.pi)
    lift_l, lift_r = (0, 0) if sit else (max(0, -sw) * 10, max(0, sw) * 10)
    hc = (256, 222)
    if carry:                                                                 # 문 막대 양끝이 머리 양옆으로 보임
        mouth_stick(cv, (256 - 140, 262), (256 + 140, 256))
    shapes = [fluff((256, 378), 80, 68, 0, n=18, amp=0.05), fluff((256, 300), 54, 40, 0, n=12, amp=0.06)] + front_head_shapes(hc, 0)
    for x, lift in ((226, lift_l), (286, lift_r)):
        shapes += [capsule((x, 404), (x, FOOT_Y - 8 - lift), 26, 22), fluff((x, FOOT_Y - lift), 26, 15, 0, n=8, amp=0.07)]
    layer(cv, shapes, FUR)
    patch(cv, [fluff((256, 196), 46, 26, 0, n=10, amp=0.08)], FUR_L)
    cv.line([(256, 410), (256, FOOT_Y - 10)], w=W_LINE * 0.45, col=OUTL)
    curls(cv, (256, 372), 54, 40, 5, 3.7)
    for sx in (-1, 1):                                                         # 뒤에서 보이는 늘어진 귀
        layer(cv, [fluff((hc[0] + sx * 60, hc[1] + 22), 26, 54, -sx * (6 + 6 * sw), n=10, amp=0.09)], EAR)
    # 엉덩이 위로 선 꼬리 + 털 방울 (흔듦)
    layer(cv, [fluff((256 + 6 * sw, 318), 22, 21, 0, n=10, amp=0.1)], FUR)     # 엉덩이 위 꼬리 방울 (흔듦)


def frames():
    f = {}
    def mk(name, fn):
        cv = Canvas()
        fn(cv)
        f[name] = cv
    still = legs_pose(0.0, stride=0, lift=0)
    for i in range(2):
        mk(f'dog_stand{i}', lambda cv, i=i: draw_stand(cv, still, tail=(22 * (i * 2 - 1),)))
    for i in range(6):
        ph = i / 6
        mk(f'dog_walk{i}', lambda cv, ph=ph: draw_stand(cv, legs_pose(ph), bob=-3 * abs(math.sin(ph * 2 * math.pi)),
                                                        tail=(16 * math.sin(ph * 2 * math.pi),),
                                                        ear_swing=5 * math.sin(ph * 2 * math.pi)))
    for i in range(4):
        ph = i / 4
        mk(f'dog_run{i}', lambda cv, ph=ph: draw_stand(cv, legs_pose(ph, stride=30, lift=22),
                                                       body=(238, 312, 104, 56, -3 + 5 * math.sin(ph * 2 * math.pi)),
                                                       bob=-10 * abs(math.sin(ph * 2 * math.pi)), head=(374, 192), mouth='pant', tongue=2,
                                                       tail=(-10,), ear_swing=-24))
    mk('dog_sit0', lambda cv: draw_sit(cv, tail_wave=0))
    mk('dog_sit1', lambda cv: draw_sit(cv, tail_wave=16))
    mk('dog_blink', lambda cv: draw_sit(cv, eyek='closed', tail_wave=8))
    mk('dog_pant0', lambda cv: draw_sit(cv, mouth='pant', eyek='happy', tongue=0))
    mk('dog_pant1', lambda cv: draw_sit(cv, mouth='pant', eyek='happy', tongue=5))
    mk('dog_howl', lambda cv: draw_sit(cv, head=(326, 168), hang=-40, mouth='howl', eyek='closed', ear_swing=-20))
    mk('dog_paw', lambda cv: draw_sit(cv, mouth='pant', eyek='happy', paw=True))
    mk('dog_bark', lambda cv: draw_stand(cv, still, mouth='open', tail=(20,), ear_swing=-8))
    mk('dog_sniff0', lambda cv: draw_stand(cv, legs_pose(0.1, stride=6, lift=3), head=(384, 300), hang=34, tail=(-10,)))
    mk('dog_sniff1', lambda cv: draw_stand(cv, legs_pose(0.6, stride=6, lift=3), head=(386, 304), hang=38, tail=(10,)))
    mk('dog_lie0', lambda cv: draw_lie(cv))
    mk('dog_lie1', lambda cv: draw_lie(cv, eyek='closed', breath=3, head_down=True))
    mk('dog_sleep0', lambda cv: draw_sleep(cv, 0))
    mk('dog_sleep1', lambda cv: draw_sleep(cv, 4))
    mk('dog_bow0', lambda cv: draw_playbow(cv, 0))
    mk('dog_bow1', lambda cv: draw_playbow(cv, 1))
    mk('dog_jump0', lambda cv: draw_jump(cv, 0))
    mk('dog_jump1', lambda cv: draw_jump(cv, 1))
    mk('dog_roll0', lambda cv: draw_roll(cv, 0))
    mk('dog_roll1', lambda cv: draw_roll(cv, 1))
    mk('dog_dig0', lambda cv: draw_dig(cv, 0))
    mk('dog_dig1', lambda cv: draw_dig(cv, 1))
    mk('dog_fsit0', lambda cv: draw_front(cv))
    mk('dog_fsit1', lambda cv: draw_front(cv, mouth='pant', tongue=2))
    mk('dog_fblink', lambda cv: draw_front(cv, eyek='closed'))
    mk('dog_ftilt', lambda cv: draw_front(cv, tilt=-16))
    mk('dog_fhappy', lambda cv: draw_front(cv, eyek='happy', mouth='pant', tongue=5))
    for i in range(4):
        mk(f'dog_fwalk{i}', lambda cv, ph=i / 4: draw_front_walk(cv, ph))
        mk(f'dog_bwalk{i}', lambda cv, ph=i / 4: draw_back(cv, ph))
    mk('dog_bsit', lambda cv: draw_back(cv, 0, sit=True))
    # 막대를 물고 다닐 때 (그림에 막대를 함께 그림)
    for i in range(6):
        ph = i / 6
        mk(f'dog_cwalk{i}', lambda cv, ph=ph: draw_stand(cv, legs_pose(ph), bob=-3 * abs(math.sin(ph * 2 * math.pi)),
                                                         tail=(16 * math.sin(ph * 2 * math.pi),),
                                                         ear_swing=5 * math.sin(ph * 2 * math.pi), carry=True))
    for i in range(4):
        ph = i / 4
        mk(f'dog_crun{i}', lambda cv, ph=ph: draw_stand(cv, legs_pose(ph, stride=30, lift=22),
                                                        body=(238, 312, 104, 56, -3 + 5 * math.sin(ph * 2 * math.pi)),
                                                        bob=-10 * abs(math.sin(ph * 2 * math.pi)), head=(374, 192),
                                                        tail=(-10,), ear_swing=-24, carry=True))
        mk(f'dog_cfwalk{i}', lambda cv, ph=i / 4: draw_front_walk(cv, ph, carry=True))
        mk(f'dog_cbwalk{i}', lambda cv, ph=i / 4: draw_back(cv, ph, carry=True))
    return f


def stick():
    """나뭇가지 무늬 (막대 표면)"""
    W, H = 128, 64
    im = Image.new('RGB', (W, H), (120, 84, 50))
    d = ImageDraw.Draw(im)
    for y in range(0, H, 6):
        d.line([(0, y), (W, y + 2)], fill=(96, 66, 40), width=2)
    return im


def dog_sprites(out):
    os.makedirs(out, exist_ok=True)
    for name, cv in frames().items():
        cv.save(out, name)
    stick().save(os.path.join(out, 'stick.png'), optimize=True)


if __name__ == '__main__':
    import sys
    o = sys.argv[1] if len(sys.argv) > 1 else '.'
    dog_sprites(o)
    names = sorted(n for n in os.listdir(o) if n.startswith('dog_') and n.endswith('.png') and not n.endswith('_a.png'))
    cols = 8
    rows = (len(names) + cols - 1) // cols
    sheet = Image.new('RGB', (cols * 256, rows * 280), (200, 200, 200))
    d = ImageDraw.Draw(sheet)
    for i, n in enumerate(names):
        im = Image.open(os.path.join(o, n)).convert('RGBA').resize((256, 256))
        bg = Image.new('RGBA', im.size, (250, 226, 120, 255))
        bg.alpha_composite(im)
        sheet.paste(bg.convert('RGB'), ((i % cols) * 256, (i // cols) * 280))
        d.text(((i % cols) * 256 + 6, (i // cols) * 280 + 258), n, fill=(0, 0, 0))
    sheet.save(os.path.join(o, 'dogsheet.jpg'), quality=85)
