# INTEGRATE-NW-015 Plan - Minimal Standard Integration Contract

Status: accepted

Mode: standard worktree-to-main integration. This is import/reconcile/verify work for already-covered source row `NW-015`; it is not gap-closure mode and must not recreate or rewrite the historical source implementation plan.

## Real Scope

Own exactly integration row `INTEGRATE-NW-015`, sourced from historical row `NW-015`: "Manual peer dial/disconnect commands preserve group topic state."

Current row state at planning time:

- Source row: `NW-015`, `covered`.
- Integration row: `INTEGRATE-NW-015`, `pending_integration`.
- Prior row `INTEGRATE-NW-014` is `blocked_external_fixture`, but this row is host-only (`3-Party E2E=N/A`) and independent of the NW-014 live fixture blocker.

The row contract is: manual peer dial/disconnect commands while groups are active must not change membership, topic joins/subscriptions, config/key pointers, key epoch, or post-command group delivery.

## Source Of Truth

- Source worktree: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline`.
- Historical source plan: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-NW-015-plan.md`.
- Historical source plan and closure evidence are the source of truth for row behavior, proof shape, and accepted row-owned deltas.
- Current main wins over stale source implementation details where accepted `NW-013` and `NW-014` dirty changes already exist.

Historical source proof:

- `cd go-mknoon && go test ./node -run TestNW015` passed: `ok github.com/mknoon/go-mknoon/node 0.597s`.
- `flutter test test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "NW-015 manual peer dial and disconnect commands preserve group topic state"` passed with `+1`.
- Scoped format, analyze, and diff checks passed in the source worktree.

Current-main scout result:

- Current main lacks `TestNW015` in `go-mknoon/node/pubsub_test.go`.
- Current main lacks the Flutter `NW-015 manual peer dial and disconnect commands preserve group topic state` selector in `test/features/groups/integration/group_messaging_smoke_test.dart`.
- Only row-owned code/test import candidates are `go-mknoon/node/pubsub_test.go` and `test/features/groups/integration/group_messaging_smoke_test.dart`.

## Write Scope For Future Execution

Future execution under this contract may write only:

- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-NW-015-plan.md`
- `go-mknoon/node/pubsub_test.go`
- `test/features/groups/integration/group_messaging_smoke_test.dart`

This planning task writes only this contract file. Future execution must preserve accepted dirty `NW-013` and `NW-014` state, including the `NW-014 deterministic network chaos run maintains model invariants` fake-network selector in `group_messaging_smoke_test.dart`.

## Explicit Exclusions

Do not edit, import, rewrite, or regenerate:

- source matrix docs, source session breakdown docs, current integration ledgers, inventories, `COMPLETE_1` docs, or closure docs;
- production code, migrations, harnesses, scripts, criteria, source worktree files, or source worktree docs;
- live proof, UI, notifications, media, privacy, Android, physical iOS, macOS app-peer roles, NW-014 live fixture repair, or `PL-001+`;
- any file outside the future execution write scope above.

No iOS 26.2 proof is required for this row. No live proof command should be run.

## Closure Bar

`INTEGRATE-NW-015` is good enough when current main has the missing row-owned Go/native proof and Flutter fake-network selector imported or confirmed already present, focused NW-015 proof passes, NW-014 and NW-006 preservation selectors remain intact, scoped format/analyze/diff pass, and any broad groups/completeness failures are classified as non-NW-015 residuals.

Allowed terminal status options are exactly:

- `accepted`
- `skipped_already_present`
- `blocked_conflict`
- `blocked_external_fixture`

## Implementation Contract

1. Start with `git status --short` and treat existing accepted dirty `NW-013` and `NW-014` changes as context, not work to revert.
2. Compare current main against the historical source row only for the two row-owned import files.
3. If both NW-015 selectors are already present and verification passes, classify as `skipped_already_present`.
4. If import is needed, reconcile only the missing row-owned deltas:
   - `TestNW015ManualDialDisconnectPreservesGroupTopicConfigAndKey` in `go-mknoon/node/pubsub_test.go`;
   - Flutter selector `NW-015 manual peer dial and disconnect commands preserve group topic state` in `test/features/groups/integration/group_messaging_smoke_test.dart`.
5. Preserve existing NW-014 fake-network selector/imports and adjacent accepted NW-013 behavior in `group_messaging_smoke_test.dart`.
6. Stop on any conflict that requires excluded file edits or production behavior changes; classify it as `blocked_conflict`.

## Verification Commands

Focused NW-015 proof:

```bash
cd go-mknoon && go test ./node -run TestNW015 -count=1
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "NW-015 manual peer dial and disconnect commands preserve group topic state"
```

Preservation selectors:

```bash
flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "NW-014 deterministic network chaos run maintains model invariants"
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name "NW-006 peer disconnect does not remove group membership and replay restores the missed message once"
```

Optional native adjacency selector:

```bash
cd go-mknoon && go test ./node -run 'TestGroupRecovery_PreservesTopicStateAcrossInPlaceRefresh|TestKnownGroupMemberDial_PrefersExistingOrDirectPathBeforeRelay' -count=1
```

Scoped maintenance:

```bash
gofmt -w go-mknoon/node/pubsub_test.go
dart format --set-exit-if-changed test/features/groups/integration/group_messaging_smoke_test.dart
flutter analyze test/features/groups/integration/group_messaging_smoke_test.dart
git diff --check -- go-mknoon/node/pubsub_test.go test/features/groups/integration/group_messaging_smoke_test.dart Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-NW-015-plan.md
```

Run `gofmt` only if `go-mknoon/node/pubsub_test.go` changes.

Broad residual classification:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
```

