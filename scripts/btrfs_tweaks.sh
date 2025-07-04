#!/bin/bash
# Btrfs detection and related tools installation
source "$(dirname "$0")/../common.sh"

step "Btrfs filesystem detection and tools"

# Detect if system is using Btrfs
print_info "Detecting filesystem type..."
if findmnt -n -o FSTYPE / | grep -q btrfs; then
    print_success "Btrfs filesystem detected!"
    
    # Check if timeshift is already installed
    if ! command -v timeshift >/dev/null; then
        print_info "Timeshift not found. Installing Timeshift for Btrfs snapshots..."
        if sudo $DNF_CMD install -y timeshift; then
            print_success "Timeshift installed successfully."
            INSTALLED_PACKAGES+=(timeshift)
        else
            print_error "Failed to install Timeshift."
        fi
    else
        print_warning "Timeshift is already installed. Skipping."
    fi
    
    # Check for btrfs-progs (should be installed by default, but let's make sure)
    if ! command -v btrfs >/dev/null; then
        print_info "Installing btrfs-progs..."
        if sudo $DNF_CMD install -y btrfs-progs; then
            print_success "btrfs-progs installed successfully."
            INSTALLED_PACKAGES+=(btrfs-progs)
        else
            print_error "Failed to install btrfs-progs."
        fi
    else
        print_info "btrfs-progs is already installed."
    fi
    
    # Offer to create initial Timeshift configuration
    if command -v timeshift >/dev/null && [ ! -f /etc/timeshift/timeshift.json ]; then
        echo -e "\n${YELLOW}═══════════════════════════════════════════════════════════════${RESET}"
        echo -e "${CYAN}📸 TIMESHIFT CONFIGURATION${RESET}"
        echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${RESET}"
        echo -e "${CYAN}Would you like to create initial Timeshift configuration?${RESET}"
        echo -e "${YELLOW}This will create your first system snapshot for backup purposes.${RESET}"
        echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${RESET}"
        read -r -p "Enter Y to create snapshot, or press Enter to skip: " response
        response="${response:-N}"  # Default to N if empty
        if [[ "$response" =~ ^[Yy]$ ]]; then
            print_info "Creating initial Timeshift configuration..."
            if sudo timeshift --create --comments "Initial snapshot"; then
                print_success "Initial Timeshift snapshot created successfully."
            else
                print_error "Failed to create initial Timeshift snapshot."
            fi
        else
            print_info "Timeshift configuration skipped. You can configure it manually later."
        fi
        echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${RESET}\n"
    fi
    
    print_success "Btrfs tools installation completed."
else
    print_info "Btrfs filesystem not detected. Skipping Btrfs-specific tools."
fi 