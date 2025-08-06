#------------------------------------------------------------------------------
# Homebrew environment
#------------------------------------------------------------------------------
eval "$(/opt/homebrew/bin/brew shellenv)"

#------------------------------------------------------------------------------
# SSH Agent Configuration
#------------------------------------------------------------------------------

# Socket path for SSH agent
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

#------------------------------------------------------------------------------
# Machine-aware SSH key loading
#------------------------------------------------------------------------------

HOST_ID=$(hostname -s)

# Always load personal key
SSH_KEYS=(id_personal)

# Load work key only on your work machine
if [[ "$HOST_ID" == "Mac-WD77LWRW" ]]; then
  SSH_KEYS+=(id_work)
fi

# Load keys if not already loaded (1-hour lifetime)
for key in "${SSH_KEYS[@]}"; do
  KEY_PATH="$HOME/.ssh/$key"
  PUB_PATH="$KEY_PATH.pub"

  # Skip if private key is missing
  [[ -f "$KEY_PATH" ]] || continue

  # Load if not already in agent
  if [[ -f "$PUB_PATH" ]]; then
    FINGERPRINT=$(ssh-keygen -lf "$PUB_PATH" | awk '{print $2}')
    if ! ssh-add -l 2>/dev/null | grep -q "$FINGERPRINT"; then
      if [[ "$OSTYPE" == "darwin"* ]]; then
        ssh-add -t 1h --apple-use-keychain "$KEY_PATH" >/dev/null 2>&1 \
          && echo "🔐 Loaded $key (macOS, 1h)"
      else
        ssh-add -t 1h "$KEY_PATH" >/dev/null 2>&1 \
          && echo "🔐 Loaded $key (1h)"
      fi
    fi
  else
    # Only warn about missing pub on the machine that should have it
    if [[ "$HOST_ID" == "Mac-WD77LWRW" ]]; then
      echo "⚠️  Missing public key: $PUB_PATH"
    fi
  fi
done
