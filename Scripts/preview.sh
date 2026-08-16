#!/bin/bash
# Rend les vues de Pulseon en PNG et les ouvre.
#
# Regarder ce qu'on dessine trouve ce qu'aucun test ne voit : une étiquette
# coupée, un bloc mal placé, une grille qui part du mauvais bord.
#
#   ./Scripts/preview.sh          # rend et ouvre
#   ./Scripts/preview.sh --quiet  # rend seulement (pour un agent, ou du CI)

set -euo pipefail

cd "$(dirname "$0")/.."
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

# Hors du dépôt : ce sont des images jetables, regénérées à chaque appel.
OUTPUT="${TMPDIR:-/tmp}/pulseon-preview"
mkdir -p "$OUTPUT"

echo "→ Rendu des vues"
swift run --package-path Tools/Preview Preview "$OUTPUT"

if [ "${1:-}" != "--quiet" ]; then
    open "$OUTPUT"/*.png
fi
