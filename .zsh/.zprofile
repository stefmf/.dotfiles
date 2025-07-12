eval "$(/opt/homebrew/bin/brew shellenv)"

#------------------------------------------------------------------------------
# SSH Agent Configuration
#------------------------------------------------------------------------------

SOCKET="$HOME/.ssh/sockets/ssh_auth_sock"
unset SSH_AUTH_SOCK

# Restart only if socket is stale or agent is dead
if [ -S "$SOCKET" ] && ssh-add -l >/dev/null 2>&1; then
  export SSH_AUTH_SOCK="$SOCKET"
else
  rm -f "$SOCKET"
  eval "$(ssh-agent -a "$SOCKET" 2>/dev/null)" >/dev/null
  export SSH_AUTH_SOCK="$SOCKET"
fi

# Load SSH keys only if not already loaded
for key in id_personal id_work; do
  KEY_PATH="$HOME/.ssh/$key"
  COMMENT=$(awk '{print $3}' "$KEY_PATH.pub")
  if [ -f "$KEY_PATH" ] && ! ssh-add -l 2>/dev/null | grep -q "$COMMENT"; then
    ssh-add "$KEY_PATH" >/dev/null 2>&1 && echo "🔐 Loaded $COMMENT"
  fi
done