If broad gates remain red, acceptance requires exact classification that failures are pre-existing or non-NW-015 residuals, not caused by this row.

## Known-Failure Interpretation

- `INTEGRATE-NW-014` being `blocked_external_fixture` does not block this host-only row.
- Do not run or require a live iOS 26.2 proof for NW-015.
- Broad `groups` and `completeness-check` failures must not be fixed under this contract unless they are directly caused by the two row-owned NW-015 import files.

## Done Criteria

- Either both NW-015 selectors were already present and verified, or the missing row-owned source deltas were imported into the two allowed code/test files.
- Focused NW-015 Go and Flutter proof passes or any blocker is classified under one of the allowed terminal statuses.
- NW-014 and NW-006 preservation selectors are not regressed.
- Scoped format/analyze/diff pass for touched files.
- No excluded files are edited.

## Execution Progress

- 2026-05-20 17:27:59 CEST - Contract extracted; write scope limited to this plan, `go-mknoon/node/pubsub_test.go`, and `test/features/groups/integration/group_messaging_smoke_test.dart`.
- 2026-05-20 17:27:59 CEST - Inspected current dirty state; existing NW-013/NW-014 and unrelated dirty files treated as preserved context.
- 2026-05-20 17:27:59 CEST - Compared current target files with `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline`; current target lacked `TestNW015ManualDialDisconnectPreservesGroupTopicConfigAndKey` and the Flutter `NW-015 manual peer dial and disconnect commands preserve group topic state` selector.
- 2026-05-20 17:27:59 CEST - Imported only the missing NW-015-owned Go test and Flutter fake-network selector; preserved the existing NW-014 fake-network selector and adjacent dirty state.
- 2026-05-20 17:36:06 CEST - `gofmt -w go-mknoon/node/pubsub_test.go` passed.
- 2026-05-20 17:36:06 CEST - `dart format --set-exit-if-changed test/features/groups/integration/group_messaging_smoke_test.dart` passed with `Formatted 1 file (0 changed)`.
- 2026-05-20 17:36:06 CEST - `cd go-mknoon && go test ./node -run TestNW015 -count=1` passed: `ok github.com/mknoon/go-mknoon/node 0.730s`.
- 2026-05-20 17:36:06 CEST - `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "NW-015 manual peer dial and disconnect commands preserve group topic state"` passed.
- 2026-05-20 17:36:06 CEST - Preservation `flutter test --no-pub test/features/groups/integration/group_messaging_smoke_test.dart --plain-name "NW-014 deterministic network chaos run maintains model invariants"` passed.
- 2026-05-20 17:36:06 CEST - Preservation `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name "NW-006 peer disconnect does not remove group membership and replay restores the missed message once"` passed.
- 2026-05-20 17:36:06 CEST - Native adjacency `cd go-mknoon && go test ./node -run 'TestNW015|TestRP017RemovedPeerExcludedFromKnownAndDiscoveredDialsAfterConfigUpdate|TestFilterDiscoveredGroupMembers' -count=1` passed: `ok github.com/mknoon/go-mknoon/node 0.557s`.
- 2026-05-20 17:36:06 CEST - `flutter analyze test/features/groups/integration/group_messaging_smoke_test.dart` passed with no issues.
- 2026-05-20 17:36:06 CEST - `git diff --check -- go-mknoon/node/pubsub_test.go test/features/groups/integration/group_messaging_smoke_test.dart Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-NW-015-plan.md` passed. Supplemental trailing-whitespace scan over the same three files also found no matches.
- 2026-05-20 17:36:06 CEST - Broad `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` ran and remained red in non-NW-015 residuals. Filtered combined rerun identified these selectors: `BB-007 accepted pending invite joins with exact full config and replays accepted epoch`, `IR-003 timestamp replay boundary drains same-ms fake-network messages once`, `BB-012 restart recovery drains replay before ack and stays live`, `NW-004 reconnect recovery stays live after ack across multiple groups`, `IR-018 restart recovery keeps recovering state until replay drains and live stays active`, `GE-017 seeded random membership operations preserve invariants`, `GE-019 seeded random key rotations preserve access windows`, `GE-020 long soak private group with churn preserves convergence`, and `GM-029 config version monotonicity converges across A/B/C shuffled delivery`.
- 2026-05-20 17:36:06 CEST - Broad `./scripts/run_test_gates.sh completeness-check` ran and remained red on pre-existing/non-NW-015 classification gap: `test/shared/fakes/fake_group_pubsub_network_test.dart` is unmatched.
- 2026-05-20 17:36:06 CEST - Final execution verdict: `accepted`; NW-015 row-owned imports are present, focused proof and required preservation selectors pass, broad residuals are outside the NW-015 manual peer-command import.
- 2026-05-20 closure note - Controller spot-checks passed the focused Flutter NW-015 selector, Go `TestNW015`, Dart format with 0 changed, Go diff check over `node/pubsub_test.go`, and scoped row-owned `git diff --check`. Ledger closure is accepted/host-only; no iOS 26.2 or live proof is required or claimed, NW-014 remains `blocked_external_fixture`, and next safe row is `INTEGRATE-PL-001` after ledger sanity and dirty-state checks.
