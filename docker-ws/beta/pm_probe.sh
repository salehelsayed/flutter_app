#!/bin/bash
# Read-only: why is pm install on emulator-5556 slow? Emulator uptime/load, top
# processes, and recent package manager / installer / dexopt log lines.
. "$(dirname "$0")/beta_env.sh"
echo "--- emulator uptime/load"; timeout 30 $ADB shell uptime 2>&1
echo "--- emulator top"; timeout 30 $ADB shell top -b -n 1 -m 8 2>&1 | tail -10 | cut -c1-120
echo "--- install sessions"; timeout 30 $ADB shell cmd package list sessions 2>&1 | head -8
echo "--- recent package manager lines"
timeout 60 $ADB logcat -d -v time 2>/dev/null | grep -iE "PackageManager|PackageInstaller|installd|dex2oat|artd|Watchdog|ANR in" | tail -25 | cut -c1-200
