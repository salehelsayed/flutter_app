# INTEGRATE-KE-020 Integration Contract - Concurrent Rotation Epoch Allocation

Status: accepted

Created: 2026-05-18

## Source Row

- Worktree source matrix row: `KE-020`
- Integration session: `INTEGRATE-KE-020`
- Title: `Concurrent rotations allocate unique increasing epochs`
- Historical worktree plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-020-plan.md`
- Historical worktree plan status: `accepted`
- Active integration mode: standard worktree-to-main integration, not gap closure

## Row Contract

Two overlapping same-process rotations for the same private group must not generate, distribute, promote, or persist different keys for the same epoch. The row-owned behavior is a same-isolate per-group FIFO around `rotateAndDistributeGroupKey` so the first rotation commits epoch `N+1` and the queued rotation reloads the latest persisted key before committing epoch `N+2`.

## Integration Decision

Current main already had persisted-key restore before generation, generated-epoch mismatch rejection, fail-closed partial distribution, and preservation coverage for single-rotation send epoch binding. It did not have KE-020 same-group rotation serialization or row-owned KE-020 direct/fake-network selectors. This session imports only the missing FIFO serialization and row-owned tests, preserving the current retry/distribution behavior rather than copying the source file.

## Owned Files

- `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`
- `test/features/groups/integration/group_messaging_smoke_test.dart`
- this integration contract
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`

## Scope Guard

Do not import source docs, COMPLETE_1 docs, source matrix docs, source `test-inventory.md`, Go/native changes, DB helper changes, durable cross-process locks, relay/device proof, criteria scripts, live harness fields, KE-021+, removed-member future key scoping, KE-007/KE-009 re-reconciliation, BB-007, BB-012, GM-029, ML-012 external-fixture work, listener/drain/replay-window residuals, UI, media, notification, relay, or broader key-safety behavior under this row.

## Device/Relay Proof Profile

- Profile: host-only unit and fake-network proof.
- iOS 26.2 live proof: not required.
- Device ids/run id: N/A.

## Required Evidence

- focused KE-020 direct rotation selector;
- focused KE-020 fake-network selector;
- affected KE-013 restore/mismatch selectors;
- promotion-after-distribution preservation selector;
- MS-018 send epoch binding selector;
- KE-005 same-generation key conflict selector;
- KE-014 legacy rotate fail-closed selector;
- full rotation use-case test file;
- full fake-network smoke file;
- scoped analyzer/format/diff hygiene;
- named `groups`, `completeness-check`, and Go bridge generate/update gates, preserving unrelated residuals.

## Final Execution Verdict

Verdict: accepted.

Imported the missing KE-020 same-group rotation FIFO and row-owned direct/fake-network proof selectors. Existing retry/distribution behavior and MS-018 send epoch binding were preserved.

Accepted files:

- `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`
- `test/features/groups/integration/group_messaging_smoke_test.dart`
- this integration contract
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`

Focused and preservation evidence:

- `flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart --plain-name 'KE-020 concurrent rotations allocate unique increasing epochs'` PASS (`+1`).
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'KE-020 concurrent rotations commit unique epochs before fake-network send'` PASS (`+1`).
- Rotation preservation selector bundle PASS (`+3`): KE-013 persisted epoch restore, KE-013 stale generated epoch rejection, and promotion-after-distribution ordering.
- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'messages before during and after rotation bind to the locally committed epoch'` PASS (`+1`).
- `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'KE-005 conflicting same-generation key updates keep first accepted material'` PASS (`+1`).
- `flutter test --no-pub test/features/groups/application/rotate_group_key_use_case_test.dart --plain-name 'KE-014 rotateGroupKey fails closed and preserves latest key'` PASS (`+1`).
- `flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart` PASS (`+25`).
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart` PASS (`+49`).
- `dart analyze lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart test/features/groups/integration/group_messaging_smoke_test.dart` PASS (`No issues found!`).
- `dart format --set-exit-if-changed lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart test/features/groups/integration/group_messaging_smoke_test.dart` PASS (`0 changed`).
- `(cd go-mknoon && go test ./bridge -run 'TestGroupGenerateNextKey|TestGroupUpdateKey' -count=1)` PASS.
- `git diff --check` PASS before doc closure.

Named gate evidence:

- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` was run for KE-020 and remains red at `+193 -3` on preserved non-KE-020 residuals. Individual reruns confirmed:
  - `BB-007 accepted pending invite joins with exact full config and replays accepted epoch` fails with `Expected: not null / Actual: <null>` at `test/features/groups/integration/invite_round_trip_test.dart:679`.
  - `BB-012 restart recovery drains replay before ack and stays live` fails with `Expected: an object with length of <1> / Actual: WhereIterable<GroupMessage>:[]` at `test/features/groups/integration/group_startup_rejoin_smoke_test.dart:842`.
  - `GM-029 config version monotonicity converges across A/B/C shuffled delivery` fails with `Expected: MemberRole.writer / Actual: MemberRole.reader` at `test/features/groups/integration/group_membership_smoke_test.dart:8144`.
- `./scripts/run_test_gates.sh completeness-check` remains red on the unrelated classification gap `test/shared/fakes/fake_group_pubsub_network_test.dart` (`732/733` classified).

Skipped/out-of-scope:

- Source docs, COMPLETE_1 docs, source matrix docs, source `test-inventory.md`, Go/native changes, DB helper changes, durable cross-process locks, criteria/live-harness artifacts, KE-021+, KE-007/KE-009 re-reconciliation, BB-007 repair, BB-012 retention-fixture repair, GM-029 repair, listener/drain/replay-window residuals, ML-012 external-fixture repair, UI, media, notification, relay, and broader lifecycle/key-safety work were not imported.

Safe next action: continue with `INTEGRATE-KE-021` after ledger sanity and dirty-state safety checks. Separately, KE-007 and KE-009 remain recorded as `blocked_conflict` until explicitly re-reconciled after KE-017.
