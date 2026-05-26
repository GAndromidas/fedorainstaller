<div align="center">

# Fedorainstaller

[![GitHub release](https://img.shields.io/github/release/GAndromidas/fedorainstaller.svg?style=for-the-badge&logo=github)](https://github.com/GAndromidas/fedorainstaller/releases)
[![Last Commit](https://img.shields.io/github/last-commit/GAndromidas/fedorainstaller.svg?style=for-the-badge&logo=git)](https://github.com/GAndromidas/fedorainstaller/commits/main)
[![License](https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge&logo=open-source-initiative)](LICENSE)
[![Fedora](https://img.shields.io/badge/Platform-Fedora-51A2DA?style=for-the-badge&logo=fedora)](https://fedoraproject.org/)
[![Stars](https://img.shields.io/github/stars/GAndromidas/fedorainstaller.svg?style=for-the-badge&logo=star)](https://github.com/GAndromidas/fedorainstaller/stargazers)

**Fedora Post-Installation Automation**

Transform your minimal Fedora installation into a fully configured, optimized system with intelligent hardware detection and tailored optimizations.

[Quick Start](#-quick-start) · [Features](#-key-features) · [Installation Modes](#-installation-modes) · [Configuration](#-customization)

</div>

---

## Overview

**Fedorainstaller** is a sophisticated post-installation automation tool that intelligently configures Fedora based on your hardware. It applies targeted optimizations rather than one-size-fits-all settings, ensuring optimal performance for your specific configuration.

### Core Philosophy

| Philosophy | Description |
|------------|-------------|
| **Hardware-Aware** | Detects CPU, GPU, storage, and desktop environment for tailored optimizations |
| **Security-First** | Comprehensive hardening enabled by default with firewall and fail2ban |
| **Performance-Optimized** | Intelligent I/O scheduling and kernel tuning for optimal responsiveness |
| **Reliable** | Resume functionality for interrupted installations with progress tracking |

---

## Key Features

### System Intelligence & Automation

#### Hardware Detection
```yaml
CPU Detection:
  Intel: microcode_ctl + microcode updates
  AMD: microcode_ctl + microcode updates
  
GPU Detection:
  NVIDIA: akmod-nvidia + CUDA support
  AMD: mesa-vulkan-drivers + Vulkan
  Intel: mesa-vulkan-drivers + VA-API
  
Storage Optimization:
  NVMe: BFQ scheduler + trim optimizations
  SSD: Deadline scheduler + wear leveling
  HDD: CFQ scheduler + readahead settings
  
Laptop Features:
  Manufacturer-specific optimizations
  Power management + thermal throttling
  Battery optimization + suspend/resume
```

#### Bootloader Detection & Configuration
| Bootloader | Features | Integration |
|------------|----------|-------------|
| **GRUB2** | Timeout optimization, boot menu management | Automatic configuration |
| **systemd-boot** | EFI support, kernel fallback | Automatic entry management |

#### Advanced Performance Optimization

- **Smart Memory Management**: Dynamic swappiness based on system RAM (1-3GB: 10, 4-7GB: 10, 8-15GB: 5, 16GB+: 1)
- **Intelligent Storage Optimization**: Automatic I/O scheduler detection (NVMe: none, SSD: deadline, HDD: mq-deadline)
- **Advanced Kernel Tuning**: Process scheduling, network stack optimization, filesystem-specific tuning
- **Hardware-Aware Configuration**: NVMe detection, virtualization awareness
- **Persistent Settings**: All optimizations survive reboots via sysctl and systemd services

#### Performance Optimization
- **I/O Scheduling**: Automatic selection based on storage type
- **Kernel Tuning**: `vm.swappiness=10`, `fs.inotify.max_user_watches=524288`
- **Parallel Downloads**: DNF parallel package fetching
- **Memory Management**: Swap optimization

#### Desktop Environment Integration
| Environment | Optimizations | Features |
|-------------|---------------|----------|
| **KDE Plasma** | Qt6-based shortcuts, fullscreen automation | kglobalshortcutsrc + Konsole fullscreen |
| **GNOME** | Latest dark theme, modern tweaks | dconf settings + current extensions |
| **Cosmic** | Latest alpha builds support | Experimental DE integration |

### Security & Stability

#### Security Hardening (Enabled by Default)
```bash
# Firewall Configuration
Firewalld:
  - Secure-by-default policies
  - Deny incoming, allow outgoing
  - SSH automatically allowed
  - Service-aware port management

# SSH Protection
Fail2ban:
  - Strict SSH policies
  - 15-minute ban on suspicious activity
  - Automatic brute-force detection
  - Customizable ban thresholds

# User Security
Sudo:
  - Password feedback enabled
  - Proper user group membership
  - Hardware access permissions
```

### Gaming Mode (Optional)

Transform your system into a gaming powerhouse with one click:

| Component | Description |
|-----------|-------------|
| **Steam** | Native gaming platform with Proton |
| **Heroic Games Launcher** | Epic Games + GOG support |
| **Faugus Launcher** | Game management and launcher |
| **MangoHud** | Performance overlay and monitoring |
| **GameMode** | Automatic performance tuning |
| **Wine** | Windows compatibility layer |

### Smart Peripheral Detection

Automatically detects connected peripherals and installs appropriate management software:

| Peripheral | Detection | Software |
|------------|------------|----------|
| **Logitech Devices** | USB vendor ID | Solaar (Unifying Receiver) |
| **Keychron Keyboards** | Device name | VIA-bin (keyboard configuration) |
| **Razer Devices** | Vendor ID | OpenRazer (COPR) |
| **Generic HID** | USB/HID tree | hidapi + udev rules |

### Wake-on-LAN Configuration

Intelligent Wake-on-LAN setup for desktop systems with multi-adapter support:

| Feature | Detection | Configuration |
|---------|------------|-------------|
| **Laptop Detection** | Battery + DMI chassis | Auto-skip WoL on laptops |
| **Multi-Adapter Support** | All ethernet interfaces | Smart selection menu |
| **Internet Testing** | Ping + route checking | Prioritizes active connection |
| **Persistent Services** | systemd integration | Survives reboots automatically |
| **MAC Display** | Interface enumeration | Easy remote wake-up setup |

---

## Installation Modes

Choose the perfect setup for your use case:

| Mode | Use Case | Requirements |
|------|-------------|-------------|
| **Default** | Full-featured desktop | General users, enthusiasts |
| **Minimal** | Lightweight essentials | Low-spec hardware, minimal bloat |
| **Server** | Headless configuration | Docker, SSH, server utilities |
| **Custom** | Interactive selection | Power users, specific requirements |

---

## Quick Start

### Prerequisites

- Fresh Fedora installation (minimal base system)
- Active internet connection
- User account with sudo privileges
- 2GB+ free disk space

### Installation

```bash
# Clone and run
git clone https://github.com/GAndromidas/fedorainstaller.git
cd fedorainstaller
./install.sh
```

**One-Click Setup:** The installer handles everything automatically - just select your preferred mode and let it configure your system.

### Command-Line Options

```bash
./install.sh [OPTIONS]

OPTIONS:
  --resume    Resume from last interrupted installation
  --dry-run   Preview changes only
  --step NAME Run only a specific step
  --help      Show help message
```

---

## Customization

### Package Management

All packages are organized in `configs/programs.yaml` with logical groupings:

```yaml
# Package Structure
dnf:              # Core packages (all modes)
default:           # Mode-specific packages
desktop_environments:  # DE-specific packages
flatpak:           # Flatpak applications
copr:              # COPR repositories
```

**Easy Customization:**

1. Open `configs/programs.yaml`
2. Add/remove packages from relevant sections
3. No script modification needed
4. Run installer - custom packages installed automatically

### Configuration Files

| File | Purpose |
|------|---------|
| `.zshrc` | Zsh shell configuration |
| `starship.toml` | Starship prompt theme |
| `config.jsonc` | Fastfetch system info |
| `gaming_mode.yaml` | Gaming package definitions |

---

## What Gets Installed

### Common Across All Modes

- System utilities and tools
- Development essentials
- Zsh shell with Oh-My-Zsh
- Starship terminal prompt
- System monitoring tools

### Mode-Specific Packages
| Mode | Desktop | Applications | Tools |
|------|-------------|-------------|------|
| **Default** | Full DE (KDE/GNOME/Cosmic) | Multimedia, Office, IDEs | Performance monitoring |
| **Minimal** | Lightweight DE | Essential apps only | Basic utilities |
| **Server** | No DE | Docker, Docker Compose | Server utilities |

### Installation Steps

The installer includes comprehensive steps for complete system setup:

| Step | Description | Mode Coverage |
|------|-------------|---------------|
| **1. System Setup** | Hostname, system updates, repos | All modes |
| **2. Terminal Customization** | Zsh + Oh-My-Zsh + Starship | All modes |
| **3. Programs Installation** | Mode-specific applications | All modes |
| **4. Codecs & Gaming** | Multimedia codecs, gaming tools | Default/Custom |
| **5. Hardware Detection** | GPU drivers, hardware utilities | All modes |
| **6. System Services** | Service optimization | All modes |
| **7. Bootloader Configuration** | GRUB2/systemd-boot setup | All modes |
| **8. Peripheral Detection** | Auto-configure peripherals | Default/Custom |
| **9. Wake-on-LAN Configuration** | Multi-adapter WoL setup | Desktop systems |
| **10. Maintenance** | Final cleanup and optimization | All modes |
| **11. Security** | Fail2ban setup | All modes |

---

## Security Features

### Enabled by Default
```bash

| Feature | Status | Configuration |
|---------|--------|---------------|
| **Firewall** | Active | Firewalld with secure policies |
| **SSH Protection** | Active | Fail2ban with strict policies |
| **Wake-on-LAN** | Desktop Only | Multi-adapter with smart selection |
| **User Groups** | Active | Proper permissions configured |
| **Bootloader** | Active | Security-hardened configuration |

---

## Supported Platforms

### Hardware Support

| Component | Support | Notes |
|-----------|---------|-------|
| **CPU** | Intel, AMD | Microcode + optimizations |
| **GPU** | NVIDIA, AMD, Intel | Driver auto-detection |
| **Storage** | NVMe, SSD, HDD | I/O scheduler optimization |
| **Form Factor** | Desktop, Laptop, VM | Power management + thermal |

### Bootloader Support

- **GRUB2** with timeout optimization
- **systemd-boot** with kernel fallback

### Desktop Environments

- **KDE Plasma** (Qt6-based)
- **GNOME** (latest stable)
- **Cosmic** (experimental, latest builds)

---

## Laptop Optimizations

### Intelligent Laptop Detection & Optimization

Fedorainstaller provides **manufacturer-specific optimizations** for laptop brands with automatic detection and tailored configuration.

#### Supported Manufacturers

| Brand | Special Features |
|-------|-----------------|
| **Lenovo** | thinkpad_acpi, power management |
| **HP** | hp-wmi, elitebook support |
| **Dell** | dell-wmi, dell-xps-firmware |
| **Acer** | acer-wmi, swift support |
| **ASUS** | asus-wmi, zenbook support |
| **MSI** | msi-wmi, msi-ec |
| **LG** | lg-specific power management |
| **Samsung** | samsung-specific optimizations |
| **Framework** | framework-specific features |

#### Automatic Features

**Power Management:**
- power-profiles-daemon
- Automatic power mode switching
- Battery vs AC power optimization

**CPU-Specific Optimizations:**
- Intel: thermald for thermal management
- AMD: CPU frequency scaling
- CPU frequency scaling

**System Integration:**
- ACPI daemon for hardware events
- Battery monitoring and management
- Suspend/resume functionality

---

## Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| **Installation Interrupted** | Resume from `~/.fedorainstaller.state` |
| **No Internet Connection** | Check `ping fedoraproject.org` |
| **Insufficient Disk Space** | Minimum 2GB free required |
| **Package Installation Failures** | Check `~/fedorainstaller/install.log` |

### Log Files

```bash
~/fedorainstaller/install.log     # Complete installation log
~/.fedorainstaller.state          # Progress tracking
```

---

## Contributing

### How to Contribute

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

### Contribution Types

- **Report bugs**: Open an issue with details
- **Suggest features**: Describe your use case
- **Improve code**: Submit a pull request
- **Update documentation**: Help others understand the project

---

## Project Status

| Component | Status |
|-----------|--------|
| **Core Functionality** | Production Ready |
| **Hardware Detection** | Stable |
| **Advanced Optimizations** | ✅ Implemented |
| **Gaming Mode** | Tested |
| **Security Hardening** | Active |
| **Documentation** | Complete |

---

## License

This project is licensed under the **MIT License** - see the [LICENSE](LICENSE) file for details.

You are free to use, modify, and distribute this software for personal or commercial purposes.

---

## Acknowledgments

- Inspired by Arch Linux philosophy: simplicity and user control
- Built with community best practices and feedback
- Thanks to all contributors and users

---

## Support & Contact

| Platform | Link |
|----------|------|
| **Issues** | [GitHub Issues](https://github.com/GAndromidas/fedorainstaller/issues) |
| **Discussions** | [GitHub Discussions](https://github.com/GAndromidas/fedorainstaller/discussions) |
| **Repository** | [github.com/GAndromidas/fedorainstaller](https://github.com/GAndromidas/fedorainstaller) |

---

<div align="center">

## Made with love for the Fedora community

If you find this useful, please consider starring the repository!

[![Star](https://img.shields.io/github/stars/GAndromidas/fedorainstaller.svg?style=social&logo=github)](https://github.com/GAndromidas/fedorainstaller/stargazers)

</div>
