#!/bin/bash
source "$(dirname "$0")/../common.sh"

step "Install programs from YAML configuration"

# Initialize arrays
declare -a dnf_packages=()
declare -a flatpak_packages=()
declare -a de_dnf_packages=()
declare -a de_flatpak_packages=()

# Check if programs.yaml exists
PROGRAMS_YAML="$(dirname "$0")/../configs/programs.yaml"
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

# Function to read packages from YAML
read_yaml_packages() {
    local yaml_file="$1"
    local yaml_path="$2"
    local array_name="$3"
    
    # Use yq to extract package names
    local yq_output
    yq_output=$(yq -r "$yaml_path[].name" "$yaml_file" 2>/dev/null)
    
    if [[ $? -eq 0 && -n "$yq_output" ]]; then
        # Clear the array first
        eval "$array_name=()"
        
        while IFS= read -r package; do
            [[ -z "$package" ]] && continue
            eval "$array_name+=(\"$package\")"
        done <<< "$yq_output"
    else
        eval "$array_name=()"
    fi
}

# Debug: Show the current mode
print_info "Current installation mode: '$INSTALL_MODE'"

# Read package lists from YAML based on mode
if [[ "$INSTALL_MODE" == "default" ]]; then
    read_yaml_packages "$PROGRAMS_YAML" ".dnf.default" "dnf_packages"
    read_yaml_packages "$PROGRAMS_YAML" ".flatpak.default" "flatpak_packages"
elif [[ "$INSTALL_MODE" == "minimal" ]]; then
    read_yaml_packages "$PROGRAMS_YAML" ".dnf.minimal" "dnf_packages"
    read_yaml_packages "$PROGRAMS_YAML" ".flatpak.minimal" "flatpak_packages"
elif [[ "$INSTALL_MODE" == "custom" ]]; then
    # For custom mode, use the existing interactive selection
    interactive_package_selection
    dnf_packages=("${CUSTOM_DNF_SELECTION[@]}")
    flatpak_packages=("${CUSTOM_FLATPAK_SELECTION[@]}")
else
    print_error "Invalid mode: '$INSTALL_MODE'"
    print_error "Available modes: default, minimal, custom"
    exit 1
fi

# Read desktop environment specific packages
DE=""
if [ "$XDG_CURRENT_DESKTOP" ]; then
    case "${XDG_CURRENT_DESKTOP,,}" in
        *gnome*) DE="gnome" ;;
        *kde*)   DE="kde" ;;
        *cosmic*) DE="cosmic" ;;
    esac
fi

