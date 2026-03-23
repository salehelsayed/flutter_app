# Push Notifications For 1:1 Chat And Group Messages - TDD Plan

Prepared on: 2026-03-22
Status: Proposed
Scope: Make TestFlight iOS push notification delivery and tap-open behavior
reliable for 1:1 chat messages and group messages.

## Document Basis

This plan is based on a code review of:

- `lib/features/identity/presentation/startup_router.dart`
- `lib/main.dart`
- `lib/features/push/application/register_push_token_use_case.dart`
- `lib/features/push/application/background_message_handler.dart`
- `lib/core/notifications/notification_route_target.dart`
- `lib/core/notifications/notification_route_dispatch.dart`
- `lib/features/conversation/application/chat_message_listener.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/core/bridge/bridge_group_helpers.dart`
- `go-mknoon/bridge/bridge.go`
- `go-mknoon/node/inbox.go`
- `go-mknoon/node/group_inbox.go`
- `go-relay-server/inbox.go`
- existing push, routing, group, and bridge tests in `test/`

It also incorporates the operational requirements from the official Firebase
Cloud Messaging docs for Flutter and Apple platform apps:

- APNs auth key must be uploaded in Firebase
- iOS app must enable Push Notifications and Background Modes
- APNs token must exist before reliable FCM token registration on iOS
- on iOS, if the user swipes the app away from the app switcher, background
  message handling does not resume until the app is reopened

## Executive Summary

The current codebase is close for 1:1 push, but not complete:

1. iOS token registration is a one-shot attempt and can give up too early.
2. The relay only sends push for the 1:1 inbox `store` action.
3. Group inbox storage does not send push at all.
4. The relay does not know group membership, so group push needs an explicit
   recipient fanout contract.
5. Push tap-open flows route quickly, but they do not explicitly guarantee that
   the relevant inbox catch-up completes before the target screen opens.
6. Firebase and APNs deployment prerequisites are not locked by a repo-local
   hardening checklist.

The smallest safe rollout is:

1. Lock the push route contract and tap-open preparation behavior with tests.
2. Make iOS token registration retry until the device has a usable APNs and FCM
   token.
3. Refactor the relay push builder so 1:1 behavior is preserved by tests.
4. Add explicit group push fanout using sender-supplied recipient peer IDs.
5. Add end-to-end push-open tests for 1:1 and groups.
6. Finish with a Firebase/APNs/TestFlight hardening gate and manual smoke pass.

## Goals

- 1:1 chat messages that fall back to relay inbox should trigger visible push on
  iOS and Android.
- Group messages that fall back to relay group inbox should trigger visible push
  for offline/background members.
- Tapping a 1:1 push should open the correct conversation with the new message
  visible.
- Tapping a group push should open the correct group conversation with the new
  message visible.
- iOS/TestFlight devices should keep retrying token registration until the
  relay has a valid token or the user denies notification permission.
- The rollout should be test-first and phase-gated.

## Non-Goals

- Redesigning post, intro, or other non-chat push contracts in the same rollout.
- Adding a full relay-side persistent group membership service in this rollout.
- Guaranteeing background delivery after the user force-quits or swipes away the
  app on iOS. That is a platform limitation, not a code bug.
- Reworking Android notification UX beyond what is necessary to keep parity with
  the new routing contract.

## Current Gaps

| # | Gap | Layer | Current State |
|---|-----|-------|---------------|
| 1 | iOS token registration is fragile | Flutter | `registerPushToken()` waits up to 5 seconds for APNs token, then returns `noToken` with no dedicated retry coordinator |
| 2 | Group inbox never triggers push | Relay | `group_store` persists the message but does not call the push service |
| 3 | Relay cannot infer group recipients | Go node + relay | Group inbox requests contain `groupId` and `message`, but not the target member peer IDs |
| 4 | Push-open does not explicitly stage catch-up before route | Flutter | valid route targets are opened directly, while inbox drain is only used for missing route targets or generic resume flows |
| 5 | Firebase and APNs setup is not locked by a release gate | Ops | repo has entitlements and `remote-notification`, but rollout checks are manual and easy to miss |
| 6 | Coverage is fragmented | Tests | isolated push and notification tests exist, but there is no phase-complete 1:1 plus group push contract |

