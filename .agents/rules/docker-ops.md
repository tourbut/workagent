---
trigger: always_on
description: docker compose v2 기반 Mattermost + hermes-agent 스택의 운영 규칙
---

# Docker Compose 운영 규칙

본 저장소는 **docker compose v2**(공백, 하이픈 없음)를 사용한다. `docker-compose`(하이픈 포함, v1) 명령은 사용하지 않는다.

## 1. 기본 명령 매핑

| 의도 | 명령 |
|---|---|
| 스택 기동 (백그라운드) | `docker compose up -d` |
| 단일 서비스 기동 | `docker compose up -d <service>` |
| 상태 확인 | `docker compose ps` |
| 실시간 로그 | `docker compose logs -f --tail=200 <service>` |
| 이미지 갱신 후 재기동 | `docker compose pull && docker compose up -d` |
| 단일 서비스 강제 재생성 | `docker compose up -d --force-recreate --no-deps <service>` |
| 머지 결과 검증 | `docker compose config` (커밋·기동 전에 한 번) |
| 정지 (데이터 보존) | `docker compose stop` 또는 `docker compose down`(볼륨 보존) |
| **금지** | `docker compose down -v` — 사용자 명시 지시 없이 실행 금지 |

## 2. 변경 전 점검

compose 파일을 수정한 뒤에는 기동/커밋 전에 항상 다음을 실행한다.

```bash
docker compose config >/dev/null && echo OK
```

오류가 출력되면 수정한다. 정상 출력은 시크릿을 포함하므로 그대로 붙여 넣지 않는다.

## 3. 서비스 재기동 우선순위

데이터 손실 가능성을 최소화하기 위해 아래 순서로 시도한다.

1. **설정만 바뀐 경우** — `docker compose up -d <service>` (compose가 diff를 보고 필요한 경우에만 재생성)
2. **이미지가 바뀐 경우** — `docker compose pull <service> && docker compose up -d <service>`
3. **강제 재생성이 필요한 경우** — `docker compose up -d --force-recreate --no-deps <service>`
4. **전체 재기동** — 마지막 수단. 사용자 확인 후 실행.

`--no-deps`를 붙이면 의존 서비스(예: DB)는 건드리지 않는다. 봇만 재시작할 때 특히 중요하다.

## 4. 로그·헬스체크 절차

기동 후에는 반드시 확인한다.

```bash
docker compose ps                                    # 모든 서비스 healthy/running 인가
docker compose logs --tail=100 mattermost            # Mattermost 부팅 완료 여부
docker compose logs --tail=100 hermes-agent          # 봇 로그인·웹소켓 연결 여부
curl -fsS http://localhost:<port>/api/v4/system/ping # Mattermost API ping
```

기동 직후 5~10초 동안은 헬스체크가 실패할 수 있다. 즉시 `down` 하지 말고 로그를 더 확인한다.

## 5. 데이터 볼륨 다루기

- Mattermost는 DB(Postgres) + 업로드 파일 디렉터리 두 가지 영속 저장소를 가진다. 둘 다 손실되면 복구 불가하므로 **백업이 없는 상태에서 볼륨 삭제 금지**.
- 백업은 정지 상태에서 수행한다.
  ```bash
  docker compose stop
  tar czf backup-$(date +%F).tgz volumes/
  docker compose start
  ```
- named volume을 쓰는 경우 `docker run --rm -v <vol>:/data -v $PWD:/backup busybox tar czf /backup/<name>.tgz /data` 패턴을 사용한다.

## 6. 네트워크·포트

- Mattermost와 hermes-agent는 같은 compose 네트워크에 두고, 컨테이너 이름(`mattermost`)을 호스트명으로 통신한다. 외부 IP/`localhost`로 호출하지 않는다.
- 호스트로 노출하는 포트는 최소화한다. 디버그용 포트는 `docker-compose.override.yml`(gitignore)에 둔다.

## 7. 디버깅 일반

- 컨테이너 진입은 `docker compose exec <service> sh` (또는 `bash`).
- `docker compose run`은 새 컨테이너를 만들기 때문에 운영 중 디버깅에는 쓰지 않는다.
- 컨테이너를 강제 종료할 때도 `docker kill`보다 `docker compose stop <service>`(SIGTERM 전송)를 우선한다.

## 8. CI/이미지 빌드

- hermes-agent를 본 저장소에서 빌드한다면 `build:` 컨텍스트와 `image:` 태그를 함께 명시해 빌드 결과를 재사용 가능하게 한다.
- 빌드 캐시가 의심스러우면 `docker compose build --no-cache <service>`를 명시적으로 실행한다.
