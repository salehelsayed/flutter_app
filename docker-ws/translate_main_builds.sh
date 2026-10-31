#!/bin/bash
# Translate gate: all native builds in sequence (run under the native-build lease):
#   1 Pixel release-mode APK (debug-signed, Hetzner)  2 iPhone device build (Hetzner, DerivedData ~/tmp-dd-161)
#   3 store AAB + App Store archive/export.   Each step logs to <evidence>/<step>.log
#   host-run docker-ws/with_native_lease.py <lease log> -- bash docker-ws/translate_main_builds.sh <evidence> <build-number> [steps, default 123]
set -uo pipefail
REPO=/Volumes/CrucialX9/flutter_app; EV=${1:?evidence}; BN=${2:?bn}; S=${3:-123}; E="$REPO/$EV"; mkdir -p "$E"
echo "builds start $(date -u +%T) steps=$S"
case "$S" in *1*) bash "$REPO/docker-ws/translate_main_pixel_apk.sh" "$EV" "$BN" > "$E/1_pixel_apk.log" 2>&1; echo "pixel_apk exit=$? $(date -u +%T)";; esac
case "$S" in *2*) DD_OVERRIDE="$HOME/tmp-dd-161" bash "$REPO/docker-ws/ios_device_build_internal.sh" wt-translate-main "$EV" "$BN" > "$E/2_ios_device.log" 2>&1; echo "ios_device exit=$? $(date -u +%T)";; esac
case "$S" in *3*) bash "$REPO/docker-ws/translate_main_store_build.sh" "$EV/store" > "$E/3_store.log" 2>&1; echo "store exit=$? $(date -u +%T)";; esac
echo "builds done $(date -u +%T)"
