Status: accepted

# INTEGRATE-BB-010 Standard Integration Plan

## Planning Progress

- 2026-05-17T05:12:00+02:00 - Spawned planner fallback invoked. Files inspected since last update: integration breakdown, source BB-010 matrix row, source BB-010 breakdown entry, source BB-010 plan, source commit `b5649694`, main COMPLETE_1 compatibility rows, current main duplicate searches, and dirty status. Decision/blocker: spawned planner left only `planning-intake` after bounded waits; local plan fallback is artifact-only and current-session-only. Next action: write execution-safe integration contract.
- 2026-05-17T05:20:00+02:00 - Local planner completed. Files inspected since last update: source commit changed-file list/stat, source production hunk, source test selector names, source plan final execution result, main exact-symbol searches, and COMPLETE_1 overlap evidence. Decision/blocker: BB-010 is importable but has a narrow production delta plus four Flutter test deltas; no source docs should be copied. Next action: execute BB-010 only.

## Real Scope

This is a standard worktree-to-main integration contract for exactly `INTEGRATE-BB-010` / source row `BB-010`: leave failure does not mutate Flutter into a false removed or joined state.

The executor must import, reconcile, or skip only the meaningful BB-010 delta already implemented in the source worktree. Do not recreate the source implementation plan, do not rerun the original rollout plan, and do not broaden into new gap closure.

In scope:

- Inspect the source BB-010 row, source BB-010 plan/evidence/closure, source commit, and main duplicate state before editing.
- Import only missing BB-010-owned code/test delta into main:
  - `lib/features/groups/application/group_message_listener.dart`
  - `test/features/groups/application/leave_group_use_case_test.dart`
  - `test/features/groups/application/delete_group_and_messages_use_case_test.dart`
  - `test/features/groups/application/group_message_listener_test.dart`
  - `test/features/groups/presentation/group_info_wired_test.dart`
- Preserve accepted main integration rows BB-001 through BB-009.
- Preserve overlapping COMPLETE_1 behavior for GM-015, GM-016, GM-017, GI-018, and GL-010.
- Update only this integration plan and the integration breakdown ledger after execution.

Out of scope:

- Do not copy source matrix, source session breakdown, source test-inventory, or the historical source BB-010 plan into main.
- Do not edit main COMPLETE_1 docs for this row.
- Do not import BB-011+, RA-015, re-add convergence, recovery acknowledgement ordering, fake-network/device/relay harness, UI polish beyond existing failure text, notifications, media, observability, or broad security work.
- Do not change native Go leave behavior; BB-010 is Flutter failed-native-leave local-state truthfulness.

## Closure Bar

The row is good enough when main contains the BB-010 source behavior or proves it was already present:

1. Forced `GROUP_ERROR` from `group:leave` propagates explicitly.
2. `leaveGroup` preserves local group, member, and key state after failed native leave.
3. The failed group remains eligible for `rejoinGroupTopics` with full config/key material.
4. Active `deleteGroupAndMessages` preserves group, members, keys, and messages after failed native leave.
5. Listener-driven self-removal leave failure preserves local group/member/key state, emits no false removed signal, saves no visible successful removal row, and does not append a durable `member_removed` event-log entry before native leave succeeds.
6. Non-self `member_removed` event-log and removal behavior remains unchanged.
7. The Group Info leave action stays mounted and shows `Failed to leave group` instead of navigating as success.
8. Required focused BB-010 selectors, bridge/leave/listener preservation selectors, host macOS `groups`, and `git diff --check` pass.
9. The integration ledger records one terminal status: `accepted`, `skipped_already_present`, `blocked_conflict`, or `blocked_external_fixture`.

## Source Of Truth

