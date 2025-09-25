#!/usr/bin/env bash

# ──────────────────────────────────────────────────────────────────────────────
# Unified Bootstrap (macOS 26 "Tahoe" and modern Linux)
# - Respects XDG Base Directory Spec
# - Uses Dotbot for linking
# - Installs packages (Homebrew on macOS; apt/pacman on Linux)
# - Preserves and improves interactive prompts
# - Safe to run multiple times (idempotent where practical)
#
# Notes
# - macOS flow is feature-complete for initial setup: CLT, Homebrew, Brewfile
#   (optional casks/services), DNS (optional), Dock, Touch ID, iTerm2, Dotbot,
#   Git config, optional gh auth, SSH sockets, optional shell change.
# - Linux flow installs base packages (apt/pacman), Dotbot, Git config, optional
#   gh auth, SSH sockets, optional GNOME Terminal font.
# - Advanced Linux installers (Docker, kubectl, kind, Helm, Terraform, AWS CLI,
#   Fastfetch, Oh My Posh, Nerd Fonts, bat symlink) are not yet ported here and
#   remain in archived scripts for reference.
# - Interactive prompts can be bypassed with env flags: INSTALL_CASKS,
#   INSTALL_SERVICES, CONFIGURE_DNS, GITHUB_AUTH, CHANGE_SHELL.
# - This script is designed for iterative testing and refinement.
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ----------------------------------------------------------------------------
# Common: Colors and logging
# ----------------------------------------------------------------------------
_color() { command -v tput >/dev/null 2>&1 && tput setaf "$1" || true; }
_reset() { command -v tput >/dev/null 2>&1 && tput sgr0 || true; }
INFO=$(_color 2); WARN=$(_color 3); ERR=$(_color 1); RST=$(_reset)
log_info()    { printf "%b[INFO]%b %s\n"    "$INFO" "$RST" "$*"; }
log_warning() { printf "%b[WARNING]%b %s\n" "$WARN" "$RST" "$*"; }
log_error()   { printf "%b[ERROR]%b %s\n"   "$ERR"  "$RST" "$*" 1>&2; }

err_trap() { log_error "Bootstrap failed at line $1"; }
trap 'err_trap $LINENO' ERR

# ----------------------------------------------------------------------------
# Common: Guards and constants
# ----------------------------------------------------------------------------
if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
  log_error "Do not run as root; run as your user (we'll sudo when needed)."
  exit 1
fi

readonly DOTFILES_DIR="$HOME/.dotfiles"
readonly DOTBOT_INSTALL="$DOTFILES_DIR/install"
readonly BREWFILE_MACOS="$DOTFILES_DIR/bootstrap/Brewfile"
readonly DOCK_CONFIG="$DOTFILES_DIR/config/dock/dock_config.zsh"

# XDG (export early so sub-steps can rely on it)
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

# Other common dirs used by this repo
export ZSH_SESSION_DIR="$HOME/.zsh_sessions"
export DOTFILES="$DOTFILES_DIR"

# Options (can be pre-seeded via env for non-interactive runs)
INSTALL_CASKS=${INSTALL_CASKS:-ask}
INSTALL_SERVICES=${INSTALL_SERVICES:-ask}
CONFIGURE_DNS=${CONFIGURE_DNS:-ask}
GITHUB_AUTH=${GITHUB_AUTH:-ask}
CHANGE_SHELL=${CHANGE_SHELL:-ask}

# ----------------------------------------------------------------------------
# Helpers: prompts and sudo keep-alive
# ----------------------------------------------------------------------------
yesno() {
  # yesno "Question?" default_no|default_yes|no_prompt -> returns 0 for yes
  local prompt default reply
  prompt="$1"; default="${2:-default_no}"
  case "$default" in
    default_yes) read -r -p "$prompt [Y/n] " reply || true ;;
    no_prompt)   reply=y ;;
    *)           read -r -p "$prompt [y/N] " reply || true ;;
  esac
  [[ "$reply" =~ ^([Yy]|[Yy][Ee][Ss])$ ]] && return 0 || return 1
}

ensure_sudo() {
  # Ensure we have sudo credentials, prompting if necessary
  if ! sudo -n true 2>/dev/null; then
    log_info "Administrator privileges required for system operations…"
    if ! sudo -v; then
      log_error "Failed to acquire sudo credentials"
      return 1
    fi
  fi
}

