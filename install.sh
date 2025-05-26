#!/bin/bash

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

DNF_CMD=$(command -v dnf5 || command -v dnf)
CYAN='\033[0;36m'
RESET='\033[0m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
LOGFILE="$HOME/fedorainstaller/install.log"
ERRORS=()
INSTALLED_PACKAGES=()
REMOVED_PACKAGES=()
CURRENT_STEP=1
TOTAL_STEPS=23 # update as needed

#=== Logging and Progress ===#
log()    { echo -e "$1" | tee -a "$LOGFILE"; }
print_info()    { log "\n${CYAN}$1${RESET}\n"; }
print_success() { log "\n${GREEN}[OK] $1${RESET}\n"; }
print_warning() { log "\n${YELLOW}[WARN] $1${RESET}\n"; }
print_error()   { log "\n${RED}[FAIL] $1${RESET}\n"; ERRORS+=("$1"); }
step()   { echo -e "\n${CYAN}[$CURRENT_STEP/$TOTAL_STEPS] $1${RESET}"; ((CURRENT_STEP++)); }

#=== Root check and sudo refresh ===#
require_sudo() {
    if [ "$EUID" -ne 0 ]; then
        print_info "Root privileges are required. You may be prompted for your password."
        sudo -v || { print_error "Sudo failed. Exiting."; exit 1; }
        # Keep-alive sudo
        while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &
    fi
}

#=== Dependency checks ===#
check_dependencies() {
    local deps=("curl" "wget" "git" "unzip" "figlet" "fastfetch")
    local missing=()
    step "Checking required dependencies"
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done
    if [ "${#missing[@]}" -gt 0 ]; then
        print_info "Installing missing dependencies: ${missing[*]}"
        sudo $DNF_CMD install -y "${missing[@]}" || print_error "Failed to install dependencies: ${missing[*]}"
        INSTALLED_PACKAGES+=("${missing[@]}")
    else
        print_success "All dependencies are present."
    fi
}

set_hostname() {
    step "Set hostname"
    if command -v figlet >/dev/null; then figlet "Set Hostname"; else print_info "========== Set Hostname =========="; fi
    print_info "Please enter the desired hostname:"
    read -p "Hostname: " hostname
    if [ -n "$hostname" ]; then
        sudo hostnamectl set-hostname "$hostname" \
            && print_success "Hostname set to $hostname successfully." \
            || print_error "Failed to set the hostname."
    else
        print_warning "No hostname entered, skipping."
    fi
}

enable_asterisks_sudo() {
    step "Enable password feedback for sudo"
    SUDOERS_FILE="/etc/sudoers.d/pwfeedback"
    if [ -f "$SUDOERS_FILE" ]; then
        print_warning "Password feedback already enabled in sudoers."
    else
        print_info "Enabling password feedback in sudoers..."
        echo "Defaults pwfeedback" | sudo tee "$SUDOERS_FILE" > /dev/null
        print_success "Password feedback enabled in sudoers."
    fi
}

configure_dnf() {
    step "Configure DNF"
    DNF_CONF="/etc/dnf/dnf.conf"
    print_info "Configuring DNF..."
    sudo grep -q '^fastestmirror=True' "$DNF_CONF" || echo "fastestmirror=True" | sudo tee -a "$DNF_CONF"
    sudo grep -q '^max_parallel_downloads=10' "$DNF_CONF" || echo "max_parallel_downloads=10" | sudo tee -a "$DNF_CONF"
    sudo grep -q '^defaultyes=True' "$DNF_CONF" || echo "defaultyes=True" | sudo tee -a "$DNF_CONF"
    print_success "DNF configuration updated successfully."
}

enable_rpm_fusion() {
    step "Enable RPM Fusion"
    print_info "Enabling RPM Fusion repositories..."
    if ! $DNF_CMD repolist | grep -q rpmfusion-free; then
        sudo $DNF_CMD install -y \
            https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
            https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm \
            && print_success "RPM Fusion repositories enabled successfully." \
            || print_error "Failed to enable RPM Fusion repositories."
    else
        print_warning "RPM Fusion repositories are already enabled. Skipping."
    fi
}

