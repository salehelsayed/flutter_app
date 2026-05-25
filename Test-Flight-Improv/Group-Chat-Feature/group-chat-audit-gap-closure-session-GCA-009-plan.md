# GCA-009 Leave Group Local Message Cleanup Contract Plan

Status: execution-ready

## Planning Progress

- 2026-05-23T18:16:31Z - Arbiter completed. Files inspected since last update: reviewer findings and final plan. Decision/blocker: no structural blockers remain; incremental details are documented; accepted differences are explicit; plan is execution-ready. Next action: hand off for implementation under the hard 3-file non-doc cap.
- 2026-05-23T18:16:13Z - Arbiter started. Files inspected since last update: reviewer findings and plan draft. Decision/blocker: classify reviewer outcome into structural blockers, incremental details, and accepted differences. Next action: finalize arbiter decision and execution-ready status if no structural blockers remain.
- 2026-05-23T18:15:43Z - Reviewer completed. Files inspected since last update: `group_conversation_wired.dart`, plan draft. Decision/blocker: sufficient with one incremental evidence adjustment applied for production `msgRepo` construction; no structural blockers found. Next action: run arbiter classification and final execution-readiness decision.
- 2026-05-23T18:15:00Z - Reviewer started. Files inspected since last update: plan draft only. Decision/blocker: review will validate whether the plan sufficiently handles existing voluntary-leave tests, optional `msgRepo` behavior, known gate failures, and the file cap. Next action: write reviewer findings and classify sufficiency.
- 2026-05-23T18:14:46Z - Planner completed. Files inspected since last update: none. Decision/blocker: draft plan written with a 2-file target, failing-first UI-path regression, exact direct tests, named `groups` gate, manual verification, and stop rule for more than 3 non-doc files. Next action: run reviewer sufficiency pass.

## Execution Progress

