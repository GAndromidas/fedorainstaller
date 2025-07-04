#!/bin/bash
# Configure DNF, enable RPM Fusion, enable COPR, enable Flathub, then update system and flatpaks
source "$(dirname "$0")/../common.sh"

system_update_and_repos() {
    # --- Configure DNF ---
    step "Configure DNF"
    DNF_CONF="/etc/dnf/dnf.conf"
    print_info "Configuring DNF..."
    sudo grep -q '^fastestmirror=True' "$DNF_CONF" || echo "fastestmirror=True" | sudo tee -a "$DNF_CONF"
    sudo grep -q '^max_parallel_downloads=10' "$DNF_CONF" || echo "max_parallel_downloads=10" | sudo tee -a "$DNF_CONF"
    sudo grep -q '^defaultyes=True' "$DNF_CONF" || echo "defaultyes=True" | sudo tee -a "$DNF_CONF"
    print_success "DNF configuration updated successfully."

    # --- Enable RPM Fusion ---
    step "Enable RPM Fusion"
    print_info "Enabling RPM Fusion repositories..."
    if ! $DNF_CMD repolist | grep -q rpmfusion-free; then
        sudo $DNF_CMD install -y \
            https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm \
            https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm \
            && print_success "RPM Fusion repositories enabled successfully." \
            || print_error "Failed to enable RPM Fusion repositories."
    else
        print_warning "RPM Fusion repositories are already enabled. Skipping."
    fi

    # --- Enable COPR Repos from YAML ---
    step "Enable COPR repositories"
    PROGRAMS_YAML="$HOME/fedorainstaller/configs/programs.yaml"
    if [ -f "$PROGRAMS_YAML" ]; then
        if ! command -v yq &>/dev/null; then
            print_info "Installing yq for YAML parsing..."
            sudo $DNF_CMD install -y yq
        fi
        COPR_REPOS=$(yq '.copr[] | .repo' "$PROGRAMS_YAML" 2>/dev/null)
        if [ -n "$COPR_REPOS" ]; then
            for repo in $COPR_REPOS; do
                print_info "Enabling COPR repo: $repo"
                sudo $DNF_CMD copr enable -y "$repo"
            done
            print_success "COPR repositories enabled."
        else
            print_warning "No COPR repositories found in YAML."
        fi
    else
        print_warning "programs.yaml not found, skipping COPR enable."
    fi

    # --- Enable Flathub ---
    step "Enable Flathub"
    if ! command -v flatpak &>/dev/null; then
        print_info "Flatpak not found. Installing..."
        sudo $DNF_CMD install -y flatpak
        INSTALLED_PACKAGES+=(flatpak)
    fi
    print_info "Adding Flathub repository..."
    sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    print_success "Flathub repository added successfully."

    # --- System Update (DNF only) ---
    step "Update system packages"
    print_info "Updating system packages..."
    if command -v dnf5 &> /dev/null; then
        sudo dnf5 upgrade --refresh -y
    else
        sudo dnf upgrade --refresh -y
    fi
    if [ $? -eq 0 ]; then
        print_success "System packages updated successfully."
    else
        print_error "System update failed."
    fi
}

system_update_and_repos
