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
#   INSTALL_MAS_APPS, INSTALL_SERVICES, INSTALL_OFFICE_TOOLS, INSTALL_SLACK, 
#   INSTALL_PARALLELS, CONFIGURE_DNS, GITHUB_AUTH, CHANGE_SHELL, SETUP_DEV_DIR,
#   RUN_XDG_CLEANUP, or by setting UNATTENDED_MODE=true for full automation.
# - This script is designed for iterative testing and refinement.
# ──────────────────────────────────────────────────────────────────────────────

set -euo pipefail

# ----------------------------------------------------------------------------
# Common: Colors and logging
# ----------------------------------------------------------------------------
_color() { command -v tput >/dev/null 2>&1 && tput setaf "$1" || true; }
_reset() { command -v tput >/dev/null 2>&1 && tput sgr0 || true; }
INFO=$(_color 2); WARN=$(_color 3); ERR=$(_color 1); STEP=$(_color 4); RST=$(_reset)
log_info()    { [[ "${DEBUG_MODE:-false}" == "true" ]] && printf "%b[INFO]%b %s\n"    "$INFO" "$RST" "$*"; }
log_warning() { printf "%b[WARNING]%b %s\n" "$WARN" "$RST" "$*"; }
log_error()   { printf "%b[ERROR]%b %s\n"   "$ERR"  "$RST" "$*" 1>&2; }
announce_step() {
  if [[ -n "$STEP" && -n "$RST" ]]; then
    printf "%b→%b %s\n" "$STEP" "$RST" "$1"
  else
    printf "→ %s\n" "$1"
  fi
}

SUDO_KEEPALIVE_PID=""

cleanup() {
  if [[ -n "${SUDO_KEEPALIVE_PID:-}" ]]; then
    kill "${SUDO_KEEPALIVE_PID}" 2>/dev/null || true
    wait "${SUDO_KEEPALIVE_PID}" 2>/dev/null || true
    SUDO_KEEPALIVE_PID=""
  fi
}

trap cleanup EXIT

err_trap() { log_error "Bootstrap failed at line $1"; }
trap 'err_trap $LINENO' ERR

# ----------------------------------------------------------------------------
# Command-line argument parsing
# ----------------------------------------------------------------------------
normalize_bool_var() {
  local var_name="$1"
  local value="${!var_name:-}"

  if [[ -z "$value" ]]; then
    printf -v "$var_name" "false"
    return
  fi

  case "$(echo "$value" | tr '[:upper:]' '[:lower:]')" in
    true|yes|1|on)
      printf -v "$var_name" "true"
      ;;
    false|no|0|off)
      printf -v "$var_name" "false"
      ;;
    *)
      log_error "Invalid value for $var_name: $value (expected true/false)"
      exit 1
      ;;
  esac
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      -d|--debug)
        DEBUG_MODE="true"
        ;;
      -u|--unattended)
        UNATTENDED_MODE="true"
        ;;
      -h|--help)
        show_help
        exit 0
        ;;
      --)
        shift
        break
        ;;
      -* )
        log_error "Unknown option: $1"
        show_help
        exit 1
        ;;
      *)
        log_error "Unexpected argument: $1"
        show_help
        exit 1
        ;;
    esac
    shift
  done

  normalize_bool_var DEBUG_MODE
  normalize_bool_var UNATTENDED_MODE
}

show_help() {
  cat << EOF
Unified Bootstrap Script for macOS and Linux

USAGE:
  $0 [OPTIONS]

OPTIONS:
  -d, --debug        Enable verbose debug logging
  -u, --unattended   Run without interactive prompts (uses safe defaults)
  -h, --help         Show this help message

EXAMPLES:
  $0                    # Interactive mode with minimal logging (default)
  $0 --debug            # Interactive mode with verbose logging  
  $0 --unattended       # Unattended mode with minimal logging
  $0 --debug --unattended  # Unattended mode with verbose logging

ENVIRONMENT VARIABLES:
  You can also set these via environment variables:
  DEBUG_MODE=true UNATTENDED_MODE=true $0
  
  Or override specific install options:
  INSTALL_CASKS=no INSTALL_OFFICE_TOOLS=yes $0

For more details, see the script header comments.
EOF
}

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

# Default values for command-line flags
DEBUG_MODE=${DEBUG_MODE:-false}
UNATTENDED_MODE=${UNATTENDED_MODE:-false}

