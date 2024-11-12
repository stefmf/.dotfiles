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
ZSH_PROFILE="$DOTFILES_DIR/.zsh/.zprofile"

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
# System Update
# ---------------------------

update_system() {
    log_info "🔄 Updating system packages..."
    sudo apt update && sudo apt upgrade -y
    
    # Install common dependencies
    sudo apt install -y \
        apt-transport-https \
        ca-certificates \
        curl \
        gnupg \
        lsb-release \
        software-properties-common
        
    log_info "✅ System update complete!"
}

# ---------------------------
# Install Zsh
# ---------------------------

if ! command -v zsh &> /dev/null; then
    log_info "Installing Zsh..."
    sudo apt update && sudo apt install -y zsh
else
    log_info "✅ Zsh is already installed."
fi

# ---------------------------
# Change shell to zsh
# ---------------------------

if [[ "$SHELL" != "$(which zsh)" ]]; then
    log_info "Changing shell to zsh..."
    sudo chsh -s "$(which zsh)" "$USER"
    log_info "✅ SUCCESS! Shell set to zsh. Please log out and log back in for changes to take effect."
else
    log_info "✅ Default shell is already set to zsh."
fi

# ---------------------------
# APT Package Installation
# ---------------------------

install_packages() {
    if [[ ! -f "$PACKAGES_FILE" ]]; then
        log_error "🚫 Package list not found at $PACKAGES_FILE"
        exit 1
    fi

    log_info "📦 Updating package lists..."
    if ! sudo apt update; then
        log_error "Failed to update package lists"
        exit 1
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
        sudo apt install -y "$package" || log_warning "⚠️ Failed to install $package"
    done

    log_info "✅ Package installation complete!"
}

# ---------------------------
# Install Missing Packages
# ---------------------------

install_atuin() {
    log_info "🔄 Installing Atuin..."
    bash <(curl https://raw.githubusercontent.com/atuinsh/atuin/main/install.sh)
    log_info "✅ Atuin installed successfully!"
}

install_awscli() {
    log_info "☁️ Installing AWS CLI..."
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    sudo apt install -y unzip
    unzip awscliv2.zip
    sudo ./aws/install
    rm -rf aws awscliv2.zip
    log_info "✅ AWS CLI installed successfully!"
}

install_fastfetch() {
    log_info "📊 Installing Fastfetch..."
    # Add the repository for Fastfetch
    echo "deb [signed-by=/usr/share/keyrings/fastfetch-archive-keyring.gpg] https://repos.fastfetch.org/debian/ $(lsb_release -cs) main" | \
        sudo tee /etc/apt/sources.list.d/fastfetch.list
    curl -fsSL https://repos.fastfetch.org/key.asc | \
        sudo gpg --dearmor -o /usr/share/keyrings/fastfetch-archive-keyring.gpg
    sudo apt update
    sudo apt install -y fastfetch
    log_info "✅ Fastfetch installed successfully!"
}

install_kind() {
    log_info "🔄 Installing Kind..."
    # Install Kind using Go (ensure Go is installed first)
    if command -v go &> /dev/null; then
        go install sigs.k8s.io/kind@latest
        # Add KIND to PATH by creating a symbolic link
        sudo ln -sf "$(go env GOPATH)/bin/kind" /usr/local/bin/kind
        log_info "✅ Kind installed successfully!"
    else
        log_error "❌ Go is required for Kind installation. Please install Go first."
    fi
}

# ---------------------------
# Additional Package Installation
# ---------------------------

install_docker() {
    log_info "🐳 Installing Docker CE..."
    
    # Add Docker's official GPG key
    sudo apt-get update
    sudo apt-get install -y ca-certificates curl gnupg
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    # Add the repository to apt sources
    echo \
    "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Install Docker packages
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # Add user to docker group
    sudo usermod -aG docker "$USER"
    log_info "✅ Docker CE installed successfully!"
}

install_go() {
    log_info "🔧 Installing Go..."
    local GO_VERSION="1.22.0"  # Update this version as needed
    local ARCH="$(dpkg --print-architecture)"
    
    # Download and install Go
    wget "https://go.dev/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz"
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf "go${GO_VERSION}.linux-${ARCH}.tar.gz"
    rm "go${GO_VERSION}.linux-${ARCH}.tar.gz"

    # Add Go to PATH in profile
    echo 'export PATH=$PATH:/usr/local/go/bin' >> "$HOME/.profile"
    log_info "✅ Go installed successfully!"
}

install_helm() {
    log_info "⎈ Installing Helm..."
    curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
    sudo apt-get update
    sudo apt-get install -y helm
    log_info "✅ Helm installed successfully!"
}

install_kubectl() {
    log_info "☸️ Installing kubectl..."
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list
    sudo apt-get update
    sudo apt-get install -y kubectl
    log_info "✅ kubectl installed successfully!"
}

install_terraform() {
    log_info "🏗️ Installing Terraform..."
    wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
    sudo apt update
    sudo apt install -y terraform
    log_info "✅ Terraform installed successfully!"
}

install_oh_my_posh() {
    log_info "🥳 Installing Oh My Posh..."
    curl -s https://ohmyposh.dev/install.sh | bash -s
    log_info "✅ Oh My Posh installed successfully!"
}

install_additional_packages() {
    log_info "🚀 Installing additional packages..."
    
    # Core tools
    install_docker
    install_go
    install_helm
    install_kubectl
    install_terraform
    install_oh_my_posh
    
    # Previously missing packages
    install_atuin
    install_awscli
    install_fastfetch
    install_kind
    
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
    git config --global user.name "$GIT_USER_NAME" || log_warning "⚠️ Failed to set Git user name."
    git config --global user.email "$GIT_USER_EMAIL" || log_warning "⚠️ Failed to set Git user email."
    log_info "✅ Git configured for user: $GIT_USER_NAME <$GIT_USER_EMAIL>"
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
            rm -rf "$link" || log_warning "⚠️ Failed to remove $link"
        fi

        # Ensure parent directory exists
        local parent_dir="$(dirname "$link")"
        if [[ ! -d "$parent_dir" ]]; then
            log_info "📁 Creating parent directory: $parent_dir"
            mkdir -p "$parent_dir" || log_warning "⚠️ Failed to create directory: $parent_dir"
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
        "$DOTBOT_INSTALL" -v || log_warning "⚠️ Dotbot installation failed."
    else
        log_error "🚫 Dotbot install script not found at $DOTBOT_INSTALL"
    fi
}

# ---------------------------
# Main Installation Process
# ---------------------------

main() {
    log_info "🚀 Starting machine bootstrap process..."
    
    # Update system first
    update_system
    
    # Gather user inputs
    get_user_inputs
    
    # Install packages
    install_packages
    install_additional_packages
    
    # Execute installation steps
    run_dotbot
    setup_git

    # Source zshrc to apply changes
    if [[ -f "$ZSH_PROFILE" ]]; then
        log_info "🎉 Bootstrap complete! Applying changes..."
        source "$ZSH_PROFILE"
    else
        log_warning "⚠️ No .zshrc found after installation."
    fi
    
    log_info "🔄 Please log out and log back in for all changes to take effect."
}

# Perform initial system check
check_linux

# Execute main function
main "$@"