## Target Behavior Contract

### 1:1 Push Contract

When a 1:1 message falls back to relay inbox storage:

- The relay sends a visible notification payload on Android and iOS.
- The data payload includes:
  - `type = "new_message"`
  - `from = <senderPeerId>`
  - `title`
  - `body`
- The notification tap route resolves to
  `NotificationRouteTarget.conversation(senderPeerId)`.
- On tap-open, the app drains the 1:1 inbox before final route handoff.

### Group Push Contract

When a group message is stored in relay group inbox:

- The sender includes:
  - `groupId`
  - `recipientPeerIds`
  - `pushTitle`
  - `pushBody`
  - the persisted group inbox message body
- The relay stores the message once for the group inbox.
- The relay fans out push notifications to every `recipientPeerId` with a
  registered token.
- The sender is excluded from fanout.
- The data payload includes:
  - `type = "group_message"`
  - `groupId = <groupId>`
  - `title`
  - `body`
- The notification tap route resolves to
  `NotificationRouteTarget.group(groupId)`.
- On tap-open, the app catches up the relevant group inbox before final route
  handoff.

### iOS Registration Contract

After permission is granted on iOS:

- The app keeps retrying until it can read a valid APNs token and FCM token.
- The relay receives at least one successful token registration on startup or
  soon after resume.
- Token refresh events re-register automatically.
- The app does not silently stop after the first `noToken` result.

### Deployment Contract

Before shipping:

- Firebase project contains the APNs auth key for the exact iOS app.
- The relay service account belongs to the same Firebase project as
  `ios/Runner/GoogleService-Info.plist`.
- Xcode capabilities include:
  - Push Notifications
  - Background Modes
  - `fetch`
  - `remote-notification`
- TestFlight smoke passes on a physical iPhone.

---

## Phase 1: Lock Push Route And Tap-Open Preparation

### Goal

Create one explicit, tested contract for how chat and group push payloads route,
and require catch-up before navigation for push-open flows.

### Inspect First

- `lib/core/notifications/notification_route_target.dart`
- `lib/core/notifications/notification_route_dispatch.dart`
- `lib/main.dart`
- `lib/features/identity/presentation/startup_router.dart`
- `lib/core/lifecycle/handle_app_resumed.dart`
- `test/features/posts/phase1/post_notification_open_flow_test.dart`

### RED

New test file: `test/core/notifications/notification_route_target_test.dart`

1. `fromRemoteMessageData()` maps `new_message` to conversation route.
2. `fromRemoteMessageData()` maps `group_message` to group route.
3. `toPayload()` and `fromPayload()` round-trip `group:<id>` correctly.
4. Unknown payloads do not accidentally coerce to invalid routes.

New test file: `test/core/notifications/notification_route_dispatch_test.dart`

1. Remote conversation push invokes a preparation callback before route handoff.
2. Remote group push invokes a preparation callback before route handoff.
3. Missing route target falls back to the current missing-route behavior.
4. Local-notification payload routing remains unchanged.

New test file:
`test/features/push/application/prepare_notification_open_use_case_test.dart`

1. Conversation target drains 1:1 inbox before navigation.
2. Group target drains the targeted group inbox before navigation.
3. Intros/posts do not trigger unrelated chat catch-up.
4. Preparation errors are surfaced as explicit failure results, not swallowed.

### GREEN

Add a shared push-open preparation use case, for example:

- `prepareNotificationOpen(...)`

Responsibilities:

- For conversation pushes, call `p2pService.drainOfflineInbox()`.
- For group pushes, call a targeted group catch-up helper.
- For other target kinds, no-op unless explicitly required.

Update these call sites to use the shared preparation path:

- `StartupRouter._handleInitialPushOpen()`
- `MyApp._setupPushListeners()` for `onMessageOpenedApp`
- any future remote-notification tap path

Add a targeted group catch-up helper if needed, for example:

- `drainGroupOfflineInboxForGroup(...)`

This helper may wrap the existing group inbox drain logic with a single-group
scope instead of draining every joined group on every push-open.

### REFACTOR

