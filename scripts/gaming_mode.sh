#!/bin/bash
# Gaming and performance tweaks installation
# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

step "Gaming and performance tweaks"

{
  echo -e "\n${THEME_BORDER}═══════════════════════════════════════════════════════════════${RESET}"
  echo -e "${THEME_HEADER}  GAMING & PERFORMANCE TWEAKS${RESET}"
  echo -e "${THEME_TEXT}  Includes: MangoHud, GameMode, Steam, GOverlay, Heroic Launcher, Discord, and more.${RESET}"
  echo -e "${THEME_BORDER}═══════════════════════════════════════════════════════════════${RESET}"
} >/dev/tty

if supports_gum; then
    if gum confirm "Install gaming and performance tweaks?" --default=true 2>/dev/tty; then
        :
    else
        print_info "Gaming tweaks skipped."
        return 0
    fi
else
    echo -n "Install gaming tweaks? [Y/n]: " >/dev/tty
    read -r response </dev/tty
    response="${response:-Y}"
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        print_info "Gaming tweaks skipped."
        return 0
    fi
fi

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
    MANGOHUD_CONFIG_SOURCE="$SCRIPT_DIR/../configs/MangoHud.conf"

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
            print_info "Expected path: $(realpath "$SCRIPT_DIR/../configs/MangoHud.conf" 2>/dev/null || echo "N/A")"
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
