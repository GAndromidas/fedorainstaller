#!/bin/bash
set -uo pipefail

# ============================================================================
# SECTION 1: COLOR VARIABLES & BASIC FUNCTIONS
# ============================================================================

# Color variables for output formatting
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
TOTAL_STEPS=13
: "${VERBOSE:=false}"   # Can be overridden/exported by caller
: "${DRY_RUN:=false}"

# Distribution detection
DNF_CMD=$(command -v dnf5 || command -v dnf)
STATE_FILE="$HOME/.fedorainstaller.state"
INSTALL_LOG="$HOME/.fedorainstaller.log"

# Only set these if not already set by install.sh
# Note: When sourced from install.sh, these are already set correctly
if [ -z "$SCRIPT_DIR" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"  # Script directory (fedorainstaller/)
fi
if [ -z "$CONFIGS_DIR" ]; then
    CONFIGS_DIR="$SCRIPT_DIR/configs"                              # Config files directory
fi
if [ -z "$SCRIPTS_DIR" ]; then
    SCRIPTS_DIR="$SCRIPT_DIR/scripts"                              # Scripts directory
fi

# Ensure critical variables are defined
: "${HOME:=/home/$USER}"
: "${USER:=$(whoami)}"
: "${XDG_CURRENT_DESKTOP:=}"

# Source library modules (provides ui_*, system detection, package mgmt, dashboard)
__COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for __lib_module in core ui system package config dashboard; do
    source "$__COMMON_DIR/lib/$__lib_module.sh"
done
unset __lib_module __COMMON_DIR

# ===== Logging Functions =====

# Log to both console and log file
log_both() {
    echo "$1" | tee -a "$INSTALL_LOG"
}

log_to_file() {
    local message="$1"
    echo "$1" >> "$INSTALL_LOG" 2>/dev/null || true
}

# Improved terminal output functions
# ============================================================================
# SECTION 2: LOGGING FUNCTIONS
# ============================================================================

log()    { echo -e "$1" | tee -a "$INSTALL_LOG"; }
print_info()    { echo -e "\n${BLUE}[INFO] $1${RESET}" | tee -a "$INSTALL_LOG"; }
print_success() { echo -e "\n${GREEN}[SUCCESS] $1${RESET}" | tee -a "$INSTALL_LOG"; }
print_warning() { echo -e "\n${YELLOW}[WARNING] $1${RESET}" | tee -a "$INSTALL_LOG"; }
print_error()   { echo -e "\n${RED}[ERROR] $1${RESET}" | tee -a "$INSTALL_LOG"; ERRORS+=("$1"); }
step()   { 
    local msg="$1"
    echo -e "\n${BLUE}[$CURRENT_STEP/$TOTAL_STEPS] $msg${RESET}" | tee -a "$INSTALL_LOG"
    log_to_file "Step $CURRENT_STEP: $msg"
    ((CURRENT_STEP++))
}

# UI functions with gum integration and fallback
ui_info() { echo -e "${BLUE}$1${RESET}" | tee -a "$INSTALL_LOG"; }
ui_success() { echo -e "${GREEN}$1${RESET}" | tee -a "$INSTALL_LOG"; }
ui_warn() { echo -e "${YELLOW}$1${RESET}" | tee -a "$INSTALL_LOG"; }
ui_error() { echo -e "${RED}$1${RESET}" | tee -a "$INSTALL_LOG"; }

# Check if gum is available for enhanced UI
supports_gum() {
    command -v gum >/dev/null 2>&1
}

# Force gum to use colors
export GUM_COLOR=always
export FORCE_COLOR=1
export CLICOLOR_FORCE=1

# Gum-based input with fallback
gum_input() {
    local prompt="$1"
    local default="${2:-}"
    
    if supports_gum; then
        if [ -n "$default" ]; then
            gum input --prompt "$prompt" --value "$default"
        else
            gum input --prompt "$prompt"
        fi
    else
        if [ -n "$default" ]; then
            read -r -p "$prompt [$default]: " response
            echo "${response:-$default}"
        else
            read -r -p "$prompt: " response
            echo "$response"
        fi
    fi
}

# Gum-based confirm with fallback
gum_confirm() {
    local prompt="$1"
    local default="${2:-true}"  # Default to true (yes)
    
    if supports_gum; then
        if [ "$default" = "true" ]; then
            gum confirm --default=true "$prompt"
        else
            gum confirm "$prompt"
        fi
    else
        local default_display="[y/N]"
        if [ "$default" = "true" ]; then
            default_display="[Y/n]"
        fi
        while true; do
            read -r -p "$prompt $default_display: " response
            case "${response,,}" in
                y|yes) return 0 ;;
                n|no|"") 
                    if [ "$default" = "true" ]; then
                        return 0
                    else
                        return 1
                    fi
                    ;;
            esac
        done
    fi
}

show_menu() {
    # Display detected OS information
    local detected_os="Fedora"
    if [[ -f /etc/os-release ]]; then
        detected_os=$(grep -E '^PRETTY_NAME=' /etc/os-release | cut -d'"' -f2)
    fi
    
    # Check if system is headless and only offer server mode
    if is_headless_system; then
        ui_warn "Headless system detected. Only Server mode is available."
        echo -e "${GREEN}Your OS is: $detected_os${RESET}"
        INSTALL_MODE="server"
        echo "Installation Mode: Server - Headless server setup"
        return
    fi

    # Check if gum is available, fallback to traditional menu if not
    if supports_gum; then
        show_gum_menu
    else
        show_traditional_menu
    fi
}

