Status: accepted

# INTEGRATE-BB-012 Standard Integration Plan

## Planning Progress

- 2026-05-17T04:54:00+02:00 - Inspected source matrix row `BB-012`, source session breakdown row, historical source plan/closure evidence, source test-inventory closure, source commit `e47a80d7`, current main production seams, main duplicate searches, and COMPLETE_1 overlap rows. Decision/blocker: source BB-012 is a bounded production-plus-tests row; main lacks exact BB-012 selectors and still has ack-before-drain behavior. Next action: execute a row-owned import, not a new rollout.

## Real Scope

This is a standard worktree-to-main integration contract for exactly `INTEGRATE-BB-012` / source row `BB-012`: recovery acknowledgement cannot clear the recovery flag before join and inbox drain finish.

The executor must reuse the historical source worktree BB-012 plan and closure as evidence only. Do not recreate, rewrite, or rerun the original source implementation plan. Do not reimplement the row from scratch. Import only missing meaningful BB-012-owned deltas into main, adapted to current main drift.

In scope:

- Make full `handleAppResumed` group recovery acknowledge only after successful `rejoinGroupTopics` and successful `drainGroupOfflineInbox`.
- Make `PendingMessageRetrier` ack-eligible recovery paths run rejoin, drain, then acknowledge only if the drain succeeded.
- Add the narrow drain result object/source-compatible return summary needed by ack gating while preserving per-group drain isolation.
- Import BB-012-owned selectors into:
  - `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
  - `test/core/services/pending_message_retrier_test.dart`
  - `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
  - `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`
- Preserve accepted BB-001 through BB-011 integration changes, especially BB-011 join-before-ack and no-ack-on-join-failure tests.
- Preserve COMPLETE_1 drain/replay behavior from overlapping rows such as GL-018, GR-006, GR-016, GP-026, GI-017/GI-018/GI-019/GI-020, GI-028/GI-030, and related drain-group offline inbox coverage.

Out of scope:

- Do not copy source matrix, source session breakdown, source test-inventory, or historical source plan docs into main.
- Do not edit main COMPLETE_1 docs for this row.
- Do not import BB-013+, RA-015, device/relay/3-party E2E, UI, notifications, media, observability, security, or broad replay/history repair rows.
- Do not redesign persistent recovery state, native Go topic state, relay-server behavior, or group membership/key policy.

## Closure Bar

The row is good enough when main contains the BB-012 source behavior or proves it was already present:

1. Full resume recovery sends `group:acknowledgeRecovery` only after all required `group:join` work and all required group inbox drains finish successfully.
2. Full resume recovery sends no ack while a group inbox drain is blocked/incomplete.
3. Full resume recovery sends no ack when group inbox drain reports an error.
4. Retrier-owned immediate and retry-sweep recovery order is rejoin, drain, acknowledge.
5. Retrier-owned recovery sends no ack while drain is incomplete or when drain fails.
6. `drainGroupOfflineInbox` reports per-group drain errors to callers while preserving existing per-group isolation.
7. A host fake-network startup/rejoin smoke proves replay drain happens before ack and post-ack publish stays live.
8. Focused BB-012 selectors, affected preservation selectors, host macOS `groups`, formatting, and `git diff --check` pass.
9. The integration ledger records one terminal status: `accepted`, `skipped_already_present`, `blocked_conflict`, or `blocked_external_fixture`.

## Source Of Truth

