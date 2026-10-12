#!/bin/zsh
# Writes build/appcast.xml, the Sparkle feed announcing the DMG that make-dmg.sh just built.
#
# Usage: make-appcast.sh <dmg> <download-url>
# The DMG is signed with the EdDSA private key: from the file in SPARKLE_KEY_FILE (CI), or else
# from the login keychain (where generate_keys stored it).
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
DMG="$1"
URL="$2"
PLIST="$ROOT/build/IPTV Player.app/Contents/Info.plist"
SIGN_UPDATE="$ROOT/.build/artifacts/sparkle/Sparkle/bin/sign_update"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$PLIST")
BUILD=$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$PLIST")
MIN_OS=$(/usr/libexec/PlistBuddy -c "Print LSMinimumSystemVersion" "$PLIST")

if [[ -n "${SPARKLE_KEY_FILE:-}" ]]; then
    SIGNATURE=$("$SIGN_UPDATE" --ed-key-file "$SPARKLE_KEY_FILE" "$DMG")
else
    SIGNATURE=$("$SIGN_UPDATE" --account dev.maiaxi.iptvplayer "$DMG")
fi
# sign_update prints: sparkle:edSignature="…" length="…"
[[ "$SIGNATURE" == *'sparkle:edSignature='* ]] || { echo "sign_update failed: $SIGNATURE" >&2; exit 1; }

cat > "$ROOT/build/appcast.xml" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>IPTV Player</title>
    <item>
      <title>Version $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MIN_OS</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>https://github.com/maiaxi/iptv-player/releases/tag/v$VERSION</sparkle:fullReleaseNotesLink>
      <enclosure url="$URL" type="application/octet-stream" $SIGNATURE />
    </item>
  </channel>
</rss>
EOF
xmllint --noout "$ROOT/build/appcast.xml"
echo "✓ $ROOT/build/appcast.xml ($VERSION, build $BUILD)"
