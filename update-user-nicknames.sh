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
    echo "  sh update-user-nicknames.sh"
    echo "  or"
    echo "  ./update-user-nicknames.sh"
    echo "=================================================="
    return 1 2>/dev/null || exit 1
fi

set -e

# 1. Load environment variables from .env if it exists
if [ -f .env ]; then
    # Load env variables safely preserving spaces
    set -a
    . ./.env
    set +a
fi

# 2. Set default values if not specified in .env
CONTAINER_ENGINE=${CONTAINER_ENGINE:-podman}
COMPOSE_COMMAND=${COMPOSE_COMMAND:-podman compose}
COMPOSE_FILE=${COMPOSE_FILE:-podman-compose.yml}
POSTGRES_USER=${POSTGRES_USER:-mmuser}
POSTGRES_DB=${POSTGRES_DB:-mattermost}

echo "=================================================="
echo "Updating Mattermost User Nicknames from CSV"
echo "Container Engine: $CONTAINER_ENGINE"
echo "Compose File:     $COMPOSE_FILE"
echo "=================================================="

# 3. Resolve the Postgres container ID dynamically using native container engine filtering
echo "Resolving Postgres container ID..."
POSTGRES_CONTAINER_ID=$($CONTAINER_ENGINE ps --filter "name=postgres" -q | head -n 1 | tr -d '\r\n')

if [ -z "$POSTGRES_CONTAINER_ID" ]; then
    echo "ERROR: Postgres container could not be found via '$CONTAINER_ENGINE ps'."
    echo "Please ensure the Postgres container is running."
    exit 1
fi
echo "Resolved Postgres container ID: $POSTGRES_CONTAINER_ID"

USER_CSV="init-mattermost-user.csv"

if [ ! -f "$USER_CSV" ]; then
    echo "ERROR: User CSV file '$USER_CSV' not found!"
    exit 1
fi

echo "Found CSV user list '$USER_CSV'. Updating nicknames..."
tail -n +2 "$USER_CSV" | while IFS=, read -r csv_email csv_username csv_password csv_is_admin csv_first_name csv_last_name csv_position csv_nickname; do
    # Clean carriage returns and spaces
    csv_username=$(echo "$csv_username" | tr -d '\r\n ')
    csv_first_name=$(echo "$csv_first_name" | tr -d '\r\n ')
    csv_last_name=$(echo "$csv_last_name" | tr -d '\r\n ')
    csv_nickname=$(echo "$csv_nickname" | tr -d '\r\n ')

    [ -z "$csv_username" ] && continue

    # Fallback to last_name + first_name if nickname column is empty
    if [ -z "$csv_nickname" ]; then
        csv_nickname="${csv_last_name}${csv_first_name}"
    fi

    if [ -n "$csv_nickname" ]; then
        echo "Updating nickname for '$csv_username' to '$csv_nickname'..."
        $CONTAINER_ENGINE exec -i "$POSTGRES_CONTAINER_ID" psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -c "UPDATE users SET nickname = '$csv_nickname' WHERE username = '$csv_username';" </dev/null >/dev/null 2>&1 || echo "WARNING: Failed to update nickname for user '$csv_username'."
    fi
done

echo "Successfully completed nickname updates!"
