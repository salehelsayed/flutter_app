#!/bin/bash
# Read-only call-line capture from one iPhone syslog (FLOW CALL/P2P events, CallKit/PushKit diag, mic/audio session lines).
#   host-run bash docker-ws/calls31_ios_syslog.sh <11|13> <out-file-in-repo> <max-secs>   (stops early when <out>.stop exists)
REPO="$(cd "$(dirname "$0")/.." && pwd)"; O="$REPO/$2"; N="${3:-3600}"
case "$1" in 11) U=00008030-001A6D2801BB802E ;; 13) U=00008110-00184D622289801E ;; *) echo "phone?"; exit 2 ;; esac
BIN="$(command -v idevicesyslog || echo /opt/homebrew/bin/idevicesyslog)"
mkdir -p "$(dirname "$O")"
"$BIN" -u "$U" --no-colors 2>/dev/null > >(grep --line-buffered -E '"event":"(CALL_|NETWORK_|P2P_|PRESENCE_|CHAT_|MESSAGE)|\[FLOW\]|MKNOON_|CXProvider|reportNewIncoming|didReceiveIncomingPush|PushKit|pushkit|Runner\(.*(AVAudioSession|audio session|mic)|callservicesd.*(com.mknoon|mknoon)' > "$O") &
P=$!; echo "capturing pid=$P"   # P is idevicesyslog itself, so the kill below stops the capture
t=0; while [ "$t" -lt "$N" ] && [ ! -f "$O.stop" ]; do sleep 5; t=$((t+5)); done
kill "$P" 2>/dev/null; rm -f "$O.stop"; sleep 1
echo "done lines=$(wc -l < "$O")"