- Source row: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md` row `BB-012`.
- Source breakdown: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md` session `BB-012`.
- Historical worktree plan/evidence: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-012-plan.md`.
- Source closure evidence: source `test-inventory.md` row `BB-012` and source matrix `BB-012` covered note.
- Source commit evidence: `e47a80d7` (`BB-012: gate recovery ack on inbox drain`).
- Main integration controller: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`.
- Main compatibility artifact: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`.
- Current code and tests in main win over stale prose when they conflict.

## Session Classification

`implementation-ready`

Reason: source BB-012 has bounded production and test deltas with green host closure evidence. Current main lacks exact BB-012 selectors and still has ack-before-drain seams in the full resume and retrier paths.

## Source Commit And File Evidence

Source commit:

```text
e47a80d7 BB-012: gate recovery ack on inbox drain
```

Changed files in that commit:

```text
A Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-012-plan.md
M Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md
M Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md
M Test-Flight-Improv/Group-Chat-Feature/test-inventory.md
M lib/core/lifecycle/handle_app_resumed.dart
M lib/core/services/pending_message_retrier.dart
M lib/features/groups/application/drain_group_offline_inbox_use_case.dart
M test/core/lifecycle/handle_app_resumed_group_recovery_test.dart
M test/core/services/pending_message_retrier_test.dart
M test/features/groups/application/drain_group_offline_inbox_use_case_test.dart
M test/features/groups/integration/group_startup_rejoin_smoke_test.dart
```

Meaningful integration files are the three production files and four Flutter test files above. The four source docs are historical evidence only and must not be copied into main.

Source test evidence:

- `handle_app_resumed_group_recovery_test.dart` adds BB-012 lifecycle success, blocked-drain, and drain-failure selectors.
- `pending_message_retrier_test.dart` adds BB-012 retrier immediate, retry-sweep, blocked-drain, and drain-failure selectors.
- `drain_group_offline_inbox_use_case_test.dart` adds `BB-012 drain result reports per-group errors for recovery ack gating`.
- `group_startup_rejoin_smoke_test.dart` adds `BB-012 restart recovery drains replay before ack and stays live`.

## Duplicate Presence In Main

Observed main state during planning:

- Exact `BB-012` selector searches returned no matches in the four source-owned test files.
- `handleAppResumed` full group branch still calls `callGroupAcknowledgeRecovery` before `drainGroupOfflineInbox`.
- `PendingMessageRetrier` still acknowledges inside `_runGroupRejoinIfNeeded`, before `drainGroupOfflineInboxFn` runs.
- `drainGroupOfflineInbox` still returns `Future<void>` and swallows per-group errors without a caller-visible summary.
- `lib/main.dart` already returns the drain callback result from `drainGroupOfflineInbox`; if the retrier callback type is widened as in source, no direct main edit is expected.

If execution-time searches show BB-012 has landed since this plan was written, skip code/test edits and classify the row `skipped_already_present` with exact selector and production evidence.

## COMPLETE_1 Overlap Rows

Inspect these before resolving conflicts:

- `GR-006`: recovery acknowledgement waits for app recovery work.
- `GL-018`: persisted app rejoin sends current config/key after restart.
- `GR-016`: watchdog restart rejoins private groups and resumes delivery.
- `GP-026`: inbox replay dedupes after live delivery.
- `GI-017`, `GI-018`, `GI-019`, `GI-020`: offline replay pagination, removal/re-add windows, and durable replay repair.
- `GI-028`, `GI-030`: history repair/defaulting behavior that shares drain/history surfaces.
- Adjacent source rows `BB-011` and `BB-013`: preserve join-before-ack/no-ack-on-join-failure from BB-011; do not import timeout semantics from BB-013.

These rows are compatibility constraints, not a reason to broaden BB-012.

## Files To Inspect Or Update

Before editing, inspect:

```bash
git status --short
git diff -- lib/core/lifecycle/handle_app_resumed.dart lib/core/services/pending_message_retrier.dart lib/features/groups/application/drain_group_offline_inbox_use_case.dart test/core/lifecycle/handle_app_resumed_group_recovery_test.dart test/core/services/pending_message_retrier_test.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart test/features/groups/integration/group_startup_rejoin_smoke_test.dart
git -C /Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline show --name-status --no-renames e47a80d7
rg -n 'BB-012|BB012|acknowledges recovery only after joins|does not acknowledge recovery while inbox drain|does not acknowledge recovery when inbox drain|retri.*drains before ack|drain result reports|restart recovery drains replay' lib/core/lifecycle/handle_app_resumed.dart lib/core/services/pending_message_retrier.dart lib/features/groups/application/drain_group_offline_inbox_use_case.dart test/core/lifecycle/handle_app_resumed_group_recovery_test.dart test/core/services/pending_message_retrier_test.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart test/features/groups/integration/group_startup_rejoin_smoke_test.dart
```

Source files to compare:

```text
/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/lib/core/lifecycle/handle_app_resumed.dart
/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/lib/core/services/pending_message_retrier.dart
/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/lib/features/groups/application/drain_group_offline_inbox_use_case.dart
/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/test/core/lifecycle/handle_app_resumed_group_recovery_test.dart
/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/test/core/services/pending_message_retrier_test.dart
/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/test/features/groups/application/drain_group_offline_inbox_use_case_test.dart
/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/test/features/groups/integration/group_startup_rejoin_smoke_test.dart
```

Main files to update only if missing the BB-012 delta:

```text
lib/core/lifecycle/handle_app_resumed.dart
lib/core/services/pending_message_retrier.dart
lib/features/groups/application/drain_group_offline_inbox_use_case.dart
test/core/lifecycle/handle_app_resumed_group_recovery_test.dart
test/core/services/pending_message_retrier_test.dart
test/features/groups/application/drain_group_offline_inbox_use_case_test.dart
test/features/groups/integration/group_startup_rejoin_smoke_test.dart
```

Docs to update after execution:

```text
Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-BB-012-plan.md
Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md
```

## Device/Relay Proof Profile

Required closure profile: `host-only`.

BB-012 source closure claims Smoke/Fake Network through the host macOS `groups` gate and the `FakeGroupPubSubNetwork` startup replay-before-ack selector. 3-Party E2E is `N/A` for this row and must not be added or claimed. Do not mark `blocked_external_fixture` unless execution unexpectedly discovers a new required external fixture.

## Step-By-Step Integration Plan

1. Reconfirm `INTEGRATE-BB-011` is accepted in the integration breakdown and BB-012 is still `pending_integration`.
2. Re-run duplicate searches for exact BB-012 selectors and production behavior.
3. Inspect uncommitted main diffs in all seven candidate files. If an uncommitted change overlaps exact BB-012 hunks and is not plainly the same row delta, stop and classify `blocked_conflict`.
4. Compare source commit `e47a80d7` hunks against current main.
5. Import the narrow drain result type and `drainGroupOfflineInbox` return summary, preserving current drain concurrency, flow events, and per-group isolation.
6. Move full resume ack after successful drain. Use current main's `rejoinResult.canAcknowledgeGroupRecovery` predicate where appropriate rather than regressing to stale `errorCount == 0` semantics if the property is the accepted main contract.
7. Move retrier-owned ack after drain success. Preserve existing non-ack retry order and external recovery skip behavior.
8. Import only missing BB-012 selectors into the four test files, adapting to current main helpers and BB-011 additions.
9. Do not import source doc changes.
10. Run focused BB-012 tests and affected preservation tests below.
11. Assign one terminal status:
    - `accepted`: missing meaningful BB-012 delta imported and required tests/gates pass.
    - `skipped_already_present`: all meaningful BB-012 delta was already present in main with concrete selector and production evidence.
    - `blocked_conflict`: main has overlapping unmerged changes or COMPLETE_1 behavior that cannot be reconciled within row scope.
    - `blocked_external_fixture`: only if execution discovers a truly required external fixture is unavailable.

## Conflict Stop/Map Rule

Stop before resolving and map conflicts if any of these are true:

- Current main intentionally moved ack policy in a way that conflicts with BB-012 drain-before-ack.
- Making drain errors caller-visible would weaken COMPLETE_1 replay, repair, cursor, pagination, retention, dedupe, or media/reaction drain behavior.
- Passing BB-012 would require BB-013 timeout semantics, RA-015 re-add convergence, or device/relay/3-party proof.
- The source patch would overwrite accepted BB-011 selectors or previously accepted BB-001 through BB-010 behavior.

When stopped, record:

- exact conflicting files/hunks
- source rows implicated: `BB-012` and any adjacent rows, especially `BB-011` and `BB-013`
- main/COMPLETE_1 rows implicated: at minimum the overlap rows above if touched
- recommended next action

Do not resolve such conflicts inside this row without a new controller decision.

## Tests And Gates To Run

Focused BB-012 proof:

```bash
flutter test --no-pub test/core/lifecycle/handle_app_resumed_group_recovery_test.dart --plain-name 'BB-012'
flutter test --no-pub test/core/services/pending_message_retrier_test.dart --plain-name 'BB-012'
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'BB-012'
flutter test --no-pub test/features/groups/integration/group_startup_rejoin_smoke_test.dart --plain-name 'BB-012'
```

Affected COMPLETE_1/main preservation:

```bash
flutter test --no-pub test/core/lifecycle/handle_app_resumed_group_recovery_test.dart --plain-name 'BB-011'
flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart --plain-name 'GR-006'
flutter test --no-pub test/features/groups/integration/group_startup_rejoin_smoke_test.dart --plain-name 'BB-011'
flutter test --no-pub test/features/groups/integration/group_startup_rejoin_smoke_test.dart --plain-name 'GL-018'
flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'GR-016'
flutter test --no-pub test/core/services/pending_message_retrier_test.dart --plain-name 'ack'
flutter test --no-pub test/core/services/pending_message_retrier_upload_ordering_test.dart
flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart --plain-name 'callGroupAcknowledgeRecovery'
flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name 'group:acknowledgeRecovery'
flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GP-026'
```

Smoke/backstop:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
dart format --set-exit-if-changed lib/core/lifecycle/handle_app_resumed.dart lib/core/services/pending_message_retrier.dart lib/features/groups/application/drain_group_offline_inbox_use_case.dart test/core/lifecycle/handle_app_resumed_group_recovery_test.dart test/core/services/pending_message_retrier_test.dart test/features/groups/application/drain_group_offline_inbox_use_case_test.dart test/features/groups/integration/group_startup_rejoin_smoke_test.dart
git diff --check
```

