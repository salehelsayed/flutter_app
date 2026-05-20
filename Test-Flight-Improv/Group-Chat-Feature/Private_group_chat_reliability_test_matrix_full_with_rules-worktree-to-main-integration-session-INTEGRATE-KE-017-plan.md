# INTEGRATE-KE-017 Integration Contract - Higher-Epoch Receive Repair

Status: accepted

Created: 2026-05-18

## Source Row

- Worktree source matrix row: `KE-017`
- Integration session: `INTEGRATE-KE-017`
- Title: `Received group event epoch matches local key state or triggers repair`
- Historical worktree plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-017-plan.md`
- Historical worktree plan status: `accepted`
- Active integration mode: standard worktree-to-main integration, not gap closure

## Row Contract

When a normal `group_message:received` event arrives at key epoch `N+1` while the local latest group key is epoch `N` or missing, the listener must persist and surface the message exactly once, emit `GROUP_RECEIVED_MESSAGE_KEY_EPOCH_AHEAD_OF_LOCAL`, and request pending-key repair with reason `received_message_epoch_missing_local_key`. A message at the local current epoch must not request repair.

## Integration Decision

Current main had partial pending-key repair infrastructure, but it did not have the exact KE-017 higher-epoch normal receive repair reason, diagnostic event, listener hook, or row-owned proof anchors. This session imported only the missing KE-017 row-owned delta:

- the repair reason constant `groupKeyRepairReasonReceivedMessageEpochMissingLocalKey`;
- a post-persistence listener check that compares incoming message epoch with local latest key epoch;
- diagnostics and repair request dispatch for higher-epoch normal receives;
- `GroupTestUser` injection of the row-owned repair callback for fake-network tests;
- listener and fake-network tests proving higher-epoch repair and same-epoch non-repair behavior.

No criteria, live-harness, Go, native, UI, notification, media, relay, or source-doc changes were imported for KE-017.

## Owned Files

- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/group_pending_key_repair_service.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `test/shared/fakes/group_test_user.dart`
- this integration contract
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`

## Scope Guard

Do not import or repair KE-007 first-post-rotation proof artifacts, KE-009 config-before-key proof artifacts, KE-018 history replay, concurrent rotation allocation, stale-invite ordering, pending-key receive repair beyond the KE-017 reason/hook, source docs, COMPLETE_1 docs, source matrix docs, source `test-inventory.md`, criteria scripts, live harnesses, unrelated fake-network scenarios, BB-007, BB-012, GM-029, ML-012 external-fixture work, UI, media, notification, relay, or broader lifecycle work under this row.

## Device/Relay Proof Profile

- Profile: host-only.
- iOS 26.2 live proof: not required and not run for KE-017.
- Rationale: the historical worktree KE-017 plan and closure evidence classify the row as normal host/fake-network repair verification, with no three-party device proof requirement.

## Required Evidence

- focused KE-017 listener selector;
- focused KE-017 fake-network selector;
- affected full fake-network smoke file;
- affected listener and drain preservation checks, preserving known non-KE-017 residuals;
- scoped analyzer/format/diff hygiene;
- named `groups` and `completeness-check` gates, preserving known non-KE-017 residuals.

## Final Execution Verdict

Verdict: accepted.

Imported the KE-017 repair reason, listener hook, diagnostic/repair dispatch, `GroupTestUser` repair callback injection, and row-owned listener/fake-network tests. The row is host-only; no live simulator proof was required or run.

Accepted files:

- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/group_pending_key_repair_service.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/integration/group_messaging_smoke_test.dart`
- `test/shared/fakes/group_test_user.dart`
- this integration contract
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`

Focused and preservation evidence:

- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'KE-017'` PASS (`+2`).
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'KE-017'` PASS (`+1`).
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --concurrency=1` PASS (`+47`).
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --name 'GEK002|GEK003|PREREQ-FUTURE-EPOCH-KEY-REPAIR'` remained red at `+2 -1`: `PREREQ-FUTURE-EPOCH-KEY-REPAIR` and `GEK002` passed; preserved non-KE-017 `GEK003 partial key-update delivery plus immediate post-rotation send repairs stale recipient after later key arrival` failed with `Expected: not null / Actual: <null>` at `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart:8041`.
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart` remained red at `+111 -6` while the KE-017 and GO-004 tests passed. The preserved non-KE-017 failures were self-peer caching expecting `2` but receiving `0` at `group_message_listener_test.dart:1542`, plus five existing notification expectation failures that received no local notification rows at `group_message_listener_test.dart:488`, `:7669`, and `:7738`.
- `dart analyze lib/features/groups/application/group_message_listener.dart lib/features/groups/application/group_pending_key_repair_service.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/integration/group_messaging_smoke_test.dart test/shared/fakes/group_test_user.dart` PASS (`No issues found!`).
- `dart format --set-exit-if-changed` on the five touched Dart files PASS (`0 changed` after formatting).
- `git diff --check` PASS before doc closure.

Named gate evidence:

- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+191 -3`, matching the preserved non-KE-017 residual gate shape plus the new passing KE-017 smoke coverage:
  - `BB-007 accepted pending invite joins with exact full config and replays accepted epoch` fails with `Expected: not null / Actual: <null>` at `test/features/groups/integration/invite_round_trip_test.dart:679`.
  - `BB-012 restart recovery drains replay before ack and stays live` fails with `Expected: an object with length of <1> / Actual: WhereIterable<GroupMessage>:[]` at `test/features/groups/integration/group_startup_rejoin_smoke_test.dart:842`.
  - `GM-029 config version monotonicity converges across A/B/C shuffled delivery` fails with `Expected: MemberRole.writer / Actual: MemberRole.reader` at `test/features/groups/integration/group_membership_smoke_test.dart:8144`.
- `./scripts/run_test_gates.sh completeness-check` remains red on the unrelated classification gap `test/shared/fakes/fake_group_pubsub_network_test.dart` (`732/733` classified).
- Final `git diff --check` PASS after the KE-017 row import.

Live proof evidence:

- Not applicable. KE-017 is host-only and no iOS 26.2 live proof was required or run.

Skipped/out-of-scope:

- KE-007 and KE-009 proof artifacts were not imported under KE-017, but their prior blocker dependency is now available for future row re-reconciliation.
- Criteria scripts, criteria tests, live harnesses, source worktree docs, COMPLETE_1 docs, source matrix docs, source `test-inventory.md`, KE-018+, history replay, concurrent rotation allocation, stale invite ordering, BB-007 repair, BB-012 retention-fixture repair, GM-029 repair, ML-012 external-fixture repair, notification, media, UI, relay, and broader lifecycle work were not imported.

Safe next action: continue with `INTEGRATE-KE-018` after ledger sanity and dirty-state safety checks. Separately, KE-007 and KE-009 may be re-evaluated in a future controller decision now that KE-017's higher-epoch receive repair dependency is present.
