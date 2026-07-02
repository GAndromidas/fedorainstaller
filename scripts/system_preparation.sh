#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

step "System Preparation"

# --- Configure DNF ---
DNF_CONF="/etc/dnf/dnf.conf"
print_info "Configuring DNF..."
sudo grep -q '^fastestmirror=True' "$DNF_CONF" || echo "fastestmirror=True" | sudo tee -a "$DNF_CONF"
sudo grep -q '^max_parallel_downloads=10' "$DNF_CONF" || echo "max_parallel_downloads=10" | sudo tee -a "$DNF_CONF"
sudo grep -q '^defaultyes=True' "$DNF_CONF" || echo "defaultyes=True" | sudo tee -a "$DNF_CONF"
sudo grep -q '^keepcache=False' "$DNF_CONF" || echo "keepcache=False" | sudo tee -a "$DNF_CONF"
print_success "DNF configuration updated successfully."

# --- Enable RPM Fusion ---
RELEASE=$(rpm -E %fedora)
if ! sudo $DNF_CMD repolist | grep -q rpmfusion-free; then
  print_info "Enabling RPM Fusion repositories..."
  sudo $DNF_CMD install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$RELEASE.noarch.rpm" \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$RELEASE.noarch.rpm"
fi

# --- Swap ffmpeg-free for full ffmpeg (game cutscenes fix) ---
print_info "Swapping ffmpeg-free for ffmpeg..."
sudo $DNF_CMD swap -y ffmpeg-free ffmpeg --allowerasing

# --- Install Helper Utilities ---
print_info "Installing helper utilities..."
install_packages_batch "dnf" "fastfetch" "btop" "inxi" "hwinfo" "lshw" "usbutils" "pciutils"

# --- Enable COPR Repos ---
if [ -f "$SCRIPT_DIR/../configs/programs.yaml" ]; then
  if command -v yq &>/dev/null; then
    COPR_REPOS=$(yq '.copr[] | .repo' "$SCRIPT_DIR/../configs/programs.yaml" 2>/dev/null)
    if [ -n "$COPR_REPOS" ]; then
      for repo in $COPR_REPOS; do
        print_info "Enabling COPR repo: $repo"
        sudo $DNF_CMD copr enable -y "$repo"
      done
    fi
  fi
fi

# --- Enable Flathub ---
if ! command -v flatpak &>/dev/null; then
  sudo $DNF_CMD install -y flatpak
fi
sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
print_success "Flathub repository added."

# --- Install GStreamer codecs ---
print_info "Installing multimedia codecs..."
if command -v "$DNF_CMD" >/dev/null 2>&1; then
  if $DNF_CMD --version 2>&1 | grep -q "5\."; then
    sudo $DNF_CMD group install -y multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin
    sudo $DNF_CMD group install -y sound-and-video
  else
    sudo $DNF_CMD groupupdate -y multimedia --setopt="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin
    sudo $DNF_CMD groupupdate -y sound-and-video
  fi
fi
install_packages_batch "dnf" \
  "gstreamer1-plugins-good" "gstreamer1-plugins-base" \
  "gstreamer1-plugin-openh264" "gstreamer1-plugin-libav" "lame-libs"

# --- System Update ---
print_info "Updating system packages..."
sudo $DNF_CMD upgrade --refresh -y

# --- CPU Microcode ---
local cpu_vendor=$(detect_cpu_vendor)
if [ "$cpu_vendor" = "intel" ]; then
  install_packages_batch "dnf" "microcode_ctl"
fi

# --- Kernel Headers ---
install_packages_batch "dnf" "kernel-devel" "kernel-headers"

print_success "System preparation complete."
