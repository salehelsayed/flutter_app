# Session 17 Plan: Profile ConversationWired Subscription Cost And Trim Only If Measured

**Date:** 2026-03-26
**Status:** Plan only

## 1. real scope

Confirm whether `ConversationWired` keeps enough active subscription or recording-related cost during open, idle, background, foreground, or hidden-route states to justify a narrow refactor.

Current repo evidence says this is a candidate, not a confirmed regression:
- `Test-Flight-Improv/04-ui-performance.md` marks ConversationWired as a profile-gated item and explicitly says pause/resume lifecycle complexity should not be added without evidence.
- `lib/features/conversation/presentation/screens/conversation_wired.dart` creates `_incomingSubscription`, `_repoChangeSubscription`, `_contactUpdateSubscription`, and `_reactionSubscription` during `initState()` and cancels them in `dispose()`.
- The same file only creates `_durationSub` and `_amplitudeSub` inside `_onRecordStart()`, and cancels them in `_onRecordStop()`, `_onRecordCancel()`, and `dispose()`, so recorder subscriptions already appear scoped to active recording.
- The file does not implement `WidgetsBindingObserver` or `didChangeAppLifecycleState`, so the route does not currently own explicit pause/resume subscription management.

In scope:
- measure whether visible or off-screen subscription churn is real
- measure whether recorder-related streams are already acceptably scoped
- only if evidence justifies it, plan the smallest subscription ownership or cancellation cleanup

Out of scope:
- redesigning conversation architecture
- broad send/retry/reconnect changes without measured route evidence
- feed inline reply durability or other Session 3 work
- transport failover or startup hardening unless the chosen fix truly expands into shared lifecycle recovery behavior

## 2. session classification

`profile-gated`

Why:
- the roadmap defines this as a profiling session
- `04-ui-performance.md` says the route already scopes/cancels subscriptions responsibly on inspection
- the current tree has strong correctness and lifecycle tests, but no dedicated open / idle / background / foreground performance harness for `ConversationWired`

## 3. files and repos to inspect next

Primary code:
- `lib/features/conversation/presentation/screens/conversation_wired.dart`
- `lib/features/conversation/application/chat_message_listener.dart`
- `lib/features/conversation/application/reaction_listener.dart`
- `lib/core/media/audio_recorder_service.dart`
- `lib/core/notifications/active_conversation_tracker.dart` if hidden-route evidence points at visibility semantics or notification suppression rather than raw subscription cost

