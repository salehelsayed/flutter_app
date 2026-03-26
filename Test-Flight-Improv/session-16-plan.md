# Session 16 Plan: Profile FeedWired Init Churn And Batch Only If Measured

**Date:** 2026-03-26
**Status:** Plan only

## 1. real scope

Confirm whether `FeedWired` init actually causes meaningful first-route churn before touching batching or sequencing.

The current init path in `lib/features/feed/presentation/screens/feed_wired.dart` still kicks off these async calls immediately from `initState()`:
- `_loadIdentity()`
- `_loadQualityPreference()`
- `_loadVideoQualityPreference()`
- `_loadFeedFromDatabase()`
- `_loadTotalUnreadCount()`

Current repo evidence says this is still a candidate, not a proven regression:
- `Test-Flight-Improv/04-ui-performance.md` calls FeedWired init churn real but small, and explicitly says to batch only if profile evidence justifies it
- `_loadIdentity()`, `_loadQualityPreference()`, and `_loadVideoQualityPreference()` each call `setState(...)`
- `_loadFeedFromDatabase()` mutates `_feedStore`, calls `_markFeedLoaded()`, and can trigger initial feed-visible state changes
- `_loadTotalUnreadCount()` updates `_totalUnreadCountNotifier`, so it can change visible UI without being another `setState(...)`

Scope is narrow:
- measure first-route behavior
- determine whether Session 9 identity caching already removed most of the visible churn
- only if evidence is strong, plan a small batching / sequencing cleanup in `FeedWired`

Out of scope:
- redesigning feed state management
- durable-send, reply, unread, or route behavior refactors unrelated to init churn
- DB schema or repository persistence changes
- startup / transport / resume resilience work

## 2. session classification

`profile-gated`

Why:
- `Test-Flight-Improv/04-ui-performance.md` marks this as a profile-first decision, not an implementation-ready bug
- the current tree has feed behavior tests and a `FeedScreen` perf harness, but no `FeedWired` init-phase perf harness
- Session 9 identity caching appears to have landed in `lib/features/identity/domain/repositories/identity_repository_impl.dart`, so part of the original suspicion may already be stale in practice

## 3. files and repos to inspect next

