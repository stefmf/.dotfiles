#!/usr/bin/env zsh

# Smart ls function that adapts to terminal width and git status
# Only activates in interactive shells to avoid affecting scripts
if [[ -o interactive ]]; then
    
    function ls() {
        # Check terminal width (using COLUMNS variable that's exported in zshenv)
        local term_width=${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}
        
        # Determine which config to use based on terminal width
        local config_file
        if (( term_width < 70 )); then
            # Narrow terminal: use compact config (no git, no icons, minimal columns)
            config_file="$HOME/.dotfiles/config/lsd/config-compact.yaml"
        elif git rev-parse --is-inside-work-tree &>/dev/null; then
            # Wide terminal + git repo: use git config
            config_file="$HOME/.dotfiles/config/lsd/config.yaml"
        else
            # Wide terminal + no git: use no-git config
            config_file="$HOME/.dotfiles/config/lsd/config-nogit.yaml"
        fi
        
        # Run lsd with the appropriate config
        lsd --long --config-file "$config_file" "$@"
    }
    
fi