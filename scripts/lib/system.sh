#!/bin/bash
set -uo pipefail

# ============================================================================
# System library: hardware/distro detection with caching.
# Detection results are cached in SYSTEM_CACHE so repeated calls are cheap.
# ============================================================================

# Cache for detection results
declare -gA SYSTEM_CACHE=()

# Find systemd-boot entries directory by checking common ESP mount points
find_systemd_boot_entries_dir() {
  for dir in "/boot/loader/entries" "/efi/loader/entries" "/boot/efi/loader/entries"; do
    if sudo test -d "$dir" 2>/dev/null; then
      echo "$dir"
      return 0
    fi
  done
  return 1
}

# Detect CPU vendor
detect_cpu_vendor() {
    local cache_key="cpu_vendor"
    if [[ -n "${SYSTEM_CACHE[$cache_key]:-}" ]]; then
        echo "${SYSTEM_CACHE[$cache_key]}"
        return 0
    fi
    local vendor="unknown"
    if grep -qi "GenuineIntel" /proc/cpuinfo 2>/dev/null; then
        vendor="intel"
    elif grep -qi "AuthenticAMD" /proc/cpuinfo 2>/dev/null; then
        vendor="amd"
    fi
    SYSTEM_CACHE[$cache_key]="$vendor"
    echo "$vendor"
}

# Detect GPU vendor
detect_gpu_vendor() {
    local cache_key="gpu_vendor"
    if [[ -n "${SYSTEM_CACHE[$cache_key]:-}" ]]; then
        echo "${SYSTEM_CACHE[$cache_key]}"
        return 0
    fi
    local vendor=""
    local graphics_devices=$(lspci 2>/dev/null | grep -i "vga\|3d\|display" || true)
    if echo "$graphics_devices" | grep -qi "nvidia" >/dev/null; then
        vendor="nvidia"
    elif echo "$graphics_devices" | grep -qi "amd" >/dev/null; then
        vendor="amd"
    elif echo "$graphics_devices" | grep -qi "intel" >/dev/null; then
        vendor="intel"
    fi
    SYSTEM_CACHE[$cache_key]="$vendor"
    echo "$vendor"
}

# Detect if system is a laptop
is_laptop() {
    local cache_key="is_laptop"
    if [[ -n "${SYSTEM_CACHE[$cache_key]:-}" ]]; then
        [[ "${SYSTEM_CACHE[$cache_key]}" == "true" ]]
        return $?
    fi
    local is_laptop_val=false
    if [[ -d "/sys/class/power_supply" ]]; then
        while IFS= read -r supply; do
            if [[ "$supply" == *"BAT"* ]]; then
                is_laptop_val=true
                break
            fi
        done < <(ls /sys/class/power_supply 2>/dev/null)
    fi
    if command -v dmidecode &>/dev/null; then
        local chassis
        chassis=$(sudo dmidecode -s chassis-type 2>/dev/null | tr '[:upper:]' '[:lower:]')
        case "$chassis" in
            *laptop*|*notebook*|*portable*) is_laptop_val=true ;;
        esac
    fi
    # Fall back to the DMI product name for common laptop indicators
    if [ -f /sys/devices/virtual/dmi/id/product_name ]; then
        local product_name
        product_name=$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null | tr '[:upper:]' '[:lower:]')
        case "$product_name" in
            *laptop*|*notebook*|*book*|*ultrabook*|*macbook*|*thinkpad*|*latitude*|*precision*)
                is_laptop_val=true
                ;;
        esac
    fi
    SYSTEM_CACHE[$cache_key]="$is_laptop_val"
    [[ "$is_laptop_val" == "true" ]]
}

# Get RAM in GB
get_ram_gb() {
    local cache_key="ram_gb"
    if [[ -n "${SYSTEM_CACHE[$cache_key]:-}" ]]; then
        echo "${SYSTEM_CACHE[$cache_key]}"
        return 0
    fi
    local ram_kb
    ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    local ram_gb=$((ram_kb / 1024 / 1024))
    SYSTEM_CACHE[$cache_key]="$ram_gb"
    echo "$ram_gb"
}

# Detect bootloader
detect_bootloader() {
    local cache_key="bootloader"
    if [[ -n "${SYSTEM_CACHE[$cache_key]:-}" ]]; then
        echo "${SYSTEM_CACHE[$cache_key]}"
        return 0
    fi
    local bootloader="unknown"
    if sudo test -d /boot/grub 2>/dev/null || sudo test -d /boot/grub2 2>/dev/null || \
       [ -d "/boot/efi/EFI/grub" ] || [ -d "/efi/EFI/grub" ]; then
        bootloader="grub"
    elif sudo test -d /boot/loader/entries 2>/dev/null || [ -d "/efi/loader/entries" ] || \
         sudo test -f /boot/loader/loader.conf 2>/dev/null || [ -f "/efi/loader/loader.conf" ] || \
         [ -d "/boot/EFI/systemd" ] || [ -d "/efi/EFI/systemd" ] || \
         sudo test -d /boot/loader 2>/dev/null; then
        bootloader="systemd-boot"
    elif [ -f /boot/grub/grub.cfg ] || [ -f /boot/grub2/grub.cfg ]; then
        bootloader="grub"
    else
        bootloader="unknown"
    fi
    SYSTEM_CACHE[$cache_key]="$bootloader"
    echo "$bootloader"
}

