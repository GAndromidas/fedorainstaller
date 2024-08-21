#!/bin/bash

# Script: install.sh
# Description: Script for setting up a Fedora system with various configurations and installations.
# Author: George Andromidas

# ASCII art
clear
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
CYAN='\033[0;36m'
RESET='\033[0m'

# Function to print messages with colors
print_info() {
    echo -e "${CYAN}$1${RESET}"
}

print_success() {
    echo -e "${GREEN}$1${RESET}"
}

print_warning() {
    echo -e "${YELLOW}$1${RESET}"
}

print_error() {
    echo -e "${RED}$1${RESET}"
}

# Function to set the hostname
set_hostname() {
    print_info "Please enter the desired hostname:"
    read -p "Hostname: " hostname
    sudo hostnamectl set-hostname "$hostname"
    if [ $? -ne 0 ]; then
        print_error "Error: Failed to set the hostname."
        exit 1
    else
        print_success "Hostname set to $hostname successfully."
    fi
}

# Function to enable asterisks for password in sudoers
enable_asterisks_sudo() {
    print_info "Enabling password feedback in sudoers..."
    echo "Defaults pwfeedback" | sudo tee -a /etc/sudoers.d/pwfeedback > /dev/null
    print_success "Password feedback enabled in sudoers."
}

# Function to configure DNF
configure_dnf() {
    print_info "Configuring DNF..."
    sudo tee -a /etc/dnf/dnf.conf <<EOL
fastestmirror=True
max_parallel_downloads=10
defaultyes=True
EOL
    print_success "DNF configuration updated successfully."
}

# Function to enable RPM Fusion repositories
enable_rpm_fusion() {
    print_info "Enabling RPM Fusion repositories..."
    sudo dnf install -y https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm
    sudo dnf install -y https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
    print_success "RPM Fusion repositories enabled successfully."
}

# Function to update the system
update_system() {
    print_info "Updating system..."
    sudo dnf upgrade --refresh -y
    sudo dnf groupupdate core -y
    print_success "System updated successfully."
}

# Function to install kernel headers
install_kernel_headers() {
    print_info "Installing kernel headers..."
    sudo dnf install -y kernel-headers kernel-devel
    if [ $? -ne 0 ]; then
        print_error "Error: Failed to install kernel headers."
        exit 1
    else
        print_success "Kernel headers installed successfully."
    fi
}

# Function to install media codecs
install_media_codecs() {
    print_info "Installing media codecs..."
    sudo dnf install -y gstreamer1-plugins-{bad-\*,good-\*,base} gstreamer1-plugin-openh264 gstreamer1-libav --exclude=gstreamer1-plugins-bad-free-devel
    sudo dnf install -y lame\* --exclude=lame-devel
    sudo dnf group upgrade -y --with-optional Multimedia
    print_success "Media codecs installed successfully."
}

# Function to enable hardware video acceleration
enable_hw_video_acceleration() {
    print_info "Enabling hardware video acceleration..."
    sudo dnf install -y ffmpeg ffmpeg-libs libva libva-utils
    sudo dnf install -y mesa-va-drivers mesa-vdpau-drivers
    sudo dnf upgrade -y
    print_success "Hardware video acceleration enabled successfully."
}

# Function to install OpenH264 for Firefox
install_openh264_for_firefox() {
    print_info "Installing OpenH264 for Firefox..."
    sudo dnf config-manager --set-enabled fedora-cisco-openh264
    sudo dnf install -y openh264 gstreamer1-plugin-openh264 mozilla-openh264
    print_success "OpenH264 for Firefox installed successfully."
}

# Function to install ZSH and Oh-My-ZSH
install_zsh() {
    print_info "Installing ZSH and Oh-My-ZSH..."
    sudo dnf install -y zsh
    yes | sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    print_success "ZSH and Oh-My-ZSH installed successfully."
}

# Function to install ZSH plugins
install_zsh_plugins() {
    print_info "Installing ZSH plugins..."
    git clone https://github.com/zsh-users/zsh-autosuggestions ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting
    print_success "ZSH plugins installed successfully."
}

# Function to change shell to ZSH
change_shell_to_zsh() {
    print_info "Changing shell to ZSH..."
    sudo chsh -s "$(which zsh)" $USER
    print_success "Shell changed to ZSH."
}

# Function to move .zshrc
move_zshrc() {
    print_info "Copying .zshrc to Home Folder..."
    cp "$HOME/fedorainstaller/configs/.zshrc" "$HOME/"
    sed -i '/^plugins=/c\plugins=(git zsh-autosuggestions zsh-syntax-highlighting)' "$HOME/.zshrc"
    print_success ".zshrc copied and configured successfully."
}

