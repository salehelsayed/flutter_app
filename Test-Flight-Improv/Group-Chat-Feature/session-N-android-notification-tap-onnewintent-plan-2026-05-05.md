# Session N — Wire MainActivity → flutter_local_notifications onNewIntent

Doc-scoped plan for the Session N row in
[`lock-window-fix-followups-tdd-plan-2026-05-04.md`](./lock-window-fix-followups-tdd-plan-2026-05-04.md)
(section starting at line 365, "2026-05-05 hardware-soak finding — Android
notification-tap callback never fires"; Session N body at lines 471–520).

Created 2026-05-05 by the implementation-session-pipeline-orchestrator local
plan-fallback path (no spawned planner — see parent ledger Controller
Progress).

## Scope

Make the OS-level Android notification tap deliver its PendingIntent payload
to the Dart `_onNotificationTap` callback when the existing app process is
brought forward via a notification tap on `singleTask` MainActivity. This is
the Pixel-soak scenario the artifact diagnosed: tap arrives, app foregrounds,
but `_onNotificationTap` (and therefore route resolution) never fires —
because `FlutterActivity` does not call `setIntent(intent)` inside
`onNewIntent`, so the `flutter_local_notifications` plugin (v18.0.1) never
sees the notification-response intent the system delivered to the Activity.

Strictly out of scope:
- Hardware re-run on physical Android device. Standing Rule 2.1 mandates one,
  but the human owns it (per rollout instructions). Recorded as explicit
  follow-up after this session lands.
- iOS path (already works, per the artifact).
- Sessions A / B / C above (already-landed-or-separate per user direction).
- Refactoring adjacent code (lock-window, listeners, repos).
- Introducing Robolectric / Espresso / `androidTest/` framework — none exists
  today, and bringing one in for a single override is disproportionate.

## Likely code-entry files

- `android/app/src/main/kotlin/com/mknoon/app/MainActivity.kt` — the override
  target. Currently bare (`configureFlutterEngine` only).
- `android/app/src/main/AndroidManifest.xml:20` — `launchMode="singleTask"`,
  the constraint that necessitates `setIntent` in `onNewIntent`.
- `lib/core/notifications/flutter_notification_service.dart` — already wired
  (the FLOW canary at `_onNotificationResponse` is what must start firing).
- `lib/main.dart:2367` — `_onNotificationTap` body (already in place).

## Likely test surface

- New: `test/core/notifications/main_activity_onnewintent_pin_test.dart` — a
  text-level regression pin. Reads `MainActivity.kt`, asserts the file
  contains:
  - `override fun onNewIntent(intent: Intent)` (or `Intent?` — spec allows
    either based on Flutter embedding API stability),
  - a call to `setIntent(intent)` inside that override,
  - and that the override is present in the `MainActivity` class.
  This is the project-appropriate substitute for Robolectric / instrumentation
  testing. It cannot prove the plugin actually receives the intent on a real
  device — that is what the hardware soak (Standing Rule 2.1) is for. But it
  pins the *contract* the fix relies on, which is exactly the regression class
  that just bit us (the override silently absent).
- Existing: `test/core/notifications/flutter_notification_service_test.dart`
  remains valid; not modified by this session.
- Existing: `flutter analyze` clean (no new warnings beyond the established
  baseline).

## Device / Relay Proof Profile

`external-fixture-blocked` for the end-to-end OS-tap proof.

- Profile: `os-notification-device-lab`. Single Pixel 6 / Android 16 receiver,
  iOS sim sender, prod debug build of branch `new-background`. Required for
  Standing Rule 2.1 verification.
- Live device availability: NOT checked by this session — orchestrator was
  explicitly told not to flash a device. This session writes the code +
  static-pin test only. The hardware run is a follow-up the human owns.
- Closure evidence accepted from this session: code change present + static
  pin test green + `flutter test` overall green + `flutter analyze` no new
  warnings. Final hardware soak grep for `NOTIFICATION_TAPPED` is recorded
  as explicit follow-up, not a controller blocker.

## Plan

### RED

Write `test/core/notifications/main_activity_onnewintent_pin_test.dart`:

```dart
// Pin: MainActivity.kt must override onNewIntent and call setIntent(intent),
// otherwise on Android with launchMode="singleTask" the flutter_local_notifications
// plugin never observes the notification PendingIntent and the Dart
// _onNotificationTap callback never fires (Pixel hardware soak 2026-05-05).
//
// This is a text-level pin, not a runtime test — the project does not have
// Android JVM / Robolectric / instrumentation test infrastructure today, and
// the bug surface (singleTask + Activity intent flow) cannot be reproduced
// off-device. Standing Rule 2.1 in
// Test-Flight-Improv/Group-Chat-Feature/lock-window-fix-followups-tdd-plan-2026-05-04.md
// requires a real-OS-tap hardware soak as the runtime regression catcher;
// this test is the cheap static catcher that goes alongside.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MainActivity.kt overrides onNewIntent and calls setIntent(intent)', () {
    final file = File('android/app/src/main/kotlin/com/mknoon/app/MainActivity.kt');
    expect(file.existsSync(), isTrue,
        reason: 'MainActivity.kt is the override target named by Session N.');

    final source = file.readAsStringSync();

    // Must override onNewIntent (Intent param spelling permitted variants).
    final overrideRegex = RegExp(
      r'override\s+fun\s+onNewIntent\s*\(\s*intent\s*:\s*Intent\??\s*\)',
    );
    expect(
      overrideRegex.hasMatch(source),
      isTrue,
      reason: 'MainActivity must override onNewIntent — without this, the '
          'flutter_local_notifications plugin never observes the notification '
          'PendingIntent on singleTask resume (Pixel soak 2026-05-05).',
    );

    // Must call setIntent(intent) — the actual fix per plugin docs for
    // singleTask apps.
    expect(
      RegExp(r'setIntent\s*\(\s*intent\s*\)').hasMatch(source),
      isTrue,
      reason: 'onNewIntent must call setIntent(intent); without this the '
          'subsequent FlutterActivity / plugin pickup of the intent extras '
          'silently fails.',
    );

    // Must call super.onNewIntent(intent) — required by the embedding contract;
    // skipping super has historically broken plugin propagation.
    expect(
      RegExp(r'super\.onNewIntent\s*\(\s*intent\s*\)').hasMatch(source),
      isTrue,
      reason: 'onNewIntent must call super.onNewIntent(intent) so the Flutter '
          'embedding plugin pipeline runs.',
    );
  });
}
```

This test fails on the current `main` (and on `new-background` HEAD) because
`MainActivity.kt` does not contain any `onNewIntent` override.

### GREEN

Edit `android/app/src/main/kotlin/com/mknoon/app/MainActivity.kt` to:

```kotlin
package com.mknoon.app

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var goBridge: GoBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        goBridge = GoBridge(flutterEngine)
    }

    /**
     * Required for flutter_local_notifications on singleTask apps.
     *
     * On Android, when launchMode="singleTask" (see AndroidManifest.xml), a
     * notification-tap PendingIntent is delivered to onNewIntent on the
     * existing MainActivity instance instead of starting a fresh activity.
     * The default FlutterActivity.onNewIntent does NOT call setIntent(intent),
     * so the intent extras (including the flutter_local_notifications
     * plugin's notification-response payload) are silently dropped before the
     * plugin's onDidReceiveNotificationResponse dispatcher can see them.
     *
     * Calling setIntent(intent) here makes the new intent visible to the
     * Flutter embedding's plugin pipeline, which then dispatches
     * didReceiveNotificationResponse to the Dart side and the
     * NOTIFICATION_TAPPED flow event finally fires.
     *
     * Diagnosed in the Pixel ↔ iOS-sim hardware soak on 2026-05-05; see
     * Test-Flight-Improv/Group-Chat-Feature/lock-window-fix-followups-tdd-plan-2026-05-04.md
     * (section "2026-05-05 hardware-soak finding"). Standing Rule 2.1 in the
     * same document requires a real-device hardware soak to verify — that is
     * the runtime regression catcher; the matching Dart pin test
     * (test/core/notifications/main_activity_onnewintent_pin_test.dart) is
     * the static catcher.
     */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }
}
```

Notes:
- Signature uses non-nullable `Intent` matching `FlutterActivity.onNewIntent`
  in flutter embedding 3.x. If the embedding ever switches to `Intent?` (it
  has not, but for defensive readability) the regex pin in the RED test
  accepts both spellings (`Intent\??`).
- `super.onNewIntent(intent)` first, then `setIntent(intent)` — order matches
  `flutter_local_notifications` plugin docs and the Android lifecycle
  contract.

### REFACTOR

Two REFACTOR items in the original spec; we land the in-scope half and
explicitly defer the bridge-coupled half.

**In scope, landed in this session:**
- The Kotlin override carries a substantial KDoc block (above) that names the
  bug, the soak date, the singleTask root cause, and the link back to this
  artifact. Future readers don't need to re-derive the reason.

**Deferred, recorded as explicit follow-up sub-row in the parent ledger:**
- `emitFlowEvent('NOTIFICATION_NEW_INTENT_RECEIVED', ...)` on the Dart side in
  `_onResumed`. To do this honestly, MainActivity needs to surface a signal
  ("the resume just had a notification-extra-bearing intent") to Dart over a
  MethodChannel — a non-trivial new bridge surface. Out of scope for this
  minimal-touch session. The Kotlin-side `Log.d` that the plan also mentions
  (a debug-build-only `intent.extras?.keySet()` dump) is also deferred — it is
  diagnostic-only and not load-bearing for the fix. Both are recorded as
  follow-ups in the parent ledger so they aren't forgotten.

### Verification (per spec, scoped to what runs without hardware)

- `flutter test test/core/notifications/main_activity_onnewintent_pin_test.dart` GREEN.
- `flutter test` overall GREEN (no regression in the broader suite).
- `flutter analyze` no new warnings beyond the established baseline.
- `git diff` shows exactly the two files changed:
  - `android/app/src/main/kotlin/com/mknoon/app/MainActivity.kt`
  - `test/core/notifications/main_activity_onnewintent_pin_test.dart`
- Hardware soak (per Standing Rule 2.1): NOT run by this session. Recorded as
  explicit external-fixture follow-up in the parent ledger; the human
  performs it manually on a Pixel + iOS-sim pair.

## Done criteria

1. `MainActivity.kt` contains the `onNewIntent` override calling
   `super.onNewIntent(intent)` then `setIntent(intent)`.
2. Static pin test exists at
   `test/core/notifications/main_activity_onnewintent_pin_test.dart` and
   passes.
3. `flutter test` overall passes (or the only failures are pre-existing and
   documented in CLAUDE.md / project memory; e.g., the four
   `onAddressesUpdated` Bridge interface failures recorded under
   `## Image Processing (UI-12)`).
4. `flutter analyze` no new warnings.
5. The parent ledger row for Session N is moved to `Code-landed,
   hardware-pending` with concrete file + test references and the explicit
   hardware follow-up recorded.

## Scope guard

If during execution any of these surface, STOP and reclassify rather than
expand scope:
- Existing `flutter test` failures unrelated to notifications. Do not fix
  them; mark them out of scope.
- Need to add Robolectric / Espresso / `androidTest/`. Do not add. The static
  pin test is the project-appropriate substitute and the spec text in the
  parent artifact explicitly says "or unit test of MainActivity's onNewIntent
  hook via Robolectric/Espresso, depending on what the project already
  supports" — the project supports neither, so the static pin is the
  available shape.
- Adding the MethodChannel for `NOTIFICATION_NEW_INTENT_RECEIVED`. Defer.
  Not a blocker; recorded as follow-up.
- iOS notification path. Working per the artifact; do not touch.
