#!/bin/bash
# Plan 414: stop this worktree's lane chain and any flutter test it started.
# Stop processes by exact PID only: list via ps, filter on the literal command text, re-check that PID's command line, then kill <pid>. No pattern kills.
stop_matching() {  # $1 = text the command line must contain, $2 = optional second text it must also contain
  local pat="$1" pat2="${2:-}" pids pid n=0 a
  pids=$(ps -axo pid=,args= | awk -v pat="$pat" -v pat2="$pat2" -v me="$$" '$1!=me && $2!~/(^|\/)(awk|ps|grep|pgrep)$/ && index($0,pat) && (pat2=="" || index($0,pat2)) {print $1}')
  for pid in $pids; do
    a=$(ps -o args= -p "$pid" 2>/dev/null)
    case "$a" in *"$pat"*) case "$a" in *"$pat2"*) kill "$pid" 2>/dev/null && { echo "stopped $pid: ${a:0:100}"; n=$((n+1)); };; esac;; esac
  done
  [ "$n" -gt 0 ]
}
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
stop_matching "$ROOT/docker-ws/pdf414_lanes.sh"
stop_matching "$ROOT/docker-ws/pdf414_lane.sh"
stop_matching "$ROOT/scripts/run_test_gates.sh"
sleep 3
stop_matching "flutter_tools.snapshot test" "pdf-407"
sleep 2
pgrep -fl "$ROOT/scripts/run_test_gates.sh|pdf414_lane" || echo "no lanes left"
