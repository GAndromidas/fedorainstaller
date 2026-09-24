<div align="center">

# FedoraInstaller

[![GitHub release](https://img.shields.io/github/release/GAndromidas/fedorainstaller.svg?style=for-the-badge&logo=github)](https://github.com/GAndromidas/fedorainstaller/releases)
[![Last Commit](https://img.shields.io/github/last-commit/GAndromidas/fedorainstaller.svg?style=for-the-badge&logo=git)](https://github.com/GAndromidas/fedorainstaller/commits/main)
[![License](https://img.shields.io/badge/License-MIT-blue.svg?style=for-the-badge&logo=open-source-initiative)](LICENSE)
[![Fedora](https://img.shields.io/badge/Platform-Fedora-51A2DA?style=for-the-badge&logo=fedora)](https://fedoraproject.org/)

Just another guided/automated Fedora post-installation setup tool with a twist.
The installer doubles as a bash library to configure Fedora systems, manage packages, and set up services — from a fresh install or an existing system.

</div>

# Features

- Hardware-aware CPU detection (Intel/AMD with microcode updates)
- Automatic GPU driver detection and installation (NVIDIA/AMD/Intel, including multi-GPU hybrids)
- Storage optimization (NVMe/SSD/HDD with I/O scheduling)
- Desktop environment detection and optimization (KDE Plasma 6+, GNOME 46+)
- Security hardening (Firewalld + Fail2ban with SSH protection)
- Advanced performance tuning (RAM-based swappiness, zRAM, transparent hugepages, sysctl)
- Wake-on-LAN configuration for ethernet devices (explicit opt-in, desktops only)
- Zsh shell with Oh-My-Zsh and Starship prompt
- Resume functionality for interrupted installations
- Dry-run preview mode and read-only post-install health check

# Requirements

- Fresh Fedora installation (Workstation or minimal)
- Active internet connection
- Regular user account with sudo privileges
- Minimum 2GB free disk space
- Supported bootloader (GRUB/systemd-boot)

# Quick Start

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
  -h, --help      Show help message and exit
  -V, --version   Show version information and exit
  -v, --verbose   Enable verbose output
  -q, --quiet     Quiet mode (minimal output)
  -d, --dry-run   Preview changes without making them
  -a, --auto      Automatically select the recommended installation mode
  -y, --yes       Non-interactive mode: accept safe/default prompts automatically
  -c, --check     Read-only health check (runs scripts/verify.sh, changes nothing)
```

Examples:

```shell
./install.sh                # Interactive install
./install.sh --verbose      # Detailed package installation output
./install.sh --dry-run      # Preview changes without making them
./install.sh --auto         # Pick the recommended mode automatically
./install.sh --yes          # Unattended run with safe/default choices
./install.sh --check        # Verify an installed system (safe, read-only)
```

### Installation modes

| Mode | Description |
|------|-------------|
| **Standard** | Complete setup with all recommended packages (intermediate users) |
| **Minimal** | Essential tools only for lightweight installations (new users) |
| **Server** | Headless configuration (Docker, SSH, server utilities) |

Headless systems automatically get Server mode. Gaming mode is offered as an
optional step during Standard/Minimal installations and is skipped on servers.

# What it does

Fedorainstaller runs a series of steps to transform a fresh Fedora system:

| # | Step | Description |
|---|------|-------------|
| 1 | **System Preparation** | Configures DNF, enables RPM Fusion/Flathub, installs codecs, CPU microcode, kernel headers, and runs a full system update |
| 2 | **Shell Setup** | Installs Zsh, Oh-My-Zsh, plugins, Starship prompt, Fastfetch config, and Nerd Fonts |
| 3 | **Programs** | Installs packages for your chosen mode (DNF + Flatpak), plus Docker/Portainer/Watchtower in server mode |
| 4 | **Gaming Mode** | Optional: reads `gaming_mode.yaml` and installs Steam, MangoHud, GameMode, Heroic Launcher, Discord |
| 5 | **Hardware Detection** | Detects CPU/GPU vendor, installs appropriate drivers |
| 6 | **Bootloader Configuration** | Configures GRUB or systemd-boot |
| 7 | **System Services** | Configures firewalld (SSH + KDE Connect), user groups, power management, GPU drivers, RAM tuning, advanced sysctl tuning, and automates essential systemd services (sshd always, plus bluetooth/CUPS/cronie/fstrim/KDE Connect when detected) |
| 8 | **Fail2ban** | Installs and configures SSH brute-force protection |
| 9 | **Maintenance** | Cleans up, removes unused packages, trims SSDs |
| 10 | **Wake-on-LAN** | Enables Wake-on-LAN on ethernet interfaces (desktops only; gracefully skipped on VMs, containers, and laptops that decline) |

# Project Structure

```text
fedorainstaller/
├── install.sh              # Orchestrator: flag parsing, sudo keep-alive, dashboard steps
├── scripts/
│   ├── common.sh           # Compatibility facade — loads every lib module
│   ├── lib/                # Shared libraries (single source of truth)
│   │   ├── core.sh         # Logging, colors, timing helpers
│   │   ├── ui.sh           # Menus, prompts, banners, messaging
│   │   ├── system.sh       # CPU/GPU/bootloader/hardware detection
│   │   ├── package.sh      # DNF / Flatpak installation helpers
│   │   ├── config.sh       # YAML helpers (yq)
│   │   ├── state.sh        # Progress tracking, resume, error handling, reboot
│   │   └── dashboard.sh    # Dashboard wizard UI
│   ├── modules/            # One install step per file, run in order by install.sh
│   └── verify.sh           # Read-only post-reboot health check
├── configs/                # Package lists (programs.yaml, gaming_mode.yaml) and dotfiles
└── tests/
    └── syntax.sh           # bash -n over every shell script
```

Package selection lives in `configs/programs.yaml` (per-mode DNF/Flatpak lists)
and `configs/gaming_mode.yaml` (gaming extras). To change *what* gets installed,
edit those files — no script changes needed.

# Resume

Progress is tracked in `/var/tmp/fedorainstaller.state`, which survives reboots
(unlike `/tmp`). If the installer is interrupted, just run `./install.sh` again:

- Completed steps are skipped automatically.
- Failed steps are retried.
- A declined Gaming Mode step is offered again; a skipped Wake-on-LAN step stays skipped.
- To start over completely: `rm -f /var/tmp/fedorainstaller.state`.

State written by older releases under `~/.fedorainstaller.state` is migrated
automatically on the next run.

# Logs

- Installation log: `/var/tmp/fedorainstaller.log` (rotated, last 3 runs kept)
- Progress tracking: `/var/tmp/fedorainstaller.state`

When reporting an issue, please attach the contents of
`/var/tmp/fedorainstaller.log` from the installation attempt.

# Safety Model

- **Confirm before continuing:** destructive or failure paths always ask first
  (e.g. bootloader or system-preparation failures prompt before continuing).
- **`--yes` never reboots:** unattended mode accepts safe defaults but always
  skips the reboot — you reboot manually when ready.
- **Dry-run changes nothing:** `--dry-run` never installs helpers (not even
  `gum`), never writes resume state, and never touches the system.
- **`--check` is read-only:** it runs `scripts/verify.sh` before any sourcing,
  sudo use, or state writes.
- **Idempotent steps:** re-running the installer skips completed work instead
  of redoing it.

# Verify After Reboot

After rebooting into the configured system, confirm everything actually works:

```shell
bash scripts/verify.sh
# or
./install.sh --check
```

This checks live, booted state the install log cannot prove: kernel command
line, loaded GPU drivers (including the NVIDIA module and Secure Boot notes),
I/O schedulers, filesystem snapshots, firewalld/fail2ban status with the sshd
jail, Wake-on-LAN link state, maintenance timers (`dnf-makecache.timer`,
`fstrim.timer`), shell/tooling, and the gaming stack when present.

# Troubleshooting

- **Resume from interruption:** run `./install.sh` again; completed steps are skipped.
- **Stale failure markers:** removed automatically on a clean finish; delete the
  state file to force a fresh run: `rm -f /var/tmp/fedorainstaller.state`.
- **Sudo timeouts on long runs:** the installer refreshes sudo in the background;
  if authentication failed up front, check the log and re-run with a valid sudo session.
- **NVIDIA + Secure Boot:** the module must be enrolled via akmods/MOK; see the
  verify output for guidance.
- **No GPU detected:** expected on headless systems — Server mode is selected automatically.
- **Start fresh:** `rm -f /var/tmp/fedorainstaller.state /var/tmp/fedorainstaller.log`.

# Testing

Preview mode (zero system changes):

```shell
./install.sh --dry-run --verbose
```

Syntax check over every shell script:

```shell
bash tests/syntax.sh
```

Read-only health check of the current machine:

```shell
bash scripts/verify.sh
# or
./install.sh --check
```

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

Please run `bash tests/syntax.sh` before opening a Pull Request.

# License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
