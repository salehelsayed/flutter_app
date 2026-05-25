Status: execution-ready

# GCA-005 - Group Conversation Message Load Error Surface Plan

## Planning Progress

- 2026-05-23T19:57:02+02:00 - Planner completed. Files inspected since last update: draft plan sections. Decision/blocker: draft keeps implementation to `GroupConversationWired`, `GroupConversationScreen`, and one wired test; no blocker. Next action: reviewer pass for sufficiency, stale assumptions, gate contract, and scope drift.
- 2026-05-23T19:58:41+02:00 - Reviewer started. Files inspected since last update: full draft plan. Decision/blocker: review against mandatory sections, TDD order, three-file hard cap, and gate contract. Next action: record sufficiency findings.
- 2026-05-23T19:58:41+02:00 - Reviewer completed. Files inspected since last update: full draft plan. Decision/blocker: sufficient with one incremental tightening: make retry recovery proof mandatory in the first regression wording. Next action: arbiter classify and finalize.
- 2026-05-23T20:00:06+02:00 - Arbiter started. Files inspected since last update: reviewer findings and tightened draft. Decision/blocker: classify reviewer finding and verify no structural blockers. Next action: final execution-ready status.
- 2026-05-23T20:00:06+02:00 - Arbiter completed. Files inspected since last update: final plan artifact. Decision/blocker: no structural blockers remain; the retry-proof tightening is incremental and already applied. Next action: hand off compact planning verdict.

## Execution Progress

