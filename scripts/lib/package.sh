#!/bin/bash
set -uo pipefail

# Check if package is installed
if ! declare -f is_package_installed >/dev/null 2>&1; then
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
fi

# Install single package via DNF
if ! declare -f dnf_install_single >/dev/null 2>&1; then
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
fi

# Install single package via Flatpak
if ! declare -f flatpak_install_single >/dev/null 2>&1; then
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
fi

# Generic package installer with error handling
if ! declare -f install_package_generic >/dev/null 2>&1; then
install_package_generic() {
    local manager="$1"
    shift
    local packages=("$@")
    local failed=0

    for pkg in "${packages[@]}"; do
        local manager_name=""
        case "$manager" in
            dnf) manager_name="DNF" ;;
            flatpak) manager_name="Flatpak" ;;
        esac

        if [ "${DRY_RUN:-false}" = true ]; then
            ui_info "Dry-run: Would install $pkg via $manager_name"
            INSTALLED_PACKAGES+=("$pkg")
        else
            local error_output
            case "$manager" in
                dnf)
                    error_output=$(sudo $DNF_CMD install -y "$pkg" 2>&1)
                    ;;
                flatpak)
                    error_output=$(flatpak install -y flathub "$pkg" 2>&1)
                    ;;
            esac

            if [ $? -eq 0 ]; then
                INSTALLED_PACKAGES+=("$pkg")
            else
                ui_error "Failed to install $pkg"
                FAILED_PACKAGES+=("$pkg")
                log_error "Failed to install $pkg via $manager_name"
                echo "$error_output" >> "$INSTALL_LOG"
                ((failed++))
            fi
        fi
    done

    if [ "$failed" -eq 0 ]; then
        ui_success "Package installation completed"
        return 0
    else
        ui_warn "Package installation completed with $failed failures"
        return 1
    fi
}
fi

# Batch package installation with filtering
if ! declare -f install_packages_batch >/dev/null 2>&1; then
install_packages_batch() {
    local manager="$1"
    shift
    local packages=("$@")
    local total=${#packages[@]}

    if [ "$total" -eq 0 ]; then
        return 0
    fi

    local packages_to_install=()
    for pkg in "${packages[@]}"; do
        if ! is_package_installed "$manager" "$pkg"; then
            packages_to_install+=("$pkg")
        fi
    done

    local install_count=${#packages_to_install[@]}
    if [ "$install_count" -eq 0 ]; then
        ui_info "All $total packages already installed"
        return 0
    elif [ "$install_count" -lt "$total" ]; then
        ui_info "Installing $install_count/$total packages ($((total - install_count)) already installed)"
    else
        ui_info "Installing $install_count packages..."
    fi

    install_package_generic "$manager" "${packages_to_install[@]}"
}
fi
