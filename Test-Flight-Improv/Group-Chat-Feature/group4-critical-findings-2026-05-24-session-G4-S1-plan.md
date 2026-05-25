Status: execution-ready

# Group4 Critical Findings 2026-05-24 Session G4-S1 Plan

## Planning Progress

- 2026-05-24 00:51:10 CEST - Planner completed. Files inspected since last update: none. Decision/blocker: draft plan covers rows G4-005, G4-007, G4-008, G4-009, and G4-019 without expanding into group media/send/lifecycle work. Next action: reviewer sufficiency pass.
- 2026-05-24 00:54:08 CEST - Reviewer started. Files inspected since last update: draft plan content. Decision/blocker: checking mandatory sections, closure bar, tests/gates, scope guard, and over-broad assumptions. Next action: record reviewer verdict and required adjustments.
- 2026-05-24 00:54:35 CEST - Reviewer completed. Files inspected since last update: draft plan content. Decision/blocker: sufficient with small adjustments to pin remote-open missing-id telemetry and route-failure retry proof; no structural blocker. Next action: arbiter classification.
- 2026-05-24 00:55:01 CEST - Arbiter started. Files inspected since last update: reviewer findings and adjusted draft. Decision/blocker: classifying reviewer findings into structural blockers, incremental details, and accepted differences. Next action: finalize execution-readiness verdict.
- 2026-05-24 00:55:17 CEST - Arbiter completed. Files inspected since last update: final plan sections, reviewer findings, and scope guard. Decision/blocker: no structural blocker remains; status set to execution-ready. Next action: controller may execute G4-S1 only.

## Execution Progress

