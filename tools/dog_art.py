"""시골 테마의 강아지 '설이' 그림 (시베리안 허스키 느낌, 선 그림 카툰). 고양이 방울이와 같은 선 굵기·그리는 방식(cat_art.py)을 쓰되
모습은 확연히 다르게: 길쭉한 주둥이의 옆얼굴, 쫑긋 선 세모 귀, 회색 등·흰 얼굴 가면과 배, 파란 눈, 등 위로 말려 올라간 풍성한 꼬리, 파란 목줄과 은색 이름표.
몸은 옆모습(오른쪽을 봄), 정면·뒷모습도 있음. 512×512, 바닥 줄 y=470"""
import math
import os
from PIL import Image, ImageDraw

import cat_art as C
from cat_art import ellipse, capsule, blob, curve, tail_pts, Canvas, INK, PAPER, W_LINE, S, GROUND

DARK = (104, 110, 122)
MID = (150, 156, 166)
EYE = (84, 152, 214)
BLUE = (48, 96, 186)
SILVER = (206, 210, 218)
PINK = (222, 128, 140)
DIRT = (120, 92, 64)


def layer(cv, shapes, fill):
    """검게 부풀려 그린 뒤 색으로 채움 (cat_art.Canvas.layer 와 같지만 채움 색을 고름)"""
    for sh in shapes:
        p = cv._p(sh(W_LINE))
        cv.d.polygon(p, fill=INK)
        cv.da.polygon(p, fill=255)
    for sh in shapes:
        cv.d.polygon(cv._p(sh(0)), fill=fill)


def patch(cv, shapes, fill):
    """윤곽선 없이 안쪽에만 칠하는 무늬 (흰 가슴·배)"""
    for sh in shapes:
        cv.d.polygon(cv._p(sh(0)), fill=fill)


def tri(p0, p1, p2):
    def poly(g):
        cx = (p0[0] + p1[0] + p2[0]) / 3
        cy = (p0[1] + p1[1] + p2[1]) / 3
        out = []
        for p in (p0, p1, p2):
            dx, dy = p[0] - cx, p[1] - cy
            d = math.hypot(dx, dy) or 1
            k = (d + g * 1.5) / d
            out.append((cx + dx * k, cy + dy * k))
        return out
    return poly


def side_head(cv, hc, ang=0.0, mouth='closed', eye='open', ear_back=False, tongue=0.0):
    """옆얼굴: 머리뼈 + 긴 주둥이(흰색) + 코 + 세모 귀 + 파란 눈. ang: 고개 들기(-) / 숙이기(+) (도)"""
    a = math.radians(ang)
    def P(dx, dy):
        return (hc[0] + dx * math.cos(a) - dy * math.sin(a), hc[1] + dx * math.sin(a) + dy * math.cos(a))
    # 먼 귀 (뒤)
    e_lean = 18 if ear_back else 0
    layer(cv, [tri(P(-30, -26), P(-8, -34), P(-34 - e_lean, -82 + e_lean * 0.6))], DARK)
    shapes = [ellipse(hc, 50, 44, ang), capsule(P(18, 14), P(78, 26), 24, 17)]
    if mouth in ('open', 'howl', 'pant'):
        shapes.append(capsule(P(16, 30), P(66, 50 if mouth != 'pant' else 40), 14, 10))      # 아래턱
    layer(cv, shapes, DARK)
    # 흰 얼굴 가면: 주둥이·볼·눈썹 점
    patch(cv, [capsule(P(18, 14), P(78, 26), 22, 15), ellipse(P(8, 20), 34, 20, ang)], PAPER)
    if mouth in ('open', 'howl', 'pant'):
        patch(cv, [capsule(P(16, 30), P(66, 50 if mouth != 'pant' else 40), 12, 8)], PAPER)
        cv.d.polygon(cv._p([P(22, 26), P(76, 30), P(64, 46 if mouth != 'pant' else 38), P(20, 34)]), fill=(150, 50, 60))
        if mouth == 'pant' or tongue > 0:
            tg = ellipse(P(52, 52 + tongue), 12, 18, ang + 10)
            cv.d.polygon(cv._p(tg(W_LINE * 0.6)), fill=INK)
            cv.d.polygon(cv._p(tg(0)), fill=PINK)
    else:
        cv.line([P(30, 32), P(56, 34), P(74, 32)], w=W_LINE * 0.5)                         # 입 선
    patch(cv, [ellipse(P(14, -18), 9, 6, ang)], PAPER)                                      # 눈썹 흰 점
    # 코
    n = ellipse(P(82, 18), 11, 9, ang)
    cv.d.polygon(cv._p(n(0)), fill=INK)
    # 눈
    ec = P(18, -4)
    if eye == 'open':
        cv.d.ellipse([(ec[0] - 9) * S, (ec[1] - 6) * S, (ec[0] + 9) * S, (ec[1] + 6) * S], fill=INK)
        cv.dot(ec, 5.5, EYE)
        cv.dot(ec, 2.5, INK)
        cv.dot((ec[0] + 2, ec[1] - 2.5), 1.6, PAPER)
    elif eye == 'closed':
        cv.line([P(9, -2), P(18, 3), P(27, -2)], w=W_LINE * 0.6)
    elif eye == 'happy':
        cv.line([P(9, 1), P(18, -6), P(27, 1)], w=W_LINE * 0.6)
    # 가까운 귀
    layer(cv, [tri(P(-14, -30), P(12, -36), P(-8 - e_lean, -88 + e_lean * 0.6))], DARK)
    patch(cv, [tri(P(-8, -36), P(6, -38), P(-6 - e_lean, -74 + e_lean * 0.6))], (228, 200, 204))


