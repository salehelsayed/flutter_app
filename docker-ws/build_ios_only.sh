#!/bin/bash
# Isolated iOS release build, same flags as run_fresh_three_phones.sh, for
# reproducing/clearing a build failure without redeploying all three phones.
set -u
cd "$(dirname "$0")/.."
STAMP=$(date +%y%m%d%H%M%S)
if [ "${CLEAN:-0}" = "1" ]; then
  echo "== flutter clean"
  flutter clean
fi
echo "== flutter build ios --release (stamp=$STAMP)"
flutter build ios --release --target=lib/main.dart --dart-define=PRODUCTION_APNS=true \
    --dart-define-from-file=tool/build/voice_call_release_defines.json \
  --build-name="1.0.0-iosprobe.t$STAMP" --build-number="$STAMP"
rc=$?
echo "== rc=$rc"
[ -d build/ios/iphoneos/Runner.app ] && echo "APP present" || echo "APP MISSING"
