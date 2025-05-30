#!/usr/bin/env zsh

# ─── Strict mode ──────────────────────────────────────────────────────────────
setopt errexit nounset pipefail

# Prevent running the script as root
if [[ $EUID -eq 0 ]]; then
    echo "[ERROR] Do not run this script as root. Please run as your regular user without sudo." >&2
    exit 1
fi

# ---------------------------
# Request Sudo Privileges
# ---------------------------

# Prompt for sudo password upfront
sudo -v

# ---------------------------
# Color Output Setup (define logging before error handler)
autoload -U colors && colors
typeset -A COLORS=(
    [info]=$fg[green]
    [warning]=$fg[yellow]
    [error]=$fg[red]
    [debug]=$fg[blue]
)

# Logging Functions
log_info() { print -P "${COLORS[info]}[INFO] $1%f"; }
log_warning() { print -P "${COLORS[warning]}[WARNING] $1%f"; }
log_error() { print -P "${COLORS[error]}[ERROR] $1%f"; }

# ─── Error Handler ────────────────────────────────────────────────────────────
error_exit() {
  echo "[ERROR] Bootstrap failed at line $LINENO: $*" >&2
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
# ensure kill trap ignores missing process
trap 'kill $KEEPALIVE_PID 2>/dev/null || true' EXIT

# ---------------------------
# Constants and Configuration
# ---------------------------

# Set Dotfiles directory
typeset -r DOTFILES_DIR="$HOME/.dotfiles"
typeset -r BREW_FILE="$DOTFILES_DIR/.bootstrap/macos/Brewfile"
typeset -r DOTBOT_INSTALL="$DOTFILES_DIR/install"
typeset -r ZSH_PROFILE="$DOTFILES_DIR/.zsh/.zprofile"
typeset -r DOCK_CONFIG="$DOTFILES_DIR/.config/dock/dock_config.zsh"

# Initialize a flag to track if dotfiles setup failed
typeset DOTBOT_FAILED=0

# ---------------------------
# Helper Functions
# ---------------------------

# If running as root, warn only (Homebrew requires non-root for installation)
if [[ $EUID -eq 0 ]]; then
    log_warning "⚠️ Running as root. Some operations may fail (e.g., Homebrew installation)."
fi

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
    read "?Press Enter after enabling App Management to continue..." dummy
}

# ---------------------------
# Package Installation
# ---------------------------