- 2026-05-23T19:55:39+02:00 - Controller contract extracted. Files inspected since last update: this plan, session breakdown, skill instructions, dirty git snapshot. Decision/blocker: execute `GCA-005` only; write scope remains this plan plus `group_conversation_wired.dart`, `group_conversation_screen.dart`, and `group_conversation_wired_test.dart`; source matrix and breakdown are closure-only and must not be edited. Next action: spawn isolated Executor.
- 2026-05-23T19:56:21+02:00 - Executor spawned/running. Files inspected or touched since last update: plan execution progress only. Command currently running: `codex exec -m gpt-5.5 -c model_reasoning_effort="xhigh"` with `GCA-005` Executor prompt. Decision/blocker: no blocker. Next action: wait for Executor result.
- 2026-05-23T19:58:20+02:00 - Executor contract extracted. Files inspected since last update: this plan, `group_conversation_wired.dart`, `group_conversation_screen.dart`, `group_conversation_wired_test.dart`, run-only `group_conversation_screen_test.dart`, `group_message_repository.dart`, `in_memory_group_message_repository.dart`, dirty git snapshot. Decision/blocker: scope is limited to initial message-page failure surfacing and retry; existing dirty files are unrelated and must be preserved. Next action: add focused failing regression.
- 2026-05-23T19:59:35+02:00 - Executor added focused regression. Files touched since last update: `group_conversation_wired_test.dart`, this plan. Command currently running next: `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "message load failure shows retryable error instead of empty conversation"`. Decision/blocker: no blocker. Next action: confirm failing-first result before production edits.
- 2026-05-23T20:01:01+02:00 - Failing-first selector finished. Files touched since last update: this plan. Command finished: `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "message load failure shows retryable error instead of empty conversation"` failed as expected because `Couldn't load messages` was absent after the simulated initial page failure. Decision/blocker: intended RED confirmed. Next action: implement minimal error/retry state.
- 2026-05-23T20:01:38+02:00 - Executor implemented minimal product change. Files touched since last update: `group_conversation_wired.dart`, `group_conversation_screen.dart`, this plan. Decision/blocker: added local message-load error state, stable retry key, and retry path through `_loadMessages()` without changing repositories or adjacent features. Next action: run required post-implementation selector.
- 2026-05-23T20:02:05+02:00 - Post-implementation focused selector finished. Files touched since last update: this plan. Command finished: `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "message load failure shows retryable error instead of empty conversation"` passed. Decision/blocker: no blocker. Next action: run required wired plus pure screen presentation tests.
- 2026-05-23T20:02:54+02:00 - Required presentation tests finished. Files touched since last update: this plan. Command finished: `flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart test/features/groups/presentation/group_conversation_screen_test.dart` failed with `+112 -17`; the new GCA-005 selector passed, while failures were in send/media/voice selectors emitting `GROUP_SEND_MSG_USE_CASE_EMPTY_MEMBERSHIP_DISSOLVED` or adjacent send-path assertions outside the allowed file set. Decision/blocker: classify as unrelated-but-required dirty-work/send-path failures, not caused by this load-error diff. Next action: run `git diff --check`.
- 2026-05-23T20:04:00+02:00 - Final Executor validation finished. Files touched since last update: `group_conversation_wired_test.dart` formatting, this plan. Commands finished: `dart format lib/features/groups/presentation/screens/group_conversation_wired.dart lib/features/groups/presentation/screens/group_conversation_screen.dart test/features/groups/presentation/group_conversation_wired_test.dart` formatted one file; focused selector rerun passed; paired presentation command rerun failed again with `+112 -17` in the same unrelated send/media/voice area; `git diff --check` passed. Decision/blocker: GCA-005 behavior is implemented and focused proof is green, but the required paired command remains red for unrelated existing send-path failures. Next action: hand off to QA Reviewer with explicit residual test failure.
- 2026-05-23T20:04:15+02:00 - Executor completed. Files touched since last update: this plan. Decision/blocker: optional `./scripts/run_test_gates.sh groups` not run because the required direct presentation command is already red from unrelated send-path failures and local budget should preserve QA focus on GCA-005. Next action: QA Reviewer should verify the diff scope, focused selector, and unrelated-failure classification.
- 2026-05-23T20:05:24+02:00 - QA Reviewer spawned/running. Files inspected or touched since last update: plan execution progress only. Command currently running: `codex exec -m gpt-5.5 -c model_reasoning_effort="xhigh"` with `GCA-005` QA Reviewer prompt. Decision/blocker: no blocker. Next action: wait for QA Reviewer result.
- 2026-05-23T20:06:59+02:00 - QA Reviewer started. Files inspected since last update: this plan, dirty git snapshot, `group_conversation_wired.dart`, `group_conversation_screen.dart`, `group_conversation_wired_test.dart`. Decision/blocker: GCA-005 diff appears confined to the allowed implementation/test files; broader worktree dirt is pre-existing per plan and needs classification, not reverting. Next action: run focused selector and hygiene checks.
- 2026-05-23T20:08:08+02:00 - QA validation completed. Files inspected since last update: allowed GCA-005 diff, source matrix/breakdown status, paired-test failure output. Commands finished: focused selector passed; `git diff --check` passed; paired presentation command failed `+112 -17` with the GCA-005 selector passing inside the run. Decision/blocker: residual paired failures are credible unrelated send/media/voice-path failures around `GROUP_SEND_MSG_USE_CASE_EMPTY_MEMBERSHIP_DISSOLVED` and adjacent send assertions; source matrix/breakdown mtimes remained before execution, and optional group gate/manual debug run were not run. Next action: record final QA classification.
- 2026-05-23T20:08:08+02:00 - QA Reviewer completed. Files touched since last update: this plan execution progress only. Decision/blocker: blocking issues none; non-blocking follow-up is the existing unrelated red paired presentation residual outside GCA-005. Final QA classification: accepted for GCA-005; no fix-pass Executor required.
- 2026-05-23T20:09:40+02:00 - Final verdict written. Files touched since last update: this plan execution progress only. Decision/blocker: `accepted_with_explicit_follow_up` because GCA-005 focused behavior is complete and QA accepted, while the paired presentation command still has unrelated send/media/voice residual failures. Next action: closure session may update source matrix and breakdown later.

## Evidence Collector Findings

