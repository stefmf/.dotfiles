#==============================================================================
# ZSH Configuration File
#==============================================================================

#------------------------------------------------------------------------------
# Core Shell Options
#------------------------------------------------------------------------------

# History configuration
setopt append_history          # Append to history file
setopt hist_ignore_dups        # Don't record duplicates
setopt hist_reduce_blanks      # Remove superfluous blanks
setopt share_history           # Share history between sessions
setopt hist_verify             # Show command with history expansion to user before running it
setopt hist_expire_dups_first  # Delete duplicates first when HISTFILE size exceeds HISTSIZE
setopt hist_ignore_space       # Don't record commands that start with space
setopt extended_history        # Record timestamp of command

# Completion and correction
setopt correct_all             # Correct all words in command line
setopt auto_param_slash        # Add trailing slash to directory completions
setopt always_to_end           # Move cursor to end of word after completion
setopt complete_in_word        # Allow completion from within a word
setopt flow_control off        # Disable flow control (Ctrl-S/Ctrl-Q)

# Globbing
setopt no_case_glob            # Case insensitive globbing
setopt no_case_match           # Case insensitive pattern matching
setopt extended_glob           # Extended globbing features
setopt dot_glob                # Include dotfiles in glob patterns
setopt glob_dots               # Include dotfiles in filename generation
setopt numeric_glob_sort       # Sort filenames numerically when possible

# Interactive and general options
setopt interactive_comments    # Allow comments in interactive shell
setopt pushd_ignore_dups       # Don't push duplicates onto directory stack
setopt pushd_silent            # Don't print directory stack after pushd/popd

#------------------------------------------------------------------------------
# History Configuration
#------------------------------------------------------------------------------

HISTFILE="$HOME/.dotfiles/.zsh/.zsh_history"
HISTSIZE=50000                 # Increased history size
SAVEHIST=50000                 # Increased save history size

#------------------------------------------------------------------------------
# Zinit Plugin Manager Setup
#------------------------------------------------------------------------------

# Set Zinit directory
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"

# Download Zinit if not installed
if [[ ! -d "$ZINIT_HOME" ]]; then
    mkdir -p "$(dirname $ZINIT_HOME)"
    git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi

# Source Zinit
source "${ZINIT_HOME}/zinit.zsh"

#------------------------------------------------------------------------------
# Zinit Plugin Loading
#------------------------------------------------------------------------------

# Load Oh My Zsh framework
zinit load ohmyzsh/ohmyzsh

# Load essential plugins with async loading where possible
zinit wait lucid for \
    atinit"zicompinit; zicdreplay" \
        zdharma-continuum/fast-syntax-highlighting \
    atload"_zsh_autosuggest_start" \
        zsh-users/zsh-autosuggestions \
    blockf atpull'zinit creinstall -q .' \
        zsh-users/zsh-completions

# Load utility plugins
zinit wait lucid for \
    MichaelAquilina/zsh-you-should-use \
    wfxr/forgit \
    Aloxaf/fzf-tab

# Load OMZ libraries and plugins we need
zinit wait lucid for \
    OMZL::git.zsh \
    OMZP::git \
    OMZP::sudo \
    OMZP::command-not-found

# Load FZF if available
zinit ice as"command" from"gh-r" \
    atclone"./fzf --zsh > init.zsh" \
    atpull"%atclone" src"init.zsh"
zinit light junegunn/fzf

#------------------------------------------------------------------------------
# Completion System Configuration
#------------------------------------------------------------------------------

# Add custom completion paths
fpath=("$HOME/.dotfiles/.zsh/.zsh_completions" $fpath)

# Make "/" a delimiter so forward-word stops on each directory
WORDCHARS=${WORDCHARS//\//}

# Enhanced completion styling
zstyle ':completion:*' menu select                        # Enable menu selection
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}     # Colored menu
zstyle ':completion:*' verbose yes                        # Verbose information
zstyle ':completion:*' group-name ''                      # Group matches
zstyle ':completion:*' squeeze-slashes true               # Remove extra slashes
zstyle ':completion:*' special-dirs true                  # Complete . and ..

