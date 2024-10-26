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

if type brew &>/dev/null; then
    # Add completion paths
    FPATH="$(brew --prefix)/share/zsh-completions:$FPATH"
    FPATH="$HOME/.dotfiles/.zsh/.zsh_completions:$FPATH"

    # Initialize completion system
    autoload -Uz compinit

    # Optimize completion dump rebuilding (once per day)
    if [ $(date +'%j') != $(stat -f '%Sm' -t '%j' "$ZSH_COMPDUMP" 2>/dev/null) ]; then
        compinit -d "$ZSH_COMPDUMP"
    else
        compinit -C -d "$ZSH_COMPDUMP"
    fi

    # Completion Styling
    zstyle ':completion:*' menu select                      # Enable menu selection
    zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' # Case insensitive
    zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}   # Colored menu
    zstyle ':completion:*' verbose yes                      # Verbose information
    zstyle ':completion:*' group-name ''                    # Group matches
fi

#------------------------------------------------------------------------------
# Plugin Configuration
#------------------------------------------------------------------------------

# FZF Configuration
# Key Bindings:
# - Ctrl+T: File search
# - Alt+C: Directory search
if type fzf &>/dev/null; then
    source "$(brew --prefix)/opt/fzf/shell/key-bindings.zsh"
    source "$(brew --prefix)/opt/fzf/shell/completion.zsh"
    
    bindkey '^T' fzf-file-widget
    bindkey '\ec' fzf-cd-widget
fi

# Atuin Shell History
# Key Bindings:
# - Ctrl+R: Search history with full UI
# - Up Arrow: Search history for current line
eval "$(atuin init zsh)"

# Auto-suggestions Configuration
# Key Bindings:
# - Right arrow: Accept suggestion
# - Ctrl+→: Accept next word
# - Alt+→: Accept next word
if type brew &>/dev/null; then
    source "$(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
    
    # Auto-suggestion Settings (these should be set before sourcing the plugin)
    ZSH_AUTOSUGGEST_STRATEGY=(history completion)
    ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20
    ZSH_AUTOSUGGEST_USE_ASYNC=true
    ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#808080'
    
    # Additional key bindings for autosuggestions
    bindkey '^[[1;3C' forward-word      # Alt + →
    bindkey '^[[1;5C' forward-word      # Ctrl + →
fi

# You-Should-Use Configuration
if type brew &>/dev/null; then
    source "$(brew --prefix)/share/zsh-you-should-use/you-should-use.plugin.zsh"
    YSU_MESSAGE_POSITION="after"  # Show alias message after command
    YSU_MODE=ALL                  # Show all matching aliases
fi

#------------------------------------------------------------------------------
# Terminal UI and Appearance
#------------------------------------------------------------------------------

# Zoxide Configuration
# Key Bindings:
# - z <dir>: Jump to directory
# - z ..: Go up one directory
# - z ...: Go up two directories
# - zi: Interactive directory selection
if type brew &>/dev/null; then
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
if type brew &>/dev/null; then
    source "$(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi