# 41 - Notification Tap Opens App Without Showing Incoming Messages

## 1. Title and Type

- Title: Notification tap opens app without showing incoming messages
- Issue type: `bug`
- Output doc path: `Test-Flight-Improv/41-notification-open-missing-incoming-messages.md`

## 2. Problem Statement

- Users are trying to tap a new-message notification and immediately see the incoming message or messages that triggered it.
- Today, the app can open a 1:1 or group message surface after a notification tap while the expected new incoming message is still not visible in that thread, and the same missing-message state can persist even after a later cold start.
- Relay evidence for the reported incident shows a worse failure mode than delayed visibility alone: the client can fetch queued inbox messages from the relay, clear them from relay memory, and still fail to surface them in the local thread state.
- From the user's perspective, the notification says that new messages exist, but the opened thread looks empty or unchanged. That makes message delivery feel untrustworthy and leaves users unsure whether the app lost messages they should have received.

## 3. Impact Analysis

- Who is affected:
  - users opening 1:1 or group conversations from notifications
  - users returning from background or reopening from a terminated state
  - users receiving data-only pushes that become local fallback notifications
- When the issue appears:
  - a notification opens the app before the relevant inbox or group catch-up has surfaced the pending incoming message in the visible thread
  - or the client repeatedly polls the relay inbox but still does not surface the queued messages into the local thread state
- Severity:
  - high, because the app's notification promise and the opened conversation state contradict each other on a core messaging flow
- Frequency:
  - repo evidence supports a repeatable path-level risk, but not a precise field frequency
  - the user report shows the symptom multiple times in one session
- User-visible cost:
  - users may think messages were lost
  - users may retry opening the app or conversation and still not trust what they see
  - support/debug burden increases because notification evidence and thread state disagree
- Important nuance:
  - current repo evidence no longer supports a notification-open timing explanation alone
  - relay and Redis AOF evidence for the reported incident show that the affected inbox entries were fetched and deleted from relay memory after the app opened
  - the stronger current signal is post-retrieve client-side loss: fetched messages can disappear before they are durably represented in local conversation state
  - without a durable pre-persist staging step and explicit reject diagnostics, users can experience a silent drop where the relay queue is cleared and the thread still shows no new messages

## 4. Current State

- Affected code areas:
  - `lib/features/push/application/prepare_notification_open_use_case.dart`
  - `lib/features/identity/presentation/startup_router.dart`
  - `lib/main.dart`
  - `lib/features/push/application/background_message_handler.dart`
  - `lib/core/lifecycle/handle_app_resumed.dart`
  - `lib/core/services/p2p_service_impl.dart`
  - `lib/core/services/incoming_message_router.dart`
  - `lib/features/conversation/application/chat_message_listener.dart`
  - `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart`
  - `lib/features/identity/domain/repositories/identity_repository_impl.dart`
  - `lib/core/bridge/p2p_bridge_client.dart`
  - `go-mknoon/node/inbox.go`
  - `lib/features/posts/application/post_notification_open_coordinator.dart` as adjacent contrast
