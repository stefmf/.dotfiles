#!/usr/bin/env zsh

# Enable strict error handling
setopt PIPE_FAIL  # Exit on pipe failure
setopt UNSET      # Exit on undefined variable

# ---------------------------
# Request Sudo Privileges
# ---------------------------

# Prompt for sudo password upfront
sudo -v

# Keep-alive: update existing `sudo` time stamp until script has finished
while true; do
    sudo -n true
    sleep 60
    kill -0 "$$" || exit
done 2>/dev/null &

# ---------------------------
# Constants and Configuration
# ---------------------------

# Set Dotfiles directory
DOTFILES_DIR="$HOME/.dotfiles"
BREW_FILE="$DOTFILES_DIR/Brewfile"
DOTBOT_INSTALL="$DOTFILES_DIR/install"
ZSH_PROFILE="$DOTFILES_DIR/.zsh/.zshrc"

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
log_info() { print -P "${COLORS[info]}[INFO] $1%f"; }
log_warning() { print -P "${COLORS[warning]}[WARNING] ⚠️ $1%f"; }
log_error() { print -P "${COLORS[error]}[ERROR] ❌ $1%f"; }

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
    
    log_info "📌 Important: Please enable App Management in the Privacy & Security settings."
    log_info "🔒 This is necessary for installing certain applications that require elevated permissions."
    log_info "✅ Once enabled, press Enter to continue with the installation."
    read -r "?Press Enter after enabling App Management to continue..."
}

# ---------------------------
# Package Installation
# ---------------------------

install_packages() {
    if [[ -f "$BREW_FILE" ]]; then
        log_info "📦 Starting package installation process..."
        
        # Define special casks that need special handling
        local special_casks=("parallels" "adobe-acrobat-pro" "microsoft-auto-update" "windows-app")
        
        # Step 1: Handle special casks that require elevated permissions
        log_info "🔧 Installing specific casks that require elevated permissions..."
        
        for cask in "${special_casks[@]}"; do
            if brew list --cask "$cask" &> /dev/null; then
                log_info "✅ Cask '$cask' is already installed. Skipping..."
                continue
            fi
            
            if [[ "$cask" == "parallels" ]]; then
                log_info "🚀 Preparing to install Parallels..."
                open_privacy_settings
                log_info "📦 Installing Parallels..."
                brew install --cask parallels --verbose || log_warning "❌ Parallels installation failed"
            else
                log_info "📦 Installing $cask..."
                brew install --cask "$cask" --verbose || log_warning "❌ $cask installation failed"
            fi
        done
        
        # Step 2: Install the rest of the packages from Brewfile
        log_info "📦 Installing remaining packages from Brewfile..."
        
        brew bundle --file="$BREW_FILE" || {
            log_warning "⚠️ Some packages failed to install."
        }
        
        log_info "✅ Package installation process completed."
    else
        log_warning "⚠️ No Brewfile found at $BREW_FILE. Skipping package installation."
    fi
}

# ---------------------------
# Dependency Checks
# ---------------------------

check_dependencies() {
    local dependencies=("git" "curl")
    for cmd in "${dependencies[@]}"; do
        if ! command -v "$cmd" > /dev/null; then
            log_error "🚫 Dependency '$cmd' is not installed. Please install it and rerun the script."
        else
            log_info "✅ Dependency '$cmd' is installed."
        fi
    done
}

# ---------------------------
# System Check
# ---------------------------

check_macos() {
    if [[ "$(uname)" != "Darwin" ]]; then
        log_error "🚫 This script is designed for macOS."
    else
        log_info "✅ Operating system is macOS."
    fi
}

# ---------------------------
# Xcode Command Line Tools Update
# ---------------------------

