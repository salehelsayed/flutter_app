#!/bin/bash
# In-place install of the fixed build (data kept => identity + friendship kept).
# Usage: install_fixed.sh <rel|nock>   (iOS variant; Android APK installed with rel only)
. "$(dirname "$0")/beta_env.sh"
RUN=$(current_run); V=${1:-rel}
if [ "$V" = rel ]; then
  $ADB install -r -d "$BETA/build/beta-android.apk" | tail -1
  echo "android: $($ADB shell dumpsys package $PKG | grep -m1 versionName | tr -d ' ')"
  $ADB shell monkey -p $PKG -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
fi
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null
xcrun simctl install "$UDID" "$BETA/build/Runner-$V.app" || { echo "FAILED ios install"; exit 1; }
APP=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" app)
echo "ios($V): $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist")  expected $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$BETA/build/Runner-$V.app/Info.plist")"
xcrun simctl launch "$UDID" "$BUNDLE" >/dev/null
echo "[$(date '+%H:%M:%S')] installed fixed build (ios=$V)" >> "$RUN/timeline.txt"
