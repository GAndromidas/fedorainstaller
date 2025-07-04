#!/bin/bash
source "$(dirname "$0")/../common.sh"
# Create Fastfetch config for user
step "Create Fastfetch config"
print_info "Generating and replacing Fastfetch config..."
CONFIG_DIR="$HOME/.config/fastfetch"
INSTALLER_CONFIG="$(dirname "$0")/../configs/config.jsonc"
mkdir -p "$CONFIG_DIR"

# Check if fastfetch is installed
if ! command -v fastfetch >/dev/null 2>&1; then
    print_warning "fastfetch is not installed. Skipping config creation."
    exit 0
fi

# Always generate default config first
if fastfetch --gen-config --file "$CONFIG_DIR/config.jsonc"; then
    # Then replace with custom config if it exists
    if [ -f "$INSTALLER_CONFIG" ]; then
        cp "$INSTALLER_CONFIG" "$CONFIG_DIR/config.jsonc"
        print_success "Custom Fastfetch config copied over default."
    else
        print_warning "Custom config.jsonc not found in installer. Default config remains."
    fi
else
    print_error "Failed to generate fastfetch config."
    exit 1
fi