# Enhanced description formatting
zstyle ':completion:*:descriptions' format '%F{yellow}-- %d --%f'

# Enhanced case-insensitive matching
zstyle ':completion:*' matcher-list \
    'm:{a-z}={A-Z}' \
    'r:|[._-]=* r:|=*' \
    'l:|=*'

# Speed up completions
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "$HOME/.dotfiles/.zsh/.zcompcache"

# Process completion
zstyle ':completion:*:*:*:*:processes' command "ps -u $USER -o pid,user,comm -w -w"
zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#) ([0-9a-z-]#)*=01;34=0=01'

# Directory completion
zstyle ':completion:*:cd:*' tag-order local-directories directory-stack path-directories
zstyle ':completion:*:cd:*:directory-stack' menu yes select
zstyle ':completion:*:-tilde-:*' group-order 'named-directories' 'path-directories' 'users' 'expand'

#------------------------------------------------------------------------------
# Key Bindings
#------------------------------------------------------------------------------

# Use emacs key bindings
bindkey -e

# Natural text editing like VS Code
# ⌥ ← / ⌥ → for word left/right
bindkey '\eb'        backward-word     # ESC b (iTerm "Left Option = Esc+")
bindkey '\ef'        forward-word      # ESC f
bindkey '\e[1;3D'    backward-word     # iTerm Alt‑Left when not Esc+
bindkey '\e[1;3C'    forward-word      # iTerm Alt‑Right when not Esc+

# ⌘ ← / ⌘ → for line start/end
bindkey '^A'         beginning-of-line # Ctrl-A
bindkey '^E'         end-of-line       # Ctrl-E
bindkey '\e[H'       beginning-of-line # Home
bindkey '\e[F'       end-of-line       # End

# History search
bindkey '^R'         history-incremental-search-backward
bindkey '^S'         history-incremental-search-forward

# Delete and backspace
bindkey '^[[3~'      delete-char       # Delete
bindkey '^?'         backward-delete-char # Backspace

#------------------------------------------------------------------------------
# Plugin Configuration
#------------------------------------------------------------------------------

# Autosuggestions configuration
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20
ZSH_AUTOSUGGEST_USE_ASYNC=true
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#808080'
ZSH_AUTOSUGGEST_PARTIAL_ACCEPT_WIDGETS=(forward-word)

# Right arrow accepts next token, Ctrl-Right accepts entire suggestion
bindkey '^[[C'       forward-word
bindkey '\e[1;2C'    autosuggest-accept

# You-Should-Use configuration
YSU_MESSAGE_POSITION="after"
YSU_MODE=ALL

# FZF configuration (if not set in environment)
if [[ -z "$FZF_DEFAULT_COMMAND" ]]; then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
fi
if [[ -z "$FZF_DEFAULT_OPTS" ]]; then
    export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border'
fi

# Load external FZF config if available
[[ -f "$HOME/.config/fzf/config.fzf" ]] && source "$HOME/.config/fzf/config.fzf"

#------------------------------------------------------------------------------
# Terminal UI and Appearance
#------------------------------------------------------------------------------

# Oh My Posh initialization
if [[ "$TERM" != "linux" ]] && command -v oh-my-posh >/dev/null 2>&1; then
    eval "$(oh-my-posh init zsh --config ~/.dotfiles/.config/ohmyposh/prompt.json)"
fi

# Terminal screensaver configuration
TMOUT=3600
TRAPALRM() {
    if command -v tty-clock >/dev/null 2>&1; then
        tty-clock -S -c -B < /dev/tty > /dev/tty
    fi
    zle reset-prompt 2>/dev/null || true
}

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
# Source Additional Configuration
#------------------------------------------------------------------------------

# Load custom aliases
[[ -f "$HOME/.dotfiles/.zsh/.zsh_aliases" ]] && source "$HOME/.dotfiles/.zsh/.zsh_aliases"