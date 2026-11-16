#!/bin/zsh
set -euo pipefail

project_dir="${0:A:h:h}"
source_app="$project_dir/.build/CodexPet.app"
target_app="$HOME/Applications/CodexPet.app"
launch_agent="$HOME/Library/LaunchAgents/com.huang.codexpet.plist"

mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents"
/usr/bin/pkill -x CodexPet 2>/dev/null || true
ditto "$source_app" "$target_app"

/usr/bin/plutil -create xml1 "$launch_agent"
/usr/bin/plutil -insert Label -string com.huang.codexpet "$launch_agent"
/usr/bin/plutil -insert ProgramArguments -json "[\"/usr/bin/open\",\"-a\",\"$target_app\"]" "$launch_agent"
/usr/bin/plutil -insert RunAtLoad -bool true "$launch_agent"

/bin/launchctl bootout "gui/$(id -u)" "$launch_agent" 2>/dev/null || true
/bin/launchctl bootstrap "gui/$(id -u)" "$launch_agent"

print "Codex Pet 已安装并启动：$target_app"
