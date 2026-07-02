#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

step "Shell Setup"

# --- ZSH & Oh-My-Zsh ---
if ! command -v zsh >/dev/null; then
  print_info "Installing ZSH..."
  install_packages_batch "dnf" "zsh"
fi

if [ ! -d "$HOME/.oh-my-zsh" ]; then
  print_info "Installing Oh-My-Zsh..."
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

# --- ZSH Plugins (via DNF for system-wide install) ---
install_packages_batch "dnf" "zsh-autosuggestions" "zsh-syntax-highlighting"

# --- Change default shell ---
if [ "$SHELL" != "$(which zsh)" ]; then
  sudo chsh -s "$(which zsh)" "$USER"
fi

# --- .zshrc ---
if [ -f "$SCRIPT_DIR/../configs/.zshrc" ]; then
  cp "$SCRIPT_DIR/../configs/.zshrc" "$HOME/"
fi

# --- Starship ---
install_packages_batch "dnf" "starship"
mkdir -p "$HOME/.config"
if [ -f "$SCRIPT_DIR/../configs/starship.toml" ]; then
  cp "$SCRIPT_DIR/../configs/starship.toml" "$HOME/.config/starship.toml"
fi

# --- Fastfetch config ---
if command -v fastfetch >/dev/null 2>&1; then
  CONFIG_DIR="$HOME/.config/fastfetch"
  mkdir -p "$CONFIG_DIR"
  if [ -f "$SCRIPT_DIR/../configs/config.jsonc" ]; then
    cp "$SCRIPT_DIR/../configs/config.jsonc" "$CONFIG_DIR/config.jsonc"
  fi
fi

# --- Nerd Fonts ---
print_info "Installing Nerd Fonts..."
install_packages_batch "dnf" "wget" "unzip"
FONT_DIR="/usr/share/fonts/nerd-fonts"
sudo mkdir -p "$FONT_DIR"
LATEST_VERSION=$(curl -s https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest | grep 'tag_name' | cut -d '"' -f4)
[ -z "$LATEST_VERSION" ] && LATEST_VERSION="v3.3.0"
for font in JetBrainsMono Hack; do
  wget -qO "/tmp/$font.zip" "https://github.com/ryanoasis/nerd-fonts/releases/download/${LATEST_VERSION}/${font}.zip"
  sudo unzip -o "/tmp/$font.zip" -d "$FONT_DIR"
  rm "/tmp/$font.zip"
done
sudo fc-cache -fv

print_success "Shell setup complete."
