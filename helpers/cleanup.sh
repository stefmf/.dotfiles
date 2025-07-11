#!/usr/bin/env bash

#==============================================================================
# Shell Tools Cleanup Script
#==============================================================================
# Uninstalls neovim, atuin, and zoxide via Homebrew and cleans up 
# persistent shell artifacts (functions, aliases, key bindings, cache)
#
# Usage: ./cleanup_shell_tools.sh
#==============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
log_success() { echo -e "${GREEN}✅ $1${NC}"; }
log_warning() { echo -e "${YELLOW}⚠️  $1${NC}"; }
log_error() { echo -e "${RED}❌ $1${NC}"; }

#------------------------------------------------------------------------------
# Main Cleanup Function
#------------------------------------------------------------------------------

main() {
    log_info "Starting shell tools cleanup..."
    
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
    
    # Uninstall via Homebrew
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
    echo "  1. Sync your dotfiles to remove config references"
    echo "  2. Run 'exec zsh' or restart your terminal"
    echo "  3. Verify with 'which vim' and 'which cd'"
}

#------------------------------------------------------------------------------
# Package Uninstallation
#------------------------------------------------------------------------------

uninstall_packages() {
    log_info "Uninstalling packages via Homebrew..."
    
    local packages=("neovim" "atuin" "zoxide")
    
    for package in "${packages[@]}"; do
        if brew list "$package" &>/dev/null; then
            log_info "Uninstalling $package..."
            brew uninstall "$package" || log_warning "Failed to uninstall $package"
            log_success "Uninstalled $package"
        else
            log_warning "$package not found or already uninstalled"
        fi
    done
}

#------------------------------------------------------------------------------
# Zoxide Cleanup
#------------------------------------------------------------------------------

cleanup_zoxide() {
    log_info "Cleaning up zoxide artifacts..."
    
    # Unset zoxide functions
    local zoxide_functions=("__zoxide_hook" "_zoxide" "__zoxide_z" "__zoxide_zi")
    
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
    
    log_success "Zoxide cleanup complete"
}

#------------------------------------------------------------------------------
# Atuin Cleanup  
#------------------------------------------------------------------------------

cleanup_atuin() {
    log_info "Cleaning up atuin artifacts..."
    
    # Unset atuin functions
    local atuin_functions=(
        "_atuin_preexec" 
        "_atuin_search" 
        "_atuin_history_search"
        "__atuin_history"
        "_atuin_bind_ctrl_r"
        "_atuin_bind_up_arrow"
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
    )
    
    for var in "${atuin_vars[@]}"; do
        if [[ -n "${!var:-}" ]]; then
            log_info "Unsetting variable: $var"
            unset "$var" 2>/dev/null || true
        fi
    done
    
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
# Completion Cache Cleanup
#------------------------------------------------------------------------------

cleanup_completion_cache() {
    log_info "Clearing zsh completion cache..."
    
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
    
    log_success "Completion cache cleared"
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
        if brew list "$package" &>/dev/null; then
            log_warning "$package still installed"
        else
            log_success "$package successfully removed"
        fi
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
}

#------------------------------------------------------------------------------
# Script Execution
#------------------------------------------------------------------------------

# Check if running with source/exec
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    log_error "This script should not be sourced. Run it directly: ./cleanup_shell_tools.sh"
    return 1
fi

# Run main function
main "$@"

# Optional verification
if [[ "${1:-}" == "--verify" ]]; then
    verify_cleanup
fi

log_info "Run 'exec zsh' to start a fresh shell session"