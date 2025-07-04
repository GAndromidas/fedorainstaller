#!/bin/bash
# Hardware detection and driver installation
source "$(dirname "$0")/../common.sh"

step "Hardware detection and driver installation"

# Detect CPU vendor
print_info "Detecting CPU vendor..."
CPU_VENDOR=""

# Debug: Show CPU information
print_info "CPU information from /proc/cpuinfo:"
grep -E "vendor_id|model name" /proc/cpuinfo | head -2

# Multiple detection methods for better accuracy
if grep -q "GenuineIntel" /proc/cpuinfo; then
    CPU_VENDOR="intel"
    print_success "Intel CPU detected via /proc/cpuinfo."
elif grep -q "AuthenticAMD" /proc/cpuinfo; then
    CPU_VENDOR="amd"
    print_success "AMD CPU detected via /proc/cpuinfo."
else
    # Try alternative detection methods
    print_info "Trying alternative CPU detection methods..."
    
    # Method 1: Check /sys/devices/system/cpu/cpu0/vendor
    if [ -f "/sys/devices/system/cpu/cpu0/vendor" ]; then
        CPU_VENDOR_SYS=$(cat /sys/devices/system/cpu/cpu0/vendor 2>/dev/null)
        print_info "CPU vendor from /sys: $CPU_VENDOR_SYS"
        
        if [[ "$CPU_VENDOR_SYS" == *"GenuineIntel"* ]]; then
            CPU_VENDOR="intel"
            print_success "Intel CPU detected via /sys."
        elif [[ "$CPU_VENDOR_SYS" == *"AuthenticAMD"* ]]; then
            CPU_VENDOR="amd"
            print_success "AMD CPU detected via /sys."
        fi
    fi
    
    # Method 2: Check dmidecode if available
    if [ -z "$CPU_VENDOR" ] && command -v dmidecode >/dev/null 2>&1; then
        print_info "Trying dmidecode for CPU detection..."
        CPU_VENDOR_DMI=$(sudo dmidecode -s processor-manufacturer 2>/dev/null | head -1)
        print_info "CPU manufacturer from dmidecode: $CPU_VENDOR_DMI"
        
        if [[ "$CPU_VENDOR_DMI" == *"Intel"* ]]; then
            CPU_VENDOR="intel"
            print_success "Intel CPU detected via dmidecode."
        elif [[ "$CPU_VENDOR_DMI" == *"AMD"* ]]; then
            CPU_VENDOR="amd"
            print_success "AMD CPU detected via dmidecode."
        fi
    fi
    
    # Method 3: Check lscpu if available
    if [ -z "$CPU_VENDOR" ] && command -v lscpu >/dev/null 2>&1; then
        print_info "Trying lscpu for CPU detection..."
        CPU_VENDOR_LSCPU=$(lscpu | grep "Vendor ID" | cut -d: -f2 | xargs)
        print_info "CPU vendor from lscpu: $CPU_VENDOR_LSCPU"
        
        if [[ "$CPU_VENDOR_LSCPU" == *"GenuineIntel"* ]]; then
            CPU_VENDOR="intel"
            print_success "Intel CPU detected via lscpu."
        elif [[ "$CPU_VENDOR_LSCPU" == *"AuthenticAMD"* ]]; then
            CPU_VENDOR="amd"
            print_success "AMD CPU detected via lscpu."
        fi
    fi
    
    # If still not detected, show warning
    if [ -z "$CPU_VENDOR" ]; then
        print_warning "Unknown CPU vendor detected. Showing all available CPU info:"
        echo "=== /proc/cpuinfo vendor_id ==="
        grep "vendor_id" /proc/cpuinfo | head -1
        echo "=== /proc/cpuinfo model name ==="
        grep "model name" /proc/cpuinfo | head -1
        if [ -f "/sys/devices/system/cpu/cpu0/vendor" ]; then
            echo "=== /sys/devices/system/cpu/cpu0/vendor ==="
            cat /sys/devices/system/cpu/cpu0/vendor
        fi
        if command -v lscpu >/dev/null 2>&1; then
            echo "=== lscpu output ==="
            lscpu | grep -E "Vendor ID|Model name"
        fi
    fi
fi

# Detect GPU vendor
print_info "Detecting GPU vendor..."
GPU_VENDOR=""

# Get all graphics devices
GRAPHICS_DEVICES=$(lspci | grep -i "vga\|3d\|display")

# Debug: Show what graphics devices were found
print_info "Found graphics devices:"
echo "$GRAPHICS_DEVICES"

# More sophisticated detection for systems with multiple GPUs
# Check for discrete graphics first (usually have more memory or are listed as 3D controllers)
DISCRETE_GPU=$(echo "$GRAPHICS_DEVICES" | grep -i "3d\|display" | head -1)
INTEGRATED_GPU=$(echo "$GRAPHICS_DEVICES" | grep -i "vga" | head -1)

# Prioritize discrete graphics over integrated
if [ -n "$DISCRETE_GPU" ]; then
    if echo "$DISCRETE_GPU" | grep -i "nvidia" >/dev/null; then
        GPU_VENDOR="nvidia"
        print_success "NVIDIA discrete GPU detected: $DISCRETE_GPU"
    elif echo "$DISCRETE_GPU" | grep -i "amd" >/dev/null; then
        GPU_VENDOR="amd"
        print_success "AMD discrete GPU detected: $DISCRETE_GPU"
    elif echo "$DISCRETE_GPU" | grep -i "intel" >/dev/null; then
        GPU_VENDOR="intel"
        print_success "Intel discrete GPU detected: $DISCRETE_GPU"
    fi
elif [ -n "$INTEGRATED_GPU" ]; then
    if echo "$INTEGRATED_GPU" | grep -i "nvidia" >/dev/null; then
        GPU_VENDOR="nvidia"
        print_success "NVIDIA integrated GPU detected: $INTEGRATED_GPU"
    elif echo "$INTEGRATED_GPU" | grep -i "amd" >/dev/null; then
        GPU_VENDOR="amd"
        print_success "AMD integrated GPU detected: $INTEGRATED_GPU"
    elif echo "$INTEGRATED_GPU" | grep -i "intel" >/dev/null; then
        GPU_VENDOR="intel"
        print_success "Intel integrated GPU detected: $INTEGRATED_GPU"
    fi
else
    # Fallback to simple detection
    if echo "$GRAPHICS_DEVICES" | grep -i "nvidia" >/dev/null; then
        GPU_VENDOR="nvidia"
        print_success "NVIDIA GPU detected."
    elif echo "$GRAPHICS_DEVICES" | grep -i "amd" >/dev/null; then
        GPU_VENDOR="amd"
        print_success "AMD GPU detected."
    elif echo "$GRAPHICS_DEVICES" | grep -i "intel" >/dev/null; then
        GPU_VENDOR="intel"
        print_success "Intel GPU detected."
    else
        print_warning "Unknown GPU vendor detected."
    fi
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
    "cpuid"
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

print_success "Hardware detection and driver installation completed." 