#==============================================================================
# ZSH Configuration File
#==============================================================================

#------------------------------------------------------------------------------
# Core Initialization
#------------------------------------------------------------------------------

# Source custom aliases early to ensure they're available
source ~/.dotfiles/.zsh/.zsh_aliases

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

# FZF Configuration
# Key Bindings:
# - Ctrl+T: File search
# - Alt+C: Directory search
if type fzf &>/dev/null; then
    if [ -f /usr/share/doc/fzf/examples/key-bindings.zsh ]; then
        source /usr/share/doc/fzf/examples/key-bindings.zsh
        source /usr/share/doc/fzf/examples/completion.zsh
    elif [ -f /usr/local/opt/fzf/shell/key-bindings.zsh ]; then
        source /usr/local/opt/fzf/shell/key-bindings.zsh
        source /usr/local/opt/fzf/shell/completion.zsh
    elif type brew &>/dev/null && [ -f "$(brew --prefix)/opt/fzf/shell/key-bindings.zsh" ]; then
        source "$(brew --prefix)/opt/fzf/shell/key-bindings.zsh"
        source "$(brew --prefix)/opt/fzf/shell/completion.zsh"
    fi

    bindkey '^T' fzf-file-widget
    bindkey '\ec' fzf-cd-widget
fi

# Atuin Shell History
# Key Bindings:
# - Ctrl+R: Search history with full UI
# - Up Arrow: Search history for current line
if type atuin &>/dev/null; then
    eval "$(atuin init zsh)"
fi

# Auto-suggestions Configuration
# Key Bindings:
# - Right arrow: Accept suggestion
# - Ctrl+→: Accept next word
# - Alt+→: Accept next word
if [ -f /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]; then
    source /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh
elif [ -f "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh" ]; then
    source "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh"
elif type brew &>/dev/null && [ -f "$(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh" ]; then
    source "$(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
fi

# Auto-suggestion Settings
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20
ZSH_AUTOSUGGEST_USE_ASYNC=true
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#808080'

# Additional key bindings for autosuggestions
bindkey '^[[1;3C' forward-word      # Alt + →
bindkey '^[[1;5C' forward-word      # Ctrl + →

# You-Should-Use Configuration
if [ -f /usr/share/zsh-you-should-use/you-should-use.plugin.zsh ]; then
    source /usr/share/zsh-you-should-use/you-should-use.plugin.zsh
elif [ -f "$HOME/.oh-my-zsh/custom/plugins/you-should-use/you-should-use.plugin.zsh" ]; then
    source "$HOME/.oh-my-zsh/custom/plugins/you-should-use/you-should-use.plugin.zsh"
elif type brew &>/dev/null && [ -f "$(brew --prefix)/share/zsh-you-should-use/you-should-use.plugin.zsh" ]; then
    source "$(brew --prefix)/share/zsh-you-should-use/you-should-use.plugin.zsh"
elif [ -f "$HOME/.zsh/.zshplugins/you-should-use/you-should-use.plugin.zsh" ]; then
    source "$HOME/.zsh/.zshplugins/you-should-use/you-should-use.plugin.zsh"
fi

YSU_MESSAGE_POSITION="after"  # Show alias message after command
YSU_MODE=ALL                  # Show all matching aliases


#------------------------------------------------------------------------------
# Terminal UI and Appearance
#------------------------------------------------------------------------------

# Zoxide Configuration
# Key Bindings:
# - z <dir>: Jump to directory
# - z ..: Go up one directory
# - z ...: Go up two directories
# - zi: Interactive directory selection
if type zoxide &>/dev/null; then
    eval "$(zoxide init --cmd cd zsh)"
fi

# Oh My Posh Theme (skip for Apple Terminal)
if [ "$TERM_PROGRAM" != "Apple_Terminal" ]; then
    eval "$(oh-my-posh init zsh --config ~/.dotfiles/.config/ohmyposh/prompt.toml)"
fi

# Terminal Screensaver Configuration
TMOUT=600
TRAPALRM() {
    tty-clock -S -c -B < /dev/tty > /dev/tty
    zle reset-prompt
}

# Syntax Highlighting (Must be last)
if [ -f /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]; then
    source /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
elif [ -f "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]; then
    source "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
elif type brew &>/dev/null && [ -f "$(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]; then
    source "$(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi
