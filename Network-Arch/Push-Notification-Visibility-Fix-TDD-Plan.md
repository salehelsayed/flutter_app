# Push Notification Visibility Fix — TDD Plan

Prepared on: 2026-03-22
Status: Proposed
Scope: Fix visible push notification delivery on both iOS and Android when the
app is backgrounded or killed. Supplements the main Push-Notifications-1to1-
Group-TDD-Plan.md.

## Problem Statement

Two bugs prevent users from seeing push notifications:

1. **iOS**: The `firebaseMessagingBackgroundHandler` in
   `lib/features/push/application/background_message_handler.dart` checks
   `!Platform.isAndroid` and returns immediately on iOS. No local notification
   is ever shown. The relay's APNS alert payload should trigger a system
   notification, but `content-available: true` combined with a data message
   causes iOS to treat it as a silent push.

2. **Android**: The relay's `buildChatPushMessage()` in
   `go-relay-server/inbox.go` sends a data-only FCM message (no top-level
   `Notification` field on the `Message` struct). The `AndroidConfig.Notification`
   is a platform-specific override but FCM still classifies the message as
   data-only. This means:
   - The system does not automatically display a notification.
   - The background handler must run and show a local notification.
   - OEM battery optimizations (Samsung, Xiaomi, Huawei, etc.) can prevent
     the background handler from running when the app is killed or swiped away.
   - Adding a top-level `Notification` field makes FCM treat the message as a
     notification message, which Android displays automatically even when the
     app is killed.

## Relationship To Main TDD Plan

The main Push-Notifications-1to1-Group-TDD-Plan.md Phase 3 refactors
`buildPushMessage()` but does not specify adding a top-level `Notification`
field. Phase 5 hardens local notifications but does not address the iOS
platform guard.

This plan can be executed:
- **Before** the main plan (as an immediate hotfix for TestFlight/Play testers)
- **During** Phase 3 of the main plan (incorporated into the relay push builder
  refactoring)

The changes here are backward-compatible and do not conflict with any phase of
the main plan.

---

## Phase A: Fix iOS Background Handler

### Goal

Remove the platform guard so iOS shows local notifications from the background
handler, identical to Android.

### Inspect First

- `lib/features/push/application/background_message_handler.dart`
- `lib/features/push/application/background_push_notification_fallback.dart`
- `lib/core/notifications/local_notification_support.dart`
- `test/features/push/application/background_message_handler_test.dart`

### RED

Extend: `test/features/push/application/background_message_handler_test.dart`

1. On iOS, a data-only RemoteMessage with `type=new_message` triggers a local
   notification via `flutter_local_notifications`.
2. On iOS, a data-only RemoteMessage with `type=group_message` triggers a local
   notification with the correct group payload.
3. On iOS, a RemoteMessage that already has a `notification` field does NOT
   show a duplicate local notification (the `shouldShowBackgroundPushFallback
   Notification` guard).
4. On iOS, a RemoteMessage with no routable data keys does NOT show a
   notification.

### GREEN

In `background_message_handler.dart`, change:

```dart
// BEFORE
if (!Platform.isAndroid ||
    !shouldShowBackgroundPushFallbackNotification(message)) {
  return;
}

// AFTER
if (!shouldShowBackgroundPushFallbackNotification(message)) {
  return;
}
```

This is a one-line deletion. The rest of the handler (initialize local
notifications, build fallback notification, call `plugin.show()`) already
supports iOS via `DarwinNotificationDetails` in `local_notification_support.dart`.

### REFACTOR

- Remove any iOS-specific comments that reference "inbox drain deferred to next
  app resume" as the only iOS strategy.
- Keep the `shouldShowBackgroundPushFallbackNotification` guard to prevent
  duplicate notifications when a system-displayed notification is already present.

### Exit Gate

- `flutter test test/features/push/application/background_message_handler_test.dart`

---

## Phase B: Add Top-Level Notification Field To Relay Push Messages

### Goal

Make FCM classify push messages as notification messages so Android's system
displays them automatically, even when the app is killed or the background
handler is suppressed by OEM battery optimization.

### Inspect First

- `go-relay-server/inbox.go` — `buildChatPushMessage()` (and
  `buildGroupPushMessage()` if it exists from the main plan)
- `go-relay-server/inbox_test.go`

### RED

Extend: `go-relay-server/inbox_test.go`

1. `buildChatPushMessage()` result has a non-nil top-level `Notification` with
   `Title` and `Body` matching the request.
2. `buildChatPushMessage()` result preserves the existing `Data` map with
   `type`, `from`, `title`, `body`.
3. `buildChatPushMessage()` result preserves the existing
   `Android.Notification` with `ChannelID`.
4. `buildChatPushMessage()` result preserves the existing `APNS.Payload.Aps`
   with `Alert` and `ContentAvailable`.
