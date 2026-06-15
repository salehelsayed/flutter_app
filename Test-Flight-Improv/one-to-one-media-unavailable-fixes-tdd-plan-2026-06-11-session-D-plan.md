# One-To-One Media Unavailable Fixes - Session D Plan

Status: execution-ready

Source doc: `Test-Flight-Improv/one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11.md`
Breakdown artifact: `Test-Flight-Improv/one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11-session-breakdown.md`
Session: D - `Retry And Duplicate Replay Repair`

## Planning Progress

- `2026-06-11T22:51:00+0200` - Role: Local fallback Arbiter completed. Files inspected since last update: incomplete spawned planner draft, Session D breakdown entry, source plan Session D, gate definitions, and evidence notes already persisted by the planner. Last completed command/result: local plan fallback replaced the stalled `planning-intake` draft with this execution-ready doc-scoped plan. Decision/blocker: no structural blockers remain; plan is execution-ready. Next action: execute Session D with failing-first regressions and scoped owner-file edits.
- `2026-06-11T22:50:00+0200` - Role: Local fallback Planner/Reviewer completed. Files inspected since last update: Session D breakdown entry and persisted evidence. Last completed command/result: mandatory sections drafted and reviewed for scope, regression-first tests, gates, and Session F simulator ownership. Decision/blocker: no blocker; exact `--plain-name` filters may be adjusted after tests land. Next action: arbiter classification.
- `2026-06-11T20:39:01Z` - Evidence Collector in progress. Files inspected since last update: source plan, session breakdown, Session C plan/verdict context, `Test-Flight-Improv/test-gate-definitions.md`, `scripts/run_test_gates.sh`, `conversation_screen.dart`, `letter_card.dart`, `conversation_wired.dart`, `download_media_use_case.dart`, `chat_message_listener.dart`, `handle_incoming_chat_message_use_case.dart`, media attachment repository APIs/fakes, and direct test search results. Last completed command/result: `rg` plus line-scoped reads show `LetterCard` already supports attachment-level unavailable retry, but `ConversationScreen` does not pass `onRetryUnavailableMedia`; `ConversationWired._loadInitialPage` replaces `_messages` wholesale; duplicate handling returns before repair/auto-download; app resume currently has outgoing upload/message retry hooks, not an incoming direct download retry hook. Decision/blocker: no structural blocker yet; plan must keep simulator closure Session F-owned and require host-focused Session D proofs plus `1to1`. Next action: complete evidence summary, draft mandatory plan sections, then run Reviewer and Arbiter passes.

## Execution Progress

