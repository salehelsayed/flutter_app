#!/bin/bash
# Read-only: can round 2 start? Host load/DNS, running tests, both phones and their builds.
H="$(cd "$(dirname "$0")" && pwd)"
. "$H/beta_env.sh"
echo "=== quiet"; bash "$H/quiet_check.sh"
echo "=== tests running"; bash "$H/tests_now.sh" | head -20
echo "=== memory"; vm_stat | awk '/free|inactive|speculative|compressor/ {print}' | head -6; sysctl -n vm.swapusage
echo "=== simulators booted"; xcrun simctl list devices booted | grep -v '^==' 
echo "=== ios app version"; /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$(xcrun simctl get_app_container "$UDID" "$BUNDLE" app)/Info.plist" 2>&1
echo "=== adb devices"; $ANDROID_HOME/platform-tools/adb devices -l
echo "=== android"; $ADB shell dumpsys package $PKG | grep -m1 versionName; $ADB shell 'pidof com.mknoon.app; getprop sys.boot_completed; cat /proc/meminfo | head -3'
echo "=== emulator procs"; ps -axo pid,etime,pcpu,rss,command | grep -E "qemu-system" | grep -v grep | cut -c1-160
echo "=== current run"; cat "$BETA/current_run.txt"
echo "=== builds dir"; ls -la "$BETA/build" | tail -25
