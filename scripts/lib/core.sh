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

# Initialize core subsystems (logging). Called once by install.sh.
init_core() {
    init_logging
}

# Append a raw line to the installation log
log_to_file() {
    local message="$1"
    echo "$message" >> "$INSTALL_LOG" 2>/dev/null || true
}

# Append a raw line to the installation log — printf %(...)T formatting via
# the shell builtin: zero `date` forks; log_to_file fires for every message.
log_to_file() {
    local message="${1:-}"
    [[ -n "$message" ]] || return 0
    printf '[%(%Y-%m-%d %H:%M:%S)T] %s\n' -1 "$message" >> "$INSTALL_LOG" 2>/dev/null || true
}

# stdout discipline shared by ALL messaging helpers:
#   - colored emit only when stdout is a real TTY (checked at emit time, not
#     load time — install phases redirect stdout mid-run);
#   - plain text when piped/redirected — INSTALL_LOG must stay ANSI-free;
#   - the plain text is additionally appended to INSTALL_LOG, timestamped.
# (The old `echo -e COLOR | tee -a` helpers put raw escapes into the log
# whenever colors had been enabled at load.)
__emit() {
    local color="${1:-}"
    local plain="${2:-}"
    log_to_file "$plain"
    if [[ -t 1 ]]; then
        printf '%b\n' "${color}${plain}${RESET}"
    else
        printf '%s\n' "$plain"
    fi
}

log() { __emit "" "$1"; }

print_info()    { __emit "$BLUE"    "[INFO] $1"; }
print_success() { __emit "$GREEN"   "[SUCCESS] $1"; }
print_warning() { __emit "$YELLOW"  "[WARNING] $1"; }
print_error()   { __emit "$RED"     "[ERROR] $1"; ERRORS+=("$1"); }

# Step counter/header (used by step scripts)
step() {
    local msg="$1"
    __emit "$BLUE" "[$CURRENT_STEP/$TOTAL_STEPS] $msg"
    ((CURRENT_STEP++))
}

# Log success/warning/error/info (console + log file)
log_success() {
    local message="${1:-}"
    local context="${2:-}"
    __emit "$GREEN" "$message"
    [ -n "$context" ] && __emit "$CYAN" "  Details: $context"
}

log_warning() {
    local message="${1:-}"
    local context="${2:-}"
    __emit "$YELLOW" "! $message"
    [ -n "$context" ] && __emit "" "  Note: $context"
}

log_error() {
    local message="${1:-}"
    local hint="${2:-}"
    __emit "$RED" "$message"
    [ -n "$hint" ] && __emit "" "  Tip: $hint"
    ERRORS+=("$message")
}

log_info() {
    __emit "$CYAN" "$1"
}

# Debug message (only shown in verbose mode)
log_debug() {
    local message="$1"
    local detail="${2:-}"
    if [ "${VERBOSE:-false}" = true ]; then
        if [[ -t 1 ]]; then
            printf '\n%b\n' "${THEME_MUTED}[DEBUG] $message${RESET}"
        else
            printf '\n[DEBUG] %s\n' "$message"
        fi
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
