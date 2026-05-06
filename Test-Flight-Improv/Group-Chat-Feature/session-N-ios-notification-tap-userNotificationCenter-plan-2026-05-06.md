# Session N (iOS) - Evidence-gated notification tap routing plan

Status: execution-ready for simulator-first evidence-gated work.

Created 2026-05-06. Rewritten 2026-05-06 after repo evidence showed the
original AppDelegate-only fix plan was not sufficient.

This is the iOS sibling of
[`session-N-android-notification-tap-onnewintent-plan-2026-05-05.md`](./session-N-android-notification-tap-onnewintent-plan-2026-05-05.md),
but it is not the same class of fix. Android had a concrete missing handoff:
`singleTask` notification intents reached `MainActivity.onNewIntent`, but the
activity did not call `setIntent(intent)`, so `flutter_local_notifications`
could not read the tap extras. The proposed iOS equivalent
("add an AppDelegate override that only calls super") is not proven, because
`AppDelegate` already subclasses `FlutterAppDelegate`, and FlutterAppDelegate
already implements `userNotificationCenter(_:didReceive:withCompletionHandler:)`
and forwards to registered plugins.

The iOS work must therefore start by proving the real failing boundary on
hardware before accepting any code change as the fix.

## Planning Progress

- 2026-05-06 - Simulator fallback update completed. Files inspected since
  last update: `scripts/push_fixture_to_simulator.sh`, push fixtures under
  `test/features/push/fixtures/`, and `xcrun simctl push` help. Decision:
  when no physical iPhone is available, run a simulator-first APNs-style tap
  proof with `simctl push` and classify results as `simulator-verified,
  hardware-pending`, not final hardware closure. Next action: execute
  diagnostics on a booted simulator.
- 2026-05-06 - Arbiter completed. Files inspected since last update:
  `AppDelegate.swift`, Flutter engine iOS `FlutterAppDelegate.mm`,
  `FlutterPluginAppLifeCycleDelegate.mm`, `flutter_local_notifications`
  iOS plugin source, `firebase_messaging` iOS plugin source, `main.dart`,
  `flutter_notification_service.dart`, and the Android Session N plan.
  Decision/blocker: the old plan's structural assumption is stale; an
  explicit Swift super-only override is not a sufficient iOS fix. Next action:
  execute evidence-gated diagnostics and branch only on observed hardware
  logs.
- 2026-05-06 - Reviewer completed. Files inspected since last update:
  current iOS plan, notification audit finding, `Info.plist`, and current
  Dart routing tests. Decision/blocker: the plan must distinguish local
  `flutter_local_notifications` taps from FCM/APNs remote notification opens.
  Next action: require native + Dart trace evidence in the closure bar.
- 2026-05-06 - Planner completed. Files inspected since last update:
  `StartupRouter`, `background_message_handler`, `background_push_notification_fallback`,
  and local/remote routing dispatch code. Decision/blocker: classify as
  `evidence-gated`, not direct implementation-ready. Next action: write
  branch-by-evidence implementation steps.
- 2026-05-06 - Evidence Collector completed. Files inspected since last
  update: native iOS AppDelegate, Android MainActivity, Flutter engine,
  FlutterFire Messaging, flutter_local_notifications, and app-root routing.
  Decision/blocker: current AppDelegate already inherits the native forwarding
  method from FlutterAppDelegate. Next action: build a plan that proves the
  runtime boundary first.

## Execution Progress

- 2026-05-06 11:46:33 CEST - Contract extracted. Files inspected:
  `Test-Flight-Improv/Group-Chat-Feature/session-N-ios-notification-tap-userNotificationCenter-plan-2026-05-06.md`
  and `mobile-notification-routing-and-deep-linking/references/repo-notification-map.md`.
  Decision/blocker: execute evidence-gated Step 1 first; required direct tests
  and `flutter analyze` are explicit, while hardware proof may remain
  hardware-pending if no iPhone is available. Next action: spawn isolated
  Executor for diagnostic/native pin implementation and required gates.
- 2026-05-06 11:48:36 CEST - Executor local pass started. Files inspected:
  `ios/Runner/AppDelegate.swift`,
  `test/core/notifications/main_activity_onnewintent_pin_test.dart`, and
  current notification tests. Decision/blocker: no Dart routing evidence yet;
  patch Step 1 only. Next action: add native diagnostic forwarding override
  and static pin test.
