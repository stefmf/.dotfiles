#!/bin/zsh

# Function to count the number of non-break modules in the config file
count_modules() {
    local config_file="$1"
    local count=$(grep -v '"type": "break"' "$config_file" | grep -c '"type":')
    echo $((count - 1))  # Subtract 1 to remove the extra line
}

# Function to generate starry field
generate_starry_field() {
    local config_file="$1"
    TERM_WIDTH=$(tput cols)
    LOGO_WIDTH=$((TERM_WIDTH / 2))
    LOGO_HEIGHT=$(count_modules "$config_file")
    COLORS=(31 32 34 35 36 94 95 96)

generate_star() {
    local colors=(31 32 33 34 35 36 37 91 92 93 94 95 96 97)
    local color=${colors[$RANDOM % ${#colors[@]}]}
    local char
    case $((RANDOM % 9)) in
        0) char="*" ;;
        1) char="·" ;;
        2) char="+" ;;
        3) char="." ;;
        4) char="✦" ;;
        5) char="✴" ;;
        6) char="✳" ;;
        7) char="⋆" ;;
        8) char="°" ;;
    esac
    echo -ne "\033[${color}m${char}\033[0m"
}

    starry_field=""
    for ((y=0; y<LOGO_HEIGHT; y++)); do
        for ((x=0; x<LOGO_WIDTH; x++)); do
            if ((RANDOM % 10 == 0)); then
                starry_field+=$(generate_star)
            else
                starry_field+=" "
            fi
        done
        if ((y < LOGO_HEIGHT - 1)); then
            starry_field+="\n"
        fi
    done
    echo -ne "$starry_field"
}

# Determine the appropriate config file
# Get the directory of the script
SCRIPT_DIR=$(dirname "${(%):-%x}")
DOTFILES_DIR=$(dirname "$(dirname "$SCRIPT_DIR")")

USERNAME=$(whoami)
if [[ "$USERNAME" == "root" || "$USERNAME" == "admin" ]]; then
    CONFIG_FILE="$DOTFILES_DIR/config/fastfetch/fastfetch_admin.jsonc"
else
    CONFIG_FILE="$DOTFILES_DIR/config/fastfetch/fastfetch.jsonc"
fi

# Generate starry field and pipe it to fastfetch with the appropriate config
generate_starry_field "$CONFIG_FILE" | fastfetch -c "$CONFIG_FILE" --logo-type file-raw --logo -
