# 52 - Notification Journey Test Matrix for 1:1 and Group Messaging

## 1. Title and Type

- Title: `Notification Journey Test Matrix for 1:1 and Group Messaging`
- Issue type: `feature-improvement`
- Output doc path: `Test-Flight-Improv/52-notification-journey-test-matrix.md`

## 2. Problem Statement

Users rely on notifications as the entry point into 1:1 and group messaging.
The product needs a durable, runnable test matrix that keeps the notification
contract stable as the app changes.

Today the repo already has strong seam coverage for notification routing,
dedupe, fallback suppression, and tray clearing, but that coverage is spread
across unit, integration, and smoke tests. What is missing is one authoritative
journey matrix that says which notification behaviors must stay green, which
automation layer should own each behavior, and which user-visible 2-party or
3-party flows still need direct E2E proof.

## 3. Impact Analysis

The affected surface is broad:

- every user who receives a 1:1 chat notification
- every user who receives a group message notification
- any user who opens the app from a notification or from the app icon after
  seeing a notification

When this area regresses, the user-visible failures are expensive:

- duplicate notifications for one message
- unnamed fallback notifications that compete with the correct named one
- stale notifications that remain in the tray after the user has already opened
  the app
- taps that route to the wrong place or route before inbox/group catch-up
- removed group members still receiving notifications they should no longer see

These are P0/P1 regressions because they make the app feel unreliable even when
message transport itself is correct.

## 4. Current State

Current repo-owned notification behavior is spread across a few core seams:

- background push intake and local fallback:
  `lib/features/push/application/background_message_handler.dart`,
  `lib/features/push/application/background_push_notification_fallback.dart`
- local notification show/suppression:
  `lib/features/push/application/show_notification_use_case.dart`,
  `lib/features/conversation/application/chat_message_listener.dart`,
  `lib/features/groups/application/group_message_listener.dart`
- tap routing and prepare-before-route:
  `lib/core/notifications/app_root_notification_open.dart`,
  `lib/features/push/application/prepare_notification_open_use_case.dart`,
  `lib/features/identity/presentation/startup_router.dart`
- tray clearing:
  `lib/core/notifications/flutter_notification_service.dart`,
  `lib/core/lifecycle/handle_app_resumed.dart`

Important current automated evidence already exists:

- 1:1 and group remote/local dedupe:
  `test/integration/chat_notification_dedupe_integration_test.dart`,
  `test/integration/group_notification_dedupe_integration_test.dart`
- warm/cold notification routing:
  `test/integration/notification_tap_smoke_test.dart`,
  `test/features/push/application/chat_and_group_push_open_flow_test.dart`,
  `test/integration/notification_deeplink_integration_test.dart`
- fallback suppression and dedupe-key logic:
  `test/features/push/application/background_push_notification_fallback_test.dart`,
  `test/features/push/application/background_message_handler_test.dart`
- show/suppress behavior:
  `test/features/push/application/show_notification_use_case_test.dart`,
  `test/features/groups/application/group_message_listener_test.dart`
- clear-on-open behavior:
  `test/core/notifications/flutter_notification_service_test.dart`,
  `test/core/lifecycle/app_lifecycle_recovery_test.dart`,
  `test/core/notifications/app_root_notification_open_test.dart`,
  `test/features/identity/presentation/screens/startup_router_notification_open_test.dart`

Current product contract to preserve:

- notification opens route directly to the targeted conversation or group after
  preparation
- active conversation/group viewing suppresses local notifications
- remote push plus later local replay should not create duplicate notifications
- normal app resume clears delivered notifications, not just notification-origin
  opens

Current limitation to keep explicit:

- the repo does not yet have a general-purpose multi-simulator notification
  command executor equivalent to the unlanded direction in
  `Test-Flight-Improv/51-e2e-test-infrastructure-plan.md`
- repo-local `flutter test` coverage is strong, but true 2-party / 3-party
  notification E2E remains a desired layer rather than a fully landed runner