# Options (can be pre-seeded via env for non-interactive runs)
INSTALL_CASKS=${INSTALL_CASKS:-ask}
INSTALL_MAS_APPS=${INSTALL_MAS_APPS:-ask}
INSTALL_SERVICES=${INSTALL_SERVICES:-ask}
INSTALL_OFFICE_TOOLS=${INSTALL_OFFICE_TOOLS:-ask}
INSTALL_SLACK=${INSTALL_SLACK:-ask}
INSTALL_PARALLELS=${INSTALL_PARALLELS:-ask}
CONFIGURE_DNS=${CONFIGURE_DNS:-ask}
GITHUB_AUTH=${GITHUB_AUTH:-ask}
CHANGE_SHELL=${CHANGE_SHELL:-ask}
SETUP_DEV_DIR=${SETUP_DEV_DIR:-ask}
RUN_XDG_CLEANUP=${RUN_XDG_CLEANUP:-ask}

# ----------------------------------------------------------------------------
# Unattended mode setup
# ----------------------------------------------------------------------------
setup_unattended_mode() {
  # Only set defaults if unattended mode was explicitly requested
  if [[ "${UNATTENDED_MODE}" == "true" ]]; then
    if [[ "${DEBUG_MODE}" == "true" ]]; then
      echo "Running in unattended mode with these defaults:"
      echo "  • Install casks: yes"
      echo "  • Install Mac App Store apps: no"  
      echo "  • Install services (Tailscale, dnsmasq): yes"
      echo "  • Install office tools: no"
      echo "  • Install Slack: no"
      echo "  • Install Parallels: no"
      echo "  • Configure DNS: yes"
      echo "  • GitHub CLI login: no"
      echo "  • Change shell: no"
      echo "  • Setup dev directory: no"
      echo "  • Run XDG cleanup: yes"
      echo "  • Git setup: skipped"
      echo ""
    else
      echo "Running in unattended mode."
    fi
    
    # Set defaults for unattended mode (override "ask" values)
    [[ "$INSTALL_CASKS" == "ask" ]] && INSTALL_CASKS=yes
    [[ "$INSTALL_MAS_APPS" == "ask" ]] && INSTALL_MAS_APPS=no
    [[ "$INSTALL_SERVICES" == "ask" ]] && INSTALL_SERVICES=yes
    [[ "$INSTALL_OFFICE_TOOLS" == "ask" ]] && INSTALL_OFFICE_TOOLS=no
    [[ "$INSTALL_SLACK" == "ask" ]] && INSTALL_SLACK=no
    [[ "$INSTALL_PARALLELS" == "ask" ]] && INSTALL_PARALLELS=no
    [[ "$CONFIGURE_DNS" == "ask" ]] && CONFIGURE_DNS=yes
    [[ "$GITHUB_AUTH" == "ask" ]] && GITHUB_AUTH=no
    [[ "$CHANGE_SHELL" == "ask" ]] && CHANGE_SHELL=no
    [[ "$SETUP_DEV_DIR" == "ask" ]] && SETUP_DEV_DIR=no
    [[ "$RUN_XDG_CLEANUP" == "ask" ]] && RUN_XDG_CLEANUP=yes
  fi
}

# ----------------------------------------------------------------------------
# Helpers: prompts and sudo keep-alive
# ----------------------------------------------------------------------------
start_sudo_keepalive() {
  if [[ -n "${SUDO_KEEPALIVE_PID:-}" ]] && kill -0 "${SUDO_KEEPALIVE_PID}" 2>/dev/null; then
    return
  fi

  (
    while true; do
      if ! sudo -n -v >/dev/null 2>&1; then
        printf "\n⚠ Cached sudo credentials expired; rerun 'sudo -v' to resume privileged steps.\n" >&2
        break
      fi
      sleep "${SUDO_KEEPALIVE_INTERVAL:-60}"
    done
  ) &
  SUDO_KEEPALIVE_PID=$!
}

yesno() {
  # yesno "Question?" default_no|default_yes|no_prompt -> returns 0 for yes
  local prompt default reply
  prompt="$1"; default="${2:-default_no}"
  # In unattended mode, use defaults without prompting
  if [[ "${UNATTENDED_MODE:-false}" == "true" ]]; then
    case "$default" in
      default_yes) return 0 ;;
      no_prompt)   return 0 ;;
      *)           return 1 ;;
    esac
  fi
  
  while true; do
    case "$default" in
      default_yes) read -r -p "$prompt [Y/n] " reply || true ;;
      no_prompt)   reply=y ;;
      *)           read -r -p "$prompt [y/N] " reply || true ;;
    esac
    
    # Handle empty input (use default)
    if [[ -z "$reply" ]]; then
      case "$default" in
        default_yes|no_prompt) return 0 ;;
        *) return 1 ;;
      esac
    fi
    
    # Validate input
    case "$(echo "$reply" | tr '[:upper:]' '[:lower:]')" in  # Convert to lowercase
      y|yes) return 0 ;;
      n|no)  return 1 ;;
      *) 
        echo "Please enter 'y' for yes or 'n' for no"
        continue
        ;;
    esac
  done
}

