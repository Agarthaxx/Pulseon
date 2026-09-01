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

# **De quand date ce binaire**, estampillé au moment où le code le devient.
#
# Deux fois — le 2026-08-18 et le 2026-09-01 — une app périmée dans
# /Applications a fait passer du travail réel pour des bugs, parce que rien ne
# permettait de distinguer « le correctif ne marche pas » de « le correctif
# n'est pas là ». Le menu affiche donc ces deux valeurs (voir `BuildStamp`).
#
# La date de modification du binaire ne conviendrait pas : la copie et la
# signature la réécrivent toutes les deux, donc elle daterait la dernière
# manipulation du fichier et non la compilation.
BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
# Le `+` dit que l'arbre était modifié : un SHA seul désignerait alors du code
# qui n'est pas celui qu'on a compilé. Mieux vaut un identifiant qui s'avoue
# approximatif qu'un identifiant faux.
BUILD_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo "")"
if [ -n "$BUILD_COMMIT" ] && ! git diff --quiet HEAD 2>/dev/null; then
    BUILD_COMMIT="${BUILD_COMMIT}+"
fi
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

# L'icône. Elle est commitée (Scripts/make-icon.sh la regénère depuis la vue
# `PulseonAppIcon`) pour qu'assembler l'app ne demande rien d'autre que le
# dépôt. Sans elle, macOS affiche le rectangle blanc générique.
cp Resources/AppIcon.icns "${APP}/Contents/Resources/AppIcon.icns"

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
    <!-- Sans extension : macOS ajoute .icns lui-même, et l'écrire ici marche
         aussi, mais la forme sans suffixe est celle qu'Xcode produit. -->
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <!-- Lues par `BuildStamp`, affichées dans le menu de la barre. -->
    <key>PulseonBuildDate</key>
    <string>${BUILD_DATE}</string>
    <key>PulseonBuildCommit</key>
    <string>${BUILD_COMMIT}</string>
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