- Source matrix row `GCA-005` is `Open` and says conversation message load failures are swallowed into an empty conversation state.
- The breakdown classifies `GCA-005` as `implementation-ready`, with no dependency on earlier sessions, and limits likely code entry to `GroupConversationWired`, `GroupConversationScreen`, and focused tests.
- `GroupConversationWired.initState()` calls `_loadMessages()` during screen initialization.
- `GroupConversationWired._loadMessages()` calls `widget.msgRepo.getMessagesPage(widget.group.id)`, resolves media, sets `_messages`, `_mediaMap`, `_initialLoadDone = true`, and then marks messages read on success.
- On any `_loadMessages()` exception, current code only sets `_initialLoadDone = true` and emits `GROUP_CONV_FL_LOAD_MESSAGES_ERROR`; it does not retain or pass a user-visible load-error state.
- `GroupConversationScreen` renders `_GroupConversationLoadingShell` while `!initialLoadDone || isRecovering`, otherwise renders `_buildEmptyState()` when `messages.isEmpty`; default empty copy is `No messages yet` plus `Send a message to start the conversation` or `Waiting for messages`.
- Existing direct tests cover pure-screen loading and empty states, and wired slow initial load plus successful initial message load. They do not cover message-page load failure.
- `CountingGroupMessageRepository` in `group_conversation_wired_test.dart` extends the in-memory repository and is the narrow place to add a local throwing/deferred test double without changing shared fakes.
- `Test-Flight-Improv/test-gates-reference.md` says `./scripts/run_test_gates.sh groups` is the named group behavior gate and that the script wins on disagreement.
- The current worktree is already dirty from other sessions; implementation must preserve unrelated edits and never revert them.

## real scope

Change only the group conversation initial message-load failure surface so a failed first page is visible to the user and is not represented as a normal empty conversation.

Allowed non-doc implementation/test write set for the eventual executor:

- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`

`test/features/groups/presentation/group_conversation_screen_test.dart` is a run-only compatibility/regression file for this session, not an editable target. If the executor cannot satisfy the plan without editing a fourth non-doc file, it must stop and ask instead of widening scope.

Do not change message repositories, database helpers, migrations, group send/receive use cases, listeners, bridge code, media repositories, notification routing, Group Info, source matrix, session breakdown, or later GCA rows.

## closure bar

The session is good enough when an initial `GroupMessageRepository.getMessagesPage()` failure with no displayable messages shows a concise load-error state and retry affordance, while successful empty loads still show the normal `No messages yet` empty state and successful non-empty loads still render the timeline. Existing loading, recovery, read-only, compose, media, reaction, and notification-anchor behavior must remain unchanged.

## source of truth

- Primary row contract: `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-matrix.md` row `GCA-005`.
- Session decomposition: `Test-Flight-Improv/Group-Chat-Feature/group-chat-audit-gap-closure-session-breakdown.md` session `GCA-005`.
- Current implementation and focused tests win over stale prose if they disagree.
- Gate source: `Test-Flight-Improv/test-gates-reference.md`; if it disagrees with `scripts/run_test_gates.sh`, the script wins.
- This plan is doc-scoped; product code, tests, matrix, and breakdown remain untouched until a later execution session.

## session classification

`implementation-ready`

## exact problem statement

When the group conversation opens, `_loadMessages()` can throw while fetching the initial message page. Current code catches the exception, logs a flow event, and marks the initial load done. Because `_messages` remains empty and `GroupConversationScreen` has no load-error input, the UI falls through to the normal empty conversation copy. Users can be told `No messages yet` even though the app failed to load messages, and they get no obvious retry path.

The fix must distinguish:

- initial load pending: existing loading shell;
- successful empty page: existing `No messages yet` state;
- initial load failure with no displayable messages: concrete error state plus retry;
- successful non-empty page: existing timeline rendering.

The fix must not change send behavior, optimistic rows, reaction behavior, media download/repair behavior, recovery banners, read-only groups, dissolved groups, or normal empty-success semantics.

## files and repos to inspect next

- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/groups/presentation/screens/group_conversation_screen.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/groups/presentation/group_conversation_screen_test.dart` run-only compatibility coverage
- `test/shared/fakes/in_memory_group_message_repository.dart` read-only reference for local test-double behavior
- `Test-Flight-Improv/test-gates-reference.md`
- `scripts/run_test_gates.sh` only if named gate behavior is unclear

## existing tests covering this area

- `test/features/groups/presentation/group_conversation_screen_test.dart`
  - Covers loading shell while `initialLoadDone` is false, normal empty state once load completes with no messages, recovery state, read-only/dissolved UI, quote rendering, media rows, reactions, and compose behavior.
  - Missing: pure-screen message-load error state. Do not add this as a separate edited test unless the executor stops and gets explicit approval for a fourth non-doc file.