ensure_sudo() {
  # Ensure we have sudo credentials, prompting if necessary
  if ! sudo -n true 2>/dev/null; then
    if [[ "${UNATTENDED_MODE:-false}" == "true" ]]; then
      local wait_total=${SUDO_REFRESH_TIMEOUT:-120}
      local wait_step=${SUDO_REFRESH_INTERVAL:-5}
      local waited=0

      echo "❌ Administrator privileges are required but no cached sudo credentials were found." >&2
      echo "   Run 'sudo -v' in another terminal or session." >&2
      echo "   Waiting up to ${wait_total}s for refreshed credentials…" >&2

      while (( waited < wait_total )); do
        sleep "$wait_step"
        (( waited += wait_step ))
        if sudo -n true 2>/dev/null; then
          echo "   ✓ Sudo credentials refreshed; resuming." >&2
          start_sudo_keepalive
          return 0
        fi
      done

      echo "   ✗ Timed out waiting for sudo credentials. Exiting." >&2
      exit 1
    fi

    echo "→ Administrator privileges required for system operations…"
    if ! sudo -v; then
      echo "✗ Failed to acquire sudo credentials" >&2
      return 1
    fi
    echo "✓ Administrator privileges confirmed"
  fi

  start_sudo_keepalive
}

sudo_run() {
  local display_cmd
  display_cmd=$(printf '%q ' "$@")
  display_cmd=${display_cmd% }

  if sudo -n "$@"; then
    start_sudo_keepalive
    return 0
  fi

  if [[ "${UNATTENDED_MODE:-false}" == "true" ]]; then
    echo "❌ Unable to run 'sudo ${display_cmd}' without prompting." >&2
    echo "   Refresh credentials with 'sudo -v' and rerun, or run interactively." >&2
    exit 1
  fi

  sudo "$@"
  local status=$?
  if [[ $status -eq 0 ]]; then
    start_sudo_keepalive
  fi
  return $status
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
    echo "⚠ Dotfiles repo not writable by $(id -un); attempting chown…" >&2
    if sudo_run chown -R "$(id -un):$(id -gn)" "$DOTFILES_DIR"; then
      echo "✓ Repository ownership fixed"
    else
      echo "✗ Could not chown $DOTFILES_DIR" >&2
    fi
  fi
}

# ----------------------------------------------------------------------------
# macOS specific helpers
# ----------------------------------------------------------------------------
macos_is() { [[ "$(uname)" == "Darwin" ]]; }

macos_require_clt() {
  echo "Checking Xcode Command Line Tools…"
  if ! xcode-select -p >/dev/null 2>&1; then
    xcode-select --install || true
    echo "Waiting for CLT to be installed…"
    until xcode-select -p >/dev/null 2>&1; do sleep 10; done
  fi
}

