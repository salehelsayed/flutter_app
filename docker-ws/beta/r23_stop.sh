#!/bin/bash
# Stop the R2-3 device run (only this run's processes: the runner, its flow wrappers, its Maestro sessions, its logcat).
. "$(dirname "$0")/beta_env.sh"
RUN=$(current_run); TAG=$(basename "$RUN")
echo "stopping run $TAG"
pkill -f "run_r23_validate.sh" && echo "runner stopped"
pkill -f "pair.sh V4_" ; pkill -f "run_flow.sh .*V4_"
pkill -f "$TAG" && echo "maestro sessions of $TAG stopped"
kill "$(cat "$RUN/logcat.pid")" 2>/dev/null && echo "logcat stopped"
sleep 2
ps -axo pid,command | grep -E "$TAG|run_r23_validate" | grep -v grep | cut -c1-160
echo "[$(date '+%H:%M:%S')] R23 VALIDATE STOPPED by hand: another session drives the same Pixel via Appium (force-stop + reinstall every few minutes)" >> "$RUN/timeline.txt"
