#!/bin/zsh

# Use XDG_CONFIG_HOME for config file location, fallback to ~/.config if not set
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

USERNAME=$(whoami)
if [[ "$USERNAME" == "root" || "$USERNAME" == "admin" ]]; then
    CONFIG_FILE="$XDG_CONFIG_HOME/fastfetch/fastfetch_admin.jsonc"
else
    CONFIG_FILE="$XDG_CONFIG_HOME/fastfetch/fastfetch.jsonc"
fi

# Call fastfetch directly with the appropriate config
fastfetch -c "$CONFIG_FILE"
