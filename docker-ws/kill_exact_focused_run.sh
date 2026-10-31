#!/bin/bash
# Stop ONE focused_in_tree.sh run by exact PID: the PID must be bash running docker-ws/focused_in_tree.sh with
# cwd inside the given tree. TERM its descendants (deepest first), then itself.
#   host-run bash docker-ws/kill_exact_focused_run.sh <pid> <tree under build/>
set -u
PID="${1:?pid}"; TREE="/Volumes/CrucialX9/flutter_app/build/${2:?tree}"
[[ "$PID" =~ ^[0-9]+$ ]] || { echo "refused: pid not numeric"; exit 2; }
ARGS="$(ps -o args= -p "$PID" 2>/dev/null)"
case "$ARGS" in *bash*docker-ws/focused_in_tree.sh*) ;; *) echo "refused: $PID is not a focused_in_tree.sh run"; exit 3 ;; esac
PCWD="$(lsof -a -p "$PID" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')"
case "$PCWD" in "$TREE"|"$TREE"/*) ;; *) echo "refused: cwd is not in $TREE"; exit 3 ;; esac
desc() { for c in $(pgrep -P "$1"); do desc "$c"; echo "$c"; done; }
KIDS="$(desc "$PID")"
for k in $KIDS; do kill -TERM "$k" 2>/dev/null && echo "TERM child $k"; done
kill -TERM "$PID" && echo "TERM $PID"
sleep 3
for p in $KIDS $PID; do ps -p "$p" >/dev/null 2>&1 && echo "still running $p"; done; exit 0
