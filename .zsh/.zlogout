#------------------------------------------------------------------------------
# Logout Shell Cleanup
# Executed when logging out of a login shell
#------------------------------------------------------------------------------

# Clear the terminal screen
if [ -n "$CLEAR_ON_LOGOUT" ]; then
    c
fi

# Clean temporary files
if [ -d "$HOME/.cache/temp" ]; then
    rm -rf "$HOME/.cache/temp"/*
else
    mkdir -p "$HOME/.cache/temp"
fi

# Display logout message
echo "Logged out at $(date '+%Y-%m-%d %H:%M:%S')"
