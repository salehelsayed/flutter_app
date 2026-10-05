#!/bin/bash
# Read-only: automation drivers (Maestro, Appium/UiAutomator) running on each Android device, with start times.
. "$(dirname "$0")/beta_env.sh"
for s in 21071FDF600CSC emulator-5554 emulator-5556 emulator-5558; do
  echo "== $s"; $ADB -s $s shell ps -A -o PID,STIME,NAME 2>/dev/null | grep -E "maestro|appium|uiautomator|instrument" | tr -d '\r'
done
