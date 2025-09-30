#!/usr/bin/env zsh

set -euo pipefail

# Check for help flag or invalid arguments
if [[ $# -gt 0 ]]; then
    case "$1" in
        --help|-h)
            cat << 'EOF'
macOS Dotfiles Bootstrap v2

USAGE:
    ./bootstrap_v2.sh [--help]

DESCRIPTION:
    Bootstraps a macOS development environment with dotfiles configuration.
    
    This script will:
    • Set up XDG directories
    • Install Homebrew and Xcode Command Line Tools
    • Install packages from Brewfile (with user prompts for optional items)
    • Configure system services, DNS, Touch ID
    • Set up GitHub authentication, development directory
    • Configure Dock and iTerm2
    • Run Dotbot configuration

OPTIONS:
    -h, --help    Show this help message and exit

REQUIREMENTS:
    • macOS (Darwin)
    • Non-root user
    • zsh (default on macOS 10.15+)
    • Internet connection

EOF
            exit 0
            ;;
        *)
            echo "✗ Unknown option: $1" >&2
            echo "Use --help for usage information" >&2
            exit 1
            ;;
    esac
fi

# Constants
readonly DOTFILES_DIR="$HOME/.dotfiles"
readonly BREWFILE="$DOTFILES_DIR/bootstrap/Brewfile"

# XDG directories
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

# Ensure we're on macOS
if [[ "$(uname)" != "Darwin" ]]; then
    echo "✗ This script is for macOS only" >&2
    exit 1
fi

# Don't run as root
if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    echo "✗ Do not run as root" >&2
    exit 1
fi

#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Utility Functions
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Utilities
log_info() { echo "→ $*"; }
log_success() { echo "✓ $*"; }
log_warn() { echo "⚠ $*" >&2; }
log_error() { echo "✗ $*" >&2; }
log_step() { echo ""; echo "[$1/$2] $3"; }

ask_yes_no() {
    local prompt="$1"
    local response
    
    while true; do
        read -r "response?$prompt (Y/n): "
        # Use zsh's native case-insensitive comparison
        case "${(L)response}" in
            y|yes) return 0 ;;
            n|no) return 1 ;;
            *) echo "Please enter 'y' or 'n' (or 'yes'/'no')" ;;
        esac
    done
}

require_sudo() {
    if ! sudo -n true 2>/dev/null; then
        log_info "Administrator privileges required"
        sudo -v || {
            log_error "Failed to acquire sudo credentials"
            exit 1
        }
    fi
}

#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Setup Functions
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup_xdg_directories() {
    log_info "Setting up XDG directories"
    mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME"
    mkdir -p "$HOME/.zsh_sessions" "$HOME/.ssh/sockets"
    chmod 700 "$HOME/.ssh" "$HOME/.ssh/sockets" 2>/dev/null || true
    log_success "XDG directories created"
}

