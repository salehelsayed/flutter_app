# INTEGRATE-ST-007 Plan - Standard Integration Contract

Status: accepted

## Scope

Import and verify historical row `ST-007`: "Process death at every step of add, remove, and re-add recovers safely."

This was standard worktree-to-main integration, not gap-closure. The historical source plan and closure evidence stayed the source of truth; no original implementation plan was regenerated.

## Source Evidence

- Historical source plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-ST-007-plan.md`.
- Source row-owned proof selectors:
  - `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name "ST-007"`
  - `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name "ST-007"`
  - `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "private_process_death_matrix"`
- Source 3-party E2E: required on `private_process_death_matrix`, with historical source run `1778749880505`.

## Imported Delta

- Imported the row-owned send-use-case process-death checkpoint proof for add, remove, and re-add checkpoints across local DB write, bridge update, key generation, invite send, inbox store, and ack.
- Imported the row-owned fake-network membership proof that simulates restart recovery through add, remove, and re-add windows, with no removed-window plaintext and post-readd delivery convergence.
- Added persistent live-harness identity reuse support for process-death relaunches while preserving default clean database setup for other scenarios.
- Added the `private_process_death_matrix` live scenario orchestration, role flows, proof fields, criteria validation, and criteria rejection tests without importing unrelated later stress-row deltas.

## Verification

Passed:

- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name "ST-007"`
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name "ST-007"`
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "private_process_death_matrix"`
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name "private_online_remove"`
- `dart format --set-exit-if-changed integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_device_real_harness.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/integration/group_multi_party_device_criteria_test.dart`
- `flutter analyze --no-pub integration_test/scripts/run_group_multi_party_device_real.dart integration_test/group_multi_device_real_harness.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/features/groups/application/send_group_message_use_case_test.dart test/features/groups/integration/group_membership_smoke_test.dart test/integration/group_multi_party_device_criteria_test.dart`
- `git diff --check`

Live proof:

- Command: `MKNOON_RELAY_ADDRESSES=... dart integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_process_death_matrix -d 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C`
- Run id: `1779360230016`
- Artifact dir: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_process_death_matrix_BBL0g8`
- Devices: Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`; all were selected from the local `-- iOS 26.2 --` CoreSimulator list and used as the only app-peer targets.
- Orchestrator verdict: `private_process_death_matrix proof passed: private_process_death_matrix verdicts valid for alice, bob, charlie`.

## Verdict

`accepted`

ST-007 is imported and verified. The integration stayed limited to row-owned process-death recovery proof artifacts, live scenario support, and documentation ledger updates. Existing blocked rows remain unchanged.