- 2026-05-23T19:48:54Z - QA Reviewer completed. Files inspected since last update: `group_info_wired.dart`, `group_info_wired_test.dart`, `delete_group_and_messages_use_case.dart`, `rotate_and_distribute_group_key_use_case.dart`, scoped diffs, and this plan file. Commands run: focused `GCA-009` widget proof passed; `delete_group_and_messages_use_case_test.dart` passed; `leave_group_use_case_test.dart` passed; `dart format --set-exit-if-changed ...` passed; `git diff --check` passed. Decision/blocker: no row-owned GCA-009 blocker found; full widget and groups gate residuals remain triaged as unrelated/pre-existing dirty-worktree failures. Next action: accept handoff with explicit follow-up for residual red gates outside GCA-009.
- 2026-05-23T19:49:34Z - Controller final verdict written. Files inspected since last update: QA Reviewer final result and session plan. Decision/blocker: final verdict is `accepted_with_explicit_follow_up`; no GCA-009 blocking issues remain; residual failed full-widget and groups-gate items are explicitly non-blocking follow-ups owned outside this row. Next action: report final execution outcome to user.
- 2026-05-23T19:44:43Z - Executor final verdict. Files inspected since last update: final diffs and scoped status for `group_info_wired.dart`, `group_info_wired_test.dart`, and this plan file. Decision/blocker: GCA-009 implementation is complete and within the allowed file scope; focused RED/GREEN proof and application cleanup backstops pass; full widget file and groups gate retain unrelated/pre-existing dirty-worktree failures documented above. Next action: hand off to QA with residual failures and manual verification step.
- 2026-05-23T19:45:34Z - Controller spawning QA Reviewer. Files inspected since last update: Executor final result and execution progress. Decision/blocker: Executor produced scoped code/test/doc delta and exact command evidence; QA must independently check sufficiency, required test/gate handling, residual failure classification, and scope adherence without editing files. Next action: wait for isolated QA Reviewer result.
- 2026-05-23T19:44:08Z - Executor required gates complete. Files touched since last update: none. Commands finished: `flutter test --no-pub test/features/groups/application/delete_group_and_messages_use_case_test.dart` passed; `flutter test --no-pub test/features/groups/application/leave_group_use_case_test.dart` passed; `dart format --set-exit-if-changed lib/features/groups/presentation/screens/group_info_wired.dart test/features/groups/presentation/group_info_wired_test.dart` passed; `git diff --check` passed; `FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups` failed with 13 known broader group-gate failures (`BB-007`, `IJ005`, `BB-012`, `NW-004`, `IR-018`, `PL-004`, `IR-003`, `ST-004`, `GE-017`, `GE-019`, `GE-020`, `GM-029`, `GM-028`). Decision/blocker: GCA-009 direct proof and application backstops pass; residual red is classified unrelated/pre-existing broader gate coverage. Next action: inspect final diff and write Executor verdict.
- 2026-05-23T19:41:19Z - Executor full widget file check triaged. Files inspected since last update: failing `group_info_wired_test.dart` sections for writer leave and remove-member assertions. Command finished: `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart` failed. Failure classification: `GCA-009` focused leave test stayed green; full-file failures are `writer leave broadcasts a durable left-the-group event before local cleanup` (pre-existing/dirty-worktree fixture conflict: rotation now denies because the leaving writer is not `group.createdBy`) plus two remove-member failures (`remove member calls bridge in correct order...` and `EK004 remove member broadcast stores signed member_removed replay envelope`) from pre-existing GCA-008 dirty remove-member changes. Decision/blocker: do not fix unrelated GCA-008/rotation behavior inside this session. Next action: continue required application backstop tests and hygiene commands.
- 2026-05-23T19:39:38Z - Executor GREEN focused check complete. Files touched since last update: `group_info_wired_test.dart` by `dart format`. Commands finished: `dart format lib/features/groups/presentation/screens/group_info_wired.dart test/features/groups/presentation/group_info_wired_test.dart` passed; `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart --plain-name "GCA-009"` passed. Decision/blocker: focused row proof is green after production cleanup wiring. Next action: run the full widget file and application backstop tests.
- 2026-05-23T19:39:16Z - Executor implemented cleanup wiring. Files touched since last update: `group_info_wired.dart`, `group_info_wired_test.dart`. Decision/blocker: `_onLeave()` still broadcasts first, then calls `deleteGroupAndMessages()` when `msgRepo` is present and keeps the direct `leaveGroup()` fallback when absent; voluntary-leave tests now keep broadcast/inbox/key-rotation/direct-send proof and expect local group history to be purged after success. Next action: format touched Dart files and run the required GREEN/direct checks.
- 2026-05-23T19:38:25Z - Executor RED complete. Files touched since last update: none. Command finished: `flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart --plain-name "GCA-009"` failed as expected because `msg-left-group` remained after successful leave (`Expected: null`, actual `GroupMessage`). Decision/blocker: failure is row-owned and proves the local-message cleanup gap before production changes. Next action: update `group_info_wired.dart` to call `deleteGroupAndMessages()` when `msgRepo` is available.
- 2026-05-23T19:37:57Z - Executor added RED proof. Files touched since last update: `group_info_wired_test.dart`. Decision/blocker: retargeted the successful leave widget test as `GCA-009`, seeded one message for `group-1` and one for `group-other`, and asserted one active `group:leave`, target message deletion, other-group preservation, group deletion, and route pop. Next action: run focused RED command before production changes.
- 2026-05-23T19:37:05Z - Executor started. Files inspected since last update: plan file, `git status --short`, overlapping diffs for `group_info_wired.dart` and `group_info_wired_test.dart`, relevant Group Info leave code and widget tests, `delete_group_and_messages_use_case.dart`, `leave_group_use_case.dart`, and `in_memory_group_message_repository.dart`. Decision/blocker: worktree is dirty with unrelated edits including prior GCA-008 changes; row-owned production path still calls `leaveGroup()` directly; continue with failing-first GCA-009 widget proof in the allowed test file. Next action: add the RED test/expectation before production changes.
- 2026-05-23T19:35:11Z - Controller extracted contract. Files inspected since last update: `group-chat-audit-gap-closure-session-GCA-009-plan.md`, `test-gate-definitions.md`, `group_info_wired.dart`, `group_info_wired_test.dart`, `delete_group_and_messages_use_case.dart`, `leave_group_use_case.dart`, `in_memory_group_message_repository.dart`. Decision/blocker: execution contract is concrete; scope is session `GCA-009` only; planned non-doc edit target remains `group_info_wired.dart` and `group_info_wired_test.dart`; matrix and breakdown are closure-only and must not be edited. Next action: spawn isolated Executor agent with `model: gpt-5.5` and `reasoning_effort: xhigh`.
- 2026-05-23T19:35:45Z - Controller spawning Executor. Files inspected since last update: none. Decision/blocker: using `codex exec -m gpt-5.5 -c model_reasoning_effort="xhigh"` for isolated execution; Executor must add the RED `GCA-009` proof first, apply the minimal Group Info leave cleanup wiring, and run the plan's direct tests/gates. Next action: wait for Executor result, then spawn QA Reviewer.
- 2026-05-23T19:36:14Z - Controller corrected Executor spawn command. Files inspected since last update: none. Decision/blocker: first child invocation failed before materializing because `-a` was passed to the `exec` subcommand; no code/test files were touched by that child. Next action: relaunch Executor with top-level approval flag placement.

