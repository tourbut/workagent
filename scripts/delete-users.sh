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
    echo "  sh scripts/delete-users.sh"
    echo "=================================================="
    return 1 2>/dev/null || exit 1
fi

set -e

# 1. Load environment variables from .env if it exists
if [ -f .env ]; then
    set -a
    . ./.env
    set +a
elif [ -f ../.env ]; then
    set -a
    . ../.env
    set +a
fi

CONTAINER_ENGINE=${CONTAINER_ENGINE:-podman}
USER_CSV=${1:-"sandbox/init-mattermost-user.csv"}

if [ ! -f "$USER_CSV" ]; then
    echo "ERROR: CSV file '$USER_CSV' not found!"
    exit 1
fi

echo "=================================================="
# Resolve the running Mattermost container ID dynamically
echo "Resolving Mattermost container ID..."
MATTERMOST_CONTAINER_ID=$($CONTAINER_ENGINE ps --filter "name=mattermost" -q | head -n 1 | tr -d '\r\n')

if [ -z "$MATTERMOST_CONTAINER_ID" ]; then
    echo "ERROR: Mattermost container could not be found via native '$CONTAINER_ENGINE ps'."
    exit 1
fi
echo "Resolved Mattermost container ID: $MATTERMOST_CONTAINER_ID"
echo "=================================================="

# Helper function to run mmctl
run_mm_cli() {
    $CONTAINER_ENGINE exec -i "$MATTERMOST_CONTAINER_ID" /mattermost/bin/mmctl --local "$@" </dev/null
}

# 2. Temporarily enable API user deletion (required by mmctl)
echo "Enabling permanent user deletion API setting..."
run_mm_cli config set ServiceSettings.EnableAPIUserDeletion true

# 3. Read usernames from CSV and delete them
echo "\nDeleting users listed in $USER_CSV..."
tail -n +2 "$USER_CSV" | while IFS=, read -r csv_email csv_username csv_password csv_is_admin csv_first_name csv_last_name csv_position; do
    # Clean carriage returns and spaces
    csv_username=$(echo "$csv_username" | tr -d '\r\n ')
    
    [ -z "$csv_username" ] && continue

    echo "Checking if user '$csv_username' exists..."
    if run_mm_cli user show "$csv_username" >/dev/null 2>&1; then
        echo "Permanently deleting user '$csv_username'..."
        run_mm_cli user delete "$csv_username" --confirm
        echo "User '$csv_username' deleted successfully!"
    else
        echo "User '$csv_username' does not exist. Skipping."
    fi
done

# 4. Restore API user deletion setting to false (for security)
echo "\nRestoring permanent user deletion API setting to false..."
run_mm_cli config set ServiceSettings.EnableAPIUserDeletion false

echo "=================================================="
echo "Cleanup completed successfully!"
echo "=================================================="
