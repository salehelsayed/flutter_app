#!/bin/bash
# VC-014 prod round without Appium (phone auto-locks): wait until <idle-min> minutes after <since-utc>, report the
# last apsd isSystemLocked state seen in the iPhone capture, then dial.   bash docker-ws/vc014p_round_locked.sh <label> <idle-min> <since-utc ISO>
cd "$(dirname "$0")/.." || exit 2
L="$1"; MIN="$2"; SINCE=$(date -d "$3" +%s); D=.codex-test-logs/vc014-prodapns-20261028
T=$((SINCE + MIN*60)); now=$(date +%s); [ "$T" -gt "$now" ] && sleep $((T-now))
LK=$(/claude-host-bin/host-run bash docker-ws/calls28_mgrep.sh "$D/ios13_syslog.txt" 'isSystemLocked' 1 400 | tail -1 | grep -oE '^Oct 28 [0-9:.]+|isSystemLocked: (YES|NO)' | tr '\n' ' ')
idle=$(awk -v a="$SINCE" -v b="$(date +%s)" 'BEGIN{printf "%.1f", (b-a)/60}')
echo "$L since=$3 idle_min=$idle last_lock_line: $LK" | tee "$D/${L}_backgrounded_at.txt"
timeout 240 bash docker-ws/vc014p_attempt.sh "$L" 45 | tee "$D/${L}_attempt.out"
echo "$(date -u +%FT%TZ) step3 $L idle=${idle}min lock[$LK] $(cut -c1-90 "$D/${L}_ring.txt") ioslines=$(grep -c . "$D/${L}_ios_syslog_window.txt") $(tail -3 "$D/${L}_attempt.out" 2>/dev/null | tr '\n' ' ')" >> "$D/progress.txt"
