#!/bin/bash
# Kill stray idevicesyslog / devicectl --console capture processes on the Mac.
# Orphaned captures hold the libimobiledevice syslog relay, so a later capture
# connects but receives nothing (observed 2026-08-21).
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
echo "before:"; pgrep -fl 'idevicesyslog' || echo "  (none)"
stop_matching 'idevicesyslog'
sleep 2
echo "after:"; pgrep -fl 'idevicesyslog' || echo "  (none)"
