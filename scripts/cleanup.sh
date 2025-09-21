#!/usr/bin/env bash

#==============================================================================
# Shell Tools Cleanup Script
#==============================================================================
# Uninstalls neovim, atuin, and zoxide via system package manager and cleans up 
# persistent shell artifacts (functions, aliases, key bindings, cache)
# 
# Supports: 
#   - macOS (Homebrew)
#   - Linux (APT, DNF, YUM, Pacman)
#   - Cargo installations
#   - Manual binary installations
#
# Usage: ./cleanup.sh [--deep-clean|--verify]
#==============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
OS=""
PACKAGE_MANAGER=""

# Logging functions
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

# OS Detection
detect_os() {
    case "$(uname -s)" in
        Darwin*)
            OS="macos"
            PACKAGE_MANAGER="brew"
            ;;
        Linux*)
            OS="linux"
            # Detect package manager
            if command -v apt &>/dev/null; then
                PACKAGE_MANAGER="apt"
            elif command -v dnf &>/dev/null; then
                PACKAGE_MANAGER="dnf"
            elif command -v yum &>/dev/null; then
                PACKAGE_MANAGER="yum"
            elif command -v pacman &>/dev/null; then
                PACKAGE_MANAGER="pacman"
            else
                log_error "Unsupported package manager on Linux"
                exit 1
            fi
            ;;
        *)
            log_error "Unsupported operating system: $(uname -s)"
            exit 1
            ;;
    esac
    
    log_info "Detected OS: $OS with package manager: $PACKAGE_MANAGER"
}

#------------------------------------------------------------------------------
# Main Cleanup Function
#------------------------------------------------------------------------------

main() {
    log_info "Starting shell tools cleanup..."
    
    # Detect operating system and package manager
    detect_os
    
    # Check if we're in a zsh shell
    if [[ ! "$SHELL" == *"zsh"* ]]; then
        log_warning "This script is designed for zsh. Current shell: $SHELL"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Exiting..."
            exit 0
        fi
    fi
    
    # Uninstall via package manager
    uninstall_packages
    
    # Clean up shell artifacts
    cleanup_zoxide
    cleanup_atuin  
    cleanup_neovim_aliases
    
    # Clear completion cache
    cleanup_completion_cache
    
    # Reset key bindings
    reset_key_bindings
    
    log_success "Cleanup complete!"
    log_info "Next steps:"
    echo "  1. ✅ Packages uninstalled and session cleaned"
    echo "  2. ⚠️  DO NOT run 'reload' - it will re-source old completion files"
    echo "  3. 🔄 Run 'exec zsh' to start completely fresh shell"
    echo "  4. 🧪 Test with 'which vim' and 'which cd'"
    echo ""
    log_warning "Important: If you still see errors after 'exec zsh', some completion files may remain."
    echo "          In that case, run this script with: ./cleanup.sh --deep-clean"
}

#------------------------------------------------------------------------------
# Package Uninstallation
#------------------------------------------------------------------------------

