#!/bin/bash
# Read-only: which processes on the Mac are driving the Pixel emulator (emulator-5556) or the iPhone 15 simulator.
. "$(dirname "$0")/beta_env.sh"
echo "now $(date '+%H:%M:%S')"
echo "=== processes naming emulator-5556 / 5556 / the iPhone 15 UDID"
ps -axo pid,ppid,etime,command | grep -E "emulator-5556|-s 5556|:5556|$UDID" | grep -v -e grep -e r23_who | cut -c1-260
echo "=== flutter / maestro / gradle / xcodebuild / adb install processes"
ps -axo pid,ppid,etime,command | grep -E "flutter_tools|maestro|gradle.*connected|xcodebuild|adb .*install|pm install|simctl (install|launch|terminate)|integration_test|run_test_gates|run_host_test_gates" | grep -v -e grep -e r23_who | cut -c1-260 | head -30
echo "=== adb devices"; $ANDROID_HOME/platform-tools/adb devices -l
echo "=== booted sims"; xcrun simctl list devices booted | grep -v '^=='
