#!/bin/sh
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
