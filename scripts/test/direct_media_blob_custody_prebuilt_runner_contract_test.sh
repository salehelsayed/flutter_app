#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

adapter=integration_test/scripts/run_direct_media_blob_custody_sims.dart
campaign=integration_test/scripts/android_direct_media_blob_custody_campaign.dart
device_action=integration_test/scripts/android_direct_media_blob_custody_device_action.dart
evidence=integration_test/support/android_direct_media_blob_custody_evidence.dart
dispatcher=integration_test/scripts/run_1to1_device_real.dart
fixture=go-relay-server/direct_media_blob_custody_device_fixture_test.go
app_action=lib/debug/android_direct_media_blob_custody_e2e.dart
app_protocol=lib/core/debug/android_direct_media_blob_custody_e2e_protocol.dart

for path in "$adapter" "$campaign" "$device_action" "$evidence" \
  "$dispatcher" "$fixture" "$app_action" "$app_protocol"; do
  [ -f "$path" ] || fail "missing Plan 347 contract file: $path"
done

jq -e '
  ([.buildProfiles[] | select(.id == "android.e2e.direct_media_custody")] == [{
    "id": "android.e2e.direct_media_custody",
    "platform": "android",
    "artifactKind": "universal-debug-apk",
    "buildRequired": true,
    "compileDefines": {
      "E2E_TEST_MODE": "true",
      "MKNOON_DIRECT_MEDIA_BLOB_CUSTODY_CLIENT_ENABLED": "true"
    },
    "declaredException": false
  }]) and
  ([.capabilities[] | select(.id == "build.android.e2e.direct_media_custody")] | length == 1) and
  ([.capabilities[] | select(.id == "android.direct_media_blob_custody")] | length == 1) and
  (.capabilities[] | select(.id == "android.direct_media_blob_custody") |
    .buildProfile == "android.e2e.direct_media_custody" and
    .dependencies == ["build.android.e2e.direct_media_custody"] and
    .command == ["dart", "run", "integration_test/scripts/run_1to1_device_real.dart", "--scenario", "android.direct_media_blob_custody"] and
    .artifactValidator == "validateDirectMediaBlobCustodyArtifact" and
    .targetCapabilities == ["android.physical", "android.emulator"] and
    any(.resources[]; .name == "device:android-physical" and .access == "exclusive") and
    any(.resources[]; .name == "device:android-emulator" and .access == "exclusive") and
    any(.resources[]; .name == "relay-mutation:local-direct-media-fixture" and .access == "exclusive"))
' tool/sims/critical_features.json >/dev/null ||
  fail 'Plan 347 build profile/capability is incomplete, duplicated, or over-enabled'

if rg -n 'flutter[[:space:]]+(build|drive)|xcrun|simctl' \
  "$adapter" "$campaign" "$device_action" >/dev/null; then
  fail 'Plan 347 adapter/campaign contains a child mobile build/drive or iOS command'
fi
rg -Fq "'--prepare-builds'" "$adapter" ||
  fail 'adapter does not invoke central Sims preparation'
rg -Fq 'result = await _runCentralSims(' "$adapter" ||
  fail 'adapter does not invoke central Sims scenario execution separately'
rg -Fq 'finally {' "$adapter" ||
  fail 'adapter has no finally-owned fixture teardown'
rg -Fq 'await fixture.stop();' "$adapter" ||
  fail 'adapter finally block does not stop the fixture'
rg -Fq "'PLAN347_FIXTURE_STOP_EXECUTABLE'" "$adapter" ||
  fail 'adapter does not expose the test-only fixture stop injection seam'
rg -Fq '.postUrl(Uri.parse(probeUrl))' "$adapter" ||
  fail 'adapter production teardown does not POST to the capability-bound probe'
rg -Fq 'HttpStatus.noContent' "$adapter" ||
  fail 'adapter production teardown does not require the exact no-content response'
rg -Fq 'AndroidDirectMediaBlobCustodyDeviceDriver?' "$dispatcher" ||
  fail 'existing 1:1 dispatcher does not expose injectable Plan 347 wiring'
rg -Fq 'runAndroidDirectMediaBlobCustodyAdbDeviceAction' "$campaign" ||
  fail 'campaign does not select the concrete ADB action by default'
for fragment in \
  "androidDirectMediaBlobCustodySenderPreparePhase" \
  "DirectMediaBlobCustodyState.outgoingStored" \
  "await Completer<void>().future" \
  "androidDirectMediaBlobCustodySenderResumePhase" \
  "StrictDirectMediaBlobDownloadAckOwner(" \
  "beforeSourcePinnedAck:" \
  ".downloadAndAcknowledge(" \
  "androidDirectMediaBlobCustodyE2EFailureReceipt"; do
  rg -Fq "$fragment" "$app_action" ||
    fail "app action omitted fail-closed custody fragment: $fragment"
