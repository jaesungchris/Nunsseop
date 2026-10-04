#!/bin/bash
# Builds the Swift package and wraps the binary in an .app bundle.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

APP="build/NotchApp.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/NotchApp" "$APP/Contents/MacOS/NotchApp"
cp "$BIN_DIR/libNowPlayingHelper.dylib" Resources/nowplaying.pl "$APP/Contents/Resources/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP/Contents/Resources/libNowPlayingHelper.dylib" >/dev/null
codesign --force --sign - "$APP" >/dev/null
echo "$APP"
