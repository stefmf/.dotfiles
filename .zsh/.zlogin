#------------------------------------------------------------------------------
# Login Shell Initialization
# Executed at start of login shell
#------------------------------------------------------------------------------

# Ensure fastfetch exists before trying to run it
if command -v fastfetch >/dev/null 2>&1; then
    fastfetch
else
    echo "Note: fastfetch not installed. Install it for system information display."
fi