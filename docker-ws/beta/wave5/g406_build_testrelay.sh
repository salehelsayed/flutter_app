#!/bin/bash
# Plan 406: app builds that use ONLY the Hetzner test relay (main checkout,
# Go 1.27.1). Android E2E + PRODUCTION_FCM debug APK (seedable, push on) and an
# iOS release for the iPhone 13. Self-detaches; log g406_build_testrelay.log.
set -u
W=/Volumes/CrucialX9/flutter_app/docker-ws/beta/wave5
OUT=$W/g406_build_testrelay.log
if [ -z "${G406TR_DETACHED:-}" ]; then
  G406TR_DETACHED=1 nohup bash "$0" "$@" >"$OUT" 2>&1 &
  echo "detached pid $! log $OUT"; exit 0
fi
export PATH="$HOME/development/flutter-3.47.2/bin:/opt/homebrew/bin:/usr/local/bin:/usr/local/go/bin:$PATH"
export FLUTTER_XCODE_CLANG_ENABLE_EXPLICIT_MODULES=NO
ID=12D3KooWB2HGqKUNt9sXigsrM3oxHsHRbqsx5TCNaBghSiebiwXM
RELAYS="/dns4/2-29-62-121.sslip.io/tcp/4001/wss/p2p/$ID,/dns4/2-29-62-121.sslip.io/udp/4002/quic-v1/p2p/$ID"
ART=$W/g406; mkdir -p "$ART"
STAMP=$(date +%y%m%d%H%M%S); echo "STAMP=$STAMP"
cd /Volumes/CrucialX9/flutter_app || exit 1
git log --oneline -1
echo "=== Android APK (test relay)"; date
flutter build apk --debug --target-platform=android-arm64 -t lib/main.dart \
  --dart-define-from-file=tool/build/voice_call_release_defines.json \
  --dart-define=E2E_TEST_MODE=true --dart-define=PRODUCTION_FCM=true \
  --dart-define=MKNOON_RELAY_ADDRESSES="$RELAYS" \
  --android-project-arg=enableAndroidNativeCalls=true \
  --build-name="1.0.1-hetzner.t$STAMP" 2>&1 | tail -3
echo "APK exit=${PIPESTATUS[0]}"
cp build/app/outputs/flutter-apk/app-debug.apk "$ART/hetzner.apk" && ls -la "$ART/hetzner.apk"
echo "=== iOS release (test relay)"; date
scripts/ensure_go_ios_bindings.sh 2>&1 | tail -1
flutter build ios --release --target=lib/main.dart --dart-define=PRODUCTION_APNS=true \
  --dart-define-from-file=tool/build/voice_call_release_defines.json \
  --dart-define=MKNOON_RELAY_ADDRESSES="$RELAYS" \
  --build-name="1.0.1-hetzner.t$STAMP" --build-number="$STAMP" 2>&1 | tail -3
echo "iOS exit=${PIPESTATUS[0]}"
echo "bundleVersion=$(defaults read "$PWD/build/ios/iphoneos/Runner.app/Info.plist" CFBundleVersion 2>&1) bridge=$(grep -c BridgeGenerateIdentity build/ios/iphoneos/Runner.app/Runner)"
date; echo "BUILD TESTRELAY DONE"
