#!/bin/bash
# Assemble Pulseon.app à partir de l'exécutable SwiftPM.
#
# Un exécutable nu ne suffit pas : sans bundle, pas d'identifiant, pas de
# LSUIElement (donc une icône dans le Dock), pas de lancement à l'ouverture de
# session, et CloudKit refusera de fonctionner. Ce script fabrique le minimum
# viable, sans projet Xcode.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Pulseon"
BUNDLE_ID="com.arthurlanllier.pulseon"
VERSION="0.1.0"
BUILD_DIR=".build/release"
APP="${BUILD_DIR}/${APP_NAME}.app"

if [ -z "${DEVELOPER_DIR:-}" ] && [ -d /Applications/Xcode.app ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

echo "→ Compilation"
swift build -c release --product PulseonMac

echo "→ Assemblage du bundle"
rm -rf "$APP"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "${BUILD_DIR}/PulseonMac" "${APP}/Contents/MacOS/${APP_NAME}"

cat > "${APP}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <!-- Agent : vit dans la barre de menu, pas dans le Dock, et n'ouvre
         aucune fenêtre au lancement. -->
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
PLIST

echo "→ Signature ad-hoc"
# Sans signature, SMAppService refuse d'enregistrer l'app au démarrage.
# La signature ad-hoc (-) suffit en local ; une vraie identité Developer ID
# ne devient nécessaire que pour distribuer à d'autres machines.
codesign --force --sign - --timestamp=none "$APP"

echo "✓ ${APP}"