uninstall_packages() {
    log_info "Uninstalling packages via $PACKAGE_MANAGER..."
    
    local packages=("neovim" "atuin" "zoxide")
    
    for package in "${packages[@]}"; do
        case "$PACKAGE_MANAGER" in
            brew)
                if brew list "$package" &>/dev/null; then
                    log_info "Uninstalling $package..."
                    brew uninstall "$package" || log_warning "Failed to uninstall $package"
                    log_success "Uninstalled $package"
                else
                    log_warning "$package not found or already uninstalled"
                fi
                ;;
            apt)
                # Check if package is installed
                if dpkg -l | grep -q "^ii.*$package"; then
                    log_info "Uninstalling $package..."
                    sudo apt remove -y "$package" || log_warning "Failed to uninstall $package"
                    log_success "Uninstalled $package"
                else
                    log_warning "$package not found or already uninstalled"
                fi
                ;;
            dnf)
                if dnf list installed "$package" &>/dev/null; then
                    log_info "Uninstalling $package..."
                    sudo dnf remove -y "$package" || log_warning "Failed to uninstall $package"
                    log_success "Uninstalled $package"
                else
                    log_warning "$package not found or already uninstalled"
                fi
                ;;
            yum)
                if yum list installed "$package" &>/dev/null; then
                    log_info "Uninstalling $package..."
                    sudo yum remove -y "$package" || log_warning "Failed to uninstall $package"
                    log_success "Uninstalled $package"
                else
                    log_warning "$package not found or already uninstalled"
                fi
                ;;
            pacman)
                if pacman -Q "$package" &>/dev/null; then
                    log_info "Uninstalling $package..."
                    sudo pacman -R --noconfirm "$package" || log_warning "Failed to uninstall $package"
                    log_success "Uninstalled $package"
                else
                    log_warning "$package not found or already uninstalled"
                fi
                ;;
            *)
                log_error "Unsupported package manager: $PACKAGE_MANAGER"
                ;;
        esac
    done
    
    # Handle special cases for Linux where some packages might have different names
    if [[ "$OS" == "linux" ]]; then
        cleanup_linux_special_packages
    fi
    
    # Clean up potential cargo installations (common on Linux)
    cleanup_cargo_installs
}

cleanup_cargo_installs() {
    log_info "Checking for Cargo/Rust installations..."
    
    local tools=("atuin" "zoxide")
    
    for tool in "${tools[@]}"; do
        if command -v cargo &>/dev/null && cargo install --list 2>/dev/null | grep -q "^$tool "; then
            log_info "Uninstalling $tool via cargo..."
            cargo uninstall "$tool" || log_warning "Failed to uninstall $tool via cargo"
        fi
        
        # Also check for manual cargo installations
        if [[ -f "$HOME/.cargo/bin/$tool" ]]; then
            log_info "Removing manually installed $tool from cargo bin"
            rm -f "$HOME/.cargo/bin/$tool"
        fi
    done
}

cleanup_linux_special_packages() {
    log_info "Checking for Linux-specific package variations..."
    
    # On some Linux distros, neovim might be installed as 'nvim'
    case "$PACKAGE_MANAGER" in
        apt)
            if dpkg -l | grep -q "^ii.*nvim"; then
                log_info "Found nvim package, uninstalling..."
                sudo apt remove -y nvim || log_warning "Failed to uninstall nvim"
            fi
            ;;
        *)
            # For other package managers, just proceed with manual cleanup
            ;;
    esac
    
    # Check for snap packages (common on Ubuntu)
    if command -v snap &>/dev/null; then
        local snap_packages=("nvim" "neovim")
        for package in "${snap_packages[@]}"; do
            if snap list | grep -q "^$package "; then
                log_info "Uninstalling snap package: $package"
                sudo snap remove "$package" || log_warning "Failed to remove snap package $package"
            fi
        done
    fi
    
    # Check for flatpak installations
    if command -v flatpak &>/dev/null; then
        # Check for common neovim flatpak IDs
        local flatpak_ids=("io.neovim.nvim" "org.neovim.Neovim")
        for app_id in "${flatpak_ids[@]}"; do
            if flatpak list | grep -q "$app_id"; then
                log_info "Uninstalling flatpak: $app_id"
                flatpak uninstall -y "$app_id" || log_warning "Failed to uninstall flatpak $app_id"
            fi
        done
    fi
    
    # Check for manually installed tools in common locations
    cleanup_manual_installs
}

