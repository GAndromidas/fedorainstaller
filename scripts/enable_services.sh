#!/bin/bash
source "$(dirname "$0")/../common.sh"
# Enable and start required systemd services
step "Enable system services"
print_info "Enabling and starting systemd services..."
SERVICES=(firewalld fail2ban)

# Enable sshd if installed
if systemctl list-unit-files | grep -q '^sshd.service'; then
    SERVICES+=(sshd)
fi

# Enable bluetooth if installed
if systemctl list-unit-files | grep -q '^bluetooth.service'; then
    SERVICES+=(bluetooth)
fi

# Enable cronie if installed
if systemctl list-unit-files | grep -q '^cronie.service'; then
    SERVICES+=(cronie)
fi

# Enable fstrim.timer if installed
if systemctl list-unit-files | grep -q '^fstrim.timer'; then
    SERVICES+=(fstrim.timer)
fi

# Enable power-profiles-daemon if installed
if systemctl list-unit-files | grep -q '^power-profiles-daemon.service'; then
    SERVICES+=(power-profiles-daemon)
fi

# Enable kdeconnectd if Plasma/KDE is detected and kdeconnectd is installed
if [ "$XDG_CURRENT_DESKTOP" ] && [[ "${XDG_CURRENT_DESKTOP,,}" == *kde* ]]; then
    if systemctl list-unit-files | grep -q '^kdeconnectd.service'; then
        SERVICES+=(kdeconnectd)
    fi
fi

for svc in "${SERVICES[@]}"; do
    sudo systemctl enable --now "$svc"
done
print_success "System services enabled and started."
