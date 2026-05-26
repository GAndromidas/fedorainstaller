#!/bin/bash

# Color variables for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
RESET='\033[0m'

DNF_CMD=$(command -v dnf5 || command -v dnf)
LOGFILE="$HOME/fedorainstaller/install.log"
STATE_FILE="$HOME/.fedorainstaller.state"
ERRORS=()
INSTALLED_PACKAGES=()
REMOVED_PACKAGES=()
CURRENT_STEP=1
# TOTAL_STEPS is now calculated dynamically in install.sh

# Logging functions
log_to_file() {
    local message="$1"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] $message" >> "$LOGFILE"
}

log()    { echo -e "$1" | tee -a "$LOGFILE"; log_to_file "$1"; }
print_info()    { log "\n${CYAN}[INFO] $1${RESET}\n"; }
print_success() { log "\n${GREEN}[SUCCESS] $1${RESET}\n"; }
print_warning() { log "\n${YELLOW}[WARNING] $1${RESET}\n"; }
print_error()   { log "\n${RED}[ERROR] $1${RESET}\n"; ERRORS+=("$1"); }
step()   { echo -e "\n${CYAN}[$CURRENT_STEP/$TOTAL_STEPS] $1${RESET}"; ((CURRENT_STEP++)); log_to_file "Step $CURRENT_STEP: $1"; }

# UI functions with gum integration and fallback
ui_info() { echo -e "${CYAN}$1${RESET}"; log_to_file "INFO: $1"; }
ui_success() { echo -e "${GREEN}$1${RESET}"; log_to_file "SUCCESS: $1"; }
ui_warn() { echo -e "${YELLOW}$1${RESET}"; log_to_file "WARNING: $1"; }
ui_error() { echo -e "${RED}$1${RESET}"; log_to_file "ERROR: $1"; }

# Check if gum is available for enhanced UI
if command -v gum &>/dev/null; then
    HAS_GUM=true
else
    HAS_GUM=false
fi

# Gum-based input with fallback
gum_input() {
    local prompt="$1"
    local default="${2:-}"
    
    if [ "$HAS_GUM" = true ]; then
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
    
    if [ "$HAS_GUM" = true ]; then
        gum confirm "$prompt"
    else
        while true; do
            read -r -p "$prompt [y/N]: " response
            case "${response,,}" in
                y|yes) return 0 ;;
                n|no|"") return 1 ;;
            esac
        done
    fi
}

show_menu() {
  echo -e "${YELLOW}Welcome to the Fedora Installer script!${RESET}"
  echo "Please select your installation mode:"
  echo "  1) Default (Full desktop experience)"
  echo "  2) Minimal (Essential packages only)"
  echo "  3) Server (Headless server setup)"
  echo "  4) Custom (Select packages manually)"
  echo "  5) Exit"

  while true; do
    read -r -p "Enter your choice [1-5]: " menu_choice
    case "$menu_choice" in
      1) INSTALL_MODE="default"; IS_DEFAULT=1; IS_MINIMAL=0; IS_SERVER=0; IS_CUSTOM=0; break ;;
      2) INSTALL_MODE="minimal"; IS_DEFAULT=0; IS_MINIMAL=1; IS_SERVER=0; IS_CUSTOM=0; break ;;
      3) INSTALL_MODE="server"; IS_DEFAULT=0; IS_MINIMAL=0; IS_SERVER=1; IS_CUSTOM=0; break ;;
      4) INSTALL_MODE="custom"; IS_DEFAULT=0; IS_MINIMAL=0; IS_SERVER=0; IS_CUSTOM=1; break ;;
      5) exit 0 ;;
      *) echo "Invalid choice!";;
    esac
  done
}

require_sudo() {
    if [ "$EUID" -eq 0 ]; then
        print_error "This script should not be run as root. Please run as a regular user."
        exit 1
    fi
    
    if ! sudo -n true 2>/dev/null; then
        print_info "This script requires sudo privileges. Please enter your password when prompted."
        sudo -v
    fi
}

check_dependencies() {
    local missing_deps=()
    
    # Check for essential commands
    for cmd in curl git; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
    fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        print_info "Installing missing dependencies: ${missing_deps[*]}"
        sudo $DNF_CMD install -y "${missing_deps[@]}"
    fi
}

