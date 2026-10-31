#!/bin/bash
# VC-014: install the existing dev build 158 Runner.app (build/wt-release-128/build/ios/iphoneos, aps development,
# CFBundleVersion 158) over whatever is on the iPhone 13, keeping data (no uninstall).   host-run bash docker-ws/vc014_install_158.sh
set -uo pipefail
R="$(cd "$(dirname "$0")/.." && pwd)"; W="$R/build/wt-release-128"; U=00008110-00184D622289801E
V=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$W/build/ios/iphoneos/Runner.app/Info.plist")
[ "$V" = "158" ] || { echo "refused: app is $V, not 158"; exit 2; }
cd "$W" && IPHONE_UDIDS="$U" bash "$W/docker-ws/install_iphones_keep_identity.sh"
