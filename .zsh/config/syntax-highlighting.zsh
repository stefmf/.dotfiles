# zsh-syntax-highlighting
# Look for the plugin in common locations
ZSH_SYNTAX_HIGHLIGHT_DIRS=(
  "$HOME/.dotfiles/.zsh/.zshplugins/zsh-syntax-highlighting"
  "/usr/share/zsh-syntax-highlighting"
  "$(brew --prefix 2>/dev/null)/share/zsh-syntax-highlighting"
)

for SYNTAX_DIR in "${ZSH_SYNTAX_HIGHLIGHT_DIRS[@]}"; do
  if [ -f "$SYNTAX_DIR/zsh-syntax-highlighting.zsh" ]; then
    if [ -n "$ZSH_SYNTAX_THEME" ] && [ -f "$ZSH_SYNTAX_THEME" ]; then
      source "$ZSH_SYNTAX_THEME"
    elif [ -f "$SYNTAX_DIR/themes/catppuccin_frappe-zsh-syntax-highlighting.zsh" ]; then
      source "$SYNTAX_DIR/themes/catppuccin_frappe-zsh-syntax-highlighting.zsh"
    fi
    source "$SYNTAX_DIR/zsh-syntax-highlighting.zsh"
    break
  fi
done
