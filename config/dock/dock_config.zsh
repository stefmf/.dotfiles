#!/bin/zsh

# Remove all current dock items
dockutil --remove all --no-restart

# Add items in specified order
dockutil --add /Applications/Apps.app --no-restart
dockutil --add /Applications/iTerm.app --no-restart
dockutil --add /Applications/Sublime\ Text.app --no-restart
dockutil --add /Applications/Visual\ Studio\ Code.app --no-restart
dockutil --add /Applications/Utilities/Screen\ Sharing.app --no-restart
dockutil --add /Applications/Safari.app --no-restart

# Add Downloads folder as a stack in list view
dockutil --add "$HOME/Downloads" --view list --display folder --no-restart

# Set additional Dock preferences
defaults write com.apple.dock minimize-to-application -bool true # Minimize into app icon
defaults write com.apple.dock show-recents -bool false # Disable recent apps

# Restart the Dock to apply changes
killall Dock