# Function to validate INSTALL_MODE
validate_install_mode() {
    local mode="$1"

    case "$mode" in
        "default"|"minimal"|"server")
            return 0
            ;;
        *)
            log_error "Invalid INSTALL_MODE: '$mode'. Valid modes are: default, minimal, server"
            return 1
            ;;
    esac
}

show_gum_menu() {
    # Display detected OS information
    local detected_os="Fedora"
    if [[ -f /etc/os-release ]]; then
        detected_os=$(grep -E '^PRETTY_NAME=' /etc/os-release | cut -d'"' -f2)
    fi
    
    echo -e "${CYAN}Your OS is: $detected_os${RESET}"
    echo ""
    
    echo -e "${YELLOW}This script will transform your fresh Fedora installation into a${RESET}"
    echo -e "${YELLOW}fully configured, optimized system with all the tools you need!${RESET}"
    echo ""

    local choice=$(gum choose --cursor="-> " \
        "Standard - Complete setup with all packages (intermediate users)" \
        "Minimal - Essential tools only (recommended for new users)" \
        "Server - Headless server setup (Docker, SSH, etc.)" \
        "Exit - Cancel installation")

    case "$choice" in
        "Standard"*)
            INSTALL_MODE="default"
            if validate_install_mode "$INSTALL_MODE"; then
                echo "Installation Mode: Standard - Complete setup with all packages (intermediate users)"
            else
                log_error "Failed to validate installation mode"
                exit 1
            fi
            ;;
        "Minimal"*)
            INSTALL_MODE="minimal"
            if validate_install_mode "$INSTALL_MODE"; then
                echo "Installation Mode: Minimal - Essential tools only (recommended for new users)"
            else
                log_error "Failed to validate installation mode"
                exit 1
            fi
            ;;
        "Server"*)
            INSTALL_MODE="server"
            if validate_install_mode "$INSTALL_MODE"; then
                echo "Installation Mode: Server - Headless server setup"
            else
                log_error "Failed to validate installation mode"
                exit 1
            fi
            ;;
        "Exit"*)
            echo -e "${YELLOW}Installation cancelled. You can run this script again anytime.${RESET}"
            exit 0
            ;;
    esac
}

show_traditional_menu() {
    # Display detected OS information
    local detected_os="Fedora"
    if [[ -f /etc/os-release ]]; then
        detected_os=$(grep -E '^PRETTY_NAME=' /etc/os-release | cut -d'"' -f2)
    fi
    
    echo "WELCOME TO FEDORA INSTALLER"
    echo "----------------------------------------"
    echo "Your OS is: $detected_os"
    echo ""
    echo "This script will transform your fresh Fedora installation into a"
    echo "fully configured, optimized system with all the tools you need!"
    echo ""
    echo -e "${CYAN}Choose your installation mode:${RESET}"
    echo ""
    printf "  1) Standard%-12s - Complete setup with all packages (intermediate users)\n" ""
    printf "  2) Minimal%-13s - Essential tools only (recommended for new users)\n" ""
    printf "  3) Server%-13s - Headless server setup (Docker, SSH, etc.)\n" ""
    printf "  4) Exit%-16s - Cancel installation\n" ""
    echo ""

    while true; do
        read -r -p "$(echo -e "${CYAN}Enter your choice [1-4]: ${RESET}")" menu_choice
        case "$menu_choice" in
            1)
                INSTALL_MODE="default"
                if validate_install_mode "$INSTALL_MODE"; then
                    echo "Installation Mode: Standard - Complete setup with all packages (intermediate users)"
                    break
                else
                    log_error "Failed to validate installation mode"
                    exit 1
                fi
                ;;
            2)
                INSTALL_MODE="minimal"
                if validate_install_mode "$INSTALL_MODE"; then
                    echo "Installation Mode: Minimal - Essential tools only (recommended for new users)"
                    break
                else
                    log_error "Failed to validate installation mode"
                    exit 1
                fi
                ;;
            3)
                INSTALL_MODE="server"
                if validate_install_mode "$INSTALL_MODE"; then
                    echo "Installation Mode: Server - Headless server setup"
                    break
                else
                    log_error "Failed to validate installation mode"
                    exit 1
                fi
                ;;
            4)
                echo -e "\n${YELLOW}Installation cancelled. You can run this script again anytime.${RESET}"
                exit 0
                ;;
            *)
                echo -e "\n${RED}Invalid choice! Please enter 1, 2, 3, or 4.${RESET}\n"
                ;;
        esac
    done
}

# ============================================================================
# SECTION 3: CONFIGURATION VALIDATION FUNCTIONS
# ============================================================================

# Validate configuration file before modification
validate_config_file() {
    local config_file="$1"
    local backup_dir="${2:-/tmp/fedorainstaller_backups}"
    
    # Create backup directory if it doesn't exist
    sudo mkdir -p "$backup_dir" 2>/dev/null || true
    
    if [ -f "$config_file" ]; then
        # Check if file is readable and not empty
        if [ ! -r "$config_file" ] || [ ! -s "$config_file" ]; then
            log_warning "Configuration file $config_file is corrupted or empty"
            return 1
        fi
        
        # Create backup with timestamp
        local backup_file="$backup_dir/$(basename "$config_file").backup.$(date +%Y%m%d_%H%M%S)"
        sudo cp "$config_file" "$backup_file" 2>/dev/null || {
            log_warning "Failed to backup $config_file"
            return 1
        }
        log_info "Backed up $config_file to $backup_file"
    fi
    
    return 0
}

