#==============================================================================
# ZSH Configuration File
#==============================================================================

#------------------------------------------------------------------------------
# Core Initialization
#------------------------------------------------------------------------------

# Source custom aliases early to ensure they're available
source ~/.dotfiles/.zsh/.zsh_aliases

#------------------------------------------------------------------------------
# SSH Detection for Root Sessions
#------------------------------------------------------------------------------

# Only for root without SSH_CONNECTION
if [[ $EUID -eq 0 ]] && [[ -z "$SSH_CONNECTION" ]]; then
    # Check if who am i shows an IP address (indicates SSH)
    if who am i 2>/dev/null | grep -qE '\([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\)'; then
        export SSH_CONNECTION="detected"
    fi
fi
#------------------------------------------------------------------------------
# Completion System Setup
#------------------------------------------------------------------------------

# Add custom completion paths
FPATH="$HOME/.dotfiles/.zsh/.zsh_completions:$FPATH"

# Initialize completion system
autoload -Uz compinit

# Optimize completion dump rebuilding (once per day)
ZSH_COMPDUMP="${ZDOTDIR:-$HOME}/.zcompdump"

# Function to get file modification time in seconds since epoch
get_file_mtime() {
    if [ -f "$1" ]; then
        if stat -c '%Y' "$1" &>/dev/null; then
            # GNU stat (Linux)
            stat -c '%Y' "$1"
        elif stat -f '%m' "$1" &>/dev/null; then
            # BSD stat (macOS)
            stat -f '%m' "$1"
        else
            echo 0
        fi
    else
        echo 0
    fi
}

current_day=$(date +%j)
compdump_mtime=$(get_file_mtime "$ZSH_COMPDUMP")
compdump_day=$(date -j -f "%s" "$compdump_mtime" +%j 2>/dev/null || date -d @"$compdump_mtime" +%j 2>/dev/null || echo 0)

if [ "$compdump_mtime" -eq 0 ] || [ "$current_day" != "$compdump_day" ]; then
    compinit -d "$ZSH_COMPDUMP"
else
    compinit -C -d "$ZSH_COMPDUMP"
fi

# Completion Styling
zstyle ':completion:*' menu select                        # Enable menu selection
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' # Case insensitive
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}     # Colored menu
zstyle ':completion:*' verbose yes                        # Verbose information
zstyle ':completion:*' group-name ''                      # Group matches

#------------------------------------------------------------------------------
# Plugin Configuration
#------------------------------------------------------------------------------

# Load FZF config
FZF_CONFIG="$HOME/.config/fzf/config.fzf"
[[ -f "$FZF_CONFIG" ]] && source "$FZF_CONFIG"



#------------------------------------------------------------------------------
# Terminal UI and Appearance
#------------------------------------------------------------------------------

# Initialize Oh My Posh in any terminal that supports it
if [ "$TERM" != "linux" ]; then
  if type oh-my-posh &>/dev/null; then
    eval "$(oh-my-posh init zsh --config ~/.dotfiles/.config/ohmyposh/prompt.json)"
  fi
fi

# Terminal Screensaver Configuration
TMOUT=600
TRAPALRM() {
    if type tty-clock &>/dev/null; then
        tty-clock -S -c -B < /dev/tty > /dev/tty
    fi
    zle reset-prompt
}

# Source every ZSH plugin config
for cfg in "$HOME/.dotfiles/.zsh/config/"*.zsh; do
  source "$cfg"
done

