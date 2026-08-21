#!/bin/bash
# Grab a screenshot from a USB iPhone into the shared checkout.
#   ./docker-ws/screenshot_iphone.sh <udid> <out-basename.png>
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
UDID="${1:?usage: screenshot_iphone.sh <udid> <out.png>}"
OUT="$DIR/${2:-iphone_shot.png}"
BIN="$(command -v idevicescreenshot || echo /opt/homebrew/bin/idevicescreenshot)"
"$BIN" -u "$UDID" "$OUT" 2>&1
ls -l "$OUT" 2>&1
