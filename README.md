# macOS Dotfiles – Overview & Guide

Opinionated macOS dotfiles and setup scripts for a clean, repeatable developer workstation. It automates tool installation, shell/app configuration, Touch ID for sudo, DNS/MagicDNS, and a few quality-of-life defaults.

## Table of Contents

- Getting started
  - Setting up a new Mac
  - Authenticate with GitHub
  - Restart Terminal
- What you get
  - Touch ID for sudo
  - DNS & MagicDNS
  - Services & tools
- Repository structure
- Post-install tips
- Updating dotfiles

---

## 🚀 Getting started

### Setting up a new Mac

1) Install Xcode Command Line Tools

```bash
xcode-select --install
```

2) Clone this repository

Replace the placeholder URL with your repo if you fork:

```bash
git clone https://github.com/stefmf/.dotfiles.git ~/.dotfiles
cd ~/.dotfiles
```

3) Bootstrap script

Run the automated bootstrap script to set up your development environment:

```bash
cd ~/.dotfiles/bootstrap
./bootstrap_v2.sh
```

The script will:
- Install Xcode Command Line Tools and Homebrew
- Set up XDG directories and run Dotbot configuration
- Prompt you for optional components (GUI apps, services, etc.)
- Configure Touch ID, DNS, and system preferences
- Set up development directory and GitHub authentication

After completion:
- Restart your terminal
- Configure Git: `git config --global user.name "Your Name"` and `git config --global user.email "you@example.com"`

For help: `./bootstrap_v2.sh --help`

---

## 🔐 Touch ID for sudo

Touch ID is enabled via `/etc/pam.d/sudo_local` so it survives OS updates.

Tip: Run any `sudo` command and tap your sensor instead of typing a password. If it doesn’t prompt for Touch ID, ensure `sudo_local` contains the `pam_tid.so` line and that you’ve authenticated once since reboot.

---

## 🌐 DNS & MagicDNS

Tailscale's MagicDNS is configured using macOS native resolver:

- A resolver file at `/etc/resolver/tail969ae0.ts.net` directs `*.tail969ae0.ts.net` queries to 100.100.100.100 (MagicDNS)
- Search domain `tail969ae0.ts.net` is added to all network interfaces for short name resolution

This allows you to use both short names (e.g., `ssh lucky`) and fully qualified names (e.g., `ssh lucky.tail969ae0.ts.net`).

Verify:

```bash
scutil --dns | grep tail969ae0
networksetup -getsearchdomains Wi-Fi
```

Manual setup (if needed):

```bash
# Create resolver file
sudo mkdir -p /etc/resolver
echo "nameserver 100.100.100.100" | sudo tee /etc/resolver/tail969ae0.ts.net

# Set search domain (replace Wi-Fi with your interface)
sudo networksetup -setsearchdomains Wi-Fi tail969ae0.ts.net
```

Revert to default:

```bash
sudo rm /etc/resolver/tail969ae0.ts.net
sudo networksetup -setsearchdomains Wi-Fi Empty
```

---

## 🛡️ Services & tools

- Tailscale VPN: runs as a system daemon (`tailscaled`). Authenticate once with `tailscale up`.
- MagicDNS: configured via native macOS resolver (no additional services required).

Check Tailscale status:

```bash
tailscale status
```

Homebrew bundle: `bootstrap/helpers/Brewfile` installs CLI tools, shells, fonts, apps Ghostty, VS Code, Chrome), Docker/K8s tooling, and more.

---

## 📁 Repository structure

This repo is organized for clarity and XDG compliance. Highlights:

```
~/.dotfiles/
├── install                      # Main installation entry point
├── bootstrap/
│   ├── bootstrap_v2.sh         # Primary bootstrap script (macOS/Linux)
│   └── helpers/
│       ├── Brewfile            # Homebrew bundle (macOS)
│       ├── linux_helper.sh     # Ubuntu/Linux bootstrap logic
│       └── ubuntu-apps.list    # Linux tool installation manifest
├── config/                     # App configs (symlinked into ~/.config)
│   ├── bat/ | btop/ | dock/ | fastfetch/ | fsh/ | fzf/ | git/
│   ├── ghostty/ | lsd/ | npm/ | nvim/ | ohmyposh/ | sublime/
│   ├── tldr/ | tmux/ | vim/
│   └── dotbot/install.conf.yaml
├── docs/                       # Additional documentation
│   └── LOCAL_CONFIG.md
├── scripts/                    # Utility scripts
│   ├── dev/bootstrap_dev_dir.sh
│   ├── dotfiles/{dotall,dotpost,dotup}
│   ├── shell/{load_shell_extensions,nuke,sudo-toggle}
│   └── system/{setup_gnu_aliases,update,xdg-cleanup}
├── shell/                      # Shell configuration
│   ├── profile                 # POSIX shell fallback (auto-switches to zsh)
│   └── zsh/                    # ZSH configuration
│       ├── zshrc | zshenv | zprofile | zaliases | zlogin | zlogout
│       ├── hushlogin
│       ├── functions/          # Custom zsh functions
│       └── completions/        # Shell completions
├── system/                     # System-level configuration
│   ├── pam.d/sudo_local
│   └── ssh/
│       ├── config
│       └── sshd_config
└── tools/
    └── dotbot/                 # Dotbot (vendored) for managing symlinks
```

Notes:
- Configs are grouped by tool and designed to live under `~/.config/` via Dotbot symlinks.
- Naming is consistent and avoids leading dots in-repo for clarity.
- It’s easy to add new tools: drop a folder under `config/` and wire it in Dotbot.

---

## 🔧 Post-install tips

- Tailscale login:

  ```bash
  tailscale up
  ```

- Check Tailscale status:

  ```bash
  tailscale status
  ```

- Troubleshoot MagicDNS:
  1) Confirm resolver file exists: `cat /etc/resolver/tail969ae0.ts.net`
  2) Check search domains: `scutil --dns | grep tail969ae0`
  3) Ensure Tailscale is connected: `tailscale status`
  4) Test resolution: `ping lucky.tail969ae0.ts.net` (replace with your device name)

---

## ⬆️ Updating dotfiles

Pull the latest and re-run the installer:

```bash
~/.dotfiles/install
```

When the bootstrap script returns, you’ll also be able to use it for a full machine setup.

— Enjoy your Touch‑ID‑enabled, MagicDNS‑powered macOS development setup!
