#!/bin/bash
# Plan 386 — run ONE reaction-catalog scenario against the live relay.
#
# The full campaign fails fast, so a scenario after the first failure never gets
# a chance to run. This isolates one scenario id so the counter-delta repair can
# be exercised on a REACTION lane (the two message lanes already passed), using
# the same prepared production-FCM APK the campaign attested.
#
# Usage (host side):
#   /claude-host-bin/host-run bash docker-ws/run_reaction_scenario_386.sh <scenario-id>
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

scenario="${1:?scenario id required}"

export MKNOON_RELAY_ADDRESSES='/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns4/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g'
export MKNOON_257_RELAY_TARGET='ubuntu@mknoun.xyz'
export MKNOON_257_RELAY_KEY="$REPO/se.pem"
export FIREBASE_SERVICE_ACCOUNT="$REPO/mknoon-c6e62-firebase-adminsdk-fbsvc-70e1a8d4fb.json"
export MKNOON_257_STAGING_MANIFEST="$REPO/docker-ws/group-reaction-staging-manifest-315.json"

apk="$(ls -t "$REPO"/build/sims/cache/android.production_fcm/*/artifact.apk 2>/dev/null | head -1)"
[ -n "$apk" ] || { echo "FATAL: no prepared android.production_fcm APK in the sims cache"; exit 2; }
[ -f "$FIREBASE_SERVICE_ACCOUNT" ] || { echo "FATAL: service account json missing"; exit 2; }
[ -f "$MKNOON_257_RELAY_KEY" ] || { echo "FATAL: relay key missing"; exit 2; }

out="$REPO/build/sims/proofs/plan386-single/$scenario"
rm -rf "$out"
mkdir -p "$out"

echo "scenario=$scenario"
echo "apk=$apk"
echo "artifacts=$out"

exec dart run integration_test/scripts/run_group_reaction_notification_device.dart \
  --scenario "$scenario" \
  --sender emulator-5554 \
  --recipient 21071FDF600CSC \
  --artifact-dir "$out" \
  --prebuilt-android-apk "$apk" \
  --no-child-builds
