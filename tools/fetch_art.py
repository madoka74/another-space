"""전시관에 걸 명화 받기 — 빌드(GitHub Actions)할 때 make_assets.py 가 부름.
tools/art_list.json (저작권이 끝난 유명 화가 21명 × 약 5점, 포켓 갤러리 작품 목록에서 고름)의 위키미디어 그림을 받아
긴 변 1024px JPG로 줄여 ios/AnotherSpace/Resources/art/p_<번호>.jpg 로 저장. 받지 못한 그림은 건너뜀(빌드는 계속)."""
import io, json, os, time, urllib.request
from concurrent.futures import ThreadPoolExecutor
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'ios', 'AnotherSpace', 'Resources', 'art')
UA = 'AnotherSpace-build/1.0 (https://github.com/madoka74/another-space; build script)'


def one(i, w):
    dst = os.path.join(OUT, f'p_{i:03d}.jpg')
    if os.path.exists(dst) and os.path.getsize(dst) > 10_000:
        return True
    for attempt in range(3):
        try:
            req = urllib.request.Request(w['img'], headers={'User-Agent': UA})
            with urllib.request.urlopen(req, timeout=40) as r:
                data = r.read()
            im = Image.open(io.BytesIO(data)).convert('RGB')
            ar = im.width / im.height
            if ar < 0.5 or ar > 2.0:            # 기둥처럼 길쭉한 그림은 벽에 걸기 어색해서 뺌
                return False
            im.thumbnail((1024, 1024), Image.LANCZOS)
            im.save(dst, 'JPEG', quality=85, optimize=True)
            return True
        except Exception as e:
            if attempt == 2:
                print('  못 받음:', w.get('a'), '-', w.get('t'), '|', e, flush=True)
            time.sleep(2 + attempt * 3)
    return False


def main():
    os.makedirs(OUT, exist_ok=True)
    lst = json.load(open(os.path.join(ROOT, 'tools', 'art_list.json'), encoding='utf-8'))
    with ThreadPoolExecutor(4) as ex:
        ok = list(ex.map(lambda p: one(*p), enumerate(lst)))
    print(f'명화 {sum(ok)}/{len(lst)}점 받음', flush=True)
    # 앱이 그림 파일 → 작품 정보(포켓 갤러리 작품 id·제목·작가·주소)를 알 수 있게 — 도슨트 해설을 받을 때 씀
    index = []
    for i, w in enumerate(lst):
        if os.path.exists(os.path.join(OUT, f'p_{i:03d}.jpg')):
            index.append({'file': f'p_{i:03d}', 'id': w['id'], 'a': w.get('a', ''), 't': w.get('t', ''), 'img': w.get('img', '')})
    with open(os.path.join(OUT, 'index.json'), 'w', encoding='utf-8') as f:
        json.dump(index, f, ensure_ascii=False)


if __name__ == '__main__':
    main()