update_system() {
    step "Update system"
    print_info "Updating system..."
    if command -v dnf5 &> /dev/null; then
        sudo dnf5 upgrade --refresh -y
    else
        sudo dnf upgrade --refresh -y
    fi
    if [ $? -eq 0 ]; then
        print_success "System updated successfully."
    else
        print_error "System update failed."
    fi
}

install_kernel_headers() {
    step "Install kernel headers"
    if rpm -q kernel-headers kernel-devel &>/dev/null; then
        print_warning "Kernel headers are already installed. Skipping."
    else
        print_info "Installing kernel headers..."
        sudo $DNF_CMD install -y kernel-headers kernel-devel \
            && print_success "Kernel headers installed successfully." \
            || print_error "Failed to install kernel headers."
        INSTALLED_PACKAGES+=(kernel-headers kernel-devel)
    fi
}

install_media_codecs() {
    step "Install media codecs"
    print_info "Installing media codecs (Fedora 42+ compatible)..."
    sudo $DNF_CMD groupupdate --with-optional Multimedia -y
    sudo $DNF_CMD install -y \
        gstreamer1-plugins-base gstreamer1-plugins-good gstreamer1-plugins-bad-free \
        gstreamer1-plugins-bad-freeworld gstreamer1-plugins-ugly gstreamer1-libav \
        lame\* --exclude=lame-devel x264 x265 a52dec faad2 faac libmad libdca \
        && print_success "Media codecs installed successfully for Fedora 42." \
        || print_error "Failed to install media codecs."
    INSTALLED_PACKAGES+=(gstreamer1-plugins-base gstreamer1-plugins-good gstreamer1-plugins-bad-free gstreamer1-plugins-bad-freeworld gstreamer1-plugins-ugly gstreamer1-libav x264 x265 a52dec faad2 faac libmad libdca)
}

enable_hw_video_acceleration() {
    step "Enable hardware video acceleration"
    print_info "Enabling hardware video acceleration..."
    sudo $DNF_CMD install -y ffmpeg ffmpeg-libs libva libva-utils mesa-va-drivers mesa-vdpau-drivers \
        && sudo $DNF_CMD upgrade -y \
        && print_success "Hardware video acceleration enabled successfully." \
        || print_error "Failed to enable hardware video acceleration."
    INSTALLED_PACKAGES+=(ffmpeg ffmpeg-libs libva libva-utils mesa-va-drivers mesa-vdpau-drivers)
}

install_openh264_for_firefox() {
    step "Install OpenH264 for Firefox"
    print_info "Installing OpenH264 for Firefox..."
    sudo $DNF_CMD install -y 'dnf-plugins-core'
    sudo $DNF_CMD config-manager --set-enabled fedora-cisco-openh264
    sudo $DNF_CMD install -y openh264 gstreamer1-plugin-openh264 mozilla-openh264 \
        && print_success "OpenH264 for Firefox installed successfully." \
        || print_error "Failed to install OpenH264 for Firefox."
    INSTALLED_PACKAGES+=(openh264 gstreamer1-plugin-openh264 mozilla-openh264)
}

install_zsh() {
    step "Install ZSH and plugins"
    if command -v zsh >/dev/null; then
        print_warning "zsh is already installed. Skipping."
    else
        print_info "Installing ZSH..."
        sudo $DNF_CMD install -y zsh \
            && print_success "ZSH installed." \
            || print_error "Failed to install ZSH."
        INSTALLED_PACKAGES+=(zsh)
    fi
    if [ -d "$HOME/.oh-my-zsh" ]; then
        print_warning "Oh-My-Zsh is already installed. Skipping."
    else
        print_info "Installing Oh-My-Zsh..."
        yes | sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
            && print_success "Oh-My-Zsh installed." \
            || print_error "Failed to install Oh-My-Zsh."
    fi
}

