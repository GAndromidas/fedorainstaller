#!/bin/bash
set -uo pipefail

# Installation log file
INSTALL_LOG="$HOME/.fedorainstaller.log"

# Get's directory where this script is located (fedorainstaller root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPTS_DIR="$SCRIPT_DIR/scripts"
CONFIGS_DIR="$SCRIPT_DIR/configs"

# State tracking for error recovery
STATE_FILE="$HOME/.fedorainstaller.state"
mkdir -p "$(dirname "$STATE_FILE")"

source "$SCRIPT_DIR/common.sh"

# Function to show help
show_help() {
  cat << 'EOF'
FedoraInstaller - Fedora Post-Installation Automation

USAGE:
    ./install.sh [OPTIONS]

OPTIONS:
    -h, --help      Show this help message and exit
    -v, --verbose   Enable verbose output (show all package installation details)
    -q, --quiet     Quiet mode (minimal output)
    -d, --dry-run   Preview what will be installed without making changes

DESCRIPTION:
    FedoraInstaller transforms a fresh Fedora installation into a fully
    configured, optimized system with intelligent hardware detection and 
    tailored optimizations. It applies targeted optimizations rather than 
    one-size-fits-all settings, ensuring optimal performance for your 
    specific configuration.

INSTALLATION MODES:
    Standard        Complete setup with all recommended packages (intermediate users)
    Minimal         Essential tools only for lightweight installations (new users)
    Server          Headless configuration (Docker, SSH, server utilities)
    Custom          Interactive selection of packages to install (advanced users)

FEATURES:
    - Hardware-aware CPU detection (Intel/AMD with microcode updates)
    - Automatic GPU driver detection and installation (NVIDIA/AMD/Intel)
    - Storage optimization (NVMe/SSD/HDD with I/O scheduling)
    - Desktop environment detection and optimization (KDE Plasma 6+, GNOME 46+)
    - Security hardening (Firewalld + Fail2ban with SSH protection)
    - Advanced performance tuning
    - Smart peripheral detection (Logitech, Keychron, Razer, gaming devices)
    - Wake-on-LAN configuration for ethernet devices (desktops only)
    - Zsh shell with Oh-My-Zsh and Starship prompt
    - Resume functionality for interrupted installations

SYSTEM INTELLIGENCE:
    - Dynamic memory management (RAM-based swappiness)
    - Intelligent storage optimization (storage-type I/O scheduling)
    - Hardware-aware configuration (NVMe detection, zRAM monitoring)
    - Transparent hugepages optimization for desktop systems
    - Persistent settings via udev rules and systemd services

BOOTLOADER SUPPORT:
    - GRUB with timeout optimization and boot menu management
    - systemd-boot with LTS kernel fallback and EFI support

REQUIREMENTS:
    - Fresh Fedora installation
    - Active internet connection
    - Regular user account with sudo privileges
    - Minimum 2GB free disk space
    - Supported bootloader (GRUB/systemd-boot)

EXAMPLES:
    ./install.sh                Run installer with interactive prompts
    ./install.sh --verbose      Run with detailed package installation output
    ./install.sh --dry-run      Preview changes without making them
    ./install.sh --help         Show this help message

LOG FILES:
    Installation log: ~/.fedorainstaller
    Progress tracking: ~/.fedorainstaller.state

MORE INFO:
    https://github.com/GAndromidas/fedorainstaller

EOF
  exit 0
}

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

# Clear terminal for clean interface
clear

# Install gum silently for enhanced UI experience
if ! command -v gum >/dev/null 2>&1; then
  log_to_file "Installing gum for enhanced UI experience..."
  if sudo $DNF_CMD install -y gum >/dev/null 2>&1; then
    log_to_file "Gum installed successfully"
  else
    log_to_file "Failed to install gum, falling back to basic UI"
  fi
fi

# Initialize log file
{
  echo "=========================================="
  echo "Fedorainstaller Installation Log"
  echo "Started: $(date)"
  echo "=========================================="
  echo ""
} > "$INSTALL_LOG"