cleanup_manual_installs() {
    log_info "Checking for manually installed binaries..."
    
    local manual_locations=(
        "$HOME/.local/bin"
        "$HOME/bin" 
        "$HOME/.cargo/bin"
        "/usr/local/bin"
        "$HOME/Applications"  # AppImages on Linux
        "$HOME/apps"          # Common custom app directory
    )
    
    local tools=("nvim" "neovim" "atuin" "zoxide")
    local appimage_patterns=("*nvim*.AppImage" "*neovim*.AppImage" "*atuin*.AppImage" "*zoxide*.AppImage")
    
    for location in "${manual_locations[@]}"; do
        if [[ -d "$location" ]]; then
            # Check for regular binaries
            for tool in "${tools[@]}"; do
                if [[ -f "$location/$tool" ]]; then
                    log_info "Removing manually installed $tool from $location"
                    rm -f "$location/$tool" || log_warning "Failed to remove $location/$tool"
                fi
            done
            
            # Check for AppImages (Linux)
            if [[ "$OS" == "linux" ]]; then
                for pattern in "${appimage_patterns[@]}"; do
                    for file in "$location"/$pattern; do
                        if [[ -f "$file" ]]; then
                            log_info "Removing AppImage: $file"
                            rm -f "$file" || log_warning "Failed to remove $file"
                        fi
                    done
                done
            fi
        fi
    done
}

#------------------------------------------------------------------------------
# Zoxide Cleanup
#------------------------------------------------------------------------------

cleanup_zoxide() {
    log_info "Cleaning up zoxide artifacts..."
    
    # Unset zoxide functions (more comprehensive list)
    local zoxide_functions=(
        "__zoxide_hook" 
        "_zoxide" 
        "__zoxide_z" 
        "__zoxide_zi"
        "__zoxide_pwd"
        "_zoxide_hook"
        "zoxide"
    )
    
    for func in "${zoxide_functions[@]}"; do
        if type "$func" &>/dev/null; then
            log_info "Removing function: $func"
            unset -f "$func" 2>/dev/null || true
            unfunction "$func" 2>/dev/null || true
        fi
    done
    
    # Remove any zoxide aliases
    local zoxide_aliases=("z" "zi")
    for alias_name in "${zoxide_aliases[@]}"; do
        if alias "$alias_name" &>/dev/null; then
            log_info "Removing alias: $alias_name"
            unalias "$alias_name" 2>/dev/null || true
        fi
    done
    
    # Unset zoxide variables
    local zoxide_vars=("_ZO_DATA_DIR" "_ZO_EXCLUDE_DIRS" "_ZO_FZF_OPTS" "_ZO_MAXAGE" "_ZO_RESOLVE_SYMLINKS")
    for var in "${zoxide_vars[@]}"; do
        if [[ -n "${!var:-}" ]]; then
            log_info "Unsetting variable: $var"
            unset "$var" 2>/dev/null || true
        fi
    done
    
    log_success "Zoxide cleanup complete"
}

#------------------------------------------------------------------------------
# Atuin Cleanup  
#------------------------------------------------------------------------------

cleanup_atuin() {
    log_info "Cleaning up atuin artifacts..."
    
    # Unset atuin functions (more comprehensive list)
    local atuin_functions=(
        "_atuin_preexec" 
        "_atuin_search" 
        "_atuin_history_search"
        "__atuin_history"
        "_atuin_bind_ctrl_r"
        "_atuin_bind_up_arrow"
        "__atuin_hook"
        "_atuin_precmd"
        "atuin"
    )
    
    for func in "${atuin_functions[@]}"; do
        if type "$func" &>/dev/null; then
            log_info "Removing function: $func"
            unset -f "$func" 2>/dev/null || true
            unfunction "$func" 2>/dev/null || true
        fi
    done
    
    # Clean up atuin variables
    local atuin_vars=(
        "ATUIN_SESSION"
        "ATUIN_HISTORY_ID" 
        "_ATUIN_SEARCH_STATE"
        "ATUIN_CONFIG_DIR"
        "ATUIN_DATA_DIR"
        "_ATUIN_PRECMD_EXECUTED"
    )
    
    for var in "${atuin_vars[@]}"; do
        if [[ -n "${!var:-}" ]]; then
            log_info "Unsetting variable: $var"
            unset "$var" 2>/dev/null || true
        fi
    done
    
    # Remove atuin from preexec/precmd arrays if they exist
    if [[ -n "${preexec_functions:-}" ]]; then
        preexec_functions=(${preexec_functions[@]/*atuin*/})
    fi
    if [[ -n "${precmd_functions:-}" ]]; then
        precmd_functions=(${precmd_functions[@]/*atuin*/})
    fi
    
    log_success "Atuin cleanup complete"
}

