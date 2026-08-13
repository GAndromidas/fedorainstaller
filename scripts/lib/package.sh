#!/bin/bash
set -uo pipefail

# ============================================================================
# Package library: DNF / Flatpak installation helpers.
# install_packages_batch is the main entry point used by the step scripts;
# it filters already-installed packages, tries a single batch command, and
# falls back to per-package installation with error reporting.
# ============================================================================

# Check if package is installed
is_package_installed() {
    local manager="$1"
    local pkg="$2"

    case "$manager" in
        dnf)
            rpm -q "$pkg" &>/dev/null
            ;;
        flatpak)
            flatpak list 2>/dev/null | grep -q "$pkg"
            ;;
    esac
}

# Install single package via DNF
dnf_install_single() {
    local pkg="$1"
    local verbose="${2:-false}"

    if [ "$verbose" = true ]; then
        printf "${THEME_TEXT}Installing DNF package:${RESET} %-30s" "$pkg"
    fi

    local output
    if output=$(sudo $DNF_CMD install -y "$pkg" 2>&1); then
        [ "$verbose" = true ] && printf "${THEME_SUCCESS} ✓ Success${RESET}\n"
        INSTALLED_PACKAGES+=("$pkg")
        return 0
    else
        [ "$verbose" = true ] && printf "${THEME_ERROR} ✗ Failed${RESET}\n"
        if [ "$verbose" = true ] || [[ "$output" == *"error:"* ]]; then
            echo "$output" | sed 's/^/    /'
        fi
        FAILED_PACKAGES+=("$pkg")
        return 1
    fi
}

# Install single package via Flatpak
flatpak_install_single() {
    local pkg="$1"
    local verbose="${2:-false}"

    if ! command -v flatpak &>/dev/null; then
        log_error "Flatpak not found"
        return 1
    fi

    if [ "$verbose" = true ]; then
        printf "${THEME_TEXT}Installing Flatpak app:${RESET} %-30s" "$pkg"
    fi

    local output
    if output=$(flatpak install -y flathub "$pkg" 2>&1); then
        [ "$verbose" = true ] && printf "${THEME_SUCCESS} ✓ Success${RESET}\n"
        INSTALLED_PACKAGES+=("$pkg")
        return 0
    else
        [ "$verbose" = true ] && printf "${THEME_ERROR} ✗ Failed${RESET}\n"
        if [ "$verbose" = true ] || [[ "$output" == *"error:"* ]]; then
            echo "$output" | sed 's/^/    /'
        fi
        FAILED_PACKAGES+=("$pkg")
        return 1
    fi
}

# Unified package installation function
# Parameters: $1 - Package manager type (dnf|flatpak), $@ - Packages to install
# Returns: 0 on success, 1 if some packages failed
install_package_generic() {
    local pkg_manager="$1"
    shift
    local pkgs=("$@")
    local total=${#pkgs[@]}
    local current=0
    local failed=0

    if [ $total -eq 0 ]; then
        ui_info "No packages to install"
        return 0
    fi

    local manager_name
    case "$pkg_manager" in
        dnf) manager_name="DNF" ;;
        flatpak) manager_name="Flatpak" ;;
        *) manager_name="Unknown" ;;
    esac

    echo -e "${CYAN}Installing ${total} packages via ${manager_name}...${RESET}"

    for pkg in "${pkgs[@]}"; do
        ((current++))

        # Check if already installed
        local already_installed=false
        case "$pkg_manager" in
            dnf)
                rpm -q "$pkg" &>/dev/null && already_installed=true
                ;;
            flatpak)
                flatpak list | grep -q "$pkg" &>/dev/null && already_installed=true
                ;;
        esac

        if [ "$already_installed" = true ]; then
            continue
        fi

        # Dry-run mode: simulate installation
        if [ "${DRY_RUN:-false}" = true ]; then
            ui_info "Dry-run: Would install $pkg"
            INSTALLED_PACKAGES+=("$pkg")
        else
            # Capture both stdout and stderr for better error diagnostics
            local error_output
            case "$pkg_manager" in
                dnf)
                    if error_output=$(sudo $DNF_CMD install -y "$pkg" 2>&1); then
                        INSTALLED_PACKAGES+=("$pkg")
                    else
                        ui_error "Failed to install $pkg"
                        FAILED_PACKAGES+=("$pkg")
                        log_error "Failed to install $pkg via $manager_name" "Check network connection and package availability"
                        # Log the actual error for debugging
                        echo "$error_output" >> "$INSTALL_LOG"
                        # Show last line of error if verbose or if it's a critical error
                        if [ "${VERBOSE:-false}" = true ] || [[ "$error_output" == *"error:"* ]]; then
                            local last_error=$(echo "$error_output" | grep -i "error" | tail -1)
                            [ -n "$last_error" ] && log_warning "  Error: $last_error" "Try running the failed command manually for more details"
                        fi
                        ((failed++))
                    fi
                    ;;
                flatpak)
                    if error_output=$(flatpak install -y flathub "$pkg" 2>&1); then
                        INSTALLED_PACKAGES+=("$pkg")
                    else
                        ui_error "Failed to install $pkg"
                        FAILED_PACKAGES+=("$pkg")
                        log_error "Failed to install $pkg via $manager_name" "Check network connection and package availability"
                        # Log the actual error for debugging
                        echo "$error_output" >> "$INSTALL_LOG"
                        # Show last line of error if verbose or if it's a critical error
                        if [ "${VERBOSE:-false}" = true ] || [[ "$error_output" == *"error:"* ]]; then
                            local last_error=$(echo "$error_output" | grep -i "error" | tail -1)
                            [ -n "$last_error" ] && log_warning "  Error: $last_error" "Try running the failed command manually for more details"
                        fi
                        ((failed++))
                    fi
                    ;;
            esac
        fi
    done

    if [ $failed -eq 0 ]; then
        ui_success "Package installation completed"
        return 0
    else
        ui_warn "Package installation completed with $failed failures" "Failed packages: ${FAILED_PACKAGES[*]}"
        return 1
    fi
}

