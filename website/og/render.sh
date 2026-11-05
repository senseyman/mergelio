#!/usr/bin/env bash
# render.sh — renders og.html into ../img/og.jpg (1200×630) with headless Chrome.
# Needs Google Chrome and ffmpeg. Run from anywhere: ./website/og/render.sh
set -euo pipefail
DIR=$(cd "$(dirname "$0")" && pwd)
CHROME=${CHROME:-"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

"$CHROME" --headless=new --user-data-dir="$TMP/profile" --hide-scrollbars \
  --force-device-scale-factor=1 --window-size=1200,630 --virtual-time-budget=3000 \
  --screenshot="$TMP/og.png" "file://$DIR/og.html" 2>/dev/null
ffmpeg -v error -y -i "$TMP/og.png" -q:v 3 "$DIR/../img/og.jpg"
echo "Wrote $DIR/../img/og.jpg"
