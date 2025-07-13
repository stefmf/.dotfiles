# zsh-autosuggestions
ZSH_AUTOSUGGEST_LOCATIONS=(
  "/usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
  "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh"
  "$(brew --prefix zsh-autosuggestions 2>/dev/null)/share/zsh-autosuggestions/zsh-autosuggestions.zsh"
  "$HOME/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh"
  "$HOME/.dotfiles/.zsh/.zshplugins/zsh-autosuggestions/zsh-autosuggestions.zsh"
)

for plugin in "${ZSH_AUTOSUGGEST_LOCATIONS[@]}"; do
  if [ -f "$plugin" ]; then
    source "$plugin"
    break
  fi
done

ZSH_AUTOSUGGEST_STRATEGY=(history completion)
ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20
ZSH_AUTOSUGGEST_USE_ASYNC=true
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#808080'

bindkey '^[[1;3C' forward-word
bindkey '^[[1;5C' forward-word
