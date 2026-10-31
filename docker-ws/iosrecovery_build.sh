#!/bin/bash
# iOS call recovery proof builds in build/wt-iosrecovery: iOS release FLOW-log app, RunnerTests selection on a simulator, Pixel debug APK (voice calls on).
#   host-run docker-ws/with_native_lease.py <log> -- bash /Volumes/CrucialX9/flutter_app/docker-ws/iosrecovery_build.sh
set -uo pipefail
W=/Volumes/CrucialX9/flutter_app/build/wt-iosrecovery
cd "$W" || exit 1
echo "=== ios start $(date -u +%FT%TZ)"
bash docker-ws/build_ios_flowlog.sh; RI=$?
echo "=== xctest start $(date -u +%FT%TZ)"
bash /Volumes/CrucialX9/flutter_app/docker-ws/iosrecovery_xctest.sh; RX=$?
echo "=== android start $(date -u +%FT%TZ)"
bash docker-ws/build_pixel_production.sh; RA=$?
cat docker-ws/build_pixel_production_result.txt 2>/dev/null
[ -f build/app/outputs/flutter-apk/app-debug.apk ] && shasum -a 256 build/app/outputs/flutter-apk/app-debug.apk
echo "=== done $(date -u +%FT%TZ) ios=$RI xctest=$RX android=$RA"
[ "$RI" = 0 ] && [ "$RX" = 0 ] && [ "$RA" = 0 ]
