#!/bin/bash
# Read-only: iPhone app log lines matching a regex between two local times today.
# Usage: r2_ios_grep.sh <from HH:MM:SS> <to HH:MM:SS> <regex> [max]
. "$(dirname "$0")/beta_env.sh"
D=$(date +%Y-%m-%d)
xcrun simctl spawn "$UDID" log show --start "$D $1" --end "$D $2" --style compact --predicate 'process == "Runner"' 2>/dev/null \
  | grep -E "$3" | sed -E 's/^([0-9-]+ )?([0-9:.]{12}).*"event":"([A-Z_:a-z]+)","details":(.{0,250}).*/\2 \3 \4/' | cut -c1-300 | head -${4:-40}
