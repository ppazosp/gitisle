#!/bin/bash
# Renders scripts/dmg/background.html to background.png and background@2x.png with headless
# Chrome. Needs site/node_modules for the Geist font (npm ci in site/).
set -euo pipefail
cd "$(dirname "$0")"
chrome="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
for scale in 1 2; do
    suffix=""
    [ "$scale" = 2 ] && suffix="@2x"
    "$chrome" --headless --disable-gpu --hide-scrollbars --force-device-scale-factor="$scale" \
        --window-size=660,420 --virtual-time-budget=3000 \
        --screenshot="$PWD/background$suffix.png" "file://$PWD/background.html"
done
printf 'Rendered %s/background.png and background@2x.png\n' "$PWD"
