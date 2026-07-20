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

# Provenance label (see deploy_all_phones.sh). Dev-environment rule: this
# builds the CURRENT WORKING TREE; the sha is a descriptive label only, and
# the per-run timestamp is what post-install verification checks.
GIT_SHA=$(git rev-parse --short HEAD)
GIT_DIRTY=$(git status --porcelain | wc -l | tr -d ' ')
RUN_STAMP=$(date +%y%m%d%H%M%S)
BUILD_NAME="1.0.0-${GIT_SHA}"
[ "$GIT_DIRTY" != "0" ] && BUILD_NAME="${BUILD_NAME}.d${GIT_DIRTY}"
BUILD_NAME="${BUILD_NAME}.t${RUN_STAMP}"
FRESH_MARK=$(mktemp)
echo "PROVENANCE tree=current-working-tree sha=$GIT_SHA dirty_files=$GIT_DIRTY build_name=$BUILD_NAME"

echo "Building non-E2E debug APK (arm64)..."
if flutter build apk --debug --target-platform=android-arm64 --target=lib/main.dart \
    --build-name="$BUILD_NAME"; then
  APK=build/app/outputs/flutter-apk/app-debug.apk
  if [ ! -f "$APK" ]; then
    echo "FAILED apk-not-found" > "$RESULT"
    exit 1
  fi
  if [ ! "$APK" -nt "$FRESH_MARK" ]; then
    # Freshness gate (same as deploy_all_phones.sh): a build that exits 0 but
    # leaves an old APK in place must not be reported as installable.
    echo "FAILED stale-artifact ($APK predates this build run)" > "$RESULT"
    exit 1
  fi
  echo "OK $APK $BUILD_NAME" > "$RESULT"
  echo "Build OK: $APK ($BUILD_NAME) — installer must verify versionName=$BUILD_NAME after adb install."
else
  echo "FAILED build (see terminal output above)" > "$RESULT"
  exit 1
fi
