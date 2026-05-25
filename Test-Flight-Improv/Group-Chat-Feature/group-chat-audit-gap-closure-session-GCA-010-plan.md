# GCA-010 Voluntary Leave Partial Broadcast-Before-Leave Ordering Plan

Status: executed - QA accepted

## Execution Progress

- 2026-05-23T22:41:35+02:00 - Final execution verdict written. Files inspected/touched: plan progress only after QA completion. Decision/blocker: recovered `GCA-010` is accepted with no blocking QA findings; source matrix and breakdown remain untouched for later closure. Residuals: `./scripts/run_test_gates.sh groups` remains red only on classified broad group failures, not on row-owned voluntary-leave ordering. Next action: hand off final verdict.
- 2026-05-23T22:41:18+02:00 - Recovery QA Reviewer completed. Files inspected: plan, gate definitions/script, `leave_group_use_case.dart`, `group_info_wired.dart`, `group_info_wired_test.dart`, and scoped diffs/status. Commands rerun by QA: recovered `GCA-010` selector, `BB-010`, sole-admin leave, multi-admin leave, writer leave, `leave_group_use_case_test.dart`, `git diff --check`, and `./scripts/run_test_gates.sh groups`. Decision/blocker: no blocking issues; unsafe callback-after-native-leave path is gone, pre-native publish/inbox/key rotation is preserved, failed native leave rolls back local timeline/key artifacts and stays on Group Info, and broad gate residuals match known non-row-owned failures.
- 2026-05-23T22:35:57+02:00 - Recovery QA Reviewer spawned/running. Files inspected by controller before spawn: Executor final handoff, scoped status/stat, `group_info_wired.dart` diff, `group_info_wired_test.dart` diff, and plan progress. Decision/blocker: Executor completed with focused tests green and `groups` residuals classified; current final diff includes earlier same-file GCA-008/GCA-009 dirty work in addition to the recovered GCA-010 hunks, so QA must focus on row-owned sufficiency and scope adherence. Next action: wait for isolated QA Reviewer verdict.
- 2026-05-23T22:32:29+02:00 - Required gate/hygiene complete. `./scripts/run_test_gates.sh groups` was run visibly and again redirected to `/tmp/gca010_groups_gate.log` for classification; both failed with the same 13 broad residuals: `BB-007`, `IJ005`, `BB-012`, `NW-004`, `IR-018`, `PL-004`, `IR-003`, `ST-004`, `GE-017`, `GE-019`, `GE-020`, `GM-029`, and known residual `GM-028`. No focused GCA-010 leave-ordering test failed. `git diff --check` passed. Decision/blocker: implementation is ready for QA with residual broad gate failures classified as pre-existing/non-row-owned.
- 2026-05-23T22:29:59+02:00 - Required focused post-fix commands passed: recovered `GCA-010 native leave failure rolls back local artifacts after pre-leave broadcast`, `BB-010 native leave failure stays on info screen and shows failed leave`, `sole admin leave stays on screen and shows an error`, `multi-admin leave broadcasts self-removal, rotates key, and pops to first route`, `writer leave broadcasts a durable left-the-group event before local cleanup`, and `test/features/groups/application/leave_group_use_case_test.dart`. Next action: run `./scripts/run_test_gates.sh groups` and `git diff --check`.
- 2026-05-23T22:28:54+02:00 - Implemented scoped recovery in allowed files. `leaveGroup` no longer exposes/invokes the first-attempt callback; Group Info now broadcasts/stores/rotates before `leaveGroup`, rolls back the self-left timeline row and retained key window only for `BridgeCommandException(group:leave)`, then refreshes in place. Updated direct widget expectations for recovered pre-native ordering. `dart analyze` on the three touched Dart files passed; `dart format` ran on the three touched Dart files. Next action: run required post-fix focused tests.
- 2026-05-23T22:24:48+02:00 - RED command run: `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart --plain-name "GCA-010 native leave failure rolls back local artifacts after pre-leave broadcast"`. Result: failed as expected; command log reached `group:leave` first and no `group:publish`/`group:inboxStore`/`group:generateNextKey` was recorded before the forced native leave failure. Next action: remove the first-attempt callback path and implement pre-native broadcast plus local rollback.
- 2026-05-23T22:24:14+02:00 - Recovery Executor started. Files inspected: plan recovery sections, `git status --short`, `leave_group_use_case.dart`, `group_info_wired.dart`, `group_info_wired_test.dart`, and rollback/rotation reference seams. Decision/blocker: current owned files contain the unsafe `afterNativeLeaveBeforeLocalCleanup` first-attempt path; retargeted the focused GCA-010 widget test only. Next action: run the required RED command against the retargeted test.
- 2026-05-23T22:21:40+02:00 - Recovery Executor spawn retry. Files inspected or touched: plan progress only. Command finished: first recovered `codex exec` invocation failed before child materialization because approval policy was passed at the wrong CLI level. Decision/blocker: no child work occurred. Next action: retry with corrected top-level approval invocation.
- 2026-05-23T22:21:09+02:00 - Recovery Executor spawned/running. Files inspected or touched: plan progress only. Command running: isolated `codex exec` Executor with `model=gpt-5.5`, `model_reasoning_effort=xhigh`, `approval=never`, `sandbox=danger-full-access`. Decision/blocker: none. Next action: wait for Executor result, inspect landed delta, then spawn QA Reviewer.
- 2026-05-23T22:20:48+02:00 - Recovery execution contract extracted by controller. Files inspected: plan `## Recovery Input`, tightened scope/closure/tests, breakdown read-only row context, gate definitions, gate script, and current `git status --short`. Decision/blocker: execute recovered `GCA-010` only; non-doc write scope remains capped to `leave_group_use_case.dart`, `group_info_wired.dart`, and `group_info_wired_test.dart`; source matrix and breakdown remain read-only for this pass. Next action: spawn isolated Executor with TDD/recovery-ordering instructions.
- 2026-05-23T22:08:31+02:00 - QA Reviewer verdict: blocking issue found. The new Group Info callback runs voluntary self-removal after `group:leave`, but native leave removes Go-side group topic/config/key state and bridge/node tests assert publish after leave fails as `group not joined`; successful multi-member leave is therefore not proven against the real bridge and can fail after native leave before local cleanup/message deletion. Focused Flutter fake-bridge tests and `git diff --check` evidence were inspected; groups gate failures remain classified residual. Session is not safe to close until the successful-leave ordering is corrected or covered by real-bridge-equivalent evidence.
- 2026-05-23T22:04:32+02:00 - Final Executor summary: GCA-010 implementation complete within allowed file cap. Touched non-doc files: `leave_group_use_case.dart`, `group_info_wired.dart`, `group_info_wired_test.dart`. Failing-first failed for the expected broadcast-before-leave reason; focused post-fix tests pass; `groups` gate remains red only on classified residual integration failures; `git diff --check` passes. QA should inspect callback ordering and the current dirty rotation-authority fixture adjustment.
- 2026-05-23T22:05:21+02:00 - QA Reviewer spawned/running. Files inspected or touched: no new files yet. Command running: isolated `codex exec` QA Reviewer with `model=gpt-5.5`, `model_reasoning_effort=xhigh`, `approval=never`, `sandbox=danger-full-access`. Decision/blocker: none. Next action: wait for QA sufficiency review.
- 2026-05-23T22:04:15+02:00 - Required broad gate/hygiene complete. `./scripts/run_test_gates.sh groups` was run twice: first visible run and second redirected to `/tmp/gca010_groups_gate.log` for failure classification. Result: failed with 13 residual integration failures, none in the row-owned GCA-010 leave ordering tests. Failure names: `BB-007 accepted pending invite joins with exact full config and replays accepted epoch`, `IJ005 multi-use direct credential replay is duplicate-safe`, `BB-012 restart recovery drains replay before ack and stays live`, `NW-004 reconnect recovery stays live after ack across multiple groups`, `IR-018 restart recovery keeps recovering state until replay drains and live stays active`, `PL-004 quote ids survive live replay and re-add visibility boundaries`, `IR-003 timestamp replay boundary drains same-ms fake-network messages once`, `ST-004 clock skew fake-network replay keeps relay boundary exact`, `GE-017 seeded random membership operations preserve invariants`, `GE-019 seeded random key rotations preserve access windows`, `GE-020 long soak private group with churn preserves convergence`, `GM-029 config version monotonicity converges across A/B/C shuffled delivery`, and known residual `GM-028 empty PeerId add event does not persist or block valid delivery`. `git diff --check` passed. Next action: final executor summary.
- 2026-05-23T22:00:42+02:00 - Required focused post-fix tests run. Passing: `GCA-010 native leave failure does not broadcast voluntary self-removal before leave succeeds`, `BB-010 native leave failure stays on info screen and shows failed leave`, `sole admin leave stays on screen and shows an error`, `multi-admin leave broadcasts self-removal, rotates key, and pops to first route`, `writer leave broadcasts a durable left-the-group event before local cleanup`, and `test/features/groups/application/leave_group_use_case_test.dart`. During the writer test, the current dirty rotation authority required the leaving writer to be the group creator; adjusted only that owned fixture to keep the successful writer leave coverage aligned with current code. Next action: run `./scripts/run_test_gates.sh groups`.
- 2026-05-23T21:58:56+02:00 - Implemented minimal fix in allowed files. `leaveGroup` now accepts `afterNativeLeaveBeforeLocalCleanup`; Group Info passes voluntary self-removal through that callback and deletes message history after successful leave cleanup; the successful multi-admin test expectation now reflects native leave before key generation. Ran `dart format` on the three touched Dart files. Next action: run the required focused post-fix commands.
- 2026-05-23T21:57:58+02:00 - Failing-first command run: `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart --plain-name "GCA-010 native leave failure does not broadcast voluntary self-removal before leave succeeds"`. Result: failed for expected reason; `bridge.commandLog` already contained `group:publish`, `group:inboxStore`, `group:generateNextKey`, key distribution commands, and then `group:leave` after the forced native failure path. Next action: move voluntary broadcast/rotation behind successful native leave.
- 2026-05-23T21:57:33+02:00 - Added focused failing-first widget regression in `group_info_wired_test.dart`. The test seeds a multi-member admin leave with `group:leave` forced to fail and asserts no publish, inbox store, key generation, P2P key distribution, or local self-left timeline row. Next action: run the exact failing-first command before implementation.
- 2026-05-23T21:56:50+02:00 - Isolated Executor started. Files inspected: session plan, `git status --short`, `group_info_wired.dart`, `leave_group_use_case.dart`, `group_info_wired_test.dart`, and reference-only broadcast/cleanup seams. Decision/blocker: existing dirty work in owned files includes GCA-009 cleanup; keep GCA-010 edits within the three allowed non-doc files and adapt current Group Info leave cleanup without touching `delete_group_and_messages_use_case.dart`. Next action: add the focused failing-first widget regression.
- 2026-05-23T21:54:03+02:00 - Contract extracted. Files inspected: `group-chat-audit-gap-closure-session-GCA-010-plan.md`, `git status --short`, `lib/features/groups/presentation/screens/group_info_wired.dart`, `lib/features/groups/application/leave_group_use_case.dart`, `test/features/groups/presentation/group_info_wired_test.dart`. Decision/blocker: execute `GCA-010` only; non-doc write scope remains capped to `group_info_wired.dart`, `leave_group_use_case.dart`, and `group_info_wired_test.dart`; source matrix and breakdown are read-only for this execution. Next action: spawn isolated Executor with TDD instructions.
- 2026-05-23T21:54:19+02:00 - Executor spawned/running. Files inspected or touched: no new files yet. Command running: isolated `codex exec` Executor with `model=gpt-5.5`, `model_reasoning_effort=xhigh`, `approval=never`, `sandbox=danger-full-access`. Decision/blocker: none. Next action: wait for Executor result, then inspect landed delta and spawn QA.
- 2026-05-23T21:54:55+02:00 - Executor spawn retry. Files inspected or touched: plan progress only. Command finished: first `codex exec` invocation failed before child materialization due to an approval option placed at the wrong CLI level. Decision/blocker: no child work occurred; retry with corrected CLI invocation. Next action: spawn isolated Executor again.

