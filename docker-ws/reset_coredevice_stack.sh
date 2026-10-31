#!/bin/bash
# Reset the user-level CoreDevice stack: kill lingering devicectl calls and the
# user-owned CoreDeviceService / remotepairingd XPC daemons (launchd respawns
# them on demand with fresh tunnel state). Fixes a zombied per-device tunnel
# that reports "connected" while every RPC hangs (iPhone 13, 2026-07-20).
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
# Exact process name (basename of the executable). Kills by PID after re-checking that PID's executable.
stop_named() {
  local name="$1" pids pid c n=0
  pids=$(ps -axo pid=,comm= | awk -v n="$name" '{pid=$1; $1=""; sub(/^ +/,""); k=split($0,a,"/"); if (a[k]==n) print pid}')
  for pid in $pids; do
    c=$(ps -o comm= -p "$pid" 2>/dev/null)
    case "$c" in "$name"|*/"$name") kill "$pid" 2>/dev/null && { echo "stopped $pid: $c"; n=$((n+1)); };; esac
  done
  [ "$n" -gt 0 ]
}
stop_matching 'devicectl device' && echo "killed lingering devicectl calls" || echo "no lingering devicectl calls"
stop_named CoreDeviceService && echo "killed CoreDeviceService" || echo "CoreDeviceService not running"
if [ "${RESET_REMOTEPAIRING:-0}" = "1" ]; then
  stop_named remotepairingd && echo "killed remotepairingd" || echo "remotepairingd not running"
fi
exit 0
