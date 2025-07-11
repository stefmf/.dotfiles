#!/usr/bin/env bash

#==============================================================================
# Shell Tools Cleanup Script
#==============================================================================
# Uninstalls neovim, atuin, and zoxide via Homebrew and cleans up 
# persistent shell artifacts (functions, aliases, key bindings, cache)
#
# Usage: ./cleanup.sh
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
    
    # Common FPATH directories where Homebrew installs completions
    local fpath_dirs=(
        "/opt/homebrew/share/zsh/site-functions"
        "/usr/local/share/zsh/site-functions" 
        "/opt/homebrew/Cellar/zsh/*/share/zsh/functions"
    )
    
    # Add current FPATH directories
    if [[ -n "${FPATH:-}" ]]; then
        while IFS=':' read -ra PATHS; do
            for path in "${PATHS[@]}"; do
                if [[ -d "$path" && "$path" == *"homebrew"* ]]; then
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
    
    # Check aliases
    if alias vim 2>/dev/null | grep -q nvim; then
        log_warning "vim still aliased to nvim"
    else
        log_success "vim alias cleaned up"
    fi
    
    # Check for completion files
    local found_completion=false
    for dir in /opt/homebrew/share/zsh/site-functions /usr/local/share/zsh/site-functions; do
        if [[ -d "$dir" ]]; then
            if find "$dir" -name "*atuin*" -o -name "*zoxide*" | grep -q .; then
                log_warning "Found completion files in $dir"
                found_completion=true
            fi
        fi
    done
    
    if ! $found_completion; then
        log_success "No stray completion files found"
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
    
    # Clean up all possible completion directories
    log_info "Deep cleaning completion directories..."
    local deep_dirs=(
        "/opt/homebrew/share/zsh/site-functions"
        "/usr/local/share/zsh/site-functions"
        "/opt/homebrew/share/zsh-completions"
        "$HOME/.zsh/completions"
        "$HOME/.oh-my-zsh/completions"
    )
    
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