# Check if configuration value exists and is valid
validate_config_value() {
    local config_file="$1"
    local key="$2"
    local expected_pattern="${3:-.*}"
    
    if [ ! -f "$config_file" ]; then
        return 1
    fi
    
    # Check if key exists and matches expected pattern
    if grep -q "^${key}=" "$config_file" 2>/dev/null; then
        local value=$(grep "^${key}=" "$config_file" | cut -d'=' -f2-)
        if [[ "$value" =~ $expected_pattern ]]; then
            return 0
        fi
    fi
    
    return 1
}

# Atomic file write with validation
atomic_write() {
    local content="$1"
    local target_file="$2"
    local temp_file="${target_file}.tmp.$$"
    local backup_dir="/tmp/fedorainstaller_backups"
    
    # Validate target directory exists
    local target_dir=$(dirname "$target_file")
    if [ ! -d "$target_dir" ]; then
        log_error "Target directory $target_dir does not exist"
        return 1
    fi
    
    # Create backup if target exists
    if [ -f "$target_file" ]; then
        validate_config_file "$target_file" "$backup_dir"
    fi
    
    # Write to temporary file first
    if ! echo "$content" > "$temp_file"; then
        log_error "Failed to write to temporary file $temp_file"
        return 1
    fi
    
    # Validate temporary file
    if [ ! -s "$temp_file" ]; then
        log_error "Temporary file $temp_file is empty"
        rm -f "$temp_file"
        return 1
    fi
    
    # Atomic move to target
    if ! sudo mv "$temp_file" "$target_file"; then
        log_error "Failed to move $temp_file to $target_file"
        rm -f "$temp_file"
        return 1
    fi
    
    log_success "Successfully wrote configuration to $target_file"
    return 0
}

