eval "$(/opt/homebrew/bin/brew shellenv)"

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