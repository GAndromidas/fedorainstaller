#!/bin/bash
# Hardware detection and driver installation
# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common.sh"

step "Hardware detection and driver installation"

CPU_VENDOR=$(detect_cpu_vendor)
GPU_VENDOR=$(detect_gpu_vendor)

print_info "Detected CPU vendor: ${CPU_VENDOR:-unknown}"
print_info "Detected GPU vendor: ${GPU_VENDOR:-none}"

# Install appropriate GPU drivers and utilities.
# RPM-Fusion REAL package names: nvidia-utils / nvidia-driver-cuda are Arch
# names and always failed here (batch failure + N per-package fallbacks).
# One merged transaction: GPU drivers + the general utils.
HARDWARE_PACKAGES=("lshw" "cpuid")

case "$GPU_VENDOR" in
    "nvidia")
        print_info "Installing NVIDIA drivers and utilities..."
        HARDWARE_PACKAGES+=(
            "akmod-nvidia"
            "xorg-x11-drv-nvidia"
            "xorg-x11-drv-nvidia-cuda"
            "xorg-x11-drv-nvidia-settings"
        )
        ;;
    "amd")
        print_info "Installing AMD drivers and utilities..."
        HARDWARE_PACKAGES+=(
            "mesa-vulkan-drivers"
            "vulkan-tools"
            "rocm-opencl-runtime"
        )
        ;;
    "intel")
        print_info "Installing Intel graphics drivers and utilities..."
        HARDWARE_PACKAGES+=(
            "mesa-vulkan-drivers"
            "vulkan-tools"
            "intel-media-driver"
        )
        ;;
    *)
        print_info "No dedicated GPU driver packages needed (vendor: ${GPU_VENDOR:-none})"
        ;;
esac

install_packages_batch "dnf" "${HARDWARE_PACKAGES[@]}"

print_success "Hardware detection and driver installation completed." 