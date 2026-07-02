<div align="center">

# Fedorainstaller

[![GitHub release](https://img.shields.io/github/release/GAndromidas/fedorainstaller.svg?style=for-the-badge&logo=github)](https://github.com/GAndromidas/fedorainstaller/releases)
[![Last Commit](https://img.shields.io/github/last-commit/GAndromidas/fedorainstaller.svg?style=for-the-badge&logo=git)](https://github.com/GAndromidas/fedorainstaller/commits/main)
[![License](https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge&logo=open-source-initiative)](LICENSE)
[![Fedora](https://img.shields.io/badge/Platform-Fedora-51A2DA?style=for-the-badge&logo=fedora)](https://fedoraproject.org/)

Just another guided/automated Fedora post-installation setup tool with a twist.
The installer doubles as a bash library to configure Fedora systems, manage packages, and set up services — from a fresh install or an existing system.

</div>

# Installation & Usage

```shell
git clone https://github.com/GAndromidas/fedorainstaller.git
cd fedorainstaller
./install.sh
```

The installer will detect your hardware, ask you which installation mode you want, and take care of the rest.

### Running with options

```shell
./install.sh [OPTIONS]

OPTIONS:
  -h, --help      Show help message
  -v, --verbose   Enable verbose output
  -q, --quiet     Quiet mode (minimal output)
  -d, --dry-run   Preview changes without making them
```

### Installation modes

| Mode | Description |
|------|-------------|
| **Standard** | Complete setup with all packages |
| **Minimal** | Essential tools only |
| **Server** | Headless configuration (Docker, SSH, server utilities) |

# What it does

Fedorainstaller runs a series of steps to transform a fresh Fedora system:

1. **System Update & Repos** — Configures DNF, enables RPM Fusion, Flathub, installs CPU microcode and kernel headers
2. **Terminal Customization** — Installs Zsh, Oh-My-Zsh, plugins, and Starship prompt
3. **Programs** — Installs packages for your chosen mode (DNF + Flatpak)
4. **Codecs** — Enables multimedia codecs via RPM Fusion, swaps ffmpeg-free for full ffmpeg
5. **Gaming Tweaks** — Optional: Steam, MangoHud, GameMode, Heroic Launcher, Discord
6. **Hardware Detection** — Detects CPU/GPU vendor, installs appropriate drivers
7. **System Services** — Configures firewalld, user groups, power management, GPU drivers, RAM tuning
8. **Bootloader** — Configures GRUB or systemd-boot
9. **Peripheral Detection** — Detects Logitech/Keychron/Razer devices, installs management tools
10. **Wake-on-LAN** — Configures WoL on ethernet interfaces (desktops only)
11. **Maintenance** — Cleans up, removes unused packages
12. **Fail2ban** — Installs and configures SSH brute-force protection

# Help or Issues

If you come across any issues, kindly submit your issue here on GitHub.

When submitting an issue, please attach the contents of `~/.fedorainstaller.log` from the installation attempt.

# Testing

The simplest way to test is to run the installer with the `--dry-run` flag:

```shell
./install.sh --dry-run --verbose
```

This will simulate the installation steps without making any changes to the system.

# FAQ

### Do I need a fresh Fedora install?

Not strictly, but the tool is designed and tested against fresh minimal Fedora installations. Running it on an existing system may overwrite some configurations.

### Will this work on Fedora derivatives (Nobara, Ultramarine, etc.)?

It may work, but it's only tested on stock Fedora Workstation. YMMV.

# Mission Statement

Fedorainstaller promises to ship a guided post-installation setup that follows Fedora best practices while giving users full control over what gets installed and configured.

The guided installer ensures a user-friendly experience with optional selections throughout the process — these options are never obligatory.

# Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

# License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