## 5. Scope Clarification

### In scope

- 1:1 message notification correctness
- group message notification correctness
- named copy versus generic fallback behavior
- remote/local dedupe and replay suppression
- warm and cold notification tap routing
- tray clearing after notification-origin open and normal app open
- notification suppression for active conversation/group views
- group notification boundaries after removal and after re-invite

### Out of scope

- posts, intros, and contact-request notification matrices
- APNs / FCM delivery SLA or provider-side fanout guarantees
- notification visual design polish
- unsupported group-role product flows such as admin promotion or demotion as a
  notification requirement, because those flows are not a stable landed product
  contract in the current repo

### Accepted ambiguity

- exact OS presentation differences between simulator, debug build, TestFlight,
  and production APNs delivery should stay outside this matrix unless a future
  repo-local executor lands
- some rows intentionally ask for 2-party or 3-party E2E even though the
  current strongest evidence is integration plus smoke; those rows are still
  useful because they define the missing future device layer clearly

## 6. Test Cases

### Coverage legend

- `Required`: should exist before treating the notification behavior as stable
- `Recommended`: high-value coverage, but not mandatory for every release gate
- `N/A`: do not force this layer for the row

### Rules used for this matrix

**Unit**
- role checks
- dedupe
- replay protection
- epoch/key rotation
- notification suppression after removal
- unread counter logic
- state transitions such as `removed -> rejoined`

**Integration**
- add/remove member
- promote admin
- re-invite
- send/receive
- notification behavior
- metadata sync

**Smoke**
- create group
- online fan-out
- add member
- remove member
- removed member blocked
- re-invite works
- admin promotion works

**Fake Network**
- retries
- duplicates
- offline recipient
- reconnect
- relay/store-and-forward
- partition healing
- removal boundary
- queued delivery after removal
- concurrent admin changes

**2-party E2E (2 simulators)**
- A sends and B receives
- B taps from background
- B taps from cold start
- B opens the app normally and delivered notifications clear
- B is already viewing the conversation and no duplicate notification appears

**3-party E2E (3 simulators)**
- A sends and B/C receive
- A removes C
- C stops receiving/sending
- A re-invites C
- notification deep-link behavior
- member list and role badges sync across devices

### Happy Path

#### Release-blocking smoke rows

| Test ID | Scenario | Expected Result | Priority | Unit | Integration | Smoke | Fake Network | Device E2E | Current coverage / notes |
|---|---|---|---|---|---|---|---|---|---|
| SM-001 | 1:1 single message while B is backgrounded | B gets one correctly named notification and tapping it opens A's conversation after inbox prep. | P0 | Recommended | Required | Required | N/A | 2-party E2E Required | Current core evidence: `test/features/push/application/chat_and_group_push_open_flow_test.dart`, `test/integration/notification_tap_smoke_test.dart`, `test/features/push/application/show_notification_use_case_test.dart`. |
| SM-002 | 1:1 normal app-open clears tray | B opens the app from the app icon or app switcher and delivered notifications are cleared. | P0 | Recommended | Required | Required | N/A | 2-party E2E Required | Current core evidence: `test/core/lifecycle/app_lifecycle_recovery_test.dart`, `test/core/notifications/flutter_notification_service_test.dart`. |
| SM-003 | Group online fan-out notification | A sends one group message and B/C each get one correct group notification. | P0 | Recommended | Required | Required | N/A | 3-party E2E Required | Current core evidence: `test/features/groups/application/group_message_listener_test.dart`, `test/features/push/application/chat_and_group_push_open_flow_test.dart`. |
| SM-004 | Removed member blocked from future group notifications | After A removes C, later group messages notify remaining members only. | P0 | Required | Required | Required | Required | 3-party E2E Required | Current core evidence: `test/features/groups/application/group_message_listener_test.dart`; stronger user-visible 3-party proof is still desirable. |
| SM-005 | Re-invite restores notification eligibility | After A re-invites C and rejoin becomes effective, C can receive new group notifications again. | P0 | Required | Required | Required | Required | 3-party E2E Required | Current repo proves rejoin send/receive in `test/features/groups/integration/group_membership_smoke_test.dart`, but the exact notification-resume row still needs direct proof. |