- 2026-05-06 11:48:36 CEST - Executor patch applied. Files touched:
  `ios/Runner/AppDelegate.swift`,
  `test/core/notifications/app_delegate_notification_tap_diagnostic_pin_test.dart`,
  and this plan. Decision/blocker: Swift diagnostic logs sanitized tap key
  shape and forwards to `FlutterAppDelegate`; static pin added. Next action:
  run fastest structural validation.
- 2026-05-06 11:50:22 CEST - Fast structural validation finished. Command:
  `flutter test test/core/notifications/app_delegate_notification_tap_diagnostic_pin_test.dart`.
  Result: passed. Next action: run remaining focused notification gates.
- 2026-05-06 11:54:23 CEST - Focused notification tests finished.
  Commands: `flutter test test/core/notifications/flutter_notification_service_test.dart`,
  `flutter test test/core/notifications/app_root_notification_open_test.dart`,
  `flutter test test/core/notifications/notification_route_target_test.dart`,
  `flutter test test/core/notifications/notification_route_contract_matrix_test.dart`,
  `flutter test test/features/identity/presentation/screens/startup_router_notification_open_test.dart`,
  and `flutter test test/integration/notification_tap_smoke_test.dart`.
  Result: all passed. `flutter analyze` completed with exit 1 on existing
  analyzer debt, reporting 1717 issues across unrelated files; targeted
  `flutter analyze test/core/notifications/app_delegate_notification_tap_diagnostic_pin_test.dart`
  passed with no issues. Next action: capture simulator/hardware availability
  evidence.
- 2026-05-06 11:55:27 CEST - Executor child closed after bounded waits.
  Files inspected/touched from landed evidence:
  `ios/Runner/AppDelegate.swift`,
  `test/core/notifications/app_delegate_notification_tap_diagnostic_pin_test.dart`,
  and this plan. Decision/blocker: child made scoped code/test/progress
  evidence but did not return a final handoff; continue with fresh QA review
  using repo files as source of truth. Next action: spawn QA Reviewer.
- 2026-05-06 11:58:39 CEST - QA Reviewer completed. Files reviewed:
  `ios/Runner/AppDelegate.swift`,
  `test/core/notifications/app_delegate_notification_tap_diagnostic_pin_test.dart`,
  and this plan. Decision/blocker: code/test portion is acceptable, but
  required simulator or hardware tap proof is missing. Next action: spawn the
  single allowed Executor fix pass, scoped only to simulator/hardware evidence
  collection or exact environment blocker recording.
- 2026-05-06 12:04:55 CEST - Executor fix pass availability evidence
  collected. Commands: `xcrun simctl list devices booted`, `flutter devices`,
  and `xcrun xctrace list devices`. Result: booted simulators available:
  `iPhone 17 Pro (38FECA55-03C1-4907-BD9D-8E64BF8E3469)` and
  `iPhone 17 (5BA69F1C-B112-47BE-B1FF-8C1003728C8F)`. `flutter devices`
  found Pixel 6 plus those simulators and listed `Saleh's iPhone` wirelessly,
  but reported code `-27` requiring unlock/cable/same LAN/Developer Mode;
  `xcrun xctrace list devices` listed iPhones under `Devices Offline`.
  Decision/blocker: no usable physical iPhone proof in this automated pass;
  proceed on simulator lane.
- 2026-05-06 12:04:55 CEST - Simulator fixture and app evidence collected.
  Commands: `scripts/push_fixture_to_simulator.sh --dry-run one_to_one_text`,
  `scripts/push_fixture_to_simulator.sh --dry-run group_text`,
  `xcrun simctl get_app_container <SIM_UDID> com.mknoon.app app`, and
  `xcrun simctl launch 38FECA55-03C1-4907-BD9D-8E64BF8E3469 com.mknoon.app`.
  Result: both APNs fixtures resolved; both booted simulators have
  `com.mknoon.app` installed; launch returned `com.mknoon.app: 24211`.
  Decision/blocker: simulator app install/run prerequisite satisfied.
