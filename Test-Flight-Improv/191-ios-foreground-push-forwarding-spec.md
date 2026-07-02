# 191 - iOS foreground push never reaches Dart: onMessage severed by notification-delegate ownership (+ Firebase init/arm hardening)  (Bug — Spec)

Status: awaiting-review (spec only — problem + impact + current state + test cases; no solution design).

Relation to earlier work:
- **189** (implemented host-green in the tree) fixed the drain *cadence*: a degraded/idle iOS device now drains every 30 s. 191 is the *instant* half: without it, every iOS receive is capped at the periodic grid. 189's periodic drain is the regression-guarded fallback floor here, not the target.
- **139/145** built the notification-**tap** forwarding (`mknoon/ios_notification_open` method channel + `didReceive` override) — proof that the manual-forward pattern works on this codebase; foreground **delivery** never got the equivalent.
- **118** (calm notification policy) owns what is *displayed*; this spec only touches what is *delivered to Dart*.
- **175** is the precedent for iOS-native test coverage (`ios/RunnerTests/*`, XCTest) of notification-path code.
- Root-cause #3 of the 2026-07-02 Pixel↔iPhone delivery RCA (`project_pixel_to_iphone_slow_delivery_rca_2026_07_02.md`); siblings #1/#2 are 189's (implemented), #4 is 190's.

---

## Problem Statement

On iOS, a remote push for a foreground app is delivered by the OS to the app process — SpringBoard logs receipt on topic `com.mknoon.app`, the NotificationService extension rewrites the encrypted preview, and the process answers `willPresent` — but the message payload is **never forwarded into Dart's `FirebaseMessaging.onMessage` stream**. Every downstream foreground-push behavior is therefore dead on iOS: the push-triggered inbox drain, `PUSH_FOREGROUND_MESSAGE_RECEIVED/ROUTED` telemetry, the unroutable-fallback notification. Push-triggered receive has **never worked on iOS**; it works on Android (measured 0–1 s store→ack all through the 2026-07-02 live debug).

**Device proof (2026-07-02, iPhone 11, fresh install, fresh FCM token, healthy process, foreground):** two relay inbox injections via `go-mknoon/cmd/testpeer` `inbox_store_v1`:
- store 10:04:27Z → relay `[PUSH] Notification sent` 10:04:30Z → ack **10:04:34Z**
- store 10:05:48Z → `[PUSH]` 10:05:48Z → ack **10:06:04Z** (16 s later, deliberately timed mid-cycle)

Both acks landed exactly on the 30 s periodic health-check drain grid (node started 09:56:33Z → ticks at :03/:33); **zero** drains followed the pushes themselves. Earlier the same day (pre-189 build), the identical delivery gap produced 86–368 s store→ack latencies and a >10-minute undelivered controlled repro — the original user-reported "Pixel→iPhone takes ages."