macos_install_homebrew() {
  if ! command -v brew >/dev/null 2>&1; then
    echo "Installing Homebrew…"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  else
    echo "Homebrew already installed"
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
    echo "⚠ No Brewfile found at $brewfile; skipping brew bundle" >&2
    return
  fi

  echo "Preparing Brewfile install…"
  local tmp=; tmp=$(mktemp)
  cp "$brewfile" "$tmp"

  # Handle optional sections
  if [[ "$INSTALL_CASKS" == "ask" ]]; then
    yesno "Install Homebrew cask apps?" default_yes && INSTALL_CASKS=yes || INSTALL_CASKS=no
  fi
  if [[ "$INSTALL_MAS_APPS" == "ask" ]]; then
    yesno "Install Mac App Store apps?" default_no && INSTALL_MAS_APPS=yes || INSTALL_MAS_APPS=no
  fi
  if [[ "$INSTALL_SERVICES" == "ask" ]]; then
    yesno "Install Tailscale and dnsmasq?" default_yes && INSTALL_SERVICES=yes || INSTALL_SERVICES=no
  fi
  if [[ "$INSTALL_OFFICE_TOOLS" == "ask" ]]; then
    yesno "Install Microsoft Office tools (Excel, PowerPoint, Word, Teams)?" default_no && INSTALL_OFFICE_TOOLS=yes || INSTALL_OFFICE_TOOLS=no
  fi
  if [[ "$INSTALL_SLACK" == "ask" ]]; then
    yesno "Install Slack?" default_no && INSTALL_SLACK=yes || INSTALL_SLACK=no
  fi
  if [[ "$INSTALL_PARALLELS" == "ask" ]]; then
    yesno "Install Parallels virtualization software?" default_no && INSTALL_PARALLELS=yes || INSTALL_PARALLELS=no
  fi

  if [[ "$INSTALL_CASKS" == "no" ]]; then
    # Keep nerd font cask installed separately later if needed; remove other casks
    sed -i '' -e '/^cask "font-jetbrains-mono-nerd-font"/!{/^cask /d;}' "$tmp" || true
  fi

  if [[ "$INSTALL_MAS_APPS" == "no" ]]; then
    sed -i '' -e '/^mas /d' "$tmp" || true
  fi

  if [[ "$INSTALL_SERVICES" == "no" ]]; then
    sed -i '' -e '/brew "tailscale"/d' -e '/brew "dnsmasq"/d' "$tmp" || true
  fi

  if [[ "$INSTALL_OFFICE_TOOLS" == "no" ]]; then
    sed -i '' -e '/cask "microsoft-teams"/d' \
           -e '/mas "Microsoft Excel"/d' \
           -e '/mas "Microsoft PowerPoint"/d' \
           -e '/mas "Microsoft Word"/d' "$tmp" || true
  fi

  if [[ "$INSTALL_SLACK" == "no" ]]; then
    sed -i '' -e '/mas "Slack"/d' "$tmp" || true
  fi

  if [[ "$INSTALL_PARALLELS" == "no" ]]; then
    sed -i '' -e '/cask "parallels"/d' "$tmp" || true
  fi

  echo "Running brew bundle…"
  if brew bundle --file="$tmp"; then
    echo "✓ Homebrew packages installed successfully"
  else
    echo "⚠ Some Homebrew packages failed to install" >&2
  fi
  rm -f "$tmp"

  # Ensure JetBrains Mono Nerd Font (if not in filtered Brewfile)
  if ! brew list --cask font-jetbrains-mono-nerd-font >/dev/null 2>&1; then
    echo "  • Installing JetBrains Mono Nerd Font..."
    if brew install --cask font-jetbrains-mono-nerd-font; then
      echo "    ✓ JetBrains Mono Nerd Font installed"
    else
      echo "    ⚠ Failed to install Nerd Font" >&2
    fi
  fi
}

macos_configure_dock() {
  [[ "$INSTALL_CASKS" == "no" ]] && { echo "→ Skipping Dock config (casks not installed)"; return; }
  if [[ -f "$DOCK_CONFIG" ]]; then
    echo "→ Configuring Dock…"
    if zsh "$DOCK_CONFIG"; then
      echo "✓ Dock configuration completed"
    else
      echo "⚠ Dock configuration script failed" >&2
    fi
  else
    echo "⚠ Dock config not found at $DOCK_CONFIG" >&2
  fi
}

macos_enable_services() {
  [[ "$INSTALL_SERVICES" == "no" ]] && { echo "→ Skipping services (user disabled)"; return; }
  if ! command -v brew >/dev/null 2>&1; then 
    echo "→ Brew not available, skipping service startup"
    return
  fi
  
  echo "→ Starting system services (requires sudo)..."
  ensure_sudo || {
    echo "⚠ Could not acquire sudo credentials, skipping service startup" >&2
    return
  }
  
  local svcs=(tailscale dnsmasq)
  local daemon_base="/Library/LaunchDaemons"
  for s in "${svcs[@]}"; do
    if brew list "$s" >/dev/null 2>&1; then
      local label="homebrew.mxcl.${s}"
      local plist="${daemon_base}/${label}.plist"
      echo "  • Managing $s via launchctl…"

      if [[ ! -f "$plist" ]]; then
        echo "    ⚠ LaunchDaemon not found at $plist; try 'brew services start $s' manually" >&2
        continue
      fi

      if launchctl print "system/${label}" >/dev/null 2>&1; then
        echo "    • $s already running; refreshing"
        sudo_run launchctl bootout system "$plist" || true
      fi

      if sudo_run launchctl bootstrap system "$plist"; then
        sudo_run launchctl enable "system/${label}" || true
        sudo_run launchctl kickstart -k "system/${label}" || true
        echo "    ✓ $s service started"
      else
        printf "    ⚠ Failed to bootstrap %s; try 'sudo launchctl bootstrap system \"%s\"' manually\n" "$s" "$plist" >&2
      fi
    else
      echo "  • $s not installed, skipping"
    fi
  done
}

