#!/bin/bash
# Install the R2-2 fix build on the iPhone simulator in place (app data kept) and prove it carries the fix.
. "$(dirname "$0")/beta_env.sh"
B="$BETA/build-r2-2"
grep -q "IOS OK" "$B/result.txt" || { echo "NO IOS BUILD"; exit 1; }
NAME=$(cat "$B/build_name.txt"); STAMP=${NAME##*.t}
echo "build name: $NAME"
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null
if xcrun simctl install "$UDID" "$B/Runner-nock.app"; then
  APP=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" app)
  echo "ios installed: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist") (want $STAMP)"
  echo "fix marker in installed app: $(LC_ALL=C grep -a -c fr.skyost.bonsoir.discovery.resolve "$APP/Frameworks/bonsoir_darwin.framework/bonsoir_darwin")"
else echo "IOS INSTALL FAILED"; fi
xcrun simctl launch "$UDID" "$BUNDLE" 2>&1 | tail -1
echo "INSTALL DONE"