- Source row: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md` row `BB-010`.
- Source breakdown: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md` session `BB-010`.
- Historical worktree plan/evidence: `/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-010-plan.md`.
- Source closure evidence: source `test-inventory.md` BB-010 row and source matrix BB-010 covered note.
- Source commit evidence: `b5649694` (`BB-010: preserve state on failed leave`).
- Main integration controller: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md`.
- Main compatibility artifact: `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_COMPLETE_1-session-breakdown.md`.
- Current code and tests in main win over stale prose when they conflict.

## Session Classification

`implementation-ready`

Reason: source BB-010 has concrete file deltas and green host closure evidence. Current main lacks exact BB-010 selectors and still appears to append `member_removed` event-log state before failed self-removal leave succeeds, so execution should import the narrow row-owned delta unless duplicate evidence appears during execution.

## Source Commit And File Evidence

Source commit:

```text
b5649694 BB-010: preserve state on failed leave
```

Changed files in that commit:

```text
A Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-BB-010-plan.md
M Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-session-breakdown.md
M Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules.md
M Test-Flight-Improv/Group-Chat-Feature/test-inventory.md
M lib/features/groups/application/group_message_listener.dart
M test/features/groups/application/delete_group_and_messages_use_case_test.dart
M test/features/groups/application/group_message_listener_test.dart
M test/features/groups/application/leave_group_use_case_test.dart
M test/features/groups/presentation/group_info_wired_test.dart
```

Meaningful integration files are the five code/test files. The four source docs are historical evidence only and must not be copied into main.

Source code evidence:

- `group_message_listener.dart` moves the `member_removed` event-log append out of the pre-handler path, passes `appendSystemEventLog` into `_handleMemberRemoved`, appends after successful self `leaveGroup`, and appends before non-self local removal to preserve existing non-self behavior.
- `leave_group_use_case_test.dart` adds `BB-010 failed native leave preserves local state and rejoin eligibility`.
- `delete_group_and_messages_use_case_test.dart` adds `BB-010 active delete preserves group messages when native leave fails`.
- `group_message_listener_test.dart` adds `BB-010 self-removal leave failure preserves local state and emits no removed signal`.
- `group_info_wired_test.dart` adds `BB-010 native leave failure stays on info screen and shows failed leave`.

## Duplicate Presence In Main

Observed main state during planning:

- Searches found no `BB-010` / `BB010` selector strings in the four BB-010 test files.
- `group_info_wired.dart` already shows `Failed to leave group` for caught leave errors; this may make the widget test a proof-only import.
- `group_message_listener.dart` still has existing `appendSystemEventLog` calls around membership handlers; execution must inspect current line drift before applying the source hunk.
- Existing bridge helper and go-bridge-client tests already cover `group:leave` command shape and non-ok response mapping; use them as preservation checks, not duplicate work.

If execution-time searches show BB-010 has landed since this plan was written, skip code/test edits and classify the row `skipped_already_present` with exact file/selector evidence.

## COMPLETE_1 Overlap Rows

Inspect these before resolving conflicts:

- `GM-015`: last-admin/self-leave policy stays explicit and blocked when applicable.
- `GM-016`: removed member remains unsubscribed from topic after successful leave/removal.
- `GM-017`: stale removed member cannot publish accepted messages.
- `GI-018`: removed-member offline replay cutoff around self-removal.
- `GL-010`: unknown native leave is safe/no-op and does not mutate unrelated joined state.

These rows are compatibility constraints, not an invitation to import their broader harness/device work.

## Files To Inspect Or Update

Before editing, inspect:

```bash
git status --short
git diff -- lib/features/groups/application/group_message_listener.dart test/features/groups/application/leave_group_use_case_test.dart test/features/groups/application/delete_group_and_messages_use_case_test.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/presentation/group_info_wired_test.dart
git -C /Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline show --name-status --no-renames b5649694
rg -n "BB-010|BB010|Failed to leave group|forced leave failure|GROUP_ERROR|groupRemovedStream|appendSystemEventLog|rejoinGroupTopics" lib/features/groups/application/group_message_listener.dart test/features/groups/application/leave_group_use_case_test.dart test/features/groups/application/delete_group_and_messages_use_case_test.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/presentation/group_info_wired_test.dart
```

Source files to compare:

```text
/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/lib/features/groups/application/group_message_listener.dart
/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/test/features/groups/application/leave_group_use_case_test.dart
/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/test/features/groups/application/delete_group_and_messages_use_case_test.dart
/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/test/features/groups/application/group_message_listener_test.dart
/Users/I560101/Project-Sat/mknoon-2/worktrees/full-rules-pipeline/test/features/groups/presentation/group_info_wired_test.dart
```

Main files to update only if missing the BB-010 delta:

```text
lib/features/groups/application/group_message_listener.dart
test/features/groups/application/leave_group_use_case_test.dart
test/features/groups/application/delete_group_and_messages_use_case_test.dart
test/features/groups/application/group_message_listener_test.dart
test/features/groups/presentation/group_info_wired_test.dart
```

Docs to update after execution:

```text
Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-BB-010-plan.md
Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-breakdown.md
```

## Device/Relay Proof Profile

Required closure profile: `host-only`.

BB-010 source closure did not require a simulator, paired device, external relay, or 3-party device-lab run. Fake Network is `Recommended` and remained unclaimed in source closure. 3-Party E2E is `N/A`.

Do not mark the row `blocked_external_fixture` unless execution unexpectedly discovers that required BB-010 acceptance now depends on unavailable external fixtures.

## Step-By-Step Integration Plan

1. Reconfirm `INTEGRATE-BB-009` is accepted in the integration breakdown and BB-010 is still `pending_integration`.
2. Re-run duplicate searches for exact BB-010 selectors and the `group_message_listener.dart` event-log ordering.
3. Inspect uncommitted main diffs in the five candidate files. If an uncommitted change overlaps the exact source BB-010 hunks, stop and classify `blocked_conflict` unless the overlap is plainly the same BB-010 delta.
4. Compare source commit `b5649694` hunks against current main:
   - Bring over the narrow `_handleMemberRemoved` event-log ordering change only if absent.
   - Bring over the four row-owned BB-010 tests only if absent.
5. Preserve main-local line drift and existing accepted tests. Use source behavior as the semantic source, not as a blind patch.
6. Do not import source doc changes.
7. Run focused BB-010 tests and affected preservation tests below.
8. Assign one terminal status:
   - `accepted`: missing meaningful BB-010 delta imported and required tests/gates pass.
   - `skipped_already_present`: all meaningful BB-010 delta was already present in main with concrete selector/code evidence.
   - `blocked_conflict`: main has overlapping unmerged changes or COMPLETE_1 behavior that cannot be reconciled within row scope.
   - `blocked_external_fixture`: only if execution discovers a truly required external fixture is unavailable.

## Conflict Stop/Map Rule

Stop before editing and map conflicts if any of these are true:

- `group_message_listener.dart` already handles failed self-removal leave with a different but equivalent event-log ordering.
- Current main intentionally changed listener removal/event-log semantics in a way that the source hunk would weaken.
- Imported BB-010 tests fail because current main intentionally changed leave-failure UX or local-state policy outside the source row's contract.
- COMPLETE_1 GM-015, GM-016, GM-017, GI-018, or GL-010 behavior would be weakened by the import.
- Passing BB-010 would require BB-011+ recovery ordering, RA-015 re-add convergence, fake-network harness work, or device/relay proof.

When stopped, record:

- exact conflicting files/hunks
- source rows implicated: `BB-010` and any adjacent source rows
- main/COMPLETE_1 rows implicated: at minimum the overlap rows above if touched
- recommended next action

Do not resolve such conflicts inside this row without a new controller decision.

## Tests And Gates To Run

Focused BB-010 proof:

```bash
flutter test --no-pub test/features/groups/application/leave_group_use_case_test.dart --plain-name 'BB-010'
flutter test --no-pub test/features/groups/application/delete_group_and_messages_use_case_test.dart --plain-name 'BB-010'
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'BB-010'
flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart --plain-name 'BB-010'
```

Affected COMPLETE_1/main preservation:

```bash
flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart --plain-name 'callGroupLeave'
flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart --plain-name 'throws BridgeCommandException when group:leave returns ok:false'
flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name 'group:leave'
flutter test --no-pub test/features/groups/application/leave_group_use_case_test.dart
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'self-removal'
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'member_removed removes other member and calls updateConfig'
flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'duplicate non-self member_removed keeps one timeline row and removal'
```

Smoke/backstop:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
dart format --set-exit-if-changed lib/features/groups/application/group_message_listener.dart test/features/groups/application/leave_group_use_case_test.dart test/features/groups/application/delete_group_and_messages_use_case_test.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/presentation/group_info_wired_test.dart
git diff --check
```