- `test/features/groups/presentation/group_conversation_wired_test.dart`
  - Covers successful initial message loading, slow initial loading shell, send/refresh paths, live upserts, scroll preservation, notification anchors, reaction inspection, media upload and retry behavior, recovery state, read-only guards, and many group conversation edge cases.
  - Missing: initial `getMessagesPage()` failure surfaces an error instead of the normal empty state.

## regression/tests to add first

Add the failing regression first in `test/features/groups/presentation/group_conversation_wired_test.dart`, using a local test double derived from `CountingGroupMessageRepository`, for example `FailingInitialPageGroupMessageRepository`.

Suggested selector:

```sh
flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "message load failure shows retryable error instead of empty conversation"
```

The failing-first test should:

- save/pump a normal group through `GroupConversationWired`;
- make the initial `getMessagesPage()` call throw;
- wait for the failed load to settle;
- expect the loading shell is gone;
- expect error copy such as `Couldn't load messages`;
- expect a `Retry` affordance, preferably with a stable key such as `group-conversation-load-retry`;
- expect `No messages yet` is absent;
- make retry recover by allowing a later `getMessagesPage()` call to return a saved message, then tap `Retry` and assert the message appears.

This proves the real wired screen seam and keeps the editable test footprint to one test file.

## step-by-step implementation plan

1. Add the focused failing regression and any local test-only throwing/recovering message repository in `group_conversation_wired_test.dart`.
2. Run the focused selector and confirm it fails for the intended reason: current UI shows the normal empty state and no error/retry surface.
3. In `GroupConversationScreen`, add defaulted optional props for a message-load error and retry callback, such as `messageLoadErrorText` and `onRetryMessageLoad`. Existing constructor callers/tests must continue to compile unchanged.
4. Adjust the empty/loading branch so visible messages always win, loading/recovery remains unchanged, and the new error state renders only when there are no messages and initial load is done. Successful empty state must remain the final fallback.
5. Add a small private `_buildMessageLoadErrorState` using existing readable color patterns, a familiar error icon, concise hardcoded copy, and a `TextButton.icon` or equivalent retry affordance. Do not add localization or shared UI abstractions.
6. In `GroupConversationWired`, add private nullable state for the current message-load error. Clear it before/after a successful `_loadMessages()` and set it in the catch block when loading fails.
7. Add a minimal retry callback that clears the error, returns to the existing loading shell when no messages are visible, and calls the existing `_loadMessages()` path. Preserve current mounted checks, media-map loading, reaction loading, pending-media download, and `markAsRead` ordering on success.
8. Pass the new error/retry props from `GroupConversationWired` to `GroupConversationScreen`.
9. Run the focused regression, the direct presentation tests, and hygiene commands listed below. Stop and ask if the fix needs more than the three allowed non-doc files.

## risks and edge cases

- Refresh failure with existing visible messages: do not blank a visible timeline into a full-screen error; this row is about false empty state when no messages are displayable.
- Successful true-empty group: must still show `No messages yet`, not an error.
- Recovery gate: `isRecovering` should continue to show the recovery/loading state while replay is pending.
- Retry loops: repeated failures must return to the error state rather than leaving the loading shell stuck.
- Media/reaction side effects: failed initial message load must not trigger reaction loading, media downloads, or mark-as-read behavior for an empty failed page.
- Error details: do not expose raw exception text to the user; flow telemetry already records technical details.

## exact tests and gates to run

Failing-first command before implementation:

```sh
flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "message load failure shows retryable error instead of empty conversation"
```

Required after implementation:

```sh
flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart --plain-name "message load failure shows retryable error instead of empty conversation"
flutter test --no-pub test/features/groups/presentation/group_conversation_wired_test.dart test/features/groups/presentation/group_conversation_screen_test.dart
git diff --check
```

Named group gate, run if local budget allows or if the controller requires full group behavior evidence:

```sh
./scripts/run_test_gates.sh groups
```

Manual verification step:

Open an existing group conversation in a local debug run after the automated fix and confirm a normal successful load still shows the existing message timeline and compose/read-only affordances without the new error state.

## known-failure interpretation

The focused wired selector is session-owned and must pass. Failures in the direct presentation command are session-owned if they involve `GroupConversationWired`, `GroupConversationScreen`, constructor compatibility, loading/empty/error rendering, or existing conversation UI regressions caused by the new props.