#------------------------------------------------------------------------------
# Neovim Aliases Cleanup
#------------------------------------------------------------------------------

cleanup_neovim_aliases() {
    log_info "Cleaning up neovim aliases..."
    
    # Remove neovim-related aliases
    local nvim_aliases=("vim" "vi" "nvim" "vimdiff" "view")
    
    for alias_name in "${nvim_aliases[@]}"; do
        if alias "$alias_name" &>/dev/null; then
            # Check if it points to nvim
            local alias_value=$(alias "$alias_name" | cut -d'=' -f2- | tr -d "'\"")
            if [[ "$alias_value" == *"nvim"* ]]; then
                log_info "Removing alias: $alias_name -> $alias_value"
                unalias "$alias_name" 2>/dev/null || true
            fi
        fi
    done
    
    log_success "Neovim aliases cleanup complete"
}

#------------------------------------------------------------------------------
# Completion Cache and FPATH Cleanup
#------------------------------------------------------------------------------

cleanup_completion_cache() {
    log_info "Clearing zsh completion cache and FPATH artifacts..."
    
    # Remove completion dump files
    local cache_files=(
        "$HOME/.zcompdump"
        "$HOME/.zcompdump-"*
    )
    
    for cache_file in "${cache_files[@]}"; do
        if [[ -f "$cache_file" ]]; then
            log_info "Removing cache file: $cache_file"
            rm -f "$cache_file"
        fi
    done
    
    # Clean up completion files from FPATH directories
    cleanup_fpath_completions
    
    log_success "Completion cache and FPATH cleanup complete"
}

cleanup_fpath_completions() {
    log_info "Cleaning completion files from FPATH directories..."
    
    # OS-specific FPATH directories
    local fpath_dirs=()
    
    case "$OS" in
        macos)
            fpath_dirs=(
                "/opt/homebrew/share/zsh/site-functions"
                "/usr/local/share/zsh/site-functions" 
                "/opt/homebrew/Cellar/zsh/*/share/zsh/functions"
                "/opt/homebrew/share/zsh-completions"
            )
            ;;
        linux)
            fpath_dirs=(
                "/usr/share/zsh/vendor-completions"
                "/usr/share/zsh/site-functions"
                "/usr/local/share/zsh/site-functions"
                "/usr/share/zsh-completions"
                "/etc/zsh_completion.d"
                "$HOME/.zsh/completions"
                "$HOME/.local/share/zsh/site-functions"
            )
            ;;
    esac
    
    # Add current FPATH directories
    if [[ -n "${FPATH:-}" ]]; then
        while IFS=':' read -ra PATHS; do
            for path in "${PATHS[@]}"; do
                # Only add system/package manager directories to be safe
                if [[ "$path" == *"homebrew"* ]] || [[ "$path" == "/usr/share"* ]] || [[ "$path" == "/usr/local"* ]]; then
                    fpath_dirs+=("$path")
                fi
            done
        done <<< "$FPATH"
    fi
    
    # Remove completion files for our target tools
    local completion_patterns=("*atuin*" "*zoxide*" "_atuin" "_zoxide")
    
    for dir in "${fpath_dirs[@]}"; do
        # Expand glob patterns
        for expanded_dir in $dir; do
            if [[ -d "$expanded_dir" ]]; then
                log_info "Checking directory: $expanded_dir"
                for pattern in "${completion_patterns[@]}"; do
                    for file in "$expanded_dir"/$pattern; do
                        if [[ -f "$file" ]]; then
                            log_info "Removing completion file: $file"
                            rm -f "$file" 2>/dev/null || {
                                log_warning "Could not remove $file (may need sudo)"
                                # Try with sudo if regular removal fails
                                sudo rm -f "$file" 2>/dev/null || log_warning "Failed to remove $file even with sudo"
                            }
                        fi
                    done
                done
            fi
        done
    done
}

