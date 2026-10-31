#!/bin/bash
# Restart only the current user's remotepairingd daemon by exact PID (launchd respawns it on demand).
#   host-run bash docker-ws/restart_coredeviceservice_exact.sh
P=$(pgrep -x -u "$(id -u)" remotepairingd)
[ -n "$P" ] || { echo "remotepairingd not running"; exit 0; }
for pid in $P; do
  [ "$(ps -o comm= -p "$pid" | xargs basename)" = remotepairingd ] || { echo "refused $pid"; continue; }
  kill "$pid" && echo "TERM remotepairingd $pid"
done
sleep 3
echo "now: $(pgrep -x -u "$(id -u)" remotepairingd | tr '\n' ' ')"