# ----------------------------------------------------------------------------
# Common: XDG directory creation and repo ownership sanity
# ----------------------------------------------------------------------------
ensure_directories() {
  mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME"
  mkdir -p "$ZSH_SESSION_DIR" "$HOME/.ssh/sockets"
  chmod 700 "$HOME/.ssh" "$HOME/.ssh/sockets" 2>/dev/null || true
}

ensure_repo_writable() {
  if [[ ! -w "$DOTFILES_DIR" ]]; then
    log_warning "Dotfiles repo not writable by $(id -un); attempting chown…"
    sudo chown -R "$(id -un):$(id -gn)" "$DOTFILES_DIR" || log_warning "Could not chown $DOTFILES_DIR"
  fi
}

# ----------------------------------------------------------------------------
# macOS specific helpers
# ----------------------------------------------------------------------------
macos_is() { [[ "$(uname)" == "Darwin" ]]; }

macos_require_clt() {
  log_info "Checking Xcode Command Line Tools…"
  if ! xcode-select -p >/dev/null 2>&1; then
    xcode-select --install || true
    log_info "Waiting for CLT to be installed…"
    until xcode-select -p >/dev/null 2>&1; do sleep 10; done
  fi
}

macos_install_homebrew() {
  if ! command -v brew >/dev/null 2>&1; then
    log_info "Installing Homebrew…"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  else
    log_info "Homebrew already installed"
  fi

  # shellenv (runtime only; permanent config handled by your zprofile)
  if [[ "$(uname -m)" == "arm64" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  else
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

macos_install_brewfile() {
  local brewfile="$BREWFILE_MACOS"
  if [[ ! -f "$brewfile" ]]; then
    log_warning "No Brewfile found at $brewfile; skipping brew bundle"
    return
  fi

  log_info "Preparing Brewfile install…"
  local tmp=; tmp=$(mktemp)
  cp "$brewfile" "$tmp"

  # Handle optional sections
  if [[ "$INSTALL_CASKS" == "ask" ]]; then
    yesno "Install Homebrew cask apps?" default_yes && INSTALL_CASKS=yes || INSTALL_CASKS=no
  fi
  if [[ "$INSTALL_SERVICES" == "ask" ]]; then
    yesno "Install Tailscale and dnsmasq?" default_yes && INSTALL_SERVICES=yes || INSTALL_SERVICES=no
  fi

  if [[ "$INSTALL_CASKS" == "no" ]]; then
    # Keep nerd font cask installed separately later if needed; remove other casks and mas
    sed -i '' -e '/^cask "font-jetbrains-mono-nerd-font"/!{/^cask /d;}' -e '/^mas /d' "$tmp" || true
  fi

  if [[ "$INSTALL_SERVICES" == "no" ]]; then
    sed -i '' -e '/brew "tailscale"/d' -e '/brew "dnsmasq"/d' "$tmp" || true
  fi

  log_info "Running brew bundle…"
  brew bundle --file="$tmp" || log_warning "Some brew bundle items failed"
  rm -f "$tmp"

  # Ensure JetBrains Mono Nerd Font (if not in filtered Brewfile)
  if ! brew list --cask font-jetbrains-mono-nerd-font >/dev/null 2>&1; then
    brew install --cask font-jetbrains-mono-nerd-font || log_warning "Failed to install Nerd Font"
  fi
}

macos_configure_dock() {
  [[ "$INSTALL_CASKS" == "no" ]] && { log_info "Skipping Dock config (casks not installed)"; return; }
  if [[ -f "$DOCK_CONFIG" ]]; then
    log_info "Configuring Dock…"
    zsh "$DOCK_CONFIG" || log_warning "Dock configuration script failed"
  else
    log_warning "Dock config not found at $DOCK_CONFIG"
  fi
}

macos_enable_services() {
  [[ "$INSTALL_SERVICES" == "no" ]] && { log_info "Skipping services"; return; }
  if ! command -v brew >/dev/null 2>&1; then return; fi
  
  ensure_sudo || {
    log_warning "Could not acquire sudo credentials, skipping service startup"
    return
  }
  
  local svcs=(tailscale dnsmasq)
  for s in "${svcs[@]}"; do
    if brew list "$s" >/dev/null 2>&1; then
      log_info "Starting $s as root via brew services…"
      sudo brew services start "$s" || log_warning "Failed to start $s"
    fi
  done
}

macos_configure_dns() {
  # Only offer DNS configuration if dnsmasq is actually installed
  if ! command -v brew >/dev/null 2>&1 || ! brew list dnsmasq >/dev/null 2>&1; then
    log_info "dnsmasq not installed, skipping DNS configuration"
    return
  fi
  
  if [[ "$CONFIGURE_DNS" == "ask" ]]; then
    yesno "Configure system DNS to 127.0.0.1 for dnsmasq?" default_no && CONFIGURE_DNS=yes || CONFIGURE_DNS=no
  fi
  [[ "$CONFIGURE_DNS" != "yes" ]] && { log_info "Skipping DNS configuration"; return; }

  ensure_sudo || {
    log_warning "Could not acquire sudo credentials, skipping DNS configuration"
    return
  }

  log_info "Setting DNS servers to 127.0.0.1 for all non‑VPN services…"
  local svc
  while IFS= read -r svc; do
    svc="${svc#\*}"; svc="$(echo "$svc" | xargs)"
    [[ -z "$svc" || "$svc" == *VPN* || "$svc" == Tailscale* ]] && continue
    sudo networksetup -setdnsservers "$svc" 127.0.0.1 || log_warning "Failed DNS on $svc"
  done < <(networksetup -listallnetworkservices 2>/dev/null | sed '1d')
}

macos_enable_touchid() {
  log_info "Enabling Touch ID for sudo (sudo_local)…"
  
  # Check if PAM directory exists (should always exist on macOS)
  if [[ ! -d /etc/pam.d ]]; then
    log_warning "PAM directory /etc/pam.d not found, skipping Touch ID setup"
    return
  fi

  # Check if our dotfiles sudo_local exists
  local dotfiles_sudo_local="$DOTFILES_DIR/system/pam.d/sudo_local"
  if [[ ! -f "$dotfiles_sudo_local" ]]; then
    log_warning "Dotfiles sudo_local not found at $dotfiles_sudo_local, skipping Touch ID setup"
    return
  fi

  ensure_sudo || {
    log_warning "Could not acquire sudo credentials, skipping Touch ID setup"
    return
  }

  # Force remove any existing sudo_local (file or symlink)
  if [[ -e /etc/pam.d/sudo_local || -L /etc/pam.d/sudo_local ]]; then
    log_info "Removing existing sudo_local…"
    sudo rm -f /etc/pam.d/sudo_local || {
      log_warning "Could not remove existing sudo_local"
      return
    }
  fi

  # Create symlink to our dotfiles version
  log_info "Creating symlink to dotfiles sudo_local…"
  sudo ln -sf "$dotfiles_sudo_local" /etc/pam.d/sudo_local || {
    log_warning "Could not create symlink to dotfiles sudo_local"
    return
  }

  log_info "Touch ID for sudo configured successfully"
}

macos_configure_iterm2() {
  log_info "Configuring iTerm2 preferences…"
  defaults write com.googlecode.iterm2 PrefsCustomFolder -string "$HOME/.config/iterm2"
  defaults write com.googlecode.iterm2 LoadPrefsFromCustomFolder -bool true
  mkdir -p "$HOME/.config/iterm2/DynamicProfiles"
  local src="$DOTFILES_DIR/config/iterm2/DynamicProfiles/Stef.json"
  local dst="$HOME/.config/iterm2/DynamicProfiles/Stef.json"
  if [[ -f "$src" ]]; then
    if [[ ! -f "$dst" ]] || ! cmp -s "$src" "$dst"; then
      cp "$src" "$dst"
      log_info "Updated iTerm2 dynamic profile"
    else
      log_info "iTerm2 dynamic profile already up to date"
    fi
  fi
}

# ----------------------------------------------------------------------------
# Linux specific helpers
# ----------------------------------------------------------------------------
linux_is() { [[ "$(uname)" == "Linux" ]]; }

linux_pkg_manager=""
linux_detect_pkgmgr() {
  if command -v apt >/dev/null 2>&1; then linux_pkg_manager=apt; return; fi
  if command -v pacman >/dev/null 2>&1; then linux_pkg_manager=pacman; return; fi
  linux_pkg_manager=unknown
}

linux_update_system() {
  case "$linux_pkg_manager" in
    apt)
      sudo apt update
      sudo apt upgrade -y || true
      ;;
    pacman)
      sudo pacman -Syu --noconfirm || true
      ;;
    *) log_warning "Unknown package manager; skipping update" ;;
  esac
}

