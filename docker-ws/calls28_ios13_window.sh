#!/bin/bash
# Bounded iPhone 13 syslog window: counts ALL lines (liveness proof, not kept) and keeps only call/push lines.
#   host-run bash docker-ws/calls28_ios13_window.sh <out-file-in-repo> <secs>
REPO="$(cd "$(dirname "$0")/.." && pwd)"; O="$REPO/$1"; N="${2:-90}"; U=00008110-00184D622289801E
BIN="$(command -v idevicesyslog || echo /opt/homebrew/bin/idevicesyslog)"
T=$(mktemp); mkdir -p "$(dirname "$O")"
"$BIN" -u "$U" --no-colors > "$T" 2>/dev/null & P=$!
sleep "$N"; kill "$P" 2>/dev/null; sleep 1
{ echo "window_end=$(date -u +%FT%TZ) secs=$N all_lines=$(wc -l < "$T") first=$(head -1 "$T" | cut -c1-22) last=$(tail -1 "$T" | cut -c1-22)"
  grep -E '"event":"CALL_|MKNOON_CALL|reportNewIncoming|Received add incoming call|ApplePushService|apsd\[[0-9]+\] <Notice>|callservicesd.*com.mknoon' "$T" | cut -c1-300; } > "$O"
rm -f "$T"; head -1 "$O"; echo "kept=$(($(wc -l < "$O")-1))"
