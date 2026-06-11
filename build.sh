#!/usr/bin/env bash
# Build MoonWatch en type-check strict sur les 3 résolutions du manifest.
#
# Usage :
#   ./build.sh           build standard (marq2 390, epix2 416, fenix847mm 454)
#   ./build.sh --tests   build avec les tests unitaires (:test) inclus
#
# Lancer les tests ensuite : connectiq && monkeydo bin/MoonWatch-<device>-test.prg <device> -t
#
# Warning connu et bénin : « launcher icon (65x65) isn't compatible » sur les
# devices attendant 60x60 ou 70x70 — l'icône SVG est rastérisée à 65 puis
# mise à l'échelle (les 23 cibles demandent 60, 65 ou 70 selon le modèle).
set -euo pipefail
cd "$(dirname "$0")"

SDK_CFG="$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg"
SDK_BIN="$(tr -d '\n' < "$SDK_CFG")/bin"
KEY="$HOME/Code/sdkgarmin/developer_key"
OUT_DIR="bin"

# Une cible par résolution présente dans le manifest (toutes AMOLED)
DEVICES=(marq2 epix2 fenix847mm)

EXTRA=()
SUFFIX=""
if [[ "${1:-}" == "--tests" ]]; then
    EXTRA=(--unit-test)
    SUFFIX="-test"
fi

mkdir -p "$OUT_DIR"
for d in "${DEVICES[@]}"; do
    echo "=== ${d} ==="
    "$SDK_BIN/monkeyc" -f monkey.jungle -d "$d" \
        -o "$OUT_DIR/MoonWatch-${d}${SUFFIX}.prg" \
        -y "$KEY" -w -l 3 ${EXTRA[@]+"${EXTRA[@]}"}
done
echo "OK — ${DEVICES[*]}"
