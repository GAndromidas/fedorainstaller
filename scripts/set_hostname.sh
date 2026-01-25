#!/bin/bash
source "$(dirname "$0")/../common.sh"

step "Set hostname"
if command -v figlet >/dev/null; then figlet "Set Hostname"; else print_info "========== Set Hostname =========="; fi

echo -e "\n${YELLOW}═══════════════════════════════════════════════════════════════${RESET}"
echo -e "${CYAN}🏷️  HOSTNAME CONFIGURATION${RESET}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${RESET}"
echo -e "${CYAN}Please enter the desired hostname for your system:${RESET}"
echo -e "${YELLOW}This will be your computer's name on the network.${RESET}"
echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${RESET}"
read -p "Hostname: " hostname
if [ -n "$hostname" ]; then
    sudo hostnamectl set-hostname "$hostname" \
        && print_success "Hostname set to $hostname successfully." \
        || print_error "Failed to set the hostname."
else
    print_warning "No hostname entered, skipping."
fi
echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${RESET}\n"
