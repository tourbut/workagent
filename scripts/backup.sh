#!/usr/bin/env bash
# Mattermost 데이터/DB 백업.
# - 정지 후 ./volumes 를 tar.gz 로 묶고 다시 시작한다.
# - 결과물: backup-YYYY-MM-DD-HHMM.tgz (저장소 루트). 외부 스토리지로 옮기는 건 호출자 책임.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ts="$(date +%F-%H%M)"
out="backup-${ts}.tgz"

echo "[backup] 스택 정지 (docker compose stop)"
docker compose stop

echo "[backup] tar 압축 → $out"
tar czf "$out" volumes/

echo "[backup] 스택 재기동 (docker compose start)"
docker compose start

echo "[backup] done. 결과: $ROOT_DIR/$out"
ls -lh "$out"
