#!/bin/zsh

# Remove all current dock items
dockutil --remove all --no-restart

# Add items in specified order
dockutil --add /System/Applications/Launchpad.app --no-restart
dockutil --add /Applications/iTerm.app --no-restart
dockutil --add /Applications/Sublime\ Text.app --no-restart
dockutil --add /Applications/Visual\ Studio\ Code.app --no-restart
dockutil --add /Applications/ChatGPT.app --no-restart
dockutil --add /Applications/Windows\ App.app --no-restart
dockutil --add /Applications/Parallels\ Desktop.app --no-restart
dockutil --add /Applications/Screens\ 5.app --no-restart
dockutil --add /System/Applications/Calendar.app --no-restart
dockutil --add /System/Applications/Notes.app --no-restart
dockutil --add /Applications/Firefox.app --no-restart
dockutil --add /Applications/Spotify.app --no-restart
dockutil --add /Applications/Discord.app --no-restart
dockutil --add /System/Applications/Messages.app --no-restart
dockutil --add /System/Applications/iPhone\ Mirroring.app --no-restart
dockutil --add /System/Applications/System\ Settings.app --no-restart

# Add Downloads folder as a stack in list view
dockutil --add "$HOME/Downloads" --view list --display folder --no-restart

# Set additional Dock preferences
defaults write com.apple.dock minimize-to-application -bool true # Minimize into app icon
defaults write com.apple.dock show-recents -bool false # Disable recent apps

# Restart the Dock to apply changes
killall Dock
