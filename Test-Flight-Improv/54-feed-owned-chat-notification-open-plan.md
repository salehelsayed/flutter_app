# 54 - Feed-Owned Chat Notification Open Plan

## Final Verdict

`implementation-ready`

The current repo already has the major pieces needed for this change:

- notification routing is centralized in `main.dart` and `startup_router.dart`
- Feed already reacts quickly when a real incoming message is persisted and
  emitted through `ChatMessageListener`
- the repo already has a pending-target pattern for posts that can be reused
  instead of inventing a new app-shell architecture

The lag comes from sequencing, not from feed-card rendering. Chat notification
open currently waits on startup/recovery work and inbox drain before the
user-visible target is materialized. The bounded fix is to make 1:1 chat
notification open Feed-owned and non-blocking, while leaving group, post,
intro, and contact-request semantics unchanged.

## 1. Real Scope

This plan changes only 1:1 chat notification-open behavior:

- treat a chat notification tap as a Feed-owned route target rather than a
  direct `ConversationWired` route
- show Feed immediately on notification open without awaiting inbox drain
- auto-open the correct stackcard in Feed when the target thread is already
  present locally
- if the target message/thread is not yet present locally, wait silently for
  the normal recovery pipeline to materialize it, then auto-open the correct
  card
- coalesce overlapping `drainOfflineInbox()` callers so startup, resume,
  foreground push, and notification-open do not stack duplicate recovery work

This plan does not add a visible temporary pending state, banner, badge, or
placeholder copy such as "Opening message...".

This plan does not redesign full deep-linking for exact message IDs.

## 2. Closure Bar

This area is good enough for the current architecture when all of the
following are true:

- tapping a 1:1 chat notification shows Feed immediately instead of waiting on
  inbox drain
- if the thread already exists locally, Feed auto-focuses and opens that
  stackcard in the same open flow
- if the thread/message is not yet local, the app performs recovery in the
  background and auto-opens the correct card when the message lands, without
  extra user action
- no temporary status UI is introduced to fake the target before the real data
  exists
- overlapping `drainOfflineInbox()` calls share one in-flight recovery path
  rather than competing
- group, post, intro, and contact-request notification-open behavior does not
  regress

## 3. Source Of Truth

Primary repo evidence:

- `lib/main.dart`
- `lib/features/identity/presentation/startup_router.dart`
- `lib/features/push/application/prepare_notification_open_use_case.dart`
- `lib/features/push/application/prepare_notification_route_target_use_case.dart`
- `lib/core/services/p2p_service_impl.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/features/feed/presentation/screens/feed_screen.dart`
- `lib/features/posts/application/pending_post_target_store.dart`
- `lib/features/posts/application/post_notification_open_coordinator.dart`
- `lib/features/conversation/application/chat_message_listener.dart`
- `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`

Primary test and gate docs:

- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/test-gates-reference.md`
- `Test-Flight-Improv/52-notification-journey-test-matrix.md`

Disagreement rule:

- current code and passing tests beat stale prose
- `test-gate-definitions.md` and `scripts/run_test_gates.sh` define named-gate
  expectations
- current notification matrix prose that says chat notification taps should
  route directly to `ConversationWired` after blocking inbox prep is stale once
  this plan lands and must be updated instead of preserved

## 4. Session Classification

`implementation-ready`

## 5. Exact Problem Statement

The current code still allows the following user-visible delay:

- the user taps a 1:1 notification
- the app opens on Feed, which is correct
- the target stackcard and incoming unread content do not materialize
  immediately
- only after startup/recovery and inbox-drain work completes does the target
  become visible

Repo-backed diagnosis:

- cold-start chat notification open is deferred until after `startP2PNode()`
  completes in `StartupRouter`
- chat notification open still uses `prepareNotificationOpen()`, which blocks
  on `drainOfflineInbox()` before routing
- the warm background path already triggers inbox drain after node start, so
  notification-open can overlap with a second drain
- resume handling also performs bridge health and inbox recovery, so
  background/warm opens can queue more recovery work while the notification
  route is trying to complete
- Feed itself is not the slow seam; once a real `ConversationMessage` reaches
  `FeedWired`, the card updates promptly via incremental merge logic

What must improve:

- Feed must become the immediate, user-visible landing surface for 1:1 chat
  notification opens
- inbox drain and message materialization must become background work instead of
  route-blocking work
- the target card should auto-open from real data as soon as that data exists
- redundant inbox drains should be coalesced

What must stay unchanged:

- no temporary target placeholder/status UI
- no change to normal manual Feed-to-Conversation navigation
- no change to group, post, intro, or contact-request notification policy in
  this session

## 6. Files And Repos To Inspect Next

Production files expected to change:

- `lib/main.dart`
- `lib/features/identity/presentation/startup_router.dart`
- `lib/features/push/application/prepare_notification_open_use_case.dart`
- `lib/features/push/application/prepare_notification_route_target_use_case.dart`
- one new small chat pending-target / coordinator file near feed or
  notifications
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/core/services/p2p_service_impl.dart`

