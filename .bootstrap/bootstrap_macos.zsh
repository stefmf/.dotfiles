#!/usr/bin/env zsh

# Enable strict error handling
setopt ERR_EXIT   # Exit on error
setopt PIPE_FAIL  # Exit on pipe failure
setopt UNSET      # Exit on undefined variable

# ---------------------------
# Constants and Configuration
# ---------------------------

# Determine the parent directory of the script
DOTFILES_DIR="${0:a:h:h}"
BREW_FILE="$DOTFILES_DIR/Brewfile"
DOTBOT_INSTALL="$DOTFILES_DIR/install"
ZSH_PROFILE="$HOME/.zshrc"

# ---------------------------
# Color Output Setup
# ---------------------------

autoload -U colors && colors
typeset -A COLORS=(
    [info]=$fg[green]
    [warning]=$fg[yellow]
    [error]=$fg[red]
    [debug]=$fg[blue]
)

# ---------------------------
# Helper Functions
# ---------------------------

# Logging Functions
log_info() { print -P "${COLORS[info]}[INFO]%f $1"; }
log_warning() { print -P "${COLORS[warning]}[WARNING]%f $1"; }
log_error() { print -P "${COLORS[error]}[ERROR]%f $1"; exit 1; }

# ---------------------------
# Dependency Checks
# ---------------------------

check_dependencies() {
    local dependencies=("git" "curl")
    for cmd in "${dependencies[@]}"; do
        if ! command -v "$cmd" > /dev/null; then
            log_error "Dependency '$cmd' is not installed. Please install it and rerun the script."
        else
            log_info "Dependency '$cmd' is installed."
        fi
    done
}

# ---------------------------
# System Check
# ---------------------------

check_macos() {
    if [[ "$(uname)" != "Darwin" ]]; then
        log_error "This script is designed for macOS."
    else
        log_info "Operating system is macOS."
    fi
}

# ---------------------------
# Homebrew Installation
# ---------------------------

install_homebrew() {
    if (( ! $+commands[brew] )); then
        log_info "Installing Homebrew..."
        if command -v curl > /dev/null; then
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        else
            log_error "curl is required but not installed. Aborting."
        fi
        
        # Configure Homebrew environment
        if [[ "$(uname -m)" == "arm64" ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
            if ! grep -q "eval \"\$(/opt/homebrew/bin/brew shellenv)\"" "$ZSH_PROFILE"; then
                echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$ZSH_PROFILE"
                log_info "Homebrew path added to $ZSH_PROFILE"
            fi
        else
            eval "$(/usr/local/bin/brew shellenv)"
            if ! grep -q "eval \"\$(/usr/local/bin/brew shellenv)\"" "$ZSH_PROFILE"; then
                echo 'eval "$(/usr/local/bin/brew shellenv)"' >> "$ZSH_PROFILE"
                log_info "Homebrew path added to $ZSH_PROFILE"
            fi
        fi
    else
        log_info "Homebrew is already installed."
    fi
}

# ---------------------------
# Package Installation
# ---------------------------

install_packages() {
    if [[ -f "$BREW_FILE" ]]; then
        log_info "Installing packages from Brewfile..."
        if ! brew bundle --file="$BREW_FILE"; then
            log_warning "Some packages failed to install. Please check the Brewfile for errors."
        fi
    else
        log_warning "No Brewfile found at $BREW_FILE"
    fi
}

# ---------------------------
# Dotbot Installation
# ---------------------------

run_dotbot() {
    if [[ -f "$DOTBOT_INSTALL" ]]; then
        log_info "Running Dotbot to symlink configuration files..."
        "$DOTBOT_INSTALL" || log_error "Dotbot installation failed."
    else
        log_error "Dotbot install script not found at $DOTBOT_INSTALL"
    fi
}

# ---------------------------
# Git Configuration
# ---------------------------

setup_git() {
    log_info "Configuring Git..."
    git config --global user.name "$GIT_USER_NAME"
    git config --global user.email "$GIT_USER_EMAIL"
    log_info "Git configured for user: $GIT_USER_NAME <$GIT_USER_EMAIL>"
}

# ---------------------------
# User Input Collection
# ---------------------------

get_user_inputs() {
    log_info "Gathering user inputs for configuration..."
    
    # Collect Git User Name
    while true; do
        read -r "GIT_USER_NAME?Enter Git user name: "
        if [[ -n "$GIT_USER_NAME" ]]; then
            break
        else
            log_warning "Git user name cannot be empty."
        fi
    done
    
    # Collect Git User Email with Validation
    while true; do
        read -r "GIT_USER_EMAIL?Enter Git user email: "
        if [[ "$GIT_USER_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
            break
        else
            log_warning "Please enter a valid email address."
        fi
    done
}

# ---------------------------
# Main Installation Process
# ---------------------------

main() {
    log_info "Starting machine bootstrap process..."
    
    # Gather user inputs
    get_user_inputs
    
    # Perform system check
    check_macos
    
    # Check for required dependencies
    check_dependencies
    
    # Execute installation steps
    install_homebrew
    install_packages
    run_dotbot
    setup_git
    
    log_info "Bootstrap complete! 🎉"
}

# ---------------------------
# Execute Main Function
# ---------------------------

main "$@"
