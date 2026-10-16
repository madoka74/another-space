"""어나더 스페이스 아이콘 — 블랭키씨 웍스 b 마크(기둥 + 원) 안에서 표현.
b의 둥근 몸통이 '다른 세계로 열린 창'이 됨: 테두리만 남은 원 안으로 해질녘 하늘과 겹겹의 산이 보이고,
오른쪽 위 빈 공간에 그 세계의 초승달이 떠 있음.
비전프로 겹 아이콘: 뒤(바탕 + 원 안의 세계) / 가운데(b 마크) / 앞(초승달)
사용: python3 tools/icon.py   → ios/AnotherSpace/Assets.xcassets/AppIcon.solidimagestack 에 저장 (+ tools/icon_preview.png)"""
import os
import cairosvg
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BG = '#1e1f21'; MK = '#f2f2f2'
SIZE = 1024


def mark(sc, tx, ty):
    S = lambda x, y: f"{tx+x*sc:.1f},{ty+y*sc:.1f}"
    stem = f"M{S(0,0)} C{S(300,0)} {S(533,250)} {S(533,530)} L{S(533,2000)} C{S(220,2000)} {S(0,1780)} {S(0,1480)} Z"
    cx, cy, r = tx+888*sc, ty+1290*sc, 712*sc
    return stem, (cx, cy, r)


def circle(cx, cy, r):
    return f"M{cx-r:.1f},{cy:.1f} a{r:.1f},{r:.1f} 0 1,0 {2*r:.1f},0 a{r:.1f},{r:.1f} 0 1,0 {-2*r:.1f},0 Z"


def geom():
    sc = .27
    w, h = 1600*sc, 2000*sc
    tx = (SIZE-w)/2 + 6; ty = (SIZE-h)/2 + 8
    stem, (cx, cy, r) = mark(sc, tx, ty)
    return stem, cx, cy, r, ty


def world(cx, cy, r):
    """원 안의 세계: 해질녘 하늘 그라데이션 + 겹겹의 산 능선 + 아래 숲"""
    def ridge(y0, amp, seed, col):
        import math
        pts = []
        x0, x1 = cx - r - 10, cx + r + 10
        n = 40
        for i in range(n + 1):
            x = x0 + (x1 - x0) * i / n
            y = y0 - amp * (0.55 * math.sin(i * 0.37 + seed) + 0.3 * math.sin(i * 0.91 + seed * 2) + 0.15 * math.sin(i * 2.3 + seed * 3))
            pts.append(f"{x:.1f},{y:.1f}")
        return f'<path d="M{x0:.1f},{cy + r + 10:.1f} L' + ' L'.join(pts) + f' L{x1:.1f},{cy + r + 10:.1f} Z" fill="{col}"/>'
    sky = (f'<linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">'
           f'<stop offset="0" stop-color="#2b2f63"/><stop offset=".55" stop-color="#8f5f86"/>'
           f'<stop offset=".8" stop-color="#f19a6a"/><stop offset="1" stop-color="#ffcf8a"/></linearGradient>')
    body = (f'<rect x="{cx-r:.1f}" y="{cy-r:.1f}" width="{2*r:.1f}" height="{2*r:.1f}" fill="url(#sky)"/>'
            + ridge(cy + r * .18, r * .16, 1.3, '#5b4a78')
            + ridge(cy + r * .38, r * .14, 4.1, '#3b3557')
            + ridge(cy + r * .58, r * .10, 2.2, '#232339'))
    return sky, body


