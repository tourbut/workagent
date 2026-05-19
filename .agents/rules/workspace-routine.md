---
trigger: always_on
description: 본 저장소에서 작업할 때의 작업 공간 규칙 — sandbox 우선, 변경 문서화, 비파괴적 진행
---

# Workspace Routine

본 저장소(`workagent`)는 운영 인프라(Mattermost + hermes-agent docker-compose)를 다룬다. 따라서 모든 변경은 **재현 가능하고 되돌릴 수 있는** 방식으로 진행한다.

## 1. Sandbox 우선

- 새 docker-compose 스니펫, 새 환경변수 조합, 실험적 명령은 먼저 `sandbox/` 하위에서 시도한다.
- 검증되지 않은 YAML/스크립트를 곧바로 루트의 `docker-compose.yml`이나 `scripts/`에 반영하지 않는다.
- `sandbox/` 하위는 `.gitignore`로 묶여 커밋되지 않는다고 가정한다. 공유가 필요하면 정규 경로로 승격하면서 커밋한다.

## 2. 변경 문서화

- 모든 비자명한 변경(이미지 태그 업그레이드, 새 서비스, 새 환경변수, 네트워크/포트 변경)은 다음 중 하나에 흔적을 남긴다.
  - 커밋 메시지 본문 (왜 변경했는지)
  - `README.md` 또는 `docs/`의 운영 메모
  - 새 스킬을 만들었다면 `.agents/skills/<name>/SKILL.md`
- 일회성 디버깅 명령은 문서화하지 않아도 되지만, **반복될 가능성이 있는 명령**은 즉시 `scripts/`로 옮긴다.

## 3. 비파괴적 진행

- 운영 중인 컨테이너에 영향을 줄 수 있는 명령(`down`, `restart`, 이미지 교체)은 실행 전에 영향 범위를 사용자에게 보고하고 확인을 받는다.
- 데이터 볼륨(`volumes/`, named volume)이 연결된 서비스에 대해 `down -v`, `rm`, 볼륨 삭제는 **명시적 지시 없이 절대 실행 금지**.
- 어떤 명령이든 실행 전후의 상태를 알 수 있도록 `docker compose ps`, `git status` 같은 관찰 명령을 함께 쓴다.

## 4. 파일·디렉터리 규약

- 새 파일은 lowercase-kebab-case(영문) 또는 한글-하이픈-구분(한글)으로 명명한다. 공백·camelCase·특수문자 금지.
- 운영 데이터(`volumes/`)와 시크릿(`.env`)은 절대 커밋하지 않는다. 디렉터리 보존이 필요하면 `.gitkeep`만 둔다.
- 임시 출력물(렌더된 compose, 로그 캡처)은 `sandbox/` 또는 `/tmp/` 아래에 두고 루트를 어지럽히지 않는다.

## 5. 작업 종료 체크리스트

작업을 마치기 전 다음을 확인한다.

- [ ] `git status` 결과에 의도치 않은 파일(`.env`, `volumes/`, 임시 로그 등)이 없는가
- [ ] 변경된 compose 파일이 `docker compose config`로 정상 파싱되는가
- [ ] 새 환경변수가 추가됐다면 `.env.example`에도 키가 반영됐는가
- [ ] 운영 중 스택이라면 실제로 기동/응답이 정상인가 (`docker compose ps`, 헬스체크)
