#!/bin/bash
# Discovery relaunch proof: disposable Pixel debug APK (com.mknoon.sims.t011, Google services off, PDF on)
# and the debug iOS simulator receiver, both from build/wt-astra3 at 28ee7c26c. Run under the native lease:
#   host-run docker-ws/with_native_lease.py <log> -- bash /Volumes/CrucialX9/flutter_app/docker-ws/dr_build.sh
set -uo pipefail
M=/Volumes/CrucialX9/flutter_app; W=$M/build/wt-astra3; SHA=28ee7c26c
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
echo "=== go ios $(date -u +%FT%TZ)"; scripts/ensure_go_ios_bindings.sh || { echo "SIM FAILED(go bindings)"; exit 5; }
echo "=== sim build $(date -u +%FT%TZ)"
flutter build ios --simulator --debug --no-pub --dart-define-from-file=tool/build/voice_call_release_defines.json \
  --dart-define=MKNOON_ENABLE_DOCUMENT_ATTACHMENTS=true || { echo "SIM FAILED(build)"; exit 6; }
APP=build/ios/iphonesimulator/Runner.app
shasum -a 256 "$APP/Runner.debug.dylib" "$APP/Runner" 2>/dev/null
echo "=== done $(date -u +%FT%TZ)"
