#!/bin/bash
# Translation 129 gate: Pixel APK then iPhone device build, both TRANSLATE_PREVIEW=true and Hetzner (run under the native-build lease).
#   host-run docker-ws/with_native_lease.py <lease log> -- bash docker-ws/translate129_builds.sh <evidence> <build-number>
set -uo pipefail
REPO=/Volumes/CrucialX9/flutter_app; EV=${1:?evidence}; BN=${2:?bn}; E="$REPO/$EV"; mkdir -p "$E"
echo "builds start $(date -u +%T)"
bash "$REPO/docker-ws/translate129_pixel_apk.sh" "$EV/apk" "$BN" > "$E/1_pixel_apk.log" 2>&1; echo "pixel_apk exit=$? $(date -u +%T)"
DD_OVERRIDE="$HOME/tmp-dd-161" bash "$REPO/docker-ws/ios_device_build_internal.sh" wt-translate-129 "$EV/ios" "$BN" "--dart-define=TRANSLATE_PREVIEW=true" > "$E/2_ios_device.log" 2>&1; echo "ios_device exit=$? $(date -u +%T)"
echo "builds done $(date -u +%T)"
