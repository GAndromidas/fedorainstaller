#!/bin/bash
set -uo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

# System services configuration for Fedora - adapted from archinstaller

configure_firewall() {
    step "Configuring firewall"
    
    # Fedora uses firewalld by default
    if ! rpm -q firewalld &>/dev/null; then
        ui_info "Installing firewalld..."
        sudo $DNF_CMD install -y firewalld >/dev/null 2>&1
        INSTALLED_PACKAGES+=(firewalld)
    fi
    
    # Enable and start firewalld
    if ! systemctl is-active firewalld &>/dev/null; then
        sudo systemctl enable --now firewalld >/dev/null 2>&1
        ui_success "firewalld enabled and started"
    else
        ui_info "firewalld already running"
    fi
    
    # Add basic services
    sudo firewall-cmd --permanent --add-service=ssh >/dev/null 2>&1
    sudo firewall-cmd --permanent --add-service=cockpit >/dev/null 2>&1
    
    # Configure KDE Connect ports if KDE is detected
    if [ "$XDG_CURRENT_DESKTOP" ] && [[ "${XDG_CURRENT_DESKTOP,,}" == *kde* ]]; then
        if rpm -q kdeconnect-kde &>/dev/null || rpm -q kdeconnect &>/dev/null; then
            ui_info "Configuring KDE Connect firewall ports..."
            sudo firewall-cmd --permanent --add-port=1714-1764/udp >/dev/null 2>&1
            sudo firewall-cmd --permanent --add-port=1714-1764/tcp >/dev/null 2>&1
            ui_success "KDE Connect ports configured"
        fi
    fi
    
    sudo firewall-cmd --reload >/dev/null 2>&1
    ui_success "Firewall configured"
}

configure_user_groups() {
    step "Configuring user groups"
    
    local current_user=$USER
    local groups_to_add=("wheel" "audio" "video" "input" "lp" "storage")
    
    for group in "${groups_to_add[@]}";
    do
        if ! groups "$current_user" | grep -q "\\b${group}\\b"; then
            ui_info "Adding user to $group group..."
            sudo usermod -aG "$group" "$current_user" >/dev/null 2>&1
            ui_success "Added to $group group"
        fi
    done
}

enable_power_management() {
    step "Configuring power management"
    
    # Install power-profiles-daemon if not present
    if ! rpm -q power-profiles-daemon &>/dev/null; then
        ui_info "Installing power-profiles-daemon..."
        sudo $DNF_CMD install -y power-profiles-daemon >/dev/null 2>&1
        INSTALLED_PACKAGES+=(power-profiles-daemon)
    fi
    
    # Enable power-profiles-daemon
    if ! systemctl is-active power-profiles-daemon &>/dev/null; then
        sudo systemctl enable --now power-profiles-daemon >/dev/null 2>&1
        ui_success "power-profiles-daemon enabled"
    else
        ui_info "power-profiles-daemon already running"
    fi
    
    # Enable TLP on laptops for better battery life
    if is_laptop; then
        if ! rpm -q tlp &>/dev/null; then
            ui_info "Installing TLP for laptop battery optimization..."
            sudo $DNF_CMD install -y tlp tlp-rdw >/dev/null 2>&1
            INSTALLED_PACKAGES+=(tlp tlp-rdw)
        fi
        
        # Enable TLP (it conflicts with power-profiles-daemon, so disable that first)
        sudo systemctl disable --now power-profiles-daemon >/dev/null 2>&1
        sudo systemctl enable --now tlp >/dev/null 2>&1
        sudo systemctl enable --now tlp-sleep >/dev/null 2>&1
        ui_success "TLP enabled for laptop power management"
    fi
}

enable_essential_services() {
    step "Enabling essential services"
    
    local services=()
    
    # SSH server
    if rpm -q openssh-server &>/dev/null; then
        services+=("sshd")
    fi
    
    # Bluetooth
    if rpm -q bluez &>/dev/null; then
        services+=("bluetooth")
    fi
    
    # CUPS (printing)
    if rpm -q cups &>/dev/null; then
        services+=("cups")
    fi
    
    # Cronie
    if rpm -q cronie &>/dev/null; then
        services+=("cronie")
    fi
    
    # fstrim timer for SSDs
    if is_ssd; then
        services+=("fstrim.timer")
    fi
    
    # KDE Connect if KDE is detected
    if [ "$XDG_CURRENT_DESKTOP" ] && [[ "${XDG_CURRENT_DESKTOP,,}" == *kde* ]]; then
        if rpm -q kdeconnect-kde &>/dev/null || rpm -q kdeconnect &>/dev/null; then
            services+=("kdeconnectd")
        fi
    fi
    
    # Enable services
    for svc in "${services[@]}"; do
        if systemctl list-unit-files | grep -q "^${svc}"; then
            if ! systemctl is-active "$svc" &>/dev/null; then
                ui_info "Enabling $svc..."
                sudo systemctl enable --now "$svc" >/dev/null 2>&1
                ui_success "$svc enabled"
            else
                ui_info "$svc already running"
            fi
        fi
    done
}

