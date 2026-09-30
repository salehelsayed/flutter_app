#!/bin/bash
# Read-only: all iPhone app FLOW/diag lines in a short window (HH:MM:SS.s to HH:MM:SS.s today).
. "$(dirname "$0")/beta_env.sh"
D=$(date +%Y-%m-%d)
xcrun simctl spawn "$UDID" log show --start "$D $1" --end "$D $2" --style compact --predicate 'process == "Runner"' 2>/dev/null \
  | grep -E '"event":|CALL|call' | grep -vE "remoteIce|iceCandidate|PEER_PING|xctest" \
  | sed -E 's/^([0-9-]+ )?([0-9:.]{12}).*"event":"([A-Z_:a-z]+)","details":(.{0,200}).*/\2 \3 \4/' | cut -c1-240 | head -${3:-40}