Run `baseline` only if execution unexpectedly touches production beyond `group_message_listener.dart` or broad non-row Flutter surfaces. Source BB-010 closure did not require baseline.

## Known-Failure Interpretation

- Failures in any `BB-010` focused selector are in scope.
- Failures in `callGroupLeave`, `group:leave`, full `leave_group_use_case_test.dart`, or the listed listener preservation selectors are integration blockers unless proven pre-existing from unchanged main.
- A `groups` gate failure may be classified unrelated only with exact failing test names and a clear reason they do not touch leave/removal/listener behavior.
- Missing fake-network/device/relay fixtures should not block BB-010 unless execution unexpectedly makes them required.

## Done Criteria

- Source BB-010 row, source plan/closure, source commit, exact changed files, duplicate presence, and COMPLETE_1 overlaps were inspected.
- Main contains the row-owned BB-010 production behavior and test selectors, or the row is explicitly `skipped_already_present`.
- No duplicate adjacent BB/GM/GI/GL work was imported.
- Required focused tests and affected preservation selectors pass.
- `git diff --check` passes.
- Integration breakdown ledger is updated with one terminal status and concrete evidence.
- This plan records execution outcome, changed files, tests run, skipped duplicate/unrelated work, conflicts, and next session.

## Scope Guard

Do not:

