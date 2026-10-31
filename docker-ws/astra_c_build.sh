#!/bin/bash
# Build the Astra Group C candidates in build/wt-astra-c: Pixel debug APK (voice calls on) then the iOS release FLOW-log app.
# Run under the native lease:
#   host-run docker-ws/with_native_lease.py <log> -- bash /Volumes/CrucialX9/flutter_app/docker-ws/astra_c_build.sh
set -uo pipefail
W=/Volumes/CrucialX9/flutter_app/build/wt-astra-c
cd "$W" || exit 1
echo "=== android start $(date -u +%FT%TZ)"
bash docker-ws/build_pixel_production.sh; RA=$?
cat docker-ws/build_pixel_production_result.txt 2>/dev/null
[ -f build/app/outputs/flutter-apk/app-debug.apk ] && shasum -a 256 build/app/outputs/flutter-apk/app-debug.apk
echo "=== ios start $(date -u +%FT%TZ)"
bash docker-ws/build_ios_flowlog.sh; RI=$?
echo "=== done $(date -u +%FT%TZ) android=$RA ios=$RI"
[ "$RA" = 0 ] && [ "$RI" = 0 ]
