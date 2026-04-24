# If you come from bash you might have to change your $PATH.
# export PATH=$HOME/bin:/usr/local/bin:$PATH

# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

# Themes
ZSH_THEME="agnoster"
DEFAULT_USER=$USER

# Oh-My-ZSH Auto Update
zstyle ':omz:update' mode auto      # update automatically without asking

# Plugins
plugins=(git fzf zsh-autosuggestions zsh-syntax-highlighting)

source $ZSH/oh-my-zsh.sh

# FZF Configuration - Compact list with colors

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

# Aliases

# System maintenance aliases
alias sync='sudo dnf update --refresh'
alias update='sudo dnf update && sudo dnf upgrade && sudo flatpak update'
alias clean='sudo dnf -y autoremove && sudo dnf clean all && sudo flatpak uninstall --unused'
alias cache='rm -rf ~/.cache/*'
alias microcode='grep . /sys/devices/system/cpu/vulnerabilities/*'
alias sr='sudo reboot'
alias ss='sudo poweroff'
alias jctl='journalctl -p 3 -xb'

# Replace ls with eza
alias ls='eza -al --color=always --group-directories-first --icons' # preferred listing
alias la='eza -a --color=always --group-directories-first --icons'  # all files and dirs
alias ll='eza -l --color=always --group-directories-first --icons'  # long format
alias lt='eza -aT --color=always --group-directories-first --icons' # tree listing
alias l.="eza -a | grep -e '^\.'"                                   # show only dotfiles

# Navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias -- -='cd -'

# Networking
alias ip='ip addr'
alias ports='netstat -tulanp'
alias ping='ping -c 5'

# System Monitoring
alias top='btop'
alias hw='hwinfo --short'
alias cpu='lscpu'
alias mem="free -mt"
alias psf='ps auxf'

# Disk Usage
alias df='df -h'
alias du='du -h'
alias duh='du -h --max-depth=1'

# Tar and Zip Operations
alias tar='tar -acf '
alias untar='tar -zxvf '
alias zip='zip -r'
alias unzip='unzip'

# Miscellaneous aliases
alias zshconfig="nano ~/.zshrc"
alias update-grub='sudo grub2-mkconfig -o /boot/grub2/grub.cfg'

# Load additional tools
fastfetch
eval "$(zoxide init zsh)"
eval "$(starship init zsh)"