macos_configure_dns() {
  # Skip DNS configuration if services were not installed
  if [[ "$INSTALL_SERVICES" == "no" ]]; then
    echo "→ Services not installed, skipping DNS configuration"
    return
  fi
  
  # Only offer DNS configuration if dnsmasq is actually installed
  if ! command -v brew >/dev/null 2>&1 || ! brew list dnsmasq >/dev/null 2>&1; then
    echo "→ dnsmasq not installed, skipping DNS configuration"
    return
  fi
  
  if [[ "$CONFIGURE_DNS" == "ask" ]]; then
    yesno "Configure system DNS to 127.0.0.1 for dnsmasq?" default_no && CONFIGURE_DNS=yes || CONFIGURE_DNS=no
  fi
  [[ "$CONFIGURE_DNS" != "yes" ]] && { echo "→ Skipping DNS configuration"; return; }

  echo "→ Configuring system DNS (requires sudo)..."
  ensure_sudo || {
    echo "⚠ Could not acquire sudo credentials, skipping DNS configuration" >&2
    return
  }

  echo "  • Setting DNS servers to 127.0.0.1 for all non‑VPN services…"
  local svc
  while IFS= read -r svc; do
    svc="${svc#\*}"; svc="$(echo "$svc" | xargs)"
    [[ -z "$svc" || "$svc" == *VPN* || "$svc" == Tailscale* ]] && continue
    if sudo_run networksetup -setdnsservers "$svc" 127.0.0.1; then
      echo "    ✓ DNS configured for $svc"
    else
      echo "    ⚠ Failed DNS setup on $svc" >&2
    fi
  done < <(networksetup -listallnetworkservices 2>/dev/null | sed '1d')
}

macos_enable_touchid() {
  echo "→ Enabling Touch ID for sudo (sudo_local)…"
  
  # Check if PAM directory exists (should always exist on macOS)
  if [[ ! -d /etc/pam.d ]]; then
    echo "⚠ PAM directory /etc/pam.d not found, skipping Touch ID setup" >&2
    return
  fi

  # Check if our dotfiles sudo_local exists
  local dotfiles_sudo_local="$DOTFILES_DIR/system/pam.d/sudo_local"
  if [[ ! -f "$dotfiles_sudo_local" ]]; then
    echo "⚠ Dotfiles sudo_local not found at $dotfiles_sudo_local, skipping Touch ID setup" >&2
    return
  fi

  echo "  • Touch ID setup requires sudo access..."
  ensure_sudo || {
    echo "⚠ Could not acquire sudo credentials, skipping Touch ID setup" >&2
    return
  }

  # Force remove any existing sudo_local (file or symlink)
  if [[ -e /etc/pam.d/sudo_local || -L /etc/pam.d/sudo_local ]]; then
    echo "  • Removing existing sudo_local…"
    if sudo_run rm -f /etc/pam.d/sudo_local; then
      echo "    ✓ Existing sudo_local removed"
    else
      echo "    ⚠ Could not remove existing sudo_local" >&2
      return
    fi
  fi

  # Create symlink to our dotfiles version
  echo "  • Creating symlink to dotfiles sudo_local…"
  if sudo_run ln -sf "$dotfiles_sudo_local" /etc/pam.d/sudo_local; then
    echo "    ✓ Touch ID for sudo configured successfully"
  else
    echo "    ⚠ Could not create symlink to dotfiles sudo_local" >&2
    return
  fi
}

macos_configure_iterm2() {
  echo "→ Configuring iTerm2 preferences…"
  defaults write com.googlecode.iterm2 PrefsCustomFolder -string "$HOME/.config/iterm2" 2>/dev/null || true
  defaults write com.googlecode.iterm2 LoadPrefsFromCustomFolder -bool true 2>/dev/null || true
  mkdir -p "$HOME/.config/iterm2/DynamicProfiles"
  local src="$DOTFILES_DIR/config/iterm2/DynamicProfiles/Stef.json"
  local dst="$HOME/.config/iterm2/DynamicProfiles/Stef.json"
  if [[ -f "$src" ]]; then
    if [[ ! -f "$dst" ]] || ! cmp -s "$src" "$dst"; then
      cp "$src" "$dst" && echo "  ✓ Updated iTerm2 dynamic profile"
    else
      echo "  ✓ iTerm2 dynamic profile already up to date"
    fi
  else
    echo "  ⚠ iTerm2 profile source not found at $src"
  fi
}