## real scope

Fix only session `GCA-009`: the Group Info active leave path must remove local group message history after a successful leave, matching the existing local-data cleanup contract.

In scope:

- Add or update focused widget coverage in `test/features/groups/presentation/group_info_wired_test.dart` so leaving an active group from Group Info deletes messages for that group and does not delete messages for another group.
- Update existing Group Info voluntary-leave tests in the same file if they currently assert local retention of the leave timeline row after successful leave. The durable remote/broadcast proof should remain through `group:publish`, `group:inboxStore`, key rotation, direct-send logs, and route pop expectations.
- Change only `lib/features/groups/presentation/screens/group_info_wired.dart` unless evidence proves this cannot satisfy the row.

Out of scope:

- Do not change product behavior for `GCA-010` broadcast-before-leave ordering.
- Do not change bridge commands, key rotation, membership authorization, dissolve behavior, group message repository APIs, database migrations, or retry/replay semantics.
- Do not update the matrix or breakdown in this planning-only session.

Hard file cap: the eventual executor must touch no more than 3 non-doc implementation/test files. The planned target is 2 non-doc files. If a fourth non-doc file appears necessary, stop and ask before editing it.

## closure bar

`GCA-009` is good enough when:

- a failing-first focused test proves Group Info active leave purges all local messages for the leaving group after the leave succeeds;
- unrelated group messages in the same repository survive the leave;
- existing leave safeguards still hold: native leave failure and sole-admin blocks preserve group state and message history, and dissolved local delete still does not publish a second `group:leave`;
- voluntary leave still broadcasts the remote/durable leave event before local cleanup where the current UI flow already does so;
- direct tests and diff hygiene pass, and any broader `groups` gate failure is clearly identified as unrelated/pre-existing.

## source of truth

Authoritative sources for this session:

- `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-session-breakdown.md`, session `GCA-009`, defines the exact scope and likely files.
- `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-matrix.md`, row `GCA-009`, defines the open gap.
- Current code wins over stale prose if behavior differs.
- `scripts/run_test_gates.sh` is the execution source of truth for named gates if it disagrees with `Test-Flight-Improv/test-gate-definitions.md`.

Repo evidence:

- `lib/features/groups/presentation/screens/group_info_wired.dart:326` calls `_broadcastSelfRemovalIfNeeded()`, then calls `leaveGroup(...)` directly at `:329-333`.
- `lib/features/groups/presentation/screens/group_conversation_wired.dart:2918-2922` constructs production `GroupInfoWired` with `msgRepo: widget.msgRepo`, so the normal conversation-to-info path has the repository needed to route through `deleteGroupAndMessages()`.
- `lib/features/groups/application/leave_group_use_case.dart:11-55` documents local cleanup and removes members, keys, and the group, but has no `GroupMessageRepository` and does not delete group messages.
- `lib/features/groups/application/delete_group_and_messages_use_case.dart:7-36` already wraps `leaveGroup(...)` and then calls `groupMessageRepo.deleteMessagesForGroup(groupId)`.
- `test/features/groups/application/delete_group_and_messages_use_case_test.dart:28-87`, `:117-166`, `:168-246`, and `:248-311` already cover successful message purge, blocked-leave preservation, failed-native-leave preservation, and other-group message isolation.
- `test/features/groups/presentation/group_info_wired_test.dart:2720-2879` covers Group Info active leave success, sole-admin blocked leave, and native leave failure, but the success path does not currently assert message cleanup.
- `test/features/groups/presentation/group_info_wired_test.dart:3120-3311` covers voluntary-leave broadcast and currently inspects a local timeline row after leave; under this session, the remote broadcast proof should remain while local history is expected to be purged.