**Mechanism (all verified in source; refined 2026-07-02 by the plan-191 adversarial pass — engine + plugin sources read at the pinned versions):**
1. `ios/Runner/Info.plist:9-10` sets `FirebaseAppDelegateProxyEnabled=false` — FlutterFire's automatic hooking is off; the host app owns all forwarding. The **token half** was manually forwarded (`Messaging.messaging().apnsToken = deviceToken`, `AppDelegate.swift:61`) — which is why FCM tokens mint, pushes physically arrive, and the NSE runs. The **delivery half** was not.
2. The only code that feeds Dart `onMessage` is the firebase_messaging plugin's own `willPresent` (`FLTFirebaseMessagingPlugin.m:316-360`; the `Messaging#onMessage` channel invoke at `:329-333`, gated on `gcm.message_id` in the payload). For that to run, the plugin must receive the `willPresent` callback — either as the `UNUserNotificationCenter` delegate or via the engine's plugin lifecycle chain.
3. **The severed link is plugin-registration timing under UIScene.** The engine DOES forward UN callbacks to registered plugins (`FlutterAppDelegate.mm:120-142` → `FlutterPluginAppLifeCycleDelegate.mm:467-490`; flutter_local_notifications rides this chain today). But the FCM plugin defers its ENTIRE launch wiring — `addApplicationDelegate` registration, delegate-install guard, initial-notification gathering — into an `NSNotificationCenter` observer for `UIApplicationDidFinishLaunchingNotification` (`FLTFirebaseMessagingPlugin.m:67-75`, handler `:214-310`, registration at `:254`). This app adopted UIScene (`Info.plist:60-81`, `FlutterSceneDelegate`, since commit `ff2c094c`), so `GeneratedPluginRegistrant.register` runs at scene-connect via `didInitializeImplicitFlutterEngine` (`AppDelegate.swift:143-156`) — AFTER UIKit posted that notification. NSNotifications are not replayed; the engine's own scene fallback (`FlutterViewController.mm:318-329`) replays lifecycle *method calls* but not NSNotifications. **The FCM plugin's observer never fires → the plugin is never in the lifecycle chain, never a delegate, never gathers anything.** The AppDelegate's 4× `UNUserNotificationCenter.delegate = self` installs (`AppDelegate.swift:38/:41/:145/:160`, impl `:165-182`) only ever replace self with self — harmless; the plugin's delegate-install guard (`FLTFirebaseMessagingPlugin.m:271-275`) is dead code in this app.
4. The AppDelegate's `willPresent` override (`AppDelegate.swift:69-83`) runs a diagnostic probe and calls `super` → engine fan-out reaches only FLN, whose `willPresent` early-returns for non-FLN payloads **without invoking the completion handler** (`FlutterLocalNotificationsPlugin.m:879-886`, guard `:858`). **Latent co-bug: for FCM-shaped foreground notifications, NOBODY calls the `willPresent` completion handler today** — the SpringBoard-captured `Received response 0` (request `6BB5-BC0F`) is the OS default on an un-invoked handler, not an explicit answer. (Same completion drop applies to `didReceive` for FCM taps — taps still work via the manual bridge below.)
5. Taps DO work because they got a hand-built forward: `didReceive` override (`:96-141`) → `forwardIosNotificationOpenIfNeeded` → `mknoon/ios_notification_open` channel → `_routeRemoteNotificationOpen` (Dart consumer wired at `main.dart:3721`, `:3844-3853`). Foreground delivery has no equivalent, and the Dart `onMessageOpenedApp` listener (`main.dart:4684-4693`) is silent for the same registration-timing reason — which is load-bearing: any fix that puts the FCM plugin back into the `didReceive` chain would DOUBLE-route taps (the 139 bug reborn).

**Secondary robustness holes in the same chain (in scope as hardening; code-verified, NOT the live mechanism — the fresh-token proof shows Firebase was initialized during the failing test):**
- `ensureFirebaseReady()` (`main.dart:397-427`) catches a thrown `Firebase.initializeApp()` (`:414-416`) but latches `firebaseInitialized=true` first (`:398-401`) — one transient init failure silently disables Firebase for the entire process lifetime, no retry.
- `_setupPushListeners()` (`main.dart:4663-4702`) returns early while `Firebase.apps.isEmpty` (`:4664`), and is only invoked at two arm points (`:3709` initState, `:3717-3719` post-runtime-ready). If Firebase is not ready at both, listeners are never armed. There is **no arm-success telemetry** — `PUSH_LISTENER_ERROR` (`:4695-4701`) only covers `listen()` throwing — so a deaf process is indistinguishable from a healthy one in FLOW logs.
- The structural condition that made this silent: the notification callback surface has three implementors (AppDelegate; firebase_messaging 15.2.10; flutter_local_notifications 18.0.1 `FlutterLocalNotificationsPlugin.m:879-886`, `:955-962`) but NO ownership/forwarding/completion contract — FLN never installs the delegate (verified: zero `delegate =` assignments; it joins the engine chain synchronously at registration, `registerWithRegistrar` `:145-147`), FCM never gets registered at all (UIScene timing), and no implementor completes handlers for payloads it doesn't own. Silence was the default outcome, with zero telemetry.

Reproduction: foreground the app on any iPhone, store a message into its relay inbox from a non-connected peer (testpeer `inbox_store_v1`), watch the relay journal: `[PUSH] sent` → no retrieve/ack until the next 30 s health-check tick. Android same test: ack ≤2 s.

---

## Impact Analysis

| Scenario | iOS today | Android today |
|---|---|---|
| Foreground receive when sender can't reach the receiver directly (inbox+push path) | ≤30 s (189 periodic grid); **pre-189 builds: minutes→unbounded** (86–368 s+, >10 min observed) | 0–1 s |
| Foreground receive with working direct/circuit stream | ~instant (unaffected — no inbox leg) | ~instant |
| Unroutable-push fallback notification (foreground) | never shown (handler never runs) | works |
| Foreground push telemetry (`PUSH_FOREGROUND_*`) | never emitted → field debugging blind (cost hours in the 2026-07-02 RCA) | works |
| Silent-deafness observability (init/arm failures) | zero signal (both platforms) | zero signal |