# ----------------------------------------------------------------------------
# Linux specific helpers
# ----------------------------------------------------------------------------
linux_is() { [[ "$(uname)" == "Linux" ]]; }

linux_pkg_manager=""
linux_detect_pkgmgr() {
  if command -v apt >/dev/null 2>&1; then
    linux_pkg_manager=apt
    echo "  • Detected apt"
    return
  fi
  if command -v pacman >/dev/null 2>&1; then
    linux_pkg_manager=pacman
    echo "  • Detected pacman"
    return
  fi
  linux_pkg_manager=unknown
  echo "⚠ Could not detect a supported package manager"
}

linux_update_system() {
  case "$linux_pkg_manager" in
    apt)
      sudo_run apt update
      sudo_run apt upgrade -y || true
      ;;
    pacman)
      sudo_run pacman -Syu --noconfirm || true
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
        pkgs=()
        while IFS= read -r line; do
          pkgs+=("$line")
        done < <(grep -vE '^\s*#' "$list" | sed '/^\s*$/d')
        sudo_run apt install -y "${pkgs[@]}" || log_warning "Some apt packages failed"
      else
        log_warning "Package list not found at $list"
      fi
      ;;
    pacman)
      # Best-effort mapping for common packages
      local pkgs=(git zsh bat eza fzf htop nmap python screen shellcheck tldr tmux github-cli git-delta glab)
      sudo_run pacman -S --needed --noconfirm "${pkgs[@]}" || log_warning "Some pacman packages failed"
      ;;
  esac
}

linux_manual_installs() {
  # Keep this lightweight: Docker/Kubernetes/Helm/Terraform can be added as needed
  echo "  • No manual Linux installers defined yet"
}

linux_set_terminal_font() {
  # Optional: attempt to set Nerd Font for GNOME
  if ! command -v gsettings >/dev/null 2>&1; then
    echo "  • gsettings not available; skipping terminal font configuration"
    return
  fi

  local prof
  prof=$(gsettings get org.gnome.Terminal.ProfilesList default 2>/dev/null | tr -d "'") || true
  if [[ -z "$prof" ]]; then
    echo "  • GNOME Terminal default profile not found; skipping"
    return
  fi

  local path="org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$prof/"
  echo "  • Setting GNOME Terminal font to JetBrainsMono Nerd Font 14"
  gsettings set "$path" font 'JetBrainsMono Nerd Font 14' || echo "⚠ Failed to set GNOME Terminal font" >&2
  gsettings set "$path" use-system-font false || true
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
    echo "Running Dotbot…"
    DOTFILES_SKIP_TOUCHID_LINK=true "$DOTBOT_INSTALL" -v || log_warning "Dotbot reported issues"
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
  # Skip git setup in unattended mode
  if [[ "${UNATTENDED_MODE:-false}" == "true" ]]; then
    echo "→ Skipping Git user configuration (unattended mode)"
    echo "   Configure Git manually later with:"
    echo "     git config --global user.name 'Your Name'"
    echo "     git config --global user.email 'your.email@example.com'"
    return
  fi

  local name email
  
  # Get and verify git user name
  while [[ -z "${GIT_USER_NAME:-}" ]]; do 
    read -r -p "Enter global Git user.name: " name
    if [[ -z "$name" ]]; then
      echo "⚠ Name cannot be empty" >&2
      continue
    fi
    
    echo "Name: $name"
    if yesno "Is this name correct?" default_yes; then
      GIT_USER_NAME="$name"
    else
      echo "→ Please enter your name again"
    fi
  done
  
  # Get and validate git user email
  while [[ -z "${GIT_USER_EMAIL:-}" ]]; do 
    read -r -p "Enter global Git user.email: " email
    if [[ -z "$email" ]]; then
      echo "⚠ Email cannot be empty" >&2
      continue
    fi
    
    if validate_email "$email"; then
      echo "Email: $email"
      if yesno "Is this email correct?" default_yes; then
        GIT_USER_EMAIL="$email"
      else
        echo "→ Please enter your email again"
      fi
    else
      echo "⚠ Invalid email format. Please enter a valid email address (e.g., user@example.com)" >&2
    fi
  done
  
  if git config --global user.name "$GIT_USER_NAME"; then
    echo "✓ Git user.name set to: $GIT_USER_NAME"
  else
    echo "⚠ Failed to set git user.name" >&2
  fi
  
  if git config --global user.email "$GIT_USER_EMAIL"; then
    echo "✓ Git user.email set to: $GIT_USER_EMAIL"
  else
    echo "⚠ Failed to set git user.email" >&2
  fi
}

