#!/bin/bash
# One-time bootstrap for the physical-iPhone notification proof.
#
#   /claude-host-bin/host-run bash docker-ws/bootstrap_ios_receiver.sh
#
# Breaks the ordering knot in the sims iOS notification rows: the staging
# attestation needs the receiver's live libp2p peer id, the peer id comes from
# ios_receiver_bootstrap.py, and that helper only talks to a
# bootstrap-enabled `ios.device.production` build — which sims refuses to build
# until the attestation exists. So this builds and installs that app OUTSIDE
# the gate, captures the handoff, and prints the peer id.
#
# It reproduces tool/sims/build_orchestrator.dart:_buildIosDevice for the
# `ios.device.production` profile: same scheme, configuration, compile
# conditions, entrypoint and dart-defines. It does NOT write to the sims build
# cache; sims still builds its own attested artifact afterwards.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
umask 077

RECEIVER="${SIMS_IOS_PHYSICAL_DEVICE_ID:-00008030-001A6D2801BB802E}"
export SIMS_IOS_PHYSICAL_DEVICE_ID="$RECEIVER"
export MKNOON_RELAY_ADDRESSES="${MKNOON_RELAY_ADDRESSES:-/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns4/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g}"

DERIVED="${SIMS_IOS_BOOTSTRAP_DERIVED_DATA:-$REPO/build/sims/ios-device-production-bootstrap-derived}"
OUT_DIR="${SIMS_IOS_BOOTSTRAP_OUT_DIR:-$HOME/.mknoon-sims}"
HANDOFF="${SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_PATH:-$OUT_DIR/ios-receiver-handoff.json}"
mkdir -p "$OUT_DIR"
chmod 700 "$OUT_DIR"

skip_build=0
for arg in "$@"; do
  if [ "$arg" = "--skip-build" ]; then
    skip_build=1
  fi
done

# dart-defines exactly as effectiveSimsCompileDefines() computes them for this
# profile: the manifest's PRODUCTION_APNS, the reserved profile id, and the
# relay addresses.
DART_DEFINES="$(python3 - "$MKNOON_RELAY_ADDRESSES" <<'PY'
import base64, sys
defines = {
    "PRODUCTION_APNS": "true",
    "SIMS_BUILD_PROFILE_ID": "ios.device.production",
    "MKNOON_RELAY_ADDRESSES": sys.argv[1],
}
print(",".join(base64.b64encode(f"{k}={v}".encode()).decode() for k, v in defines.items()))
PY
)"

if [ "$skip_build" -eq 0 ]; then
  echo "=== building ios.device.production (bootstrap-enabled) ==="
  rm -rf "$DERIVED"
  mkdir -p "$DERIVED"
  xcodebuild build-for-testing \
    -workspace ios/Runner.xcworkspace \
    -scheme Runner \
    -configuration Release \
    ENABLE_TESTABILITY=YES \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$DERIVED" \
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS=$(inherited) MKNOON_SIMS_IOS_RECEIVER_BOOTSTRAP' \
    FLUTTER_TARGET=lib/main.dart \
    "DART_DEFINES=$DART_DEFINES"
else
  echo "=== reusing existing build at $DERIVED ==="
fi

APP="$DERIVED/Build/Products/Release-iphoneos/Runner.app"
[ -d "$APP" ] || { echo "FATAL: built app not found at $APP"; exit 2; }

echo
echo "=== installing over the existing com.mknoon.app on $RECEIVER ==="
xcrun devicectl device install app --device "$RECEIVER" "$APP"

echo
echo "=== capturing the receiver handoff ==="
export SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_NONCE="${SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_NONCE:-$(uuidgen)}"
export SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_PATH="$HANDOFF"
rm -f "$HANDOFF"
integration_test/scripts/ios_receiver_bootstrap.py

echo
echo "=== handoff summary (no token, no keys) ==="
python3 - "$HANDOFF" "$SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_NONCE" <<'PY'
import json, sys
h = json.load(open(sys.argv[1]))
safe = ("schema", "receiverDeviceId", "peerDeviceId", "bundleId", "apnsEnvironment",
        "notificationAuthorization", "notificationAlertSetting",
        "notificationBadgeSetting", "capturedAt")
for key in safe:
    if key in h:
        print(f"  {key}: {h[key]}")
print()
print("Reuse with:")
print(f"  export SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_PATH={sys.argv[1]}")
print(f"  export SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_NONCE={sys.argv[2]}")
print(f"  peer device id: {h.get('peerDeviceId')}")
PY
