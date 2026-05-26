#!/bin/bash
# Gaming and performance tweaks installation
# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

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

# Install gaming packages using unified batch installation
print_info "Installing gaming packages..."
GAMING_PACKAGES=(
    "mangohud"
    "gamemode"
    "steam"
    "goverlay"
)

install_packages_batch "dnf" "${GAMING_PACKAGES[@]}"

if command -v gamemoded >/dev/null; then
    print_info "GameMode installed. You can manually enable the service later if needed."
fi

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

# Install additional gaming-related Flatpaks using unified batch installation
print_info "Installing gaming-related Flatpaks..."
GAMING_FLATPAKS=(
    "com.heroicgameslauncher.hgl"
    "io.github.Faugus.faugus-launcher"
    "com.discordapp.Discord"
    "com.vysp3r.ProtonPlus"
)

# Ensure Flatpak daemon is running
if ! flatpak ps >/dev/null 2>&1; then
    print_info "Starting Flatpak daemon..."
    flatpak ps >/dev/null 2>&1 || true
fi

# Use unified batch installation for Flatpaks
install_packages_batch "flatpak" "${GAMING_FLATPAKS[@]}"

print_success "Gaming and performance tweaks installation completed."