## Recovery Input

2026-05-23T22:10:00+02:00 - Same-session recovery requested by the pipeline controller.

- Blocker class: `implementation-owned ordering blocker`.
- Blocker signature: `GCA-010` first implementation moved voluntary self-removal/key rotation after native `group:leave`; focused fake-bridge tests passed, but QA found the ordering is unsafe against real bridge semantics because publishing/rotating after native leave can fail with `group not joined` or missing group key/config.
- Current files touched by this row: `lib/features/groups/application/leave_group_use_case.dart`, `lib/features/groups/presentation/screens/group_info_wired.dart`, `test/features/groups/presentation/group_info_wired_test.dart`, and this plan file.
- Current passing focused evidence from the first attempt: new `GCA-010` selector failed before implementation and passed after implementation; `BB-010 native leave failure stays on info screen and shows failed leave`, `sole admin leave stays on screen and shows an error`, `multi-admin leave broadcasts self-removal, rotates key, and pops to first route`, `writer leave broadcasts a durable left-the-group event before local cleanup`, and `leave_group_use_case_test.dart` passed under fake bridge; `git diff --check` passed.
- Current residual broad gate evidence: `./scripts/run_test_gates.sh groups` remains red on the known 13 broad residuals (`BB-007`, `IJ005`, `BB-012`, `NW-004`, `IR-018`, `PL-004`, `IR-003`, `ST-004`, `GE-017`, `GE-019`, `GE-020`, `GM-029`, `GM-028`) and is not the blocker.
- Recovery requirement: tighten the plan around a safe ordering that prevents failed native leave from accepting local partial state without moving publish/key rotation after native leave. Prefer preserving the real-bridge-safe publish/inbox/key-rotation-before-native-leave ordering for successful leave, then preventing local acceptance and restoring/removing local artifacts if final `group:leave` fails. Stay within the existing three non-doc owner files unless the fresh planner declares a hard blocker.