Primary tests already tied to this route or its lifecycle:
- `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `test/features/conversation/presentation/screens/conversation_wired_bg_task_test.dart`
- `test/features/conversation/presentation/screens/conversation_wired_sending_to_failed_test.dart`
- `test/features/conversation/integration/send_then_lock_delivery_test.dart`
- `test/core/lifecycle/handle_app_resumed_upload_ordering_test.dart`
- `test/core/lifecycle/handle_app_resumed_stuck_sending_test.dart`
- `test/core/lifecycle/background_reconnect_smoke_test.dart`

Reference harness patterns to reuse:
- `integration_test/feed_wired_init_performance_test.dart`
- `integration_test/orbit_performance_test.dart`
- `integration_test/feed_performance_test.dart`

Useful adjacent context if the profile data points at shared listener behavior:
- `Test-Flight-Improv/08-network-1to1-messaging.md`
- `Test-Flight-Improv/14-regression-test-strategy.md`

## 4. existing tests covering this area

Useful current coverage:
- `conversation_wired_test.dart` already covers initial load, optimistic send, upload state, quote reply flows, and a narrow rendering-proof test: `recording ticks update composer without rebuilding header or message list`
- `conversation_wired_bg_task_test.dart` already protects background-task ordering for text send, media upload, and voice send paths
- `conversation_wired_sending_to_failed_test.dart` already proves repository-driven `sending -> failed` UI refresh behavior
- `send_then_lock_delivery_test.dart` already covers real conversation send paths under pause/resume interruption and includes a reusable `pumpConversationWired(...)` helper pattern
- the lifecycle tests under `test/core/lifecycle/` already cover `handleAppResumed(...)` ordering and reconnect behavior

What is still missing:
- no existing route-open / idle / hidden-route / background / foreground perf harness for `ConversationWired`
- no existing trace that answers whether screen-level subscriptions create meaningful cost while the route is no longer visible
- no existing trace that ranks `_incomingSubscription`, `_repoChangeSubscription`, `_contactUpdateSubscription`, `_reactionSubscription`, `_durationSub`, or `_amplitudeSub` by actual impact

## 5. regressions/tests to add first, if any

Default answer: none.

If Session 17 stays measurement-only, do not add a regression first.

If evidence justifies a production change, add the smallest lifecycle regression at the layer actually touched:
- if the change is route-local subscription cancellation or visibility scoping, extend `test/features/conversation/presentation/screens/conversation_wired_test.dart`
- if the change affects send interruption or resume behavior, extend `test/features/conversation/integration/send_then_lock_delivery_test.dart`
- if the change touches `handleAppResumed(...)` ordering or reconnect behavior, extend the relevant `test/core/lifecycle/*` test first

The first regression should protect only the changed lifecycle contract:
- dispose / hidden-route subscription behavior
- active recording start / stop / cancel subscription behavior
- background / foreground transitions only if the implementation actually changes them

## 6. evidence to capture first, if the session is profile-gated or evidence-gated

Capture this before any production edit:
- route-open frame timing for `ConversationWired`
- idle-visible frame timing with no new events
- hidden-route or no-longer-visible behavior after another route covers or replaces the conversation route
- background / foreground traces for the conversation route if the chosen target can support them credibly
- event counts and timestamps for:
  - `_incomingSubscription`
  - `_repoChangeSubscription`
  - `_contactUpdateSubscription`
  - `_reactionSubscription`
  - `_durationSub`
  - `_amplitudeSub`
- whether recorder subscriptions are absent before recording, present only during active recording, and gone again after stop / cancel
- whether any work continues after the route is no longer visible
- whether any observed cost is build churn, message-list churn, recorder stream churn, or shared listener-side work outside the screen itself

Current repo evidence says a temporary harness is required:
- `rg` across `integration_test/`, `test/features/conversation/`, and `test/core/lifecycle/` shows no existing conversation performance harness using `watchPerformance(...)` or `traceAction(...)`
- the current tests prove correctness and some rebuild isolation, but not route lifecycle cost
- `send_then_lock_delivery_test.dart` provides a good `ConversationWired` mount pattern, but it is not a performance trace harness

## 7. step-by-step implementation or evidence-collection plan

1. Reconfirm the route-local subscription model in `conversation_wired.dart`.
2. Treat recorder subscriptions separately from the always-mounted screen subscriptions, because the current code already scopes `_durationSub` and `_amplitudeSub` to active recording only.
3. Build a temporary profile harness for `ConversationWired`, preferably under `integration_test/`, because no existing open / idle / background / foreground harness exists.
4. Reuse the harness style from `integration_test/feed_wired_init_performance_test.dart` and `integration_test/orbit_performance_test.dart` for `watchPerformance(...)`, `traceAction(...)`, and `binding.reportData`.
5. Reuse the smaller `pumpConversationWired(...)` setup pattern from `send_then_lock_delivery_test.dart` instead of inventing a full app shell.
6. Add temporary wrapper or spy inputs around the message, reaction, and recorder streams so the harness can timestamp callback activity without changing production code first.
7. Use a reproducible command shape for the temporary harness, following the repo's existing integration driver pattern:

```bash
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/<conversation_perf_harness>.dart \
  -d <device> \
  --profile
```

8. Capture at least these scenarios on the same target:
- conversation route open and settle
- idle visible route with no incoming events
- visible route while synthetic incoming message and reaction events arrive
- active recording window with duration and amplitude emissions
- hidden or covered route after another screen is pushed above it
- background / foreground transition if the target supports meaningful profile evidence; if not, simulate lifecycle state in the harness and document that limitation explicitly
9. Answer the key questions explicitly:
- do the always-mounted screen subscriptions produce meaningful route cost while visible
- do they continue to matter after the route is hidden or disposed
- are recorder subscriptions already scoped only during active recording
- is any observed cost local to the screen, or actually coming from shared listener or lifecycle code outside the screen
10. If the evidence says current behavior is acceptable, stop with no production change.
11. If the evidence shows real off-screen churn or route-specific jank, add one focused regression first, then make the smallest route-local cleanup.
12. Only if the smallest viable cleanup necessarily touches shared pause/resume or reconnect behavior should this session widen into lifecycle recovery code.

## 8. risks and edge cases

- `ConversationWired` has multiple subscriptions, but static inspection alone does not prove they are expensive.
- Hidden-route cost is not the same as disposed-route cost. The harness must distinguish those states.
- Message or reaction event handling may look like route subscription cost even when the real work lives in `ChatMessageListener` or `ReactionListener`.
- Recorder streams are already scoped to active recording by inspection, so refactoring them without evidence is likely wasted motion.
- Simulated lifecycle state changes are weaker evidence than true mobile backgrounding on a physical device.
- `conversation_wired_test.dart` already proves recording updates do not rebuild the header or message list, so Session 17 must avoid rediscovering only that narrow fact and mistaking it for a full route-performance answer.
- If the route is acceptable, the correct outcome is no code change.

## 9. exact tests to run after implementation, if code changes occur

If no production code changes occur:
- run the temporary `ConversationWired` profile harness on the chosen target
- do not run Baseline or named gates just for profiling-only work

If production code changes occur, run:
- `flutter test test/features/conversation/presentation/screens/conversation_wired_test.dart`
- `flutter test test/features/conversation/presentation/screens/conversation_wired_bg_task_test.dart`
- `flutter test test/features/conversation/presentation/screens/conversation_wired_sending_to_failed_test.dart`
- `flutter test test/features/conversation/integration/send_then_lock_delivery_test.dart`
- `flutter test test/core/lifecycle`
- if `chat_message_listener.dart` changes, rerun `flutter test test/features/conversation/application/chat_message_listener_test.dart`
- if `reaction_listener.dart` changes, rerun `flutter test test/features/conversation/application/reaction_listener_test.dart`
- rerun the temporary `ConversationWired` profile harness on the same target used for the before evidence

## 10. subsystem gate(s), if relevant

`1:1 Reliability Gate` if production code changes touch conversation listener ownership, send behavior, retry behavior, or lifecycle behavior that can affect 1:1 messaging correctness.

Canonical gate from `Test-Flight-Improv/14-regression-test-strategy.md`:
```bash
flutter test \
  test/features/conversation/integration/two_user_message_exchange_test.dart \
  test/features/conversation/integration/offline_inbox_roundtrip_test.dart \
  test/features/conversation/integration/media_attachment_flow_test.dart \
  test/features/conversation/integration/media_retry_smoke_test.dart \
  test/features/conversation/integration/voice_message_exchange_test.dart \
  test/features/conversation/integration/incomplete_upload_recovery_test.dart \
  test/features/conversation/integration/send_then_lock_delivery_test.dart \
  test/features/conversation/integration/stuck_sending_recovery_test.dart \
  test/features/conversation/integration/quote_reply_thread_test.dart
```

For pure profiling with no production change:
- no named subsystem gate is required beyond the direct evidence run

## 11. whether Baseline Gate is required

Optional / not required for pure profiling.

Required if any Flutter production code changes land.

Reason:
- the roadmap explicitly treats Session 17 as profile-first
- Baseline Gate is only needed once the session turns into a real Flutter code change

## 12. whether Startup / Transport Gate is required

Not by default.

Run the `Startup / Transport Gate` only if the chosen fix actually changes shared pause / resume, reconnect, offline inbox drain, or other startup/transport recovery behavior outside the screen itself.

Reason:
- current Session 17 scope is route-local subscription cost
- `mobile-network-resilience-qa` is not needed for the planning baseline, because this session is not primarily validating transport failover or device-backed recovery correctness
- that skill only becomes relevant if evidence forces a real transport or lifecycle-recovery change and the execution session must validate those behaviors on device

## 13. done criteria

Session 17 is complete when one of these is true:
- the profile evidence shows the current `ConversationWired` subscription model is acceptable, and the session stops with no production change
- the profile evidence shows a real off-screen or lifecycle cost, one narrow cleanup lands, and before/after evidence shows improvement without breaking conversation behavior

And all of these are true:
- the session answers whether recorder subscriptions are already acceptably scoped to active recording
- the session answers whether any meaningful cost remains after the route is hidden or no longer visible
- no shared 1:1 lifecycle behavior regresses if a cleanup lands
- the session stays narrow and does not turn into a broad conversation architecture rewrite

## 14. dependency impact on later sessions if this session blocks

- later sessions do not need to stop if Session 17 remains unresolved
- Session 18 and later DB/storage follow-ups can still proceed independently
- what must not happen is speculation: later work must not assume `ConversationWired` needs subscription refactoring until Session 17 captures evidence
- if the only blocker is lack of a good route harness, that should remain local to Session 17 rather than expanding into a larger observability project

## 15. scope guard

- Do not refactor subscriptions from inspection alone.
- Do not add pause/resume lifecycle complexity just because multiple subscriptions exist.
- Do not treat the existing `recording ticks do not rebuild header or message list` test as a full performance answer.
- Do not widen into shared transport or inbox recovery unless the measured hotspot truly lives there.
- Do not invoke `mobile-network-resilience-qa` unless the implementation actually changes device-backed recovery or transport behavior.
- If the evidence says the route is already acceptable, stop there.