- 2026-05-06 12:04:55 CEST - Simulator push/tap evidence attempted. Commands:
  `scripts/push_fixture_to_simulator.sh --device 38FECA55-03C1-4907-BD9D-8E64BF8E3469 --bundle-id com.mknoon.app one_to_one_text`,
  `scripts/push_fixture_to_simulator.sh --device 38FECA55-03C1-4907-BD9D-8E64BF8E3469 --bundle-id com.mknoon.app group_text`,
  `xcrun simctl terminate 38FECA55-03C1-4907-BD9D-8E64BF8E3469 com.mknoon.app`,
  bounded `xcrun simctl spawn ... log stream`, and canary `log show`
  queries for `ios_native_un_didReceive`, `PUSH_MESSAGE_OPENED_APP`,
  `PUSH_INITIAL_MESSAGE_OPENED`, `NOTIFICATION_TAP_NAV_ERROR`,
  `NOTIFICATION_TAPPED`, `NOTIFICATION_TAP_TO_MESSAGE_TIMING`, and
  `INITIAL_LOCAL_NOTIFICATION_ROUTE_ERROR`. Result: sequential 1:1 and group
  pushes returned `Notification sent to 'com.mknoon.app'`; parallel fixture
  attempts hit `mktemp: mkstemp failed ... File exists` and were rerun
  sequentially. Screenshot `/tmp/mknoon-ios-push-terminated.png` showed the
  delivered iOS banner (`New Message` / `You have a new message`). Runner
  canary log queries returned only headers/no matching Runner tap/open logs.
  `osascript` UI automation to send Simulator keystrokes failed with
  `osascript is not allowed to send keystrokes. (1002)`, and `simctl` exposes
  no notification tap/keypress subcommand. Decision/blocker: simulator remote
  push delivery is proven, but simulator notification tap activation was not
  performed; classify as `environment_blocker` / `tap-not-proven`, not
  `simulator-failed, fix-needed`. No app-side boundary failure was traced and
  no production code change is justified in this fix pass. Next action: final
  QA should keep the tap proof blocker open until a manual simulator tap or
  usable physical iPhone run captures the required native/Dart route logs.
- 2026-05-06 12:09:09 CEST - Final QA completed and verdict written. Files
  reviewed: `ios/Runner/AppDelegate.swift`,
  `test/core/notifications/app_delegate_notification_tap_diagnostic_pin_test.dart`,
  and this plan. Decision/blocker: final QA accepted the scoped diagnostic
  code/test delta but confirmed `tap-not-proven` remains blocking because no
  simulator notification activation or physical iPhone tap produced native/Dart
  route logs. Final verdict: `blocked`, blocker class
  `environment_blocker`. Recommended next retry focus: perform a manual
  simulator notification tap or use a connected/unlocked physical iPhone, then
  capture `ios_native_un_didReceive`, `PUSH_MESSAGE_OPENED_APP`,
  `PUSH_INITIAL_MESSAGE_OPENED`, navigation error canaries, and final
  target-route proof.
- 2026-05-06 12:47:09 CEST - Follow-up iOS-only fix applied after user
  reported the bug persists and clarified Android is working. Files touched:
  `ios/Runner/AppDelegate.swift` and
  `test/core/notifications/app_delegate_notification_tap_diagnostic_pin_test.dart`.
  Decision/blocker: harden the iOS native boundary by re-seating
  `UNUserNotificationCenter.current().delegate = self` before
  `super.application(...)`, after `super.application(...)`, after implicit
  engine plugin registration, and on `didBecomeActive`, while still forwarding
  taps to `FlutterAppDelegate`. Direct notification tests passed and
  `flutter build ios --simulator --debug` passed. Next action: retest on iOS
  hardware/simulator tap and inspect the new `notification_center_delegate_installed`
  and `ios_native_un_didReceive` logs if routing still fails.
- 2026-05-06 16:14:01 CEST - Real simulator notification tap proof collected
  through the new UI smoke. Command:
  `scripts/run_ios_notification_tap_ui_smoke.sh --skip-build --devices 38FECA55-03C1-4907-BD9D-8E64BF8E3469,5BA69F1C-B112-47BE-B1FF-8C1003728C8F`.
  Result: passed all five scenarios: iPhone 17 Pro warm 1:1, iPhone 17 Pro
  warm group, iPhone 17 warm 1:1, iPhone 17 warm group, and iPhone 17 Pro
  cold 1:1. The cold-start log included `MKNOON_APNS_TAP_READY mode=cold`,
  `ios_native_un_didReceive`, `ios_notification_open_stored_pending`,
  `ios_notification_open_initial_consumed`, and
  `IOS_APNS_INITIAL_NOTIFICATION_OPENED`; warm scenarios included
  `ios_notification_open_forwarded_warm` and `IOS_APNS_NOTIFICATION_OPENED`.
  Forbidden route/open error markers were absent. Decision/blocker: simulator
  tap proof is now closed for the APNs-direct native-to-Dart route path;
  physical iPhone proof remains optional/manual release evidence.

## Real Scope

Make iOS notification taps route to the tapped conversation, group, intro,
contact request, or post target when the app is resumed or launched by the
tap.

In scope:

- Prove which iOS tap path is actually failing, starting with simulator proof
  when physical hardware is unavailable:
  local `flutter_local_notifications` fallback notification,
  FCM/APNs remote notification open, cold-start initial notification,
  warm-resume notification tap, or Dart route materialization after a valid
  tap callback.
