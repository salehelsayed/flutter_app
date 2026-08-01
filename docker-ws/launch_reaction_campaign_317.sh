#!/usr/bin/env bash
# Detached launcher for the TC-317-13 campaign gate: survives the host-run
# bridge returning, logs to a repo-shared file, and first reaps any campaign
# processes left by an aborted bridge-bound attempt.
set -u
LOG="docker-ws/campaign_317_run.log"
pkill -f 'run_reaction_campaign_315.sh' 2>/dev/null
pkill -f 'run_with_devices.sh major --only groups.reaction_notification_campaign' 2>/dev/null
pkill -f 'run_group_reaction_notification_sims.dart' 2>/dev/null
sleep 2
: > "$LOG"
nohup bash -c 'bash docker-ws/run_reaction_campaign_315.sh >> docker-ws/campaign_317_run.log 2>&1; echo "CAMPAIGN_EXIT=$?" >> docker-ws/campaign_317_run.log' >/dev/null 2>&1 &
echo "campaign launched detached: pid $!, log $LOG"