- Existing user-visible flow today:
  - The repo already has a dedicated preparation step for notification opens. `prepareNotificationOpen(...)` drains the 1:1 inbox for conversation targets and drains the targeted group inbox for group targets before routing.
  - The returning-user terminated remote-push path in `lib/features/identity/presentation/startup_router.dart` uses `routeRemoteNotificationOpen(...)` with `_prepareNotificationRouteTarget`, so initial remote push opens explicitly prepare before navigation.
  - The warm-start remote path in `lib/main.dart` handles `FirebaseMessaging.onMessageOpenedApp` by calling `routeRemoteNotificationOpen(...)` without a preparation callback. Conversation and group targets therefore route immediately through `_handleNotificationRouteTarget(...)`.
  - The local notification tap paths in `lib/main.dart` use `routeInitialLocalNotificationOpen(...)` and `routeNotificationPayload(...)` without a preparation callback. For conversation and group targets, `_handleNotificationRouteTarget(...)` pushes `ConversationWired` or `GroupConversationWired` directly.
  - Background data-only pushes can create local fallback notifications in `lib/features/push/application/background_message_handler.dart`. That file explicitly records the assumption `local notification shown if routable; inbox drain on next resume`, which matches deferred catch-up rather than guaranteed message visibility before route open.
  - `lib/core/services/p2p_service_impl.dart` only drains the offline inbox once the node is started. Startup later schedules `warmBackground()`, which drains the inbox asynchronously, and `lib/core/lifecycle/handle_app_resumed.dart` also drains the inbox on resume. The repo therefore has later recovery paths, but not a uniform "message already visible when the notification-opened route appears" contract.
  - `lib/core/services/p2p_service_impl.dart` also drains the offline inbox on periodic and recovery-triggered health checks, not just on startup and resume. Repeated relay-side inbox stream openings over a long session are therefore consistent with the current client design when inbox retrieval is not settling successfully.
  - The current 1:1 inbox retrieve path is destructive from the client's perspective:
    - `lib/core/bridge/p2p_bridge_client.dart` sends `cmd: 'inbox:retrieve'` with no separate ack/confirm phase.
    - `lib/core/services/p2p_service_impl.dart` retrieves messages and immediately injects them into the live message stream via `_emitInboxMessages(...)`.
    - `_drainOfflineInbox()` logs success as `messages consumed and deleted from relay memory`, which matches a fetch-then-delete contract rather than a stage-then-ack contract.
  - The service-level retrieve path currently hides bridge-level inbox failures from user-visible behavior:
    - `retrieveInbox(...)` logs `P2P_SERVICE_INBOX_RETRIEVE_ERROR` and returns `[]` when `response['ok'] != true`.
    - `_retrieveInboxPage(...)` converts any non-`ok` inbox response into `(emitted: 0, hasMore: false)`.
    - `_drainOfflineInbox()` therefore treats a failed retrieve the same as an empty inbox for downstream UI behavior.
  - The first foreground inbox page uses a shorter `3s` budget in `lib/core/services/p2p_service_impl.dart`, while the Go inbox retrieve path defaults to `15s` in `go-mknoon/node/config.go` when no override is provided. The repo currently has no product-level guarantee that a slower first inbox retrieve is surfaced distinctly from an actually empty queue.
  - Listener startup order is not the strongest current failure seam:
    - `lib/main.dart` starts `messageRouter` before `chatMessageListener`, and starts both before the app later kicks off P2P startup from `StartupRouter`.
    - repo evidence therefore points more toward post-retrieve processing loss than toward a simple "no listeners attached yet" race.
  - The router and listener layers still do not provide a durable fetch-to-store audit trail:
    - `lib/core/services/incoming_message_router.dart` routes inbox messages through in-memory broadcast streams.
    - `lib/features/conversation/application/chat_message_listener.dart` only persists a message after downstream parsing, key lookup, decryption, sender validation, duplicate checks, and repository save all succeed.
    - there is no local staging store that guarantees recoverability between relay fetch and successful local persistence.
  - `lib/features/conversation/application/handle_incoming_chat_message_use_case.dart` can reject a fetched `chat_message` before persistence when:
    - the envelope is `version: "2"` but the bridge or own ML-KEM secret key is unavailable
    - decryption fails
    - the sender is not a known contact
    - the message ID is treated as a duplicate or edit-with-missing-original
  - `lib/features/identity/presentation/startup_router.dart` only repairs identities that are missing an ML-KEM public key. It does not explicitly repair or block startup for a case where the public key exists but the ML-KEM secret key is missing or unreadable, even though `version: "2"` chat messages require that secret to decrypt.
  - The relay-side evidence collected for this incident is now stronger and more specific than the earlier report:
    - 5 `version: "2"` `chat_message` envelopes from `12D3KooWE2UsgX8GDogqXBxYS3iu5eM3Na2ztsQvdH8LWE7ppq2v` were stored for recipient `12D3KooWFwMYVPPjKQnBbeSU7rVuihxCeSSVM6GVVGrozXdfJq7b` at:
      - `2026-04-01 11:26:49 UTC / 13:26:49 CEST` size `2049` bytes
      - `2026-04-01 11:26:53 UTC / 13:26:53 CEST` size `2053` bytes
      - `2026-04-01 11:27:26 UTC / 13:27:26 CEST` size `2181` bytes
      - `2026-04-01 11:27:44 UTC / 13:27:44 CEST` size `2145` bytes
      - `2026-04-01 11:27:54 UTC / 13:27:54 CEST` size `2073` bytes
    - the relay journal then logged the recipient peer connecting at `2026-04-01 11:27:55 UTC` with `6 pending messages`
    - Redis AOF evidence showed a destructive `DEL relay:inbox:<recipient>` after those writes, which means the client fetched and cleared that inbox key from relay memory between the connect window at `11:27:55 UTC` and later inbox activity at `11:28:21 UTC`
    - the `6 pending messages` count was real: the same inbox key also held one older `version: "2"` `chat_message` from a different sender at `2026-04-01 06:25:20 UTC / 08:25:20 CEST`, size `2117` bytes, and that older entry was cleared in the same fetch window
    - a later message for the same recipient at `2026-04-01 11:55:42 UTC / 13:55:42 CEST`, size `2073` bytes, was also followed by a later destructive delete of the same inbox key
  - The current incident therefore fits a post-retrieve-loss pattern more closely than any route-only notification explanation:
    - the relay did receive and queue the messages
    - the app did later retrieve and remove them from the relay
    - the messages still did not become visible in the conversation
    - the repo currently lacks a durable client-side staging phase and a single exact reject record per dropped inbound envelope that would explain which downstream gate rejected each fetched message
  - `test/features/conversation/integration/offline_inbox_roundtrip_test.dart` proves that queued 1:1 messages become visible once inbox drain runs, which reinforces that user-visible message presence depends on catch-up actually completing.
  - The inbox retrieve protocol itself does not include an explicit target peer ID in the request body. The relay answers based on the libp2p peer attached to the stream. If the running node identity does not match the peer that owns the queued messages, the client can poll successfully while leaving the intended recipient queue untouched.