- Redesign leave/deletion/listener architecture.
- Add a new durable degraded-state model.
- Change successful leave cleanup semantics from BB-009.
- Implement BB-011+, RA-015, GM-016, GM-017, GI-018, or fake-network/device harness work.
- Touch COMPLETE_1 docs.
- Use this row to fix unrelated dirty worktree changes.

## Accepted Differences / Intentionally Out Of Scope

- Focused fake-network proof remains recommended and unclaimed.
- 3-Party E2E is N/A for BB-010.
- Group Info UI polish beyond existing explicit failed-leave state remains out of scope.
- Source BB-010 changed only one production file; production changes outside `group_message_listener.dart` should be treated as suspicious unless required by a compile-time main drift adaptation.

## Dependency Impact

BB-011+ and recovery ordering rows may rely on BB-010 only for the invariant that failed native leave preserves app-local truth and retry/rejoin eligibility. They must not assume restart acknowledgement ordering, re-add convergence, fake-network proof, or device/relay behavior was integrated here.

If BB-010 blocks, keep `INTEGRATE-BB-011+` pending until the conflict is mapped and resolved or explicitly accepted by the integration controller.

## Reviewer Pass

Verdict: sufficient for a standard integration execution pass.

Findings:

- The plan names the source row, source closure, source commit, exact changed files, duplicate state in main, and COMPLETE_1 overlap rows.
- The plan prevents source doc copying and gap-closure expansion.
- The plan has an explicit conflict stop/map rule and terminal status contract.
- The plan requires focused BB-010 tests plus affected bridge/leave/listener preservation and the `groups` gate.

## Arbiter Decision

Final verdict: `execution-ready`.

Structural blockers remaining: none.

Incremental details intentionally deferred:

- Exact helper placement in main test files because line numbers have drifted.
- Whether `baseline` is run; it is conditional and not part of source BB-010 required closure.

Accepted differences intentionally left unchanged:

- No fake-network proof claim.
- No BB-011+ or RA-015 import.
- No COMPLETE_1 doc edits.

## Execution Progress

