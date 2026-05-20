# INTEGRATE-RA-007 - Partial-Present Integration Contract

Status: accepted

Created: 2026-05-19

## Source Row Contract

Source row: `RA-007 | B misses removal but receives re-add and still converges | P0 | Remove and Re-add Regression Suite`

Historical source plan:
`/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-RA-007-plan.md`

The source contract covers an active remaining-member partition:

- Bob remains an active member and subscribed observer before the partition.
- Bob misses Charlie's removal and Alice's removed-window live send while Bob deliveries are held.
- Alice re-adds Charlie at the current epoch and Bob later heals.
- Bob converges to Alice/Bob/Charlie membership at the current epoch, keeps his entitled removed-window history, and accepts Alice/Charlie post-heal messages.
- Charlie records no removed-window plaintext and accepts post-heal delivery.

Historical source proof passed with RA-007-named fake-network, criteria, and live-harness proof fields on `private_readd_current`, including iOS 26.2 live run `1778638861218`.

## Controller Classification

Classification: `partial_present`.

Current main has nearby and partially overlapping behavior:

- COMPLETE_1/current `GE-007` proves Bob fully offline through the remove/re-add window, drains entitled messages, converges to Alice/Bob/Charlie, and sends after catch-up.
- Current `FakeGroupPubSubNetwork` already has generic held-delivery support.
- Current `private_readd_current` already carries adjacent RA-002, RA-006, KE-011, and KE-012 proof surfaces.

This is not a skip because the source RA-007 historical source-of-truth is the active-observer held-delivery partition, not the fully-offline GE-007 path, and current main has no `RA-007` selector, no `ra007PartitionedObserverReaddProof`, no RA-007 criteria validation/tests/fixtures, and no RA-007 test-inventory closure row.

## Integration Scope

Import only the missing RA-007-owned proof/test/doc deltas:

- Reconcile `FakeGroupPubSubNetwork` held-delivery resolution so holding by literal peer id and resolved device id both work for active-observer partitions, without disturbing existing hold/release semantics.
- Add the RA-007 fake-network selector to `group_membership_smoke_test.dart`.
- Add `ra007PartitionedObserverReaddProof` fields beside existing `private_readd_current` proof fields for Alice, Bob, and Charlie.
- Add RA-007 criteria validation and RA-007 criteria positive/negative checks without importing RA-008+ or unrelated source proof rows.
- Update `test-inventory.md` for RA-007 only.

Production app code changes are out of scope. Do not import source matrix or source session-breakdown rewrites. RA-008+, first-message/restart/stale-leave/rotated-device rows, NW-003, BB-007, BB-012, accepted-row IR-018 fixture aging, GM-029, ML-008, GE-018, retained-history drain follow-up, COMPLETE_1 GI-017, replay-window residuals, listener/drain residuals, ML-012 external-fixture work, KE-007/KE-009 re-reconciliation, UI, notification, media, relay architecture, and broader stress rows are out of scope.

## Device/Relay Proof Profile

Profile: exact iOS 26.2 three-party simulator proof required after host verification.

Use only iOS 26.2 CoreSimulator app-peer devices for the live proof:

- Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`
- Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`
- Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`

The live proof must run:

```bash
MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g' dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_readd_current -d 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C
```

Record run id, shared dir, role devices, and RA-007 proof facts. Do not substitute iOS 26.1, iOS 26.5, Android, physical iOS, macOS, Chrome, or single-device proof for the app-peer roles.

## Required Verification

```bash
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'RA-007'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'RA-007'
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_readd_current'
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-007'
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'RA-006'
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'KE-011'
dart analyze test/shared/fakes/fake_group_pubsub_network.dart test/features/groups/integration/group_membership_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart
dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_readd_current --list-scenarios
git diff --check
```

Named gates to classify after focused checks:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
```

Known unrelated residuals from RA-006 are expected to remain outside RA-007 unless changed by this row.

## Execution Result

Implemented on 2026-05-19 in standard integration mode.

Changed files:

