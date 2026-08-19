# 385 — Push permission gate reports `authorized` while POST_NOTIFICATIONS is revoked

Status: OPEN — production bug, accepted as a defect (owner decision 2026-08-18). Not scheduled.
Type: Bug finding (no fix attempted)
Found by: Plan 380 device execution, `tc_g7_permission_denied`, 2026-08-18
Blocks: Plan 380 `tc_g7_permission_denied` and the three G7 legs queued behind it
Tier: device-observed, host-reproducible seam

---

## 1. The bug in one paragraph

When the user turns notifications off for the app, the app does not notice. Its push
permission gate asks Firebase Messaging whether notifications are allowed, gets back
`authorized`, and proceeds as if everything is healthy. Nothing records the denial, no
health warning is raised, no settings banner is shown, and push registration reports
success. The app then posts notifications blind and the OS silently discards every one
of them.

## 2. Evidence (measured, `emulator-5554`, Android 17 / SDK 37, 2026-08-18)

**The OS really has notifications off.** Reproduced twice, on a live device:

```
adb shell pm revoke <pkg> android.permission.POST_NOTIFICATIONS
  dumpsys notification →  AppSettings: <pkg> (10238) importance=NONE    userSet=false
adb shell pm grant  <pkg> android.permission.POST_NOTIFICATIONS
  dumpsys notification →  AppSettings: <pkg> (10238) importance=DEFAULT userSet=false
```

`importance=NONE` is the OS saying "this app may not post". This is not ambiguous.

**In that exact state, the app says the opposite.** From the campaign's own run
(permission revoked and verified not-granted immediately beforehand, then the app
terminated and relaunched so the coordinator would re-evaluate):

```
[FLOW] PUSH_PERMISSION_REQUEST_RESULT  {"status":"authorized","granted":true}
[FLOW] PUSH_REGISTER_COORDINATOR_SUCCESS {"trigger":"startup"}
```

Whole-run census on the receiver:

| Event | Count |
|---|---|
| `PUSH_REGISTER_COORDINATOR_SUCCESS` | 9 |
| `PUSH_PERMISSION_REQUEST_RESULT status=authorized granted=true` | 4 |
| **`PUSH_REGISTER_COORDINATOR_PERMISSION_DENIED`** | **0** |

## 3. Where it goes wrong

`lib/features/push/application/request_push_permission_use_case.dart:5-41`

```dart
final effectiveRequestPermission =
    requestPermissionFn ??
    () => FirebaseMessaging.instance.requestPermission(
      alert: true, badge: true, sound: true,
    );
final settings = await effectiveRequestPermission();
final granted =
    settings.authorizationStatus == AuthorizationStatus.authorized ||
    settings.authorizationStatus == AuthorizationStatus.provisional;
return granted;   // ← returns true with POST_NOTIFICATIONS revoked
```

That boolean is the ONLY thing standing between the app and its entire denied-handling
branch. `lib/features/push/application/push_registration_coordinator.dart:204-226`:

```dart
if (checkPermission || _permissionState == _PushPermissionState.unknown) {
  final granted = await requestPermission();        // ← true
  _permissionState = granted ? granted : denied;
  if (!granted) {                                    // ← never entered
    await _publishAndPersistHealth(PushRegistrationHealthRecord.permissionDenied(...));
    emitFlowEvent(event: 'PUSH_REGISTER_COORDINATOR_PERMISSION_DENIED', ...);
    return;
  }
}
```

So the durable health record, the diagnostic, the FLOW event, and the early return are
all dead code whenever the plugin lies. Downstream, the health notifier never surfaces
`permissionDenied`, so the user-facing warning and its `openNotificationSettings` action
never appear either.

Versions in play: `firebase_messaging 15.2.10`, `firebase_messaging_platform_interface
4.6.10`, device Android 17 / SDK 37.

## 4. Why it matters (user impact, not test debt)

1. A user who declines or later revokes the notification permission gets **no feedback
   at all** — the app's own health surface says push is fine.
2. The app keeps registering its FCM token with the relay, so the relay keeps sending
   pushes that can never be displayed. Wasted delivery, and misleading relay metrics.
