#!/bin/bash
# Builds a release app and packages it as build/Nunsseop-<version>.dmg.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/bundle.sh release >/dev/null
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
STAGE="$(mktemp -d)"
cp -R build/Nunsseop.app "$STAGE/"
xattr -cr "$STAGE/Nunsseop.app"
codesign --verify --deep --strict "$STAGE/Nunsseop.app"
ln -s /Applications "$STAGE/Applications"
DMG="build/Nunsseop-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "Nunsseop" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
echo "$DMG"
