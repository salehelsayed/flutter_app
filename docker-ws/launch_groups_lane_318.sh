#!/usr/bin/env bash
# Detached launcher for the curated groups lane (host toolchains).
#
# Reaps any in-flight lane FIRST: without this, a relaunch silently leaves the
# previous lane running, both append to this one log, and they compete for CPU
# — which manifests as phantom timing failures in wall-clock tests and makes
# LANE_EXIT unattributable (observed 2026-08-01, plan 319).
set -u
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
LOG="docker-ws/groups_lane_318_run.log"

stop_matching 'run_test_gates.sh groups'
stop_matching 'flutter_tools.snapshot test'
sleep 3
if pgrep -f 'run_test_gates.sh groups' >/dev/null 2>&1; then
  echo "REFUSING: a groups lane is still alive after the reap"
  exit 2
fi

: > "$LOG"
nohup bash -c 'bash ./scripts/run_test_gates.sh groups >> docker-ws/groups_lane_318_run.log 2>&1; echo "LANE_EXIT=$?" >> docker-ws/groups_lane_318_run.log' >/dev/null 2>&1 &
echo "groups lane launched detached: pid $!, log $LOG"
