#!/usr/bin/env bash

set -euo pipefail

if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
  echo "✗ Do not run as root" >&2
  exit 1
fi

# Constants
readonly DOTFILES_DIR="$HOME/.dotfiles"
readonly DOTBOT_INSTALL="$DOTFILES_DIR/install"
readonly BREWFILE="$DOTFILES_DIR/bootstrap/Brewfile"
readonly DOCK_CONFIG="$DOTFILES_DIR/config/dock/dock_config.zsh"

# XDG directories
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
export DOTFILES="$DOTFILES_DIR"

# Configuration (override via environment variables)
# Smart defaults based on platform and common usage
if is_macos; then
  INSTALL_CASKS=${INSTALL_CASKS:-true}
  INSTALL_MAS_APPS=${INSTALL_MAS_APPS:-ask}
  INSTALL_SERVICES=${INSTALL_SERVICES:-true}
  INSTALL_OFFICE_TOOLS=${INSTALL_OFFICE_TOOLS:-ask}
  INSTALL_SLACK=${INSTALL_SLACK:-ask}
  INSTALL_PARALLELS=${INSTALL_PARALLELS:-ask}
  CONFIGURE_DNS=${CONFIGURE_DNS:-ask}
else
  INSTALL_CASKS=false
  INSTALL_MAS_APPS=false
  INSTALL_SERVICES=false
  INSTALL_OFFICE_TOOLS=false
  INSTALL_SLACK=false
  INSTALL_PARALLELS=false
  CONFIGURE_DNS=false
fi

# Common defaults for all platforms
GITHUB_AUTH=${GITHUB_AUTH:-true}
CONFIGURE_GIT=${CONFIGURE_GIT:-true}
CHANGE_SHELL=${CHANGE_SHELL:-auto}
SETUP_DEV_DIR=${SETUP_DEV_DIR:-true}
RUN_XDG_CLEANUP=${RUN_XDG_CLEANUP:-true}

# Logging
info() { echo "→ $*"; }
step() { echo ""; echo "→ $*"; }
warn() { echo "⚠ $*" >&2; }
error() { echo "✗ $*" >&2; }
success() { echo "✓ $*"; }

# Utilities
is_macos() { [[ "$(uname)" == "Darwin" ]]; }
is_linux() { [[ "$(uname)" == "Linux" ]]; }

confirm() {
  local prompt="$1" default="${2:-n}"
  local reply
  if [[ "$default" == "y" ]]; then
    read -r -p "$prompt [Y/n] " reply
    [[ -z "$reply" || "$reply" =~ ^[Yy] ]]
  else
    read -r -p "$prompt [y/N] " reply
    [[ "$reply" =~ ^[Yy] ]]
  fi
}

# Convert "ask" values to true/false based on user input
resolve_option() {
  local var_name="$1" prompt="$2" default="${3:-n}"
  local current_value="${!var_name}"
  
  if [[ "$current_value" == "ask" ]]; then
    if confirm "$prompt" "$default"; then
      printf -v "$var_name" "true"
    else
      printf -v "$var_name" "false"
    fi
  fi
}

require_sudo() {
  if ! sudo -n true 2>/dev/null; then
    info "Administrator privileges required"
    sudo -v || { error "Failed to acquire sudo credentials"; exit 1; }
  fi
}

# System setup
setup_directories() {
  mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME"
  mkdir -p "$HOME/.zsh_sessions" "$HOME/.ssh/sockets"
  chmod 700 "$HOME/.ssh" "$HOME/.ssh/sockets" 2>/dev/null || true
}

fix_repository_ownership() {
  if [[ ! -w "$DOTFILES_DIR" ]]; then
    require_sudo
    sudo chown -R "$(id -un):$(id -gn)" "$DOTFILES_DIR" || warn "Could not fix repository ownership"
  fi
}

# macOS functions
install_xcode_clt() {
  if ! xcode-select -p >/dev/null 2>&1; then
    info "Installing Xcode Command Line Tools"
    xcode-select --install
    until xcode-select -p >/dev/null 2>&1; do sleep 10; done
    success "Command Line Tools installed"
  fi
}

