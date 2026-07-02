#!/bin/bash
set -uo pipefail

# Terminal helpers
__term_width() {
    tput cols 2>/dev/null || echo 80
}

__print_top_border() {
    local w=$(__term_width)
    echo -e "${THEME_BORDER}+$(printf '%*s' $((w - 2)) '' | tr ' ' '-')+${RESET}"
}

__print_bottom_border() {
    local w=$(__term_width)
    echo -e "${THEME_BORDER}+$(printf '%*s' $((w - 2)) '' | tr ' ' '-')+${RESET}"
}

__print_border_line() {
    local content="$1"
    local w=$(__term_width)
    local pad=$((w - ${#content} - 4))
    (( pad < 1 )) && pad=1
    echo -e "${THEME_BORDER}|${RESET} ${content}$(printf '%*s' $pad '') ${THEME_BORDER}|${RESET}"
}

__print_thick_top_border() {
    local w=$(__term_width)
    echo -e "${THEME_BORDER}#$(printf '%*s' $((w - 2)) '' | tr ' ' '=')#${RESET}"
}

__print_thick_bottom_border() {
    local w=$(__term_width)
    echo -e "${THEME_BORDER}#$(printf '%*s' $((w - 2)) '' | tr ' ' '=')#${RESET}"
}

__print_thick_border_line() {
    local content="$1"
    local w=$(__term_width)
    local pad=$((w - ${#content} - 4))
    (( pad < 1 )) && pad=1
    echo -e "${THEME_BORDER}#${RESET} ${content}$(printf '%*s' $pad '') ${THEME_BORDER}#${RESET}"
}

# Check if gum is available
if ! declare -f supports_gum >/dev/null 2>&1; then
supports_gum() {
    command -v gum &>/dev/null
}
fi

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
        echo ""
        echo -e "${THEME_HEADER}$title${RESET}"
        echo -e "${THEME_MUTED}(Enter numbers space-separated)${RESET}"
        echo ""
        local i=1
        for opt in "${options[@]}"; do
            echo -e "  [ ] $i) $opt"
            ((i++))
        done
        echo ""
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
if ! declare -f ui_confirm >/dev/null 2>&1; then
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
fi

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
if ! declare -f ui_header >/dev/null 2>&1; then
ui_header() {
    local title="$1"
    echo ""
    if supports_gum; then
        gum style --border normal --margin "1 2" --padding "1 2" --align center --foreground "$GUM_HEADER" "$title"
    else
        __print_top_border
        __print_border_line "${THEME_HEADER}${title}${RESET}"
        __print_bottom_border
    fi
    echo ""
}
fi

# Info message
if ! declare -f ui_info >/dev/null 2>&1; then
ui_info() {
    local message="$1"
    if supports_gum; then
        gum style --foreground "$GUM_TEXT" "$message"
    else
        echo -e "${THEME_TEXT}$message${RESET}"
    fi
}
fi

# Success message
if ! declare -f ui_success >/dev/null 2>&1; then
ui_success() {
    local message="$1"
    if supports_gum; then
        gum style --foreground "$GUM_SUCCESS" "✓ $message"
    else
        echo -e "${THEME_SUCCESS}✓ $message${RESET}"
    fi
}
fi

# Warning message
if ! declare -f ui_warn >/dev/null 2>&1; then
ui_warn() {
    local message="$1"
    if supports_gum; then
        gum style --foreground "$GUM_WARN" "⚠ $message"
    else
        echo -e "${THEME_WARN}⚠ $message${RESET}"
    fi
}
fi

# Error message
if ! declare -f ui_error >/dev/null 2>&1; then
ui_error() {
    local message="$1"
    if supports_gum; then
        gum style --foreground "$GUM_ERROR" "✗ $message"
    else
        echo -e "${THEME_ERROR}✗ $message${RESET}"
    fi
}
fi

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

# Simple banner with double-line box
if ! declare -f simple_banner >/dev/null 2>&1; then
simple_banner() {
    local title="$1"
    echo ""
    if supports_gum; then
        gum style --border double --align center --padding "1 2" --foreground "$GUM_HEADER" "$title"
    else
        __print_thick_top_border
        __print_thick_border_line "${THEME_HEADER}  ${title}${RESET}"
        __print_thick_bottom_border
    fi
    echo ""
}
fi

# Step indicator
if ! declare -f step >/dev/null 2>&1; then
step() {
    local message="$1"
    if supports_gum; then
        gum style --foreground "$GUM_PRIMARY" "▶ $message"
    else
        echo -e "${THEME_SECONDARY}▶ $message${RESET}"
    fi
}
fi
