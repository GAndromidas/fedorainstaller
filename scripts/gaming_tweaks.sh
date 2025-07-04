#!/bin/bash
# Gaming and performance tweaks installation
source "$(dirname "$0")/../common.sh"

step "Gaming and performance tweaks"

# Check if user wants gaming tweaks (default to No)
print_info "Would you like to install gaming and performance tweaks? (y/N): "
read -r response
response="${response:-N}"  # Default to N if empty
if [[ ! "$response" =~ ^[Yy]$ ]]; then
    print_info "Gaming tweaks skipped."
    exit 0
fi

# Install MangoHud for performance monitoring
print_info "Installing MangoHud for performance monitoring..."
if ! rpm -q mangohud >/dev/null 2>&1; then
    if sudo $DNF_CMD install -y mangohud mangohud-32bit; then
        print_success "MangoHud installed successfully."
        INSTALLED_PACKAGES+=(mangohud mangohud-32bit)
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
        
        # Enable GameMode service
        if systemctl is-enabled gamemoded >/dev/null 2>&1; then
            print_info "GameMode service is already enabled."
        else
            print_info "Enabling GameMode service..."
            if sudo systemctl enable gamemoded; then
                print_success "GameMode service enabled."
            else
                print_error "Failed to enable GameMode service."
            fi
        fi
    else
        print_error "Failed to install GameMode."
    fi
else
    print_warning "GameMode is already installed. Skipping."
fi

# Install additional gaming utilities
print_info "Installing additional gaming utilities..."
GAMING_PACKAGES=(
    "steam"
    "lutris"
    "wine"
    "winetricks"
    "dxvk"
    "vkd3d"
    "lib32-dxvk"
    "lib32-vkd3d"
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

# Create MangoHud configuration directory and basic config
if command -v mangohud >/dev/null; then
    print_info "Creating MangoHud configuration..."
    mkdir -p "$HOME/.config/MangoHud"
    
    if [ ! -f "$HOME/.config/MangoHud/MangoHud.conf" ]; then
        cat > "$HOME/.config/MangoHud/MangoHud.conf" << 'EOF'
# MangoHud Configuration
toggle_hud=Shift_R+F12
toggle_logging=Shift_L+F2
output_folder=/tmp/mangohud
log_interval=100
EOF
        print_success "MangoHud configuration created."
    else
        print_warning "MangoHud configuration already exists. Skipping."
    fi
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