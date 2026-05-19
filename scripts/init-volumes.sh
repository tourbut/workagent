#!/usr/bin/env bash
# 데이터 볼륨 디렉터리를 미리 생성하고 hermes-agent config.yaml 을 시드한다.
# - Mattermost 컨테이너는 일부 디렉터리가 없으면 권한 문제로 부팅에 실패할 수 있다.
# - hermes-agent 는 /opt/data/config.yaml 에서 model/provider 를 읽으므로 첫 실행 전에 만들어 둔다.
# - 본 스크립트는 멱등이다 (이미 있으면 건드리지 않는다).
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

# ─── 3. Mattermost 볼륨 권한 (Linux 호스트) ──────────────────
# Mattermost 공식 이미지의 컨테이너 사용자 (UID:GID 2000:2000) 에 맞춘다.
# macOS 의 Docker Desktop 은 자동 매핑하므로 chown 은 생략한다.
if [[ "$(uname)" == "Linux" ]]; then
  echo "chown -R 2000:2000 volumes/mattermost (sudo 필요할 수 있음)"
  sudo chown -R 2000:2000 volumes/mattermost
fi

echo "done."
