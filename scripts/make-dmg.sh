#!/bin/zsh
# Builds the app and packages it as build/IPTV-Player-<version>.dmg (drag-to-Applications
# installer). Takes the same environment as build-app.sh (ARCHS, VERSION, BUILD_NUMBER).
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
./scripts/build-app.sh

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$ROOT/build/IPTV Player.app/Contents/Info.plist")
STAGING="$ROOT/build/dmg"
DMG="$ROOT/build/IPTV-Player-$VERSION.dmg"

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
ditto "$ROOT/build/IPTV Player.app" "$STAGING/IPTV Player.app"
ln -s /Applications "$STAGING/Applications"
cat > "$STAGING/How to open.txt" <<'EOF'
1. Drag "IPTV Player" into the Applications folder.
2. Open the app. macOS will say it can't verify it (the app isn't signed by Apple).
3. Go to System Settings → Privacy & Security, scroll to the bottom and click "Open Anyway".
4. Confirm. From then on it opens normally.

Requires a Mac with Apple silicon (M1 or later) and macOS 15 or later.
EOF

hdiutil create -volname "IPTV Player" -srcfolder "$STAGING" -ov -format UDZO -quiet "$DMG"
rm -rf "$STAGING"
echo "✓ $DMG"
