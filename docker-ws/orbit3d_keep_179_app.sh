#!/bin/bash
# Keep a copy of the iPhone 11 build 179 app (3D active-center candidate) before the next preview build overwrites ~/tmp-dd-161.
#   host-run bash docker-ws/orbit3d_keep_179_app.sh
set -uo pipefail
SRC="$HOME/tmp-dd-161/Build/Products/Release-iphoneos/Runner.app"; DST="$HOME/tmp-dd-179-keep/Build/Products/Release-iphoneos"
V=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$SRC/Info.plist"); echo "source bundle=$V"
[ "$V" = "179" ] || { echo "STOP source is not 179"; exit 3; }
mkdir -p "$DST" && rm -rf "$DST/Runner.app" && cp -Rp "$SRC" "$DST/" && echo "kept bundle=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$DST/Runner.app/Info.plist") at ~/tmp-dd-179-keep ($(du -sh "$DST/Runner.app" | cut -f1))"