- `2026-06-11T22:56:42+0200` - Phase: contract extracted. Files inspected or touched: Session D plan, session breakdown, execution skill, graphify skill, `git status --short`, scoped owner-file diffs for Session D production/test files. Last completed command/result: `graphify-arch` graph exists; `graphify query "Session D direct unavailable-media retry duplicate replay stale initial page repair paths ConversationWired ChatMessageListener HandleIncomingChatMessageUseCase" .` returned only a shallow listener neighborhood, so source inspection will carry exact owner-file evidence. Decision/blocker: nested Executor/QA child tools are unavailable in this callable toolset; using the user-authorized local sequential fallback with Executor then QA phases, no spawned child partial work exists. Next action: local Executor adds failing-first regressions, records RED results, then implements the scoped retry/replay/merge fixes.
- `2026-06-11T23:05:00+0200` - Phase: local Executor RED tests started. Files inspected or touched: `conversation_screen_test.dart`, `conversation_wired_test.dart`, `handle_incoming_chat_message_use_case_test.dart`. Last completed command/result: added failing-first regressions for direct UI retry callback wiring, targeted wired retry/download dedupe, stale initial-page repair preservation, and duplicate replay media repair; `dart format` completed on the touched test files. Decision/blocker: pending RED classification. Next action: run the focused Session D filters and record expected failures before production edits.
- `2026-06-11T23:06:50+0200` - Phase: local Executor RED tests completed. Files inspected or touched: focused test output for `conversation_screen_test.dart`, `conversation_wired_test.dart`, and `handle_incoming_chat_message_use_case_test.dart`. Last completed command/result: `flutter test test/features/conversation/presentation/screens/conversation_screen_test.dart --plain-name "incoming unavailable media retry is wired for direct conversation"` failed because `ConversationScreen` has no `onRetryUnavailableMedia`; `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name "direct unavailable retry downloads failed attachment"` and `--plain-name "loadInitialPage"` failed because `DownloadMediaFn`, `downloadMediaFn`, and `ConversationScreen.onRetryUnavailableMedia` do not exist; `flutter test test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart --plain-name "duplicate replay repairs failed media attachment without duplicate"` failed because the attachment remained `failed` instead of becoming `pending`. Decision/blocker: expected Session D RED failures confirmed. Next action: implement UI callback seam, targeted retry/dedupe, duplicate replay media repair, stale initial-page merge, and resume classification.
- `2026-06-11T23:18:17+0200` - Phase: local Executor implementation and GREEN focused tests completed. Files inspected or touched: `conversation_screen.dart`, `conversation_wired.dart`, `handle_incoming_chat_message_use_case.dart`, `conversation_screen_test.dart`, `conversation_wired_test.dart`, `handle_incoming_chat_message_use_case_test.dart`. Last completed command/result: implemented direct UI unavailable-media retry wiring, targeted `DownloadMediaUseCase` retry with in-flight attachment dedupe, affected-message refresh, duplicate replay media repair without duplicate message insertion, and stale initial-page merge preservation. Focused GREEN results: `conversation_screen_test.dart --plain-name "incoming unavailable media retry is wired for direct conversation"` passed; `conversation_wired_test.dart --plain-name "direct unavailable retry downloads failed attachment"` passed; `conversation_wired_test.dart --plain-name "loadInitialPage"` passed; `handle_incoming_chat_message_use_case_test.dart --plain-name "duplicate"` passed; `chat_message_listener_test.dart --plain-name "duplicate"` passed. Resume classification: `rg` inspection found existing app-resume paths for outgoing retry, group recovery, post media, push/key exchange, and inbox drain, but no existing incoming direct media download resume path to extend; incoming direct media resume recovery is not applicable in Session D without adding a new lifecycle subsystem. Decision/blocker: no implementation blocker. Next action: run full direct suites and named gate.
- `2026-06-11T23:18:17+0200` - Phase: local QA completed. Files inspected or touched: touched Session D files plus focused/direct/gate command output. Last completed command/result: `flutter test test/features/conversation/presentation/screens/conversation_screen_test.dart` passed; `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart` passed; `flutter test test/features/conversation/application/chat_message_listener_test.dart` passed; `flutter test test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart` passed; `./scripts/run_test_gates.sh 1to1` passed; `dart format` reported 0 further changes across touched Dart files; `git diff --check -- <touched Session D files>` passed. `graphify update .` was attempted after code changes and completed AST extraction for `5035/5035` files, but did not return cleanly after roughly two minutes and was stopped, exiting non-zero; because the plan requires graph refresh only if feasible, this is recorded as a non-blocking follow-up rather than a Session D blocker. Final verdict: `accepted_with_explicit_follow_up`. Remaining follow-up: rerun `graphify update .` later if a clean graph refresh is required before subsequent planning.

## Evidence Summary

- The breakdown scopes Session D to incoming direct unavailable-media retry, targeted receiver retry with `DownloadMediaUseCase`, duplicate replay repair, stale initial-page merge, and resume recovery only if an existing app-resume media path is present.
- `LetterCard` already has an attachment-level unavailable retry affordance, but the direct `ConversationScreen` path does not pass `onRetryUnavailableMedia` through to that affordance.
- `ConversationWired` is the right integration point for a direct retry handler because it owns direct conversation state, message refresh, and `DownloadMediaUseCase` dependencies.
- The current initial page load path replaces `_messages` wholesale, which can overwrite a newer streamed or retry-repaired attachment state with stale page data.
- Duplicate direct-message handling currently returns early before scheduling repair or auto-download for failed/pending media on an already-known message.
- App resume currently has outgoing upload/message retry hooks. Do not add new incoming resume behavior unless current code already has a suitable app-resume media path to extend without widening Session D.
- Sessions A-C have landed the lower-level relay durability, receiver orphan adoption, and local-WiFi fallback needed for this UI/listener recovery layer.

