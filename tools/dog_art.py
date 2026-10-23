"""시골 테마의 강아지 '설이' 그림 — 매끈한 단색 카툰 강아지 (형선이 보내 준 그림 느낌):
연한 노란 크림색 털, 몸에 비해 큰 동그란 머리, 머리 위 양옆에서 접혀 눈높이까지만 내려오는 작은 귀(움직임이 잘 보이게),
반짝이는 큰 갈색 눈·까만 코·분홍 볼, 혀를 내민 웃는 입, 짧고 통통한 다리와 둥근 발, 위로 말린 가는 꼬리.
가장자리는 매끈하고(털 뭉치 없음) 가는 밤색 윤곽선 (선 그림에서는 이 선만 검게 남음).
몸은 옆모습(오른쪽을 봄), 정면·뒷모습도 있음. 512×512, 바닥 줄 y=470"""
import math
import os
from PIL import Image, ImageDraw

from cat_art import capsule, blob, Canvas, INK, W_LINE, S, GROUND

FUR = (250, 222, 160)          # 연한 노란 크림색 털
FUR_D = (238, 198, 128)        # 그늘진 털 (귀·먼 발)
CREAM = (254, 238, 200)        # 주둥이·가슴·발끝 (털보다 조금 밝게)
OUTL = (96, 64, 40)            # 가는 밤색 윤곽선 (선 그림에선 검게)
TONGUE = (236, 120, 132)
MOUTH = (120, 52, 56)
DIRT = (120, 92, 64)
FOOT_Y = GROUND - 8


# ───────── 모양 ─────────
def fluff(c, rx, ry, ang=0.0, n=16, amp=0.045, ph=0.0):
    """곱슬 털 덩어리: 가장자리가 오돌토돌한 타원"""
    def poly(g):
        a = math.radians(ang)
        pts = []
        for k in range(144):
            t = k / 144 * 2 * math.pi
            bump = 1.0                     # 매끈한 윤곽 (곱슬 털 뭉치 없앰)
            x, y = (rx * bump + g) * math.cos(t), (ry * bump + g) * math.sin(t)
            pts.append((c[0] + x * math.cos(a) - y * math.sin(a), c[1] + x * math.sin(a) + y * math.cos(a)))
        return pts
    return poly


BARK = (150, 104, 62)
BARK_D = (118, 80, 46)


