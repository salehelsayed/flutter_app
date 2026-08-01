#!/usr/bin/env bash
# Detached launcher for the plan-318 curated groups lane (host toolchains).
set -u
LOG="docker-ws/groups_lane_318_run.log"
: > "$LOG"
nohup bash -c 'bash ./scripts/run_test_gates.sh groups >> docker-ws/groups_lane_318_run.log 2>&1; echo "LANE_EXIT=$?" >> docker-ws/groups_lane_318_run.log' >/dev/null 2>&1 &
echo "groups lane launched detached: pid $!, log $LOG"
