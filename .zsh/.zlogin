#------------------------------------------------------------------------------
# Login Shell Initialization
# Executed at start of login shell
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# SSH Agent Configuration
#------------------------------------------------------------------------------
# Clear any existing SSH_AUTH_SOCK to avoid conflicts
unset SSH_AUTH_SOCK  

# Ensure ssh-agent is running
SOCKET="$HOME/.ssh/sockets/ssh_auth_sock"

if [ ! -S "$SOCKET" ]; then
  eval "$(ssh-agent -a $SOCKET)"
fi

export SSH_AUTH_SOCK="$SOCKET"

# Add SSH key if not already added
for key in id_personal id_work; do
  KEY_PATH="$HOME/.ssh/$key"
  if [ -f "$KEY_PATH" ] && ! ssh-add -l | grep -q "$key"; then
    ssh-add "$KEY_PATH" && echo "🔐 Loaded $key"
  fi
done

# Ensure fastfetch exists before trying to run it
if command -v fastfetch >/dev/null 2>&1; then
    fastfetch
else
    echo "Note: fastfetch not installed. Install it for system information display."
fi