Production files expected to stay source-of-truth only:

- `lib/features/conversation/application/chat_message_listener.dart`
- `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`
- `lib/features/feed/presentation/screens/feed_screen.dart`
- `lib/features/posts/application/pending_post_target_store.dart`
- `lib/features/posts/application/post_notification_open_coordinator.dart`

Tests expected to change or be added:

- `test/core/notifications/app_root_notification_open_test.dart`
- `test/integration/notification_deeplink_integration_test.dart`
- `test/features/identity/presentation/screens/startup_router_notification_open_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`
- `test/core/lifecycle/app_lifecycle_recovery_test.dart`
- one new direct/coordinator test for chat notification open semantics
- one new direct test for inbox-drain coalescing in `p2p_service_impl.dart`

## 7. Existing Tests Covering This Area

Already covered:

- `test/core/notifications/app_root_notification_open_test.dart`
  proves app-root notification helper sequencing
- `test/integration/notification_deeplink_integration_test.dart`
  proves the current `prepare -> drain -> route` contract
- `test/features/identity/presentation/screens/startup_router_test.dart`
  documents the current expectation that Feed is shown before network warm-up
- `test/features/feed/presentation/screens/feed_wired_test.dart`
  proves Feed reacts correctly to incoming messages and open-mode card
  transitions
- `test/core/lifecycle/app_lifecycle_recovery_test.dart`
  covers resume recovery sequencing around inbox drain
- posts already prove the repo-local pending-target pattern via
  `pending_post_target_store.dart` and `post_notification_open_coordinator.dart`

Currently missing:

- direct proof that a chat notification tap is Feed-owned instead of
  conversation-route-owned
- direct proof that Feed consumes a pending chat target and auto-opens the
  correct card when the thread already exists locally
- direct proof that Feed silently waits for the target to materialize when it
  does not yet exist locally, then auto-opens it
- direct proof that concurrent `drainOfflineInbox()` callers coalesce

Current tests pin behavior that now needs to change:

- `test/integration/notification_deeplink_integration_test.dart`
  currently encodes `prepare -> drain -> route` for chat
- notification journey matrix rows in
  `Test-Flight-Improv/52-notification-journey-test-matrix.md`
  currently describe direct route-to-conversation semantics for 1:1 chat

## 8. Regression / Tests To Add First

Add or update these first, before production edits:

1. Add a direct coordinator-level chat notification-open test that proves:
   - Feed target is set immediately
   - inbox drain is started unawaited
   - no direct conversation route is required for the first visible response

2. Extend `test/features/feed/presentation/screens/feed_wired_test.dart` with:
   - pending chat target already present locally -> target card opens and
     viewport follows
   - pending chat target not present locally -> no fake UI appears, but the
     card auto-opens once the incoming message is emitted

3. Update `test/integration/notification_deeplink_integration_test.dart`
   so 1:1 chat no longer asserts blocking `prepare -> drain -> route` semantics
   and instead asserts the new Feed-owned contract

4. Add one focused drain-coalescing test around `p2p_service_impl.dart`:
   - multiple callers await the same in-flight drain
   - only one underlying drain execution starts

5. Keep group notification tests unchanged or explicitly mirrored to prove
   their existing blocking prep semantics remain intact

## 9. Step-By-Step Implementation Plan

