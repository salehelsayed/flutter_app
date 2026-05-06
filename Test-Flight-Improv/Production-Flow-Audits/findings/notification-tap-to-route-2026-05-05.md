# Findings: notification-tap-to-route — 2026-05-05

Audit basis: commit `5fec83b3` on branch `new-background`, app version
`1.0.0+88`. Hardware-soak basis: Pixel 6 / Android 16 (API 36) receiver +
iPhone 17 Pro sim sender.

---

## Re-audit note — 2026-05-05 (force re-audit, same SHA 5fec83b3)

Full chain trace performed against committed HEAD. The `onNewIntent` fix
described in the suggested-fix below is present in the **working tree**
(un-committed local modification to `MainActivity.kt`) but is **not** in
the committed code at `5fec83b3`. The plugin source confirms the fix
would close this break: `FlutterLocalNotificationsPlugin.java:1907`
registers as an `OnNewIntentListener` via `ActivityPluginBinding`; once
`super.onNewIntent(intent)` propagates through `FlutterActivity`, the
plugin's listener fires and invokes `channel.invokeMethod("didReceiveNotificationResponse")`,
which reaches `_onNotificationResponse` → `onNotificationTap` → `_onNotificationTap`.
The remainder of the Dart chain (`_handleNotificationRouteTarget`, navigator.push
to `ConversationWired`/`GroupConversationWired`) is correctly wired for both
1:1 and group notification kinds. No new breaks found beyond the existing 001.
Commit the working-tree MainActivity.kt change and verify on hardware per
Standing Rule 2.1.

---

```yaml
id: notif-tap-2026-05-05-001
severity: high
what-user-sees: >
  When Alice has any chat open (e.g. user-C's), backgrounds the app, and
  receives a chat notification from Bob, tapping the notification
  foregrounds the app to whichever screen was last visible (user-C's
  chat) instead of routing to Bob's conversation. The user perceives
  this as "the wrong chat opened".
chain-break-at: >
  Android OS → flutter_local_notifications PendingIntent dispatch →
  Dart _onNotificationResponse callback. The plugin's tap callback is
  never invoked despite the notification being shown and the app
  resuming. With no callback, no payload reaches Dart, so
  _handleNotificationRouteTarget never runs and the app simply
  resumes to whichever route was last on top.
production-files:
  - android/app/src/main/kotlin/com/mknoon/app/MainActivity.kt
  - android/app/src/main/AndroidManifest.xml:20
  - lib/core/notifications/flutter_notification_service.dart:55
  - lib/main.dart:2367
flow-files-touched:
  - lib/main.dart:2307,2367
  - lib/core/notifications/flutter_notification_service.dart
  - lib/core/notifications/app_root_notification_open.dart
  - lib/features/push/application/prepare_notification_open_use_case.dart
  - lib/features/push/application/prepare_notification_route_target_use_case.dart
evidence:
  log-capture: /tmp/mknoon-pixel-logcat.log (6909 lines, hardware soak
    2026-05-05). NOTIFICATION_SHOWN at 11:53:13.343, [RESUME] _onResumed
    at 11:53:27.479, but NOTIFICATION_TAPPED, NOTIFICATIONS_CLEARED,
    and any route/navigation events are absent from the entire capture.
  dumpsys: After the tap, MainActivity's intent is
    `act=android.intent.action.MAIN cat=[LAUNCHER]` — no notification
    PendingIntent extras carried through.
suggested-fix: >
  Override onNewIntent in MainActivity.kt to forward the new intent to
  the FlutterEngine plugin registry / call setIntent(intent), so the
  flutter_local_notifications plugin can read the response and dispatch
  to onDidReceiveNotificationResponse. The bare MainActivity +
  launchMode="singleTask" combination drops the plugin's tap intent on
  Android 12+ (matches plugin GitHub issues #2023, #2287).
verifiable-only-by: hardware
status: open
related-docs:
  - Test-Flight-Improv/Group-Chat-Feature/lock-window-fix-followups-tdd-plan-2026-05-04.md  # Session N RED→GREEN→REFACTOR plan
  - Standing Rule 2.1 in the same TDD-plan addendum
```
