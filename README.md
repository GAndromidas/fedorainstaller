# Fedorainstaller: Fedora Post-Installation Script

[![Latest Release](https://img.shields.io/github/v/release/GAndromidas/fedorainstaller.svg?style=for-the-badge)](https://github.com/GAndromidas/fedorainstaller/releases)
[![Total Downloads](https://img.shields.io/github/downloads/GAndromidas/fedorainstaller/total.svg?style=for-the-badge)](https://github.com/GAndromidas/fedorainstaller/releases)
[![Last Commit](https://img.shields.io/github/last-commit/GAndromidas/fedorainstaller.svg?style=for-the-badge)](https://github.com/GAndromidas/fedorainstaller/commits/main)

---

## Demo

![Screenshot_20250705_212646](https://github.com/user-attachments/assets/97d9fa08-1d63-403d-bed5-1b5429ad7783)

---

## 🚀 Overview

**Fedorainstaller** is a comprehensive, automated post-installation script for Fedora that transforms your fresh installation into a fully configured, optimized system. It handles everything from system preparation to desktop environment customization, gaming optimizations, security hardening, and robust dual-boot support.

### ✨ Key Features

- **Two Installation Modes**: Default (full setup) and Minimal (core utilities)
- **🖥️ Smart DE Detection**: Automatic detection and optimization for KDE, GNOME, Cosmic, and fallback support
- **🎮 Gaming Optimizations**: GameMode integration with GPU-specific optimizations
- **🎨 Security Hardening**: Fail2ban, Firewalld, and system service configuration
- **⚡ Performance Tuning**: System optimizations and hardware acceleration
- **📦 Multi-Source Packages**: DNF, RPM Fusion, and Flatpak integration
- **🎨 Beautiful UI**: Custom terminal interface with progress tracking and error handling
- **🧭 Dual Bootloader Support**: Automatically detects and configures both GRUB and systemd-boot
- **🪟 Windows Dual-Boot Automation**: Detects Windows installations, copies EFI files if needed, adds Windows to the boot menu for both GRUB and systemd-boot, and sets the hardware clock for compatibility
- **💾 NTFS Support**: Installs `ntfs-3g` automatically if Windows is detected, for seamless access to NTFS partitions

---

## 🧭 Bootloader & Windows Dual-Boot Support

- **Automatic Detection**: The installer detects whether your system uses GRUB or systemd-boot.
- **Configuration**: Sets kernel parameters, timeout, default entry, and console mode for the detected bootloader.
- **Windows Dual-Boot**: 
  - Detects Windows installations.
  - For systemd-boot: finds and copies Microsoft EFI files from the Windows EFI partition if needed, then creates a loader entry.
  - For GRUB: enables os-prober, ensures Windows is in the boot menu.
  - Sets the hardware clock to local time for compatibility.
- **NTFS Support**: Installs `ntfs-3g` for NTFS access and os-prober compatibility.

---

## 🛠️ Installation Modes

### 1. **Default Mode** 🎯
Complete setup with all recommended packages and optimizations:
- Full package suite (20+ DNF packages, 2+ Flatpak packages)
- Desktop environment-specific optimizations
- Gaming tools and optimizations
- Security hardening
- Performance tuning

### 2. **Minimal Mode** ⚡
Lightweight setup with essential utilities:
- Core system utilities (18 DNF packages, 1 Flatpak package)
- Basic desktop environment support
- Essential security features
- Minimal performance optimizations

---

## 🖥️ Desktop Environment Support

### **KDE Plasma** 
- **Install**: KDE-specific utilities and optimizations
- **Remove**: Conflicting packages (Akregator, Digikam, Dragon, Elisa, etc.)
- **Flatpaks**: GearLever

### **GNOME** 🟪
- **Install**: GNOME-specific utilities and extensions
- **Remove**: Conflicting packages (Epiphany, GNOME Contacts, GNOME Maps, etc.)
- **Flatpaks**: Extension Manager, GearLever

### **Cosmic** 🟨
- **Install**: Cosmic-specific utilities and tweaks
- **Remove**: Conflicting packages
- **Flatpaks**: GearLever, CosmicTweaks

### **Other DEs/WMs** 🔧
- Falls back to minimal package set
- Generic optimizations
- Basic Flatpak support

---

## 🎨 Package Categories

### **DNF Packages (Default Mode)**
- **Development**: `android-tools`
- **System Tools**: `btop`, `hwinfo`, `inxi`, `gnome-disk-utility`
- **Utilities**: `bat`, `eza`, `fzf`, `zoxide`, `fastfetch`
- **Gaming**: `gamemode`, `mangohud`
- **Media**: `vlc`, `cmatrix`, `sl`
- **System**: `bleachbit`, `unrar`, `unzip`, `figlet`
- **Networking**: `filezilla`, `python3-speedtest-cli`

### **Essential Packages (Default Mode)**
- **Productivity**: `vlc` (with codecs from RPM Fusion)
- **Gaming**: `steam`, `lutris`, `wine`
- **Media**: `vlc`
- **Utilities**: `filezilla`

### **Flatpak Applications (Default Mode)**
- **Media**: `com.stremio.Stremio`
- **Remote Access**: `com.rustdesk.RustDesk`

---

## 🔧 System Optimizations

### **Performance Enhancements**
- **DNF Optimization**: Fastest mirror selection and parallel downloads
- **Hardware Acceleration**: Automatic detection and configuration
- **Media Codecs**: RPM Fusion integration for enhanced media support
- **Kernel Headers**: Automatic installation for all installed kernels

### **Gaming Optimizations (GameMode)**
- **CPU Governor**: Performance mode during gaming
- **GPU Optimizations**: 
  - NVIDIA: PowerMizer performance mode
  - AMD: Performance DPM level
- **System Tweaks**: Lower swappiness, real-time priority
- **Desktop Integration**: KDE compositor suspension
- **VM Detection**: Minimal config for virtual machines

### **Security Hardening**
- **Fail2ban**: SSH protection with 30-minute bans, 3 retry limit
- **Firewalld**: Automatic configuration with SSH and KDE Connect support
- **System Services**: Automatic service enablement and configuration

---

## 🎨 User Experience

### **Shell Configuration**
- **ZSH**: Default shell with autosuggestions and syntax highlighting
- **Starship**: Beautiful, fast prompt with system information
- **Zoxide**: Smart directory navigation
- **Fastfetch**: System information display with custom configuration

### **Boot Experience**
- **Bootloader Support**: Automatic detection and configuration for both GRUB and systemd-boot
- **Splash Parameters**: Automatic kernel parameter configuration for both bootloaders
- **Windows Dual-Boot**: Detects Windows installations, copies EFI files if needed, adds Windows to the boot menu for both GRUB and systemd-boot, and sets the hardware clock to local time for compatibility
- **NTFS Support**: Installs `ntfs-3g` for NTFS access and os-prober compatibility

### **Terminal Interface**
- **Progress Tracking**: Real-time installation progress
- **Error Handling**: Comprehensive error collection and reporting
- **Color Coding**: Intuitive color-coded status messages
- **ASCII Art**: Beautiful Fedora branding

---

## 🚀 Quick Start

```bash
# Clone the repository
git clone https://github.com/gandromidas/fedorainstaller && cd fedorainstaller

# Make executable and run
chmod +x install.sh
./install.sh
```

### **Requirements**
- ✅ Fresh Fedora installation (recommended Fedora 40+)
- ✅ Regular user with sudo privileges (NOT root)
- ✅ Internet connection
- ✅ At least 2GB free disk space

### **Installation Process**

1. **System Setup**
   - Hostname configuration
   - System updates and repository configuration
   - RPM Fusion and Flathub integration

2. **Terminal Customization**
   - ZSH shell installation and configuration
   - Starship prompt setup
   - Nerd fonts installation

3. **Package Installation**
   - Core utilities and applications
   - Desktop environment-specific packages
   - Gaming tools and optimizations

4. **System Configuration**
   - Service enablement (SSH, Bluetooth, etc.)
   - Firewalld configuration
   - Bootloader configuration
   - Fastfetch setup

5. **Cleanup and Security**
   - Package cache cleanup
   - Fail2ban installation and configuration

---

## 🛠️ Customization

### **Package Lists**
Edit `configs/programs.yaml` to customize:
- DNF packages for default and minimal modes
- Flatpak applications
- Desktop environment-specific packages
- Package removal lists

### **Configuration Files**
- `configs/config.jsonc`: Main configuration options
- `configs/starship.toml`: Starship prompt configuration
- `scripts/`: Individual installation scripts for modular customization

### **Adding Custom Scripts**
1. Create your script in the `scripts/` directory
2. Add it to the `STEP_FUNCS` array in `install.sh`
3. Follow the existing script patterns for consistency

---

### **Log Files**
- Installation logs are saved to `/tmp/fedorainstaller.log`
- Check for specific error messages and package failures

---

## 🤝 Contributing

We welcome contributions! Please follow these guidelines:

1. **Fork** the repository
2. **Create** a feature branch (`git checkout -b feature/amazing-feature`)
3. **Commit** your changes (`git commit -m 'Add amazing feature'`)
4. **Push** to the branch (`git push origin feature/amazing-feature`)
5. **Open** a Pull Request

### **Code Style**
- Follow existing bash script patterns
- Add comments for complex logic
- Use consistent error handling
- Test on fresh Fedora installations

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 🤝 Acknowledgments

- **Fedora Project** for the excellent base system
- **RPM Fusion** for additional software repositories
- **Flatpak** for universal package distribution
- **Community contributors** for feedback and improvements

---

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/gandromidas/fedorainstaller/issues)
- **Discussions**: [GitHub Discussions](https://github.com/gandromidas/fedorainstaller/discussions)
- **Wiki**: [Documentation](https://github.com/gandromidas/fedorainstaller/wiki)

---

_Transform your Fedora installation into a powerful, optimized system with Fedorainstaller! 🚀_