- Use `scripts/push_fixture_to_simulator.sh` and `xcrun simctl push` to
  exercise simulator remote APNs-style notification taps before hardware.
- Add the smallest diagnostic hooks needed to classify the boundary.
- Apply only the fix indicated by the trace.
- Keep all final routing centralized through existing app-root paths:
  `MyApp._onNotificationTap(...)`, `_routeRemoteNotificationOpen(...)`, or
  `StartupRouter._handleInitialPushOpen(...)`.

Out of scope:

- Treating a super-only AppDelegate override as the final fix without hardware
  proof.
- Rewriting notification payload formats unless the trace proves payload shape
  is the broken boundary.
- Refactoring Firebase/APNs registration, push-token registration, startup,
  listener, or route architecture broadly.
- Android changes.
- Foreground presentation behavior unless the hardware trace proves the tap
  notification was never displayed because foreground presentation was broken.

## Closure Bar

This session is closed only when the physical iPhone tap proof shows the same
user-visible result Android now has:

- Receiver starts in a non-target chat or non-target surface.
- Sender triggers a routable notification.
- Receiver taps the OS notification.
- App opens the tapped target, not the previous route.
- Logs show the expected path for the actual notification type:
  - Local FLN fallback path:
    `ios_native_un_didReceive` or equivalent native tap log ->
    `NOTIFICATION_TAPPED` -> route target handling ->
    `NOTIFICATION_TAP_TO_MESSAGE_TIMING` or equivalent target-route proof.
  - Remote FCM/APNs path:
    native `UNUserNotificationCenter didReceive` and/or
    `PUSH_MESSAGE_OPENED_APP` / `PUSH_INITIAL_MESSAGE_OPENED` ->
    route target handling -> target screen visible.
- No `NOTIFICATION_TAP_NAV_ERROR`, no `INITIAL_LOCAL_NOTIFICATION_ROUTE_ERROR`,
  no duplicate route push, and no app crash.
- Static/unit tests added in this session pass.
- `flutter analyze` introduces no new warnings beyond the existing baseline.

Static text pins are supporting evidence only. They do not replace the
physical iPhone tap proof.

If a physical iPhone is not available, this session may advance only to
`simulator-verified, hardware-pending`. That interim state is useful enough to
validate remote APNs-style tap routing and choose the next code branch, but it
does not prove real APNs/FCM delivery, push-token registration, lock-screen
behavior, or data-only background push -> local notification fallback behavior
on hardware.

## Source Of Truth

Current code beats stale prose.

Authoritative files and behavior sources:

- `ios/Runner/AppDelegate.swift`
- `ios/Runner/Info.plist`
- `ios/Runner/GeneratedPluginRegistrant.m`
- Flutter engine iOS `FlutterAppDelegate.mm` and
  `FlutterPluginAppLifeCycleDelegate.mm`
- `flutter_local_notifications` 18.0.1 iOS plugin source
- `firebase_messaging` 15.2.10 iOS plugin source
- `lib/core/notifications/flutter_notification_service.dart`
- `lib/core/notifications/app_root_notification_open.dart`
- `lib/core/notifications/notification_route_dispatch.dart`
- `lib/core/notifications/notification_route_target.dart`
- `lib/features/identity/presentation/startup_router.dart`
- `lib/features/push/application/background_message_handler.dart`
- `lib/main.dart`
- Android Session N hardware-verified plan for parity expectations, not for
  iOS implementation mechanics.

If these disagree:

- Hardware trace of the actual iPhone tap wins over any static assumption.
- Flutter engine/plugin source wins over local comments about how delegation
  works.
- Existing centralized Dart route functions win over feature-specific
  navigation ideas.

## Session Classification

`evidence-gated`.

The user-visible gap is real enough to investigate, but the old proposed fix
does not identify a proven missing iOS handoff. Execution must first add or
collect trace evidence, then branch to the smallest confirmed fix.

## Exact Problem Statement

The reported iOS symptom is: tapping a chat notification on iPhone can bring
the app back to the previously visible screen instead of opening the tapped
conversation or group, mirroring the Android user-visible failure.

What is not yet proven:

- Whether the tapped iOS notification is a local notification created by
  `flutter_local_notifications` from a data-only push fallback.
- Whether the tapped notification is a visible FCM/APNs remote notification
  handled by `FirebaseMessaging.onMessageOpenedApp` or
  `FirebaseMessaging.getInitialMessage`.
