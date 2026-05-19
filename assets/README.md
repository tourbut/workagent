# assets/

Mattermost 커스텀 브랜드 로고를 두는 위치입니다.

## 사용

`logo.png` (또는 `logo.jpg`/`logo.jpeg`) 파일을 이 디렉터리에 두고 `./scripts/init-volumes.sh` 를 실행하면 `volumes/mattermost/data/brand/image.png` 로 복사돼 즉시 로그인 화면에 노출됩니다.

- 권장 크기: 200–500px (가로/세로)
- 최대 용량: 2MB
- 지원 포맷: PNG · JPG (Mattermost 자체는 TIFF/BMP 도 지원하지만 시드 스크립트는 PNG/JPG 만 처리)

## 주의

- 이미 `volumes/mattermost/data/brand/image.png` 가 있으면(= 시스템 콘솔에서 업로드한 경우) 시드 스크립트는 덮어쓰지 않습니다.
- 로고를 바꾸려면: ① 새 파일을 `assets/logo.png` 로 저장 → ② `rm volumes/mattermost/data/brand/image.png` → ③ `./scripts/init-volumes.sh`
- 활성화 토글(`MM_TEAMSETTINGS_ENABLECUSTOMBRAND`) 은 `docker-compose.yml` 에서 `true` 로 고정돼 있습니다.
