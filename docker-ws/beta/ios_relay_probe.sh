#!/bin/bash
# Read-only: which relay address the iPhone simulator app used in the last N minutes
# (log lines naming the old or new relay address or the relay host name).
. "$(dirname "$0")/beta_env.sh"
M=${1:-10}
L=$(xcrun simctl spawn "$UDID" log show --last ${M}m --style compact --predicate 'process == "Runner"' 2>/dev/null)
echo "log lines in the last ${M}m: $(printf '%s\n' "$L" | wc -l | tr -d ' ')"
echo "old 13.60.250.19: $(printf '%s\n' "$L" | grep -c '13\.60\.250\.19')  new 51.21.194.144: $(printf '%s\n' "$L" | grep -c '51\.21\.194\.144')"
printf '%s\n' "$L" | grep -E "13\.60\.250\.19|51\.21\.194\.144|mknoun\.xyz|[Rr]elay (connect|reserv|dial)|RELAY_" | tail -6 | cut -c1-240