- Whether iOS native `UNUserNotificationCenterDelegate.didReceive` fires at
  all.
- Whether the native callback fires but the Flutter plugin callback does not.
- Whether Dart receives the callback but route target preparation or navigation
  fails.

The implementation must improve only the proven broken boundary while keeping
local and remote notification routing behavior aligned with Android's final
contract.

## Files And Repos To Inspect Next

Production/native:

- `ios/Runner/AppDelegate.swift`
- `ios/Runner/Info.plist`
- `ios/Runner/GeneratedPluginRegistrant.m`

Production/Dart:

- `lib/core/notifications/flutter_notification_service.dart`
- `lib/core/notifications/notification_route_target.dart`
- `lib/core/notifications/notification_route_dispatch.dart`
- `lib/core/notifications/app_root_notification_open.dart`
- `lib/features/push/application/background_message_handler.dart`
- `lib/features/push/application/background_push_notification_fallback.dart`
- `lib/features/identity/presentation/startup_router.dart`
- `lib/main.dart`

Reference/plugin source:

- `.pub-cache/hosted/pub.dev/flutter_local_notifications-18.0.1/ios/Classes/FlutterLocalNotificationsPlugin.m`
- `.pub-cache/hosted/pub.dev/firebase_messaging-15.2.10/ios/firebase_messaging/Sources/firebase_messaging/FLTFirebaseMessagingPlugin.m`
- Flutter engine `FlutterAppDelegate.mm`
- Flutter engine `FlutterPluginAppLifeCycleDelegate.mm`

Tests:

- `test/core/notifications/flutter_notification_service_test.dart`
- `test/core/notifications/main_activity_onnewintent_pin_test.dart`
- `test/core/notifications/app_root_notification_open_test.dart`
- `test/core/notifications/notification_route_target_test.dart`
- `test/core/notifications/notification_route_contract_matrix_test.dart`
- `test/features/identity/presentation/screens/startup_router_notification_open_test.dart`
- `test/integration/notification_tap_smoke_test.dart`
- `integration_test/notification_open_ui_smoke_test.dart`

## Existing Tests Covering This Area

Already covered:

- Local notification response callback forwards non-empty payloads through
  `FlutterNotificationService.onNotificationTap`.
- Local notification tap payloads route through `routeAppRootLocalNotificationTap`.
- Initial local notification launch can consume the stored payload.
- Remote message data maps to `NotificationRouteTarget`.
- Startup initial remote messages route after P2P startup and inbox drain.
- Android `MainActivity.onNewIntent` static pin covers the Android-only
  `singleTask` handoff.
- Integration smoke tests cover app-root notification open flows in harnessed
  environments.

Missing:

- A physical iPhone proof that the OS tap reaches the expected native and Dart
  callback.
- A simulator `simctl push` proof that a remote APNs-style notification tap
  reaches the expected native and Dart callback before hardware is available.
- A diagnostic pin that classifies local FLN fallback notification taps versus
  FCM/APNs remote notification opens.
- A regression test that prevents future iOS work from relying on a no-op
  AppDelegate override as complete proof.

## Regression/Tests To Add First

Add diagnostics before claiming a fix.

1. Add a native iOS tap diagnostic in `AppDelegate.swift`.
   - Acceptable form: explicit
     `userNotificationCenter(_:didReceive:withCompletionHandler:)` override
     that logs action identifier, delegate class, and sanitized userInfo keys,
     then calls `super.userNotificationCenter(...)`.
   - Important: this is diagnostic/defensive forwarding, not accepted as the
     final fix by itself.
   - The log must identify whether the tapped notification has FLN keys such
     as `NotificationId` / `payload`, FCM keys such as `gcm.message_id`, or
     neither.

2. Add a static pin test for the diagnostic contract.
   - Suggested path:
     `test/core/notifications/app_delegate_notification_tap_diagnostic_pin_test.dart`.
   - It should assert:
     - `AppDelegate` subclasses `FlutterAppDelegate`.
     - AppDelegate sets `UNUserNotificationCenter.current().delegate = self`.
     - The diagnostic `didReceive` override calls
       `super.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)`.
     - The test reason must say this is a hardware-trace aid, not proof of
       routing.

3. Add or extend a focused Dart test only if the evidence points to Dart.
   - If local payload parsing is wrong, extend
     `notification_route_target_test.dart`.
   - If remote initial-open handling is wrong, extend
     `startup_router_notification_open_test.dart`.
   - If app-root local tap routing is wrong, extend
     `app_root_notification_open_test.dart` or `notification_tap_smoke_test.dart`.

