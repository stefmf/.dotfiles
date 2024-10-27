#!/usr/bin/env zsh

# Enable strict error handling
setopt ERR_EXIT   # Exit on error
setopt PIPE_FAIL  # Exit on pipe failure
setopt UNSET      # Exit on undefined variable

# ---------------------------
# Request Sudo Privileges
# ---------------------------

# Prompt for sudo password upfront
sudo -v

# Keep-alive: update existing `sudo` time stamp until script has finished
while true; do sudo -n true; sleep 60; kill -0 "$$" || exit; done 2>/dev/null &

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
# Privacy & Security Settings Helper
# ---------------------------

open_privacy_settings() {
    log_info "Opening Privacy & Security settings for App Management..."
    osascript -e 'tell application "System Settings"
        activate
        delay 1
        reveal anchor "Privacy_AppBundles" of pane id "com.apple.settings.PrivacySecurity.extension"
    end tell'
    
    log_info "Please enable App Management in Privacy & Security settings."
    log_info "Once enabled, press Enter to continue with the installation..."
    read -r "?Press Enter after enabling App Management..."
}

# ---------------------------
# Package Installation
# ---------------------------

install_packages() {
    if [[ -f "$BREW_FILE" ]]; then
        log_info "Installing packages from Brewfile..."

        # Install regular packages first
        brew bundle --file="$BREW_FILE" --except=cask || {
            log_warning "Some packages failed to install."
            return 1
        }

        # Handle Parallels installation separately
        if grep -q "cask \"parallels\"" "$BREW_FILE"; then
            log_info "Preparing to install Parallels..."
            open_privacy_settings
            log_info "Installing Parallels..."
            brew install --cask parallels || log_warning "Parallels installation failed"
        fi

        # Install other casks that require sudo
        log_info "Installing remaining casks that require sudo..."
        local casks=("adobe-acrobat-pro" "microsoft-auto-update" "windows-app")
        for cask in "${casks[@]}"; do
            if [[ "$cask" != "parallels" ]]; then
                log_info "Installing $cask with sudo..."
                echo "$SUDO_PASSWORD" | sudo -S brew install --cask "$cask" || log_warning "$cask installation failed"
            fi
        done
    else
        log_warning "No Brewfile found at $BREW_FILE"
        return 1
    fi
}

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
# Xcode Command Line Tools Update
# ---------------------------

update_command_line_tools() {
    if ! xcode-select --print-path &> /dev/null; then
        log_info "Installing Command Line Tools..."
        xcode-select --install
    else
        log_info "Command Line Tools already installed. Checking for updates..."
        softwareupdate -l | grep -q "Command Line Tools" && {
            log_info "Updating Command Line Tools..."
            sudo softwareupdate -i "Command Line Tools"
        } || {
            log_info "No updates found for Command Line Tools. Reinstalling to ensure they are up to date..."
            sudo rm -rf /Library/Developer/CommandLineTools
            sudo xcode-select --install
        }
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
# Dotbot Installation
# ---------------------------

run_dotbot() {
    if [[ -f "$DOTBOT_INSTALL" ]]; then
        log_info "Running Dotbot to symlink configuration files..."
        
        # Handle existing files before running Dotbot
        handle_existing_links
        
        # Run Dotbot with verbose output
        "$DOTBOT_INSTALL" -v || log_error "Dotbot installation failed."
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

    # Collect Sudo Password
    while true; do
        read -rs "SUDO_PASSWORD?Enter your password for sudo commands: "
        echo
        if [[ -n "$SUDO_PASSWORD" ]]; then
            break
        else
            log_warning "Password cannot be empty."
        fi
    done
}

# ---------------------------
# Handle Existing Links or Files
# ---------------------------

handle_existing_links() {
    local links=(
        "$HOME/.zshrc"
        "$HOME/.config"
        "$HOME/.vscode"
        "$HOME/Library/Application Support/Sublime Text/Packages/User"
    )

    for link in "${links[@]}"; do
        if [[ -e "$link" || -L "$link" ]]; then
            log_info "Removing existing link or file: $link"
            rm -rf "$link"
        fi

        # Ensure parent directory exists
        local parent_dir="${link:h}"
        if [[ ! -d "$parent_dir" ]]; then
            log_info "Creating parent directory: $parent_dir"
            mkdir -p "$parent_dir"
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
    
    # Update Xcode Command Line Tools
    update_command_line_tools
    
    # Check for required dependencies
    check_dependencies
    
    # Execute installation steps
    install_homebrew || return 1
    install_packages || return 1
    run_dotbot || return 1
    setup_git || return 1

    # Source zshrc to apply changes
    if [[ -f "$ZSH_PROFILE" ]]; then
        log_info "Bootstrap complete! 🎉 Applying changes..."
        source "$ZSH_PROFILE"
    else
        log_warning "No .zshrc found after installation"
        return 1
    fi
}

# ---------------------------
# Execute Main Function
# ---------------------------

main "$@"