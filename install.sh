#!/bin/bash
set -uo pipefail

source "$(dirname "$0")/common.sh"

# Start timing the installation
START_TIME=$(date +%s)

# Command-line arguments
RESUME_MODE=false
DRY_RUN=false
SPECIFIC_STEP=""

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --resume)
            RESUME_MODE=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --step)
            SPECIFIC_STEP="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --resume    Resume from last interrupted installation"
            echo "  --dry-run   Preview changes without executing"
            echo "  --step NAME Run only a specific step"
            echo "  --help      Show this help message"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Dry-run mode notification
if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}=== DRY-RUN MODE ===${RESET}"
    echo -e "${YELLOW}No changes will be made to the system${RESET}"
    echo -e "${YELLOW}====================${RESET}"
    echo
fi

# Resume mode notification
if [ "$RESUME_MODE" = true ]; then
    if [ -f "$STATE_FILE" ]; then
        echo -e "${CYAN}=== RESUME MODE ===${RESET}"
        echo -e "${CYAN}Resuming from last interrupted installation${RESET}"
        echo -e "${CYAN}==================${RESET}"
        echo
        load_state
    else
        echo -e "${YELLOW}No state file found. Starting fresh installation.${RESET}"
        RESUME_MODE=false
    fi
fi

# Fedora ASCII ART
fedora_ascii() {
  echo -e "${CYAN}"
  cat << "EOF"
  ______       _                 _____           _        _ _
 |  ____|     | |               |_   _|         | |      | | |
 | |__ ___  __| | ___  _ __ __ _  | |  _ __  ___| |_ __ _| | | ___ _ __
 |  __/ _ \/ _` |/ _ \| '__/ _` | | | | '_ \/ __| __/ _` | | |/ _ \ '__|
 | | |  __/ (_| | (_) | | | (_| |_| |_| | | \__ \ || (_| | | |  __/ |
 |_|  \___|\__,_|\___/|_|  \__,_|_____|_| |_|___/\__\__,_|_|_|\___|_|
EOF
  echo -e "${RESET}"
}

#=== Main Execution ===#
exec > >(tee -a "$LOGFILE") 2>&1

clear
fedora_ascii

# Skip menu in resume mode or if running specific step
if [ "$RESUME_MODE" = false ] && [ -z "$SPECIFIC_STEP" ]; then
    show_menu
else
    # Load installation mode from state if resuming
    if [ "$RESUME_MODE" = true ]; then
        if [ -n "${INSTALL_MODE:-}" ]; then
            echo -e "${CYAN}Resuming with installation mode: $INSTALL_MODE${RESET}"
        else
            echo -e "${YELLOW}No installation mode found in state. Please select mode:${RESET}"
            show_menu
        fi
    fi
fi

# Export variables for child scripts
export INSTALL_MODE
export IS_DEFAULT
export IS_MINIMAL
export IS_SERVER
export IS_CUSTOM
export DRY_RUN

require_sudo
check_dependencies
enable_sudo_pwfeedback

# Step functions - organized by category
declare -A STEP_FUNCS=(
  # System setup
  [set_hostname]="scripts/set_hostname.sh"
  [system_update_and_repos]="scripts/system_update_and_repos.sh"
  
  # Terminal and shell customization
  [terminal_customization]="scripts/terminal_customization.sh"
  [install_programs]="scripts/programs.sh"
  [install_nerd_fonts]="scripts/install_nerd_fonts.sh"
  
  # Package installation
  [enable_codecs]="scripts/enable_codecs.sh"
  [gaming_tweaks]="scripts/gaming_tweaks.sh"
  [hardware_detection]="scripts/hardware_detection.sh"
  
  # System configuration
  [system_services]="scripts/system_services.sh"
  [bootloader_config]="scripts/bootloader_config.sh"
  
  # Advanced features
  [peripheral_detection]="scripts/peripheral_detection.sh"
  [wakeonlan_config]="scripts/wakeonlan_config.sh"
  
  # Cleanup and security
  [maintenance]="scripts/maintenance.sh"
  [install_fail2ban]="scripts/install_fail2ban.sh"
)

# Calculate total steps dynamically
TOTAL_STEPS=${#STEP_FUNCS[@]}
export TOTAL_STEPS

run_step() {
  local step_name="$1"
  local script_path="$(dirname "$0")/${STEP_FUNCS[$step_name]}"
  
  # Skip if step already completed and in resume mode
  if [ "$RESUME_MODE" = true ] && is_step_completed "$step_name"; then
    echo -e "${YELLOW}Skipping $step_name (already completed)${RESET}"
    log_to_file "Skipping $step_name (already completed)"
    return 0
  fi
  
  # Skip if running specific step and this is not it
  if [ -n "$SPECIFIC_STEP" ] && [ "$step_name" != "$SPECIFIC_STEP" ]; then
    return 0
  fi
  
  step "$step_name"
  
  if [ "$DRY_RUN" = true ]; then
    echo -e "${YELLOW}[DRY-RUN] Would execute: $script_path${RESET}"
    log_to_file "[DRY-RUN] Would execute: $script_path"
    save_state "$step_name" "completed"
    return 0
  fi
  
  if bash "$script_path"; then
    save_state "$step_name" "completed"
    return 0
  else
    print_error "$step_name failed"
    save_state "$step_name" "failed"
    return 1
  fi
}

# Run all steps in logical order
# Skip gaming_tweaks in server mode
if [ "$INSTALL_MODE" = "server" ]; then
    unset 'STEP_FUNCS[gaming_tweaks]'
fi

# Skip peripheral detection and wakeonlan in minimal mode
if [ "$INSTALL_MODE" = "minimal" ]; then
    unset 'STEP_FUNCS[peripheral_detection]'
    unset 'STEP_FUNCS[wakeonlan_config]'
fi

# Recalculate total steps after mode-specific adjustments
TOTAL_STEPS=${#STEP_FUNCS[@]}
export TOTAL_STEPS

print_info "=== System Setup ==="
run_step set_hostname
run_step system_update_and_repos

print_info "=== Terminal Customization ==="
run_step terminal_customization
run_step install_programs
run_step install_nerd_fonts

print_info "=== Package Installation ==="
run_step enable_codecs
if [ "$INSTALL_MODE" != "server" ]; then
    run_step gaming_tweaks
fi
run_step hardware_detection

print_info "=== System Configuration ==="
run_step system_services
run_step bootloader_config

print_info "=== Advanced Features ==="
if [ "$INSTALL_MODE" != "minimal" ]; then
    run_step peripheral_detection
fi
if [ "$INSTALL_MODE" != "minimal" ]; then
    run_step wakeonlan_config
fi

print_info "=== Cleanup and Security ==="
run_step maintenance
run_step install_fail2ban

# Check if there were any errors
if [ ${#ERRORS[@]} -eq 0 ]; then
    print_summary 0
    prompt_reboot 0
else
    print_summary 1
    prompt_reboot 1
fi
