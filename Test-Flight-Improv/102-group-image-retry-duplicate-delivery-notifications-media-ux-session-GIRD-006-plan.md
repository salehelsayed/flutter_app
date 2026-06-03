Status: accepted

# GIRD-006 - Group Image Notification Identity, Suppression, Fallback, and Tap Routing Plan

## Scope

Close only the notification-path gaps owned by `GIRD-006` from
`Test-Flight-Improv/102-group-image-retry-duplicate-delivery-notifications-media-ux-session-breakdown.md`:

- one logical group image send maps to at most one eligible visible notification across local listener replay, foreground remote drain, background fallback, and duplicate delivery
- active-group and muted-group suppression remain consistent for foreground/local replay paths
- background remote announcements are not consumed as visible notifications unless a visible remote notification already exists or local fallback display actually succeeds
- Android foreground/background fallback identity uses the canonical group route payload and stable message identity
- iOS repo-level APNs/NSE payload shape, preview/fallback, same-id duplicate behavior, re-minted-id behavior, and tap routing are proven without claiming real APNs delivery
- existing group notification-open routing and route-contract tests remain green

Out of scope:

- no sender retry, recipient logical dedupe, relay/native storage idempotency, or media unavailable UI changes unless a focused notification assertion exposes a direct regression
- no three-user simulator/device incident closure; that belongs to `GIRD-007`
- no real APNs background/terminated device-context claim; `GIRD-007` must classify or prove it
- no broad notification redesign or new route format beyond the existing `group:<groupId>|message:<messageId>` contract

## Current Contract

- Local group notifications use `NotificationRouteTarget.group(groupId, messageId: result.id).toPayload()`.
- Foreground remote group pushes drain the targeted group inbox before route handoff.
- Background data-only group pushes build a protected fallback with generic copy and the same canonical group payload.
- Background duplicate fallback suppression uses `RecentBackgroundNotificationGate`.
- Local replay suppression uses `RecentRemoteNotificationGate` only when a visible remote or local fallback announcement was actually made.
- iOS NSE preview dedupes by `type + messageId`; same-id duplicate decrypt is skipped, while a re-minted id remains independently decryptable.

## Device And Relay Proof Profile

- Session profile: `host-only` repo-level notification proof.
- Live availability checks run on `2026-05-31`:
  - `flutter devices --machine` showed supported host/device targets including macOS, Pixel 6, two physical iPhones, and booted iOS simulators `38FECA55-03C1-4907-BD9D-8E64BF8E3469`, `347FB118-10D0-40C8-A05B-B0C3BD6B8CCD`, `5BA69F1C-B112-47BE-B1FF-8C1003728C8F`, and `1B098DFF-6294-407A-A209-BBF360893485`.
  - `xcrun simctl list devices available` showed the same iOS 26.1 booted simulators plus additional shutdown iOS 26.2/26.5 fixtures.
- Required GIRD-006 closure evidence is host-side Flutter, Go, and Swift unit/build evidence. A single Flutter device id is not required for the focused host tests.
- Real APNs background/terminated delivery, OS coalescing, and device-context notification open are deferred to `GIRD-007` and must not be claimed here.

## Owner Files

Expected production files:

- `lib/features/push/application/background_message_handler.dart`
- `lib/features/push/application/background_push_notification_fallback.dart`
- `lib/features/push/application/show_notification_use_case.dart`
- `lib/features/groups/application/group_message_listener.dart`
- `lib/core/notifications/notification_route_target.dart`
- `go-relay-server/inbox.go`
- `ios/NotificationService/NotificationPreviewResolver.swift`

Expected test files:

- `test/features/push/application/background_message_handler_test.dart`
- `test/features/push/application/background_push_notification_fallback_test.dart`
- `test/features/push/application/show_notification_use_case_test.dart`
- `test/features/groups/application/group_message_listener_test.dart`
- `test/features/push/application/handle_foreground_remote_message_use_case_test.dart`
- `test/core/notifications/notification_route_target_test.dart`
- `test/core/notifications/notification_route_contract_matrix_test.dart`
- `test/features/push/application/chat_and_group_push_open_flow_test.dart`
- `go-relay-server/inbox_test.go`
- `ios/RunnerTests/NotificationPreviewResolverTests.swift`

## TDD Plan

1. Add RED Flutter tests:
   - background group fallback display failure must not mark `RecentRemoteNotificationGate`
   - successful background group fallback must mark `RecentRemoteNotificationGate` using the canonical group payload and message id
   - duplicate group background fallback with the same logical id must produce one visible fallback
   - foreground local group replay must suppress only an exactly announced same message and preserve different message ids
2. Add RED/preservation iOS NSE tests:
   - duplicate same-id group push keeps fallback and skips the second decrypt
   - re-minted-id group image retry decrypts independently and keeps the group thread identifier
3. Add RED/preservation Go tests if current relay payload coverage does not already prove canonical group push identity for data-only Android/APNs payloads.
4. Implement the smallest production change needed. Expected code change: mark recent remote announcements for data-only background fallback only after `_backgroundNotificationsPlugin.show(...)` succeeds; keep existing mark-before-return behavior for FCM pushes that already carry a visible `RemoteNotification`.
5. Run focused GREEN commands, then preservation gates.

## Verification Commands

Focused Flutter:

```bash
flutter test test/features/push/application/background_message_handler_test.dart --plain-name GIRD-006
flutter test test/features/push/application/background_push_notification_fallback_test.dart --plain-name GIRD-006
flutter test test/features/push/application/show_notification_use_case_test.dart --plain-name GIRD-006
flutter test test/features/groups/application/group_message_listener_test.dart --plain-name GIRD-006
flutter test test/features/push/application/handle_foreground_remote_message_use_case_test.dart --plain-name GIRD-006
flutter test test/core/notifications/notification_route_target_test.dart --plain-name GIRD-006
flutter test test/core/notifications/notification_route_contract_matrix_test.dart --plain-name GIRD-006
flutter test test/features/push/application/chat_and_group_push_open_flow_test.dart --plain-name GIRD-006
```

