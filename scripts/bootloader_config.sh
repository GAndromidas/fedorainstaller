#!/bin/bash
set -uo pipefail

# Configure bootloader (GRUB2/systemd-boot) with dual-boot support
# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

step "Configure bootloader"

# Detect bootloader type
BOOTLOADER=$(detect_bootloader)
ui_info "Detected bootloader: $BOOTLOADER"

# Configure bootloader based on type
configure_traditional_bootloader

# Configure dual-boot with Windows if detected
configure_windows_dual_boot

# Configure grub-btrfs for Timeshift snapshot menu entries
configure_grub_btrfs

# Add kernel parameters for better boot experience
add_kernel_parameters

print_success "Bootloader configuration completed"

configure_traditional_bootloader() {
    case "$BOOTLOADER" in
        "grub")
            configure_grub
            ;;
        "systemd-boot")
            configure_systemd_boot
            ;;
        "unknown")
            ui_warn "Unknown bootloader detected, skipping configuration"
            ;;
    esac
}

configure_grub() {
    ui_info "Configuring GRUB2 bootloader"
    
    local grub_conf="/etc/default/grub"
    local grub_sysconf="/etc/sysconfig/grub"
    
    # Use whichever exists
    local grub_config="$grub_conf"
    if [ ! -f "$grub_config" ]; then
        grub_config="$grub_sysconf"
    fi
    
    if [ ! -f "$grub_config" ]; then
        ui_warn "GRUB configuration file not found"
        return 1
    fi
    
    # Set GRUB timeout
    if ! grep -q "^GRUB_TIMEOUT=" "$grub_config"; then
        echo "GRUB_TIMEOUT=5" | sudo tee -a "$grub_config" >/dev/null
    else
        sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=5/' "$grub_config"
    fi
    
    # Enable GRUB save default
    if ! grep -q "^GRUB_SAVEDEFAULT=" "$grub_config"; then
        echo "GRUB_SAVEDEFAULT=true" | sudo tee -a "$grub_config" >/dev/null
    fi
    
    ui_success "GRUB2 configured"
}