# Check if system uses UKI (Unified Kernel Image)
is_uki_system() {
    local cache_key="is_uki"
    if [[ -n "${SYSTEM_CACHE[$cache_key]:-}" ]]; then
        [[ "${SYSTEM_CACHE[$cache_key]}" == "true" ]]
        return $?
    fi
    local result="false"
    if sudo test -d /boot/efi/EFI/Linux 2>/dev/null && sudo ls /boot/efi/EFI/Linux/*.efi >/dev/null 2>&1; then
        result="true"
    elif sudo test -d /boot/EFI/Linux 2>/dev/null && sudo ls /boot/EFI/Linux/*.efi >/dev/null 2>&1; then
        result="true"
    fi
    if [[ "$result" == "false" ]]; then
        local entries_dir
        entries_dir=$(find_systemd_boot_entries_dir)
        if [[ -n "$entries_dir" ]]; then
            while IFS= read -r -d '' entry; do
                if grep -qE "^\s*efi\s+/" "$entry" 2>/dev/null; then
                    result="true"
                    break
                fi
            done < <(find "$entries_dir" -name "*.conf" -print0 2>/dev/null)
        fi
    fi
    SYSTEM_CACHE[$cache_key]="$result"
    [[ "$result" == "true" ]]
}

# Check if system is headless
is_headless_system() {
    if systemctl is-active --quiet gdm 2>/dev/null || \
       systemctl is-active --quiet sddm 2>/dev/null || \
       systemctl is-active --quiet lightdm 2>/dev/null || \
       systemctl is-active --quiet lxdm 2>/dev/null || \
       systemctl is-active --quiet slim 2>/dev/null; then
        return 1
    fi
    if pgrep -x X >/dev/null 2>&1 || pgrep -x Xorg >/dev/null 2>&1; then
        return 1
    fi
    if pgrep -x weston >/dev/null 2>&1 || pgrep -x gnome-shell >/dev/null 2>&1; then
        return 1
    fi
    if [[ -n "${XDG_CURRENT_DESKTOP:-}" ]]; then
        return 1
    fi
    return 0
}

# Check if SSD
is_ssd() {
    if command -v lsblk &>/dev/null; then
        # Note: lsblk right-pads its numeric columns, so match whitespace-tolerant.
        if lsblk -d -o rota | grep -qE '^[[:space:]]*0[[:space:]]*$'; then
            return 0
        fi
    fi
    return 1
}

# Get installed kernel types
get_installed_kernel_types() {
    local kernel_types=()

    if rpm -q kernel >/dev/null 2>&1; then
        kernel_types+=("kernel")
    fi
    if rpm -q kernel-rt >/dev/null 2>&1; then
        kernel_types+=("kernel-rt")
    fi

    echo "${kernel_types[@]}"
}

# Check system compatibility for running the installer (Fedora, disk, network)
check_system_compatibility() {
    local issues=()

    # Check if running as root (should not be)
    if [[ $EUID -eq 0 ]]; then
        issues+=("Script should not be run as root")
    fi

    # Check if on Fedora
    if [[ ! -f /etc/fedora-release ]] && ! grep -q -i "fedora" /etc/os-release 2>/dev/null; then
        issues+=("Not running on Fedora Linux")
    fi

    # Check disk space (need at least 2GB)
    local available_space=$(df / | awk 'NR==2 {print $4}')
    if [[ $available_space -lt 2097152 ]]; then
        issues+=("Insufficient disk space (need 2GB, have $((available_space / 1024 / 1024))GB)")
    fi

    # Check internet connection
    if ! ping -c 1 -W 5 fedoraproject.org &>/dev/null; then
        issues+=("No internet connection")
    fi

    # Check bootloader compatibility
    if [ ! -d "/boot" ]; then
        issues+=("Boot directory not found")
    fi

    # Report issues
    if [ ${#issues[@]} -gt 0 ]; then
        log_error "System compatibility issues found:"
        for issue in "${issues[@]}"; do
            log_error "  - $issue"
        done
        return 1
    fi

    return 0
}

# Get system information summary
get_system_info() {
    local cpu=$(detect_cpu_vendor)
    local ram=$(get_ram_gb)
    local gpu=$(detect_gpu_vendor)
    local laptop
    is_laptop && laptop="Yes" || laptop="No"
    local bootloader=$(detect_bootloader)

    cat << EOF
CPU: $cpu
RAM: ${ram} GB
GPU: ${gpu:-none}
Laptop: $laptop
Bootloader: $bootloader
EOF
}
