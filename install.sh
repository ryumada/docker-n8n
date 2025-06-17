#!/bin/bash

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
    echo -e "${color}[$(date +"%Y-%m-%d %H:%M:%S")] ${emoji} ${message}${COLOR_RESET}"
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
  SERVICE_NAME=$(basename "$PATH_TO_ROOT_REPOSITORY")
  REPOSITORY_OWNER=$(stat -c '%U' "$PATH_TO_ROOT_REPOSITORY")

  log_info "Update env file."
  "$PATH_TO_ROOT_REPOSITORY/scripts/update_env_file.sh"
  log_success "Update env file completed"

  local ENV_FILE="${PATH_TO_ROOT_REPOSITORY}/.env"

  log_info "Validate .env file content"
  if grep -q "enter-" "$ENV_FILE"; then
    log_error "Your .env file still contains default placeholder values."
    grep "enter-" "$ENV_FILE" | while read -r line ; do
      log_error "  - Please configure: ${line}"
    done
    log_error "Exiting. Please update the .env file and re-run the script again."
    exit 1
  fi
  log_success "Validate .env file content completed"

  log_info "Reading variables from ${ENV_FILE} to prepare for substitution..."
  # Create a string of 'sed' expressions. Example: s|\${VAR1}|val1|g;s|\${VAR2}|val2|g;
  local SED_EXPRESSIONS=""
  # Source .env file to load its variables into the current shell
  # This makes complex variable substitutions possible
  set -a # automatically export all variables
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  set +a # Stop automatically exporting variables

  # Read variables again for simple replacement
  while IFS='=' read -r key value || [[ -n "$key" ]]; do
    # Ignore blank lines and comments
    if [[ -n "$key" && ! "$key" =~ ^# ]]; then
      # Escape characters that are special to sed's replacement string
      # This handles characters like /, &, etc. safely.
      value_escaped=$(printf '%s\n' "$value" | sed -e 's/[&\\/]/\\&/g')

      # Add a complete '-e' argument to our array for each variable
      sed_args+=(-e "s|\${${key}}|${value_escaped}|g")
    fi
  done < "$ENV_FILE"

  # --- Step 3: Find and process compose files ---
  log_info "Finding and processing all 'docker-compose.yml' files..."
  find "$PATH_TO_ROOT_REPOSITORY" -type f -name "docker-compose.yml.example" | while read -r COMPOSE_FILE; do
    local DIR
    DIR=$(dirname "$COMPOSE_FILE")
    local PROD_FILE="${DIR}/docker-compose.yml"

    log_info "Processing -> ${COMPOSE_FILE}"

    # Execute sed with the array of expressions. The shell will expand the array safely.
    sed "${sed_args[@]}" "$COMPOSE_FILE" > "$PROD_FILE"
    chown "$REPOSITORY_OWNER": "$PROD_FILE"

    log_success "  └─ Created deployable file: ${PROD_FILE}"
  done

  echo ""
  log_success "🎉 All compose files have been processed successfully!"
  log_info "You can now use the *.yml files for your 'docker stack deploy' commands."
}

main