Run `baseline` only if execution unexpectedly touches broad non-row surfaces outside the seven owner files.

## Done Criteria

- Source BB-012 row, source plan/closure, source commit, exact changed files, duplicate presence, and COMPLETE_1 overlaps were inspected.
- Main contains the row-owned BB-012 production and test delta, or the row is explicitly `skipped_already_present`.
- No duplicate adjacent BB/GL/GR/GI/GP work was imported.
- Required focused tests and affected preservation selectors pass.
- `git diff --check` passes.
- Integration breakdown ledger is updated with one terminal status and concrete evidence.
- This plan records execution outcome, changed files, tests run, skipped duplicate/unrelated work, conflicts, and next session.

## Scope Guard

Do not:

- Copy source closure docs into main.
- Add BB-013 timeout semantics.
- Add RA-015, device/relay proof, or 3-party E2E.
- Rewrite the drain/replay architecture beyond the narrow result summary needed for ack gating.
- Touch COMPLETE_1 docs.
- Use this row to fix unrelated dirty worktree changes.

## Accepted Differences / Intentionally Out Of Scope

- Current main's `rejoinResult.canAcknowledgeGroupRecovery` predicate may be retained instead of source commit's raw `errorCount == 0`, as long as BB-011 and BB-012 tests pass.
- Group-repo-only resume remains join-before-ack only because it has no message repository and no drain dependency.
- 3-party E2E remains N/A.
- Source docs remain evidence only and are not copied.