github_auth() {
  if [[ "$GITHUB_AUTH" == "ask" ]]; then
    yesno "Login with GitHub CLI now?" default_yes && GITHUB_AUTH=yes || GITHUB_AUTH=no
  fi
  [[ "$GITHUB_AUTH" != "yes" ]] && { echo "→ Skipping GitHub CLI authentication"; return; }
  
  if command -v gh >/dev/null 2>&1; then
    echo "→ Starting GitHub CLI authentication..."
    if gh auth login --hostname github.com --git-protocol ssh; then
      echo "✓ GitHub CLI authentication completed"
    else
      echo "⚠ GitHub CLI authentication failed" >&2
    fi
  else
    echo "⚠ GitHub CLI not installed; skipping GitHub login" >&2
  fi
}

# ----------------------------------------------------------------------------
# Additional setup functions
# ----------------------------------------------------------------------------
run_xdg_cleanup() {
  if [[ "$RUN_XDG_CLEANUP" == "ask" ]]; then
    yesno "Run XDG cleanup to remove legacy config files?" default_yes && RUN_XDG_CLEANUP=yes || RUN_XDG_CLEANUP=no
  fi
  [[ "$RUN_XDG_CLEANUP" != "yes" ]] && { echo "→ Skipping XDG cleanup"; return; }

  local xdg_script="$DOTFILES_DIR/scripts/system/xdg-cleanup"
  if [[ -x "$xdg_script" ]]; then
    echo "→ Running XDG cleanup script…"
    if [[ "${UNATTENDED_MODE:-false}" == "true" ]]; then
      "$xdg_script" --unattended --from-bootstrap || echo "⚠ XDG cleanup script reported issues" >&2
    else
      "$xdg_script" --from-bootstrap || echo "⚠ XDG cleanup script reported issues" >&2
    fi
  else
    echo "⚠ XDG cleanup script not found at $xdg_script" >&2
  fi
}

setup_dev_directory() {
  if [[ "$SETUP_DEV_DIR" == "ask" ]]; then
    yesno "Set up ~/dev directory structure?" default_yes && SETUP_DEV_DIR=yes || SETUP_DEV_DIR=no
  fi
  [[ "$SETUP_DEV_DIR" != "yes" ]] && { echo "→ Skipping dev directory setup"; return; }

  local dev_script="$DOTFILES_DIR/scripts/dev/bootstrap_dev_dir.sh"
  if [[ -x "$dev_script" ]]; then
    echo "→ Setting up development directory structure…"
    "$dev_script" || echo "⚠ Dev directory setup reported issues" >&2
    echo "→ Development directory structure ensured at ~/dev"
  else
    echo "⚠ Dev directory script not found at $dev_script" >&2
  fi
}

# ----------------------------------------------------------------------------
# Terminal management (macOS)
# ----------------------------------------------------------------------------
macos_quit_terminal() {
  echo "→ Quitting Terminal.app to apply changes…"
  osascript -e 'tell application "Terminal" to quit'
  echo "→ Terminal.app closed"
}

# ----------------------------------------------------------------------------
# Change login shell to zsh (optional)
# ----------------------------------------------------------------------------
maybe_change_shell() {
  # Check current shell
  local current_shell="${SHELL:-$(getent passwd "$USER" 2>/dev/null | cut -d: -f7 || echo)}"
  current_shell="${current_shell:-/bin/bash}"  # fallback
  
  echo "→ Checking default shell (current: $current_shell)"
  
  if [[ "$current_shell" == */zsh ]]; then
    echo "  ✓ Shell is already zsh, no change needed"
    return
  fi

  if [[ "$CHANGE_SHELL" == "ask" ]]; then
    yesno "Change your default shell to zsh?" default_yes && CHANGE_SHELL=yes || CHANGE_SHELL=no
  fi
  [[ "$CHANGE_SHELL" != "yes" ]] && return

  if command -v zsh >/dev/null 2>&1; then
    local zpath
    zpath=$(command -v zsh) || {
      echo "  ⚠ Could not determine zsh path" >&2
      return
    }
    
    if [[ "$SHELL" != "$zpath" ]]; then
      echo "  • Changing default shell to $zpath…"
      # Temporarily disable error trapping for this operation
      set +e
      chsh -s "$zpath" "${USER}"
      local chsh_result=$?
      set -e
      
      if [[ $chsh_result -ne 0 ]]; then
        echo "    ⚠ Could not change default shell (exit code: $chsh_result)" >&2
        echo "    ℹ You can change it manually later with: chsh -s $zpath"
      else
        echo "    ✓ Default shell changed successfully"
      fi
    else
      echo "  ✓ Default shell is already zsh"
    fi
  else
    echo "  ⚠ zsh not installed; cannot change default shell" >&2
  fi
}