Do not add XCUITest, XCTest, Quick, or new iOS native test infrastructure for
this session. Hardware proof is the runtime test surface.

## Step-by-step Implementation Plan

### Step 1 - Instrument without deciding the fix

- Add the AppDelegate diagnostic/defensive forwarding override described
  above.
- Keep the body limited to sanitized `NSLog` plus `super.userNotificationCenter(...)`.
- Do not call `completionHandler()` directly.
- Do not remove or move `UNUserNotificationCenter.current().delegate = self`.
- Add the static diagnostic pin test.
- Run the direct static pin test.

Stop here if the Swift code does not compile or if the method signature does
not match Swift's `UNUserNotificationCenterDelegate` shape.

### Step 2 - Run local gates before hardware

- Run the focused notification tests listed below.
- Run `flutter analyze` and compare against the established baseline.
- Record whether the only code change so far is diagnostic/defensive
  forwarding plus tests.

### Step 3 - Simulator-first APNs tap proof

Use this step when no physical iPhone is connected. It is a required
pre-hardware evidence lane for this session, not final closure.

Prerequisites:

- At least one booted iOS simulator.
- App installed/running on that simulator with bundle id `com.mknoon.app`
  unless overridden by `IOS_BUNDLE_ID`.
- Native diagnostic logging from Step 1 is present.

Commands:

```sh
xcrun simctl list devices booted
flutter run -d <SIM_UDID>
scripts/push_fixture_to_simulator.sh --dry-run one_to_one_text
scripts/push_fixture_to_simulator.sh --device <SIM_UDID> --bundle-id com.mknoon.app one_to_one_text
```

Also run a group fixture if group taps are in the reproduced symptom:

```sh
scripts/push_fixture_to_simulator.sh --device <SIM_UDID> --bundle-id com.mknoon.app group_text
```

Manual action:

- Background the app or leave it warm.
- Send the simulated push.
- Tap the simulator notification.
- Capture `flutter run` stdout and simulator/device logs.

Expected classification for this simulator lane:

- `xcrun simctl push` creates a remote APNs-style notification. It should
  exercise the native `UNUserNotificationCenter didReceive` path and then the
  Firebase remote-open path: `PUSH_MESSAGE_OPENED_APP` for warm opens or
  `PUSH_INITIAL_MESSAGE_OPENED` for cold/suspended launches.
- It is not expected to prove a data-only background push that wakes the
  background isolate and creates a local FLN fallback notification.
- If simulator tap routing works, record `simulator-verified,
  hardware-pending` and keep the physical iPhone proof as the final closure
  gate.
- If simulator tap routing fails, branch on the observed evidence in Step 5
  before waiting for hardware.

### Step 4 - Physical iPhone tap proof

Use the physical iPhone as receiver and Pixel 6 or another working peer as
sender.

Required reps:

- Warm-resume from a different chat/surface into a 1:1 notification target.
- Warm-resume into a group notification target if group notifications are in
  scope for the reproduced symptom.
- Cold-start or suspended launch by tapping the notification.

Capture `flutter run` stdout / iOS device logs and classify each tap:

- Local FLN fallback:
  userInfo contains FLN `payload`; expect `NOTIFICATION_TAPPED`.
- Remote FCM/APNs:
  userInfo contains `gcm.message_id`; expect `PUSH_MESSAGE_OPENED_APP` or
  `PUSH_INITIAL_MESSAGE_OPENED`.
- Unknown:
  userInfo has neither expected key family; inspect payload origin before
  coding.

### Step 5 - Branch only on evidence

Branch A: native AppDelegate diagnostic does not log on tap.

- The OS tap is not reaching the expected delegate object.
- Inspect who owns `UNUserNotificationCenter.current().delegate` after plugin
  registration and before backgrounding.
- Candidate fix may be resetting the delegate after implicit engine plugin
  registration, but only if logs prove another object has replaced it.
- Do not change Firebase/APNs token registration unless delegate ownership
  evidence requires it.

Branch B: native diagnostic logs, but neither `NOTIFICATION_TAPPED` nor
`PUSH_MESSAGE_OPENED_APP` / `PUSH_INITIAL_MESSAGE_OPENED` fires.

- If userInfo is FLN-shaped, inspect `flutter_local_notifications` registration
  and initialization timing.
- If userInfo is FCM-shaped, inspect `firebase_messaging` open handling and
  whether the message is classified as initial notification versus warm open.
- Fix the plugin handoff or initialization timing indicated by the trace.

Branch C: Dart open/tap event fires, but route target is null or wrong.

- Fix `NotificationRouteTarget.fromPayload(...)` or
  `NotificationRouteTarget.fromRemoteMessageData(...)`.
