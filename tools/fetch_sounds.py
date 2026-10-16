"""엠비언트 소리를 앱에 담기 (GitHub Actions에서 실행)
ios/AnotherSpace/Sounds/manifest.json 의 파일들을 R2 버킷(ambient-audio)에서 wrangler로 받아
ios/AnotherSpace/Sounds/<경로> 에 저장. 필요: CLOUDFLARE_API_TOKEN, CLOUDFLARE_ACCOUNT_ID (환경 변수)
첫 파일은 결과를 그대로 보여 줘서, 토큰·계정 값이 틀렸으면 로그에서 이유를 바로 볼 수 있게 함."""
import json, os, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'ios', 'AnotherSpace', 'Sounds')
BUCKET = os.environ.get('R2_BUCKET', 'ambient-audio')

for k in ('CLOUDFLARE_API_TOKEN', 'CLOUDFLARE_ACCOUNT_ID'):
    if not os.environ.get(k):
        print(f'::error::{k} 비밀값이 비어 있어요 (저장소 Settings > Secrets and variables > Actions)')
        sys.exit(1)

m = json.load(open(os.path.join(OUT, 'manifest.json')))
files = sorted({e['file'] for sec in ('beds', 'weather', 'events') for l in m.get(sec, {}).values() for e in l})
print(f'목록의 소리 파일 {len(files)}개')


def get(rel):
    out = os.path.join(OUT, rel)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    r = subprocess.run(['wrangler', 'r2', 'object', 'get', f'{BUCKET}/{rel}', '--file', out, '--remote'],
                       capture_output=True, text=True)
    ok = r.returncode == 0 and os.path.exists(out) and os.path.getsize(out) > 1000
    return rel, ok, (r.stdout + r.stderr).strip()


if not files:
    print('::error::manifest.json 에 소리 파일이 없어요'); sys.exit(1)

# 첫 파일: 실패하면 wrangler가 한 말을 그대로 보여 주고 멈춤 (토큰·계정 값 확인용)
rel, ok, log = get(files[0])
if not ok:
    print('::error::첫 소리 파일부터 받지 못했어요. 아래 wrangler 메시지를 확인해 주세요.')
    print(log[-3000:])
    sys.exit(1)

fail = []
with ThreadPoolExecutor(8) as ex:
    for rel, ok, log in ex.map(get, files[1:]):
        if not ok:
            fail.append(rel)
n = len(files) - len(fail)
size = sum(os.path.getsize(os.path.join(dp, f)) for dp, _, fs in os.walk(OUT) for f in fs)
print(f'소리 {n}개 담음, {size / 1e6:.1f}MB, 받지 못함 {len(fail)}개')
for f in fail[:30]:
    print('  받지 못함:', f)
