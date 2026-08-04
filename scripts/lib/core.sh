#!/bin/bash
set -uo pipefail

# ============================================================================
# Core library: colors, logging and small shared helpers.
# Sourced by common.sh (via the lib loader). Every function defined here is
# guaranteed to be available to all step scripts.
# ============================================================================

# Theme colors — single source of truth for all UI output
if [ -z "${THEME_PRIMARY:-}" ]; then
  readonly THEME_PRIMARY='\033[1;34m'
  readonly THEME_SECONDARY='\033[0;34m'
  readonly THEME_TEXT='\033[0;37m'
  readonly THEME_TEXT_BOLD='\033[1;37m'
  readonly THEME_SUCCESS='\033[0;32m'
  readonly THEME_WARN='\033[0;33m'
  readonly THEME_ERROR='\033[0;31m'
  readonly THEME_MUTED='\033[2m'
  readonly THEME_HIGHLIGHT='\033[1;34m'
  readonly THEME_BORDER='\033[1;34m'
  readonly THEME_HEADER='\033[1;34m'
fi

# Gum color mappings for blue/white theme
if [ -z "${GUM_PRIMARY:-}" ]; then
  readonly GUM_PRIMARY="26"
  readonly GUM_SECONDARY="39"
  readonly GUM_TEXT="15"
  readonly GUM_SUCCESS="46"
  readonly GUM_WARN="226"
  readonly GUM_ERROR="196"
  readonly GUM_MUTED="8"
  readonly GUM_HEADER="26"
  readonly GUM_BORDER="26"
fi

# ===== Logging =====

# Rotate old log files (keep last 3 backups)
rotate_logs() {
    local log="$INSTALL_LOG"
    for i in 3 2 1; do
        [ -f "${log}.$((i-1))" ] && mv -f "${log}.$((i-1))" "${log}.${i}" 2>/dev/null || true
    done
    [ -f "$log" ] && mv -f "$log" "${log}.1" 2>/dev/null || true
}

# Initialize logging (rotate + fresh header)
init_logging() {
    mkdir -p "$(dirname "$INSTALL_LOG")" 2>/dev/null || true
    rotate_logs
    touch "$INSTALL_LOG" 2>/dev/null || true
    echo "=== Fedora Installer Log - $(date) ===" >> "$INSTALL_LOG"
}

# Append a raw line to the installation log
log_to_file() {
    local message="$1"
    echo "$message" >> "$INSTALL_LOG" 2>/dev/null || true
}

# Echo (with escapes) and append to the log
log() {
    echo -e "$1" | tee -a "$INSTALL_LOG"
}

print_info()    { echo -e "\n${BLUE}[INFO] $1${RESET}" | tee -a "$INSTALL_LOG"; }
print_success() { echo -e "\n${GREEN}[SUCCESS] $1${RESET}" | tee -a "$INSTALL_LOG"; }
print_warning() { echo -e "\n${YELLOW}[WARNING] $1${RESET}" | tee -a "$INSTALL_LOG"; }
print_error()   { echo -e "\n${RED}[ERROR] $1${RESET}" | tee -a "$INSTALL_LOG"; ERRORS+=("$1"); }

# Step counter/header (used by step scripts)
step() {
    local msg="$1"
    echo -e "\n${BLUE}[$CURRENT_STEP/$TOTAL_STEPS] $msg${RESET}" | tee -a "$INSTALL_LOG"
    log_to_file "Step $CURRENT_STEP: $msg"
    ((CURRENT_STEP++))
}

# Log success/warning/error/info (console + log file)
log_success() {
    local message="$1"
    local context="${2:-}"
    echo -e "${GREEN}$message${RESET}" | tee -a "$INSTALL_LOG"
    if [ -n "$context" ]; then
        echo -e "${CYAN}  Details: $context${RESET}" | tee -a "$INSTALL_LOG"
    fi
}

log_warning() {
    local message="$1"
    local context="${2:-}"
    echo -e "${YELLOW}! $message${RESET}" | tee -a "$INSTALL_LOG"
    if [ -n "$context" ]; then
        echo -e "  Note: $context" | tee -a "$INSTALL_LOG"
    fi
}

log_error() {
    local message="$1"
    local hint="${2:-}"
    echo -e "${RED}$message${RESET}" | tee -a "$INSTALL_LOG"
    if [ -n "$hint" ]; then
        echo -e "  Tip: $hint" | tee -a "$INSTALL_LOG"
    fi
    ERRORS+=("$message")
}

log_info() {
    echo -e "${CYAN}$1${RESET}" | tee -a "$INSTALL_LOG"
}

# Debug message (only shown in verbose mode)
log_debug() {
    local message="$1"
    local detail="${2:-}"
    if [ "${VERBOSE:-false}" = true ]; then
        echo -e "${THEME_MUTED}[DEBUG] $message${RESET}"
        log_to_file "DEBUG: $message"
        if [ -n "$detail" ]; then
            log_to_file "  DETAIL: $detail"
        fi
    fi
}

# ===== Shared helpers =====

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Format a number of seconds as a human readable duration (e.g. "5m 3s")
format_time() {
    local seconds=$1
    if [ $seconds -lt 60 ]; then
        echo "${seconds}s"
    elif [ $seconds -lt 3600 ]; then
        local minutes=$((seconds / 60))
        local remaining_seconds=$((seconds % 60))
        echo "${minutes}m ${remaining_seconds}s"
    else
        local hours=$((seconds / 3600))
        local minutes=$(((seconds % 3600) / 60))
        echo "${hours}h ${minutes}m"
    fi
}

# Performance tracking (uses INSTALLATION_START_TIME, set by install.sh)
log_performance() {
    local step_name="$1"
    local current_time=$(date +%s)
    local elapsed=$((current_time - INSTALLATION_START_TIME))
    local minutes=$((elapsed / 60))
    local seconds=$((elapsed % 60))

    # Special formatting for total installation time
    if [[ "$step_name" == "Total installation time" ]]; then
        echo -e "\n${YELLOW}═══════════════════════════════════════════════════════════════${RESET}"
        echo -e "${CYAN}⏱️  INSTALLATION TIME SUMMARY${RESET}"
        echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${RESET}"
        echo -e "${GREEN}🎯 Total Installation Time: ${YELLOW}${minutes}m ${seconds}s${RESET}"
        echo -e "${CYAN}📊 Total Seconds: ${YELLOW}${elapsed}s${RESET}"
        echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${RESET}\n"
    else
        echo -e "${CYAN}$step_name completed in ${minutes}m ${seconds}s (${elapsed}s)${RESET}"
    fi
}
