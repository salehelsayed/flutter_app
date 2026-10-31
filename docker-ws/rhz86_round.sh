#!/bin/bash
# relay-hz-86b786747 idle round: send Mknoon on the iPhone 13 to the background (Home), idle <min> minutes, then dial from the Pixel.
#   bash docker-ws/rhz86_round.sh <label> <idle-min>
cd "$(dirname "$0")/.." || exit 2
L="$1"; MIN="$2"; D=.codex-test-logs/relay-hz-86b786747-20261029; A="timeout 120 python3 docker-ws/beta/ap.py 13"
$A app activate com.mknoon.app >/dev/null; sleep 3
$A app background >/dev/null; tb=$(date +%s); echo "$L backgrounded $(date -u +%FT%TZ) state=$($A app state com.mknoon.app)" | tee "$D/${L}_backgrounded_at.txt"
rem=$(( MIN*60 - ($(date +%s)-tb) - 20 )); [ "$rem" -gt 0 ] && sleep "$rem"
echo "$L pre-dial state=$($A app state com.mknoon.app) $($A islocked)" | tee -a "$D/${L}_backgrounded_at.txt"
idle=$(awk -v a="$tb" -v b="$(date +%s)" 'BEGIN{printf "%.1f", (b-a)/60}'); echo "$L idle_min=$idle" | tee -a "$D/${L}_backgrounded_at.txt"
timeout 300 bash docker-ws/rhz86_attempt.sh "$L" 45 5 > "$D/${L}_attempt.out" 2>&1
echo "$(date -u +%FT%TZ) step3d $L idle=${idle}min $(cut -c1-60 "$D/${L}_ring.txt") $(grep -E 'IPHONE_END|relay delta' "$D/${L}_attempt.out" | cut -c1-110 | tr '\n' ' ')" >> "$D/progress.txt"
