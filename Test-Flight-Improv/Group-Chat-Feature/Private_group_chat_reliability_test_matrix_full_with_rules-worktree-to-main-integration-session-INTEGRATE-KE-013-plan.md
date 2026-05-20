# INTEGRATE-KE-013 Integration Contract - Restart Key Memory Protection

Status: accepted

Created: 2026-05-18

## Source Row

- Worktree source matrix row: `KE-013`
- Integration session: `INTEGRATE-KE-013`
- Title: `Restart with missing Go key memory does not generate duplicate epoch`
- Historical worktree plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-013-plan.md`
- Historical worktree plan status: `accepted`
- Active integration mode: standard worktree-to-main integration, not gap closure

## Row Contract

When Flutter persists the current group key at epoch `7` but the restarted Go node has no in-memory group key state, the next rotation must restore the persisted current key into Go before `group:generateNextKey`, generate epoch `8`, and never fabricate or persist duplicate epoch `2`. Missing persisted key state, restore failure, and stale generated epochs fail closed before direct distribution, generated-key promotion, local save, or system publish.

This row is independent of the KE-007/KE-009/KE-017 higher-epoch receive-repair blocker because KE-013 covers the generation precondition for a local admin rotation after restart, not receive-side repair for a message ahead of local key state.

## Integration Decision

Current main was missing the KE-013 generation precondition. This session imported only the missing KE-013 row-owned delta and the narrow affected-test reconciliations required by that preflight restore:

- `rotateAndDistributeGroupKey` now loads the persisted latest key, restores it into Go with `group:updateKey`, blocks absent persisted key/restore failure, and rejects generated epochs that do not equal persisted epoch plus one before distribution or promotion.
- Native `GroupGenerateNextKey` now returns `GROUP_KEY_NOT_FOUND` when Go has no current group key state instead of fabricating epoch `2`.
- Row-owned Dart, Go, and startup smoke tests cover restored epoch `7 -> 8`, absent persisted key, restore failure, stale generated epoch, and native missing-key failure.
- Affected preservation assertions were narrowed to reject generated-epoch promotion before distribution while allowing the KE-013 persisted-current-key restore.

No source worktree docs, source matrix status, COMPLETE_1 docs, source `test-inventory.md`, or later-row harness/script changes were imported.

## Owned Files

- `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- `go-mknoon/bridge/bridge.go`
- `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`
- `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`
- `go-mknoon/bridge/bridge_generate_next_key_test.go`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/integration/group_messaging_smoke_test.dart`
- this integration contract
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`

## Scope Guard

Do not import or repair KE-007, KE-009, KE-014+, KE-017, higher-epoch receive repair, pending-key receive repair, source docs, COMPLETE_1 docs, source matrix docs, source `test-inventory.md`, live harnesses, criteria scripts, runner scripts, BB-007, BB-012, GM-029, ML-012 external-fixture work, UI, media, notification, relay, or broader key-safety work under this row.

No iOS 26.2 live proof is required for KE-013; the historical source plan classifies Fake Network and 3-Party E2E as `N/A`.

## Required Evidence

- `flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart --plain-name 'KE-013'`
- `cd go-mknoon && go test ./bridge -run 'TestGroupGenerateNextKey_KE013' -count=1`
- `flutter test --no-pub test/features/groups/integration/group_startup_rejoin_smoke_test.dart --plain-name 'KE-013'`
- full rotation unit preservation
- affected send-message and GE-015 preservation selectors
- Go bridge preservation
- scoped format/analyzer/diff hygiene
- named `groups` and `completeness-check` gates, preserving known non-KE-013 residuals

## Final Execution Verdict

Verdict: accepted.

Imported the KE-013 restart key-memory protection into current main. A rotation after restart restores the persisted current key into Go before generating the next key, generates from the persisted epoch, and fails closed before side effects when persisted state is absent, restore fails, or Go returns a stale generated epoch.

Accepted files:

- `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- `go-mknoon/bridge/bridge.go`
- `test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart`
- `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`
- `go-mknoon/bridge/bridge_generate_next_key_test.go`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `test/features/groups/integration/group_messaging_smoke_test.dart`
- this integration contract
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`

Focused and preservation evidence:

- `flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart --plain-name 'KE-013'` PASS (`+4`).
- `cd go-mknoon && go test ./bridge -run 'TestGroupGenerateNextKey_KE013' -count=1` PASS.
- `flutter test --no-pub test/features/groups/integration/group_startup_rejoin_smoke_test.dart --plain-name 'KE-013'` PASS (`+1`).
- `flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart` PASS (`+23`).
- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'messages before during and after rotation bind to the locally committed epoch'` PASS (`+1`).
- `cd go-mknoon && go test ./bridge -run 'TestGroupGenerateNextKey' -count=1` PASS.
- `cd go-mknoon && go test ./bridge -count=1` PASS.
- `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name 'GE-015 admin restart during add/remove repairs fanout honestly'` PASS (`+1`).
- Full `test/features/groups/integration/group_startup_rejoin_smoke_test.dart` remains red only on preserved `BB-012`; KE-013 focused selector passes.
- `dart format --set-exit-if-changed` on touched Dart files PASS (`Formatted ... 0 changed`).
- `gofmt -w` on touched Go files completed.
- `git diff --check` PASS.
- Scoped `flutter analyze --no-pub` on touched files returned one existing non-KE-013 warning in `test/features/groups/integration/group_startup_rejoin_smoke_test.dart:26` (`_RecoveryJoinBridge.joinDelay` optional parameter is never given); no KE-013 implementation error was reported.

Named gate evidence:

- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+188 -3` on preserved non-KE-013 residuals:
  - `BB-007 accepted pending invite joins with exact full config and replays accepted epoch` fails with `Expected: not null / Actual: <null>` at `test/features/groups/integration/invite_round_trip_test.dart:679`.
  - `BB-012 restart recovery drains replay before ack and stays live` fails with no replayed message at `test/features/groups/integration/group_startup_rejoin_smoke_test.dart:842`; previous isolated evidence ties this to the May 11, 2026 replay fixture being older than the seven-day retention cutoff on May 18, 2026.
  - `GM-029 config version monotonicity converges across A/B/C shuffled delivery` fails with `Expected: MemberRole.writer / Actual: MemberRole.reader` at `test/features/groups/integration/group_membership_smoke_test.dart:8144`.
- `./scripts/run_test_gates.sh completeness-check` remains red on the unrelated classification gap `test/shared/fakes/fake_group_pubsub_network_test.dart` (`732/733` classified).

Live proof evidence:

- Not required for KE-013. Source plan marks Fake Network and 3-Party E2E as `N/A`; no iOS 26.2 live proof was run for this row.

Skipped/out-of-scope:

- KE-007, KE-009, KE-014+, KE-017, higher-epoch receive repair, pending-key receive repair, source worktree docs, COMPLETE_1 docs, source matrix docs, source `test-inventory.md`, criteria scripts, live harnesses, runner scripts, BB-007 repair, BB-012 retention-fixture repair, GM-029 repair, ML-012 external-fixture repair, notification, media, UI, relay, and broader lifecycle work were not imported.

Safe next action: continue with `INTEGRATE-KE-014` after ledger sanity and dirty-state safety checks, preserving KE-007 and KE-009 conflict blockers, ML-012 external-fixture blocker, BB-007/BB-012/GM-029 residual group-gate failures, the completeness classification gap, and the existing scoped analyzer warning in `_RecoveryJoinBridge`.
