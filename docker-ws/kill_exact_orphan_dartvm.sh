#!/bin/bash
# Stop orphaned Flutter tool processes by exact PID. Each must be dartvm, parented by launchd,
# have the main checkout as cwd, and have started inside the given local-time window.
#   host-run bash docker-ws/kill_exact_orphan_dartvm.sh [--kill] <cwd> <window-start YYYYmmddHHMMSS> <window-end> <pid>...
set -u
SIG=TERM; [[ "${1:-}" == --kill ]] && { SIG=KILL; shift; }
CWD="$1"; FROM="$2"; TO="$3"; shift 3
for PID in "$@"; do
  [[ "$PID" =~ ^[0-9]+$ ]] || { echo "refused: $PID not numeric"; continue; }
  NAME="$(ps -o comm= -p "$PID" 2>/dev/null)"; PARENT="$(ps -o ppid= -p "$PID" 2>/dev/null | tr -d ' ')"
  case "$NAME" in */dartvm|dartvm) ;; *) echo "refused: $PID not dartvm"; continue ;; esac
  [[ "$PARENT" == 1 ]] || { echo "refused: $PID not orphaned"; continue; }
  PCWD="$(lsof -a -p "$PID" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')"
  [[ "$PCWD" == "$CWD" ]] || { echo "refused: $PID cwd differs"; continue; }
  START="$(date -j -f '%a %b %d %T %Y' "$(ps -o lstart= -p "$PID" | sed 's/  */ /g;s/ $//')" +%Y%m%d%H%M%S 2>/dev/null)"
  [[ -n "$START" && "$START" -ge "$FROM" && "$START" -le "$TO" ]] || { echo "refused: $PID start $START outside window"; continue; }
  kill -s "$SIG" "$PID" && echo "$SIG $PID"
done
sleep 3
for PID in "$@"; do ps -p "$PID" >/dev/null 2>&1 && echo "still running $PID"; done
echo done
