#!/bin/bash
# Rebuild ONLY the Play App Bundle from the current tree, without redoing the
# ~50 minute iOS archive of docker-ws/build_store_release.sh.
#
# Why this exists: when nothing in the Android inputs changed, Gradle leaves the
# existing app-release.aab in place (up to date), so its mtime predates the run
# and build_store_release.sh reports PLAY FAILED(stale-artifact). Deleting the
# bundle first forces a genuine re-package, so the freshness gate means what it
# says. Same defines and gates as the store script.
# Result: docker-ws/build_play_aab_result.txt
set -uo pipefail
cd "$(dirname "$0")/.."

RESULT_FILE="docker-ws/build_play_aab_result.txt"
: > "$RESULT_FILE"
note() { echo "$*" | tee -a "$RESULT_FILE"; }

VERSION=$(grep -E '^version:' pubspec.yaml | awk '{print $2}')
VERSION_NAME="${VERSION%%+*}"
BUILD_NUMBER="${VERSION##*+}"
note "PROVENANCE version=$VERSION name=$VERSION_NAME build=$BUILD_NUMBER sha=$(git rev-parse --short HEAD) branch=$(git rev-parse --abbrev-ref HEAD) dirty_files=$(git status --porcelain | wc -l | tr -d ' ') date=$(date '+%Y-%m-%d %H:%M:%S')"

AAB=build/app/outputs/bundle/release/app-release.aab
rm -f "$AAB"
FRESH_MARK=$(mktemp)

echo "== Building Android App Bundle (release)"
if ! flutter build appbundle --release --target=lib/main.dart \
    --dart-define-from-file=tool/build/voice_call_release_defines.json \
    --android-project-arg=enableAndroidNativeCalls=true \
    || [ ! -f "$AAB" ]; then
  note "PLAY FAILED(build)"; exit 1
fi
if [ ! "$AAB" -nt "$FRESH_MARK" ]; then
  note "PLAY FAILED(stale-artifact: $AAB predates this build run)"; exit 1
fi
note "PLAY OK $AAB ($(du -m "$AAB" | cut -f1) MB) versionName=$VERSION_NAME versionCode=$BUILD_NUMBER"
echo "---"; cat "$RESULT_FILE"