- 2026-05-24 00:56:25 CEST - Contract extraction starting. Files inspected since last update: execution skill, this plan, `Test-Flight-Improv/test-gate-definitions.md`, `git status --short`. Command currently running: none. Decision/blocker: nested agent spawning is not available in this tool session; because this worker is already a fresh isolated execution+QA worker and no child produced partial work, proceeding with the skill's local sequential fallback. Next action: extract exact G4-S1 scope, owner files, tests, gates, done criteria, and scope guard before coding.
- 2026-05-24 00:56:58 CEST - Contract extracted. Files inspected since last update: G4-S1 rows in source matrix and session breakdown, notification route target, active tracker, dedupe gate, route dispatch, app-root route open, show-notification use case, foreground remote-message handler, background fallback, `main.dart` imports/references. Command currently running: none. Decision/blocker: scope is limited to rows G4-005/G4-007/G4-008/G4-009/G4-019 and owner files; required direct tests and gates are explicit; G4-S2 media/send/read/reaction and G4-S3 lifecycle/retry remain out of scope. Next action: inspect owner call sites and add the required RED regressions before implementation.
- 2026-05-24 00:57:09 CEST - Executor pass starting. Files inspected since last update: none. Command currently running: none. Decision/blocker: no blocker; implementation will stay within owner files and preserve dirty worktree changes. Next action: inspect tests and call sites, then add row-local failing regressions.
- 2026-05-24 01:01:35 CEST - RED regression check starting. Files touched since last update: focused notification/push/group tests for G4-005, G4-007, G4-008, G4-009, and G4-019. Command currently running: `flutter test test/core/notifications/notification_route_target_test.dart test/core/notifications/notification_open_dedupe_gate_test.dart test/features/push/application/show_notification_use_case_test.dart test/features/push/application/handle_foreground_remote_message_use_case_test.dart test/features/push/application/background_push_notification_fallback_test.dart`. Decision/blocker: expecting failures because new parser aliases, tracker clear, dedupe API, foreground result, and fallback helper are not implemented yet. Next action: capture red result, then implement production changes.
- 2026-05-24 01:01:57 CEST - RED regression check completed. Files inspected since last update: red test output. Command completed: `flutter test test/core/notifications/notification_route_target_test.dart test/core/notifications/notification_open_dedupe_gate_test.dart test/features/push/application/show_notification_use_case_test.dart test/features/push/application/handle_foreground_remote_message_use_case_test.dart test/features/push/application/background_push_notification_fallback_test.dart` failed as expected. Decision/blocker: failures prove missing `tryBegin`/`finish`/TTL API, group id aliases, `clearIfActive`, foreground result enum, and foreground fallback helper. Next action: implement G4-S1 production seams coherently.
- 2026-05-24 01:02:11 CEST - Implementation starting. Files to touch next: notification route target/dispatch/app-root open, active tracker, dedupe gate, foreground handler, fallback builder, `main.dart`, group and 1:1 wired disposal call sites. Command currently running: none. Decision/blocker: no blocker. Next action: land parser, telemetry, suppression, guarded clear, two-phase dedupe, and foreground fallback changes.
- 2026-05-24 01:05:55 CEST - Implementation completed; structural validation starting. Files touched since last update: `lib/core/notifications/notification_route_target.dart`, `lib/core/notifications/active_conversation_tracker.dart`, `lib/core/notifications/notification_open_dedupe_gate.dart`, `lib/core/notifications/notification_route_dispatch.dart`, `lib/core/notifications/app_root_notification_open.dart`, `lib/features/push/application/show_notification_use_case.dart`, `lib/features/push/application/handle_foreground_remote_message_use_case.dart`, `lib/features/push/application/background_push_notification_fallback.dart`, `lib/features/groups/presentation/screens/group_conversation_wired.dart`, `lib/features/conversation/presentation/screens/conversation_wired.dart`, `lib/main.dart`, focused test files. Command currently running: none. Decision/blocker: caller/callee seams have been landed and formatted. Next action: run required direct tests.
- 2026-05-24 01:06:11 CEST - Direct tests starting. Files inspected/touched since last update: none. Command currently running: focused notification and push `flutter test` suites. Decision/blocker: no blocker. Next action: run required direct tests, then widget tests and named gates.
- 2026-05-24 01:06:33 CEST - Direct notification/push tests completed. Files inspected since last update: test output. Command completed: `flutter test test/core/notifications/notification_route_target_test.dart test/core/notifications/notification_open_dedupe_gate_test.dart test/core/notifications/notification_route_dispatch_test.dart test/core/notifications/app_root_notification_open_test.dart test/features/push/application/show_notification_use_case_test.dart test/features/push/application/handle_foreground_remote_message_use_case_test.dart test/features/push/application/background_push_notification_fallback_test.dart test/features/push/application/chat_and_group_push_open_flow_test.dart` passed. Decision/blocker: no blocker. Next action: run group and 1:1 widget direct tests.
- 2026-05-24 01:07:12 CEST - Group widget direct test completed. Files inspected since last update: test output. Command completed: `flutter test test/features/groups/presentation/group_conversation_wired_test.dart` passed. Decision/blocker: no blocker. Next action: run `ConversationWired` direct test because the 1:1 disposal call site changed.
- 2026-05-24 01:07:42 CEST - Direct widget tests completed; named gates starting. Files inspected since last update: `ConversationWired` test output. Command completed: `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart` passed. Command currently running: `./scripts/run_test_gates.sh groups`. Decision/blocker: no blocker. Next action: run required script gates.
- 2026-05-24 01:08:50 CEST - `groups` named gate completed. Files inspected since last update: gate output. Command completed: `./scripts/run_test_gates.sh groups` failed after running the group test set. Decision/blocker: failure signature is in unrelated already-dirty group membership/invite paths (`Bad state: Stale group membership event` in `add_group_member_use_case.dart`/`remove_group_member_use_case.dart`, plus a `GM-028` expectation in `group_membership_smoke_test.dart`), not in G4-S1 notification routing, active tracker, dedupe, foreground fallback, or owner tests. Next action: run the required `completeness-check` gate, then perform QA with this required-gate failure explicitly classified.
- 2026-05-24 01:09:34 CEST - `completeness-check` named gate completed. Files inspected since last update: gate output, current dirty status, historical gate notes. Command completed: `./scripts/run_test_gates.sh completeness-check` failed with `744/746 test files classified`; unmatched files are `test/shared/fakes/fake_group_pubsub_network_test.dart` and `test/shared/fakes/seeded_group_reproduction_log_test.dart`. Decision/blocker: both files are outside G4-S1 owner scope, clean in git status, and already documented as current completeness residuals in prior Group Chat docs. Next action: run scoped hygiene and the production-change baseline gate, then QA.
- 2026-05-24 01:12:46 CEST - Extra production-change baseline evidence completed. Files inspected since last update: baseline output and scoped diff hygiene output. Command completed: `git diff --check -- <G4-S1 owner paths>` passed with no output. Command completed: `./scripts/run_test_gates.sh baseline` failed at `+90 -7` in `test/features/groups/integration/group_messaging_smoke_test.dart`; visible failure includes `ST-003 fake-network randomized key epoch monotonicity keeps active epoch` expecting no historical key for generation 2. Decision/blocker: baseline failure is in broad group smoke, outside G4-S1 notification/push owner behavior and consistent with the dirty group application residuals seen in `groups`. Next action: run optional broader notification/push suites, then QA.
- 2026-05-24 01:13:18 CEST - Optional broader notification/push suites completed; closure docs starting. Files inspected since last update: optional suite outputs and formatter output. Commands completed: `flutter test test/core/notifications` passed (`+117`); `flutter test test/features/push/application` passed (`+161`); `dart format --set-exit-if-changed <G4-S1 owner Dart files>` passed with `0 changed`. Decision/blocker: G4-S1 notification/push behavior is green beyond the direct test set; broad group gates still have unrelated dirty-worktree residuals. Next action: update only G4-005/G4-007/G4-008/G4-009/G4-019 matrix and breakdown evidence, then run local QA.
- 2026-05-24 01:14:41 CEST - Closure docs completed; QA review starting. Files touched since last update: `group4-critical-findings-2026-05-24-matrix.md`, `group4-critical-findings-2026-05-24-session-breakdown.md`, and this plan. Command currently running: diff/scope inspection. Decision/blocker: no doc-scope blocker; only G4-S1 rows were marked closed. Next action: complete QA review and decide final verdict.
- 2026-05-24 01:16:13 CEST - QA review completed; final verdict writing. Files inspected since last update: scoped diff stats, production notification/push diffs, active tracker call-site diffs, focused test diffs, docs, and final scoped `git diff --check` output. Command completed: `git diff --check -- <G4-S1 owner paths and docs>` passed with no output. Decision/blocker: no G4-S1 blocking issue found; all G4-S1 direct and broader notification/push tests pass, rows are covered, and G4-S2/G4-S3 owner work was not implemented. Broad gate residuals remain classified as unrelated dirty-worktree follow-up because failures are outside G4-S1 notification/push owner behavior and current completeness misses are already documented. Next action: record final verdict.
- 2026-05-24 01:16:13 CEST - Final verdict written. Files touched since last update: this plan. Command currently running: none. Decision/blocker: verdict `accepted_with_explicit_follow_up`; no fix pass required. Next action: hand off final response with changed paths, test results, and classified residuals.

