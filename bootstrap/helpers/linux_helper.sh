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
KUBERNETES_REPO_VERSION="${KUBERNETES_REPO_VERSION:-v1.34}"

export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

declare -Ag INSTALL_RESULTS=()
declare -a INSTALL_ORDER=()
DEFAULT_SHELL_UPDATED=false
DEFAULT_SHELL_TARGET=""

record_install_result() {
    local tool="$1"
    local status="$2"
    local details="${3:-}"
    if [[ -n "$details" ]]; then
        INSTALL_RESULTS["$tool"]="$status - $details"
    else
        INSTALL_RESULTS["$tool"]="$status"
    fi
}

detect_tool_presence() {
    local tool="$1"
    local method="$2"
    local payload="$3"

    case "$method" in
        apt)
            local pkg
            for pkg in $payload; do
                if ! dpkg -s "$pkg" >/dev/null 2>&1; then
                    return 1
                fi
            done
            return 0
            ;;
        manual)
            case "$tool" in
                awscli)
                    command -v aws >/dev/null 2>&1
                    ;;
                bat-extras)
                    command -v batman >/dev/null 2>&1 && command -v batdiff >/dev/null 2>&1
                    ;;
                btop)
                    command -v btop >/dev/null 2>&1
                    ;;
                docker)
                    command -v docker >/dev/null 2>&1
                    ;;
                fastfetch)
                    command -v fastfetch >/dev/null 2>&1
                    ;;
                helm)
                    command -v helm >/dev/null 2>&1
                    ;;
                kind)
                    command -v kind >/dev/null 2>&1
                    ;;
                kubernetes-cli)
                    command -v kubectl >/dev/null 2>&1
                    ;;
                minikube)
                    command -v minikube >/dev/null 2>&1
                    ;;
                terraform)
                    command -v terraform >/dev/null 2>&1
                    ;;
                xq)
                    if command -v xq >/dev/null 2>&1; then
                        return 0
                    fi
                    if command -v pipx >/dev/null 2>&1 && pipx list 2>/dev/null | grep -q '^package yq'; then
                        return 0
                    fi
                    return 1
                    ;;
                oh-my-posh)
                    command -v oh-my-posh >/dev/null 2>&1
                    ;;
                pyenv)
                    command -v pyenv >/dev/null 2>&1 || [[ -x "${PYENV_ROOT:-$HOME/.pyenv}/bin/pyenv" ]]
                    ;;
                *)
                    return 1
                    ;;
            esac
            return $?
            ;;
        provided)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

