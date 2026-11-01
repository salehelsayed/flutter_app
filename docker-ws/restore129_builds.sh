#!/bin/bash
# Prod restore builds for the owner's phones after the P0 campaign: check out bac98f244 (1.0.1+129, release code) in
# build/wt-translate-129, then the Pixel prod APK as versionCode 192 and the iOS prod device build 129, the iOS one in
# its OWN DerivedData folder so a later Hetzner build cannot overwrite it. Run under the native-build lease.
#   host-run docker-ws/with_native_lease.py <log> -- bash docker-ws/restore129_builds.sh <evidence dir under repo>
set -uo pipefail
EV=${1:?evidence}; REPO=/Volumes/CrucialX9/flutter_app; E="$REPO/$EV"; mkdir -p "$E"
bash "$REPO/docker-ws/wt129_checkout.sh" bac98f244
bash "$REPO/docker-ws/wt_checks.sh" wt-translate-129 > "$E/wt_checks.log" 2>&1; echo "wt_checks exit=$?"; grep -E "errors=|warnings=" "$E/wt_checks.log"
bash "$REPO/docker-ws/owner129_pixel_apk.sh" "$EV/apk" 192 > "$E/1_pixel_apk.log" 2>&1; echo "pixel_apk exit=$?"; grep -E "^APK|libapp" "$E/1_pixel_apk.log"
DD_OVERRIDE="$HOME/tmp-dd-129-prod" bash "$REPO/docker-ws/ios_device_build_prod.sh" wt-translate-129 "$EV/ios" 129 > "$E/2_ios_prod.log" 2>&1; echo "ios_prod exit=$?"; tail -2 "$E/2_ios_prod.log"
A="$HOME/tmp-dd-129-prod/Build/Products/Release-iphoneos/Runner.app"
echo "ios bundle=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$A/Info.plist" 2>/dev/null) hetzner_strings=$(strings "$A/Frameworks/App.framework/App" 2>/dev/null | grep -c sslip.io)"
echo "done $(date +%H:%M:%S)"
