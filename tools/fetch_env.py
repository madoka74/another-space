"""실사 하늘·바닥 재료 받기 — 빌드(GitHub Actions)할 때 make_assets.py 가 부름.
Poly Haven(https://polyhaven.com, 모든 자료 CC0 — 출처 표기 없이 자유롭게 사용 가능)의
- 하늘: 'Pure Skies'(땅을 지운 하늘만의 360° 사진) 톤매핑 JPG (가로 8K)
- 바닥·벽·바위·나무껍질: 이어 붙여도 이음새가 없는 사진 무늬 2K JPG
를 받아 캐시 폴더(ASSET_CACHE, 기본 ~/.cache/another-space)에 둠. 이미 있으면 다시 받지 않음(빌드 캐시로 재사용).
받지 못한 것은 건너뜀 — make_assets 가 그 자리는 직접 만든 그림을 씀."""
import os, time, urllib.request
from concurrent.futures import ThreadPoolExecutor

CACHE = os.environ.get('ASSET_CACHE', os.path.expanduser('~/.cache/another-space'))
UA = 'AnotherSpace-build/1.0 (https://github.com/madoka74/another-space; build script)'

# (시간, 하늘 상태) → Poly Haven 하늘
SKIES = {
    ('dawn', 'clear'): 'qwantani_dawn_puresky',
    ('dawn', 'cloudy'): 'kloofendal_misty_morning_puresky',
    ('dawn', 'overcast'): 'kloofendal_28d_misty_puresky',
    ('morning', 'clear'): 'qwantani_morning_puresky',
    ('morning', 'cloudy'): 'kloofendal_38d_partly_cloudy_puresky',
    ('morning', 'overcast'): 'kloofendal_overcast_puresky',
    ('afternoon', 'clear'): 'kloofendal_43d_clear_puresky',
    ('afternoon', 'cloudy'): 'kloofendal_48d_partly_cloudy_puresky',
    ('afternoon', 'overcast'): 'kloofendal_overcast_puresky',
    ('afternoon', 'storm'): 'overcast_soil_puresky',
    ('dusk', 'clear'): 'qwantani_sunset_puresky',
    ('dusk', 'cloudy'): 'belfast_sunset_puresky',
    ('dusk', 'overcast'): 'qwantani_dusk_2_puresky',
    ('night', 'clear'): 'qwantani_night_puresky',
}

# 먼 풍경 띠 (360° 사진에서 땅·산 부분만 오려 냄: 같은 장소의 '하늘만' 사진과 비교해 하늘을 지움)
PANOS = {
    'pano_hills': ('qwantani_afternoon', 'qwantani_afternoon_puresky'),
    'pano_peaks': ('drakensberg_solitary_mountain', 'drakensberg_solitary_mountain_puresky'),
}

# 무늬 이름 → Poly Haven 무늬 (diffuse 2K)
TEXTURES = {
    'grass': 'aerial_grass_rock',
    'moss': 'forest_floor',
    'pebble': 'ganges_river_pebbles',
    'sand': 'coast_sand_01',
    'dirt': 'dirt_floor',
    'planks': 'plank_flooring',
    'planks_dark': 'dark_wooden_planks',
    'brick': 'red_brick',
    'rock': 'aerial_rocks_02',
    'mossrock': 'mossy_rock',
    'bark': 'bark_brown_02',
    'cliff': 'cliff_side',          # 계곡 폭포 뒤 절벽·절벽 띠 (세로 암벽 사진)
    'fabric': 'wool_boucle',        # (예전 통나무집 가구 — 모든 가구가 천이라 어색해서 oak로 바꿈)
    'oak': 'grey_oak_veneer_01',
    'house_stucco': 'beige_wall_001',          # 시골집·거리 건물 벽: 실제 회벽 (밝은 베이지)
    'house_plaster': 'painted_plaster_wall',   # 칠한 회벽
    'house_stone': 'medieval_wall_01',         # 돌집
    'house_wood': 'brown_planks_03',           # 나무 판자 벽    # 통나무집 가구: 결이 고운 밝은 회갈색 참나무 (통나무 벽·마루와 겹치지 않는 빛깔)
    'walnut': 'american_walnut_veneer',   # 카페 가구 (윤나는 호두나무)
    'concrete': 'concrete_wall_003',      # 도시 옥상 구조물 (콘크리트)
}
# 실제 녹음 효과음: BigSoundBank (https://bigsoundbank.com, CC0 — 출처 표기 없이 자유롭게 사용 가능) 번호.
# make_assets.real_sfx 가 잘라·다듬어 앱 효과음 이름으로 바꿈 (받지 못하면 직접 만든 소리를 그대로 씀)
SFX_IDS = [1889, 1890, 1891, 1892, 1893, 1894, 1895, 1896, 1897,      # 고양이 야옹 #1~#9
           494, 1472, 1473, 1474, 1475, 1476, 1477, 1478, 1479,       # 작은 냥 (짧은 냥·므르·짹)
           98, 436, 1885,                                             # 가는 냥(트릴), 그르릉, 으르렁
           612, 682, 2450, 1060, 1547,                                # 강아지: 짖음(작은 개), 스피츠 왈, 하울링, 놀자 그르릉, 헥헥
           690,                                                       # 얕은 물을 걷는 발소리 (첨벙)
           823, 507, 30,                                              # 작은 개울, 작은 폭포, 벽난로 장작
           3005, 2478]                                                # 비행기 지나감