done
if rg -n 'callP2PMedia(Upload|Download|Delete)\(' "$app_action" >/dev/null; then
  fail 'debug app action bypasses the production strict network owners'
fi
for fragment in \
  "'force-stop'" \
  "'pidof'" \
  "receiverPidWhileArmed" \
  "senderPidBeforeRestart" \
  "receiverPidBeforeRestart" \
  "_fixtureProtectedCount" \
  "protectedBeforeAck" \
  "protectedAfterAck"; do
  rg -Fq "$fragment" "$device_action" ||
    fail "device action omitted process choreography: $fragment"
done
if rg -n "'(senderRestartObserved|strictCommitmentVerified|envelopeExpiryWithinBlobBound|durableLocalCommit|ackSourcePinned|relayProtectedAbsentAfterAck)':[[:space:]]*true" \
  "$device_action" "$app_action" >/dev/null; then
  fail 'device/app action hard-codes derived custody evidence'
fi

listed="$(dart "$dispatcher" --scenario android.direct_media_blob_custody --list-scenarios)"
[ "$listed" = android.direct_media_blob_custody ] ||
  fail 'existing 1:1 dispatcher does not list the exact Plan 347 scenario'

missing_output="$(mktemp)"
set +e
env -u SIMS_ARTIFACT_ANDROID_E2E_DIRECT_MEDIA_CUSTODY \
  dart "$dispatcher" \
    --scenario android.direct_media_blob_custody \
    --device pixel-usb \
    --device emulator-5554 >"$missing_output" 2>&1
missing_exit=$?
set -e
[ "$missing_exit" -eq 78 ] ||
  fail "missing Plan 347 APK exited $missing_exit instead of BLOCKED/78"
grep -Fq '"blocker":"missingArtifact"' "$missing_output" ||
  fail 'missing Plan 347 APK did not fail closed before device mutation'
rm -f "$missing_output"

for fragment in \
  '//go:build integration' \
  'TestDirectMediaBlobCustodyDeviceFixtureContract' \
  'newControlPlaneStores' \
  'backendKindRedis' \
  'NewMediaStore' \
  'HandleRendezvousStream' \
  'HandleInboxStream' \
  'HandleMediaStream' \
  'ProbeURL' \
  'directMediaFixturePendingProtectedCount' \
  'mediaCustodyStatePending' \
  'ackCustodyAdmissionEnabledEnv' \
  'mediaCustodyAdmissionEnabledEnv'; do
  rg -Fq "$fragment" "$fixture" ||
    fail "fixture omitted production contract fragment: $fragment"
done

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
go_log="$tmp_dir/go.log"
adb_log="$tmp_dir/adb.log"
sims_log="$tmp_dir/sims.log"
stop_log="$tmp_dir/stop.log"
stop_marker="$tmp_dir/fixture-stopped"
go_shim="$tmp_dir/go"
adb_shim="$tmp_dir/adb"
dart_shim="$tmp_dir/dart-sims"
stop_shim="$tmp_dir/fixture-stop"

cat >"$go_shim" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'args=%s ack=%s media=%s host=%s\n' "$*" \
  "${DIRECT_INBOX_ACK_CUSTODY_ADMISSION_ENABLED-}" \
  "${DIRECT_MEDIA_BLOB_CUSTODY_ADMISSION_ENABLED-}" \
  "${MKNOON_DIRECT_MEDIA_DEVICE_FIXTURE_HOST_IP-}" >>"${PLAN347_GO_LOG:?}"
printf '%s\n' 'MKNOON_DIRECT_MEDIA_FIXTURE_READY={"schema":"mknoon.plan347.direct-media-fixture.v1","multiaddr":"/ip4/192.0.2.10/tcp/40123/p2p/12D3KooWFixture","probeUrl":"http://192.0.2.10:40124/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc","fixtureIdentitySha256":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb","backend":"redis","ephemeral":true,"ackCustodyAdmissionEnabled":true,"mediaCustodyAdmissionEnabled":true}'
while [ ! -f "${PLAN347_STOP_MARKER:?}" ]; do
  sleep 0.01
done
printf 'fixture-stop-marker=observed\n' >>"${PLAN347_GO_LOG:?}"
SH

cat >"$adb_shim" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"${PLAN347_ADB_LOG:?}"
device=""
if [ "${1-}" = -s ]; then
  device="${2-}"
  shift 2