- Important constraints and adjacent coverage already present:
  - Helper-level tests already encode a prepare-then-route expectation for chat and group notification opens:
    - `test/features/push/application/prepare_notification_open_use_case_test.dart`
    - `test/features/push/application/chat_and_group_push_open_flow_test.dart`
    - `test/integration/notification_deeplink_integration_test.dart`
    - `test/core/notifications/notification_route_dispatch_test.dart`
  - Post notifications have broader open-path coverage in `test/features/posts/phase1/post_notification_open_flow_test.dart`, and the post flow uses a dedicated coordinator that explicitly drains and waits for catch-up visibility.
  - `Test-Flight-Improv/32-notification-card-interactions.md` covers notification-opened Feed card interaction bugs after messages are already visible, not this missing-message-on-open problem.
  - No equivalent test was found for the real chat/group `MyApp` handlers in `lib/main.dart` that own:
    - `FirebaseMessaging.onMessageOpenedApp`
    - `_handleInitialLocalNotificationLaunch()`
    - `_onNotificationTap(...)`

## 5. Scope Clarification

- In scope:
  - user-visible guarantee that tapping a 1:1 or group message notification surfaces the pending incoming message or messages that caused that notification
  - consistency across warm-start remote opens, terminated remote opens, warm local taps, and terminated local fallback launches
  - cases where multiple notifications arrive before the user opens the app
  - distinguishing "messages are not visible yet" from "messages were fetched but local processing failed" in the product experience and diagnostics
  - ensuring fetched inbox envelopes remain durably recoverable until local persistence succeeds, so a post-fetch failure does not silently erase the user's only copy
  - emitting an exact reject reason for every inbound envelope that is dropped after fetch, with enough identifiers to correlate relay-side receipt and client-side rejection
- Explicit non-goals:
  - posts or introduction notifications
  - Feed-card interaction bugs after a notification-opened message is already visible
  - sender-side delivery semantics, read receipts, or unread-badge redesign
  - broader transport, relay, or push-architecture redesign outside the inbox fetch, persistence, and notification-open recovery contract
  - redesigning notification copy, unread badges, or conversation UI beyond what is required to make the missing messages reliably appear
- Accepted ambiguities to keep open for the later implementation pass:
  - whether the reported 5-notification case came from visible remote push, local fallback notification, or a mix of both
  - whether the failure is limited to direct conversation/group routes or can also present through Feed/Orbit notification-led entry
  - which exact post-retrieve rejection seam dominates the incident in production:
    - ML-KEM secret unavailable during v2 receive
    - decryption failure
    - unknown-sender rejection
    - duplicate/edit rejection
    - timeout or wrong-identity retrieval in adjacent sessions
    - or a combination of those factors
  - whether the same post-retrieve-loss pattern also affects group inbox recovery, or only the 1:1 inbox path is confirmed by current evidence

## 6. Test Cases

### Happy Path

- `TC-41-H01` Given the app is backgrounded and a new 1:1 message arrives from Alice, when the user taps that notification, then the app opens the Alice thread and the message that triggered the notification becomes visible during that same open flow.
- `TC-41-H02` Given the app is not running and a new 1:1 message arrives, when the user launches from the notification, then the app shows the notified message in the opened conversation without requiring the user to leave and reopen the thread.
- `TC-41-H02a` Given the app is fully cold-started after the notification-open attempt already failed once, when the user launches the app again normally, then the same queued 1:1 message still becomes visible instead of remaining silently absent.
- `TC-41-H02b` Given the app fetches queued 1:1 inbox messages during startup and the app is interrupted before those messages become visible, when the user launches again, then those same fetched messages are still recoverable and appear exactly once instead of disappearing after the first fetch.
- `TC-41-H03` Given the app is backgrounded and a new group message arrives, when the user taps that group notification, then the opened group thread shows the incoming message that triggered the notification.
- `TC-41-H04` Given the app was not in the foreground and a routable data-only message notification produced a local fallback notification, when the user taps that local notification, then the app still reveals the pending message for that conversation during the same notification-open flow.

