#!/bin/bash
source "$(dirname "$0")/../common.sh"

step "Set hostname"
if command -v figlet >/dev/null; then figlet "Set Hostname"; else print_info "========== Set Hostname =========="; fi
print_info "Please enter the desired hostname:"
read -p "Hostname: " hostname
if [ -n "$hostname" ]; then
    sudo hostnamectl set-hostname "$hostname" \
        && print_success "Hostname set to $hostname successfully." \
        || print_error "Failed to set the hostname."
else
    print_warning "No hostname entered, skipping."
fi
