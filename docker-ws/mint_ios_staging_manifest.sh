#!/bin/bash
# Mint the iOS notification staging attestation + provider request.
#
#   /claude-host-bin/host-run bash docker-ws/mint_ios_staging_manifest.sh
#
# Run AFTER docker-ws/bootstrap_ios_receiver.sh has captured the handoff: the
# receiver's live peer id is read from that handoff. Produces, all 0600 under
# ~/.mknoon-sims/:
#   iospayloadproducer          Go 1.25 payload producer, hashed into the manifest
#   provider-request.json       the three display strings + receiver/peer ids
#   ios-staging-manifest.json   the attestation, minted by the adapter's probe
#
# The probe hashes the signing leaf, the provisioning profile, the fixture
# driver and the producer itself. Nothing secret is written into the manifest.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
umask 077

OUT_DIR="${SIMS_IOS_BOOTSTRAP_OUT_DIR:-$HOME/.mknoon-sims}"
HANDOFF="${SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_PATH:-$OUT_DIR/ios-receiver-handoff.json}"
DERIVED="${SIMS_IOS_BOOTSTRAP_DERIVED_DATA:-$REPO/build/sims/ios-device-production-bootstrap-derived}"
PROFILE="${SIMS_IOS_PROVISIONING_PROFILE_PATH:-$DERIVED/Build/Products/Release-iphoneos/Runner.app/embedded.mobileprovision}"
PRODUCER="$OUT_DIR/iospayloadproducer"
REQUEST="$OUT_DIR/provider-request.json"
MANIFEST="$OUT_DIR/ios-staging-manifest.json"

RECEIVER="${SIMS_IOS_PHYSICAL_DEVICE_ID:-00008030-001A6D2801BB802E}"
RELAY_A='/dns4/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g'
RELAY_B='/dns4/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g'
# Deployed relay identity, as recorded in docker-ws/group-reaction-staging-manifest-315.json.
# Must match ^v[0-9A-Za-z][0-9A-Za-z._+-]{0,127}$ (adapter _RELAY_REVISION).
RELAY_REV="${SIMS_CANDIDATE_RELAY_REVISION:-v1.10.5}"
RELAY_SHA="${SIMS_CANDIDATE_RELAY_SHA256:-10e4bd449208940d061ad05a0ddfda8103200315be8da56ab7c31f7aac2223f1}"

# The three display strings. Constraints from tool/sims/device_binding.dart:641:
# printable ASCII, title <= 30, body <= 512, message <= 140, and neither the
# title nor the body may contain the message text.
TITLE="${SIMS_IOS_EXPECTED_TITLE:-Sims Fixture Sender}"
BODY="${SIMS_IOS_EXPECTED_BODY:-You have a new secure message.}"
MESSAGE="${SIMS_IOS_EXPECTED_MESSAGE:-sims ios payload fast path check}"

export SIMS_IOS_APNS_AUTH_KEY_PATH="${SIMS_IOS_APNS_AUTH_KEY_PATH:-$REPO/APPLE/AuthKey_M7T46H43B2.p8}"
export SIMS_IOS_APNS_KEY_ID="${SIMS_IOS_APNS_KEY_ID:-M7T46H43B2}"
export SIMS_IOS_APNS_TEAM_ID="${SIMS_IOS_APNS_TEAM_ID:-397R9Q4WMX}"
export SIMS_IOS_NOTIFICATION_RELAY_FIXTURE_DRIVER="${SIMS_IOS_NOTIFICATION_RELAY_FIXTURE_DRIVER:-$REPO/integration_test/scripts/ios_notification_relay_fixture_driver.py}"

mkdir -p "$OUT_DIR"
chmod 700 "$OUT_DIR"
[ -f "$HANDOFF" ] || { echo "FATAL: no receiver handoff at $HANDOFF — run docker-ws/bootstrap_ios_receiver.sh first"; exit 2; }
[ -f "$PROFILE" ] || { echo "FATAL: no provisioning profile at $PROFILE"; exit 2; }

PEER="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["peerDeviceId"])' "$HANDOFF")"
[ -n "$PEER" ] || { echo "FATAL: handoff has no peerDeviceId"; exit 2; }
APP_REV="$(git rev-parse HEAD)"
echo "receiver : $RECEIVER"
echo "peer     : $PEER"
echo "app rev  : $APP_REV"
echo

echo "=== building the payload producer (Go 1.25) ==="
(cd go-mknoon && GOTOOLCHAIN=go1.27.1 go build -o "$PRODUCER" ./cmd/iospayloadproducer)
chmod 700 "$PRODUCER"

echo "=== writing the provider request ==="
python3 - "$REQUEST" "$TITLE" "$BODY" "$MESSAGE" "$RECEIVER" "$PEER" <<'PY'
import json, sys
path, title, body, message, receiver, peer = sys.argv[1:7]
request = {
    "schema": "mknoon.sims.ios-payload-fast-path-provider-request.v1",
    "expectedTitle": title,
    "expectedBody": body,
    "expectedMessageText": message,
    "receiverDeviceId": receiver,
    "peerDeviceId": peer,
}
assert len(title) <= 30 and len(body) <= 512 and len(message) <= 140
assert message not in title and message not in body
with open(path, "w") as handle:
    json.dump(request, handle, indent=2)
print(f"  {path}")
PY
chmod 600 "$REQUEST"

echo
echo "=== probing APNs + signing and minting the attestation ==="
rm -f "$MANIFEST"
integration_test/scripts/ios_notification_provider_adapter.py \
  --action probe \
  --receiver "$RECEIVER" \
  --peer-device "$PEER" \
  --provisioning-profile "$PROFILE" \
  --candidate-app-revision "$APP_REV" \
  --candidate-relay-revision "$RELAY_REV" \
  --candidate-relay-sha256 "$RELAY_SHA" \
  --relay-address "$RELAY_A" \
  --relay-address "$RELAY_B" \
  --relay-fixture-driver "$SIMS_IOS_NOTIFICATION_RELAY_FIXTURE_DRIVER" \
  --payload-producer "$PRODUCER" \
  --output "$MANIFEST"

echo
echo "=== attestation ==="
python3 - "$MANIFEST" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
for key in sorted(m):
    value = m[key]
    if isinstance(value, str) and len(value) > 48:
        value = value[:16] + "…"
    print(f"  {key}: {value}")
PY
echo
echo "Export these before running sims:"
echo "  export SIMS_IOS_NOTIFICATION_STAGING_MANIFEST=$MANIFEST"
echo "  export SIMS_IOS_NOTIFICATION_PROVIDER_REQUEST=$REQUEST"
echo "  export SIMS_IOS_NOTIFICATION_PAYLOAD_PRODUCER=$PRODUCER"
