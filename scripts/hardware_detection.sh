#!/bin/bash
# Hardware detection and driver installation
# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

step "Hardware detection and driver installation"

CPU_VENDOR=$(detect_cpu_vendor)
GPU_VENDOR=$(detect_gpu_vendor)

print_info "Detected CPU vendor: ${CPU_VENDOR:-unknown}"
print_info "Detected GPU vendor: ${GPU_VENDOR:-none}"

# Install appropriate GPU drivers and utilities
case "$GPU_VENDOR" in
    "nvidia")
        print_info "Installing NVIDIA drivers and utilities..."
        NVIDIA_PACKAGES=(
            "akmod-nvidia"
            "nvidia-settings"
            "nvidia-utils"
            "nvidia-driver-cuda"
        )
        
        # Use unified batch installation for all NVIDIA packages
        install_packages_batch "dnf" "${NVIDIA_PACKAGES[@]}"
        ;;
        
    "amd")
        print_info "Installing AMD drivers and utilities..."
        AMD_PACKAGES=(
            "mesa-vulkan-drivers"
            "vulkan-tools"
            "rocm-opencl-runtime"
        )
        
        # Use unified batch installation for all AMD packages
        install_packages_batch "dnf" "${AMD_PACKAGES[@]}"
        ;;
        
    "intel")
        print_info "Installing Intel graphics drivers and utilities..."
        INTEL_PACKAGES=(
            "mesa-vulkan-drivers"
            "vulkan-tools"
            "intel-media-driver"
        )
        
        # Use unified batch installation for all Intel packages
        install_packages_batch "dnf" "${INTEL_PACKAGES[@]}"
        ;;
esac

# Install general hardware utilities
print_info "Installing general hardware utilities..."
install_packages_batch "dnf" "lshw" "cpuid"

print_success "Hardware detection and driver installation completed." 