#!/bin/bash
# Enable all major multimedia codecs from RPM Fusion
source "$(dirname "$0")/../common.sh"

step "Enabling multimedia codecs (RPM Fusion)"

# Ensure RPM Fusion repos are enabled (should already be handled, but double-check)
if ! sudo $DNF_CMD repolist | grep -q rpmfusion-free; then
    print_info "Enabling RPM Fusion Free repository..."
    sudo $DNF_CMD install -y https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm
fi
if ! sudo $DNF_CMD repolist | grep -q rpmfusion-nonfree; then
    print_info "Enabling RPM Fusion Nonfree repository..."
    sudo $DNF_CMD install -y https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
fi

# Update multimedia groups (use dnf instead of dnf5 for group commands)
print_info "Updating multimedia groups..."
if command -v dnf >/dev/null 2>&1; then
    sudo dnf groupupdate -y multimedia --setop="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin
    sudo dnf groupupdate -y sound-and-video
else
    print_warning "dnf not available, skipping group updates"
fi

# Install GStreamer plugins and codecs
print_info "Installing GStreamer plugins and codecs..."
sudo $DNF_CMD install -y gstreamer1-plugins-good gstreamer1-plugins-base gstreamer1-plugin-openh264 gstreamer1-plugin-libav

# Install ffmpeg and lame
print_info "Installing ffmpeg and lame..."
sudo $DNF_CMD install -y ffmpeg lame-libs

print_success "All major multimedia codecs are enabled and installed." 