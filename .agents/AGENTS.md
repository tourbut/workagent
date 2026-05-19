---
title: "workagent — Mattermost + hermes-agent 운영 규범 (AGENTS.md)"
description: "Mattermost 서버와 hermes-agent를 단일 docker-compose 스택으로 운영하는 저장소의 공통 에이전트 규범"
type: "schema"
updated_at: "2026-05-19"
---

# AGENTS.md

이 저장소(`workagent`)는 **Mattermost 서버**와 **hermes-agent**(Mattermost에 봇으로 연결되는 AI 에이전트 워커)를 **하나의 docker-compose 스택**으로 묶어 운영하기 위한 인프라/오케스트레이션 저장소입니다. 본 문서는 이 저장소에서 작업하는 모든 AI 에이전트/코딩 어시스턴트(Claude Code, Codex, Cursor, Windsurf 등)가 하네스에 종속되지 않고 공통으로 따라야 하는 운영 규범을 정의합니다.

---

## 1. 저장소 목적

- 단일 `docker-compose.yml`로 다음 두 서비스를 함께 기동·중지·업그레이드한다.
  - **Mattermost** — 팀 메신저 서버 (공식 이미지 + Postgres)
  - **hermes-agent** — Mattermost에 봇으로 로그인해 메시지를 수신·응답하는 AI 에이전트 서비스. **공식 이미지 `nousresearch/hermes-agent`** 를 그대로 사용한다 (로컬 빌드 없음).
- LLM 공급자는 **OpenRouter** 로 고정한다. `OPENROUTER_API_KEY` 와 기본 모델 (`HERMES_INFERENCE_MODEL`) 은 `.env` 에서 관리한다.
- 두 서비스는 같은 docker 네트워크에서 통신하며, hermes-agent는 Mattermost API/WebSocket 으로 봇 토큰으로 연결된다.
- 본 저장소는 **운영 코드(YAML·.env.example·기동/관리 스크립트)** 만 보관한다. 실제 시크릿·DB 데이터·업로드 파일은 커밋하지 않는다.

---

## 2. 디렉터리 맵 (예상 구조)

저장소가 비어 있는 초기 상태라면 아래 구조를 점진적으로 채워 나간다. 이미 존재하는 파일을 정렬할 때도 이 구조를 기준으로 한다.

| 경로 | 역할 |
|---|---|
| `docker-compose.yml` | Mattermost · hermes-agent · (선택) Postgres 서비스 정의 |
| `docker-compose.override.yml` | 로컬 개발용 오버라이드(포트 노출·디버그 로그 등). gitignore 권장 |
| `.env.example` | 필요한 환경변수의 키와 더미값. **커밋 대상** |
| `.env` | 실제 시크릿이 들어가는 파일. **커밋 금지** (`.gitignore`) |
| `mattermost/` | Mattermost 설정 템플릿(`config.json` 스니펫 등). 런타임 데이터 볼륨은 `volumes/` |
| `scripts/` | `init-volumes.sh`, `backup.sh` 등 운영 보조 스크립트 |
| `volumes/` | docker 바인드 마운트용 데이터(`postgres/`, `mattermost/*`, `hermes/`). **커밋 금지**, 디렉터리만 `.gitkeep`으로 유지 |
| `sandbox/` | 초안·임시 작업 공간. `.gitignore` 포함 |
| `.agents/` | 본 운영 규범 (AGENTS.md, rules/, 추후 workflows/skills/) |
| `CLAUDE.md` | Claude Code 진입점 — `@.agents/AGENTS.md`를 import |

---

## 3. 규범 로딩 순서

에이전트는 작업 시작 전에 다음 규칙을 순서대로 적용한다.

1. [rules/workspace-routine.md](./rules/workspace-routine.md) — 샌드박스 우선·변경 문서화 원칙
2. [rules/docker-ops.md](./rules/docker-ops.md) — docker compose 운영 규칙 (데이터 손실 방지·재기동·로그 확인)
3. [rules/secrets.md](./rules/secrets.md) — `.env` / 토큰 / 자격증명 취급
4. [rules/python-env.md](./rules/python-env.md) — 보조 Python 스크립트가 있을 때만 적용 (uv 기반)

작업 성격에 따라 추가로 참조할 진입점은 추후 `workflows/`와 `skills/`에 추가한다. 현재는 진입점이 정의되지 않았으므로, 새로운 반복 작업이 생기면 먼저 `sandbox/`에서 시도한 뒤 안정화된 절차를 `skills/<name>/SKILL.md`로 승격한다.

---

## 4. 핵심 운영 루프 (Plan · Apply · Observe)

이 저장소의 일상 작업은 다음 3단계 루프를 따른다.

