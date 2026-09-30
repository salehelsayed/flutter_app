#!/bin/bash
# Read-only: the vc204 lane process tree, its device, and adb clients per device.
ps -axo pid,ppid,etime,command | grep -E "run_vc204|vc204|connectedVc204|am instrument" | grep -v grep | cut -c1-220
echo "--- adb clients naming a device"
ps -axo pid,etime,command | grep -oE "adb -s [^ ]+ [a-z-]+( [a-z-]+)?" | sort | uniq -c | sort -rn | head -12
echo "--- installed mknoon build on emulator-5556"
"$HOME/Library/Android/sdk/platform-tools/adb" -s emulator-5556 shell dumpsys package com.mknoon.app 2>/dev/null | grep -E "versionName|lastUpdateTime" | head -3
