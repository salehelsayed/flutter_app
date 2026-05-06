# Session N (iOS) — Wire AppDelegate → flutter_local_notifications didReceive

iOS sibling of
[`session-N-android-notification-tap-onnewintent-plan-2026-05-05.md`](./session-N-android-notification-tap-onnewintent-plan-2026-05-05.md).
The Android plan was filed against
[`lock-window-fix-followups-tdd-plan-2026-05-04.md`](./lock-window-fix-followups-tdd-plan-2026-05-04.md)
under "Session N — Wire MainActivity → flutter_local_notifications onNewIntent"
and explicitly asserted the iOS path was "working per the artifact; do not
touch". That assumption is now **incorrect**: a 2026-05-06 follow-up trace of
the production-flow-integrity-auditor's
[`notification-tap-to-route`](../Production-Flow-Audits/findings/notification-tap-to-route-2026-05-05.md)
flow, plus the user's manual hardware confirmation, established that the iOS
side has the same class of break, at the symmetric boundary
(`UNUserNotificationCenter` → AppDelegate → `flutter_local_notifications` →
Dart `_onNotificationTap`). This document is the iOS-side fix plan.

Created 2026-05-06.

## Scope

Make the OS-level iOS notification tap deliver its `UNNotificationResponse`
payload to the Dart `_onNotificationTap` callback when the existing app
process is brought forward (warm-resume) or relaunched from suspended
(cold-resume via tap) on iOS 16+.

Strictly out of scope:
- Hardware re-run on a physical iPhone. Standing Rule 2.1 in the parent
  artifact mandates one, but the human owns it. Recorded as explicit
  follow-up after this session lands.
- Android path. Already addressed by `session-N-android-...-2026-05-05.md`.
- Foreground notification presentation
  (`userNotificationCenter:willPresent:withCompletionHandler:`). The
  symmetric AppDelegate-clobbers-plugin-delegate problem may also affect
  foreground presentation, but the user-reported symptom and audit finding
  are about the tap path. A separate session can audit `willPresent` if a
  finding is filed; do **not** expand this session to cover it.
- Refactoring `AppDelegate.swift`'s FCM/APNs registration or implicit-engine
  wiring. Those are co-located but unrelated.
- Removing `AppDelegate.swift:21` (`UNUserNotificationCenter.current().delegate
  = self`). That line may be needed by the FCM/APNs path elsewhere in the
  app (Firebase Messaging is wired in line 2 / 43); leaving it in place and
  adding a forwarding override is the safer minimal-touch fix.

## Likely code-entry files

- `ios/Runner/AppDelegate.swift` — the override target. Currently sets the
  AppDelegate as `UNUserNotificationCenter.current().delegate` (line 21) but
  does not implement the tap-response method, so taps that land in the
  AppDelegate's UN-delegate slot are silently dropped before they can reach
  the `flutter_local_notifications` plugin.
- `ios/Runner/Info.plist` — no edits expected; UNUserNotificationCenter
  delegation is purely runtime.
- `lib/core/notifications/flutter_notification_service.dart:55` — already
  wired (`_onNotificationResponse` is the FLOW canary that must start
  firing).
- `lib/main.dart:2367` — `_onNotificationTap` body (already in place).

## Likely test surface

- New: `test/core/notifications/app_delegate_user_notification_center_pin_test.dart`
  — a text-level regression pin, symmetric to
  `main_activity_onnewintent_pin_test.dart`. Reads `AppDelegate.swift`,
  asserts the file contains:
  - an `override func userNotificationCenter(...didReceive...withCompletionHandler:)`
    declaration, with parameter spelling tolerant of `UNNotificationResponse`
    on either Swift API form (Swift 5+ stable),
  - a `super.userNotificationCenter(center, didReceive: response,
    withCompletionHandler: completionHandler)` call inside that override
    (this is what causes `FlutterAppDelegate`'s plugin-pipeline forwarding
    to run, which is the actual fix), and
  - that the override is inside the `AppDelegate` class.
  This is the project-appropriate substitute for XCUITest / XCTest / Quick.
  It cannot prove the OS actually invokes the override on real-device tap —
  that is what the iPhone hardware soak (Standing Rule 2.1) is for. But it
  pins the *contract* the fix relies on, which is the regression class that
  just bit us symmetrically on Android.
- Existing: `test/core/notifications/flutter_notification_service_test.dart`
  remains valid; not modified by this session.