print_install_summary() {
    if [[ ${#INSTALL_ORDER[@]} -eq 0 ]]; then
        return
    fi

    log_info "Tools installation summary:"
    local tool
    for tool in "${INSTALL_ORDER[@]}"; do
        local result="${INSTALL_RESULTS[$tool]:-not processed}"
        log_info "  • ${tool}: ${result}"
    done
}

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

remove_repo_file_if_contains() {
    local file_path="$1"
    local pattern="$2"

    if [[ -f "$file_path" ]] && grep -Fq "$pattern" "$file_path" 2>/dev/null; then
        sudo rm -f "$file_path"
        reset_apt_update_flag
    fi
}

remove_repo_file() {
    local file_path="$1"

    if [[ -f "$file_path" ]]; then
        sudo rm -f "$file_path"
        reset_apt_update_flag
    fi
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
    local key_url="${3:-}"
    local force_key="${4:-false}"
    local custom_key_path="${5:-}"
    local custom_list_file="${6:-}"

    ensure_keyring_directory

    local key_path
    key_path="${custom_key_path:-$APT_KEYRING_DIR/${name}.gpg}"
    local list_file
    list_file="${custom_list_file:-/etc/apt/sources.list.d/${name}.list}"

    if [[ -n "$key_url" ]]; then
        if [[ "$force_key" == "true" ]]; then
            sudo rm -f "$key_path"
        fi
        if [[ ! -f "$key_path" ]]; then
            if curl -fsSL "$key_url" | gpg --dearmor 2>/dev/null | sudo tee "$key_path" >/dev/null; then
                sudo chmod a+r "$key_path"
            else
                log_warn "Failed to download GPG key for $name repositories"
            fi
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
    remove_repo_file_if_contains "/etc/apt/sources.list.d/helm.list" "baltocdn.com/helm"
    remove_repo_file_if_contains "/etc/apt/sources.list.d/helm-stable-debian.list" "baltocdn.com/helm"
    remove_repo_file "/etc/apt/sources.list.d/helm.list"
    remove_repo_file "/etc/apt/sources.list.d/helm-stable-debian.list"

    local repo_line="deb [signed-by=${APT_KEYRING_DIR}/helm.gpg] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main"
    add_apt_repository "helm" "$repo_line" "https://packages.buildkite.com/helm-linux/helm-debian/gpgkey" true "" "/etc/apt/sources.list.d/helm-stable-debian.list"
}

setup_kubernetes_repository() {
    remove_repo_file_if_contains "/etc/apt/sources.list.d/kubernetes.list" "apt.kubernetes.io"

    local key_path="${APT_KEYRING_DIR}/kubernetes-apt-keyring.gpg"
    local repo_line="deb [signed-by=${key_path}] https://pkgs.k8s.io/core:/stable:/${KUBERNETES_REPO_VERSION}/deb/ /"
    add_apt_repository "kubernetes" "$repo_line" "https://pkgs.k8s.io/core:/stable:/${KUBERNETES_REPO_VERSION}/deb/Release.key" true "$key_path" "/etc/apt/sources.list.d/kubernetes.list"
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

install_awscli() {
    if command -v aws >/dev/null 2>&1; then
        if aws --version 2>/dev/null | grep -q 'aws-cli/2'; then
            log_success "AWS CLI v2 already installed"
            return
        fi
        log_info "Replacing existing AWS CLI installation"
    fi

    local arch
    if ! arch=$(detect_binary_arch); then
        log_warn "Skipping AWS CLI installation due to unsupported architecture"
        return
    fi

    local asset_arch
    case "$arch" in
        amd64)
            asset_arch="x86_64"
            ;;
        arm64)
            asset_arch="aarch64"
            ;;
        *)
            log_warn "Unsupported AWS CLI architecture mapping for $arch"
            return
            ;;
    esac

    local tmp_dir
    tmp_dir=$(mktemp -d)
    local zip_path="$tmp_dir/awscliv2.zip"

    if curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${asset_arch}.zip" -o "$zip_path"; then
        if unzip -q "$zip_path" -d "$tmp_dir"; then
            if sudo "$tmp_dir/aws/install" --update; then
                log_success "AWS CLI v2 installed"
            else
                log_warn "AWS CLI installer reported an error"
            fi
        else
            log_warn "Failed to extract AWS CLI archive"
        fi
    else
        log_warn "Failed to download AWS CLI archive"
    fi

    rm -rf "$tmp_dir"
}

install_helm() {
    setup_helm_repository

    if command -v helm >/dev/null 2>&1; then
        log_success "Helm already installed"
        return
    fi

    if ensure_package helm; then
        log_success "Helm installed"
    else
        log_warn "Helm installation failed"
    fi
}

install_kubectl() {
    setup_kubernetes_repository

    if command -v kubectl >/dev/null 2>&1; then
        log_success "kubectl already installed"
        return
    fi

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

install_btop() {
    if command -v btop >/dev/null 2>&1; then
        local current_version
        current_version=$(btop --version 2>/dev/null || true)
        log_success "btop already installed${current_version:+ ($current_version)}"
        return
    fi

    if dpkg -s btop >/dev/null 2>&1; then
        log_info "Removing apt-provided btop to avoid config rewrites"
        if ! sudo apt-get remove -y btop >/dev/null 2>&1; then
            log_warn "Failed to remove existing btop package"
        fi
    fi

    local release_json
    release_json=$(curl -fsSL https://api.github.com/repos/aristocratos/btop/releases/latest 2>/dev/null || true)
    if [[ -z "$release_json" ]]; then
        log_warn "Unable to query btop release metadata"
        return
    fi

    local version
    version=$(jq -r '.tag_name' <<<"$release_json" 2>/dev/null || true)
    if [[ -z "$version" || "$version" == null ]]; then
        log_warn "Unable to determine latest btop version"
        return
    fi

    local arch_token
    case "$(uname -m)" in
        x86_64|amd64)
            arch_token="x86_64"
            ;;
        arm64|aarch64)
            arch_token="aarch64"
            ;;
        *)
            log_warn "Unsupported architecture for btop: $(uname -m)"
            return
            ;;
    esac

    local asset_name="btop-${arch_token}-linux-musl.tbz"
    local asset_url
    asset_url=$(jq -r --arg name "$asset_name" '.assets[]?.browser_download_url | select(endswith($name))' <<<"$release_json" 2>/dev/null | head -n1)

    if [[ -z "$asset_url" || "$asset_url" == null ]]; then
        log_warn "Failed to locate btop release asset matching $asset_name"
        return
    fi

    local tmp_dir
    tmp_dir=$(mktemp -d)
    local archive="$tmp_dir/$asset_name"

    if ! curl -fsSL "$asset_url" -o "$archive"; then
        log_warn "Failed to download btop archive"
        rm -rf "$tmp_dir"
        return
    fi

    if ! tar -xjf "$archive" -C "$tmp_dir"; then
        log_warn "Failed to extract btop archive"
        rm -rf "$tmp_dir"
        return
    fi

    local extracted_dir
    extracted_dir=$(find "$tmp_dir" -maxdepth 1 -type d -name 'btop*' -print -quit)
    if [[ -z "$extracted_dir" ]]; then
        log_warn "Unable to locate extracted btop directory"
        rm -rf "$tmp_dir"
        return
    fi

    if [[ ! -x "$extracted_dir/bin/btop" ]]; then
        log_warn "btop binary missing from extracted archive"
        rm -rf "$tmp_dir"
        return
    fi

    sudo install -m 0755 "$extracted_dir/bin/btop" /usr/local/bin/btop

    if [[ -d "$extracted_dir/share/btop" ]]; then
        sudo rm -rf /usr/local/share/btop
        sudo install -d /usr/local/share/btop
        sudo cp -R "$extracted_dir/share/btop/." /usr/local/share/btop/
    fi

    rm -rf "$tmp_dir"
    log_success "btop ${version#v} installed"
}

