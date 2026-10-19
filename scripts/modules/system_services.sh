#!/bin/bash
set -uo pipefail

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

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
        # `id -nG` is the reliable membership check; `groups | grep -q \b`
        # breaks on substrings/words like "video" vs "realtime_video".
        if ! id -nG "$current_user" 2>/dev/null | grep -qw "$group"; then
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
        # NOTE: tlp-sleep no longer ships as a separate unit on modern Fedora
        # (hibernate/suspend handling is built into tlp itself); enabling it
        # was a permanent silent no-op.
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
    # ONE full dump filtered in-process instead of one list-unit-files fork
    # per service (N full-dump forks per run).
    local available=() unit_cache
    unit_cache=$(systemctl list-unit-files 2>/dev/null)
    for svc in "${services[@]}"; do
        if grep -q "^${svc}" <<<"$unit_cache"; then
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

sshd_hardened_enough() {
    local v="${1,,}"
    [[ "$v" == "prohibit-password" || "$v" == "no" ]]
}

# File-level hardening gate — used when the sshd -T dump can't be trusted.
# Conditions sshd itself would resolve: our 00-* drop-in exists with
# PermitRootLogin prohibit-password AND the sshd_config.d Include is the
# first managed-key-capable line in the main sshd_config (first-obtained
# value wins). sshd -t has already passed when this is consulted.
# $1 = drop-in path.
_sshd_file_level_hardened() {
    local dropin="${1:-}"
    [[ -n "$dropin" ]] || return 1
    sudo test -f "$dropin" 2>/dev/null || return 1
    sudo grep -qi '^[[:space:]]*PermitRootLogin[[:space:]]\+prohibit-password' "$dropin" 2>/dev/null || return 1
    local main="${SSHD_MAIN_CONFIG:-/etc/ssh/sshd_config}"
    [[ -s "$main" ]] || return 1
    local inc_line
    inc_line=$(sudo grep -nE '^[[:space:]]*Include[[:space:]].*sshd_config\.d' "$main" 2>/dev/null | head -1 | cut -d: -f1)
    [[ -n "$inc_line" ]] || return 1
    # No managed key above the Include — otherwise that directive, not the
    # drop-in, wins the first-obtained race.
    sudo awk -v n="$inc_line" '
        NR >= n { exit 0 }
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*$/ { next }
        { k = tolower($1); if (k ~ /^(permitrootlogin|maxauthtries|logingracetime|maxstartups|clientaliveinterval|clientalivecountmax)$/) exit 1 }
      ' "$main" 2>/dev/null
}

# Make sure the sshd_config.d Include is present and effectively first.
harden_sshd_restore_include() {
    local main="${SSHD_MAIN_CONFIG:-/etc/ssh/sshd_config}"
    local include_re='^[[:space:]]*Include[[:space:]].*sshd_config\.d'
    local first_include
    local _offending=""
    first_include=$(sudo grep -nE "$include_re" "$main" 2>/dev/null | head -1 | cut -d: -f1 || echo "")
    if [[ -n "$first_include" ]]; then
        # Include exists — is a managed key above it (and therefore winning)?
        # awk exits 0 when the Include is effectively first (clean).
        if sudo awk -v n="$first_include" '
            NR >= n { exit 0 }
            /^[[:space:]]*#/ { next }
            /^[[:space:]]*$/ { next }
            { k = tolower($1); if (k ~ /^(permitrootlogin|maxauthtries|logingracetime|maxstartups|clientaliveinterval|clientalivecountmax)$/) exit 1 }
          ' "$main" 2>/dev/null; then
            ui_info "Include for sshd_config.d already present and first in $main"
            return 0
        fi
        ui_warn "Managed SSH setting precedes Include in $main (first value wins) — moving Include to the top"
        _offending=$(sudo awk -v n="$first_include" '
            NR >= n { exit }
            /^[[:space:]]*#/ { next }
            /^[[:space:]]*$/ { next }
            { k = tolower($1); if (k ~ /^(permitrootlogin|maxauthtries|logingracetime|maxstartups|clientaliveinterval|clientalivecountmax)$/) print NR ": " $0 }
          ' "$main" 2>/dev/null || true)
        [[ -n "$_offending" ]] && log_to_file "Managed keys above Include (line $first_include): ${_offending//$'\n'/ ; }"
    else
        ui_warn "No Include for sshd_config.d in $main — adding it at the top"
    fi
    sudo cp "$main" "${main}.backup.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || {
        ui_warn "Failed to back up $main — leaving sshd_config untouched"
        return 1
    }
    local tmp
    tmp=$(mktemp /tmp/sshd_config.XXXXXX) || return 1
    {
        echo "# Added by fedorainstaller — enables sshd_config.d drop-ins (managed)"
        echo "Include /etc/ssh/sshd_config.d/*.conf"
        echo ""
        sudo grep -vE "$include_re" "$main" 2>/dev/null
    } > "$tmp" || { rm -f "$tmp"; return 1; }
    if ! sudo cp "$tmp" "$main" 2>/dev/null; then
        ui_warn "Failed to write $main — leaving sshd_config untouched"
        rm -f "$tmp"
        return 1
    fi
    rm -f "$tmp"
    if sudo sshd -t 2>/dev/null; then
        ui_success "Include in $main fixed — drop-in should now be active"
        return 0
    fi
    ui_warn "sshd config test failed after Include fix — rolling back"
    local latest_backup
    latest_backup=$(ls -t "${main}.backup."* 2>/dev/null | head -1 || true)
    [[ -n "$latest_backup" ]] && sudo cp "$latest_backup" "$main" 2>/dev/null || true
    return 1
}

