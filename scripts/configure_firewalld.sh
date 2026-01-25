#!/bin/bash
source "$(dirname "$0")/../common.sh"
# Configure firewalld with basic rules
step "Configure firewalld"
print_info "Configuring firewalld..."
sudo systemctl enable --now firewalld
sudo firewall-cmd --permanent --add-service=ssh
sudo firewall-cmd --permanent --add-service=cockpit

# Configure KDE Connect ports if KDE Connect is installed
if rpm -q kdeconnect-kde &>/dev/null || rpm -q kdeconnect &>/dev/null; then
    print_info "Configuring KDE Connect firewall ports..."
    # KDE Connect uses UDP ports 1714-1764 for discovery and communication
    sudo firewall-cmd --permanent --add-port=1714-1764/udp
    print_success "KDE Connect ports (1714-1764/udp) added to firewall."
fi

sudo firewall-cmd --reload
print_success "firewalld configured."