- Keep push-open preparation out of widgets as much as possible.
- Reuse one contract for `getInitialMessage()` and `onMessageOpenedApp`.
- Do not route directly from background handlers.

### Exit Gate

- `flutter test test/core/notifications/notification_route_target_test.dart`
- `flutter test test/core/notifications/notification_route_dispatch_test.dart`
- `flutter test test/features/push/application/prepare_notification_open_use_case_test.dart`

---

## Phase 2: Harden iOS Token Registration

### Goal

Make iOS token registration resilient enough that TestFlight devices actually
reach the relay with a valid FCM token.

### Inspect First

- `lib/features/push/application/request_push_permission_use_case.dart`
- `lib/features/push/application/register_push_token_use_case.dart`
- `lib/features/identity/presentation/startup_router.dart`
- `lib/core/lifecycle/handle_app_resumed.dart`
- `ios/Runner/AppDelegate.swift`
- `ios/Runner/Info.plist`
- `ios/Runner/Runner.entitlements`
- `test/features/push/application/register_push_token_use_case_test.dart`

### RED

Extend: `test/features/push/application/register_push_token_use_case_test.dart`

1. APNs token is unavailable initially, then appears within retry budget and
   registration succeeds.
2. APNs token never appears and the result is `noToken`.
3. FCM token lookup returns null after APNs exists and the result is `noToken`.
4. Relay registration failure returns `failed` without crashing.

New test file:
`test/features/push/application/push_registration_coordinator_test.dart`

1. Permission denied stops the flow with no retries.
2. First attempt returns `noToken`, retry later succeeds, and the relay is
   registered exactly once with the latest token.
3. `onTokenRefresh` triggers re-registration.
4. App resume retries registration after prior `noToken` or `failed`.
5. Coordinator does not attach duplicate token-refresh listeners across
   repeated startup calls.

Extend or add targeted tests around iOS config:

1. `Info.plist` includes both `fetch` and `remote-notification`.
2. `Runner.entitlements` keeps `aps-environment = production`.

### GREEN

Introduce a dedicated coordinator, for example:

- `PushRegistrationCoordinator`

Responsibilities:

- request permission once
- wait for APNs token with bounded retry and backoff
- fetch FCM token once APNs token exists
- register token with relay
- retry after `noToken` and retry after transient `failed`
- subscribe to `onTokenRefresh` once
- offer a `retryNow()` entry point for resume recovery

Wire it into:

- startup after node start succeeds
- app resume recovery

Add `fetch` to `UIBackgroundModes` in `ios/Runner/Info.plist` so the project
matches Firebase's documented Flutter iOS requirements.

Do not disable Firebase method swizzling in this rollout.

### REFACTOR

- Keep `registerPushToken()` as the low-level primitive.
- Move retry policy and lifecycle orchestration into the coordinator.
- Keep `AppDelegate.swift` minimal unless the FlutterFire plugin forces a
  native delegate change.

### Exit Gate

- `flutter test test/features/push/application/register_push_token_use_case_test.dart`
- `flutter test test/features/push/application/push_registration_coordinator_test.dart`
- verify `ios/Runner/Info.plist` contains both background modes

---

## Phase 3: Lock 1:1 Relay Push Behavior Before Group Changes

### Goal

Refactor the relay push builder only after current 1:1 behavior is pinned by
tests, so group push work cannot silently break chat push.

### Inspect First

- `go-relay-server/inbox.go`
- `go-relay-server/inbox_test.go`
- `go-mknoon/node/inbox.go`
- `lib/core/services/p2p_service_impl.dart`

### RED

Extend: `go-relay-server/inbox_test.go`

1. 1:1 push payload includes:
   - `type = "new_message"`
   - `from`
   - visible Android notification payload
   - visible APNs alert payload
2. APNs config preserves:
   - `apns-push-type = alert`
   - `apns-priority = 10`
   - `content-available = true`
3. `store` action triggers push send after inbox persistence.
4. Invalid-token send failure unregisters the token.

### GREEN

Refactor `buildPushMessage(...)` into an explicit request builder, for example:

- `buildChatPushMessage(...)`
- `buildGroupPushMessage(...)`