def collar_side(cv, a, b):
    pts = [a, ((a[0] + b[0]) / 2 + 4, (a[1] + b[1]) / 2 + 6), b]
    cv.line(pts, w=W_LINE * 2.4, col=INK)
    cv.line(pts, w=W_LINE * 1.2, col=BLUE)
    m = ((a[0] + b[0]) / 2 + 4, (a[1] + b[1]) / 2 + 14)
    cv.ring(m, 7, SILVER, w=W_LINE * 0.6)


def husky_tail(cv, base, ang, curl, wave=0.0, length=170):
    tp = tail_pts(base, ang, length, curl, wave)
    rs = [26 - 10 * k / len(tp) for k in range(len(tp))]
    layer(cv, blob(tp, rs), DARK)
    patch(cv, blob(tp[-4:], [r * 0.7 for r in rs[-4:]]), PAPER)               # 흰 꼬리 끝
    for i in range(3, len(tp) - 4, 3):                                            # 털 결
        (x0, y0), (x1, y1) = tp[i - 1], tp[i + 1]
        L = math.hypot(x1 - x0, y1 - y0) or 1
        nx, ny = -(y1 - y0) / L, (x1 - x0) / L
        c = tp[i]
        cv.line([(c[0] + nx * 6, c[1] + ny * 6), (c[0] + nx * 14 + (x1 - x0) * 0.3, c[1] + ny * 14 + (y1 - y0) * 0.3)], w=W_LINE * 0.4)
    return tp


def legs_pose(ph, stride=36, lift=18, run=False):
    def foot(px, p):
        s = math.sin(p * 2 * math.pi)
        c = math.cos(p * 2 * math.pi)
        return (px + s * stride, GROUND - 10 - max(0, c) * lift)
    hip, sh = (150, 340), (318, 340)
    if run:
        hip, sh = (140, 330), (326, 326)
    return [((hip[0] - 22, hip[1] - 4), foot(hip[0] - 30, ph + 0.5)),
            ((sh[0] - 18, sh[1] - 4), foot(sh[0] - 10, ph + 0.75)),
            (hip, foot(hip[0] - 8, ph)),
            (sh, foot(sh[0] + 8, ph + 0.25))]


