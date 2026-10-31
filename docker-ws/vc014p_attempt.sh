#!/bin/bash
# VC-014 production-APNs round: caller emulator (in chat with iphone-13) dials; poll the iPhone 13 syslog capture (Mac side)
# for the CallKit incoming report; then end the call from the caller. Relay /metrics (read-only) before and after.
#   bash docker-ws/vc014p_attempt.sh <label> [max-secs]
cd "$(dirname "$0")/.." || exit 2
L="$1"; MAX="${2:-45}"; S=${CALLER:-emulator-5560}; D=.codex-test-logs/vc014-prodapns-20261028; F=$D/ios13_syslog.txt
RE='reportNewIncomingCallWithUUID|Received add incoming call'
M() { RELAY_SSH_HOST=51.21.194.144 timeout 90 python3 docker-ws/relay_ssh.py < docker-ws/vc014/aws_metrics.sh 2>&1 | grep -E 'Z$|outcome="sent"|call_store_v1|invalid_token|sent_cross'; }
M > "$D/${L}_relay_before.txt"
base=$(/claude-host-bin/host-run bash docker-ws/calls28_mgrep.sh "$F" '^$' 1 | sed -n 's/.*lines=//p')
bash docker-ws/pixel_ui_texts.sh "$S" | grep -q 'Start voice call' || { echo "CALLER NOT IN CHAT"; exit 3; }
t0=$(date +%s.%N); echo "$L dial $(date -u +%FT%T.%3NZ)" | tee "$D/${L}_dial.txt"
bash docker-ws/pixel_tap_desc.sh "$S" "Start voice call" >/dev/null
hit=""
while [ "$(awk -v a="$t0" -v b="$(date +%s.%N)" 'BEGIN{print int(b-a)}')" -lt "$MAX" ]; do
  h=$(/claude-host-bin/host-run bash docker-ws/calls28_tail_from.sh "$F" "$base" "$RE" | head -1)
  if [ -n "$h" ]; then hit="$h"; el=$(awk -v a="$t0" -v b="$(date +%s.%N)" 'BEGIN{printf "%.1f", b-a}'); break; fi
  sleep 1
done
if [ -n "$hit" ]; then echo "$L RING yes poll+${el}s :: $hit" | tee "$D/${L}_ring.txt"; sleep 5
else echo "$L RING no within ${MAX}s" | tee "$D/${L}_ring.txt"; fi
bash docker-ws/pixel_ui_texts.sh "$S" > "$D/${L}_caller_after.txt" 2>&1
C=$(grep -oE 'content-desc="(Cancel call|End call|End|Hang up)"' "$D/${L}_caller_after.txt" | head -1)
[ -n "$C" ] && bash docker-ws/pixel_tap_desc.sh "$S" "$C" >/dev/null && echo "$L caller end tapped $(date -u +%T) ($C)"
sleep 8; bash docker-ws/pixel_ui_texts.sh "$S" > "$D/${L}_caller_end.txt" 2>&1
/claude-host-bin/host-run bash docker-ws/calls28_tail_from.sh "$F" "$base" '.' > "$D/${L}_ios_syslog_window.txt"
echo "ios window lines: $(wc -l < "$D/${L}_ios_syslog_window.txt")"
M > "$D/${L}_relay_after.txt"
paste <(grep -oE '\{[^}]*\} [0-9]+' "$D/${L}_relay_before.txt") <(grep -oE ' [0-9]+$' "$D/${L}_relay_after.txt") | awk '{d=$3-$2; if(d) print "relay delta", $1, "+"d}'
