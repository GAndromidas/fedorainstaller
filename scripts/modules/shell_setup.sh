#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

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
# $SHELL is the invoking environment (wrong under sudo/ssh); ask passwd via
# getent, which macOS `which` is not: use command -v.
local_target_shell=$(command -v zsh)
users_login_shell=$(getent passwd "$USER" 2>/dev/null | cut -d: -f7)
if [ "$users_login_shell" != "$local_target_shell" ]; then
  sudo chsh -s "$local_target_shell" "$USER"
fi

# --- .zshrc ---
if [ -f "$SCRIPT_DIR/../../configs/.zshrc" ]; then
  cp "$SCRIPT_DIR/../../configs/.zshrc" "$HOME/"
fi

# --- Starship ---
if ! command -v starship >/dev/null; then
  print_info "Installing Starship prompt..."
  sh -c "$(curl -fsSL https://starship.rs/install.sh)" "" -y
fi
mkdir -p "$HOME/.config"
if [ -f "$SCRIPT_DIR/../../configs/starship.toml" ]; then
  cp "$SCRIPT_DIR/../../configs/starship.toml" "$HOME/.config/starship.toml"
fi

# --- Fastfetch config ---
if command -v fastfetch >/dev/null 2>&1; then
  CONFIG_DIR="$HOME/.config/fastfetch"
  mkdir -p "$CONFIG_DIR"
  if [ -f "$SCRIPT_DIR/../../configs/config.jsonc" ]; then
    cp "$SCRIPT_DIR/../../configs/config.jsonc" "$CONFIG_DIR/config.jsonc"
  fi
fi

# --- Nerd Fonts ---
print_info "Installing Nerd Fonts..."
install_packages_batch "dnf" "wget" "unzip" || true
FONT_DIR="/usr/share/fonts/nerd-fonts"
sudo mkdir -p "$FONT_DIR"
# GitHub tag parse wired to a known-good fallback, and each font download is
# gated: a failing wget previously left empty/partial installs while the
# module still claimed success.
LATEST_VERSION=$(curl -fsSL https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest 2>/dev/null | grep 'tag_name' | cut -d '"' -f4)
[ -z "$LATEST_VERSION" ] && LATEST_VERSION="v3.3.0"
_font_failures=0
for font in JetBrainsMono Hack; do
  if wget -O "/tmp/$font.zip" "https://github.com/ryanoasis/nerd-fonts/releases/download/${LATEST_VERSION}/${font}.zip" >>"$INSTALL_LOG" 2>&1; then
    sudo unzip -o "/tmp/$font.zip" -d "$FONT_DIR" >>"$INSTALL_LOG" 2>&1 || _font_failures=1
    rm -f "/tmp/$font.zip"
  else
    _font_failures=1
    print_warning "Font download failed: $font ($LATEST_VERSION)"
  fi
done
sudo fc-cache -fv >/dev/null 2>&1
if [ "$_font_failures" -ne 0 ]; then
  print_warning "Some Nerd Fonts failed to install — re-run shell setup or install manually."
fi

print_success "Shell setup complete."