# Function to log to both console and file
log_both() {
  echo "$1" | tee -a "$INSTALL_LOG"
}

START_TIME=$(date +%s)
export START_TIME
INSTALLATION_START_TIME=$START_TIME

# Parse flags
VERBOSE=false
DRY_RUN=false
for arg in "$@"; do
  case "$arg" in
    -h|--help)
      show_help
      ;;
    --verbose|-v)
      VERBOSE=true
      ;;
    --quiet|-q)
      VERBOSE=false
      ;;
    --dry-run|-d)
      DRY_RUN=true
      VERBOSE=true
      ;;
    *)
      echo "Unknown option: $arg"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done
export VERBOSE
export DRY_RUN
export INSTALL_LOG

fedora_ascii

# Enhanced system requirements checking with hardware compatibility
check_system_requirements() {
  local requirements_failed=false
  
  # Use the enhanced compatibility check from common.sh
  if ! check_system_compatibility; then
    echo -e "${RED}Error: System compatibility check failed!${RESET}"
    echo -e "${YELLOW}   Please address the issues listed above before continuing.${RESET}"
    exit 1
  fi
  
  # Additional hardware-specific checks
  local hardware_issues=()
  
  # Check bootloader type and compatibility
  local bootloader=$(detect_bootloader 2>/dev/null || echo "unknown")
  case "$bootloader" in
    "grub"|"systemd-boot")
      log_to_file "Detected bootloader: $bootloader"
      ;;
    "unknown")
      hardware_issues+=("Unsupported or unknown bootloader detected")
      ;;
  esac
  
  # Check for UEFI vs BIOS mode
  if [ -d /sys/firmware/efi ]; then
    log_to_file "UEFI boot mode detected"
  else
    log_to_file "BIOS/Legacy boot mode detected"
    hardware_issues+=("Legacy BIOS mode detected - some features may not work optimally")
  fi
  
  # Check GPU drivers availability
  if lspci | grep -qi vga; then
    local gpu_vendor=$(lspci | grep -i vga | head -1 | awk '{print $1}' | cut -d: -f2)
    case "$gpu_vendor" in
      *"Intel"*)
        log_to_file "Intel GPU detected - mesa drivers will be configured"
        ;;
      *"NVIDIA"*)
        log_to_file "NVIDIA GPU detected - proprietary drivers will be configured"
        ;;
      *"AMD"*)
        log_to_file "AMD GPU detected - open-source drivers will be configured"
        ;;
      *)
        log_to_file "Unknown GPU detected - generic drivers will be used"
        ;;
    esac
  else
    hardware_issues+=("No GPU detected - this may be a headless system")
  fi
  
  # Check storage type for optimizations
  local root_device=$(findmnt -n -o SOURCE / | cut -d'[' -f1 | cut -d'/' -f3)
  if [ -n "$root_device" ]; then
    if echo "$root_device" | grep -q "nvme"; then
      log_to_file "NVMe storage detected - NVMe optimizations will be applied"
    elif [ -b "/dev/$root_device" ] && [ "$(cat /sys/block/${root_device}/queue/rotational 2>/dev/null)" = "0" ]; then
      log_to_file "SSD storage detected - SSD optimizations will be applied"
    else
      log_to_file "HDD storage detected - HDD optimizations will be applied"
    fi
  else
    hardware_issues+=("Could not determine root storage device")
  fi
  
  # Check system memory for optimizations
  local total_mem_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
  local total_mem_gb=$((total_mem_kb / 1024 / 1024))
  if [ "$total_mem_gb" -lt 2 ]; then
    hardware_issues+=("Low memory detected (${total_mem_gb}GB) - at least 2GB recommended")
  else
    log_to_file "System memory: ${total_mem_gb}GB - appropriate optimizations will be applied"
  fi
  
  # Report hardware issues if any
  if [ ${#hardware_issues[@]} -gt 0 ]; then
    echo -e "${YELLOW}Warning: Hardware compatibility issues detected:${RESET}"
    for issue in "${hardware_issues[@]}"; do
      echo -e "${YELLOW}   - $issue${RESET}"
    done
    echo ""
    if ! gum_confirm "Continue despite hardware compatibility issues?" "Some features may not work optimally."; then
      ui_info "Installation cancelled by user"
      exit 0
    fi
  fi
  
  log_to_file "System requirements and hardware compatibility checks passed"
}

check_system_requirements
show_menu

# Validate INSTALL_MODE after menu selection
if ! validate_install_mode "$INSTALL_MODE"; then
  log_error "Invalid installation mode selected. Please run the script again."
  exit 1
fi

export INSTALL_MODE

# Function to validate state file integrity
validate_state_file() {
  if [ ! -f "$STATE_FILE" ]; then
    return 0  # No file is valid
  fi
  
  # Check if file is readable and not empty
  if [ ! -r "$STATE_FILE" ] || [ ! -s "$STATE_FILE" ]; then
    log_warning "State file is corrupted or empty. Starting fresh installation."
    rm -f "$STATE_FILE" 2>/dev/null || true
    return 1
  fi
  
  return 0
}

# Enhanced resume functionality with partial failure handling and error recovery
# Show resume menu if previous installation detected
if [ -f "$STATE_FILE" ] && [ -s "$STATE_FILE" ]; then
  show_resume_menu
fi

# Dry-run mode banner
if [ "$DRY_RUN" = true ]; then
  echo ""
  echo -e "${YELLOW}========================================${RESET}"
  echo -e "${YELLOW}         DRY-RUN MODE ENABLED${RESET}"
  echo -e "${YELLOW}========================================${RESET}"
  echo -e "${CYAN}Preview mode: No changes will be made${RESET}"
  echo -e "${CYAN}Package installations will be simulated${RESET}"
  echo -e "${CYAN}System configurations will be previewed${RESET}"
  echo ""
  sleep 2
fi

# Prompt for sudo using UI helpers
if [ "$DRY_RUN" = false ]; then
  ui_info "Please enter your sudo password to begin the installation:"
  sudo -v || { ui_error "Sudo required. Exiting."; exit 1; }
else
  ui_info "Dry-run mode: Skipping sudo authentication"
fi

# Keep sudo alive (skip in dry-run mode)
if [ "$DRY_RUN" = false ]; then
  while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
  SUDO_KEEPALIVE_PID=$!
  # Enhanced trap with error handling
  trap 'cleanup_on_error $LINENO; save_log_on_exit' EXIT INT TERM ERR
else
  trap 'cleanup_on_error $LINENO; save_log_on_exit' EXIT INT TERM ERR
fi

# Function to check if step was completed
is_step_complete() {
  [ -f "$STATE_FILE" ] && grep -q "^COMPLETED: $1$" "$STATE_FILE"
}

# Installation start
echo "Starting FedoraInstaller"

# Step 1: System Update and Repos
if is_step_complete "system_update_and_repos"; then
  ui_info "Step 1 (System Update and Repos) already completed - skipping"
else
  step "System Update and Repos"
  ui_info "Updating system and configuring repos..."
  if source "$SCRIPTS_DIR/system_update_and_repos.sh"; then
    mark_step_complete_with_progress "system_update_and_repos" "completed"
  else
    mark_step_complete_with_progress "system_update_and_repos" "failed"
    log_error "System update and repos configuration failed"
    if gum_confirm "System update failed. Continue with installation?" "This may cause issues with subsequent steps."; then
      ui_warn "Continuing installation despite system update failure"
    else
      ui_error "Installation stopped due to system update failure"
      exit 1
    fi
  fi
fi

# Step 2: Set Hostname
if is_step_complete "set_hostname"; then
  ui_info "Step 2 (Set Hostname) already completed - skipping"
else
  step "Set Hostname"
  ui_info "Configuring hostname..."
  if source "$SCRIPTS_DIR/set_hostname.sh"; then
    mark_step_complete_with_progress "set_hostname" "completed"
  else
    mark_step_complete_with_progress "set_hostname" "failed"
    log_error "Hostname configuration failed"
    ui_warn "Hostname configuration failed but continuing installation"
  fi
fi

# Step 3: Terminal Customization
if is_step_complete "terminal_customization"; then
  ui_info "Step 3 (Terminal Customization) already completed - skipping"
else
  step "Terminal Customization"
  ui_info "Setting up terminal environment..."
  if source "$SCRIPTS_DIR/terminal_customization.sh"; then
    mark_step_complete_with_progress "terminal_customization" "completed"
  else
    mark_step_complete_with_progress "terminal_customization" "failed"
    log_error "Terminal customization failed"
    ui_warn "Terminal customization failed but continuing installation"
  fi
fi

# Step 4: Install Programs
if is_step_complete "install_programs"; then
  ui_info "Step 4 (Install Programs) already completed - skipping"
else
  step "Install Programs"
  ui_info "Installing applications..."
  if source "$SCRIPTS_DIR/programs.sh"; then
    mark_step_complete_with_progress "install_programs" "completed"
  else
    mark_step_complete_with_progress "install_programs" "failed"
    log_error "Programs installation failed"
    ui_warn "Programs installation failed but continuing installation"
  fi
fi

# Step 5: Install Nerd Fonts
if is_step_complete "install_nerd_fonts"; then
  ui_info "Step 5 (Install Nerd Fonts) already completed - skipping"
else
  step "Install Nerd Fonts"
  ui_info "Installing nerd fonts..."
  if source "$SCRIPTS_DIR/install_nerd_fonts.sh"; then
    mark_step_complete_with_progress "install_nerd_fonts" "completed"
  else
    mark_step_complete_with_progress "install_nerd_fonts" "failed"
    log_error "Nerd fonts installation failed"
    ui_warn "Nerd fonts installation failed but continuing installation"
  fi
fi

# Step 6: Enable Codecs
if is_step_complete "enable_codecs"; then
  ui_info "Step 6 (Enable Codecs) already completed - skipping"
else
  step "Enable Codecs"
  ui_info "Enabling multimedia codecs..."
  if source "$SCRIPTS_DIR/enable_codecs.sh"; then
    mark_step_complete_with_progress "enable_codecs" "completed"
  else
    mark_step_complete_with_progress "enable_codecs" "failed"
    log_error "Codecs installation failed"
    ui_warn "Codecs installation failed but continuing installation"
  fi
fi

# Step 7: Gaming Tweaks (skip in server mode)
if [[ "$INSTALL_MODE" == "server" ]]; then
  ui_info "Server mode selected, skipping Gaming Tweaks."
else
  if is_step_complete "gaming_tweaks"; then
    ui_info "Step 7 (Gaming Tweaks) already completed - skipping"
  else
    step "Gaming Tweaks"
    ui_info "Applying gaming optimizations..."
    if source "$SCRIPTS_DIR/gaming_tweaks.sh"; then
      mark_step_complete_with_progress "gaming_tweaks" "completed"
    else
      mark_step_complete_with_progress "gaming_tweaks" "failed"
      log_error "Gaming tweaks failed"
      ui_warn "Gaming tweaks failed but continuing installation"
    fi
  fi
fi

# Step 8: Hardware Detection
if is_step_complete "hardware_detection"; then
  ui_info "Step 8 (Hardware Detection) already completed - skipping"
else
  step "Hardware Detection"
  ui_info "Detecting and configuring hardware..."
  if source "$SCRIPTS_DIR/hardware_detection.sh"; then
    mark_step_complete_with_progress "hardware_detection" "completed"
  else
    mark_step_complete_with_progress "hardware_detection" "failed"
    log_error "Hardware detection failed"
    ui_warn "Hardware detection failed but continuing installation"
  fi
fi

# Step 9: System Services
if is_step_complete "system_services"; then
  ui_info "Step 9 (System Services) already completed - skipping"
else
  step "System Services"
  ui_info "Configuring system services..."
  if source "$SCRIPTS_DIR/system_services.sh"; then
    mark_step_complete_with_progress "system_services" "completed"
  else
    mark_step_complete_with_progress "system_services" "failed"
    log_error "System services configuration failed"
    ui_warn "System services configuration failed but continuing installation"
  fi
fi

# Step 10: Bootloader Configuration
if is_step_complete "bootloader_config"; then
  ui_info "Step 10 (Bootloader Configuration) already completed - skipping"
else
  step "Bootloader Configuration"
  ui_info "Configuring bootloader..."
  if source "$SCRIPTS_DIR/bootloader_config.sh"; then
    mark_step_complete_with_progress "bootloader_config" "completed"
  else
    mark_step_complete_with_progress "bootloader_config" "failed"
    log_error "Bootloader configuration failed"
    if gum_confirm "Bootloader configuration failed. Continue with installation?" "This may prevent your system from booting properly."; then
      ui_warn "Continuing installation despite bootloader configuration failure"
    else
      ui_error "Installation stopped due to bootloader configuration failure"
      exit 1
    fi
  fi
fi

# Step 11: Peripheral Detection (skip in minimal mode)
if [[ "$INSTALL_MODE" == "minimal" ]]; then
  ui_info "Minimal mode selected, skipping Peripheral Detection."
else
  if is_step_complete "peripheral_detection"; then
    ui_info "Step 11 (Peripheral Detection) already completed - skipping"
  else
    step "Peripheral Detection"
    ui_info "Detecting peripherals..."
    if source "$SCRIPTS_DIR/peripheral_detection.sh"; then
      mark_step_complete_with_progress "peripheral_detection" "completed"
    else
      mark_step_complete_with_progress "peripheral_detection" "failed"
      log_error "Peripheral detection failed"
      ui_warn "Peripheral detection failed but continuing installation"
    fi
  fi
fi

# Step 12: Wake-on-LAN Configuration (skip in minimal mode)
if [[ "$INSTALL_MODE" == "minimal" ]]; then
  ui_info "Minimal mode selected, skipping Wake-on-LAN Configuration."
else
  if is_step_complete "wakeonlan_config"; then
    ui_info "Step 12 (Wake-on-LAN Configuration) already completed - skipping"
  else
    step "Wake-on-LAN Configuration"
    ui_info "Configuring Wake-on-LAN..."
    if source "$SCRIPTS_DIR/wakeonlan_config.sh"; then
      mark_step_complete_with_progress "wakeonlan_config" "completed"
    else
      mark_step_complete_with_progress "wakeonlan_config" "failed"
      log_error "Wake-on-LAN configuration failed"
      ui_warn "Wake-on-LAN configuration failed but continuing installation"
    fi
  fi
fi

# Step 13: Maintenance
if is_step_complete "maintenance"; then
  ui_info "Step 13 (Maintenance) already completed - skipping"
else
  step "Maintenance"
  ui_info "Running system maintenance..."
  if source "$SCRIPTS_DIR/maintenance.sh"; then
    mark_step_complete_with_progress "maintenance" "completed"
  else
    mark_step_complete_with_progress "maintenance" "failed"
    log_error "Maintenance failed"
    ui_warn "Maintenance failed but installation completed"
  fi
fi

# Step 14: Fail2ban Setup
if is_step_complete "install_fail2ban"; then
  ui_info "Step 14 (Fail2ban Setup) already completed - skipping"
else
  step "Fail2ban Setup"
  ui_info "Setting up security protection..."
  if source "$SCRIPTS_DIR/install_fail2ban.sh"; then
    mark_step_complete_with_progress "install_fail2ban" "completed"
  else
    mark_step_complete_with_progress "install_fail2ban" "failed"
    log_error "Fail2ban setup failed"
    ui_warn "Fail2ban setup failed but continuing installation"
  fi
fi

if [ "$DRY_RUN" = true ]; then
  echo -e "${YELLOW}This was a preview run. No changes were made to your system.${RESET}"
  echo -e "${CYAN}To perform the actual installation, run:${RESET} ${GREEN}./install.sh${RESET}"
  echo ""
fi

log_performance "Total installation time"

# Check for errors and prompt reboot
if [ ${#ERRORS[@]} -eq 0 ]; then
  print_summary 0
  prompt_reboot 0
else
  print_summary 1
  prompt_reboot 1
fi