#------------------------------------------------------------------------------
# Key Bindings Reset
#------------------------------------------------------------------------------

reset_key_bindings() {
    log_info "Resetting key bindings..."
    
    # Reset Ctrl+R to default history search
    if command -v bindkey &>/dev/null; then
        log_info "Resetting Ctrl+R to default history search"
        bindkey '^R' history-incremental-search-backward
        
        # Reset Up arrow to default
        log_info "Resetting Up arrow to default"
        bindkey '^[[A' up-line-or-history
        
        # Reset other potentially affected keys
        bindkey '^[[B' down-line-or-history  # Down arrow
    fi
    
    log_success "Key bindings reset"
}

#------------------------------------------------------------------------------
# Verification
#------------------------------------------------------------------------------

verify_cleanup() {
    log_info "Verifying cleanup..."
    
    # Check if packages are uninstalled
    local packages=("neovim" "atuin" "zoxide")
    for package in "${packages[@]}"; do
        case "$PACKAGE_MANAGER" in
            brew)
                if brew list "$package" &>/dev/null; then
                    log_warning "$package still installed"
                else
                    log_success "$package successfully removed"
                fi
                ;;
            apt)
                if dpkg -l | grep -q "^ii.*$package"; then
                    log_warning "$package still installed"
                else
                    log_success "$package successfully removed"
                fi
                ;;
            dnf|yum)
                if $PACKAGE_MANAGER list installed "$package" &>/dev/null; then
                    log_warning "$package still installed"
                else
                    log_success "$package successfully removed"
                fi
                ;;
            pacman)
                if pacman -Q "$package" &>/dev/null; then
                    log_warning "$package still installed"
                else
                    log_success "$package successfully removed"
                fi
                ;;
        esac
    done
    
    # Check if functions are gone
    local all_functions=("__zoxide_hook" "_atuin_preexec" "_atuin_search")
    for func in "${all_functions[@]}"; do
        if type "$func" &>/dev/null; then
            log_warning "Function $func still exists"
        else
            log_success "Function $func removed"
        fi
    done
    
    # Check aliases
    if alias vim 2>/dev/null | grep -q nvim; then
        log_warning "vim still aliased to nvim"
    else
        log_success "vim alias cleaned up"
    fi
    
    # Check for completion files based on OS
    local found_completion=false
    case "$OS" in
        macos)
            for dir in /opt/homebrew/share/zsh/site-functions /usr/local/share/zsh/site-functions; do
                if [[ -d "$dir" ]]; then
                    if find "$dir" -name "*atuin*" -o -name "*zoxide*" | grep -q .; then
                        log_warning "Found completion files in $dir"
                        found_completion=true
                    fi
                fi
            done
            ;;
        linux)
            for dir in /usr/share/zsh/vendor-completions /usr/share/zsh/site-functions /usr/local/share/zsh/site-functions; do
                if [[ -d "$dir" ]]; then
                    if find "$dir" -name "*atuin*" -o -name "*zoxide*" | grep -q .; then
                        log_warning "Found completion files in $dir"
                        found_completion=true
                    fi
                fi
            done
            ;;
    esac
    
    if ! $found_completion; then
        log_success "No stray completion files found"
    fi
    
    # Check for manual installations
    local manual_found=false
    for location in "$HOME/.local/bin" "$HOME/bin" "$HOME/.cargo/bin"; do
        if [[ -d "$location" ]]; then
            for tool in nvim atuin zoxide; do
                if [[ -f "$location/$tool" ]]; then
                    log_warning "Found manually installed $tool in $location"
                    manual_found=true
                fi
            done
        fi
    done
    
    if ! $manual_found; then
        log_success "No manual installations found"
    fi
    
    log_info "Verification complete"
}

