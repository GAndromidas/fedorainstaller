#!/bin/bash
# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../common.sh"
# Clean up unused packages and cache
step "Clean up unused packages and cache"
print_info "Removing unused packages and cleaning cache..."
sudo $DNF_CMD autoremove -y
sudo $DNF_CMD clean all
if command -v flatpak &>/dev/null; then
    print_info "Removing unused Flatpak runtimes..."
    flatpak uninstall --unused -y
fi
print_success "Unused packages and Flatpak runtimes removed, cache cleaned."
