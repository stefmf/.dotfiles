#!/usr/bin/env zsh

# ─── Strict mode ──────────────────────────────────────────────────────────────
setopt errexit nounset pipefail

# ---------------------------
# Request Sudo Privileges
# ---------------------------

# Prompt for sudo password upfront
sudo -v

# ─── Error Handler ────────────────────────────────────────────────────────────
error_exit() {
  log_error "❌ Bootstrap failed at line $LINENO: $*"
  exit 1
}
trap 'error_exit "Unexpected error"' ERR

# ─── Keep‐alive sudo ──────────────────────────────────────────────────────────
function keep_sudo {
  while true; do
    sudo -n true
    sleep 60
    kill -0 "$$" || exit
  done
}
keep_sudo & 
KEEPALIVE_PID=$!
trap 'kill $KEEPALIVE_PID' EXIT

# ---------------------------
# Constants and Configuration
# ---------------------------

# Set Dotfiles directory
typeset -r DOTFILES_DIR="$HOME/.dotfiles"
typeset -r BREW_FILE="$DOTFILES_DIR/.bootstrap/macos/Brewfile"
typeset -r DOTBOT_INSTALL="$DOTFILES_DIR/install"
typeset -r ZSH_PROFILE="$DOTFILES_DIR/.zsh/.zprofile"
typeset -r DOCK_CONFIG="$DOTFILES_DIR/.config/dock/dock_config.zsh"

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
log_warning() { print -P "${COLORS[warning]}[WARNING] $1%f"; }
log_error() { print -P "${COLORS[error]}[ERROR] $1%f"; }

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
        local special_casks=("parallels" "adobe-acrobat-pro" "microsoft-auto-update" "windows-app")
        log_info "🔧 Installing specific casks that require elevated permissions..."
        for cask in "${special_casks[@]}"; do
            if ! brew search --casks "$cask" &> /dev/null; then
                log_info "❌ Cask '$cask' does not exist in the Homebrew repository. Skipping..."
                continue
            fi
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
        log_info "📦 Installing remaining packages from Brewfile..."
        brew bundle --file="$BREW_FILE" || {
            log_warning "⚠️ Some packages failed to install."
        }
        # Font check and reboot prompt
        if brew list --cask | grep -q font-jetbrains-mono-nerd-font; then
            if ls /Library/Fonts | grep -iq jetbrains; then
                log_info "✅ JetBrains Mono Nerd Font is installed and present in system fonts."
            elif ls ~/Library/Fonts | grep -iq jetbrains; then
                log_info "✅ JetBrains Mono Nerd Font is installed in user fonts."
            else {
                log_warning "⚠️ JetBrains Mono Nerd Font cask installed, but font files not found in system/user fonts."
            fi
            log_info "ℹ️ If you do not see glyphs, try rebooting or reselecting the font in your terminal/editor."
        else
            log_warning "⚠️ JetBrains Mono Nerd Font is not installed."
        fi
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
    
    # Get current CLI tools version
    current_version=$(pkgutil --pkg-info=com.apple.pkg.CLTools_Executables 2>/dev/null | grep version | awk '{print $2}')
    if [[ -z "$current_version" ]]; then
        log_warning "⚠️ Unable to determine current Command Line Tools version."
        log_info "🔧 Initiating installation of Command Line Tools..."
        xcode-select --install
        
        log_info "⏳ Waiting for Command Line Tools installation to complete..."
        local wait_message="⏳ Still waiting for Command Line Tools to install"
        until xcode-select --print-path &> /dev/null; do
            sleep 10
            wait_message+="."
            log_info "$wait_message"
        done
        log_info "✅ Command Line Tools installation completed."
        return
    fi
    
    # Extract major.minor version
    current_major_minor=$(echo "$current_version" | cut -d. -f1,2)
    required_version="16.0"
    
    log_info "📦 Current Command Line Tools version: $current_major_minor"
    log_info "📦 Required minimum version: $required_version"
    
    if [[ "$current_major_minor" < "$required_version" ]]; then
        log_info "🔄 Command Line Tools version is below the required minimum. Attempting to update..."
        
        # Check for available updates
        softwareupdate_output=$(softwareupdate -l)
        log_info "📄 Software Update Output:\n$softwareupdate_output"
        
        # Extract the exact name of the Command Line Tools update using sed to avoid awk errors
        command_line_tools_update=$(echo "$softwareupdate_output" | grep -i "Command Line Tools for Xcode" | head -n 1 | sed 's/^\* Label: //')
        
        if [[ -n "$command_line_tools_update" ]]; then
            log_info "🔄 Found update for Command Line Tools: $command_line_tools_update"
            log_info "🔧 Initiating update for Command Line Tools..."
            sudo softwareupdate -i "$command_line_tools_update" --verbose
            log_info "✅ Command Line Tools update completed."
        else
            log_info "🛠️ No update found via softwareupdate. Reinstalling Command Line Tools to ensure they are current..."
            sudo rm -rf /Library/Developer/CommandLineTools
            log_info "🗑️ Removed existing Command Line Tools."
            xcode-select --install
            
            log_info "⏳ Waiting for Command Line Tools installation to complete..."
            local wait_message="⏳ Still waiting for Command Line Tools to install"
            until xcode-select --print-path &> /dev/null; do
                sleep 10
                wait_message+="."
                log_info "$wait_message"
            done
            log_info "✅ Command Line Tools installation completed."
        fi
        
        # Re-check the version after update
        current_version=$(pkgutil --pkg-info=com.apple.pkg.CLTools_Executables 2>/dev/null | grep version | awk '{print $2}')
        current_major_minor=$(echo "$current_version" | cut -d. -f1,2)
        log_info "📦 Updated Command Line Tools version: $current_major_minor"
        
        if [[ "$current_major_minor" < "$required_version" ]]; then
            log_warning "⚠️ Command Line Tools are still below the required version ($required_version). Please update them manually."
        else
            log_info "✅ Command Line Tools meet the required version ($required_version)."
        fi
    else
        log_info "✅ Command Line Tools are up to date (version: $current_major_minor)."
    fi
}