## Real Scope

Implement the direct 1:1 receiver recovery/UI-state slice.

In scope:

- Wire incoming unavailable-media retry from direct conversation UI to a `ConversationWired` handler.
- Implement targeted direct retry for a failed/pending incoming attachment by invoking `DownloadMediaUseCase`, deduping concurrent retries for the same attachment, and refreshing only the affected message state.
- Repair failed or pending media when a duplicate envelope for the same direct message arrives, without inserting a duplicate message.
- Merge initial-page results by message ID so stale load results cannot overwrite a newer streamed or retried media repair.
- Add resume recovery only if an existing app-resume media path can be extended within this same receiver-recovery seam.

Out of scope:

- Relay media durability, multi-relay failover, receiver orphan adoption, local-WiFi fallback, thumbnail fallback, group media, posts/media, encryption protocol changes, broad state-management refactors, and final simulator/source-report/matrix closure updates.

## Closure Bar

Session D is good enough for implementation acceptance when:

- An incoming direct message with a failed media attachment shows and invokes the unavailable retry callback.
- The direct retry callback calls `DownloadMediaUseCase` for the selected attachment, dedupes in-flight retry for the same attachment, and refreshes the affected message/attachment state after completion.
- Duplicate delivery of the same direct message with media descriptors does not insert a duplicate message and does repair or schedule download for failed/pending media when appropriate.
- A stale `_loadInitialPage` result cannot overwrite a newer repaired attachment state for the same message.
- Resume recovery is either covered by an existing app-resume media path or explicitly recorded as not applicable for this session with evidence.
- Focused direct tests pass and `./scripts/run_test_gates.sh 1to1` passes.
- The overall source plan remains open until Session F supplies simulator evidence and final source-report/matrix/closure updates.

## Source Of Truth

- Active Session D contract: `Test-Flight-Improv/one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11-session-breakdown.md`.
- Source plan: `Test-Flight-Improv/one-to-one-media-unavailable-fixes-tdd-plan-2026-06-11.md`.
- Root-cause report: `Test-Flight-Improv/one-to-one-media-unavailable-debug-codex-2026-06-11.md`.
- Named gate source: `scripts/run_test_gates.sh`; `Test-Flight-Improv/test-gate-definitions.md` is the companion.
- Current code and tests win over stale prose.

## Session Classification

`implementation-ready`.

Reason: the seams are direct Flutter UI/listener/use-case paths with focused host tests. Device-backed simulator proof remains Session F-owned and is not required for Session D implementation acceptance.

## Exact Problem Statement

Direct 1:1 media can remain unavailable after lower-level recovery paths exist because the receiver UI and duplicate replay paths do not reliably trigger repair. The user-visible failure is an incoming direct media attachment that remains failed or unavailable even though retry/replay could now recover it. Session D must wire the retry affordance, targeted download, duplicate replay repair, and stale page merge so receiver-side recovery can actually surface.

## Files And Repos To Inspect Next

Production:

- `lib/features/conversation/presentation/screens/conversation_screen.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/conversation/application/chat_message_listener.dart`
- `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`
- `lib/features/conversation/presentation/widgets/letter_card.dart`
- `lib/features/conversation/application/download_media_use_case.dart`
- `lib/features/conversation/domain/repositories/media_attachment_repository.dart`

Tests:

- `test/features/conversation/presentation/screens/conversation_screen_test.dart`
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `test/features/conversation/application/chat_message_listener_test.dart`
- `test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart`

## Existing Tests Covering This Area

