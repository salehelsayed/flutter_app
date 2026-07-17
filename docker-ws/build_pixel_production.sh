#!/bin/bash
# Build a non-E2E (no dart-defines) debug APK for the Pixel.
# Debug-signed like the currently installed sims build, so it installs as an
# in-place UPDATE (app data and identity survive). No E2E_TEST_MODE define
# means the contact-request presentation gate stays open.
# Run ON THE MAC:
#   /Users/I560101/Project-Sat/mknoon-2/flutter_app/docker-ws/build_pixel_production.sh
set -uo pipefail
cd "$(dirname "$0")/.."

RESULT=docker-ws/build_pixel_production_result.txt
rm -f "$RESULT"

echo "Building non-E2E debug APK (arm64)..."
if flutter build apk --debug --target-platform=android-arm64 --target=lib/main.dart; then
  APK=build/app/outputs/flutter-apk/app-debug.apk
  if [ -f "$APK" ]; then
    echo "OK $APK" > "$RESULT"
    echo "Build OK: $APK — Claude will pick it up and install it on the Pixel."
  else
    echo "FAILED apk-not-found" > "$RESULT"
    exit 1
  fi
else
  echo "FAILED build (see terminal output above)" > "$RESULT"
  exit 1
fi
