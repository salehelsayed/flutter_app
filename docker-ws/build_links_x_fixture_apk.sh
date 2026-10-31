#!/bin/bash
# Update-link check: debug APK from build/wt-links-x (release-126 head with the X patch) as the disposable package
# com.mknoon.sims.links with the approved SE41 fixture profile, so a signed TEST envelope can force the hard screen.
#   host-run docker-ws/with_native_lease.py <log> -- bash docker-ws/build_links_fixture_apk.sh
set -uo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"; WT="$REPO/build/wt-links-x"
for f in android/app/libs/GoMknoon.aar android/app/libs/GoMknoon-sources.jar android/local.properties android/key.properties; do
  [ -f "$REPO/$f" ] && mkdir -p "$(dirname "$WT/$f")" && cp -p "$REPO/$f" "$WT/$f"
done
cd "$WT" || exit 2
flutter pub get --offline --enforce-lockfile || exit 3
flutter build apk --debug --no-pub --build-number=125 \
  --android-project-arg=androidApplicationId=com.mknoon.sims.links \
  --android-project-arg=disableGoogleServicesForDisposableProof=true \
  --dart-define=E2E_TEST_MODE=true \
  --dart-define=SIMS_BUILD_PROFILE_ID=android.e2e.production_call_local \
  --dart-define=MKNOON_SE41_TEST_PROFILE=true \
  --dart-define=MKNOON_UPDATE_CHECK=on \
  --dart-define=MKNOON_SE41_TEST_PUBLIC_KEY_B64=0EqyMnQrtKs6E2i9RhXk5tAiSrcaAWuvhSCjMsl3hzc=
rc=$?
[ "$rc" -eq 0 ] && shasum -a 256 build/app/outputs/flutter-apk/app-debug.apk
exit $rc
