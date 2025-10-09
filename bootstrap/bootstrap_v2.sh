#!/usr/bin/env bash

set -euo pipefail

# Check for help flag or invalid arguments
if [[ $# -gt 0 ]]; then
    case "$1" in
        --help|-h)
            cat << 'EOF'
Dotfiles Bootstrap v2

USAGE:
    ./bootstrap_v2.sh [--help]

DESCRIPTION:
    Bootstraps a macOS or Linux development environment with dotfiles configuration.
    
    This script will:
    • macOS: Install Homebrew, configure services, Dock, and run Dotbot
    • Linux: Delegate to a minimal Ubuntu bootstrap helper

OPTIONS:
    -h, --help    Show this help message and exit

REQUIREMENTS:
    • macOS (Darwin) or Ubuntu (Linux)
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
readonly BREWFILE="$DOTFILES_DIR/bootstrap/helpers/Brewfile"

# XDG directories
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

# OS dispatch
case "$(uname)" in
    Darwin)
        ;;
    Linux)
        if ! command -v zsh >/dev/null 2>&1; then
            echo "→ zsh not found; attempting installation (requires administrator access)"
            if command -v apt-get >/dev/null 2>&1; then
                if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
                    if ! command -v sudo >/dev/null 2>&1; then
                        echo "✗ sudo not available; install zsh manually and re-run" >&2
                        exit 1
                    fi
                    if ! sudo -v; then
                        echo "✗ Failed to acquire sudo credentials for zsh installation" >&2
                        exit 1
                    fi
                    sudo apt-get update
                    DEBIAN_FRONTEND=noninteractive sudo apt-get install -y zsh
                else
                    apt-get update
                    DEBIAN_FRONTEND=noninteractive apt-get install -y zsh
                fi
                echo "✓ zsh installed"
            else
                echo "✗ Automatic zsh installation is unsupported on this distribution. Install zsh manually and re-run" >&2
                exit 1
            fi
        fi
        linux_helper="$DOTFILES_DIR/bootstrap/helpers/linux_helper.sh"
        if [[ ! -x "$linux_helper" ]]; then
            echo "✗ Linux bootstrap helper not found at $linux_helper" >&2
            exit 1
        fi
        /usr/bin/env bash "$linux_helper" "$@"
        exit $?
        ;;
    *)
        echo "✗ Unsupported operating system: $(uname)" >&2
        exit 1
        ;;
esac

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
        printf "%s " "$prompt (Y/n): "
        read -r response
        case "$response" in
            ""|[Yy]|[Yy][Ee][Ss]) return 0 ;;
            [Nn]|[Nn][Oo]) return 1 ;;
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
    mkdir -p \
        "$XDG_CONFIG_HOME" \
        "$XDG_DATA_HOME" \
        "$XDG_CACHE_HOME" \
        "$XDG_STATE_HOME" \
        "$XDG_CACHE_HOME/zsh" \
        "$XDG_STATE_HOME/zsh/sessions"
    chmod 700 "$HOME/.ssh" "$XDG_STATE_HOME/zsh" "$XDG_STATE_HOME/zsh/sessions" 2>/dev/null || true
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
    [[ "$install_services" != "true" ]] && sed -i '' '/brew "tailscale"/d' "$temp_brewfile"
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
        log_info "Configuring tailscale service"
        # Stop any existing user-level service first
        brew services stop tailscale 2>/dev/null || true
        # Start as system service with proper privileges
        require_sudo
        sudo brew services restart tailscale || log_warn "Failed to start tailscale"
    fi
    
    log_success "Services configured"
}

