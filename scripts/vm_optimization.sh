#!/bin/bash
# VM/Cloud detection and optimization
source "$(dirname "$0")/../common.sh"

step "VM/Cloud detection and optimization"

# Detect virtualization environment
print_info "Detecting virtualization environment..."
VM_TYPE=""
VM_DETECTED=false

# Check for various VM indicators
if systemd-detect-virt --vm >/dev/null 2>&1; then
    VM_TYPE=$(systemd-detect-virt --vm)
    VM_DETECTED=true
    print_success "Virtual machine detected: $VM_TYPE"
elif systemd-detect-virt --container >/dev/null 2>&1; then
    VM_TYPE=$(systemd-detect-virt --container)
    VM_DETECTED=true
    print_success "Container detected: $VM_TYPE"
elif [ -f /sys/class/dmi/id/product_name ]; then
    PRODUCT_NAME=$(cat /sys/class/dmi/id/product_name)
    case "$PRODUCT_NAME" in
        *"VirtualBox"*) VM_TYPE="virtualbox"; VM_DETECTED=true ;;
        *"VMware"*) VM_TYPE="vmware"; VM_DETECTED=true ;;
        *"KVM"*) VM_TYPE="kvm"; VM_DETECTED=true ;;
        *"QEMU"*) VM_TYPE="qemu"; VM_DETECTED=true ;;
        *"Xen"*) VM_TYPE="xen"; VM_DETECTED=true ;;
        *"Microsoft"*) VM_TYPE="hyperv"; VM_DETECTED=true ;;
        *"Amazon"*) VM_TYPE="aws"; VM_DETECTED=true ;;
        *"Google"*) VM_TYPE="gcp"; VM_DETECTED=true ;;
        *"Azure"*) VM_TYPE="azure"; VM_DETECTED=true ;;
    esac
    if [ "$VM_DETECTED" = true ]; then
        print_success "Virtual machine detected: $VM_TYPE"
    fi
fi

if [ "$VM_DETECTED" = false ]; then
    print_info "No virtualization detected. Skipping VM optimizations."
    exit 0
fi

