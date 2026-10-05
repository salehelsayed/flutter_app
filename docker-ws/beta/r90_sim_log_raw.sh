#!/bin/bash
# Read-only: raw Runner log lines matching a regex on one simulator between two local times.
U=$1; S=$2; E=$3; R=$4
xcrun simctl spawn "$U" log show --start "$S" --end "$E" --predicate 'process == "Runner"' --style compact 2>/dev/null \
  | grep -E "$R" | cut -c1-400
