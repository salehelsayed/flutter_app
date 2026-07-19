#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

adapter='integration_test/scripts/run_connectivity_restore_media_outbox_sims.dart'
manifest='tool/sims/critical_features.json'
endpoint='lib/core/debug/private_media_outbox_e2e.dart'
conversation_endpoint='lib/core/debug/private_media_outbox_e2e_conversation.dart'
protocol='lib/core/debug/private_media_outbox_e2e_protocol.dart'
observer='lib/core/debug/intro_e2e_runner.dart'
main_wiring='lib/main.dart'
conversation_wiring='lib/features/conversation/presentation/screens/conversation_wired.dart'

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

for path in "$adapter" "$endpoint" "$conversation_endpoint" "$protocol" \
  "$observer" "$main_wiring" "$conversation_wiring"; do
  [[ -f "$path" ]] || fail "required production proof file is missing: $path"
done

rg -q 'SIMS_ARTIFACT_ANDROID_E2E_MAIN' "$adapter" ||
  fail 'adapter does not consume the centrally prepared main APK'
rg -q 'SIMS_ANDROID_PHYSICAL_DEVICE_ID' "$adapter" ||
  fail 'adapter does not consume the physical Android control target'
rg -q 'SIMS_ANDROID_EMULATOR_DEVICE_ID' "$adapter" ||
  fail 'adapter does not consume the Android recipient target'
rg -q 'privateMediaOutboxE2EAction' "$adapter" ||
  fail 'adapter does not drive the dedicated production action'
rg -q 'final messageId = _exactMessageId()' "$adapter" ||
  fail 'adapter does not use a complete event-correlatable message ID'
rg -q 'airplane-mode' "$adapter" ||
  fail 'adapter does not drive real Android network loss and restore'
rg -q "'physicalSenderTargetSha256': privateMediaOutboxTargetSha256" "$adapter" ||
  fail 'durable artifact does not hash the physical sender target'
rg -q "'emulatorReceiverTargetSha256': privateMediaOutboxTargetSha256" "$adapter" ||
  fail 'durable artifact does not hash the emulator receiver target'
if rg -q "'deviceIds': <String>\[physical, emulator\]" "$adapter"; then
  fail 'durable artifact retains raw ADB target IDs'
fi
rg -q 'Duration\(seconds: 31\)' "$adapter" ||
  fail 'phase two does not preserve the required offline dwell'
rg -q 'const Duration _offlineObservationDwell = Duration\(seconds: 2\)' "$adapter" ||
  fail 'sender isolation does not preserve the app-observation dwell'
rg -q "'KEYCODE_HOME'" "$adapter" ||
  fail 'phase two does not background the production app'
rg -q "'am'.*'start'|'start'.*MainActivity" "$adapter" ||
  fail 'phase two does not resume the production app'
rg -q "'childFlutterBuilds': 0" "$adapter" ||
  fail 'artifact does not attest zero child Flutter builds'
if rg -q "Process\.(run|start)\(['\"]flutter|flutter (build|drive|run)" "$adapter"; then
  fail 'adapter contains a child Flutter invocation'
fi

python3 - "$adapter" <<'PY'
import sys

source = open(sys.argv[1], encoding='utf-8').read()
phase_start = source.index('Future<Map<String, Object?>> _runPhase(')
phase_end = source.index('Map<String, Object?> _buildPhaseArtifact(', phase_start)
phase = source[phase_start:phase_end]
sender_stage = phase.index('await _stagePrivateRequest(physical')
sender_armed = phase.index("expectedStatus: 'armed'", sender_stage)
network_mutation = phase.index('markNetworkMutated()', sender_armed)
network_off = phase.index('await _setNetworkAvailable(physical, false)', network_mutation)
offline_observed = phase.index("'physical Android offline state", network_off)
offline_dwell = phase.index(
    'await Future<void>.delayed(_offlineObservationDwell)', offline_observed
)
offline_recheck = phase.index(
    'if (await _networkAvailable(physical))', offline_dwell
)
sender_release = phase.index('await _releasePrivateMediaSender', offline_recheck)
sender_queued = phase.index("expectedStatus: 'queued'", sender_release)
assert (
    sender_stage < sender_armed < network_mutation < network_off <
    offline_observed < offline_dwell < offline_recheck < sender_release <
    sender_queued
)

start = source.index('final class _NetworkState')
end = source.index('final class _Identity', start)
network = source[start:end]
restore = network[network.index('Future<void> restore('):]

for field in ('airplaneEnabled', 'wifiEnabled', 'dataEnabled'):
    assert f'current.{field} == {field}' in restore
assert "'exact physical Android network-state restoration'" in restore
assert 'const Duration(seconds: 30)' in restore
assert '_NetworkState.capture(campaign, device)' in restore
assert restore.index("'svc', 'data'") < restore.index('campaign._waitFor(')
assert restore.index('campaign._waitFor(') < restore.index(
    '_NetworkState.capture(campaign, device)'
)
PY

python3 - "$manifest" <<'PY'
import json, sys

with open(sys.argv[1], encoding='utf-8') as handle:
    manifest = json.load(handle)

rows = {row['id']: row for row in manifest['capabilities']}
campaign = rows['android.connectivity_restore_media_outbox']
assert campaign['command'] == [
    'dart', 'run',
    'integration_test/scripts/run_connectivity_restore_media_outbox_sims.dart',
]
assert campaign['buildProfile'] == 'android.e2e.main'
assert campaign['dependencies'] == ['build.android.e2e.main']
assert campaign['artifactValidator'] == 'validatePrivateMediaOutboxRestoreArtifact'
resources = {row['name']: row['access'] for row in campaign['resources']}
assert resources['device-control:android-physical'] == 'exclusive'
assert resources['device:android-emulator'] == 'exclusive'
assert resources['relay-mutation:staging'] == 'exclusive'
assert resources['artifact:private-media-outbox'] == 'write'
PY