# Batch install with fallback to individual (optimized for speed)
install_packages_batch() {
    local pkg_manager="$1"
    shift
    local packages=("$@")
    local total=${#packages[@]}

    if [ $total -eq 0 ]; then
        ui_info "No packages to install"
        return 0
    fi

    ui_info "Installing ${total} packages via $pkg_manager (batch mode)..."

    # Filter out already installed packages
    local packages_to_install=()
    for pkg in "${packages[@]}"; do
        local already_installed=false
        case "$pkg_manager" in
            dnf)
                rpm -q "$pkg" &>/dev/null && already_installed=true
                ;;
            flatpak)
                flatpak list | grep -q "$pkg" &>/dev/null && already_installed=true
                ;;
        esac

        if [ "$already_installed" = false ]; then
            packages_to_install+=("$pkg")
        fi
    done

    local filtered_total=${#packages_to_install[@]}
    if [ $filtered_total -eq 0 ]; then
        ui_info "All packages already installed"
        return 0
    fi

    # Try batch install first for speed
    if [ "${DRY_RUN:-false}" = true ]; then
        ui_info "Dry-run: Would install ${filtered_total} packages"
        INSTALLED_PACKAGES+=("${packages_to_install[@]}")
        return 0
    fi

    case "$pkg_manager" in
        dnf)
            if sudo $DNF_CMD install -y "${packages_to_install[@]}" >/dev/null 2>&1; then
                ui_success "All packages installed successfully in batch"
                INSTALLED_PACKAGES+=("${packages_to_install[@]}")
                return 0
            fi
            ;;
        flatpak)
            if flatpak install -y flathub "${packages_to_install[@]}" >/dev/null 2>&1; then
                ui_success "All packages installed successfully in batch"
                INSTALLED_PACKAGES+=("${packages_to_install[@]}")
                return 0
            fi
            ;;
    esac

    # Fallback to individual installation using the generic function
    ui_warn "Batch installation failed, falling back to individual installation..."
    install_package_generic "$pkg_manager" "${packages_to_install[@]}"
    return $?
}

# Update the whole system (dnf upgrade, mirrors refreshed automatically by dnf)
update_system() {
    ui_info "Updating system packages..."
    if sudo $DNF_CMD upgrade -y; then
        ui_success "System updated successfully"
    else
        ui_error "System update failed"
        return 1
    fi
}

# Refresh package metadata before installing (mirrors what update_system does,
# but only refreshes the cache — useful before a long batch install)
preload_package_lists() {
    ui_info "Preloading package lists..."
    sudo $DNF_CMD makecache >>"$INSTALL_LOG" 2>&1 || true
}
