#!/bin/bash
# Fabrique Resources/AppIcon.icns à partir de la vue `PulseonAppIcon`.
#
# L'icône est **dessinée en SwiftUI**, pas exportée d'un outil de dessin : la
# même vue rend le 1024 du Finder et le 16 d'une liste, chaque taille
# redessinée plutôt que réduite. Le `.icns` est commité pour que
# `build-app.sh` n'ait besoin de rien d'autre que du dépôt.
#
#   ./Scripts/make-icon.sh          # regénère et ouvre la planche de contrôle
#   ./Scripts/make-icon.sh --quiet  # regénère seulement
set -euo pipefail

cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

WORK="${TMPDIR:-/tmp}/pulseon-icon"
mkdir -p "$WORK" Resources

echo "→ Rendu des dix tailles"
swift run --package-path Tools/Preview Icon "$WORK" > /dev/null

echo "→ Assemblage"
iconutil --convert icns --output Resources/AppIcon.icns "${WORK}/Pulseon.iconset"

echo "✓ Resources/AppIcon.icns"

if [ "${1:-}" != "--quiet" ]; then
    open "${WORK}/icon-sheet.png"
fi