install_zsh_plugins() {
    step "Install ZSH plugins"
    ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"
    if [ -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]; then
        print_warning "zsh-autosuggestions already installed. Skipping."
    else
        git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions" \
            && print_success "zsh-autosuggestions installed." \
            || print_error "Failed to install zsh-autosuggestions."
    fi
    if [ -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]; then
        print_warning "zsh-syntax-highlighting already installed. Skipping."
    else
        git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" \
            && print_success "zsh-syntax-highlighting installed." \
            || print_error "Failed to install zsh-syntax-highlighting."
    fi
}

change_shell_to_zsh() {
    step "Change shell to ZSH"
    if [ "$SHELL" = "$(which zsh)" ]; then
        print_warning "ZSH is already your default shell. Skipping."
    else
        print_info "Changing shell to ZSH..."
        sudo chsh -s "$(which zsh)" "$USER" \
            && print_success "Shell changed to ZSH." \
            || print_error "Failed to change default shell."
    fi
}

move_zshrc() {
    step "Setup .zshrc"
    print_info "Copying .zshrc to Home Folder..."
    if [ -f "$HOME/fedorainstaller/configs/.zshrc" ]; then
        cp "$HOME/fedorainstaller/configs/.zshrc" "$HOME/"
        sed -i '/^plugins=/c\plugins=(git zsh-autosuggestions zsh-syntax-highlighting)' "$HOME/.zshrc"
        print_success ".zshrc copied and configured successfully."
    else
        print_warning ".zshrc not found in configs. Skipping."
    fi
}

install_starship() {
    step "Install Starship prompt"
    if command -v starship >/dev/null; then
        print_warning "starship is already installed. Skipping."
    else
        print_info "Installing Starship prompt..."
        curl -sS https://starship.rs/install.sh | sh -s -- -y \
            && print_success "Starship prompt installed successfully." \
            || print_error "Failed to install Starship."
        INSTALLED_PACKAGES+=(starship)
    fi
    mkdir -p "$HOME/.config"
    if [ -f "$HOME/fedorainstaller/configs/starship.toml" ]; then
        cp "$HOME/fedorainstaller/configs/starship.toml" "$HOME/.config/starship.toml"
        print_success "Starship config copied."
    else
        print_warning "starship.toml not found in configs. Skipping."
    fi
}

add_flathub_repo() {
    step "Enable Flathub"
    if ! command -v flatpak &>/dev/null; then
        print_info "Flatpak not found. Installing..."
        sudo $DNF_CMD install -y flatpak
        INSTALLED_PACKAGES+=(flatpak)
    fi
    print_info "Adding Flathub repository..."
    sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    sudo flatpak update
    print_success "Flathub repository added successfully."
}

install_programs() {
    step "Install user programs"
    print_info "Installing Programs..."
    if [ -f "$HOME/fedorainstaller/scripts/programs.sh" ]; then
        (cd "$HOME/fedorainstaller/scripts" && ./programs.sh) \
            && print_success "Programs installed successfully." \
            || print_error "Failed to install user programs."
    else
        print_warning "User programs script not found. Skipping."
    fi
    install_flatpak_programs
}

install_flatpak_programs() {
    step "Install flatpak programs"
    print_info "Installing Flatpak Programs..."
    if [ -f "$HOME/fedorainstaller/scripts/flatpak_programs.sh" ]; then
        (cd "$HOME/fedorainstaller/scripts" && ./flatpak_programs.sh) \
            && print_success "Flatpak programs installed successfully." \
            || print_error "Failed to install flatpak programs."
    else
        print_warning "Flatpak programs script not found. Skipping."
    fi
}