# Function to install Starship prompt
install_starship() {
    print_info "Installing Starship prompt..."
    curl -sS https://starship.rs/install.sh | sh -s -- -y
    if [ $? -eq 0 ]; then
        mkdir -p "$HOME/.config"
        if [ -f "$HOME/fedorainstaller/configs/starship.toml" ]; then
            mv "$HOME/fedorainstaller/configs/starship.toml" "$HOME/.config/starship.toml"
            print_success "Starship prompt installed successfully."
            print_success "starship.toml moved to $HOME/.config/"
        else
            print_warning "starship.toml not found in $HOME/fedorainstaller/configs/"
        fi
    else
        print_error "Starship prompt installation failed."
    fi
}

# Function to add Flathub repository
add_flathub_repo() {
    print_info "Adding Flathub repository..."
    sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    sudo flatpak update
    print_success "Flathub repository added successfully."
}

# Function to install programs
install_programs() {
    print_info "Installing Programs..."
    (cd "$HOME/fedorainstaller/scripts" && ./programs.sh)
    print_success "Programs installed successfully."
    install_flatpak_programs
}

# Function to install flatpak programs
install_flatpak_programs() {
    print_info "Installing Flatpak Programs..."
    (cd "$HOME/fedorainstaller/scripts" && ./flatpak_programs.sh)
    print_success "Flatpak programs installed successfully."
}

# Function to install multiple Nerd Fonts
install_nerd_fonts() {
    print_info "Installing Nerd Fonts..."
    mkdir -p ~/.local/share/fonts
    fonts=("Hack" "FiraCode" "JetBrainsMono" "Noto")
    for font in "${fonts[@]}"; do
        wget -O "$font.zip" "https://github.com/ryanoasis/nerd-fonts/releases/download/v2.1.0/$font.zip"
        unzip -o "$font.zip" -d ~/.local/share/fonts/
        rm "$font.zip"
    done
    fc-cache -fv
    print_success "Nerd Fonts installed successfully."
}

# Function to enable services
enable_services() {
    print_info "Enabling Services..."
    local services=(
        "fstrim.timer"
        "bluetooth"
        "sshd"
        "firewalld"
    )
    for service in "${services[@]}"; do
        sudo systemctl enable --now "$service"
    done
    print_success "Services enabled successfully."
}

# Function to create fastfetch config
create_fastfetch_config() {
    print_info "Creating fastfetch config..."
    fastfetch --gen-config
    print_success "fastfetch config created successfully."
    print_info "Copying fastfetch config from repository to ~/.config/fastfetch/..."
    cp "$HOME/fedorainstaller/configs/config.jsonc" "$HOME/.config/fastfetch/config.jsonc"
    print_success "fastfetch config copied successfully."
}

# Function to configure firewall
configure_firewalld() {
    print_info "Configuring Firewalld..."
    sudo dnf install -y firewalld
    sudo systemctl start firewalld
    sudo systemctl enable firewalld
    sudo firewall-cmd --permanent --set-default-zone=public
    sudo firewall-cmd --permanent --add-service=ssh
    if rpm -q kde-connect &> /dev/null; then
        sudo firewall-cmd --permanent --add-port=1714-1764/tcp
        sudo firewall-cmd --permanent --add-port=1714-1764/udp
    fi
    sudo firewall-cmd --reload
    print_success "Firewalld configured successfully."
}

# Function to clear unused packages and cache
clear_unused_packages_cache() {
    print_info "Clearing Unused Packages and Cache..."
    sudo dnf autoremove -y
    sudo dnf clean all
    print_success "Unused packages and cache cleared successfully."
}

# Function to delete the fedorainstaller folder
delete_fedorainstaller_folder() {
    print_info "Deleting Fedorainstaller Folder..."
    sudo rm -rf "$HOME/fedorainstaller"
    print_success "Fedorainstaller folder deleted successfully."
}

# Function to reboot system
reboot_system() {
    print_info "Rebooting System..."
    printf "${YELLOW}Do you want to reboot now? (Y/n)${RESET} "

    read -rp "" confirm_reboot

    # Convert input to lowercase for case-insensitive comparison
    confirm_reboot="${confirm_reboot,,}"

    # Handle empty input (Enter pressed)
    if [[ -z "$confirm_reboot" ]]; then
        confirm_reboot="y"  # Apply "yes" if Enter is pressed
    fi

    # Validate input
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

# Call functions in the desired order
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
