#!/bin/bash
# Read-only: dump the Pixel's current logcat buffer (all buffers) to a file and print matching lines.
#   host-run bash docker-ws/pixel_logcat_dump_grep.sh <out-file-in-repo> <regex>
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"; OUT="$REPO/${1:?out}"; RE="${2:?regex}"
ADB="$HOME/Library/Android/sdk/platform-tools/adb"; S=21071FDF600CSC
mkdir -p "$(dirname "$OUT")"
timeout 120 "$ADB" -s "$S" logcat -d -b all -v threadtime > "$OUT" 2>&1; echo "dump exit=$? bytes=$(wc -c < "$OUT" | tr -d ' ') first=$(head -1 "$OUT" | cut -c1-18) last=$(tail -1 "$OUT" | cut -c1-18)"
grep -E "$RE" "$OUT" | cut -c1-260 | tail -60
