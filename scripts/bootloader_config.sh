#!/bin/bash
# Configure GRUB2 for dual-boot with Windows (UEFI or BIOS)
source "$(dirname "$0")/../common.sh"

step "Configure GRUB2 for dual-boot"

# 1. Detect Windows installation (look for Windows EFI or NTFS partitions)
print_info "Detecting Windows installation..."
WINDOWS_FOUND=0
if lsblk -f | grep -qi ntfs; then
    WINDOWS_FOUND=1
elif [ -d /boot/efi/EFI/Microsoft ]; then
    WINDOWS_FOUND=1
fi

if [ $WINDOWS_FOUND -eq 1 ]; then
    print_success "Windows installation detected. Configuring dual-boot..."

    # 2. Ensure ntfs-3g is installed
    if ! rpm -q ntfs-3g &>/dev/null; then
        print_info "Installing ntfs-3g for NTFS support..."
        sudo $DNF_CMD install -y ntfs-3g && print_success "ntfs-3g installed." || print_error "Failed to install ntfs-3g."
    else
        print_warning "ntfs-3g already installed. Skipping."
    fi

    # 3. Ensure os-prober is installed
    if ! rpm -q os-prober &>/dev/null; then
        print_info "Installing os-prober..."
        sudo $DNF_CMD install -y os-prober && print_success "os-prober installed." || print_error "Failed to install os-prober."
    else
        print_warning "os-prober already installed. Skipping."
    fi

    # 4. Enable os-prober in GRUB config
    GRUB_DEFAULTS=(/etc/default/grub /etc/sysconfig/grub)
    for grub_file in "${GRUB_DEFAULTS[@]}"; do
        if [ -f "$grub_file" ]; then
            if grep -q '^GRUB_DISABLE_OS_PROBER=true' "$grub_file"; then
                sudo sed -i 's/^GRUB_DISABLE_OS_PROBER=true/GRUB_DISABLE_OS_PROBER=false/' "$grub_file"
                print_success "Set GRUB_DISABLE_OS_PROBER=false in $grub_file"
            elif ! grep -q '^GRUB_DISABLE_OS_PROBER=' "$grub_file"; then
                echo 'GRUB_DISABLE_OS_PROBER=false' | sudo tee -a "$grub_file"
                print_success "Added GRUB_DISABLE_OS_PROBER=false to $grub_file"
            else
                print_warning "GRUB_DISABLE_OS_PROBER already set to false in $grub_file. Skipping."
            fi
        fi
    done

    # 5. Regenerate GRUB2 config (UEFI or BIOS)
    print_info "Regenerating GRUB2 configuration..."
    if [ -d /sys/firmware/efi ]; then
        # UEFI system
        sudo grub2-mkconfig -o /boot/efi/EFI/fedora/grub.cfg && print_success "GRUB2 config regenerated (UEFI)." || print_error "Failed to regenerate GRUB2 config (UEFI)."
        sudo grub2-mkconfig -o /boot/grub2/grub.cfg
    else
        # BIOS system
        sudo grub2-mkconfig -o /boot/grub2/grub.cfg && print_success "GRUB2 config regenerated (BIOS)." || print_error "Failed to regenerate GRUB2 config (BIOS)."
    fi

    print_success "Dual-boot configuration complete. Windows should now appear in the GRUB menu."
else
    print_warning "No Windows installation detected. Skipping dual-boot configuration."
fi 