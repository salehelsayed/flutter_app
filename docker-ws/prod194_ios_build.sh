#!/bin/bash
# Prod-config iOS device build 194 from <sha> (same DB version as the Hetzner test build on the phones, so it can go over it).
# Own DerivedData folder ~/tmp-dd-194-prod. Run under the native-build lease.
#   host-run docker-ws/with_native_lease.py <log> -- bash docker-ws/prod194_ios_build.sh <sha> <evidence dir under repo>
set -uo pipefail
SHA=${1:?sha}; EV=${2:?evidence}; REPO=/Volumes/CrucialX9/flutter_app; E="$REPO/$EV"; mkdir -p "$E"
bash "$REPO/docker-ws/wt129_checkout.sh" "$SHA"
DD_OVERRIDE="$HOME/tmp-dd-194-prod" bash "$REPO/docker-ws/ios_device_build_prod.sh" wt-translate-129 "$EV/ios" 194 > "$E/ios_prod194.log" 2>&1
echo "ios_prod exit=$?"; tail -2 "$E/ios_prod194.log"
A="$HOME/tmp-dd-194-prod/Build/Products/Release-iphoneos/Runner.app"
echo "bundle=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$A/Info.plist" 2>/dev/null) hetzner_strings=$(strings "$A/Frameworks/App.framework/App" 2>/dev/null | grep -c sslip.io) aws_strings=$(strings "$A/Frameworks/App.framework/App" 2>/dev/null | grep -c mknoun.xyz)"
echo "done $(date +%H:%M:%S)"
