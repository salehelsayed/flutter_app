#!/bin/bash
# Read-only: count app FLOW events by name in a time window of the current run's live logcat.
# Usage: r2_events.sh <from HH:MM:SS> <to HH:MM:SS> [name regex]
. "$(dirname "$0")/beta_env.sh"
RUN=$(current_run); L="$RUN/android_logcat_live.txt"
A=$1; B=$2; RX=${3:-.}
awk -v a="$A" -v b="$B" 'substr($2,1,8)>=a && substr($2,1,8)<=b' "$L" \
  | grep -oE '"event":"[A-Z0-9_]+"' | sed 's/"event"://; s/"//g' | grep -E "$RX" | sort | uniq -c | sort -rn | head -${4:-60}
