# macOS Dotfiles Setup – Overview & Guide

This repository contains my macOS dotfiles and setup scripts for a new machine. It automates the installation of development tools, configures the shell and applications, and applies custom settings (DNS, Touch ID for sudo, etc.) for a consistent environment.

## 🚀 Setting Up a New Mac

1. **Install Xcode Command Line Tools**  
   Run:
   ```bash
   xcode-select --install
   ```

2. **Clone this Repository**  
- Replace placeholder URL with your repo:

```bash
git clone https://github.com/stefmf/.dotfiles.git ~/.dotfiles
cd ~/.dotfiles
```

3. **Run the Bootstrap Script**  
  ```bash
  ./.bootstrap/macos/bootstrap_macos.zsh
  ```
  The script will install tools, symlink configs, configure Touch ID for `sudo`, set up DNS/MagicDNS, enable services, and apply your Dock layout.

  You'll first be prompted to choose whether the script should use automated
  `sudo` via `SUDO_ASKPASS` or request your password manually for each
  privileged command. On managed Macs where non-interactive `sudo` is blocked,
  answer **n** to use interactive prompts.

### Authenticate with GitHub

Once `gh` is installed, you’ll be prompted to log in:

```bash
gh auth login --hostname github.com --git-protocol ssh
```

The bootstrap will then attempt to pull your name and email from your GitHub profile and configure:

```bash
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
```

If your email is private or the fetch fails, you may need to set them manually.

4. **Restart Terminal**  
   Open a new window or run:
   ```bash
   source ~/.zshrc
   ```
   If you installed new fonts (e.g., JetBrains Mono Nerd Font), update your Terminal/iTerm2 profile to use them.

---

## 🔐 Touch ID for `sudo`

- Uses `/etc/pam.d/sudo_local` (survives OS updates).

---

## 📁 Directory Structure

This dotfiles repository is organized for clarity and maintainability:

```
~/.dotfiles/
├── README.md                 # This file
├── install*                  # Main installation script
│
├── config/                   # XDG-compliant app configurations
│   ├── bat/                  # Bat (better cat) theme and config
│   ├── btop/                 # System monitor config
│   ├── delta/                # Git diff viewer config
│   ├── dotbot/               # Dotbot installation config
│   ├── fastfetch/            # System info tool config
│   ├── fzf/                  # Fuzzy finder config and themes
│   ├── git/                  # Git configuration (placeholder)
│   ├── htop/                 # Process viewer config
│   ├── iterm2/               # Terminal profiles and themes
│   ├── nvim/                 # Neovim config (placeholder)
│   ├── ohmyposh/             # Prompt theme config
│   ├── sublime/              # Sublime Text settings
│   ├── tmux/                 # Terminal multiplexer (placeholder)
│   └── vim/                  # Vim configuration and themes
│
├── shell/zsh/                # Shell configurations
│   ├── zshrc                 # Main zsh configuration
│   ├── zshenv                # Environment variables
│   ├── zprofile              # Login shell config
│   ├── zaliases               # Shell aliases
│   ├── functions/            # Custom shell functions
│   └── completions/          # Shell completions
│
├── system/                   # System-level configurations
│   ├── ssh/config            # SSH client configuration
│   ├── dnsmasq/              # DNS configuration
│   └── pam.d/                # PAM authentication config
│
├── bootstrap/                # Machine-specific setup
│   ├── macos/                # macOS bootstrap scripts and Brewfile
│   └── linux/                # Linux bootstrap scripts and packages
│
├── scripts/                  # Utility scripts
│   ├── update                # Update all tools and packages
│   ├── cleanup.sh            # Clean up system files
│   └── dotall                # Run dotfiles commands
│
└── tools/                    # Third-party tools
    └── dotbot/               # Dotbot installation tool
```

### Key Benefits:
- **Logical Grouping**: Related configurations are grouped together
- **XDG Compliance**: Modern apps use `~/.config/` via symlinks
- **Clean Naming**: No unnecessary leading dots or mixed conventions
- **Scalable**: Easy to add new tools (nvim, tmux, etc.)
- **Maintainable**: Clear separation of concerns

Run any `sudo` command and tap your sensor instead of typing a password.  
**Troubleshoot:** Ensure `/etc/pam.d/sudo_local` contains the `pam_tid.so` line and you’ve authenticated once since reboot.

---

## 🌐 DNS & MagicDNS

We use Tailscale’s MagicDNS with a local `dnsmasq` resolver:

- System DNS is set to **127.0.0.1** for all interfaces.
- `dnsmasq` forwards:
  - `*.ts.net` queries to **100.100.100.100** (Tailscale MagicDNS).
  - Other queries to **8.8.8.8** (or your preferred upstream).

Verify with:
```bash
scutil --dns | grep nameserver
sudo lsof -i :53
```

To revert:
```bash
sudo networksetup -setdnsservers "Wi-Fi" Empty
sudo networksetup -setdnsservers "Ethernet" Empty
```

---

## 🛡️ Services & Tools

- **Tailscale VPN**: Runs as a system daemon (`tailscaled`). Authenticate once with `tailscale up`.
- **dnsmasq**: Runs on boot via Brew services. Config at `~/.config/dnsmasq/dnsmasq.conf`.  
  Restart with:
  ```bash
  sudo brew services restart dnsmasq
  ```

The `Brewfile` installs CLI tools, shells, productivity apps, Docker/K8s tools, fonts, and casks (iTerm2, VSCode, Chrome, etc.).

---

## 🔧 Post-Install Tips

- **Tailscale Login**:  
  ```bash
  tailscale up
  ```
- **Check Services**:  
  ```bash
  brew services list   # dnsmasq
  tailscale status     # Tailscale
  ```
- **Troubleshoot DNS**:  
  1. Confirm `dnsmasq` is listening on port 53.  
  2. Check `127.0.0.1` in `scutil --dns`.  
  3. Ensure Tailscale is connected for `*.ts.net` resolution.  
  4. Review logs: `/opt/homebrew/var/log/dnsmasq.log`.

- **Updating Dotfiles**:  
  Pull updates and re-run:
  ```bash
  ~/.dotfiles/install
  ```
  or the bootstrap script.

Enjoy your fully automated, Touch-ID-enabled, MagicDNS-powered macOS development setup!
