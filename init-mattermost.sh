#!/bin/sh
set -e

# Mattermost Bootstrapping & AI Bot Automagic Config Script
# Supports both Docker and Podman environments.

# 1. Load environment variables from .env if it exists
if [ -f .env ]; then
    # Load env variables safely preserving spaces
    set -a
    . ./.env
    set +a
fi

# 2. Set container defaults if not specified in .env
CONTAINER_ENGINE=${CONTAINER_ENGINE:-podman}
COMPOSE_COMMAND=${COMPOSE_COMMAND:-podman compose}
COMPOSE_FILE=${COMPOSE_FILE:-podman-compose.yml}

# 3. Setup configurations and credentials (feel free to customize)
INITIAL_ADMIN_USERNAME=${INITIAL_ADMIN_USERNAME:-admin}
INITIAL_ADMIN_EMAIL=${INITIAL_ADMIN_EMAIL:-admin@example.com}
INITIAL_ADMIN_PASSWORD=${INITIAL_ADMIN_PASSWORD:-AdminPassword123!}

BOT_USERNAME=${BOT_USERNAME:-hermes}
BOT_DISPLAY_NAME=${BOT_DISPLAY_NAME:-"Hermes Agent"}
BOT_DESCRIPTION=${BOT_DESCRIPTION:-"AI Agent bot for WorkAgent"}

# Utility to update .env variable cross-platform (macOS vs Linux)
update_env_var() {
    VAR_KEY=$1
    VAR_VAL=$2
    if [ -f .env ]; then
        if grep -q "^${VAR_KEY}=" .env; then
            if [ "$(uname)" = "Darwin" ]; then
                sed -i '' "s|^${VAR_KEY}=.*|${VAR_KEY}=${VAR_VAL}|g" .env
            else
                sed -i "s|^${VAR_KEY}=.*|${VAR_KEY}=${VAR_VAL}|g" .env
            fi
        else
            echo "${VAR_KEY}=${VAR_VAL}" >> .env
        fi
        echo "Successfully updated ${VAR_KEY} in .env"
    else
        echo "WARNING: .env not found. Please set ${VAR_KEY}=${VAR_VAL} manually."
    fi
}

echo "=================================================="
echo "Initializing Mattermost & AI Gateway Configuration"
echo "Container Engine: $CONTAINER_ENGINE"
echo "Compose Command:  $COMPOSE_COMMAND"
echo "Compose File:     $COMPOSE_FILE"
echo "=================================================="

# Ensure the core services are running
echo "Checking if database & Mattermost are running..."
$COMPOSE_COMMAND -f $COMPOSE_FILE up -d postgres mattermost

# 4. Wait for Mattermost to be ready and responsive
echo "Waiting for Mattermost API server to be healthy on port ${MATTERMOST_PORT:-8065}..."
PORT_TO_CHECK=${MATTERMOST_PORT:-8065}
until curl -fsS "http://localhost:${PORT_TO_CHECK}/api/v4/system/ping" >/dev/null 2>&1; do
    echo "Mattermost is starting up or migrations are in progress... Retrying in 5 seconds."
    sleep 5
done
echo "Mattermost is healthy and online!"

# Resolve the actual running container ID dynamically using native container engine filtering
echo "Resolving Mattermost container ID..."
MATTERMOST_CONTAINER_ID=$($CONTAINER_ENGINE ps --filter "name=mattermost" -q | head -n 1 | tr -d '\r\n')

if [ -z "$MATTERMOST_CONTAINER_ID" ]; then
    echo "ERROR: Mattermost container could not be found via native '$CONTAINER_ENGINE ps'."
    exit 1
fi
echo "Resolved Mattermost container ID: $MATTERMOST_CONTAINER_ID"

# Wrapper to execute Mattermost CLI internally using native container engine exec with mmctl local auth
# Redirects stdin to /dev/null to prevent interactive container commands from hijacking the shell pipe stream.
run_mm_cli() {
    $CONTAINER_ENGINE exec -i "$MATTERMOST_CONTAINER_ID" /mattermost/bin/mmctl --local "$@" </dev/null
}

echo ""
echo "=================================================="
echo "Step 1: User Provisioning"
echo "=================================================="

USER_CSV="init-mattermost-user.csv"