# Safe SSH hardening: root password login off, key auth unaffected.
harden_sshd() {
    step "Applying safe SSH hardening"
    install_sshd

    local dropin_dir="/etc/ssh/sshd_config.d"
    local dropin="$dropin_dir/00-fedorainstaller-hardening.conf"

    if [ "${DRY_RUN:-false}" = true ]; then
        ui_info "Dry-run: would write $dropin (PermitRootLogin prohibit-password) and reload sshd"
        return 0
    fi

    sudo mkdir -p "$dropin_dir"
    if [ -f "$dropin" ]; then
        sudo sed -i 's/^\(PermitRootLogin\).*/\1 prohibit-password/' "$dropin"
    else
        echo "# Managed by fedorainstaller — safe-by-default root SSH policy" | sudo tee "$dropin" >/dev/null
        echo "PermitRootLogin prohibit-password" | sudo tee -a "$dropin" >/dev/null
    fi

    if ! sudo sshd -t 2>/dev/null; then
        ui_error "sshd -t failed after writing $dropin — not reloading sshd"
        return 1
    fi

    local effective
    effective=$(sudo sshd -T 2>/dev/null | awk '$1=="permitrootlogin" {print $2; exit}' || true)
    if sshd_hardened_enough "$effective"; then
        sudo systemctl reload sshd.service 2>/dev/null || sudo systemctl reload sshd 2>/dev/null || true
        ui_success "SSH hardening applied and reloaded (root password login off, key auth unaffected)"
        return 0
    fi
    if ! harden_sshd_restore_include; then
        ui_warn "Include repair failed — hardening may be inert until fixed"
        return 0
    fi
    effective=$(sudo sshd -T 2>/dev/null | awk '$1=="permitrootlogin" {print $2; exit}' || true)
    if ! sshd_hardened_enough "$effective"; then
        # Deep-dive before deciding: field experience shows sshd -T can exit
        # 0 with NO permitrootlogin line in its dump at all (custom builds).
        local _t_out="" _t_rc=0 _t_prl=""
        _t_out=$(sudo sshd -T 2>/dev/null) || _t_rc=$?
        _t_prl=$(awk '$1=="permitrootlogin" {print; exit}' <<< "$_t_out")
        log_to_file "sshd -T rc=$_t_rc; dump ${#_t_out} bytes; ${_t_prl:-no permitrootlogin line in output}"
        if _sshd_file_level_hardened "$dropin"; then
            ui_info "sshd -T dump lacks PermitRootLogin (probe inconclusive) — hardening verified at file level (drop-in + Include position OK)"
        else
            ui_warn "SSH hardening still not in effect (sshd -T reports PermitRootLogin '${effective:-<none>}') — leaving $dropin in place"
            return 0
        fi
    fi

    if sudo systemctl reload sshd.service 2>/dev/null || sudo systemctl reload sshd 2>/dev/null; then
        ui_success "SSH hardening applied and reloaded (root password login off, key auth unaffected)"
    else
        ui_warn "Hardening written but sshd reload failed — takes effect on next restart"
    fi
}

# Enable all detected services automatically. sshd is always installed and
# enabled so the machine stays reachable out of the box; KDE Connect is
# enabled automatically whenever it is found (RPM or Flatpak).
enable_essential_services() {
    step "Enabling essential services"

    # SSH server is always installed so the system is reachable out of the box,
    # regardless of the chosen installation mode.
    install_sshd

    # Safe-by-default hardening right after the server is in place.
    harden_sshd

    # Enable every detected service: sshd always, plus bluetooth, CUPS, cronie,
    # fstrim (SSDs) and KDE Connect whenever their package is present.
    local services
    mapfile -t services < <(detect_enabled_services)

    for svc in "${services[@]}"; do
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
