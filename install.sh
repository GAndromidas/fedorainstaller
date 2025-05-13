#!/bin/bash

# Script: install.sh
# Description: Script for setting up a Fedora system with various configurations and installations.
# Author: George Andromidas

# Prefer dnf5 if available
DNF_CMD=$(command -v dnf5 || command -v dnf)

# ASCII art
clear
CYAN='\033[0;36m'
RESET='\033[0m'
echo -e "${CYAN}"
cat << "EOF"
  ______       _                 _____           _        _ _           
 |  ____|     | |               |_   _|         | |      | | |          
 | |__ ___  __| | ___  _ __ __ _  | |  _ __  ___| |_ __ _| | | ___ _ __ 
 |  __/ _ \/ _` |/ _ \| '__/ _` | | | | '_ \/ __| __/ _` | | |/ _ \ '__|
 | | |  __/ (_| | (_) | | | (_| |_| |_| | | \__ \ || (_| | | |  __/ |   
 |_|  \___|\__,_|\___/|_|  \__,_|_____|_| |_|___/\__\__,_|_|_|\___|_|
EOF

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'

# Print functions
print_info() { echo -e "${CYAN}$1${RESET}"; }
print_success() { echo -e "${GREEN}$1${RESET}"; }
print_warning() { echo -e "${YELLOW}$1${RESET}"; }
print_error() { echo -e "${RED}$1${RESET}"; }

set_hostname() {
    print_info "Please enter the desired hostname:"
    read -p "Hostname: " hostname
    sudo hostnamectl set-hostname "$hostname" || {
        print_error "Error: Failed to set the hostname."; exit 1;
    }
    print_success "Hostname set to $hostname successfully."
}

enable_asterisks_sudo() {
    print_info "Enabling password feedback in sudoers..."
    echo "Defaults pwfeedback" | sudo tee /etc/sudoers.d/pwfeedback > /dev/null
    print_success "Password feedback enabled in sudoers."
}

configure_dnf() {
    print_info "Configuring DNF..."
    sudo tee -a /etc/dnf/dnf.conf <<EOL
fastestmirror=True
max_parallel_downloads=10
defaultyes=True
EOL
    print_success "DNF configuration updated successfully."
}

enable_rpm_fusion() {
    print_info "Enabling RPM Fusion repositories..."
    if ! $DNF_CMD repolist | grep -q rpmfusion-free; then
        sudo $DNF_CMD install -y \
            https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
            https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
    fi
    print_success "RPM Fusion repositories enabled successfully."
}

update_system() {
    print_info "Updating system..."
    sudo $DNF_CMD upgrade --refresh -y
    sudo $DNF_CMD groupupdate core -y
    print_success "System updated successfully."
}

install_kernel_headers() {
    print_info "Installing kernel headers..."
    sudo $DNF_CMD install -y kernel-headers kernel-devel || {
        print_error "Error: Failed to install kernel headers."; exit 1;
    }
    print_success "Kernel headers installed successfully."
}

install_media_codecs() {
    print_info "Installing media codecs (Fedora 42+ compatible)..."

    # GStreamer codecs
    sudo $DNF_CMD groupupdate --with-optional Multimedia -y
    sudo $DNF_CMD install -y \
        gstreamer1-plugins-base \
        gstreamer1-plugins-good \
        gstreamer1-plugins-bad-free \
        gstreamer1-plugins-bad-freeworld \
        gstreamer1-plugins-ugly \
        gstreamer1-libav

    # MP3 / AAC / etc.
    sudo $DNF_CMD install -y \
        lame\* --exclude=lame-devel \
        x264 x265 a52dec faad2 faac libmad libdca

    print_success "Media codecs installed successfully for Fedora 42."
}

enable_hw_video_acceleration() {
    print_info "Enabling hardware video acceleration..."
    sudo $DNF_CMD install -y ffmpeg ffmpeg-libs libva libva-utils
    sudo $DNF_CMD install -y mesa-va-drivers mesa-vdpau-drivers
    sudo $DNF_CMD upgrade -y
    print_success "Hardware video acceleration enabled successfully."
}

install_openh264_for_firefox() {
    print_info "Installing OpenH264 for Firefox..."
    sudo $DNF_CMD install -y 'dnf-plugins-core'
    sudo $DNF_CMD config-manager --set-enabled fedora-cisco-openh264
    sudo $DNF_CMD install -y openh264 gstreamer1-plugin-openh264 mozilla-openh264
    print_success "OpenH264 for Firefox installed successfully."
}

install_zsh() {
    print_info "Installing ZSH and Oh-My-ZSH..."
    sudo $DNF_CMD install -y zsh
    yes | sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    print_success "ZSH and Oh-My-ZSH installed successfully."
}

install_zsh_plugins() {
    print_info "Installing ZSH plugins..."
    git clone https://github.com/zsh-users/zsh-autosuggestions ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting
    print_success "ZSH plugins installed successfully."
}

change_shell_to_zsh() {
    print_info "Changing shell to ZSH..."
    sudo chsh -s "$(which zsh)" "$USER"
    print_success "Shell changed to ZSH."
}

move_zshrc() {
    print_info "Copying .zshrc to Home Folder..."
    cp "$HOME/fedorainstaller/configs/.zshrc" "$HOME/"
    sed -i '/^plugins=/c\plugins=(git zsh-autosuggestions zsh-syntax-highlighting)' "$HOME/.zshrc"
    print_success ".zshrc copied and configured successfully."
}

install_starship() {
    print_info "Installing Starship prompt..."
    curl -sS https://starship.rs/install.sh | sh -s -- -y && {
        mkdir -p "$HOME/.config"
        if [ -f "$HOME/fedorainstaller/configs/starship.toml" ]; then
            mv "$HOME/fedorainstaller/configs/starship.toml" "$HOME/.config/starship.toml"
            print_success "Starship prompt installed successfully."
        else
            print_warning "starship.toml not found in $HOME/fedorainstaller/configs/"
        fi
    } || print_error "Starship prompt installation failed."
}

add_flathub_repo() {
    if ! command -v flatpak &>/dev/null; then
        print_info "Flatpak not found. Installing..."
        sudo $DNF_CMD install -y flatpak
    fi
    print_info "Adding Flathub repository..."
    sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    sudo flatpak update
    print_success "Flathub repository added successfully."
}

install_programs() {
    print_info "Installing Programs..."
    (cd "$HOME/fedorainstaller/scripts" && ./programs.sh)
    print_success "Programs installed successfully."
    install_flatpak_programs
}

install_flatpak_programs() {
    print_info "Installing Flatpak Programs..."
    (cd "$HOME/fedorainstaller/scripts" && ./flatpak_programs.sh)
    print_success "Flatpak programs installed successfully."
}

install_nerd_fonts() {
    print_info "Installing Hack Nerd Font..."
    
    # Create fonts directory if it doesn't exist
    mkdir -p ~/.local/share/fonts
    
    # Get the latest Nerd Fonts version from GitHub
    print_info "Fetching latest Nerd Fonts version..."
    NERD_FONT_VERSION=$(curl -s https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest | grep -oP '"tag_name": "\K(.*)(?=")')
    
    if [ -z "$NERD_FONT_VERSION" ]; then
        print_error "Failed to fetch latest Nerd Fonts version"
        return 1
    fi
    
    print_info "Latest Nerd Fonts version: ${NERD_FONT_VERSION}"
    FONT_NAME="Hack"
    
    print_info "Installing $FONT_NAME Nerd Font..."
    url="https://github.com/ryanoasis/nerd-fonts/releases/download/${NERD_FONT_VERSION}/${FONT_NAME}.zip"
    
    # Download and install font
    if curl --head --silent --fail "$url" > /dev/null; then
        wget -q --show-progress -O "/tmp/${FONT_NAME}.zip" "$url"
        if [ $? -eq 0 ]; then
            unzip -q -o "/tmp/${FONT_NAME}.zip" -d ~/.local/share/fonts/
            rm "/tmp/${FONT_NAME}.zip"
            print_success "Successfully installed $FONT_NAME Nerd Font"
            
            # Update font cache
            fc-cache -fv
            
            # Set Hack Nerd Font as default for Konsole
            if command -v konsole &>/dev/null; then
                print_info "Setting Hack Nerd Font as default for Konsole..."
                mkdir -p ~/.local/share/konsole
                cat > ~/.local/share/konsole/Default.profile << EOF
[Appearance]
ColorScheme=Breeze
Font=Hack Nerd Font,10,-1,5,50,0,0,0,0,0
EOF
                print_success "Konsole font configured"
            fi
            
            # Set Hack Nerd Font as default for GNOME Terminal (kgx)
            if command -v kgx &>/dev/null; then
                print_info "Setting Hack Nerd Font as default for GNOME Terminal..."
                gsettings set org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$(gsettings get org.gnome.Terminal.ProfilesList default | tr -d \')/ font 'Hack Nerd Font 10'
                print_success "GNOME Terminal font configured"
            fi
            
            # Verify installation
            if fc-list | grep -i "hack.*nerd" > /dev/null; then
                print_success "Hack Nerd Font installed and configured successfully"
            else
                print_warning "Hack Nerd Font not found after installation. Please check the installation manually."
            fi
        else
            print_error "Failed to download Hack Nerd Font"
        fi
    else
        print_error "Hack Nerd Font not found at version ${NERD_FONT_VERSION}"
    fi
}

enable_services() {
    print_info "Enabling Services..."
    services=("fstrim.timer" "bluetooth" "sshd" "firewalld")
    for service in "${services[@]}"; do
        sudo systemctl enable --now "$service"
    done
    print_success "Services enabled successfully."
}

create_fastfetch_config() {
    print_info "Creating fastfetch config..."
    fastfetch --gen-config
    cp "$HOME/fedorainstaller/configs/config.jsonc" "$HOME/.config/fastfetch/config.jsonc"
    print_success "Fastfetch config created and copied."
}

configure_firewalld() {
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
    print_info "Clearing Unused Packages and Cache..."
    sudo $DNF_CMD autoremove -y
    sudo $DNF_CMD clean all
    print_success "Unused packages and cache cleared successfully."
}

delete_fedorainstaller_folder() {
    print_info "Deleting Fedorainstaller Folder..."
    sudo rm -rf "$HOME/fedorainstaller"
    print_success "Fedorainstaller folder deleted successfully."
}

reboot_system() {
    print_info "Rebooting System..."
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

# Run the setup
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
delete_fedorainstaller_folder
reboot_system
