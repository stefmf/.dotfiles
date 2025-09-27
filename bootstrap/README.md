# Bootstrap

Unified cross-platform bootstrap for macOS 26 "Tahoe" and modern Linux, with XDG compliance and Dotbot-managed symlinks. This folder also contains an `archive/` with the previous OS-specific scripts preserved for reference while the new unified flow is tested.

## Entry point

- `bootstrap.sh` — single entry that detects OS and branches cleanly. It:
  - Ensures XDG base dirs exist (XDG_CONFIG_HOME, DATA_HOME, CACHE_HOME, STATE_HOME)
  - Starts sudo keepalive (non-interactive via SUDO_ASKPASS on macOS when opted-in)
  - Installs Homebrew (macOS) or base packages (Linux)
  - Optionally installs casks/services on macOS (behind prompts)
  - Uses `brew services` to manage background daemons on macOS
  - Runs Dotbot (`./install`) to link configs and shells
  - Configures Git (global user.name/user.email)
  - Optional GitHub CLI auth
  - Optionally change default shell to zsh (Linux) or offer to on macOS
  - Sets up SSH sockets dir (~/.ssh/sockets)
  - Idempotent by design: safe to re-run

## macOS 26 (Tahoe) specifics

- Xcode CLTs are ensured and optionally updated
- Homebrew is installed and evaluated in-session only; persistent shellenv is handled by `shell/zsh/zprofile` (via Dotbot)
- Optional features behind prompts:
  - Install cask apps and MAS apps
  - Enable services (Tailscale, dnsmasq) and optionally set DNS via `networksetup`
    - Install Parallels Desktop after the bundle step with manual fallback guidance
  - Configure Dock via `config/dock/dock_config.zsh`
  - iTerm2 prefs path to XDG (`~/.config/iterm2`) and Dynamic Profile `Stef.json`
  - Enable Touch ID for sudo via `/etc/pam.d/sudo_local`

## Linux specifics (modern Debian/Ubuntu baseline)

- Updates system packages and installs essentials from `bootstrap/archive/base_packages.list`
- Stubs are in the unified script for advanced installers (Docker, kubectl, Kind, Helm, Terraform, AWS CLI, Fastfetch, fonts) — preserved in archived script pending port
- Terminal fonts and symlinks (bat/batcat) are handled in the archived script; these will be ported selectively

## Flags and prompts

The unified script keeps interactivity light and explicit:

- macOS:
  - Install casks? Install services? Configure DNS? Login with GitHub? Change shell?
- Linux:
  - Non-destructive prompts only; advanced installers deferred

Command-line flags (optional):

- `--debug` — enable verbose logging for troubleshooting runs.

Environment variables you can pre-set to change defaults:

- `GITHUB_AUTH=1` — auto-run `gh auth login` if gh is present
- `CHANGE_SHELL=1` — offer to change default shell to zsh at the end

## Archive

- `archive/bootstrap_macos.zsh` — previous macOS bootstrap preserved verbatim for reference
- `archive/bootstrap_linux.sh` — previous Linux bootstrap preserved verbatim for reference

You can diff these against `bootstrap.sh` to confirm behavior parity while we iterate.

## Migration plan

- Phase 1 (done): Create unified `bootstrap.sh`, fix macOS paths, enforce XDG, and keep prompts
- Phase 2 (this repo state): Archive old scripts for safety, document flow and flags, test on fresh macOS 26 and Ubuntu
- Phase 3 (next): Port selective advanced Linux installers behind flags; refine macOS SUDO_ASKPASS UX; write small tests for idempotency
- Phase 4: Remove archived scripts after validation and cut a tag

## Next steps

- Port advanced Linux installers (Docker, kubectl, Kind, Helm, Terraform, AWS CLI, Fastfetch, fonts) behind flags in `bootstrap.sh` with idempotent checks.
- Add a simple "doctor" check to validate prerequisites (brew, git, gh) and report actionable fixes.
- Add a tiny idempotency smoke test (run twice, assert no changes) and optional CI job to run shellcheck.
- Confirm Dotbot mapping covers all XDG targets; prune legacy symlinks as needed.
- After validation on fresh macOS and Ubuntu, remove `archive/` and tag the repo.

## Makefile (recommended)

A small Makefile makes common tasks easy and discoverable. Suggested targets:

- `bootstrap` — run the unified bootstrap
- `bootstrap-macos` / `bootstrap-linux` — OS-guarded wrappers
- `dotbot` — run the dotfiles linker
- `brew-bundle` — apply the Brewfile
- `brew-dump` — refresh `bootstrap/Brewfile` from current system
- `doctor` — quick health checks (brew, gh, git)

Example Makefile snippet you can drop at repo root:

```makefile
.PHONY: help bootstrap bootstrap-macos bootstrap-linux dotbot brew-bundle brew-dump doctor

help:
  @awk -F':.*##' '/^[a-zA-Z_-]+:.*##/ { printf "\033[36m%-20s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

bootstrap: ## Run unified bootstrap
  bash bootstrap/bootstrap.sh

bootstrap-macos: ## Bootstrap (macOS only)
  @uname | grep -qi Darwin || (echo "This target is macOS-only" && exit 1)
  bash bootstrap/bootstrap.sh

bootstrap-linux: ## Bootstrap (Linux only)
  @uname | grep -qi Linux || (echo "This target is Linux-only" && exit 1)
  bash bootstrap/bootstrap.sh

dotbot: ## Link dotfiles via Dotbot
  ./install

brew-bundle: ## Apply Brewfile
  brew bundle --file=bootstrap/Brewfile

brew-dump: ## Dump current brew state to Brewfile
  brew bundle dump --file=bootstrap/Brewfile --force

doctor: ## Quick health checks
  command -v brew >/dev/null 2>&1 || echo "brew not found"
  command -v gh >/dev/null 2>&1   || echo "gh not found"
  command -v git >/dev/null 2>&1  || echo "git not found"
```

## How to run

From the repo root:

- macOS: run `bootstrap/bootstrap.sh` from Terminal or iTerm2. It will guide you through optional steps.
- Linux: run `bootstrap/bootstrap.sh`. It performs base setup; advanced installers will be added as flags later.

If you prefer the legacy flows during testing, use the archived scripts directly at your own risk.

## Troubleshooting

- If Homebrew was installed but `brew` isn’t in PATH, ensure your `~/.zprofile` symlink is correct and includes the Homebrew shellenv via `shell/zsh/zprofile`.
- DNS changes require sudo and are applied per network service; VPN/Tailscale services are skipped intentionally.
- Dotbot links `~/.config` to `config/` in this repo; verify `config/dotbot/install.conf.yaml` for the mapping.
- Parallels Desktop sometimes requires signing in to download the installer. If the scripted install fails, download it manually from Parallels and rerun the bootstrap to pick up the rest of the configuration.

