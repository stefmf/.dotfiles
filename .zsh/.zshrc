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
setopt correct                 # Correct mistyped commands
setopt auto_param_slash        # Add trailing slash to directory completions
setopt always_to_end           # Move cursor to end of word after completion
setopt complete_in_word        # Allow completion from within a word
unsetopt flow_control          # Disable flow control (Ctrl-S/Ctrl-Q)

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

# Skip expensive security checks on trusted system
autoload -Uz compinit
compinit -C

#------------------------------------------------------------------------------
# Zinit Plugin Loading
#------------------------------------------------------------------------------

# Load Oh My Zsh framework
zinit load ohmyzsh/ohmyzsh

# Configure autosuggestions BEFORE loading
ZSH_AUTOSUGGEST_STRATEGY=(history completion)
ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20
ZSH_AUTOSUGGEST_USE_ASYNC=true
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#808080'
# Only accept full suggestion on End; Right‑arrow should be partial (word/segment)
ZSH_AUTOSUGGEST_ACCEPT_WIDGETS=(end-of-line)
ZSH_AUTOSUGGEST_PARTIAL_ACCEPT_WIDGETS=(forward-word vi-forward-word)

# Load autosuggestions via zinit
zinit load zsh-users/zsh-autosuggestions

# Load other essential plugins with async loading
zinit lucid for \
    atinit"ZINIT[COMPINIT_OPTS]=-C; zicompinit; zicdreplay" \
        zdharma-continuum/fast-syntax-highlighting \
    blockf atpull'zinit creinstall -q .' \
        zsh-users/zsh-completions

# Load fzf-tab for fuzzy completion menu
# zinit light Aloxaf/fzf-tab

# Load utility plugins
zinit wait lucid for \
    MichaelAquilina/zsh-you-should-use \
    wfxr/forgit

# Load OMZ libraries and plugins we need
zinit wait lucid for \
    OMZL::git.zsh \
    OMZP::git \
    OMZP::command-not-found \
    OMZP::sudo               # Press ESC twice to add sudo to current command

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
# Start with default WORDCHARS and remove "/"
WORDCHARS=${WORDCHARS//\//}

# Simple completion styling
zstyle ':completion:*' menu select                        # Enable menu selection
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}     # Colored menu
zstyle ':completion:*' squeeze-slashes true               # Remove extra slashes
zstyle ':completion:*' special-dirs true                  # Complete . and ..

# Case-insensitive matching with fuzzy matching
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'

# Speed up completions
zstyle ':completion:*' use-cache on
zstyle ':completion:*' cache-path "$HOME/.dotfiles/.zsh/.zcompcache"

# Enable incremental completion search
zstyle ':completion:*:*:*:*:*' menu select search

#------------------------------------------------------------------------------
# Key Bindings
#------------------------------------------------------------------------------

# Use emacs key bindings
bindkey -e

# ─── Custom Keybindings ───────────────────────────

# ------- Natural text editing like VS Code -------
bindkey -e                       # emacs keymap (default on macOS)

# ⌥ ← / ⌥ →  → word left/right
bindkey '\eb'        backward-word   # ESC b (iTerm "Left Option = Esc+")
bindkey '\ef'        forward-word    # ESC f
bindkey '\e[1;3D'    backward-word   # iTerm Alt‑Left when not Esc+
bindkey '\e[1;3C'    forward-word    # iTerm Alt‑Right when not Esc+

# ⌘ ← / ⌘ →  → line start/end
bindkey '^A'         beginning-of-line   # sent if you chose Hex 01
bindkey '^E'         end-of-line         # sent if you chose Hex 05
bindkey '\e[H'       beginning-of-line   # ESC [ H  (Home)
bindkey '\e[F'       end-of-line         # ESC [ F  (End)


# ─── Autosuggestion navigation ──────────────────────────────

# Right‑arrow → accept next token (/‑delimited path segment or word)
# Cover common escape sequences and terminfo so we don’t fall back to forward-char
bindkey '^[[C'    forward-word   # CSI C
bindkey '\e[C'   forward-word   # xterm normal mode
bindkey '\eOC'   forward-word   # application cursor mode
if [[ -n ${terminfo[kRIT]} ]]; then
  bindkey "${terminfo[kRIT]}" forward-word
fi
# Ctrl‑Right → accept the entire suggestion
bindkey '\e[1;2C'  autosuggest-accept

# History search
bindkey '^R'         history-incremental-search-backward
bindkey '^S'         history-incremental-search-forward

# Delete and backspace
bindkey '^[[3~'      delete-char       # Delete
bindkey '^?'         backward-delete-char # Backspace

# ─── Completion menu navigation and search ──────────────────

# Load menuselect for advanced menu features
zmodload zsh/complist

# Enable incremental search in menu with '/'
bindkey -M menuselect '/' history-incremental-search-forward
bindkey -M menuselect '?' history-incremental-search-backward

# Accept completion with Enter and stay in menu for more completions
bindkey -M menuselect '^M' .accept-line

# Cancel completion with Escape
bindkey -M menuselect '^[' send-break

# You-Should-Use Configuration
YSU_PLUGIN_PATHS=(
    "${ZINIT_HOME}/plugins/MichaelAquilina---zsh-you-should-use/you-should-use.plugin.zsh"
    "$HOME/.dotfiles/.zsh/.zshplugins/zsh-you-should-use/you-should-use.plugin.zsh"
    "/usr/share/zsh-you-should-use/zsh-you-should-use.plugin.zsh"
    "$(brew --prefix 2>/dev/null)/share/zsh-you-should-use/you-should-use.plugin.zsh"
)

for ysu_plugin in "${YSU_PLUGIN_PATHS[@]}"; do
    if [ -f "$ysu_plugin" ]; then
        source "$ysu_plugin"
        break
    fi
done

YSU_MESSAGE_POSITION="after"  # Show alias message after command
YSU_MODE=ALL                  # Show all matching aliases

# FZF configuration (if not set in environment)
if [[ -z "$FZF_DEFAULT_COMMAND" ]]; then
    export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'
fi
if [[ -z "$FZF_DEFAULT_OPTS" ]]; then
    export FZF_DEFAULT_OPTS='--height 40% --layout=reverse --border'
fi

# Enhanced FZF-Tab configuration
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -1 --color=always $realpath'
zstyle ':fzf-tab:complete:ls:*' fzf-preview 'eza -1 --color=always $realpath'
zstyle ':fzf-tab:complete:cat:*' fzf-preview 'bat --color=always --style=numbers --line-range=:500 $realpath'
zstyle ':fzf-tab:complete:less:*' fzf-preview 'bat --color=always --style=numbers --line-range=:500 $realpath'
zstyle ':fzf-tab:complete:vim:*' fzf-preview 'bat --color=always --style=numbers --line-range=:500 $realpath'
zstyle ':fzf-tab:complete:nvim:*' fzf-preview 'bat --color=always --style=numbers --line-range=:500 $realpath'
zstyle ':fzf-tab:complete:*:*' fzf-preview 'echo $realpath'
zstyle ':fzf-tab:*' fzf-flags --height=60% --layout=reverse
zstyle ':fzf-tab:*' fzf-command ftb-tmux-popup

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
# Source Additional Configuration
#------------------------------------------------------------------------------

# Load custom aliases
[[ -f "$HOME/.dotfiles/.zsh/.zaliases" ]] && source "$HOME/.dotfiles/.zsh/.zaliases"