install_bat_extras() {
    local needs_install=false
    local tool

    for tool in batman batdiff; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            needs_install=true
        fi
    done

    if [[ "$needs_install" == false ]]; then
        log_success "bat-extras already installed (batman, batdiff)"
        return
    fi

    local release_json
    release_json=$(curl -fsSL https://api.github.com/repos/eth-p/bat-extras/releases/latest 2>/dev/null || true)
    if [[ -z "$release_json" ]]; then
        log_warn "Unable to query bat-extras release metadata"
        return
    fi

    local version
    version=$(jq -r '.tag_name' <<<"$release_json" 2>/dev/null || true)
    if [[ -z "$version" || "$version" == null ]]; then
        log_warn "Unable to determine latest bat-extras version"
        return
    fi

    local asset_url
    local asset_type
    asset_url=$(jq -r '.assets[]?.browser_download_url | select(test("bat-extras-.*\\.zip$"))' <<<"$release_json" 2>/dev/null | head -n1)
    if [[ -n "$asset_url" && "$asset_url" != null ]]; then
        asset_type="zip"
    else
        asset_url=$(jq -r '.assets[]?.browser_download_url | select(test("bat-extras-.*\\.tar\\.gz$"))' <<<"$release_json" 2>/dev/null | head -n1)
        if [[ -n "$asset_url" && "$asset_url" != null ]]; then
            asset_type="tar"
        else
            log_warn "Failed to locate bat-extras release asset"
            return
        fi
    fi

    local tmp_dir
    tmp_dir=$(mktemp -d)
    local bin_dir=""

    case "$asset_type" in
        zip)
            local archive_zip="$tmp_dir/bat-extras.zip"
            if curl -fsSL "$asset_url" -o "$archive_zip" && unzip -q "$archive_zip" -d "$tmp_dir"; then
                bin_dir=$(find "$tmp_dir" -maxdepth 2 -type d -name bin -print -quit)
            fi
            ;;
        tar)
            local archive_tar="$tmp_dir/bat-extras.tar.gz"
            if curl -fsSL "$asset_url" -o "$archive_tar" && tar -xzf "$archive_tar" -C "$tmp_dir"; then
                bin_dir=$(find "$tmp_dir" -maxdepth 2 -type d -name bin -print -quit)
            fi
            ;;
    esac

    if [[ -n "$bin_dir" ]]; then
        local installed_any=false
        for tool in batman batdiff; do
            if [[ -x "$bin_dir/$tool" ]]; then
                sudo install -m 0755 "$bin_dir/$tool" /usr/local/bin/"$tool"
                installed_any=true
            else
                log_warn "bat-extras binary '$tool' not found in release"
            fi
        done

        if [[ "$installed_any" == true ]]; then
            log_success "bat-extras ${version} installed (batman, batdiff)"
        else
            log_warn "Failed to install required bat-extras tools"
        fi
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

    local arch
    if ! arch=$(detect_binary_arch); then
        log_warn "Skipping fastfetch installation due to unsupported architecture"
        return
    fi

    local release_json
    release_json=$(curl -fsSL https://api.github.com/repos/fastfetch-cli/fastfetch/releases/latest 2>/dev/null || true)
    if [[ -z "$release_json" ]]; then
        log_warn "Unable to query fastfetch release metadata"
        return
    fi

    local version
    version=$(jq -r '.tag_name' <<<"$release_json" 2>/dev/null || true)
    if [[ -z "$version" || "$version" == null ]]; then
        log_warn "Unable to determine latest fastfetch version"
        return
    fi

    local asset_arch
    case "$arch" in
        amd64)
            asset_arch="amd64"
            ;;
        arm64)
            asset_arch="aarch64"
            ;;
        *)
            log_warn "Unsupported fastfetch architecture mapping for $arch"
            return
            ;;
    esac

    local asset_url
    asset_url=$(jq -r --arg arch "$asset_arch" '.assets[]?.browser_download_url | select(test("fastfetch-linux-" + $arch + "\\.tar\\.gz$") and (contains("polyfilled") | not))' <<<"$release_json" 2>/dev/null | head -n1)
    if [[ -z "$asset_url" ]]; then
        asset_url=$(jq -r --arg arch "$asset_arch" '.assets[]?.browser_download_url | select(test("fastfetch-linux-" + $arch + "\\.tar\\.gz$"))' <<<"$release_json" 2>/dev/null | head -n1)
    fi
    if [[ -z "$asset_url" || "$asset_url" == null ]]; then
        log_warn "Failed to locate fastfetch release asset"
        return
    fi

    local tmp_dir
    tmp_dir=$(mktemp -d)
    if curl -fsSL "$asset_url" -o "$tmp_dir/fastfetch.tar.gz" && \
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