- Existing media widget and `LetterCard` tests cover unavailable retry only when a callback is supplied.
- Direct conversation screen/wired tests cover many send, quote, local media, and state paths but do not prove incoming unavailable retry is supplied end to end.
- Listener/use-case tests cover duplicate message dedupe and incoming handling but do not prove duplicate replay repairs failed/pending media.
- Existing direct download tests now cover Session B orphan adoption and cleanup, so Session D should use `DownloadMediaUseCase` rather than reimplementing download behavior.

Missing:

- Incoming direct unavailable retry callback wiring.
- Direct retry invoking `DownloadMediaUseCase` and refreshing the affected message.
- Duplicate replay media repair without duplicate message insertion.
- Initial-page stale merge protection for newer repaired attachment state.
- Resume recovery classification for incoming failed/pending direct media.

## Regression/Tests To Add First

1. `conversation_screen_test.dart`: add `incoming unavailable media retry is wired for direct conversation`.
   - Arrange an incoming direct message with a failed media attachment.
   - Provide a retry callback.
   - Tap the unavailable retry affordance.
   - Assert the callback receives the message and attachment identifiers.

2. `conversation_wired_test.dart`: add `direct unavailable retry downloads failed attachment`.
   - Arrange direct conversation state with a failed incoming attachment.
   - Invoke the retry callback.
   - Assert `DownloadMediaUseCase` runs for that attachment and the affected message refreshes.
   - Assert concurrent retry for the same attachment is deduped.

3. `chat_message_listener_test.dart` or `handle_incoming_chat_message_use_case_test.dart`: add duplicate replay repair coverage.
   - Arrange an existing message with a failed or pending media attachment.
   - Deliver a duplicate envelope with the same message id and media descriptor.
   - Assert no duplicate message is inserted.
   - Assert media recovery is scheduled or attachment state is repaired when a valid local/canonical file is available.

4. `conversation_wired_test.dart`: add `_loadInitialPage does not overwrite newer streamed media repair`.
   - Start an initial page load.
   - Repair or stream an updated attachment for the same message.
   - Complete the initial page with stale attachment state.
   - Assert the repaired attachment remains visible.

5. Resume recovery:
   - Inspect current app-resume media hooks during execution.
   - If an existing incoming direct media resume path exists, add a focused dedupe test.
   - If none exists, record `not applicable in Session D` in execution and closure notes; do not invent a new lifecycle subsystem here.

## Step-By-Step Implementation Plan

1. Inspect current dirty diffs for the owner files before editing; preserve unrelated changes.
2. Add the UI retry wiring regression in `conversation_screen_test.dart` and confirm it fails because direct retry callback is not passed/invoked.
3. Add the `ConversationWired` retry regression and confirm it fails because there is no direct retry handler invoking `DownloadMediaUseCase`.
4. Add the duplicate replay repair regression and confirm it fails because duplicate handling returns before media repair.
5. Add the stale initial page merge regression and confirm it fails because `_loadInitialPage` overwrites newer state.
6. Wire `onRetryUnavailableMedia` through direct `ConversationScreen` to `LetterCard`.
7. Implement a narrow `ConversationWired` direct retry handler that:
   - locates the message and attachment;
   - dedupes by attachment id;
   - invokes `DownloadMediaUseCase`;
   - refreshes only that message from repository/listener state;
   - preserves scroll/focus and unrelated message state.
8. Update duplicate direct-message handling so an existing message row with failed/pending media can repair or schedule recovery from duplicate descriptors while preserving message dedupe.
9. Change initial page application to merge by message ID and keep newer repaired attachment state when the same message appears in stale page results.
10. Classify resume recovery as implemented only if an existing incoming media resume path is present; otherwise record it as not applicable for Session D.
11. Run focused direct tests and the `1to1` gate.

## Risks And Edge Cases

- Retrying all failed media too broadly could duplicate downloads or race UI refresh; dedupe per attachment.
- Duplicate replay repair must not insert duplicate messages or duplicate attachments.
- Stale page merge must not hide legitimate newer pagination results for messages that were not repaired.
- Completed valid local paths must not be overwritten by duplicate stale descriptors.
- Retry callback wiring must remain attachment-specific, not message-global only.
- Dirty worktree contains many unrelated edits; do not normalize or revert outside Session D owner files.

