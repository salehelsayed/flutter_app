#!/bin/bash
# Why does adb install hang on emulator-5556? Free space, then push and install as
# separate, timed steps (push to /data/local/tmp, then pm install from there).
. "$(dirname "$0")/beta_env.sh"
APK="$BETA/build/beta-android-b8.apk"
echo "--- emulator storage"
timeout 30 $ADB shell df -h /data 2>&1 | tail -2
echo "--- stale temp APKs"
timeout 30 $ADB shell 'ls -la /data/local/tmp/*.apk 2>/dev/null | tail -5'
echo "--- push ($(du -h "$APK" | cut -f1))"
t0=$(date +%s)
timeout 300 $ADB push "$APK" /data/local/tmp/beta-b8.apk 2>&1 | tail -1
echo "push rc=$? in $(( $(date +%s) - t0 )) s"
echo "--- pm install"
t0=$(date +%s)
timeout 300 $ADB shell pm install -r -d /data/local/tmp/beta-b8.apk 2>&1 | tail -2
echo "install rc=$? in $(( $(date +%s) - t0 )) s"
timeout 30 $ADB shell rm -f /data/local/tmp/beta-b8.apk
echo "installed: $(timeout 30 $ADB shell dumpsys package $PKG | grep -m1 versionName | tr -d ' ')"