## session classification

`implementation-ready`

The row has a direct failing seam, a reusable existing use case for message cleanup, focused tests/fakes already available, and no prerequisite architecture work.

## exact problem statement

When a user leaves an active group from Group Info, the UI prepares/broadcasts voluntary leave and then calls `leaveGroup()` directly. `leaveGroup()` removes membership, keys, and the group row after native `group:leave`, but it cannot delete message rows because it has no message repository dependency. As a result, local group messages can remain after the user-facing leave flow has navigated away and implied local cleanup.

The user-visible behavior to improve: after successful Group Info leave, the left group and its local message history are gone from this device. The behavior that must stay unchanged: failed native leave and blocked sole-admin leave must not delete group state or messages, and voluntary leave must still send the existing remote/durable leave event before local cleanup.

## files and repos to inspect next

Production:

- `lib/features/groups/presentation/screens/group_info_wired.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart` for production construction evidence only; do not edit unless the executor proves `msgRepo` is not actually supplied on the shipped route.
- `lib/features/groups/application/delete_group_and_messages_use_case.dart`
- `lib/features/groups/application/leave_group_use_case.dart`

Tests/fakes:

- `test/features/groups/presentation/group_info_wired_test.dart`
- `test/features/groups/application/delete_group_and_messages_use_case_test.dart`
- `test/features/groups/application/leave_group_use_case_test.dart`
- `test/shared/fakes/in_memory_group_message_repository.dart`

Gate docs/scripts:

- `Test-Flight-Improv/test-gate-definitions.md`
- `scripts/run_test_gates.sh`

## existing tests covering this area

- `leave_group_use_case_test.dart` covers successful group/member/key cleanup, bridge `group:leave`, native leave failure preserving state, last-admin block, and admin-with-other-admin leave.
- `delete_group_and_messages_use_case_test.dart` covers active leave plus message purge, native leave failure preserving messages, blocked sole-admin leave preserving messages, other-group isolation, and dissolved local cleanup without an extra `group:leave`.
- `group_info_wired_test.dart` covers the UI leave route pop, sole-admin error, native leave failure, dissolved local delete, and voluntary leave broadcast/rotation paths.

Missing coverage:

- No Group Info active-leave test proves that the UI path purges local group messages when `msgRepo` is available.
- Existing voluntary-leave widget tests prove local timeline persistence before cleanup, which conflicts with this row's local-history purge contract after successful leave.

## regression/tests to add first

Failing-first intent:

1. In `test/features/groups/presentation/group_info_wired_test.dart`, add a focused `GCA-009` widget test or retarget the existing successful leave test to provide an `InMemoryGroupMessageRepository` with:
   - one message for `group-1`;
   - one message for a different group id.
2. Trigger `tapLeaveGroupButton(...)` on an active, non-dissolved group.
3. Assert after the route pops:
   - `bridge.commandLog` contains exactly one active `group:leave`;
   - `await msgRepo.getMessage(<group-1-message-id>)` is `null`;
   - `await msgRepo.getMessage(<other-group-message-id>)` is not `null`;
   - `await groupRepo.getGroup('group-1')` is `null`.
4. Update the existing voluntary-leave broadcast tests in the same file so they keep asserting publish/inbox/key-rotation/direct-send evidence but no longer require the leaver's local message repository to retain the timeline row after successful leave.

Expected RED before implementation: the new/updated `GCA-009` assertion fails because `GroupInfoWired._onLeave()` calls `leaveGroup()` directly and the target message remains in `InMemoryGroupMessageRepository`.

## step-by-step implementation plan

