#!/bin/bash
set -uo pipefail

# ============================================================================
# UI library: terminal styling, menus, prompts and confirmations.
# Both the interactive menus (gum-based when available, plain otherwise) and
# the messaging helpers used by the step scripts live here.
# ============================================================================

# Check if gum is available for enhanced UI
supports_gum() {
    command -v gum >/dev/null 2>&1
}

# ===== Basic output helpers (console + log file) =====

# stdout discipline lives in core.sh (__emit): colored on a real TTY, plain
# when piped/redirected, and the plain text appended to INSTALL_LOG.
ui_info()    { __emit "$BLUE"    "$1"; }
ui_success() { __emit "$GREEN"   "$1"; }
ui_warn()    { __emit "$YELLOW"  "$1"; }
ui_error()   { __emit "$RED"     "$1"; }

fedora_ascii() {
    echo -e "${CYAN}"
    cat << "EOF"
  ______       _                 _____           _        _ _
 |  ____|     | |               |_   _|         | |      | | |
 | |__ ___  __| | ___  _ __ __ _  | |  _ __  ___| |_ __ _| | | ___ _ __
 |  __/ _ \/ _` |/ _ \| '__/ _` | | | | '_ \/ __| __/ _` | | |/ _ \ '__|
 | | |  __/ (_| | (_) | | | (_| |_| |_| | | \__ \ || (_| | | |  __/ |
 |_|  \___|\__,_|\___/|_|  \__,_|_____|_| |_|___/\__\__,_|_|_|\___|_|
EOF
    echo -e "${RESET}"
}
# Gum-based confirm with fallback
gum_confirm() {
    local prompt="$1"
    local default="${2:-true}"  # Default to true (yes)

    # --yes / unattended mode accepts the existing dialog default.
    if [[ "${AUTO_CONFIRM:-false}" == true ]]; then
        log_to_file "Auto-confirmed default ($default): $prompt"
        [[ "$default" == "true" ]] && return 0 || return 1
    fi

    if supports_gum; then
        # Draw on the controlling terminal: when stdout is redirected
        # (dashboard runs it) the confirm would be invisible, and gum's
        # non-interactive path silently answers the default — auto-accepting
        # optional installs the user never saw.
        if exec 3</dev/tty 2>/dev/null; then
            exec 3<&-
            if [ "$default" = "true" ]; then
                gum confirm --default=true "$prompt" </dev/tty >/dev/tty 2>/dev/tty
            else
                gum confirm --default=false "$prompt" </dev/tty >/dev/tty 2>/dev/tty
            fi
            return $?
        fi
        # No controlling terminal at all: fall back to the env default
        # and log it, mirroring AUTO_CONFIRM behavior.
        log_to_file "Non-interactive shell: using default ($default) for confirm: $prompt"
        [[ "$default" == true ]] && return 0 || return 1
    else
        local default_display="[y/N]"
        if [ "$default" = "true" ]; then
            default_display="[Y/n]"
        fi
        while true; do
            read -r -p "$prompt $default_display: " response || return 1
            case "${response,,}" in
                y|yes) return 0 ;;
                n|no) return 1 ;;
                "") [ "$default" = "true" ] && return 0 || return 1 ;;
            esac
        done
    fi
}

# ===== Installation mode menus =====

# Validate the selected INSTALL_MODE
validate_install_mode() {
    local mode="$1"

    case "$mode" in
        "default"|"minimal"|"server")
            return 0
            ;;
        *)
            log_error "Invalid INSTALL_MODE: '$mode'. Valid modes are: default, minimal, server"
            return 1
            ;;
    esac
}

# Show the main mode-selection menu (server-only on headless systems)
show_menu() {
    # Display detected OS information
    local detected_os="Fedora"
    if [[ -f /etc/os-release ]]; then
        detected_os=$(grep -E '^PRETTY_NAME=' /etc/os-release | cut -d'"' -f2)
    fi

    # Check if system is headless and only offer server mode
    if is_headless_system; then
        ui_warn "Headless system detected. Only Server mode is available."
        echo -e "${GREEN}Your OS is: $detected_os${RESET}"
        INSTALL_MODE="server"
        echo "Installation Mode: Server - Headless server setup"
        return
    fi

    # Check if gum is available, fallback to traditional menu if not
    if supports_gum; then
        show_gum_menu
    else
        show_traditional_menu
    fi
}

show_gum_menu() {
    # Display detected OS information
    local detected_os="Fedora"
    if [[ -f /etc/os-release ]]; then
        detected_os=$(grep -E '^PRETTY_NAME=' /etc/os-release | cut -d'"' -f2)
    fi

    echo -e "${CYAN}Your OS is: $detected_os${RESET}"
    echo ""

    echo -e "${YELLOW}This script will transform your fresh Fedora installation into a${RESET}"
    echo -e "${YELLOW}fully configured, optimized system with all the tools you need!${RESET}"
    echo ""

    local choice=$(gum choose --cursor="-> " \
        "Standard - Complete setup with all packages (intermediate users)" \
        "Minimal - Essential tools only (recommended for new users)" \
        "Server - Headless server setup (Docker, SSH, etc.)" \
        "Exit - Cancel installation")

    case "$choice" in
        "Standard"*)
            INSTALL_MODE="default"
            if validate_install_mode "$INSTALL_MODE"; then
                echo "Installation Mode: Standard - Complete setup with all packages (intermediate users)"
            else
                log_error "Failed to validate installation mode"
                exit 1
            fi
            ;;
        "Minimal"*)
            INSTALL_MODE="minimal"
            if validate_install_mode "$INSTALL_MODE"; then
                echo "Installation Mode: Minimal - Essential tools only (recommended for new users)"
            else
                log_error "Failed to validate installation mode"
                exit 1
            fi
            ;;
        "Server"*)
            INSTALL_MODE="server"
            if validate_install_mode "$INSTALL_MODE"; then
                echo "Installation Mode: Server - Headless server setup"
            else
                log_error "Failed to validate installation mode"
                exit 1
            fi
            ;;
        "Exit"*)
            echo -e "${YELLOW}Installation cancelled. You can run this script again anytime.${RESET}"
            exit 0
            ;;
    esac
}