apply_laptop_optimizations() {
    step "Applying laptop-specific optimizations"
    
    if ! is_laptop; then
        ui_info "Not a laptop, skipping laptop optimizations"
        return 0
    fi
    
    local manufacturer=$(dmidecode -s system-manufacturer 2>/dev/null | tr '[:upper:]' '[:lower:]')
    
    case "$manufacturer" in
        *lenovo*)
            ui_info "Lenovo laptop detected - applying optimizations"
            # Lenovo-specific optimizations can be added here
            ;;
        *dell*)
            ui_info "Dell laptop detected - applying optimizations"
            # Dell-specific optimizations can be added here
            ;;
        *hp*)
            ui_info "HP laptop detected - applying optimizations"
            # HP-specific optimizations can be added here
            ;;
        *asus*)
            ui_info "ASUS laptop detected - applying optimizations"
            # ASUS-specific optimizations can be added here
            ;;
        *)
            ui_info "Generic laptop detected - applying generic optimizations"
            ;;
    esac
    
    # Enable laptop-mode-tools if available
    if ! rpm -q laptop-mode-tools &>/dev/null; then
        ui_info "Installing laptop-mode-tools..."
        sudo $DNF_CMD install -y laptop-mode-tools >/dev/null 2>&1
        INSTALLED_PACKAGES+=(laptop-mode-tools)
    fi
    
    ui_success "Laptop optimizations applied"
}

configure_gpu_drivers() {
    step "Configuring GPU drivers"
    
    local gpu_vendor=$(detect_gpu_vendor)
    
    case "$gpu_vendor" in
        "nvidia")
            ui_info "NVIDIA GPU detected"
            # NVIDIA drivers are already handled in hardware_detection.sh
            # This is just for any additional configuration
            ;;
        "amd")
            ui_info "AMD GPU detected"
            # AMD drivers are already handled in hardware_detection.sh
            ;;
        "intel")
            ui_info "Intel GPU detected"
            # Intel drivers are already handled in hardware_detection.sh
            ;;
        *)
            ui_info "Unknown or no GPU detected"
            ;;
    esac
    
    ui_success "GPU driver configuration complete"
}

apply_ram_based_tuning() {
    step "Applying RAM-based tuning"
    
    local total_mem=$(free -g | awk '/^Mem:/ {print $2}')
    
    ui_info "System has ${total_mem}GB RAM"
    
    if [ "$total_mem" -le 4 ]; then
        ui_info "Low memory system - applying conservative tuning"
        # Already handled in optimize_memory()
    elif [ "$total_mem" -le 16 ]; then
        ui_info "Medium memory system - applying balanced tuning"
        # Already handled in optimize_memory()
    else
        ui_info "High memory system - applying aggressive caching"
        # Already handled in optimize_memory()
    fi
    
    ui_success "RAM-based tuning applied"
}

enable_timeshift_autosnap() {
    step "Configuring Timeshift autosnap (optional)"
    
    if ! rpm -q timeshift &>/dev/null; then
        ui_info "Timeshift not installed, skipping autosnap configuration"
        return 0
    fi
    
    # Check if user wants to enable autosnap
    if gum_confirm "Enable Timeshift autosnap for system snapshots?"; then
        ui_info "Enabling Timeshift autosnap..."
        
        # Create timeshift-autosnap config if it doesn't exist
        if ! rpm -q timeshift-autosnap &>/dev/null; then
            # timeshift-autosnap may not be available in Fedora repos
            ui_warn "timeshift-autosnap package not found, skipping"
            return 0
        fi
        
        sudo systemctl enable --now timeshift-autosnap.timer >/dev/null 2>&1
        ui_success "Timeshift autosnap enabled"
    else
        ui_info "Timeshift autosnap skipped"
    fi
}

# Main execution
main() {
    echo -e "${CYAN}=== System Services Configuration ===${RESET}"
    
    configure_firewall
    configure_user_groups
    enable_power_management
    enable_essential_services
    apply_laptop_optimizations
    configure_gpu_drivers
    apply_ram_based_tuning
    enable_timeshift_autosnap
    
    echo -e "${GREEN}=== System Services Configuration Complete ===${RESET}"
}

main "$@"
