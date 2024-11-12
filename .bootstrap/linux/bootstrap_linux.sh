#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# ---------------------------
# Request Sudo Privileges
# ---------------------------

# Prompt for sudo password upfront
sudo -v

# Keep-alive: update existing `sudo` time stamp until script has finished
while true; do
    sudo -n true
    sleep 60
    kill -0 "$$" || exit  # Fixed: Changed "$" to "$$" to reference the script's PID
done 2>/dev/null &

# ---------------------------
# Constants and Configuration
# ---------------------------

# Set Dotfiles directory
DOTFILES_DIR="$HOME/.dotfiles"
PACKAGES_FILE="$DOTFILES_DIR/.bootstrap/linux/base_packages.list"
DOTBOT_INSTALL="$DOTFILES_DIR/install"
ZPROFILE="$DOTFILES_DIR/.zsh/.zprofile"

# ---------------------------
# Color Output Setup
# ---------------------------

COLORS_INFO="\e[32m"
COLORS_WARNING="\e[33m"
COLORS_ERROR="\e[31m"
COLORS_RESET="\e[0m"

# ---------------------------
# Helper Functions
# ---------------------------

# Logging Functions
log_info() { echo -e "${COLORS_INFO}[INFO] $1${COLORS_RESET}"; }
log_warning() { echo -e "${COLORS_WARNING}[WARNING] $1${COLORS_RESET}"; }
log_error() { echo -e "${COLORS_ERROR}[ERROR] $1${COLORS_RESET}"; }

# ---------------------------
# System Check
# ---------------------------

check_linux() {
    if [[ "$(uname)" != "Linux" ]]; then
        log_error "🚫 This script is designed for Linux."
        exit 1
    else
        log_info "✅ Operating system is Linux."
    fi
}

# ---------------------------
# Clear Cache
# ---------------------------

