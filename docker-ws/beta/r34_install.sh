#!/bin/bash
# Install the r2o validation build on iPhone 11 + 13 over the existing app (no uninstall: identity, contacts and
# data are kept), launch it and verify the bundle version. Restore the fixer's app afterwards with:
#   r34_install.sh /Volumes/CrucialX9/flutter_app-r2-fixes-20261001/.codex-test-logs/r2-open-issues/candidate-normal-profile-final/Runner.app
set -u
APP="${1:-/Volumes/CrucialX9/flutter_app-r2val/build/ios/iphoneos/Runner.app}"
BUNDLE=com.mknoon.app
WANT=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Info.plist")
echo "app $APP version $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist") build $WANT"
for U in 00008030-001A6D2801BB802E 00008110-00184D622289801E; do
  timeout 300 xcrun devicectl device install app --device "$U" "$APP" > /tmp/r34_install_$U.log 2>&1 \
    || { echo "$U INSTALL FAILED: $(tail -3 /tmp/r34_install_$U.log | tr '\n' ' ')"; continue; }
  timeout 90 xcrun devicectl device process launch --device "$U" --terminate-existing "$BUNDLE" > /dev/null 2>&1 \
    || echo "$U LAUNCH FAILED (phone locked?)"
  J=$(mktemp); timeout 90 xcrun devicectl device info apps --device "$U" --json-output "$J" > /dev/null 2>&1
  GOT=$(python3 -c "import json,sys;print(next((a.get('bundleVersion') for a in json.load(open('$J'))['result']['apps'] if a.get('bundleIdentifier')=='$BUNDLE'),'not-installed'))")
  [ "$GOT" = "$WANT" ] && echo "$U OK build $GOT" || echo "$U VERIFY FAILED: '$GOT' != '$WANT'"
done