linux_install_base_packages() {
  case "$linux_pkg_manager" in
    apt)
  local list="$DOTFILES_DIR/bootstrap/archive/base_packages.list"
      if [[ -f "$list" ]]; then
        # filter comments/empty
        mapfile -t pkgs < <(grep -vE '^\s*#' "$list" | sed '/^\s*$/d')
        sudo apt install -y "${pkgs[@]}" || log_warning "Some apt packages failed"
      else
        log_warning "Package list not found at $list"
      fi
      ;;
    pacman)
      # Best-effort mapping for common packages
      local pkgs=(git zsh bat eza fzf htop nmap python screen shellcheck tldr tmux github-cli git-delta glab)
      sudo pacman -S --needed --noconfirm "${pkgs[@]}" || log_warning "Some pacman packages failed"
      ;;
  esac
}

linux_manual_installs() {
  # Keep this lightweight: Docker/Kubernetes/Helm/Terraform can be added as needed
  :
}

linux_set_terminal_font() {
  # Optional: attempt to set Nerd Font for GNOME
  if command -v gsettings >/dev/null 2>&1; then
    local prof
    prof=$(gsettings get org.gnome.Terminal.ProfilesList default 2>/dev/null | tr -d "'") || true
    if [[ -n "$prof" ]]; then
      local path="org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$prof/"
      gsettings set "$path" font 'JetBrainsMono Nerd Font 14' || true
      gsettings set "$path" use-system-font false || true
    fi
  fi
}

