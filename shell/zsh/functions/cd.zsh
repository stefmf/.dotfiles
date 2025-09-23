#!/bin/zsh
#==============================================================================
# Smart CD Wrapper Function
#==============================================================================
# A smart cd wrapper that:
# 1. Tries normal cd relative to $PWD
# 2. If that fails, searches forward through subdirectories to find target
# 3. If still no match, shows normal error
#
# Only activates in interactive shells to avoid affecting scripts.
# Preserves tab completion and autosuggestions.
#==============================================================================

# Only define the wrapper in interactive shells
if [[ -o interactive ]]; then
    
    function cd() {
        # Handle special cases - pass directly to builtin cd
        case "${1:-}" in
            # No arguments - go to $HOME
            "")
                builtin cd
                return $?
                ;;
            # Special directories - pass through (removed "-")
            "--"|"."|"..")
                builtin cd "$@"
                return $?
                ;;
        esac
        
        # Multiple arguments - pass through to builtin
        if [[ $# -gt 1 ]]; then
            builtin cd "$@"
            return $?
        fi
        
        # Single argument - try smart resolution
        local target="$1"
        
        # First attempt: normal cd behavior
        if builtin cd "$target" 2>/dev/null; then
            return 0
        fi
        
        # Smart resolution only for simple directory names (no paths)
        # Skip if target contains slashes (already a path)
        if [[ "$target" == */* ]]; then
            # For paths, just show clean error message
            echo "cd: no such file or directory: $target" >&2
            return 1
        fi
        
        # Second attempt: search forward through subdirectories
        # Use find to search for directories with the target name
        # Limit search depth to avoid performance issues
        local found_dir
        found_dir=$(find "$PWD" -maxdepth 3 -type d -name "$target" -print -quit 2>/dev/null)
        
        if [[ -n "$found_dir" && -d "$found_dir" ]]; then
            builtin cd "$found_dir"
            return $?
        fi
        
        # All attempts failed - show clean error message
        echo "cd: no such file or directory: $target" >&2
        return 1
    }
    
fi

# Bash compatibility version
if [[ -n "$BASH_VERSION" ]] && [[ $- == *i* ]]; then
    
    function cd() {
        # Handle special cases - pass directly to builtin cd
        case "${1:-}" in
            # No arguments - go to $HOME
            "")
                builtin cd
                return $?
                ;;
            # Special directories - pass through (removed "-")
            "--"|"."|"..")
                builtin cd "$@"
                return $?
                ;;
        esac
        
        # Multiple arguments - pass through to builtin
        if [[ $# -gt 1 ]]; then
            builtin cd "$@"
            return $?
        fi
        
        # Single argument - try smart resolution
        local target="$1"
        
        # First attempt: normal cd behavior
        if builtin cd "$target" 2>/dev/null; then
            return 0
        fi
        
        # Smart resolution only for simple directory names (no paths)
        # Skip if target contains slashes (already a path)
        if [[ "$target" == */* ]]; then
            # For paths, just show clean error message
            echo "cd: no such file or directory: $target" >&2
            return 1
        fi
        
        # Second attempt: search forward through subdirectories
        # Use find to search for directories with the target name
        # Limit search depth to avoid performance issues
        local found_dir
        found_dir=$(find "$PWD" -maxdepth 3 -type d -name "$target" -print -quit 2>/dev/null)
        
        if [[ -n "$found_dir" && -d "$found_dir" ]]; then
            builtin cd "$found_dir"
            return $?
        fi
        
        # All attempts failed - show clean error message
        echo "cd: no such file or directory: $target" >&2
        return 1
    }
    
fi