configure_systemd_boot() {
    ui_info "Configuring systemd-boot bootloader"
    
    local loader_conf="/boot/loader/loader.conf"
    
    if [ ! -f "$loader_conf" ]; then
        ui_warn "systemd-boot loader.conf not found"
        return 1
    fi
    
    # Set timeout
    if ! grep -q "^timeout" "$loader_conf"; then
        echo "timeout 5" | sudo tee -a "$loader_conf" >/dev/null
    else
        sudo sed -i 's/^timeout.*/timeout 5/' "$loader_conf"
    fi
    
    # Set default
    if ! grep -q "^default" "$loader_conf"; then
        # Find first entry
        local first_entry=$(ls /boot/loader/entries/*.conf 2>/dev/null | head -1 | xargs basename)
        if [ -n "$first_entry" ]; then
            echo "default $first_entry" | sudo tee -a "$loader_conf" >/dev/null
        fi
    fi
    
    ui_success "systemd-boot configured"
}

configure_windows_dual_boot() {
    # Detect Windows installation
    ui_info "Detecting Windows installation..."
    local windows_found=0
    
    if lsblk -f | grep -qi ntfs; then
        windows_found=1
    elif [ -d /boot/efi/EFI/Microsoft ]; then
        windows_found=1
    fi
    
    if [ $windows_found -eq 0 ]; then
        ui_info "No Windows installation detected"
        return 0
    fi
    
    ui_success "Windows installation detected"
    
    # For GRUB systems, configure os-prober
    if [ "$BOOTLOADER" = "grub" ]; then
        # Ensure ntfs-3g and os-prober are installed using unified batch installation
        ui_info "Installing ntfs-3g and os-prober for Windows boot support..."
        install_packages_batch "dnf" "ntfs-3g" "os-prober"
        
        # Enable os-prober in GRUB config
        local grub_conf="/etc/default/grub"
        local grub_sysconf="/etc/sysconfig/grub"
        local grub_config="$grub_conf"
        if [ ! -f "$grub_config" ]; then
            grub_config="$grub_sysconf"
        fi
        
        if [ -f "$grub_config" ]; then
            if grep -q '^GRUB_DISABLE_OS_PROBER=true' "$grub_config"; then
                sudo sed -i 's/^GRUB_DISABLE_OS_PROBER=true/GRUB_DISABLE_OS_PROBER=false/' "$grub_config"
            elif ! grep -q '^GRUB_DISABLE_OS_PROBER=' "$grub_config"; then
                echo 'GRUB_DISABLE_OS_PROBER=false' | sudo tee -a "$grub_config" >/dev/null
            fi
        fi
        
        # Regenerate GRUB config
        ui_info "Regenerating GRUB configuration..."
        if [ -d /sys/firmware/efi ]; then
            sudo grub2-mkconfig -o /boot/efi/EFI/fedora/grub.cfg >/dev/null 2>&1
        else
            sudo grub2-mkconfig -o /boot/grub2/grub.cfg >/dev/null 2>&1
        fi
        
        ui_success "Windows dual-boot configured"
    fi
}

add_kernel_parameters() {
    ui_info "Adding kernel parameters"
    
    if [ "$BOOTLOADER" = "grub" ]; then
        # GRUB systems use /etc/default/grub
        local grub_conf="/etc/default/grub"
        local grub_sysconf="/etc/sysconfig/grub"
        local grub_config="$grub_conf"
        if [ ! -f "$grub_config" ]; then
            grub_config="$grub_sysconf"
        fi
        
        if [ -f "$grub_config" ]; then
            if ! grep -q "^GRUB_CMDLINE_LINUX=" "$grub_config"; then
                echo 'GRUB_CMDLINE_LINUX="quiet"' | sudo tee -a "$grub_config" >/dev/null
            else
                sudo sed -i 's/^GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="\1 quiet"/' "$grub_config"
            fi
            
            # Regenerate GRUB
            if [ -d /sys/firmware/efi ]; then
                sudo grub2-mkconfig -o /boot/efi/EFI/fedora/grub.cfg >/dev/null 2>&1
            else
                sudo grub2-mkconfig -o /boot/grub2/grub.cfg >/dev/null 2>&1
            fi
        fi
    fi
    
    ui_success "Kernel parameters added"
}

configure_grub_btrfs() {
    # Only for GRUB with Btrfs filesystem
    if [ "$BOOTLOADER" != "grub" ]; then
        return 0
    fi

    # Check if root filesystem is Btrfs
    local root_fs
    root_fs=$(findmnt -n -o FSTYPE /)
    if [ "$root_fs" != "btrfs" ]; then
        ui_info "Root filesystem is not Btrfs — skipping grub-btrfs"
        return 0
    fi

    # Check if timeshift is installed
    if ! rpm -q timeshift &>/dev/null; then
        return 0
    fi

    # Enable COPR and install grub-btrfs
    if ! rpm -q grub-btrfs &>/dev/null; then
        ui_info "Installing grub-btrfs for Timeshift snapshot GRUB entries..."
        if sudo $DNF_CMD copr enable -y kylegospo/grub-btrfs 2>/dev/null; then
            if install_packages_batch "dnf" "grub-btrfs" "inotify-tools"; then
                ui_success "grub-btrfs installed"
            else
                ui_warn "grub-btrfs installation failed"
                return 1
            fi
        else
            ui_warn "Failed to enable COPR kylegospo/grub-btrfs"
            return 1
        fi
    fi

    local grub_btrfs_config="/etc/default/grub-btrfs/config"

    # Configure grub-btrfs for Fedora paths
    if [ -f "$grub_btrfs_config" ]; then
        sudo sed -i 's|^GRUB_BTRFS_MKCONFIG=.*|GRUB_BTRFS_MKCONFIG=/sbin/grub2-mkconfig|' "$grub_btrfs_config"
        sudo sed -i 's|^GRUB_BTRFS_GRUB_DIRNAME=.*|GRUB_BTRFS_GRUB_DIRNAME="/boot/grub2"|' "$grub_btrfs_config"
        sudo sed -i 's|^GRUB_BTRFS_SCRIPT_CHECK=.*|GRUB_BTRFS_SCRIPT_CHECK=grub2-script-check|' "$grub_btrfs_config"
        ui_success "grub-btrfs configured for Fedora"
    fi

    # Enable the daemon for auto-updating GRUB on snapshot changes
    if ! systemctl is-active grub-btrfsd &>/dev/null; then
        sudo systemctl enable --now grub-btrfsd 2>/dev/null || \
        sudo systemctl enable --now grub-btrfs.path 2>/dev/null || true
        ui_success "grub-btrfs auto-update service enabled"
    fi

    # Regenerate GRUB config to include snapshots
    if [ -d /sys/firmware/efi ]; then
        sudo grub2-mkconfig -o /boot/efi/EFI/fedora/grub.cfg >/dev/null 2>&1
    else
        sudo grub2-mkconfig -o /boot/grub2/grub.cfg >/dev/null 2>&1
    fi
    ui_success "GRUB updated with Timeshift snapshot entries"
} 