#### 1:1 core journeys

| Test ID | Scenario | Expected Result | Priority | Unit | Integration | Smoke | Fake Network | 2-party E2E | Current coverage / notes |
|---|---|---|---|---|---|---|---|---|---|
| DM-001 | Backgrounded B receives one named 1:1 notification | Notification title/body use sender-aware copy and there is only one visible notification path. | P0 | Recommended | Required | Required | N/A | Required | Covered strongly at the app-owned seam by `test/features/push/application/show_notification_use_case_test.dart`; real device presentation remains complementary. |
| DM-002 | Warm notification tap | B taps a notification while the app is backgrounded and the app performs `prepare -> drain -> route` to A's conversation. | P0 | N/A | Required | Required | N/A | Required | Covered by `test/features/push/application/chat_and_group_push_open_flow_test.dart`, `test/integration/notification_tap_smoke_test.dart`. |
| DM-003 | Cold-start notification tap | B taps a notification from a terminated state and the app still performs `prepare -> drain -> route`. | P0 | N/A | Required | Required | N/A | Required | Covered by `test/features/push/application/chat_and_group_push_open_flow_test.dart`, `test/core/notifications/app_root_notification_open_test.dart`, `test/features/identity/presentation/screens/startup_router_notification_open_test.dart`. |
| DM-004 | Active conversation suppression | If B is already viewing A's conversation, no duplicate local notification is shown. | P0 | Recommended | Required | Recommended | N/A | Required | Covered by `test/features/push/application/show_notification_use_case_test.dart`. |
| DM-005 | Normal app-open clears delivered notifications | Opening the app normally clears any delivered 1:1 notifications without requiring a notification tap. | P0 | Recommended | Required | Required | N/A | Required | Covered by `test/core/lifecycle/app_lifecycle_recovery_test.dart` and `test/core/notifications/flutter_notification_service_test.dart`. |

#### Group core journeys

| Test ID | Scenario | Expected Result | Priority | Unit | Integration | Smoke | Fake Network | 3-party E2E | Current coverage / notes |
|---|---|---|---|---|---|---|---|---|---|
| GMN-001 | A sends, B/C receive one correct group notification | B and C each get one notification for the correct group with sender-prefixed body text. | P0 | Recommended | Required | Required | N/A | Required | Current local evidence: `test/features/groups/application/group_message_listener_test.dart`, `test/features/push/application/show_notification_use_case_test.dart`. |
| GMN-002 | Warm group notification tap | Tapping the notification performs targeted group catch-up before opening the group. | P0 | N/A | Required | Required | N/A | Required | Covered by `test/features/push/application/chat_and_group_push_open_flow_test.dart`, `test/integration/notification_tap_smoke_test.dart`. |
| GMN-003 | Cold-start group notification tap | From a terminated launch, the app still does targeted group prepare/catch-up before route. | P0 | N/A | Required | Required | N/A | Required | Covered by `test/features/push/application/chat_and_group_push_open_flow_test.dart`, `test/core/notifications/app_root_notification_open_test.dart`. |
| GMN-004 | Active group suppression | If B is already viewing the same group, no local group notification is shown. | P0 | Recommended | Required | Recommended | N/A | Required | Covered by `test/features/groups/application/group_message_listener_test.dart` and `test/features/push/application/show_notification_use_case_test.dart`. |
| GMN-005 | Normal app-open clears delivered group notifications | Opening the app normally clears delivered group notifications just like 1:1 notifications. | P0 | Recommended | Required | Required | N/A | Required | Covered by the shared clear-on-resume seams in `test/core/lifecycle/app_lifecycle_recovery_test.dart` and `test/core/notifications/flutter_notification_service_test.dart`. |