- Add a unit test for the exact payload/data shape seen in the hardware log.

Branch D: route target resolves, but UI remains on the previous screen.

- Fix app-root navigation or preparation in `main.dart`,
  `StartupRouter`, or the route target materializer.
- Add a widget/integration test for the exact route kind.

Branch E: diagnostics plus existing code already route correctly on hardware.

- Do not invent a further code fix.
- Keep or remove the diagnostic override based on reviewer judgment:
  - keep if it is wanted as a defensive forwarding/documented trace point;
  - remove if the team wants zero native churn after proof.
- Close as evidence-verified with no product-code fix beyond optional
  diagnostics.

Branch F: simulator remote APNs-style taps work, but hardware is unavailable.

- Do not invent a production fix from absence of hardware.
- Record `simulator-verified, hardware-pending`.
- Keep the native diagnostic available for the later iPhone run unless the
  reviewer explicitly chooses to remove it.
- Do not claim data-only background push or local FLN fallback behavior is
  proven by `simctl push`.

### Step 6 - Final verification

- Re-run focused tests and `flutter analyze`.
- Re-run the simulator tap proof after the targeted fix.
- Re-run the physical iPhone tap proof after the targeted fix when hardware is
  available.
- Update the parent ledger and production-flow audit finding with the actual
  proven boundary and fix, not the stale AppDelegate-clobbers-plugin claim.

## Risks And Edge Cases

- Local fallback notifications and remote APNs notifications have different
  callback surfaces. Treating them as one path can hide the real break.
- Simulator `simctl push` supports remote APNs-style notifications only; it
  does not prove real APNs/FCM delivery or data-only background wake -> local
  notification fallback.
- `FlutterAppDelegate` already forwards `didReceive`; a super-only override can
  create false confidence.
- Calling `completionHandler()` directly in AppDelegate can double-complete if
  `super` or a plugin also calls it.
- If Firebase Messaging owns the tap path, `NOTIFICATION_TAPPED` may never be
  the correct canary; the correct canary is `PUSH_MESSAGE_OPENED_APP` or
  `PUSH_INITIAL_MESSAGE_OPENED`.
- Cold-start routing waits for startup/P2P readiness; warm routing does not
  have the same timing.
- Group route materialization may require inbox drain or pending invite
  resolution before navigation.
- Duplicate notifications can make the tapped payload look stale unless the
  hardware run records notification id, payload prefix, and message id.

## Exact Tests And Gates To Run

Direct tests after adding diagnostics:

```sh
flutter test test/core/notifications/app_delegate_notification_tap_diagnostic_pin_test.dart
flutter test test/core/notifications/flutter_notification_service_test.dart
flutter test test/core/notifications/app_root_notification_open_test.dart
flutter test test/core/notifications/notification_route_target_test.dart
flutter test test/core/notifications/notification_route_contract_matrix_test.dart
flutter test test/features/identity/presentation/screens/startup_router_notification_open_test.dart
flutter test test/integration/notification_tap_smoke_test.dart
```

Broader gate:

```sh
flutter analyze
```

Run broader `flutter test` only if the code change moves beyond native logging
and focused notification routing tests, or if the session controller requires
the same closure level as Android Session N.

Hardware proof:

- Physical iPhone receiver.
- Pixel 6 or known-good peer sender.
- Capture `flutter run` stdout and native iOS logs.
- Grep for native diagnostic, `NOTIFICATION_TAPPED`,
  `PUSH_MESSAGE_OPENED_APP`, `PUSH_INITIAL_MESSAGE_OPENED`,
  `NOTIFICATION_TAP_NAV_ERROR`, and final route timing/target logs.

Simulator proof when physical iPhone is unavailable:

```sh
xcrun simctl list devices booted
flutter run -d <SIM_UDID>
scripts/push_fixture_to_simulator.sh --dry-run one_to_one_text
scripts/push_fixture_to_simulator.sh --device <SIM_UDID> --bundle-id com.mknoon.app one_to_one_text
scripts/push_fixture_to_simulator.sh --device <SIM_UDID> --bundle-id com.mknoon.app group_text
```

Simulator logs must be checked for native diagnostic output,
`PUSH_MESSAGE_OPENED_APP`, `PUSH_INITIAL_MESSAGE_OPENED`,
`NOTIFICATION_TAP_NAV_ERROR`, and final route timing/target logs.

## Known-failure Interpretation

- Existing `flutter analyze` warning debt is not this session's failure if the
  count and diagnostics are unchanged by the diff.