# --- DE-specific removals ---
if [ -n "$DE" ]; then
    # Read DNF packages to remove
    read_yaml_packages "$PROGRAMS_YAML" ".desktop_environments.$DE.remove" "de_remove_dnf_packages"
    if [ ${#de_remove_dnf_packages[@]} -gt 0 ]; then
        print_info "Attempting to remove ${#de_remove_dnf_packages[@]} DNF packages for $DE: ${de_remove_dnf_packages[*]}"
        for pkg in "${de_remove_dnf_packages[@]}"; do
            if rpm -q "$pkg" >/dev/null 2>&1; then
                if sudo $DNF_CMD remove -y "$pkg"; then
                    print_success "$pkg removed successfully."
                    REMOVED_PACKAGES+=("$pkg")
                else
                    print_warning "Failed to remove $pkg."
                fi
            fi
        done
    else
        print_info "No DNF packages to remove for $DE."
    fi
    # Read Flatpak packages to remove (if ever added in future)
    de_remove_flatpak_packages=()
    if command -v flatpak &>/dev/null; then
        yq_output=$(yq -r ".desktop_environments.$DE.remove_flatpak[].name" "$PROGRAMS_YAML" 2>/dev/null)
        if [[ $? -eq 0 && -n "$yq_output" ]]; then
            while IFS= read -r package; do
                [[ -z "$package" ]] && continue
                de_remove_flatpak_packages+=("$package")
            done <<< "$yq_output"
        fi
        if [ ${#de_remove_flatpak_packages[@]} -gt 0 ]; then
            print_info "Attempting to remove ${#de_remove_flatpak_packages[@]} Flatpak apps for $DE: ${de_remove_flatpak_packages[*]}"
            for app in "${de_remove_flatpak_packages[@]}"; do
                if flatpak list | grep -q "$app"; then
                    if flatpak uninstall -y "$app"; then
                        print_success "$app Flatpak removed successfully."
                        REMOVED_PACKAGES+=("$app (Flatpak)")
                    else
                        print_warning "Failed to remove Flatpak $app."
                    fi
                else
                    print_info "$app Flatpak is not installed. Skipping."
                fi
            done
        fi
    fi
fi

# Read package lists from YAML based on mode
if [[ "$INSTALL_MODE" == "default" ]]; then
    read_yaml_packages "$PROGRAMS_YAML" ".dnf.default" "dnf_packages"
    read_yaml_packages "$PROGRAMS_YAML" ".flatpak.default" "flatpak_packages"
elif [[ "$INSTALL_MODE" == "minimal" ]]; then
    read_yaml_packages "$PROGRAMS_YAML" ".dnf.minimal" "dnf_packages"
    read_yaml_packages "$PROGRAMS_YAML" ".flatpak.minimal" "flatpak_packages"
elif [[ "$INSTALL_MODE" == "custom" ]]; then
    # For custom mode, use the existing interactive selection
    interactive_package_selection
    dnf_packages=("${CUSTOM_DNF_SELECTION[@]}")
    flatpak_packages=("${CUSTOM_FLATPAK_SELECTION[@]}")
else
    print_error "Invalid mode: '$INSTALL_MODE'"
    print_error "Available modes: default, minimal, custom"
    exit 1
fi

# Read desktop environment specific packages
DE=""
if [ "$XDG_CURRENT_DESKTOP" ]; then
    case "${XDG_CURRENT_DESKTOP,,}" in
        *gnome*) DE="gnome" ;;
        *kde*)   DE="kde" ;;
        *cosmic*) DE="cosmic" ;;
    esac
fi

if [ -n "$DE" ]; then
    read_yaml_packages "$PROGRAMS_YAML" ".desktop_environments.$DE.install" "de_dnf_packages"
    read_yaml_packages "$PROGRAMS_YAML" ".desktop_environments.$DE.flatpak" "de_flatpak_packages"
    
    # Add DE-specific packages to main arrays
    dnf_packages+=("${de_dnf_packages[@]}")
    flatpak_packages+=("${de_flatpak_packages[@]}")
    
    print_info "Detected desktop environment: $DE"
    print_info "Added ${#de_dnf_packages[@]} DE-specific DNF packages"
    print_info "Added ${#de_flatpak_packages[@]} DE-specific Flatpak packages"
fi

# Install DNF packages
if [ ${#dnf_packages[@]} -gt 0 ]; then
    print_info "Installing ${#dnf_packages[@]} DNF packages: ${dnf_packages[*]}"
    
    # Remove duplicates
    dnf_packages=($(printf "%s\n" "${dnf_packages[@]}" | sort -u))
    
    # Track installation results
    failed_packages=()
    successful_packages=()
    
    # Try to install all packages first
    if sudo $DNF_CMD install -y "${dnf_packages[@]}" 2>/dev/null; then
        print_success "All DNF packages installed successfully."
        INSTALLED_PACKAGES+=("${dnf_packages[@]}")
    else
        print_warning "Some packages failed to install. Attempting individual installation..."
        
        # Install packages individually to identify which ones fail
        for package in "${dnf_packages[@]}"; do
            print_info "Installing $package..."
            if sudo $DNF_CMD install -y "$package" 2>/dev/null; then
                print_success "$package installed successfully."
                successful_packages+=("$package")
                INSTALLED_PACKAGES+=("$package")
            else
                print_warning "Failed to install $package. Package may not be available in repositories."
                failed_packages+=("$package")
            fi
        done
        
        # Summary
        if [ ${#successful_packages[@]} -gt 0 ]; then
            print_success "Successfully installed ${#successful_packages[@]} packages: ${successful_packages[*]}"
        fi
        if [ ${#failed_packages[@]} -gt 0 ]; then
            print_warning "Failed to install ${#failed_packages[@]} packages: ${failed_packages[*]}"
        fi
    fi
else
    print_warning "No DNF packages to install for mode: $INSTALL_MODE"
fi

# Install Flatpak packages
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
        
        for app in "${flatpak_packages[@]}"; do
            install_flatpak_app "$app"
            # Small delay between installations to prevent overwhelming the system
            sleep 2
        done
        
        print_success "Flatpak packages installed successfully."
    fi
else
    print_warning "No Flatpak packages to install for mode: $INSTALL_MODE"
fi

print_success "Program installation from YAML completed." 