1. Introduce a new small pending-target store for chat notifications.
   Preferred shape:
   - `peerId` only
   - optional internal consumed/cleared state
   - no user-visible status string
   - same lifecycle philosophy as `PendingPostTargetStore`, but narrower

2. Add a chat notification open coordinator that owns only 1:1 chat opens.
   The coordinator should:
   - accept a chat `NotificationRouteTarget`
   - set the pending chat target immediately
   - reveal/ensure Feed as the owning surface
   - start inbox recovery unawaited
   - never synthesize fake visible card content
   - clear the target only after Feed has successfully consumed it or the app
     determines it can never be resolved

3. Rewire 1:1 chat notification entry points to use the new coordinator:
   - local tap path in `main.dart`
   - warm remote open path in `main.dart`
   - initial remote message open path in `startup_router.dart`
   - initial local-notification launch path in `main.dart`

4. Keep route policy centralized.
   Do not add feature-owned tap handlers inside listeners or background code.
   Chat notification route policy should remain rooted in `main.dart` and
   `startup_router.dart`.

5. Split chat semantics from the current blocking
   `prepareNotificationOpen()` contract.
   Preferred shape:
   - chat: route to Feed immediately, recover in background
   - group/contact-request/intros: keep current prepare-before-route behavior
     unless repo evidence later says otherwise
   - do not widen this helper into a generic "maybe blocking / maybe not"
     abstraction unless the code clearly stays simple

6. Extend `FeedWired` so it can consume the pending chat target.
   Required behavior:
   - on init and after relevant feed changes, check whether a pending target
     matches an existing thread
   - if found, set `_expandedCardId`, request viewport follow, and clear the
     target
   - if not found, leave the target pending silently and retry after normal
     incoming-message and refresh code paths
   - reuse existing real-data card behavior; do not mark unread/open
     synthetically

7. Hook the target-consumption checks into the smallest real-data moments:
   - after `_loadFeedFromDatabase()`
   - after `_applyIncomingContactMessageToFeed()`
   - after `_refreshContactFeedItem()`
   - optionally after bulk route-change refreshes if evidence shows the target
     can arrive through that path

8. Add drain coalescing to `P2PServiceImpl`.
   Preferred shape:
   - one private in-flight future/completer for inbox drain
   - if a drain is already active, new callers await the same future
   - preserve current first-page foreground budget and background continuation
   - do not change durable staging semantics

9. Ensure resume, startup warm path, and notification-open all use the same
   coalesced drain behavior without reordering unrelated bridge health logic.

10. Update stale routing tests and matrix prose so the repo contract is clear:
    1:1 notification taps are Feed-owned and do not block on inbox drain before
    the first visible response.

11. Stop if implementation starts pulling group notification behavior into the
    same coordinator or requires exact-message deep-linking. Those are separate
    scope items.

## 10. Risks And Edge Cases

- pending target exists but the contact/thread never resolves locally
- background tap happens while resume recovery is already in progress
- cold start, warm start, and local-notification launch must stay aligned
- multiple notifications for the same peer may race target replacement/clearing
- a target may resolve from database load, live inbox replay, or later refresh;
  Feed must not consume it twice
- drain coalescing must not hide real drain failures or strand waiting callers
- route changes for posts/groups must not accidentally consume chat targets

## 11. Exact Tests And Gates To Run

Direct targeted tests first:

```bash
flutter test test/core/notifications/app_root_notification_open_test.dart
flutter test test/integration/notification_deeplink_integration_test.dart
flutter test test/features/identity/presentation/screens/startup_router_notification_open_test.dart
flutter test test/features/feed/presentation/screens/feed_wired_test.dart
flutter test test/core/lifecycle/app_lifecycle_recovery_test.dart
```

Notification/routing integrations next:

```bash
flutter test test/integration/notification_tap_smoke_test.dart
flutter test test/features/push/application/chat_and_group_push_open_flow_test.dart
```

If a new direct coordinator or service test file is added, run it explicitly.

Named gates matching the blast radius:

```bash
./scripts/run_test_gates.sh feed
./scripts/run_test_gates.sh 1to1
./scripts/run_test_gates.sh transport
```

If a new test file is added under `test/`, keep classification current:

```bash
./scripts/run_test_gates.sh completeness-check
```

