#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

adapter=integration_test/scripts/run_1to1_reaction_notification_sims.dart
runner=integration_test/scripts/run_1to1_reaction_notification_device.dart
capture=integration_test/scripts/capture_1to1_reaction_head_provenance.dart
proof=integration_test/one_to_one_reaction_notification_proof_test.dart

[ -f "$adapter" ] || fail 'typed-reaction Sims adapter is missing'

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

apk="$tmp_dir/production-fcm.apk"
credential="$tmp_dir/service-account.json"
relay_key="$tmp_dir/staging.pem"
staging="$tmp_dir/staging.json"
printf 'central-production-fcm-apk\n' >"$apk"
printf 'fixture-key\n' >"$relay_key"
printf '%s\n' '{"project_id":"contract-project"}' >"$credential"
printf '%s\n' \
  '{"schema":"mknoon.plan257.staging-prerequisites.v1","version":1,"environment":"staging","relayActive":true,"providerConfigured":true,"providerProbeSucceeded":true,"productionDeploymentPerformed":false,"allowAppDataReset":true,"candidateRelayRevision":"contract-revision","candidateRelaySha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","provider":"fcm","relayAddresses":["127.0.0.1:4001"]}' \
  >"$staging"

run_adapter() {
  env \
    MKNOON_RELAY_ADDRESSES='127.0.0.1:4001' \
    MKNOON_257_RELAY_TARGET='staging@example.invalid' \
    MKNOON_257_RELAY_KEY="$relay_key" \
    MKNOON_257_STAGING_MANIFEST="$staging" \
    SIMS_ARTIFACT_ANDROID_PRODUCTION_FCM="$apk" \
    SIMS_ARTIFACT_PROFILE_ID='android.production_fcm' \
    SIMS_PROVIDER_FCM_CREDENTIAL_PATH="$credential" \
    SIMS_ANDROID_PHYSICAL_DEVICE_ID='PLAN392PHYSICAL' \
    SIMS_ANDROID_EMULATOR_DEVICE_ID='emulator-6554' \
    SIMS_PROOF_DIRECTORY="$tmp_dir/proofs" \
    "$@"
}

set +e
output="$(run_adapter dart "$adapter")"
status=$?
set -e
[ "$status" -eq 78 ] || fail "availability preflight exited $status"
[ "$(printf '%s\n' "$output" | grep -c '^SIMS_RESULT_JSON=' || true)" -eq 1 ] ||
  fail 'adapter did not emit exactly one structured result'
[ "$(printf '%s\n' "$output" | awk 'NF { count++ } END { print count + 0 }')" -eq 1 ] ||
  fail 'adapter emitted non-sentinel stdout'
printf '%s\n' "$output" | grep -Fq '"status":"BLOCKED"' ||
  fail 'unavailable targets did not produce BLOCKED'
printf '%s\n' "$output" | grep -Fq '"blocker":"deviceLost"' ||
  fail 'unavailable assigned targets were not typed deviceLost'
printf '%s\n' "$output" | grep -Fq 'android_typed_reaction_smoke' ||
  fail 'blocked result dropped the exact owned selector'

set +e
missing="$(run_adapter env -u SIMS_ARTIFACT_ANDROID_PRODUCTION_FCM dart "$adapter")"
missing_status=$?
set -e
[ "$missing_status" -eq 78 ] || fail 'missing artifact did not exit 78'
printf '%s\n' "$missing" | grep -Fq '"blocker":"missingArtifact"' ||
  fail 'missing central APK was not typed missingArtifact'

python3 - "$adapter" "$runner" "$capture" "$proof" <<'PY'
import re
import sys

adapter, runner, capture, proof = [open(path, encoding="utf-8").read() for path in sys.argv[1:]]

assert "const String _capabilityId = 'notifications.android_typed_reaction_smoke'" in adapter
assert "const String _scenarioId = 'android_typed_reaction_smoke'" in adapter
assert "SIMS_ARTIFACT_ANDROID_PRODUCTION_FCM" in adapter
assert "SIMS_ARTIFACT_PROFILE_ID" in adapter
assert "android.production_fcm" in adapter
assert "capture-${DateTime.now().toUtc().microsecondsSinceEpoch}-$pid" in adapter
assert "captureRoot.existsSync()" not in adapter or "captureRoot.listSync().isNotEmpty" in adapter
assert "--prebuilt-android-apk" in adapter
assert "--no-child-builds" in adapter
assert "--android-state-prepared" in adapter
assert "writeSimsArtifactEvidenceSync" in adapter
assert "auditSimsArtifactEvidence" in adapter
assert "'evidenceKind': 'plan393_g30_diagnostic'" in adapter
assert "'artifactEvidence': evidence.toJson()" in adapter
assert "SimsArtifactEvidence.fromJson" in adapter
assert "proofValue['diagnostic'] is! Map" in adapter
assert "preparedArtifactSha256Before" in adapter
assert "preparedArtifactSha256After" in adapter
assert "childBuildCount" in adapter
assert not re.search(r"Process\.(?:run|start)\([^\n]*(?:flutter build|gradle|xcodebuild)", adapter)

capture_args_start = runner.index("final captureArgs = <String>[")
capture_args_end = runner.index("\n    ];", capture_args_start)
capture_args = runner[capture_args_start:capture_args_end]
for token in ("--prebuilt-android-apk", "--no-child-builds", "--android-state-prepared"):
    assert token in capture_args

for token in (
    "prebuiltAndroidApk",
    "noChildBuilds",
    "statePreparedByParent",
    "buildMode",
    "central_prebuilt",
    "buildProfile",
    "android.production_fcm",
    "childBuildCount",
    "candidate_build_provenance.json",
):
    assert token in capture
