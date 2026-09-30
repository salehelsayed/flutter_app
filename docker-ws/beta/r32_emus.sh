#!/bin/bash
# Read-only: which emulators are attached, their AVD name, and the Mknoon build/app data on each.
. "$(dirname "$0")/beta_env.sh"
A="$ANDROID_HOME/platform-tools/adb"
$A devices | tr -d '\r'
for s in $($A devices | awk 'NR>1 && $2=="device" {print $1}'); do
  echo "== $s avd=$($A -s $s emu avd name 2>/dev/null | head -1 | tr -d '\r') uptime=$($A -s $s shell cat /proc/uptime | awk '{printf "%.0f", $1}')"
  echo "   $($A -s $s shell dumpsys package $PKG | grep -m1 versionName | tr -d ' \r') $($A -s $s shell dumpsys package $PKG | grep -m1 -oE 'ceDataInode=[0-9]+' | tr -d '\r') $($A -s $s shell cmd appops get $PKG USE_FULL_SCREEN_INTENT 2>/dev/null | head -1 | tr -d '\r')"
done