# Function to safely create a user
create_user_safely() {
    EMAIL=$1
    USERNAME=$2
    PASSWORD=$3
    IS_ADMIN=$4
    FIRST_NAME=$5
    LAST_NAME=$6

    if run_mm_cli user search "$EMAIL" >/dev/null 2>&1 || run_mm_cli user search "$USERNAME" >/dev/null 2>&1; then
        echo "User '$USERNAME' ($EMAIL) already exists. Skipping creation."
    else
        echo "Creating user '$USERNAME' (System Admin: $IS_ADMIN, First Name: '$FIRST_NAME', Last Name: '$LAST_NAME')..."
        
        if [ -n "$FIRST_NAME" ] && [ -n "$LAST_NAME" ]; then
            if [ "$IS_ADMIN" = "true" ]; then
                run_mm_cli user create \
                    --email "$EMAIL" \
                    --username "$USERNAME" \
                    --password "$PASSWORD" \
                    --system-admin \
                    --firstname "$FIRST_NAME" \
                    --lastname "$LAST_NAME"
            else
                run_mm_cli user create \
                    --email "$EMAIL" \
                    --username "$USERNAME" \
                    --password "$PASSWORD" \
                    --firstname "$FIRST_NAME" \
                    --lastname "$LAST_NAME"
            fi
        elif [ -n "$FIRST_NAME" ]; then
            if [ "$IS_ADMIN" = "true" ]; then
                run_mm_cli user create \
                    --email "$EMAIL" \
                    --username "$USERNAME" \
                    --password "$PASSWORD" \
                    --system-admin \
                    --firstname "$FIRST_NAME"
            else
                run_mm_cli user create \
                    --email "$EMAIL" \
                    --username "$USERNAME" \
                    --password "$PASSWORD" \
                    --firstname "$FIRST_NAME"
            fi
        else
            if [ "$IS_ADMIN" = "true" ]; then
                run_mm_cli user create \
                    --email "$EMAIL" \
                    --username "$USERNAME" \
                    --password "$PASSWORD" \
                    --system-admin
            else
                run_mm_cli user create \
                    --email "$EMAIL" \
                    --username "$USERNAME" \
                    --password "$PASSWORD"
            fi
        fi
        echo "User '$USERNAME' created successfully!"
    fi
}

if [ -f "$USER_CSV" ]; then
    echo "Found CSV user list '$USER_CSV'. Bootstrapping bulk users..."
    tail -n +2 "$USER_CSV" | while IFS=, read -r csv_email csv_username csv_password csv_is_admin csv_first_name csv_last_name; do
        # Clean carriage returns and spaces
        csv_email=$(echo "$csv_email" | tr -d '\r\n ')
        csv_username=$(echo "$csv_username" | tr -d '\r\n ')
        csv_password=$(echo "$csv_password" | tr -d '\r\n ')
        csv_is_admin=$(echo "$csv_is_admin" | tr -d '\r\n ' | tr '[:upper:]' '[:lower:]')
        csv_first_name=$(echo "$csv_first_name" | tr -d '\r\n ')
        csv_last_name=$(echo "$csv_last_name" | tr -d '\r\n ')

        [ -z "$csv_username" ] && continue

        create_user_safely "$csv_email" "$csv_username" "$csv_password" "$csv_is_admin" "$csv_first_name" "$csv_last_name"
    done
else
    echo "CSV user list '$USER_CSV' not found. Bootstrapping fallback default Admin user..."
    create_user_safely "$INITIAL_ADMIN_EMAIL" "$INITIAL_ADMIN_USERNAME" "$INITIAL_ADMIN_PASSWORD" "true" "" ""
fi

echo ""
echo "=================================================="
echo "Step 4: Enabling Bot Accounts & Access Tokens"
echo "=================================================="
echo "Configuring Mattermost to allow Bot integration..."
run_mm_cli config set ServiceSettings.EnableBotAccountCreation true
run_mm_cli config set ServiceSettings.EnableUserAccessTokens true

echo ""
echo "=================================================="
echo "Step 5: Hermes Bot Account Setup"
echo "=================================================="
if run_mm_cli user search "$BOT_USERNAME" >/dev/null 2>&1; then
    echo "Bot user '$BOT_USERNAME' already exists. Skipping creation."
