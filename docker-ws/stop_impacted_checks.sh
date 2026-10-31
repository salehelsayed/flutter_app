#!/bin/bash
# Stop one run_impacted_checks.sh run and its descendants by exact PID (name-checked root).
#   host-run bash docker-ws/stop_impacted_checks.sh <out dir under .codex-test-logs/>
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
R="$(cat "$REPO/${1:?out}/pid" 2>/dev/null)"; [[ "$R" =~ ^[0-9]+$ ]] || { echo "no pid"; exit 2; }
ps -o args= -p "$R" | grep -q 'run_impacted_checks.sh _run' || { echo "pid $R is not an impacted-checks run"; exit 2; }
tree() { echo "$1"; for c in $(pgrep -P "$1"); do tree "$c"; done; }
PIDS="$(tree "$R")"
kill -STOP $PIDS 2>/dev/null
for p in $PIDS; do echo "stop $p $(ps -o comm= -p "$p")"; done
kill -TERM $PIDS 2>/dev/null; kill -CONT $PIDS 2>/dev/null; sleep 2
for p in $PIDS; do ps -p "$p" >/dev/null 2>&1 && { kill -KILL "$p"; echo "killed $p"; }; done
echo "left: $(for p in $PIDS; do ps -p "$p" >/dev/null 2>&1 && echo "$p"; done)"