def mouth_stick(cv, p0, p1, r=9):
    """입에 문 나뭇가지: 가는 밤색 윤곽의 막대 + 결 + 곁가지 하나"""
    layer(cv, [capsule(p0, p1, r, r * 0.85)], BARK)
    mx, my = (p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2
    layer(cv, [capsule((mx + (p1[0] - p0[0]) * 0.25, my + (p1[1] - p0[1]) * 0.25), (mx + (p1[0] - p0[0]) * 0.33, my - 22), 4, 3)], BARK)
    cv.line([(p0[0] + 10, p0[1] - 2), (p1[0] - 10, p1[1] - 2)], w=W_LINE * 0.3, col=BARK_D)


def oval(c, rx, ry, ang=0.0):
    return fluff(c, rx, ry, ang, amp=0.0)


def nub(top, foot, r_top=26, r_foot=22):
    """몸에서 이어져 내려오는 짧고 통통한 발 (몸과 같은 겹에 그려 윤곽이 하나로 이어짐)"""
    return capsule(top, foot, r_top, r_foot)


def layer(cv, shapes, fill):
    """검게 부풀려 그린 뒤 색으로 채움 → 겹친 모양들은 바깥 윤곽선 하나로 이어짐"""
    for sh in shapes:
        p = cv._p(sh(W_LINE * 0.7))
        cv.d.polygon(p, fill=OUTL)
        cv.da.polygon(p, fill=255)
    for sh in shapes:
        cv.d.polygon(cv._p(sh(0)), fill=fill)


def patch(cv, shapes, fill):
    """윤곽선 없이 안쪽에만 칠함"""
    for sh in shapes:
        cv.d.polygon(cv._p(sh(0)), fill=fill)


def curl_marks(cv, c, rx, ry, n=5, seed=0, col=FUR_D):
    """(매끈한 털이라 결 표시는 그리지 않음)"""
    return
    for k in range(n):
        t = (k * 2.399 + seed) % (2 * math.pi)
        r = 0.35 + 0.45 * ((k * 0.618 + seed * 0.3) % 1)
        x, y = c[0] + math.cos(t) * rx * r, c[1] + math.sin(t) * ry * r
        cv.line([(x - 6, y), (x - 2, y - 5), (x + 4, y - 3)], w=W_LINE * 0.45, col=col)


def eye_dot(cv, c, kind='open', r=7.5):
    if kind == 'open':
        r = r * 1.35                                          # 크고 반짝이는 갈색 눈
        cv.dot(c, r, (52, 32, 22))
        cv.dot((c[0] + r * 0.32, c[1] - r * 0.36), r * 0.34, (255, 255, 255))
        cv.dot((c[0] - r * 0.3, c[1] + r * 0.35), r * 0.14, (255, 255, 255))
    elif kind == 'closed':
        cv.line([(c[0] - 8, c[1] - 1), (c[0], c[1] + 4), (c[0] + 8, c[1] - 1)], w=W_LINE * 0.6)
    elif kind == 'happy':
        cv.line([(c[0] - 8, c[1] + 3), (c[0], c[1] - 4), (c[0] + 8, c[1] + 3)], w=W_LINE * 0.6)


def tail_curve(base, wag=0.0, back=1.0):
    """위로 말린 가는 꼬리: 밑동(굵음) → 끝(가늘게), wag 도만큼 흔들림. back=1 이면 왼쪽(뒤)으로 휨"""
    a = math.radians(wag)
    pts0 = [(0, 0), (-16 * back, -22), (-20 * back, -48), (-10 * back, -70)]
    pts = [(base[0] + x * math.cos(a) - y * math.sin(a), base[1] + x * math.sin(a) + y * math.cos(a)) for x, y in pts0]
    return blob(pts, [14, 12, 10, 8])


# ───────── 옆모습 ─────────
def side_head(cv, hc, ang=0.0, mouth='closed', eye='open', ear_swing=0.0, tongue=0.0, carry=False):
    """옆얼굴 (오른쪽을 봄): 동그란 곱슬 머리 + 앞으로 살짝 나온 크림색 주둥이 + 까만 코 + 점 눈 + 축 늘어진 큰 귀.
    ang: 고개 들기(-) / 숙이기(+) (도), ear_swing: 귀가 뒤로 흔들림(도)"""
    a = math.radians(ang)
    def P(dx, dy):
        return (hc[0] + dx * math.cos(a) - dy * math.sin(a), hc[1] + dx * math.sin(a) + dy * math.cos(a))
    # 먼 귀 (머리 위 뒤쪽에 살짝 보임)
    layer(cv, [oval(P(-36, -58), 24, 34, ang - 40 + ear_swing)], FUR_D)
    shapes = [fluff(hc, 92, 84, ang, n=18, amp=0.04), fluff(P(64, 30), 44, 36, ang, n=10, amp=0.05)]
    if mouth in ('open', 'pant', 'howl'):
        shapes.append(oval(P(60, 58 if mouth != 'pant' else 52), 26, 16, ang))
    layer(cv, shapes, FUR)
    curl_marks(cv, P(-20, -30), 50, 36, n=5, seed=1)
    # 크림색 주둥이
    patch(cv, [fluff(P(66, 32), 40, 31, ang, n=10, amp=0.05)], CREAM)
    if mouth in ('open', 'pant', 'howl'):
        patch(cv, [oval(P(60, 58 if mouth != 'pant' else 52), 22, 12, ang)], CREAM)
        if mouth == 'howl':
            o = oval(P(84, 52), 9, 11, ang)
            cv.d.polygon(cv._p(o(0)), fill=MOUTH)
        else:
            cv.d.polygon(cv._p([P(52, 46), P(96, 44), P(86, 58 if mouth != 'pant' else 54), P(56, 56)]), fill=MOUTH)
            if mouth == 'pant' or tongue > 0:
                tg = oval(P(76, 60 + tongue), 11, 15, ang + 10)
                cv.d.polygon(cv._p(tg(W_LINE * 0.55)), fill=INK)
                cv.d.polygon(cv._p(tg(0)), fill=TONGUE)
    else:
        cv.line([P(70, 48), P(82, 52), P(94, 46)], w=W_LINE * 0.5)
    # 코 · 눈 · 볼
    nz = oval(P(102, 22), 13, 10, ang)
    cv.d.polygon(cv._p(nz(0)), fill=INK)
    cv.dot(P(98, 18), 2.6, (255, 255, 255))
    eye_dot(cv, P(36, -4), eye)
    cv.dot(P(40, 24), 9, (248, 178, 160))
    # 가까운 귀: 머리 위 옆에서 접혀 앞으로 살짝 내려온 작은 귀 (눈 위·뒤, 눈높이까지만)
    layer(cv, [oval(P(-18, -40), 28, 40, ang + 28 + ear_swing)], FUR_D)
    if carry:
        # 막대를 가로로 물고 있음: 주둥이 아래쪽(입)에 걸쳐 앞뒤로 삐져나옴
        mouth_stick(cv, P(-24, 56), P(118, 48))


def legs_pose(ph, stride=16, lift=9):
    """걷는 발 네 개의 발끝 자리 (뒷다리 먼·가까운, 앞다리 먼·가까운). 몸에서 바로 이어진 짧은 발이라 보폭이 작음"""
    def foot(px, p):
        s = math.sin(p * 2 * math.pi)
        c = math.cos(p * 2 * math.pi)
        return (px + s * stride, FOOT_Y - max(0, c) * lift)
    return [foot(170, ph + 0.5), foot(306, ph + 0.75), foot(150, ph), foot(290, ph + 0.25)]


def draw_stand(cv, feet, body=(234, 356, 104, 70, -2), head=(368, 238), hang=0.0, mouth='closed', eye='open',
               tail=(104, 300, 0.0), ear_swing=0.0, tongue=0.0, bob=0.0, carry=False):
    bx, by, brx, bry, bang = body
    by += bob
    # 꼬리: 엉덩이에서 위로 말려 올라간 가는 꼬리 (tw = 흔드는 각도)
    tx, ty, tw = tail
    layer(cv, tail_curve((tx + 18, ty + 14 + bob), tw), FUR)
    # 몸 + 네 발 + 목: 한 덩어리 (윤곽선 하나)
    (rf, rn, ff, fn) = feet
    shapes = [fluff((bx, by), brx, bry, bang, n=20, amp=0.035),
              nub((rf[0] + 4, by + 30), rf, 26, 21), nub((ff[0] - 4, by + 30), ff, 26, 21),
              nub((rn[0] + 4, by + 34), rn, 28, 22), nub((fn[0] - 4, by + 34), fn, 28, 22),
              fluff((bx + brx * 0.7, by - bry * 0.5), 56, 52, 0, n=10, amp=0.05)]
    layer(cv, shapes, FUR)
    # 먼 발은 조금 그늘, 가까운 발과의 사이를 짧은 선으로만 나눔
    for f in (rf, ff):
        patch(cv, [capsule((f[0], f[1] - 26), f, 19, 17)], FUR_D)
    for f in (rf, ff, rn, fn):
        patch(cv, [oval((f[0], f[1] + 2), 19, 12)], CREAM)                                # 하얀 발끝
    for f in (rn, fn):
        cv.line([(f[0] - 18, f[1] - 30), (f[0] - 20, f[1] - 4)], w=W_LINE * 0.45)
        cv.line([(f[0] - 4, f[1] + 4), (f[0] - 4, f[1] + 12)], w=W_LINE * 0.35)
        cv.line([(f[0] + 6, f[1] + 4), (f[0] + 6, f[1] + 12)], w=W_LINE * 0.35)
    # 크림색 가슴
    patch(cv, [fluff((bx + brx * 0.66, by + 6), 40, 46, 0, n=10, amp=0.06)], CREAM)
    curl_marks(cv, (bx - 20, by - 10), brx * 0.6, bry * 0.5, n=7, seed=2)
    side_head(cv, (head[0], head[1] + bob * 0.6), hang, 'closed' if carry else mouth, eye, ear_swing, 0 if carry else tongue, carry=carry)


def draw_sit(cv, head=(330, 214), hang=-4, mouth='closed', eye='open', tail_wave=0.0, paw=False, tongue=0.0, ear_swing=0.0):
    layer(cv, tail_curve((150, 452), -60 + tail_wave), FUR)                                     # 꼬리 (바닥에서 살랑)
    shapes = [fluff((236, 372), 92, 96, -12, n=20, amp=0.035),                                   # 엉덩이·몸
              fluff((196, 428), 72, 42, 0, n=14, amp=0.04),                                       # 뒷다리 허벅지
              nub((292, 380), (300, FOOT_Y), 28, 22)]                                             # 가까운 앞발
    if paw:
        shapes.append(nub((300, 340), (366, 330), 24, 20))                                         # 손 주기: 앞발을 듦
    else:
        shapes.append(nub((262, 384), (266, FOOT_Y), 26, 21))
    layer(cv, shapes, FUR)
    patch(cv, [fluff((286, 336), 40, 54, -8, n=10, amp=0.06)], CREAM)                            # 가슴
    feet = [(300, FOOT_Y)] + ([] if paw else [(266, FOOT_Y)]) + [(214, FOOT_Y + 2)]
    for f in feet:
        patch(cv, [oval((f[0], f[1] + 2), 19, 12)], CREAM)
    if paw:
        patch(cv, [oval((366, 330), 17, 15)], CREAM)
    cv.line([(282, 400), (280, FOOT_Y - 4)], w=W_LINE * 0.45)
    curl_marks(cv, (220, 380), 60, 60, n=6, seed=4)
    side_head(cv, head, hang, mouth, eye, ear_swing, tongue)


def draw_lie(cv, eye='open', breath=0.0, head_down=False):
    layer(cv, [fluff((96, 430), 22, 20, 0, n=8, amp=0.09)], FUR)
    shapes = [fluff((234, 422), 136, 46 + breath, 0, n=24, amp=0.03),
              nub((330, 440), (420, FOOT_Y - 2), 22, 19), nub((300, 446), (392, FOOT_Y), 24, 20)]
    layer(cv, shapes, FUR)
    for f in ((420, FOOT_Y - 2), (392, FOOT_Y)):
        patch(cv, [oval(f, 17, 11)], CREAM)
    curl_marks(cv, (220, 410), 90, 26, n=7, seed=5)
    hc = (384, 352) if not head_down else (392, 368)
    side_head(cv, hc, 8 if head_down else 0, 'closed', eye, ear_swing=-40)


def draw_sleep(cv, breath=0.0):
    shapes = [fluff((248, 420), 128, 48 + breath, 0, n=24, amp=0.03)]
    layer(cv, shapes, FUR)
    curl_marks(cv, (240, 410), 90, 28, n=7, seed=6)
    side_head(cv, (370, 366), 14, 'closed', 'closed', ear_swing=-50)
    layer(cv, [fluff((132, 436), 26, 22, 0, n=8, amp=0.09)], FUR)                              # 꼬리를 몸에 붙임


def draw_playbow(cv, k):
    feet = [(156, FOOT_Y), (330, FOOT_Y), (140, FOOT_Y), (356, FOOT_Y)]
    draw_stand(cv, feet, body=(236, 348, 116, 70, 20), head=(380, 330), hang=-6, mouth='pant', tongue=3 * k,
               tail=(98, 262 - 10 * k, 20 * (k * 2 - 1)), ear_swing=10 * k)


def draw_jump(cv, k):
    """신나서 뒷발로 서서 앞발을 듦"""
    layer(cv, [fluff((150, 404), 24, 22, 0, n=8, amp=0.09)], FUR)
    shapes = [fluff((232, 344), 78, 108, 16, n=20, amp=0.035),
              nub((214, 420), (206, FOOT_Y), 28, 22), nub((248, 422), (250, FOOT_Y), 28, 22),
              nub((280, 300), (338, 262 - 10 * k), 24, 20), nub((262, 310), (320, 280 - 6 * k), 22, 18)]
    layer(cv, shapes, FUR)
    for f in ((206, FOOT_Y), (250, FOOT_Y), (338, 262 - 10 * k), (320, 280 - 6 * k)):
        patch(cv, [oval(f, 17, 12)], CREAM)
    patch(cv, [fluff((262, 318), 34, 60, 16, n=10, amp=0.06)], CREAM)
    side_head(cv, (302, 186), -16, 'pant', 'happy', ear_swing=20, tongue=3)


def draw_roll(cv, k):
    wig = (k * 2 - 1) * 8
    feet = [(180 + wig, 336), (230 - wig, 330), (286 + wig, 334), (206 - wig, 342)]
    shapes = [fluff((236, 420), 124, 50, 0, n=22, amp=0.03)] + [nub((f[0], 392), f, 24, 20) for f in feet]
    layer(cv, shapes, FUR)
    for f in feet:
        patch(cv, [oval(f, 16, 12)], CREAM)
    patch(cv, [fluff((236, 404), 90, 26, 0, n=14, amp=0.05)], CREAM)                           # 배
    side_head(cv, (384, 428), 160, 'pant', 'happy', tongue=2)


def draw_dig(cv, k):
    feet = [(158, FOOT_Y), (330 - 20 * k, FOOT_Y - 6), (142, FOOT_Y), (352 + 20 * k, FOOT_Y - 14 + 8 * k)]
    draw_stand(cv, feet, body=(234, 344, 116, 70, 14), head=(382, 340), hang=24, tail=(100, 274, 25 * (k * 2 - 1)))
    for i in range(6):                                                                           # 튀는 흙
        x = 316 - i * 14 - 20 * k
        y = 430 - (i % 3) * 18 - 12 * k
        cv.dot((x, y), 5 - (i % 2), DIRT)


# ───────── 정면 ─────────
def front_head(cv, hc, tilt=0.0, eye='open', mouth='closed', tongue=0.0, ear_swing=0.0, carry=False):
    a = math.radians(tilt)
    def P(dx, dy):
        return (hc[0] + dx * math.cos(a) - dy * math.sin(a), hc[1] + dx * math.sin(a) + dy * math.cos(a))
    layer(cv, [fluff(hc, 110, 96, tilt, n=22, amp=0.035)], FUR)
    # 머리 위 양옆에서 바깥으로 접혀 내려온 작은 귀 (머리 가장자리에 겹쳐, 눈높이까지)
    for sx in (-1, 1):
        layer(cv, [oval(P(sx * 88, -22), 28, 46, tilt - sx * (24 + ear_swing))], FUR_D)
    curl_marks(cv, P(0, -52), 60, 22, n=4, seed=7)
    # 크림색 주둥이 털 (볼까지 복슬)
    patch(cv, [fluff(P(0, 40), 52, 40, tilt, n=12, amp=0.06)], CREAM)
    for sx in (-1, 1):
        eye_dot(cv, P(sx * 38, -4), eye, r=8.5)
        cv.dot(P(sx * 62, 24), 11, (248, 178, 160))
    nz = oval(P(0, 24), 15, 11, tilt)
    cv.d.polygon(cv._p(nz(0)), fill=INK)
    cv.dot(P(-4, 20), 3, (255, 255, 255))
    if mouth == 'pant' or tongue > 0:
        cv.d.polygon(cv._p([P(-14, 40), P(14, 40), P(0, 52)]), fill=MOUTH)
        tg = oval(P(0, 54 + tongue), 10, 14, tilt)
        cv.d.polygon(cv._p(tg(W_LINE * 0.5)), fill=INK)
        cv.d.polygon(cv._p(tg(0)), fill=TONGUE)
    else:
        cv.line([P(0, 34), P(0, 42)], w=W_LINE * 0.45)
        cv.line([P(-12, 46), P(-5, 50), P(0, 44), P(5, 50), P(12, 46)], w=W_LINE * 0.45)
    if carry:
        mouth_stick(cv, P(-128, 52), P(128, 46))


def front_body(cv, lift_l=0.0, lift_r=0.0, tail_wave=0.0, sit=True):
    """정면 몸: 둥근 몸 아래에 짧은 두 발이 한 덩어리로, 가운데 짧은 선으로만 나뉨"""
    layer(cv, [fluff((256 + 70 + tail_wave, 440), 20, 18, 0, n=8, amp=0.09)], FUR)              # 뒤로 살짝 보이는 꼬리
    shapes = [fluff((256, 396), 84, 64, 0, n=18, amp=0.04),
              nub((226, 420), (224, FOOT_Y - lift_l), 30, 24), nub((286, 420), (288, FOOT_Y - lift_r), 30, 24)]
    if sit:
        shapes += [fluff((182, 444), 30, 24, 0, n=8, amp=0.06), fluff((330, 444), 30, 24, 0, n=8, amp=0.06)]   # 뒷발이 옆으로 살짝
    layer(cv, shapes, FUR)
    patch(cv, [fluff((256, 384), 50, 46, 0, n=12, amp=0.06)], CREAM)
    cv.line([(256, 424), (256, FOOT_Y - 6)], w=W_LINE * 0.5)                                    # 두 발 사이
    for f in ((224, FOOT_Y - lift_l), (288, FOOT_Y - lift_r)):
        patch(cv, [oval((f[0], f[1] + 2), 22, 13)], CREAM)
        cv.line([(f[0] - 6, f[1] + 2), (f[0] - 6, f[1] + 12)], w=W_LINE * 0.35)
        cv.line([(f[0] + 6, f[1] + 2), (f[0] + 6, f[1] + 12)], w=W_LINE * 0.35)
    if sit:
        for f in ((182, 452), (330, 452)):
            patch(cv, [oval(f, 18, 10)], CREAM)


def draw_front_sit(cv, eye='open', mouth='closed', tilt=0.0, tongue=0.0):
    front_body(cv, sit=True)
    front_head(cv, (256, 236), tilt, eye, mouth, tongue)


def draw_front_walk(cv, ph, carry=False):
    sw = math.sin(ph * 2 * math.pi)
    lift_l, lift_r = max(0, sw) * 10, max(0, -sw) * 10
    front_body(cv, lift_l, lift_r, tail_wave=8 * sw, sit=False)
    front_head(cv, (256, 240 + 4 * abs(sw)), tilt=3 * sw, mouth='closed' if carry else 'pant', tongue=0 if carry else 1, ear_swing=6 * sw, carry=carry)


def draw_back(cv, ph, sit=False, carry=False):
    sw = math.sin(ph * 2 * math.pi)
    lift_l, lift_r = (0, 0) if sit else (max(0, -sw) * 10, max(0, sw) * 10)
    shapes = [fluff((256, 396), 88, 66, 0, n=18, amp=0.04),
              nub((226, 420), (224, FOOT_Y - lift_l), 30, 24), nub((286, 420), (288, FOOT_Y - lift_r), 30, 24)]
    layer(cv, shapes, FUR)
    for f in ((224, FOOT_Y - lift_l), (288, FOOT_Y - lift_r)):
        patch(cv, [oval((f[0], f[1] + 4), 20, 10)], CREAM)
    cv.line([(256, 428), (256, FOOT_Y - 6)], w=W_LINE * 0.5)
    hc = (256, 250)
    if carry:                                                                                     # 문 막대 양끝이 머리 양옆으로 보임
        mouth_stick(cv, (256 - 140, 296), (256 + 140, 290))
    layer(cv, [fluff(hc, 108, 94, 0, n=22, amp=0.035)], FUR)
    for sx in (-1, 1):
        layer(cv, [oval((hc[0] + sx * 88, hc[1] - 22), 28, 46, -sx * (24 + 6 * sw))], FUR_D)
    curl_marks(cv, (256, 236), 70, 50, n=6, seed=8)
    layer(cv, tail_curve((262, 392), 14 + 12 * sw, back=0.6), FUR)                                    # 꼬리 (엉덩이 위로 서서 흔듦)


def frames():
    f = {}
    def mk(name, fn):
        cv = Canvas()
        fn(cv)
        f[name] = cv
    still = legs_pose(0.0, stride=0, lift=0)
    for i in range(2):
        mk(f'dog_stand{i}', lambda cv, i=i: draw_stand(cv, still, tail=(104, 300, 22 * (i * 2 - 1))))
    for i in range(6):
        ph = i / 6
        mk(f'dog_walk{i}', lambda cv, ph=ph: draw_stand(cv, legs_pose(ph), bob=-3 * abs(math.sin(ph * 2 * math.pi)),
                                                        tail=(104, 300, 16 * math.sin(ph * 2 * math.pi)),
                                                        ear_swing=5 * math.sin(ph * 2 * math.pi)))
    for i in range(4):
        ph = i / 4
        mk(f'dog_run{i}', lambda cv, ph=ph: draw_stand(cv, legs_pose(ph, stride=30, lift=20),
                                                       body=(232, 344, 122, 70, -3 + 5 * math.sin(ph * 2 * math.pi)),
                                                       bob=-10 * abs(math.sin(ph * 2 * math.pi)), head=(378, 228), mouth='pant', tongue=2,
                                                       tail=(104, 290, 0), ear_swing=-24))
    mk('dog_sit0', lambda cv: draw_sit(cv, tail_wave=0))
    mk('dog_sit1', lambda cv: draw_sit(cv, tail_wave=16))
    mk('dog_blink', lambda cv: draw_sit(cv, eye='closed', tail_wave=8))
    mk('dog_pant0', lambda cv: draw_sit(cv, mouth='pant', eye='happy', tongue=0))
    mk('dog_pant1', lambda cv: draw_sit(cv, mouth='pant', eye='happy', tongue=5))
    mk('dog_howl', lambda cv: draw_sit(cv, head=(318, 190), hang=-40, mouth='howl', eye='closed', ear_swing=-20))
    mk('dog_paw', lambda cv: draw_sit(cv, mouth='pant', eye='happy', paw=True))
    mk('dog_bark', lambda cv: draw_stand(cv, still, mouth='open', tail=(104, 300, 20), ear_swing=-8))
    mk('dog_sniff0', lambda cv: draw_stand(cv, legs_pose(0.1, stride=6, lift=3), head=(382, 320), hang=34, tail=(104, 300, -10)))
    mk('dog_sniff1', lambda cv: draw_stand(cv, legs_pose(0.6, stride=6, lift=3), head=(384, 324), hang=38, tail=(104, 300, 10)))
    mk('dog_lie0', lambda cv: draw_lie(cv))
    mk('dog_lie1', lambda cv: draw_lie(cv, eye='closed', breath=3, head_down=True))
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
    mk('dog_fsit0', lambda cv: draw_front_sit(cv))
    mk('dog_fsit1', lambda cv: draw_front_sit(cv, mouth='pant', tongue=2))
    mk('dog_fblink', lambda cv: draw_front_sit(cv, eye='closed'))
    mk('dog_ftilt', lambda cv: draw_front_sit(cv, tilt=-16))
    mk('dog_fhappy', lambda cv: draw_front_sit(cv, eye='happy', mouth='pant', tongue=5))
    for i in range(4):
        mk(f'dog_fwalk{i}', lambda cv, ph=i / 4: draw_front_walk(cv, ph))
        mk(f'dog_bwalk{i}', lambda cv, ph=i / 4: draw_back(cv, ph))
    mk('dog_bsit', lambda cv: draw_back(cv, 0, sit=True))
    # 막대를 물고 다닐 때 (그림에 막대를 함께 그림 — 따로 띄운 막대가 입 위에 겹쳐 보이지 않게)
    for i in range(6):
        ph = i / 6
        mk(f'dog_cwalk{i}', lambda cv, ph=ph: draw_stand(cv, legs_pose(ph), bob=-3 * abs(math.sin(ph * 2 * math.pi)),
                                                         tail=(104, 300, 16 * math.sin(ph * 2 * math.pi)),
                                                         ear_swing=5 * math.sin(ph * 2 * math.pi), carry=True))
    for i in range(4):
        ph = i / 4
        mk(f'dog_crun{i}', lambda cv, ph=ph: draw_stand(cv, legs_pose(ph, stride=30, lift=20),
                                                        body=(232, 344, 122, 70, -3 + 5 * math.sin(ph * 2 * math.pi)),
                                                        bob=-10 * abs(math.sin(ph * 2 * math.pi)), head=(378, 228),
                                                        tail=(104, 290, 0), ear_swing=-24, carry=True))
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
    cols = 6
    rows = (len(names) + cols - 1) // cols
    sheet = Image.new('RGB', (cols * 256, rows * 280), (200, 200, 200))
    d = ImageDraw.Draw(sheet)
    for i, n in enumerate(names):
        im = Image.open(os.path.join(o, n)).convert('RGBA').resize((256, 256))
        bg = Image.new('RGBA', im.size, (196, 214, 170, 255))
        bg.alpha_composite(im)
        sheet.paste(bg.convert('RGB'), ((i % cols) * 256, (i // cols) * 280))
        d.text(((i % cols) * 256 + 6, (i // cols) * 280 + 258), n, fill=(0, 0, 0))
    sheet.save(os.path.join(o, 'dogsheet.jpg'), quality=85)