# Install appropriate guest tools based on VM type
case "$VM_TYPE" in
    "virtualbox")
        print_info "Installing VirtualBox Guest Additions..."
        VBOX_PACKAGES=(
            "virtualbox-guest-additions"
            "virtualbox-guest-additions-iso"
        )
        
        for package in "${VBOX_PACKAGES[@]}"; do
            if ! rpm -q "$package" >/dev/null 2>&1; then
                print_info "Installing $package..."
                if sudo $DNF_CMD install -y "$package"; then
                    print_success "$package installed successfully."
                    INSTALLED_PACKAGES+=("$package")
                else
                    print_error "Failed to install $package."
                fi
            else
                print_warning "$package is already installed. Skipping."
            fi
        done
        
        # Enable VirtualBox services
        VBOX_SERVICES=("vboxadd" "vboxadd-service" "vboxguest")
        for service in "${VBOX_SERVICES[@]}"; do
            if systemctl is-enabled "$service" >/dev/null 2>&1; then
                print_info "$service service is already enabled."
            else
                print_info "Enabling $service service..."
                if sudo systemctl enable "$service"; then
                    print_success "$service service enabled."
                else
                    print_error "Failed to enable $service service."
                fi
            fi
        done
        ;;
        
    "vmware")
        print_info "Installing VMware Tools..."
        if ! rpm -q open-vm-tools >/dev/null 2>&1; then
            if sudo $DNF_CMD install -y open-vm-tools; then
                print_success "VMware Tools installed successfully."
                INSTALLED_PACKAGES+=(open-vm-tools)
                
                # Enable VMware services
                if systemctl is-enabled vmtoolsd >/dev/null 2>&1; then
                    print_info "vmtoolsd service is already enabled."
                else
                    print_info "Enabling vmtoolsd service..."
                    if sudo systemctl enable vmtoolsd; then
                        print_success "vmtoolsd service enabled."
                    else
                        print_error "Failed to enable vmtoolsd service."
                    fi
                fi
            else
                print_error "Failed to install VMware Tools."
            fi
        else
            print_warning "VMware Tools are already installed. Skipping."
        fi
        ;;
        
    "kvm"|"qemu")
        print_info "Installing QEMU Guest Agent..."
        if ! rpm -q qemu-guest-agent >/dev/null 2>&1; then
            if sudo $DNF_CMD install -y qemu-guest-agent; then
                print_success "QEMU Guest Agent installed successfully."
                INSTALLED_PACKAGES+=(qemu-guest-agent)
                
                # Enable QEMU guest agent service
                if systemctl is-enabled qemu-guest-agent >/dev/null 2>&1; then
                    print_info "qemu-guest-agent service is already enabled."
                else
                    print_info "Enabling qemu-guest-agent service..."
                    if sudo systemctl enable qemu-guest-agent; then
                        print_success "qemu-guest-agent service enabled."
                    else
                        print_error "Failed to enable qemu-guest-agent service."
                    fi
                fi
            else
                print_error "Failed to install QEMU Guest Agent."
            fi
        else
            print_warning "QEMU Guest Agent is already installed. Skipping."
        fi
        ;;
        
    "hyperv")
        print_info "Installing Hyper-V integration services..."
        if ! rpm -q hyperv-daemons >/dev/null 2>&1; then
            if sudo $DNF_CMD install -y hyperv-daemons; then
                print_success "Hyper-V integration services installed successfully."
                INSTALLED_PACKAGES+=(hyperv-daemons)
                
                # Enable Hyper-V services
                HYPERV_SERVICES=("hypervfcopyd" "hypervkvpd" "hypervvssd")
                for service in "${HYPERV_SERVICES[@]}"; do
                    if systemctl is-enabled "$service" >/dev/null 2>&1; then
                        print_info "$service service is already enabled."
                    else
                        print_info "Enabling $service service..."
                        if sudo systemctl enable "$service"; then
                            print_success "$service service enabled."
                        else
                            print_error "Failed to enable $service service."
                        fi
                    fi
                done
            else
                print_error "Failed to install Hyper-V integration services."
            fi
        else
            print_warning "Hyper-V integration services are already installed. Skipping."
        fi
        ;;
        
    "aws"|"gcp"|"azure")
        print_info "Cloud environment detected: $VM_TYPE"
        
        # Install cloud-init if not present
        if ! command -v cloud-init >/dev/null; then
            print_info "Installing cloud-init..."
            if sudo $DNF_CMD install -y cloud-init; then
                print_success "cloud-init installed successfully."
                INSTALLED_PACKAGES+=(cloud-init)
            else
                print_error "Failed to install cloud-init."
            fi
        else
            print_warning "cloud-init is already installed. Skipping."
        fi
        
        # Install cloud-specific utilities
        case "$VM_TYPE" in
            "aws")
                print_info "Installing AWS utilities..."
                if ! command -v aws >/dev/null; then
                    if sudo $DNF_CMD install -y awscli; then
                        print_success "AWS CLI installed successfully."
                        INSTALLED_PACKAGES+=(awscli)
                    else
                        print_error "Failed to install AWS CLI."
                    fi
                else
                    print_warning "AWS CLI is already installed. Skipping."
                fi
                ;;
            "gcp")
                print_info "Installing Google Cloud utilities..."
                if ! command -v gcloud >/dev/null; then
                    if sudo $DNF_CMD install -y google-cloud-cli; then
                        print_success "Google Cloud CLI installed successfully."
                        INSTALLED_PACKAGES+=(google-cloud-cli)
                    else
                        print_error "Failed to install Google Cloud CLI."
                    fi
                else
                    print_warning "Google Cloud CLI is already installed. Skipping."
                fi
                ;;
            "azure")
                print_info "Installing Azure utilities..."
                if ! command -v az >/dev/null; then
                    if sudo $DNF_CMD install -y azure-cli; then
                        print_success "Azure CLI installed successfully."
                        INSTALLED_PACKAGES+=(azure-cli)
                    else
                        print_error "Failed to install Azure CLI."
                    fi
                else
                    print_warning "Azure CLI is already installed. Skipping."
                fi
                ;;
        esac
        ;;
esac

# Disable unnecessary services in VM environments
print_info "Optimizing services for VM environment..."
VM_SERVICES_TO_DISABLE=(
    "bluetooth"
    "cups"
    "avahi-daemon"
    "ModemManager"
    "NetworkManager-wait-online"
)

for service in "${VM_SERVICES_TO_DISABLE[@]}"; do
    if systemctl is-enabled "$service" >/dev/null 2>&1; then
        print_info "Disabling $service service for VM optimization..."
        if sudo systemctl disable "$service"; then
            print_success "$service service disabled."
        else
            print_error "Failed to disable $service service."
        fi
    else
        print_info "$service service is already disabled or not present."
    fi
done

# Optimize VM performance settings
print_info "Applying VM performance optimizations..."

# Disable transparent hugepages for better VM performance
if [ -f /sys/kernel/mm/transparent_hugepage/enabled ]; then
    if ! grep -q "\[never\]" /sys/kernel/mm/transparent_hugepage/enabled; then
        print_info "Disabling transparent hugepages for VM optimization..."
        echo never | sudo tee /sys/kernel/mm/transparent_hugepage/enabled >/dev/null
        echo never | sudo tee /sys/kernel/mm/transparent_hugepage/defrag >/dev/null
        print_success "Transparent hugepages disabled."
    else
        print_info "Transparent hugepages are already disabled."
    fi
fi

# Optimize I/O scheduler for VM
if [ -b /dev/sda ]; then
    print_info "Setting I/O scheduler to none for VM optimization..."
    echo none | sudo tee /sys/block/sda/queue/scheduler >/dev/null
    print_success "I/O scheduler set to none."
fi

print_success "VM/Cloud optimization completed." 