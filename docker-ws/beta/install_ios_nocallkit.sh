#!/bin/bash
# In-place install of the no-CallKit iOS build (app data container is kept,
# so the identity and the friendship survive). Verifies the installed version.
. "$(dirname "$0")/beta_env.sh"
xcrun simctl terminate "$UDID" "$BUNDLE" 2>/dev/null
xcrun simctl install "$UDID" "$BETA/build/Runner-nocallkit.app" || { echo "FAILED install"; exit 1; }
APP=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" app)
echo "installed: $(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Info.plist")"
DOCS=$(ios_docs); ls "$DOCS" | head -20
xcrun simctl launch "$UDID" "$BUNDLE"
echo "[$(date '+%H:%M:%S')] iOS switched to no-CallKit build" >> "$(current_run)/timeline.txt"
