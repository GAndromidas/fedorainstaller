#!/bin/bash

# Color variables for output formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

DNF_CMD=$(command -v dnf5 || command -v dnf)
LOGFILE="$HOME/fedorainstaller/install.log"
ERRORS=()
INSTALLED_PACKAGES=()
REMOVED_PACKAGES=()
CURRENT_STEP=1
# TOTAL_STEPS is now calculated dynamically in install.sh

log()    { echo -e "$1" | tee -a "$LOGFILE"; }
print_info()    { log "\n${CYAN}$1${RESET}\n"; }
print_success() { log "\n${GREEN}[OK] $1${RESET}\n"; }
print_warning() { log "\n${YELLOW}[WARN] $1${RESET}\n"; }
print_error()   { log "\n${RED}[FAIL] $1${RESET}\n"; ERRORS+=("$1"); }
step()   { echo -e "\n${CYAN}[$CURRENT_STEP/$TOTAL_STEPS] $1${RESET}"; ((CURRENT_STEP++)); }

show_menu() {
  echo -e "${YELLOW}Welcome to the Fedora Installer script!${RESET}"
  echo "Please select your installation mode:"
  echo "  1) Default"
  echo "  2) Minimal"
  echo "  3) Exit"

  while true; do
    read -r -p "Enter your choice [1-3]: " menu_choice
    case "$menu_choice" in
      1) INSTALL_MODE="default"; IS_DEFAULT=1; IS_MINIMAL=0; break ;;
      2) INSTALL_MODE="minimal"; IS_DEFAULT=0; IS_MINIMAL=1; break ;;
      3) exit 0 ;;
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
    else
        print_warning "Installation completed with some errors."
        print_info "Review the errors above and check the log at $LOGFILE"
        log_performance "Total installation time"
    fi
}
