#!/bin/bash
# Read-only: capture call and push-delivery lines from the iPhone 13 syslog for N seconds, reconnecting if
# idevicesyslog drops (the 10-27 capture had a 7-minute gap). Keeps Runner FLOW CALL_ events, the uppercase
# [MKNOON_PUSHKIT_DIAG]/[MKNOON_CALLKIT_DIAG] diagnostics, CallKit/PushKit framework lines and apsd/APNs
# delivery status for the app's topics. Long hex runs (tokens, ids) are redacted; no message content is kept.
#   host-run bash docker-ws/ios13_call_capture.sh <out-file-in-repo> <secs>
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"; O="$REPO/${1:?out}"; N="${2:-3600}"; U=00008110-00184D622289801E
BIN="$(command -v idevicesyslog || echo /opt/homebrew/bin/idevicesyslog)"
RX='"event":"CALL_|MKNOON_PUSHKIT_DIAG|MKNOON_CALLKIT_DIAG|CXProvider|CXCallController|callservicesd.*[Cc]all|PushKit|pushkit|didReceiveIncomingPush|reportNewIncoming|apsd.*(com\.mknoon|voip|[Dd]eliver|[Rr]eceived message|topic)'
mkdir -p "$(dirname "$O")"; : > "$O"
END=$(( $(date +%s) + N ))
while [ "$(date +%s)" -lt "$END" ]; do
  echo "== capture (re)start $(date -u +%H:%M:%SZ)" >> "$O"
  LEFT=$(( END - $(date +%s) ))
  timeout "$LEFT" "$BIN" -u "$U" --no-colors 2>/dev/null \
    | grep --line-buffered -E "$RX" \
    | sed -u -E 's/[0-9A-Fa-f]{24,}/<hex>/g' >> "$O"
  sleep 2
done
echo "lines=$(wc -l < "$O") restarts=$(grep -c '^== capture' "$O")"
