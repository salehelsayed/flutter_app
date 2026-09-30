#!/bin/bash
# Install the R2-1 fix builds in place (app data kept: identity, friendship, groups).
# Android: push + pm install with long limits (adb is slow under load); iPhone: simctl install.
# Prints one line per step and the installed versions.
. "$(dirname "$0")/beta_env.sh"
B="$BETA/build"
cat "$B/result.txt"
grep -q "ANDROID OK" "$B/result.txt" || { echo "NO ANDROID BUILD"; exit 1; }
grep -q "IOS OK" "$B/result.txt" || { echo "NO IOS BUILD"; exit 1; }
NAME=$(cat "$B/build_name.txt"); STAMP=${NAME##*.t}
echo "build name: $NAME"
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null
if xcrun simctl install "$UDID" "$B/Runner-nock.app"; then
  echo "ios installed: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$(xcrun simctl get_app_container "$UDID" "$BUNDLE" app)/Info.plist") (want $STAMP)"
else echo "IOS INSTALL FAILED"; fi
xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null 2>&1
want=$(stat -f %z "$B/beta-android.apk"); t0=$(date +%s)
timeout 1800 $ADB push "$B/beta-android.apk" /data/local/tmp/beta-r2fix.apk > /dev/null 2>&1
have=$($ADB shell stat -c %s /data/local/tmp/beta-r2fix.apk 2>/dev/null | tr -d '\r')
echo "android push: ${have:-0}/$want bytes in $(( $(date +%s) - t0 )) s"
if [ "$have" = "$want" ]; then
  t0=$(date +%s)
  echo "android pm install: $(timeout 900 $ADB shell pm install -r -d /data/local/tmp/beta-r2fix.apk 2>&1 | tail -1) in $(( $(date +%s) - t0 )) s"
fi
$ADB shell rm -f /data/local/tmp/beta-r2fix.apk
got=$($ADB shell dumpsys package $PKG | grep -m1 versionName | tr -d ' \r' | sed 's/versionName=//')
echo "android installed: $got $([ "$got" = "$NAME" ] && echo MATCH || echo MISMATCH)"
$ADB shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
echo "INSTALL DONE"