## Final Execution Verdict

- Final verdict: `accepted_with_explicit_follow_up`.
- Spawned-agent isolation used: no nested spawn tool was available in this tool session; this worker proceeded as the fresh isolated execution+QA worker using the skill's local sequential fallback.
- Local sequential fallback used: yes.
- Blocking issues remaining: none for G4-S1.
- Non-blocking follow-ups deferred: clean the unrelated dirty group membership/key-smoke residuals causing `./scripts/run_test_gates.sh groups` and extra `baseline` to fail, and classify the already documented unmatched shared fake tests so `./scripts/run_test_gates.sh completeness-check` returns green.
- Why safe to consider G4-S1 complete: the five scoped rows have row-local code and regression coverage, direct and broader notification/push tests pass, docs were updated only for G4-S1 rows, and broad red gates are outside G4-S1 owner behavior.

## real scope

This session owns only rows G4-005, G4-007, G4-008, G4-009, and G4-019 from `group4-critical-findings-2026-05-24-matrix.md`.

Implement only:

- Group push route parsing aliases for group identifiers and group-message-like payloads.
- A missing-group-id telemetry event for group-message-like pushes that cannot route because no accepted group id field is present.
- Active notification suppression that treats `group:<id>` and `group:<id>|message:<id>` as the same active group while preserving existing 1:1 callers.
- Safe active-route clearing so an older disposed conversation/group screen cannot clear a newer active screen.
- Remote notification-open dedupe that separates in-flight attempts from completed route attempts, expires entries by TTL, and marks completed only after a route attempt succeeds.
- Foreground group-push drain failure signaling and a local fallback notification path when the foreground group drain fails.

Do not implement G4-S2 media/send/read/reaction fixes, G4-S3 lifecycle/retry fixes, database migrations, Go/relay changes, notification permission UX changes, or broad push architecture rewrites.

## closure bar

The session is closed when:

