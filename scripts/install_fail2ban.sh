#!/bin/bash
# Install and configure fail2ban
step "Install fail2ban"
print_info "Installing fail2ban..."
sudo $DNF_CMD install -y fail2ban
sudo systemctl enable --now fail2ban
print_success "fail2ban installed and enabled."

# Custom fail2ban configuration (Fedora style, adapted from Arch)
step "Configure fail2ban (jail.local)"
JAIL_LOCAL="/etc/fail2ban/jail.local"
if [ ! -f "$JAIL_LOCAL" ]; then
    print_info "Creating jail.local from jail.conf and applying customizations..."
    sudo cp /etc/fail2ban/jail.conf "$JAIL_LOCAL"
    sudo sed -i 's/^backend = auto/backend = systemd/' "$JAIL_LOCAL"
    sudo sed -i 's/^bantime  = 10m/bantime = 30m/' "$JAIL_LOCAL"
    sudo sed -i 's/^maxretry = 5/maxretry = 3/' "$JAIL_LOCAL"
    print_success "jail.local created and customized."
else
    print_warning "jail.local already exists. Skipping creation."
fi

print_info "Restarting fail2ban to apply configuration..."
sudo systemctl restart fail2ban
print_success "fail2ban configuration complete."