# Enable sudo password feedback (asterisks when typing password)
enable_sudo_pwfeedback() {
    if ! sudo grep -q '^Defaults.*pwfeedback' /etc/sudoers /etc/sudoers.d/* 2>/dev/null; then
        print_info "Enabling sudo password feedback (asterisks when typing password)..."
        if echo 'Defaults env_reset,pwfeedback' | sudo EDITOR='tee -a' visudo; then
            print_success "Sudo password feedback enabled successfully."
        else
            print_error "Failed to enable sudo password feedback."
        fi
    else
        print_warning "Sudo password feedback already enabled. Skipping."
    fi
}

install_flatpak_app() {
    local app="$1"
    local timeout_seconds="${2:-600}"
    
    # Check if app is already installed
    if flatpak list | grep -q "$app"; then
        print_warning "$app is already installed. Skipping."
        return 0
    fi
    
    print_info "Installing $app..."
    
    # Try to install with timeout
    if timeout "$timeout_seconds" flatpak install -y flathub "$app" 2>/dev/null; then
        print_success "$app installed successfully."
        return 0
    else
        print_warning "Failed to install $app (timeout or error). Skipping."
        # Try to kill any stuck Flatpak processes
        pkill -f "flatpak.*install" 2>/dev/null || true
        return 1
    fi
}

delete_fedorainstaller_folder() {
    if [ -d "$HOME/fedorainstaller" ]; then
        print_info "Cleaning up installer files..."
        rm -rf "$HOME/fedorainstaller"
        print_success "Installer files cleaned up."
    fi
}

prompt_reboot() {
    local errors_present="$1"
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
        
        while true; do
            read -r -p "$(echo -e "${YELLOW}Reboot now? [Y/n]: ${RESET}")" reboot_ans
            reboot_ans=${reboot_ans,,}
            case "$reboot_ans" in
                ""|y|yes)
                    echo -e "\n${CYAN}Rebooting...${RESET}\n"
                    delete_fedorainstaller_folder
                    # Silently uninstall figlet before reboot
                    if command -v figlet >/dev/null; then
                        sudo $DNF_CMD remove -y figlet >/dev/null 2>&1
                    fi
                    sudo reboot
                    break
                    ;;
                n|no)
                    echo -e "\n${YELLOW}Reboot skipped. You can reboot manually at any time using \`sudo reboot\`.${RESET}\n"
                    break
                    ;;
                *)
                    echo -e "\n${RED}Please answer Y (yes) or N (no).${RESET}\n"
                    ;;
            esac
        done
        echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${RESET}\n"
    else
        echo -e "\n${YELLOW}═══════════════════════════════════════════════════════════════${RESET}"
        echo -e "${RED}⚠️  INSTALLATION COMPLETED WITH ERRORS${RESET}"
        echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${RESET}"
        print_warning "Some steps failed. The fedorainstaller folder was NOT deleted for troubleshooting."
        print_warning "Review the log at $LOGFILE"
        if [ ${#ERRORS[@]} -gt 0 ]; then
            for err in "${ERRORS[@]}"; do
                print_error "$err"
            done
        fi
        echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${RESET}\n"
    fi
}

# Performance tracking
log_performance() {
    local step_name="$1"
    local current_time=$(date +%s)
    local elapsed=$((current_time - START_TIME))
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
        print_info "Review the errors above and check the log at $LOGFILE"
        log_performance "Total installation time"
    fi
}

# System detection functions
command_exists() {
    command -v "$1" &>/dev/null
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

# Detect if system is headless (no display)
is_headless() {
    if [ -z "$DISPLAY" ] && [ -z "$WAYLAND_DISPLAY" ]; then
        return 0
    fi
    return 1
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
    if rpm -q kernel-xanmod >/dev/null 2>&1; then
        kernel_types+=("kernel-xanmod")
    fi
    if rpm -q kernel-lqx >/dev/null 2>&1; then
        kernel_types+=("kernel-lqx")
    fi
    if rpm -q kernel-tkg >/dev/null 2>&1; then
        kernel_types+=("kernel-tkg")
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

# Package installation helpers
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

install_packages_quietly() {
    local packages=("$@")
    
    for package in "${packages[@]}"; do
        if ! rpm -q "$package" >/dev/null 2>&1; then
            log_to_file "Installing $package..."
            sudo $DNF_CMD install -y "$package" >/dev/null 2>&1
            if [ $? -eq 0 ]; then
                log_to_file "$package installed successfully"
                INSTALLED_PACKAGES+=("$package")
            else
                log_to_file "Failed to install $package"
            fi
        fi
    done
}

# Step execution with error handling
run_step() {
    local step_name="$1"
    local step_function="$2"
    
    log_to_file "Running step: $step_name"
    
    if $step_function; then
        log_to_file "Step completed: $step_name"
        return 0
    else
        log_to_file "Step failed: $step_name"
        print_error "$step_name failed"
        return 1
    fi
}

# State management functions
save_state() {
    local step="$1"
    local status="$2"
    
    echo "$step=$status" >> "$STATE_FILE"
}

load_state() {
    if [ -f "$STATE_FILE" ]; then
        source "$STATE_FILE"
    fi
}

get_step_status() {
    local step="$1"
    
    if [ -f "$STATE_FILE" ]; then
        grep "^$step=" "$STATE_FILE" | cut -d'=' -f2
    fi
}

is_step_completed() {
    local step="$1"
    local status=$(get_step_status "$step")
    
    [ "$status" = "completed" ]
}

# Memory management optimizations
optimize_memory() {
    local total_mem=$(free -g | awk '/^Mem:/ {print $2}')
    
    # Apply memory optimizations based on available RAM
    if [ "$total_mem" -le 4 ]; then
        # Low memory system
        log_to_file "Applying low memory optimizations"
        # Add sysctl settings for low memory
        if [ ! -f /etc/sysctl.d/99-fedorainstaller-memory.conf ]; then
            sudo tee /etc/sysctl.d/99-fedorainstaller-memory.conf > /dev/null <<EOF
vm.swappiness=10
vm.vfs_cache_pressure=50
vm.dirty_ratio=15
vm.dirty_background_ratio=5
EOF
            sudo sysctl --system >/dev/null 2>&1
        fi
    elif [ "$total_mem" -le 16 ]; then
        # Medium memory system
        log_to_file "Applying medium memory optimizations"
        if [ ! -f /etc/sysctl.d/99-fedorainstaller-memory.conf ]; then
            sudo tee /etc/sysctl.d/99-fedorainstaller-memory.conf > /dev/null <<EOF
vm.swappiness=20
vm.vfs_cache_pressure=75
vm.dirty_ratio=20
vm.dirty_background_ratio=10
EOF
            sudo sysctl --system >/dev/null 2>&1
        fi
    else
        # High memory system
        log_to_file "Applying high memory optimizations"
        if [ ! -f /etc/sysctl.d/99-fedorainstaller-memory.conf ]; then
            sudo tee /etc/sysctl.d/99-fedorainstaller-memory.conf > /dev/null <<EOF
vm.swappiness=30
vm.vfs_cache_pressure=100
EOF
            sudo sysctl --system >/dev/null 2>&1
        fi
    fi
}


# Desktop environment version detection
get_desktop_version() {
    local desktop="$1"
    local version=""
    
    case "$desktop" in
        "KDE"|"kde"|"plasma"|"Plasma")
            if command -v plasmashell >/dev/null; then
                version=$(plasmashell --version 2>/dev/null | grep -o "Plasma [0-9.]*" | head -1)
                if [ -n "$version" ]; then
                    echo "$version"
                    return 0
                fi
            fi
            
            if command -v rpm >/dev/null; then
                version=$(rpm -q plasma-workspace 2>/dev/null | grep -o "[0-9.]*" | head -1)
                if [ -n "$version" ]; then
                    echo "Plasma $version"
                    return 0
                fi
            fi
            
            echo "Plasma (version unknown)"
            ;;
        "GNOME"|"gnome")
            if command -v gnome-shell >/dev/null; then
                version=$(gnome-shell --version 2>/dev/null | grep -o "GNOME Shell [0-9.]*" | head -1)
                if [ -n "$version" ]; then
                    echo "$version"
                    return 0
                fi
            fi
            
            if command -v rpm >/dev/null; then
                version=$(rpm -q gnome-shell 2>/dev/null | grep -o "[0-9.]*" | head -1)
                if [ -n "$version" ]; then
                    echo "GNOME $version"
                    return 0
                fi
            fi
            
            echo "GNOME (version unknown)"
            ;;
        "COSMIC"|"cosmic")
            if command -v cosmic-comp >/dev/null; then
                version=$(cosmic-comp --version 2>/dev/null | grep -o "COSMIC [0-9.]*" | head -1)
                if [ -n "$version" ]; then
                    echo "$version"
                    return 0
                fi
            fi
            
            if command -v rpm >/dev/null; then
                version=$(rpm -q cosmic-session 2>/dev/null | grep -o "[0-9.]*" | head -1)
                if [ -n "$version" ]; then
                    echo "COSMIC $version"
                    return 0
                fi
            fi
            
            echo "COSMIC (version unknown)"
            ;;
        *)
            echo "$desktop (version unknown)"
            ;;
    esac
}
