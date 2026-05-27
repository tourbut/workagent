#!/usr/bin/env bash
# config/hermes 의 주요 에이전트 설정(SOUL.md 및 ax-interview 스킬)을
# podman/docker 컨테이너 볼륨 및 실시간 실행 공간으로 동기화 덮어쓰기하는 스크립트입니다.

# Prevent sourcing to avoid SSH disconnection on error/exit
is_sourced=0
if [ -n "$BASH_VERSION" ]; then
    [ "$0" != "${BASH_SOURCE[0]}" ] && is_sourced=1
elif [ -n "$ZSH_VERSION" ]; then
    [ "$0" != "${(%):-%x}" ] && is_sourced=1
else
    case "$0" in
        sh|-sh|bash|-bash|zsh|-zsh|ksh|-ksh) is_sourced=1 ;;
    esac
fi

if [ "$is_sourced" -eq 1 ]; then
    echo "=================================================="
    echo "WARNING: Sourcing this script is not allowed!"
    echo "=================================================="
    return 1 2>/dev/null || exit 1
fi

set -euo pipefail

# 1. 프로젝트 루트로 이동
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
cd "$ROOT_DIR"

# 2. .env 환경변수 로드
if [ -f .env ]; then
    set -a
    # shellcheck disable=SC1091
    source .env
    set +a
fi

CONTAINER_ENGINE=${CONTAINER_ENGINE:-podman}
echo "=================================================="
echo "Hermes 에이전트 설정 및 스킬 동기화 덮어쓰기 시작"
echo "Container Engine: $CONTAINER_ENGINE"
echo "=================================================="

SRC_SOUL="config/hermes/SOUL.md"
SRC_SKILL="config/hermes/ax-interview"

DST_VOL_DIR="volumes/hermes"
DST_VOL_SOUL="$DST_VOL_DIR/SOUL.md"
DST_VOL_SKILL_DIR="$DST_VOL_DIR/skills/ax-interview"

# 3. 소스 파일 유효성 검사
if [ ! -f "$SRC_SOUL" ]; then
    echo "에러: 소스 파일이 존재하지 않습니다: $SRC_SOUL" >&2
    exit 1
fi
if [ ! -d "$SRC_SKILL" ]; then
    echo "에러: 소스 스킬 디렉터리가 존재하지 않습니다: $SRC_SKILL" >&2
    exit 1
fi

# 4. 바인드 마운트된 로컬 볼륨 경로(volumes/hermes)로 덮어쓰기 복사
echo "[*] 로컬 볼륨 경로($DST_VOL_DIR)로 파일 복사 중..."
if [ "$CONTAINER_ENGINE" = "podman" ] && command -v podman >/dev/null 2>&1; then
    echo "[*] Podman unshare 네임스페이스를 활용해 권한 문제를 예방하며 볼륨 복사를 수행합니다..."
    podman unshare mkdir -p "$DST_VOL_DIR"
    podman unshare mkdir -p "$DST_VOL_SKILL_DIR"
    podman unshare cp "$SRC_SOUL" "$DST_VOL_SOUL"
    podman unshare cp -pr "$SRC_SKILL"/. "$DST_VOL_SKILL_DIR"/
else
    mkdir -p "$DST_VOL_DIR"
    mkdir -p "$DST_VOL_SKILL_DIR"
    cp -p "$SRC_SOUL" "$DST_VOL_SOUL"
    cp -pr "$SRC_SKILL"/. "$DST_VOL_SKILL_DIR"/
fi

echo "[+] 로컬 볼륨 동기화 복사 완료!"

# 5. Linux 환경 및 Podman 사용 시 rootless 권한 안전 조정
if [ "$(uname)" = "Linux" ] && [ "$CONTAINER_ENGINE" = "podman" ]; then
    echo "[*] Linux Podman rootless 볼륨 소유권 조정 중 (podman unshare)..."
    podman unshare chown -R 10000:10000 "$DST_VOL_SOUL" "$DST_VOL_SKILL_DIR" 2>/dev/null || true
    podman unshare chmod -R 755 "$DST_VOL_SKILL_DIR" 2>/dev/null || true
    podman unshare chmod 644 "$DST_VOL_SOUL" 2>/dev/null || true
fi

# 6. 실행 중인 hermes-agent 컨테이너가 있다면 컨테이너 내부로 직접 실시간 덮어쓰기
echo "[*] 실행 중인 hermes-agent 컨테이너 확인 중..."
if command -v "$CONTAINER_ENGINE" >/dev/null 2>&1; then
    CONTAINER_ID=$($CONTAINER_ENGINE ps --filter "name=hermes-agent" -q | head -n 1 | tr -d '\r\n')

    if [ -n "$CONTAINER_ID" ]; then
        echo "[+] 실행 중인 컨테이너 감지 (ID: $CONTAINER_ID). 내부 실시간 동기화 복사를 진행합니다."
        
        # 컨테이너 내부 경로로 직접 복사 (덮어쓰기)
        $CONTAINER_ENGINE cp "$SRC_SOUL" "$CONTAINER_ID":/opt/data/SOUL.md
        $CONTAINER_ENGINE cp "$SRC_SKILL"/. "$CONTAINER_ID":/opt/data/skills/ax-interview/
        
        # 컨테이너 내 권한/소유권 맞추기 (UID 10000)
        $CONTAINER_ENGINE exec -u 0 -i "$CONTAINER_ID" chown -R 10000:10000 /opt/data/SOUL.md /opt/data/skills/ax-interview/ 2>/dev/null || true
        $CONTAINER_ENGINE exec -u 0 -i "$CONTAINER_ID" chmod -R 755 /opt/data/skills/ax-interview/ 2>/dev/null || true
        $CONTAINER_ENGINE exec -u 0 -i "$CONTAINER_ID" chmod 644 /opt/data/SOUL.md 2>/dev/null || true
        
        echo "[+] 컨테이너 내부 실시간 덮어쓰기 및 권한 조정 완료!"
    else
        echo "[!] 실행 중인 hermes-agent 컨테이너가 없습니다. (볼륨 파일만 덮어써졌으며, 다음 컨테이너 구동 시 자동 반영됩니다.)"
    fi
else
    echo "[!] '$CONTAINER_ENGINE' 명령어가 현재 호스트 환경에 설치되어 있지 않습니다. 컨테이너 내부 실시간 동기화를 건너뜁니다."
    echo "[!] (로컬 볼륨 파일은 정상적으로 덮어써졌으므로 컨테이너 재구동 시 자동으로 동기화됩니다.)"
fi

echo "=================================================="
echo "동기화 덮어쓰기 작업이 성공적으로 완료되었습니다!"
echo "=================================================="