## Planning Progress

- 2026-05-23T22:11:52+02:00 - Recovery Evidence Collector started. Files inspected since last update: `implementation-plan-orchestrator` skill instructions, this plan's `## Recovery Input`, `group-chat-audit-gap-closure-session-breakdown.md`, and `group-chat-audit-gap-closure-matrix.md`. Decision/blocker: same-session recovery is required because the previous callback-after-native-leave plan is unsafe for real bridge semantics. Next action: inspect the live three owner files, direct tests, and gate definitions before deciding whether the recovery can stay within the cap.
- 2026-05-23T22:15:08+02:00 - Recovery Evidence Collector completed; Planner started. Files inspected since last update: `git status --short`, `lib/features/groups/application/leave_group_use_case.dart`, `lib/features/groups/presentation/screens/group_info_wired.dart`, `test/features/groups/presentation/group_info_wired_test.dart`, `broadcast_voluntary_leave_use_case.dart`, `rotate_and_distribute_group_key_use_case.dart`, `group_repository.dart`, `group_repository_impl.dart`, `in_memory_group_repository.dart`, `group_message_repository.dart`, `group_membership_timeline_message.dart`, `bridge_group_helpers.dart`, and `Test-Flight-Improv/test-gate-definitions.md`. Decision/blocker: recovery can stay within the existing three non-doc owner files if it reverts callback-after-native-leave ordering and adds local rollback for the timeline row plus retained key window when final native `group:leave` fails. Next action: rewrite the plan around pre-native publish/inbox/key rotation, local rollback, focused TDD, and hard stop rules.
- 2026-05-23T22:17:48+02:00 - Planner completed; Reviewer started. Files inspected since last update: no additional files. Decision/blocker: draft plan now preserves pre-native publish/inbox/key rotation, removes the first-attempt leave callback, and scopes rollback to deterministic local timeline/key restoration in the three owner files. Next action: review for missing regression proof, stale assumptions, overengineering, and stop-rule sufficiency.
- 2026-05-23T22:18:14+02:00 - Reviewer completed; Arbiter started. Files inspected since last update: updated plan sections plus `BridgeCommandException` definition in `bridge_group_helpers.dart`. Decision/blocker: plan is sufficient with wording adjustments: failed leave cannot promise remote undo, only local non-acceptance and local artifact rollback. Next action: classify that remote-compensation gap as an accepted difference or structural blocker.
- 2026-05-23T22:18:55+02:00 - Arbiter completed. Files inspected since last update: updated reviewer findings and final plan text. Decision/blocker: no structural blockers remain; remote undo and unbounded key-history restoration are accepted differences, not scope-expanding requirements for this row. Next action: recovery plan is execution-ready for `GCA-010` only.

