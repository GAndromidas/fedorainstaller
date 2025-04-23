#!/bin/bash

# Script: programs.sh
# Description: Installs and removes packages based on detected desktop environment (GNOME/KDE).
# Compatible with Fedora 42, including COPR support for 'eza'.

# Function to detect the desktop environment
detect_desktop_environment() {
    echo "🔍 Detecting desktop environment..."
    local desktop="${XDG_CURRENT_DESKTOP,,}"  # lowercase
    echo "Current Desktop: $XDG_CURRENT_DESKTOP"

    if [[ "$desktop" == *"kde"* ]]; then
        echo "🖼️  KDE detected."
        specific_install_programs=("${kde_install_programs[@]}")
        specific_remove_programs=("${kde_remove_programs[@]}")
    elif [[ "$desktop" == *"gnome"* ]]; then
        echo "🖼️  GNOME detected."
        specific_install_programs=("${gnome_install_programs[@]}")
        specific_remove_programs=("${gnome_remove_programs[@]}")
    else
        echo "⚠️  Unknown desktop environment. Proceeding with essential programs only."
        specific_install_programs=()
        specific_remove_programs=()
    fi
}

# Function to remove unwanted default programs
remove_programs() {
    echo -e "\n🔻 Removing unnecessary default programs..."
    if [ ${#specific_remove_programs[@]} -eq 0 ]; then
        echo "No default programs to remove."
        return
    fi

    if ! sudo dnf remove -y "${specific_remove_programs[@]}"; then
        echo "❌ Failed to remove one or more programs."
    else
        echo "✅ Unwanted programs removed successfully."
    fi
}

# Function to install useful programs
install_programs() {
    echo -e "\n📦 Installing selected programs..."

    # Enable COPR for 'eza' if not installed
    if ! command -v eza &> /dev/null; then
        echo "🔧 Enabling COPR for 'eza'..."
        sudo dnf copr enable alternateved/eza -y
    fi

    # Combine essential + DE-specific
    local all_programs=("${essential_programs[@]}" "${specific_install_programs[@]}")

    if ! sudo dnf install -y "${all_programs[@]}"; then
        echo "❌ Failed to install one or more packages."
        exit 1
    else
        echo -e "\n✅ All programs installed successfully!"
    fi
}

# Essential CLI and GUI programs (COPR: eza)
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
)

# KDE-specific installs and removals
kde_install_programs=(
    kvantum
    qbittorrent
    vlc
)

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
)

# GNOME-specific installs and removals
gnome_install_programs=(
    celluloid
    dconf-editor
    gnome-disk-utility
    gnome-tweaks
    seahorse
    transmission-gtk
)

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
)

# Execute workflow
detect_desktop_environment
remove_programs
install_programs
