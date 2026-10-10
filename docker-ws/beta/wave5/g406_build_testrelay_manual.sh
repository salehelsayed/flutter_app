#!/bin/bash
# Plan 406: E2E-free debug APK on the Hetzner TEST relay (contact requests show a
# dialog), for an in-place update of BobH. Runs in the foreground.
set -u
export PATH="$HOME/development/flutter-3.47.2/bin:/opt/homebrew/bin:/usr/local/bin:/usr/local/go/bin:$PATH"
ID=12D3KooWB2HGqKUNt9sXigsrM3oxHsHRbqsx5TCNaBghSiebiwXM
RELAYS="/dns4/2-29-62-121.sslip.io/tcp/4001/wss/p2p/$ID,/dns4/2-29-62-121.sslip.io/udp/4002/quic-v1/p2p/$ID"
cd /Volumes/CrucialX9/flutter_app || exit 1
flutter build apk --debug --target-platform=android-arm64 -t lib/main.dart \
  --dart-define-from-file=tool/build/voice_call_release_defines.json \
  --dart-define=MKNOON_RELAY_ADDRESSES="$RELAYS" \
  --android-project-arg=enableAndroidNativeCalls=true \
  --build-name="1.0.1-hetznerm.t$(date +%y%m%d%H%M%S)" 2>&1 | tail -2
cp build/app/outputs/flutter-apk/app-debug.apk /Volumes/CrucialX9/flutter_app/docker-ws/beta/wave5/g406/hetznerm.apk
ADBB=$HOME/Library/Android/sdk/platform-tools/adb
$ADBB -s emulator-5556 install -r -g /Volumes/CrucialX9/flutter_app/docker-ws/beta/wave5/g406/hetznerm.apk | tail -1
echo "BobH: $($ADBB -s emulator-5556 shell dumpsys package com.mknoon.app | grep -m1 versionName | tr -d ' \r')"
