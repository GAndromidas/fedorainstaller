# Fedorainstaller: Fedora Post-Installation Script

---

## Overview

**Fedorainstaller** automates your Fedora post-install setup. It configures your system, installs essential and optional packages, and customizes your environment—all with minimal user input.

- **Streamlined setup:** Handles system configuration, package installation, and service management.
- **Modular scripts:** Easily customize what gets installed.
- **Idempotent:** Safe to run multiple times.

---

## Quick Start

```bash
git clone https://github.com/gandromidas/fedorainstaller && cd fedorainstaller
chmod +x install.sh
./install.sh
```

- Run as a regular user with sudo privileges.
- Follow the interactive prompts.

---

## Features

- Sets hostname
- Enables password feedback in sudo
- Configures DNF package manager
- Updates the system
- Installs kernel headers
- Enables RPM Fusion repositories for additional software
- Adds Flathub repository for installing flatpak applications
- Installs media codecs
- Enables hardware video acceleration
- Installs OpenH264 for Firefox web browser
- Installs ZSH shell and Oh-My-ZSH framework
- Installs ZSH plugins for auto-suggestions and syntax highlighting
- Changes the default shell to ZSH
- Configures ZSH with additional plugins
- Installs Starship prompt theme (optional)
- Installs DNF plugins for extended functionality
- Installs programs from a separate script (`fedorainstaller/scripts/programs.sh`)
- Installs flatpak applications from a separate script (`fedorainstaller/scripts/flatpak_programs.sh`)
- Enables system services like fstrim, bluetooth, ssh, and firewall
- Creates a configuration file for the fastfetch system information tool
- Configures firewalld for basic security
- Cleans unused packages and cache
- Optionally deletes the fedorainstaller folder (prompts for confirmation)
- Optionally reboots the system (prompts for confirmation)

---

## Structure

- `install.sh` — Main script
- `scripts/` — Modular sub-scripts (programs, flatpak_programs, etc.)
- `configs/` — Config templates

---

## Customization

- Edit package lists in `scripts/programs.sh` and `scripts/flatpak_programs.sh` for custom installs.
- Review and adjust configuration files in `configs/` as needed.

---

## FAQ

- **Should I run as root?** No, use a regular user with sudo privileges.
- **What Fedora versions are supported?** Recommended for fresh Fedora 40 installations.
- **What if something fails?** Check the terminal output for errors.
- **Is internet required?** Yes, for most installation steps.

---

## Contributing

Pull requests are welcome! Please follow the code style and add comments where needed.

---

## License

MIT — see [LICENSE](LICENSE).

---

_Enjoy your automated Fedora setup!_
