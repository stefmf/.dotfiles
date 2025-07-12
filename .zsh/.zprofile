eval "$(/opt/homebrew/bin/brew shellenv)"

#------------------------------------------------------------------------------
# SSH Agent Configuration
#------------------------------------------------------------------------------

mkdir -p "$HOME/.ssh/sockets"
SOCKET="$HOME/.ssh/sockets/ssh_auth_sock"
unset SSH_AUTH_SOCK

# Start agent only if socket is valid and agent is alive
if [ -S "$SOCKET" ] && SSH_AUTH_SOCK="$SOCKET" ssh-add -l >/dev/null 2>&1; then
  export SSH_AUTH_SOCK="$SOCKET"
else
  rm -f "$SOCKET"
  eval "$(ssh-agent -a "$SOCKET" 2>/dev/null)" >/dev/null
  export SSH_AUTH_SOCK="$SOCKET"
fi

# Load SSH keys if not already loaded (1-hour lifetime)
for key in id_personal id_work; do
  KEY_PATH="$HOME/.ssh/$key"
  PUB_PATH="$KEY_PATH.pub"

  if [ -f "$KEY_PATH" ]; then
    if [ -f "$PUB_PATH" ]; then
      FINGERPRINT=$(ssh-keygen -lf "$PUB_PATH" | awk '{print $2}')
      if ! ssh-add -l 2>/dev/null | grep -q "$FINGERPRINT"; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
          ssh-add -t 1h --apple-use-keychain "$KEY_PATH" >/dev/null 2>&1 && echo "🔐 Loaded $key (macOS, 1h)"
        else
          ssh-add -t 1h "$KEY_PATH" >/dev/null 2>&1 && echo "🔐 Loaded $key (1h)"
        fi
      fi
    else
      echo "⚠️  Missing public key: $PUB_PATH"
    fi
  fi
done
