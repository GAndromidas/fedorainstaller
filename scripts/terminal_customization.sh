#!/bin/bash
# Terminal customization: ZSH, plugins, Starship

source "$(dirname "$0")/../common.sh"

customize_terminal() {
    step "Install ZSH, Oh-My-Zsh, plugins, and Starship"

    # --- ZSH & Oh-My-Zsh ---
    if ! command -v zsh >/dev/null; then
        print_info "Installing ZSH..."
        sudo $DNF_CMD install -y zsh && print_success "ZSH installed." || print_error "Failed to install ZSH."
        INSTALLED_PACKAGES+=(zsh)
    else
        print_warning "zsh is already installed. Skipping."
    fi

    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        print_info "Installing Oh-My-Zsh..."
        yes | sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
            && print_success "Oh-My-Zsh installed." \
            || print_error "Failed to install Oh-My-Zsh."
    else
        print_warning "Oh-My-Zsh is already installed. Skipping."
    fi

    # --- ZSH Plugins ---
    ZSH_CUSTOM="$HOME/.oh-my-zsh/custom"
    declare -A plugins=(
        [zsh-autosuggestions]="https://github.com/zsh-users/zsh-autosuggestions"
        [zsh-syntax-highlighting]="https://github.com/zsh-users/zsh-syntax-highlighting.git"
    )
    for plugin in "${!plugins[@]}"; do
        plugin_dir="$ZSH_CUSTOM/plugins/$plugin"
        if [ ! -d "$plugin_dir" ]; then
            git clone "${plugins[$plugin]}" "$plugin_dir" \
                && print_success "$plugin installed." \
                || print_error "Failed to install $plugin."
        else
            print_warning "$plugin already installed. Skipping."
        fi
    done

    # --- Change default shell to ZSH ---
    if [ "$SHELL" != "$(which zsh)" ]; then
        print_info "Changing shell to ZSH..."
        sudo chsh -s "$(which zsh)" "$USER" \
            && print_success "Shell changed to ZSH." \
            || print_error "Failed to change default shell."
    else
        print_warning "ZSH is already your default shell. Skipping."
    fi

    # --- .zshrc config ---
    print_info "Copying .zshrc to Home Folder..."
    if [ -f "$HOME/fedorainstaller/configs/.zshrc" ]; then
        cp "$HOME/fedorainstaller/configs/.zshrc" "$HOME/"
        sed -i '/^plugins=/c\plugins=(git zsh-autosuggestions zsh-syntax-highlighting)' "$HOME/.zshrc"
        print_success ".zshrc copied and configured successfully."
    else
        print_warning ".zshrc not found in configs. Skipping."
    fi

    # --- Starship prompt ---
    if ! command -v starship >/dev/null; then
        print_info "Installing Starship prompt..."
        curl -sS https://starship.rs/install.sh | sh -s -- -y \
            && print_success "Starship prompt installed successfully." \
            || print_error "Failed to install Starship."
        INSTALLED_PACKAGES+=(starship)
    else
        print_warning "starship is already installed. Skipping."
    fi
    mkdir -p "$HOME/.config"
    if [ -f "$HOME/fedorainstaller/configs/starship.toml" ]; then
        cp "$HOME/fedorainstaller/configs/starship.toml" "$HOME/.config/starship.toml"
        print_success "Starship config copied."
    else
        print_warning "starship.toml not found in configs. Skipping."
    fi

    # --- DE-specific tweaks ---
    if [ "$XDG_CURRENT_DESKTOP" ]; then
        case "${XDG_CURRENT_DESKTOP,,}" in
            *gnome*)
                print_info "Applying GNOME-specific tweaks (placeholder)"
                # Add GNOME-specific tweaks here
                ;;
            *kde*)
                print_info "Applying KDE-specific tweaks (placeholder)"
                # Add KDE-specific tweaks here
                ;;
            *cosmic*)
                print_info "Applying Cosmic-specific tweaks (placeholder)"
                # Add Cosmic-specific tweaks here
                ;;
            *)
                print_info "No specific tweaks for detected DE: $XDG_CURRENT_DESKTOP"
                ;;
        esac
    fi
}

customize_terminal