clear_cache() {
    log_info "🧹 Clearing local package cache and updating..."

    # Clear the package list cache
    sudo rm -rf /var/lib/apt/lists/*
    
    # Update the package list
    if sudo apt update; then
        log_info "✅ Package cache cleared and updated successfully."
    else
        log_error "🚫 Failed to update package list. Please check your network connection or repository configuration."
        return 1
    fi
}


# ---------------------------
# Clock Sync
# ---------------------------

sync_system_clock() {
    log_info "🔄 Synchronizing system clock..."

    if command -v timedatectl &> /dev/null; then
        # Most modern systems (Ubuntu, CentOS 7+, etc.)
        sudo timedatectl set-ntp true
        log_info "✅ System clock synchronized using timedatectl."

    elif command -v ntpdate &> /dev/null; then
        # Older systems or fallback to ntpdate if available
        sudo ntpdate -u pool.ntp.org
        log_info "✅ System clock synchronized using ntpdate."

    elif command -v chronyd &> /dev/null; then
        # Some distributions like CentOS 8+ use chronyd as the default NTP client
        sudo systemctl start chronyd
        sudo chronyc -a makestep
        log_info "✅ System clock synchronized using chronyd."

    elif command -v openntpd &> /dev/null; then
        # OpenNTPD, an alternative NTP client
        sudo systemctl start openntpd
        log_info "✅ System clock synchronized using openntpd."

    else
        log_error "🚫 No suitable time synchronization tool found. Please install ntpdate, timedatectl, chrony, or openntpd."
        return 1
    fi
}

# ---------------------------
# Shell Check
# ---------------------------

check_zsh() {
    log_info "🔍 Checking if ZSH is installed..."

    if command -v zsh &> /dev/null; then
        log_info "✅ ZSH is already installed."
    else
        log_info "ZSH is not installed. Installing ZSH..."

        local max_attempts=3
        local attempt=1

        while [[ $attempt -le 3 ]]; do
            log_info "Attempt $attempt of 3 to install ZSH..."
            if sudo apt update && sudo apt install -y zsh; then
                log_info "✅ ZSH installed successfully."
                break
            else
                log_warning "⚠️ Failed to install ZSH on attempt $attempt."
                ((attempt++))
                sleep 2
            fi
        done

        if [[ $attempt -gt 3 ]]; then
            log_error "🚫 ZSH installation failed after 3 attempts."
            exit 1
        fi
    fi
}

# ---------------------------
# System Update
# ---------------------------

update_system() {
    log_info "🔄 Updating system packages..."

    local max_attempts=3
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        log_info "Attempt $attempt of $max_attempts..."
        if sudo apt update && sudo apt upgrade -y; then
            log_info "✅ System update complete!"
            break
        else
            log_warning "⚠️ System update failed on attempt $attempt."
            ((attempt++))
            sleep 2  # Wait a bit before retrying
        fi
    done

    if [[ $attempt -gt $max_attempts ]]; then
        log_error "🚫 System update failed after $max_attempts attempts."
        exit 1
    fi

    # Install common dependencies
    if sudo apt install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        software-properties-common; then
        log_info "✅ Common dependencies installed."
    else
        log_warning "⚠️ Failed to install common dependencies."
    fi
}

# ---------------------------
# APT Package Installation
# ---------------------------

install_packages() {
    if [[ ! -f "$PACKAGES_FILE" ]]; then
        log_error "🚫 Package list not found at $PACKAGES_FILE"
        return 1
    fi

    log_info "📦 Updating package lists..."
    if ! sudo apt update; then
        log_error "Failed to update package lists"
        return 1
    fi

    # Read packages from file, filtering out comments and empty lines
    local packages=()
    while IFS= read -r line; do
        # Skip comments and empty lines
        [[ $line =~ ^#.*$ || -z $line ]] && continue
        packages+=("$line")
    done < "$PACKAGES_FILE"

    log_info "📦 Installing packages..."
    for package in "${packages[@]}"; do
        log_info "Installing $package..."
        if sudo apt install -y "$package"; then
            log_info "✅ $package installed successfully."
        else
            log_warning "⚠️ Failed to install $package."
        fi
    done

    log_info "✅ Package installation complete!"
}

# ---------------------------
# Additional Package Installation
# ---------------------------

install_atuin() {
    log_info "🔄 Installing Atuin..."

    # Check if cargo is installed
    if ! command -v cargo &> /dev/null; then
        log_warning "⚠️ Cargo is not installed. Installing Rust toolchain..."
        if curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y; then
            source "$HOME/.cargo/env"
        else
            log_error "🚫 Failed to install Rust toolchain."
            return
        fi
    fi

    # Install Atuin using official method
    if git clone https://github.com/atuinsh/atuin.git "$HOME/atuin_temp" && \
       cd "$HOME/atuin_temp/crates/atuin" && \
       cargo install --path .; then
        log_info "✅ Atuin installed successfully!"
        # Clean up
        rm -rf "$HOME/atuin_temp"
    else
        log_warning "⚠️ Failed to install Atuin."
    fi
}

install_awscli() {
    log_info "☁️ Installing AWS CLI..."
    local arch
    arch=$(uname -m)
    local url
    case "$arch" in
        x86_64)
            url="https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip"
            ;;
        aarch64)
            url="https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip"
            ;;
        *)
            log_warning "⚠️ Unsupported architecture: $arch"
            return
            ;;
    esac

    if curl "$url" -o "awscliv2.zip"; then
        unzip awscliv2.zip
        if sudo ./aws/install; then
            rm -rf aws awscliv2.zip
            log_info "✅ AWS CLI installed successfully!"
        else
            log_warning "⚠️ Failed to install AWS CLI."
        fi
    else
        log_warning "⚠️ Failed to download AWS CLI."
    fi
}

install_fastfetch() {
    log_info "📊 Installing Fastfetch..."

    local ubuntu_version
    ubuntu_version=$(lsb_release -rs)
    if [[ $(echo "$ubuntu_version >= 22.04" | bc -l) -eq 1 ]]; then
        log_info "Using PPA for Ubuntu $ubuntu_version."
        if sudo add-apt-repository -y ppa:zhangsongcui3371/fastfetch && sudo apt update && sudo apt install -y fastfetch; then
            log_info "✅ Fastfetch installed successfully!"
        else
            log_warning "⚠️ Failed to install Fastfetch."
        fi
    else
        log_info "Ubuntu version is less than 22.04, using alternative installation method."
        # Use alternative method if needed
        if sudo apt install -y fastfetch; then
            log_info "✅ Fastfetch installed successfully!"
        else
            log_warning "⚠️ Failed to install Fastfetch."
        fi
    fi
}

install_kind() {
    log_info "🔄 Installing Kind..."
    # Install Kind using Go (ensure Go is installed first)
    if command -v go &> /dev/null; then
        if go install sigs.k8s.io/kind@latest; then
            # Add KIND to PATH by creating a symbolic link
            sudo ln -sf "$(go env GOPATH)/bin/kind" /usr/local/bin/kind
            log_info "✅ Kind installed successfully!"
        else
            log_warning "⚠️ Failed to install Kind."
        fi
    else
        log_error "❌ Go is required for Kind installation. Please install Go first."
    fi
}

install_zsh_you_should_use() {
    log_info "🔌 Installing zsh-you-should-use plugin..."

    ZSH_PLUGIN_DIR="$HOME/.zsh/.zshplugins"

    if [[ ! -d "$ZSH_PLUGIN_DIR" ]]; then
        mkdir -p "$ZSH_PLUGIN_DIR"
    fi

    if [[ ! -d "$ZSH_PLUGIN_DIR/you-should-use" ]]; then
        if git clone https://github.com/MichaelAquilina/zsh-you-should-use "$ZSH_PLUGIN_DIR/you-should-use"; then
            log_info "✅ zsh-you-should-use plugin installed successfully!"
        else
            log_warning "⚠️ Failed to clone zsh-you-should-use plugin."
        fi
    else
        log_info "✅ zsh-you-should-use plugin is already installed."
    fi
}

install_docker() {
    log_info "🐳 Installing Docker CE..."

    # Add Docker's official GPG key
    if sudo apt-get update && sudo apt-get install -y ca-certificates curl gnupg; then
        sudo install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        sudo chmod a+r /etc/apt/keyrings/docker.gpg

        # Add the repository to apt sources
        echo \
        "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

        # Install Docker packages
        if sudo apt-get update && sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
            # Add user to docker group
            sudo usermod -aG docker "$USER"
            log_info "✅ Docker CE installed successfully!"
        else
            log_warning "⚠️ Failed to install Docker CE."
        fi
    else
        log_warning "⚠️ Failed to set up Docker repository."
    fi
}

install_go() {
    log_info "🔧 Installing Go..."
    local GO_VERSION="1.22.0"  # Update this version as needed
    local ARCH="$(dpkg --print-architecture)"

    # Download and install Go
    if wget "https://go.dev/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz"; then
        sudo rm -rf /usr/local/go
        if sudo tar -C /usr/local -xzf "go${GO_VERSION}.linux-${ARCH}.tar.gz"; then
            rm "go${GO_VERSION}.linux-${ARCH}.tar.gz"

            # Add Go to PATH in zprofile
            echo 'export PATH="$PATH:/usr/local/go/bin"' >> "$ZPROFILE"
            export PATH="$PATH:/usr/local/go/bin"
            log_info "✅ Go installed successfully!"
        else
            log_warning "⚠️ Failed to extract Go tarball."
        fi
    else
        log_warning "⚠️ Failed to download Go."
    fi
}

install_helm() {
    log_info "⎈ Installing Helm..."
    if curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null && \
       echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | \
       sudo tee /etc/apt/sources.list.d/helm-stable-debian.list && \
       sudo apt-get update && \
       sudo apt-get install -y helm; then
        log_info "✅ Helm installed successfully!"
    else
        log_warning "⚠️ Failed to install Helm."
    fi
}

install_kubectl() {
    log_info "☸️ Installing kubectl..."
    if curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg && \
       echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | \
       sudo tee /etc/apt/sources.list.d/kubernetes.list && \
       sudo apt-get update && \
       sudo apt-get install -y kubectl; then
        log_info "✅ kubectl installed successfully!"
    else
        log_warning "⚠️ Failed to install kubectl."
    fi
}

install_terraform() {
    log_info "🏗️ Installing Terraform..."
    if wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg && \
       echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | \
       sudo tee /etc/apt/sources.list.d/hashicorp.list && \
       sudo apt update && \
       sudo apt install -y terraform; then
        log_info "✅ Terraform installed successfully!"
    else
        log_warning "⚠️ Failed to install Terraform."
    fi
}

install_oh_my_posh() {
    log_info "🥳 Installing Oh My Posh..."

    # Determine installation directory
    local install_dir
    if [ -d "$HOME/bin" ]; then
        install_dir="$HOME/bin"
    elif [ -d "$HOME/.local/bin" ]; then
        install_dir="$HOME/.local/bin"
    else
        mkdir -p "$HOME/.local/bin"
        install_dir="$HOME/.local/bin"
    fi

    if curl -s https://ohmyposh.dev/install.sh | bash -s -- -d "$install_dir"; then
        log_info "✅ Oh My Posh installed successfully in $install_dir"

        # Ensure install_dir is in PATH
        if [[ ":$PATH:" != *":$install_dir:"* ]]; then
            export PATH="$install_dir:$PATH"
            echo 'export PATH="$HOME/.local/bin:$HOME/bin:$PATH"' >> "$ZPROFILE"
            log_info "🔧 Updated PATH to include $install_dir"
        fi
    else
        log_warning "⚠️ Failed to install Oh My Posh."
    fi
}

install_jetbrains_mono_nerd_font() {
    log_info "🎨 Installing JetBrains Mono Nerd Font..."

    local font_dir="$HOME/.local/share/fonts"
    mkdir -p "$font_dir"

    local url="https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/JetBrainsMono.zip"
    local zip_file="/tmp/JetBrainsMono.zip"

    if wget -O "$zip_file" "$url"; then
        unzip -o "$zip_file" -d "$font_dir"
        fc-cache -fv "$font_dir"
        rm "$zip_file"
        log_info "✅ JetBrains Mono Nerd Font installed successfully!"
    else
        log_warning "⚠️ Failed to download JetBrains Mono Nerd Font."
    fi
}

setup_bat_symlink() {
    log_info "🔧 Setting up bat symlink if needed..."
    if ! command -v bat &> /dev/null; then
        if command -v batcat &> /dev/null; then
            mkdir -p "$HOME/.local/bin"
            ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat"
            log_info "✅ Created symlink from batcat to bat."
        else
            log_warning "⚠️ Neither bat nor batcat found. Please install bat."
        fi
    else
        log_info "✅ bat command is already available."
    fi
}

update_path() {
    log_info "🔧 Ensuring ~/.local/bin and ~/bin are in PATH..."

    local profile_file="$HOME/.zprofile"

    # Create .zprofile if it doesn't exist
    if [[ ! -f "$profile_file" ]]; then
        log_info "📝 Creating .zprofile at $profile_file"
        touch "$profile_file"
    fi

    if ! grep -q 'export PATH="$HOME/.local/bin:$HOME/bin:$PATH"' "$profile_file"; then
        echo 'export PATH="$HOME/.local/bin:$HOME/bin:$PATH"' >> "$profile_file"
        log_info "✅ Updated PATH in $profile_file"
    else
        log_info "✅ PATH already includes ~/.local/bin and ~/bin"
    fi

    # Export the PATH in the current session
    export PATH="$HOME/.local/bin:$HOME/bin:$PATH"
}

install_additional_packages() {
    log_info "🚀 Installing additional packages..."

    install_docker
    install_go
    install_helm
    install_kubectl
    install_terraform
    install_oh_my_posh
    install_atuin
    install_awscli
    install_fastfetch
    install_kind
    install_zsh_you_should_use
    install_jetbrains_mono_nerd_font
    setup_bat_symlink  # Added function call to setup bat symlink

    log_info "✅ All additional packages installed successfully!"
}

# ---------------------------
# Git Configuration
# ---------------------------

setup_git() {
    if [[ -z "$GIT_USER_NAME" || -z "$GIT_USER_EMAIL" ]]; then
        log_warning "⚠️ Git user name or email not set. Skipping Git configuration."
        return
    fi

    log_info "🛠️ Configuring Git..."
    if git config --global user.name "$GIT_USER_NAME"; then
        log_info "✅ Git user.name set to $GIT_USER_NAME"
    else
        log_warning "⚠️ Failed to set Git user name."
    fi

    if git config --global user.email "$GIT_USER_EMAIL"; then
        log_info "✅ Git user.email set to $GIT_USER_EMAIL"
    else
        log_warning "⚠️ Failed to set Git user email."
    fi
}

# ---------------------------
# User Input Collection
# ---------------------------

get_user_inputs() {
    log_info "📝 Gathering user inputs for configuration..."

    # Collect Git User Name
    while true; do
        read -r -p "🔍 Enter Git user name: " GIT_USER_NAME
        if [[ -n "$GIT_USER_NAME" ]]; then
            break
        else
            log_warning "⚠️ Git user name cannot be empty."
        fi
    done

    # Collect Git User Email with Validation
    while true; do
        read -r -p "📧 Enter Git user email: " GIT_USER_EMAIL
        if [[ "$GIT_USER_EMAIL" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
            break
        else
            log_warning "⚠️ Please enter a valid email address."
        fi
    done
}


# ---------------------------
# Handle Existing Links or Files
# ---------------------------

handle_existing_links() {
    local links=(
        "$HOME/.zshrc"
        "$HOME/.config"
        "$HOME/.vscode"
    )

    for link in "${links[@]}"; do
        if [[ -e "$link" || -L "$link" ]]; then
            log_info "🗑️ Removing existing link or file: $link"
            if rm -rf "$link"; then
                log_info "✅ Removed $link"
            else
                log_warning "⚠️ Failed to remove $link"
            fi
        fi

        # Ensure parent directory exists
        local parent_dir="$(dirname "$link")"
        if [[ ! -d "$parent_dir" ]]; then
            log_info "📁 Creating parent directory: $parent_dir"
            if mkdir -p "$parent_dir"; then
                log_info "✅ Created directory: $parent_dir"
            else
                log_warning "⚠️ Failed to create directory: $parent_dir"
            fi
        fi
    done
}

# ---------------------------
# Dotbot Installation
# ---------------------------

run_dotbot() {
    if [[ -f "$DOTBOT_INSTALL" ]]; then
        log_info "🔗 Running Dotbot to symlink configuration files..."

        # Handle existing files before running Dotbot
        handle_existing_links

        # Run Dotbot with verbose output
        if "$DOTBOT_INSTALL" -v; then
            log_info "✅ Dotbot installation completed successfully."
        else
            log_warning "⚠️ Dotbot installation failed."
        fi
    else
        log_error "🚫 Dotbot install script not found at $DOTBOT_INSTALL"
    fi
}

# ---------------------------
# Change Default Shell to ZSH and Reboot
# ---------------------------

change_shell() {
    log_info "🔄 Changing default shell to ZSH..."

    if chsh -s "$(which zsh)" "$USER"; then
        log_info "✅ Default shell changed to ZSH."
        log_info "🔄 The system will reboot in 10 seconds to apply changes..."
        sleep 10
        sudo reboot
    else
        log_error "🚫 Failed to change the default shell to ZSH."
    fi
}

# ---------------------------
# Main Installation Process
# ---------------------------

main() {
    log_info "🚀 Starting machine bootstrap process..."

    # Perform initial system check
    check_linux

    # Clock Sync
    sync_system_clock

    # Clear Cache
    clear_cache

    # Check if ZSH is installed
    check_zsh

    # Update system
    update_system

    # Ensure PATH includes ~/.local/bin and ~/bin
    update_path

    # Gather user inputs
    get_user_inputs

    # Install packages
    install_packages
    install_additional_packages

    # Execute installation steps
    run_dotbot
    setup_git

    # Change default shell to ZSH at the end and trigger reboot
    change_shell
}

# Execute main function
main "$@"
