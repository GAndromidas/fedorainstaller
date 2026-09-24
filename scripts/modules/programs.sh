#!/bin/bash
# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

step "Install programs from YAML configuration"

# Initialize arrays
declare -a dnf_packages=()
declare -a flatpak_packages=()
declare -a de_dnf_packages=()
declare -a de_flatpak_packages=()
declare -a de_remove_packages=()

# Check if programs.yaml exists
PROGRAMS_YAML="$SCRIPT_DIR/../../configs/programs.yaml"
if [[ ! -f "$PROGRAMS_YAML" ]]; then
    print_error "Programs configuration file not found: $PROGRAMS_YAML"
    exit 1
fi

# Ensure yq is available
if ! command -v yq &>/dev/null; then
    print_info "yq is required for YAML parsing. Installing..."
    sudo $DNF_CMD install -y yq
    if ! command -v yq &>/dev/null; then
        print_error "Failed to install yq. Please install it manually: sudo dnf install yq"
        exit 1
    fi
fi

# Debug: Show the current mode
print_info "Current installation mode: '$INSTALL_MODE'"

# Read package lists from YAML based on mode
if [[ "$INSTALL_MODE" == "default" ]]; then
    read_yaml_packages "$PROGRAMS_YAML" ".dnf.default" "dnf_packages"
    read_yaml_packages "$PROGRAMS_YAML" ".flatpak.default" "flatpak_packages"
elif [[ "$INSTALL_MODE" == "minimal" ]]; then
    read_yaml_packages "$PROGRAMS_YAML" ".dnf.minimal" "dnf_packages"
    read_yaml_packages "$PROGRAMS_YAML" ".flatpak.minimal" "flatpak_packages"
elif [[ "$INSTALL_MODE" == "server" ]]; then
    read_yaml_packages "$PROGRAMS_YAML" ".dnf.server" "dnf_packages"
    read_yaml_packages "$PROGRAMS_YAML" ".flatpak.server" "flatpak_packages"
else
    print_error "Invalid mode: '$INSTALL_MODE'"
    print_error "Available modes: default, minimal, server"
    exit 1
fi

# Read desktop environment specific packages
# Uses shared detection with a process-based fallback, so DE-specific setup
# works even when run from a TTY/SSH where XDG_CURRENT_DESKTOP is unset.
DE=$(detect_desktop_environment)
case "$DE" in
    gnome|kde|cosmic) ;;
    *) DE="" ;;  # unsupported DE — skip DE-specific packages
esac

if [ -n "$DE" ]; then
    read_yaml_packages "$PROGRAMS_YAML" ".desktop_environments.$DE.install" "de_dnf_packages"
    read_yaml_packages "$PROGRAMS_YAML" ".desktop_environments.$DE.flatpak" "de_flatpak_packages"
    read_yaml_packages "$PROGRAMS_YAML" ".desktop_environments.$DE.remove" "de_remove_packages"
    
    # Add DE-specific packages to main arrays
    dnf_packages+=("${de_dnf_packages[@]}")
    flatpak_packages+=("${de_flatpak_packages[@]}")
    
    print_info "Detected desktop environment: $DE"
    print_info "Added ${#de_dnf_packages[@]} DE-specific DNF packages"
    print_info "Added ${#de_flatpak_packages[@]} DE-specific Flatpak packages"
    print_info "Found ${#de_remove_packages[@]} DE-specific packages to remove"
fi

