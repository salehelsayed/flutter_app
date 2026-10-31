#!/bin/bash
# Batch C VC-014: Pixel (already in chat with iphone-13) dials, then poll the iPhone 13 call syslog capture for the CallKit
# incoming report. Prints RING yes/no with seconds from dial. Leaves the call ringing for the caller of this script.
#   bash docker-ws/vcC_dial_wait.sh <label> <capture-file-in-repo> [max-secs]
cd "$(dirname "$0")/.." || exit 2
export ADB_SERVER_SOCKET=${ADB_SERVER_SOCKET:-tcp:host.docker.internal:5037}
L="$1"; F="$2"; MAX="${3:-45}"; S=21071FDF600CSC
RE="reportNewIncomingCallWithUUID|Received add incoming call"
base=$(/claude-host-bin/host-run bash docker-ws/calls28_mgrep.sh "$F" "^$" 1 | sed -n "s/.*lines=//p")
echo "$L base=$base"
bash docker-ws/pixel_ui_texts.sh "$S" | grep -q "Start voice call" || { echo "CALLER NOT IN CHAT"; exit 3; }
el() { awk -v a="$1" -v b="$(date +%s.%N)" "BEGIN{printf \"%.1f\", b-a}"; }
t0=$(date +%s.%N); echo "$L dial $(date -u +%FT%T.%3NZ)"
bash docker-ws/pixel_tap_desc.sh "$S" "Start voice call" >/dev/null
while [ "$(el "$t0" | cut -d. -f1)" -lt "$MAX" ]; do
  h=$(/claude-host-bin/host-run bash docker-ws/calls28_tail_from.sh "$F" "$base" "$RE" | head -1)
  [ -n "$h" ] && { echo "$L RING yes poll+$(el "$t0")s at $(date -u +%T.%3NZ)"; exit 0; }
  sleep 1
done
echo "$L RING no within ${MAX}s"; exit 1
