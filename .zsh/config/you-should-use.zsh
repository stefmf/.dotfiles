# you-should-use
YSU_PLUGIN_PATHS=(
  "$HOME/.dotfiles/.zsh/.zshplugins/zsh-you-should-use/you-should-use.plugin.zsh"
  "/usr/share/zsh-you-should-use/zsh-you-should-use.plugin.zsh"
  "$(brew --prefix 2>/dev/null)/share/zsh-you-should-use/you-should-use.plugin.zsh"
)

for ysu_plugin in "${YSU_PLUGIN_PATHS[@]}"; do
  if [ -f "$ysu_plugin" ]; then
    source "$ysu_plugin"
    break
  fi
done

YSU_MESSAGE_POSITION="after"
YSU_MODE=ALL