install_homebrew() {
  if ! command -v brew >/dev/null 2>&1; then
    info "Installing Homebrew"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
  
  if [[ "$(uname -m)" == "arm64" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  else
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

install_packages_macos() {
  [[ ! -f "$BREWFILE" ]] && { warn "Brewfile not found at $BREWFILE"; return; }
  
  local temp_brewfile
  temp_brewfile=$(mktemp)
  cp "$BREWFILE" "$temp_brewfile"
  
  # Filter packages based on configuration
  [[ "$INSTALL_CASKS" != "true" ]] && sed -i '' '/^cask /d' "$temp_brewfile"
  [[ "$INSTALL_MAS_APPS" != "true" ]] && sed -i '' '/^mas /d' "$temp_brewfile"
  [[ "$INSTALL_SERVICES" != "true" ]] && sed -i '' -e '/brew "tailscale"/d' -e '/brew "dnsmasq"/d' "$temp_brewfile"
  [[ "$INSTALL_OFFICE_TOOLS" != "true" ]] && sed -i '' -e '/cask "microsoft-teams"/d' -e '/mas "Microsoft Excel"/d' -e '/mas "Microsoft PowerPoint"/d' -e '/mas "Microsoft Word"/d' "$temp_brewfile"
  [[ "$INSTALL_SLACK" != "true" ]] && sed -i '' '/mas "Slack"/d' "$temp_brewfile"
  [[ "$INSTALL_PARALLELS" != "true" ]] && sed -i '' '/cask "parallels"/d' "$temp_brewfile"
  
  if brew bundle --file="$temp_brewfile" check >/dev/null 2>&1; then
    success "Homebrew packages already satisfied"
  else
    info "Installing Homebrew packages"
    brew bundle --file="$temp_brewfile" || warn "Some packages failed to install"
  fi
  
  rm -f "$temp_brewfile"
  
  # Ensure Nerd Font
  if ! brew list --cask font-jetbrains-mono-nerd-font >/dev/null 2>&1; then
    brew install --cask font-jetbrains-mono-nerd-font || warn "Failed to install Nerd Font"
  fi
}

configure_services_macos() {
  [[ "$INSTALL_SERVICES" != "true" ]] && return
  
  command -v brew >/dev/null 2>&1 || return
  require_sudo
  
  for service in tailscale dnsmasq; do
    if brew list "$service" >/dev/null 2>&1; then
      info "Starting $service"
      brew services restart "$service" || warn "Failed to start $service"
    fi
  done
}

configure_dns_macos() {
  [[ "$CONFIGURE_DNS" != "true" ]] && return
  [[ "$INSTALL_SERVICES" != "true" ]] && return
  
  command -v brew >/dev/null 2>&1 && brew list dnsmasq >/dev/null 2>&1 || return
  
  require_sudo
  info "Configuring DNS to use dnsmasq"
  
  while IFS= read -r service; do
    service="${service#\*}"
    service="$(echo "$service" | xargs)"
    [[ -z "$service" || "$service" == *VPN* || "$service" == Tailscale* ]] && continue
    sudo networksetup -setdnsservers "$service" 127.0.0.1 || warn "Failed to set DNS for $service"
  done < <(networksetup -listallnetworkservices 2>/dev/null | sed '1d')
}

configure_touchid_macos() {
  local dotfiles_sudo_local="$DOTFILES_DIR/system/pam.d/sudo_local"
  [[ ! -f "$dotfiles_sudo_local" ]] && { warn "sudo_local config not found"; return; }
  
  require_sudo
  info "Enabling Touch ID for sudo"
  
  sudo rm -f /etc/pam.d/sudo_local 2>/dev/null || true
  sudo ln -sf "$dotfiles_sudo_local" /etc/pam.d/sudo_local || warn "Failed to configure Touch ID"
}

configure_dock_macos() {
  [[ "$INSTALL_CASKS" == "true" && -f "$DOCK_CONFIG" ]] || return
  
  info "Configuring Dock"
  zsh "$DOCK_CONFIG" || warn "Dock configuration failed"
}

configure_iterm2_macos() {
  info "Configuring iTerm2"
  defaults write com.googlecode.iterm2 PrefsCustomFolder -string "$HOME/.config/iterm2" 2>/dev/null
  defaults write com.googlecode.iterm2 LoadPrefsFromCustomFolder -bool true 2>/dev/null
  
  mkdir -p "$HOME/.config/iterm2/DynamicProfiles"
  local src="$DOTFILES_DIR/config/iterm2/DynamicProfiles/Stef.json"
  local dst="$HOME/.config/iterm2/DynamicProfiles/Stef.json"
  
  if [[ -f "$src" ]] && ([[ ! -f "$dst" ]] || ! cmp -s "$src" "$dst"); then
    cp "$src" "$dst"
  fi
}

# Linux functions
detect_package_manager() {
  if command -v apt >/dev/null 2>&1; then
    echo "apt"
  elif command -v pacman >/dev/null 2>&1; then
    echo "pacman"
  else
    echo "unknown"
  fi
}

update_system_linux() {
  local pkg_manager
  pkg_manager=$(detect_package_manager)
  require_sudo
  
  case "$pkg_manager" in
    apt)
      sudo apt update && sudo apt upgrade -y
      ;;
    pacman)
      sudo pacman -Syu --noconfirm
      ;;
    *)
      warn "Unknown package manager, skipping system update"
      ;;
  esac
}

