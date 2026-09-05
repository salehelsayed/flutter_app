#!/bin/bash
# Read-only: what does the current build/ios artifact actually contain?
cd /Volumes/CrucialX9/flutter_app
APP=build/ios/iphoneos/Runner.app
echo "now: $(date '+%H:%M:%S')"
if [ ! -d "$APP" ]; then echo "NO APP at $APP"; exit 1; fi
echo "=== binary ==="
ls -la "$APP/Runner" 2>/dev/null
echo "=== version ==="
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist" 2>/dev/null
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist" 2>/dev/null
echo "=== go bridge symbol count ==="
grep -c "BridgeGenerateIdentity" "$APP/Runner" 2>/dev/null || echo 0
echo "=== 405 call-row string present in the flutter assets? ==="
if [ -f "$APP/Frameworks/App.framework/App" ]; then
  grep -c "Missed voice call" "$APP/Frameworks/App.framework/App" 2>/dev/null || echo 0
else
  echo "(no App.framework)"
fi
echo "=== embedded flutter engine version ==="
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Frameworks/Flutter.framework/Info.plist" 2>/dev/null
