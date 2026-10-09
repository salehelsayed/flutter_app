#!/bin/bash
# Read-only: who drives which device, and the physical Pixel 6 state.
. "$(dirname "$0")/../beta_env.sh"
A="$ANDROID_HOME/platform-tools/adb -s 21071FDF600CSC"
echo "WDA destinations:"
ps -axo pid,etime,command | grep -E 'xcodebuild build-for-testing' | grep -v grep | grep -oE 'id=[^ ,]+' | sort | uniq -c
echo "appium 4725 sessions: $(curl -s http://127.0.0.1:4725/sessions | cut -c1-400)"
echo "sims booted:"; xcrun simctl list devices booted | grep -v '^--\|^=='
echo "iphones: $(xcrun devicectl list devices 2>/dev/null | grep -E 'iPhone' | tr -s ' ' | cut -c1-120 | tr '\n' ';')"
echo "pixel6: $($A shell dumpsys package com.mknoon.app | grep -m1 versionName | tr -d ' \r') $($A shell dumpsys package com.mknoon.app | grep -m1 -oE 'lastUpdateTime=[0-9 :-]+' | tr -d '\r')"
echo "pixel6 secure: $($A shell dumpsys window policy | grep -m3 -E 'secure|showing' | tr -d '\r' | tr -s ' ' | tr '\n' ' ')"
echo "pixel6 power: $($A shell dumpsys power | grep -m1 -oE 'mWakefulness=[A-Za-z]+') sdk=$($A shell getprop ro.build.version.sdk | tr -d '\r') fsi=$($A shell cmd appops get com.mknoon.app USE_FULL_SCREEN_INTENT | head -1 | tr -d '\r')"
now=$($A shell date +%s | tr -d '\r')
since=$($A shell date -d "@$(( now - 600 ))" "'+%m-%d %H:%M:%S.000'" | tr -d '\r')
echo "pixel6 appium/force-stop lines since $since:"
$A logcat -d -v time -T "$since" 2>/dev/null | grep -E 'appium|Force stopping com\.mknoon|killDueToPackageUpdate|uiautomator' | tail -5 | cut -c1-160
echo "pixel6 procs: $($A shell ps -A -o PID,STIME,NAME | grep -E 'mknoon|maestro|uiautomator|appium' | tr -s ' ' | tr '\n' ';')"
echo "avd configs:"
for a in Pixel_6a Pixel_7 Pixel_8; do
  echo " $a: $(grep -E '^(image.sysdir.1|hw.device.name)' $HOME/.android/avd/$a.avd/config.ini 2>/dev/null | tr '\n' ' ') size=$(du -sh $HOME/.android/avd/$a.avd 2>/dev/null | cut -f1) mtime=$(stat -f %Sm $HOME/.android/avd/$a.avd/userdata-qemu.img 2>/dev/null)"
done
ls -la $HOME/.android/avd/ 2>/dev/null | head -20
