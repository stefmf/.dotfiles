#!/usr/bin/env zsh

# ─── Strict mode ──────────────────────────────────────────────────────────────
setopt errexit nounset pipefail

# Prevent running the script as root
if [[ $EUID -eq 0 ]]; then
    echo "[ERROR] Do not run this script as root. Please run as your regular user without sudo." >&2
    exit 1
fi

# ─── Conditional sudo setup ─────────────────────────────────────────────────

# Prompt user to decide whether to use non-interactive sudo via SUDO_ASKPASS
USE_AUTO_SUDO=true
read -r "?Enable automated sudo via SUDO_ASKPASS? (y/n): " ans
[[ $ans =~ ^[Yy] ]] || USE_AUTO_SUDO=false

if [[ "$USE_AUTO_SUDO" == true ]]; then
  # Maximum retries for wrong sudo password
  typeset -i MAX_RETRIES=3
  typeset -i attempt=0

  while (( attempt < MAX_RETRIES )); do
    # prompt silently for password
    read -rs "PASSWORD?Enter your sudo password: "

    # build a fresh ASKPASS helper
    ASKPASS=$(mktemp)
    chmod 700 "$ASKPASS"
    cat >"$ASKPASS" <<-EOF
#!/usr/bin/env zsh
echo "$PASSWORD"
EOF
    chmod +x "$ASKPASS"
    export SUDO_ASKPASS="$ASKPASS"
    sudo() { /usr/bin/sudo -A "$@"; }

    # test it immediately
    if sudo -v 2>/dev/null; then
      break
    else
      (( attempt++ ))
      rm -f "$ASKPASS"
      if (( attempt < MAX_RETRIES )); then
        echo "[WARNING] Incorrect password; please try again." >&2
      else
        echo "[ERROR] Wrong password entered $MAX_RETRIES times. Aborting." >&2
        exit 1
      fi
    fi
  done

  # clean up when the script finally exits
  trap 'rm -f "$ASKPASS"' EXIT

  # background keep-alive loop
  keep_sudo() {
    while kill -0 $$ 2>/dev/null; do
      sudo -v
      sleep 60
    done
  }
  keep_sudo &
else
  # Fallback: use interactive sudo for each command
  sudo() { /usr/bin/sudo "$@"; }
fi


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

# ---------------------------
# Constants and Configuration
# ---------------------------

# Set Dotfiles directory
typeset -r DOTFILES_DIR="$HOME/.dotfiles"
typeset -r BREW_FILE="$DOTFILES_DIR/.bootstrap/macos/Brewfile"
typeset -r DOTBOT_INSTALL="$DOTFILES_DIR/install"
typeset -r ZSH_PROFILE="$DOTFILES_DIR/.zsh/.zprofile"
typeset -r DOCK_CONFIG="$DOTFILES_DIR/.config/dock/dock_config.zsh"

# Flags controlled by user prompts
typeset INSTALL_CASKS=false
typeset INSTALL_SERVICES=false
typeset CONFIGURE_DNS_CHOICE=false

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
# Prompt for optional components
# ---------------------------
prompt_user_choices() {
    local ans

    read -r "?Install Homebrew cask applications? (y/n): " ans
    [[ $ans =~ ^[Yy] ]] && INSTALL_CASKS=true

    read -r "?Install Tailscale and dnsmasq? (y/n): " ans
    if [[ $ans =~ ^[Yy] ]]; then
        INSTALL_SERVICES=true
        read -r "?Configure system DNS for Tailscale/dnsmasq? (y/n): " ans
        [[ $ans =~ ^[Yy] ]] && CONFIGURE_DNS_CHOICE=true
    fi
}

# ---------------------------
# Privacy & Security Settings Helper
# ---------------------------

