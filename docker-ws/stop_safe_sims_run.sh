#!/bin/bash
# Stop one docker-ws/run_sims_safe.py run by exact PID: verifies the launcher's command line, then sends TERM to
# each exact descendant PID (deepest first) and finally the launcher. Nothing is matched by name pattern.
#   host-run bash docker-ws/stop_safe_sims_run.sh <launcher-python-pid>
set -u
L="${1:?launcher pid}"; [[ "$L" =~ ^[0-9]+$ ]] || exit 2
ARGS="$(ps -o args= -p "$L" 2>/dev/null)"
case "$ARGS" in *docker-ws/run_sims_safe.py*) ;; *) echo "refused: $L is not run_sims_safe.py"; exit 2;; esac
collect() { local c; for c in $(pgrep -P "$1"); do collect "$c"; echo "$c"; done; }
PIDS="$(collect "$L")"
for P in $PIDS; do kill -TERM "$P" 2>/dev/null && echo "TERM $P $(ps -o comm= -p "$P" 2>/dev/null | xargs basename 2>/dev/null)"; done
kill -TERM "$L" && echo "TERM $L launcher"
sleep 8
for P in $PIDS $L; do ps -p "$P" >/dev/null 2>&1 && echo "still running $P"; done
echo done