configure_magicdns_resolver() {
    local install_services="$1"
    local tailnet_domain="tail969ae0.ts.net"
    
    [[ "$install_services" != "true" ]] && return
    
    log_info "Configuring MagicDNS resolver for Tailscale"
    require_sudo
    
    # Create resolver directory and file for Tailscale domain
    sudo mkdir -p /etc/resolver
    echo "nameserver 100.100.100.100" | sudo tee "/etc/resolver/${tailnet_domain}" >/dev/null
    
    # Set search domain for all active network interfaces
    while IFS= read -r service; do
        service="${service#\*}"
        service="$(echo "$service" | xargs)"
        [[ -z "$service" || "$service" == *VPN* || "$service" == Tailscale* ]] && continue
        sudo networksetup -setsearchdomains "$service" "$tailnet_domain" || log_warn "Failed to set search domain for $service"
    done < <(networksetup -listallnetworkservices 2>/dev/null | sed '1d')
    
    log_success "MagicDNS resolver configured"
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
    local start_time
    start_time=$(date +%s)
    
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
    ask_yes_no "Install and configure Tailscale with MagicDNS" && install_services="true" || install_services="false"
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
    local step=1 total=11
    
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
    
    log_step $step $total "Configuring MagicDNS resolver"; ((step++))
    configure_magicdns_resolver "$install_services"
    
    log_step $step $total "Setting up Touch ID"; ((step++))
    setup_touchid
    
    log_step $step $total "Configuring Dock"; ((step++))
    configure_dock "$install_casks"
    
    log_step $step $total "Setting up GitHub authentication"; ((step++))
    if [[ "$install_github" == "true" ]]; then
        setup_github_auth
    else
        log_info "Skipping GitHub authentication"
    fi
    
    log_step $step $total "Setting up development directory"; ((step++))
    if [[ "$install_dev_dir" == "true" ]]; then
        setup_dev_directory
    else
        log_info "Skipping development directory setup"
    fi
    
    log_step $step $total "Running XDG cleanup"; ((step++))
    run_xdg_cleanup
    
    echo
    echo "🎉 Bootstrap Complete!"
    echo "====================="
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    echo "→ Total time: $((duration / 60))m $((duration % 60))s"
    echo "→ Run 'git config --global user.name \"Your Name\"' and 'git config --global user.email \"you@example.com\"' to configure Git"
    echo ""
    
    # Sophisticated terminal detection and restart logic
    echo "To apply all configuration changes, your terminal session needs to restart."
    echo ""
    
    if ask_yes_no "Would you like to restart your terminal now"; then
        log_info "Restarting terminal session..."
        
        # Detect terminal environment and handle accordingly
        if [[ -n "${VSCODE_INJECTION:-}" ]] || [[ "${TERM_PROGRAM:-}" == "vscode" ]] || [[ -n "${VSCODE_PID:-}" ]]; then
            # VS Code integrated terminal
            log_info "VS Code detected: Restarting shell session..."
            exec zsh
            
        elif [[ "${TERM_PROGRAM:-}" == "ghostty" ]]; then
            # Ghostty - quit the application
            log_info "Ghostty detected: Quitting application..."
            osascript -e 'tell application "Ghostty" to quit' 2>/dev/null || true
            
        elif [[ "${TERM_PROGRAM:-}" == "Apple_Terminal" ]]; then
            # Terminal.app - quit the application
            log_info "Terminal.app detected: Quitting application..."
            osascript -e 'tell application "Terminal" to quit' 2>/dev/null || true
            
        elif [[ -n "${SSH_CONNECTION:-}" ]] || [[ -n "${SSH_CLIENT:-}" ]] || [[ -n "${SSH_TTY:-}" ]]; then
            # SSH session - restart shell
            log_info "SSH session detected: Restarting shell..."
            exec zsh
            
        else
            # Fallback for other integrated terminals or unknown environments
            log_info "Attempting to restart shell..."
            if command -v zsh >/dev/null 2>&1; then
                exec zsh
            else
                log_warn "Shell restart failed. Please manually restart your terminal."
                exit 0
            fi
        fi
    else
        echo ""
        log_info "Skipping terminal restart."
        echo "To apply changes manually:"
        echo "  • In VS Code: Close terminal and open new one"
        echo "  • In Ghostty/Terminal: Quit and reopen application"
        echo "  • In any terminal: Run 'exec zsh'"
    fi
}

main "$@"