install_packages() {
    if [[ -f "$BREW_FILE" ]]; then
        log_info "📦 Starting package installation process..."
        # Prompt once for sudo to cover all special casks
        log_info "🔒 Requesting sudo access for special casks installation (you may be prompted)"
        sudo -v

        # Install special casks requiring elevated permissions
        log_info "🔧 Installing special casks..."
        local special_casks=("parallels" "adobe-acrobat-pro" "microsoft-auto-update" "windows-app")
        for cask in "${special_casks[@]}"; do
            if ! brew search --casks "$cask" &>/dev/null; then
                log_warning "Cask '$cask' not found; skipping."
                continue
            fi
            if brew list --cask "$cask" &>/dev/null; then
                log_info "Cask '$cask' already installed."
                continue
            fi
            if [[ "$cask" == "parallels" ]]; then
                log_info "🚀 Preparing to install Parallels..."
                open_privacy_settings
            fi
            log_info "📦 Installing $cask..."
            brew install --cask "$cask" --verbose || log_warning "Installation of $cask failed"
        done

        # Install all remaining Brewfile packages
        log_info "📦 Installing Brewfile packages..."
        brew bundle --file="$BREW_FILE" || log_warning "Some Brewfile packages failed to install."

        log_info "✅ Package installation completed."
    else
        log_warning "No Brewfile found at $BREW_FILE; skipping package installation."
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

# ---------------------------
# Ensure dotfiles directory is writable
ensure_dotfiles_writable() {
  log_info "🔧 Checking writability of $DOTFILES_DIR"
  if [[ -w "$DOTFILES_DIR" ]]; then
    log_info "✅ Dotfiles directory is already writable by $(id -un)"
  else
    log_warning "⚠️ Dotfiles directory not writable by $(id -un). Attempting to fix ownership."
    if sudo chown -R "$(id -un):$(id -gn)" "$DOTFILES_DIR"; then
      log_info "✅ Ownership of $DOTFILES_DIR fixed to $(id -un):$(id -gn)"
    else
      log_error "❌ Failed to fix ownership of $DOTFILES_DIR. Please adjust manually."
    fi
  fi
}

# -------------------------------------------------------------------
# Preflight checks: OS, Xcode CLI, dependencies
preflight_checks() {
    log_info "🔍 Running preflight checks..."
    check_macos
    ensure_dotfiles_writable
    update_command_line_tools
    check_dependencies
}

# -------------------------------------------------------------------
# Homebrew installation
install_homebrew() {
    # Ensure the ZSH_PROFILE exists
    log_info "🔧 Creating directory for ZSH profile: $(dirname "$ZSH_PROFILE")"
    if mkdir -p "$(dirname "$ZSH_PROFILE")"; then
      log_info "✅ Directory ensured: $(dirname "$ZSH_PROFILE")"
    else
      log_warning "⚠️ Could not create directory $(dirname "$ZSH_PROFILE"). Check permissions."
    fi
    log_info "🔧 Ensuring profile file exists: $ZSH_PROFILE"
    if touch "$ZSH_PROFILE"; then
      log_info "✅ Profile file created/existed: $ZSH_PROFILE"
    else
      log_warning "⚠️ Could not create profile file $ZSH_PROFILE. Check permissions."
    fi
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
# Font verification
install_fonts() {
    log_info "🔧 Ensuring JetBrains Mono Nerd Font is installed…"

    # 1. Install via Homebrew if missing
    if ! brew list --cask font-jetbrains-mono-nerd-font &>/dev/null; then
        log_info "📦 Installing font-jetbrains-mono-nerd-font via Homebrew…"
        brew install --cask font-jetbrains-mono-nerd-font \
            || log_error "❌ Failed to install font-jetbrains-mono-nerd-font"
    else
        log_info "✅ font-jetbrains-mono-nerd-font already installed"
    fi

    # 2. Copy font files into user's Fonts directory
    log_info "📂 Copying font files to ~/Library/Fonts…"
    mkdir -p "$HOME/Library/Fonts"
    caskroom_dir="$(brew --prefix)/Caskroom/font-jetbrains-mono-nerd-font"
    if [[ -d "$caskroom_dir" ]]; then
        # Enable NULL_GLOB to avoid no-match errors
        setopt NULL_GLOB
        for fontfile in "$caskroom_dir"/*/*.(ttf|otf); do
            if [[ -f "$fontfile" ]]; then
                cp -n "$fontfile" "$HOME/Library/Fonts/" \
                    && log_info "✅ Copied $(basename "$fontfile")"
            fi
        done
        unsetopt NULL_GLOB
    else
        log_warning "⚠️ Caskroom directory not found at $caskroom_dir"
    fi

    # 3. Restart font daemon so macOS detects new fonts immediately
    log_info "🔄 Restarting macOS font service (fontd)…"
    sudo killall fontd &>/dev/null || true

    log_info "✅ Font installation & registration complete. Please restart your terminal/editor to apply changes."
}

# -------------------------------------------------------------------
# GitHub authentication & git config
github_auth_and_git_config() {
  # Ask user if they want to login with GitHub CLI
  local ans
  read -r "?🔑 Would you like to login with GitHub CLI? (y/n) " ans
  if [[ "$ans" =~ ^[Yy] ]]; then
    log_info "🔑 Starting GitHub authentication..."
    authenticate_github
  else
    log_info "ℹ️ Skipping GitHub authentication."
  fi
}

# -------------------------------------------------------------------
# Enable core services (Tailscale, dnsmasq)
enable_services() {
    log_info "🔧 Cleaning up and starting Tailscale & dnsmasq services..."

    local brew_cmd
    brew_cmd=$(command -v brew)

    for svc in tailscale dnsmasq; do
        log_info "🔄 Stopping user-level $svc service..."
        "$brew_cmd" services stop "$svc" &>/dev/null || true
        log_info "🔄 Stopping system-level $svc service..."
        sudo "$brew_cmd" services stop "$svc" &>/dev/null || true

        log_info "🔄 Removing leftover LaunchAgents & LaunchDaemons for $svc..."
        rm -f "$HOME/Library/LaunchAgents/homebrew.mxcl.$svc.plist" || true
        sudo rm -f "/Library/LaunchDaemons/homebrew.mxcl.$svc.plist" || true

        log_info "🔄 Terminating any running $svc processes..."
        sudo pkill -f "${svc}d" &>/dev/null || true
        [[ "$svc" == "dnsmasq" ]] && sudo pkill -f "dnsmasq" &>/dev/null || true
    done

    log_info "🔧 Starting services as system daemons via brew..."
    for svc in tailscale dnsmasq; do
        if "$brew_cmd" list "$svc" &>/dev/null; then
            log_info "🔧 Starting $svc with root privileges..."
            sudo "$brew_cmd" services start "$svc" \
                && log_info "✅ $svc started successfully" \
                || log_error "❌ Failed to start $svc"
        else
            log_warning "🚫 $svc not installed; skipping"
        fi
    done
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
  if "$DOTBOT_INSTALL" -v; then
    log_info "✅ Dotbot setup completed successfully."
  else
    log_error "❌ Dotbot failed to apply configurations."
    DOTBOT_FAILED=1
  fi
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
  if [[ $DOTBOT_FAILED -ne 0 ]]; then
    log_error "❌ Bootstrap completed with errors (dotfiles setup failed)."
    exit 1
  else
    log_info "🎉 macOS bootstrap complete!"
  fi
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
    setup_dotfiles
    configure_dock
    # Configure DNS last, after services are running (dnsmasq & tailscale)
    configure_dns
    enable_touchid_for_sudo
    finalize_bootstrap
}

main "$@"