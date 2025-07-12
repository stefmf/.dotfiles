eval "$(/opt/homebrew/bin/brew shellenv)"

#------------------------------------------------------------------------------
# SSH Agent Configuration
#------------------------------------------------------------------------------
# Clear any existing SSH_AUTH_SOCK to avoid conflicts
unset SSH_AUTH_SOCK  

# Ensure ssh-agent is running
SOCKET="$HOME/.ssh/sockets/ssh_auth_sock"
unset SSH_AUTH_SOCK

# Check if socket exists and agent is alive
if [ -S "$SOCKET" ] && ssh-add -l >/dev/null 2>&1; then
  export SSH_AUTH_SOCK="$SOCKET"
else
  echo "🔁 Restarting ssh-agent..."
  rm -f "$SOCKET"
  eval "$(ssh-agent -a "$SOCKET")"
  export SSH_AUTH_SOCK="$SOCKET"
fi

# Load keys if not already loaded
for key in id_personal id_work; do
  KEY_PATH="$HOME/.ssh/$key"
  if [ -f "$KEY_PATH" ] && ! ssh-add -l 2>/dev/null | grep -q "$key"; then
    ssh-add "$KEY_PATH" && echo "🔐 Loaded $key"
  fi
done
