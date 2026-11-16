#!/bin/zsh
set -euo pipefail

target_app="$HOME/Applications/CodexPet.app"
launch_agent="$HOME/Library/LaunchAgents/com.huang.codexpet.plist"

/usr/bin/pkill -x CodexPet 2>/dev/null || true
/bin/launchctl bootout "gui/$(id -u)" "$launch_agent" 2>/dev/null || true
[[ ! -e "$launch_agent" ]] || /bin/mv "$launch_agent" "$HOME/.Trash/com.huang.codexpet.plist"
[[ ! -e "$target_app" ]] || /bin/mv "$target_app" "$HOME/.Trash/CodexPet.app"

print "Codex Pet 已移到废纸篓。"

