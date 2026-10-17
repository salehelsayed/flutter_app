#!/bin/bash
# Stop ONE hung devicectl process by exact PID, only after verifying the PID is devicectl.
#   host-run bash docker-ws/kill_exact_devicectl.sh <pid>
set -u
PID="${1:?pid}"
[[ "$PID" =~ ^[0-9]+$ ]] || { echo "refused: pid must be numeric" >&2; exit 2; }
NAME="$(ps -o comm= -p "$PID" 2>/dev/null)"
case "$NAME" in
  */devicectl|devicectl) ;;
  *) echo "refused: pid $PID is not devicectl" >&2; exit 2 ;;
esac
kill "$PID" && echo "sent TERM to devicectl $PID"
sleep 3
ps -p "$PID" >/dev/null 2>&1 && echo "still running" || echo "gone"
