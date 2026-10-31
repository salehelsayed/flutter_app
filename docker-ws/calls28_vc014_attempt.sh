#!/bin/bash
# One VC-014 attempt: Pixel (in chat with iphone-13) dials, poll the iPhone 13 call syslog (Mac side) for the CallKit
# incoming report, then cancel from the Pixel. Prints dial time, first ring line and time-to-ring.
#   calls28_vc014_attempt.sh <label> [max-secs]
cd "$(dirname "$0")/.." || exit 2
L="$1"; MAX="${2:-40}"; D=.codex-test-logs/calls-20261028/VC-014; mkdir -p "$D"
F=${IOSCAP:-.codex-test-logs/calls-20261028/ios13_call_syslog2.txt}
RE='reportNewIncomingCallWithUUID|Received add incoming call'
base=$(/claude-host-bin/host-run bash docker-ws/calls28_mgrep.sh "$F" '^$' 1 | sed -n 's/.*lines=//p')
bash docker-ws/calls28.sh pui | grep -q 'View contact profile&#10;iphone-13' || { echo "PIXEL NOT IN iphone-13 CHAT"; exit 3; }
t0=$(date +%s.%N); echo "$L dial $(date -u +%FT%T.%3NZ)" | tee "$D/${L}_dial.txt"
bash docker-ws/calls28.sh ptap "Start voice call" >/dev/null
hit=""
while [ "$(awk -v a="$t0" -v b="$(date +%s.%N)" 'BEGIN{print int(b-a)}')" -lt "$MAX" ]; do
  h=$(/claude-host-bin/host-run bash docker-ws/calls28_tail_from.sh "$F" "$base" "$RE" | head -1)
  if [ -n "$h" ]; then hit="$h"; el=$(awk -v a="$t0" -v b="$(date +%s.%N)" 'BEGIN{printf "%.1f", b-a}'); break; fi
  sleep 1
done
if [ -n "$hit" ]; then echo "$L RING yes poll+${el}s :: $hit" | tee "$D/${L}_ring.txt"; sleep 4
else echo "$L RING no within ${MAX}s" | tee "$D/${L}_ring.txt"; fi
bash docker-ws/calls28.sh pui > "$D/${L}_pixel_after.txt" 2>&1
C=$(grep -oE 'content-desc="(Cancel call|End)"' "$D/${L}_pixel_after.txt" | head -1); [ -n "$C" ] && bash docker-ws/calls28.sh ptap "$C" && echo "$L pixel End tapped $(date -u +%T)"
/claude-host-bin/host-run bash docker-ws/calls28_tail_from.sh "$F" "$base" '.' | grep -vE 'RunningBoard|runningboardd' > "$D/${L}_ios_syslog_window.txt"
echo "ios window lines: $(wc -l < "$D/${L}_ios_syslog_window.txt")"
