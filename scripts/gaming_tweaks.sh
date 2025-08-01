#!/bin/bash
# Gaming and performance tweaks installation
source "$(dirname "$0")/../common.sh"

step "Gaming and performance tweaks"

# Check if user wants gaming tweaks (default to No)
echo -e "\n${YELLOW}═══════════════════════════════════════════════════════════════${RESET}"
echo -e "${CYAN}🎮 GAMING & PERFORMANCE TWEAKS${RESET}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${RESET}"
echo -e "${CYAN}Would you like to install gaming and performance tweaks?${RESET}"
echo -e "${YELLOW}This includes: MangoHud, GameMode, Steam, Lutris, Wine, and more.${RESET}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${RESET}"
read -r -p "Enter Y to install gaming tweaks, or press Enter to skip: " response
response="${response:-N}"  # Default to N if empty
if [[ ! "$response" =~ ^[Yy]$ ]]; then
    print_info "Gaming tweaks skipped."
    echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${RESET}\n"
    exit 0
fi
echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${RESET}\n"

# Install MangoHud for performance monitoring
print_info "Installing MangoHud for performance monitoring..."
if ! rpm -q mangohud >/dev/null 2>&1; then
    if sudo $DNF_CMD install -y mangohud; then
        print_success "MangoHud installed successfully."
        INSTALLED_PACKAGES+=(mangohud)
    else
        print_error "Failed to install MangoHud."
    fi
else
    print_warning "MangoHud is already installed. Skipping."
fi

# Install GameMode if not already installed
if ! command -v gamemoded >/dev/null; then
    print_info "Installing GameMode for performance optimization..."
    if sudo $DNF_CMD install -y gamemode; then
        print_success "GameMode installed successfully."
        INSTALLED_PACKAGES+=(gamemode)
        print_info "GameMode installed. You can manually enable the service later if needed."
    else
        print_error "Failed to install GameMode."
    fi
else
    print_warning "GameMode is already installed. Skipping."
fi

# Install additional gaming utilities (removed non-existent packages)
print_info "Installing additional gaming utilities..."
GAMING_PACKAGES=(
    "steam"
    "lutris"
    "wine"
)

for package in "${GAMING_PACKAGES[@]}"; do
    if ! rpm -q "$package" >/dev/null 2>&1; then
        print_info "Installing $package..."
        if sudo $DNF_CMD install -y "$package"; then
            print_success "$package installed successfully."
            INSTALLED_PACKAGES+=("$package")
        else
            print_error "Failed to install $package."
        fi
    else
        print_warning "$package is already installed. Skipping."
    fi
done

# Copy MangoHud configuration
if rpm -q mangohud >/dev/null 2>&1 || command -v mangohud >/dev/null; then
    print_info "Configuring MangoHud..."
    MANGOHUD_CONFIG_DIR="$HOME/.config/MangoHud"
    MANGOHUD_CONFIG_SOURCE="$(dirname "$0")/../configs/MangoHud.conf"

    # Create MangoHud config directory if it doesn't exist
    if ! mkdir -p "$MANGOHUD_CONFIG_DIR" 2>/dev/null; then
        print_error "Failed to create MangoHud config directory: $MANGOHUD_CONFIG_DIR"
    else
        # Copy MangoHud configuration file, replacing if it exists
        if [ -f "$MANGOHUD_CONFIG_SOURCE" ]; then
            if cp "$MANGOHUD_CONFIG_SOURCE" "$MANGOHUD_CONFIG_DIR/MangoHud.conf" 2>/dev/null; then
                # Set proper permissions
                chmod 644 "$MANGOHUD_CONFIG_DIR/MangoHud.conf" 2>/dev/null || true

                # Verify the config was copied correctly
                if [ -f "$MANGOHUD_CONFIG_DIR/MangoHud.conf" ] && [ -s "$MANGOHUD_CONFIG_DIR/MangoHud.conf" ]; then
                    print_success "MangoHud configuration copied and verified at: $MANGOHUD_CONFIG_DIR/MangoHud.conf"
                else
                    print_error "MangoHud configuration file is empty or corrupted after copy"
                fi
            else
                print_error "Failed to copy MangoHud configuration file"
            fi
        else
            print_warning "MangoHud configuration file not found at: $MANGOHUD_CONFIG_SOURCE"
            print_info "Expected path: $(realpath "$(dirname "$0")/../configs/MangoHud.conf" 2>/dev/null || echo "N/A")"
        fi
    fi
else
    print_warning "MangoHud not installed, skipping configuration."
fi

# Install additional gaming-related Flatpaks
print_info "Installing gaming-related Flatpaks..."
GAMING_FLATPAKS=(
    "com.heroicgameslauncher.hgl"
)

# Add ProtonUp tools based on desktop environment
if [ "$XDG_CURRENT_DESKTOP" ]; then
    case "${XDG_CURRENT_DESKTOP,,}" in
        *gnome*|*cosmic*)
            print_info "Detected GNOME/Cosmic desktop, adding ProtonPlus..."
            GAMING_FLATPAKS+=("com.vysp3r.ProtonPlus")
            ;;
        *kde*)
            print_info "Detected KDE Plasma desktop, adding ProtonUp-Qt..."
            GAMING_FLATPAKS+=("net.davidotek.pupgui2")
            ;;
    esac
fi

# Ensure Flatpak daemon is running
if ! flatpak ps >/dev/null 2>&1; then
    print_info "Starting Flatpak daemon..."
    flatpak ps >/dev/null 2>&1 || true
fi

for flatpak in "${GAMING_FLATPAKS[@]}"; do
    if ! flatpak list | grep -q "$flatpak"; then
        print_info "Installing $flatpak..."
        if timeout 600 flatpak install -y flathub "$flatpak" 2>/dev/null; then
            print_success "$flatpak installed successfully."
        else
            print_warning "Failed to install $flatpak (timeout or error). Skipping."
            # Try to kill any stuck Flatpak processes
            pkill -f "flatpak.*install" 2>/dev/null || true
        fi
    else
        print_warning "$flatpak is already installed. Skipping."
    fi

    # Small delay between installations
    sleep 2
done

print_success "Gaming and performance tweaks installation completed."