def layers():
    stem, cx, cy, r, ty = geom()
    ring = r * 0.17                     # 원 테두리 두께 (창틀)
    inner = r - ring
    head = f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {SIZE} {SIZE}" width="{SIZE}" height="{SIZE}">'
    sky, body = world(cx, cy, inner + 2)
    back = (f'{head}<defs>{sky}<clipPath id="win"><path d="{circle(cx, cy, inner + 2)}"/></clipPath></defs>'
            f'<rect width="{SIZE}" height="{SIZE}" fill="{BG}"/><g clip-path="url(#win)">{body}</g></svg>')
    # b 마크(기둥 XOR 원)에서 창(안쪽 원)만 비움 → 창 안에서는 기둥도 비어 세계가 그대로 보임
    middle = (f'{head}<defs><clipPath id="hole"><path d="M0,0 H{SIZE} V{SIZE} H0 Z {circle(cx, cy, inner)}" clip-rule="evenodd"/></clipPath></defs>'
              f'<g clip-path="url(#hole)"><path d="{stem} {circle(cx, cy, r)}" fill="{MK}" fill-rule="evenodd"/></g></svg>')
    # 초승달 (오른쪽 위 빈 공간)
    mx, my, mr = cx + r * .62, ty + 92, r * .30
    # 초승달: 큰 원에서 비켜 놓은 원을 뺀 모양 (두 원의 교점을 잇는 두 호)
    import math
    bx, by, br = mx + mr * .45, my - mr * .25, mr * .88
    d = math.hypot(bx - mx, by - my)
    a = (mr * mr - br * br + d * d) / (2 * d)
    hh = math.sqrt(max(0.0, mr * mr - a * a))
    ux, uy = (bx - mx) / d, (by - my) / d
    px, py = mx + a * ux, my + a * uy
    p1 = (px - hh * uy, py + hh * ux); p2 = (px + hh * uy, py - hh * ux)
    moon = (f'M{p1[0]:.1f},{p1[1]:.1f} A{mr:.1f},{mr:.1f} 0 1,1 {p2[0]:.1f},{p2[1]:.1f} '
            f'A{br:.1f},{br:.1f} 0 0,0 {p1[0]:.1f},{p1[1]:.1f} Z')
    front = (f'{head}<defs><radialGradient id="glow"><stop offset="0" stop-color="#ffe7b0" stop-opacity=".45"/>'
             f'<stop offset="1" stop-color="#ffe7b0" stop-opacity="0"/></radialGradient></defs>'
             f'<circle cx="{mx:.1f}" cy="{my:.1f}" r="{mr*1.9:.1f}" fill="url(#glow)"/>'
             f'<path d="{moon}" fill="#ffe2a0"/></svg>')
    return back, middle, front


if __name__ == '__main__':
    base = os.path.join(ROOT, 'ios', 'AnotherSpace', 'Assets.xcassets', 'AppIcon.solidimagestack')
    pngs = []
    for name, svg in zip(['Back', 'Middle', 'Front'], layers()):
        d = os.path.join(base, f'{name}.solidimagestacklayer', 'Content.imageset')
        os.makedirs(d, exist_ok=True)
        out = os.path.join(d, f'{name.lower()}.png')
        cairosvg.svg2png(bytestring=svg.encode(), write_to=out, output_width=SIZE, output_height=SIZE)
        if name == 'Back':                       # 뒤 층은 불투명해야 함
            Image.open(out).convert('RGB').save(out)
        pngs.append(out)
        open(os.path.join(d, 'Contents.json'), 'w').write(
            '{\n  "images" : [ { "filename" : "%s.png", "idiom" : "vision", "scale" : "2x" } ],\n  "info" : { "author" : "xcode", "version" : 1 }\n}\n' % name.lower())
        open(os.path.join(base, f'{name}.solidimagestacklayer', 'Contents.json'), 'w').write(
            '{\n  "info" : { "author" : "xcode", "version" : 1 }\n}\n')
    open(os.path.join(base, 'Contents.json'), 'w').write(
        '{\n  "info" : { "author" : "xcode", "version" : 1 },\n  "layers" : [\n    { "filename" : "Front.solidimagestacklayer" },\n'
        '    { "filename" : "Middle.solidimagestacklayer" },\n    { "filename" : "Back.solidimagestacklayer" }\n  ]\n}\n')
    open(os.path.join(ROOT, 'ios', 'AnotherSpace', 'Assets.xcassets', 'Contents.json'), 'w').write(
        '{\n  "info" : { "author" : "xcode", "version" : 1 }\n}\n')
    im = Image.open(pngs[0]).convert('RGBA')
    for p in pngs[1:]:
        im.alpha_composite(Image.open(p).convert('RGBA'))
    im.save(os.path.join(ROOT, 'tools', 'icon_preview.png'))
    print('ok')
