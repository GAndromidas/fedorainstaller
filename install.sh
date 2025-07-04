#!/bin/bash

source "$(dirname "$0")/common.sh"

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

show_menu

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
  [install_nerd_fonts]="scripts/install_nerd_fonts.sh"
  
  # Package installation
  [enable_codecs]="scripts/enable_codecs.sh"
  [btrfs_tweaks]="scripts/btrfs_tweaks.sh"
  [gaming_tweaks]="scripts/gaming_tweaks.sh"
  [hardware_detection]="scripts/hardware_detection.sh"
  
  # System configuration
  [enable_services]="scripts/enable_services.sh"
  [configure_firewalld]="scripts/configure_firewalld.sh"
  [bootloader_config]="scripts/bootloader_config.sh"
  [create_fastfetch_config]="scripts/create_fastfetch_config.sh"
  
  # Cleanup and security
  [clear_unused_packages_cache]="scripts/clear_unused_packages_cache.sh"
  [install_fail2ban]="scripts/install_fail2ban.sh"
)

run_step() {
  local step_name="$1"
  local script_path="$(dirname "$0")/${STEP_FUNCS[$step_name]}"
  step "$step_name"
  if ! bash "$script_path"; then
    print_error "$step_name failed"
  fi
}

# Run all steps in logical order
print_info "=== System Setup ==="
run_step set_hostname
run_step system_update_and_repos

print_info "=== Terminal Customization ==="
run_step terminal_customization
install_programs_from_yaml || print_error "install_programs_from_yaml failed"
run_step install_nerd_fonts

print_info "=== Package Installation ==="
run_step enable_codecs
run_step btrfs_tweaks
run_step gaming_tweaks
run_step hardware_detection

print_info "=== System Configuration ==="
run_step enable_services
run_step configure_firewalld
run_step bootloader_config
run_step create_fastfetch_config

print_info "=== Cleanup and Security ==="
run_step clear_unused_packages_cache
run_step install_fail2ban

# Check if there were any errors
if [ ${#ERRORS[@]} -eq 0 ]; then
    print_summary 0
    prompt_reboot 0
else
    print_summary 1
    prompt_reboot 1
fi
