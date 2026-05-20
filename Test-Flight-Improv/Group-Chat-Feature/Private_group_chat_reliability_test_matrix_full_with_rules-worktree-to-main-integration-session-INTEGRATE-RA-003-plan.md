# INTEGRATE-RA-003 - Offline Removal/Re-Add Integration Contract

Status: accepted

Started: 2026-05-19 11:23 CEST
Completed: 2026-05-19 12:05 CEST

## Source Row Contract

Source row: `RA-003 | Removed peer is offline during removal and online during re-add | P0 | Remove and Re-add Regression Suite`

Historical source plan:
`/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-003-plan.md`

RA-003 owns only the offline-removal/online-readd path: Charlie is offline during Alice's removal and removed-window send, reconnects before re-add, resolves the removal before or together with re-add, receives only Alice/Bob post-readd traffic, and successfully publishes after re-add. Charlie must never render removed-window plaintext.

## Reconciliation Decision

Classification before import: `partial`.

Current main has adjacent GE-006 coverage for a remove/re-add catch-up path where Charlie remains offline through re-add and drains post-readd replay after relaunch. That is useful overlap but not an exact RA-003 substitute, because RA-003 requires Charlie to reconnect before re-add and prove removal resolution before the re-add path proceeds. Current main has no row-named RA-003 selector, no `private_offline_readd` scenario, and no `ra003OfflineReaddProof` criteria/live-harness evidence.

The source RA-003 row has no production changes, so this integration imports only missing row-owned proof surfaces and leaves existing production behavior unchanged.

## Intended Import Scope

Import only:

- one RA-003 row-named host fake-network selector in `test/features/groups/integration/group_membership_smoke_test.dart`
- `private_offline_readd` live scenario routing in `integration_test/scripts/run_group_multi_party_device_real.dart` and `integration_test/group_multi_party_device_real_harness.dart`
- `ra003OfflineReaddProof` emission for Alice, Bob, and Charlie in the live harness
- `private_offline_readd` criteria requirements, expected proof messages, and `ra003OfflineReaddProof` validation
- RA-003 criteria fixtures plus positive, missing-proof, and removed-window leakage tests
- this integration plan plus test-inventory/breakdown closure docs

Do not import source RA-004+ row markers, unrelated stale-removal/key downgrade paths, unrelated COMPLETE_1 GE-006 rewrites, source matrix rewrites, source session-breakdown rewrites, production changes, runner or harness changes for unrelated scenarios, or adjacent-row repairs.

## Verification Contract

Focused RA-003 checks:

- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'RA-003'`
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'offline_readd'`
- scoped analyzer over `group_membership_smoke_test.dart`, `group_multi_party_device_real_harness.dart`, `group_multi_party_device_criteria.dart`, `run_group_multi_party_device_real.dart`, and `group_multi_party_device_criteria_test.dart`

Affected preservation checks:

- GE-006 host and criteria selectors, because GE-006 is the closest adjacent offline re-add proof
- GM-007/IR-005/KE-018 host selector
- GM-017 stale subscription host selector
- GM-018 remaining-member stale-pressure host selector
- GM-019 and GM-024 affected selectors where practical
- GM-007/GM-017/GM-018/GM-019/GM-024 criteria preservation where practical

Named gates:

- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`
- `./scripts/run_test_gates.sh completeness-check`
- `git diff --check`

Live proof requirement: exact iOS 26.2 `private_offline_readd` proof is required before final acceptance unless a real external fixture blocker is recorded. Source historical proof run `1778634585460` is source evidence only.

## Imported Scope

Imported only the missing RA-003 row-owned proof surfaces:

- `test/features/groups/integration/group_membership_smoke_test.dart`: added `RA-003 offline removed member resolves removal before readd and receives only post-readd`, proving Charlie is offline during removal, gets no removed-window plaintext, reconnects before re-add, resolves removal, receives Alice/Bob post-readd traffic only, and can publish after re-add.
- `integration_test/scripts/run_group_multi_party_device_real.dart`: added `private_offline_readd` runner/listing support.
- `integration_test/group_multi_party_device_real_harness.dart`: added `private_offline_readd` role routing and `ra003OfflineReaddProof` emission for Alice, Bob, and Charlie. A row-local harness wait was reconciled after first live proof: Charlie now accepts either retained self-exclusion or deleted local group/key state when resolving removal before re-add.
- `integration_test/scripts/group_multi_party_device_criteria.dart`: added `private_offline_readd` requirements, expected messages, and `ra003OfflineReaddProof` validation.
- `test/integration/group_multi_party_device_criteria_test.dart`: added positive `private_offline_readd` proof validation plus missing-proof and removed-window leakage rejection coverage.
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` and this integration breakdown record the accepted import.

Production code stayed untouched. No RA-004+ source row markers, unrelated stale invite/remove/key downgrade paths, source matrix rewrites, COMPLETE_1 rewrites, or unrelated test fixtures were imported.

## Verification Evidence

Focused checks:

- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'RA-003'`: PASS (`+1`).
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'offline_readd'`: PASS (`+3`).
- `dart analyze test/features/groups/integration/group_membership_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart integration_test/scripts/run_group_multi_party_device_real.dart test/integration/group_multi_party_device_criteria_test.dart`: PASS (`No issues found!`) before and after the row-local harness wait reconciliation.
- `dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_offline_readd --list-scenarios`: PASS; lists `private_offline_readd`.

Affected preservation:

- GE-006 host selector: PASS (`+1`).
- GE-006 criteria selector: PASS (`+3`).
- Group-membership preservation bundle `GM-016|GM-017|GM-018|IR-005 GM-007 KE-018|GM-019|GM-024|RA-002`: PASS (`+7`).
- Member-removal preservation bundle `GM-017|GM-018|GM-019|GM-024`: PASS (`+4`).
- Criteria preservation bundle `GM-007|GM-016|GM-017|GM-018|GM-019|GM-024|private_readd_current`: PASS (`+46`).

Live proof:

- Initial iOS 26.2 `private_offline_readd` proof run `1779183448372` failed because the harness waited only for retained self-removal state; Charlie correctly deleted local group/key state, so Alice timed out on `gmp_1779183448372_charlie_self_removed`, Bob timed out waiting for Charlie inclusion, and Charlie timed out in `_waitForRetainedSelfRemoval`.
- After the row-local harness wait reconciliation, iOS 26.2 `private_offline_readd` proof run `1779184279659` passed with shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_offline_readd_l6RN7b`. Devices: Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`. Final result: `private_offline_readd proof passed: private_offline_readd verdicts valid for alice, bob, charlie`.

Named gates and hygiene:

- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`: red at `+223 -3` only on preserved non-RA-003 residuals `BB-007`, `BB-012`, and `GM-029`.
- `./scripts/run_test_gates.sh completeness-check`: red only on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`733/734`).
- `git diff --check`: PASS.

## Final Decision

`INTEGRATE-RA-003` is accepted. The row-owned offline-removal/online-readd proof surfaces are present in main, the required focused and live iOS 26.2 proof passed after a row-local harness reconciliation, and all residual gate failures are preserved known non-RA-003 residuals.
