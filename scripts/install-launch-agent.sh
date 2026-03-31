#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
AGENT_LABEL="com.voice.volume-guardian"
PLIST_PATH="$HOME/Library/LaunchAgents/$AGENT_LABEL.plist"
BUILD_DIR="$ROOT_DIR/.build/release"
# ~/Documents 等用户目录受 TCC 保护，launchd 无法直接访问其中的可执行文件。
# 将可执行文件安装到不受 TCC 限制的 ~/.local/bin 目录。
INSTALL_DIR="$HOME/.local/bin"
EXECUTABLE_PATH="$INSTALL_DIR/volume-guardian"
LOG_DIR="$HOME/.local/share/volume-guardian/logs"

mkdir -p "$HOME/Library/LaunchAgents"
mkdir -p "$INSTALL_DIR"
mkdir -p "$LOG_DIR"

# 清空旧日志，避免重装后日志混杂
: > "$LOG_DIR/stdout.log"
: > "$LOG_DIR/stderr.log"

swift build -c release --package-path "$ROOT_DIR"

BUILD_EXECUTABLE="$BUILD_DIR/volume-guardian"

if [[ ! -x "$BUILD_EXECUTABLE" ]]; then
    echo "Build succeeded but executable is missing or not executable: $BUILD_EXECUTABLE" >&2
    exit 1
fi

cp -f "$BUILD_EXECUTABLE" "$EXECUTABLE_PATH"
codesign --force --sign - "$EXECUTABLE_PATH"

cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$AGENT_LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$EXECUTABLE_PATH</string>
    </array>
    <key>WorkingDirectory</key>
    <string>$HOME</string>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$LOG_DIR/stdout.log</string>
    <key>StandardErrorPath</key>
    <string>$LOG_DIR/stderr.log</string>
    <key>SoftResourceLimits</key>
    <dict>
        <key>NumberOfFiles</key>
        <integer>10240</integer>
    </dict>
    <key>HardResourceLimits</key>
    <dict>
        <key>NumberOfFiles</key>
        <integer>10240</integer>
    </dict>
</dict>
</plist>
PLIST

launchctl bootout "gui/$(id -u)/$AGENT_LABEL" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"
launchctl enable "gui/$(id -u)/$AGENT_LABEL"
launchctl kickstart -k "gui/$(id -u)/$AGENT_LABEL"

echo "Installed launch agent: $AGENT_LABEL"
echo "Executable: $EXECUTABLE_PATH"
echo "Plist: $PLIST_PATH"