install_nerd_fonts() {
    step "Install Nerd Font"
    FONT_NAME="Hack"
    FONT_DIR="$HOME/.local/share/fonts"
    if fc-list | grep -i "hack.*nerd" > /dev/null; then
        print_warning "$FONT_NAME Nerd Font is already installed. Skipping."
        return
    fi
    print_info "Installing $FONT_NAME Nerd Font..."
    mkdir -p "$FONT_DIR"
    NERD_FONT_VERSION=$(curl -s https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')
    if [ -z "$NERD_FONT_VERSION" ]; then
        print_error "Failed to fetch latest Nerd Fonts version"
        return 1
    fi
    url="https://github.com/ryanoasis/nerd-fonts/releases/download/${NERD_FONT_VERSION}/${FONT_NAME}.zip"
    if curl --head --silent --fail "$url" > /dev/null; then
        wget -q --show-progress -O "/tmp/${FONT_NAME}.zip" "$url"
        if [ $? -eq 0 ]; then
            unzip -q -o "/tmp/${FONT_NAME}.zip" -d "$FONT_DIR"
            rm "/tmp/${FONT_NAME}.zip"
            print_success "Successfully installed $FONT_NAME Nerd Font"
            fc-cache -fv
        else
            print_error "Failed to download $FONT_NAME Nerd Font"
        fi
    else
        print_error "$FONT_NAME Nerd Font not found at version ${NERD_FONT_VERSION}"
    fi
}

enable_services() {
    step "Enable services"
    print_info "Enabling Services..."
    services=("fstrim.timer" "bluetooth" "sshd" "firewalld")
    for service in "${services[@]}"; do
        if systemctl is-enabled --quiet "$service"; then
            print_warning "Service $service is already enabled. Skipping."
        else
            sudo systemctl enable --now "$service" \
                && print_success "Service $service enabled and started." \
                || print_error "Failed to enable/start $service."
        fi
    done
}

create_fastfetch_config() {
    step "Setup fastfetch config"
    if [ -f "$HOME/.config/fastfetch/config.jsonc" ]; then
        print_warning "fastfetch config already exists. Skipping."
    else
        print_info "Creating fastfetch config..."
        mkdir -p "$HOME/.config/fastfetch"
        fastfetch --gen-config
        if [ -f "$HOME/fedorainstaller/configs/config.jsonc" ]; then
            cp "$HOME/fedorainstaller/configs/config.jsonc" "$HOME/.config/fastfetch/config.jsonc"
            print_success "Fastfetch config created and copied."
        else
            print_warning "Fastfetch config.jsonc not found in configs."
        fi
    fi
}

configure_firewalld() {
    step "Configure firewalld"
    print_info "Configuring Firewalld..."
    sudo $DNF_CMD install -y firewalld
    sudo systemctl enable --now firewalld
    sudo firewall-cmd --permanent --set-default-zone=public
    sudo firewall-cmd --permanent --add-service=ssh
    if rpm -q kde-connect &>/dev/null; then
        sudo firewall-cmd --permanent --add-port=1714-1764/tcp
        sudo firewall-cmd --permanent --add-port=1714-1764/udp
    fi
    sudo firewall-cmd --reload
    print_success "Firewalld configured successfully."
}

clear_unused_packages_cache() {
    step "Clear unused packages and cache"
    print_info "Clearing Unused Packages and Cache..."
    sudo $DNF_CMD autoremove -y
    sudo $DNF_CMD clean all
    print_success "Unused packages and cache cleared successfully."
}

install_fail2ban() {
    step "Install/configure fail2ban"
    if command -v figlet >/dev/null; then
        figlet "Fail2ban"
    else
        print_info "========== Fail2ban =========="
    fi
    while true; do
        read -rp "$(echo -e "${YELLOW}Install & configure Fail2ban? [Y/n]: ${RESET}")" fail2ban_ans
        fail2ban_ans=${fail2ban_ans,,}
        case "$fail2ban_ans" in
            ""|y|yes)
                if rpm -q fail2ban &>/dev/null; then
                    print_warning "Fail2ban is already installed. Skipping."
                else
                    sudo $DNF_CMD install -y fail2ban
                    sudo systemctl enable --now fail2ban \
                        && print_success "Fail2ban installed and started." \
                        || print_error "Failed to install or start Fail2ban."
                    INSTALLED_PACKAGES+=(fail2ban)
                fi
                break
                ;;
            n|no)
                print_warning "Skipped Fail2ban installation."
                break
                ;;
            *)
                echo -e "${RED}Please answer Y (yes) or N (no).${RESET}"
                ;;
        esac
    done
}

