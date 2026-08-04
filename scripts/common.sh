#!/bin/bash
set -uo pipefail

# ============================================================================
# common.sh — bootstrap entry point.
#
# This file defines only the shared environment (paths, flags, globals) and
# then loads the actual implementation from the lib/ modules:
#
#   lib/core.sh     logging + small shared helpers
#   lib/ui.sh       menus, prompts, banners, messaging helpers
#   lib/system.sh   CPU/GPU/laptop/bootloader/SSD detection (cached)
#   lib/package.sh  DNF / Flatpak package installation
#   lib/config.sh   YAML helpers (yq)
#   lib/state.sh    progress tracking, resume, error handling, reboot
#   lib/dashboard.sh dashboard wizard UI
#
# Every script (install.sh and the step scripts) should source this file.
# ============================================================================

# ============================================================================
# COLOR VARIABLES
# ============================================================================

# Legacy color variables for output formatting (kept for compatibility)
if [ -t 1 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[1;34m'
    CYAN='\033[1;34m'
    MAGENTA='\033[0;35m'
    WHITE='\033[0;37m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    MAGENTA=''
    WHITE=''
    BOLD=''
    RESET=''
fi

# Terminal formatting helpers
TERM_WIDTH=$(tput cols 2>/dev/null || echo 80)
TERM_HEIGHT=$(tput lines 2>/dev/null || echo 24)

# Force gum to use colors
export GUM_COLOR=always
export FORCE_COLOR=1
export CLICOLOR_FORCE=1

# ============================================================================
# GLOBAL STATE
# ============================================================================

# Global arrays and variables
ERRORS=()                   # Collects error messages for summary
CURRENT_STEP=1              # Tracks current step for progress display
INSTALLED_PACKAGES=()       # Tracks installed packages
REMOVED_PACKAGES=()         # Tracks removed packages
FAILED_PACKAGES=()          # Tracks packages that failed to install

# Timing and progress tracking
STEP_TIMES=()               # Tracks time for each step
STEP_START_TIME=0           # Start time of current step
INSTALLATION_START_TIME=0   # Overall installation start time

# UI/Flow configuration
TOTAL_STEPS=10
: "${VERBOSE:=false}"   # Can be overridden/exported by caller
: "${DRY_RUN:=false}"

# Global installation success tracking
INSTALLATION_SUCCESS=true
SUDO_KEEPALIVE_PID=""

# ============================================================================
# PATHS & ENVIRONMENT
# ============================================================================

# Distribution detection
DNF_CMD=$(command -v dnf5 || command -v dnf)
STATE_FILE="$HOME/.fedorainstaller.state"
INSTALL_LOG="$HOME/.fedorainstaller.log"

# Only set these if not already set by install.sh
# Note: When sourced from install.sh, these are already set correctly
if [ -z "${SCRIPT_DIR:-}" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"  # Script directory (fedorainstaller/scripts)
fi
if [ -z "${CONFIGS_DIR:-}" ]; then
    CONFIGS_DIR="$(dirname "$SCRIPT_DIR")/configs"             # Config files directory
fi
if [ -z "${SCRIPTS_DIR:-}" ]; then
    SCRIPTS_DIR="$SCRIPT_DIR"                                  # Scripts directory
fi

# Ensure critical variables are defined
: "${HOME:=/home/$USER}"
: "${USER:=$(whoami)}"
: "${XDG_CURRENT_DESKTOP:=}"

# ============================================================================
# LIBRARY LOADER
# ============================================================================

# Source library modules (provides log_*, ui_*, system detection, package
# management, state/resume and dashboard).
__COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for __lib_module in core ui system package config state dashboard; do
    source "$__COMMON_DIR/lib/$__lib_module.sh"
done
unset __lib_module __COMMON_DIR