- **Plan** — 변경할 항목을 식별한다. 이미지 태그 업데이트, 환경변수 추가, 새 서비스 등 영향이 큰 변경은 `sandbox/`에 임시 `docker-compose.<topic>.yml`을 만들어 검토한다.
- **Apply** — `docker compose config`로 머지 결과를 먼저 확인하고, `docker compose pull && docker compose up -d`로 적용한다. 데이터 볼륨이 있는 서비스는 단순 `down`이 아니라 `restart` 또는 `up -d --force-recreate <service>`를 우선 사용한다.
- **Observe** — `docker compose ps`로 상태, `docker compose logs -f --tail=200 <service>`로 부팅 로그, Mattermost는 `https://<host>/api/v4/system/ping`, hermes-agent는 자체 헬스 엔드포인트(있다면)로 확인한다. 실패 시 즉시 `down` 하지 말고 로그를 먼저 캡처해 sandbox 메모에 남긴다.

> 위 흐름은 [rules/docker-ops.md](./rules/docker-ops.md)의 세부 명령 규약을 따른다.

---

## 5. 불변 원칙

1. **데이터 볼륨 불변성** — `volumes/`(또는 named volume) 안의 Mattermost DB·업로드 파일은 사람의 명시적 지시 없이는 절대 삭제·수정하지 않는다. 백업이 없는 상태에서 `docker compose down -v` 금지.
2. **시크릿 미커밋** — `.env`, `*_TOKEN`, `*_PASSWORD`, 봇 personal access token, TLS 키 등은 절대 커밋하지 않는다. 새 변수는 반드시 `.env.example`에 더미값과 함께 키만 추가한다.
3. **Sandbox 우선** — 새 compose 스니펫·새 서비스·실험적 환경변수는 먼저 `sandbox/`에서 검증한 뒤 루트로 승격한다.
4. **운영 중인 서비스 보호** — 이미 기동 중인 컨테이너에 영향을 줄 수 있는 행동(`down`, `restart`, 이미지 교체, 볼륨 마운트 변경)은 사용자에게 영향 범위를 보고하고 확인을 받는다.
5. **재현 가능성** — 모든 기동/중지/복구 절차는 `scripts/` 안의 셸 스크립트 또는 README의 명령으로 재현 가능해야 한다. 임시 명령 한 줄로 끝내지 말고 스크립트에 반영한다.
6. **버전 고정** — `docker-compose.yml`의 이미지 태그는 가능한 한 명시적 버전(`mattermost/mattermost-team-edition:10.x.y`)을 쓰고 `:latest`는 지양한다. 변경 시 사유를 커밋 메시지에 남긴다.
7. **단일 책임 커밋** — compose 변경, 시크릿 키 추가, 스크립트 추가는 서로 다른 커밋으로 분리한다.

---

## 6. 보안·시크릿 요약

세부는 [rules/secrets.md](./rules/secrets.md)에 위임한다. 본 절은 항상 의식해야 하는 최소 사항만 기록한다.

- 봇 토큰은 Mattermost 시스템 콘솔 → Integrations → Bot Accounts에서 발급해 `.env`의 `HERMES_MATTERMOST_TOKEN`(또는 동등 키)에 둔다.
- `.env`는 600 권한, 호스트별로 별도 보관한다. 가능하면 1Password/Vault 같은 외부 보관소를 1차 소스로 한다.
- 디버깅용으로 토큰을 echo 하거나 로그에 흘리지 않는다. `docker compose config`도 시크릿을 평문으로 노출하므로 결과를 그대로 붙여 넣지 않는다.

---

## 7. 커밋·푸시 가이드

- 모든 커밋은 해당 변경의 **의도**를 1~2문장으로 설명한다(무엇이 아니라 왜).
- compose 변경은 **머지 결과를 검증**한 뒤 커밋한다.
  ```bash
  docker compose -f docker-compose.yml config > /tmp/compose.rendered.yml
  ```
- 이미지 태그 업그레이드 커밋에는 **이전 → 새 버전**과 **사유(보안패치/기능)**을 본문에 남긴다.
- 푸시 전에 `git status`로 `.env`·`volumes/` 같은 의도치 않은 파일이 스테이지에 올라오지 않았는지 확인한다.

---

## 8. 금지 사항

- 운영 데이터를 가진 컨테이너에 대해 `docker compose down -v` 실행
- `.env`·봇 토큰·DB 비밀번호 등 시크릿을 평문으로 커밋
- 사용자 확인 없이 이미지 태그를 `:latest`로 회귀
- `volumes/` 하위 파일을 직접 편집(컨테이너 내부에서 정상 절차로 변경)
- 운영 중 스택을 사용자 확인 없이 임의로 재기동

---

## 9. 향후 확장 슬롯

본 저장소는 시작 단계이므로 아래 영역은 비어 있다. 작업이 반복되면 다음 위치로 승격한다.

- `.agents/workflows/` — 슬래시 명령 진입점(`/up`, `/down`, `/upgrade`, `/backup` 등)
- `.agents/skills/` — 구체 작업 SOP(예: `mattermost-bot-bootstrap`, `compose-upgrade`, `volume-backup`)
- `scripts/` — 위 스킬의 실행 가능한 본체
