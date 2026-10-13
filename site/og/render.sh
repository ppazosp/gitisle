#!/bin/bash
# Renders the social preview images at 2x (2400 x 1260) with headless Chrome: og/og.html to
# public/og.png for most sites, and og/og-square.html to public/og-square.png for Slack.
set -euo pipefail
cd "$(dirname "$0")/.."
chrome="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
for name in og og-square; do
    "$chrome" --headless --disable-gpu --hide-scrollbars --force-device-scale-factor=2 \
        --window-size=1200,630 --virtual-time-budget=3000 \
        --screenshot="$PWD/public/$name.png" "file://$PWD/og/$name.html"
    printf 'Rendered %s\n' "$PWD/public/$name.png"
done
