#!/usr/bin/env bash

set -euo pipefail

log_info() { echo "→ $*"; }
log_success() { echo "✓ $*"; }
log_warn() { echo "⚠ $*" >&2; }
log_error() { echo "✗ $*" >&2; }

fail() {
    log_error "$1"
    exit 1
}

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
DOTBOT_INSTALL="$DOTFILES_DIR/install"
DEV_BOOTSTRAP_SCRIPT="$DOTFILES_DIR/scripts/dev/bootstrap_dev_dir.sh"
XDG_CLEANUP_SCRIPT="$DOTFILES_DIR/scripts/system/xdg-cleanup"
APPS_LIST_FILE="$DOTFILES_DIR/bootstrap/helpers/ubuntu-apps.list"
APT_KEYRING_DIR="/etc/apt/keyrings"
KUBERNETES_REPO_VERSION="${KUBERNETES_REPO_VERSION:-v1.30}"

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

ensure_platform() {
    if [[ "$(uname)" != "Linux" ]]; then
        fail "Unsupported operating system: $(uname)"
    fi

    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        if [[ "${ID:-}" != "ubuntu" && "${ID_LIKE:-}" != *"ubuntu"* ]]; then
            log_warn "Non-Ubuntu distribution detected (ID=${ID:-unknown}). Proceeding anyway."
        fi
    fi
}

ensure_not_root() {
    if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
        fail "Do not run this script as root"
    fi
}

