#!/bin/bash
# Discovery-fix proof: disposable Android debug APK (com.mknoon.sims.t011, Google services off, PDF on) from build/wt-proof6.
# Run under the native lease: host-run docker-ws/with_native_lease.py <log> -- bash /Volumes/CrucialX9/flutter_app/docker-ws/fp_build_apk.sh
set -uo pipefail
M=/Volumes/CrucialX9/flutter_app; W=$M/build/wt-proof6; SHA=e203260be
cd "$W" || exit 2
case "$(git rev-parse HEAD)" in ${SHA}*) ;; *) echo "WT HEAD mismatch"; exit 2;; esac
for f in android/app/google-services.json android/local.properties android/key.properties ios/Runner/GoogleService-Info.plist .env; do
  [ -f "$M/$f" ] && [ ! -f "$W/$f" ] && mkdir -p "$(dirname "$W/$f")" && cp -p "$M/$f" "$W/$f"
done
mkdir -p android/app/libs
for f in GoMknoon.aar GoMknoon-sources.jar GoMknoon.inputs.sha256; do [ -f "$M/android/app/libs/$f" ] && [ ! -f "android/app/libs/$f" ] && cp -p "$M/android/app/libs/$f" "android/app/libs/$f"; done
. docker-ws/_flutter_sdk_env.sh
echo "=== go android $(date -u +%FT%TZ)"; bash scripts/ensure_go_android_bindings.sh || { echo "ANDROID FAILED(go bindings)"; exit 3; }
flutter pub get --enforce-lockfile || exit 3
echo "=== apk $(date -u +%FT%TZ)"
flutter build apk --debug --no-pub \
  --android-project-arg=androidApplicationId=com.mknoon.sims.t011 \
  --android-project-arg=disableGoogleServicesForDisposableProof=true --dart-define=MKNOON_ENABLE_DOCUMENT_ATTACHMENTS=true || { echo "ANDROID FAILED(build)"; exit 4; }
shasum -a 256 build/app/outputs/flutter-apk/app-debug.apk
echo "=== done $(date -u +%FT%TZ)"