show_traditional_menu() {
    # Display detected OS information
    local detected_os="Fedora"
    if [[ -f /etc/os-release ]]; then
        detected_os=$(grep -E '^PRETTY_NAME=' /etc/os-release | cut -d'"' -f2)
    fi

    echo "WELCOME TO FEDORA INSTALLER"
    echo "----------------------------------------"
    echo "Your OS is: $detected_os"
    echo ""
    echo "This script will transform your fresh Fedora installation into a"
    echo "fully configured, optimized system with all the tools you need!"
    echo ""
    echo -e "${CYAN}Choose your installation mode:${RESET}"
    echo ""
    printf "  1) Standard%-12s - Complete setup with all packages (intermediate users)\n" ""
    printf "  2) Minimal%-13s - Essential tools only (recommended for new users)\n" ""
    printf "  3) Server%-13s - Headless server setup (Docker, SSH, etc.)\n" ""
    printf "  4) Exit%-16s - Cancel installation\n" ""
    echo ""

    while true; do
        read -r -p "$(echo -e "${CYAN}Enter your choice [1-4]: ${RESET}")" menu_choice
        case "$menu_choice" in
            1)
                INSTALL_MODE="default"
                if validate_install_mode "$INSTALL_MODE"; then
                    echo "Installation Mode: Standard - Complete setup with all packages (intermediate users)"
                    break
                else
                    log_error "Failed to validate installation mode"
                    exit 1
                fi
                ;;
            2)
                INSTALL_MODE="minimal"
                if validate_install_mode "$INSTALL_MODE"; then
                    echo "Installation Mode: Minimal - Essential tools only (recommended for new users)"
                    break
                else
                    log_error "Failed to validate installation mode"
                    exit 1
                fi
                ;;
            3)
                INSTALL_MODE="server"
                if validate_install_mode "$INSTALL_MODE"; then
                    echo "Installation Mode: Server - Headless server setup"
                    break
                else
                    log_error "Failed to validate installation mode"
                    exit 1
                fi
                ;;
            4)
                echo -e "\n${YELLOW}Installation cancelled. You can run this script again anytime.${RESET}"
                exit 0
                ;;
            *)
                echo -e "\n${RED}Invalid choice! Please enter 1, 2, 3, or 4.${RESET}\n"
                ;;
        esac
    done
}
# Confirmation dialog
ui_confirm() {
    local question="$1"
    local description="${2:-}"
    local default_yes="${3:-true}"

    # --yes / unattended mode accepts the existing dialog default. Callers can
    # pass false when the original prompt intentionally defaulted to No.
    if [[ "${AUTO_CONFIRM:-false}" == true ]]; then
        log_to_file "Auto-confirmed default ($default_yes): $question"
        [[ "$default_yes" == true ]] && return 0 || return 1
    fi

    if supports_gum; then
        (
            exec >/dev/tty 2>/dev/tty
            echo ""
            if [ -n "$description" ]; then
                gum style --foreground "$GUM_WARN" "$description"
            fi
            if gum confirm --default=true --prompt.foreground "$GUM_PRIMARY" --selected.background "$GUM_PRIMARY" "$question"; then
                exit 0
            else
                exit 1
            fi
        )
        return $?
    else
        echo ""
        if [ -n "$description" ]; then
            echo -e "${THEME_WARN}${description}${RESET}"
        fi
        local response
        while true; do
            read -r -p "$(echo -e "${THEME_SECONDARY}${question} [Y/n]: ${RESET}")" response
            response=${response,,}
            case "$response" in
                ""|y|yes) return 0 ;;
                n|no) return 1 ;;
                *) echo -e "\n${THEME_ERROR}Please answer Y (yes) or N (no).${RESET}\n" ;;
            esac
        done
    fi
}
# Styled header with bordered box
ui_header() {
    local title="$1"
    echo ""
    if supports_gum; then
        gum style --border normal --margin "1 2" --padding "1 2" --align center --foreground "$GUM_HEADER" "$title"
    else
        echo -e "${THEME_BORDER}+$(printf '%*s' $(($(tput cols 2>/dev/null || echo 80) - 2)) '' | tr ' ' '-')+${RESET}"
        echo -e "${THEME_BORDER}|${RESET} ${THEME_HEADER}${title}${RESET}$(printf '%*s' $(($(tput cols 2>/dev/null || echo 80) - ${#title} - 4)) '') ${THEME_BORDER}|${RESET}"
        echo -e "${THEME_BORDER}+$(printf '%*s' $(($(tput cols 2>/dev/null || echo 80) - 2)) '' | tr ' ' '-')+${RESET}"
    fi
    echo ""
}
