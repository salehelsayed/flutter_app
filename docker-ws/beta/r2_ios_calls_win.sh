#!/bin/bash
# Read-only: iPhone CALL_STATE_TRANSITION / media events between two local times today.
. "$(dirname "$0")/beta_env.sh"
D=$(date +%Y-%m-%d)
xcrun simctl spawn "$UDID" log show --start "$D $1" --end "$D $2" --style compact --predicate 'process == "Runner"' 2>/dev/null \
  | grep -E '"event":"(CALL_STATE_TRANSITION|CALL_TERMINAL_CLEANUP_RESULT|CALL_AUDIO_START_RESULT|CALL_MEDIA[A-Z_]*)"' \
  | grep -vE '"trigger":"(remoteIce|iceCandidateHandled)"' \
  | sed -E 's/^([0-9-]+ )?([0-9:.]{12}).*"event":"([A-Z_]+)","details":(.{0,160}).*/\2 \3 \4/' | head -${3:-40}
