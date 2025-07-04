#!/bin/bash
# Create Fastfetch config for user
step "Create Fastfetch config"
print_info "Generating and replacing Fastfetch config..."
CONFIG_DIR="$HOME/.config/fastfetch"
INSTALLER_CONFIG="$(dirname "$0")/../configs/config.jsonc"
mkdir -p "$CONFIG_DIR"
# Always generate default config first
fastfetch --gen-config --file "$CONFIG_DIR/config.jsonc"
# Then replace with custom config if it exists
if [ -f "$INSTALLER_CONFIG" ]; then
    cp "$INSTALLER_CONFIG" "$CONFIG_DIR/config.jsonc"
    print_success "Custom Fastfetch config copied over default."
else
    print_warning "Custom config.jsonc not found in installer. Default config remains."
fi