- `test/shared/fakes/fake_group_pubsub_network.dart`
- `test/features/groups/integration/group_membership_smoke_test.dart`
- `integration_test/group_multi_party_device_real_harness.dart`
- `integration_test/scripts/group_multi_party_device_criteria.dart`
- `test/integration/group_multi_party_device_criteria_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/test-inventory.md`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-RA-007-plan.md`

Imported only the RA-007 partial-present deltas: held-delivery peer/device resolution, the active Bob observer fake-network selector, `ra007PartitionedObserverReaddProof` maps on `private_readd_current`, criteria validation, valid/missing/Bob non-convergence criteria tests, and one test-inventory row. Production `lib/` and Go code were not edited, and no RA-008+ proof surfaces were imported.

Host checks run:

```bash
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'RA-007' # passed, +1
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'RA-007' # passed, +3
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_readd_current' # passed, +21
dart analyze test/shared/fakes/fake_group_pubsub_network.dart test/features/groups/integration/group_membership_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart # No issues found!
dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_readd_current --list-scenarios # listed private_readd_current
git diff --check # passed
```

Controller verification run after the write-active worker:

```bash
flutter test --no-pub test/features/groups/integration/group_membership_smoke_test.dart --plain-name 'RA-007' # passed, +1
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'RA-007' # passed, +3
flutter test --no-pub test/integration/group_multi_party_device_criteria_test.dart --plain-name 'private_readd_current' # passed, +21
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-007' # passed, +1
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'RA-006' # passed, +1
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'KE-011' # passed, +1
dart analyze test/shared/fakes/fake_group_pubsub_network.dart test/features/groups/integration/group_membership_smoke_test.dart integration_test/group_multi_party_device_real_harness.dart integration_test/scripts/group_multi_party_device_criteria.dart test/integration/group_multi_party_device_criteria_test.dart # No issues found!
dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_readd_current --list-scenarios # listed private_readd_current
git diff --check # passed before live proof and after named gates
```

iOS 26.2 simulator profile verified with `xcrun simctl list devices 'iOS 26.2'`: Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, and Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C` were booted iOS 26.2 devices.

Live proof run:

```bash
MKNOON_RELAY_ADDRESSES='/dns/mknoun.xyz/tcp/4001/wss/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g,/dns/mknoun.xyz/udp/4002/quic-v1/p2p/12D3KooWGMYMmN1RGUYjWaSV6P3XtnBjwnosnJGNMnttfVCRnd6g' dart run integration_test/scripts/run_group_multi_party_device_real.dart --scenario private_readd_current -d 5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3,279B82AE-2BB9-4924-9AAE-581870ED3FA9,116B4AF6-C1A9-4F36-B929-0A7130B5E83C
```

Live proof result:

- Scenario `private_readd_current`
- Run id `1779190970058`
- Shared dir `/var/folders/nd/_55d26s936d0fb_5l9s00t980000gn/T/group_multi_party_private_readd_current_rRoiSx`
- Role devices: Alice `5A9A8286-001B-4BF1-8F40-5A3AB8BF8FE3`, Bob `279B82AE-2BB9-4924-9AAE-581870ED3FA9`, Charlie `116B4AF6-C1A9-4F36-B929-0A7130B5E83C`
- Orchestrator verdict: `private_readd_current proof passed: private_readd_current verdicts valid for alice, bob, charlie`
- Alice RA-007 proof: rowId `RA-007`, `partitionedObserverOrderingCoveredByFakeNetwork=true`, `livePostHealDeliveryCovered=true`, `removedCharlie=true`, `readdedCharlie=true`, `sentRemovedWindowWhileBobPartitionedCoveredByFakeNetwork=true`, `sentAlicePostHealAtCurrentEpoch=true`, `receivedBobPostHealAtCurrentEpoch=true`, `finalEpoch=2`
- Bob RA-007 proof: rowId `RA-007`, `activeObserverPartitionCoveredByFakeNetwork=true`, `retainedEntitledRemovedWindowCoveredByFakeNetwork=true`, `observedCharlieReadded=true`, `receivedAlicePostHealAtCurrentEpoch=true`, `receivedCharliePostHealAtCurrentEpoch=true`, `sentBobPostHealAtCurrentEpoch=true`, `finalEpoch=2`
- Charlie RA-007 proof: rowId `RA-007`, `bobPartitionDoesNotLeakRemovedWindowCoveredByFakeNetwork=true`, `removedWindowPlaintextCount=0`, `postHealPublishAccepted=true`, `receivedAlicePostHealAtCurrentEpoch=true`, `receivedBobPostHealAtCurrentEpoch=true`, `memberListIncludesAliceBob=true`, `memberListIncludesCharlie=true`, `finalEpoch=2`

Named gate classification:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups # red, +224 -4, only preserved residuals
./scripts/run_test_gates.sh completeness-check # red, 733/734, only unmatched test/shared/fakes/fake_group_pubsub_network_test.dart
```

The preserved `groups` residuals were:

- `BB-007` `Expected: not null / Actual: <null>` at `test/features/groups/integration/invite_round_trip_test.dart:679`
- `BB-012` `Expected: an object with length of <1> / Actual: WhereIterable<GroupMessage>:[]` at `test/features/groups/integration/group_startup_rejoin_smoke_test.dart:859`
- accepted-row `IR-018` fixture-aging replay residual `Expected: an object with length of <1> / Actual: WhereIterable<GroupMessage>:[]` at `test/features/groups/integration/group_startup_rejoin_smoke_test.dart:1027`
- `GM-029` `Expected: MemberRole.writer / Actual: MemberRole.reader` at `test/features/groups/integration/group_membership_smoke_test.dart:8986`

Final status: accepted. RA-007 imported only row-owned missing deltas, did not touch production code, did not duplicate existing GE-007 coverage, and preserved all named residuals as non-RA-007 work.
