#!/bin/bash
# Renders og/og.html to public/og.png at 2x (2400 x 1260) with headless Chrome.
set -euo pipefail
cd "$(dirname "$0")/.."
chrome="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
"$chrome" --headless --disable-gpu --hide-scrollbars --force-device-scale-factor=2 \
    --window-size=1200,630 --virtual-time-budget=3000 \
    --screenshot="$PWD/public/og.png" "file://$PWD/og/og.html"
printf 'Rendered %s\n' "$PWD/public/og.png"
