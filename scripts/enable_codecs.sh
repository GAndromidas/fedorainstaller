#!/bin/bash
# Enable all major multimedia codecs from RPM Fusion
source "$(dirname "$0")/../common.sh"

step "Enabling multimedia codecs (RPM Fusion)"

# Ensure RPM Fusion repos are enabled (should already be handled, but double-check)
if ! sudo dnf repolist | grep -q rpmfusion-free; then
    print_info "Enabling RPM Fusion Free repository..."
    sudo dnf install -y https://download1.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm
fi
if ! sudo dnf repolist | grep -q rpmfusion-nonfree; then
    print_info "Enabling RPM Fusion Nonfree repository..."
    sudo dnf install -y https://download1.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
fi

# Update multimedia groups
print_info "Updating multimedia groups..."
sudo dnf groupupdate -y multimedia --setop="install_weak_deps=False" --exclude=PackageKit-gstreamer-plugin
sudo dnf groupupdate -y sound-and-video

# Install GStreamer plugins and codecs
print_info "Installing GStreamer plugins and codecs..."
sudo dnf install -y gstreamer1-plugins-{bad,good,ugly,base} gstreamer1-plugin-openh264 gstreamer1-libav --exclude=gstreamer1-plugins-bad-free-devel

# Install ffmpeg and lame
print_info "Installing ffmpeg and lame..."
sudo dnf install -y ffmpeg lame* --exclude=lame-devel

print_success "All major multimedia codecs are enabled and installed." 