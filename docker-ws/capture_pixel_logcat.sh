#!/bin/bash
# Stream the Pixel's logcat to a file in the shared checkout (host bridge buffers
# long-running output, so a repo file is the working channel).
#   ./docker-ws/capture_pixel_logcat.sh <serial> [out-basename]
set -uo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
SERIAL="${1:?usage: capture_pixel_logcat.sh <serial> [out]}"
OUT="$DIR/${2:-pixel_logcat.txt}"
adb -s "$SERIAL" logcat -c 2>/dev/null || true
exec adb -s "$SERIAL" logcat -v time > "$OUT" 2>&1
