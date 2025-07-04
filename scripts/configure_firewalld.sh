#!/bin/bash
# Configure firewalld with basic rules
step "Configure firewalld"
print_info "Configuring firewalld..."
sudo systemctl enable --now firewalld
sudo firewall-cmd --permanent --add-service=ssh
sudo firewall-cmd --permanent --add-service=cockpit
sudo firewall-cmd --reload
print_success "firewalld configured."
