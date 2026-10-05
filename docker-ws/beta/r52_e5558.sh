#!/bin/bash
# Read-only: what runs on emulator-5558 (Pixel_8) and who started its qemu.
. "$(dirname "$0")/beta_env.sh"
S=emulator-5558
echo "uptime: $($ADB -s $S shell uptime | tr -d '\r')"
$ADB -s $S shell dumpsys activity activities | grep -E "mResumedActivity|topResumedActivity" | head -2 | tr -d '\r'
$ADB -s $S shell pm list packages -3 | tr -d '\r' | head -20
$ADB -s $S shell ps -A -o PID,STIME,NAME | grep -E "mknoon|maestro|appium|uiautomator" | tr -d '\r'
ps -axo pid,lstart,command | grep -E "qemu.*Pixel_8|avd Pixel_8" | grep -v grep | cut -c1-200
