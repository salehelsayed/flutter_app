#!/bin/bash
# VC-014 prod round: send Mknoon on the iPhone 13 to the background (Home), let it auto-lock, idle <min> minutes, then dial.
#   bash docker-ws/vc014p_round.sh <label> <idle-min>
cd "$(dirname "$0")/.." || exit 2
L="$1"; MIN="$2"; D=.codex-test-logs/vc014-prodapns-20261028; A="timeout 120 python3 docker-ws/beta/ap.py 13"
$A app activate com.mknoon.app >/dev/null; sleep 3
$A app background >/dev/null; tb=$(date +%s); echo "$L backgrounded $(date -u +%FT%TZ)" | tee "$D/${L}_backgrounded_at.txt"
sleep 90; echo "$L t+90s $($A islocked)" | tee -a "$D/${L}_backgrounded_at.txt"
rem=$(( MIN*60 - ($(date +%s)-tb) - 25 )); [ "$rem" -gt 0 ] && sleep "$rem"
echo "$L pre-dial $($A islocked) state=$($A app state com.mknoon.app)" | tee -a "$D/${L}_backgrounded_at.txt"
idle=$(awk -v a="$tb" -v b="$(date +%s)" 'BEGIN{printf "%.1f", (b-a)/60}'); echo "$L idle_min=$idle" | tee -a "$D/${L}_backgrounded_at.txt"
timeout 240 bash docker-ws/vc014p_attempt.sh "$L" 45
echo "$(date -u +%FT%TZ) step3 $L idle=${idle}min $(cat "$D/${L}_ring.txt" | cut -c1-90) $(grep -c . "$D/${L}_ios_syslog_window.txt") ioslines" >> "$D/progress.txt"