5. If `buildGroupPushMessage()` exists, same assertions for group push with
   `type=group_message` and `groupId`.

### GREEN

In `go-relay-server/inbox.go`, add a top-level `Notification` field to the
`Message` struct returned by `buildChatPushMessage()`:

```go
return &messaging.Message{
    Token: req.Token,
    // ADD THIS — makes FCM treat this as a notification message
    Notification: &messaging.Notification{
        Title: title,
        Body:  body,
    },
    Data: map[string]string{
        "type":  "new_message",
        "from":  req.FromPeerID,
        "title": title,
        "body":  body,
    },
    Android: &messaging.AndroidConfig{
        Priority: "high",
        Notification: &messaging.AndroidNotification{
            Title:     title,
            Body:      body,
            ChannelID: channelID,
        },
    },
    APNS: &messaging.APNSConfig{
        Headers: map[string]string{
            "apns-priority":  "10",
            "apns-push-type": "alert",
        },
        Payload: &messaging.APNSPayload{
            Aps: &messaging.Aps{
                ContentAvailable: true,
                Alert: &messaging.ApsAlert{
                    Title: title,
                    Body:  body,
                },
            },
        },
    },
}
```

Apply the same change to `buildGroupPushMessage()` if it exists.

### Impact On Flutter Background Handler

With a top-level `Notification` field:

- **Android background/killed**: System automatically displays the notification.
  `message.notification` will be non-null. The `shouldShowBackgroundPush
  FallbackNotification` check returns `false`, correctly avoiding a duplicate
  local notification.
- **Android foreground**: `onMessage` fires. The notification is NOT auto-
  displayed (standard FCM behavior). The foreground listener drains the inbox.
- **iOS background**: System displays the APNS alert. The background handler
  also fires. `message.notification` may be non-null depending on how
  FlutterFire maps the payload, so the fallback guard may skip the local
  notification (avoiding duplicates). If `message.notification` is null (data-
  only path), the Phase A fix ensures a local notification is shown.
- **iOS foreground**: `onMessage` fires. `setForegroundNotificationPresentation
  Options(alert: false)` suppresses the system banner. The foreground listener
  drains the inbox.

No changes needed to the Flutter background handler beyond Phase A.

### REFACTOR

- Keep the `Data` map intact for routing (`type`, `from`, `groupId`).
- Keep platform-specific overrides (`Android.Notification.ChannelID`,
  `APNS.ContentAvailable`) alongside the top-level `Notification`.
- The top-level `Notification` is the baseline; platform overrides customize.

### Exit Gate

- `cd go-relay-server && go test ./...`

---

## Phase C: Verify End-To-End On Devices

### Goal

Confirm visible notifications appear on real iOS and Android devices in all
app states.

### Test Matrix

| # | Scenario | Expected |
|---|----------|----------|
| 1 | iOS app backgrounded, 1:1 message via relay | Visible banner notification |
| 2 | iOS app killed (not force-quit), 1:1 message | Visible banner notification |
| 3 | iOS app force-quit (swiped from switcher) | No notification (platform limitation) |
| 4 | Android app backgrounded, 1:1 message via relay | Visible notification in system tray |
| 5 | Android app killed/swiped, 1:1 message via relay | Visible notification in system tray |
| 6 | Android app foregrounded, 1:1 message via relay | No notification banner; message appears in feed |
| 7 | iOS notification tap opens correct conversation | Conversation screen with message visible |
| 8 | Android notification tap opens correct conversation | Conversation screen with message visible |

### Relay Log Verification

For each test, confirm in relay logs:

```
journalctl -u mknoon-relay | grep PUSH | tail -10
```

- `[PUSH] Token registered for <peerId>` — token is registered
- `[PUSH] Notification sent to <peerId>` — push was delivered to FCM
- No `[PUSH] Failed to send` errors

### Device Notification Settings Verification

- iOS: Settings → mknoon → Notifications → Allow Notifications ON, Banners ON
- Android: Settings → Apps → mknoon → Notifications → enabled, channel
  "Messages" enabled

### Exit Gate

- All 8 test matrix scenarios pass on physical devices
- Relay logs confirm successful push delivery

---

## Recommended Implementation Order

1. **Phase A** (Flutter, one-line fix, immediate)
2. **Phase B** (Relay server, add top-level Notification field, deploy)
3. **Phase C** (Manual verification on devices)

Phase A is already applied in the current working tree. Phase B requires a
relay server code change and redeployment. Phase C is manual verification.

## Interaction With Main TDD Plan

- Phase A should be merged before or during main plan Phase 5.
- Phase B should be merged before or during main plan Phase 3.
- If the main plan's Phase 3 refactors `buildChatPushMessage()`, incorporate
  the top-level `Notification` field into that refactoring.
- No conflicts exist — all changes are additive.