else
    echo "Creating bot account '$BOT_USERNAME'..."
    run_mm_cli bot create "$BOT_USERNAME" "$BOT_DISPLAY_NAME" "$BOT_DESCRIPTION" --system-admin
    echo "Bot account created successfully!"
fi


echo ""
echo "=================================================="
echo "Step 6: Automagic Token Sync"
echo "=================================================="
CURRENT_TOKEN=$(grep -E "^MATTERMOST_TOKEN=" .env 2>/dev/null | cut -d'=' -f2- || echo "")

if [ -z "$CURRENT_TOKEN" ] || [ "$CURRENT_TOKEN" = "changeme-bot-token" ] || [ "$CURRENT_TOKEN" = "changeme-token" ]; then
    echo "Generating new Personal Access Token for bot '$BOT_USERNAME'..."
    TOKEN_OUTPUT=$(run_mm_cli user token generate "$BOT_USERNAME" "Hermes AI Agent Access Token" 2>&1)
    
    # Parse the 26 character alphanumeric token
    NEW_TOKEN=$(echo "$TOKEN_OUTPUT" | grep -i "Token:" | awk '{print $2}' | tr -d '\r\n')
    
    if [ -n "$NEW_TOKEN" ]; then
        echo "Token generated: ${NEW_TOKEN%${NEW_TOKEN#????}}******************" # Secure logging
        update_env_var "MATTERMOST_TOKEN" "$NEW_TOKEN"
    else
        echo "ERROR: Failed to extract token from output:"
        echo "$TOKEN_OUTPUT"
    fi
else
    echo "MATTERMOST_TOKEN is already custom configured. Skipping token generation."
fi

echo ""
echo "=================================================="
echo "Step 7: Admin ID Permission Synchronization"
echo "=================================================="

# Resolve the target admin username to whitelist
TARGET_ADMIN_USERNAME=""
if [ -f "$USER_CSV" ]; then
    # Find the first user in the CSV with system_admin=true
    TARGET_ADMIN_USERNAME=$(tail -n +2 "$USER_CSV" | while IFS=, read -r _ username _ is_admin; do
        is_admin=$(echo "$is_admin" | tr -d '\r\n ' | tr '[:upper:]' '[:lower:]')
        if [ "$is_admin" = "true" ]; then
            echo "$username" | tr -d '\r\n '
            break
        fi
    done)
fi

# Fallback to default admin username if no admin found in CSV
if [ -z "$TARGET_ADMIN_USERNAME" ]; then
    TARGET_ADMIN_USERNAME="$INITIAL_ADMIN_USERNAME"
fi

ADMIN_ID=$(run_mm_cli user show "$TARGET_ADMIN_USERNAME" 2>/dev/null | grep -i "Id:" | awk '{print $2}' | tr -d '\r\n')
if [ -n "$ADMIN_ID" ]; then
    echo "Resolved Target Admin ($TARGET_ADMIN_USERNAME) ID: $ADMIN_ID"
    CURRENT_ALLOWED=$(grep -E "^MATTERMOST_ALLOWED_USERS=" .env 2>/dev/null | cut -d'=' -f2- || echo "")
    if [ -z "$CURRENT_ALLOWED" ] || [ "$CURRENT_ALLOWED" = "changeme-user-id" ]; then
        update_env_var "MATTERMOST_ALLOWED_USERS" "$ADMIN_ID"
    else
        echo "MATTERMOST_ALLOWED_USERS is already custom configured. Skipping user whitelist injection."
    fi
else
    echo "WARNING: Could not resolve Admin ID for '$TARGET_ADMIN_USERNAME'."
fi

echo ""
echo "=================================================="
echo "Initialization Complete!"
echo "=================================================="
echo "You can now log in to Mattermost with the following:"
echo "Site URL:      ${MM_SERVICESETTINGS_SITEURL:-http://localhost:8065}"
echo "Admin User:    $INITIAL_ADMIN_USERNAME"
echo "Admin Pass:    $INITIAL_ADMIN_PASSWORD"
echo "Admin Email:   $INITIAL_ADMIN_EMAIL"
echo ""
echo "Hermes bot is set up, whitelisted, and tokenized."
echo "You can now safely restart the stacks or start hermes-agent:"
echo "  $COMPOSE_COMMAND --profile hermes up -d --force-recreate"
echo "=================================================="
