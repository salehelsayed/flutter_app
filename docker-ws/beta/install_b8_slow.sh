#!/bin/bash
# Install build/beta-android-b8.apk on emulator-5556 when adb is slow: push with a long
# limit, check the pushed size, then pm install. Prints one line per step.
. "$(dirname "$0")/beta_env.sh"
APK="$BETA/build/beta-android-b8.apk"
LIMIT=${1:-1500}
PM_LIMIT=${2:-300}
want=$(stat -f %z "$APK")
t0=$(date +%s)
timeout "$LIMIT" $ADB push "$APK" /data/local/tmp/beta-b8.apk > /dev/null 2>&1
have=$($ADB shell stat -c %s /data/local/tmp/beta-b8.apk 2>/dev/null | tr -d '\r')
echo "push: ${have:-0}/$want bytes in $(( $(date +%s) - t0 )) s"
if [ "$have" = "$want" ]; then
  t0=$(date +%s)
  echo "pm install: $(timeout "$PM_LIMIT" $ADB shell pm install -r -d /data/local/tmp/beta-b8.apk 2>&1 | tail -1) in $(( $(date +%s) - t0 )) s"
fi
$ADB shell rm -f /data/local/tmp/beta-b8.apk
echo "installed: $($ADB shell dumpsys package $PKG | grep -m1 versionName | tr -d ' \r')"
echo "INSTALL DONE"
