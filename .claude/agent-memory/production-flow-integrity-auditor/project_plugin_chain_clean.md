---
name: Dart notification chain past onNewIntent is correctly wired
description: Full chain trace 2026-05-05 confirmed that once onNewIntent dispatches to the plugin, the Dart-side chain for both 1:1 and group notification taps is correct
type: project
---

Deep chain trace performed on 2026-05-05 against flutter_local_notifications 18.0.1 + main.dart at SHA 5fec83b3:

- Plugin's `onNewIntent` (FlutterLocalNotificationsPlugin.java:1907) correctly checks `SELECT_NOTIFICATION` action and invokes `channel.invokeMethod("didReceiveNotificationResponse")`.
- Dart `_onNotificationResponse` (flutter_notification_service.dart:55) receives it, calls `onNotificationTap?.call(payload)`.
- `onNotificationTap` is assigned in `initState` (main.dart:2307) before any warm-start intent can arrive — safe ordering.
- Payload serialization: `NotificationRouteTarget.toPayload()` / `fromPayload()` round-trips correctly for all kinds (conversation, group, contactRequest, intros, post, postComment).
- Group notification key: `'group:$groupId'` used consistently in GroupMessageListener (line 362) and GroupConversationWired tracker (line 233) — no mismatch.
- Cold-start path (killed app): `getNotificationAppLaunchDetails()` reads `mainActivity.getIntent()` pre-Dart; `consumeInitialPayload()` guarded by `_initialPayloadConsumed` flag — no double-routing.
- `drainOfflineInbox()` guard: `if (!_currentState.isStarted) return` — safe to call before p2p node starts.

The ONLY break in the notification-tap-to-route flow is the missing `onNewIntent` override at committed HEAD.

**How to apply:** If a future audit finds the onNewIntent fix committed and the finding marked fixed, the rest of the chain does not need re-tracing unless flutter_local_notifications or main.dart notification wiring changes.