def draw_stand(cv, legs, body=(228, 316, 132, 58, -2), head=(394, 222), hang=0.0, mouth='closed', eye='open',
               tail=(106, 296, -120, 130, 0.0), ear_back=False, tongue=0.0, sniff=False):
    # 먼 다리
    for (a, b) in legs[:2]:
        layer(cv, [capsule(a, b, 18, 13), ellipse(b, 18, 10)], MID)
    # 몸통 + 목
    hx, hy = head
    layer(cv, [ellipse(body[:2], body[2], body[3], body[4]), capsule((body[0] + body[2] * 0.72, body[1] - 18), (hx - 22, hy + 16), 44, 36)], DARK)
    patch(cv, [ellipse((body[0] + 8, body[1] + 32), body[2] * 0.78, body[3] * 0.42, body[4]),
               ellipse((body[0] + body[2] * 0.82, body[1] + 6), 30, 40)], PAPER)         # 흰 배·가슴
    # 가까운 다리 (허벅지는 회색, 아래는 흰색)
    (h0, h1), (f0, f1) = legs[2], legs[3]
    layer(cv, [ellipse((h0[0], h0[1] + 6), 44, 52, 8)], DARK)
    layer(cv, [capsule((h0[0] + 4, h0[1] + 30), h1, 18, 13), ellipse(h1, 19, 10), capsule(f0, f1, 19, 13), ellipse(f1, 19, 10)], PAPER)
    # 꼬리 (등 위로 말림)
    husky_tail(cv, (tail[0], tail[1]), tail[2], tail[3], tail[4])
    collar_side(cv, (hx - 50, hy + 24), (hx - 18, hy + 52))
    side_head(cv, head, hang, mouth, eye, ear_back, tongue)
    for b in (h1, f1):
        for dx in (-6, 4):
            cv.line([(b[0] + dx, b[1] - 6), (b[0] + dx, b[1] + 3)], w=W_LINE * 0.4)


def draw_sit(cv, head=(338, 186), hang=-6, mouth='closed', eye='open', tail_wave=0.0, paw=False, tongue=0.0, ear_back=False):
    # 꼬리는 바닥에 둥글게
    husky_tail(cv, (190, 450), 172, -80 - tail_wave, tail_wave * 0.3, length=115)
    layer(cv, [capsule((292, 330), (296, 460), 17, 13), ellipse((300, 462), 18, 10)], MID)          # 먼 앞다리
    hx, hy = head
    layer(cv, [ellipse((246, 352), 74, 110, -18), ellipse((200, 420), 66, 50), capsule((280, 290), (hx - 16, hy + 22), 46, 40)], DARK)
    patch(cv, [ellipse((292, 330), 34, 70, -10), ellipse((214, 446), 40, 18)], PAPER)
    layer(cv, [ellipse((236, 462), 28, 11)], PAPER)                                                  # 뒷발
    if paw:
        layer(cv, [capsule((312, 340), (372, 352), 18, 14), ellipse((378, 352), 16, 13)], PAPER)
    else:
        layer(cv, [capsule((314, 336), (322, 460), 18, 13), ellipse((326, 462), 19, 10)], PAPER)
    collar_side(cv, (hx - 50, hy + 26), (hx - 16, hy + 54))
    side_head(cv, head, hang, mouth, eye, ear_back, tongue)


def draw_lie(cv, eye='open', breath=0.0, head_down=False):
    husky_tail(cv, (136, 432), 168, -50, length=105)
    layer(cv, [capsule((300, 446), (430, 458), 17, 13), ellipse((436, 458), 18, 10)], MID)
    layer(cv, [ellipse((244, 418), 132, 50 + breath, 0), ellipse((160, 420), 50, 44)], DARK)
    patch(cv, [ellipse((256, 444), 100, 18)], PAPER)
    layer(cv, [capsule((320, 440), (450, 456), 18, 13), ellipse((456, 458), 19, 10)], PAPER)
    hc = (402, 392) if not head_down else (412, 424)
    collar_side(cv, (hc[0] - 52, hc[1] + 20), (hc[0] - 22, hc[1] + 46))
    side_head(cv, hc, 12 if head_down else 0, 'closed', eye)


def draw_sleep(cv, breath=0.0):
    layer(cv, [ellipse((244, 424), 128, 48 + breath, 0)], DARK)
    patch(cv, [ellipse((250, 448), 96, 16)], PAPER)
    side_head(cv, (370, 420), 18, 'closed', 'closed')
    husky_tail(cv, (126, 440), 30, -95, length=230)                                                 # 꼬리로 코를 덮음


def draw_playbow(cv, k):
    legs = [((150, 300), (140, 462)), ((300, 410), (380, 462)), ((170, 306), (160, 462)), ((318, 414), (410, 462))]
    draw_stand(cv, legs, body=(232, 340, 128, 56, 22), head=(400, 372), hang=-8, mouth='pant', tongue=4 * k,
               tail=(110, 262, -110 + 20 * k, 130, 20 * k))