install_packages_linux() {
  local pkg_manager
  pkg_manager=$(detect_package_manager)
  require_sudo
  
  case "$pkg_manager" in
    apt)
      local list="$DOTFILES_DIR/bootstrap/archive/base_packages.list"
      if [[ -f "$list" ]]; then
        mapfile -t packages < <(grep -vE '^\s*#|^\s*$' "$list")
        sudo apt install -y "${packages[@]}" || warn "Some packages failed to install"
      else
        warn "Package list not found at $list"
      fi
      ;;
    pacman)
      local packages=(git zsh bat eza fzf htop nmap python screen shellcheck tldr tmux github-cli git-delta glab)
      sudo pacman -S --needed --noconfirm "${packages[@]}" || warn "Some packages failed to install"
      ;;
    *)
      warn "Unknown package manager, skipping package installation"
      ;;
  esac
}

configure_terminal_font_linux() {
  command -v gsettings >/dev/null 2>&1 || return
  
  local profile
  profile=$(gsettings get org.gnome.Terminal.ProfilesList default 2>/dev/null | tr -d "'")
  [[ -n "$profile" ]] || return
  
  local path="org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$profile/"
  gsettings set "$path" font 'JetBrainsMono Nerd Font 14' 2>/dev/null || true
  gsettings set "$path" use-system-font false 2>/dev/null || true
}

# Dotfiles and Git setup
prepare_dotbot() {
  local template="$DOTFILES_DIR/config/git/gitconfig.local.template"
  local target="$DOTFILES_DIR/config/git/gitconfig.local"
  
  if [[ -f "$template" && ! -f "$target" ]]; then
    cp "$template" "$target" || warn "Failed to create gitconfig.local"
  fi
  
  mkdir -p "${XDG_DATA_HOME}/zinit"
}

run_dotbot() {
  prepare_dotbot
  
  if [[ -x "$DOTBOT_INSTALL" ]]; then
    info "Running Dotbot"
    # Ensure script continues even if Dotbot returns non-zero
    set +e
    DOTFILES_SKIP_TOUCHID_LINK=true "$DOTBOT_INSTALL"
    local dotbot_exit=$?
    set -e
    
    if [[ $dotbot_exit -eq 0 ]]; then
      success "Dotbot completed successfully"
    else
      warn "Dotbot reported issues (exit code: $dotbot_exit) but continuing..."
    fi
  else
    error "Dotbot installer not found at $DOTBOT_INSTALL"
    exit 1
  fi
}

