#!/bin/bash
# Read-only: recent Runner log lines from a booted simulator (flutter, error and FLOW lines only).
#   host-run bash docker-ws/sim_app_log.sh <sim-udid> <minutes>
xcrun simctl spawn "${1:?udid}" log show --last "${2:-5}m" --style compact --predicate 'process == "Runner"' 2>/dev/null \
  | grep -E 'flutter|Flutter|error|Error|FLOW|exception|Exception|migrat' | tail -40 | cut -c1-240
