# INTEGRATE-SV-008 Minimal Integration Contract

Status: accepted

## Scope

Import/reconcile source row `SV-008` from the full-with-rules worktree into main: unauthorized network config-update payloads must not add an attacker, remove an active member, persist a local config-update message, or poison later valid delivery.

This is standard worktree-to-main integration, not new implementation rollout and not gap closure. The historical source plan remains the source of truth:

`/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-SV-008-plan.md`

## Reconciliation

- Source status: accepted/covered in the historical worktree.
- Main status before import: partial. Current main already rejected non-admin and removed-member membership events in the listener and fake-network paths, but lacked the SV-008 row-named native validator proof, direct/fake-network unauthorized config-update proof selectors, criteria validation, and live-harness proof fields.
- Imported delta: only missing SV-008 row-owned proof selectors, criteria validation, and live-harness proof enrichment for `private_removed_old_key_publish_rejected`.
- Current-main adaptation: the live proof was layered onto the existing SV-002 removed-old-key scenario and preserved the current criteria contract for that scenario.
- Live proof: required and passed on iOS 26.2 simulator devices.

## Imported Artifacts

- `go-mknoon/node/pubsub_test.go`
  - `TestSV008UnauthorizedConfigUpdateRejectsBeforeApply`
- `test/features/groups/application/group_message_listener_test.dart`
  - `SV-008 unauthorized config update payloads leave state and bridge unchanged`
- `test/features/groups/integration/group_membership_smoke_test.dart`
  - `SV-008 unauthorized config update payloads are ignored by peers`
- `integration_test/group_multi_party_device_real_harness.dart`
  - adds SV-008 unauthorized config-update attempt/observer proof fields to `private_removed_old_key_publish_rejected`.
- `integration_test/scripts/group_multi_party_device_criteria.dart`
  - validates `sv008UnauthorizedConfigUpdateProof` for Alice, Bob, and Charlie verdicts.
- `test/integration/group_multi_party_device_criteria_test.dart`
  - SV-008 acceptance and rejection criteria tests.
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`
- This contract.

## Verification

- PASS: `gofmt -w go-mknoon/node/pubsub_test.go`
- PASS: `dart format --set-exit-if-changed test/features/groups/application/group_message_listener_test.dart test/features/groups/integration/group_membership_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart`
- PASS: `cd go-mknoon && go test ./node -run TestSV008UnauthorizedConfigUpdateRejectsBeforeApply -count=1`
- PASS: `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name SV-008`
- PASS: `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name SV-008`
- PASS: `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name SV-008`
- PASS: `dart analyze test/features/groups/application/group_message_listener_test.dart test/features/groups/integration/group_membership_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart`
- PASS: `cd go-mknoon && go test ./node -run 'TestSV008UnauthorizedConfigUpdateRejectsBeforeApply|TestGroupTopicValidator_ValidMessage|TestGK015ValidateGroupEnvelopeRejectsGroupIDMismatchBeforeTransportPeerAndSignature' -count=1`
- PASS: `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --name 'unauthorized member_added is ignored|unauthorized members_added is ignored|SV-008 unauthorized config update payloads leave state and bridge unchanged'`
- PASS: `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --name 'ML-013 non-admin and non-member raw membership events are ignored by peers|SV-008 unauthorized config update payloads are ignored by peers'`
- PASS: `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --name 'SV-002|SV-008'`
- PASS: iOS 26.2 live proof run `1779340259686` for `private_removed_old_key_publish_rejected` in `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_removed_old_key_publish_rejected_rzjbkL` on Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, and Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`; orchestrator verdict `private_removed_old_key_publish_rejected proof passed: private_removed_old_key_publish_rejected verdicts valid for alice, bob, charlie`.
- PASS: `git diff --check`

## Closure

`INTEGRATE-SV-008` is accepted with required iOS 26.2 live proof. Adjacent rows `SV-009` and later remain separate pending integration sessions.