def draw_jump(cv, k):
    """신나서 뒷발로 서서 앞발을 듦"""
    husky_tail(cv, (196, 420), -150, 100, 20 * k)
    layer(cv, [capsule((262, 330), (330, 260 - 10 * k), 17, 13), ellipse((336, 256 - 10 * k), 16, 12)], MID)
    layer(cv, [ellipse((236, 330), 70, 120, 18), ellipse((214, 420), 52, 46), capsule((262, 240), (300, 172), 42, 36)], DARK)
    patch(cv, [ellipse((262, 300), 32, 80, 18)], PAPER)
    layer(cv, [capsule((214, 430), (200, 462), 17, 13), ellipse((206, 464), 22, 10), capsule((270, 300), (346, 236 + 10 * k), 18, 13), ellipse((352, 232 + 10 * k), 16, 12)], PAPER)
    collar_side(cv, (262, 196), (296, 222))
    side_head(cv, (316, 150), -18, 'pant', 'happy', tongue=3)


def draw_roll(cv, k):
    wig = (k * 2 - 1) * 10
    husky_tail(cv, (124, 434), 190, 60 - k * 40, length=120)
    legs = [((180, 400), (160 + wig, 320)), ((236, 396), (230 - wig, 310)), ((290, 398), (302 + wig, 316)), ((206, 400), (196 - wig, 334))]
    layer(cv, [ellipse((236, 424), 124, 50, 0)], DARK)
    patch(cv, [ellipse((236, 404), 100, 26)], PAPER)
    layer(cv, sum([[capsule(a, b, 17, 13), ellipse(b, 16, 12)] for a, b in legs], []), PAPER)
    side_head(cv, (384, 430), 160, 'pant', 'happy', tongue=2)


def draw_dig(cv, k):
    legs = [((150, 330), (140, 462)), ((300, 380), (380 - 30 * k, 450)), ((170, 336), (160, 462)), ((318, 384), (360 + 30 * k, 440 + 10 * k))]
    draw_stand(cv, legs, body=(232, 330, 128, 56, 14), head=(392, 360), hang=24, tail=(110, 280, -110, 130, 25 * (k * 2 - 1)))
    for i in range(6):                                                                               # 튀는 흙
        x = 330 - i * 14 - 20 * k
        y = 430 - (i % 3) * 18 - 12 * k
        cv.dot((x, y), 5 - (i % 2), DIRT)


def draw_front_sit(cv, eye='open', mouth='closed', tilt=0.0, tongue=0.0):
    hc = (256, 190)
    a = math.radians(tilt)
    def P(dx, dy):
        return (hc[0] + dx * math.cos(a) - dy * math.sin(a), hc[1] + dx * math.sin(a) + dy * math.cos(a))
    husky_tail(cv, (340, 446), 180, 70, length=150)
    layer(cv, [ellipse((196, 432), 50, 36), ellipse((316, 432), 50, 36)], DARK)
    layer(cv, [ellipse((256, 360), 86, 104)], DARK)
    patch(cv, [ellipse((256, 350), 58, 88)], PAPER)
    layer(cv, [capsule((232, 330), (228, 458), 18, 14), ellipse((226, 462), 20, 10), capsule((280, 330), (284, 458), 18, 14), ellipse((286, 462), 20, 10)], PAPER)
    # 귀
    for sx in (-1, 1):
        layer(cv, [tri(P(sx * 26, -40), P(sx * 62, -30), P(sx * 52, -100))], DARK)
        patch(cv, [tri(P(sx * 32, -44), P(sx * 54, -36), P(sx * 48, -86))], (228, 200, 204))
    layer(cv, [ellipse(hc, 72, 62, tilt)], DARK)
    # 흰 얼굴 가면 (이마 가운데 회색 줄은 남김)
    patch(cv, [ellipse(P(0, 18), 62, 44, tilt), ellipse(P(-24, -18), 12, 8, tilt), ellipse(P(24, -18), 12, 8, tilt)], PAPER)
    cv.d.polygon(cv._p([P(-10, -60), P(10, -60), P(4, -6), P(-4, -6)]), fill=DARK)
    collar_y = 262
    cv.line([(200, collar_y - 6), (256, collar_y + 8), (312, collar_y - 6)], w=W_LINE * 2.4, col=INK)
    cv.line([(200, collar_y - 6), (256, collar_y + 8), (312, collar_y - 6)], w=W_LINE * 1.2, col=BLUE)
    cv.ring((256, collar_y + 18), 8, SILVER, w=W_LINE * 0.6)
    for sx in (-1, 1):
        ec = P(sx * 26, -4)
        if eye == 'open':
            cv.d.ellipse([(ec[0] - 11) * S, (ec[1] - 7) * S, (ec[0] + 11) * S, (ec[1] + 7) * S], fill=INK)
            cv.dot(ec, 6.5, EYE)
            cv.dot(ec, 3, INK)
            cv.dot((ec[0] + 2, ec[1] - 3), 1.8, PAPER)
        elif eye == 'closed':
            cv.line([P(sx * 26 - 10, -4), P(sx * 26, 2), P(sx * 26 + 10, -4)], w=W_LINE * 0.6)
        else:
            cv.line([P(sx * 26 - 10, 0), P(sx * 26, -7), P(sx * 26 + 10, 0)], w=W_LINE * 0.6)
    nz = ellipse(P(0, 20), 13, 9, tilt)
    cv.d.polygon(cv._p(nz(0)), fill=INK)
    if mouth == 'pant' or tongue > 0:
        cv.d.polygon(cv._p([P(-16, 32), P(16, 32), P(0, 44)]), fill=(150, 50, 60))
        tg = ellipse(P(0, 46 + tongue), 10, 15, tilt)
        cv.d.polygon(cv._p(tg(W_LINE * 0.5)), fill=INK)
        cv.d.polygon(cv._p(tg(0)), fill=PINK)
    else:
        cv.line([P(-16, 34), P(-6, 38), P(0, 30), P(6, 38), P(16, 34)], w=W_LINE * 0.5)


