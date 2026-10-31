#!/bin/bash
# Copy the internal-disk device build into build/<tree>/build/ios/iphoneos and install it on ONE iPhone,
# keeping identity and data (no uninstall).   host-run bash docker-ws/install_ios_keep_identity_one.sh <tree under build/> <udid>
set -uo pipefail
W=/Volumes/CrucialX9/flutter_app/build/${1:?tree}; U=${2:?udid}; A="${3:-$HOME/tmp-dd-device}/Build/Products/Release-iphoneos/Runner.app"
[ -d "$A" ] || { echo "no app at $A"; exit 2; }
mkdir -p "$W/build/ios/iphoneos"; rm -rf "$W/build/ios/iphoneos/Runner.app"; cp -R "$A" "$W/build/ios/iphoneos/Runner.app"
cd "$W" || exit 2
IPHONE_UDIDS="$U" bash docker-ws/install_iphones_keep_identity.sh
