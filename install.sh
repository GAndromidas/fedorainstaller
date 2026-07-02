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

source "$SCRIPT_DIR/scripts/common.sh"

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

FEATURES:
    - Hardware-aware CPU detection (Intel/AMD with microcode updates)
    - Automatic GPU driver detection and installation (NVIDIA/AMD/Intel)
    - Storage optimization (NVMe/SSD/HDD with I/O scheduling)
    - Desktop environment detection and optimization (KDE Plasma 6+, GNOME 46+)
    - Security hardening (Firewalld + Fail2ban with SSH protection)
    - Advanced performance tuning
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
    Installation log: ~/.fedorainstaller.log
    Progress tracking: ~/.fedorainstaller.state

MORE INFO:
    https://github.com/GAndromidas/fedorainstaller

EOF
  exit 0
}

#=== Main Execution ===#

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
  local gpu_vendor=$(detect_gpu_vendor)
  if [ -n "$gpu_vendor" ]; then
    case "$gpu_vendor" in
      intel)
        log_to_file "Intel GPU detected - mesa drivers will be configured"
        ;;
      nvidia)
        log_to_file "NVIDIA GPU detected - proprietary drivers will be configured"
        ;;
      amd)
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

# Installation start — enter dashboard wizard mode
dashboard_init

# Step 1: System Preparation
dashboard_step "System Preparation" 1
if is_step_complete "system_preparation"; then
  dashboard_skip
else
  if dashboard_run "$SCRIPTS_DIR/system_preparation.sh"; then
    mark_step_complete_with_progress "system_preparation" "completed"
    dashboard_ok
  else
    mark_step_complete_with_progress "system_preparation" "failed"
    dashboard_fail
    log_error "System preparation failed"
    if gum_confirm "System preparation failed. Continue with installation?" "This may cause issues with subsequent steps."; then
      ui_warn "Continuing installation despite system preparation failure"
    else
      ui_error "Installation stopped due to system preparation failure"
      exit 1
    fi
  fi
fi

# Step 2: Shell Setup
dashboard_step "Shell Setup" 2
if is_step_complete "shell_setup"; then
  dashboard_skip
else
  if dashboard_run "$SCRIPTS_DIR/shell_setup.sh"; then
    mark_step_complete_with_progress "shell_setup" "completed"
    dashboard_ok
  else
    mark_step_complete_with_progress "shell_setup" "failed"
    dashboard_fail
    log_error "Shell setup failed"
    ui_warn "Shell setup failed but continuing installation"
  fi
fi

# Step 3: Programs
dashboard_step "Programs" 3
if is_step_complete "programs"; then
  dashboard_skip
else
  if dashboard_run "$SCRIPTS_DIR/programs.sh"; then
    mark_step_complete_with_progress "programs" "completed"
    dashboard_ok
  else
    mark_step_complete_with_progress "programs" "failed"
    dashboard_fail
    log_error "Programs installation failed"
    ui_warn "Programs installation failed but continuing installation"
  fi
fi

# Step 4: Gaming Mode (skip in server mode)
dashboard_step "Gaming Mode" 4
if [[ "$INSTALL_MODE" == "server" ]]; then
  dashboard_skip "Skipped — server mode"
elif is_step_complete "gaming_mode"; then
  dashboard_skip
else
  if dashboard_run "$SCRIPTS_DIR/gaming_mode.sh"; then
    mark_step_complete_with_progress "gaming_mode" "completed"
    dashboard_ok
  else
    mark_step_complete_with_progress "gaming_mode" "failed"
    dashboard_fail
    log_error "Gaming mode failed"
    ui_warn "Gaming mode failed but continuing installation"
  fi
fi

# Step 5: Hardware Detection
dashboard_step "Hardware Detection" 5
if is_step_complete "hardware_detection"; then
  dashboard_skip
else
  if dashboard_run "$SCRIPTS_DIR/hardware_detection.sh"; then
    mark_step_complete_with_progress "hardware_detection" "completed"
    dashboard_ok
  else
    mark_step_complete_with_progress "hardware_detection" "failed"
    dashboard_fail
    log_error "Hardware detection failed"
    ui_warn "Hardware detection failed but continuing installation"
  fi
fi

# Step 6: Bootloader Configuration
dashboard_step "Bootloader Configuration" 6
if is_step_complete "bootloader_config"; then
  dashboard_skip
else
  if dashboard_run "$SCRIPTS_DIR/bootloader_config.sh"; then
    mark_step_complete_with_progress "bootloader_config" "completed"
    dashboard_ok
  else
    mark_step_complete_with_progress "bootloader_config" "failed"
    dashboard_fail
    log_error "Bootloader configuration failed"
    if gum_confirm "Bootloader configuration failed. Continue with installation?" "This may prevent your system from booting properly."; then
      ui_warn "Continuing installation despite bootloader configuration failure"
    else
      ui_error "Installation stopped due to bootloader configuration failure"
      exit 1
    fi
  fi
fi

# Step 7: System Services
dashboard_step "System Services" 7
if is_step_complete "system_services"; then
  dashboard_skip
else
  if dashboard_run "$SCRIPTS_DIR/system_services.sh"; then
    mark_step_complete_with_progress "system_services" "completed"
    dashboard_ok
  else
    mark_step_complete_with_progress "system_services" "failed"
    dashboard_fail
    log_error "System services configuration failed"
    ui_warn "System services configuration failed but continuing installation"
  fi
fi

# Step 8: Fail2ban
dashboard_step "Fail2ban" 8
if is_step_complete "fail2ban"; then
  dashboard_skip
else
  if dashboard_run "$SCRIPTS_DIR/fail2ban.sh"; then
    mark_step_complete_with_progress "fail2ban" "completed"
    dashboard_ok
  else
    mark_step_complete_with_progress "fail2ban" "failed"
    dashboard_fail
    log_error "Fail2ban setup failed"
    ui_warn "Fail2ban setup failed but continuing installation"
  fi
fi

# Step 9: Maintenance
dashboard_step "Maintenance" 9
if is_step_complete "maintenance"; then
  dashboard_skip
else
  if dashboard_run "$SCRIPTS_DIR/maintenance.sh"; then
    mark_step_complete_with_progress "maintenance" "completed"
    dashboard_ok
  else
    mark_step_complete_with_progress "maintenance" "failed"
    dashboard_fail
    log_error "Maintenance failed"
    ui_warn "Maintenance failed but installation completed"
  fi
fi

if [ "$DRY_RUN" = true ]; then
  echo ""
  ui_info "This was a preview run. No changes were made to your system."
  ui_info "To perform the actual installation, run: ./install.sh"
  echo ""
fi

dashboard_finish

log_performance "Total installation time"

# Check for errors and prompt reboot
if [ ${#ERRORS[@]} -eq 0 ]; then
  prompt_reboot 0
else
  prompt_reboot 1
fi