## 12. Known-Failure Interpretation

- any failure in newly touched notification, Feed, lifecycle, or drain tests is
  a blocker
- if `transport` fails with a documented pre-existing integration/device issue,
  only treat it as pre-existing if the failure signature matches current repo
  truth exactly
- stale tests that still assert direct conversation-route ownership for chat
  notification taps must be updated rather than treated as proof against the
  new requirement

## 13. Done Criteria

This plan is done when:

- a 1:1 notification tap shows Feed immediately without awaiting inbox drain
- Feed auto-opens the correct stackcard when the target thread already exists
  locally
- Feed silently waits and then auto-opens the correct card when the target
  message arrives later through normal recovery
- no temporary visible pending/status UI is introduced
- overlapping `drainOfflineInbox()` callers coalesce
- group/post/contact-request notification behavior remains green
- updated tests and gates pass
- stale notification matrix prose is corrected

## 14. Scope Guard

Do not broaden this work into:

- exact `messageId` deep linking
- placeholder/loading/status UI on Feed
- badge-count redesign
- unread-count architecture changes
- group notification route redesign
- full app-shell navigation refactor
- notification visual-design changes

Overengineering for this session would be:

- adding a large generic notification target framework for every feature
- inventing synthetic Feed card state just to fake instant open
- changing all route kinds to one new coordinator despite different recovery
  needs

## 15. Accepted Differences / Intentionally Out Of Scope

- exact-message restore from notification payload remains out of scope
- group notifications keep blocking recovery-before-route semantics
- posts keep their existing pending-target coordinator
- direct `ConversationWired` route remains the normal manual navigation path;
  only notification-origin chat opens change

## 16. Dependency Impact

- this plan creates a clean seam for a later exact-message deep-link effort if
  product ever wants it
- later notification journey docs and tests should treat Feed-owned 1:1 open as
  the current contract
- if drain coalescing proves unsafe or unexpectedly invasive, the routing change
  can still land first, but the perceived-latency win will be smaller

## Structural Blockers Remaining

None.

## Incremental Details Intentionally Deferred

- whether the pending chat target store lives under `core/notifications/` or
  under Feed/application
- whether target expiry uses a timer or only explicit clear-on-consume
- whether one new coordinator test file is enough or should be split by warm
  vs cold path

## Accepted Differences Intentionally Left Unchanged

- group notification open still blocks on recovery
- posts retain their current pending-target implementation
- no exact message payload enrichment is required for this session

## Exact Docs/Files Used As Evidence

- `lib/main.dart`
- `lib/features/identity/presentation/startup_router.dart`
- `lib/features/push/application/prepare_notification_open_use_case.dart`
- `lib/features/push/application/prepare_notification_route_target_use_case.dart`
- `lib/core/services/p2p_service_impl.dart`
- `lib/features/feed/presentation/screens/feed_wired.dart`
- `lib/features/feed/presentation/screens/feed_screen.dart`
- `lib/features/posts/application/pending_post_target_store.dart`
- `lib/features/posts/application/post_notification_open_coordinator.dart`
- `lib/features/conversation/application/chat_message_listener.dart`
- `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`
- `test/core/notifications/app_root_notification_open_test.dart`
- `test/integration/notification_deeplink_integration_test.dart`
- `test/features/feed/presentation/screens/feed_wired_test.dart`
- `test/features/identity/presentation/screens/startup_router_test.dart`
- `test/core/lifecycle/app_lifecycle_recovery_test.dart`
- `Test-Flight-Improv/test-gate-definitions.md`
- `Test-Flight-Improv/test-gates-reference.md`
- `Test-Flight-Improv/52-notification-journey-test-matrix.md`

## Why The Plan Is Safe To Implement Now

This plan is safe because it stays narrow and uses seams the repo already has:

- notification policy is already centralized
- Feed already knows how to reorient and open cards from real data
- posts already demonstrate the pending-target pattern
- the recovery bottleneck is localized behind `drainOfflineInbox()`, which can
  be coalesced without redesigning messaging persistence

The plan changes route ownership and recovery timing, not the core message
storage model. It avoids speculative exact-message deep linking and avoids fake
UI state, which keeps the implementation bounded and testable.
