#!/bin/zsh

set -euo pipefail

AGENT_LABEL="com.voice.volume-guardian"
PLIST_PATH="$HOME/Library/LaunchAgents/$AGENT_LABEL.plist"
INSTALL_PATH="$HOME/.local/bin/volume-guardian"

launchctl bootout "gui/$(id -u)/$AGENT_LABEL" >/dev/null 2>&1 || true
rm -f "$PLIST_PATH"
rm -f "$INSTALL_PATH"

echo "Removed launch agent: $AGENT_LABEL"