## Real Scope

This recovery session is only about voluntary leave from `GroupInfoWired` when the final native `group:leave` step fails after voluntary self-removal prework has already run.

Change the eventual implementation so successful voluntary leave keeps the real-bridge-safe ordering:

- publish the self-removal system event while the user is still joined;
- store the durable replay envelope while group config/key state still exists;
- rotate and distribute the next key while the local bridge can still publish/update group state;
- then call native `group:leave`;
- then delete local group state and local group messages only after native leave succeeds.

If final native `group:leave` fails, the attempted leave must not be locally accepted: keep the user on Group Info, preserve group and membership rows, remove the local self-left timeline row created by the attempt, and restore the retained local key window to the pre-attempt state.

Do not change admin/member permissions, invite behavior, member-removal flows for removing someone else, group dissolve/local-delete flows, notification routing, database schema, group message rendering, or the no-confirmation leave UX polish item.

Hard implementation/test file cap: the executor may touch no more than 3 non-doc implementation/test files for the eventual fix. If the fix cannot satisfy the regression inside that cap, stop and ask before editing a fourth non-doc file.

## Closure Bar

Good enough for `GCA-010` means:

- A focused failing-first regression proves a multi-member voluntary leave with forced final `group:leave` failure still performs self-removal publish, durable inbox store, and key rotation before `group:leave`, then rolls back local acceptance when `group:leave` fails.
- The failed native-leave path leaves no new local "left the group" timeline row, keeps the group and all members locally present, restores the retained key window to the pre-attempt generations, keeps the user on Group Info, and shows the existing failed-leave message.
- Existing successful voluntary leave behavior still broadcasts self-removal, stores the durable replay envelope, rotates/distributes the key before native leave, calls `group:leave`, deletes local group state and messages, and pops to the first route.
- Sole-admin leave remains blocked before any bridge leave, publish, inbox store, or key rotation.
- The fix stays within the existing use-case/widget seams and the 3 non-doc file cap.

