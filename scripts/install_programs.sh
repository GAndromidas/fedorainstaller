#!/bin/bash

# Function to detect desktop environment and set specific programs to install or remove
detect_desktop_environment() {
    if [ "$XDG_CURRENT_DESKTOP" == "KDE" ]; then
        echo "KDE detected."
        specific_install_programs=("${kde_install_programs[@]}")
        specific_remove_programs=("${kde_remove_programs[@]}")
        kde_environment=true
    elif [ "$XDG_CURRENT_DESKTOP" == "GNOME" ]; then
        echo "GNOME detected."
        specific_install_programs=("${gnome_install_programs[@]}")
        specific_remove_programs=("${gnome_remove_programs[@]}")
        kde_environment=false
    else
        echo "Unsupported desktop environment detected."
        specific_install_programs=()
        specific_remove_programs=()
        kde_environment=false
    fi
}

# Function to remove programs
remove_programs() {
    echo
    printf "Removing Programs... \n"
    echo
    sudo dnf remove -y "${specific_remove_programs[@]}"
    echo
    printf "Programs removed successfully.\n"
}

# Function to install programs
install_programs() {
    echo
    printf "Installing Programs... \n"
    echo
    sudo dnf install -y "${pacman_programs[@]}" "${essential_programs[@]}" "${specific_install_programs[@]}"
    echo
    printf "Programs installed successfully.\n"

    # If KDE environment and KDE Connect is installed, configure KDE Connect firewall rules
    if $kde_environment && [[ " ${specific_install_programs[@]} " =~ " kdeconnect " ]]; then
        enable_kde_connect_firewall
    fi
}

# Function to enable KDE Connect firewall rules
enable_kde_connect_firewall() {
    echo
    printf "Configuring KDE Connect Firewall Rules... \n"
    echo
    sudo firewall-cmd --add-port=1714-1764/tcp --permanent
    sudo firewall-cmd --add-port=1714-1764/udp --permanent
    sudo firewall-cmd --reload
    echo
    printf "KDE Connect Firewall Rules configured successfully.\n"
}

# Main script

# Programs to install using dnf
pacman_programs=(
    android-tools
    bleachbit
    btop
    cmatrix
    curl
    dosfstools
    flatpak
    firewall-config
    fwupd
    gamemode
    gamescope
    gnome-disk-utility
    hwinfo
    inxi
    mangohud
    net-tools
    ntfs-3g
    os-prober
    p7zip
    p7zip-plugins
    python3-speedtest-cli
    samba
    sshfs
    sl
    unrar
    unzip
    util-linux-user
    wget
    wlroots
    xdg-desktop-portal-gtk
    zoxide
    # Add or remove programs as needed
)

# Essential programs to install using dnf
essential_programs=(
    discord
    chromium
    filezilla
    firefox
    gimp
    lutris
    obs-studio
    smplayer
    steam
    telegram
    timeshift
    wine
    # Add or remove essential programs as needed
)

# KDE-specific programs to install using dnf
kde_install_programs=(
    gwenview
    kdeconnect
    kwalletmanager
    kvantum
    okular
    qbittorrent
    spectacle
    vlc
    # Add or remove KDE-specific programs as needed
)

# KDE-specific programs to remove using dnf
kde_remove_programs=(
    htop
    kontact
    telepathy
    kget
    ktorrent
    elisa-player
    dragonplayer
    k3b
    marble
    parley
    kiten
    kalzium
    # Add other KDE-specific programs to remove if needed
)

# GNOME-specific programs to install using dnf
gnome_install_programs=(
    celluloid
    dconf-editor
    gnome-tweaks
    seahorse
    transmission-gtk
    # Add or remove GNOME-specific programs as needed
)

# GNOME-specific programs to remove using dnf
gnome_remove_programs=(
    epiphany
    gnome-contacts
    gnome-maps
    gnome-music
    gnome-tour
    htop
    snapshot
    totem
    # Add other GNOME-specific programs to remove if needed
)

# Detect desktop environment
detect_desktop_environment

# Remove specified programs
remove_programs

# Install specified programs
install_programs