### Edge Cases

#### 1:1 notification edge journeys

| Test ID | Scenario | Expected Result | Priority | Unit | Integration | Smoke | Fake Network | 2-party E2E | Current coverage / notes |
|---|---|---|---|---|---|---|---|---|---|
| DM-101 | Visible remote push plus later local replay | One message yields one user-visible notification path; later local replay does not materialize a second notification. | P0 | Required | Required | Recommended | Required | Recommended | Covered by `test/integration/chat_notification_dedupe_integration_test.dart` and `test/features/push/application/show_notification_use_case_test.dart`. |
| DM-102 | Delayed redelivery / retry of same message | The same `message_id` redelivered later still does not produce a second notification. | P0 | Required | Required | N/A | Required | Recommended | Current exact message-aware gate coverage exists in `test/core/notifications/recent_remote_notification_gate_test.dart`; a later-delivery end-to-end replay remains a high-value fake-network row. |
| DM-103 | Generic unnamed iOS fallback is suppressed | A routable iOS chat push with only routing data does not create the extra unnamed generic fallback when a visible remote push already exists. | P0 | Required | Required | Required | Recommended | Recommended | Covered by `test/features/push/application/background_push_notification_fallback_test.dart` and `test/features/push/application/background_message_handler_test.dart`. |
| DM-104 | Stale notification tap after message already seen | Tapping an older notification remains safe, routes to the conversation, and does not recreate duplicate local state. | P1 | Recommended | Required | Recommended | N/A | Required | Current closest evidence: `test/integration/notification_tap_smoke_test.dart`, `test/integration/notification_deeplink_integration_test.dart`. |
| DM-105 | Attachment-only/caption-first body text | Notification body uses caption-first semantics and stable media labels when text is empty. | P1 | Required | Recommended | N/A | N/A | Recommended | Covered by `test/features/push/application/notification_body_for_message_test.dart`. |

#### Group notification edge journeys

| Test ID | Scenario | Expected Result | Priority | Unit | Integration | Smoke | Fake Network | 3-party E2E | Current coverage / notes |
|---|---|---|---|---|---|---|---|---|---|
| GMN-101 | Visible remote push plus later local group replay | One group message yields one user-visible notification path; later local replay is suppressed. | P0 | Required | Required | Recommended | Required | Recommended | Covered by `test/integration/group_notification_dedupe_integration_test.dart` and `test/features/groups/application/group_message_listener_test.dart`. |
| GMN-102 | Removed member loses notification eligibility | After removal, C does not receive later group notifications or later group messages. | P0 | Required | Required | Required | Required | Required | Notification suppression side is covered by `test/features/groups/application/group_message_listener_test.dart`; end-to-end receive blocking is covered by `test/features/groups/integration/group_membership_smoke_test.dart`. |
| GMN-103 | Re-invited member regains notification eligibility only after rejoin | C stays silent while removed and starts receiving again only after rejoin becomes effective. | P0 | Required | Required | Required | Required | Required | Rejoin messaging is covered by `test/features/groups/integration/group_membership_smoke_test.dart`; exact notification-resume proof is still a gap. |
| GMN-104 | Offline member reconnect / drain | If C is offline, allowed post-reconnect delivery yields one notification/materialization path without duplicate replay. | P1 | Required | Required | N/A | Required | Recommended | Current mixed-path delivery coverage exists in `test/features/groups/integration/group_resume_recovery_test.dart`, but the exact notification row is still not direct. |
| GMN-105 | Group copy formatting remains truthful | Group notification title stays on the group and the body preserves `sender: text` semantics. | P1 | Recommended | Required | Recommended | N/A | Recommended | Covered by `test/features/groups/application/group_message_listener_test.dart` and `test/features/push/application/show_notification_use_case_test.dart`. |

