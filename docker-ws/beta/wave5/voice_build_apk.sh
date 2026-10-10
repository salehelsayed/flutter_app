#!/bin/bash
# Voice-playback repro: debug arm64 APK of the main checkout (E2E seeding on). Self-detaches.
set -u
W=/Volumes/CrucialX9/flutter_app/docker-ws/beta/wave5
OUT=$W/voice_build.log
if [ -z "${VOICE_BUILD_DETACHED:-}" ]; then
  VOICE_BUILD_DETACHED=1 nohup bash "$0" "$@" >"$OUT" 2>&1 &
  echo "detached pid $! log $OUT"; exit 0
fi
cd /Volumes/CrucialX9/flutter_app || exit 1
echo "HEAD $(git rev-parse --short HEAD) dirty=$(git status --porcelain --untracked-files=no | wc -l | tr -d ' ')"; date
"$HOME/development/flutter-3.47.2/bin/flutter" build apk --debug --target-platform=android-arm64 -t lib/main.dart \
  --dart-define-from-file=tool/build/voice_call_release_defines.json \
  --dart-define=E2E_TEST_MODE=true --dart-define=PRODUCTION_FCM=true \
  --android-project-arg=enableAndroidNativeCalls=true \
  --build-name="1.0.0-$(git rev-parse --short HEAD).voice" 2>&1 | tail -5
echo "build exit=${PIPESTATUS[0]}"; date
mkdir -p $W/voice && cp build/app/outputs/flutter-apk/app-debug.apk $W/voice/app.apk && ls -la $W/voice/app.apk
