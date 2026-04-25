# 75 - iOS Background Push Notifications Are Silent

## 1. Title and Type

- Title: iOS background push notifications are silent
- Issue type: `bug`
- Output doc path: `Test-Flight-Improv/75-ios-background-push-sound.md`

## 2. Problem Statement

Users want incoming message notifications to make a sound when mknoon is not the active app, so they notice new messages without watching the screen.

Today, Android notifications can be heard, but iPhone notifications can arrive visibly without audible sound. The desired behavior is not "always noisy": when the user is actively using the app, especially while chatting, notification sound should stay silent or suppressed.

This is a problem because iPhone users can miss background messages even though the notification itself appears, while foreground users should not be interrupted by sounds during active conversations.

## 3. Impact Analysis

- Affected users: iOS users receiving 1:1 or group message notifications while the app is backgrounded, locked, or otherwise not actively in use.
- Affected flows: relay-built APNs message pushes, encrypted 1:1 message pushes, group message pushes, background local fallback notifications, foreground push handling, and active-conversation notification suppression.
- Severity: high for message awareness on iOS because the notification can be visible but easy to miss.
- Frequency: applies whenever an iOS message notification relies on the current APNs alert payload that has no audible notification intent.
- User-visible cost: Android and iOS feel inconsistent; iPhone users may believe notifications are broken or unreliable.
- Regression risk: adding background sound must not make the app noisy while the user is already in the app or viewing the active conversation.

## 4. Current State

- `go-relay-server/inbox.go` builds APNs alert payloads for user-visible message pushes. `buildPushMessage` sets APNs headers and an alert but does not set an APNs sound value.
- `go-relay-server/inbox.go` also builds ciphertext-only 1:1 and group message APNs payloads through `buildCiphertextOnlyPushMessage`; those payloads set `content-available`, `mutable-content`, and fallback alert copy, but no APNs sound value.
- `go-relay-server/inbox_test.go` checks APNs alert presence, priority, `content-available`, and `mutable-content` for encrypted message pushes, but does not assert audible iOS behavior.
- `lib/main.dart` registers the Firebase background handler and sets foreground presentation options with `sound: false`, so foreground remote presentation is intentionally quiet.
- `lib/core/notifications/local_notification_support.dart` defines the app's shared local notification details. Android uses high importance and `playSound: true`; iOS local notification details use `presentSound: true`, `presentAlert: true`, and `presentBadge: true`.
- `test/core/notifications/local_notification_support_test.dart` already checks the Android and iOS local notification sound configuration.
- `lib/features/push/application/request_push_permission_use_case.dart` requests Firebase notification permission with `sound: true`.
- `ios/Runner/AppDelegate.swift` logs native iOS notification settings, including `soundSetting`, and registers for remote notifications.
- `ios/NotificationService/NotificationService.swift` and `ios/NotificationService/NotificationPreviewResolver.swift` rewrite notification title/body/thread for encrypted previews but do not define sound behavior.
- `lib/features/push/application/show_notification_use_case.dart` suppresses local notifications when the app is resumed and the user is viewing the relevant conversation.
- `test/features/push/application/show_notification_use_case_test.dart` covers background local notification display and active/recent-remote suppression behavior, but does not prove background iOS audibility.
- `test/features/push/application/background_message_handler_test.dart` covers routable background data-only push fallback and an iOS local fallback show call, but does not assert the final iOS notification is audible only in background.
- `test/integration/notification_tap_smoke_test.dart` covers background fallback show-to-tap routing, but not sound.
- `Test-Flight-Improv/notification-sound-smoke-plan.md` previously identified notification sound smoke coverage needs for 1:1, group discussion, group announcement, and suppression controls. It focused on local notification smoke evidence and explicitly left Firebase remote-push background sound outside that plan.
- `Test-Flight-Improv/74-privacy-preserving-notification-previews.md` defines adjacent notification-preview behavior and states that active conversation notification suppression should remain preserved.

## 5. Scope Clarification

- In scope: iOS message notifications should be audible when the app is not active and the notification is user-visible.
- In scope: 1:1 message notifications and group message notifications, including encrypted/ciphertext-only APNs payloads.
- In scope: preserving foreground quiet behavior while the user is actively using the app.
- In scope: preserving active-conversation suppression so users do not hear notification sounds for the chat they are already viewing.
- In scope: Android parity checks that confirm Android remains audible and unchanged.
- In scope: regression, unit, integration, smoke, and simulator acceptance evidence for the user-visible behavior.
- Non-goal: changing message preview privacy, notification title/body copy, notification tap routing, inbox drain routing, or message encryption semantics.
- Non-goal: adding a new in-app sound preference surface.
- Non-goal: changing muted chat or muted group semantics.
- Non-goal: requiring sound while iOS Focus, silent mode, user notification settings, or app-specific sound permission disables sound.
- Accepted ambiguity: exact product copy for any notification remains unchanged by this spec.
- Accepted ambiguity: whether foreground app-open but off-conversation notifications should stay fully silent or later become user-configurable remains open; this bug requires no noisy foreground regression.

