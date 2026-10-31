#!/bin/bash
# Copy the internal-disk device build into build/<tree>/build/ios/iphoneos and install it on the iPhone 13 ONLY,
# keeping identity and data (no uninstall).   host-run bash docker-ws/final128_install_ios13.sh <tree under build/>
set -uo pipefail
W=/Volumes/CrucialX9/flutter_app/build/${1:?tree}; A="$HOME/tmp-dd-device/Build/Products/Release-iphoneos/Runner.app"
[ -d "$A" ] || { echo "no app at $A"; exit 2; }
mkdir -p "$W/build/ios/iphoneos"; rm -rf "$W/build/ios/iphoneos/Runner.app"; cp -R "$A" "$W/build/ios/iphoneos/Runner.app"
cd "$W" || exit 2
IPHONE_UDIDS=00008110-00184D622289801E bash docker-ws/install_iphones_keep_identity.sh
