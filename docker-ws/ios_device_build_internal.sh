#!/bin/bash
# Release iOS DEVICE build for the Hetzner TEST relay with DerivedData on the internal disk (external-drive reads fail
# in Xcode builds since the 10-26 Mac restart). Release voice-call defines, update check off, flow log on.
#   host-run docker-ws/with_native_lease.py <log> -- bash docker-ws/ios_device_build_internal.sh <tree under build/> <evidence dir under repo> <build-number> [extra --dart-define]
set -uo pipefail
REPO=/Volumes/CrucialX9/flutter_app; W="$REPO/build/${1:?tree}"; E="$REPO/${2:?evidence}"; BN="${3:?build-number}"; XD="${4:-}"; mkdir -p "$E"
DD="${DD_OVERRIDE:-$HOME/tmp-dd-device}"
export PATH="$HOME/development/flutter-3.47.2/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin" GOTOOLCHAIN=go1.27.1
cd "$W" || exit 2
PID=12D3KooWB2HGqKUNt9sXigsrM3oxHsHRbqsx5TCNaBghSiebiwXM
H="--dart-define=MKNOON_UPDATE_CHECK=off --dart-define=MKNOON_RELAY_ADDRESSES=/dns4/2-29-62-121.sslip.io/tcp/4001/wss/p2p/$PID,/dns4/2-29-62-121.sslip.io/udp/4002/quic-v1/p2p/$PID"
VERSION=$(grep -E '^version:' pubspec.yaml | awk '{print $2}')
{
  echo "start $(date -u +%T) head=$(git rev-parse HEAD) dirty=$(git status --porcelain | wc -l | tr -d ' ') build_number=$BN"
  bash scripts/ensure_go_ios_bindings.sh; echo "bindings exit=$?"
  flutter build ios --release --config-only --no-pub --target=lib/main.dart --dart-define=PRODUCTION_APNS=true --dart-define=FDC_FLOW_LOG=1 \
    --dart-define-from-file=tool/build/voice_call_release_defines.json $H $XD --build-name="${VERSION%%+*}" --build-number="$BN"; echo "config exit=$?"
  xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Release -sdk iphoneos \
    -destination 'generic/platform=iOS' -jobs 1 -allowProvisioningUpdates -derivedDataPath "$DD" build; echo "build exit=$? $(date -u +%T)"
} > "$E/ios_device_build.log" 2>&1
B=$(grep -oE 'build exit=[0-9]+' "$E/ios_device_build.log" | tail -1); echo "$B"
[ "$B" = "build exit=0" ] || { echo "DEVICE BUILD FAILED"; exit 3; }
A=$(find "$DD/Build/Products" -maxdepth 2 -name Runner.app -path '*iphoneos*' | head -1); echo "app=$A"
echo "bundle=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$A/Info.plist") go_runtime=$(LC_ALL=C grep -a -c 'runtime.main' "$A/Runner") nse=$(ls -d "$A/PlugIns/"*.appex 2>/dev/null | wc -l | tr -d ' ')"
