#!/bin/bash
# Prod-config iOS device build from <sha> WITH the You page on (MKNOON_ENABLE_YOU_PAGE=true), for the owner's preview phones.
# Same store defines as 194, own DerivedData folder ~/tmp-dd-<build>-prod-you. Run under the native-build lease.
#   host-run docker-ws/with_native_lease.py <log> -- bash docker-ws/prod_you_ios_build.sh <sha> <evidence dir under repo> <build-number>
set -uo pipefail
SHA=${1:?sha}; EV=${2:?evidence}; BN=${3:?bn}; REPO=/Volumes/CrucialX9/flutter_app; E="$REPO/$EV"; mkdir -p "$E"
DD="$HOME/tmp-dd-$BN-prod-you"
bash "$REPO/docker-ws/wt129_checkout.sh" "$SHA"
PROD_EXTRA_DEFINES="--dart-define=MKNOON_ENABLE_YOU_PAGE=true" DD_OVERRIDE="$DD" bash "$REPO/docker-ws/ios_device_build_prod.sh" wt-translate-129 "$EV/ios" "$BN" > "$E/ios_prod_you.log" 2>&1
echo "ios_prod exit=$?"; tail -2 "$E/ios_prod_you.log"
grep -c "MKNOON_ENABLE_YOU_PAGE=true" "$E/ios/ios_device_build.log" | sed 's/^/you_define_in_log=/'
A="$DD/Build/Products/Release-iphoneos/Runner.app"
echo "bundle=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$A/Info.plist" 2>/dev/null) hetzner_strings=$(strings "$A/Frameworks/App.framework/App" 2>/dev/null | grep -c sslip.io) aws_strings=$(strings "$A/Frameworks/App.framework/App" 2>/dev/null | grep -c mknoun.xyz)"
echo "dd=$DD done $(date +%H:%M:%S)"
