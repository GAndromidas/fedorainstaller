#!/bin/bash

# Function to detect desktop environment and set specific programs to install or remove
detect_desktop_environment() {
    echo "Detecting desktop environment..."
    echo "Current Desktop: $XDG_CURRENT_DESKTOP"
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
    echo "Specific install programs: ${specific_install_programs[@]}"
    echo "Specific remove programs: ${specific_remove_programs[@]}"
}

# Function to remove programs
remove_programs() {
    echo
    printf "Removing Programs... \n"
    echo
    if [ ${#specific_remove_programs[@]} -eq 0 ]; then
        echo "No programs to remove."
    else
        sudo dnf remove -y "${specific_remove_programs[@]}"
        if [ $? -ne 0 ]; then
            echo "Error removing programs."
        else
            echo "Programs removed successfully."
        fi
    fi
}

# Function to install programs
install_programs() {
    echo
    printf "Installing Programs... \n"
    echo
    sudo dnf install -y "${essential_programs[@]}" "${specific_install_programs[@]}"
    if [ $? -eq 0 ]; then
        echo
        printf "Programs installed successfully.\n"
    else
        echo
        printf "Failed to install programs. Exiting...\n"
        exit 1
    fi
}

# Main script

# Essential programs to install using dnf
essential_programs=(
    android-tools
    bleachbit
    btop
    cmatrix
    eza
    fastfetch
    filezilla
    firefox
    firewall-config
    fzf
    gnome-disk-utility
    hwinfo
    inxi
    python3-speedtest-cli
    samba
    sl
    timeshift
    unrar
    zoxide
    # Add or remove essential programs as needed
)

# KDE-specific programs to install using dnf
kde_install_programs=(
    kvantum
    qbittorrent
    vlc
    # Add or remove KDE-specific programs as needed
)

# KDE-specific programs to remove using dnf
kde_remove_programs=(
    dragonplayer
    elisa-player
    htop
    kaddressbook
    kamoso
    kmahjongg
    kmail
    kmines
    kmouth
    kolourpaint
    korganizer
    kpat
    ktnef
    neochat
    pim-sieve-editor
    skanpage
    # Add other KDE-specific programs to remove if needed
)

# GNOME-specific programs to install using dnf
gnome_install_programs=(
    celluloid
    dconf-editor
    gnome-disk-utility
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
    rhythmbox
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