# ----------------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------------
main() {
  # Parse command-line arguments first
  parse_args "$@"
  
  echo "Starting unified bootstrap…"
  
  # Set terminal environment to minimize color/escape sequence issues
  export TERM="${TERM:-xterm-256color}"
  export COLORTERM="${COLORTERM:-truecolor}"
  
  # Suppress potential shell startup warnings during bootstrap
  export BOOTSTRAP_MODE=1
  
  # Setup unattended mode if requested
  setup_unattended_mode
  
  # For unattended mode, ensure sudo credentials upfront without prompting
  if [[ "${UNATTENDED_MODE:-false}" == "true" ]]; then
    echo "Checking sudo credentials for unattended operations…"
    if ensure_sudo; then
      echo "✅ Sudo credentials verified for unattended mode."
    else
      echo "❌ Unable to verify sudo credentials; exiting." >&2
      exit 1
    fi
  fi
  
  announce_step "Ensuring XDG base directories exist"
  ensure_directories

  announce_step "Ensuring dotfiles repository is writable"
  ensure_repo_writable

  if macos_is; then
    echo "Detected macOS ($(sw_vers -productVersion 2>/dev/null || echo))"
    announce_step "Checking for Xcode Command Line Tools"
    macos_require_clt
    announce_step "Installing Homebrew and evaluating Brew bundle"
    macos_install_homebrew
    announce_step "Applying Homebrew bundle"
    macos_install_brewfile
    announce_step "Linking dotfiles with Dotbot"
    run_dotbot
    announce_step "Configuring global Git settings"
    setup_git
    announce_step "Handling GitHub CLI authentication"
    github_auth
    announce_step "Starting macOS background services"
    macos_enable_services
    announce_step "Applying Dock preferences"
    macos_configure_dock
    announce_step "Configuring DNS for dnsmasq"
    macos_configure_dns
    announce_step "Enabling Touch ID for sudo"
    macos_enable_touchid
    announce_step "Applying iTerm2 preferences"
    macos_configure_iterm2
  elif linux_is; then
    echo "Detected Linux"
    announce_step "Detecting package manager"
    linux_detect_pkgmgr
    announce_step "Updating base system packages"
    linux_update_system
    announce_step "Installing essential packages"
    linux_install_base_packages
    announce_step "Running additional Linux installers"
    linux_manual_installs
    announce_step "Linking dotfiles with Dotbot"
    run_dotbot
    announce_step "Configuring global Git settings"
    setup_git
    announce_step "Handling GitHub CLI authentication"
    github_auth
    announce_step "Setting terminal font preferences"
    linux_set_terminal_font
  else
    log_error "Unsupported OS: $(uname)"
    exit 1
  fi

  announce_step "Creating SSH socket directory"
  mkdir -p "$HOME/.ssh/sockets" && chmod 700 "$HOME/.ssh/sockets"

  announce_step "Evaluating default shell configuration"
  maybe_change_shell
  
  # Additional setup
  announce_step "Cleaning up legacy configuration via XDG script"
  run_xdg_cleanup
  announce_step "Bootstrapping ~/dev directory structure"
  setup_dev_directory
  
  echo ""
  echo "🎉 Bootstrap complete!"
  echo ""
  
  if [[ "${UNATTENDED_MODE:-false}" == "true" ]]; then
    echo "✅ Installation completed in unattended mode."
    echo "ℹ  Please restart your terminal to apply all changes."
  elif macos_is; then
    echo "ℹ  To apply all changes, you need to restart your terminal."
    echo ""
    if yesno "Quit terminal now to apply changes?" default_yes; then
      macos_quit_terminal
    else
      echo "ℹ  Please restart your terminal manually when ready"
    fi
  else
    echo "❗ IMPORTANT: Close this terminal and open a new one to:"
    echo "  • Pick up the new shell configuration"
    echo "  • Allow zinit and other tools to initialize properly"
    echo "  • Ensure all environment variables are set correctly"
  fi
}

main "$@"
