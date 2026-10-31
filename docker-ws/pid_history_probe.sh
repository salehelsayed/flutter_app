#!/bin/bash
# Read-only: unified log lines about one PID in the last N minutes (process exits, launchd). No kills.
#   host-run bash docker-ws/pid_history_probe.sh <pid> <minutes>
P="${1:?pid}"; M="${2:-15}"
[[ "$P" =~ ^[0-9]+$ ]] || exit 2
log show --last "${M}m" --style compact --predicate "processID == $P OR eventMessage CONTAINS[c] \"pid $P\" OR eventMessage CONTAINS \"[$P]\"" 2>/dev/null | tail -15 | cut -c1-220
