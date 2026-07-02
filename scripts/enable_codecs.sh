#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

step "Enabling multimedia codecs (RPM Fusion)"

RELEASE=$(rpm -E %fedora)

if ! sudo $DNF_CMD repolist | grep -q rpmfusion-free; then
  print_info "Enabling RPM Fusion Free repository..."
  sudo $DNF_CMD install -y \
    "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$RELEASE.noarch.rpm"
fi
if ! sudo $DNF_CMD repolist | grep -q rpmfusion-nonfree; then
  print_info "Enabling RPM Fusion Nonfree repository..."
  sudo $DNF_CMD install -y \
    "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$RELEASE.noarch.rpm"
fi

# Swap ffmpeg-free → ffmpeg for codec support (game cutscenes fix)
print_info "Swapping ffmpeg-free for ffmpeg (game cutscenes fix)..."
sudo $DNF_CMD swap -y ffmpeg-free ffmpeg --allowerasing

# Update multimedia groups
print_info "Updating multimedia groups..."
if command -v dnf >/dev/null 2>&1; then
  sudo dnf groupupdate -y multimedia --setop="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin
  sudo dnf groupupdate -y sound-and-video
else
  print_warning "dnf not available, skipping group updates"
fi

# Install GStreamer plugins
print_info "Installing GStreamer plugins and codecs..."
CODEC_PACKAGES=(
  "gstreamer1-plugins-good"
  "gstreamer1-plugins-base"
  "gstreamer1-plugin-openh264"
  "gstreamer1-plugin-libav"
  "lame-libs"
)
install_packages_batch "dnf" "${CODEC_PACKAGES[@]}"

print_success "All major multimedia codecs are enabled and installed."
