#!/bin/bash
# Build the Codex-UI Step 3 debug APK as the disposable package com.mknoon.sims.step3 (Google services off) in build/wt-cui-d816.
#   host-run docker-ws/with_native_lease.py <log> -- bash docker-ws/build_step3_disposable_apk.sh
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"; WT="$REPO/build/wt-cui-d816"
for f in android/app/libs/GoMknoon.aar android/app/libs/GoMknoon-sources.jar android/local.properties android/key.properties; do
  [ -f "$REPO/$f" ] && mkdir -p "$(dirname "$WT/$f")" && cp -p "$REPO/$f" "$WT/$f"
done
cd "$WT" || exit 2
git rev-parse HEAD
flutter pub get --offline --enforce-lockfile || exit 3
flutter build apk --debug --no-pub \
  --android-project-arg=androidApplicationId=com.mknoon.sims.step3 \
  --android-project-arg=disableGoogleServicesForDisposableProof=true
