#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# ---------------------------
# Request Sudo Privileges
# ---------------------------

# Prompt for sudo password upfront
sudo -v

# Keep-alive: update existing `sudo` time stamp until script has finished
while true; do
    sudo -n true
    sleep 60
    kill -0 "$" || exit
done 2>/dev/null &

# ---------------------------
# Constants and Configuration
# ---------------------------

# Set Dotfiles directory
DOTFILES_DIR="$HOME/.dotfiles"
BREW_FILE="$DOTFILES_DIR/Brewfile"
DOTBOT_INSTALL="$DOTFILES_DIR/install"
ZSH_PROFILE="$DOTFILES_DIR/.zsh/.zprofile"

# ---------------------------
# Color Output Setup
# ---------------------------

COLORS_INFO="\e[32m"
COLORS_WARNING="\e[33m"
COLORS_ERROR="\e[31m"
COLORS_RESET="\e[0m"

# ---------------------------
# Helper Functions
# ---------------------------

# Logging Functions
log_info() { echo -e "${COLORS_INFO}[INFO] $1${COLORS_RESET}"; }
log_warning() { echo -e "${COLORS_WARNING}[WARNING] $1${COLORS_RESET}"; }
log_error() { echo -e "${COLORS_ERROR}[ERROR] $1${COLORS_RESET}"; }

# ---------------------------
# System Check
# ---------------------------

check_linux() {
    if [[ "$(uname)" != "Linux" ]]; then
        log_error "🚫 This script is designed for Linux."
        exit 1
    else
        log_info "✅ Operating system is Linux."
    fi
}

# Run system check
check_linux

# ---------------------------
# Install Zsh
# ---------------------------

if ! command -v zsh &> /dev/null; then
    log_info "Installing Zsh..."
    sudo apt update && sudo apt install -y zsh
else
    log_info "✅ Zsh is already installed."
fi

# ---------------------------
# Change shell to zsh
# ---------------------------

if [[ "$SHELL" != "$(which zsh)" ]]; then
  log_info "Changing shell to zsh..."
  chsh -s "$(which zsh)"
  log_info "✅ SUCCESS! Shell set to zsh."
else
  log_info "✅ Default shell is already set to zsh."
fi

# ---------------------------
# Install Homebrew for Linux
# ---------------------------

if ! command -v brew &> /dev/null; then
  log_info "Installing Homebrew..."
  /bin/bash -c "$(curl -k -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
      log_error "🚫 Homebrew installation failed due to SSL issues. Trying again with insecure options..."
      sudo apt install -y --no-install-recommends ca-certificates curl
      /bin/bash -c "$(curl -k -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  }

  # Add Homebrew to the PATH
  echo 'eval "$($(brew --prefix)/bin/brew shellenv)"' >> ~/.zprofile
  eval "$($(brew --prefix)/bin/brew shellenv)"

  # Verify Homebrew is in PATH
  if command -v brew > /dev/null; then
      log_info "✅ Homebrew is successfully installed and added to PATH."
      log_info "🔍 Current PATH: $PATH"
  else
      log_error "🚫 Homebrew installation failed or is not in PATH."
      exit 1
  fi
else
  log_info "🍺 Homebrew is already installed."
  log_info "🔍 Current PATH: $PATH"
fi

# ---------------------------
# Install brew packages from Brewfile (no casks)
# ---------------------------

if [[ -f "$BREW_FILE" ]]; then
  log_info "Installing brew packages from Brewfile..."
  brew bundle --file="$BREW_FILE" --no-upgrade --no-cask || log_error "🚫 Failed to install brew packages."
else
  log_warning "Brewfile not found at $BREW_FILE"
fi

# ---------------------------
# Git Configuration
# ---------------------------

setup_git() {
    if [[ -z "$GIT_USER_NAME" || -z "$GIT_USER_EMAIL" ]]; then
        log_warning "⚠️ Git user name or email not set. Skipping Git configuration."
        return
    fi
    
    log_info "🛠️ Configuring Git..."
    git config --global user.name "$GIT_USER_NAME" || log_warning "⚠️ Failed to set Git user name."
    git config --global user.email "$GIT_USER_EMAIL" || log_warning "⚠️ Failed to set Git user email."
    log_info "✅ Git configured for user: $GIT_USER_NAME <$GIT_USER_EMAIL>"
}

# ---------------------------
# User Input Collection
# ---------------------------

get_user_inputs() {
    log_info "📝 Gathering user inputs for configuration..."
    
    # Collect Git User Name
    while true; do
        read -r -p "🔍 Enter Git user name: " GIT_USER_NAME
        if [[ -n "$GIT_USER_NAME" ]]; then
            break
        else
            log_warning "⚠️ Git user name cannot be empty."
        fi
    done
    
    # Collect Git User Email with Validation
    while true; do
        read -r -p "📧 Enter Git user email: " GIT_USER_EMAIL
        if [[ "$GIT_USER_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
            break
        else
            log_warning "⚠️ Please enter a valid email address."
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
    )

    for link in "${links[@]}"; do
        if [[ -e "$link" || -L "$link" ]]; then
            log_info "🗑️ Removing existing link or file: $link"
            rm -rf "$link" || log_warning "⚠️ Failed to remove $link"
        fi

        # Ensure parent directory exists
        local parent_dir="$(dirname "$link")"
        if [[ ! -d "$parent_dir" ]]; then
            log_info "📁 Creating parent directory: $parent_dir"
            mkdir -p "$parent_dir" || log_warning "⚠️ Failed to create directory: $parent_dir"
        fi
    done
}

# ---------------------------
# Dotbot Installation
# ---------------------------

run_dotbot() {
    if [[ -f "$DOTBOT_INSTALL" ]]; then
        log_info "🔗 Running Dotbot to symlink configuration files..."
        
        # Handle existing files before running Dotbot
        handle_existing_links
        
        # Run Dotbot with verbose output
        "$DOTBOT_INSTALL" -v || log_warning "⚠️ Dotbot installation failed."
    else
        log_error "🚫 Dotbot install script not found at $DOTBOT_INSTALL"
    fi
}

# ---------------------------
# Main Installation Process
# ---------------------------

main() {
    log_info "🚀 Starting machine bootstrap process..."
    
    # Gather user inputs
    get_user_inputs
    
    # Perform system check
    check_linux
    
    # Execute installation steps
    run_dotbot
    setup_git

    # Source zshrc to apply changes
    if [[ -f "$ZSH_PROFILE" ]]; then
        log_info "🎉 Bootstrap complete! Applying changes..."
        source "$ZSH_PROFILE"
    else
        log_warning "⚠️ No .zshrc found after installation."
    fi
}

# ---------------------------
# Execute Main Function
# ---------------------------

main "$@"