fi
if [ "$*" = 'shell getprop ro.kernel.qemu' ]; then
  if [ "$device" = emulator-5554 ]; then
    printf '1\n'
  else
    printf '0\n'
  fi
fi
SH

cat >"$dart_shim" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
printf 'args=%s relay=%s fixture=%s probe=%s devices=%s physical=%s emulator=%s\n' "$*" \
  "${MKNOON_RELAY_ADDRESSES-}" \
  "${MKNOON_DIRECT_MEDIA_CUSTODY_FIXTURE_IDENTITY_SHA256-}" \
  "${MKNOON_DIRECT_MEDIA_CUSTODY_FIXTURE_PROBE_URL-}" \
  "${RELIABILITY_MULTI_DEVICE_IDS-}" \
  "${SIMS_ANDROID_PHYSICAL_DEVICE_ID-}" \
  "${SIMS_ANDROID_EMULATOR_DEVICE_ID-}" >>"${PLAN347_SIMS_LOG:?}"
SH

cat >"$stop_shim" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[ "$#" -eq 1 ] || exit 64
printf 'probe=%s\n' "$1" >>"${PLAN347_STOP_LOG:?}"
touch "${PLAN347_STOP_MARKER:?}"
SH
chmod +x "$go_shim" "$adb_shim" "$dart_shim" "$stop_shim"

set +e
PLAN347_GO_EXECUTABLE="$go_shim" \
PLAN347_ADB_EXECUTABLE="$adb_shim" \
PLAN347_SIMS_DART_EXECUTABLE="$dart_shim" \
PLAN347_FIXTURE_STOP_EXECUTABLE="$stop_shim" \
PLAN347_FIXTURE_HOST_IP=192.0.2.10 \
PLAN347_GO_LOG="$go_log" \
PLAN347_ADB_LOG="$adb_log" \
PLAN347_SIMS_LOG="$sims_log" \
PLAN347_STOP_LOG="$stop_log" \
PLAN347_STOP_MARKER="$stop_marker" \
RELIABILITY_MULTI_DEVICE_IDS=pixel-usb,emulator-5554 \
  dart run "$adapter" \
    --mode major \
    --scenario android.direct_media_blob_custody >/dev/null
adapter_exit=$?
set -e

[ "$adapter_exit" -eq 0 ] ||
  fail "adapter exited $adapter_exit instead of completing teardown with exit 0"

grep -Fq 'ack=true media=true host=192.0.2.10' "$go_log" ||
  fail 'fixture did not receive both admissions and the exact reachable host'
grep -Fq 'fixture-stop-marker=observed' "$go_log" ||
  fail 'fixture did not remain alive until the injected stop command completed'
[ "$(wc -l <"$stop_log" | tr -d ' ')" -eq 1 ] ||
  fail 'adapter did not invoke the fixture stop command exactly once'
grep -Fxq 'probe=http://192.0.2.10:40124/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc' "$stop_log" ||
  fail 'adapter did not pass the exact capability-bound probe URL to fixture teardown'
[ "$(wc -l <"$sims_log" | tr -d ' ')" -eq 2 ] ||
  fail 'adapter did not perform exactly one prepare and one execute operation'
sed -n '1p' "$sims_log" | grep -Fq \
  'args=run tool/sims/sims.dart major --only android.direct_media_blob_custody --prepare-builds' ||
  fail 'central preparation was not the first Sims operation'
sed -n '2p' "$sims_log" | grep -Fq \
  'args=run tool/sims/sims.dart major --only android.direct_media_blob_custody' ||
  fail 'central execution was not the second Sims operation'
grep -Fq 'relay=/ip4/192.0.2.10/tcp/40123/p2p/12D3KooWFixture' "$sims_log" ||
  fail 'fixture address was not injected before central preparation/execution'
grep -Fq 'probe=http://192.0.2.10:40124/cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc' "$sims_log" ||
  fail 'fixture protected-state probe was not injected before execution'
grep -Fq 'devices=pixel-usb,emulator-5554' "$sims_log" ||
  fail 'adapter did not retain the explicit physical/emulator selectors'
grep -Fq 'physical=pixel-usb emulator=emulator-5554' "$sims_log" ||
  fail 'adapter did not pin the exact classified devices into Sims resources'
[ "$(grep -c 'toybox nc -z -w 5 192.0.2.10 40123' "$adb_log")" -eq 2 ] ||
  fail 'adapter did not prove fixture reachability from both Android targets'

printf 'PASS: Plan 347 disposable-relay adapter is central-build-only, Android-pair bounded, and teardown-safe\n'
