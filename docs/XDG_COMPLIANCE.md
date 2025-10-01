# XDG Base Directory Compliance

This document tracks the XDG Base Directory Specification compliance status for applications used in this dotfiles repository.

## XDG Base Directories

- `XDG_CONFIG_HOME` (~/.config): User-specific configuration files
- `XDG_DATA_HOME` (~/.local/share): User-specific data files
- `XDG_CACHE_HOME` (~/.cache): User-specific non-essential (cached) data
- `XDG_STATE_HOME` (~/.local/state): User-specific state files (logs, history)

## Fully Compliant Applications

These applications natively support XDG directories:

| Application | Config Location | Data Location | Cache Location |
|------------|----------------|---------------|----------------|
| Zsh | `$XDG_CONFIG_HOME/zsh/` | `$DOTFILES/shell/zsh/` | `$XDG_CACHE_HOME/zsh/` |
| Vim | `$XDG_CONFIG_HOME/vim/` | - | - |
| Git | `$XDG_CONFIG_HOME/git/` | - | - |
| npm | `$XDG_CONFIG_HOME/npm/` | `$XDG_DATA_HOME/npm/` | `$XDG_CACHE_HOME/npm/` |
| bat | `$XDG_CONFIG_HOME/bat/` | - | - |
| btop | `$XDG_CONFIG_HOME/btop/` | - | - |
| fzf | `$XDG_CONFIG_HOME/fzf/` | - | - |
| lsd | `$XDG_CONFIG_HOME/lsd/` | - | - |
| oh-my-posh | `$XDG_CONFIG_HOME/ohmyposh/` | - | `$XDG_CACHE_HOME/oh-my-posh/` |
| pyenv | - | `$XDG_DATA_HOME/pyenv/` | - |
| less | - | - | `$XDG_CACHE_HOME/less/` |

## Partial Compliance (Environment Variable Required)

These applications support XDG directories via environment variables:

| Application | Environment Variable | Configured Location |
|------------|---------------------|-------------------|
| Docker | `DOCKER_CONFIG` | `$XDG_CONFIG_HOME/docker` |
| TLDR | `TLDR_CACHE_DIR` | `$XDG_CACHE_HOME/tldr` |

## Non-Compliant (Hardcoded Paths)

These applications do not support XDG directories and use hardcoded paths:

### ~/.colima (Colima - Docker Runtime)
- **Status**: Hardcoded, cannot be moved
- **Reason**: 
  - Colima hardcodes `~/.colima` for configuration and runtime data
  - SSH config includes `~/.colima/ssh_config` (required for container access)
  - Moving would break SSH connectivity to Colima VMs
- **Action**: Leave in place, exclude from cleanup

### ~/.vs-kubernetes (VS Code Kubernetes Extension)
- **Status**: Hardcoded by VS Code extension
- **Reason**: VS Code extensions often use `~/.vs-*` or `~/.vscode-*` paths
- **Size**: Can be 100MB+ (downloads minikube, kubectl, and other tool binaries)
- **Action**: Warning only (not auto-removed, may be actively used)
- **Manual cleanup**: `rm -rf ~/.vs-kubernetes` (regenerates on demand if needed)

### ~/.ssh
- **Status**: Hardcoded by SSH specification
- **Reason**: Expected by many SSH clients, daemons, and related tools
- **Action**: Keep in place (industry standard location)

## Cleanup History

The following directories were removed during XDG migration:

### Old Dotfiles Structure (Pre-Refactor)
- `~/.dotfiles/.config` → Moved to proper locations within repo
- `~/.dotfiles/.zsh` → Moved to `~/.dotfiles/shell/zsh/`

### Legacy Application Directories
- `~/.tldrc` → Removed (TLDR cache, regenerates in `~/.cache/tldr/`)
- `~/.docker` → Moved to `~/.config/docker` (via `DOCKER_CONFIG`)
- `~/.zsh_sessions` → Moved to `~/.local/state/zsh/sessions/`
- `~/.zcompcache` → Moved to `~/.cache/zsh/`
- `~/.minikube` → Removed (safe to remove if not actively used)
- `~/.dotfiles/dotbot` → Removed (old path, now in `tools/dotbot`)

### Legacy Shell Files
- `~/.zsh_history` → Now in `~/.dotfiles/shell/zsh/.zsh_history`
- `~/.zcompdump*` → Now in `~/.cache/zsh/`
- `~/.bash*` → Removed (not using Bash)
- `~/.vimrc` → Legacy symlink (vim has native XDG support, automatically uses `$XDG_CONFIG_HOME/vim/vimrc`)

### Legacy macOS Files
- `~/.CFUserTextEncoding` → Legacy macOS encoding file (pre-Mac OS X 10.4, no longer used)

## Environment Variables

All XDG-related environment variables are set in `shell/zsh/zshenv`:

```bash
# XDG Base Directory Specification
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share" 
export XDG_CACHE_HOME="$HOME/.cache"
export XDG_STATE_HOME="$HOME/.local/state"

# Application-specific XDG compliance
export LESSHISTFILE="$XDG_CACHE_HOME/less/history"
export TLDR_CACHE_DIR="$XDG_CACHE_HOME/tldr"
export NPM_CONFIG_USERCONFIG="$XDG_CONFIG_HOME/npm/npmrc"
export DOCKER_CONFIG="$XDG_CONFIG_HOME/docker"
```

## Running the Cleanup Script

To clean up legacy directories on a new machine:

```bash
~/.dotfiles/scripts/system/xdg-cleanup
```

Or run automatically during bootstrap:

```bash
~/.dotfiles/bootstrap/bootstrap_v2.sh
```

## References

- [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/latest/)
- [Arch Wiki: XDG Base Directory](https://wiki.archlinux.org/title/XDG_Base_Directory)