## 6. Test Cases

### Happy Path

- iOS background 1:1 sound: when Alice sends Bob a 1:1 message and Bob's iPhone has mknoon backgrounded with notification sounds allowed, Bob receives a visible notification with an audible notification sound.
- iOS background group sound: when Alice sends a group message and Bob's iPhone has mknoon backgrounded with notification sounds allowed, Bob receives a visible group notification with an audible notification sound.
- iOS encrypted fallback sound: when a message notification uses generic fallback copy because the recipient preview cannot be resolved before display, the background notification is still audible.
- Android parity: when Bob receives the same message types on Android, existing audible notification behavior remains unchanged.

Required acceptance evidence:

- Unit evidence for the deterministic notification-sound contract on relay-built iOS message notification payloads and existing local notification detail objects.
- Integration evidence that 1:1 and group message notification paths keep routing, dedupe, and notification visibility while satisfying the background-audible expectation.
- Smoke evidence across 1:1, group discussion, group announcement, and active-conversation suppression journeys.
- Simulator evidence for iOS foreground/background lifecycle behavior: background visible notifications are audible, while foreground active-chat delivery stays silent or suppressed.
- Regression evidence that Android audible notifications, iOS permission requests, APNs registration, encrypted preview rewriting, and notification tap routing still work.

### Edge Cases

- Active conversation open: when Bob is already viewing Alice's conversation and Alice sends a new 1:1 message, Bob does not hear a notification sound for that already-open chat.
- Foreground app open: when Bob has mknoon open and receives a push outside the active chat, the app does not introduce unexpected foreground noise unless a future product setting explicitly allows it.
- Muted group: when Bob has muted a group, a new group message does not become audible because the iOS background sound bug is fixed.
- Recent remote duplicate: when a remote push has already announced a message, later local replay does not create a duplicate audible notification for the same message.
- Missing or denied sound permission: when iOS notification sound permission is disabled, the app does not claim the notification was audibly delivered.
- Notification Service Extension fallback: when the iOS notification service extension cannot decrypt or rewrite preview copy, the visible fallback notification still follows the expected background sound behavior.
- Malformed or unroutable push data: malformed notification data does not produce an audible notification that cannot be opened to a meaningful destination.

### Regressions To Preserve

- Bug regression: an iOS background message notification must not regress to visible-but-silent delivery when the user's iOS notification sound settings allow sound.
- Preservation/regression: foreground remote presentation remains quiet; the existing `sound: false` foreground expectation does not regress into noisy app-open push presentation.
- Preservation/regression: active-conversation notification suppression remains in force for 1:1 chats and groups.
- Preservation/regression: notification tap routing still opens the correct conversation, group, contact request, introduction, or supported notification target.
- Preservation/regression: encrypted 1:1 and group notification preview rewriting keeps its existing title/body/thread behavior.
- Preservation/regression: background local fallback dedupe continues to prevent duplicate notifications for repeated delivery of the same message.
- Preservation/regression: Android notification channel behavior remains high-priority and audible for message notifications.
- Preservation/regression: iOS APNs registration and sound permission request behavior remains observable through existing diagnostics.

Current partial coverage:

- `go-relay-server/inbox_test.go` partially covers APNs payload structure for 1:1, encrypted 1:1, and group pushes, but not audible iOS behavior.
- `test/core/notifications/local_notification_support_test.dart` partially covers local Android/iOS notification sound settings.
- `test/features/push/application/show_notification_use_case_test.dart` partially covers background local notification display and active/recent-remote suppression.
- `test/features/push/application/background_message_handler_test.dart` partially covers background fallback local notification display, including iOS show-call coverage.
- `test/integration/notification_tap_smoke_test.dart` partially covers fallback notification show-to-tap routing.
- `test/features/push/application/handle_foreground_remote_message_use_case_test.dart` partially covers foreground push routing and drain behavior, not sound.
- `test/features/push/application/ios_push_project_config_test.dart` partially covers iOS push project configuration and APNs registration diagnostics.

Known coverage gaps:

- No current unit test asserts that relay-built iOS message notification payloads carry an audible background notification contract.
- No current integration test proves that iOS background 1:1 and group message notifications remain visible, routable, deduped, and audible.
- No current smoke test records background-audible pass/fail for both 1:1 and group message journeys while also proving active-chat silence.
- No current simulator-level acceptance covers foreground versus background iOS sound behavior for the same notification family.
- No current regression case catches the exact user-visible bug: iPhone notification appears but makes no sound while notification sound settings allow sound.
