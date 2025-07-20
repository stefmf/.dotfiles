#------------------------------------------------------------------------------
# Logout Shell Cleanup
# Executed when logging out of a login shell
#------------------------------------------------------------------------------

# Clear the terminal screen
if [ -n "$CLEAR_ON_LOGOUT" ]; then
  c
fi

# Clean temporary files — suppress error if no matches
if [ -d "$HOME/.cache/temp" ]; then
  rm -f "$HOME/.cache/temp/"*(.N) 2>/dev/null
else
  mkdir -p "$HOME/.cache/temp"
fi

# Optional: unload SSH keys (uncomment to enable)
# ssh-add -D >/dev/null 2>&1 && echo "🔓 SSH keys unloaded"

# Display logout message
# echo "Logged out at $(date '+%Y-%m-%d %H:%M:%S')"
