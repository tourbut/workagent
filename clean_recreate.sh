#!/bin/sh

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
    echo "  sh clean_recreate.sh"
    echo "  or"
    echo "  ./clean_recreate.sh"
    echo "=================================================="
    return 1 2>/dev/null || exit 1
fi

set -e

# 1. Load environment variables from .env if it exists
if [ -f .env ]; then
    # Load env variables safely preserving spaces (like COMPOSE_COMMAND="podman compose")
    set -a
    . ./.env
    set +a
fi

# 2. Set default values if not specified in .env
CONTAINER_ENGINE=${CONTAINER_ENGINE:-podman}
COMPOSE_COMMAND=${COMPOSE_COMMAND:-podman compose}
COMPOSE_FILE=${COMPOSE_FILE:-podman-compose.yml}

echo "=== [1/5] Loading configurations ==="
echo "Container Engine: $CONTAINER_ENGINE"
echo "Compose Command: $COMPOSE_COMMAND"
echo "Compose File: $COMPOSE_FILE"

# 3. Stop and remove active containers (strictly avoiding -v to prevent data loss)
echo "\n=== [2/5] Stopping and removing containers ==="
$COMPOSE_COMMAND -f $COMPOSE_FILE down

# 4. Cleanup unused/dangling resources safely
echo "\n=== [3/5] Cleaning up unused data and caches ==="
echo "Cleaning up stopped containers..."
$CONTAINER_ENGINE container prune -f

echo "Cleaning up dangling images..."
$CONTAINER_ENGINE image prune -f

echo "Cleaning up unused networks..."
$CONTAINER_ENGINE network prune -f

# 5. Bring the stack up again in background mode
echo "\n=== [4/5] Starting compose stack ==="
$COMPOSE_COMMAND -f $COMPOSE_FILE up -d

# 6. Apply initial configurations (session_reset.mode, etc.)
echo "\n=== [5/5] Re-applying configuration options ==="
if [ -f "./init_config.sh" ]; then
    # 실행 권한이 누락된 원격 서버 환경을 위해 sh 인터프리터로 직접 실행
    sh ./init_config.sh
else
    echo "Warning: init_config.sh not found. Skipping config application."
fi

echo "\nClean Recreate completed successfully!"
