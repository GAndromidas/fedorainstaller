#!/bin/bash
set -uo pipefail
# One query for ALL candidates instead of one fork per package:
#   dnf:     rpm -q accepts multiple names and prints the FOUND ones (one
#            fork for the whole batch).
#   flatpak: one `flatpak list --app` dump, membership by exact app id.
# Callers must pass a non-empty list — guard your loops.
PKG_INSTALLED_MAP=()
populate_installed_map() {
    local manager="$1"; shift
    PKG_INSTALLED_MAP=()
    local p
    case "$manager" in
        dnf)
            while IFS= read -r p; do PKG_INSTALLED_MAP["$p"]=1; done < <(rpm -q -- "$@" 2>/dev/null)
            ;;
        flatpak)
            command -v flatpak &>/dev/null || return 0
            while IFS= read -r p; do PKG_INSTALLED_MAP["${p%% *}"]=1; done < <(flatpak list --app 2>/dev/null)
            ;;
    esac
}

pkg_installed_via_map() {
    [[ -n "${PKG_INSTALLED_MAP[$1]:-}" ]]
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

    # Single-filter: one query for the whole list, no fork per package.
    populate_installed_map "$pkg_manager" "${pkgs[@]}"

    for pkg in "${pkgs[@]}"; do
        ((current++))

        # Check if already installed
        if pkg_installed_via_map "$pkg"; then
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

    # Number of packages this batch actually tried to install (after the
    # already-installed filter). 0 = nothing pending → callers must not
    # treat "no packages newly installed" as a failure on idempotent reruns.
    BATCH_PENDING=0

    if [ $total -eq 0 ]; then
        ui_info "No packages to install"
        return 0
    fi

    ui_info "Installing ${total} packages via $pkg_manager (batch mode)..."

    # Filter out already installed packages — ONE query instead of a fork
    # per package (N×rpm/flatpak pipelines dominated batch prep time on a
    # first install).
    populate_installed_map "$pkg_manager" "${packages[@]}"
    local packages_to_install=()
    for pkg in "${packages[@]}"; do
        if ! pkg_installed_via_map "$pkg"; then
            packages_to_install+=("$pkg")
        fi
    done

    local filtered_total=${#packages_to_install[@]}
    if [ $filtered_total -eq 0 ]; then
        ui_info "All packages already installed"
        return 0
    fi
    BATCH_PENDING=$filtered_total

    # Try batch install first for speed
    if [ "${DRY_RUN:-false}" = true ]; then
        ui_info "Dry-run: Would install ${filtered_total} packages"
        INSTALLED_PACKAGES+=("${packages_to_install[@]}")
        return 0
    fi

    case "$pkg_manager" in
        dnf)
            local batch_out=""
            if batch_out=$(sudo $DNF_CMD install -y "${packages_to_install[@]}" 2>&1); then
                ui_success "All packages installed successfully in batch"
                INSTALLED_PACKAGES+=("${packages_to_install[@]}")
                return 0
            fi
            # Batch failures must be diagnosable — never swallow dnf output.
            { echo ""; echo "[$(date '+%F %T')] BATCH FAILURE (dnf) — fallback to per-package"; echo "$batch_out"; } >> "$INSTALL_LOG" 2>/dev/null || true
            ;;
        flatpak)
            local batch_out=""
            if batch_out=$(flatpak install -y flathub "${packages_to_install[@]}" 2>&1); then
                ui_success "All packages installed successfully in batch"
                INSTALLED_PACKAGES+=("${packages_to_install[@]}")
                return 0
            fi
            { echo ""; echo "[$(date '+%F %T')] BATCH FAILURE (flatpak) — fallback to per-app"; echo "$batch_out"; } >> "$INSTALL_LOG" 2>/dev/null || true
            ;;
    esac

    # Fallback to individual installation using the generic function
    ui_warn "Batch installation failed, falling back to individual installation..."
    install_package_generic "$pkg_manager" "${packages_to_install[@]}"
    return $?
}
