#!/bin/bash
# Keep a copy of the iPhone 11 build <N> app before the next preview build overwrites ~/tmp-dd-161.
#   host-run bash docker-ws/orbit3d_keep_app.sh <build number>
set -uo pipefail
N=${1:?build number}
SRC="$HOME/tmp-dd-161/Build/Products/Release-iphoneos/Runner.app"; DST="$HOME/tmp-dd-${N}-keep/Build/Products/Release-iphoneos"
V=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$SRC/Info.plist"); echo "source bundle=$V"
[ "$V" = "$N" ] || { echo "STOP source is not $N"; exit 3; }
mkdir -p "$DST" && rm -rf "$DST/Runner.app" && cp -Rp "$SRC" "$DST/" && echo "kept bundle=$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$DST/Runner.app/Info.plist") at ~/tmp-dd-${N}-keep ($(du -sh "$DST/Runner.app" | cut -f1))"
