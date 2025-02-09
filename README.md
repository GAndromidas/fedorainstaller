# Fedora Setup Script

## Overview

This Bash script automates system setup on Fedora, streamlining configurations and installations for a smoother experience.

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
- Installs programs from a separate script (located in fedorainstaller/scripts)
- Installs flatpak applications from a separate script (located in fedorainstaller/scripts)
- Enables system services like fstrim, bluetooth, ssh, and firewall
- Creates a configuration file for the fastfetch system information tool
- Configures firewalld for basic security
- Cleans unused packages and cache
- Deletes the fedorainstaller folder (optional - prompts for confirmation)
- Reboots the system (optional - prompts for confirmation)

## Important

- Review the script before execution for customization.
- Ensure necessary permissions to execute the script.
- Recommended for fresh Fedora 40 installations.
- Some steps may require internet access.
- The script will prompt for system reboot after completion.

## License

This project is under the [MIT License](LICENSE).
