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

ui_info() { echo -e "${BLUE}$1${RESET}" | tee -a "$INSTALL_LOG"; }
ui_success() { echo -e "${GREEN}$1${RESET}" | tee -a "$INSTALL_LOG"; }
ui_warn() { echo -e "${YELLOW}$1${RESET}" | tee -a "$INSTALL_LOG"; }
ui_error() { echo -e "${RED}$1${RESET}" | tee -a "$INSTALL_LOG"; }

# ===== Banners =====

simple_banner() {
    local title="$1"
    echo -e "${CYAN}\n============================================================${RESET}"
    echo -e "${CYAN}========== $title ==========${RESET}"
    echo -e "${CYAN}============================================================${RESET}"
}

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

# ===== Input helpers =====

# Gum-based input with fallback
gum_input() {
    local prompt="$1"
    local default="${2:-}"

    if supports_gum; then
        if [ -n "$default" ]; then
            gum input --prompt "$prompt" --value "$default"
        else
            gum input --prompt "$prompt"
        fi
    else
        if [ -n "$default" ]; then
            read -r -p "$prompt [$default]: " response
            echo "${response:-$default}"
        else
            read -r -p "$prompt: " response
            echo "$response"
        fi
    fi
}

# Gum-based confirm with fallback
gum_confirm() {
    local prompt="$1"
    local default="${2:-true}"  # Default to true (yes)

    if supports_gum; then
        if [ "$default" = "true" ]; then
            gum confirm --default=true "$prompt"
        else
            gum confirm "$prompt"
        fi
    else
        local default_display="[y/N]"
        if [ "$default" = "true" ]; then
            default_display="[Y/n]"
        fi
        while true; do
            read -r -p "$prompt $default_display: " response
            case "${response,,}" in
                y|yes) return 0 ;;
                n|no|"")
                    if [ "$default" = "true" ]; then
                        return 0
                    else
                        return 1
                    fi
                    ;;
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

# ===== Generic gum UI helpers (unified menu, multiselect, spinner, etc.) =====

# Unified menu function with arrow navigation
ui_menu() {
    local title="$1"
    local description="${2:-}"
    shift 2
    local options=("$@")

    if supports_gum; then
        if [ -n "$description" ]; then
            gum style --foreground "$GUM_WARN" --margin "1 0" "$description"
            echo ""
        fi
        gum choose --header="$title" --cursor.foreground "$GUM_PRIMARY" --selected.foreground "$GUM_PRIMARY" "${options[@]}"
    else
        echo ""
        echo -e "${THEME_HEADER}$title${RESET}"
        if [ -n "$description" ]; then
            echo -e "${THEME_MUTED}$description${RESET}"
        fi
        echo ""
        local i=1
        for opt in "${options[@]}"; do
            echo -e "  ${THEME_SECONDARY}$i)${RESET} $opt"
            ((i++))
        done
        echo ""
        local selection
        while true; do
            read -r -p "$(echo -e "${THEME_SECONDARY}Select option [1-$((i-1))]: ${RESET}")" selection
            if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "$((i-1))" ]; then
                echo "${options[$((selection-1))]}"
                return 0
            fi
            echo -e "${THEME_ERROR}Invalid selection. Try again.${RESET}"
        done
    fi
}

# Multi-select menu for custom packages
ui_multiselect() {
    local title="$1"
    shift
    local options=("$@")

    if supports_gum; then
        gum choose --header="$title" --no-limit --cursor.foreground "$GUM_PRIMARY" --selected.foreground "$GUM_PRIMARY" "${options[@]}"
    else
        echo "" >&2
        echo -e "${THEME_HEADER}$title${RESET}" >&2
        echo -e "${THEME_MUTED}(Enter numbers space-separated)${RESET}" >&2
        echo "" >&2
        local i=1
        for opt in "${options[@]}"; do
            echo -e "  [ ] $i) $opt" >&2
            ((i++))
        done
        echo "" >&2
        local selection
        read -r -p "$(echo -e "${THEME_SECONDARY}Enter numbers (space-separated): ${RESET}")" selection
        for num in $selection; do
            if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "$((i-1))" ]; then
                echo "${options[$((num-1))]}"
            fi
        done
    fi
}

# Multi-select menu with pre-selected options.
# $1: title, $2: newline-separated list of pre-selected options (* = all),
# then the full list of options.
ui_multiselect_preselect() {
    local title="$1"
    local preselected="$2"
    shift 2
    local options=("$@")

    if supports_gum; then
        local selected_args=()
        if [ "$preselected" = "*" ]; then
            selected_args=(--selected="*")
        elif [ -n "$preselected" ]; then
            # gum --selected takes a comma-separated list
            selected_args=(--selected="$(printf '%s' "$preselected" | tr '\n' ',')")
        fi
        gum choose --header="$title" --no-limit \
            --cursor.foreground "$GUM_PRIMARY" --selected.foreground "$GUM_PRIMARY" \
            --selected-prefix "[x] " --unselected-prefix "[ ] " \
            "${selected_args[@]}" "${options[@]}"
    else
        echo "" >&2
        echo -e "${THEME_HEADER}$title${RESET}" >&2
        echo -e "${THEME_MUTED}(Enter numbers space-separated)${RESET}" >&2
        echo "" >&2
        local i=1
        for opt in "${options[@]}"; do
            echo -e "  [ ] $i) $opt" >&2
            ((i++))
        done
        echo "" >&2
        local selection
        read -r -p "$(echo -e "${THEME_SECONDARY}Enter numbers (space-separated): ${RESET}")" selection
        for num in $selection; do
            if [[ "$num" =~ ^[0-9]+$ ]] && [ "$num" -ge 1 ] && [ "$num" -le "$((i-1))" ]; then
                echo "${options[$((num-1))]}"
            fi
        done
    fi
}

# Confirmation dialog
ui_confirm() {
    local question="$1"
    local description="${2:-}"

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

# Progress spinner for long operations
ui_spinner() {
    local message="$1"
    shift
    local command=("$@")

    if supports_gum; then
        gum spin --spinner dot --title="$message" -- "${command[@]}"
    else
        echo -e "${THEME_TEXT}$message...${RESET}"
        "${command[@]}"
    fi
}

# Progress bar for batch operations
ui_progress() {
    local total="$1"
    local current="$2"
    local message="$3"

    if supports_gum; then
        local percent=$((current * 100 / total))
        gum format --template "progress" \
            --field "value:$percent" \
            --field "message:$message" \
            <<< "$message"
    else
        local bar_width=40
        local filled=$((current * bar_width / total))
        local empty=$((bar_width - filled))
        printf "\r${THEME_SECONDARY}%s${RESET} [%s%s] %d/%d" \
            "$message" \
            "$(printf '#%.0s' $(seq 1 $filled))" \
            "$(printf ' %.0s' $(seq 1 $empty))" \
            "$current" "$total"
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

# Input prompt
ui_input() {
    local prompt="$1"
    local default="${2:-}"

    if supports_gum; then
        gum input --prompt="$prompt" --prompt.foreground "$GUM_PRIMARY" --value="$default"
    else
        local response
        read -r -p "$(echo -e "${THEME_SECONDARY}${prompt}${RESET}")" response
        echo "${response:-$default}"
    fi
}

# Password input
ui_password() {
    local prompt="$1"

    if supports_gum; then
        gum input --password --prompt="$prompt" --prompt.foreground "$GUM_PRIMARY"
    else
        local response
        read -r -s -p "$(echo -e "${THEME_SECONDARY}${prompt}${RESET}")" response
        echo ""
        echo "$response"
    fi
}
