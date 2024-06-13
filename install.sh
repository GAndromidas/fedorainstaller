#!/bin/bash

# Script: install.sh
# Description: Script for setting up a Fedora 40 system with various configurations and installations.
# Author: George Andromidas

# Function to set the hostname
set_hostname() {
    echo "Please enter the desired hostname:"
    read -p "Hostname: " hostname
    sudo hostnamectl set-hostname "$hostname"
    if [ $? -ne 0 ]; then
        echo "Error: Failed to set the hostname."
        exit 1
    else
        echo "Hostname set to $hostname successfully."
    fi
}

# Function to enable asterisks for password in sudoers
enable_asterisks_sudo() {
    echo "Enabling password feedback in sudoers..."
    echo "Defaults pwfeedback" | sudo tee -a /etc/sudoers.d/pwfeedback
    echo "Password feedback enabled in sudoers."
}

# Function to configure DNF
configure_dnf() {
    echo "Configuring DNF..."
    sudo tee -a /etc/dnf/dnf.conf <<EOL
fastestmirror=True
max_parallel_downloads=10
defaultyes=True
EOL
    echo "DNF configuration updated successfully."
}

# Function to enable RPM Fusion repositories
enable_rpm_fusion() {
    echo "Enabling RPM Fusion repositories..."
    sudo dnf install -y https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm
    sudo dnf install -y https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
    echo "RPM Fusion repositories enabled successfully."
}

# Function to update the system
update_system() {
    echo "Updating system..."
    # Perform a full system upgrade and refresh the package cache
    sudo dnf upgrade --refresh -y
    # Update the core group of packages
    sudo dnf groupupdate core -y
    echo "System updated successfully."
}

# Function to install kernel headers
install_kernel_headers() {
    echo "Installing kernel headers..."
    sudo dnf install -y kernel-headers kernel-devel
    if [ $? -ne 0 ]; then
        echo "Error: Failed to install kernel headers."
        exit 1
    else
        echo "Kernel headers installed successfully."
    fi
}

# Function to install media codecs
install_media_codecs() {
    echo "Installing media codecs..."
    sudo dnf install -y gstreamer1-plugins-{bad-\*,good-\*,base} gstreamer1-plugin-openh264 gstreamer1-libav --exclude=gstreamer1-plugins-bad-free-devel
    sudo dnf install -y lame\* --exclude=lame-devel
    sudo dnf group upgrade -y --with-optional Multimedia
    echo "Media codecs installed successfully."
}

# Function to enable hardware video acceleration
enable_hw_video_acceleration() {
    echo "Enabling hardware video acceleration..."

    # Install required packages if not already installed
    sudo dnf install -y ffmpeg ffmpeg-libs libva libva-utils

    # Swap mesa drivers if necessary
    sudo dnf install -y mesa-va-drivers mesa-vdpau-drivers  # Install if not already present

    # Upgrade all packages to ensure dependencies are correctly resolved
    sudo dnf upgrade -y

    echo "Hardware video acceleration enabled successfully."
}

# Function to install OpenH264 for Firefox
install_openh264_for_firefox() {
    echo "Installing OpenH264 for Firefox..."
    sudo dnf config-manager --set-enabled fedora-cisco-openh264
    sudo dnf install -y openh264 gstreamer1-plugin-openh264 mozilla-openh264
    echo "OpenH264 for Firefox installed successfully."
}

# Function to install ZSH and Oh-My-ZSH
install_zsh() {
    echo "Installing ZSH and Oh-My-ZSH..."
    sudo dnf install -y zsh
    yes | sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    echo "ZSH and Oh-My-ZSH installed successfully."
}

# Function to install ZSH plugins
install_zsh_plugins() {
    echo "Installing ZSH plugins..."
    git clone https://github.com/zsh-users/zsh-autosuggestions ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions
    git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting
    echo "ZSH plugins installed successfully."
}

# Function to change shell to ZSH
change_shell_to_zsh() {
    echo "Changing shell to ZSH..."
    sudo chsh -s "$(which zsh)" $USER
    echo "Shell changed to ZSH."
}

# Function to move .zshrc
move_zshrc() {
    echo "Copying .zshrc to Home Folder..."
    cp "$HOME"/fedorainstaller/configs/.zshrc "$HOME"/

    # Add plugins to .zshrc
    echo "Configuring .zshrc for plugins..."
    sed -i '/^plugins=/c\plugins=(git zsh-autosuggestions zsh-syntax-highlighting)' "$HOME/.zshrc"

    echo ".zshrc copied and configured successfully."
}

