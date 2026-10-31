#!/bin/bash
# Build the Astra Group D debug APK as the disposable package com.mknoon.sims.groupd (Google services off) in build/wt-astra-c (62450cba4, app code = f14f7d369).
#   host-run docker-ws/with_native_lease.py <log> -- bash docker-ws/build_groupd_disposable_apk.sh
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"; WT="$REPO/build/wt-astra-c"
for f in android/app/libs/GoMknoon.aar android/app/libs/GoMknoon-sources.jar android/local.properties android/key.properties; do
  [ -f "$REPO/$f" ] && mkdir -p "$(dirname "$WT/$f")" && cp -p "$REPO/$f" "$WT/$f"
done
cd "$WT" || exit 2
git rev-parse HEAD
flutter pub get --offline --enforce-lockfile || exit 3
flutter build apk --debug --no-pub \
  --android-project-arg=androidApplicationId=com.mknoon.sims.groupd \
  --android-project-arg=disableGoogleServicesForDisposableProof=true
rc=$?
[ "$rc" -eq 0 ] && shasum -a 256 build/app/outputs/flutter-apk/app-debug.apk
exit $rc
