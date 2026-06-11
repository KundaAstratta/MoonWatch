#!/usr/bin/env bash
# Lance le simulateur avec MoonWatch pour prendre les captures de référence
# (parité visuelle entre les phases de refactoring — à archiver dans refs/).
#
# Usage : ./capture-refs.sh [device]   (défaut : fenix847mm)
#
# Une fois le cadran affiché, prendre 3 captures (File > Save Screenshot,
# noms de menus selon la version du simulateur) :
#   refs/<device>-actif.png   : état par défaut
#   refs/<device>-aod.png     : après bascule Low Power Mode
#   refs/<device>-chrono.png  : après chronoState = 1 dans l'éditeur de
#                               réglages de l'application
set -euo pipefail
cd "$(dirname "$0")"

DEVICE="${1:-fenix847mm}"
SDK_BIN="$(tr -d '\n' < "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")/bin"

mkdir -p refs
[ -f "bin/MoonWatch-${DEVICE}.prg" ] || ./build.sh

"$SDK_BIN/connectiq" &
sleep 5
"$SDK_BIN/monkeydo" "bin/MoonWatch-${DEVICE}.prg" "$DEVICE"