- `NotificationRouteTarget.fromRemoteMessageData` routes group pushes with `groupId`, `group_id`, `gid`, or `conversation_id`; it also routes currently evidenced group-message-like payloads that identify the payload through `type`, `payloadType`, or `kind` without changing `group_invite` behavior.
- Missing group id on a group-message-like foreground/open payload emits a dedicated event rather than only a generic unroutable event.
- Local foreground notification suppression works when the active tracker stores `group:<id>` and the incoming notification uses either `contactPeerId: group:<id>` or `routePayload: group:<id>|message:<id>`.
- `ActiveConversationTracker.clearIfActive(key)` or an equivalent guarded clear is used by group and 1:1 conversation disposal/removal paths.
- Duplicate native/Firebase remote opens are blocked while a first open is in-flight or already completed, but failed route/preparation attempts can be retried.
- Group remote-open dedupe keys include route identity, so the same message id in different groups does not collide.
- Foreground group drain failure produces a notification-needed result and the foreground push listener shows a local fallback notification using the existing notification service/fallback payload contract.

## source of truth

- Active contract: `Test-Flight-Improv/Group-Chat-Feature/group4-critical-findings-2026-05-24-session-breakdown.md`.
- Row-level closure text: `Test-Flight-Improv/Group-Chat-Feature/group4-critical-findings-2026-05-24-matrix.md`.
- Gate authority: `Test-Flight-Improv/test-gate-definitions.md`; if it disagrees with `scripts/run_test_gates.sh`, the script wins.
- Current code and focused tests win over stale prose. If a row is already covered by current code when implementation starts, stop that row at evidence/tests and do not invent changes.

## session classification

implementation-ready

## exact problem statement

Group notification routing and foreground notification safety currently have five correctness gaps:

- G4-005: group push route parsing accepts only `groupId` for `type: group_message`, so payloads with `group_id`, `gid`, `conversation_id`, or group-message identity carried through other current fields can become unroutable.
- G4-007: foreground notification suppression compares raw active keys; a viewed group stored as `group:<id>` can miss an incoming anchored payload such as `group:<id>|message:<id>`.
- G4-008: `ActiveConversationTracker.clear()` clears unconditionally from `GroupConversationWired` and `ConversationWired`, so an old route dispose can erase a newer active route.
- G4-009: `NotificationOpenDedupeGate.shouldRoute()` records a key before route/preparation success; failed route attempts cannot retry, and group dedupe does not include group route identity.
- G4-019: `handleForegroundRemoteMessage` catches group drain errors and only emits telemetry; because foreground remote presentation is quiet in `main.dart`, users may see no notification when the foreground drain fails.

The user-visible improvement is that group push opens and foreground group push notifications remain reliable across payload variants, duplicate native/Firebase opens, active-screen suppression, screen replacement, and foreground drain failure. Existing 1:1 notification behavior, contact-request/intros routing, post push routing, background push fallback behavior, and group invite redirect behavior must stay unchanged.

## owner files

Production owner files:

