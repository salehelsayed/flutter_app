#!/usr/bin/env bash
# Detached launcher for the curated groups lane (host toolchains).
#
# Reaps any in-flight lane FIRST: without this, a relaunch silently leaves the
# previous lane running, both append to this one log, and they compete for CPU
# — which manifests as phantom timing failures in wall-clock tests and makes
# LANE_EXIT unattributable (observed 2026-08-01, plan 319).
set -u
LOG="docker-ws/groups_lane_318_run.log"

pkill -f 'run_test_gates.sh groups' 2>/dev/null
pkill -f 'flutter_tools.snapshot test' 2>/dev/null
sleep 3
if pgrep -f 'run_test_gates.sh groups' >/dev/null 2>&1; then
  echo "REFUSING: a groups lane is still alive after the reap"
  exit 2
fi

: > "$LOG"
nohup bash -c 'bash ./scripts/run_test_gates.sh groups >> docker-ws/groups_lane_318_run.log 2>&1; echo "LANE_EXIT=$?" >> docker-ws/groups_lane_318_run.log' >/dev/null 2>&1 &
echo "groups lane launched detached: pid $!, log $LOG"