## Device/Relay Proof Profile

- Session D changes direct 1:1 retry/replay UI and listener behavior.
- Host tests can prove callback wiring, targeted retry invocation, duplicate replay repair, stale initial-page merge, and in-flight dedupe.
- `./scripts/run_test_gates.sh 1to1` is required because this touches direct conversation retry/listener behavior.
- Device-backed simulator proof for the full 1:1 media journey remains Session F-owned. Session D must not claim overall source-plan closure.

Session F-owned simulator commands:

```sh
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1 --list
"${CODEX_HOME:-$HOME/.codex}/skills/run-flutter-reliability-sims/scripts/run_with_devices.sh" 1to1
```

## Exact Tests And Gates To Run

Focused tests:

```sh
flutter test test/features/conversation/presentation/screens/conversation_screen_test.dart --plain-name "incoming unavailable media retry is wired for direct conversation"
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name "direct unavailable retry downloads failed attachment"
flutter test test/features/conversation/application/chat_message_listener_test.dart --plain-name "duplicate"
flutter test test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart --plain-name "duplicate"
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart --plain-name "loadInitialPage"
```

Direct suites:

```sh
flutter test test/features/conversation/presentation/screens/conversation_screen_test.dart
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart
flutter test test/features/conversation/application/chat_message_listener_test.dart
flutter test test/features/conversation/application/handle_incoming_chat_message_use_case_test.dart
```

Named gate:

```sh
./scripts/run_test_gates.sh 1to1
```

Conditional:

```sh
./scripts/run_test_gates.sh completeness-check
```

Run `completeness-check` only if execution adds a new test file or updates gate/test inventory classifications.

## Known-Failure Interpretation

- The new Session D tests must fail before implementation for the expected missing wiring, missing retry handler, duplicate repair, or stale merge reason.
- If broad direct suites fail outside Session D owner files, classify against the dirty worktree before attributing to Session D.
- If `1to1` fails in a file unrelated to changed retry/listener paths, run a focused triage slice and record whether it is pre-existing or caused by Session D.
- Missing Session F simulator evidence is not a Session D blocker; it keeps the overall source plan open.

## Done Criteria

- Incoming unavailable direct retry is wired from UI to a callback.
- Direct retry invokes `DownloadMediaUseCase`, dedupes in-flight retry, and refreshes the affected message.
- Duplicate replay repairs or schedules recovery for failed/pending media without duplicating the message.
- Initial page load merge preserves newer repaired attachment state.
- Resume recovery is either implemented via an existing incoming media resume path or explicitly classified not applicable.
- Focused direct tests and direct suites pass.
- `./scripts/run_test_gates.sh 1to1` passes.
- No final source-report, matrix, or closure-reference updates are made in Session D unless a test classification change requires it.

## Scope Guard

Do not:

- Modify relay server, Go node media failover, local-WiFi fallback, receiver orphan adoption, thumbnail fallback, group media, public posts, or encryption protocol.
- Add broad lifecycle/resume infrastructure if no existing incoming media resume path exists.
- Rewrite conversation state management beyond targeted message merge/refresh.
- Expand named gate membership unless a new test file requires classification.
- Revert unrelated dirty worktree changes.

Overengineering signs:

- A new global media retry scheduler when a direct attachment-level handler is enough.
- A broad stream/state architecture rewrite to solve stale initial-page merge.
- Duplicate replay changes that touch group or post message handling.

## Accepted Differences / Intentionally Out Of Scope

- Session F owns final simulator proof and final source-report/matrix/closure docs.
- Resume recovery may remain not applicable in Session D if no existing incoming direct media resume path exists; do not create a new lifecycle subsystem in this session.
- Retry/replay behavior is direct 1:1 only. Group media recovery remains out of scope.

## Dependency Impact

- Session E can assume true unavailable media retry wiring exists when distinguishing thumbnail failure from true media unavailability.
- Session F can use Session D evidence as host proof for DM-019 media retry without duplicates, but still must run or add simulator evidence before closing the source plan.