- Severity: **high** — core receive latency on one entire platform; systematically, for all iOS users, since the proxy was disabled. Masked historically because direct/circuit paths and (now) the 189 grid deliver eventually.
- Frequency: every foreground push on every iOS device.
- Workarounds: none for users; 189's 30 s grid is the only mitigation.

---

## Current State (verified file:line, 2026-07-02; shared tree — 189/172 sessions active, no mid-edit anomalies observed in these files)

### iOS native
| Item | Location |
|---|---|
| `FirebaseAppDelegateProxyEnabled=false` | `ios/Runner/Info.plist:9-10` |
| Delegate self-install ×4 (`before/after_didFinishLaunching_super`, `after_implicit_engine_plugin_registration`, `didBecomeActive`) | `ios/Runner/AppDelegate.swift:38, :41, :145, :160`; impl `:165-182` |
| `willPresent` override: probe + `super` only (no Dart forward) | `AppDelegate.swift:69-83` |
| Manual APNs-token forward (`Messaging.messaging().apnsToken`) | `AppDelegate.swift:54-67` (`:61`) |
| Tap forward: `didReceive` → `forwardIosNotificationOpenIfNeeded` → `mknoon/ios_notification_open`; route-shape + FLN-payload filters | `AppDelegate.swift:96-141`, `:475-495`, shape check `:497-530` |
| Native diagnostics (`[PUSH_DIAG]` NSLog): delegate installs incl. `previousDelegateClass`, settings, register calls, didReceive key-shape | `AppDelegate.swift:42, :58, :122-129, :159, :176-180, :186-191, :259-265` |

### Plugin/engine internals (pinned versions; engine rev `e4b8dca3f1` / Flutter 3.41.4)
| Item | Location |
|---|---|
| UIScene adoption (`FlutterSceneDelegate`, storyboard) — plugin registration moves to scene-connect | `ios/Runner/Info.plist:60-81`; `AppDelegate.swift:143-156` (`didInitializeImplicitFlutterEngine` → `GeneratedPluginRegistrant.register`) |
| firebase_messaging **15.2.10**: ALL launch wiring (incl. `addApplicationDelegate` `:254` and delegate install/guard `:257-297`) deferred into a `UIApplicationDidFinishLaunchingNotification` observer — **never fires under UIScene** (dead code in this app) | `FLTFirebaseMessagingPlugin.m:67-75`, `:214-310` |
| The ONLY Dart-onMessage feed: plugin `willPresent` → `Messaging#onMessage` channel (gated on `gcm.message_id`); iOS-18 duplicate-suppression `_foregroundUniqueIdentifier` `:327-330,:359`; completes with persisted presentation options when no original delegate `:343-357` | `FLTFirebaseMessagingPlugin.m:316-360` (`:329-333`) |
| Plugin instance is **published** to the registry (public retrieval surface) | `FLTFirebaseMessagingPlugin.m:91` (`[registrar publish:instance]`); key `"FLTFirebaseMessagingPlugin"` `GeneratedPluginRegistrant.m:154`; `FlutterPluginRegistry.valuePublishedByPlugin:` `Flutter.framework/Headers/FlutterPlugin.h:469` |
| Engine DOES forward UN callbacks to registered plugins (FLN rides this today) | `FlutterAppDelegate.mm:120-142` → `FlutterPluginAppLifeCycleDelegate.mm:467-490`; scene fallback replays lifecycle calls, NOT NSNotifications `FlutterViewController.mm:318-329` |
| flutter_local_notifications **18.0.1**: never installs the UN delegate; joins engine chain at registration; `willPresent`/`didReceive` early-return WITHOUT completing for non-FLN payloads | `FlutterLocalNotificationsPlugin.m:145-147`, `:858`, `:879-886`, `:955-962` |
| App's FLN init (no explicit delegate handling in Dart) | `lib/core/notifications/flutter_notification_service.dart:10-11, :39-46` |

