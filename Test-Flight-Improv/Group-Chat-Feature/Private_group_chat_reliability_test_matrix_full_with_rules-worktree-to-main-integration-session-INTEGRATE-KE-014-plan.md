# INTEGRATE-KE-014 Integration Contract - Legacy RotateKey Fail-Closed

Status: accepted

Created: 2026-05-18

## Source Row

- Worktree source matrix row: `KE-014`
- Integration session: `INTEGRATE-KE-014`
- Title: `Legacy rotateKey cannot mutate Go before distribution is durably owned`
- Historical worktree plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-KE-014-plan.md`
- Historical worktree plan status: `accepted`
- Active integration mode: standard worktree-to-main integration, not gap closure

## Row Contract

The legacy `group:rotateKey` path must fail closed before generating, saving, returning, or committing any new key material. Durable group-key rotation remains owned by `rotateAndDistributeGroupKey`, which generates the next key, distributes it to active recipients, and only then promotes it with `group:updateKey`.

## Integration Decision

Current main already had the modern distributed rotation path and its fail-closed preservation tests, but still exposed the legacy helper/use-case/native bridge path that could immediately mutate local Go validator state. This session imported only the missing KE-014 row-owned delta:

- `callGroupRotateKey` now returns `LEGACY_ROTATE_KEY_UNSUPPORTED` locally without sending `group:rotateKey`.
- `rotateGroupKey` now fails before any repository save because the legacy helper is unsupported.
- Native `GroupRotateKey` still validates initialization, JSON, and `groupId`, then returns `LEGACY_ROTATE_KEY_UNSUPPORTED` before key generation or `UpdateGroupKey`.
- Row-owned tests replace stale success expectations with no-send, no-save, no-mutation, and fake-network epoch-preservation proofs.

No source worktree docs, source matrix status, COMPLETE_1 docs, source `test-inventory.md`, criteria scripts, live harnesses, runner scripts, or later-row key-repair behavior were imported.

## Owned Files

- `lib/core/bridge/bridge_group_helpers.dart`
- `lib/features/groups/application/rotate_group_key_use_case.dart`
- `go-mknoon/bridge/bridge.go`
- `test/core/bridge/bridge_group_helpers_test.dart`
- `test/features/groups/application/rotate_group_key_use_case_test.dart`
- `test/features/groups/integration/group_edge_cases_smoke_test.dart`
- `go-mknoon/bridge/bridge_test.go`
- this integration contract
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`

## Scope Guard

Do not import or repair KE-015+, partial key distribution recovery, concurrent rotation epoch allocation, higher-epoch receive repair, pending-key receive repair, KE-007/KE-009/KE-017 blockers, BB-007, BB-012, GM-029, ML-012 external-fixture work, source docs, COMPLETE_1 docs, source matrix docs, source `test-inventory.md`, live harnesses, criteria scripts, runner scripts, UI, media, notification, relay, or broader lifecycle work under this row.

No iOS 26.2 live proof is required for KE-014; the source plan classifies host fake-network proof as sufficient and live group-real-network-nightly as optional only.

## Required Evidence

- `flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart --plain-name 'callGroupRotateKey legacy helper'`
- `flutter test --no-pub test/features/groups/application/rotate_group_key_use_case_test.dart --plain-name 'KE-014 rotateGroupKey fails closed and preserves latest key'`
- `cd go-mknoon && go test ./bridge -run 'TestGroupRotateKey|TestGroupGenerateNextKey' -count=1`
- `flutter test --no-pub test/features/groups/integration/group_edge_cases_smoke_test.dart --plain-name 'KE-014 failed legacy rotation keeps later sends on previous key epoch'`
- full modern rotation unit preservation
- affected send-message epoch-binding preservation
- full Go bridge preservation
- scoped format/analyzer/diff hygiene
- named `groups` and `completeness-check` gates, preserving known non-KE-014 residuals

## Final Execution Verdict

Verdict: accepted.

