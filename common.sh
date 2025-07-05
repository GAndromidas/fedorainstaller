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
TOTAL_STEPS=21 # update as needed

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
  echo "  3) Custom"
  echo "  4) Exit"

  while true; do
    read -r -p "Enter your choice [1-4]: " menu_choice
    case "$menu_choice" in
      1) INSTALL_MODE="default"; IS_DEFAULT=1; IS_MINIMAL=0; IS_CUSTOM=0; break ;;
      2) INSTALL_MODE="minimal"; IS_DEFAULT=0; IS_MINIMAL=1; IS_CUSTOM=0; break ;;
      3) INSTALL_MODE="custom"; IS_DEFAULT=0; IS_MINIMAL=0; IS_CUSTOM=1; break ;;
      4) exit 0 ;;
      *) echo "Invalid choice!";;
    esac
  done
}

interactive_package_selection() {
    local MODE="custom"
    local PROGRAMS_YAML="$HOME/fedorainstaller/configs/programs.yaml"
    local DNF_LIST=()
    local DNF_CHOICES=()
    local FLATPAK_LIST=()
    local FLATPAK_CHOICES=()
    local DE=""
    if [ "$XDG_CURRENT_DESKTOP" ]; then
        case "${XDG_CURRENT_DESKTOP,,}" in
            *gnome*) DE="gnome" ;;
            *kde*)   DE="kde" ;;
            *cosmic*) DE="cosmic" ;;
        esac
    fi
    # Get minimal sets for pre-selection
    mapfile -t MINIMAL_DNF < <(yq ".minimal.dnf[].name" "$PROGRAMS_YAML" 2>/dev/null)
    mapfile -t MINIMAL_FLATPAK < <(yq ".minimal.flatpak[].name" "$PROGRAMS_YAML" 2>/dev/null)
    # DNF packages
    mapfile -t DNF_LIST < <(yq ".${MODE}.dnf[] | [.name, .description] | @tsv" "$PROGRAMS_YAML" 2>/dev/null)
    if [ -n "$DE" ]; then
        mapfile -t DE_DNF_LIST < <(yq ".desktop_environments.${DE}.install[] | [.name, .description] | @tsv" "$PROGRAMS_YAML" 2>/dev/null)
        DNF_LIST+=("${DE_DNF_LIST[@]}")
    fi
    for entry in "${DNF_LIST[@]}"; do
        local name desc preselect
        name="$(echo "$entry" | cut -f1)"
        desc="$(echo "$entry" | cut -f2-)"
        preselect="off"
        for min in "${MINIMAL_DNF[@]}"; do
            if [ "$name" = "$min" ]; then preselect="on"; break; fi
        done
        DNF_CHOICES+=("$name" "$desc" "$preselect")
    done
    # Flatpak packages
    mapfile -t FLATPAK_LIST < <(yq ".${MODE}.flatpak[] | [.name, .description] | @tsv" "$PROGRAMS_YAML" 2>/dev/null)
    if [ -n "$DE" ]; then
        mapfile -t DE_FLATPAK_LIST < <(yq ".desktop_environments.${DE}.flatpak[] | [.name, .description] | @tsv" "$PROGRAMS_YAML" 2>/dev/null)
        FLATPAK_LIST+=("${DE_FLATPAK_LIST[@]}")
    fi
    for entry in "${FLATPAK_LIST[@]}"; do
        local name desc preselect
        name="$(echo "$entry" | cut -f1)"
        desc="$(echo "$entry" | cut -f2-)"
        preselect="off"
        for min in "${MINIMAL_FLATPAK[@]}"; do
            if [ "$name" = "$min" ]; then preselect="on"; break; fi
        done
        FLATPAK_CHOICES+=("$name" "$desc" "$preselect")
    done
    # Ensure whiptail is installed
    if ! command -v whiptail &>/dev/null; then
        print_info "Installing whiptail for interactive selection..."
        sudo $DNF_CMD install -y newt
    fi
    # DNF selection
    local DNF_SELECTED
    DNF_SELECTED=$(whiptail --title "Fedora Installer - DNF Packages" --checklist \
        "Select DNF packages to install (SPACE=select, ENTER=confirm):" 22 78 12 \
        "${DNF_CHOICES[@]}" 3>&1 1>&2 2>&3)
    if [ $? -ne 0 ]; then
        print_warning "Whiptail cancelled or failed. Installing all custom DNF packages."
        DNF_SELECTED="${DNF_CHOICES[@]//\"/}"
    fi
    # Flatpak selection
    local FLATPAK_SELECTED
    if command -v flatpak &>/dev/null && [ ${#FLATPAK_CHOICES[@]} -gt 0 ]; then
        FLATPAK_SELECTED=$(whiptail --title "Fedora Installer - Flatpak Apps" --checklist \
            "Select Flatpak apps to install (SPACE=select, ENTER=confirm):" 22 78 12 \
            "${FLATPAK_CHOICES[@]}" 3>&1 1>&2 2>&3)
        if [ $? -ne 0 ]; then
            print_warning "Whiptail cancelled or failed. Installing all custom Flatpak apps."
            FLATPAK_SELECTED="${FLATPAK_CHOICES[@]//\"/}"
        fi
    fi
    # Clean up selected lists
    DNF_SELECTED=( $(echo $DNF_SELECTED | tr -d '"') )
    FLATPAK_SELECTED=( $(echo $FLATPAK_SELECTED | tr -d '"') )
    # Return as global variables
    CUSTOM_DNF_SELECTION=("${DNF_SELECTED[@]}")
    CUSTOM_FLATPAK_SELECTION=("${FLATPAK_SELECTED[@]}")
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
        echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${RESET}"
        read -p "Press Y to clean up installer files and reboot, or any other key to exit without reboot: " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            delete_fedorainstaller_folder
            # Uninstall figlet before reboot if installed
            if command -v figlet >/dev/null; then
                sudo $DNF_CMD remove -y figlet
            fi
            print_info "Rebooting system now..."
            sudo reboot
        else
            print_info "Reboot cancelled. Installer files not deleted."
        fi
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
    echo -e "${CYAN}$step_name completed in ${minutes}m ${seconds}s (${elapsed}s)${RESET}"
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