assert "if (noChildBuilds" in capture
assert "flutter', [\n      'build'" in capture, "standalone build mode must remain"

conversation_start = capture.index("Future<void> _openConversation(")
conversation_end = capture.index("Map<String, dynamic> _contactEntry", conversation_start)
conversation = capture[conversation_start:conversation_end]
assert "await _waitForValue<String>(" in conversation, (
    "conversation setup samples Flutter only once after Android activity resume"
)
assert "direct chat or chat-list entry point on ${owner.role}" in conversation, (
    "conversation readiness wait is not scoped to the semantic entry points"
)
assert "'Show inner circle'" in conversation, (
    "conversation setup cannot recover when Orbit is already in all-chats view"
)
assert re.search(
    r"findSemanticNodeCenter\(\s*candidate,\s*contactUsername,\s*\)",
    conversation,
), (
    "conversation setup ignores the plain username row in all-chats view"
)
assert "_captureConversationEntryDiagnostic(" in conversation, (
    "conversation timeout does not preserve a sanitized UI diagnosis"
)
assert re.search(r"'exec-out',\s*'screencap',\s*'-p'", capture), (
    "conversation timeout does not capture the actual foreground surface"
)

prepopulate_start = capture.index("Future<void> _prepopulateContactAtStartup(")
prepopulate_end = capture.index("Future<void> _exchangeWakeToken(", prepopulate_start)
prepopulate = capture[prepopulate_start:prepopulate_end]
launch = prepopulate.index("await _launch(owner.deviceId)")
receipt = prepopulate.index("await _waitForIntroE2EStepCompletion(", launch)
delete = prepopulate.index(
    "await _deleteAppFile(owner.deviceId, 'intro_e2e_config.json')", launch
)
assert launch < receipt < delete, (
    "startup contact fixture is deleted before Flutter confirms insertion"
)

setup_start = capture.index("_stage = 'e2e_setup';")
setup_end = capture.index("await _prepopulateContacts();", setup_start)
setup = capture[setup_start:setup_end]
sender_install = setup.index("await _installApk(senderId, _build!.e2eApk)")
recipient_install = setup.index("await _installApk(recipientId, _build!.e2eApk)")
sender_grant = setup.index("await _grantNotificationPermission(senderId)")
recipient_grant = setup.index("await _grantNotificationPermission(recipientId)")
first_launch = setup.index("await _launch(senderId)")
assert max(sender_install, recipient_install) < min(sender_grant, recipient_grant)
assert max(sender_grant, recipient_grant) < first_launch, (
    "Android notification permission can obscure fixture UI before setup"
)

typed_start = proof.index("test('android_typed_reaction_smoke'")
typed_end = proof.index("test('android_durable_reaction_background_connected'", typed_start)
typed = proof[typed_start:typed_end]
for token in ("buildMode", "buildProfile", "childBuildCount", "senderHarnessApkSha256"):
    assert token in typed
PY

python3 - "$runner" "$proof" "$adapter" <<'PY'
import json
import subprocess
import sys

runner, proof, adapter = sys.argv[1:]
manifest = json.load(open("tool/sims/critical_features.json", encoding="utf-8"))
owners = [row for row in manifest["capabilities"] if row["id"] == "notifications.android_typed_reaction_smoke"]
assert len(owners) == 1
row = owners[0]
assert row["required"] is True and row["active"] is True and row["automationReady"] is True
assert row["modes"] == ["major", "full"]
assert row["buildProfile"] == "android.production_fcm"
assert row["dependencies"] == ["build.android.production_fcm"]
assert row["command"] == ["dart", "run", adapter]
assert row["artifactRequired"] is True

roots = json.load(open("tool/runtime_roots/runtime_roots.json", encoding="utf-8"))
matches = [entry for entry in roots["externalEntrypoints"] if entry["path"] == adapter]
assert len(matches) == 1 and matches[0]["seedsTooling"] is True
assert any(
    evidence.get("source") == "tool/sims/critical_features.json"
    and evidence.get("value") == adapter
    for evidence in matches[0]["evidence"]
)

listed = subprocess.check_output(["dart", runner, "--list-scenarios"], text=True).splitlines()
assert listed == [
    "head_provenance",
    "android_typed_reaction_smoke",
    "android_durable_reaction_background_connected",
    "android_background_crypto_preflight",
    "android_first_wake_profile_aot",
    "android_message_unread_lifecycle",
    "android_physical_recipient",
    "ios_physical_recipient",
]

registry = open("test/tool/sims/sims_proof_binding_registry_test.dart", encoding="utf-8").read()
assert proof not in registry.split("const _captureOwnedBindings", 1)[1].split("};", 1)[0]
inventory = open("scripts/test/sims_full_inventory_contract_test.sh", encoding="utf-8").read()
assert runner not in inventory.split("excluded = {", 1)[1].split("}", 1)[0]
PY

tsv="$tmp_dir/discovery.tsv"
./scripts/check_reliability_simulation_discovery.sh --records-tsv >"$tsv"
awk -F'\t' -v path="$adapter" '$3 == path {print $1 "\t" $2}' "$tsv" |
  grep -Fxq $'support\tsupport' ||
  fail 'typed adapter is not support-classified in reliability discovery'
awk -F'\t' -v path="$runner" '$3 == path {print $1 "\t" $2}' "$tsv" |
  grep -Fxq $'1to1\trunner' ||
  fail 'shared reaction runner was reclassified'
awk -F'\t' -v path="$proof" '$3 == path {print $1 "\t" $2}' "$tsv" |
  grep -Fxq $'1to1\ttest' ||
  fail 'shared reaction proof was reclassified'

printf 'PASS: typed 1:1 reaction has one central-prebuilt Sims owner\n'