1. Start from the current dirty worktree. Do not revert or overwrite unrelated edits. Before editing, re-run `git status --short` and inspect any overlapping changes in the two planned files.
2. Add the failing-first Group Info widget regression in `test/features/groups/presentation/group_info_wired_test.dart`; keep all test fixture changes local to that file.
3. Run the focused RED command:

   ```bash
   flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart --plain-name "GCA-009"
   ```

   If the selector is not available because the executor retargeted an existing test name, run the nearest exact `--plain-name` for that test and record the command.
4. Implement the minimal wiring in `lib/features/groups/presentation/screens/group_info_wired.dart`:
   - keep `_broadcastSelfRemovalIfNeeded()` before local cleanup;
   - when `widget.msgRepo != null`, call `deleteGroupAndMessages(bridge: widget.bridge, groupRepo: widget.groupRepo, groupMessageRepo: widget.msgRepo!, groupId: _group.id)` instead of direct `leaveGroup(...)`;
   - when `widget.msgRepo == null`, keep the current `leaveGroup(...)` fallback so existing callers/tests without a message repository keep working;
   - keep current error handling, snackbar copy, and route pop behavior.
5. Update only the affected expectations in `group_info_wired_test.dart` that conflict with message purge after successful leave. Preserve remote broadcast and ordering assertions.
6. Run formatter on touched Dart files only:

   ```bash
   dart format lib/features/groups/presentation/screens/group_info_wired.dart test/features/groups/presentation/group_info_wired_test.dart
   ```

7. Run the exact direct tests and gates below.
8. Stop and ask if the fix appears to require changing repository interfaces, migrations, bridge code, `leaveGroup()` semantics for every caller, or more than 3 non-doc implementation/test files.

## risks and edge cases

- Failed native `group:leave` must not delete local messages. The existing `deleteGroupAndMessages()` sequencing already deletes messages only after `leaveGroup(...)` succeeds.
- Sole-admin blocked leave must preserve the group, members, keys, messages, and route.
- Voluntary leave broadcast happens before local cleanup; changing to the delete-and-messages use case must not reorder broadcast, key rotation, or direct/inbox sends.
- If `widget.msgRepo` is absent, the UI cannot purge messages through this path. Keep the existing fallback and document that this session closes the normal Group Info path where the repository is supplied.
- Other group histories must not be removed by the target group's cleanup.
- Do not fold `GCA-010` partial broadcast-before-leave failure handling into this row.

## exact tests and gates to run

Required failing-first/direct verification:

```bash
flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart --plain-name "GCA-009"
flutter test --no-pub test/features/groups/presentation/group_info_wired_test.dart
flutter test --no-pub test/features/groups/application/delete_group_and_messages_use_case_test.dart
flutter test --no-pub test/features/groups/application/leave_group_use_case_test.dart
dart format --set-exit-if-changed lib/features/groups/presentation/screens/group_info_wired.dart test/features/groups/presentation/group_info_wired_test.dart
git diff --check
```

Named gate after direct tests are green:

```bash
FLUTTER_DEVICE_ID=macos ./scripts/run_test_gates.sh groups
```

If no macOS/device target is available, run the host-side direct tests above and record the skipped named gate with the device limitation. Do not edit `Test-Flight-Improv/test-gate-definitions.md` or `scripts/run_test_gates.sh`; this session adds no new gate file.

Manual verification step:

- In a local app build with an active group that has visible messages, leave the group from Group Info. Verify the app returns to the first route/group list and the left group's old conversation/history is not reachable or rendered after restart.

## known-failure interpretation

- Any failure in `group_info_wired_test.dart`, `delete_group_and_messages_use_case_test.dart`, or `leave_group_use_case_test.dart` is row-owned unless the executor can prove it existed before these changes with the same test name and error.
- If `./scripts/run_test_gates.sh groups` fails outside the touched direct suites, compare against the current matrix notes. Earlier rows document unrelated group-gate residuals including `GM-028`, `GM-029`, `BB-007`, `IJ005`, startup/rejoin replay cases, and `GE-017`/`GE-019`/`GE-020`. Record exact failing test names and do not classify them as new `GCA-009` regressions without matching touched behavior.
- Do not mark the row closed if the focused `GCA-009` proof or the two direct use-case backstops are red.

