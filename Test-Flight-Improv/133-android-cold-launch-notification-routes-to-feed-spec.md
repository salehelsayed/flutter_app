# 133 — Android: tapping a 1:1 message notification on COLD START routes to Feed, not the conversation

Status: **FIXED + ANDROID DEVICE-VERIFIED (2026-06-19).** iOS cold-tap regression check still advised.

> **Android device verification PASSED (2026-06-19, Pixel 6, debug build w/ the fix):** killed the app,
> sent `coldtest` from the iPhone (→ relay inbox, status `inboxed`), tapped the notification → the app
> cold-launched directly into the **iPhone/Hashkobly conversation showing `coldtest`** (NOT Feed).
> Logcat showed the fix's signature ordering — `route_pushed` (home) THEN `CONV_FL_SCREEN_INIT` (the
> conversation, on top), `CONV_FL_MESSAGES_LOADED`, then `CHAT_MSG_RECEIVE_STORED coldtest` — with NO
> `NOTIFICATION_ROUTE_HOME_READY_FALLBACK` (the normal home-ready signal drove it, not the safety net).
> NOTE (minor follow-up): the cold-launch *initial* notification path does not stamp
> `_notificationTappedAt`, so 131's explicit `notif_tap` drain-refetch didn't engage on cold launch —
> `coldtest` still surfaced via 131's repo-change incoming filter / live append. Consider stamping
> `_notificationTappedAt` on the initial-launch path so the stronger notif_tap recovery also runs on
> cold launch.
Discovered during the on-device verification of findings 131/132 (iPhone 00008110 ↔ Pixel 6
`21071FDF600CSC`, prod relay). Distinct from 131 (which assumes the tap *does* open the conversation,
just stale) and unrelated to the 131/132 code changes (notification routing was never touched).

## ROOT CAUSE (confirmed by a graph-first source trace — supersedes the hypotheses below)
A **startup route race**, NOT contact-resolution and NOT the iOS bridge. Two independent producers
fight for the navigator on cold start:
1. The deferred notification flush `navigator.push`es `ConversationWired` (`main.dart`
   `_openConversationForContact`).
2. `StartupRouter._routeBasedOnIdentity` independently does `Navigator.pushReplacement(home)` after
   `WidgetsBinding.instance.endOfFrame` (`startup_router.dart:1011-1021`, the single home funnel
   `_pushStartupReplacement`, called from the 5 terminal startup routes).

On **Android** the ordering resolves as: conversation pushed first → then the home `pushReplacement`
**clobbers** it → user lands on Feed. On **iOS** the engine warm-up/`endOfFrame` cadence differs and
the conversation push survives. So **H4 holds (push-then-replaced) with H2 as the cause (unsynchronized
flush vs home build)**. **H1 (contact-null) and H3 (iOS-bridge derail) are REFUTED**: the contact DB is
already open at flush time, and the iOS bridge self-catches its `MissingPluginException` and is isolated
from the local-tap route (pure log noise). iOS uses the SAME Dart local path (its AppDelegate excludes
`fln` payloads from the APNs bridge), confirming the divergence is purely the per-platform frame race.

## FIX IMPLEMENTED (host-green; Android device-verify pending)
- **(A) noise:** `Platform.isIOS`-guard the iOS APNs bridge wiring so the channel is never invoked on
  Android — kills the `MissingPluginException` on every cold start (`main.dart`
  `_setupIosApnsNotificationOpenBridge`; field stays assigned so `dispose` is safe).
- **(B) the race fix:** a **home-ready gate**. `StartupRouter` gained `onStartupHomeReady`, fired inside
  `_pushStartupReplacement` right after the home `pushReplacement`. `_MyAppState` holds a
  `_startupHomeReady` flag (+ an 8s fallback timer so a notification is never permanently stranded on an
  abnormal startup path) and now **defers every notification route until the home is up**, so the
  conversation is pushed ON TOP of the home (additive `navigator.push`) and survives. Group/post routes
  share the same deferral mechanism and get the fix for free. New host test:
  `startup_router_notification_open_test.dart` → "133: fires onStartupHomeReady after the home surface
  is pushed" (mutation-verified). 52 startup-screen tests + analyze 0 new.
- **REMAINING:** Android device verification — cold-launch tap of a 1:1 notification must open the
  conversation (not Feed); `idevicesyslog`/`adb logcat` should show the conversation route surviving and
  no `NOTIFICATION_ROUTE_HOME_READY_FALLBACK` on the normal path. iOS regression check: cold-tap still
  opens the conversation. (Host-side can't reproduce the navigation race; the home-ready gate makes the
  behavior deterministic and is unit-tested at the StartupRouter seam.)

---

## Original problem statement + hypotheses (retained for context)

## Problem statement
On **Android**, when the app is **fully closed** and the user **taps a 1:1 message notification**, the
app cold-launches but lands on the **Feed** screen instead of the sender's conversation. The user never
reaches the chat from the notification; they must navigate to it manually (where the message then
shows). On **iOS** the same tap *does* route into the conversation (that path is what finding 131
addresses). So this is an Android-cold-start-specific routing failure.