def draw_front_walk(cv, ph):
    sw = math.sin(ph * 2 * math.pi)
    hc = (256, 214 + 4 * abs(sw))
    husky_tail(cv, (276, 300), -60, 110, 20 * sw, length=130)
    lift_l, lift_r = max(0, sw) * 18, max(0, -sw) * 18
    layer(cv, [capsule((196, 360), (194, 454 - lift_r * 0.5), 16, 12), ellipse((192, 456 - lift_r * 0.5), 16, 9),
               capsule((316, 360), (318, 454 - lift_l * 0.5), 16, 12), ellipse((320, 456 - lift_l * 0.5), 16, 9)], MID)
    layer(cv, [ellipse((256, 340), 84, 70)], DARK)
    patch(cv, [ellipse((256, 350), 50, 56)], PAPER)
    layer(cv, [capsule((230, 360), (226, 458 - lift_l), 18, 13), ellipse((224, 462 - lift_l), 20, 10),
               capsule((284, 360), (288, 458 - lift_r), 18, 13), ellipse((290, 462 - lift_r), 20, 10)], PAPER)
    def P(dx, dy):
        return (hc[0] + dx, hc[1] + dy)
    for sx in (-1, 1):
        layer(cv, [tri(P(sx * 26, -40), P(sx * 62, -30), P(sx * 52, -100))], DARK)
        patch(cv, [tri(P(sx * 32, -44), P(sx * 54, -36), P(sx * 48, -86))], (228, 200, 204))
    layer(cv, [ellipse(hc, 70, 60)], DARK)
    patch(cv, [ellipse(P(0, 18), 60, 42), ellipse(P(-24, -18), 12, 8), ellipse(P(24, -18), 12, 8)], PAPER)
    cv.d.polygon(cv._p([P(-10, -58), P(10, -58), P(4, -6), P(-4, -6)]), fill=DARK)
    for sx in (-1, 1):
        ec = P(sx * 26, -4)
        cv.d.ellipse([(ec[0] - 11) * S, (ec[1] - 7) * S, (ec[0] + 11) * S, (ec[1] + 7) * S], fill=INK)
        cv.dot(ec, 6.5, EYE)
        cv.dot(ec, 3, INK)
        cv.dot((ec[0] + 2, ec[1] - 3), 1.8, PAPER)
    nz = ellipse(P(0, 20), 13, 9)
    cv.d.polygon(cv._p(nz(0)), fill=INK)
    cv.d.polygon(cv._p([P(-14, 32), P(14, 32), P(0, 42)]), fill=(150, 50, 60))
    tg = ellipse(P(0, 44), 9, 13)
    cv.d.polygon(cv._p(tg(W_LINE * 0.5)), fill=INK)
    cv.d.polygon(cv._p(tg(0)), fill=PINK)