Direct preservation Flutter:

```bash
flutter test \
  test/features/push/application/background_message_handler_test.dart \
  test/features/push/application/background_push_notification_fallback_test.dart \
  test/features/push/application/show_notification_use_case_test.dart \
  test/features/groups/application/group_message_listener_test.dart \
  test/features/push/application/handle_foreground_remote_message_use_case_test.dart \
  test/core/notifications/notification_route_target_test.dart \
  test/core/notifications/notification_route_contract_matrix_test.dart \
  test/features/push/application/chat_and_group_push_open_flow_test.dart
```

Go:

```bash
cd go-relay-server && go test ./... -run 'GIRD006|BuildGroupPushMessage|HandleInboxStream_GroupStoreFansOutPushToRecipientsWithTokens|GroupInbox'
```

iOS repo-level NSE:

```bash
xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner \
  -destination 'platform=iOS Simulator,id=5BA69F1C-B112-47BE-B1FF-8C1003728C8F' \
  CODE_SIGNING_ALLOWED=NO \
  -only-testing:RunnerTests/NotificationPreviewResolverTests
```

Named gates and hygiene:

```bash
./scripts/run_test_gates.sh groups
./scripts/run_test_gates.sh runtime-telemetry
git diff --check
```

Run `transport` only if startup, reconnect, bridge, or notification-open app bootstrap wiring changes.

## Done Criteria

- RED evidence is recorded before production edits for at least one real GIRD-006 notification gap.
- Focused GREEN evidence proves local, foreground, background fallback, remote gate, tap route, relay payload, and iOS NSE duplicate behavior.
- Active-group and muted-group suppression remain covered by direct listener/show-notification tests.
- Real APNs device delivery is explicitly deferred to `GIRD-007` and not claimed.
- This plan and the breakdown ledger classify GIRD-006 as accepted, residual-only with follow-up, or blocked with command evidence.

## Execution Log

- `2026-05-31 21:35 CEST` - Spawned planner created only a `planning-intake` stub and no execution-safe plan after bounded waits; controller closed the no-progress agent and used the pipeline local plan fallback.
- `2026-05-31 21:44 CEST` - Local fallback plan written after inspecting notification map, GIRD-006 breakdown scope, background/local/foreground notification code, current tests, live device availability, and gate definitions.
- `2026-05-31 21:47 CEST` - RED evidence captured before the production change: `flutter test test/features/push/application/background_message_handler_test.dart --plain-name GIRD-006` failed because `GIRD-006 does not mark remote announcement when group fallback display fails` expected no recent remote mark but found one.
- `2026-05-31 21:51 CEST` - Implemented the minimal notification fix in `lib/features/push/application/background_message_handler.dart`: visible FCM notifications still mark the recent remote gate immediately, but data-only group fallback now marks the gate only after local fallback display succeeds. Failed fallback display no longer suppresses later in-app replay.
- `2026-05-31 21:56 CEST` - Focused GREEN evidence passed:
  - `flutter test test/features/push/application/background_message_handler_test.dart --plain-name GIRD-006`
  - `flutter test test/features/push/application/background_push_notification_fallback_test.dart --plain-name GIRD-006`
  - `flutter test test/features/push/application/show_notification_use_case_test.dart --plain-name GIRD-006`
  - `flutter test test/features/groups/application/group_message_listener_test.dart --plain-name GIRD-006`
  - combined focused Flutter command across background handler, fallback, show-notification, listener, foreground drain, route target, route contract, and push-open suites with `10` GIRD-006 tests passing.
- `2026-05-31 21:56 CEST` - Relay payload proof passed with `cd go-relay-server && go test ./... -run 'GIRD006|BuildGroupPushMessage|HandleInboxStream_GroupStoreFansOutPushToRecipientsWithTokens|GroupInbox'`.
- `2026-05-31 21:56 CEST` - iOS repo-level NSE proof passed with `xcodebuild test -workspace ios/Runner.xcworkspace -scheme Runner -destination 'platform=iOS Simulator,id=5BA69F1C-B112-47BE-B1FF-8C1003728C8F' CODE_SIGNING_ALLOWED=NO -only-testing:RunnerTests/NotificationPreviewResolverTests`.
- `2026-05-31 21:56 CEST` - Direct preservation Flutter command across the eight touched notification/listener/route suites passed with `301` tests.
- `2026-05-31 21:56 CEST` - Named gates and hygiene passed: `./scripts/run_test_gates.sh groups` with `313` tests, `./scripts/run_test_gates.sh runtime-telemetry` with `4` tests, `dart format --set-exit-if-changed ...` with `0` pending changes, and `git diff --check`.

## Final Execution Verdict

- Verdict: `accepted`.
- Closed GIRD-006 scope:
  - Android/background data-only fallback no longer records a visible remote announcement unless the fallback display succeeds.
  - Duplicate background fallback, foreground/local replay suppression, active/mute-adjacent local behavior, canonical group route payloads, foreground group push drain, and notification tap route preparation are covered by focused Flutter tests.
  - Relay group push payload identity is covered by Go tests.
  - iOS repo-level NSE duplicate same-id versus re-minted-id behavior is covered by `NotificationPreviewResolverTests`.
- Residual boundary:
  - Real APNs background/terminated delivery, OS coalescing, and device-context notification-open proof remain explicitly deferred to `GIRD-007`; no GIRD-006 evidence claims that device-context path.
- Blockers:
  - None for GIRD-006.
