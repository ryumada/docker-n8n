#!/bin/bash
# This script interactively prepares the .env file by reading a template,
# duplicating required variables, and saving it as a new .env file.

# Exit immediately if a command exits with a non-zero status.
set -e

# --- Logging Functions & Colors ---
# Define colors for log messages
readonly COLOR_RESET="\033[0m"
readonly COLOR_INFO="\033[0;34m"
readonly COLOR_SUCCESS="\033[0;32m"
readonly COLOR_WARN="\033[0;33m"
readonly COLOR_ERROR="\033[0;31m"

# Function to log messages with a specific color and emoji
log() {
    local color="$1"
    local emoji="$2"
    local message="$3"
    echo -e "${color}${emoji} ${message}${COLOR_RESET}"
}

log_info() { log "${COLOR_INFO}" "ℹ️" "$1"; }
log_success() { log "${COLOR_SUCCESS}" "✅" "$1"; }
log_warn() { log "${COLOR_WARN}" "⚠️" "$1"; }
log_error() { log "${COLOR_ERROR}" "❌" "$1"; }
# ------------------------------------

function main() {
    CURRENT_DIR=$(dirname "$(readlink -f "$0")")
    CURRENT_DIR_USER=$(stat -c '%U' "$CURRENT_DIR")
    PATH_TO_ROOT_REPOSITORY=$(sudo -u "$CURRENT_DIR_USER" git -C "$(dirname "$(readlink -f "$0")")" rev-parse --show-toplevel)
    # SERVICE_NAME=$(basename "$PATH_TO_ROOT_REPOSITORY")
    # REPOSITORY_OWNER=$(stat -c '%U' "$PATH_TO_ROOT_REPOSITORY")

    # --- Update env file from .env.example
    "$PATH_TO_ROOT_REPOSITORY/scripts/update_env_file.sh"

    # Define source and destination files relative to the script's location
    SOURCE_FILE="$PATH_TO_ROOT_REPOSITORY/.env"
    DEST_FILE="$PATH_TO_ROOT_REPOSITORY/.env" # We will append to the same file.

    # Define variable mappings.
    # Key: The new variable to create.
    # Value: The formula using other variables from the .env file.
    declare -A VARIABLE_MAPPINGS
    VARIABLE_MAPPINGS=(
    ["DB_POSTGRESDB_DATABASE"]='${POSTGRES_DB}'
    ["DB_POSTGRESDB_USER"]='${POSTGRES_USER}'
    ["DB_POSTGRESDB_PASSWORD"]='${POSTGRES_PASSWORD}'
    ["N8N_HOST"]='${SUBDOMAIN}.${DOMAIN_NAME}'
    ["WEBHOOK_URL"]='https://${SUBDOMAIN}.${DOMAIN_NAME}/'
    )
    # --------------------

    log_info "Starting .env file update process..."

    # Check if the source .env file exists
    if [ ! -f "$SOURCE_FILE" ]; then
        log_error "Error: Source file '$SOURCE_FILE' not found. Please ensure you've created it."
        exit 1
    fi

    # Add a header for the auto-generated variables, with a newline first for spacing
    echo -e "\n# --- Auto-generated variables for service compatibility (from generate-env.sh) ---" >> "$DEST_FILE"

    # Loop through each mapping defined in VARIABLE_MAPPINGS
    for DEST_VAR in "${!VARIABLE_MAPPINGS[@]}"; do
    FORMULA=${VARIABLE_MAPPINGS[$DEST_VAR]}
    EVALUATED_VALUE=$FORMULA
    ALL_VARS_FOUND=true

    # Find all variable placeholders like ${VAR} in the formula
    PLACEHOLDERS=$(echo "$FORMULA" | grep -o -E '\$\{[^}]+\}')

    for PLACEHOLDER in $PLACEHOLDERS; do
        # Extract the variable name from the placeholder, e.g., ${VAR_NAME} -> VAR_NAME
        SRC_VAR=$(echo "$PLACEHOLDER" | sed 's/\$//;s/{//;s/}//')

        # Get the value of the source variable from the .env file
        VALUE=$(grep -E "^${SRC_VAR}=" "$SOURCE_FILE" | cut -d'=' -f2-)

        if [ -n "$VALUE" ]; then
        # Substitute the placeholder with the actual value.
        # Using a different delimiter for sed to avoid issues with special characters.
        EVALUATED_VALUE=$(echo "$EVALUATED_VALUE" | sed "s|${PLACEHOLDER}|${VALUE}|g")
        else
        log_warn "Source variable '${SRC_VAR}' for '${DEST_VAR}' not found in '$SOURCE_FILE'. Skipping."
        ALL_VARS_FOUND=false
        break
        fi
    done

    # Only write the final variable if all its source components were found
    if [ "$ALL_VARS_FOUND" = true ]; then
        echo "${DEST_VAR}=${EVALUATED_VALUE}" >> "$DEST_FILE"
        log_success "Variable '${DEST_VAR}' was created."
    fi
    done

    echo ""
    log_success "🎉 Success! The '$DEST_FILE' file has been updated."
    log_info "You can now run 'docker stack deploy' from this directory."

}

main