Primary code:
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/features/feed/application/load_feed_use_case.dart`
- `lib/features/feed/application/app_shell_controller.dart`
- `lib/features/settings/application/image_quality_preference_use_cases.dart`
- `lib/features/identity/domain/repositories/identity_repository_impl.dart`
- `lib/features/identity/presentation/startup_router.dart`
- `lib/features/identity/application/startup_decision.dart`
- `lib/features/feed/presentation/screens/feed_screen.dart` only as needed to confirm how `feedLoaded`, `feedItemsListenable`, and `totalUnreadCountListenable` become visible work

Primary tests and harness patterns:
- `integration_test/feed_performance_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`
- `test/features/feed/presentation/screens/feed_wired_bg_task_test.dart`
- `test/features/feed/integration/feed_card_flow_test.dart`
- `test/features/feed/integration/expanded_collapsed_card_test.dart`
- `test/features/feed/integration/feed_color_smoke_test.dart`
- `test/features/identity/domain/repositories/identity_repository_impl_test.dart`
- `Test-Flight-Improv/session-9-plan.md` for the identity-cache prerequisite question

Production mount-path context:
- `StartupRouter` calls `decideStartupRoute(...)` before opening `FeedWired`
- `decideStartupRoute(...)` calls `identityRepo.loadIdentity()` first, so the normal `hasIdentityWithContacts` production path may already warm the Session 9 identity cache before `FeedWired` mounts

## 4. existing tests covering this area

Useful current coverage:
- `test/features/feed/presentation/screens/feed_wired_test.dart` already proves identity load, image quality preference load, video quality preference load, feed refresh behavior, and orbit-return refresh behavior
- `test/features/feed/presentation/screens/feed_wired_bg_task_test.dart` is not about init churn, but it covers another sensitive path in the same file and should be rerun if `FeedWired` changes
- the feed integration tests under `test/features/feed/integration/` protect visible feed card behavior
- `integration_test/feed_performance_test.dart` already shows the repo's `FrameTiming` pattern
- `test/features/identity/domain/repositories/identity_repository_impl_test.dart` already proves Session 9 cache behavior for repeated null loads and repeated identity loads, so execution can treat identity caching as present and measure its visible effect rather than re-proving its correctness

What is missing:
- no existing test or harness counts init-phase completions inside `FeedWired`
- no existing profile trace isolates first-route open for `FeedWired`
- `integration_test/feed_performance_test.dart` measures `FeedScreen` scroll / expand / swipe / compose, not `FeedWired` init sequencing

## 5. regressions/tests to add first, if any

Default answer: none.

If Session 16 stays measurement-only, do not add a regression first.

If evidence justifies production code changes, add one focused regression at the `FeedWired` widget layer before changing behavior. That regression should protect:
- initial loading behavior
- first visible feed state
- non-regression of unread badge state
- non-regression of reply / expanded-card / route state that existing `FeedWired` tests already cover

Keep that regression narrow. Do not turn this into a broad feed refactor test sweep.

## 6. evidence to capture first, if the session is profile-gated or evidence-gated

Capture this before any production edit:
- first-route frame timing for `FeedWired` from initial mount to settled state
- a timeline trace that covers the init window, not just steady-state feed interaction
- the number and timing of init-phase completions for:
  - `_loadIdentity()`
  - `_loadQualityPreference()`
  - `_loadVideoQualityPreference()`
  - `_loadFeedFromDatabase()`
  - `_loadTotalUnreadCount()`
- whether those completions actually produce separate visible frames or whether Flutter coalesces most of them already
- whether `loadFeed(...)` work is the dominant cost instead of the state-update count
- whether Session 9 identity caching already removes most identity-related visible churn

Because current repo evidence is insufficient to answer that directly:
- `integration_test/feed_performance_test.dart` is reusable as a pattern, but not as the actual Session 16 harness
- `FeedWired` has no existing init-phase counters or debug hooks
- execution will likely need a small temporary `FeedWired` init perf harness and may need tiny profile-only instrumentation or debug callbacks if plain frame timing cannot attribute the five init paths clearly enough

Minimum evidence scenarios:
- cold-ish path with a fresh `IdentityRepositoryImpl` instance
- warm identity path modeled on the real startup flow where `StartupRouter` has already called `decideStartupRoute(...)`, and that decision path has already satisfied `identityRepo.loadIdentity()` before `FeedWired` mounts

## 7. step-by-step implementation or evidence-collection plan

1. Reconfirm the current init call graph in `feed_wired.dart` and note exactly which paths call `setState(...)`, which paths update listenables, and which path controls `feedLoaded`.
2. Reconfirm the real production mount path through `StartupRouter` and `decideStartupRoute(...)` so the session measures a true warm-identity case, not an invented one.
3. Treat Session 9 as a real prerequisite check, not a guess. `IdentityRepositoryImpl` currently has `_cachedIdentity` and `_hasCachedIdentity`, and `identity_repository_impl_test.dart` already proves repeated-load caching behavior, so the execution session must explicitly measure whether that already removes part of the suspected churn.
4. Prefer wrapped dependencies and existing spy patterns before production instrumentation. Reuse or adapt the timing/counting style already present in `feed_wired_test.dart` spies and the counting wrapper style from `identity_repository_impl_test.dart` to timestamp init completions for `_loadIdentity()`, `_loadFeedFromDatabase()`, and `_loadTotalUnreadCount()` where possible.
5. Reuse the `IntegrationTestWidgetsFlutterBinding` and `FrameTiming` collection style from `integration_test/feed_performance_test.dart`.
6. Create a small temporary harness dedicated to `FeedWired` init, not `FeedScreen` interaction.
7. Prefer fake or in-memory dependencies that keep the flow deterministic while still exercising the real `FeedWired` init logic.
8. Make the harness record:
- route-open frame timings
- route-settled frame timings
- ordered timestamps for each init dependency completion
9. Use a reproducible command shape for the temporary harness, following the repo's existing integration driver pattern:

```bash
flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/<feed_init_perf_harness>.dart \
  -d <device> \
  --profile
