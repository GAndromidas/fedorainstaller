#!/bin/bash
set -uo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# System services configuration for Fedora

# Ensure firewalld is installed, enabled and its daemon is responsive.
# Returns 0 when the daemon answers, 1 otherwise.
ensure_firewalld_running() {
    if ! rpm -q firewalld &>/dev/null; then
        ui_info "Installing firewalld..."
        install_packages_batch "dnf" "firewalld"
    fi

    sudo systemctl enable firewalld >/dev/null 2>&1
    if ! systemctl is-active firewalld &>/dev/null; then
        sudo systemctl start firewalld >/dev/null 2>&1
    fi

    # Wait for the daemon to come up — firewall-cmd fails immediately with
    # "FirewallD is not running" if called too soon after start.
    local attempts=0
    until firewall-cmd --state &>/dev/null || [ "$attempts" -ge 10 ]; do
        sleep 1
        ((attempts++))
    done

    if firewall-cmd --state &>/dev/null; then
        ui_success "firewalld is running"
        return 0
    fi

    ui_error "firewalld could not be started — firewall rules (SSH/Cockpit) will NOT be applied."
    return 1
}

# List every zone a rule must be applied to: the default zone plus all
# currently active zones (deduplicated). A rule added only to the default
# zone is silently ineffective when an interface is bound to another zone.
get_firewall_zones() {
    local default_zone active_zones
    default_zone=$(firewall-cmd --get-default-zone 2>/dev/null)
    active_zones=$(firewall-cmd --get-active-zones 2>/dev/null | awk '!/^[[:space:]]/')
    {
        echo "$default_zone"
        echo "$active_zones"
    } | grep -v '^$' | sort -u
}

# Check whether a rule is active at runtime in a given zone.
# $1: zone, $2: rule option, e.g. "--add-service=ssh" or "--add-port=1714-1764/tcp"
firewall_rule_present() {
    local zone="$1"
    local rule="$2"
    case "$rule" in
        --add-service=*)
            firewall-cmd --zone="$zone" --query-service="${rule#--add-service=}" >/dev/null 2>&1 ;;
        --add-port=*)
            firewall-cmd --zone="$zone" --query-port="${rule#--add-port=}" >/dev/null 2>&1 ;;
        *)
            return 1 ;;
    esac
}

# Apply a firewall rule to the default zone AND every active zone.
# A rule added only to the default zone is silently ineffective when the
# interface is bound to a different zone, so this covers both cases.
# Applies permanently, reloads the daemon, then enforces + verifies at runtime.
# $1: a single firewall-cmd option, e.g. "--add-service=ssh" or "--add-port=1714-1764/tcp"
firewall_allow() {
    local rule="$1"
    local zone ok=true

    # 1) Persist the rule in every relevant zone.
    while IFS= read -r zone; do
        [ -z "$zone" ] && continue
        if ! sudo firewall-cmd --permanent --zone="$zone" "$rule" >/dev/null 2>&1; then
            ui_warn "Could not persist $rule in zone '$zone'"
            ok=false
        fi
    done < <(get_firewall_zones)

    # 2) Push permanent config into the running daemon.
    sudo firewall-cmd --reload >/dev/null 2>&1

    # 3) Enforce at runtime (fallback if reload was skipped) and verify per zone.
    while IFS= read -r zone; do
        [ -z "$zone" ] && continue
        if ! firewall_rule_present "$zone" "$rule"; then
            sudo firewall-cmd --zone="$zone" "$rule" >/dev/null 2>&1
        fi
        if firewall_rule_present "$zone" "$rule"; then
            log_to_file "Firewall: $rule active in zone '$zone'"
        else
            ui_warn "Firewall rule NOT active in zone '$zone': $rule"
            ok=false
        fi
    done < <(get_firewall_zones)

    [ "$ok" = true ]
}

