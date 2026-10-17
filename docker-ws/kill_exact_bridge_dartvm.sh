#!/bin/bash
# Stop leftover Flutter tool processes by exact PID, only when each is dartvm and a direct child of the given bridge PID.
#   host-run bash docker-ws/kill_exact_bridge_dartvm.sh <bridge-pid> <pid>...
set -u
BRIDGE="${1:?bridge pid}"; shift
for PID in "$@"; do
  [[ "$PID" =~ ^[0-9]+$ ]] || { echo "refused: $PID not numeric"; continue; }
  NAME="$(ps -o comm= -p "$PID" 2>/dev/null)"; PARENT="$(ps -o ppid= -p "$PID" 2>/dev/null | tr -d ' ')"
  case "$NAME" in */dartvm|dartvm) ;; *) echo "refused: $PID is not dartvm"; continue ;; esac
  [[ "$PARENT" == "$BRIDGE" ]] || { echo "refused: $PID parent is not the bridge"; continue; }
  kill "$PID" && echo "TERM $PID"
done
sleep 3
for PID in "$@"; do ps -p "$PID" >/dev/null 2>&1 && echo "still running $PID"; done
echo done
