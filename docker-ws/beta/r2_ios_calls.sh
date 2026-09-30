#!/bin/bash
# Read-only: iPhone call-related log lines (state transitions, errors, relay refusals) in the last N minutes.
. "$(dirname "$0")/beta_env.sh"
xcrun simctl spawn "$UDID" log show --last ${1:-6}m --style compact --predicate 'process == "Runner"' 2>/dev/null \
  | grep -E '"event":"CALL_[A-Z_]+"' \
  | grep -vE "remoteIce|iceCandidate|CALL_DIAG" \
  | sed -E 's/^([0-9-]+ )?([0-9:.]{12}).*"event":"([A-Z_]+)","details":(.{0,230}).*/\2 \3 \4/' | tail -${2:-60}
