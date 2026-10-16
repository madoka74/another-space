# 어나더 스페이스 (Another Space)

블랭키씨 웍스 · 비전프로 앱. 집을 한 번 스캔해 두면, 방마다 다른 세계(엠비언트의 장소·날씨·시간)가 입혀지고 그 세계의 소리가 들려요.

- 번들 ID: `com.blankishworks.another-space` (visionOS 2.0 이상)
- 빌드: `ios/project.yml`(XcodeGen) → GitHub Actions `.github/workflows/ios.yml` → TestFlight
- 버전: `version.json`
- 소리: 엠비언트 Worker(`ambient.madoka74.workers.dev`)의 `manifest.json`과 `/audio/` 파일을 처음 들어갈 때 받아 기기에 보관
- 그림 재료: `python3 tools/make_assets.py` (바닥·벽 무늬, 하늘), 아이콘: `python3 tools/icon.py`