3. The "notifications aren't working" support path is defeated: the in-app banner that
   would deep-link the user to the OS settings screen is gated on exactly the state that
   never gets recorded.

## 5. What I did NOT verify — read this before fixing

I did not read the `firebase_messaging` Android plugin source to establish *why* it
returns `authorized`. Plausible candidates, in the order I would check them:

- the plugin returns the pre-existing `NotificationManagerCompat` state rather than
  performing a fresh runtime request;
- `requestPermission()` short-circuits to `authorized` when the permission has already
  been requested once in the app's lifetime;
- the USER_FIXED flag makes the request return "no dialog needed", which the plugin maps
  to authorized rather than denied.

Do not assume it is a plugin bug. It may be a plugin API whose Android semantics simply
differ from the iOS semantics this code was written against, in which case the fix
belongs in our code, not theirs.

**Suggested direction (unvalidated):** read the real OS state instead of trusting the
request result — `NotificationManagerCompat.areNotificationsEnabled()` via a platform
channel, or `Permission.notification.status` from `permission_handler` (already a repo
dependency) — and treat a permission REQUEST as a separate action from a permission
CHECK. The coordinator wants a check; today it calls a request.

## 6. How to reproduce in ~2 minutes

```bash
# with the production_fcm build installed and running on emulator-5554
adb -s emulator-5554 shell pm revoke com.mknoon.app android.permission.POST_NOTIFICATIONS
adb -s emulator-5554 shell pm set-permission-flags com.mknoon.app \
    android.permission.POST_NOTIFICATIONS user-fixed
adb -s emulator-5554 shell dumpsys notification --noredact | grep "AppSettings: com.mknoon.app"
#   → importance=NONE   (OS: notifications OFF)

adb -s emulator-5554 shell am force-stop com.mknoon.app   # or the campaign's am kill
adb -s emulator-5554 logcat -c
adb -s emulator-5554 shell am start -W -n com.mknoon.app/.MainActivity
adb -s emulator-5554 logcat -d | grep -E "PUSH_PERMISSION_REQUEST_RESULT|PERMISSION_DENIED"
#   → status=authorized granted=true, and zero PERMISSION_DENIED

# restore
adb -s emulator-5554 shell pm clear-permission-flags com.mknoon.app \
    android.permission.POST_NOTIFICATIONS user-fixed
adb -s emulator-5554 shell pm grant com.mknoon.app android.permission.POST_NOTIFICATIONS
```

## 7. The test that is currently red on purpose

`tc_g7_permission_denied` in `notifications.android_payload_campaign`
(`integration_test/scripts/notification_android_payload_campaign.dart`,
`_runPermissionDeniedLeg`). Per the owner's decision it has **not** been narrowed — it
still asserts the correct behaviour and will stay red until this bug is fixed.

Its four checks:

| Check | Meaning | Status |
|---|---|---|
| `g7.permission_denied_typed_health` | coordinator records the typed denial | **RED — this bug** |
| `g7.permission_denied_no_post` | no card appears on any channel | not reached |
| `g7.permission_custody_preserved` | the message survives and converges | not reached |
| `g7.permission_regrant_recovery` | re-granting restores an audible card | not reached |

The leg is also gated on a post-attempt marker (`NOTIFICATION_SHOWN` /
`PUSH_BACKGROUND_NOTIFICATION_SHOWN`) before its zero-card census, so once the health
bug is fixed the remaining three checks should be meaningful immediately.

## 8. Related, and explicitly NOT the same thing

Plan 383 (killed-app typed-event deferral) is a different defect in a different file. It
is fixed and I confirmed it working in the same run: `PUSH_BACKGROUND_DURABLE_EFFECT_DEFERRED
{"presentation":"nondurable_fallback"}` is now followed by `PUSH_BACKGROUND_NOTIFICATION_SHOWN`
every time (4 deferrals, 5 shown). Do not conflate the two — 383 touches
`background_message_handler.dart`; this bug is in the permission seam and 383 never
mentions permissions.