# -------------------------------------------------------------------
# Preflight checks: OS, Xcode CLI, dependencies
preflight_checks() {
    log_info "🔍 Running preflight checks..."
    check_macos
    update_command_line_tools
    check_dependencies
}

# -------------------------------------------------------------------
# Homebrew installation
install_homebrew() {
    # Ensure the ZSH_PROFILE exists
    mkdir -p "$(dirname \"$ZSH_PROFILE\")"
    touch "$ZSH_PROFILE"
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

# -------------------------------------------------------------------
# Brew packages & casks
install_brew_packages() {
    install_packages  # existing logic
}

# -------------------------------------------------------------------
# Font verification (no reboot needed)
install_fonts() {
    if brew list --cask | grep -q font-jetbrains-mono-nerd-font; then
        log_info "✅ JetBrains Mono Nerd Font installed. Restart apps to apply."
    else
        log_warning "⚠️ JetBrains Mono Nerd Font not found. Add to Brewfile if needed."
    fi
}

# -------------------------------------------------------------------
# GitHub authentication & git config
github_auth_and_git_config() {
    authenticate_github  # existing logic
}

# -------------------------------------------------------------------
# Enable core services (Tailscale, dnsmasq)
enable_services() {
    log_info "🔧 Starting core services..."
    if command -v tailscaled &>/dev/null; then
        sudo tailscaled install-system-daemon && log_info "✅ Tailscale system daemon installed"
    else
        log_warning "tailscaled not found; skipping Tailscale service"
    fi

    if brew list dnsmasq &>/dev/null; then
        sudo brew services start dnsmasq && log_info "✅ dnsmasq started via brew services"
    else
        log_warning "dnsmasq missing; skipping dnsmasq service"
    fi
}

# -------------------------------------------------------------------
# Configure DNS for dnsmasq/MagicDNS
configure_dns() {
    log_info "🌐 Configuring system DNS to 127.0.0.1 for dnsmasq..."
    networksetup -listallnetworkservices 2>/dev/null | sed '1d' | while IFS= read -r svc; do
        svc="${svc#\*}"; svc="$(echo "$svc" | xargs)"
        [[ -z "$svc" || "$svc" == *"VPN"* || "$svc" == "Tailscale"* ]] && continue
        sudo networksetup -setdnsservers "$svc" 127.0.0.1 \
            && log_info "✅ DNS set for '$svc'" \
            || log_warning "Failed to set DNS for '$svc'"
    done
    log_info "📎 DNS setup complete."
}

# -------------------------------------------------------------------
# Enable Touch ID for sudo (persistent)
enable_touchid_for_sudo() {
    log_info "🔐 Configuring Touch ID authentication for sudo..."
    # Remove legacy symlink if present
    if [[ -L "/etc/pam.d/sudo" ]]; then
        log_warning "Removing existing /etc/pam.d/sudo symlink"
        sudo rm "/etc/pam.d/sudo"
    fi

    if [[ -f "/etc/pam.d/sudo_local.template" ]]; then
        # macOS 14+ (Sonoma)
        if [[ ! -f "/etc/pam.d/sudo_local" ]]; then
            sudo cp "/etc/pam.d/sudo_local.template" "/etc/pam.d/sudo_local"
            log_info "Copied sudo_local template"
        fi
        sudo sed -i '' 's/^#auth[[:space:]]\+sufficient[[:space:]]\+pam_tid.so/auth       sufficient     pam_tid.so/' "/etc/pam.d/sudo_local"
        log_info "✅ Enabled Touch ID in /etc/pam.d/sudo_local"
        # Ensure main sudo includes sudo_local
        if [[ ! -f "/etc/pam.d/sudo" ]]; then
            log_warning "/etc/pam.d/sudo missing; restoring default with sudo_local include"
            sudo tee "/etc/pam.d/sudo" > /dev/null <<-'PAM'
# sudo: auth account password session
auth       include        sudo_local
auth       sufficient     pam_smartcard.so
auth       required       pam_opendirectory.so
account    required       pam_permit.so
password   required       pam_deny.so
session    required       pam_permit.so
PAM
            log_info "✅ Restored /etc/pam.d/sudo"
        fi
    else
        # Older macOS
        if ! grep -q "pam_tid.so" "/etc/pam.d/sudo"; then
            sudo sed -i.bak $'2i\\\nauth       sufficient     pam_tid.so\\\n' "/etc/pam.d/sudo"
            log_info "✅ Added Touch ID to /etc/pam.d/sudo (backup in /etc/pam.d/sudo.bak)"
        else
            log_info "Touch ID already enabled in /etc/pam.d/sudo"
        fi
    fi
}

# -------------------------------------------------------------------
# Symlink dotfiles via Dotbot
setup_dotfiles() {
    log_info "🔗 Setting up dotfiles with Dotbot..."
    handle_existing_links
    "$DOTBOT_INSTALL" -v || log_warning "⚠️ Dotbot failed."
}

# -------------------------------------------------------------------
# Authenticate with GitHub via gh CLI
authenticate_github() {
    if command -v gh &>/dev/null; then
        log_info "🔑 Logging in to GitHub with gh CLI..."
        gh auth login --hostname github.com --git-protocol ssh
        if name="$(gh api user --jq '.name')" && email="$(gh api user --jq '.email')" ; then
            git config --global user.name "$name"
            git config --global user.email "$email"
            log_info "✅ Set Git author to: $name <$email>"
        else
            log_warning "Couldn’t fetch name/email from GitHub profile; please set manually with git config"
        fi
    else
        log_warning "⚠️ gh CLI not installed; skipping GitHub login"
    fi
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

# -------------------------------------------------------------------
# Configure macOS Dock
configure_dock() {
    log_info "⚙️ Configuring macOS Dock..."
    source "$DOCK_CONFIG"
}

# -------------------------------------------------------------------
# Final message
finalize_bootstrap() {
    log_info "🎉 macOS bootstrap complete!"
}

# ---------------------------
# Main Installation Process
# ---------------------------
main() {
    log_info "🚀 Starting macOS bootstrap..."
    preflight_checks
    install_homebrew
    install_brew_packages
    install_fonts
    github_auth_and_git_config
    enable_services
    configure_dns
    enable_touchid_for_sudo
    setup_dotfiles
    configure_dock
    finalize_bootstrap
}

main "$@"