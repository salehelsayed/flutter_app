#!/bin/bash
# Build the Original-lossless candidates in build/wt-lossless: Pixel debug APK (voice calls on) then the iOS release FLOW-log app.
# Run under the native lease:
#   host-run docker-ws/with_native_lease.py <log> -- bash /Volumes/CrucialX9/flutter_app/docker-ws/fullres_build.sh
set -uo pipefail
W=/Volumes/CrucialX9/flutter_app/build/wt-lossless
cd "$W" || exit 1
echo "=== image_processor test $(date -u +%FT%TZ)"
flutter test --concurrency=1 test/core/media/image_processor_test.dart test/core/media/image_processor_original_jpeg_test.dart 2>&1 | tail -5; echo "test_exit=${PIPESTATUS[0]}"
echo "=== android start $(date -u +%FT%TZ)"
bash docker-ws/build_pixel_production.sh; RA=$?
cat docker-ws/build_pixel_production_result.txt 2>/dev/null
[ -f build/app/outputs/flutter-apk/app-debug.apk ] && shasum -a 256 build/app/outputs/flutter-apk/app-debug.apk
echo "=== ios start $(date -u +%FT%TZ)"
bash docker-ws/build_ios_flowlog.sh; RI=$?
echo "=== done $(date -u +%FT%TZ) android=$RA ios=$RI"
[ "$RA" = 0 ] && [ "$RI" = 0 ]
