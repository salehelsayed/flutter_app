#!/bin/bash
# 3D Orbit for 129 (claude-ui/orbit-3d-129): check out <sha> in build/wt-translate-129 (it already sits on main), checks,
# then the Pixel APK and the iPhone device build, both TRANSLATE_PREVIEW=true and Hetzner (run under the native-build lease).
#   host-run docker-ws/with_native_lease.py <log> -- bash docker-ws/orbit3d129_builds.sh <sha> <evidence dir> <build-number>
set -uo pipefail
SHA=${1:?sha}; EV=${2:?evidence}; BN=${3:?bn}
REPO=/Volumes/CrucialX9/flutter_app; W=$REPO/build/wt-translate-129; E="$REPO/$EV"; mkdir -p "$E"
cd "$W" || exit 2
git checkout -- ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved 2>/dev/null
[ -z "$(git status --porcelain --untracked-files=no)" ] || { git status --porcelain --untracked-files=no; echo "STOP tree dirty"; exit 3; }
git checkout --detach "$SHA" 2>&1 | tail -1; echo "head=$(git rev-parse HEAD)"
bash "$REPO/docker-ws/wt_checks.sh" wt-translate-129 > "$E/wt_checks.log" 2>&1; echo "wt_checks exit=$?"; grep -E "errors=|warnings=" "$E/wt_checks.log"
bash "$REPO/docker-ws/translate129_pixel_apk.sh" "$EV/apk" "$BN" > "$E/1_pixel_apk.log" 2>&1; echo "pixel_apk exit=$?"; grep -E "^APK|libapp" "$E/1_pixel_apk.log"
DD_OVERRIDE="$HOME/tmp-dd-161" bash "$REPO/docker-ws/ios_device_build_internal.sh" wt-translate-129 "$EV/ios" "$BN" "--dart-define=TRANSLATE_PREVIEW=true" > "$E/2_ios_device.log" 2>&1; echo "ios_device exit=$?"; tail -1 "$E/2_ios_device.log"
git checkout -- ios/Runner.xcworkspace/xcshareddata/swiftpm/Package.resolved 2>/dev/null
echo "done $(date -u +%T) tracked_dirty=$(git status --porcelain --untracked-files=no | wc -l | tr -d ' ')"
