#!/bin/bash
# Hardware detection and driver installation
source "$(dirname "$0")/../common.sh"

step "Hardware detection and driver installation"

# Detect CPU vendor
print_info "Detecting CPU vendor..."
CPU_VENDOR=""
if grep -q "GenuineIntel" /proc/cpuinfo; then
    CPU_VENDOR="intel"
    print_success "Intel CPU detected."
elif grep -q "AuthenticAMD" /proc/cpuinfo; then
    CPU_VENDOR="amd"
    print_success "AMD CPU detected."
else
    print_warning "Unknown CPU vendor detected."
fi

# Install appropriate microcode
if [ "$CPU_VENDOR" = "intel" ]; then
    print_info "Installing Intel microcode..."
    if ! rpm -q intel-microcode >/dev/null 2>&1; then
        if sudo $DNF_CMD install -y intel-microcode; then
            print_success "Intel microcode installed successfully."
            INSTALLED_PACKAGES+=(intel-microcode)
        else
            print_error "Failed to install Intel microcode."
        fi
    else
        print_warning "Intel microcode is already installed. Skipping."
    fi
elif [ "$CPU_VENDOR" = "amd" ]; then
    print_info "Installing AMD microcode..."
    if ! rpm -q amd-microcode >/dev/null 2>&1; then
        if sudo $DNF_CMD install -y amd-microcode 2>/dev/null; then
            print_success "AMD microcode installed successfully."
            INSTALLED_PACKAGES+=(amd-microcode)
        else
            print_warning "AMD microcode package not available in repositories. Skipping."
        fi
    else
        print_warning "AMD microcode is already installed. Skipping."
    fi
fi

# Detect GPU vendor
print_info "Detecting GPU vendor..."
GPU_VENDOR=""
if lspci | grep -i "nvidia" >/dev/null; then
    GPU_VENDOR="nvidia"
    print_success "NVIDIA GPU detected."
elif lspci | grep -i "amd" >/dev/null; then
    GPU_VENDOR="amd"
    print_success "AMD GPU detected."
elif lspci | grep -i "intel" >/dev/null; then
    GPU_VENDOR="intel"
    print_success "Intel GPU detected."
else
    print_warning "Unknown GPU vendor detected."
fi

# Install appropriate GPU drivers and utilities
case "$GPU_VENDOR" in
    "nvidia")
        print_info "Installing NVIDIA drivers and utilities..."
        NVIDIA_PACKAGES=(
            "akmod-nvidia"
            "nvidia-settings"
            "nvidia-utils"
            "lib32-nvidia-utils"
        )
        
        for package in "${NVIDIA_PACKAGES[@]}"; do
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
        
        # Install additional NVIDIA utilities
        print_info "Installing additional NVIDIA utilities..."
        if ! command -v nvidia-smi >/dev/null; then
            if sudo $DNF_CMD install -y nvidia-driver-cuda; then
                print_success "NVIDIA CUDA drivers installed successfully."
                INSTALLED_PACKAGES+=(nvidia-driver-cuda)
            else
                print_error "Failed to install NVIDIA CUDA drivers."
            fi
        else
            print_warning "NVIDIA CUDA drivers are already installed. Skipping."
        fi
        ;;
        
    "amd")
        print_info "Installing AMD drivers and utilities..."
        AMD_PACKAGES=(
            "mesa-vulkan-drivers"
            "lib32-mesa-vulkan-drivers"
            "vulkan-tools"
            "rocm-opencl-runtime"
        )
        
        for package in "${AMD_PACKAGES[@]}"; do
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
        ;;
        
    "intel")
        print_info "Installing Intel graphics drivers and utilities..."
        INTEL_PACKAGES=(
            "mesa-vulkan-drivers"
            "vulkan-tools"
            "intel-media-driver"
        )
        
        for package in "${INTEL_PACKAGES[@]}"; do
            if ! rpm -q "$package" >/dev/null 2>&1; then
                print_info "Installing $package..."
                if sudo $DNF_CMD install -y "$package" 2>/dev/null; then
                    print_success "$package installed successfully."
                    INSTALLED_PACKAGES+=("$package")
                else
                    print_warning "Failed to install $package. Package may not be available."
                fi
            else
                print_warning "$package is already installed. Skipping."
            fi
        done
        
        # Try to install lib32-mesa-vulkan-drivers separately
        if ! rpm -q lib32-mesa-vulkan-drivers >/dev/null 2>&1; then
            print_info "Installing lib32-mesa-vulkan-drivers..."
            if sudo $DNF_CMD install -y lib32-mesa-vulkan-drivers 2>/dev/null; then
                print_success "lib32-mesa-vulkan-drivers installed successfully."
                INSTALLED_PACKAGES+=(lib32-mesa-vulkan-drivers)
            else
                print_warning "lib32-mesa-vulkan-drivers not available. Skipping."
            fi
        else
            print_warning "lib32-mesa-vulkan-drivers is already installed. Skipping."
        fi
        ;;
esac

# Install general hardware utilities
print_info "Installing general hardware utilities..."
HARDWARE_PACKAGES=(
    "lshw"
    "dmidecode"
    "cpuid"
    "lm_sensors"
)

for package in "${HARDWARE_PACKAGES[@]}"; do
    if ! command -v "$package" >/dev/null; then
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

# Configure lm_sensors if installed
if command -v sensors >/dev/null; then
    print_info "Configuring lm_sensors..."
    if [ ! -f /etc/sensors3.conf ]; then
        if sudo sensors-detect --auto; then
            print_success "lm_sensors configured successfully."
        else
            print_error "Failed to configure lm_sensors."
        fi
    else
        print_warning "lm_sensors is already configured. Skipping."
    fi
fi

# Install additional hardware monitoring tools
print_info "Installing hardware monitoring tools..."
MONITORING_PACKAGES=(
    "gwe"
)

for package in "${MONITORING_PACKAGES[@]}"; do
    if ! command -v "$package" >/dev/null; then
        print_info "Installing $package..."
        if sudo $DNF_CMD install -y "$package" 2>/dev/null; then
            print_success "$package installed successfully."
            INSTALLED_PACKAGES+=("$package")
        else
            print_warning "Failed to install $package. Package may not be available."
        fi
    else
        print_warning "$package is already installed. Skipping."
    fi
done

# Try to install psensor and hardinfo separately
for package in psensor hardinfo; do
    if ! command -v "$package" >/dev/null; then
        print_info "Installing $package..."
        if sudo $DNF_CMD install -y "$package" 2>/dev/null; then
            print_success "$package installed successfully."
            INSTALLED_PACKAGES+=("$package")
        else
            print_warning "Failed to install $package. Package may not be available."
        fi
    else
        print_warning "$package is already installed. Skipping."
    fi
done

print_success "Hardware detection and driver installation completed." 