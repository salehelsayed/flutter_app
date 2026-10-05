#!/bin/bash
# Read-only: the app's [FLOW] lines from one simulator between two local times.  r89_sim_flow_log.sh <udid> <start> <end> [regex]
U=$1; S=$2; E=$3; R=${4:-.}
xcrun simctl spawn "$U" log show --start "$S" --end "$E" --predicate 'process == "Runner"' --style compact 2>/dev/null \
  | grep -F '[FLOW]' | grep -E "$R" | sed -E 's/.*\[FLOW\] //' | cut -c1-330