is_valid_email() {
  [[ "$1" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]
}

configure_git() {
  [[ "$CONFIGURE_GIT" != "true" ]] && return
  
  local name email
  
  while [[ -z "${name:-}" ]]; do
    read -r -p "Enter Git user.name: " name
    [[ -n "$name" ]] && confirm "Use '$name'?" y && break
    name=""
  done
  
  while [[ -z "${email:-}" ]]; do
    read -r -p "Enter Git user.email: " email
    if [[ -n "$email" ]] && is_valid_email "$email" && confirm "Use '$email'?" y; then
      break
    fi
    email=""
    warn "Please enter a valid email address"
  done
  
  git config --global user.name "$name" || warn "Failed to set git user.name"
  git config --global user.email "$email" || warn "Failed to set git user.email"
}

setup_github_auth() {
  [[ "$GITHUB_AUTH" == "true" ]] || return
  
  if command -v gh >/dev/null 2>&1; then
    info "Setting up GitHub CLI authentication"
    gh auth login --hostname github.com --git-protocol ssh || warn "GitHub authentication failed"
  else
    warn "GitHub CLI not installed"
  fi
}

# Additional setup
run_xdg_cleanup() {
  [[ "$RUN_XDG_CLEANUP" == "true" ]] || return
  
  local script="$DOTFILES_DIR/scripts/system/xdg-cleanup"
  if [[ -x "$script" ]]; then
    info "Running XDG cleanup"
    "$script" --from-bootstrap || warn "XDG cleanup reported issues"
  else
    warn "XDG cleanup script not found"
  fi
}

setup_dev_directory() {
  [[ "$SETUP_DEV_DIR" == "true" ]] || return
  
  local script="$DOTFILES_DIR/scripts/dev/bootstrap_dev_dir.sh"
  if [[ -x "$script" ]]; then
    info "Setting up development directory"
    "$script" || warn "Dev directory setup failed"
  else
    warn "Dev directory script not found"
  fi
}

configure_shell() {
  # Skip if explicitly disabled
  [[ "$CHANGE_SHELL" == "false" ]] && return
  
  local current_shell="${SHELL:-/bin/bash}"
  
  # Check if already using zsh
  if [[ "$current_shell" == */zsh ]]; then
    success "Shell is already zsh"
    return
  fi
  
  # On macOS 10.15+, zsh is default but user might be on older shell
  if is_macos; then
    local macos_version
    macos_version=$(sw_vers -productVersion)
    info "macOS $macos_version detected"
  fi
  
  # Change shell if zsh is available and we're not already using it
  if command -v zsh >/dev/null 2>&1; then
    local zsh_path
    zsh_path=$(command -v zsh)
    
    if [[ "$SHELL" != "$zsh_path" ]]; then
      info "Changing default shell from $current_shell to zsh"
      if chsh -s "$zsh_path"; then
        success "Default shell changed to zsh"
      else
        warn "Failed to change shell to zsh - you may need to logout/login"
      fi
    fi
  else
    warn "zsh not installed, cannot change shell"
  fi
}

# Main execution
bootstrap_macos() {
  step "macOS Bootstrap"
  
  install_xcode_clt
  install_homebrew
  install_packages_macos
  run_dotbot
  configure_git
  setup_github_auth
  configure_services_macos
  configure_dns_macos
  configure_touchid_macos
  configure_dock_macos
  configure_iterm2_macos
}

bootstrap_linux() {
  step "Linux Bootstrap"
  
  update_system_linux
  install_packages_linux
  run_dotbot
  configure_git
  setup_github_auth
  configure_terminal_font_linux
}

# Resolve user prompts for "ask" options (only for optional items)
resolve_user_options() {
  info "Configuring optional components..."
  
  if is_macos; then
    resolve_option INSTALL_MAS_APPS "Install Mac App Store apps?" n
    resolve_option INSTALL_OFFICE_TOOLS "Install Microsoft Office tools?" n
    resolve_option INSTALL_SLACK "Install Slack?" n
    resolve_option INSTALL_PARALLELS "Install Parallels Desktop?" n
    resolve_option CONFIGURE_DNS "Configure DNS to use dnsmasq?" n
  fi
}

main() {
  info "Starting dotfiles bootstrap"
  
  export TERM="${TERM:-xterm-256color}"
  export BOOTSTRAP_MODE=1
  
  resolve_user_options
  setup_directories
  fix_repository_ownership
  
  if is_macos; then
    bootstrap_macos
  elif is_linux; then
    bootstrap_linux
  else
    error "Unsupported OS: $(uname)"
    exit 1
  fi
  
  configure_shell
  run_xdg_cleanup
  setup_dev_directory
  
  step "Bootstrap Complete"
  success "Dotfiles bootstrap finished successfully"
  
  if is_macos; then
    info "Restart your terminal to apply all changes"
    if confirm "Quit Terminal.app now?" y; then
      osascript -e 'tell application "Terminal" to quit' 2>/dev/null || true
    fi
  else
    info "Open a new terminal to apply all changes"
  fi
}

main "$@"