- Existing: `test/core/notifications/main_activity_onnewintent_pin_test.dart`
  remains valid; not modified.
- Existing: `flutter analyze` clean (no new warnings beyond the established
  baseline).

## Device / Relay Proof Profile

`external-fixture-blocked` for the end-to-end OS-tap proof.

- Profile: `os-notification-device-lab`. Single physical iPhone (the wireless
  device `00008030-001A6D2801BB802E` iOS 26.3.1 listed in
  `flutter devices` is suitable) as receiver, Pixel 6 sender (already paired
  via the 2026-05-05 hardware-soak DI), prod debug build of branch
  `new-background`. iOS Simulator is **not** acceptable for the verification
  — sim notification UX (no real lock screen, no real banner-tap) does not
  reliably exercise the `userNotificationCenter:didReceive:` path.
- Live device availability: NOT checked by this session — orchestrator was
  explicitly told not to flash a device. This session writes the code +
  static-pin test only. The hardware run is a follow-up the human owns.
- Closure evidence accepted from this session: code change present + static
  pin test green + `flutter test` overall green + `flutter analyze` no new
  warnings. Final hardware soak grep for `NOTIFICATION_TAPPED` (in `flutter
  run`'s stdout, since iOS does not have logcat) is recorded as explicit
  follow-up, not a controller blocker.

## Plan

### RED

Write `test/core/notifications/app_delegate_user_notification_center_pin_test.dart`:

```dart
// Pin: AppDelegate.swift must override
// userNotificationCenter(_:didReceive:withCompletionHandler:) and call
// super.userNotificationCenter(...), otherwise on iOS the tap-response is
// intercepted at the AppDelegate (which sets itself as the UN delegate at
// AppDelegate.swift:21) and never reaches the flutter_local_notifications
// plugin's didReceiveNotificationResponse dispatcher. Without that
// dispatcher, the Dart _onNotificationTap callback never fires and the
// app resumes to whichever screen was last visible (mirror of the
// Android Pixel hardware-soak symptom 2026-05-05).
//
// This is a text-level pin, not a runtime test — the project does not
// have XCUITest / XCTest / Quick infrastructure today, and the bug
// surface (UN delegate ownership across AppDelegate / plugin / FCM)
// cannot be reproduced off-device. Standing Rule 2.1 in
// Test-Flight-Improv/Group-Chat-Feature/lock-window-fix-followups-tdd-plan-2026-05-04.md
// requires a real-OS-tap hardware soak as the runtime regression catcher;
// this test is the cheap static catcher that goes alongside.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
      'AppDelegate.swift overrides userNotificationCenter didReceive and '
      'forwards to super', () {
    final file = File('ios/Runner/AppDelegate.swift');
    expect(file.existsSync(), isTrue,
        reason: 'AppDelegate.swift is the override target named by Session N (iOS).');

    final source = file.readAsStringSync();

    // Must override userNotificationCenter(_:didReceive:withCompletionHandler:).
    // Tolerate optional whitespace and the `_` external parameter label that
    // is canonical on the UNUserNotificationCenterDelegate protocol.
    final overrideRegex = RegExp(
      r'override\s+func\s+userNotificationCenter\s*\(\s*'
      r'_\s+center\s*:\s*UNUserNotificationCenter\s*,\s*'
      r'didReceive\s+response\s*:\s*UNNotificationResponse\s*,\s*'
      r'withCompletionHandler\s+completionHandler\s*:\s*'
      r'@escaping\s*\(\s*\)\s*->\s*Void\s*\)',
    );
    expect(
      overrideRegex.hasMatch(source),
      isTrue,
      reason: 'AppDelegate must override '
          'userNotificationCenter(_:didReceive:withCompletionHandler:) — '
          'without this, the flutter_local_notifications plugin never '
          'observes the notification tap response on iOS, because '
          'AppDelegate.swift:21 sets the AppDelegate as the UN delegate.',
    );

    // Must forward to super so FlutterAppDelegate's plugin-pipeline
    // forwarding fires. This is the actual fix: super forwards the call to
    // every registered plugin, including flutter_local_notifications, which
    // then invokes didReceiveNotificationResponse on its Dart channel.
    final superForwardRegex = RegExp(
      r'super\.userNotificationCenter\s*\(\s*'
      r'center\s*,\s*'
      r'didReceive\s*:\s*response\s*,\s*'
      r'withCompletionHandler\s*:\s*completionHandler\s*\)',
    );
    expect(
      superForwardRegex.hasMatch(source),
      isTrue,
      reason: 'The override must call '
          'super.userNotificationCenter(center, didReceive: response, '
          'withCompletionHandler: completionHandler) — without the super '
          'call, FlutterAppDelegate cannot dispatch to the plugin pipeline '
          'and the tap is silently dropped.',
    );
  });
}
```

This test fails on the current `new-background` HEAD because
`AppDelegate.swift` does not contain any
`userNotificationCenter(_:didReceive:withCompletionHandler:)` override.

### GREEN

Edit `ios/Runner/AppDelegate.swift` to add the override. The minimal,
non-clobbering change is to insert a single method on the `AppDelegate`
class. Place it after the existing
`didFailToRegisterForRemoteNotificationsWithError` method (line 59) and
before the `didInitializeImplicitFlutterEngine` callback (line 61) so the
notification-related delegate methods stay grouped together.

```swift
/// Required for flutter_local_notifications on iOS.
///
/// `AppDelegate` sets itself as the `UNUserNotificationCenter` delegate at
/// `application(_:didFinishLaunchingWithOptions:)` (see line ~21) so that
/// FCM-related foreground/will-present customizations have a place to live.
/// That assignment, however, prevents the `flutter_local_notifications`
/// plugin from cleanly owning the delegate slot itself: even when the
/// plugin tries to re-claim ownership during plugin registration (which is
/// further deferred in this app by `FlutterImplicitEngineDelegate` /
/// `didInitializeImplicitFlutterEngine`), Firebase Messaging may re-claim
/// the slot back, and any tap that lands in the AppDelegate slot without an
/// explicit forwarding override is silently dropped.
///
/// Forwarding to `super` here triggers `FlutterAppDelegate`'s
/// plugin-pipeline dispatch, which calls
/// `userNotificationCenter:didReceiveNotificationResponse:withCompletionHandler:`
/// on every registered plugin — including `flutter_local_notifications`,
/// which then invokes `didReceiveNotificationResponse` on its Dart channel.
/// That is what causes `_onNotificationResponse` (and therefore
/// `_onNotificationTap`, and therefore `_handleNotificationRouteTarget`) to
/// fire, finally routing the user to the correct conversation.
///
/// Diagnosed in the Pixel ↔ iPhone hardware soak follow-up on 2026-05-06;
/// see Test-Flight-Improv/Production-Flow-Audits/findings/notification-tap-to-route-2026-05-05.md
/// (re-audit note added 2026-05-06) and
/// Test-Flight-Improv/Group-Chat-Feature/lock-window-fix-followups-tdd-plan-2026-05-04.md
/// (Standing Rule 2.1 — real-device hardware soak required for verification).
/// The matching Dart pin test
/// (test/core/notifications/app_delegate_user_notification_center_pin_test.dart)
/// is the static catcher.
override func userNotificationCenter(
  _ center: UNUserNotificationCenter,
  didReceive response: UNNotificationResponse,
  withCompletionHandler completionHandler: @escaping () -> Void
) {
  super.userNotificationCenter(
    center,
    didReceive: response,
    withCompletionHandler: completionHandler
  )
}
```

Notes:
- The signature **must** match the `UNUserNotificationCenterDelegate`
  protocol exactly. The `_` external parameter label on `center` is
  required — Swift's protocol shape uses the underscore there. The pin
  regex in the RED test enforces this spelling.
- `super.userNotificationCenter(...)` is the entire body. Do not call
  `completionHandler()` directly — `super` is responsible for either
  invoking `completionHandler` itself (after plugins finish) or forwarding
  the responsibility to the plugin pipeline. Calling it twice is a
  documented crash on Apple's `os_log`.
- Do **not** remove `AppDelegate.swift:21`
  (`UNUserNotificationCenter.current().delegate = self`). That assignment
  is load-bearing for FCM/APNs registration paths elsewhere in the
  AppDelegate. The override is what makes coexistence with the plugin
  work; removing the delegate line is a wider scope change with FCM
  implications.
- `FlutterAppDelegate` (the parent class) implements
  `UNUserNotificationCenterDelegate` and forwards to plugins via its
  internal plugin registry; this is the contract this fix relies on. If
  the Flutter version ever stops doing this forwarding, the Dart pin
  test still passes (since the override is present) but the runtime
  behavior would regress — Standing Rule 2.1's hardware soak is the
  catcher for that class of upstream regression.

### REFACTOR

Two REFACTOR items in scope; mirroring the Android session's split.

**In scope, landed in this session:**
- The Swift override carries a substantial doc comment (above) that names
  the bug, the soak date, the AppDelegate-clobbers-delegate root cause,
  and the link back to this artifact. Future readers don't need to
  re-derive the reason. Mirror of the KDoc block on Android.

**Deferred, recorded as explicit follow-up sub-row in the parent ledger:**
- `emitFlowEvent('NOTIFICATION_DID_RECEIVE_RESPONSE', ...)` on the Dart
  side in `_onResumed`. To do this honestly, AppDelegate would need to
  surface a signal ("the tap response just landed at the AppDelegate
  level") to Dart over a MethodChannel — a non-trivial new bridge
  surface. Out of scope for this minimal-touch session. The Swift-side
  `NSLog` that the plan also mentions (a debug-build-only
  `response.notification.request.content.userInfo` dump) is also
  deferred — it is diagnostic-only and not load-bearing for the fix.
  Both are recorded as follow-ups in the parent ledger so they aren't
  forgotten.
- `userNotificationCenter:willPresent:withCompletionHandler:` audit. The
  same AppDelegate-clobbers-delegate dynamic could be silently dropping
  *foreground* notification presentations as well. Filing as a separate
  finding under `notification-tap-to-route`'s flow file (or a new flow if
  the auditor prefers) so a future session triages.

### Verification (per spec, scoped to what runs without hardware)

- `flutter test test/core/notifications/app_delegate_user_notification_center_pin_test.dart`
  GREEN.
- `flutter test` overall GREEN (no regression in the broader suite).
- `flutter analyze` no new warnings beyond the established baseline.
- `git diff` shows exactly the two files changed:
  - `ios/Runner/AppDelegate.swift`
  - `test/core/notifications/app_delegate_user_notification_center_pin_test.dart`
- Hardware soak (per Standing Rule 2.1): NOT run by this session. Recorded
  as explicit external-fixture follow-up in the parent ledger; the human
  performs it manually on the wireless iPhone + Pixel 6 sender pair.

## Done criteria

1. `AppDelegate.swift` contains the
   `userNotificationCenter(_:didReceive:withCompletionHandler:)` override
   calling
   `super.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler)`.
2. Static pin test exists at
   `test/core/notifications/app_delegate_user_notification_center_pin_test.dart`
   and passes.
3. `flutter test` overall passes (or the only failures are pre-existing
   and documented in CLAUDE.md / project memory; e.g., the four
   `onAddressesUpdated` Bridge interface failures recorded under
   `## Image Processing (UI-12)`).
4. `flutter analyze` no new warnings.
5. The parent ledger row for Session N (iOS) is opened (or appended to
   the existing Android Session N row) with status `Code-landed,
   hardware-pending`, concrete file + test references, and the explicit
   hardware follow-up recorded.
6. Production-Flow-Audits side: append to
   `Test-Flight-Improv/Production-Flow-Audits/findings/notification-tap-to-route-2026-05-05.md`
   a `notif-tap-2026-05-06-002` block (or move to a new dated file
   `notification-tap-to-route-2026-05-06.md` if the auditor's schema
   prefers) describing the iOS variant of the same break + this session's
   fix path. Update the ledger row's findings-file pointer accordingly.

## Scope guard

If during execution any of these surface, STOP and reclassify rather than
expand scope:
- Existing `flutter test` failures unrelated to notifications. Do not fix
  them; mark them out of scope.
- Need to add XCUITest / XCTest / Quick / iOS native test infrastructure.
  Do not add. The static pin test is the project-appropriate substitute
  and is symmetric to the Android Session N approach.
- Adding the MethodChannel for `NOTIFICATION_DID_RECEIVE_RESPONSE`. Defer.
  Not a blocker; recorded as follow-up.
- Auditing or fixing `userNotificationCenter:willPresent:withCompletionHandler:`
  — file as a separate finding for a future session, do not bundle with
  this fix.
- Removing or moving `AppDelegate.swift:21`
  (`UNUserNotificationCenter.current().delegate = self`). Out of scope —
  the FCM path may depend on it, and the override is the targeted minimal
  fix.
- Touching FCM / APNs registration code in `AppDelegate.swift`. Out of
  scope.
- Switching from `FlutterImplicitEngineDelegate` to standard
  `FlutterAppDelegate` plugin registration. Architectural change; out of
  scope.
- Android notification path. Working per the matching Android Session N;
  do not touch.