python3 - "$endpoint" "$conversation_endpoint" "$protocol" "$observer" \
  "$main_wiring" "$conversation_wiring" <<'PY'
import sys

endpoint = open(sys.argv[1], encoding='utf-8').read()
conversation_endpoint = open(sys.argv[2], encoding='utf-8').read()
protocol = open(sys.argv[3], encoding='utf-8').read()
observer = open(sys.argv[4], encoding='utf-8').read()
main = open(sys.argv[5], encoding='utf-8').read()
conversation = open(sys.argv[6], encoding='utf-8').read()

for event in (
    'PENDING_RETRIER_NETWORK_RESTORED_TRIGGER',
    'MEDIA_UPLOAD_LEASE_CLAIMED',
    'MEDIA_ENCRYPTION_PREPARED',
    'MEDIA_UPLOAD_START',
    'CHAT_MSG_SEND_SUCCESS',
    'PRIVATE_MEDIA_OUTBOX_E2E_RECEIVED',
):
    assert event in protocol

poller = observer.index('void startIntroE2EPoller')
branch = observer.index('privateMediaOutboxE2EAction', poller)
generic = observer.index('await runIntroE2EActions(', poller)
assert branch < generic
private_branch_end = observer.index(
    'if (isGroupReactionE2EProbeAction', branch
)
private_branch = observer[branch:private_branch_end]
delete_config = private_branch.index('await _deleteConfigIfPresent();')
profile_guard = private_branch.index('requirePrivateMediaOutboxE2EBuildProfile();')
ensure_endpoint = private_branch.index('ensurePrivateMediaOutboxE2EEndpoint')
dispatch = private_branch.index('await controller.run')
terminal_result = private_branch.index('await _writeIntroE2EResult', dispatch)
assert private_branch.count('await _deleteConfigIfPresent();') == 1
assert delete_config < profile_guard < ensure_endpoint < dispatch < terminal_result
assert '_waitForPrivateMediaOutboxE2EHostRelease' in private_branch[dispatch:terminal_result]
assert 'runCorrelationSha256' in endpoint
assert 'resumed_queued' in endpoint
assert 'privateMediaOutboxE2EHostRelease' in endpoint
assert 'PrivateMediaOutboxE2EConversationEndpoint' in conversation_endpoint
assert 'PrivateMediaOutboxE2EFlowCapture' in conversation_endpoint
assert 'privateMediaOutboxE2EHostReleaseSchema' in protocol

sender_capture = conversation_endpoint.index(
    'final capture = PrivateMediaOutboxE2EFlowCapture(request)..start();'
)
sender_endpoint = conversation_endpoint[sender_capture:]
sender_armed = sender_endpoint.index(
    'writeProgress(privateMediaOutboxE2EArmedReceipt(request))'
)
host_release = sender_endpoint.index('await waitForSenderHostRelease()')
offline_confirmation = sender_endpoint.index(
    'await waitForSenderOfflineObservation()', host_release
)
production_send = sender_endpoint.index('await sendPrivateMedia(request)')
delivery_signal = sender_endpoint.index('await capture.waitForRestoredDeliverySignal()')
sender_settled = sender_endpoint.index("label: 'settled outgoing private media'")
quiet_seal = sender_endpoint.index('await capture.sealAfterQuietPeriod')
assert 0 < sender_armed < host_release < offline_confirmation < production_send
assert production_send < delivery_signal < sender_settled < quiet_seal
assert '_exactSenderEventOrder' in conversation_endpoint

assert 'privateMediaOutboxE2EController' in main
assert 'startIntroE2EPoller(' in main
assert main.count('privateMediaOutboxE2EController:') >= 4
assert 'registerEndpoint(' in conversation
assert '_runPrivateMediaOutboxE2E' in conversation
assert 'createPrivateMediaOutboxE2ESource(' in conversation
assert "await _onSend('');" in conversation
offline_wait_start = conversation.index(
    'Future<void> _waitForPrivateMediaOutboxE2EOfflineConnectivity('
)
offline_wait_end = conversation.index(
    'PrivateMediaPolicy _privateMediaOutboxPolicy(', offline_wait_start
)
offline_wait = conversation[offline_wait_start:offline_wait_end]
assert 'Connectivity().checkConnectivity()' in offline_wait
assert 'result == ConnectivityResult.none' in offline_wait
sender_delivered_start = conversation.index(
    'Future<bool> _isPrivateMediaOutboxE2ESenderDelivered('
)
sender_delivered_end = conversation.index(
    'Future<bool> _isPrivateMediaOutboxE2EReceiverDelivered(',
    sender_delivered_start,
)
sender_delivered = conversation[sender_delivered_start:sender_delivered_end]
assert "attachment.downloadStatus != 'done'" in sender_delivered
assert 'wireEnvelope' not in sender_delivered
PY

set +e
output="$(env -u SIMS_ARTIFACT_ANDROID_E2E_MAIN dart run "$adapter" 2>&1)"
status=$?
set -e
[[ $status -eq 78 ]] ||
  fail "missing prepared APK returned $status, expected 78"
[[ "$(printf '%s\n' "$output" | grep -o 'SIMS_RESULT_JSON=' | wc -l | tr -d ' ')" -eq 1 ]] ||
  fail 'missing prepared APK did not emit one structured result'
[[ "$output" == *'"status":"BLOCKED"'* ]] ||
  fail 'missing prepared APK did not emit a typed BLOCKED result'
[[ "$output" == *'"artifactPresent":false'* ]] ||
  fail 'missing prepared APK claimed artifact evidence'

printf 'PASS: private-media outbox restore adapter is production-driving and build-free\n'
