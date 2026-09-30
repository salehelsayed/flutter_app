#!/bin/bash
# Read-only snapshot of the two beta devices before an R2-9 run: emulator uptime, installed build, app process,
# full-screen access, screen state, emulator clock offset (bracketed), Mac load, and other sessions' tools.
. "$(dirname "$0")/beta_env.sh"
echo "mac time: $(date '+%Y-%m-%d %H:%M:%S') load: $(sysctl -n vm.loadavg)"
echo "emulator uptime: $($ADB shell cat /proc/uptime | tr -d '\r' | awk '{printf "%.0f s (%.1f h)", $1, $1/3600}')"
echo "emulator qemu processes: $(ps -axo pid,etime,command | grep -E 'qemu-system|emulator' | grep -v grep | grep 5556 | cut -c1-200)"
echo "installed: $($ADB shell dumpsys package $PKG | grep -E -m3 'versionName|lastUpdateTime|firstInstallTime' | tr -d '\r' | tr -s ' ' | tr '\n' ' ')"
echo "data inode: $($ADB shell dumpsys package $PKG | grep -m1 -oE 'ceDataInode=[0-9]+' | tr -d '\r') $($ADB shell dumpsys package $PKG | grep -m1 -oE 'stopped=(true|false)' | tr -d '\r')"
echo "app pid: '$($ADB shell pidof $PKG | tr -d '\r')'"
echo "full-screen access: $($ADB shell cmd appops get $PKG USE_FULL_SCREEN_INTENT | tr -d '\r' | tr '\n' ' ')"
echo "screen: $($ADB shell dumpsys power | grep -m1 -oE 'mWakefulness=[A-Za-z]+' | tr -d '\r')"
for i in 1 2 3; do
  a=$(python3 -c 'import time; print(f"{time.time():.3f}")')
  e=$($ADB shell date +%s.%N | tr -d '\r' | cut -c1-14)
  b=$(python3 -c 'import time; print(f"{time.time():.3f}")')
  python3 -c "import sys; a,e,b=map(float,sys.argv[1:]); print(f'clock offset emulator-mac: {e-(a+b)/2:+.2f} s (adb round trip {b-a:.2f} s)')" "$a" "$e" "$b"
done
echo "automatic time: $($ADB shell settings get global auto_time | tr -d '\r')"
echo "iphone booted: $(xcrun simctl list devices booted | grep -c "$UDID") ios build: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$(xcrun simctl get_app_container "$UDID" "$BUNDLE" app)/Info.plist" 2>/dev/null)"
echo "maestro processes: $(ps -axo command | grep -E 'maestro' | grep -vc grep)  appium: $(ps -axo command | grep -iE 'appium' | grep -vc grep)"
echo "mknoon_checks / flutter test / gradle runs: $(ps -axo command | grep -E 'mknoon_checks|flutter_tools.snapshot test|GradleDaemon|xcodebuild' | grep -v grep | cut -c1-140 | sort | uniq -c | head -8 | tr '\n' ';')"
echo "other-session apk last save: $(cat "$BETA/other-session-apk/last.txt" 2>/dev/null)"
bash "$(dirname "$0")/r28_busy_check.sh" "${1:-30}"