## Reviewer Pass

Verdict: sufficient for a standard integration execution pass.

Findings:

- The plan names the source row, source closure, source commit, exact changed files, duplicate state in main, and relevant overlap rows.
- The plan prevents source doc copying and gap-closure expansion.
- The plan has an explicit conflict stop/map rule and terminal status contract.
- The plan requires focused BB-012 tests plus affected BB-011/GR-006/GL-018/GR-016/pending-retrier/bridge/drain preservation and the `groups` gate.

## Arbiter Decision

Final verdict: `execution-ready`.

Structural blockers remaining: none.

Incremental details intentionally deferred:

- Exact helper placement in main test files because line numbers have drifted after BB-011 and accepted COMPLETE_1 work.
- Whether `baseline` is run; it is conditional and not part of source BB-012 required closure.

Accepted differences intentionally left unchanged:

- No 3-party E2E proof claim.
- No BB-013 timeout import.
- No COMPLETE_1 doc edits.

## Execution Progress

- 2026-05-17T04:59:00+02:00 - Imported only the missing BB-012 row-owned delta into main: drain result reporting, full-resume drain-before-ack gating, retrier-owned rejoin/drain/ack ordering, and four BB-012 test selector groups. Source docs were not copied and COMPLETE_1 docs were not edited.
- 2026-05-17T04:59:00+02:00 - Verified focused BB-012 selectors and affected BB-011/GR-006/GL-018/GR-016/retrier/bridge/drain preservation selectors. The macOS `groups` gate, Dart format check, and `git diff --check` passed.