install_pyenv() {
    if command -v pyenv >/dev/null 2>&1; then
        log_success "pyenv already installed"
        return
    fi

    local build_deps=(
        make
        build-essential
        libssl-dev
        zlib1g-dev
        libbz2-dev
        libreadline-dev
        libsqlite3-dev
        libffi-dev
        liblzma-dev
        libncurses-dev
        xz-utils
        tk-dev
    )

    local dep
    for dep in "${build_deps[@]}"; do
        ensure_package "$dep"
    done

    local pyenv_root="${PYENV_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/pyenv}"
    local legacy_pyenv_root="$HOME/.pyenv"

    mkdir -p "$(dirname "$pyenv_root")"

    if [[ "$pyenv_root" != "$legacy_pyenv_root" && -d "$legacy_pyenv_root" && ! -e "$pyenv_root" ]]; then
        log_info "Migrating legacy pyenv directory to $pyenv_root"
        if mv "$legacy_pyenv_root" "$pyenv_root"; then
            log_success "Legacy pyenv directory migrated"
        else
            log_warn "Failed to migrate legacy pyenv directory"
        fi
    fi
    if [[ -d "$pyenv_root/.git" ]]; then
        log_info "Updating pyenv repository"
        if ! git -C "$pyenv_root" pull --ff-only >/dev/null 2>&1; then
            log_warn "Failed to update pyenv repository"
        fi
    else
        log_info "Cloning pyenv"
        if ! git clone https://github.com/pyenv/pyenv.git "$pyenv_root" >/dev/null 2>&1; then
            log_warn "Failed to clone pyenv"
            return
        fi
    fi

    if [[ -x "$pyenv_root/bin/pyenv" ]]; then
        ensure_local_bin
        ln -sf "$pyenv_root/bin/pyenv" "$HOME/.local/bin/pyenv"
        log_success "pyenv installed"
    else
        log_warn "pyenv binary not found after installation"
    fi
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

        INSTALL_ORDER+=("$tool")

        case "$method" in
            apt)
                local pkg
                local success=true
                for pkg in $payload; do
                    if ! ensure_package "$pkg"; then
                        success=false
                    fi
                done
                if [[ "$success" == true ]]; then
                    if detect_tool_presence "$tool" "$method" "$payload"; then
                        record_install_result "$tool" "available" "apt: $payload"
                    else
                        record_install_result "$tool" "needs attention" "apt verification failed"
                    fi
                else
                    record_install_result "$tool" "failed" "apt: $payload"
                fi
                ;;
            manual)
                if declare -F "$payload" >/dev/null 2>&1; then
                    local install_exit=0
                    if "$payload"; then
                        install_exit=0
                    else
                        install_exit=$?
                    fi
                    if detect_tool_presence "$tool" "$method" "$payload"; then
                        record_install_result "$tool" "available" "manual: $payload"
                    elif (( install_exit == 0 )); then
                        record_install_result "$tool" "needs attention" "manual: $payload"
                    else
                        record_install_result "$tool" "failed" "manual: $payload"
                    fi
                else
                    log_warn "Installer function $payload for $tool not found"
                    record_install_result "$tool" "skipped" "installer not defined"
                fi
                ;;
            provided)
                log_success "$tool provided by ${payload:-another installer}"
                record_install_result "$tool" "provided" "${payload:-}"
                ;;
            *)
                log_warn "Unknown install method '$method' for $tool"
                record_install_result "$tool" "skipped" "unknown method $method"
                ;;
        esac
    done < "$APPS_LIST_FILE"

    ensure_fd_alias
    ensure_bat_alias
    print_install_summary
}

