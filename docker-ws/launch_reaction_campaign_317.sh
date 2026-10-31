#!/usr/bin/env bash
# Detached launcher for the TC-317-13 campaign gate: survives the host-run
# bridge returning, logs to a repo-shared file, and first reaps any campaign
# processes left by an aborted bridge-bound attempt.
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
LOG="docker-ws/campaign_317_run.log"
stop_matching 'run_reaction_campaign_315.sh'
stop_matching 'run_with_devices.sh major --only groups.reaction_notification_campaign'
stop_matching 'run_group_reaction_notification_sims.dart'
sleep 2
: > "$LOG"
nohup bash -c 'bash docker-ws/run_reaction_campaign_315.sh >> docker-ws/campaign_317_run.log 2>&1; echo "CAMPAIGN_EXIT=$?" >> docker-ws/campaign_317_run.log' >/dev/null 2>&1 &
echo "campaign launched detached: pid $!, log $LOG"