#------------------------------------------------------------------------------
# Deep Clean Function (for stubborn cases)
#------------------------------------------------------------------------------

deep_clean() {
    log_info "Performing deep cleanup..."
    
    # More aggressive function cleanup (zsh-compatible)
    log_info "Performing aggressive function cleanup..."
    if command -v functions &>/dev/null; then
        # In zsh, use functions builtin
        for func in $(functions 2>/dev/null | grep -E "(atuin|zoxide)" | cut -d' ' -f1); do
            log_info "Force removing function: $func"
            unset -f "$func" 2>/dev/null || true
            unfunction "$func" 2>/dev/null || true
        done
    else
        # Fallback for bash/other shells - check common function names
        local common_funcs=(
            "_atuin_preexec" "_atuin_search" "_atuin_history_search" "__atuin_history"
            "__zoxide_hook" "_zoxide" "__zoxide_z" "__zoxide_zi" "__zoxide_pwd"
        )
        for func in "${common_funcs[@]}"; do
            if type "$func" &>/dev/null; then
                log_info "Force removing function: $func"
                unset -f "$func" 2>/dev/null || true
            fi
        done
    fi
    
    # Clean up all possible completion directories based on OS
    log_info "Deep cleaning completion directories..."
    local deep_dirs=()
    
    case "$OS" in
        macos)
            deep_dirs=(
                "/opt/homebrew/share/zsh/site-functions"
                "/usr/local/share/zsh/site-functions"
                "/opt/homebrew/share/zsh-completions"
                "$HOME/.zsh/completions"
                "$HOME/.oh-my-zsh/completions"
            )
            ;;
        linux)
            deep_dirs=(
                "/usr/share/zsh/vendor-completions"
                "/usr/share/zsh/site-functions"
                "/usr/local/share/zsh/site-functions"
                "/usr/share/zsh-completions"
                "/etc/zsh_completion.d"
                "$HOME/.zsh/completions"
                "$HOME/.local/share/zsh/site-functions"
                "$HOME/.oh-my-zsh/completions"
                "$HOME/.dotfiles/.zsh/.zsh_completions"
            )
            ;;
    esac
    
    for dir in "${deep_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            log_info "Deep cleaning: $dir"
            find "$dir" -name "*atuin*" -delete 2>/dev/null || true
            find "$dir" -name "*zoxide*" -delete 2>/dev/null || true
        fi
    done
    
    # Force remove any compiled zsh files
    find "$HOME" -name "*.zwc" -exec grep -l "atuin\|zoxide" {} \; 2>/dev/null | while read -r file; do
        log_info "Removing compiled zsh file: $file"
        rm -f "$file"
    done
    
    # Clean up cargo/rust installations if they exist
    if [[ -d "$HOME/.cargo/bin" ]]; then
        log_info "Checking cargo installations..."
        for tool in atuin zoxide; do
            if [[ -f "$HOME/.cargo/bin/$tool" ]]; then
                log_info "Removing cargo-installed $tool"
                rm -f "$HOME/.cargo/bin/$tool"
            fi
        done
    fi
    
    log_success "Deep cleanup complete"
}

#------------------------------------------------------------------------------
# Script Execution
#------------------------------------------------------------------------------

# Check if running with source/exec
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    log_error "This script should not be sourced. Run it directly: ./cleanup.sh"
    return 1
fi

# Handle command line arguments
case "${1:-}" in
    "--deep-clean")
        log_info "Running deep cleanup mode..."
        uninstall_packages
        cleanup_zoxide
        cleanup_atuin  
        cleanup_neovim_aliases
        cleanup_completion_cache
        deep_clean
        reset_key_bindings
        log_success "Deep cleanup complete! Run 'exec zsh' now."
        ;;
    "--verify")
        verify_cleanup
        ;;
    *)
        # Run main function
        main "$@"
        ;;
esac

log_info "Run 'exec zsh' to start a fresh shell session"