require_commands() {
    local missing=()
    for cmd in "$@"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done

    if (( ${#missing[@]} > 0 )); then
        fail "Missing required command(s): ${missing[*]}"
    fi
}

APT_UPDATED=false
reset_apt_update_flag() {
    APT_UPDATED=false
}

ensure_package() {
    local package="$1"
    if dpkg -s "$package" >/dev/null 2>&1; then
        return 0
    fi

    if [[ "$APT_UPDATED" == "false" ]]; then
        log_info "Updating apt package index"
        if ! sudo apt-get update; then
            log_error "Failed to update apt package index"
            return 1
        fi
        APT_UPDATED=true
    fi

    log_info "Installing $package"
    if DEBIAN_FRONTEND=noninteractive sudo apt-get install -y "$package"; then
        return 0
    fi

    log_error "Failed to install $package"
    return 1
}

ensure_keyring_directory() {
    sudo install -m 0755 -d "$APT_KEYRING_DIR"
}

ensure_ubuntu_codename() {
    if [[ -n "${UBUNTU_CODENAME:-}" ]]; then
        return
    fi

    if [[ -r /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        UBUNTU_CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
    fi
}

add_apt_repository() {
    local name="$1"
    local repo_line="$2"
    local key_url="$3"

    ensure_keyring_directory

    local key_path="$APT_KEYRING_DIR/${name}.gpg"
    local list_file="/etc/apt/sources.list.d/${name}.list"

    if [[ -n "$key_url" && ! -f "$key_path" ]]; then
        if curl -fsSL "$key_url" | sudo gpg --dearmor -o "$key_path"; then
            sudo chmod a+r "$key_path"
        else
            log_warn "Failed to download GPG key for $name repositories"
        fi
    fi

    if [[ ! -f "$list_file" ]] || ! grep -Fqx "$repo_line" "$list_file" 2>/dev/null; then
        echo "$repo_line" | sudo tee "$list_file" >/dev/null
        reset_apt_update_flag
    fi
}

detect_binary_arch() {
    case "$(uname -m)" in
        x86_64|amd64)
            echo "amd64"
            ;;
        arm64|aarch64)
            echo "arm64"
            ;;
        *)
            log_warn "Unsupported architecture: $(uname -m)"
            return 1
            ;;
    esac
}

install_minimal_packages() {
    local packages=(
        zsh
        git
        python3
        python3-pip
        python3-venv
        curl
        ca-certificates
        gnupg
        lsb-release
        software-properties-common
    jq
        unzip
    )
    for pkg in "${packages[@]}"; do
        ensure_package "$pkg"
    done
}

setup_docker_repository() {
    ensure_ubuntu_codename
    local arch
    arch=$(dpkg --print-architecture)
    local repo_line="deb [arch=${arch} signed-by=${APT_KEYRING_DIR}/docker.gpg] https://download.docker.com/linux/ubuntu ${UBUNTU_CODENAME} stable"
    add_apt_repository "docker" "$repo_line" "https://download.docker.com/linux/ubuntu/gpg"
}

setup_hashicorp_repository() {
    ensure_ubuntu_codename
    local arch
    arch=$(dpkg --print-architecture)
    local repo_line="deb [arch=${arch} signed-by=${APT_KEYRING_DIR}/hashicorp.gpg] https://apt.releases.hashicorp.com ${UBUNTU_CODENAME} main"
    add_apt_repository "hashicorp" "$repo_line" "https://apt.releases.hashicorp.com/gpg"
}

setup_helm_repository() {
    local arch
    arch=$(dpkg --print-architecture)
    local repo_line="deb [arch=${arch} signed-by=${APT_KEYRING_DIR}/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main"
    add_apt_repository "helm" "$repo_line" "https://baltocdn.com/helm/signing.asc"
}

setup_kubernetes_repository() {
    ensure_keyring_directory
    local key_path="${APT_KEYRING_DIR}/kubernetes.gpg"
    local repo_path="/etc/apt/sources.list.d/kubernetes.list"
    local repo_line="deb [signed-by=${key_path}] https://pkgs.k8s.io/core:/stable:/${KUBERNETES_REPO_VERSION}/deb/ /"

    if [[ ! -f "$key_path" ]]; then
        if curl -fsSLo "$key_path" "https://pkgs.k8s.io/core:/stable:/${KUBERNETES_REPO_VERSION}/deb/Release.key"; then
            sudo chmod a+r "$key_path"
        else
            log_warn "Failed to download Kubernetes apt key"
        fi
    fi

    if [[ ! -f "$repo_path" ]] || ! grep -Fqx "$repo_line" "$repo_path" 2>/dev/null; then
        echo "$repo_line" | sudo tee "$repo_path" >/dev/null
        reset_apt_update_flag
    fi
}

install_docker_suite() {
    if command -v docker >/dev/null 2>&1; then
        log_success "Docker already installed"
        return
    fi

    setup_docker_repository
    local packages=(docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin)
    local installed_all=true
    for pkg in "${packages[@]}"; do
        if ! ensure_package "$pkg"; then
            installed_all=false
        fi
    done

    if [[ "$installed_all" == "false" ]]; then
        log_warn "Docker installation encountered issues"
        return
    fi

    if groups "$USER" | grep -q '\bdocker\b'; then
        log_success "Docker installed and user already in docker group"
    else
        log_info "Adding $USER to docker group"
        if sudo usermod -aG docker "$USER"; then
            log_success "User added to docker group"
        else
            log_warn "Failed to add $USER to docker group"
        fi
    fi
}

install_helm() {
    if command -v helm >/dev/null 2>&1; then
        log_success "Helm already installed"
        return
    fi

    setup_helm_repository
    if ensure_package helm; then
        log_success "Helm installed"
    else
        log_warn "Helm installation failed"
    fi
}

install_kubectl() {
    if command -v kubectl >/dev/null 2>&1; then
        log_success "kubectl already installed"
        return
    fi

    setup_kubernetes_repository
    if ensure_package kubectl; then
        log_success "kubectl installed"
    else
        log_warn "kubectl installation failed"
    fi
}

install_terraform() {
    if command -v terraform >/dev/null 2>&1; then
        log_success "Terraform already installed"
        return
    fi

    setup_hashicorp_repository
    if ensure_package terraform; then
        log_success "Terraform installed"
    else
        log_warn "Terraform installation failed"
    fi
}

install_minikube() {
    if command -v minikube >/dev/null 2>&1; then
        log_success "minikube already installed"
        return
    fi

    local arch
    if ! arch=$(detect_binary_arch); then
        log_warn "Skipping minikube installation due to unsupported architecture"
        return
    fi

    local tmp_file
    tmp_file=$(mktemp)
    if curl -fsSL "https://storage.googleapis.com/minikube/releases/latest/minikube-linux-${arch}" -o "$tmp_file"; then
        sudo install -m 0755 "$tmp_file" /usr/local/bin/minikube
        log_success "minikube installed"
    else
        log_warn "Failed to download minikube"
    fi
    rm -f "$tmp_file"
}

install_kind() {
    if command -v kind >/dev/null 2>&1; then
        log_success "kind already installed"
        return
    fi

    local arch
    if ! arch=$(detect_binary_arch); then
        log_warn "Skipping kind installation due to unsupported architecture"
        return
    fi

    local version
    version=$(curl -fsSL https://api.github.com/repos/kubernetes-sigs/kind/releases/latest | jq -r '.tag_name' 2>/dev/null || true)
    if [[ -z "$version" || "$version" == null ]]; then
        version="v0.23.0"
        log_warn "Falling back to kind ${version}"
    fi

    local tmp_file
    tmp_file=$(mktemp)
    if curl -fsSL "https://github.com/kubernetes-sigs/kind/releases/download/${version}/kind-linux-${arch}" -o "$tmp_file"; then
        sudo install -m 0755 "$tmp_file" /usr/local/bin/kind
        log_success "kind ${version} installed"
    else
        log_warn "Failed to download kind ${version}"
    fi
    rm -f "$tmp_file"
}

install_bat_extras() {
    if command -v batman >/dev/null 2>&1 || command -v batdiff >/dev/null 2>&1; then
        log_success "bat-extras already installed"
        return
    fi

    local version
    version=$(curl -fsSL https://api.github.com/repos/eth-p/bat-extras/releases/latest | jq -r '.tag_name' 2>/dev/null || true)
    if [[ -z "$version" || "$version" == null ]]; then
        log_warn "Unable to determine latest bat-extras version"
        return
    fi

    local tmp_dir
    tmp_dir=$(mktemp -d)
    if curl -fsSL "https://github.com/eth-p/bat-extras/releases/download/${version}/bat-extras-${version#v}.tar.gz" -o "$tmp_dir/bat-extras.tar.gz" && \
        tar -xzf "$tmp_dir/bat-extras.tar.gz" -C "$tmp_dir"; then
        sudo install -m 0755 "$tmp_dir"/bat-extras-*/bin/* /usr/local/bin/
        log_success "bat-extras ${version} installed"
    else
        log_warn "Failed to install bat-extras"
    fi
    rm -rf "$tmp_dir"
}

install_fastfetch() {
    if command -v fastfetch >/dev/null 2>&1; then
        log_success "fastfetch already installed"
        return
    fi

    if ensure_package fastfetch; then
        log_success "fastfetch installed via apt"
        return
    fi

    local version
    version=$(curl -fsSL https://api.github.com/repos/fastfetch-cli/fastfetch/releases/latest | jq -r '.tag_name' 2>/dev/null || true)
    if [[ -z "$version" || "$version" == null ]]; then
        log_warn "Unable to determine latest fastfetch version"
        return
    fi

    local arch
    if ! arch=$(detect_binary_arch); then
        log_warn "Skipping fastfetch installation due to unsupported architecture"
        return
    fi

    local tmp_dir
    tmp_dir=$(mktemp -d)
    if curl -fsSL "https://github.com/fastfetch-cli/fastfetch/releases/download/${version}/fastfetch-linux-${arch}.tar.gz" -o "$tmp_dir/fastfetch.tar.gz" && \
        tar -xzf "$tmp_dir/fastfetch.tar.gz" -C "$tmp_dir"; then
        local binary
        binary=$(find "$tmp_dir" -type f -name fastfetch -print -quit)
        if [[ -n "$binary" ]]; then
            sudo install -m 0755 "$binary" /usr/local/bin/fastfetch
            log_success "fastfetch ${version} installed from release"
        else
            log_warn "fastfetch binary not found in release archive"
        fi
    else
        log_warn "Failed to install fastfetch"
    fi
    rm -rf "$tmp_dir"
}

install_uv() {
    if command -v uv >/dev/null 2>&1; then
        log_success "uv already installed"
        return
    fi

    ensure_local_bin
    if curl -LsSf https://astral.sh/uv/install.sh | sh -s -- --yes; then
        log_success "uv installed"
    else
        log_warn "uv installation script failed"
    fi
}

install_tlrc() {
    if command -v tlrc >/dev/null 2>&1; then
        log_success "tlrc already installed"
        return
    fi

    local version
    version=$(curl -fsSL https://api.github.com/repos/tldr-pages/tlrc/releases/latest | jq -r '.tag_name' 2>/dev/null || true)
    if [[ -z "$version" || "$version" == null ]]; then
        log_warn "Unable to determine latest tlrc version"
        return
    fi

    local arch
    if ! arch=$(detect_binary_arch); then
        log_warn "Skipping tlrc installation due to unsupported architecture"
        return
    fi

    local asset_arch
    case "$arch" in
        amd64)
            asset_arch="x86_64-unknown-linux-gnu"
            ;;
        arm64)
            asset_arch="aarch64-unknown-linux-gnu"
            ;;
        *)
            log_warn "Unsupported tlrc architecture mapping for $arch"
            return
            ;;
    esac

    local tmp_dir
    tmp_dir=$(mktemp -d)
    if curl -fsSL "https://github.com/tldr-pages/tlrc/releases/download/${version}/tlrc-${asset_arch}.tar.gz" -o "$tmp_dir/tlrc.tar.gz" && \
        tar -xzf "$tmp_dir/tlrc.tar.gz" -C "$tmp_dir"; then
        local binary
        binary=$(find "$tmp_dir" -type f -name tlrc -print -quit)
        if [[ -n "$binary" ]]; then
            sudo install -m 0755 "$binary" /usr/local/bin/tlrc
            log_success "tlrc ${version} installed"
        else
            log_warn "tlrc binary not found in release archive"
        fi
    else
        log_warn "Failed to install tlrc"
    fi
    rm -rf "$tmp_dir"
}

install_oh_my_posh() {
    if command -v oh-my-posh >/dev/null 2>&1; then
        log_success "oh-my-posh already installed"
        return
    fi

    local version
    version=$(curl -fsSL https://api.github.com/repos/JanDeDobbeleer/oh-my-posh/releases/latest | jq -r '.tag_name' 2>/dev/null || true)
    if [[ -z "$version" || "$version" == null ]]; then
        log_warn "Unable to determine latest oh-my-posh version"
        return
    fi

    local arch
    if ! arch=$(detect_binary_arch); then
        log_warn "Skipping oh-my-posh installation due to unsupported architecture"
        return
    fi

    local asset_arch
    case "$arch" in
        amd64)
            asset_arch="amd64"
            ;;
        arm64)
            asset_arch="arm64"
            ;;
        *)
            log_warn "Unsupported oh-my-posh architecture mapping for $arch"
            return
            ;;
    esac

    local tmp_dir
    tmp_dir=$(mktemp -d)
    if curl -fsSL "https://github.com/JanDeDobbeleer/oh-my-posh/releases/download/${version}/posh-linux-${asset_arch}" -o "$tmp_dir/oh-my-posh"; then
        sudo install -m 0755 "$tmp_dir/oh-my-posh" /usr/local/bin/oh-my-posh
        log_success "oh-my-posh ${version} installed"
    else
        log_warn "Failed to install oh-my-posh"
    fi
    rm -rf "$tmp_dir"
}

ensure_pipx_ready() {
    if ! ensure_package pipx; then
        log_warn "pipx installation failed"
        return 1
    fi

    if command -v pipx >/dev/null 2>&1; then
        pipx ensurepath >/dev/null 2>&1 || true
    fi
}

install_xq() {
    if command -v xq >/dev/null 2>&1; then
        log_success "xq already installed"
        return
    fi

    if ! ensure_pipx_ready; then
        log_warn "Skipping xq installation because pipx is unavailable"
        return
    fi

    ensure_local_bin
    if pipx list 2>/dev/null | grep -q '^package yq'; then
        log_info "yq already managed by pipx"
    else
        if pipx install yq; then
            log_success "yq installed via pipx"
        else
            log_warn "Failed to install yq via pipx"
        fi
    fi

    if command -v xq >/dev/null 2>&1; then
        log_success "xq available via pipx"
    else
        log_warn "xq is still not in PATH. Ensure ~/.local/bin is exported."
    fi
}

ensure_local_bin() {
    mkdir -p "$HOME/.local/bin"
}

ensure_fd_alias() {
    local fd_path
    fd_path=$(command -v fdfind || true)
    if [[ -z "$fd_path" ]]; then
        return
    fi

    if command -v fd >/dev/null 2>&1; then
        return
    fi

    ensure_local_bin
    if sudo ln -sf "$fd_path" /usr/local/bin/fd 2>/dev/null; then
        log_success "Created fd shortcut"
    else
        log_warn "Failed to create fd symlink in /usr/local/bin"
    fi
}

ensure_bat_alias() {
    local batcat_path
    batcat_path=$(command -v batcat || true)
    if [[ -z "$batcat_path" ]]; then
        return
    fi

    if command -v bat >/dev/null 2>&1; then
        return
    fi

    if sudo ln -sf "$batcat_path" /usr/local/bin/bat 2>/dev/null; then
        log_success "Created bat shortcut"
    else
        log_warn "Failed to create bat symlink in /usr/local/bin"
    fi
}

install_requested_apps() {
    if [[ ! -f "$APPS_LIST_FILE" ]]; then
        log_warn "Apps list file not found at $APPS_LIST_FILE"
        return
    fi

    while IFS='|' read -r tool method payload; do
        tool="${tool//[[:space:]]/}"
        method="${method//[[:space:]]/}"
        payload="${payload%%#*}"
        payload="${payload#"${payload%%[![:space:]]*}"}"
        payload="${payload%"${payload##*[![:space:]]}"}"

        if [[ -z "$tool" || "$tool" == \#* ]]; then
            continue
        fi

        case "$method" in
            apt)
                local pkg
                for pkg in $payload; do
                    ensure_package "$pkg"
                done
                ;;
            manual)
                if declare -F "$payload" >/dev/null 2>&1; then
                    "$payload"
                else
                    log_warn "Installer function $payload for $tool not found"
                fi
                ;;
            provided)
                log_success "$tool provided by ${payload:-another installer}"
                ;;
            *)
                log_warn "Unknown install method '$method' for $tool"
                ;;
        esac
    done < "$APPS_LIST_FILE"

    ensure_fd_alias
    ensure_bat_alias
}

setup_xdg_directories() {
    log_info "Ensuring XDG base directories exist"
    mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME"
    mkdir -p "$HOME/.zsh_sessions" "$HOME/.ssh/sockets"
    chmod 700 "$HOME/.ssh" "$HOME/.ssh/sockets" 2>/dev/null || true
    log_success "XDG directories ready"
}

run_dotbot() {
    if [[ ! -x "$DOTBOT_INSTALL" ]]; then
        fail "Dotbot installer not found at $DOTBOT_INSTALL"
    fi

    local template="$DOTFILES_DIR/config/git/gitconfig.local.template"
    local target="$DOTFILES_DIR/config/git/gitconfig.local"

    if [[ -f "$template" && ! -f "$target" ]]; then
        cp "$template" "$target"
    fi

    mkdir -p "$XDG_DATA_HOME/zinit"

    log_info "Running Dotbot to apply symlinks"
    DOTFILES_SKIP_TOUCHID_LINK=true "$DOTBOT_INSTALL" || log_warn "Dotbot reported issues"
    log_success "Dotbot configuration applied"
}

setup_dev_directory() {
    if [[ ! -x "$DEV_BOOTSTRAP_SCRIPT" ]]; then
        log_warn "Dev directory bootstrap script not found"
        return
    fi

    log_info "Setting up development directory"
    "$DEV_BOOTSTRAP_SCRIPT" || log_warn "Dev directory setup encountered issues"
    log_success "Development directory ready"
}

run_xdg_cleanup() {
    if [[ ! -x "$XDG_CLEANUP_SCRIPT" ]]; then
        log_warn "XDG cleanup script not found"
        return
    fi

    log_info "Running XDG cleanup"
    "$XDG_CLEANUP_SCRIPT" --from-bootstrap || log_warn "XDG cleanup reported issues"
    log_success "XDG cleanup complete"
}

ensure_default_shell() {
    local zsh_path
    zsh_path=$(command -v zsh || true)

    if [[ -z "$zsh_path" ]]; then
        log_warn "zsh binary not found; skipping default shell change"
        return
    fi

    if [[ "${SHELL:-}" == "$zsh_path" ]]; then
        log_success "Default shell already set to zsh"
        return
    fi

    log_info "Setting default shell to zsh"
    if chsh -s "$zsh_path" "$USER" >/dev/null 2>&1; then
        log_success "Default shell updated"
    else
        log_warn "Failed to change default shell automatically. Run 'chsh -s $zsh_path' manually."
    fi
}

main() {
    echo "🚀 Ubuntu Dotfiles Bootstrap"
    echo "============================"

    ensure_platform
    ensure_not_root
    require_commands sudo apt-get dpkg
    ensure_ubuntu_codename

    log_info "Requesting sudo credentials"
    sudo -v || fail "Failed to acquire sudo credentials"

    install_minimal_packages
    install_requested_apps
    setup_xdg_directories
    run_dotbot
    setup_dev_directory
    run_xdg_cleanup
    ensure_default_shell

    log_success "Bootstrap complete. Restart your shell to load the new configuration."
}

main "$@"