configure_firewall() {
    step "Configuring firewall"

    if ! ensure_firewalld_running; then
        ui_error "Skipping firewall configuration — SSH will not be reachable. Run 'sudo systemctl enable --now firewalld && sudo firewall-cmd --add-service=ssh' manually."
        return 1
    fi

    ui_info "Firewall zones in use: $(get_firewall_zones | tr '\n' ' ')"

    # SSH must always be allowed so the machine stays reachable after the install.
    firewall_allow "--add-service=ssh"
    firewall_allow "--add-service=cockpit"

    # Open the KDE Connect port range whenever KDE Connect is installed (RPM or
    # Flatpak), so phone integration works out of the box.
    if is_kdeconnect_installed; then
        ui_info "Configuring KDE Connect firewall ports..."
        firewall_allow "--add-port=1714-1764/udp"
        firewall_allow "--add-port=1714-1764/tcp"
        ui_success "KDE Connect ports configured"
    fi

    # Final verification: SSH must be open on the default AND every active zone.
    local ssh_ok=true
    while IFS= read -r zone; do
        [ -z "$zone" ] && continue
        if firewall-cmd --zone="$zone" --query-service=ssh &>/dev/null; then
            ui_success "SSH allowed in zone '$zone'"
        else
            ui_error "SSH blocked in zone '$zone'!"
            ssh_ok=false
        fi
    done < <(get_firewall_zones)

    if [ "$ssh_ok" = true ]; then
        ui_success "Firewall fully configured — SSH is reachable on all zones."
    else
        ui_error "Firewall configuration incomplete — SSH may be blocked. Check: firewall-cmd --list-all"
    fi
}

# Detect KDE Connect installed either as an RPM package or a Flatpak app
is_kdeconnect_installed() {
    rpm -q kdeconnect-kde &>/dev/null || rpm -q kdeconnect &>/dev/null || \
        { command -v flatpak &>/dev/null && flatpak list 2>/dev/null | grep -q "org.kde.kdeconnect"; }
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
        install_packages_batch "dnf" "power-profiles-daemon"
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
            install_packages_batch "dnf" "tlp" "tlp-rdw"
        fi
        
        # Enable TLP (it conflicts with power-profiles-daemon, so disable that first)
        sudo systemctl disable --now power-profiles-daemon >/dev/null 2>&1
        sudo systemctl enable --now tlp >/dev/null 2>&1
        sudo systemctl enable --now tlp-sleep >/dev/null 2>&1
        ui_success "TLP enabled for laptop power management"
    fi
}

# Build the list of services whose unit file actually exists and whose
# underlying package is installed. Kept separate so it can be reused both for
# the interactive picker and for the enable loop.
detect_enabled_services() {
    local services=()

    # SSH server — the unit is always available once openssh-server is present.
    if rpm -q openssh-server &>/dev/null || rpm -q openssh &>/dev/null; then
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
        services+=("crond")
    fi

    # fstrim timer for SSDs
    if is_ssd; then
        services+=("fstrim.timer")
    fi

    # KDE Connect if installed (RPM or Flatpak). The enable loop below skips the
    # service if no kdeconnectd unit exists (Flatpak ships its own in-app daemon).
    if is_kdeconnect_installed; then
        services+=("kdeconnectd")
    fi

    # Keep only services that actually ship a unit on this system.
    local available=()
    for svc in "${services[@]}"; do
        if systemctl list-unit-files | grep -q "^${svc}"; then
            available+=("$svc")
        fi
    done

    printf '%s\n' "${available[@]}"
}

install_sshd() {
    if ! rpm -q openssh-server &>/dev/null; then
        ui_info "Installing openssh-server..."
        install_packages_batch "dnf" "openssh-server"
    fi
}

