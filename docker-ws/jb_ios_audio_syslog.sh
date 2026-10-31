#!/bin/bash
# Batch-B journeys: short iPhone 13 syslog window, keep only Runner / audio daemon lines (call audio evidence).
#   host-run bash docker-ws/jb_ios_audio_syslog.sh <out-file-in-repo> <secs<=60>
REPO="$(cd "$(dirname "$0")/.." && pwd)"; O="$REPO/$1"; N="${2:-15}"; [ "$N" -le 60 ] || N=60
BIN="$(command -v idevicesyslog || echo /opt/homebrew/bin/idevicesyslog)"
"$BIN" -u 00008110-00184D622289801E --no-colors 2>/dev/null > >(grep --line-buffered -E 'Runner\[|audiomxd|mediaserverd|AudioSession|RTC|webrtc|callservicesd' > "$O") &
P=$!; sleep "$N"; kill "$P" 2>/dev/null; sleep 1
echo "lines=$(wc -l < "$O")"; ps -o pid= -p "$P" >/dev/null && echo "WARN pid $P alive"
