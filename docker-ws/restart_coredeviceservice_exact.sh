#!/bin/bash
# Restart only the current user's CoreDeviceService XPC daemon by exact PID (launchd respawns it on demand).
#   host-run bash docker-ws/restart_coredeviceservice_exact.sh
P=$(pgrep -x -u "$(id -u)" CoreDeviceService)
[ -n "$P" ] || { echo "CoreDeviceService not running"; exit 0; }
for pid in $P; do
  [ "$(ps -o comm= -p "$pid" | xargs basename)" = CoreDeviceService ] || { echo "refused $pid"; continue; }
  kill "$pid" && echo "TERM CoreDeviceService $pid"
done
sleep 3
echo "now: $(pgrep -x -u "$(id -u)" CoreDeviceService | tr '\n' ' ')"