install_homebrew() {
    # Install Xcode Command Line Tools first
    if ! xcode-select -p >/dev/null 2>&1; then
        log_info "Installing Xcode Command Line Tools"
        xcode-select --install
        log_info "Please complete the Xcode Command Line Tools installation in the popup, then press Enter to continue"
        read -r
        # Wait for installation to complete
        until xcode-select -p >/dev/null 2>&1; do
            sleep 5
        done
        log_success "Xcode Command Line Tools installed"
    fi
    
    if command -v brew >/dev/null 2>&1; then
        log_success "Homebrew already installed"
        return
    fi
    
    log_info "Installing Homebrew"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    
    # Add Homebrew to PATH
    if [[ "$(uname -m)" == "arm64" ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    else
        eval "$(/usr/local/bin/brew shellenv)"
    fi
    
    log_success "Homebrew installed"
}

install_packages() {
    local install_casks="$1"
    local install_mas="$2"
    local install_services="$3"
    local install_office="$4"
    local install_parallels="$5"
    
    if [[ ! -f "$BREWFILE" ]]; then
        log_warn "Brewfile not found at $BREWFILE"
        return
    fi
    
    log_info "Installing packages from Brewfile"
    
    # Create filtered Brewfile
    local temp_brewfile
    temp_brewfile=$(mktemp)
    cp "$BREWFILE" "$temp_brewfile"
    
    # Remove unwanted packages based on user choices
    [[ "$install_casks" != "true" ]] && sed -i '' '/^cask /d' "$temp_brewfile"
    [[ "$install_mas" != "true" ]] && sed -i '' '/^mas /d' "$temp_brewfile"
    [[ "$install_services" != "true" ]] && sed -i '' -e '/brew "tailscale"/d' -e '/brew "dnsmasq"/d' "$temp_brewfile"
    [[ "$install_office" != "true" ]] && sed -i '' -e '/cask "microsoft-teams"/d' -e '/mas "Microsoft Excel"/d' -e '/mas "Microsoft PowerPoint"/d' -e '/mas "Microsoft Word"/d' -e '/mas "Slack"/d' "$temp_brewfile"
    [[ "$install_parallels" != "true" ]] && sed -i '' '/cask "parallels"/d' "$temp_brewfile"
    
    # Install packages
    if brew bundle --file="$temp_brewfile" check >/dev/null 2>&1; then
        log_success "All packages already installed"
    else
        brew bundle --file="$temp_brewfile" || log_warn "Some packages failed to install"
    fi
    
    # Ensure JetBrains Nerd Font is installed (required for terminal themes)
    if ! brew list --cask font-jetbrains-mono-nerd-font >/dev/null 2>&1; then
        log_info "Installing JetBrains Mono Nerd Font"
        brew install --cask font-jetbrains-mono-nerd-font || log_warn "Failed to install Nerd Font"
    fi
    
    rm -f "$temp_brewfile"
    log_success "Package installation complete"
}

configure_services() {
    local install_services="$1"
    
    [[ "$install_services" != "true" ]] && return
    
    log_info "Starting system services"
    
    # Start Tailscale as system service (requires system extensions)
    if brew list tailscale >/dev/null 2>&1; then
        log_info "Starting tailscale as system service"
        require_sudo
        sudo brew services restart tailscale || log_warn "Failed to start tailscale"
    fi
    
    # Start dnsmasq with sudo (needs port 53 access)
    if brew list dnsmasq >/dev/null 2>&1; then
        log_info "Starting dnsmasq with sudo"
        require_sudo
        sudo brew services restart dnsmasq || log_warn "Failed to start dnsmasq"
    fi
    
    log_success "Services configured"
}

configure_dns() {
    local install_services="$1"
    
    [[ "$install_services" != "true" ]] && return
    
    if ! brew list dnsmasq >/dev/null 2>&1; then
        log_warn "dnsmasq not installed, skipping DNS configuration"
        return
    fi
    
    log_info "Configuring DNS to use dnsmasq"
    require_sudo
    
    while IFS= read -r service; do
        service="${service#\*}"
        service="$(echo "$service" | xargs)"
        [[ -z "$service" || "$service" == *VPN* || "$service" == Tailscale* ]] && continue
        sudo networksetup -setdnsservers "$service" 127.0.0.1 || log_warn "Failed to set DNS for $service"
    done < <(networksetup -listallnetworkservices 2>/dev/null | sed '1d')
    
    log_success "DNS configured"
}

setup_github_auth() {
    if ! command -v gh >/dev/null 2>&1; then
        log_warn "GitHub CLI not installed, skipping authentication"
        return
    fi
    
    log_info "Setting up GitHub CLI authentication"
    gh auth login --hostname github.com --git-protocol ssh || log_warn "GitHub authentication failed"
    log_success "GitHub authentication complete"
}

setup_dev_directory() {
    local script="$DOTFILES_DIR/scripts/dev/bootstrap_dev_dir.sh"
    
    if [[ ! -x "$script" ]]; then
        log_warn "Dev directory script not found"
        return
    fi
    
    log_info "Setting up development directory"
    "$script" || log_warn "Dev directory setup failed"
    log_success "Development directory setup complete"
}

run_xdg_cleanup() {
    local script="$DOTFILES_DIR/scripts/system/xdg-cleanup"
    
    if [[ ! -x "$script" ]]; then
        log_warn "XDG cleanup script not found"
        return
    fi
    
    log_info "Running XDG cleanup"
    "$script" --from-bootstrap || log_warn "XDG cleanup reported issues"
    log_success "XDG cleanup complete"
}

setup_touchid() {
    local sudo_local="$DOTFILES_DIR/system/pam.d/sudo_local"
    
    if [[ ! -f "$sudo_local" ]]; then
        log_warn "Touch ID config not found"
        return
    fi
    
    log_info "Enabling Touch ID for sudo"
    require_sudo
    
    sudo rm -f /etc/pam.d/sudo_local 2>/dev/null || true
    sudo ln -sf "$sudo_local" /etc/pam.d/sudo_local || log_warn "Failed to configure Touch ID"
    log_success "Touch ID configured"
}

configure_dock() {
    local install_casks="$1"
    local dock_config="$DOTFILES_DIR/config/dock/dock_config.zsh"
    
    [[ "$install_casks" != "true" ]] && return
    [[ ! -f "$dock_config" ]] && return
    
    log_info "Configuring Dock"
    zsh "$dock_config" || log_warn "Dock configuration failed"
    log_success "Dock configured"
}

setup_iterm2() {
    log_info "Configuring iTerm2"
    
    # Set iTerm2 preferences location
    defaults write com.googlecode.iterm2 PrefsCustomFolder -string "$HOME/.config/iterm2" 2>/dev/null
    defaults write com.googlecode.iterm2 LoadPrefsFromCustomFolder -bool true 2>/dev/null
    
    # Copy dynamic profile
    mkdir -p "$HOME/.config/iterm2/DynamicProfiles"
    local src="$DOTFILES_DIR/config/iterm2/DynamicProfiles/Stef.json"
    local dst="$HOME/.config/iterm2/DynamicProfiles/Stef.json"
    
    if [[ -f "$src" ]] && ([[ ! -f "$dst" ]] || ! cmp -s "$src" "$dst"); then
        cp "$src" "$dst"
    fi
    
    log_success "iTerm2 configured"
}

run_dotbot() {
    local dotbot_install="$DOTFILES_DIR/install"
    
    if [[ ! -x "$dotbot_install" ]]; then
        log_error "Dotbot installer not found"
        exit 1
    fi
    
    # Prepare gitconfig.local if needed
    local template="$DOTFILES_DIR/config/git/gitconfig.local.template"
    local target="$DOTFILES_DIR/config/git/gitconfig.local"
    
    if [[ -f "$template" && ! -f "$target" ]]; then
        cp "$template" "$target"
    fi
    
    # Ensure zinit directory exists
    mkdir -p "${XDG_DATA_HOME}/zinit"
    
    log_info "Running Dotbot"
    DOTFILES_SKIP_TOUCHID_LINK=true "$dotbot_install" || log_warn "Dotbot reported issues but continuing"
    log_success "Dotbot complete"
}

#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Main Execution
#━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

main() {
    local start_time=$(date +%s)
    
    echo "🚀 macOS Dotfiles Bootstrap v2"
    echo "==============================="
    echo
    
    # Ensure proper repository ownership
    if [[ ! -w "$DOTFILES_DIR" ]]; then
        log_info "Fixing repository ownership"
        require_sudo
        sudo chown -R "$(id -un):$(id -gn)" "$DOTFILES_DIR" || log_warn "Could not fix repository ownership"
    fi
    
    # Collect user preferences upfront
    echo "Configuration Options:"
    echo "---------------------"
    
    local install_casks install_mas install_services install_office install_parallels install_github install_dev_dir
    
    ask_yes_no "Install GUI applications (casks)" && install_casks="true" || install_casks="false"
    ask_yes_no "Install Mac App Store apps" && install_mas="true" || install_mas="false"
    ask_yes_no "Install and start services (Tailscale, dnsmasq)" && install_services="true" || install_services="false"
    ask_yes_no "Install Microsoft Office tools & Slack" && install_office="true" || install_office="false"
    ask_yes_no "Install Parallels Desktop" && install_parallels="true" || install_parallels="false"
    ask_yes_no "Setup GitHub authentication" && install_github="true" || install_github="false"
    ask_yes_no "Setup development directory structure" && install_dev_dir="true" || install_dev_dir="false"
    
    # Show summary
    echo
    echo "Configuration Summary:"
    echo "====================="
    echo "• GUI Applications: $([ "$install_casks" = "true" ] && echo "✓ Yes" || echo "✗ No")"
    echo "• Mac App Store: $([ "$install_mas" = "true" ] && echo "✓ Yes" || echo "✗ No")"
    echo "• Services: $([ "$install_services" = "true" ] && echo "✓ Yes" || echo "✗ No")"
    echo "• Office & Slack: $([ "$install_office" = "true" ] && echo "✓ Yes" || echo "✗ No")"
    echo "• Parallels: $([ "$install_parallels" = "true" ] && echo "✓ Yes" || echo "✗ No")"
    echo "• GitHub Auth: $([ "$install_github" = "true" ] && echo "✓ Yes" || echo "✗ No")"
    echo "• Dev Directory: $([ "$install_dev_dir" = "true" ] && echo "✓ Yes" || echo "✗ No")"
    
    echo
    echo "Starting installation..."
    echo "========================"
    
    # Execute setup tasks in order with progress
    local step=1 total=12
    
    log_step $step $total "Setting up XDG directories"; ((step++))
    setup_xdg_directories
    
    log_step $step $total "Installing Homebrew & Command Line Tools"; ((step++))
    install_homebrew
    
    log_step $step $total "Installing packages"; ((step++))
    install_packages "$install_casks" "$install_mas" "$install_services" "$install_office" "$install_parallels"
    
    log_step $step $total "Configuring services"; ((step++))
    configure_services "$install_services"
    
    log_step $step $total "Running Dotbot configuration"; ((step++))
    run_dotbot
    
    log_step $step $total "Setting up Touch ID"; ((step++))
    setup_touchid
    
    log_step $step $total "Configuring Dock"; ((step++))
    configure_dock "$install_casks"
    
    log_step $step $total "Setting up iTerm2"; ((step++))
    setup_iterm2
    
    log_step $step $total "Setting up GitHub authentication"; ((step++))
    [[ "$install_github" == "true" ]] && setup_github_auth || log_info "Skipping GitHub authentication"
    
    log_step $step $total "Setting up development directory"; ((step++))
    [[ "$install_dev_dir" == "true" ]] && setup_dev_directory || log_info "Skipping development directory setup"
    
    log_step $step $total "Running XDG cleanup"; ((step++))
    run_xdg_cleanup
    
    log_step $step $total "Configuring DNS (final step)"; ((step++))
    configure_dns "$install_services"
    
    echo
    echo "🎉 Bootstrap Complete!"
    echo "====================="
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    echo "→ Total time: $((duration / 60))m $((duration % 60))s"
    echo "→ Restart your terminal to apply all changes"
    echo "→ Run 'git config --global user.name \"Your Name\"' and 'git config --global user.email \"you@example.com\"' to configure Git"
    
    if ask_yes_no "Quit Terminal.app now"; then
        osascript -e 'tell application "Terminal" to quit' 2>/dev/null || true
    fi
}

main "$@"