# Interactive service selection. Lets the user pick which of
# the detected services to enable at boot. sshd is always preselected so the
# machine stays reachable out of the box; the rest are preselected too but can
# be toggled off by unselecting them.
prompt_service_selection() {
    local available
    mapfile -t available < <(detect_enabled_services)
    [ ${#available[@]} -eq 0 ] && return 0

    # Preselect everything by default (sshd must remain available).
    local preselected="*"

    step "Select which services to enable"

    if [ "${DRY_RUN:-false}" = true ]; then
        ui_info "Dry-run: would enable services: ${available[*]}"
        SERVICES_TO_ENABLE=("${available[@]}")
        return 0
    fi

    ui_info "Select the services to enable at boot (all preselected):"
    local selected
    selected=$(ui_multiselect_preselect "Services to enable" "$preselected" "${available[@]}")

    if [ -z "$selected" ]; then
        ui_warn "No services selected — nothing will be enabled except sshd."
        SERVICES_TO_ENABLE=("sshd")
        return 0
    fi

    mapfile -t SERVICES_TO_ENABLE <<< "$selected"
    ui_info "Will enable: ${SERVICES_TO_ENABLE[*]}"
}

enable_essential_services() {
    step "Enabling essential services"

    # SSH server is always installed so the system is reachable out of the box,
    # regardless of the chosen installation mode.
    install_sshd

    prompt_service_selection

    # Enable selected services
    for svc in "${SERVICES_TO_ENABLE[@]:-}"; do
        [ -z "$svc" ] && continue
        if [ "${DRY_RUN:-false}" = true ]; then
            ui_info "Dry-run: would enable $svc"
            continue
        fi
        if systemctl is-enabled "$svc" &>/dev/null || systemctl is-active "$svc" &>/dev/null; then
            ui_info "$svc already enabled/running"
        else
            ui_info "Enabling $svc..."
            if sudo systemctl enable --now "$svc" >/dev/null 2>&1; then
                ui_success "$svc enabled"
            else
                ui_warn "$svc could not be enabled"
            fi
        fi
    done

    # Report SSH status clearly for headless/server setups
    if [ "${DRY_RUN:-false}" = true ]; then
        ui_success "Dry-run: SSH server would be left running for: ssh ${USER}@<host>"
    elif systemctl is-active sshd &>/dev/null; then
        ui_success "SSH server is running — you can connect with: ssh ${USER}@$(hostname -I 2>/dev/null | awk '{print $1}')"
    else
        ui_warn "SSH server could not be started"
    fi
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
        install_packages_batch "dnf" "laptop-mode-tools"
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

# Apply advanced system optimizations (kernel/network tuning)
setup_advanced_optimizations() {
    step "Applying advanced system optimizations"
    
    local sysctl_conf="/etc/sysctl.d/99-fedorainstaller.conf"
    local ram_gb
    ram_gb=$(free -g | awk '/^Mem:/ {print $2}')
    
    # Apply kernel/network optimizations (fq_codel + BBR for lower latency,
    # adaptive swappiness based on RAM size, lower VFS cache pressure)
    {
        echo "# System optimizations generated by fedorainstaller"
        echo "# System RAM: ${ram_gb}GB detected on $(date)"
        echo ""
        echo "# Network: CoDel queue discipline + BBR congestion control"
        echo "net.core.default_qdisc=fq_codel"
        echo "net.ipv4.tcp_congestion_control=bbr"
        echo ""
        if [ "$ram_gb" -le 4 ]; then
            echo "# Aggressive swappiness for low RAM systems"
            echo "vm.swappiness=60"
            echo ""
            echo "# Reduce cache pressure"
            echo "vm.vfs_cache_pressure=50"
        elif [ "$ram_gb" -le 8 ]; then
            echo "# Moderate swappiness for standard systems"
            echo "vm.swappiness=30"
        elif [ "$ram_gb" -le 16 ]; then
            echo "# Low swappiness for high memory systems"
            echo "vm.swappiness=10"
            echo ""
            echo "# Reduce cache pressure"
            echo "vm.vfs_cache_pressure=50"
        else
            echo "# Minimal swappiness for very high memory systems"
            echo "vm.swappiness=1"
            echo ""
            echo "# Reduce cache pressure"
            echo "vm.vfs_cache_pressure=50"
        fi
    } | sudo tee "$sysctl_conf" >/dev/null
    
    # Apply the settings immediately
    sudo sysctl -p "$sysctl_conf" >>"$INSTALL_LOG" 2>&1 || true
    
    ui_success "Advanced system optimizations applied (fq_codel, BBR, adaptive swappiness)"
    log_success "Advanced system optimizations applied to $sysctl_conf"
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
    setup_advanced_optimizations
    
    echo -e "${GREEN}=== System Services Configuration Complete ===${RESET}"
}

main "$@"