### Preservation / Regression Cases

#### Supporting logic and regression seams

| Test ID | Seam | Expected Result | Priority | Unit | Integration | Smoke | Fake Network | Device E2E | Current coverage / notes |
|---|---|---|---|---|---|---|---|---|---|
| RG-001 | Route-target parsing from push payloads | Conversation, group, and other payloads resolve to the correct route target without losing IDs. | P0 | Required | Recommended | N/A | N/A | N/A | Covered by `test/core/notifications/notification_route_target_test.dart`, `test/core/notifications/notification_route_contract_matrix_test.dart`. |
| RG-002 | Recent remote announcement gate | The gate is message-aware, consumes once, and does not over-suppress unrelated messages. | P0 | Required | Recommended | N/A | Recommended | N/A | Covered by `test/core/notifications/recent_remote_notification_gate_test.dart`. |
| RG-003 | Background fallback dedupe gate | Repeated background fallback deliveries use a stable dedupe key and suppress repeats. | P0 | Required | Recommended | N/A | Recommended | N/A | Covered by `test/core/notifications/recent_background_notification_gate_test.dart`, `test/features/push/application/background_push_notification_fallback_test.dart`. |
| RG-004 | Notification service dismissal / clear | Tapped or resumed opens dismiss delivered notifications and clear failures do not break lifecycle recovery. | P0 | Required | Required | Recommended | N/A | Recommended | Covered by `test/core/notifications/flutter_notification_service_test.dart`, `test/core/lifecycle/app_lifecycle_recovery_test.dart`. |
| RG-005 | Local notification payload round-trip | Local notification payload survives show -> tap -> route for chat and group targets. | P0 | Recommended | Required | Recommended | N/A | Recommended | Covered by `test/core/notifications/app_root_notification_open_test.dart`, `test/integration/notification_deeplink_integration_test.dart`. |
| RG-006 | Removed -> rejoined notification eligibility transition | Group notification eligibility stays off while removed and becomes valid again only after rejoin state is current. | P0 | Required | Required | Recommended | Required | Required | Current state-transition ingredients exist across `test/features/groups/application/group_message_listener_test.dart` and `test/features/groups/integration/group_membership_smoke_test.dart`, but one row-owned regression still needs to be landed. |

### Current runnable bundles

These are the strongest repo-local suites to run today while true device E2E is
still only partly automated:

- Core notification routing / smoke:
  - `flutter test test/integration/notification_tap_smoke_test.dart`
  - `flutter test test/features/push/application/chat_and_group_push_open_flow_test.dart`
  - `flutter test test/integration/notification_deeplink_integration_test.dart`
- 1:1 notification correctness:
  - `flutter test test/features/push/application/show_notification_use_case_test.dart`
  - `flutter test test/integration/chat_notification_dedupe_integration_test.dart`
  - `flutter test test/features/push/application/background_push_notification_fallback_test.dart test/features/push/application/background_message_handler_test.dart`
- Group notification correctness:
  - `flutter test test/features/groups/application/group_message_listener_test.dart`
  - `flutter test test/integration/group_notification_dedupe_integration_test.dart`
  - `flutter test test/features/groups/integration/group_membership_smoke_test.dart test/features/groups/integration/group_resume_recovery_test.dart`
- Tray clearing / open behavior:
  - `flutter test test/core/notifications/flutter_notification_service_test.dart`
  - `flutter test test/core/lifecycle/app_lifecycle_recovery_test.dart`
  - `flutter test test/core/notifications/app_root_notification_open_test.dart test/features/identity/presentation/screens/startup_router_notification_open_test.dart`

Preservation / regression requirement:

- any future notification refactor should keep the above bundles green
- rows `SM-005`, `GMN-103`, `GMN-104`, and `RG-006` are the most important
  still-thin areas for future direct additions because they close the remaining
  removal/rejoin notification boundary