# 전시관 벽(plaster)은 실사 대신 직접 그린 흰 대리석 느낌 벽을 씀 (실사 거친 회벽은 통나무집처럼 투박해 보였음)


def sky_url(i):
    return f'https://dl.polyhaven.org/file/ph-assets/HDRIs/extra/Tonemapped%20JPG/{i}.jpg'


def tex_url(i):
    return f'https://dl.polyhaven.org/file/ph-assets/Textures/jpg/2k/{i}/{i}_diff_2k.jpg'


def get(url, dst):
    if os.path.exists(dst) and os.path.getsize(dst) > 50_000:
        return True
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    for attempt in range(3):
        try:
            req = urllib.request.Request(url, headers={'User-Agent': UA})
            with urllib.request.urlopen(req, timeout=120) as r:
                data = r.read()
            if len(data) < 50_000:
                raise IOError('too small')
            with open(dst + '.part', 'wb') as f:
                f.write(data)
            os.replace(dst + '.part', dst)
            return True
        except Exception as e:
            if attempt == 2:
                print('  못 받음:', url, '|', e, flush=True)
            time.sleep(2 + attempt * 3)
    return False


def sfx_url(i):
    return f'https://bigsoundbank.com/UPLOAD/mp3/{i:04d}.mp3'


def sfx_path(i):
    return os.path.join(CACHE, 'sfx', f'{i:04d}.mp3')


def get_small(url, dst):
    """작은 파일(효과음)용 — 크기 기준을 낮춤"""
    if os.path.exists(dst) and os.path.getsize(dst) > 4000:
        return True
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    for attempt in range(3):
        try:
            req = urllib.request.Request(url, headers={'User-Agent': UA})
            with urllib.request.urlopen(req, timeout=60) as r:
                data = r.read()
            if len(data) < 4000:
                raise IOError('too small')
            with open(dst + '.part', 'wb') as f:
                f.write(data)
            os.replace(dst + '.part', dst)
            return True
        except Exception as e:
            if attempt == 2:
                print('  못 받음:', url, '|', e, flush=True)
            time.sleep(2 + attempt * 3)
    return False


def sky_path(i):
    return os.path.join(CACHE, 'sky', i + '.jpg')


def tex_path(i):
    return os.path.join(CACHE, 'tex', i + '.jpg')


def main():
    ids = set(SKIES.values())
    for a, b in PANOS.values():
        ids |= {a, b}
    jobs = [(sky_url(i), sky_path(i)) for i in sorted(ids)]
    jobs += [(tex_url(i), tex_path(i)) for i in sorted(set(TEXTURES.values()))]
    with ThreadPoolExecutor(4) as ex:
        ok = list(ex.map(lambda j: get(*j), jobs))
    print(f'실사 재료: {sum(ok)}/{len(ok)}개 (캐시 {CACHE})', flush=True)
    with ThreadPoolExecutor(4) as ex:
        ok2 = list(ex.map(lambda i: get_small(sfx_url(i), sfx_path(i)), SFX_IDS))
    print(f'실제 녹음 효과음: {sum(ok2)}/{len(ok2)}개', flush=True)


if __name__ == '__main__':
    main()