If `./scripts/run_test_gates.sh groups` fails, triage the first failing selector and compare it to the current diff. The matrix/breakdown already record unrelated residual group-gate failures from nearby sessions, including `group_membership_smoke_test.dart` `GM-028` and invite/recovery/membership integration residuals. Do not classify those as `GCA-005` regressions without a diff-linked reason.

## done criteria

- The new focused wired regression fails before implementation and passes after implementation.
- Initial message-page failure with no visible messages shows user-facing load-error copy and retry.
- The normal `No messages yet` empty state remains reserved for successful empty loads.
- Existing non-empty conversation load still renders messages.
- Retry reuses the existing load path and can recover to showing messages.
- Direct conversation presentation tests pass, or any failure is truthfully classified with evidence.
- No more than three non-doc implementation/test files are touched.
- `git diff --check` passes.
- The manual verification step above is performed or explicitly marked not run.

## scope guard

Non-goals:

- no changes to `GCA-006`, `GCA-007`, send/composer behavior, unauthorized send handling, or optimistic message cleanup;
- no repository, database, migration, bridge, listener, media, reaction, notification, Group Info, or navigation refactor;
- no shared error-state component, dependency, design-system rewrite, or localization pass;
- no edits to `group_conversation_screen_test.dart` unless the executor stops and gets approval for exceeding the three-file cap;
- no source matrix or breakdown status updates until a later execution/closure session has real evidence.

Stop and ask if implementation requires touching more than `group_conversation_wired.dart`, `group_conversation_screen.dart`, and `group_conversation_wired_test.dart`, or if the failure turns out to originate below the presentation layer.

## accepted differences / intentionally out of scope

- This session intentionally does not add a global conversation error framework; it adds one local error state for the audited group conversation load seam.
- It does not localize the new copy because surrounding group presentation code already contains hardcoded strings and this session forbids broader localization work.
- It does not cover send-time failures, missing identity, unauthorized sends, or missing-group send results; those remain owned by `GCA-006` and `GCA-007`.
- It does not define behavior for later refresh failures when a timeline is already visible beyond avoiding a false full-screen empty state.

## dependency impact

Closing `GCA-005` gives later group conversation sessions a clear separation between initial load failure and true empty state. `GCA-006` and `GCA-007` also touch `GroupConversationWired`, so their executors must re-read the current file and avoid overwriting this session's load-error state. If this plan blocks under the three-file cap, later conversation sessions should not copy or depend on this error-state pattern until the blocker is resolved.

## Reviewer Notes

Reviewer verdict: sufficient with one incremental tightening.

- Missing files/tests/gates: none. The focused selector, direct conversation presentation command, optional named group gate, and `git diff --check` are named.
- Stale assumptions: none found. The current code and tests confirm the false-empty-state seam.
- Overengineering: none. The draft uses local screen props and wired state, forbids shared abstractions/localization, and preserves lower layers.
- Decomposition: narrow enough for execution under the three-file non-doc cap.
- Minimum needed to make sufficient: make retry recovery proof required in the regression wording rather than optional, because done criteria require retry recovery.

## Arbiter Notes

Arbiter verdict: `execution-ready`.

- Structural blockers remaining: none.
- Incremental details intentionally deferred: no dedicated pure-screen error-state test, because `group_conversation_screen_test.dart` remains run-only to preserve the three-file hard cap.
- Accepted differences intentionally left unchanged: no shared error component, no localization pass, no send/composer/unauthorized-send work, and no lower-layer repository changes.
- Final stop rule: executor must stop and ask if the fix cannot be completed within `group_conversation_wired.dart`, `group_conversation_screen.dart`, and `group_conversation_wired_test.dart`.

## Final Planning Verdict

Final verdict: execution-ready for `GCA-005` only.

Final plan: implement one failing-first wired regression for initial message load failure, then add minimal local message-load error and retry state across `GroupConversationWired` and `GroupConversationScreen`.

Structural blockers remaining: none.

Incremental details intentionally deferred: no separate pure-screen test edit and no broad named-gate repair work.

Accepted differences intentionally left unchanged: hardcoded local copy, no shared abstraction, and no adjacent `GCA-006`/`GCA-007` send-path changes.

Why safe to implement now: the plan is grounded in current code/tests, names exact files and gates, preserves the three-file hard cap, and has an explicit stop-and-ask rule for scope expansion.
