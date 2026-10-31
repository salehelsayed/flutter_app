#!/bin/bash
# Read-only: unified log lines from launchd in the last N minutes that mention a given pid (exits/respawns).
#   host-run bash docker-ws/mac_pid_log_probe.sh <pid> [minutes]
P="${1:?pid}"; M="${2:-90}"
[[ "$P" =~ ^[0-9]+$ ]] || exit 2
echo "now: $(date)  max pid seen: $(ps -axo pid= | sort -n | tail -1)  lowest user pid>100: $(ps -axo pid= | sort -n | awk '$1>100' | head -1)"
ps -o pid,ppid,lstart,comm -p "$P" 2>/dev/null || echo "pid $P not running now"
log show --last "${M}m" --style compact --predicate "process == \"launchd\" AND (eventMessage CONTAINS \"[$P]\" OR eventMessage CONTAINS \"pid $P \" OR eventMessage CONTAINS \"pid = $P\")" 2>/dev/null | head -20