- `lib/core/notifications/notification_route_target.dart`
- `lib/core/notifications/active_conversation_tracker.dart`
- `lib/core/notifications/notification_open_dedupe_gate.dart`
- `lib/core/notifications/notification_route_dispatch.dart`
- `lib/core/notifications/app_root_notification_open.dart`
- `lib/features/push/application/show_notification_use_case.dart`
- `lib/features/push/application/handle_foreground_remote_message_use_case.dart`
- `lib/features/push/application/background_push_notification_fallback.dart`
- `lib/features/groups/presentation/screens/group_conversation_wired.dart`
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/main.dart`

Test owner files:

- `test/core/notifications/notification_route_target_test.dart`
- `test/core/notifications/notification_route_dispatch_test.dart`
- `test/core/notifications/notification_open_dedupe_gate_test.dart`
- `test/core/notifications/app_root_notification_open_test.dart`
- `test/features/push/application/show_notification_use_case_test.dart`
- `test/features/push/application/handle_foreground_remote_message_use_case_test.dart`
- `test/features/push/application/background_push_notification_fallback_test.dart`
- `test/features/push/application/chat_and_group_push_open_flow_test.dart`
- `test/features/groups/presentation/group_conversation_wired_test.dart`
- `test/features/conversation/presentation/screens/conversation_wired_test.dart` only if the 1:1 guarded-clear call needs widget-level proof beyond tracker unit tests.

Docs to update during implementation closure:

- `Test-Flight-Improv/Group-Chat-Feature/group4-critical-findings-2026-05-24-matrix.md`
- `Test-Flight-Improv/Group-Chat-Feature/group4-critical-findings-2026-05-24-session-breakdown.md`

## files and repos to inspect next

Inspect these before editing because the worktree is already dirty:

- `lib/core/notifications/notification_route_target.dart` for group id extraction and payload parsing.
- `lib/core/notifications/active_conversation_tracker.dart` for normalization and guarded clear.
- `lib/core/notifications/notification_open_dedupe_gate.dart` for in-flight/completed TTL behavior.
- `lib/core/notifications/notification_route_dispatch.dart` and `lib/core/notifications/app_root_notification_open.dart` if a route result helper is needed for success marking.
- `lib/features/push/application/show_notification_use_case.dart` for active suppression normalization.
- `lib/features/push/application/handle_foreground_remote_message_use_case.dart` for result enum and missing-id/drain-failure events.
- `lib/features/push/application/background_push_notification_fallback.dart` to keep fallback payload construction aligned with route parsing aliases.
- `lib/main.dart` for remote-open dedupe wiring and foreground fallback display.
- `lib/features/groups/presentation/screens/group_conversation_wired.dart` and `lib/features/conversation/presentation/screens/conversation_wired.dart` for guarded clear call sites.
- The focused tests listed under owner files.

No other repo is in scope.

## existing tests covering this area

Existing direct tests already cover the baseline contracts:

- `notification_route_target_test.dart` covers `new_message`, `group_message` with `groupId`, payload-only group routes, APNs/FCM-shaped group payloads, group message anchors, group invite to intros, and empty `groupId` rejection.
- `notification_route_dispatch_test.dart` covers remote open preparation before route handoff, missing remote route fallback, and local group payload routing.
- `notification_open_dedupe_gate_test.dart` covers current message-id and FCM-id dedupe, but it also documents the problematic mark-on-check API.
- `show_notification_use_case_test.dart` covers local notification suppression for active 1:1 and basic active group `contactPeerId: group:<id>`.
- `handle_foreground_remote_message_use_case_test.dart` covers targeted group foreground drain, unroutable post/unknown payloads, empty group id behavior, payload-only group fallback, and current swallowed drain errors.
- `background_push_notification_fallback_test.dart` covers group fallback payload construction and protected preview defaults.
- `chat_and_group_push_open_flow_test.dart` covers preparation-before-route sequencing for background/terminated group opens.
- `group_conversation_wired_test.dart` covers current active tracker set/clear, but not stale-route guarded clear.

Missing coverage is exactly the five row gaps: group id aliases and alternate group-message identity fields, normalized active suppression for anchored group payloads, guarded clear, route-success dedupe semantics with retry after failure and route-identity group keys, and foreground group drain failure fallback display.

## regression/tests to add first

Add failing tests before implementation, in this order:

1. G4-005 route parsing:
   - `notification_route_target_test.dart`: table test for `group_id`, `gid`, and `conversation_id` resolving to group route with `message_id`.
   - `notification_route_target_test.dart`: table test for group-message-like payloads where `payloadType: group_message` or `kind` identifies the payload while `group_id` is used for the group id. Keep `group_invite` mapped to intros.
   - `handle_foreground_remote_message_use_case_test.dart`: missing group id on a group-message-like payload emits the dedicated missing-id event and does not drain.
   - `notification_route_dispatch_test.dart` or `app_root_notification_open_test.dart`: remote-open group-message-like payload without any accepted group id emits the same missing-id event before falling back to the missing-route handler.
   - `background_push_notification_fallback_test.dart`: fallback payload construction uses the same aliases.

2. G4-007 active suppression:
   - `show_notification_use_case_test.dart`: active `group:group-123` suppresses when `contactPeerId` is `group:group-123` and `routePayload` is `group:group-123|message:msg-123`.
   - `show_notification_use_case_test.dart`: active `group:group-123` suppresses when the caller only supplies anchored group payload but leaves `contactPeerId` compatible with existing call sites. Preserve 1:1 tests.

3. G4-008 guarded clear:
   - Tracker unit test: `clearIfActive('peer-123')` clears only matching keys and leaves newer keys intact.
   - `group_conversation_wired_test.dart`: if a newer active group key is set before an old group screen disposes or handles removal, the newer key remains active.
   - Add a 1:1 widget test only if the tracker unit test does not prove `ConversationWired` uses the guarded method.

4. G4-009 dedupe semantics:
   - `notification_open_dedupe_gate_test.dart`: `begin`/`tryBegin` blocks a duplicate while in-flight.
   - `notification_open_dedupe_gate_test.dart`: failed finish clears in-flight without marking completed, so the next attempt can begin.
   - `notification_open_dedupe_gate_test.dart`: successful finish blocks duplicate until TTL/entry expiry.
   - `notification_open_dedupe_gate_test.dart`: group dedupe key includes route identity, so same `message_id` in different `groupId` values can route independently.
   - `app_root_notification_open_test.dart` or a focused main-route helper test: a preparation/routing failure does not mark the remote-open key completed, and a following duplicate attempt can retry.
   - Add a small route/open flow test if a new route-result helper is introduced.

5. G4-019 foreground fallback:
   - `handle_foreground_remote_message_use_case_test.dart`: group drain failure returns a result such as `notificationNeeded` while preserving telemetry.
   - `handle_foreground_remote_message_use_case_test.dart`: 1:1 drain failures preserve existing behavior unless explicitly changed by the row.
   - Add/extend a focused push application test for the foreground fallback display helper used by `main.dart`: when the use case returns notification-needed, the helper calls `NotificationService.showNotification` with the existing fallback title/body/payload contract.

## step-by-step implementation plan

1. Re-read all owner files and direct tests from this plan. Run or note a pre-change focused baseline only if the implementer needs to distinguish current dirty-worktree failures from new failures.

2. Implement G4-005 in `notification_route_target.dart`:
   - Add private helpers for group-message-like detection and group id extraction.
   - Accept `groupId`, `group_id`, `gid`, and `conversation_id`, trimming whitespace and preserving current null-on-empty behavior.
   - Treat a payload as group-message-like only when current fields explicitly identify it as a group message, such as `type: group_message`, `payloadType: group_message`, or an evidenced group replay kind paired with group-message payload identity.
   - Keep `group_invite` routed to intros and keep posts/contact/intros behavior unchanged.
   - Reuse the same parsing through background fallback because it already calls `NotificationRouteTarget.fromRemoteMessageData`.

3. Add missing-id telemetry at the push handling boundary:
   - Keep `NotificationRouteTarget` a pure parser.
   - In foreground handling and, if needed, remote-open dispatch, detect group-message-like payloads that fail solely because accepted group id fields are missing.
   - Emit a dedicated event such as `PUSH_GROUP_ROUTE_MISSING_GROUP_ID` with only non-sensitive metadata (`type`, keys, and which id aliases were present as booleans). Do not include group names, message text, ciphertext, nonce, or sender display names.

4. Implement G4-007 in active suppression:
   - Add key normalization either in `ActiveConversationTracker` or a small notification helper. Normalize `group:<id>|message:<messageId>` to active key `group:<id>`.
   - Keep 1:1 keys unchanged.
   - Update `maybeShowNotification` to check the normalized contact key and, when present, the normalized route payload key.
   - Preserve existing caller compatibility: current callers passing `contactPeerId: group:<id>` or a raw peer id still work.

5. Implement G4-008 guarded clear:
   - Add `clearIfActive(String key)` to `ActiveConversationTracker`.
   - Replace unconditional tracker clears in `GroupConversationWired.dispose`, `_handleCurrentGroupRemoved`, and `ConversationWired.dispose` with guarded clears using the route key that screen set active with.
   - Do not implement G4-017 group-change state reset in this session. If `didUpdateWidget` exposes an active-key mismatch, add only the minimum active-key refresh needed for this tracker contract and document any broader reset as out of scope.

6. Implement G4-009 dedupe:
   - Replace `shouldRoute(data)` as the main remote-open API with a two-phase API, for example `tryBegin(data)`, `markCompleted(data)`/`finish(success: true)`, and `finish(success: false)` or equivalent.
   - Track in-flight and completed keys separately with TTLs and the existing `maxEntries` bound. Use injectable time in tests.
   - Include route identity in keys when routable: group keys should include normalized group route payload and message id when available; 1:1 keys should include route peer/message identity where available; FCM id remains a fallback when route identity is unavailable.
   - In `main.dart`, begin before routing, mark completed only after the remote-open route path reports success, and clear in-flight without marking completed if preparation/routing throws or reports failure.
   - If current route helpers cannot express route success, add a narrow result-returning helper for remote opens rather than changing local notification routing broadly.

7. Implement G4-019 foreground fallback:
   - Change `handleForegroundRemoteMessage` from `Future<void>` to a small result enum/class.
   - On successful drains return `drained`; on unroutable returns `unroutable`; on group drain failure emit existing error telemetry and return `notificationNeeded` or equivalent. Keep 1:1 failure behavior unchanged unless tests prove a shared result is safer.
   - In `_setupPushListeners` in `main.dart`, await the result in the unawaited task and, when the result requests fallback, build a local fallback from the existing background fallback contract and call `widget.notificationService.showNotification`.
   - Catch and log fallback display errors so a notification plugin failure does not crash the foreground listener.

8. Update direct tests as each row is implemented. Keep failures row-local and avoid broad golden/widget rewrites.

9. After code passes, update the matrix and breakdown rows for G4-005, G4-007, G4-008, G4-009, and G4-019 with concise closure evidence and direct gate results. Do not mark unrelated rows closed.

## risks and edge cases

- Duplicate native/Firebase opens can arrive almost simultaneously; in-flight dedupe must block the second attempt without permanently suppressing the first attempt if it fails.
- Group message ids may be globally unique today but should not be assumed; group route identity must prevent cross-group collisions.
- Missing group id telemetry must not leak sensitive payload content.
- Foreground presentation is intentionally quiet in `main.dart`; fallback display on group drain failure must be explicit.
- Active tracker normalization must not cause a group route key to suppress a 1:1 peer id that happens to contain similar text.
- Guarded clear must not leave stale active keys after normal route disposal.
- `group_invite` must continue routing to intros, not group conversation.
- Existing background push fallback duplicate suppression and protected preview rules must remain unchanged.

## exact tests and gates to run

Run focused direct tests first:

```bash
flutter test test/core/notifications/notification_route_target_test.dart
flutter test test/core/notifications/notification_open_dedupe_gate_test.dart
flutter test test/core/notifications/notification_route_dispatch_test.dart
flutter test test/core/notifications/app_root_notification_open_test.dart
flutter test test/features/push/application/show_notification_use_case_test.dart
flutter test test/features/push/application/handle_foreground_remote_message_use_case_test.dart
flutter test test/features/push/application/background_push_notification_fallback_test.dart
flutter test test/features/push/application/chat_and_group_push_open_flow_test.dart
flutter test test/features/groups/presentation/group_conversation_wired_test.dart
```

If `ConversationWired` receives a guarded-clear widget proof, also run:

```bash
flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart
```

Run script-backed gates:

```bash
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh completeness-check
```

Optional broader confidence if the route helper/dedupe changes touch shared notification routing beyond the focused files:

```bash
flutter test test/core/notifications
flutter test test/features/push/application
```

## known-failure interpretation

- The worktree is already dirty across many Flutter, Go, relay, iOS, Android, and test files. Treat any failure in already-modified unrelated files as pre-existing only if it can be reproduced before implementation or its failure signature is unchanged after the session patch.
- Do not classify old red tests as new regressions unless this session changed the failing module or the failure appears only after this session's patch.
- `Test-Flight-Improv/test-gate-definitions.md` documents older known failures for some posts integration tests and device-specific gate behavior; those are not expected to be exercised by this session.
- If `./scripts/run_test_gates.sh groups` needs a device in the local environment, set `FLUTTER_DEVICE_ID=<device-id>` as the gate definitions describe. Direct host tests should still run without simulator setup.

## done criteria

- All five scoped rows have tests that fail before the corresponding implementation and pass afterward, or the implementer records proof that current code already covers a row and no code change was needed.
- All production changes are limited to the owner files or a narrowly justified new push helper file.
- Direct focused tests listed above pass, except any documented pre-existing dirty-worktree failure.
- `./scripts/run_test_gates.sh groups` and `./scripts/run_test_gates.sh completeness-check` pass or have documented pre-existing/environment failures with unchanged signatures.
- Source matrix and session breakdown are updated only for G4-005, G4-007, G4-008, G4-009, and G4-019 with closure evidence.
- No database migration, Go/relay behavior, group media/send state, reaction behavior, read receipt behavior, or notification permission behavior is changed.

## scope guard

Non-goals:

- Do not touch G4-001, G4-002, G4-003, G4-004, G4-006, or G4-010 through G4-020 except G4-019.
- Do not refactor the whole notification stack, app root navigator, or push listener lifecycle.
- Do not add schema leases, inbox replay redesign, group recovery ack changes, media validation, MIME policy changes, read receipt gating, or reaction rollback.
- Do not broaden group-message type recognition to fuzzy substring matching. Use exact, evidenced fields and exact literals only.
- Do not change local notification copy, protected preview policy, notification permissions, APNs project settings, or remote foreground presentation settings.
- Do not revert or clean up user-owned dirty worktree changes.

Overengineering indicators:

- Adding a new notification router framework instead of a small parser/tracker/dedupe/result change.
- Making all route handlers return rich navigation state when only remote-open success marking needs a narrow result.
- Adding storage-backed dedupe or database state for this in-process notification-open gate.
- Turning foreground fallback into a full retry scheduler.

## accepted differences / intentionally out of scope

- 1:1 foreground drain failure behavior can remain as-is unless the minimal result enum requires a shared status; G4-019 closes only the group foreground drain fallback gap.
- Group invite pushes remain intros routes rather than group conversation routes.
- Background push fallback behavior remains separate from foreground drain failure fallback; this session may reuse its payload/title/body builder but should not redesign background delivery.
- Dedupe TTL values can be conservative and process-local; cross-restart notification-open dedupe is out of scope.
- G4-017 full group-change reset/re-subscribe/reload is explicitly deferred to G4-S2 even though `GroupConversationWired` is an owner file here.

## dependency impact

- G4-S1 has no prerequisite sessions, but later notification-open and group push reliability work should use the parser aliases, active key normalization, and two-phase dedupe semantics established here.
- G4-S2 also edits `GroupConversationWired`; if G4-S1 is not closed first, G4-S2 should avoid tracker/dispose behavior or rebase on the guarded-clear contract.
- If the route-result approach changes `notification_route_dispatch.dart`, subsequent notification tap/open work must use the new success-marking helper rather than the legacy mark-on-check pattern.
- If implementation proves a row is already covered, keep the matrix row evidence-only and do not create follow-on work without a concrete failing test.

## dirty-worktree caution

`git status --short` shows a heavily dirty repository, including modified production and test files under `lib/`, `test/`, Go modules, relay server, iOS, Android, and untracked Group Chat planning docs. The implementer must:

- inspect each owner file immediately before editing,
- avoid reverting or formatting unrelated user-owned changes,
- keep the patch scoped to this session's owner files,
- preserve any unrelated dirty hunks in files that must be touched,
- report any unavoidable overlap rather than resetting the worktree.

## reviewer findings

- Verdict: sufficient with adjustments.
- Missing files/tests/gates: no missing owner file or named gate after adding explicit remote-open missing-id telemetry proof and route-failure retry proof.
- Stale or incorrect assumptions: none found. The plan correctly treats current code/tests as authoritative and preserves `group_invite` to intros.
- Overengineering risk: controlled by the scope guard. The plan allows a narrow route-result helper only where success marking needs it.
- Decomposition: sufficient. The five rows share notification routing/tracker/dedupe/fallback seams and are still bounded enough for one implementation session.
- Minimum needed for sufficiency: keep the regression-first order and do not begin G4-S2/G4-S3 work from `GroupConversationWired`.

## arbiter decision

- Final verdict: execution-ready for G4-S1 only.
- Structural blockers remaining: none.
- Incremental details intentionally deferred:
  - Exact group-message-like alternate literals beyond `type`, `payloadType`, and evidenced `kind` values should be added only if the implementer finds a concrete current producer or failing fixture.
  - The 1:1 `ConversationWired` widget-level guarded-clear test is optional if tracker unit coverage plus call-site inspection proves the behavior.
  - Broader `flutter test test/core/notifications` and `flutter test test/features/push/application` runs are optional confidence after the required focused tests and gates.
- Accepted differences intentionally left unchanged:
  - 1:1 foreground drain failure behavior may remain unchanged; G4-019 closes the group foreground fallback gap.
  - `group_invite` remains routed to intros.
  - Remote-open dedupe remains process-local and TTL-based; cross-restart dedupe is out of scope.
  - G4-S2/G4-S3 group conversation lifecycle/media/send work remains out of scope even where files overlap.
- Why safe to implement now: the plan has explicit real scope, owner files, regression-first tests, exact gates, dirty-worktree caution, done criteria, and a stop rule that prevents expanding into adjacent group chat findings.