or a single generic builder with a typed request struct.

The important rule is not the exact shape of the helper. The important rule is
that 1:1 push stays locked while group fanout is added next.

### REFACTOR

- Keep push construction separate from inbox storage logic.
- Keep data-payload routing fields explicit in tests.

### Exit Gate

- `cd go-relay-server && go test ./...`

---

## Phase 4: Add Group Push Fanout With Explicit Recipients

### Goal

Add group push without introducing a new relay-side group-membership control
plane in this rollout.

### Chosen Minimal Design

The sender already knows the group membership locally. Use that to avoid a much
larger server-side membership system in this fix.

New contract:

- Flutter group send path gathers current member peer IDs from `groupRepo`
- sender excludes self
- sender passes `recipientPeerIds`, `pushTitle`, and `pushBody` into
  `group:inboxStore`
- Go bridge and node pass those fields through to relay `group_store`
- relay stores the group inbox record once
- relay fans out push to every recipient that has a registered token

This is the smallest end-to-end design that fixes group push now.

### Inspect First

- `lib/features/groups/application/send_group_message_use_case.dart`
- `lib/core/bridge/bridge_group_helpers.dart`
- `test/core/bridge/bridge_group_helpers_test.dart`
- `test/features/groups/application/send_group_message_use_case_test.dart`
- `go-mknoon/bridge/bridge.go`
- `go-mknoon/node/group_inbox.go`
- `go-relay-server/inbox.go`
- `go-relay-server/inbox_test.go`

### RED

Extend: `test/core/bridge/bridge_group_helpers_test.dart`

1. `callGroupInboxStore()` includes `recipientPeerIds`.
2. `callGroupInboxStore()` includes `pushTitle`.
3. `callGroupInboxStore()` includes `pushBody`.
4. null or empty optional fields are omitted correctly.

Extend: `test/features/groups/application/send_group_message_use_case_test.dart`

1. group send loads members and excludes the sender from push recipients.
2. text group message builds preview body like `Sender: hello`.
3. media-only group message builds a non-empty fallback preview body.
4. empty recipient list does not crash and still stores group inbox.

Extend: `go-mknoon/bridge/bridge_test.go`

1. `GroupInboxStore` accepts `recipientPeerIds`, `pushTitle`, `pushBody`.
2. missing required `groupId` or `message` still fails.

New test file: `go-mknoon/node/group_inbox_test.go`

1. `GroupInboxStore` request marshals `recipientPeerIds`.
2. `GroupInboxStore` request marshals `pushTitle`.
3. `GroupInboxStore` request marshals `pushBody`.

Extend: `go-relay-server/inbox_test.go`

1. `group_store` fans out push to all recipient peer IDs with tokens.
2. sender is excluded from push fanout.
3. peers without tokens are skipped, not fatal.
4. group push data includes `type = "group_message"` and `groupId`.
5. group inbox is stored once even when multiple push sends are attempted.

### GREEN

Flutter changes:

- Extend `callGroupInboxStore(...)`
- Update `sendGroupMessage(...)` to gather group members and build push preview

Bridge and node changes:

- extend `group:inboxStore` payload in `bridge_group_helpers.dart`
- extend `GroupInboxStore(...)` input JSON in `go-mknoon/bridge/bridge.go`
- extend `groupInboxRequest` in `go-mknoon/node/group_inbox.go`

Relay changes:

- extend `group_store` request handling to accept `recipientPeerIds`,
  `pushTitle`, and `pushBody`
- fan out push sends via the existing push token store
- build Android and iOS payloads with:
  - `type = "group_message"`
  - `groupId`
  - `title`
  - `body`

### REFACTOR

- Keep push fanout helper separate from group inbox persistence.
- Do not parse ad hoc message JSON on the relay if explicit push-preview fields
  are already available.
- Do not introduce a relay-side group-membership database in this phase.

### Exit Gate

- `flutter test test/core/bridge/bridge_group_helpers_test.dart`
- `flutter test test/features/groups/application/send_group_message_use_case_test.dart`
- `cd go-mknoon && go test ./bridge ./node`
- `cd go-relay-server && go test ./...`

---

