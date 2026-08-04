# =============================================================================
# ZSH Configuration
# =============================================================================

# Path to your oh-my-zsh installation
export ZSH="$HOME/.oh-my-zsh"

# Add local bin to PATH if it exists
[ -d "$HOME/.local/bin" ] && export PATH="$HOME/.local/bin:$PATH"

# Themes
ZSH_THEME="agnoster"
DEFAULT_USER=$USER

# Oh-My-ZSH Auto Update
zstyle ':omz:update' mode auto      # Update automatically without asking

# Plugins
# git: Git integration with aliases and prompt info
# fzf: Fuzzy finder for commands (Ctrl+R), files (Ctrl+T), and directories (Alt+C)
plugins=(git fzf)

source $ZSH/oh-my-zsh.sh

# Manually source additional plugins
source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# =============================================================================
# FZF Configuration - Compact list with colors
# =============================================================================

# Set FZF default options to inherit terminal colors
export FZF_DEFAULT_OPTS="
  --height 40%
  --layout=reverse
  --border
  --inline-info
  --color=fg:-1,bg:-1,hl:blue:bold
  --color=fg+:white,bg+:bright-black,hl+:blue:bold
  --color=info:magenta,prompt:blue,pointer:blue
  --color=marker:green,spinner:yellow,header:blue
  --color=border:bright-black
"

# FZF file search (Ctrl+T)
export FZF_CTRL_T_OPTS="
  --preview 'bat --color=always --style=numbers --line-range=:500 {}'
  --preview-window=right:50%:wrap
"

# FZF directory search (Alt+C)
export FZF_ALT_C_OPTS="
  --preview 'eza --tree --color=always --icons {} | head -200'
"

# FZF command history (Ctrl+R)
export FZF_CTRL_R_OPTS="
  --preview 'echo {}'
  --preview-window=down:3:wrap
"

# =============================================================================
# Aliases
# =============================================================================

# System maintenance aliases
alias sync='sudo dnf makecache && sudo dnf check-update'
alias update='sudo dnf update && sudo dnf upgrade && flatpak update'
alias clean='echo "Starting DNF system clean..." && \
  sudo dnf autoremove && \
  sudo dnf clean all && \
  echo "Removing unused Flatpaks..." && \
  flatpak uninstall --unused && \
  echo "Vacuuming systemd journal (keep 3 days)..." && \
  sudo journalctl --vacuum-time=3d && \
  echo "Wiping caches..." && \
  rm -rf ~/.cache/thumbnails/* 2>/dev/null; \
  echo "Clean complete!"'
alias cache='rm -rf ~/.cache/*'
alias mirror='sudo dnf makecache'                                                          # Refresh DNF metadata
alias microcode='grep . /sys/devices/system/cpu/vulnerabilities/*'
alias sr='sudo reboot'
alias ss='sudo poweroff'
alias bios='systemctl reboot --firmware-setup'                                            # Reboot to UEFI firmware
alias suspend='systemctl suspend'
alias hibernate='systemctl hibernate'
alias jctl='journalctl -p 3 -xb'

# Replace ls with eza
alias ls='eza -al --color=always --group-directories-first --icons' # preferred listing
alias la='eza -a --color=always --group-directories-first --icons'  # all files and dirs
alias ll='eza -l --color=always --group-directories-first --icons'  # long format
alias lt='eza -aT --color=always --group-directories-first --icons' # tree listing
alias l.="eza -a | grep -e '^\.'"                                   # show only dotfiles
alias lh='eza -ahl --color=always --group-directories-first --icons' # human-readable sizes

# Navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'
alias -- -='cd -'
alias home='cd ~'
alias docs='cd ~/Documents'
alias down='cd ~/Downloads'

# Networking
alias ip='ip addr'
alias ipa='ip -c -br addr'                                                               # Brief colored IP info
alias myip='curl -s ifconfig.me'                                                         # Show public IP
alias localip='hostname -I'                                                              # Show local IP
alias ports='netstat -tulanp'
alias listenports='sudo lsof -i -P -n | grep LISTEN'                                     # Listening ports
alias scanports='nmap -p 1-1000'                                                         # Scan ports 1-1000
alias ping='ping -c 5'
alias fastping='ping -c 100 -s.2'                                                        # Fast ping test
alias wget='wget -c'                                                                     # Resume downloads