## Source Of Truth

Authoritative inputs:

- `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-session-breakdown.md` row `GCA-010` defines this session and its hard scope.
- `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-matrix.md` row `GCA-010` defines the open audit finding.
- Current code in `GroupInfoWired`, `leaveGroup`, and `broadcastVoluntaryLeaveAndRotateKey` wins over stale prose.
- `Test-Flight-Improv/test-gate-definitions.md` and `scripts/run_test_gates.sh` are the source of truth for the named `groups` gate.

If docs and code disagree, preserve current tested behavior unless the new `GCA-010` regression explicitly requires changing it.

## Session Classification

`implementation-ready`

## Exact Problem Statement

Original audit gap: `GroupInfoWired._onLeave()` could save a local `member_removed` timeline message, publish the self-removal, store a durable replay envelope, and rotate/distribute the group key before the final native `group:leave`; if native leave then failed, the UI stayed on the info screen and local group state remained, but local history/key state could already reflect that the user left.

First implementation blocker: moving the voluntary self-removal/key rotation callback after native `group:leave` made focused fake-bridge tests pass but is unsafe for the real bridge. Go bridge/node evidence shows publish/rotation after leave can fail with `group not joined` or missing group key/config because native leave tears down topic/config/key state.

User-visible behavior to improve: when a user attempts voluntary leave and native leave fails, the local app should behave as a failed leave attempt, not a partial completed leave. The user should stay on Group Info, see the existing failed-leave error path, and not retain a local self-left timeline event or newer local leave key from that failed attempt.

Must stay unchanged: successful voluntary leave still notifies remaining members and rotates future group traffic away from the leaving member before native leave; sole admin cannot leave; dissolve and local-delete paths remain separate.

## Files And Repos To Inspect Next

Production target files:

- `lib/features/groups/presentation/screens/group_info_wired.dart`
- `lib/features/groups/application/leave_group_use_case.dart`

Direct test target file:

- `test/features/groups/presentation/group_info_wired_test.dart`

Reference-only files:

