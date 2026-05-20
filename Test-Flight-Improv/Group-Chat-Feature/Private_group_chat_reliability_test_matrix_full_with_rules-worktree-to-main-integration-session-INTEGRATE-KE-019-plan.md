# INTEGRATE-KE-019 Integration Contract - Tampered Key Update Payload Rejection

Status: accepted

Created: 2026-05-18

## Source Row

- Worktree source matrix row: `KE-019`
- Integration session: `INTEGRATE-KE-019`
- Title: `Tampered key update payload is rejected and leaves current key intact`
- Historical worktree plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-019-plan.md`
- Historical worktree plan status: `accepted`
- Active integration mode: standard worktree-to-main integration, not gap closure

## Row Contract

Tampering the direct group key-update payload after signing, including key material, epoch, or sender identity, must reject before `payload.verify`, `group:updateKey`, event-log append, local key save, repair retry, or sender-side send-state mutation. The previously valid current key must remain usable for later publish.

## Integration Decision

Current main already rejected mismatched direct key-update signed payloads before verify/update/key save. This session imported only the missing row-owned KE-019 proof delta:

- diagnostic reason classification for invalid signature envelopes, including `signed_payload_mismatch`;
- the direct listener `KE-019` selector proving tamper variants and preserved current-epoch sendability;
- the fake-network `KE-019` selector proving a tampered distributed key update is rejected and previous-epoch delivery still works.

No source docs, COMPLETE_1 docs, source matrix docs, source `test-inventory.md`, Go/native changes, criteria scripts, live harnesses, or unrelated key-epoch rows were imported for KE-019.

## Owned Files

- `lib/features/groups/application/group_key_update_listener.dart`
- `test/features/groups/application/group_key_update_listener_test.dart`
- `test/features/groups/integration/group_messaging_smoke_test.dart`
- this integration contract
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`

## Scope Guard

Do not import source docs, COMPLETE_1 docs, source matrix docs, source `test-inventory.md`, Go/native files, criteria scripts, runner changes, live harness fields, KE-020+, KE-007/KE-009 re-reconciliation, concurrent rotation allocation, removed-member future key scoping, BB-007, BB-012, GM-029, ML-012 external-fixture work, listener/drain residuals, replay-window residuals, UI, media, notification, relay, or broader key-safety behavior under this row.

## Device/Relay Proof Profile

- Profile: host-only listener and fake-network proof.
- iOS 26.2 live proof: not required.
- Device ids/run id: N/A.

## Required Evidence

- focused KE-019 direct listener selector;
- focused KE-019 fake-network selector;
- affected direct key-update validation preservation selectors;
- adjacent fake-network key-epoch preservation selectors;
- full listener test file;
- full fake-network smoke file;
- scoped analyzer/format/diff hygiene;
- named `groups` and `completeness-check` gates, preserving unrelated residuals.

## Final Execution Verdict

Verdict: accepted.

Imported the missing KE-019 diagnostic reason and row-owned test proof. Existing main rejection behavior remained the production base and was not rewritten.

Accepted files:

- `lib/features/groups/application/group_key_update_listener.dart`
- `test/features/groups/application/group_key_update_listener_test.dart`
- `test/features/groups/integration/group_messaging_smoke_test.dart`
- this integration contract
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`

Focused and preservation evidence:

- `dart analyze lib/features/groups/application/group_key_update_listener.dart test/features/groups/application/group_key_update_listener_test.dart test/features/groups/integration/group_messaging_smoke_test.dart` PASS with exit code `0`; reported only existing info-level style diagnostics in the listener/test helpers.
- `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart --plain-name 'KE-019 rejects tampered direct key update payloads with diagnostics and keeps current key usable'` PASS (`+1`).
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'KE-019 tampered key update is rejected and preserved key still sends over fake network'` PASS (`+1`).
- Direct key-update preservation selector bundle PASS (`+5`): EK004 mismatched signed payload, EK004 invalid signature, tampered replay rejection, KE-005 same-generation conflict, and pending-key send epoch behavior.
- Adjacent fake-network key-epoch preservation selector bundle PASS (`+5`): KE-017, KE-015, KE-003, KE-004, and KE-005.
- `flutter test --no-pub test/features/groups/application/group_key_update_listener_test.dart` PASS (`+37`).
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart` PASS (`+48`).
- `dart format --set-exit-if-changed lib/features/groups/application/group_key_update_listener.dart test/features/groups/application/group_key_update_listener_test.dart test/features/groups/integration/group_messaging_smoke_test.dart` PASS (`0 changed`).
- `git diff --check` PASS before doc closure.

Named gate evidence:

- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` was run for KE-019. The row-owned focused and full files above passed; the known non-KE-019 residual selectors remain reproducible individually:
  - `BB-007 accepted pending invite joins with exact full config and replays accepted epoch` fails with `Expected: not null / Actual: <null>` at `test/features/groups/integration/invite_round_trip_test.dart:679`.
  - `BB-012 restart recovery drains replay before ack and stays live` fails with `Expected: an object with length of <1> / Actual: WhereIterable<GroupMessage>:[]` at `test/features/groups/integration/group_startup_rejoin_smoke_test.dart:842`.
  - `GM-029 config version monotonicity converges across A/B/C shuffled delivery` fails with `Expected: MemberRole.writer / Actual: MemberRole.reader` at `test/features/groups/integration/group_membership_smoke_test.dart:8144`.
- `./scripts/run_test_gates.sh completeness-check` remains red on the unrelated classification gap `test/shared/fakes/fake_group_pubsub_network_test.dart` (`732/733` classified).

Skipped/out-of-scope:

- Go/native changes, criteria/live-harness artifacts, source docs, COMPLETE_1 docs, source matrix docs, source `test-inventory.md`, KE-020+, KE-007/KE-009 re-reconciliation, BB-007 repair, BB-012 retention-fixture repair, GM-029 repair, listener/drain/replay-window residuals, ML-012 external-fixture repair, UI, media, notification, relay, and broader lifecycle/key-safety work were not imported.

Safe next action: continue with `INTEGRATE-KE-020` after ledger sanity and dirty-state safety checks. Separately, KE-007 and KE-009 remain recorded as `blocked_conflict` until explicitly re-reconciled after KE-017.