## Final Execution Result

Status: `accepted`.

Changed files accepted for this row:

- `lib/core/lifecycle/handle_app_resumed.dart`
- `lib/core/services/pending_message_retrier.dart`
- `lib/features/groups/application/drain_group_offline_inbox_use_case.dart`
- `test/core/lifecycle/handle_app_resumed_group_recovery_test.dart`
- `test/core/services/pending_message_retrier_test.dart`
- `test/features/groups/application/drain_group_offline_inbox_use_case_test.dart`
- `test/features/groups/integration/group_startup_rejoin_smoke_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-BB-012-plan.md`

Tests and gates passed:

- `flutter test --no-pub test/core/lifecycle/handle_app_resumed_group_recovery_test.dart --plain-name 'BB-012'` (`+3`)
- `flutter test --no-pub test/core/services/pending_message_retrier_test.dart --plain-name 'BB-012'` (`+4`)
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'BB-012'` (`+1`)
- `flutter test --no-pub test/features/groups/integration/group_startup_rejoin_smoke_test.dart --plain-name 'BB-012'` (`+1`)
- `flutter test --no-pub test/core/lifecycle/handle_app_resumed_group_recovery_test.dart --plain-name 'BB-011'` (`+2`)
- `flutter test --no-pub test/core/lifecycle/app_lifecycle_recovery_test.dart --plain-name 'GR-006'` (`+1`)
- `flutter test --no-pub test/features/groups/integration/group_startup_rejoin_smoke_test.dart --plain-name 'BB-011'` (`+1`)
- `flutter test --no-pub test/features/groups/integration/group_startup_rejoin_smoke_test.dart --plain-name 'GL-018'` (`+1`)
- `flutter test --no-pub test/features/groups/integration/group_resume_recovery_test.dart --plain-name 'GR-016'` (`+1`)
- `flutter test --no-pub test/core/services/pending_message_retrier_test.dart --plain-name 'ack'` (`+6`)
- `flutter test --no-pub test/core/services/pending_message_retrier_upload_ordering_test.dart` (`+3`)
- `flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart --plain-name 'callGroupAcknowledgeRecovery'` (`+3`)
- `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name 'group:acknowledgeRecovery'` (`+1`)
- `flutter test --no-pub test/features/groups/application/drain_group_offline_inbox_use_case_test.dart --plain-name 'GP-026'` (`+1`)
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` (`+167`)
- `dart format --set-exit-if-changed ...` (`0 changed`)
- `git diff --check`

Skipped duplicate/unrelated work:

- Source matrix, source session breakdown, source test-inventory, and historical source plan docs remain evidence only and were not copied.
- COMPLETE_1 docs were not touched.
- No BB-013 timeout semantics, RA-015 work, device/relay/3-party E2E proof, UI, notification, media, observability, security, or broad replay/history repair work was imported.

Conflicts: none.

Next session: `INTEGRATE-BB-013`.
