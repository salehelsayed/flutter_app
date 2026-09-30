#!/bin/bash
# Install the R2-9 validation builds (build-r2-11) in place (app data kept: identity, friendship, groups). First saves the APK
# another session installed on the Pixel (r28_other_apk.sh save), so it can be restored after the run.
. "$(dirname "$0")/beta_env.sh"
B="$BETA/build-r2-11"
cat "$B/result.txt"
grep -q "ANDROID OK" "$B/result.txt" || { echo "NO ANDROID BUILD"; exit 1; }
grep -q "IOS OK" "$B/result.txt" || { echo "NO IOS BUILD"; exit 1; }
NAME=$(cat "$B/build_name.txt"); STAMP=${NAME##*.t}
echo "build name: $NAME"
bash "$(dirname "$0")/r28_other_apk.sh" save
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null
if xcrun simctl install "$UDID" "$B/Runner-nock.app"; then
  echo "ios installed: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$(xcrun simctl get_app_container "$UDID" "$BUNDLE" app)/Info.plist") (want $STAMP)"
else echo "IOS INSTALL FAILED"; fi
xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null 2>&1
want=$(stat -f %z "$B/beta-android.apk"); t0=$(date +%s)
timeout 1800 $ADB push "$B/beta-android.apk" /data/local/tmp/beta-r32.apk > /dev/null 2>&1
have=$($ADB shell stat -c %s /data/local/tmp/beta-r32.apk 2>/dev/null | tr -d '\r')
echo "android push: ${have:-0}/$want bytes in $(( $(date +%s) - t0 )) s"
if [ "$have" = "$want" ]; then
  t0=$(date +%s)
  echo "android pm install: $(timeout 900 $ADB shell pm install -r -d /data/local/tmp/beta-r32.apk 2>&1 | tail -1) in $(( $(date +%s) - t0 )) s"
fi
$ADB shell rm -f /data/local/tmp/beta-r32.apk
got=$($ADB shell dumpsys package $PKG | grep -m1 versionName | tr -d ' \r' | sed 's/versionName=//')
echo "android installed: $got $([ "$got" = "$NAME" ] && echo MATCH || echo MISMATCH)"
$ADB shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
echo "INSTALL DONE"
