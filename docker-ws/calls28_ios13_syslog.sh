#!/bin/bash
# Read-only call-line capture from the iPhone 13 syslog (FLOW CALL events, CallKit/PushKit diag, apsd VoIP delivery).
#   host-run bash docker-ws/calls28_ios13_syslog.sh <out-file-in-repo> <max-secs>   (stops early when <out>.stop exists)
REPO="$(cd "$(dirname "$0")/.." && pwd)"; O="$REPO/$1"; N="${2:-3600}"; U=00008110-00184D622289801E
BIN="$(command -v idevicesyslog || echo /opt/homebrew/bin/idevicesyslog)"
mkdir -p "$(dirname "$O")"
"$BIN" -u "$U" --no-colors 2>/dev/null | grep --line-buffered -E '"event":"CALL_|MKNOON_CALL|CXProvider|reportNewIncoming|didReceiveIncomingPush|PushKit|pushkit|apsd.*(voip|VoIP|com.mknoon)|callservicesd.*(com.mknoon|mknoon)|ApplePushService.*(deliver message|didReceiveIncomingMessage)|Received add incoming call|apsd\[[0-9]+\] <Notice>|ApplePushService' > "$O" &
P=$!; echo "capturing pid=$P"
t=0; while [ "$t" -lt "$N" ] && [ ! -f "$O.stop" ]; do sleep 5; t=$((t+5)); done
kill "$P" 2>/dev/null; rm -f "$O.stop"; sleep 1
echo "done lines=$(wc -l < "$O")"
