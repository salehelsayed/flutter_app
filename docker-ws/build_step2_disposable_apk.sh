#!/bin/bash
# Build the Codex-UI Step 2 debug APK as the disposable package com.mknoon.sims.step2 (Google services off) in build/wt-cui-377d.
#   host-run bash docker-ws/build_step2_disposable_apk.sh   (run under docker-ws/with_native_lease.py)
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"; WT="$REPO/build/wt-cui-377d"
for f in android/app/libs/GoMknoon.aar android/app/libs/GoMknoon-sources.jar android/local.properties android/key.properties; do
  [ -f "$REPO/$f" ] && mkdir -p "$(dirname "$WT/$f")" && cp -p "$REPO/$f" "$WT/$f"
done
cd "$WT" || exit 2
flutter pub get --offline --enforce-lockfile || exit 3
flutter build apk --debug --no-pub \
  --android-project-arg=androidApplicationId=com.mknoon.sims.step2 \
  --android-project-arg=disableGoogleServicesForDisposableProof=true
