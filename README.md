# workagent

[Mattermost](https://mattermost.com) 서버와 [hermes-agent](https://github.com/NousResearch/hermes-agent)(Mattermost 봇으로 동작하는 AI 에이전트)를 **하나의 `docker-compose.yml`** 로 묶어서 운영하는 저장소입니다.

운영 규범과 AI 에이전트 작업 규칙은 [.agents/AGENTS.md](.agents/AGENTS.md) 를 참조하세요.

---

## 구성

| 서비스 | 이미지 | 역할 |
|---|---|---|
| `postgres` | `postgres:15-alpine` | Mattermost 백엔드 DB |
| `mattermost` | `mattermost/mattermost-team-edition:10.5` | 메신저 서버 (호스트 `:8065`). **Calls 비활성·기본 한국어·커스텀 브랜딩 활성** 으로 초기화 |
| `hermes-agent` | `nousresearch/hermes-agent:latest` (공식 이미지) | Mattermost 봇 어댑터 (`gateway run`). LLM 공급자: OpenRouter |

세 서비스는 `workagent-stack` 브리지 네트워크에서만 통신하고, 외부에는 Mattermost 의 `8065` 포트만 노출됩니다.

---

## 빠른 시작

### 1. 사전 요구

- Docker Engine + Docker Compose v2 (`docker compose version` 으로 확인)
- Git
- (리눅스 호스트) sudo 권한 — Mattermost 볼륨 권한 조정용

### 2. 환경변수 준비

```bash
cp .env.example .env
$EDITOR .env   # 비밀번호·토큰을 채운다
chmod 600 .env
```

이 시점에는 `MATTERMOST_TOKEN` / `MATTERMOST_ALLOWED_USERS` 값을 아직 모릅니다 — Mattermost 가 처음 떠야 봇을 만들 수 있기 때문에, 빈 값으로 두고 일단 진행해도 됩니다. `OPENROUTER_API_KEY` 와 `HERMES_INFERENCE_MODEL` (예: `anthropic/claude-opus-4.7`) 은 hermes-agent 기동 전에 채워야 합니다.

### 3. 볼륨 디렉터리 생성 + hermes 설정 시드

```bash
./scripts/init-volumes.sh
```

수행 내용:
- 바인드 마운트 대상 디렉터리(`volumes/postgres`, `volumes/mattermost/*`, `volumes/hermes`) 생성
- **`.env` 의 `HERMES_INFERENCE_PROVIDER`/`HERMES_INFERENCE_MODEL`/`OPENROUTER_BASE_URL` 값으로 `volumes/hermes/config.yaml` 생성** (이미 있으면 건드리지 않음 — 모델 변경 시 파일 삭제 후 재실행)
- **`assets/logo.png` 가 있으면 `volumes/mattermost/data/brand/image.png` 로 시드** (커스텀 브랜드 로고)
- 리눅스 호스트에서는 `volumes/mattermost/*` 의 소유권을 `2000:2000` (Mattermost 이미지의 컨테이너 사용자) 으로 변경

> `OPENROUTER_API_KEY` 는 config.yaml 에 쓰지 않고 컨테이너 환경변수로만 주입됩니다(시크릿 노출 최소화).

### 4. Mattermost 먼저 띄우기 (봇 생성을 위해)

```bash
docker compose up -d postgres mattermost
docker compose ps
```

`http://localhost:8065` 에 접속해서:

1. 최초 관리자 계정 생성
2. 시스템 콘솔 → Integrations → **Bot Accounts 활성화**
3. Integrations → Bot Accounts → **Add Bot Account** 로 hermes 봇 생성
4. 표시되는 토큰을 `.env` 의 `MATTERMOST_TOKEN` 에 저장 (이 화면을 떠나면 다시 못 봅니다)
5. 봇이 응답할 사용자의 26자 User ID 를 프로필에서 복사 → `MATTERMOST_ALLOWED_USERS`

### 5. hermes-agent 기동

```bash
docker compose pull hermes-agent
docker compose up -d hermes-agent
docker compose logs -f hermes-agent
```

봇이 Mattermost 에 로그인하고 WebSocket 이 붙으면 다이렉트 메시지로 대화할 수 있습니다.

---

## 일상 운영 명령

```bash
# 상태
docker compose ps

# 로그
docker compose logs -f --tail=200 mattermost
docker compose logs -f --tail=200 hermes-agent

# 봇만 재기동 (Mattermost/DB 는 건드리지 않음)
docker compose up -d --force-recreate --no-deps hermes-agent

# 이미지 업그레이드 (태그를 .env 에서 먼저 변경)
docker compose pull
docker compose up -d

# 정지 (데이터 보존)
docker compose stop

# 백업
./scripts/backup.sh   # backup-YYYY-MM-DD-HHMM.tgz 생성
```

> **금지**: `docker compose down -v` — named volume 이 아니라 바인드 마운트라 직접적 위험은 작지만, 운영 중 스택에 대해 down 류를 도는 습관 자체를 들이지 않습니다. 상세 규칙은 [.agents/rules/docker-ops.md](.agents/rules/docker-ops.md).

---

## 디렉터리

```
.
├── docker-compose.yml         # 스택 정의
├── .env.example               # 환경변수 카탈로그 (커밋)
├── .env                       # 실제 시크릿 (커밋 금지)
├── .gitignore
├── README.md
├── assets/                    # 로고 등 정적 자산
│   └── logo.png               # (선택) Mattermost 커스텀 브랜드 로고
├── config/
│   └── hermes-config.template.yaml  # hermes config.yaml 시드 템플릿
├── scripts/
│   ├── init-volumes.sh        # 볼륨 디렉터리 생성 + hermes config.yaml 시드 + 권한
│   └── backup.sh              # 정지 후 ./volumes tar 압축
├── volumes/                   # 런타임 데이터 (커밋 금지)
│   ├── postgres/
│   ├── mattermost/{config,data,logs,plugins,client-plugins,bleve-indexes}/
│   └── hermes/                # hermes-agent /opt/data 영속화 (config.yaml, .env, sessions, memories, skills, logs)
└── .agents/                   # AI 에이전트 운영 규범
    ├── AGENTS.md
    └── rules/
        ├── workspace-routine.md
        ├── docker-ops.md
        ├── secrets.md
        └── python-env.md
```

---

## 트러블슈팅

- **Mattermost 가 부팅 중 권한 오류**: 리눅스에서 `volumes/mattermost/*` 의 소유권이 `2000:2000` 인지 확인. `./scripts/init-volumes.sh` 를 다시 돌립니다.
- **hermes-agent 가 401/403 으로 Mattermost 접속 실패**: 봇 계정이 비활성화됐거나 토큰이 회수됐을 가능성. 시스템 콘솔에서 봇 상태 확인 후 새 토큰 발급 → `.env` 업데이트 → `docker compose up -d --no-deps hermes-agent`.
- **봇이 응답하지 않음**: ① 봇이 해당 채널의 멤버인지, ② `MATTERMOST_ALLOWED_USERS` 에 사용자 ID 가 들어있는지, ③ 채널에서 응답하려면 `@봇이름` 멘션이 필요한지(`MATTERMOST_REQUIRE_MENTION`) 확인.
- **LLM 호출 실패 (401/402)**: OpenRouter 키가 만료·크레딧 부족일 수 있음. <https://openrouter.ai/keys> 에서 상태 확인 후 `.env` 갱신 → `docker compose up -d --no-deps hermes-agent`.
- **모델을 바꾸고 싶을 때**: ① `.env` 의 `HERMES_INFERENCE_MODEL` 수정 → ② `rm volumes/hermes/config.yaml` → ③ `./scripts/init-volumes.sh` (config 재시드) → ④ `docker compose up -d --no-deps hermes-agent`. 모델 슬러그는 <https://openrouter.ai/models> 에서 확인.
  - 또는 `volumes/hermes/config.yaml` 의 `model.default` 를 직접 편집해도 됩니다 — 그러면 ④ 만 실행.

## 로고 / 사이트명 / 언어 커스터마이즈

기본 초기 설정은 다음과 같습니다 (compose 에서 고정):
- **Calls 플러그인 비활성**
- **기본 서버/클라이언트 언어: 한국어**
- **커스텀 브랜딩 활성** (`MM_TEAMSETTINGS_ENABLECUSTOMBRAND=true`)

세부 조정은 `.env` 의 아래 키로:

| 키 | 효과 |
|---|---|
| `MM_DEFAULT_LOCALE` | 서버/클라이언트 기본 언어 (기본 `ko`) |
| `MM_AVAILABLE_LOCALES` | 사용자 선택 가능 언어 목록 (콤마 구분, 비우면 전체) |
| `MM_SITE_NAME` | 로그인 화면 사이트명 (기본 `workagent`) |
| `MM_CUSTOM_BRAND_TEXT` | 로고 옆에 표시되는 짧은 문구 (최대 500자) |
| `MM_CUSTOM_DESCRIPTION_TEXT` | 로그인 화면 하단 설명 (최대 1024자) |

**로고 이미지**:
- `assets/logo.png` (또는 `.jpg`) 를 두고 `./scripts/init-volumes.sh` 실행 → `volumes/mattermost/data/brand/image.png` 로 시드. 즉시 로그인 화면에 노출됩니다.
- 권장 200–500px, 최대 2MB.
- 이미 시스템 콘솔에서 업로드한 이미지가 있으면 시드 스크립트는 건드리지 않습니다.
- 변경 시: 새 파일을 `assets/logo.png` 로 저장 → `rm volumes/mattermost/data/brand/image.png` → `./scripts/init-volumes.sh`.

---

## 참고

- Mattermost 공식 docker 저장소: <https://github.com/mattermost/docker>
- hermes-agent 저장소: <https://github.com/NousResearch/hermes-agent>
- hermes-agent Mattermost 가이드: <https://github.com/NousResearch/hermes-agent/blob/main/website/docs/user-guide/messaging/mattermost.md>