```

10. If dependency-level timestamps still do not answer whether UI updates are arriving as separate visible churn, add the smallest temporary profile-only instrumentation needed in `FeedWired` to mark init-phase UI update points. Do not add permanent observability unless the evidence session proves it is needed.
11. Capture a cold-ish run and a warm-identity run on the same target.
12. Prefer a representative physical device if available. If that is not available, use the same supported fallback target consistently for before/after evidence.
13. Answer the core question explicitly:
- if first-route churn is already small or mostly coalesced, stop with no production change
- if churn is measurable and attributable to avoidable init sequencing, choose the smallest cleanup
14. Only if cleanup is justified, add one focused regression first, then implement the smallest batching / sequencing change, then rerun the same harness and direct tests.

## 8. risks and edge cases

- `_loadTotalUnreadCount()` does not call `setState(...)`, so counting only `setState(...)` calls will undercount visible init work.
- `FeedStore` and `ValueNotifier` listeners can still trigger meaningful UI work even when the widget itself is not calling `setState(...)`.
- `loadFeed(...)` may dominate the route-open cost more than the count of local state updates.
- a warm identity path may look fine while a fresh-repo path still churns, so the plan must distinguish the two rather than averaging them away.
- secure-storage preference reads may resolve quickly and overlap unpredictably, so completion ordering should be recorded, not inferred.
- `FeedWired` also refreshes state on avatar/settings return and orbit-route return; those flows are out of scope for this session unless init evidence proves they are part of the same problem.
- do not mistake widget build counts for performance proof; frame timing and a trace are the primary evidence.

## 9. exact tests to run after implementation, if code changes occur

If the session ends with no production code changes:
- run the temporary `FeedWired` init profile harness on the chosen device / target
- rerun `integration_test/feed_performance_test.dart` only if the execution session reused or modified that harness pattern
- do not run Baseline or the Feed gate just for measurement-only work

If production code changes occur, run:
- `flutter test test/features/feed/presentation/screens/feed_wired_test.dart`
- `flutter test test/features/feed/presentation/screens/feed_wired_bg_task_test.dart`
- `flutter test test/features/feed/integration/feed_card_flow_test.dart`
- `flutter test test/features/feed/integration/expanded_collapsed_card_test.dart`
- `flutter test test/features/feed/integration/feed_color_smoke_test.dart`
- the temporary `FeedWired` init profile harness on the same target used for before evidence
- `flutter test integration_test/feed_performance_test.dart -d <device>` if the execution session also updates or relies on that existing perf harness

## 10. subsystem gate(s), if relevant

`Feed / Surface Gate` if production code changes occur.

Canonical command from `Test-Flight-Improv/14-regression-test-strategy.md`:
```bash
flutter test \
  test/features/feed/integration/feed_card_flow_test.dart \
  test/features/feed/integration/expanded_collapsed_card_test.dart \
  test/features/feed/integration/feed_color_smoke_test.dart
```

For pure profiling with no production change:
- no named subsystem gate is required beyond the direct evidence run

If a cleanup expands into inline reply send behavior or feed-to-conversation handoff, also run the `1:1 Reliability Gate`.

## 11. whether Baseline Gate is required

Optional / not required for pure profiling.

Required if any Flutter production code changes land.

Reason:
- the Session 16 roadmap entry explicitly marks Baseline Gate optional for pure profiling and required if production code changes occur

## 12. whether Startup / Transport Gate is required

No, in planned scope.

Reason:
- Session 16 is about local `FeedWired` init-time churn
- it does not target startup transport fallback, reconnect, resume orchestration, or device-backed media flows

If execution later discovers a proposed cleanup touches shared bootstrap or startup ordering outside `FeedWired`, reopen this call before implementation.

## 13. done criteria

Session 16 is complete when one of these is true:
- evidence shows current `FeedWired` init behavior is already good enough, and the session stops with no production code change
- evidence shows measurable avoidable churn, one narrow batching / sequencing cleanup lands, and before/after evidence shows improvement

And all of these are true:
- the session explicitly answers whether Session 9 identity caching already removed part of the suspected churn
- the answer is based on first-route `FeedWired` evidence, not on `FeedScreen` steady-state interaction alone
- no feed correctness behavior regresses if a cleanup lands
- the session stays narrow and does not broaden into feed architecture redesign

## 14. dependency impact on later sessions if this session blocks

- later sessions do not need to stop entirely if Session 16 remains unresolved
- Session 17 and the later DB / operability sessions can still proceed independently
- what must not happen is silent speculation: later work must not assume `FeedWired` batching is needed until Session 16 captures evidence
- if the only blocker is lack of a clean init profiling hook, that gap should remain local to Session 16 rather than being folded into broader observability or startup work

## 15. scope guard

- Do not batch or reorder init work from inspection alone.
- Do not redesign `FeedWired`, `FeedStore`, or `AppShellController`.
- Do not reopen Session 9 identity-cache implementation unless evidence proves that cache behavior is missing or ineffective.
- Do not mix this session with durable-send, unread logic changes, reply behavior changes, or route-navigation cleanup.
- Do not run Startup / Transport validation unless the execution session truly expands into startup behavior.
- If the evidence says `leave it alone`, stop there.
