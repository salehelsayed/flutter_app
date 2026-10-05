#!/bin/bash
# Stop the Maestro driver left on the USB Pixel by this session's Maestro MCP use (O10, started 16:41 device time).
. "$(dirname "$0")/beta_env.sh"
for p in dev.mobile.maestro dev.mobile.maestro.test; do $ADB -s 21071FDF600CSC shell am force-stop $p; done
$ADB -s 21071FDF600CSC shell ps -A -o PID,STIME,NAME | grep -E "maestro" | tr -d '\r' || echo "no maestro process"