### Dart chain (all downstream of the severed link — healthy and tested)
| Item | Location |
|---|---|
| `ensureFirebaseReady()` swallow+latch; bg handler + presentation options `alert:false,badge:false,sound:false` | `lib/main.dart:397-427` |
| Arm points ×2 + `Firebase.apps.isEmpty` early return + arm latch | `main.dart:3709`, `:3717-3719`, `:4663-4669` |
| `onMessage` listener → `PUSH_FOREGROUND_MESSAGE_RECEIVED` → `_handleForegroundRemotePush` | `main.dart:4672-4682`, handler `:4704-4764` (migration-gated drain `:4708-4711`, fallback notification `:4737-4756`) |
| Routing use case (drain per kind; `ROUTED`/`UNROUTABLE`/`DRAIN_ERROR` events) | `lib/features/push/application/handle_foreground_remote_message_use_case.dart:10-87` |
| Route-target parse (`type`+`sender_id`, relay sends both — `go-relay-server/inbox.go:289-291`) | `lib/core/notifications/notification_route_target.dart:129-194` |
| Tap-open Dart consumer (`ios_notification_open`) | `main.dart:3721`, `:3844-3853` |

### Existing tests and the gap
Covered: Dart routing use case (`test/features/push/application/handle_foreground_remote_message_use_case_test.dart`), route-target parse, background handler, NSE preview + SI-5 dedupe parity (`ios/RunnerTests/NotificationPreviewResolverTests.swift` — the 175-era native XCTest precedent), entitlement parity (`NotificationServiceConfigurationTests.swift`).
**Not covered anywhere:** (1) an iOS foreground remote push reaching the Dart handler at all; (2) notification-delegate ownership/forwarding across the 4 install points and 3 contenders; (3) Firebase-init-failure recovery; (4) listener-arm observability; (5) any foreground-push→drain latency assertion.

---

## Scope Clarification

| Area | Status |
|---|---|
| iOS foreground remote-push delivery into the Dart foreground handler (and its telemetry) | **In scope** |
| Notification-delegate ownership behavior across all 4 install points + 3-way contention (FCM plugin, FLN, AppDelegate) | **In scope** (behavioral guarantee, not a prescribed wiring) |
| Firebase init-failure recoverability + listener-arm observability (the two hardening holes) | **In scope** |
| Notification-tap routing (`ios_notification_open`), cold + warm | **Unchanged — regression-guarded** |
| NSE preview rewriting + SI-5 cross-process dedupe | **Unchanged — regression-guarded** |
| Background/killed push semantics (no drain; local fallback per current design) | **Unchanged — regression-guarded** |
| Foreground presentation policy (no system banner: options 0 / `alert:false`) | **Unchanged — regression-guarded** |
| Android push path | **Unchanged — regression-guarded** |
| Migration-gate semantics around the drain | **Unchanged** |
| 189's periodic drain / recovery behavior | **Unchanged** (remains the fallback floor) |
| Relay push payload / relay server | **Out of scope** (payload proven correct — NSE consumes the same keys) |
| Push token registration / slot semantics (last-write-wins, expiry) | **Out of scope** — separate follow-up if pursued |
| firebase_messaging / flutter_local_notifications version bumps | **Out of scope** (a solution may propose one, but the spec does not require it) |

---

## Test Cases

### Group A — iOS foreground delivery reaches Dart (the core defect)
- **TC-191-01 (device, the headline)** — iPhone foreground in a conversation, relay inbox store injected via testpeer `inbox_store_v1` from a non-contact peer → relay `[PUSH]` → the iPhone acks/retrieves within **≤5 s of the push and OFF the 30 s health-check grid** (repeat ×3 at grid-offset times; the 2026-07-02 protocol, inverted expectation). Falsifier: acks only on :03/:33-style grid ticks (today's behavior).
- **TC-191-02** — the same push produces `PUSH_FOREGROUND_MESSAGE_RECEIVED` (with `dataKeys` including `type`, `sender_id`) followed by `PUSH_FOREGROUND_MESSAGE_ROUTED{kind:conversation}` in FLOW logs — the full Dart handler chain runs with a real APNs-shaped payload.
- **TC-191-03** — host-tier: whatever bridge/stream feeds the Dart handler on iOS is unit-covered with a captured real APNs `userInfo` fixture (aps + `gcm.message_id` + `type`/`sender_id` custom keys): payload maps to a routable conversation target and the drain closure fires. Include a data-shaped-but-unroutable fixture → `PUSH_FOREGROUND_MESSAGE_UNROUTABLE` + fallback-notification path (now reachable on iOS).
- **TC-191-04** — foreground presentation unchanged: the delivered push still presents NO system banner/sound/badge while the app is foreground (options-0 policy), and the NSE preview rewrite still occurs for the same notification (mutable-content chain intact).
- **TC-191-05** — no double-handling: a message that arrives via the foreground push AND is picked up by a concurrent periodic/manual drain is displayed exactly once (existing dedup semantics hold); the fallback local notification is NOT shown when the drain succeeded.

### Group B — delegate ownership is stable and forwarding survives every install point
- **TC-191-10 (device)** — background the app, foreground it again (fires the `didBecomeActive` delegate re-install, `AppDelegate.swift:160`), THEN inject a push → still delivered to Dart within the Group-A bound. The forwarding guarantee survives every delegate (re)installation, not just cold start.
- **TC-191-11** — notification-tap routing still works: (a) warm tap on a remote notification routes via `ios_notification_open` exactly as today (`forwarded_warm` PUSH_DIAG); (b) cold-start tap consumes the pending payload; (c) a tap on an FLN **local** notification still reaches FLN's handler (3-way contention: no contender's tap path is orphaned).
- **TC-191-12 (native XCTest, 175 precedent)** — delegate-ownership behavior is locked by a RunnerTests case: after the full install sequence, a synthetic FCM-shaped `willPresent` results in the payload being handed toward Dart (observable seam) AND the completion handler still returning the options-0 policy. Falsifier: payload dropped at `super`.

