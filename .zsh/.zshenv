#------------------------------------------------------------------------------
# Environment Variables and Core Settings
#------------------------------------------------------------------------------

# Dotfile Management
export DOTFILES="$HOME/.dotfiles"                           # Central location for dotfiles
export ZSH_COMPDUMP="$DOTFILES/.zsh/.zcompdump"            # Completion cache
export ZSH_CUSTOM="$DOTFILES/.zsh/plugins"                 # Custom plugin directory
export HISTFILE="$DOTFILES/.zsh/.zsh_history"              # History file location
export ZSH_SESSION_DIR="$DOTFILES/.zsh/zsh_sessions"       # Session management

# Default Applications
if [ "$TERM_PROGRAM" = "vscode" ]; then
    # Running within VS Code, use 'code -w' as editor
    function vscode() {
        code -w "$@"
    }
    export VISUAL=vscode
    export EDITOR=vscode
else
    # Default to neovim when not in VS Code
    export VISUAL=nvim
    export EDITOR=nvim
fi

# FZF Core Settings (these should be available to scripts)
export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border'

# Optional: Set to any value to clear screen on logout
export CLEAR_ON_LOGOUT=1