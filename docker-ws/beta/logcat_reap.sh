#!/bin/bash
# Stop every beta logcat stream for emulator-5556 (left behind by stopped runs).
. "$(dirname "$0")/beta_env.sh"
pkill -f "adb -s $SERIAL logcat" 2>/dev/null
sleep 1; echo "logcat streams left: $(pgrep -f "adb -s $SERIAL logcat" | wc -l | tr -d ' ')"
