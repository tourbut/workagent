#!/bin/sh
set -e

# 1. Load environment variables from .env if it exists
if [ -f .env ]; then
    # Load env variables, skipping comments and blank lines
    export $(grep -v '^#' .env | xargs)
fi

# 2. Set default values if not specified in .env
CONTAINER_ENGINE=${CONTAINER_ENGINE:-podman}
COMPOSE_COMMAND=${COMPOSE_COMMAND:-podman compose}
COMPOSE_FILE=${COMPOSE_FILE:-podman-compose.yml}
HERMES_SESSION_RESET_MODE=${HERMES_SESSION_RESET_MODE:-none}
HERMES_INFERENCE_MODEL=${HERMES_INFERENCE_MODEL:-google/gemini-3.5-flash}

echo "Using Container Engine: $CONTAINER_ENGINE"
echo "Using Compose Command: $COMPOSE_COMMAND"
echo "Using Compose File: $COMPOSE_FILE"
echo "Session Reset Mode: $HERMES_SESSION_RESET_MODE"
echo "Inference Model: $HERMES_INFERENCE_MODEL"

# 3. Startup the hermes-agent service if not already running (to create default volumes)
echo "Starting hermes-agent..."
$COMPOSE_COMMAND -f $COMPOSE_FILE up -d --no-deps hermes-agent

# 4. Wait a brief moment for the container to become available (if starting fresh)
sleep 2

# 5. Apply session_reset.mode using exec safely (using -i instead of -it to avoid TTY issues)
echo "Applying session_reset.mode=$HERMES_SESSION_RESET_MODE to hermes-agent..."
$CONTAINER_ENGINE exec -i hermes-agent hermes config set session_reset.mode "$HERMES_SESSION_RESET_MODE"

# 6. Apply model.default using exec safely
echo "Applying model.default=$HERMES_INFERENCE_MODEL to hermes-agent..."
$CONTAINER_ENGINE exec -i hermes-agent hermes config set model.default "$HERMES_INFERENCE_MODEL"

echo "Configuration completed successfully!"