Imported the KE-014 legacy rotation fail-closed behavior into current main. Legacy Dart and Go `rotateKey` entry points now reject the operation before bridge send, repository save, key generation, native `UpdateGroupKey`, or epoch promotion. Later sends remain on the previously committed epoch.

Accepted files:

- `lib/core/bridge/bridge_group_helpers.dart`
- `lib/features/groups/application/rotate_group_key_use_case.dart`
- `go-mknoon/bridge/bridge.go`
- `test/core/bridge/bridge_group_helpers_test.dart`
- `test/features/groups/application/rotate_group_key_use_case_test.dart`
- `test/features/groups/integration/group_edge_cases_smoke_test.dart`
- `go-mknoon/bridge/bridge_test.go`
- this integration contract
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`

Focused and preservation evidence:

- `flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart --plain-name 'callGroupRotateKey legacy helper'` PASS (`+1`).
- `flutter test --no-pub test/features/groups/application/rotate_group_key_use_case_test.dart --plain-name 'KE-014 rotateGroupKey fails closed and preserves latest key'` PASS (`+1`).
- `cd go-mknoon && go test ./bridge -run 'TestGroupRotateKey|TestGroupGenerateNextKey' -count=1` PASS.
- `flutter test --no-pub test/features/groups/integration/group_edge_cases_smoke_test.dart --plain-name 'KE-014 failed legacy rotation keeps later sends on previous key epoch'` PASS (`+1`) after using the file-local wait helper for deterministic delivery polling.
- `flutter test --no-pub test/features/groups/application/rotate_and_distribute_group_key_use_case_test.dart` PASS (`+23`).
- `flutter test --no-pub test/features/groups/application/send_group_message_use_case_test.dart --plain-name 'messages before during and after rotation bind to the locally committed epoch'` PASS (`+1`).
- `cd go-mknoon && go test ./bridge -count=1` PASS.
- `dart format --set-exit-if-changed` on touched Dart files PASS (`Formatted ... 0 changed` after formatting).
- `gofmt -w` on touched Go files completed.
- `git diff --check` PASS.
- Scoped `dart analyze` on touched Dart files returned only existing info-level style findings in `lib/core/bridge/bridge_group_helpers.dart:46` and `:48`; no KE-014 error or warning remains.

Named gate evidence:

- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` remains red at `+189 -3` only on preserved non-KE-014 residuals:
  - `BB-007 accepted pending invite joins with exact full config and replays accepted epoch` fails with `Expected: not null / Actual: <null>` at `test/features/groups/integration/invite_round_trip_test.dart:679`.
  - `BB-012 restart recovery drains replay before ack and stays live` fails with no replayed message at `test/features/groups/integration/group_startup_rejoin_smoke_test.dart:842`; previous isolated evidence ties this to the May 11, 2026 replay fixture being older than the seven-day retention cutoff on May 18, 2026.
  - `GM-029 config version monotonicity converges across A/B/C shuffled delivery` fails with `Expected: MemberRole.writer / Actual: MemberRole.reader` at `test/features/groups/integration/group_membership_smoke_test.dart:8144`.
- `./scripts/run_test_gates.sh completeness-check` remains red on the unrelated classification gap `test/shared/fakes/fake_group_pubsub_network_test.dart` (`732/733` classified).

Live proof evidence:

- Not required for KE-014. No iOS 26.2 live proof was run.

Skipped/out-of-scope:

- KE-015+, partial-distribution recovery, concurrent epoch allocation, higher-epoch receive repair, pending-key receive repair, KE-007/KE-009/KE-017 blockers, source worktree docs, COMPLETE_1 docs, source matrix docs, source `test-inventory.md`, criteria scripts, live harnesses, runner scripts, BB-007 repair, BB-012 retention-fixture repair, GM-029 repair, ML-012 external-fixture repair, notification, media, UI, relay, and broader lifecycle work were not imported.

Safe next action: continue with `INTEGRATE-KE-015` after ledger sanity and dirty-state safety checks, preserving KE-007 and KE-009 conflict blockers, ML-012 external-fixture blocker, BB-007/BB-012/GM-029 residual group-gate failures, and the completeness classification gap.