# Check system compatibility
check_system_compatibility() {
    local issues=()
    
    # Check if running as root (should not be)
    if [[ $EUID -eq 0 ]]; then
        issues+=("Script should not be run as root")
    fi
    
    # Check if on Fedora
    if [[ ! -f /etc/fedora-release ]] && ! grep -q -i "fedora" /etc/os-release 2>/dev/null; then
        issues+=("Not running on Fedora Linux")
    fi
    
    # Check disk space (need at least 2GB)
    local available_space=$(df / | awk 'NR==2 {print $4}')
    if [[ $available_space -lt 2097152 ]]; then
        issues+=("Insufficient disk space (need 2GB, have $((available_space / 1024 / 1024))GB)")
    fi
    
    # Check internet connection
    if ! ping -c 1 -W 5 fedoraproject.org &>/dev/null; then
        issues+=("No internet connection")
    fi
    
    # Check bootloader compatibility
    if [ ! -d "/boot" ]; then
        issues+=("Boot directory not found")
    fi
    
    # Report issues
    if [ ${#issues[@]} -gt 0 ]; then
        log_error "System compatibility issues found:"
        for issue in "${issues[@]}"; do
            log_error "  - $issue"
        done
        return 1
    fi
    
    return 0
}

# ============================================================================
# SECTION 4: TERMINAL OUTPUT & UI FUNCTIONS
# ============================================================================

# Format time display helper function
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

# Timing functions for progress estimation
start_step_timer() {
    STEP_START_TIME=$(date +%s)
    if [ $INSTALLATION_START_TIME -eq 0 ]; then
        INSTALLATION_START_TIME=$STEP_START_TIME
    fi
}

end_step_timer() {
    local step_name="${1:-Step $CURRENT_STEP}"
    local end_time=$(date +%s)
    local duration=$((end_time - STEP_START_TIME))
    STEP_TIMES+=("$duration")

    # Calculate average time per step
    local total_time=0
    for time in "${STEP_TIMES[@]}"; do
        total_time=$((total_time + time))
    done

    local avg_time=$((total_time / ${#STEP_TIMES[@]}))
    local remaining_steps=$((TOTAL_STEPS - CURRENT_STEP))
    local estimated_remaining=$((remaining_steps * avg_time))

    if [ $remaining_steps -gt 0 ]; then
        ui_info "Step completed in $(format_time $duration). Estimated remaining time: $(format_time $estimated_remaining)"
    fi
}

# Unified styling functions for consistent UI across all scripts
print_unified_step_header() {
    local step_num="$1"
    local total="$2"
    local title="$3"

    echo ""
    echo -e "${CYAN}============================================================${RESET}"
    echo -e "${CYAN}  Step $step_num of $total: $title${RESET}"
    echo -e "${CYAN}============================================================${RESET}"
    echo ""
}

print_unified_substep() {
    local description="$1"

    echo -e "${CYAN}> $description${RESET}"
}

print_unified_success() {
    local message="$1"

    echo -e "${GREEN}✓ $message${RESET}"
}

print_unified_error() {
    local message="$1"

    echo -e "${RED}✗ $message${RESET}"
}

# ============================================================================
# SECTION 5: UI STYLING FUNCTIONS (gum-based)
# ============================================================================

print_header() {
    local title="$1"; shift
    echo -e "${CYAN}========================================${RESET}"
    echo -e "${CYAN}$title${RESET}"
    echo -e "${CYAN}========================================${RESET}"
    while (( "$#" )); do
        echo -e "${YELLOW}$1${RESET}"
        shift
    done
}

print_step_header() {
    local step_num="$1"; local total="$2"; local title="$3"
    echo -e "${CYAN}Step ${step_num}/${total}: ${title}${RESET}"
}

simple_banner() {
    local title="$1"
    echo -e "${CYAN}\n============================================================${RESET}"
    echo -e "${CYAN}========== $title ==========${RESET}"
    echo -e "${CYAN}============================================================${RESET}"
}

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

# ============================================================================
# SECTION 6: SYSTEM DETECTION & ENVIRONMENT FUNCTIONS
# ============================================================================

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if system uses UKI (Unified Kernel Image)
is_uki_system() {
    # Method 1: Check for UKI files in /boot/efi/EFI/Linux/
    if [[ -d /boot/efi/EFI/Linux/ ]] && ls /boot/efi/EFI/Linux/*.efi >/dev/null 2>&1; then
        return 0
    fi
    
    # Method 2: Check for UKI files in /boot/EFI/Linux/ (alternative path)
    if [[ -d /boot/EFI/Linux/ ]] && ls /boot/EFI/Linux/*.efi >/dev/null 2>&1; then
        return 0
    fi
    
    # Method 3: Check for any .efi files in /boot that might be UKI
    if find /boot -name "*.efi" -path "*linux*" 2>/dev/null | grep -q .; then
        return 0
    fi
    
    return 1
}

# Function to check if system is headless (no display manager or X server)
is_headless_system() {
    # Check for display manager
    if systemctl is-active --quiet gdm 2>/dev/null || \
       systemctl is-active --quiet sddm 2>/dev/null || \
       systemctl is-active --quiet lightdm 2>/dev/null || \
       systemctl is-active --quiet lxdm 2>/dev/null || \
       systemctl is-active --quiet slim 2>/dev/null; then
        return 1  # Not headless
    fi

    # Check for X server
    if pgrep -x X >/dev/null 2>&1 || pgrep -x Xorg >/dev/null 2>&1; then
        return 1  # Not headless
    fi

    # Check for Wayland
    if pgrep -x weston >/dev/null 2>&1 || pgrep -x gnome-shell >/dev/null 2>&1; then
        return 1  # Not headless
    fi

    # Check if XDG_CURRENT_DESKTOP is set
    if [[ -n "${XDG_CURRENT_DESKTOP:-}" ]]; then
        return 1  # Not headless
    fi

    return 0  # Headless
}

# Detect bootloader
detect_bootloader() {
    if [ -d /boot/efi/EFI/systemd ] || [ -d /boot/loader ]; then
        echo "systemd-boot"
    elif [ -f /boot/grub/grub.cfg ] || [ -f /boot/grub2/grub.cfg ]; then
        echo "grub"
    elif [ -f /boot/limine/limine.cfg ] || [ -f /boot/limine.cfg ]; then
        echo "limine"
    else
        echo "unknown"
    fi
}

# Get installed kernel types
get_installed_kernel_types() {
    local kernel_types=()
    
    if rpm -q kernel >/dev/null 2>&1; then
        kernel_types+=("kernel")
    fi
    if rpm -q kernel-rt >/dev/null 2>&1; then
        kernel_types+=("kernel-rt")
    fi
    
    echo "${kernel_types[@]}"
}

# Detect CPU vendor
detect_cpu_vendor() {
    if grep -q "GenuineIntel" /proc/cpuinfo; then
        echo "intel"
    elif grep -q "AuthenticAMD" /proc/cpuinfo; then
        echo "amd"
    else
        echo "unknown"
    fi
}

# Detect GPU vendor
detect_gpu_vendor() {
    local gpu_vendor=""
    local graphics_devices=$(lspci | grep -i "vga\|3d\|display")
    
    if echo "$graphics_devices" | grep -i "nvidia" >/dev/null; then
        gpu_vendor="nvidia"
    elif echo "$graphics_devices" | grep -i "amd" >/dev/null; then
        gpu_vendor="amd"
    elif echo "$graphics_devices" | grep -i "intel" >/dev/null; then
        gpu_vendor="intel"
    fi
    
    echo "$gpu_vendor"
}

# Detect storage type (SSD vs HDD)
is_ssd() {
    if command -v lsblk &>/dev/null; then
        if lsblk -d -o rota | grep -q '^0$'; then
            return 0
        fi
    fi
    return 1
}

# Detect if system is a laptop
is_laptop() {
    # Check for battery presence
    if [ -d /sys/class/power_supply/BAT0 ] || [ -d /sys/class/power_supply/BAT1 ]; then
        return 0
    fi
    
    # Check DMI product type for laptop/chassis
    if command -v dmidecode &>/dev/null; then
        local chassis_type=$(dmidecode -s chassis-type 2>/dev/null | tr '[:upper:]' '[:lower:]')
        case "$chassis_type" in
            "laptop"|"notebook"|"portable"|"sub notebook"|"convertible"|"detachable")
                return 0
                ;;
        esac
    fi
    
    # Check system product name for common laptop indicators
    if [ -f /sys/devices/virtual/dmi/id/product_name ]; then
        local product_name=$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null | tr '[:upper:]' '[:lower:]')
        case "$product_name" in
            *laptop*|*notebook*|*book*|*ultrabook*|*macbook*|*thinkpad*|*latitude*|*precision*)
                return 0
                ;;
        esac
    fi
    
    return 1
}

# ============================================================================
# SECTION 7: PACKAGE INSTALLATION FUNCTIONS
# ============================================================================

# Single package installation for DNF
dnf_install_single() {
    local package="$1"
    local quiet="${2:-true}"
    
    if rpm -q "$package" >/dev/null 2>&1; then
        log_to_file "$package is already installed"
        return 0
    fi
    
    if [ "$quiet" = true ]; then
        sudo $DNF_CMD install -y "$package" >/dev/null 2>&1
    else
        sudo $DNF_CMD install -y "$package"
    fi
    
    return $?
}

# Single package installation for Flatpak
flatpak_install_single() {
    local app="$1"
    local quiet="${2:-true}"
    local timeout_seconds="${3:-600}"
    
    # Check if app is already installed
    if flatpak list | grep -q "$app" 2>/dev/null; then
        log_to_file "$app is already installed (Flatpak)"
        return 0
    fi
    
    if [ "$quiet" = true ]; then
        timeout "$timeout_seconds" flatpak install -y flathub "$app" >/dev/null 2>&1
    else
        timeout "$timeout_seconds" flatpak install -y flathub "$app"
    fi
    
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        # Try to kill any stuck Flatpak processes
        pkill -f "flatpak.*install" 2>/dev/null || true
    fi
    
    return $exit_code
}

# Unified package installation function (similar to archinstaller's install_package_generic)
# Parameters: $1 - Package manager type (dnf|flatpak), $@ - Packages to install
# Returns: 0 on success, 1 if some packages failed
install_package_generic() {
    local pkg_manager="$1"
    shift
    local pkgs=("$@")
    local total=${#pkgs[@]}
    local current=0
    local failed=0
    
    if [ $total -eq 0 ]; then
        ui_info "No packages to install"
        return 0
    fi
    
    local manager_name
    case "$pkg_manager" in
        dnf) manager_name="DNF" ;;
        flatpak) manager_name="Flatpak" ;;
        *) manager_name="Unknown" ;;
    esac
    
    echo -e "${CYAN}Installing ${total} packages via ${manager_name}...${RESET}"
    
    for pkg in "${pkgs[@]}"; do
        ((current++))
        
        # Check if already installed
        local already_installed=false
        case "$pkg_manager" in
            dnf)
                rpm -q "$pkg" &>/dev/null && already_installed=true
                ;;
            flatpak)
                flatpak list | grep -q "$pkg" &>/dev/null && already_installed=true
                ;;
        esac
        
        if [ "$already_installed" = true ]; then
            continue
        fi
        
        # Dry-run mode: simulate installation
        if [ "${DRY_RUN:-false}" = true ]; then
            ui_info "Dry-run: Would install $pkg"
            INSTALLED_PACKAGES+=("$pkg")
        else
            # Capture both stdout and stderr for better error diagnostics
            local error_output
            case "$pkg_manager" in
                dnf)
                    if error_output=$(sudo $DNF_CMD install -y "$pkg" 2>&1); then
                        INSTALLED_PACKAGES+=("$pkg")
                    else
                        ui_error "Failed to install $pkg"
                        FAILED_PACKAGES+=("$pkg")
                        log_error "Failed to install $pkg via $manager_name" "Check network connection and package availability"
                        # Log the actual error for debugging
                        echo "$error_output" >> "$INSTALL_LOG"
                        # Show last line of error if verbose or if it's a critical error
                        if [ "${VERBOSE:-false}" = true ] || [[ "$error_output" == *"error:"* ]]; then
                            local last_error=$(echo "$error_output" | grep -i "error" | tail -1)
                            [ -n "$last_error" ] && log_warning "  Error: $last_error" "Try running the failed command manually for more details"
                        fi
                        ((failed++))
                    fi
                    ;;
                flatpak)
                    if error_output=$(flatpak install -y flathub "$pkg" 2>&1); then
                        INSTALLED_PACKAGES+=("$pkg")
                    else
                        ui_error "Failed to install $pkg"
                        FAILED_PACKAGES+=("$pkg")
                        log_error "Failed to install $pkg via $manager_name" "Check network connection and package availability"
                        # Log the actual error for debugging
                        echo "$error_output" >> "$INSTALL_LOG"
                        # Show last line of error if verbose or if it's a critical error
                        if [ "${VERBOSE:-false}" = true ] || [[ "$error_output" == *"error:"* ]]; then
                            local last_error=$(echo "$error_output" | grep -i "error" | tail -1)
                            [ -n "$last_error" ] && log_warning "  Error: $last_error" "Try running the failed command manually for more details"
                        fi
                        ((failed++))
                    fi
                    ;;
            esac
        fi
    done
    
    if [ $failed -eq 0 ]; then
        ui_success "Package installation completed"
        return 0
    else
        ui_warn "Package installation completed with $failed failures" "Failed packages: ${FAILED_PACKAGES[*]}"
        return 1
    fi
}

# Batch install with fallback to individual (optimized for speed)
install_packages_batch() {
    local pkg_manager="$1"
    shift
    local packages=("$@")
    local total=${#packages[@]}
    
    if [ $total -eq 0 ]; then
        ui_info "No packages to install"
        return 0
    fi
    
    ui_info "Installing ${total} packages via $pkg_manager (batch mode)..."
    
    # Filter out already installed packages
    local packages_to_install=()
    for pkg in "${packages[@]}"; do
        local already_installed=false
        case "$pkg_manager" in
            dnf)
                rpm -q "$pkg" &>/dev/null && already_installed=true
                ;;
            flatpak)
                flatpak list | grep -q "$pkg" &>/dev/null && already_installed=true
                ;;
        esac
        
        if [ "$already_installed" = false ]; then
            packages_to_install+=("$pkg")
        fi
    done
    
    local filtered_total=${#packages_to_install[@]}
    if [ $filtered_total -eq 0 ]; then
        ui_info "All packages already installed"
        return 0
    fi
    
    # Try batch install first for speed
    if [ "${DRY_RUN:-false}" = true ]; then
        ui_info "Dry-run: Would install ${filtered_total} packages"
        INSTALLED_PACKAGES+=("${packages_to_install[@]}")
        return 0
    fi
    
    case "$pkg_manager" in
        dnf)
            if sudo $DNF_CMD install -y "${packages_to_install[@]}" >/dev/null 2>&1; then
                ui_success "All packages installed successfully in batch"
                INSTALLED_PACKAGES+=("${packages_to_install[@]}")
                return 0
            fi
            ;;
        flatpak)
            if flatpak install -y flathub "${packages_to_install[@]}" >/dev/null 2>&1; then
                ui_success "All packages installed successfully in batch"
                INSTALLED_PACKAGES+=("${packages_to_install[@]}")
                return 0
            fi
            ;;
    esac
    
    # Fallback to individual installation using the generic function
    ui_warn "Batch installation failed, falling back to individual installation..."
    install_package_generic "$pkg_manager" "${packages_to_install[@]}"
    return $?
}

# ============================================================================
# SECTION 8: STEP EXECUTION & LOGGING
# ============================================================================

# Function: log_success
# Description: Prints success message in green with optional context
# Parameters: $1 - Success message, $2 - Optional context/details
log_success() {
    local message="$1"
    local context="${2:-}"
    echo -e "${GREEN}$message${RESET}" | tee -a "$INSTALL_LOG"
    if [ -n "$context" ]; then
        echo -e "${CYAN}  Details: $context${RESET}" | tee -a "$INSTALL_LOG"
    fi
}

# Function: log_warning
# Description: Prints warning message with optional context
# Parameters: $1 - Warning message, $2 - Optional context/details
log_warning() {
    local message="$1"
    local context="${2:-}"
    echo -e "${YELLOW}! $message${RESET}" | tee -a "$INSTALL_LOG"
    if [ -n "$context" ]; then
        echo -e "  Note: $context" | tee -a "$INSTALL_LOG"
    fi
}

# Function: log_error
log_error() {
    local message="$1"
    local hint="${2:-}"
    echo -e "${RED}$message${RESET}" | tee -a "$INSTALL_LOG"
    if [ -n "$hint" ]; then
        echo -e "  Tip: $hint" | tee -a "$INSTALL_LOG"
    fi
    ERRORS+=("$message")
}

# Function: log_info
# Description: Prints info message in cyan
# Parameters: $1 - Info message
log_info() {
    echo -e "${CYAN}$1${RESET}" | tee -a "$INSTALL_LOG"
}

# Function: run_step
# Description: Runs a command with step logging and error handling
# Parameters: $1 - Step description, $@ - Command to execute
# Returns: 0 on success, non-zero on failure
run_step() {
    local description="$1"
    shift
    step "$description"

    if "$@" 2>&1 | tee -a "$INSTALL_LOG" >/dev/null; then
        log_success "$description"
        return 0
    else
        log_error "$description failed"
        return 1
    fi
}

# ============================================================================
# SECTION 9: STATE MANAGEMENT FUNCTIONS (Enhanced with atomic writes)
# ============================================================================

# Validate state file integrity
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

# Mark step as completed with atomic write
mark_step_complete() {
    local step_name="$1"
    
    # Validate step name
    if [ -z "$step_name" ]; then
        log_error "mark_step_complete: step_name cannot be empty"
        return 1
    fi
    
    # Atomic write with file locking to prevent corruption
    local temp_state_file="$STATE_FILE.tmp.$$"
    (
        flock -x 200
        echo "$step_name" >> "$temp_state_file"
    ) 200>"$temp_state_file" && mv "$temp_state_file" "$STATE_FILE" 2>/dev/null || {
        log_error "Failed to update state file for step: $step_name"
        return 1
    }
}

# Mark step with status (completed/failed)
mark_step_complete_with_progress() {
    local step_name="$1"
    local status="${2:-completed}"

    # Validate step name
    if [ -z "$step_name" ]; then
        log_error "mark_step_complete_with_progress: step_name cannot be empty"
        return 1
    fi

    # Write status to state file with consistent format for parsing
    if [ "$status" = "completed" ]; then
        echo "COMPLETED: $step_name" >> "$STATE_FILE"
    else
        echo "FAILED: $step_name" >> "$STATE_FILE"
    fi
}

# Check if step was completed (checks for "COMPLETED: stepname" format)
is_step_complete() {
    [ -f "$STATE_FILE" ] && grep -q "^COMPLETED: $1$" "$STATE_FILE"
}

# Check if step was completed (alias for is_step_complete)
is_step_completed() {
    is_step_complete "$1"
}

# Get step status
get_step_status() {
    local step="$1"
    
    if [ -f "$STATE_FILE" ]; then
        grep "^COMPLETED: $step" "$STATE_FILE" 2>/dev/null | cut -d' ' -f2
    fi
}

# ============================================================================
# SECTION 10: ERROR HANDLING & CLEANUP
# ============================================================================

# Global installation success tracking
INSTALLATION_SUCCESS=true
SUDO_KEEPALIVE_PID=""

# Enhanced error handling and cleanup functions
cleanup_on_error() {
    local exit_code=${1:-$?}
    local error_line=${2:-$LINENO}
    
    if [ $exit_code -ne 0 ]; then
        # Mark installation as failed
        INSTALLATION_SUCCESS=false
        
        log_error "Installation failed with exit code $exit_code at line $error_line"
        log_error "Check the log file for details: $INSTALL_LOG"
        
        # Kill sudo keep-alive if running
        if [ -n "${SUDO_KEEPALIVE_PID+x}" ]; then
            kill $SUDO_KEEPALIVE_PID 2>/dev/null || true
        fi
        
        # Offer recovery options
        echo ""
        ui_error "Installation encountered an error!"
        ui_info "Options:"
        ui_info "1. Run the script again to resume from where it left off"
        ui_info "2. Check the log file: $INSTALL_LOG"
        ui_info "3. Start fresh installation: rm -f $STATE_FILE"
        
        # Save error state
        echo "FAILED: Installation failed at line $error_line (exit code: $exit_code)" >> "$STATE_FILE"
    fi
}

# Function to save log on exit
save_log_on_exit() {
    # Kill sudo keep-alive if running
    if [ -n "${SUDO_KEEPALIVE_PID+x}" ]; then
        kill $SUDO_KEEPALIVE_PID 2>/dev/null || true
    fi
    
    {
        echo ""
        echo "=========================================="
        echo "Installation ended: $(date)"
        echo "=========================================="
        
        # Add summary if installation completed successfully
        if [ "$INSTALLATION_SUCCESS" = "true" ]; then
            echo "Installation completed successfully!"
            echo "Total installation time: $(($(date +%s) - INSTALLATION_START_TIME)) seconds"
        else
            echo "Installation completed with errors!"
            echo "Check the log above for details."
        fi
    } >> "$INSTALL_LOG"
}

# Performance tracking
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

# Print summary
print_summary() {
    local errors_present="$1"
    if [ "$errors_present" = "0" ]; then
        print_success "Installation completed successfully!"
        print_info "All packages and configurations have been installed."
        log_performance "Total installation time"
        
        # Clean up state file on success
        if [ -f "$STATE_FILE" ]; then
            rm -f "$STATE_FILE"
            log_to_file "State file cleaned up after successful installation"
        fi
    else
        print_warning "Installation completed with some errors."
        print_info "Review the errors above and check the log at $INSTALL_LOG"
        log_performance "Total installation time"
    fi
}

# Delete installer files
delete_fedorainstaller_files() {
    print_info "Cleaning up installer files..."
    [ -d "$HOME/.fedorainstaller" ] && rm -rf "$HOME/.fedorainstaller"
    [ -f "$INSTALL_LOG" ] && rm -f "$INSTALL_LOG"
    [ -f "$STATE_FILE" ] && rm -f "$STATE_FILE"
    print_success "Installer files cleaned up."
}

# Prompt for reboot
prompt_reboot() {
    local errors_present="${1:-0}"
    if [ "$errors_present" = "0" ]; then
        echo -e "\n${YELLOW}═══════════════════════════════════════════════════════════════${RESET}"
        echo -e "${CYAN}🔄 SYSTEM REBOOT${RESET}"
        echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${RESET}"
        
        if command -v figlet >/dev/null; then
            echo -e "${CYAN}"
            figlet "System Reboot"
            echo -e "${RESET}"
        else
            echo -e "${CYAN}========== System Reboot ==========${RESET}"
        fi
        
        echo -e "${CYAN}Installation completed successfully!${RESET}"
        echo -e "${YELLOW}It's strongly recommended to reboot your system now.\n${RESET}"

        if supports_gum; then
            if gum confirm "Reboot now?" --default=true; then
                reboot_now=true
            else
                reboot_now=false
            fi
        else
            echo -n -e "${YELLOW}Reboot now? [Y/n]: ${RESET}"
            read -r reboot_ans
            reboot_ans=${reboot_ans,,}
            case "$reboot_ans" in
                ""|y|yes) reboot_now=true ;;
                *)        reboot_now=false ;;
            esac
        fi

        if [ "$reboot_now" = true ]; then
            echo -e "\n${CYAN}Rebooting...${RESET}\n"
            delete_fedorainstaller_files
            if command -v figlet >/dev/null; then
                sudo $DNF_CMD remove -y figlet >/dev/null 2>&1
            fi
            sudo reboot
        else
            echo -e "\n${YELLOW}Reboot skipped. You can reboot manually at any time using \`sudo reboot\`.${RESET}\n"
        fi
        echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${RESET}\n"
    else
        echo -e "\n${YELLOW}═══════════════════════════════════════════════════════════════${RESET}"
        echo -e "${RED}⚠️  INSTALLATION COMPLETED WITH ERRORS${RESET}"
        echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${RESET}"
        print_warning "Some steps failed. Review the log at $INSTALL_LOG"
        if [ ${#ERRORS[@]} -gt 0 ]; then
            for err in "${ERRORS[@]}"; do
                print_error "$err"
            done
        fi
        echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${RESET}\n"
    fi
}

# ============================================================================
# SECTION 11: RESUME FUNCTIONALITY
# ============================================================================

# Show resume menu with options
show_resume_menu() {
    # Validate state file first
    if ! validate_state_file; then
        return 0
    fi
    
    if [ -f "$STATE_FILE" ] && [ -s "$STATE_FILE" ]; then
        echo ""
        ui_info "Previous installation detected. Checking installation status..."

        local completed_steps=()
        local step_status=()
        local has_failures=false
        local last_completed_step=""

        # Read and parse state file
        while IFS= read -r step; do
            if [[ "$step" =~ ^COMPLETED:\ (.+)$ ]]; then
                local step_name="${BASH_REMATCH[1]}"
                completed_steps+=("$step")
                step_status+=("completed")
                last_completed_step="$step_name"
            elif [[ "$step" =~ ^FAILED:\ (.+)$ ]]; then
                local step_name="${BASH_REMATCH[1]}"
                completed_steps+=("$step")
                step_status+=("failed")
                has_failures=true
            elif [[ "$step" =~ ^FAILED: ]]; then
                # Legacy format
                completed_steps+=("$step")
                step_status+=("failed")
                has_failures=true
            else
                # Legacy format - assume completed
                completed_steps+=("$step")
                step_status+=("completed")
                last_completed_step="$step"
            fi
        done < "$STATE_FILE"

        if [ ${#completed_steps[@]} -eq 0 ]; then
            ui_info "No completed steps found in state file"
            return 0
        fi

        echo ""
        echo -e "${YELLOW}Installation Progress Summary${RESET}"
        echo ""
        for i in "${!completed_steps[@]}"; do
                local step="${completed_steps[$i]}"
                local status="${step_status[$i]}"
                local display_step="${step#*: }"
                
                case "$status" in
                    "completed")
                        echo -e "${GREEN}  [COMPLETED] $display_step${RESET}"
                        ;;
                    "failed")
                        echo -e "${RED}  [FAILED] $display_step${RESET}"
                        ;;
                esac
            done
            echo ""
            
            if supports_gum; then
                if [ "$has_failures" = true ]; then
                    if gum confirm --default=true "Found failed steps. Retry failed steps first?"; then
                        ui_info "Will retry failed steps during installation"
                        return 0
                    elif gum confirm --default=false "Resume from last completed step?"; then
                        ui_success "Resuming installation from last completed step..."
                        return 0
                    else
                        if gum confirm --default=false "Start fresh installation (this will clear previous progress)?"; then
                            rm -f "$STATE_FILE" 2>/dev/null || true
                            ui_info "Starting fresh installation..."
                            return 0
                        else
                            ui_info "Installation cancelled by user"
                            exit 0
                        fi
                    fi
                else
                    if gum confirm --default=true "Resume installation from where you left off?"; then
                        ui_success "Resuming installation..."
                        return 0
                    else
                        if gum confirm --default=false "Start fresh installation (this will clear previous progress)?"; then
                            rm -f "$STATE_FILE" 2>/dev/null || true
                            ui_info "Starting fresh installation..."
                            return 0
                        else
                            ui_info "Installation cancelled by user"
                            exit 0
                        fi
                    fi
                fi
            else
                if [ "$has_failures" = true ]; then
                    echo "Found failed steps. Options:"
                    echo "1. Retry failed steps first"
                    echo "2. Resume from last completed step"
                    echo "3. Start fresh installation"
                    echo "4. Cancel"
                    echo ""
                    read -r -p "Choose an option (1-4): " choice
                    case "$choice" in
                        1)
                            ui_info "Will retry failed steps during installation"
                            return 0
                            ;;
                        2)
                            ui_success "Resuming installation from last completed step..."
                            return 0
                            ;;
                        3)
                            rm -f "$STATE_FILE" 2>/dev/null || true
                            ui_info "Starting fresh installation..."
                            return 0
                            ;;
                        4)
                            ui_info "Installation cancelled by user"
                            exit 0
                            ;;
                        *)
                            ui_warn "Invalid option. Resuming installation..."
                            return 0
                            ;;
                    esac
                else
                    echo "Resume installation from where you left off? (y/n)"
                    read -r response
                    if [[ "$response" =~ ^[Yy]$ ]]; then
                        ui_success "Resuming installation..."
                        return 0
                    else
                        echo "Start fresh installation? (y/n)"
                        read -r fresh_response
                        if [[ "$fresh_response" =~ ^[Yy]$ ]]; then
                            rm -f "$STATE_FILE" 2>/dev/null || true
                            ui_info "Starting fresh installation..."
                            return 0
                        else
                            ui_info "Installation cancelled by user"
                            exit 0
                        fi
                    fi
                fi
            fi
        fi
}