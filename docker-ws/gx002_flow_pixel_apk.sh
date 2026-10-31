#!/bin/bash
# GX-002 self-leave rerun: release-mode APK (TRANSLATE_PREVIEW=true, FDC_FLOW_LOG=1 observer build) for the Pixel from build/wt-translate-129, store defines plus the Hetzner TEST
# relay, DEBUG-signed (key.properties held aside for the build, restored after) so it installs with adb install -r
# over the Pixel's debug-signed build 168 and keeps its account. Copy of translate_main_pixel_apk.sh with the tree changed.
#   bash docker-ws/gx002_flow_pixel_apk.sh <evidence dir under repo> <build-number>
set -uo pipefail
REPO=/Volumes/CrucialX9/flutter_app; W=$REPO/build/wt-translate-129; E="$REPO/${1:?evidence}"; BN=${2:?build-number}; mkdir -p "$E"
export ANDROID_HOME="$HOME/Library/Android/sdk" JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home GOTOOLCHAIN=go1.27.1
export PATH="$HOME/development/flutter-3.47.2/bin:$ANDROID_HOME/platform-tools:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
cd "$W" || exit 2
K=android/key.properties; H=build/.key.properties.gx002flow-hold
[ -f "$K" ] && { mkdir -p build; mv "$K" "$H"; }
restore() { [ -f "$H" ] && mv "$H" "$K"; [ -f "$K" ] && echo "key.properties restored"; }
trap restore EXIT
PID=12D3KooWB2HGqKUNt9sXigsrM3oxHsHRbqsx5TCNaBghSiebiwXM
RELAY="/dns4/2-29-62-121.sslip.io/tcp/4001/wss/p2p/$PID,/dns4/2-29-62-121.sslip.io/udp/4002/quic-v1/p2p/$PID"
VERSION=$(grep -E '^version:' pubspec.yaml | awk '{print $2}')
echo "== provenance $(date -u +%T) head=$(git rev-parse --short HEAD) dirty=$(git status --porcelain --untracked-files=no | wc -l | tr -d ' ') pubspec=$VERSION build_number=$BN"
python3 scripts/check_update_check_release_defines.py --dart-define-from-file=tool/build/voice_call_release_defines.json || { echo "RELEASE_GUARD FAILED"; exit 3; }
bash scripts/ensure_go_android_bindings.sh || { echo "GO_ANDROID_BINDINGS FAILED"; exit 4; }
MARK=$(mktemp); APK=build/app/outputs/flutter-apk/app-release.apk
echo "== flutter build apk $(date -u +%T)"
flutter build apk --release --target=lib/main.dart --build-name="${VERSION%%+*}" --build-number="$BN" \
  --dart-define-from-file=tool/build/voice_call_release_defines.json --dart-define=MKNOON_RELAY_ADDRESSES="$RELAY" --dart-define=TRANSLATE_PREVIEW=true --dart-define=FDC_FLOW_LOG=1 \
  --android-project-arg=enableAndroidNativeCalls=true --android-project-arg=allowDebugSigningInRelease=true
rc=$?; echo "apk exit=$rc $(date -u +%T)"
[ $rc -eq 0 ] || exit $rc
[ "$APK" -nt "$MARK" ] || { echo "STALE APK"; exit 5; }
cp -p "$APK" "$E/pixel-$BN.apk"
BT=$(ls -d "$ANDROID_HOME/build-tools/"* | sort -V | tail -1)
echo "APK $E/pixel-$BN.apk sha256=$(shasum -a 256 "$APK" | cut -c1-64) bytes=$(stat -f %z "$APK")"
"$BT/aapt2" dump badging "$APK" 2>/dev/null | head -1
"$BT/apksigner" verify --print-certs "$APK" 2>/dev/null | grep -E 'SHA-256' | head -1
keytool -list -v -keystore "$HOME/.android/debug.keystore" -storepass android -alias androiddebugkey 2>/dev/null | grep -E 'SHA256:' | head -1
L=$(unzip -l "$APK" | awk '/lib\/arm64-v8a\/libapp.so/{print $4}'); T=$(mktemp -d); unzip -q -o "$APK" "$L" -d "$T"
echo "libapp hetzner_relay=$(LC_ALL=C grep -a -c '2-29-62-121.sslip.io' "$T/$L") E2E_TEST_MODE=$(LC_ALL=C grep -a -c 'E2E_TEST_MODE' "$T/$L")"; rm -rf "$T"
echo "== done $(date -u +%T)"