- `lib/features/groups/application/broadcast_voluntary_leave_use_case.dart`
- `lib/features/groups/application/rotate_and_distribute_group_key_use_case.dart`
- `lib/features/groups/domain/repositories/group_repository.dart`
- `lib/features/groups/domain/repositories/group_message_repository.dart`
- `lib/features/groups/domain/repositories/group_repository_impl.dart`
- `test/shared/fakes/in_memory_group_repository.dart`
- `test/features/groups/application/leave_group_use_case_test.dart`
- `test/features/groups/application/member_removal_integration_test.dart`
- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`

Stop and ask before touching any additional non-doc implementation/test file.

## Existing Tests Covering This Area

Existing direct widget coverage in `group_info_wired_test.dart`:

- `BB-010 native leave failure stays on info screen and shows failed leave` covers a forced native leave failure, but it does not seed a multi-member state that triggers voluntary self-removal broadcast/rotation and does not assert absence of publish/inbox/timeline/rotation.
- First-attempt `GCA-010 native leave failure does not broadcast voluntary self-removal before leave succeeds` is now stale: it proves no publish/rotation occurs before a forced native leave failure under fake bridge, but that encodes the unsafe callback-after-native-leave ordering QA rejected.
- `sole admin leave stays on screen and shows an error` proves the sole-admin block avoids `group:leave`.
- `multi-admin leave broadcasts self-removal, rotates key, and pops to first route` proves successful admin voluntary leave broadcasts, inbox-stores, rotates, leaves, deletes local group state, and currently asserts the unsafe first-attempt ordering where `group:leave` occurs before key generation.
- `writer leave broadcasts a durable left-the-group event before local cleanup` proves successful writer voluntary leave broadcasts and rotates.

Existing application coverage:

- `leave_group_use_case_test.dart` covers successful local cleanup, native leave command dispatch, native leave failure preserving local state/rejoin eligibility, sole-admin block, and multi-admin leave allowance.
- `member_removal_integration_test.dart` covers direct `broadcastVoluntaryLeaveAndRotateKey()` behavior, including signed replay envelope storage, last-admin skip, and voluntary leave rotation excluding the leaver for remaining-member future sends.

Missing coverage:

- No focused test proves the real-bridge-safe successful ordering of publish/inbox/key rotation before native leave while also proving that a failed final native leave rolls back local acceptance artifacts.
- No focused test proves the rollback restores both retained local key generations after a pre-native leave rotation generated a new epoch.

## Regression/Tests To Add First

Replace or retarget the stale first-attempt `GCA-010` widget regression in `test/features/groups/presentation/group_info_wired_test.dart`, near the existing leave tests.

Suggested name:

```text
GCA-010 native leave failure rolls back local artifacts after pre-leave broadcast
```

Test intent:

- Seed `group-1` as a multi-member group where the leaving identity is a non-sole admin or writer with `rotateKeys` permission and is allowed by the current rotation-authority rules.
- Save retained local keys at generation `1` and generation `2`.
- Include at least one remaining member so voluntary self-removal would currently publish, inbox-store, and rotate.
- Provide an `InMemoryGroupMessageRepository`.
- Use `PassthroughCryptoBridge` or equivalent fake bridge responses for successful `group:publish`, `group:inboxStore`, and `group:generateNextKey` returning key epoch `3`, but force final `group:leave` to return `ok: false`.
- Open `GroupInfoWired`, tap the existing leave button, and assert:
  - `group:publish`, `group:inboxStore`, and `group:generateNextKey` all happened before `group:leave`;
  - one `group:leave` attempt occurred;
  - key-distribution P2P sends happened before the failed leave path completed;
  - `msgRepo.getMessageCount('group-1') == 0` when no baseline messages were seeded;
  - `groupRepo.getGroup('group-1')` is still non-null;
  - all pre-attempt members are still present;
  - `groupRepo.getLatestKey('group-1')` is restored to generation `2`;
  - `groupRepo.getKeyByGeneration('group-1', 1)` is still non-null;
  - `groupRepo.getKeyByGeneration('group-1', 3)` is null;
  - `GroupInfoScreen` is still shown and the existing failed-leave message is visible.

Run this before implementation and confirm it fails against the current first-attempt callback-after-native-leave ordering because publish/inbox/key rotation do not happen before the forced `group:leave` failure.

## Step-By-Step Implementation Plan

1. Confirm the worktree before editing:

```bash
git status --short
```

If any of the three target files contain user edits that conflict with this plan, inspect and work with them. Do not revert or overwrite unrelated edits.

2. Replace or retarget the stale `GCA-010` widget test in `group_info_wired_test.dart` only.

3. Run the new test by exact name and confirm it fails for the expected reason:

```bash
flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart --plain-name "GCA-010 native leave failure rolls back local artifacts after pre-leave broadcast"
```

Expected pre-fix failure against the first-attempt code: current code attempts `group:leave` first and therefore records no `group:publish`, `group:inboxStore`, `group:generateNextKey`, or key-distribution P2P sends before the forced native leave failure.

4. In `leave_group_use_case.dart`, remove the first-attempt optional callback parameter `afterNativeLeaveBeforeLocalCleanup` and its invocation.

Execution order inside `leaveGroup` must return to the narrow use-case contract:

- existing flow event begin;
- existing group load and sole-admin block;
- existing `callGroupLeave(bridge, groupId)`;
- existing `removeAllMembers`, `removeAllKeys`, `deleteGroup`;
- existing success event.

Do not change `leaveGroup` behavior for existing callers beyond removing the unused first-attempt callback hook. Do not add a new use case, new repository API, database migration, global transaction abstraction, or retry system.

5. In `group_info_wired.dart`, restore pre-native voluntary leave prework and add local rollback around the final native leave:

- before broadcasting, snapshot the local rollback inputs: loaded identity, operation start timestamp, current latest key, current previous retained key if `latest.keyGeneration > 1`, and current pending rotation draft if `groupRepo is GroupKeyRotationDraftRepository`;
- call `_broadcastSelfRemovalIfNeeded()` before `leaveGroup`;
- call `leaveGroup(...)` without a callback;
- delete group messages and navigate only after `leaveGroup(...)` succeeds;
- if the caught error is a `BridgeCommandException` for `group:leave` after voluntary prework started, run a local rollback helper before showing the existing failed-leave snackbar.

Rollback helper requirements inside `group_info_wired.dart`:

- delete only the self-left `member_removed` timeline row created by this attempt by using `GroupMessageRepository.getLatestSystemEventTimestampForTarget(...)`, the operation start timestamp guard, and `buildMemberRemovedTimelineMessage(...)` to reconstruct the deterministic id;
- restore the retained key window if a newer generated key is now latest by calling `removeAllKeys(groupId)`, then re-saving the captured previous retained key if present, then re-saving the captured latest key, then restoring the captured pending draft if present;
- leave group rows and member rows intact;
- call `_loadGroupInfo()` or otherwise refresh visible local state after rollback, without navigating away.

6. Update only directly affected expectations in `group_info_wired_test.dart`.

The successful multi-admin leave test should still assert publish/inbox/key rotation/leave/local delete/popup, and it must now assert `group:publish`, `group:inboxStore`, and `group:generateNextKey` occur before `group:leave`. Add the same pre-native order assertion to the writer leave test if the existing assertions can do so without new fixtures.

7. Stop and ask before proceeding if any of the following are true:

- satisfying the failing test requires editing a fourth non-doc implementation/test file;
- deleting the local self-left timeline row cannot be done deterministically without editing `broadcast_voluntary_leave_use_case.dart` to return the timeline id;
- restoring the retained key window cannot be done with the current `GroupRepository` methods and current two-key retention evidence;
- final native leave failure is indistinguishable from local cleanup failure without broadening `leaveGroup`'s public result/error contract;
- the implementation would require schema changes, repository-wide API changes, or a new voluntary-leave orchestration abstraction.

## Risks And Edge Cases

- Remote side effects are already possible before final native leave: this recovery intentionally restores local acceptance artifacts only. It does not unpublish the self-removal event, delete inbox replay envelopes, or retract P2P key packets.
- Cleanup failure after native leave succeeds is not rollback-safe in this session because the bridge has already left the topic. Do not treat that as `GCA-010`; stop if tests expose it as row-owned.
- Sole-admin ordering: the last-admin path must still avoid publish, inbox store, key rotation, and native leave.
- Successful leave cleanup: local group/member/key cleanup must remain exactly where `leaveGroup` owns it.
- Durable replay behavior: remaining members still need the self-removal replay and rotated key on successful voluntary leave.
- Retained key restoration: both current repo implementations keep at most the latest two committed keys; rollback must restore that observed retained window and must not claim to restore an unbounded key history.
- Duplicate failed leave attempts: timeline deletion must be guarded by this attempt's start timestamp so an older legitimate membership event is not deleted.
- Existing dirty worktree: several group-related files are already modified; executor must preserve unrelated user changes.

## Exact Tests And Gates To Run

Failing-first command:

```bash
flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart --plain-name "GCA-010 native leave failure rolls back local artifacts after pre-leave broadcast"
```

Focused post-fix commands:

```bash
flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart --plain-name "GCA-010 native leave failure rolls back local artifacts after pre-leave broadcast"
flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart --plain-name "BB-010 native leave failure stays on info screen and shows failed leave"
flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart --plain-name "sole admin leave stays on screen and shows an error"
flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart --plain-name "multi-admin leave broadcasts self-removal, rotates key, and pops to first route"
flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart --plain-name "writer leave broadcasts a durable left-the-group event before local cleanup"
flutter test --no-pub test/features/groups/application/leave_group_use_case_test.dart
```

Named gate and hygiene:

```bash
./scripts/run_test_gates.sh groups
git diff --check
```

Run `dart format` on any touched Dart files before the final test pass.

## Manual Verification Step

After automated focused tests pass, run one manual/interactive verification using a development build or widget harness that can force `group:leave` to fail for a multi-member group:

- Open Group Info for a group where the current user is not the sole admin and at least one other member remains.
- Trigger Leave Group while native leave is forced to fail.
- Verify the screen stays on Group Info, the failed-leave snackbar appears, no local "left the group" timeline row appears when returning to the conversation, no successful leave navigation occurs, and the latest local key generation remains the same as before the attempt.

Do not perform manual verification by changing product code outside the 3-file cap.

## Known-Failure Interpretation

The source matrix records previous unrelated `./scripts/run_test_gates.sh groups` failures, including `group_membership_smoke_test.dart` `GM-028` and other residual group integration failures from earlier rows. Treat the new focused `GCA-010` regression and the listed direct leave tests as row-owned.

If the named `groups` gate fails after the focused tests pass, classify failures by exact test name and error. Only failures in the voluntary leave ordering path count as `GCA-010` regressions. Preserve logs for unrelated existing failures instead of weakening the new focused assertions.

## Done Criteria

- The new `GCA-010` test fails before implementation and passes after implementation.
- Forced final native leave failure from Group Info shows pre-native self-removal publish, inbox-store replay, and voluntary key rotation before `group:leave`, but rolls back local timeline/key artifacts and does not navigate or delete local group/member rows.
- Successful multi-member voluntary leave still broadcasts, inbox-stores, rotates/distributes key material before native leave, leaves natively, clears local group state/messages, and pops to the first route.
- Sole-admin leave still blocks before bridge commands.
- No more than 3 non-doc implementation/test files are changed.
- `git diff --check` passes.
- Focused direct tests pass, and the `groups` gate is either green or has documented unrelated residual failures.

## Scope Guard

Non-goals:

- No product-code edits during planning.
- No matrix or breakdown ledger edits until an executor actually implements and verifies the fix.
- No refactor of group membership, key rotation, repositories, database helpers, bridge helper APIs, P2P service, or navigation architecture.
- No new voluntary-leave service/use-case abstraction.
- No schema migration.
- No retry queue or distributed compensation design.
- No edits to `broadcast_voluntary_leave_use_case.dart`, `rotate_and_distribute_group_key_use_case.dart`, repository interfaces/implementations, bridge helpers, or source matrix/breakdown in this recovery planning/implementation pass.
- No changes to member-removal of other users, group dissolve, local delete, invite acceptance, conversation send, unread, notification, or startup recovery behavior.

Overengineering for this session includes touching more than the three target files, adding a transaction framework, making key rotation generally pluggable, adding a remote undo protocol, changing durable inbox semantics, or trying to solve every broadcast-failure mode outside the final native-leave-failure regression.

## Accepted Differences / Intentionally Out Of Scope

- `GCA-008` member-removal partial mutation is separate and must not be bundled here.
- `GCA-009` message-history cleanup after leave is separate and must not be bundled here.
- The no-confirmation leave UX polish item is explicitly out of scope in the matrix.
- This plan does not attempt remote compensation for already completed publishes, inbox replay envelopes, or key deliveries. That would need a separate distributed recovery design outside the cap.
- Direct calls to `broadcastVoluntaryLeaveAndRotateKey()` in application tests remain valid reference behavior; this session changes how Group Info accepts or rolls back the local result, not the broadcast helper's standalone contract.
- The retained key rollback is intentionally bounded to the current latest-plus-previous key retention behavior observed in `GroupRepositoryImpl` and `InMemoryGroupRepository`.

## Dependency Impact

Later closure work for `GCA-010` should update the matrix row and this breakdown ledger only after implementation and verification. If local rollback cannot be implemented deterministically inside the three owner files, later work should mark `GCA-010` blocked under the cap and revisit it as a broader orchestration/repository design rather than forcing the unsafe callback-after-native-leave approach.

`GCA-009` message cleanup depends on this ordering: Group Info may delete local messages only after native leave succeeds, and any future cleanup refactor must preserve the `GCA-010` guarantee that failed native leave does not locally accept self-removal or key rotation artifacts.

## Reviewer Pass

Reviewer verdict: sufficient with recovery adjustments.

Answers to required review questions:

- Sufficiency: sufficient after changing the contract from "do not publish before leave" to "publish/inbox/rotate before native leave, then roll back local acceptance if final native leave fails."
- Missing files/tests/gates: no additional target files are required if timeline deletion and retained-key restoration can be implemented through existing `GroupMessageRepository` and `GroupRepository` methods. The focused widget regression, existing leave-focused selectors, `leave_group_use_case_test.dart`, `groups`, and `git diff --check` are enough for this row.
- Stale or incorrect assumptions: the first-attempt callback-after-native-leave assumption is stale and rejected by real bridge evidence; the updated plan explicitly relies on pre-native bridge operations.
- Overengineering: adding remote undo, repository APIs, schema changes, transaction frameworks, or edits to `broadcast_voluntary_leave_use_case.dart` would exceed this row.
- Decomposition: small enough for implementation; one retargeted regression, two production owner files, one test file, with hard stops before any fourth non-doc file.
- Minimum needed: keep the three-file cap, prove pre-native operation order, prove local rollback of timeline plus retained key window, and preserve successful leave/message cleanup behavior.

## Arbiter Decision

Structural blockers remaining: none.

Incremental details intentionally deferred:

- A dedicated `leaveGroup` callback-removal unit test is not required because the row-owned behavior is covered through the Group Info voluntary-leave path and `leave_group_use_case_test.dart`.
- Full `group_info_wired_test.dart` may be run if time allows, but the required row-owned commands are the exact focused tests listed above.
- Manual verification remains useful but must not require edits outside the three-file cap.

Accepted differences intentionally left unchanged:

- Direct `broadcastVoluntaryLeaveAndRotateKey()` tests continue to prove the broadcast helper's standalone behavior; this session changes Group Info's orchestration and local acceptance/rollback only.
- Remote compensation for already published self-removal events, stored inbox envelopes, or distributed P2P keys is intentionally out of scope and would need a separate design.
- Retained key rollback is bounded to current latest-plus-previous key retention evidence. If executor evidence shows more key history must be restored, the session must stop as blocked under the cap.
- Cleanup failure after native `group:leave` succeeds is not treated as this row's rollback target.

Why this plan is safe to implement now:

- It has a failing-first regression that fails against the current unsafe first-attempt ordering and proves the recovered pre-native order plus local rollback.
- It names only three non-doc target files and has explicit stop rules before any fourth non-doc file.
- It preserves real-bridge-safe publish/inbox/key rotation before native leave for successful voluntary leave.
- It preserves existing leave cleanup ownership in `leaveGroup` and existing standalone broadcast behavior in `broadcastVoluntaryLeaveAndRotateKey`.
- It includes direct focused tests, the named `groups` gate, known-failure interpretation, and a manual verification step.
