#!/bin/bash
# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common.sh"
# Install and configure fail2ban
step "Install fail2ban"
print_info "Installing fail2ban..."
if install_packages_batch "dnf" "fail2ban"; then
    sudo systemctl enable --now fail2ban.service
    print_success "fail2ban installed and enabled."
else
    print_error "Failed to install fail2ban. Package may not be available."
    exit 1
fi

# Custom fail2ban configuration (Fedora style)
step "Configure fail2ban (jail.local)"
JAIL_LOCAL="/etc/fail2ban/jail.local"
if [ ! -f "$JAIL_LOCAL" ]; then
    print_info "Creating jail.local from jail.conf and applying customizations..."
    if [ ! -f "/etc/fail2ban/jail.conf" ]; then
        print_error "jail.conf not found. Cannot create jail.local."
        exit 1
    fi

    sudo cp /etc/fail2ban/jail.conf "$JAIL_LOCAL"
    # Spacing-tolerant substitutions: the previously hardcoded patterns
    # (backend = auto / bantime  = 10m) silently no-op whenever upstream
    # changed spacing, while the step still claimed success. Final values
    # are verified below.
    sudo sed -i -E 's/^backend *= *auto$/backend = systemd/' "$JAIL_LOCAL"
    sudo sed -i -E 's/^(bantime *= *)[0-9a-z]+$/\1 30m/' "$JAIL_LOCAL"
    sudo sed -i -E 's/^(maxretry *= *)[0-9]+$/\1 3/' "$JAIL_LOCAL"

    _sanity=0
    sudo grep -qE '^backend *= *systemd$' "$JAIL_LOCAL" || _sanity=1
    sudo grep -qE '^bantime *= *30m$' "$JAIL_LOCAL" || _sanity=1
    sudo grep -qE '^maxretry *= *3$' "$JAIL_LOCAL" || _sanity=1
    if [ "$_sanity" -eq 0 ]; then
        print_success "jail.local created and customized."
    else
        print_warning "jail.local created, but some customizations did not apply — verify bantime/maxretry/backend manually."
    fi
else
    print_warning "jail.local already exists. Skipping creation."
fi

print_info "Restarting fail2ban to apply configuration..."
sudo systemctl restart fail2ban
print_success "fail2ban configuration complete."
