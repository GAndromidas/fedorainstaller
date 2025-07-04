#!/bin/bash
source "$(dirname "$0")/../common.sh"
# Install Nerd Fonts for all users
step "Install Nerd Fonts"
print_info "Installing Nerd Fonts..."
FONT_DIR="/usr/share/fonts/nerd-fonts"
sudo mkdir -p "$FONT_DIR"

# Always fetch the latest version dynamically
LATEST_VERSION=$(curl -s https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest | grep 'tag_name' | cut -d '"' -f4)

# Install JetBrainsMono Nerd Font
JETBRAINS_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/${LATEST_VERSION}/JetBrainsMono.zip"
wget -qO /tmp/JetBrainsMono.zip "$JETBRAINS_URL"
sudo unzip -o /tmp/JetBrainsMono.zip -d "$FONT_DIR"
rm /tmp/JetBrainsMono.zip

# Install Hack Nerd Font
HACK_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/${LATEST_VERSION}/Hack.zip"
wget -qO /tmp/Hack.zip "$HACK_URL"
sudo unzip -o /tmp/Hack.zip -d "$FONT_DIR"
rm /tmp/Hack.zip

sudo fc-cache -fv
print_success "Nerd Fonts (JetBrainsMono, Hack) installed from $LATEST_VERSION."