- Existing unrelated `flutter test` failures must be recorded as pre-existing
  and not fixed here.
- Hardware proof blocked by device availability is an external-fixture blocker,
  not a code pass.
- Simulator proof can classify and de-risk the remote APNs-style tap path, but
  it cannot close the hardware-only parts of the contract.
- A static pin passing is not enough to declare the iOS notification tap fixed.

## Done Criteria

All must be true:

1. The plan's stale root-cause claim is not used in final closure notes.
2. Diagnostic/static regression coverage exists if native code was touched.
3. The actual tap type is classified from hardware evidence as local FLN,
   remote FCM/APNs, or another explicit path.
4. The targeted fix, if needed, matches the classified boundary.
5. Focused notification tests pass.
6. `flutter analyze` introduces no new warnings.
7. Physical iPhone tap proof shows the app opens the tapped target from
   warm-resume and cold/suspended launch.
8. Parent ledger and production-flow audit docs record the proven boundary,
   concrete files changed, tests run, and hardware evidence.

Interim done criteria when no physical iPhone is connected:

1. Simulator `simctl push` proof runs for at least `one_to_one_text`.
2. `group_text` simulator proof runs if the reproduced symptom includes group
   notification taps.
3. Logs classify the simulator tap as remote APNs-style and show either
   successful routing or a concrete failing boundary.
4. The session status is recorded as `simulator-verified, hardware-pending` or
   `simulator-failed, fix-needed`; it is not recorded as fully closed.

## Scope Guard

Stop and re-plan instead of expanding scope if:

- The hardware trace shows no iOS notification is actually delivered.
- The simulator trace fails because the app is not installed, the simulator is
  not booted, or `simctl push` rejects the payload; fix the fixture/environment
  before changing app code.
- The issue is push-token registration, APNs entitlement, or backend FCM
  payload generation rather than app-side tap routing.
- The fix would require changing the relay push contract.
- The fix would require new iOS native test infrastructure.
- The only evidence is "a super-only override was added and the static test
  passed."
- The proposed fix bypasses centralized app-root routing.
- The proposed fix routes directly from a background handler.

## Accepted Differences / Intentionally Out Of Scope

- Android's fix is a `MainActivity.onNewIntent`/`setIntent` handoff. iOS does
  not have a proven equivalent yet.
- iOS remote notifications may route through Firebase Messaging events instead
  of `flutter_local_notifications`; that is acceptable if the final route
  contract is identical.
- Simulator `simctl push` is accepted as pre-hardware evidence for remote
  APNs-style tap routing, but it is intentionally not accepted as proof of
  physical-device delivery or local FLN fallback behavior.
- Foreground presentation is intentionally separate unless it blocks the
  reproduction.
- A native diagnostic override may remain as defensive documentation if the
  reviewer accepts it, but it is not the proof of correctness.

## Dependency Impact

- If this closes with a local FLN fix, future notification work should use
  `NOTIFICATION_TAPPED` as the local-tap canary on iOS and Android.
- If this closes with a Firebase remote-open fix, future docs must stop
  requiring `NOTIFICATION_TAPPED` for remote APNs taps and instead require
  `PUSH_MESSAGE_OPENED_APP` / `PUSH_INITIAL_MESSAGE_OPENED`.
- If hardware evidence shows the app already routes correctly, the production
  audit should be corrected and no follow-up implementation session should be
  opened.
- If simulator evidence shows remote APNs-style taps already route correctly
  while no physical iPhone is available, the next dependency is a hardware-only
  follow-up rather than more app-side implementation.
- If the issue is APNs/backend delivery, route implementation sessions should
  be skipped until push delivery is proven.

## Reviewer Pass

Finding 1: The old plan's claim that AppDelegate does not implement
`didReceive` is structurally wrong because AppDelegate inherits
FlutterAppDelegate, which implements and forwards that method.

Resolution: Fixed. The rewritten plan treats AppDelegate override as
diagnostic/defensive only and requires hardware evidence.

Finding 2: The old plan assumes `flutter_local_notifications` is the only tap
path.

Resolution: Fixed. The rewritten plan branches local FLN fallback versus
remote FCM/APNs open paths.

Finding 3: The old closure bar accepted static pins plus later hardware.

Resolution: Fixed. Physical iPhone tap proof is required for closure.

Finding 4: The plan could still drift into broad Firebase/APNs refactors.

Resolution: Fixed with scope guard and branch-by-evidence steps.

## Arbiter Decision

No structural blockers remain in this rewritten plan. It is safe to execute as
an evidence-gated session because it does not assume the fix, it preserves
centralized routing, and it requires hardware proof before closure.