update_command_line_tools() {
    log_info "🔍 Checking for Xcode Command Line Tools updates..."
    
    softwareupdate_output=$(softwareupdate -l)
    log_info "📄 Software Update Output:\n$softwareupdate_output"
    
    # Extract the exact name of the Command Line Tools update
    command_line_tools_update=$(echo "$softwareupdate_output" | grep -i "Command Line Tools" | head -n 1 | awk -F'* ' '{print $2}')
    
    if [[ -n "$command_line_tools_update" ]]; then
        log_info "🔄 Found update for Command Line Tools: $command_line_tools_update"
        log_info "🔧 Initiating update for Command Line Tools..."
        sudo softwareupdate -i "$command_line_tools_update" --verbose
        log_info "✅ Command Line Tools update completed."
    else
        log_info "🛠️ Command Line Tools already up to date. Reinstalling to ensure they are current..."
        sudo rm -rf /Library/Developer/CommandLineTools
        log_info "🗑️ Removed existing Command Line Tools."
        xcode-select --install
        
        log_info "⏳ Waiting for Command Line Tools installation to complete..."
        # Wait until Command Line Tools are installed
        until xcode-select --print-path &> /dev/null; do
            sleep 15
            log_info "⏳ Still waiting for Command Line Tools to install..."
            while ! xcode-select --print-path &> /dev/null; do
                printf "."
                sleep 10
            done
            echo ""  # Move to the next line after the dots
        done
        log_info "✅ Command Line Tools installation completed."
# ---------------------------
# Homebrew Installation
# ---------------------------

install_homebrew() {
    if ! command -v brew > /dev/null; then
        log_info "🍺 Installing Homebrew..."
        if command -v curl > /dev/null; then
            /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        else
            log_error "🚫 'curl' is required but not installed. Aborting."
        fi
        
        # Configure Homebrew environment
        if [[ "$(uname -m)" == "arm64" ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
            if ! grep -q "eval \"\$(/opt/homebrew/bin/brew shellenv)\"" "$ZSH_PROFILE"; then
                echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$ZSH_PROFILE"
                log_info "✅ Homebrew path added to $ZSH_PROFILE"
            fi
        else
            eval "$(/usr/local/bin/brew shellenv)"
            if ! grep -q "eval \"\$(/usr/local/bin/brew shellenv)\"" "$ZSH_PROFILE"; then
                echo 'eval "$(/usr/local/bin/brew shellenv)"' >> "$ZSH_PROFILE"
                log_info "✅ Homebrew path added to $ZSH_PROFILE"
            fi
        fi

        # Verify Homebrew is in PATH
        if command -v brew > /dev/null; then
            log_info "✅ Homebrew is successfully installed and added to PATH."
            log_info "🔍 Current PATH: $PATH"
        else
            log_error "🚫 Homebrew installation failed or is not in PATH."
        fi
    else
        log_info "🍺 Homebrew is already installed."
        log_info "🔍 Current PATH: $PATH"
    fi
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
        read -r "GIT_USER_NAME?🔍 Enter Git user name: "
        if [[ -n "$GIT_USER_NAME" ]]; then
            break
        else
            log_warning "⚠️ Git user name cannot be empty."
        fi
    done
    
    # Collect Git User Email with Validation
    while true; do
        read -r "GIT_USER_EMAIL?📧 Enter Git user email: "
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
        "$HOME/Library/Application Support/Sublime Text/Packages/User"
    )

    for link in "${links[@]}"; do
        if [[ -e "$link" || -L "$link" ]]; then
            log_info "🗑️ Removing existing link or file: $link"
            rm -rf "$link" || log_warning "⚠️ Failed to remove $link"
        fi

        # Ensure parent directory exists
        local parent_dir="${link:h}"
        if [[ ! -d "$parent_dir" ]]; then
            log_info "📁 Creating parent directory: $parent_dir"
            mkdir -p "$parent_dir" || log_warning "⚠️ Failed to create directory: $parent_dir"
        fi
    done
}

# ---------------------------
# Main Installation Process
# ---------------------------

main() {
    log_info "🚀 Starting machine bootstrap process..."
    
    # Gather user inputs
    get_user_inputs
    
    # Perform system check
    check_macos
    
    # Update Xcode Command Line Tools
    update_command_line_tools
    
    # Check for required dependencies
    check_dependencies
    
    # Execute installation steps
    install_homebrew
    run_dotbot
    install_packages
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