## done criteria

- `group_info_wired_test.dart` contains a failing-first `GCA-009` proof or equivalent retargeted active-leave proof for local message purge through Group Info.
- Group Info successful active leave uses `deleteGroupAndMessages()` when `msgRepo` is available and keeps `leaveGroup()` fallback when it is not.
- Other-group message isolation is asserted in the UI-path regression.
- Failed leave and blocked leave preservation behavior remains covered and green.
- Required direct tests, formatter check, and `git diff --check` pass.
- The `groups` gate is run and recorded, or a concrete unavailable-device reason is recorded.
- No more than 3 non-doc implementation/test files are touched.

## scope guard

Do not:

- refactor leave architecture;
- add a new abstraction or service;
- change `GroupMessageRepository` APIs;
- alter database schemas/migrations;
- change group bridge payloads or native Go/libp2p behavior;
- change voluntary leave ordering or failure semantics for `GCA-010`;
- edit source matrix or breakdown during this planning-only task;
- broaden into remote member-removal cleanup unless the executor stops and asks for expanded scope.

Overengineering includes moving leave orchestration into a new application coordinator, making `leaveGroup()` own every message cleanup caller, adding new cleanup modes, or changing all `leaveGroup()` call sites without row-specific evidence.

## accepted differences / intentionally out of scope

- Direct `leaveGroup()` callers outside Group Info may still use the membership/key/group cleanup primitive without message purge. This session accepts that difference because the row-owned gap is the Group Info leave path and because widening `leaveGroup()` would likely exceed the hard file cap.
- Dissolved local delete already uses `deleteGroupAndMessages(deleteLocallyIfDissolved: true)` and must remain local-only without sending a new `group:leave`.
- `GCA-010` may later revisit leave ordering and partial-failure handling; this plan preserves current ordering and only changes the successful local cleanup target.

## dependency impact

- `GCA-010` depends on this plan not hiding or changing voluntary leave ordering. If implementation changes broadcast/rotation order, stop and re-plan under `GCA-010`.
- Later closure work should update `group-chat-audit-gap-closure-matrix.md` row `GCA-009` and this breakdown ledger only after implementation and verification land.
- If the executor discovers that `GroupInfoWired` is sometimes constructed without `msgRepo` in production, that is an evidence blocker for full closure; either document accepted partial coverage or stop and ask before broadening constructor/wiring scope.

## Reviewer Findings

Sufficiency: sufficient with adjustments.

Reviewer answers:

- Missing files/tests/gates: no structural gap. The plan includes the row-owned widget test, the two application backstops, diff hygiene, and the `groups` named gate.
- Stale or incorrect assumptions: no stale source-of-truth issue found. The plan now records that production `GroupInfoWired` is constructed from `group_conversation_wired.dart` with `msgRepo`.
- Overengineering: none. The planned implementation reuses `deleteGroupAndMessages()` and does not add a new coordinator, repository API, migration, or bridge behavior.
- Decomposition: sufficient. The executor can implement from one failing test file and one UI wiring file, with a hard stop before a fourth non-doc file.
- Minimum needed: keep the `msgRepo == null` fallback, preserve voluntary-leave broadcast ordering, and update any conflicting local-timeline assertions in the same widget test file.

## Arbiter Decision

Final verdict: execution-ready.

Structural blockers: none.

Incremental details intentionally deferred:

- The executor may choose whether to add a new `GCA-009` test or retarget the existing successful leave widget test, as long as the failing-first proof and final assertion set are equivalent.
- The broader `groups` gate may expose existing unrelated reds; exact failure names should be recorded rather than fixed inside this session.

Accepted differences:

- This session does not make every direct `leaveGroup()` caller purge messages. The row-owned closure is the Group Info active leave path, and the plan keeps the hard 3-file cap.
- This session does not change voluntary leave partial-failure ordering; that remains row `GCA-010`.

Why safe to implement now: the plan reuses an already-tested cleanup use case, keeps the existing failed-leave preservation sequence, targets one UI caller and one widget test file, and has explicit stop rules for scope expansion.
