#!/bin/bash
# relay-hz-86b786747 round: Pixel (in chat with iphone-13) dials; poll the iPhone 13 syslog capture for the CallKit incoming
# report; then the caller cancels and we time the iPhone terminal line. Hetzner /metrics before/after (read-only).
#   bash docker-ws/rhz86_attempt.sh <label> [max-secs] [ring-hold-secs]
cd "$(dirname "$0")/.." || exit 2
export ADB_SERVER_SOCKET=${ADB_SERVER_SOCKET:-tcp:host.docker.internal:5037}
L="$1"; MAX="${2:-45}"; HOLD="${3:-5}"; S=21071FDF600CSC; D=.codex-test-logs/relay-hz-86b786747-20261029; F=$D/ios13_syslog.txt
RE='reportNewIncomingCallWithUUID|Received add incoming call'
TRE='MKNOON_CALLKIT_DIAG\] (terminal=|result=remote_cancelled)|remote_cancel reason='
M() { timeout 120 python3 docker-ws/hetzner_ssh.py < docker-ws/rhz86_metrics.sh 2>&1 | grep -E 'Z$|outcome="sent"|call_store_v1|invalid_token|sent_cross|expired'; }
M > "$D/${L}_relay_before.txt"
base=$(/claude-host-bin/host-run bash docker-ws/calls28_mgrep.sh "$F" '^$' 1 | sed -n 's/.*lines=//p')
bash docker-ws/pixel_ui_texts.sh "$S" | grep -q 'Start voice call' || { echo "CALLER NOT IN CHAT"; exit 3; }
el() { awk -v a="$1" -v b="$(date +%s.%N)" 'BEGIN{printf "%.1f", b-a}'; }
t0=$(date +%s.%N); echo "$L dial $(date -u +%FT%T.%3NZ)" | tee "$D/${L}_dial.txt"
bash docker-ws/pixel_tap_desc.sh "$S" "Start voice call" >/dev/null
hit=""
while [ "$(el "$t0" | cut -d. -f1)" -lt "$MAX" ]; do
  h=$(/claude-host-bin/host-run bash docker-ws/calls28_tail_from.sh "$F" "$base" "$RE" | head -1)
  if [ -n "$h" ]; then hit="$h"; e=$(el "$t0"); break; fi
  sleep 1
done
if [ -n "$hit" ]; then echo "$L RING yes poll+${e}s :: $(echo "$hit" | cut -c1-80)" | tee "$D/${L}_ring.txt"; sleep "$HOLD"
else echo "$L RING no within ${MAX}s" | tee "$D/${L}_ring.txt"; fi
bash docker-ws/pixel_ui_texts.sh "$S" > "$D/${L}_caller_after.txt" 2>&1
C=$(grep -oE 'content-desc="(Cancel call|End call|End|Hang up)"' "$D/${L}_caller_after.txt" | head -1 | sed 's/content-desc="//; s/"$//')
tc=""; [ -n "$C" ] && bash docker-ws/pixel_tap_desc.sh "$S" "$C" >/dev/null && tc=$(date +%s.%N) && echo "$L caller end tapped $(date -u +%T.%3N) ($C)"
if [ -n "$hit" ] && [ -n "$tc" ]; then
  term=""; while [ "$(el "$tc" | cut -d. -f1)" -lt 20 ]; do
    term=$(/claude-host-bin/host-run bash docker-ws/calls28_tail_from.sh "$F" "$base" "$TRE" | head -1)
    [ -n "$term" ] && { echo "$L IPHONE_END poll+$(el "$tc")s after cancel :: $(echo "$term" | cut -c1-120)"; break; }; sleep 1
  done; [ -z "$term" ] && echo "$L IPHONE_END none within 20s"
fi
sleep 6; bash docker-ws/pixel_ui_texts.sh "$S" > "$D/${L}_caller_end.txt" 2>&1
/claude-host-bin/host-run bash docker-ws/calls28_tail_from.sh "$F" "$base" '.' > "$D/${L}_ios_syslog_window.txt"
echo "ios window lines: $(wc -l < "$D/${L}_ios_syslog_window.txt")"
M > "$D/${L}_relay_after.txt"
awk 'FNR==NR{ if ($NF ~ /^[0-9]+$/) b[$1]=$NF; next } ($NF ~ /^[0-9]+$/) { d=$NF-($1 in b ? b[$1] : 0); if (d) print "relay delta", $1, "+"d }' "$D/${L}_relay_before.txt" "$D/${L}_relay_after.txt"