delete_fedorainstaller_folder() {
    step "Delete installer folder"
    print_info "Deleting fedorainstaller folder..."
    rm -rf "$HOME/fedorainstaller"
    print_success "fedorainstaller folder deleted successfully."
}

print_summary() {
  echo -e "\n${CYAN}========= INSTALL SUMMARY =========${RESET}"
  if [ ${#INSTALLED_PACKAGES[@]} -gt 0 ]; then
    echo -e "${GREEN}Installed:${RESET} ${INSTALLED_PACKAGES[*]}"
  else
    echo -e "${YELLOW}No new packages were installed.${RESET}"
  fi
  if [ ${#REMOVED_PACKAGES[@]} -gt 0 ]; then
    echo -e "${RED}Removed:${RESET} ${REMOVED_PACKAGES[*]}"
  else
    echo -e "${GREEN}No packages were removed.${RESET}"
  fi
  echo -e "${CYAN}===================================${RESET}"
  if [ ${#ERRORS[@]} -gt 0 ]; then
    echo -e "\n${RED}The following steps failed:${RESET}\n"
    for err in "${ERRORS[@]}"; do
      echo -e "${YELLOW}  - $err${RESET}"
    done
    echo -e "\n${YELLOW}Check the install log for more details: ${CYAN}$LOGFILE${RESET}\n"
  else
    echo -e "\n${GREEN}All steps completed successfully!${RESET}\n"
  fi
}

reboot_system() {
    if command -v figlet >/dev/null; then
        figlet "Reboot System"
    else
        print_info "========== Reboot System =========="
    fi
    printf "${YELLOW}Do you want to reboot now? (Y/n)${RESET} "
    read -rp "" confirm_reboot
    confirm_reboot="${confirm_reboot,,}"
    [ -z "$confirm_reboot" ] && confirm_reboot="y"
    while [[ ! "$confirm_reboot" =~ ^(y|n)$ ]]; do
        read -rp "Invalid input. Please enter 'Y' to reboot now or 'n' to cancel: " confirm_reboot
        confirm_reboot="${confirm_reboot,,}"
    done
    if [[ "$confirm_reboot" == "y" ]]; then
        print_info "Rebooting now..."
        sudo reboot
    else
        print_warning "Reboot canceled. You can reboot manually later by typing 'sudo reboot'."
    fi
}

#=== Main Execution ===#
exec > >(tee -a "$LOGFILE") 2>&1

clear
fedora_ascii

require_sudo
check_dependencies

set_hostname
enable_asterisks_sudo
configure_dnf
enable_rpm_fusion
update_system
install_kernel_headers
install_media_codecs
enable_hw_video_acceleration
install_openh264_for_firefox

install_zsh
install_zsh_plugins
change_shell_to_zsh
move_zshrc
install_starship
add_flathub_repo
install_programs
install_nerd_fonts
enable_services
create_fastfetch_config
configure_firewalld
clear_unused_packages_cache
install_fail2ban

print_summary

if [ ${#ERRORS[@]} -eq 0 ]; then
    delete_fedorainstaller_folder
else
    print_warning "Some steps failed. The fedorainstaller folder was NOT deleted for troubleshooting."
    print_warning "Review the log at $LOGFILE"
    for err in "${ERRORS[@]}"; do
        print_error "$err"
    done
fi

reboot_system
