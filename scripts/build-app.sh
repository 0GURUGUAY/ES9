#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="$PWD/dist/ES-9 Mixer.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
ICONSET="$PWD/.build/ES9Mixer.iconset"
swift scripts/generate-icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/ES9Fader.icns"
cp "$BIN_DIR/ES9Mixer" "$APP/Contents/MacOS/ES9Mixer"
/usr/libexec/PlistBuddy -c 'Print' "$PWD/Resources/Info.plist" >/dev/null
cp "$PWD/Resources/Info.plist" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
printf '\nApplication créée : %s\n' "$APP"