# Remove DE-specific packages first
if [ ${#de_remove_packages[@]} -gt 0 ]; then
    print_info "Removing ${#de_remove_packages[@]} DE-specific packages: ${de_remove_packages[*]}"
    
    # Filter out packages that are not installed
    declare -a packages_to_remove=()
    for pkg in "${de_remove_packages[@]}"; do
        if rpm -q "$pkg" &>/dev/null; then
            packages_to_remove+=("$pkg")
        fi
    done
    
    if [ ${#packages_to_remove[@]} -gt 0 ]; then
        if sudo $DNF_CMD remove -y "${packages_to_remove[@]}" 2>&1 | tee -a "$INSTALL_LOG"; then
            print_success "Removed ${#packages_to_remove[@]} packages successfully"
        else
            print_warning "Some packages may not have been removed"
        fi
    else
        print_info "None of the specified packages are installed"
    fi
fi

# Install DNF packages using unified batch installation
if [ ${#dnf_packages[@]} -gt 0 ]; then
    print_info "Installing ${#dnf_packages[@]} DNF packages: ${dnf_packages[*]}"
    
    # Remove duplicates
    dnf_packages=($(printf "%s\n" "${dnf_packages[@]}" | sort -u))
    
    # Use unified batch installation with fallback
    install_packages_batch "dnf" "${dnf_packages[@]}"
else
    print_warning "No DNF packages to install for mode: $INSTALL_MODE"
fi

# Install Flatpak packages using unified batch installation
if [ ${#flatpak_packages[@]} -gt 0 ]; then
    if ! command -v flatpak &>/dev/null; then
        print_warning "Flatpak is not installed, skipping Flatpak apps."
    else
        print_info "Installing ${#flatpak_packages[@]} Flatpak packages: ${flatpak_packages[*]}"
        
        # Remove duplicates
        flatpak_packages=($(printf "%s\n" "${flatpak_packages[@]}" | sort -u))
        
        # Ensure Flatpak daemon is running
        if ! flatpak ps >/dev/null 2>&1; then
            print_info "Starting Flatpak daemon..."
            flatpak ps >/dev/null 2>&1 || true
        fi
        
        # Update Flatpak repositories first
        print_info "Updating Flatpak repositories..."
        timeout 300 flatpak update --appstream 2>/dev/null || print_warning "Flatpak repository update timed out or failed, continuing..."
        
        # Use unified batch installation with fallback
        install_packages_batch "flatpak" "${flatpak_packages[@]}"
    fi
else
    print_warning "No Flatpak packages to install for mode: $INSTALL_MODE"
fi

# Configure server applications (Docker, Portainer, Watchtower)
configure_server_applications() {
    print_info "Configuring server applications..."

    # Configure Docker
    if command -v docker >/dev/null; then
        print_info "Enabling and starting Docker service..."
        if sudo systemctl enable --now docker >/dev/null 2>&1; then
            print_success "Docker service enabled and started."
        else
            print_warning "Failed to enable or start Docker service."
        fi

        print_info "Adding user to the docker group..."
        if sudo usermod -aG docker "$USER" 2>/dev/null; then
            print_success "User '$USER' added to the docker group. Please log out and back in to apply changes."
        else
            print_warning "Failed to add user to the docker group."
        fi

        # Interactively install Portainer
        if gum_confirm "Install Portainer for Docker management?"; then
            print_info "Creating Portainer data volume..."
            sudo docker volume create portainer_data >/dev/null 2>&1 || true

            print_info "Starting Portainer container..."
            sudo docker stop portainer >/dev/null 2>&1 || true
            sudo docker rm portainer >/dev/null 2>&1 || true

            if sudo docker run -d -p 8000:8000 -p 9443:9443 --name=portainer --restart=always \
                -v /var/run/docker.sock:/var/run/docker.sock \
                -v portainer_data:/data \
                portainer/portainer-ce:latest >/dev/null 2>&1; then
                print_success "Portainer container is running."
                print_info "You can access Portainer at https://<your-server-ip>:9443"
            else
                print_warning "Failed to start the Portainer container."
            fi
        else
            print_info "Portainer installation skipped."
        fi

        # Interactively install Watchtower
        if gum_confirm "Install Watchtower for automatic container updates?"; then
            print_info "Starting Watchtower container..."
            sudo docker stop watchtower >/dev/null 2>&1 || true
            sudo docker rm watchtower >/dev/null 2>&1 || true

            if sudo docker run -d --name=watchtower --restart=always \
                -v /var/run/docker.sock:/var/run/docker.sock \
                containrrr/watchtower >/dev/null 2>&1; then
                print_success "Watchtower container is running."
                print_info "Watchtower will monitor and update your containers automatically."
            else
                print_warning "Failed to start the Watchtower container."
            fi
        else
            print_info "Watchtower installation skipped."
        fi
    else
        print_warning "Docker not installed, skipping server application configuration."
    fi
}

# Configure server applications (Docker, Portainer, Watchtower)
if [[ "$INSTALL_MODE" == "server" ]]; then
    configure_server_applications
fi

print_success "Program installation from YAML completed." 