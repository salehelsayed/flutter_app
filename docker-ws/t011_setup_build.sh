#!/bin/bash
# TRANSFER-011: create build/wt-t011 at cb02da5e9, copy ignored inputs, build the disposable Android debug APK
# (com.mknoon.sims.t011, Google services off) and the iOS release FLOW-log app. Run under the native lease:
#   host-run docker-ws/with_native_lease.py <log> -- bash /Volumes/CrucialX9/flutter_app/docker-ws/t011_setup_build.sh
set -uo pipefail
M=/Volumes/CrucialX9/flutter_app; W=$M/build/wt-t011; SHA=cb02da5e9640a93ad9e98548ff1bb384a2f3ae3f
if [ ! -d "$W/.git" ] && [ ! -f "$W/.git" ]; then git -C "$M" worktree add --detach "$W" "$SHA" || exit 2; fi
[ "$(git -C "$W" rev-parse HEAD)" = "$SHA" ] || { echo "WT HEAD mismatch"; exit 2; }
for f in android/app/google-services.json android/local.properties android/key.properties ios/Runner/GoogleService-Info.plist .env; do
  [ -f "$M/$f" ] && [ ! -f "$W/$f" ] && mkdir -p "$(dirname "$W/$f")" && cp -p "$M/$f" "$W/$f"
done
mkdir -p "$W/android/app/libs"
for f in GoMknoon.aar GoMknoon-sources.jar GoMknoon.inputs.sha256; do [ -f "$M/android/app/libs/$f" ] && cp -p "$M/android/app/libs/$f" "$W/android/app/libs/$f"; done
cd "$W" || exit 2
. docker-ws/_flutter_sdk_env.sh
echo "=== go android $(date -u +%FT%TZ)"; bash scripts/ensure_go_android_bindings.sh || { echo "ANDROID FAILED(go bindings)"; exit 3; }
flutter pub get --enforce-lockfile || exit 3
echo "=== apk $(date -u +%FT%TZ)"
flutter build apk --debug --no-pub \
  --android-project-arg=androidApplicationId=com.mknoon.sims.t011 \
  --android-project-arg=disableGoogleServicesForDisposableProof=true --dart-define=MKNOON_ENABLE_DOCUMENT_ATTACHMENTS=true || { echo "ANDROID FAILED(build)"; exit 4; }
shasum -a 256 build/app/outputs/flutter-apk/app-debug.apk
echo "=== ios $(date -u +%FT%TZ)"
bash docker-ws/build_ios_flowlog.sh || exit 5
shasum -a 256 build/ios/iphoneos/Runner.app/Runner
echo "=== done $(date -u +%FT%TZ)"