### Group C — hardening: init failure recoverable, arm state observable
- **TC-191-20** — `Firebase.initializeApp()` throws on first attempt → a later attempt retries and succeeds → push listeners arm and foreground pushes flow. Falsifier: the current permanent `firebaseInitialized=true` latch (`main.dart:398-401`) makes the process permanently deaf.
- **TC-191-21** — listener-arm success is observable: a FLOW event (e.g. `PUSH_LISTENERS_ARMED` with platform + listener kinds) is emitted exactly once on successful arm; absence of the event within startup telemetry = detectable deafness. `PUSH_LISTENER_ERROR` semantics unchanged for `listen()` throws.
- **TC-191-22** — late-Firebase re-arm: if `Firebase.apps` is empty at BOTH existing arm points but Firebase becomes ready later, the listeners still get armed (no ordering permanently disarms pushes). Falsifier: the current two-point-only arming.
- **TC-191-23** — arm idempotency preserved: repeated arm invocations never double-subscribe (`_pushListenersArmed` latch semantics kept — no duplicate `PUSH_FOREGROUND_MESSAGE_RECEIVED` per push).

### Group D — regression guards
- **TC-191-30 (device control)** — Android: same testpeer injection to the Pixel foreground → ack ≤2 s, exactly one `PUSH_FOREGROUND_MESSAGE_RECEIVED` (unchanged).
- **TC-191-31** — background/killed iOS push behavior unchanged: background handler shows/updates the local notification per current semantics, does NOT drain; drain happens on resume (existing suite green).
- **TC-191-32** — migration gate unchanged: with the runtime gate blocked, the foreground push runs the handler but the drain is skipped with `ACCOUNT_MIGRATION_RUNTIME_NETWORK_ACTION_BLOCKED` (and no crash).
- **TC-191-33** — 189 fallback floor intact: with push delivery artificially disabled, a foreground degraded device still drains on the 30 s grid (189's suite stays green, no re-baseline).
- **TC-191-34** — APNs-token half unchanged: token forwarding (`AppDelegate.swift:61`) and FCM token minting still work after any delegate/forwarding changes (fresh-install token registration observed at the relay).

### Group E — closure runsheet (device, 183/187 format)
- **TC-191-40** — iPhone 11 (`00008030-001A6D2801BB802E`, profile build — NEVER debug, see dev_keychain_wipe hazard) + Pixel 6 control: run the full injection protocol ×3 iOS + ×1 Android with relay-journal timestamps and FLOW captures; PASS = all iOS acks ≤5 s post-push and off-grid, Android unchanged, no banner shown, one displayed message each, tap-routing spot-check green.

---

## Scope guard (non-goals)

- Do NOT change what is *presented* (banner policy, notification copy, 118 calm rules) — only what is *delivered to Dart*.
- Do NOT touch the relay push payload, token registration flow, or the NSE.
- Do NOT re-enable `FirebaseAppDelegateProxyEnabled` as an unexamined side effect — whatever the solution, tap routing (139/145), FLN local notifications, and the APNs-token forward must be proven unbroken (Groups B/D lock this).
- Do NOT redesign 189's drain cadence; it is the fallback, not the subject.
- Do NOT bump plugin versions as a hidden prerequisite; if a solution requires it, that is its own reviewed decision.
- Device closure MUST use `--profile` builds on the physical phones (`flutter run --debug` trips the dev_keychain_wipe landmine — identity loss).