## Phase 5: End-To-End Push Open And Local Notification Hardening

### Goal

Prove that visible push, local notification payloads, and tap-open behavior all
agree for both 1:1 and group conversations.

### Inspect First

- `lib/features/conversation/application/chat_message_listener.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/features/push/application/show_notification_use_case.dart`
- `lib/core/notifications/flutter_notification_service.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/push/application/show_notification_use_case_test.dart`

### RED

Extend: `test/features/push/application/show_notification_use_case_test.dart`

1. local group notifications keep payload `group:<groupId>`.
2. foreground suppression still works for active group conversation.
3. foreground suppression still works for active 1:1 conversation.

Extend: `test/features/groups/application/group_message_listener_test.dart`

1. incoming group message in background shows local notification with
   `contactPeerId = group:<groupId>`.
2. notification is suppressed when that group conversation is already active.

New test file:
`test/features/push/application/chat_and_group_push_open_flow_test.dart`

1. background 1:1 push opens conversation only after inbox preparation.
2. terminated 1:1 push opens conversation only after inbox preparation.
3. background group push opens group only after targeted group catch-up.
4. terminated group push opens group only after targeted group catch-up.

### GREEN

- Reuse the Phase 1 preparation helper everywhere push routes enter the app.
- Keep one payload contract across:
  - relay remote push
  - Android fallback local notification
  - foreground local notification tap payloads

### REFACTOR

- Keep navigation policy centralized in `MyApp`.
- Keep listeners responsible for persistence plus notification display only.

### Exit Gate

- `flutter test test/features/push/application/show_notification_use_case_test.dart`
- `flutter test test/features/groups/application/group_message_listener_test.dart`
- `flutter test test/features/push/application/chat_and_group_push_open_flow_test.dart`

---

## Phase 6: Firebase, APNs, And TestFlight Hardening Gate

### Goal

Finish with an explicit release gate so the code fix is not invalidated by
console or provisioning drift.

### Hard Requirements

1. Firebase Console
   - project matches `ios/Runner/GoogleService-Info.plist`
   - APNs auth key uploaded for the iOS app

2. Relay deployment
   - `FIREBASE_SERVICE_ACCOUNT` points to the correct service account JSON
   - relay startup logs show push is enabled
   - logs show iOS token registration and successful push sends during smoke

3. Xcode / Apple setup
   - Push Notifications capability enabled
   - Background Modes enabled
   - `fetch` and `remote-notification` present
   - TestFlight build signed with production APNs entitlement

### Manual Smoke Matrix

Run on at least one physical iPhone with the TestFlight build installed.

1. Firebase console sends a direct test notification to the device FCM token.
   - Expected: visible notification while app is backgrounded.

2. 1:1 message with recipient app backgrounded.
   - Expected: relay logs token registration and push send success.
   - Expected: recipient sees visible push.
   - Expected: tapping opens the correct conversation with message visible.

3. 1:1 message with recipient app terminated but not force-quit.
   - Expected: same as above.

4. Group message with one member backgrounded.
   - Expected: relay stores group inbox and sends group push to that member.
   - Expected: tapping opens the correct group with the new message visible.

5. Group message with one member terminated but not force-quit.
   - Expected: same as above.

6. Resume smoke after successful registration.
   - Expected: app resume does not register duplicate token-refresh listeners.

### Out-Of-Code Caveat

If the user swipes the app away from the iOS app switcher, background message
delivery will not resume until the app is opened again. This is a platform
constraint and should be written into QA expectations.

### Exit Gate

- All prior automated phase gates are GREEN.
- Firebase/APNs checklist is complete.
- Manual smoke matrix passes on TestFlight.

---

## Recommended Implementation Order

1. Phase 1
2. Phase 2
3. Phase 3
4. Phase 4
5. Phase 5
6. Phase 6

Do not start Phase 4 before Phase 3 is GREEN. Group push changes touch the same
relay push builder and should not be allowed to regress 1:1 chat delivery.

## Phase Acceptance Rule

A phase is accepted only when:

- the listed RED tests were added first or captured as failing expectations
- the targeted verification commands are green
- no later-phase scope leaked into the implementation
- residual risks are written down before moving on
