#!/bin/zsh
# Builds "IPTV Player.app" into ./build. libmpv comes from MPVKit (statically linked).
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
APP="$ROOT/build/IPTV Player.app"
CONFIG="${1:-release}"

# The macOS 27 SDK turns SwiftUI's @State into a macro whose plugin only ships with full Xcode.
# With just the Command Line Tools, build against the newest older SDK instead.
if ! xcode-select -p | grep -q "Xcode.app"; then
    SDK=$(/bin/ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26*.sdk 2>/dev/null | sort -V | tail -1 || true)
    if [[ -n "$SDK" ]]; then export SDKROOT="$SDK"; fi
fi

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/IPTVPlayer"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/IPTVPlayer"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"

# Translations. English is the source language (the strings in code), so en.lproj only needs to
# exist for macOS to pick English; other languages carry a Localizable.strings.
mkdir -p "$APP/Contents/Resources/en.lproj"
for LPROJ in "$ROOT"/Resources/*.lproj(N); do
    DEST="$APP/Contents/Resources/$(basename "$LPROJ")"
    mkdir -p "$DEST"
    for STRINGS in "$LPROJ"/*.strings(N); do
        plutil -lint -s "$STRINGS"
        plutil -convert binary1 -o "$DEST/$(basename "$STRINGS")" "$STRINGS"
    done
done

ICONSET="$ROOT/build/AppIcon.iconset"
if [[ ! -f "$ROOT/build/AppIcon.icns" ]]; then
    swift "$ROOT/scripts/make-icon.swift" "$ICONSET"
    iconutil -c icns "$ICONSET" -o "$ROOT/build/AppIcon.icns"
    rm -rf "$ICONSET"
fi
cp "$ROOT/build/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

codesign --force --sign - "$APP" >/dev/null
echo "✓ $APP"