### Edge Cases

- `TC-41-E01` Given 5 unread messages arrive from the same contact while the app is backgrounded or closed, when the user taps one of those notifications, then the thread shows the queued incoming messages for that contact rather than opening to an apparently unchanged or empty conversation.
- `TC-41-E02` Given several unread group messages arrive while the app is not foregrounded, when the user opens from any one of those group notifications, then the group thread shows the queued incoming messages that were waiting for that group.
- `TC-41-E03` Given the thread already has older persisted history, when a new notification opens that same thread, then the newly arrived message is distinguishable as present in the opened result rather than the screen appearing unchanged.
- `TC-41-E04` Given the notification opens the app before all background startup work is complete, when the opened thread first renders, then the user still reaches a state in the same open flow where the notified message becomes visible without manually reopening the notification or force-quitting the app.
- `TC-41-E05` Given the relay inbox is destructively fetched but local conversation persistence does not complete, when the user relaunches or resumes later, then the previously fetched messages are still surfaced from client-side recovery state instead of being gone from both relay memory and the thread UI.
- `TC-41-E06` Given the client is connected and polling the inbox repeatedly while the relay queue for that recipient is still non-empty, when the app remains open through multiple health-check cycles, then at least one of those cycles must surface the queued messages or expose a visible failure/diagnostic state rather than repeatedly behaving as if the inbox were empty.
- `TC-41-E07` Given a fetched inbound envelope is rejected after fetch because of decrypt failure, missing ML-KEM secret, unknown sender, duplicate handling, or another local validation failure, when QA or support inspects client logs for that session, then the log shows the exact reject reason and enough message identifiers to correlate the drop with the fetched envelope.
- `TC-41-E08` Given multiple queued messages are fetched in one inbox drain, including older backlog plus the newest notification-triggering messages, when the recovery completes, then all fetched recoverable messages appear and none of them silently disappear because one message in the batch failed local processing.

### Regressions To Preserve

- `TC-41-R01` Bug regression: Given unread incoming message notifications exist for a specific 1:1 or group thread, when the user opens the app from one of those notifications, then the corresponding thread must not settle in a state where none of the pending incoming messages are visible.
- `TC-41-R02` Given messages were queued while the recipient was offline, when the recipient returns and the app performs its normal recovery, then those messages still surface exactly once in the appropriate thread.
- `TC-41-R03` Given the app is already open and not focused on the sender thread, when a new message arrives live, then existing notification behavior and message visibility still work as before.
- `TC-41-R04` Given the relay queue for the active recipient peer remains non-empty after a failed retrieve attempt, when the app retries inbox recovery later, then the retry path must not silently collapse the failure into an empty-thread experience.
- `TC-41-R05` Bug regression: Given the client has already fetched inbox messages from the relay, when downstream local processing fails before persistence, then those messages must not be silently lost with no remaining relay copy and no exact reject record.
- Existing tests that partially cover this area today:
  - `test/features/push/application/prepare_notification_open_use_case_test.dart`
  - `test/features/push/application/chat_and_group_push_open_flow_test.dart`
  - `test/integration/notification_deeplink_integration_test.dart`
  - `test/core/notifications/notification_route_dispatch_test.dart`
  - `test/features/conversation/integration/offline_inbox_roundtrip_test.dart`
  - `test/features/posts/phase1/post_notification_open_flow_test.dart` as adjacent evidence that a fully covered notification-open catch-up contract already exists elsewhere in the app
- Current test gap:
  - No existing test was found for the real chat/group notification handlers in `lib/main.dart` proving that warm-start remote taps, warm local taps, and terminated local launches surface the notified incoming message or messages before or during route open.
  - No existing test was found for the failure case where `inbox:retrieve` returns a non-`ok` bridge response during startup/resume/open flows and the app must preserve a trustworthy user-visible outcome rather than behaving like the inbox is empty.
  - No existing test was found for the identity-bound retrieve contract where queued messages exist for peer A but the running node is peer B, and the product must avoid giving the user a false “no new messages” impression.
  - No existing test was found for the destructive-fetch case where inbox messages are removed from relay memory before local persistence succeeds and the client must still recover them exactly once on a later launch.
  - No existing test was found for exact reject-reason logging tied to a fetched inbound envelope that is dropped after retrieve.