# System Monitoring
alias top='btop'
alias htop='btop'
alias hw='hwinfo --short'
alias cpu='lscpu'
alias gpu='lspci | grep -i vga'                                                          # GPU information
alias mem="free -mt"
alias gove='cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor'                   # CPU Governor
alias cpustat='cpupower frequency-info | grep -E "governor|current policy"'              # CPU Power Stats
alias psf='ps auxf'
alias psg='ps aux | grep -v grep | grep -i -e VSZ -e'                                    # Search processes
alias topcpu='ps auxf | sort -nr -k 3 | head -10'                                        # Top 10 CPU processes
alias topmem='ps auxf | sort -nr -k 4 | head -10'                                        # Top 10 memory processes

# Disk Usage
alias df='df -h'
alias du='du -h'
alias duh='du -h --max-depth=1 | sort -h'
alias duf='duf'                                                                          # Modern disk usage tool

# Tar and Zip Operations
alias mktar='tar -acf'
alias untar='tar -xvf'
alias mkzip='zip -r'
alias lstar='tar -tvf'                                                                   # List tar contents
alias lszip='unzip -l'                                                                   # List zip contents

# File Operations
alias cp='cp -iv'                                                                        # Interactive, verbose copy
alias mv='mv -iv'                                                                        # Interactive, verbose move
alias rm='rm -Iv --preserve-root'                                                        # Interactive delete
alias mkdir='mkdir -pv'                                                                  # Create parents as needed
alias grep='grep --color=auto'
alias diff='diff --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# Miscellaneous aliases
alias zshconfig="nano ~/.zshrc"
alias zshreload='source ~/.zshrc'                                                        # Reload zsh config
alias aliases='cat ~/.zshrc | grep "^alias" | sed "s/alias //" | column -t -s="# "'      # List aliases
alias update-grub='sudo grub2-mkconfig -o /boot/grub2/grub.cfg'
alias orphans='sudo dnf autoremove'                                                      # Remove orphaned packages
alias weather='curl wttr.in'                                                             # Show weather
alias matrix='cmatrix'
alias ports-used='netstat -tulanp | grep ESTABLISHED'                                    # Active connections

# =============================================================================
# Tool Initialization
# =============================================================================

# Zoxide - Smart cd replacement (use 'z dirname' to jump to frequently used directories)
eval "$(zoxide init zsh)"
alias cd='z'  # Replace cd with zoxide for smart directory jumping

# Starship - Modern prompt with git integration
eval "$(starship init zsh)"

# Fastfetch - Display system information on shell start
fastfetch

# =============================================================================
# Additional Functions
# =============================================================================

# Extract any archive type
extract() {
  if [ -f "$1" ]; then
    case "$1" in
      *.tar.bz2)   tar xjf "$1"     ;;
      *.tar.gz)    tar xzf "$1"     ;;
      *.bz2)       bunzip2 "$1"     ;;
      *.rar)       unrar x "$1"     ;;
      *.gz)        gunzip "$1"      ;;
      *.tar)       tar xf "$1"      ;;
      *.tbz2)      tar xjf "$1"     ;;
      *.tgz)       tar xzf "$1"     ;;
      *.zip)       unzip "$1"       ;;
      *.Z)         uncompress "$1"  ;;
      *.7z)        7z x "$1"        ;;
      *)           echo "'$1' cannot be extracted via extract()" ;;
    esac
  else
    echo "'$1' is not a valid file"
  fi
}

# Create directory and cd into it
mkcd() {
  mkdir -p "$1" && cd "$1"
}

# Find and kill process by name
killp() {
  ps aux | grep -i "$1" | grep -v grep | awk '{print $2}' | xargs sudo kill -9
}

# =============================================================================
# End of Configuration
# =============================================================================