# Function to install Starship prompt
install_starship() {
    echo "Installing Starship prompt..."
    curl -sS https://starship.rs/install.sh | sh -s -- -y

    if [ $? -eq 0 ]; then
        echo "Starship prompt installed successfully."
        mkdir -p "$HOME/.config"
        if [ -f "$HOME/fedorainstaller/configs/starship.toml" ]; then
            mv "$HOME/fedorainstaller/configs/starship.toml" "$HOME/.config/starship.toml"
            echo "starship.toml moved to $HOME/.config/"
        else
            echo "starship.toml not found in $HOME/fedorainstaller/configs/"
        fi
    else
        echo "Starship prompt installation failed."
    fi
}

# Function to add Flathub repository
add_flathub_repo() {
    echo "Adding Flathub repository..."
    sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    sudo flatpak update
    echo "Flathub repository added successfully."
}

# Function to install programs
install_programs() {
    echo "Installing Programs..."
    (cd "$HOME/fedorainstaller/scripts" && ./install_programs.sh)
    echo "Programs installed successfully."

    install_flatpak_programs
}

# Function to install flatpak programs
install_flatpak_programs() {
    echo "Installing Flatpak Programs..."
    (cd "$HOME/fedorainstaller/scripts" && ./install_flatpak_programs.sh)
    echo "Flatpak programs installed successfully."
}

# Function to enable services
enable_services() {
    echo "Enabling Services..."
    local services=(
        "fstrim.timer"
        "bluetooth"
        "sshd"
        "firewalld"
    )

    for service in "${services[@]}"; do
        sudo systemctl enable --now "$service"
    done

    echo "Services enabled successfully."
}

# Function to create fastfetch config
create_fastfetch_config() {
    echo
    printf "Creating fastfetch config... "
    echo
    fastfetch --gen-config
    echo
    printf "fastfetch config created successfully.\n"

    echo
    printf "Copying fastfetch config from repository to ~/.config/fastfetch/... "
    echo
    cp "$HOME"/fedorainstaller/configs/config.jsonc "$HOME"/.config/fastfetch/config.jsonc
    echo
    printf "fastfetch config copied successfully.\n"
}

# Function to configure firewall
configure_firewalld() {
    echo "Configuring Firewalld..."
    sudo dnf install -y firewalld
    sudo systemctl start firewalld
    sudo systemctl enable firewalld
    sudo firewall-cmd --permanent --set-default-zone=public

    # Check if SSH service is already enabled
    sudo firewall-cmd --permanent --list-services | grep -q "\bssh\b"
    if [ $? -ne 0 ]; then
        sudo firewall-cmd --permanent --add-service=ssh
    else
        echo "SSH service is already enabled. Skipping..."
    fi

    # Check if KDE Connect is installed
    if rpm -q kde-connect &> /dev/null; then
        # KDE Connect is installed, enable ports
        sudo firewall-cmd --permanent --add-port=1714-1764/tcp
        sudo firewall-cmd --permanent --add-port=1714-1764/udp
        echo "KDE Connect ports enabled."
    else
        echo "KDE Connect is not installed. Skipping port configuration."
    fi

    sudo firewall-cmd --reload
    echo "Firewalld configured successfully."
}

# Function to install Nerd Fonts
install_nerd_fonts() {
    # Create directory for fonts if it doesn't exist
    mkdir -p ~/.local/share/fonts

    # Download Nerd Font (Replace URL with the desired Nerd Font version)
    wget -O ~/.local/share/fonts/Hack.zip https://github.com/ryanoasis/nerd-fonts/releases/download/v2.1.0/Hack.zip

    # Navigate to the fonts directory
    cd ~/.local/share/fonts

    # Unzip the downloaded font archive
    unzip Hack.zip

    # Clean up the zip file
    rm Hack.zip

    # Update font cache
    fc-cache -f -v

    echo "Nerd Fonts installed successfully!"

    # Optionally, remove the zip file after installation
    rm -f ~/.local/share/fonts/Hack.zip
}

# Function to clear unused packages and cache
clear_unused_packages_cache() {
    echo "Clearing Unused Packages and Cache..."
    sudo dnf autoremove -y
    sudo dnf clean all
    echo "Unused packages and cache cleared successfully."
}

# Function to delete the fedorainstaller folder
delete_fedorainstaller_folder() {
    echo "Deleting Fedorainstaller Folder..."
    sudo rm -rf "$HOME"/fedorainstaller
    echo "Fedorainstaller folder deleted successfully."
}

# Function to reboot system
reboot_system() {
    echo "Rebooting System..."
    echo "Press 'y' to reboot now, or 'n' to cancel."

    read -p "Do you want to reboot now? (y/n): " confirm_reboot

    while [[ ! "$confirm_reboot" =~ ^[yn]$ ]]; do
        read -p "Invalid input. Please enter 'y' to reboot now or 'n' to cancel: " confirm_reboot
    done

    if [[ "$confirm_reboot" == "y" ]]; then
        echo "Rebooting now..."
        sudo reboot
    else
        echo "Reboot canceled."
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
enable_services
create_fastfetch_config
configure_firewalld
install_nerd_fonts
clear_unused_packages_cache
delete_fedorainstaller_folder
reboot_system
