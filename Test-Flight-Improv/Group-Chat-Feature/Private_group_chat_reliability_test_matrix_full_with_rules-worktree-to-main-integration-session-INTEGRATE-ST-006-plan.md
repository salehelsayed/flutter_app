# INTEGRATE-ST-006 Plan - Standard Integration Contract

Status: accepted

## Scope

Import and verify historical row `ST-006`: "Concurrent publishes during key rotation remain visible to active members."

This was standard worktree-to-main integration, not gap-closure. The historical source plan and closure evidence stayed the source of truth; no original implementation plan was regenerated.

## Source Evidence

- Historical source plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-006-plan.md`.
- Source row-owned proof selectors:
  - `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name "ST-006"`
  - `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "ST-006"`
  - `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "private_online_remove"`
- Source 3-party E2E: required on `private_online_remove`, with historical source run `1778745074465`.

## Imported Delta

- Imported the row-owned send-use-case proof that gates key rotation, sends Bob's boundary message before rotated-key installation, sends Alice's post-rotation message after epoch promotion, and proves active-recipient targeting plus valid epochs.
- Imported the row-owned fake-network proof that Alice and Bob retain exact-once boundary visibility while removed Charlie is excluded from plaintext, publish, and inbox-recovery paths.
- Extended the existing `private_online_remove` live harness with `st006RotationBoundaryPublishProof` for Alice, Bob, and Charlie without importing unrelated KE-007 or later stress-row proof fields.
- Extended the criteria validator and criteria tests so missing or invalid ST-006 boundary proof fails the existing `private_online_remove` verdict.

## Verification

Passed:

- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name "ST-006"`
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "ST-006"`
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "private_online_remove"`
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "GM-004"`
- `flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart --plain-name "KE-006"`
- `flutter test --no-pub test/features/groups/application/remove_group_member_use_case_test.dart --plain-name "ML-005"`
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name "ML-005"`
- `flutter test --no-pub test/features/groups/integration/group_media_fanout_test.dart --plain-name "PL-006"`
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name "PL-006"`
- `dart format --set-exit-if-changed test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/integration/group_messaging_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart`
- `flutter analyze --no-pub test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/integration/group_messaging_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart`

Live proof:

- Command: `MKNOON_RELAY_ADDRESSES=... dart integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_online_remove -d 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C`
- Run id: `1779358398568`
- Artifact dir: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_online_remove_XPZ4IA`
- Devices: Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`; all were selected from the local `-- iOS 26.2 --` CoreSimulator list and used as the only app-peer targets.
- Orchestrator verdict: `private_online_remove proof passed: private_online_remove verdicts valid for alice, bob, charlie`.

## Verdict

`accepted`

ST-006 is imported and verified. The integration stayed limited to row-owned rotation-boundary proof artifacts and documentation ledger updates. Existing blocked rows remain unchanged.
