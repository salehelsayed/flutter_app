# INTEGRATE-ST-009 Plan - Standard Integration Contract

Status: accepted

## Scope

Import and verify historical row `ST-009`: "Maximum group size churn remains reliable."

This was standard worktree-to-main integration, not gap-closure. The historical source plan and closure evidence stayed the source of truth; no original implementation plan was regenerated.

## Source Evidence

- Historical source plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-009-plan.md`.
- Source row-owned proof selectors:
  - `flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart --plain-name "ST-009"`
  - `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name "ST-009"`
  - `flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart --plain-name "ST-009"`
  - `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name "ST-009"`
  - `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "ST-009"`
- Source 3-party E2E: `private_max_group_size_churn`, iOS 26.2 Alice/Bob/Charlie.

## Imported Delta

- Imported the row-owned add-member max-size churn selector that rejects overflow at 50 members, removes one member, re-adds into the freed slot, and proves bridge config sync contains exactly the active 50-member set.
- Imported the row-owned send-use-case max-size fanout selector proving removed-window delivery excludes Charlie and post-readd delivery targets all 49 active recipients.
- Imported the row-owned key-rotation fanout selector proving re-add at the limit restores group-key fanout to every active recipient.
- Imported the row-owned fake-network max-size churn selector proving Alice, Bob, and Charlie converge after slot reuse without removed-window plaintext leakage.
- Imported `private_max_group_size_churn` live-harness, runner, criteria, and criteria-test support with `st009MaxGroupSizeChurnProof` validation.
- Adapted the imported harness flow to current-main `_importGm004JoinedGroupFixture` by adding the narrow `replaceMembers` option required by ST-009 fixture re-imports.

## Verification

Passed:

- `flutter test --no-pub test/features/groups/application/add_group_member_use_case_test.dart --plain-name "ST-009"`
- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name "ST-009"`
- `flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart --plain-name "ST-009"`
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name "ST-009"`
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "ST-009"`
- `dart format --set-exit-if-changed test/features/groups/application/add_group_member_use_case_test.dart test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart test/features/groups/integration/group_membership_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart`
- `dart analyze test/features/groups/application/add_group_member_use_case_test.dart test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart test/features/groups/integration/group_membership_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart`
- `git diff --check`
- iOS 26.2 live proof: `MKNOON_RELAY_ADDRESSES=... dart integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_max_group_size_churn -d 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C`

Live proof evidence:

- Run id: `1779362667252`
- Shared dir: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_max_group_size_churn_PoJYak`
- Devices: Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`
- Orchestrator verdict: `private_max_group_size_churn proof passed: private_max_group_size_churn verdicts valid for alice, bob, charlie`

## Verdict

`accepted`

ST-009 is imported and verified. The integration stayed limited to row-owned max-size churn proof artifacts and documentation ledger updates. Existing blocked rows remain unchanged.
