---
trigger: always_on
description: 시크릿 · .env · Mattermost 봇 토큰 · DB 비밀번호의 취급 규칙
---

# Secrets

본 저장소는 Mattermost 봇 토큰·DB 비밀번호·외부 API 키 등 운영 시크릿을 다룬다. 다음 규칙을 예외 없이 따른다.

## 1. 절대 커밋하지 않는 파일

- `.env`
- `*.env`(예: `mattermost.env`, `hermes-agent.env`)
- 사설 키(`*.pem`, `*.key`, `id_rsa*`)
- 자격증명 JSON(`*-credentials.json`, `*.sa.json` 등)

`.gitignore`에 위 패턴을 명시한다. 새 시크릿 파일을 추가할 때는 `.gitignore`를 먼저 갱신한 뒤 파일을 생성한다.

## 2. `.env.example`은 항상 커밋

- 새 환경변수가 필요해지면 동시에 `.env.example`에 **키와 더미값**을 추가한다.
- 더미값은 형식만 알려주는 수준으로 둔다(예: `MATTERMOST_BOT_TOKEN=changeme-token`). 실제 토큰의 첫/끝 몇 글자라도 노출하지 않는다.
- 변수마다 한 줄 주석으로 용도를 명시한다.

```env
# Mattermost 시스템 콘솔 > Integrations > Bot Accounts 에서 발급
HERMES_MATTERMOST_TOKEN=changeme-token

# hermes-agent 가 접근할 Mattermost 베이스 URL (compose 네트워크 내부)
HERMES_MATTERMOST_URL=http://mattermost:8065
```

## 3. 출력 노출 방지

다음 명령들은 시크릿을 평문으로 노출한다. 출력을 그대로 채팅·이슈·로그·커밋 메시지에 붙여 넣지 않는다.

- `docker compose config` — `.env` 치환 결과를 평문으로 보여준다
- `docker compose exec <svc> env` — 컨테이너 환경변수 전체 덤프
- `cat .env`, `grep . .env`
- `docker inspect <container>` — `Env` 필드에 시크릿 포함

부득이 출력이 필요하면 시크릿 라인을 마스킹한 뒤 공유한다.

## 4. 봇 토큰 발급 절차 (요약)

1. Mattermost에 시스템 관리자 계정으로 로그인
2. **시스템 콘솔 → Integrations → Bot Accounts → Enable** (활성화 필요)
3. **Integrations → Bot Accounts → Add Bot Account** 로 hermes 전용 봇 생성
4. 표시되는 토큰을 즉시 `.env`의 해당 키에 저장. 토큰은 그 화면을 떠나면 다시 볼 수 없다.
5. 봇이 소속될 팀/채널에 봇을 초대(별도 단계)

## 5. 로컬 보관 권장

- `.env`는 호스트별로 별도 보관하고 권한은 600.
  ```bash
  chmod 600 .env
  ```
- 팀 공유가 필요하면 1Password/Vault/Doppler 등 비밀 관리자에 두고, 저장소에는 키 이름만 남긴다.

## 6. 사고 대응

토큰이 커밋·로그·메시지에 노출됐다고 판단되면 즉시 다음을 수행한다.

1. Mattermost 시스템 콘솔에서 해당 봇 토큰을 **revoke**하거나 봇을 비활성화
2. 새 토큰을 발급해 `.env`에 반영
3. hermes-agent 재기동 (`docker compose up -d --no-deps hermes-agent`)
4. 노출 경로(커밋·로그)에 대한 정리(필요 시 git history 정리는 사용자 확인 후)

`git filter-repo`나 history rewrite는 영향이 크므로 **반드시 사용자 확인 후** 실행한다.