disable_sudo_admin_flag() {
    local sudoers_file="/etc/sudoers.d/disable_admin_flag"
    local visudo_cmd
    visudo_cmd=$(command -v visudo 2>/dev/null || echo /usr/sbin/visudo)

    if sudo test -f "$sudoers_file" 2>/dev/null && \
       sudo grep -Eq '^\s*Defaults\s+!admin_flag\b' "$sudoers_file" 2>/dev/null; then
        log_success "sudo admin flag already disabled"
        return
    fi

    local tmp_file
    tmp_file=$(mktemp)
    printf 'Defaults !admin_flag\n' >"$tmp_file"

    if ! sudo "$visudo_cmd" -cf "$tmp_file" >/dev/null 2>&1; then
        log_warn "Failed to validate sudoers snippet for disabling admin flag"
        rm -f "$tmp_file"
        return
    fi

    if sudo install -o root -g root -m 0440 "$tmp_file" "$sudoers_file"; then
        log_success "Disabled sudo admin flag"
    else
        log_warn "Failed to install sudoers snippet to disable admin flag"
    fi

    rm -f "$tmp_file"
}

setup_xdg_directories() {
    log_info "Ensuring XDG base directories exist"
    mkdir -p \
        "$XDG_CONFIG_HOME" \
        "$XDG_DATA_HOME" \
        "$XDG_CACHE_HOME" \
        "$XDG_STATE_HOME" \
        "$XDG_CACHE_HOME/zsh" \
        "$XDG_STATE_HOME/zsh/sessions" \
        "$HOME/.ssh/sockets"
    chmod 700 "$HOME/.ssh" "$HOME/.ssh/sockets" "$XDG_STATE_HOME/zsh" "$XDG_STATE_HOME/zsh/sessions" 2>/dev/null || true
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

schedule_post_cleanup_pass() {
    if [[ "${DOTFILES_SKIP_XDG_CLEANUP_SECOND_PASS:-false}" == "true" ]]; then
        return
    fi

    if [[ ! -x "$XDG_CLEANUP_SCRIPT" ]]; then
        return
    fi

    log_info "Scheduling follow-up XDG cleanup pass"
    (
        sleep 2
        "$XDG_CLEANUP_SCRIPT" --from-bootstrap >/dev/null 2>&1 || true
    ) &
}

ensure_shell_registered() {
    local shell_path="$1"

    if [[ -z "$shell_path" ]]; then
        return
    fi

    if sudo grep -Fxq "$shell_path" /etc/shells 2>/dev/null; then
        return
    fi

    log_info "Registering $shell_path as a valid login shell"
    if printf '%s\n' "$shell_path" | sudo tee -a /etc/shells >/dev/null; then
        log_success "Added $shell_path to /etc/shells"
    else
        log_warn "Failed to register $shell_path in /etc/shells"
    fi
}

canonical_shell_path() {
    local shell_path="$1"

    if [[ -z "$shell_path" ]]; then
        return
    fi

    if command -v readlink >/dev/null 2>&1; then
        readlink -f "$shell_path" 2>/dev/null || echo "$shell_path"
        return
    fi

    if command -v realpath >/dev/null 2>&1; then
        realpath "$shell_path" 2>/dev/null || echo "$shell_path"
        return
    fi

    echo "$shell_path"
}

ensure_default_shell() {
    declare -A seen_paths=()
    local -a candidates=()

    if command -v zsh >/dev/null 2>&1; then
        candidates+=("$(command -v zsh)")
    fi

    if [[ -x /usr/bin/zsh ]]; then
        candidates+=("/usr/bin/zsh")
    fi

    if [[ -x /bin/zsh ]]; then
        candidates+=("/bin/zsh")
    fi

    local -a unique_candidates=()
    local candidate
    for candidate in "${candidates[@]}"; do
        local resolved
        resolved="$(canonical_shell_path "$candidate")"
        if [[ -n "$resolved" && -z "${seen_paths[$resolved]:-}" ]]; then
            unique_candidates+=("$resolved")
            seen_paths[$resolved]=1
        fi
    done

    if (( ${#unique_candidates[@]} == 0 )); then
        log_warn "zsh binary not found; skipping default shell change"
        return
    fi

    local current_default
    current_default=$(getent passwd "$USER" | awk -F: '{print $7}' 2>/dev/null || echo "${SHELL:-}")
    local current_resolved
    current_resolved="$(canonical_shell_path "$current_default")"

    for candidate in "${unique_candidates[@]}"; do
        ensure_shell_registered "$candidate"
        if [[ -n "$current_resolved" && "$current_resolved" == "$candidate" ]]; then
            export SHELL="$candidate"
            DEFAULT_SHELL_TARGET="$candidate"
            log_success "Default shell already set to zsh ($candidate)"
            return
        fi
    done

    if ! sudo -n true 2>/dev/null; then
        log_info "Revalidating sudo credentials for shell change"
        if ! sudo -v; then
            log_warn "Unable to refresh sudo credentials; default shell unchanged"
            return
        fi
    fi

    for candidate in "${unique_candidates[@]}"; do
        log_info "Setting default shell to $candidate"

        if sudo usermod -s "$candidate" "$USER" >/dev/null 2>&1 ||
           sudo chsh -s "$candidate" "$USER" >/dev/null 2>&1 ||
           chsh -s "$candidate" "$USER" >/dev/null 2>&1; then
            current_default=$(getent passwd "$USER" | awk -F: '{print $7}' 2>/dev/null || true)
            current_resolved="$(canonical_shell_path "$current_default")"
            if [[ -n "$current_resolved" && "$current_resolved" == "$candidate" ]]; then
                export SHELL="$candidate"
                DEFAULT_SHELL_TARGET="$candidate"
                DEFAULT_SHELL_UPDATED=true
                log_success "Default shell updated to $candidate"
                return
            fi
        fi

        log_warn "Failed to change default shell to $candidate"
    done

    log_warn "Failed to change default shell automatically. Run 'sudo chsh -s ${unique_candidates[0]} $USER' manually."
}

maybe_restart_shell() {
    local zsh_path="${DEFAULT_SHELL_TARGET:-}"
    if [[ -z "$zsh_path" ]]; then
        zsh_path=$(command -v zsh || true)
    fi
    if [[ -z "$zsh_path" ]]; then
        return
    fi

    if [[ "${DOTFILES_SKIP_SHELL_RESTART:-false}" == "true" ]]; then
        log_info "Skipping automatic shell restart (DOTFILES_SKIP_SHELL_RESTART=true)."
        return
    fi

    local shell_matches=false
    if [[ "${SHELL:-}" == "$zsh_path" ]]; then
        shell_matches=true
    fi

    if [[ "$DEFAULT_SHELL_UPDATED" != true && "$shell_matches" == true ]]; then
        return
    fi

    if [[ ! -t 0 || ! -t 1 ]]; then
        if [[ "$DEFAULT_SHELL_UPDATED" == true ]]; then
            log_info "Default shell changed to zsh. Start a new session or run '$zsh_path -l' to reload the environment."
        else
            log_info "Default shell already set to zsh ($zsh_path). Start a new session or run '$zsh_path -l' to reload the environment."
        fi
        return
    fi

    if [[ "$shell_matches" == true ]]; then
        return
    fi

    export SHELL="$zsh_path"
    if [[ "$DEFAULT_SHELL_UPDATED" == true ]]; then
        log_info "Launching a new zsh login shell ($zsh_path) to apply changes"
    else
        log_info "Switching to zsh login shell ($zsh_path) to match current default"
    fi
    exec "$zsh_path" -l
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

    setup_helm_repository
    setup_kubernetes_repository

    install_minimal_packages
    install_requested_apps
    disable_sudo_admin_flag
    setup_xdg_directories
    run_dotbot
    setup_dev_directory
    ensure_default_shell
    run_xdg_cleanup
    schedule_post_cleanup_pass

    log_success "Bootstrap complete."
    maybe_restart_shell
}

main "$@"
