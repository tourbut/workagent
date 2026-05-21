#!/usr/bin/env bash
# 데이터 볼륨 디렉터리를 미리 생성하고 hermes-agent config.yaml 을 시드한다.
# - Mattermost 컨테이너는 일부 디렉터리가 없으면 권한 문제로 부팅에 실패할 수 있다.
# - hermes-agent 는 /opt/data/config.yaml 에서 model/provider 를 읽으므로 첫 실행 전에 만들어 둔다.
# - 본 스크립트는 멱등이다 (이미 있으면 건드리지 않는다).

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
    echo "Sourcing ('source' or '.') will cause your SSH session"
    echo "to disconnect if an error occurs (due to set -e or exit)."
    echo ""
    echo "Please run the script directly instead:"
    echo "  bash scripts/init-volumes.sh"
    echo "  or"
    echo "  ./scripts/init-volumes.sh"
    echo "=================================================="
    return 1 2>/dev/null || exit 1
fi

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# ─── 1. 디렉터리 생성 ────────────────────────────────────────
dirs=(
  "volumes/postgres"
  "volumes/mattermost/config"
  "volumes/mattermost/data"
  "volumes/mattermost/logs"
  "volumes/mattermost/plugins"
  "volumes/mattermost/client-plugins"
  "volumes/mattermost/bleve-indexes"
  "volumes/hermes"
)

for d in "${dirs[@]}"; do
  if [[ ! -d "$d" ]]; then
    mkdir -p "$d"
    echo "created: $d"
  fi
done

# ─── 2. hermes-agent config.yaml 시드 ────────────────────────
config_dst="volumes/hermes/config.yaml"
config_tpl="config/hermes-config.template.yaml"

if [[ -f "$config_dst" ]]; then
  echo "skip: $config_dst already exists (regenerate by deleting it first)"
else
  if [[ ! -f "$config_tpl" ]]; then
    echo "error: template not found at $config_tpl" >&2
    exit 1
  fi

  # .env 로드 (있으면). 없으면 기본값으로 진행.
  if [[ -f ".env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source .env
    set +a
  else
    echo "warning: .env not found. 기본값으로 config.yaml 을 생성합니다." >&2
  fi

  provider="${HERMES_INFERENCE_PROVIDER:-openrouter}"
  model="${HERMES_INFERENCE_MODEL:-anthropic/claude-opus-4.7}"
  base_url="${OPENROUTER_BASE_URL:-}"

  sed \
    -e "s|@@PROVIDER@@|${provider}|g" \
    -e "s|@@MODEL@@|${model}|g" \
    -e "s|@@BASE_URL@@|${base_url}|g" \
    "$config_tpl" > "$config_dst"

  echo "seeded: $config_dst (provider=${provider}, default=${model})"
fi

# ─── 3. Mattermost 커스텀 브랜드 로고 시드 ────────────────────
# assets/logo.{png,jpg} 가 있으면 volumes/mattermost/data/brand/image.png 로 복사한다.
# 이미 brand/image 가 있으면 (= 시스템 콘솔에서 업로드한 경우) 건드리지 않는다.
brand_dir="volumes/mattermost/data/brand"
brand_dst="$brand_dir/image.png"

if [[ -f "$brand_dst" ]]; then
  echo "skip: $brand_dst already exists"
else
  src=""
  for cand in assets/logo.png assets/logo.jpg assets/logo.jpeg; do
    if [[ -f "$cand" ]]; then src="$cand"; break; fi
  done
  if [[ -n "$src" ]]; then
    mkdir -p "$brand_dir"
    cp "$src" "$brand_dst"
    echo "seeded: $brand_dst (from $src)"
  else
    echo "info: assets/logo.{png,jpg} 가 없어 로고 시드를 건너뜁니다. (System Console 에서 업로드 가능)"
  fi
fi

# ─── 4. Mattermost 볼륨 권한 (Linux 호스트) ──────────────────
# Mattermost 공식 이미지의 컨테이너 사용자 (UID:GID 2000:2000) 에 맞춘다.
# macOS 의 Docker Desktop 은 자동 매핑하므로 chown 은 생략한다.
if [[ "$(uname)" == "Linux" ]]; then
  echo "chown -R 2000:2000 volumes/mattermost (sudo 필요할 수 있음)"
  sudo chown -R 2000:2000 volumes/mattermost
fi

echo "done."
