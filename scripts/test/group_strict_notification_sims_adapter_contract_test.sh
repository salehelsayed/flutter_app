#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

ADAPTER='integration_test/scripts/run_group_strict_notification_sims.dart'
DART_BIN="$(command -v dart)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

criteria="$($DART_BIN "$ADAPTER" --list-criteria)"
[ "$(printf '%s\n' "$criteria" | awk 'NF { count++ } END { print count + 0 }')" -eq 5 ] ||
  fail 'strict adapter did not list exactly five assertions'
for criterion in \
  groups.strict_exact_chat_suppressed \
  groups.strict_message_killed_card \
  groups.strict_reaction_author_card \
  groups.strict_relay_provenance \
  groups.strict_state_restored; do
  [ "$(printf '%s\n' "$criteria" | grep -cx "$criterion" || true)" -eq 1 ] ||
    fail "strict criterion missing or duplicated: $criterion"
done

"$DART_BIN" "$ADAPTER" --probe-source-extension |
  grep -q '^READY: strict source extension\.$' ||
  fail 'shared capture source extension is not ready'

APK="$TMP_DIR/base.apk"
CREDENTIAL="$TMP_DIR/service-account.json"
RELAY_KEY="$TMP_DIR/staging.pem"
STAGING="$TMP_DIR/staging.json"
: >"$APK"
: >"$RELAY_KEY"
printf '%s\n' '{"project_id":"contract-project"}' >"$CREDENTIAL"
printf '%s\n' \
  '{"schema":"mknoon.plan257.staging-prerequisites.v1","version":1,"environment":"staging","relayActive":true,"providerConfigured":true,"providerProbeSucceeded":true,"productionDeploymentPerformed":false,"allowAppDataReset":true,"candidateRelayRevision":"contract-revision","candidateRelaySha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","provider":"fcm","relayAddresses":["127.0.0.1:4001"]}' \
  >"$STAGING"

set +e
output="$(env \
  MKNOON_RELAY_ADDRESSES='127.0.0.1:4001' \
  MKNOON_257_RELAY_TARGET='staging@example.invalid' \
  MKNOON_257_RELAY_KEY="$RELAY_KEY" \
  MKNOON_257_STAGING_MANIFEST="$STAGING" \
  SIMS_ARTIFACT_ANDROID_PRODUCTION_FCM="$APK" \
  SIMS_PROVIDER_FCM_CREDENTIAL_PATH="$CREDENTIAL" \
  SIMS_ANDROID_PHYSICAL_DEVICE_ID='PHYSICAL123' \
  SIMS_ANDROID_EMULATOR_DEVICE_ID='emulator-5554' \
  "$DART_BIN" "$ADAPTER")"
status=$?
set -e
[ "$status" -eq 78 ] || fail "unavailable-device preflight exited $status"
[ "$(printf '%s\n' "$output" | grep -c '^SIMS_RESULT_JSON=' || true)" -eq 1 ] ||
  fail 'strict adapter did not emit one result sentinel'
printf '%s\n' "$output" | grep -q '"status":"BLOCKED"' ||
  fail 'strict adapter did not block unavailable targets'
printf '%s\n' "$output" | grep -q '"blocker":"deviceLost"' ||
  fail 'strict adapter misclassified unavailable targets'
printf '%s\n' "$output" | grep -q '"assertionsAttempted":0' ||
  fail 'strict preflight claimed attempted assertions'

grep -q "SIMS_ARTIFACT_ANDROID_PRODUCTION_FCM" "$ADAPTER" ||
  fail 'strict adapter does not consume the central base APK'
grep -q "'--no-child-builds'" "$ADAPTER" ||
  fail 'strict adapter does not forbid child builds'
grep -q "await stateGuard.restoreAll()" "$ADAPTER" ||
  fail 'strict adapter does not restore exact Android state'
grep -q "'stateRestored': true" "$ADAPTER" ||
  fail 'strict aggregate lacks post-restoration evidence'
grep -q "group_strict_notification_authority" \
  integration_test/scripts/capture_group_reaction_notification_device.dart ||
  fail 'shared capture does not use the strict authority endpoint'
grep -q "setGroupContentAuthoringResolver(groupRepository" \
  lib/debug/group_strict_notification_e2e_action.dart ||
  fail 'strict endpoint does not install its verified fixture authority'
grep -q "DirectLinkedDeviceSelector.enabled()" \
  lib/debug/group_strict_notification_e2e_action.dart ||
  fail 'strict endpoint does not activate disposable strict authoring'
if grep -q "senderPeerId != proof.actorAccountPeerId" \
  lib/debug/group_strict_notification_e2e_action.dart; then
  fail 'strict endpoint confines content authoring to the authority signer'
fi
grep -q "observation\['strictAuthoringActivated'\] != true" \
  integration_test/scripts/capture_group_reaction_notification_device.dart ||
  fail 'strict capture does not fail closed on fixture authoring activation'
grep -q "outcome == 'strict_custody_complete'" \
  integration_test/scripts/reaction_notification_proof_support.dart ||
  fail 'strict capture cannot recognize completed durable custody'
grep -q "'deliveryMode': 'strict_inbox_custody'" \
  lib/features/groups/application/send_group_reaction_use_case.dart ||
  fail 'strict reaction does not emit the shared queued delivery contract'
grep -q "PUSH_FOREGROUND_MESSAGE_RECEIVED" \
  integration_test/scripts/capture_group_reaction_notification_device.dart ||
  fail 'strict exact-chat row does not observe the Android foreground route'
grep -q "GROUP_DRAIN_OFFLINE_INBOX_SINGLE_DONE" \
  integration_test/scripts/capture_group_reaction_notification_device.dart ||
  fail 'strict exact-chat row does not require canonical group drain'
grep -q "await _reactivateStrictRecipientAfterProviderLaunch()" \
  integration_test/scripts/capture_group_reaction_notification_device.dart ||
  fail 'strict recipient authority is not restored after provider relaunch'
grep -q "_strictFinalAuthorityTransfer = null" \
  integration_test/scripts/capture_group_reaction_notification_device.dart ||
  fail 'strict setup transfer is retained into the graded window'
grep -q "await _exchangeStrictReactionWakeAuthorization()" \
  integration_test/scripts/capture_group_reaction_notification_device.dart ||
  fail 'strict fixture does not establish the reaction wake authorization prerequisite'
grep -q "WAKE_TOKEN_RECEIVED_STORED" \
  integration_test/scripts/capture_group_reaction_notification_device.dart ||
  fail 'strict wake authorization is not bound to production receive persistence'
grep -q "_waitForStrictReactionReplacement" \
  integration_test/scripts/capture_group_reaction_notification_device.dart ||
  fail 'strict reaction card wait can advance on the stale killed-message card'
grep -q "relay_group_content_wake_total" \
  integration_test/scripts/capture_group_reaction_notification_device.dart ||
  fail 'strict capture omits strict-content counter provenance'
grep -q "relayGroupReactionWakeCounter" \
  integration_test/scripts/capture_group_reaction_notification_device.dart ||
  fail 'strict capture omits strict-reaction counter provenance'

printf 'PASS: strict notification Sims adapter is central-build, fail-closed, and restoration-bound\n'