# ----------------------------------------------------------------------------
# Dotbot linking and git config
# ----------------------------------------------------------------------------
prepare_dotbot_dependencies() {
  # Create gitconfig.local from template if it doesn't exist
  local template="$DOTFILES_DIR/config/git/gitconfig.local.template"
  local target="$DOTFILES_DIR/config/git/gitconfig.local"
  if [[ -f "$template" && ! -f "$target" ]]; then
    log_info "Creating gitconfig.local from template…"
    cp "$template" "$target" || log_warning "Failed to create gitconfig.local"
  fi

  # Ensure XDG directories exist for zinit and other tools
  mkdir -p "${XDG_DATA_HOME:-$HOME/.local/share}/zinit"
  mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}"
  mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}"
  mkdir -p "${XDG_STATE_HOME:-$HOME/.local/state}"
}

run_dotbot() {
  prepare_dotbot_dependencies
  if [[ -x "$DOTBOT_INSTALL" ]]; then
    log_info "Running Dotbot…"
    "$DOTBOT_INSTALL" -v || log_warning "Dotbot reported issues"
  else
    log_error "Dotbot installer not found at $DOTBOT_INSTALL"
  fi
}

validate_email() {
  local email="$1"
  # Basic email validation regex
  [[ "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]
}

setup_git() {
  local name email
  
  # Get git user name
  while [[ -z "${GIT_USER_NAME:-}" ]]; do 
    read -r -p "Enter global Git user.name: " name
    if [[ -n "$name" ]]; then
      GIT_USER_NAME="$name"
    else
      log_warning "Name cannot be empty"
    fi
  done
  
  # Get and validate git user email
  while [[ -z "${GIT_USER_EMAIL:-}" ]]; do 
    read -r -p "Enter global Git user.email: " email
    if [[ -z "$email" ]]; then
      log_warning "Email cannot be empty"
      continue
    fi
    
    if validate_email "$email"; then
      echo "Email: $email"
      if yesno "Is this email correct?" default_yes; then
        GIT_USER_EMAIL="$email"
      else
        log_info "Please enter your email again"
      fi
    else
      log_warning "Invalid email format. Please enter a valid email address (e.g., user@example.com)"
    fi
  done
  
  git config --global user.name "$GIT_USER_NAME" || log_warning "Failed to set git user.name"
  git config --global user.email "$GIT_USER_EMAIL" || log_warning "Failed to set git user.email"
}

github_auth() {
  if [[ "$GITHUB_AUTH" == "ask" ]]; then
    yesno "Login with GitHub CLI now?" default_yes && GITHUB_AUTH=yes || GITHUB_AUTH=no
  fi
  [[ "$GITHUB_AUTH" != "yes" ]] && return
  if command -v gh >/dev/null 2>&1; then
    gh auth login --hostname github.com --git-protocol ssh || log_warning "gh auth login failed"
  else
    log_warning "gh CLI not installed; skipping GitHub login"
  fi
}

# ----------------------------------------------------------------------------
# Terminal management (macOS)
# ----------------------------------------------------------------------------
macos_quit_terminal() {
  log_info "Quitting Terminal.app to apply changes…"
  osascript -e 'tell application "Terminal" to quit'
  log_info "Terminal.app closed"
}

# ----------------------------------------------------------------------------
# Change login shell to zsh (optional)
# ----------------------------------------------------------------------------
maybe_change_shell() {
  # Check current shell
  local current_shell="${SHELL:-$(getent passwd "$USER" 2>/dev/null | cut -d: -f7 || echo)}"
  current_shell="${current_shell:-/bin/bash}"  # fallback
  
  log_info "Current shell: $current_shell"
  
  if [[ "$current_shell" == */zsh ]]; then
    log_info "Shell is already zsh, skipping shell change"
    return
  fi

  if [[ "$CHANGE_SHELL" == "ask" ]]; then
    yesno "Change your default shell to zsh?" default_yes && CHANGE_SHELL=yes || CHANGE_SHELL=no
  fi
  [[ "$CHANGE_SHELL" != "yes" ]] && return

  if command -v zsh >/dev/null 2>&1; then
    local zpath
    zpath=$(command -v zsh) || {
      log_warning "Could not determine zsh path"
      return
    }
    
    if [[ "$SHELL" != "$zpath" ]]; then
      log_info "Changing default shell to $zpath…"
      # Temporarily disable error trapping for this operation
      set +e
      chsh -s "$zpath" "${USER}"
      local chsh_result=$?
      set -e
      
      if [[ $chsh_result -ne 0 ]]; then
        log_warning "Could not change default shell (exit code: $chsh_result)"
        log_info "You can change it manually later with: chsh -s $zpath"
      else
        log_info "Default shell changed successfully"
      fi
    else
      log_info "Default shell already zsh"
    fi
  else
    log_warning "zsh not installed; cannot change default shell"
  fi
}

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------
main() {
  log_info "Starting unified bootstrap…"
  
  # Set terminal environment to minimize color/escape sequence issues
  export TERM="${TERM:-xterm-256color}"
  export COLORTERM="${COLORTERM:-truecolor}"
  
  # Suppress potential shell startup warnings during bootstrap
  export BOOTSTRAP_MODE=1
  
  ensure_directories
  ensure_repo_writable

  if macos_is; then
    log_info "Detected macOS ($(sw_vers -productVersion 2>/dev/null || echo))"
    macos_require_clt
    macos_install_homebrew
    macos_install_brewfile
    run_dotbot
    setup_git
    github_auth
    macos_enable_services
    macos_configure_dock
    macos_configure_dns
    macos_enable_touchid
    macos_configure_iterm2
  elif linux_is; then
    log_info "Detected Linux"
    linux_detect_pkgmgr
    linux_update_system
    linux_install_base_packages
    linux_manual_installs
    run_dotbot
    setup_git
    github_auth
    linux_set_terminal_font
  else
    log_error "Unsupported OS: $(uname)"
    exit 1
  fi

  log_info "Creating SSH socket directory…"
  mkdir -p "$HOME/.ssh/sockets" && chmod 700 "$HOME/.ssh/sockets"

  maybe_change_shell
  
  log_info "Bootstrap complete!"
  log_info ""
  
  if macos_is; then
    log_info "To apply all changes, you need to restart your terminal."
    log_info "This will:"
    log_info "  • Pick up the new shell configuration"
    log_info "  • Allow zinit and other tools to initialize properly"
    log_info "  • Ensure all environment variables are set correctly"
    log_info ""
    if yesno "Quit Terminal.app now (you can then open iTerm2 or a new Terminal)?" default_yes; then
      macos_quit_terminal
    else
      log_info "Please restart your terminal manually when ready"
    fi
  else
    log_info "IMPORTANT: Close this terminal and open a new one to:"
    log_info "  • Pick up the new shell configuration"
    log_info "  • Allow zinit and other tools to initialize properly"
    log_info "  • Ensure all environment variables are set correctly"
  fi
}

main "$@"