## Impact
- **Severity: high for Android.** A message notification that doesn't open the message defeats the
  notification's purpose. It is arguably worse than the 131 stale-window bug, which at least opened the
  correct chat. Likely perceived as "notifications are broken / take me to the wrong place."
- Scope of users: every Android user who taps a 1:1 message notification from a cold (killed) app
  state. Warm-tap (app already running) was **not** tested and may behave differently.

## Device evidence (captured 2026-06-19, Pixel 6, debug build, `adb logcat`)
Cold launch (new pid `12292`) after tapping a `notif3` notification:
1. **Route deferred at cold start** — `4 deferred` log markers. The handler defers when
   `MyApp.navigatorKey.currentState == null` (`lib/main.dart:3760-3766`) and flushes on a post-frame
   callback (`_flushDeferredNotificationRouteTarget`).
2. **An iOS-only method channel throws on Android** (×2):
   `IOS_APNS_NOTIFICATION_OPEN_ERROR {"phase":"markNotificationOpenBridgeReady","error":"MissingPluginException(No implementation found for method markNotificationOpenBridgeReady on channel mknoon/ios_notification_open)"}`.
   `mknoon/ios_notification_open` is an iOS-only channel; it is being invoked on Android.
3. A conversation screen **did** init (`CONV_FL_SCREEN_INIT`) and load (`CONV_FL_MESSAGES_LOADED
   count:3`) — but **without** a `notificationTappedAt` (no `CONV_FL_NOTIF_DRAIN_REFETCH`, no
   notification-tap timing), i.e. it was NOT opened via the notification-tap route
   (`_openConversationForContact`, which passes `notificationTappedAt`).
4. The just-delivered message (`CHAT_MSG_RECEIVE_STORED id=dc162a8a "notif3"`) was persisted **after**
   the screen's initial load.
5. **User-observed outcome:** the visible screen was **Feed**, not the conversation.

## Current state / hypotheses for the future investigation (UNCONFIRMED — do not treat as root cause)
The evidence points at one or more of:
- **H1 — cold-start contact-resolution race.** The 1:1 branch resolves the contact via
  `contactRepository.getContact(routeTarget.peerId!)` (`lib/main.dart:3886`) and **returns early if it
  is null** (`:3889-3892`). At cold start, the deferred route may flush before the contact DB is
  warm → `getContact` returns null → no conversation is pushed → the app stays on its default
  (Feed). The transient `CONV_FL_SCREEN_INIT` without `notificationTappedAt` suggests a different/late
  build path, not the notification route.
- **H2 — the iOS-only `markNotificationOpenBridgeReady` call on Android.** Whether or not it derails
  routing, an iOS-only `MethodChannel('mknoon/ios_notification_open')` invoked on Android is a
  cross-platform-call smell (`MissingPluginException`) and should be guarded by `Platform.isIOS`.
- **H3 — deferred-route flush ordering.** The post-frame flush of `_deferredNotificationRouteTarget`
  may run before the app shell/navigator is in a state where a conversation push survives, or the
  push is superseded by the default Feed landing.

These are hypotheses; the fix plan must confirm which holds (instrument the deferred flush +
`getContact` result at cold start) before changing routing.

## Scope
- **In scope:** Android, 1:1 (`NotificationRouteTargetKind.conversation`) message notifications, cold
  (killed) app start.
- **Out of scope (separate behavior, may need their own checks):** iOS (routes correctly today);
  group/post/contact-request notification kinds; warm-tap (app already running) — all untested here.
- Relationship: **independent of 131/132.** 131 makes an *opened* conversation re-fetch a missed
  message; this finding is about the conversation never opening on Android cold start.

## Reproduction
1. Android: fully close the app (swipe from recents).
2. From a contact's device, send a 1:1 message (recipient offline → relay inbox + push).
3. Android: tap the resulting notification.
4. **Observed:** app cold-launches to Feed; the conversation is not shown. **Expected:** the sender's
   conversation opens (with the new message, per 131).

## Test cases (for the future fix)
- **T1 (integration / device):** Android cold start + 1:1 message notification tap → the sender's
  `ConversationWired` is the visible route (not Feed), and is opened via the notification path
  (`notificationTappedAt` set, so 131's drain-refetch engages).
- **T2 (unit):** the deferred-route flush, when the contact is not yet resolvable, **retries/awaits**
  contact readiness rather than dropping the route (no silent fall-through to Feed).
- **T3 (unit/platform):** `markNotificationOpenBridgeReady` (and any `mknoon/ios_notification_open`
  call) is a no-op / guarded on Android — no `MissingPluginException`.
- **T4 (regression):** iOS 1:1 notification cold-tap still routes to the conversation.

## Notes
- Evidence logs are ephemeral (debug `adb logcat`); re-capture during the fix with
  `adb -s <pixel> logcat | grep -E "NOTIFICATION|CONV_FL_SCREEN_INIT|deferred|MissingPlugin"`.
- iOS debug builds **cannot** be used to test cold-launch-from-notification (JIT is denied to
  standalone-launched debug apps → splash hang); use a **profile** build with flow-logging forced on,
  or device console for the iOS regression check (T4).