- 2026-05-17T04:14:46+0200 (CEST) - Execution inspection in progress; no code or test files have been edited yet. Inspected this BB-010 integration plan, dirty main worktree status, scoped diff for the five owned BB-010 files, source BB-010 matrix row, source session breakdown/plan evidence, source `test-inventory.md` evidence, and source commit `b5649694` changed files/stat/hunks. Reconfirmed integration breakdown state read-only: `INTEGRATE-BB-009` is `accepted` and `INTEGRATE-BB-010` is still `pending_integration`; per user instruction, the integration breakdown will not be edited in this execution pass. Current main duplicate search found no exact `BB-010`/`BB010` selectors in the four owned test files. Current main listener inspection found `member_removed` still calls `appendSystemEventLog()` before `_handleMemberRemoved`, so the source BB-010 event-log ordering delta appears missing. Main also has later COMPLETE_1/GI-018-style self-removal cutoff-marker drift inside `_handleMemberRemoved`; that drift must be preserved while importing only the narrow BB-010 event-log delay and selectors. No tests have been run yet.
- 2026-05-17T04:19:12+0200 (CEST) - Imported the narrow BB-010 listener hunk and four BB-010 selectors. Changed files so far: `lib/features/groups/application/group_message_listener.dart`, `test/features/groups/application/leave_group_use_case_test.dart`, `test/features/groups/application/delete_group_and_messages_use_case_test.dart`, `test/features/groups/application/group_message_listener_test.dart`, and `test/features/groups/presentation/group_info_wired_test.dart`. Exact selectors added: `BB-010 failed native leave preserves local state and rejoin eligibility`; `BB-010 active delete preserves group messages when native leave fails`; `BB-010 self-removal leave failure preserves local state and emits no removed signal`; `BB-010 native leave failure stays on info screen and shows failed leave`. Main drift adaptation: the leave-use-case test seeds `publicKey: 'pk-peer-1'` so current `buildGroupConfigPayload` includes the preserved member in the rejoin payload; listener behavior preserves existing self-removal cutoff-marker logic while delaying only the durable event-log append until after successful native leave. Focused test status: `flutter test --no-pub test/features/groups/application/leave_group_use_case_test.dart --plain-name 'BB-010'` initially failed because the seeded member lacked deliverable identity, then passed after the public-key adaptation; `flutter test --no-pub test/features/groups/application/delete_group_and_messages_use_case_test.dart --plain-name 'BB-010'` passed; `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'BB-010'` initially hit a compile error from an incorrectly placed callback parameter, then passed after correction; `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart --plain-name 'BB-010'` passed. Remaining required work: preservation selectors, groups gate, final format check, `git diff --check`, and Final Execution Result. Integration breakdown remains unedited.

## Final Execution Result

Verdict: `accepted`.

Completed at 2026-05-17T04:21:51+0200 (CEST). Imported only the missing BB-010 row-owned delta from source commit `b5649694`: `group_message_listener.dart` now delays the durable `member_removed` event-log append until after successful self-removal native leave while preserving current main's self-removal cutoff marker and non-self removal behavior. Added the four BB-010 selectors named in the plan. No source docs, BB-011+, RA-015, COMPLETE_1 docs, fake-network/device/relay harness work, or integration breakdown edits were made.

Changed files:

- `lib/features/groups/application/group_message_listener.dart`
- `test/features/groups/application/leave_group_use_case_test.dart`
- `test/features/groups/application/delete_group_and_messages_use_case_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/groups/presentation/group_info_wired_test.dart`
- `Test-Flight-Improv/Group-Chat-Feature/Private_group_chat_reliability_test_matrix_full_with_rules-worktree-to-main-integration-session-INTEGRATE-BB-010-plan.md`

Tests and gates:

- `flutter test --no-pub test/features/groups/application/leave_group_use_case_test.dart --plain-name 'BB-010'` PASS after main-drift test adaptation (`publicKey: 'pk-peer-1'`).
- `flutter test --no-pub test/features/groups/application/delete_group_and_messages_use_case_test.dart --plain-name 'BB-010'` PASS.
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'BB-010'` PASS after correcting callback parameter placement.
- `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart --plain-name 'BB-010'` PASS.
- `flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart --plain-name 'callGroupLeave'` PASS.
- `flutter test --no-pub test/core/bridge/bridge_group_helpers_test.dart --plain-name 'throws BridgeCommandException when group:leave returns ok:false'` PASS.
- `flutter test --no-pub test/core/bridge/go_bridge_client_test.dart --plain-name 'group:leave'` PASS.
- `flutter test --no-pub test/features/groups/application/leave_group_use_case_test.dart` PASS.
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'self-removal'` PASS.
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'member_removed removes other member and calls updateConfig'` PASS.
- `flutter test --no-pub test/features/groups/application/group_message_listener_test.dart --plain-name 'duplicate non-self member_removed keeps one timeline row and removal'` PASS.
- `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` PASS (`+165`).
- `dart format --set-exit-if-changed lib/features/groups/application/group_message_listener.dart test/features/groups/application/leave_group_use_case_test.dart test/features/groups/application/delete_group_and_messages_use_case_test.dart test/features/groups/application/group_message_listener_test.dart test/features/groups/presentation/group_info_wired_test.dart` PASS.
- `git diff --check` PASS.

Skipped/unmodified: integration breakdown ledger by explicit user instruction; source matrix/breakdown/test-inventory docs; COMPLETE_1 docs; baseline gate because production changes were confined to `group_message_listener.dart` and no broad non-row Flutter surfaces were touched.

Conflicts/blockers: none.
