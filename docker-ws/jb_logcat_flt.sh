#!/bin/bash
# Batch-B journeys: filtered Pixel logcat to a repo file (small on disk). Stops at max secs or when <out>.stop exists.
#   host-run bash docker-ws/jb_logcat_flt.sh <serial> <out-file-in-repo> <max-secs>
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"; S="$1"; OUT="$REPO/$2"; MAX="$3"
export PATH="$HOME/Library/Android/sdk/platform-tools:/opt/homebrew/bin:/usr/bin:/bin"
mkdir -p "$(dirname "$OUT")"
adb -s "$S" logcat -v threadtime -T 1 > >(grep --line-buffered -E 'flutter|[Mm]knoon|WebRTC|webrtc|AudioRecord|AudioTrack|Telecom|CallStyle|ActivityManager.*(mknoon|Kill)' > "$OUT") &
P=$!; echo "capturing pid=$P"
t=0; while kill -0 "$P" 2>/dev/null && [ "$t" -lt "$MAX" ] && [ ! -f "$OUT.stop" ]; do sleep 5; t=$((t+5)); done
kill "$P" 2>/dev/null; rm -f "$OUT.stop"
echo "done lines=$(wc -l < "$OUT")"
