#!/bin/zsh
# Builds the app and packages it as build/IPTV-Player.dmg (drag-to-Applications installer).
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
./scripts/build-app.sh

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)
STAGING="$ROOT/build/dmg"
DMG="$ROOT/build/IPTV-Player-$VERSION.dmg"

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
ditto "$ROOT/build/IPTV Player.app" "$STAGING/IPTV Player.app"
ln -s /Applications "$STAGING/Aplicações"
cat > "$STAGING/Como abrir.txt" <<'EOF'
1. Arrasta "IPTV Player" para a pasta Aplicações.
2. Abre a app. O macOS vai avisar que não a consegue verificar (não está assinada pela Apple).
3. Vai a Definições do Sistema → Privacidade e Segurança, desce até ao fim e carrega em "Abrir na mesma".
4. Confirma. A partir daí abre normalmente.

Requer um Mac com processador Apple (M1 ou mais recente) e macOS 15 ou posterior.
EOF

hdiutil create -volname "IPTV Player" -srcfolder "$STAGING" -ov -format UDZO -quiet "$DMG"
rm -rf "$STAGING"
echo "✓ $DMG"
