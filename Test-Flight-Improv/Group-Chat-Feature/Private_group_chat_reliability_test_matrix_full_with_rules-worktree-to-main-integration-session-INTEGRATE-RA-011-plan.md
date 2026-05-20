# INTEGRATE-RA-011 - Missing-Delta Integration Contract

Status: accepted

Created: 2026-05-19

## Source Row Contract

Source row: `RA-011 | Immediate re-add before group:leave completes does not strand C | P0 | Remove and Re-add Regression Suite`

Historical source plan:
`/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-011-plan.md`

The source contract covers the late native leave completion race:

- Charlie begins a self-removal path that holds native `group:leave` open.
- Alice re-adds Charlie with the current config/key before the delayed leave completes.
- Charlie detects that the late leave completion is stale, keeps the current local group/member/key state, and repairs the native topic with the latest config/key.
- Alice, Bob, and Charlie can exchange current-epoch post-repair messages, and final membership still contains Alice/Bob/Charlie.

Historical source proof passed with RA-011-named direct listener, fake-network, criteria, and live-harness proof fields on `private_late_leave_readd`, including iOS 26.2 live run `1778644696040`.

## Controller Classification

Classification: `partial_present_missing_row_owned_delta`.

Current main has adjacent COMPLETE_1 and imported coverage for ordinary leave/rejoin, stale removal after re-add, and first messages after re-add, but it has no exact RA-011 repair marker, no deterministic delayed-leave hook, no `private_late_leave_readd` scenario, no `ra011LateLeaveReaddProof` criteria, and no RA-011 row-owned tests in the current checkout. This row is therefore not `skipped_already_present`.

Existing blocker/residual rows are dependency-independent for this row unless the focused RA-011 import touches their owner contracts. Do not repair or re-reconcile unrelated residuals inside INTEGRATE-RA-011.

## Integration Scope

Import only the missing RA-011-owned meaningful deltas from the historical source worktree:

- Add the narrow late self-removal leave repair in `group_message_listener.dart`.
- Add only the deterministic test-only leave delay hook needed by the RA-011 proof in `bridge_group_helpers.dart`.
- Add the RA-011 direct listener test and fake-network selector.
- Add the isolated `private_late_leave_readd` live scenario, runner discovery, RA-011 criteria validation, and RA-011 criteria tests/fixtures.
- Update `test-inventory.md` for RA-011 only.

Do not import RA-012+, same-user multi-device policy, rotated-device identity, broad group lifecycle rewrites, unrelated source worktree docs, COMPLETE_1 docs, network/UI/notification/media rows, Go production changes not owned by RA-011, Android, physical iOS, or existing blocker repairs.

## Device/Relay Proof Profile

Profile: exact iOS 26.2 three-party simulator proof required after host verification.

Use only iOS 26.2 CoreSimulator app-peer devices for the live proof:

- Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`
- Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`
- Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`

The live proof must run:

```bash
MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g' dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_late_leave_readd -d 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C
```

Record run id, shared dir, role devices, and RA-011 proof facts. Do not substitute iOS 26.1, iOS 26.5, Android, physical iOS, macOS, Chrome, or single-device proof for the app-peer roles.

## Required Verification

```bash
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'RA-011'
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'RA-011'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'RA-011'
dart analyze lib/features/groups/application/group_message_listener.dart lib/core/bridge/bridge_group_helpers.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/integration/group_membership_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart
dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_late_leave_readd --list-scenarios
git diff --check
```

Named gates to classify after focused checks:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
```

Known unrelated residuals from prior rows may remain red if unchanged by RA-011; record exact evidence instead of broadening this row.

## Execution Result

Final status: `accepted`.

Imported only the missing RA-011-owned meaningful delta:

- `group_message_listener.dart`: late self-removal leave completion repair when the current group state proves the member was immediately re-added.
- `bridge_group_helpers.dart`: test-only delayed `group:leave` hook, scoped to `callGroupLeave`.
- RA-011 direct listener and fake-network selectors.
- `private_late_leave_readd` runner/live-harness scenario, criteria validator, and criteria tests.
- `test-inventory.md` RA-011 row evidence.

The first live attempt, run `1779197912568`, correctly exposed an in-scope import defect: the deterministic leave-delay hook had landed outside `callGroupLeave`, so Charlie's late leave completed before the immediate re-add race was exercised. The controller fixed only that RA-011 hook placement, reran the focused checks, and then reran live proof.

Focused verification passed after the hook fix:

- `dart analyze lib/features/groups/application/group_message_listener.dart lib/core/bridge/bridge_group_helpers.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/integration/group_membership_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/run_group_multi_party_device_real.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart` -> `No issues found!`
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'RA-011'` -> `+1`
- `flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'RA-011'` -> `+1`
- `flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'RA-011'` -> `+3`
- `dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_late_leave_readd --list-scenarios` listed `private_late_leave_readd`.

iOS 26.2 live proof passed for `private_late_leave_readd`:

- run id: `1779198513960`
- shared dir: `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_late_leave_readd_yyKBHZ`
- role devices: Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`
- orchestrator verdict: `private_late_leave_readd verdicts valid for alice, bob, charlie`
- Alice `ra011LateLeaveReaddProof`: Charlie removed, leave started before re-add, re-added before late leave completed, Charlie post-repair message received, member list includes Charlie, final epoch `2`.
- Bob `ra011LateLeaveReaddProof`: Charlie removed/re-added observed, Alice and Charlie post-repair messages received, member list includes Charlie, final epoch `2`.
- Charlie `ra011LateLeaveReaddProof`: leave started before re-add, re-add imported before late leave completed, repair join completed, post-readd publish accepted, Alice post-repair message received, Alice/Bob/Charlie membership present, final epoch `2`.

Named gate classification:

- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remained red at `+224 -8`; RA-011's in-gate selector passed and the red rows are preserved non-RA-011 residuals: `BB-007`, `BB-012`, accepted-row `IR-018` fixture-aging replay residual, non-RA `IR-003`, `GE-017`, `GE-019`, `GE-020`, and `GM-029`.
- `./scripts/run_test_gates.sh completeness-check` remained red at `733/734`, only on unrelated `test/shared/fakes/fake_group_pubsub_network_test.dart`.
- `git diff --check` passed before ledger update.
