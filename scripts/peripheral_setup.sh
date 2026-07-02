#!/bin/bash
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

step "Peripheral Setup"

# Skip everything on laptops
if is_laptop; then
  ui_info "Laptop detected — skipping peripheral setup"
  exit 0
fi

# ──────────────────────────────────────────────
# Peripheral Detection
# ──────────────────────────────────────────────

detect_logitech_devices() {
  if ! command -v lsusb &>/dev/null; then return; fi
  local logitech_devices=$(lsusb | grep -i logitech)
  if [ -z "$logitech_devices" ]; then
    ui_info "No Logitech devices detected"
    return
  fi
  ui_success "Logitech devices detected"
  if install_packages_batch "dnf" "solaar"; then
    if systemctl list-unit-files | grep -q "^solaar.service"; then
      sudo systemctl enable --now solaar >/dev/null 2>&1
    fi
  fi
}

detect_keychron_devices() {
  if ! command -v lsusb &>/dev/null; then return; fi
  local keychron_devices=$(lsusb | grep -i keychron)
  if [ -n "$keychron_devices" ]; then
    ui_success "Keychron devices detected"
  fi
}

detect_razer_devices() {
  if ! command -v lsusb &>/dev/null; then return; fi
  local razer_devices=$(lsusb | grep -i razer)
  if [ -n "$razer_devices" ]; then
    ui_success "Razer devices detected"
  fi
}

detect_bluetooth_devices() {
  if ! command -v bluetoothctl &>/dev/null; then return; fi
  if ! systemctl is-active bluetooth &>/dev/null; then
    sudo systemctl start bluetooth >/dev/null 2>&1
  fi
  local paired_devices=$(bluetoothctl paired-devices 2>/dev/null || echo "")
  if [ -n "$paired_devices" ]; then
    ui_success "Bluetooth paired devices found"
  fi
}

detect_logitech_devices
detect_keychron_devices
detect_razer_devices
detect_bluetooth_devices

# ──────────────────────────────────────────────
# Wake-on-LAN Configuration
# ──────────────────────────────────────────────

test_interface_connectivity() {
  local iface="$1"
  local timeout=5
  if ! ip link show "$iface" | grep -q "state UP"; then
    ip link set "$iface" up 2>/dev/null || return 1
  fi
  timeout "$timeout" ping -c 1 -I "$iface" -W 2 8.8.8.8 >/dev/null 2>&1
}

configure_wakeonlan() {
  local interfaces=()
  for iface in /sys/class/net/*; do
    local name=$(basename "$iface")
    [[ "$name" == "lo" ]] && continue
    [ -d "/sys/class/net/$name/device" ] || continue
    local operstate=$(cat "/sys/class/net/$name/operstate" 2>/dev/null || echo "unknown")
    local carrier=$(cat "/sys/class/net/$name/carrier" 2>/dev/null || echo "0")

    local wol_capable="no"
    if [ -f "/sys/class/net/$name/device/power/wakeup" ]; then
      local wakeup=$(cat "/sys/class/net/$name/device/power/wakeup" 2>/dev/null || echo "disabled")
      [ "$wakeup" = "enabled" ] && wol_capable="yes"
    fi
    if ethtool "$name" 2>/dev/null | grep -q "Wake-on"; then
      ethtool "$name" 2>/dev/null | grep -q "Supports Wake-on.*g" && wol_capable="yes"
    fi

    if [ "$wol_capable" = "yes" ]; then
      interfaces+=("$name ($carrier, $operstate)")
    fi
  done

  [ ${#interfaces[@]} -eq 0 ] && { ui_info "No WoL-capable interfaces found"; return; }

  ui_info "WoL-capable interfaces: ${interfaces[*]}"

  local selection=""
  for iface_entry in "${interfaces[@]}"; do
    local iface_name="${iface_entry%% *}"
    if test_interface_connectivity "$iface_name"; then
      selection="$iface_name"
      break
    fi
  done

  if [ -z "$selection" ]; then
    selection="${interfaces[0]%% *}"
  fi

  if ethtool "$selection" 2>/dev/null | grep -q "Wake-on.*g"; then
    sudo ethtool -s "$selection" wol g 2>/dev/null
    ui_success "Wake-on-LAN enabled on $selection"

    local mac_addr=$(cat "/sys/class/net/$selection/address" 2>/dev/null || echo "unknown")
    ui_info "MAC address for $selection: $mac_addr"

    # systemd service for persistent WoL
    local svc="wol@$selection.service"
    if ! systemctl list-unit-files 2>/dev/null | grep -q "$svc"; then
      sudo tee "/etc/systemd/system/wol@.service" >/dev/null <<'EOF'
[Unit]
Description=Wake-on-LAN for %I
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/sbin/ethtool -s %I wol g
RemainAfterExit=yes

[Install]
WantedBy=basic.target
EOF
      sudo systemctl enable "wol@$selection" 2>/dev/null
      sudo systemctl start "wol@$selection" 2>/dev/null
    fi
  else
    ui_warn "Interface $selection does not support Wake-on-LAN"
  fi
}

configure_wakeonlan
ui_success "Peripheral setup complete."
