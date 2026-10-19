#!/bin/bash
# Gaming and performance tweaks installation
# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

step "Gaming and performance tweaks"

{
  echo -e "\n${THEME_BORDER}═══════════════════════════════════════════════════════════════${RESET}"
  echo -e "${THEME_HEADER}  GAMING & PERFORMANCE TWEAKS${RESET}"
  echo -e "${THEME_TEXT}  Includes: MangoHud, GameMode, Steam, GOverlay, Heroic Launcher, ProtonPlus, Discord, and more.${RESET}"
  echo -e "${THEME_BORDER}═══════════════════════════════════════════════════════════════${RESET}"
} >/dev/tty

if [[ "${AUTO_CONFIRM:-false}" == true ]]; then
    print_info "Unattended mode: installing gaming and performance tweaks (default choice)."
elif supports_gum; then
    if gum confirm "Install gaming and performance tweaks?" --default=true 2>/dev/tty; then
        :
    else
        print_info "Gaming tweaks skipped."
        # Exit 2 = declined: the installer records SKIPPED (not COMPLETED)
        # so a later re-run offers gaming setup again.
        return 2
    fi
else
    echo -n "Install gaming tweaks? [Y/n]: " >/dev/tty
    read -r response </dev/tty
    response="${response:-Y}"
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        print_info "Gaming tweaks skipped."
        # Exit 2 = declined (see above).
        return 2
    fi
fi

# Install gaming packages from YAML configuration
print_info "Loading gaming package lists from gaming_mode.yaml..."

GAMING_YAML="$SCRIPT_DIR/../../configs/gaming_mode.yaml"
if [[ ! -f "$GAMING_YAML" ]]; then
    print_error "Gaming configuration file not found: $GAMING_YAML"
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

GAMING_PACKAGES=()
GAMING_FLATPAKS=()
read_yaml_packages "$GAMING_YAML" ".dnf.packages" "GAMING_PACKAGES"
read_yaml_packages "$GAMING_YAML" ".flatpak.apps" "GAMING_FLATPAKS"

print_info "Found ${#GAMING_PACKAGES[@]} gaming packages and ${#GAMING_FLATPAKS[@]} gaming Flatpaks"

# Batch return codes gate nothing fatal by themselves (single-package
# failures recover below), but a batch where NOTHING installed is a step
# failure — never silently mark it COMPLETED. BATCH_PENDING (set by
# install_packages_batch) is the already-installed filter count, so fully
# installed reruns don't false-fail.
_dnf_installed_before=${#INSTALLED_PACKAGES[@]}
install_packages_batch "dnf" "${GAMING_PACKAGES[@]}" || true
if [[ ${BATCH_PENDING:-0} -gt 0 && ${#INSTALLED_PACKAGES[@]} -eq ${_dnf_installed_before} ]]; then
    print_error "FAILED installing all ${BATCH_PENDING} pending gaming packages" "Batch failure — see log"
    return 1
fi

# gamemode is D-Bus activated: there is no gamemoded.service unit, so the
# old `systemctl enable --now gamemoded` was a permanent silent no-op. Just
# confirm the daemon exists on disk.
if command -v gamemoded >/dev/null 2>&1; then
    print_info "GameMode daemon available (D-Bus activated)"
fi

# Copy MangoHud configuration
if rpm -q mangohud >/dev/null 2>&1 || command -v mangohud >/dev/null; then
    print_info "Configuring MangoHud..."
    MANGOHUD_CONFIG_DIR="$HOME/.config/MangoHud"
    MANGOHUD_CONFIG_SOURCE="$SCRIPT_DIR/../../configs/MangoHud.conf"

    # Create MangoHud config directory if it doesn't exist
    if ! mkdir -p "$MANGOHUD_CONFIG_DIR" 2>/dev/null; then
        print_error "Failed to create MangoHud config directory: $MANGOHUD_CONFIG_DIR"
    else
        # Copy MangoHud configuration file, replacing if it exists
        if [ -f "$MANGOHUD_CONFIG_SOURCE" ]; then
            if cp "$MANGOHUD_CONFIG_SOURCE" "$MANGOHUD_CONFIG_DIR/MangoHud.conf" 2>/dev/null; then
                # Set proper permissions
                chmod 644 "$MANGOHUD_CONFIG_DIR/MangoHud.conf" 2>/dev/null || true

                # Verify the config was copied correctly
                if [ -f "$MANGOHUD_CONFIG_DIR/MangoHud.conf" ] && [ -s "$MANGOHUD_CONFIG_DIR/MangoHud.conf" ]; then
                    print_success "MangoHud configuration copied and verified at: $MANGOHUD_CONFIG_DIR/MangoHud.conf"
                else
                    print_error "MangoHud configuration file is empty or corrupted after copy"
                fi
            else
                print_error "Failed to copy MangoHud configuration file"
            fi
        else
            print_warning "MangoHud configuration file not found at: $MANGOHUD_CONFIG_SOURCE"
            print_info "Expected path: $(realpath "$SCRIPT_DIR/../../configs/MangoHud.conf" 2>/dev/null || echo "N/A")"
        fi
    fi
else
    print_warning "MangoHud not installed, skipping configuration."
fi

# Install additional gaming-related Flatpaks from YAML
if [ ${#GAMING_FLATPAKS[@]} -gt 0 ]; then
    print_info "Installing ${#GAMING_FLATPAKS[@]} gaming-related Flatpaks..."

    # Ensure Flatpak daemon is running
    if ! flatpak ps >/dev/null 2>&1; then
        print_info "Starting Flatpak daemon..."
        flatpak ps >/dev/null 2>&1 || true
    fi

    # Same gate as the DNF batch above: an all-zero install fails the step,
    # but only when something was actually pending (BATCH_PENDING).
    _flat_before=${#INSTALLED_PACKAGES[@]}
    install_packages_batch "flatpak" "${GAMING_FLATPAKS[@]}" || true
    if [[ ${BATCH_PENDING:-0} -gt 0 && ${#INSTALLED_PACKAGES[@]} -eq ${_flat_before} ]]; then
        print_error "FAILED installing all ${BATCH_PENDING} gaming Flatpaks"
        return 1
    fi
fi

print_success "Gaming and performance tweaks installation completed."