open_privacy_settings() {
    log_info "Opening Privacy & Security settings for App Management..."
    osascript -e 'tell application "System Settings"
        activate
        delay 1
        reveal anchor "Privacy_AppBundles" of pane id "com.apple.settings.PrivacySecurity.extension"
    end tell' &>/dev/null || true

    # Detailed user guidance for App Management
    log_info "📌 'Privacy & Security' → 'App Management' pane opened successfully."
    log_info "🔍 In the sidebar, select 'App Management'."
    log_info "🔒 Click the lock icon in the bottom-left and authenticate with your password to allow changes."
    log_info "➕ Click the '+' button under 'Allowed Apps', select your terminal application (e.g., Terminal.app or iTerm.app), and click 'Open'."
    log_info "✅ Verify your terminal appears in the list and is marked as 'Allowed'."

    # Updated prompt for clarity
    read -r "?Press Enter once you've added your terminal in App Management and unlocked settings to continue..." dummy
}

# ---------------------------
# Package Installation
# ---------------------------

install_packages() {
    if [[ -f "$BREW_FILE" ]]; then
        log_info "📦 Starting package installation process..."

        local brewfile_to_use="$BREW_FILE"
        local cleanup=false

        if [[ "$INSTALL_CASKS" != true || "$INSTALL_SERVICES" != true ]]; then
            brewfile_to_use=$(mktemp)
            cp "$BREW_FILE" "$brewfile_to_use"
            cleanup=true
        fi

        if [[ "$INSTALL_CASKS" == true ]]; then
            log_info "🔒 Requesting sudo access for special casks installation (you may be prompted)"
            sudo -v
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
                brew install --cask "$cask" > /dev/null 2>&1 || log_warning "Installation of $cask failed"
            done
        else
            log_info "⏭️ Skipping Homebrew cask and MAS app installation"
            sed -i '' \
                -e '/^cask "font-jetbrains-mono-nerd-font"/!{/^cask /d;}' \
                -e '/^mas /d' "$brewfile_to_use"
        fi

        if [[ "$INSTALL_SERVICES" != true ]]; then
            sed -i '' -e '/brew "tailscale"/d' -e '/brew "dnsmasq"/d' "$brewfile_to_use"
        fi

        log_info "📦 Installing Brewfile packages..."
        brew bundle --file="$brewfile_to_use" || log_warning "Some Brewfile packages failed to install."

        [[ "$cleanup" == true ]] && rm -f "$brewfile_to_use"

        # Install JetBrains Mono Nerd Font cask
        log_info "📦 Installing JetBrains Mono Nerd Font cask..."
        if ! brew list --cask font-jetbrains-mono-nerd-font &>/dev/null; then
            brew install --cask font-jetbrains-mono-nerd-font \
                || log_warning "❌ Failed to install font-jetbrains-mono-nerd-font"
        else
            log_info "✅ JetBrains Mono Nerd Font already installed"
        fi

        log_info "✅ Package installation completed."
    else
        log_warning "⚠️ No Brewfile found at $BREW_FILE; skipping package installation."
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

# ---------------------------
# GitHub authentication & git config
# ---------------------------
github_auth_and_git_config() {
    # Prompt for global Git config (user.name and user.email)
    read -r "?✏️ Enter global Git user name: " GIT_USER_NAME
    read -r "?✏️ Enter global Git user email: " GIT_USER_EMAIL
    log_info "🛠️ Setting global git config: $GIT_USER_NAME <$GIT_USER_EMAIL>"
    git config --global user.name "$GIT_USER_NAME" || log_warning "⚠️ Failed to set Git user name"
    git config --global user.email "$GIT_USER_EMAIL" || log_warning "⚠️ Failed to set Git user email"

    # Ask user if they want to login with GitHub CLI
    local ans
    read -r "?Login with GitHub CLI? (y/n): " ans
    if [[ "$ans" =~ ^[Yy] ]]; then
        log_info "🔑 Starting GitHub authentication..."
        authenticate_github
    else
        log_info "ℹ️ Skipping GitHub authentication."
    fi
}

# -------------------------------------------------------------------
# Authenticate with GitHub via gh CLI
authenticate_github() {
    if command -v gh &>/dev/null; then
        log_info "🔑 Logging in to GitHub with gh CLI..."
        gh auth login --hostname github.com --git-protocol ssh
    else
        log_warning "⚠️ gh CLI not installed; skipping GitHub login"
    fi
}

# -------------------------------------------------------------------
# Enable core services (Tailscale, dnsmasq)
enable_services() {
    if [[ "$INSTALL_SERVICES" != true ]]; then
        log_info "⏭️ Skipping Tailscale and dnsmasq service setup"
        return
    fi

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
    if [[ "$CONFIGURE_DNS_CHOICE" != true ]]; then
        log_info "⏭️ Skipping DNS configuration"
        return
    fi

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
  log_info "🔐 Enabling Touch ID for sudo via sudo_local…"

  # Ensure we have the template
  if [[ ! -f /etc/pam.d/sudo_local ]]; then
    sudo cp /etc/pam.d/sudo_local.template /etc/pam.d/sudo_local
  fi

  # Uncomment the Touch ID line
  sudo sed -i '' -E 's/^#(auth[[:space:]]+sufficient[[:space:]]+pam_tid\.so)/\1/' \
    /etc/pam.d/sudo_local

  log_info "✅ Touch ID enabled in /etc/pam.d/sudo_local"
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

# ---------------------------
# Handle Existing Links or Files
# ---------------------------

handle_existing_links() {
    local links=(
        "$HOME/.zshrc"
        "$HOME/.config"
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
    if [[ "$INSTALL_CASKS" != true ]]; then
        log_info "⏭️ Skipping Dock configuration (cask apps not installed)"
        return
    fi
    log_info "⚙️ Configuring macOS Dock..."
    source "$DOCK_CONFIG"
}

# -------------------------------------------------------------------
# iTerm2 configuration: set prefs folder and deploy dynamic profile
configure_iterm2() {
    log_info "🔧 Configuring iTerm2 preferences folder and dynamic profiles"
    # Set custom preferences folder
    defaults write com.googlecode.iterm2 PrefsCustomFolder -string "$HOME/.config/iterm2"
    defaults write com.googlecode.iterm2 LoadPrefsFromCustomFolder -bool true

    # Ensure DynamicProfiles directory exists
    mkdir -p "$HOME/.config/iterm2/DynamicProfiles"

    # Copy dynamic profile from dotfiles repo if present
    if [[ -f "$HOME/.config/iterm2/DynamicProfiles/Stef.json" ]] && cmp -s "$DOTFILES_DIR/.config/iterm2/DynamicProfiles/Stef.json" "$HOME/.config/iterm2/DynamicProfiles/Stef.json"; then
        log_info "✅ Stef dynamic profile already up to date"
    else
        if [[ -f "$DOTFILES_DIR/.config/iterm2/DynamicProfiles/Stef.json" ]]; then
            cp "$DOTFILES_DIR/.config/iterm2/DynamicProfiles/Stef.json" "$HOME/.config/iterm2/DynamicProfiles/Stef.json"
            log_info "✅ Copied Stef dynamic profile"
        else
            log_warning "⚠️ Stef dynamic profile not found in repository"
        fi
    fi
}

# -------------------------------------------------------------------
# Setup SSH socket directory
setup_ssh_socket_dir() {
    log_info "🔐 Setting up SSH socket directory..."
    
    # Ensure socket directory exists with correct permissions
    SOCKET_DIR=~/.ssh/sockets
    
    mkdir -p "$SOCKET_DIR"
    chmod 700 "$SOCKET_DIR"
    
    log_info "✅ SSH socket directory created and secured"
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
    prompt_user_choices
    install_homebrew
    install_brew_packages
    github_auth_and_git_config
    enable_services
    setup_dotfiles
    configure_dock
    configure_dns
    enable_touchid_for_sudo
    configure_iterm2
    setup_ssh_socket_dir
    finalize_bootstrap
}

main "$@"