def draw_back(cv, ph, sit=False):
    sw = math.sin(ph * 2 * math.pi)
    hc = (256, 214 if sit else 236)
    for sx in (-1, 1):
        layer(cv, [tri((hc[0] + sx * 26, hc[1] - 40), (hc[0] + sx * 62, hc[1] - 30), (hc[0] + sx * 52, hc[1] - 100))], DARK)
    layer(cv, [ellipse(hc, 70, 60)], DARK)
    if sit:
        layer(cv, [ellipse((256, 376), 92, 96), ellipse((256, 452), 100, 22), capsule((256, 300), (256, 262), 40, 36)], DARK)
        patch(cv, [ellipse((256, 450), 60, 14)], PAPER)
        husky_tail(cv, (300, 452), 0, -70, length=130)
    else:
        lift_l, lift_r = max(0, -sw) * 16, max(0, sw) * 16
        layer(cv, [capsule((224, 380), (220, 458 - lift_l), 20, 14), ellipse((218, 462 - lift_l), 20, 10),
                   capsule((288, 380), (292, 458 - lift_r), 20, 14), ellipse((294, 462 - lift_r), 20, 10)], PAPER)
        layer(cv, [ellipse((256, 344), 88, 70)], DARK)
        patch(cv, [ellipse((256, 392), 30, 24)], PAPER)
        husky_tail(cv, (262, 318), -70 + 10 * sw, 150, 20 * sw, length=110)


def frames():
    f = {}
    def mk(name, fn):
        cv = Canvas()
        fn(cv)
        f[name] = cv
    for i in range(2):
        mk(f'dog_stand{i}', lambda cv, i=i: draw_stand(cv, legs_pose(0.0, stride=0, lift=0), tail=(106, 296, -120, 130, 25 * (i * 2 - 1))))
    for i in range(6):
        ph = i / 6
        mk(f'dog_walk{i}', lambda cv, ph=ph: draw_stand(cv, legs_pose(ph), body=(228, 316 + 3 * math.sin(ph * 4 * math.pi), 132, 58, -2),
                                                        tail=(106, 296, -120, 130, 15 * math.sin(ph * 2 * math.pi))))
    for i in range(4):
        ph = i / 4
        mk(f'dog_run{i}', lambda cv, ph=ph: draw_stand(cv, legs_pose(ph, stride=62, lift=34, run=True),
                                                       body=(236, 304 + 8 * math.sin(ph * 2 * math.pi), 140, 54, -3 + 6 * math.sin(ph * 2 * math.pi)),
                                                       head=(404, 216), mouth='pant', tongue=2, tail=(108, 290, -150, 120, 0), ear_back=True))
    mk('dog_sit0', lambda cv: draw_sit(cv, tail_wave=0))
    mk('dog_sit1', lambda cv: draw_sit(cv, tail_wave=24))
    mk('dog_blink', lambda cv: draw_sit(cv, eye='closed', tail_wave=10))
    mk('dog_pant0', lambda cv: draw_sit(cv, mouth='pant', eye='happy', tongue=0))
    mk('dog_pant1', lambda cv: draw_sit(cv, mouth='pant', eye='happy', tongue=5))
    mk('dog_howl', lambda cv: draw_sit(cv, head=(320, 160), hang=-48, mouth='howl', eye='closed', ear_back=True))
    mk('dog_paw', lambda cv: draw_sit(cv, mouth='pant', eye='happy', paw=True))
    mk('dog_bark', lambda cv: draw_stand(cv, legs_pose(0.0, stride=0, lift=0), mouth='open', tail=(106, 296, -120, 130, 20)))
    mk('dog_sniff0', lambda cv: draw_stand(cv, legs_pose(0.1, stride=14, lift=6), head=(398, 330), hang=40, tail=(106, 296, -120, 130, -10)))
    mk('dog_sniff1', lambda cv: draw_stand(cv, legs_pose(0.6, stride=14, lift=6), head=(400, 334), hang=44, tail=(106, 296, -120, 130, 10)))
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
    mk('dog_ftilt', lambda cv: draw_front_sit(cv, tilt=-20))
    mk('dog_fhappy', lambda cv: draw_front_sit(cv, eye='happy', mouth='pant', tongue=5))
    for i in range(4):
        mk(f'dog_fwalk{i}', lambda cv, ph=i / 4: draw_front_walk(cv, ph))
        mk(f'dog_bwalk{i}', lambda cv, ph=i / 4: draw_back(cv, ph))
    mk('dog_bsit', lambda cv: draw_back(cv, 0, sit=True))
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
