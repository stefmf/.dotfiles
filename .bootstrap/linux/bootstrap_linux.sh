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

# Set environment variable to indicate non-TTY session
IS_TTY_SESSION=false

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
# OS Check
# ---------------------------

check_os() {
    if [[ "$(uname)" != "Linux" ]]; then
        log_error "🚫 This script is designed for Linux."
        exit 1
    else
        log_info "✅ Operating system is Linux."
    fi
}

# ---------------------------
# Check if TTY Session
# ---------------------------

check_tty_session() {
    if [[ -t 1 && "$(tty)" == /dev/tty[0-9]* ]]; then
        log_info "ℹ️ TTY session detected."
        IS_TTY_SESSION=true
    else
        log_info "ℹ️ Not a TTY session."
        IS_TTY_SESSION=false
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
# Clear Cache
# ---------------------------

clear_cache() {
    log_info "🧹 Clearing local package cache and updating..."
    
    # Clear ZPROFILE PATH entries if ZPROFILE is set and exists
    if [[ -n "$ZPROFILE" && -f "$ZPROFILE" ]]; then
        local temp_file
        temp_file=$(mktemp)
        grep -v "export PATH=" "$ZPROFILE" > "$temp_file" || true
        mv "$temp_file" "$ZPROFILE"
        log_info "✅ Cleaned up PATH entries in $ZPROFILE"
    fi

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
# Update PATH Configuration
# ---------------------------

update_path() {
    log_info "🔧 Ensuring necessary directories are in PATH..."

    # Ensure ZPROFILE is set and the directory exists
    if [[ -z "$ZPROFILE" ]]; then
        log_error "ZPROFILE variable is not set!"
        return 1
    fi

    # Create parent directory if it doesn't exist
    mkdir -p "$(dirname "$ZPROFILE")"

    # Create local bin directories if they don't exist
    mkdir -p "$HOME/.local/bin"
    mkdir -p "$HOME/bin"

    # Ensure we start with a fresh ZPROFILE
    if [[ ! -f "$ZPROFILE" ]]; then
        touch "$ZPROFILE"
        log_info "Created new profile at $ZPROFILE"
    fi

    # Remove any existing PATH exports from .zprofile
    local temp_file
    temp_file=$(mktemp)
    grep -v "export PATH=" "$ZPROFILE" > "$temp_file" || true
    mv "$temp_file" "$ZPROFILE"

    # Add PATH configuration at the BEGINNING of .zprofile
    {
        echo "# Path configuration"
        echo "# Added by bootstrap script"
        echo "if [[ \"\$PATH\" != *\"\$HOME/.local/bin\"* ]]; then"
        echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
        echo "fi"
        echo "if [[ \"\$PATH\" != *\"\$HOME/bin\"* ]]; then"
        echo "    export PATH=\"\$HOME/bin:\$PATH\""
        echo "fi"
        echo "if [[ \"\$PATH\" != *\"\$HOME/.cargo/bin\"* ]]; then"
        echo "    export PATH=\"\$HOME/.cargo/bin:\$PATH\""
        echo "fi"
        echo ""
        cat "$ZPROFILE"
    } > "${ZPROFILE}.tmp"
    mv "${ZPROFILE}.tmp" "$ZPROFILE"

    log_info "✅ Updated PATH configuration in $ZPROFILE"

    # Export PATH for current session
    export PATH="$HOME/.local/bin:$HOME/bin:$HOME/.cargo/bin:$PATH"
    
    # Verify PATH updates
    log_info "Current PATH: $PATH"
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
# Manual Package Installation
# ---------------------------

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

install_kind() {
    log_info "🔄 Installing Kind..."
    if command -v go &> /dev/null; then
        # Use a temporary directory
        local temp_dir
        temp_dir=$(mktemp -d)
        pushd "$temp_dir" > /dev/null

        if go install sigs.k8s.io/kind@latest; then
            # Add KIND to PATH
            sudo ln -sf "$(go env GOPATH)/bin/kind" /usr/local/bin/kind
            log_info "✅ Kind installed successfully!"
        else
            log_warning "⚠️ Failed to install Kind."
        fi

        popd > /dev/null
        rm -rf "$temp_dir"
    else
        log_error "❌ Go is required for Kind installation. Please install Go first."
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

    local temp_dir
    temp_dir=$(mktemp -d)
    pushd "$temp_dir" > /dev/null

    if curl -sSL "$url" -o "awscliv2.zip"; then
        unzip awscliv2.zip
        if sudo ./aws/install; then
            log_info "✅ AWS CLI installed successfully!"
        else
            log_warning "⚠️ Failed to install AWS CLI."
        fi
    else
        log_warning "⚠️ Failed to download AWS CLI."
    fi

    popd > /dev/null
    rm -rf "$temp_dir"
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

install_oh_my_posh() {
    if [ "$IS_TTY_SESSION" = true ]; then
        log_info "TTY session detected. Skipping Oh My Posh installation."
        return
    fi

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
            echo "export PATH=\"$install_dir:\$PATH\"" >> "$ZPROFILE"
            log_info "🔧 Updated PATH to include $install_dir"
        fi
    else
        log_warning "⚠️ Failed to install Oh My Posh."
    fi
}

install_atuin() {
    if [ "$IS_TTY_SESSION" = true ]; then
        log_info "TTY session detected. Skipping Atuin installation."
        return
    fi

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

    local temp_dir
    temp_dir=$(mktemp -d)
    pushd "$temp_dir" > /dev/null

    if git clone https://github.com/atuinsh/atuin.git && \
       cd atuin/crates/atuin && \
       cargo install --path .; then
        log_info "✅ Atuin installed successfully!"
    else
        log_warning "⚠️ Failed to install Atuin."
    fi

    popd > /dev/null
    rm -rf "$temp_dir"
}

install_zsh_autosuggestions() {
    log_info "🔌 Installing zsh-autosuggestions plugin..."

    ZSH_PLUGIN_DIR="$DOTFILES_DIR/.zsh/.zshplugins"
    mkdir -p "$ZSH_PLUGIN_DIR"

    pushd "$ZSH_PLUGIN_DIR" > /dev/null
    if [[ ! -d "zsh-autosuggestions" ]]; then
        if git clone https://github.com/zsh-users/zsh-autosuggestions.git; then
            log_info "✅ zsh-autosuggestions plugin installed successfully!"
        else
            log_warning "⚠️ Failed to clone zsh-autosuggestions plugin."
        fi
    else
        log_info "✅ zsh-autosuggestions plugin is already installed."
    fi
    popd > /dev/null
}

install_zsh_syntax_highlighting() {
    log_info "🔌 Installing zsh-syntax-highlighting plugin..."

    ZSH_PLUGIN_DIR="$DOTFILES_DIR/.zsh/.zshplugins"
    mkdir -p "$ZSH_PLUGIN_DIR"

    pushd "$ZSH_PLUGIN_DIR" > /dev/null
    if [[ ! -d "zsh-syntax-highlighting" ]]; then
        if git clone https://github.com/zsh-users/zsh-syntax-highlighting.git; then
            log_info "✅ zsh-syntax-highlighting plugin installed successfully!"
        else
            log_warning "⚠️ Failed to clone zsh-syntax-highlighting plugin."
        fi
    else
        log_info "✅ zsh-syntax-highlighting plugin is already installed."
    fi
    popd > /dev/null
}

install_zsh_you_should_use() {
    log_info "🔌 Installing zsh-you-should-use plugin..."

    ZSH_PLUGIN_DIR="$DOTFILES_DIR/.zsh/.zshplugins"
    mkdir -p "$ZSH_PLUGIN_DIR"

    pushd "$ZSH_PLUGIN_DIR" > /dev/null
    if [[ ! -d "you-should-use" ]]; then
        if git clone https://github.com/MichaelAquilina/zsh-you-should-use.git; then
            log_info "✅ zsh-you-should-use plugin installed successfully!"
        else
            log_warning "⚠️ Failed to clone zsh-you-should-use plugin."
        fi
    else
        log_info "✅ zsh-you-should-use plugin is already installed."
    fi
}

# ---------------------------
# Install JetBrains Mono Nerd Font
# ---------------------------

install_jetbrains_mono_nerd_font() {
    if [ "$IS_TTY_SESSION" = true ]; then
        log_info "TTY session detected. Skipping Font installation."
        return
    fi

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

# ---------------------------
# Setup bat Symlink
# ---------------------------

setup_bat_symlink() {
    # First ensure PATH is properly set up
    update_path

    # Ensure .local/bin exists
    mkdir -p "$HOME/.local/bin"

    # Remove existing symlink if it exists
    if [[ -L "$HOME/.local/bin/bat" ]]; then
        rm "$HOME/.local/bin/bat"
        log_info "Removed existing bat symlink"
    fi

    # Create new symlink if batcat exists
    if command -v batcat &> /dev/null; then
        ln -sf "$(command -v batcat)" "$HOME/.local/bin/bat"
        
        # Verify symlink
        if [[ -L "$HOME/.local/bin/bat" ]]; then
            
            # Update current session PATH
            export PATH="$HOME/.local/bin:$PATH"
        else
            log_warning "⚠️ Failed to create bat symlink"
        fi
    else
        log_warning "⚠️ batcat not found. Please install bat package first"
    fi
}


# ---------------------------
# Install Wrapper
# ---------------------------

install_manual_packages() {
    log_info "🚀 Installing manual packages..."

    install_go
    install_docker
    install_kubectl
    install_kind
    install_helm
    install_awscli
    install_terraform
    install_fastfetch
    install_oh_my_posh
    install_atuin
    install_zsh_autosuggestions
    install_zsh_syntax_highlighting
    install_zsh_you_should_use
    # Install JetBrains Mono Nerd Font
    install_jetbrains_mono_nerd_font
    # Setup bat symlink
    setup_bat_symlink

    log_info "✅ All manual packages installed successfully!"
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
# Git Configuration
# ---------------------------

setup_git() {
    cd "$DOTFILES_DIR"
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
# Verify Environment Setup
# ---------------------------

verify_environment() {
    log_info "🔍 Verifying environment setup..."
    
    # Check ZPROFILE
    if [[ -n "$ZPROFILE" ]]; then
        if [[ -f "$ZPROFILE" ]]; then
            if grep -q "export PATH=" "$ZPROFILE"; then
                log_info "✅ PATH is configured in ZPROFILE"
            else
                log_warning "⚠️ No PATH configuration found in ZPROFILE"
            fi
        else
            log_warning "⚠️ ZPROFILE file does not exist"
        fi
    else
        log_error "❌ ZPROFILE variable is not set"
    fi
    
    # Check PATH
    log_info "Current PATH: $PATH"
}


# ---------------------------
# Set Terminal Font
# ---------------------------

set_terminal_font() {
    if [ "$IS_TTY_SESSION" = true ]; then
        log_info "TTY session detected. Skipping Font Setting."
        return
    fi

    log_info "🖥️ Setting JetBrains Mono Nerd Font as default terminal font..."

    # For GNOME Terminal
    if command -v gsettings &> /dev/null; then
        # Get the list of terminal profiles
        local profile_list
        profile_list=$(gsettings get org.gnome.Terminal.ProfilesList list | tr -d '[],' | tr "'" '\n' | grep '^:')
        
        # Get the default profile ID
        local default_profile
        default_profile=$(gsettings get org.gnome.Terminal.ProfilesList default | tr -d "'")
        
        if [ -n "$default_profile" ]; then
            gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$default_profile/" font 'JetBrainsMono Nerd Font 14'
            gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:$default_profile/" use-system-font false
            log_info "✅ Font set for GNOME Terminal"
        fi
    fi

    # For Konsole (KDE)
    local konsole_dir="$HOME/.local/share/konsole"
    if [ -d "$konsole_dir" ] || command -v konsole &> /dev/null; then
        mkdir -p "$konsole_dir"
        local profile_file="$konsole_dir/Default.profile"
        
        # Create or update Konsole profile
        cat > "$profile_file" << EOF
[Appearance]
Font=JetBrains Mono Nerd Font,14,-1,5,50,0,0,0,0,0
EOF
        log_info "✅ Font set for Konsole"
    fi

    # For Xfce4-terminal
    local xfce_config_dir="$HOME/.config/xfce4/terminal"
    if [ -d "$xfce_config_dir" ] || command -v xfce4-terminal &> /dev/null; then
        mkdir -p "$xfce_config_dir"
        local xfce_config_file="$xfce_config_dir/terminalrc"
        
        if [ -f "$xfce_config_file" ]; then
            # Update existing config
            sed -i '/FontName=/d' "$xfce_config_file"
            echo "FontName=JetBrains Mono Nerd Font 12" >> "$xfce_config_file"
        else
            # Create new config
            cat > "$xfce_config_file" << EOF
[Configuration]
FontName=JetBrains Mono Nerd Font 14
EOF
        fi
        log_info "✅ Font set for Xfce4-terminal"
    fi

    # For Tilix
    if command -v tilix &> /dev/null; then
        local tilix_schema="com.gexperts.Tilix.ProfilesList"
        local default_profile
        default_profile=$(gsettings get "$tilix_schema" default | tr -d "'")
        
        if [ -n "$default_profile" ]; then
            gsettings set "com.gexperts.Tilix.Profile:/com/gexperts/Tilix/profiles/$default_profile/" font 'JetBrains Mono Nerd Font 14'
            gsettings set "com.gexperts.Tilix.Profile:/com/gexperts/Tilix/profiles/$default_profile/" use-system-font false
            log_info "✅ Font set for Tilix"
        fi
    fi

    # For Alacritty
    local alacritty_config_dir="$HOME/.config/alacritty"
    if [ -d "$alacritty_config_dir" ] || command -v alacritty &> /dev/null; then
        mkdir -p "$alacritty_config_dir"
        local alacritty_config_file="$alacritty_config_dir/alacritty.yml"
        
        # Create or update Alacritty config
        if [ -f "$alacritty_config_file" ]; then
            # Backup existing config
            cp "$alacritty_config_file" "$alacritty_config_file.backup"
            
            # Update font configuration
            if grep -q "^font:" "$alacritty_config_file"; then
                sed -i '/^font:/,/^[^ ]/c\font:\n  normal:\n    family: JetBrainsMono Nerd Font\n    style: Regular\n  bold:\n    family: JetBrainsMono Nerd Font\n    style: Bold\n  italic:\n    family: JetBrainsMono Nerd Font\n    style: Italic\n  size: 14.0' "$alacritty_config_file"
            else
                cat >> "$alacritty_config_file" << EOF

font:
  normal:
    family: JetBrainsMono Nerd Font
    style: Regular
  bold:
    family: JetBrainsMono Nerd Font
    style: Bold
  italic:
    family: JetBrainsMono Nerd Font
    style: Italic
  size: 14.0
EOF
            fi
        else
            # Create new config
            cat > "$alacritty_config_file" << EOF
font:
  normal:
    family: JetBrainsMono Nerd Font
    style: Regular
  bold:
    family: JetBrainsMono Nerd Font
    style: Bold
  italic:
    family: JetBrainsMono Nerd Font
    style: Italic
  size: 14.0
EOF
        fi
        log_info "✅ Font set for Alacritty"
    fi

    log_info "✅ Terminal font configuration completed!"
    log_info "📝 Note: You may need to restart your terminal for changes to take effect"
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
    cd "$HOME"
    log_info "🚀 Starting machine bootstrap process..."

    # Perform initial system check
    check_os

    # Check if TTY session
    check_tty_session

    # Clock Sync
    sync_system_clock

    # Clear Cache
    clear_cache

    # Check if ZSH is installed
    check_zsh

    # Update system
    update_system

    # Set up PATH
    update_path

    # Install packages
    install_packages
    install_manual_packages

    # Gather user inputs
    get_user_inputs

    # Execute installation steps
    run_dotbot
    setup_git

    # Final environment verification
    verify_environment

    # Set terminal font
    set_terminal_font

    # Change default shell to ZSH at the end and trigger reboot
    change_shell
}

# Execute main function
main "$@"
