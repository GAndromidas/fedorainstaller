#!/bin/bash
set -uo pipefail

# Get directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

# System maintenance and cleanup for Fedora - adapted from archinstaller

cleanup_and_optimize() {
    step "Performing final cleanup and optimizations"
    
    # Check if lsblk is available for SSD detection
    if command_exists lsblk; then
        if lsblk -d -o rota | grep -q '^0$'; then
            ui_info "SSD detected, running fstrim..."
            sudo fstrim -v / >/dev/null 2>&1
            ui_success "SSD trim completed"
        else
            ui_info "HDD detected, skipping fstrim"
        fi
    else
        ui_warn "lsblk not available. Skipping SSD optimization."
    fi
    
    # Clean /tmp directory
    ui_info "Cleaning /tmp directory..."
    sudo find /tmp -mindepth 1 -maxdepth 1 ! -path '/tmp/systemd-*' ! -path '/tmp/.X*' ! -path '/tmp/pulse-*' -exec rm -rf {} + 2>/dev/null || true
    ui_success "/tmp directory cleaned"
    
    # Sync disk writes
    ui_info "Syncing disk writes..."
    sync
    ui_success "Disk writes synced"
}

setup_maintenance() {
    step "Performing comprehensive system cleanup"
    
    # Clean DNF cache
    ui_info "Cleaning DNF cache..."
    sudo $DNF_CMD clean all >/dev/null 2>&1
    ui_success "DNF cache cleaned"
    
    # Flatpak cleanup - remove unused packages and runtimes
    if command -v flatpak >/dev/null 2>&1; then
        ui_info "Removing unused flatpak packages..."
        sudo flatpak uninstall --unused --noninteractive -y >/dev/null 2>&1 || true
        ui_success "Flatpak cleanup completed"
    else
        ui_info "Flatpak not installed, skipping flatpak cleanup"
    fi
    
    # Remove orphaned packages if any exist
    if sudo $DNF_CMD list autoremove &>/dev/null; then
        ui_info "Removing orphaned packages..."
        sudo $DNF_CMD autoremove -y >/dev/null 2>&1
        ui_success "Orphaned packages removed"
    else
        ui_info "No orphaned packages found"
    fi
}

cleanup_helpers() {
    step "Cleaning helper directories"
    
    # Clean any temporary build directories
    if [ -d /tmp/rpmbuild ]; then
        ui_info "Cleaning rpmbuild temp dir..."
        sudo rm -rf /tmp/rpmbuild
        ui_success "rpmbuild temp dir cleaned"
    fi
    
    # Clean any other temporary directories
    if [ -d /tmp/copr ]; then
        ui_info "Cleaning COPR build dir..."
        sudo rm -rf /tmp/copr
        ui_success "COPR build dir cleaned"
    fi
}

# Execute all maintenance steps
cleanup_and_optimize
setup_maintenance
cleanup_helpers

# Final message
echo ""
ui_success "Maintenance and optimization completed"
ui_info "System is ready for use"
