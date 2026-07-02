#!/bin/bash
set -uo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Peripheral detection for Fedora - adapted from archinstaller
# Intelligently detects and configures peripherals like Logitech mice, Keychron keyboards

# Skip detection on laptops
if is_laptop; then
    ui_info "Laptop system detected - skipping peripheral detection"
    ui_info "Peripheral detection is typically not needed on laptops"
    log_to_file "Laptop detected - peripheral detection skipped"
    exit 0
fi

step "Peripheral detection and configuration"

# Detect Logitech devices
detect_logitech_devices() {
    ui_info "Checking for Logitech devices..."
    
    if ! command -v lsusb &>/dev/null; then
        ui_warn "lsusb not found, skipping USB device detection"
        return 0
    fi
    
    local logitech_devices=$(lsusb | grep -i logitech)
    
    if [ -n "$logitech_devices" ]; then
        ui_success "Logitech devices detected:"
        echo "$logitech_devices"
        
        # Install Solaar for Logitech device management using unified batch installation
        ui_info "Installing Solaar for Logitech device management..."
        if install_packages_batch "dnf" "solaar"; then
            ui_success "Solaar installed successfully"
            
            # Enable Solaar service
            if systemctl list-unit-files | grep -q "^solaar.service"; then
                sudo systemctl enable --now solaar >/dev/null 2>&1
                ui_success "Solaar service enabled"
            fi
        else
            ui_warn "Failed to install Solaar"
        fi
    else
        ui_info "No Logitech devices detected"
    fi
}

# Detect Keychron keyboards
detect_keychron_devices() {
    ui_info "Checking for Keychron devices..."
    
    if ! command -v lsusb &>/dev/null; then
        ui_warn "lsusb not found, skipping USB device detection"
        return 0
    fi
    
    local keychron_devices=$(lsusb | grep -i keychron)
    
    if [ -n "$keychron_devices" ]; then
        ui_success "Keychron devices detected:"
        echo "$keychron_devices"
        
        # VIA is typically used for Keychron keyboard configuration
        # VIA is available as a Flatpak
        ui_info "VIA keyboard configurator is available as a Flatpak"
        ui_info "Install it with: flatpak install flathub com.vial.Vial"
    else
        ui_info "No Keychron devices detected"
    fi
}

# Detect Razer devices
detect_razer_devices() {
    ui_info "Checking for Razer devices..."
    
    if ! command -v lsusb &>/dev/null; then
        ui_warn "lsusb not found, skipping USB device detection"
        return 0
    fi
    
    local razer_devices=$(lsusb | grep -i razer)
    
    if [ -n "$razer_devices" ]; then
        ui_success "Razer devices detected:"
        echo "$razer_devices"
        
        # Install OpenRazer for Razer device management
        if ! rpm -q openrazer &>/dev/null; then
            ui_info "Installing OpenRazer for Razer device management..."
            # OpenRazer may not be in Fedora repos, check COPR
            if sudo $DNF_CMD copr search openrazer &>/dev/null; then
                ui_info "OpenRazer available via COPR"
                ui_info "Enable with: sudo dnf copr enable openrazer/release"
                ui_info "Install with: sudo dnf install openrazer"
            else
                ui_warn "OpenRazer not found in available repositories"
            fi
        else
            ui_info "OpenRazer already installed"
        fi
        
        # Install Polychromatic for GUI configuration
        if ! rpm -q polychromatic &>/dev/null; then
            ui_info "Polychromatic GUI for OpenRazer is available"
            ui_info "Install with: sudo dnf install polychromatic"
        fi
    else
        ui_info "No Razer devices detected"
    fi
}

# Detect Bluetooth devices
detect_bluetooth_devices() {
    ui_info "Checking for Bluetooth devices..."
    
    if ! command -v bluetoothctl &>/dev/null; then
        ui_warn "bluetoothctl not found, skipping Bluetooth device detection"
        return 0
    fi
    
    # Check if bluetooth service is running
    if ! systemctl is-active bluetooth &>/dev/null; then
        ui_info "Bluetooth service not running, starting it..."
        sudo systemctl start bluetooth >/dev/null 2>&1
    fi
    
    # Get paired devices
    local paired_devices=$(bluetoothctl paired-devices 2>/dev/null || echo "")
    
    if [ -n "$paired_devices" ]; then
        ui_success "Bluetooth paired devices detected:"
        echo "$paired_devices"
    else
        ui_info "No paired Bluetooth devices found"
    fi
}

# Main execution
main() {
    echo -e "${CYAN}=== Peripheral Detection ===${RESET}"
    
    detect_logitech_devices
    detect_keychron_devices
    detect_razer_devices
    detect_bluetooth_devices
    
    echo -e "${GREEN}=== Peripheral Detection Complete ===${RESET}"
}

main "$@"
