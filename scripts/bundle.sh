#!/bin/bash
# Builds the Swift package and wraps the binary in an .app bundle.
set -euo pipefail
cd "$(dirname "$0")/.."

# Pass "release" for a build to use day to day; the debug build adds snapshot/demo flags.
CONFIG="${1:-debug}"
swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

APP="build/Nunsseop.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Nunsseop" "$APP/Contents/MacOS/Nunsseop"
cp "$BIN_DIR/libNowPlayingHelper.dylib" Resources/nowplaying.pl "$APP/Contents/Resources/"
cp -R Resources/*.lproj Resources/AppIcon.icns "$APP/Contents/Resources/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
xattr -cr "$APP"
codesign --force --sign - "$APP/Contents/Resources/libNowPlayingHelper.dylib" >/dev/null
codesign --force --sign - "$APP" >/dev/null
echo "$APP"
