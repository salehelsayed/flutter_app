# INTEGRATE-RA-002 - Online Removed/Re-Add Integration Contract

Status: accepted

Started: 2026-05-19 10:43 CEST
Closed: 2026-05-19 11:09 CEST

## Source Row Contract

Source row: `RA-002 | Removed peer stays online and subscribed, then is re-added | P0 | Remove and Re-add Regression Suite`

Historical source plan:
`/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-002-plan.md`

RA-002 owns only the online/subscribed removed-member path: Charlie remains online and subscribed while Alice removes Charlie, Alice sends removed-window traffic, and Alice re-adds Charlie without a Charlie app restart. Charlie must see zero removed-window plaintext, receive Alice/Bob post-readd traffic without restart, and successfully publish after re-add.

## Reconciliation Decision

Classification before import: `partial`.

Current main has overlapping GM-006, GM-007, GM-017, GM-018, GM-019, GM-024, ML-007, and KE proof coverage, but it does not contain a row-named RA-002 selector or `ra002OnlineSubscribedReaddProof` criteria/live-harness evidence. The source RA-002 row has no production changes, so this integration imports only missing row-owned proof surfaces and leaves existing production behavior unchanged.

## Intended Import Scope

Import only:

- one RA-002 row-named host fake-network selector in `test/features/groups/integration/group_membership_smoke_test.dart`
- `ra002OnlineSubscribedReaddProof` emission for Alice, Bob, and Charlie in the existing `private_readd_current` live-harness path
- `ra002OnlineSubscribedReaddProof` criteria validation for `private_readd_current`
- RA-002 criteria fixture fields and negative tests for missing proof and removed-window leakage
- this integration plan plus test-inventory/breakdown closure docs

Do not import source RA-001 row markers, `ra001CanonicalReaddProof`, source matrix rewrites, source session-breakdown rewrites, unrelated later RA/KE/PL proof fields, production changes, runner script changes, fixtures outside the existing proof path, or adjacent-row repairs.

## Verification Contract

Focused RA-002 checks:

- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'RA-002'`
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_readd_current'`
- scoped analyzer over `group_membership_smoke_test.dart`, `group_multi_party_device_real_harness.dart`, `group_multi_party_device_criteria.dart`, and `group_multi_party_device_criteria_test.dart`

Affected preservation checks:

- GM-007/IR-005/KE-018 host selector
- GM-017 stale subscription host selector
- GM-018 remaining-member stale-pressure host selector
- GM-019 and GM-024 affected selectors where practical
- GM-007/GM-017/GM-018/GM-019/GM-024 criteria preservation where practical

Named gates:

- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups`
- `./scripts/run_test_gates.sh completeness-check`
- `git diff --check`

Live proof requirement: exact iOS 26.2 `private_readd_current` proof is required before final acceptance unless a real external fixture blocker is recorded. Source historical proof run `1778633141962` is source evidence only.

## Imported Row-Owned Deltas

- `test/features/groups/integration/group_membership_smoke_test.dart`: added the row-named RA-002 host fake-network selector proving Charlie remains online/subscribed during removal, sees zero removed-window plaintext, is re-added without restart, receives Alice/Bob post-readd traffic, and publishes after re-add.
- `integration_test/group_multi_party_device_real_harness.dart`: added `ra002OnlineSubscribedReaddProof` verdict fields for Alice, Bob, and Charlie in the existing `private_readd_current` path, plus the narrow stale-subscription wait helper needed by that path.
- `integration_test/scripts/group_multi_party_device_criteria.dart`: added `ra002OnlineSubscribedReaddProof` validation for `private_readd_current`.
- `test/integration/group_multi_party_device_criteria_test.dart`: added RA-002 proof fixture fields and negative checks for missing proof and removed-window plaintext leakage.
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md` and this integration breakdown: recorded the RA-002 integration closure.

No production code, source RA-001 markers, `ra001CanonicalReaddProof`, unrelated runner changes, unrelated fixtures, or adjacent RA rows were imported.

## Verification Result

- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'RA-002'` passed (`+1`).
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_readd_current'` passed (`+15`).
- Scoped analyzer over the four touched Dart files passed (`No issues found!`).
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --name 'GM-016|GM-017|GM-018|IR-005 GM-007 KE-018|GM-019|GM-024'` passed (`+6`).
- `flutter test --no-pub test/features/groups/application/member_removal_integration_test.dart --name 'GM-017|GM-018|GM-019|GM-024'` passed (`+4`).
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --name 'GM-007|GM-016|GM-017|GM-018|GM-019|GM-024'` passed (`+31`).
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+222 -3` only on preserved non-RA-002 residuals `BB-007`, `BB-012`, and `GM-029`; RA-002 ran inside that gate and passed.
- `./scripts/run_test_gates.sh completeness-check` remains red only on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart` classification (`733/734`).
- iOS 26.2 live proof passed for `private_readd_current`: run id `1779181396891`, shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_readd_current_dPRI1j`, Alice device `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob device `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie device `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`; orchestrator verdict: `private_readd_current proof passed: private_readd_current verdicts valid for alice, bob, charlie`.
- `git diff --check` passed.

Final decision: `accepted`.
