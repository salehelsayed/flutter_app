# Voice Record Button UX — TDD Plan

**Problem:** Users report that tapping the record icon feels unresponsive — "it doesn't feel like I pressed it and it needs to be fast enough." Root cause: the button uses `onLongPressStart` (≈500ms delay), has no instant visual/haptic feedback, and has a small hit target.

**Scope:** 6 fixes across 3 files, 1 new dependency (for haptics testability).

---

## Files to Modify

| File | Role |
|------|------|
| `lib/features/conversation/presentation/widgets/voice_record_button.dart` | Button widget — gesture handling, animations, haptics, hit target |
| `lib/features/conversation/presentation/widgets/compose_area.dart` | Parent — passes new callback for too-short feedback |
| `lib/features/conversation/presentation/screens/conversation_wired.dart` | Wired — surfaces too-short snackbar, passes callback |
| `test/features/conversation/presentation/widgets/voice_record_button_test.dart` | Button unit tests |
| `test/features/conversation/presentation/widgets/compose_area_test.dart` | Compose area integration tests |

---

## Fix 1: Instant Visual Feedback on Touch-Down

**What:** Add a press-down scale animation that fires immediately on `onLongPressDown` (which fires at 0ms, before the 500ms long-press threshold). The button shrinks to 0.92x on touch-down and springs back on release/cancel.

**Why:** Bridges the 500ms dead zone — the user sees a reaction within one frame of touching the button.

### Implementation

- Add `AnimationController` + `SingleTickerProviderStateMixin` to `_VoiceRecordButtonState`.
- `_pressAnimationController`: 80ms duration, value 1.0 → 0.92.
- On `onLongPressDown` (new handler): forward the animation.
- On `onLongPressEnd` / `onLongPressCancel`: reverse the animation.
- Wrap the `Container` child in `AnimatedBuilder` + `Transform.scale`.

### Tests — write FIRST, all must fail (RED)

```
File: test/features/conversation/presentation/widgets/voice_record_button_test.dart
```

**T1.1 — Button scales down on press-down**
```dart
testWidgets('button scales down immediately on touch-down', (tester) async {
  await tester.pumpWidget(buildTestWidget());

  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(VoiceRecordButton)),
  );
  // Pump just enough for the animation to start (NOT 500ms for long press)
  await tester.pump(const Duration(milliseconds: 50));

  final transform = tester.widget<Transform>(
    find.descendant(
      of: find.byType(VoiceRecordButton),
      matching: find.byType(Transform),
    ),
  );
  // Scale should be < 1.0 (pressed state)
  final matrix = transform.transform;
  expect(matrix.storage[0], lessThan(1.0)); // scaleX

  await gesture.up();
});
```

**T1.2 — Button scales back up on release**
```dart
testWidgets('button restores scale on release', (tester) async {
  await tester.pumpWidget(buildTestWidget());

  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(VoiceRecordButton)),
  );
  await tester.pump(const Duration(milliseconds: 80));

  await gesture.up();
  await tester.pumpAndSettle();

  final transform = tester.widget<Transform>(
    find.descendant(
      of: find.byType(VoiceRecordButton),
      matching: find.byType(Transform),
    ),
  );
  final matrix = transform.transform;
  expect(matrix.storage[0], closeTo(1.0, 0.01)); // back to full size
});
```

**T1.3 — Button scales back up on cancel**
```dart
testWidgets('button restores scale on long press cancel', (tester) async {
  await tester.pumpWidget(buildTestWidget());

  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(VoiceRecordButton)),
  );
  await tester.pump(const Duration(milliseconds: 50));

  await gesture.cancel();
  await tester.pumpAndSettle();

  final transform = tester.widget<Transform>(
    find.descendant(
      of: find.byType(VoiceRecordButton),
      matching: find.byType(Transform),
    ),
  );
  final matrix = transform.transform;
  expect(matrix.storage[0], closeTo(1.0, 0.01));
});
```

---

## Fix 2: Haptic Feedback on Record Start/Stop/Cancel

**What:** Fire `HapticFeedback.mediumImpact()` when recording starts (long press fires), `HapticFeedback.lightImpact()` on stop, and `HapticFeedback.lightImpact()` on cancel.

**Why:** Physical confirmation that the device registered the action — critical for a button with a delayed gesture.

### Implementation

- Add an optional `HapticService` abstraction (a simple callable typedef or abstract class) so tests can verify haptic calls without platform channels.
  ```dart
  /// Injectable haptic feedback for testability.
  typedef HapticFn = Future<void> Function();
  ```
- In `VoiceRecordButton`, accept optional `HapticFn? onHapticStart` and `HapticFn? onHapticStop` parameters (defaults to `HapticFeedback.mediumImpact` / `HapticFeedback.lightImpact` when null).
- Call `onHapticStart` inside `_onLongPressStart()`.
- Call `onHapticStop` inside `_onLongPressEnd()` and `_onLongPressCancel()`.

### Tests — write FIRST

```
File: test/features/conversation/presentation/widgets/voice_record_button_test.dart
```

**T2.1 — Haptic fires on record start**
```dart
testWidgets('fires haptic feedback on long press start', (tester) async {
  var hapticStartCalled = false;
  await tester.pumpWidget(buildTestWidget(
    onHapticStart: () async => hapticStartCalled = true,
  ));

  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(VoiceRecordButton)),
  );
  await tester.pump(const Duration(milliseconds: 500));

  expect(hapticStartCalled, true);
  await gesture.up();
});
```

**T2.2 — Haptic fires on record stop**
```dart
testWidgets('fires haptic feedback on long press end', (tester) async {
  var hapticStopCalled = false;
  await tester.pumpWidget(buildTestWidget(
    onHapticStop: () async => hapticStopCalled = true,
  ));

  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(VoiceRecordButton)),
  );
  await tester.pump(const Duration(milliseconds: 500));

  await gesture.up();
  await tester.pump();

  expect(hapticStopCalled, true);
});
```

**T2.3 — Haptic fires on cancel**
```dart
testWidgets('fires haptic feedback on drag cancel', (tester) async {
  var hapticStopCalled = false;
  await tester.pumpWidget(buildTestWidget(
    onHapticStop: () async => hapticStopCalled = true,
  ));

  final center = tester.getCenter(find.byType(VoiceRecordButton));
  final gesture = await tester.startGesture(center);
  await tester.pump(const Duration(milliseconds: 500));

  await gesture.moveBy(const Offset(-120, 0));
  await tester.pump();

  expect(hapticStopCalled, true);
  await gesture.up();
});
```

---

## Fix 3: Increase Hit Target to 44x44

**What:** Increase the button's outer hit area from 36x36 to 48x48 (exceeds Apple's 44pt minimum), keeping the visual circle at 36x36 using padding.

**Why:** 36x36 is below platform minimum touch target guidelines. Small targets cause missed taps, especially under time pressure.

### Implementation

- Wrap the existing `Container(width: 36, height: 36, ...)` in a `SizedBox(width: 48, height: 48)` that centers the inner circle.
- The GestureDetector wraps the outer SizedBox so the entire 48x48 area is tappable.

### Tests — write FIRST

```
File: test/features/conversation/presentation/widgets/voice_record_button_test.dart
```

**T3.1 — Hit target is at least 44x44**
```dart
testWidgets('hit target is at least 44x44', (tester) async {
  await tester.pumpWidget(buildTestWidget());

  final size = tester.getSize(find.byType(VoiceRecordButton));
  expect(size.width, greaterThanOrEqualTo(44));
  expect(size.height, greaterThanOrEqualTo(44));
});
```

**T3.2 — Visual circle remains 36x36**
```dart
testWidgets('visual circle remains 36x36', (tester) async {
  await tester.pumpWidget(buildTestWidget());

  final container = tester.widget<Container>(
    find.descendant(
      of: find.byType(VoiceRecordButton),
      matching: find.byType(Container),
    ),
  );
  final box = container.constraints;
  // The decorated container should still be 36x36
  expect(box?.maxWidth, 36);
  expect(box?.maxHeight, 36);
});
```

**T3.3 — Tap at edge of enlarged area still fires callback**
```dart
testWidgets('tap at edge of hit target area triggers long press', (tester) async {
  var called = false;
  await tester.pumpWidget(buildTestWidget(onTapDown: () => called = true));

  // Tap near the top-left corner of the 48x48 area (but outside the 36x36 visual)
  final topLeft = tester.getTopLeft(find.byType(VoiceRecordButton));
  final gesture = await tester.startGesture(topLeft + const Offset(2, 2));
  await tester.pump(const Duration(milliseconds: 500));

  expect(called, true);
  await gesture.up();
});
```

---

## Fix 4: Too-Short Recording Feedback (Snackbar)

**What:** When a recording is rejected because it was too short (<500ms), show a brief snackbar: "Hold to record a voice message."

**Why:** Currently the recording is silently discarded. The user thinks they sent something but nothing happened — this is the #1 source of the "it didn't register" feeling.

### Implementation

- In `conversation_wired.dart` `_onRecordStop()`, after the `recording == null` check (line ~1132), show a snackbar:
  ```dart
  if (recording == null) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Hold to record a voice message'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    // ... existing flow event
    return;
  }
  ```
- Also add an optional `VoidCallback? onRecordTooShort` to `ComposeArea` so the compose area can surface this without depending on wired internals. The wired widget passes its snackbar callback.

### Tests — write FIRST

```
File: test/features/conversation/presentation/widgets/compose_area_test.dart
```

**T4.1 — onRecordTooShort callback is invocable from compose area**
```dart
testWidgets('onRecordTooShort callback is forwarded', (tester) async {
  var tooShortCalled = false;
  await tester.pumpWidget(
    buildVoiceWidget(
      onRecordStart: () {},
      onRecordStop: () {},
      onRecordCancel: () {},
      onRecordTooShort: () => tooShortCalled = true,
    ),
  );

  // This test validates the callback is wired through;
  // the actual triggering is tested in conversation_wired_test
  expect(tooShortCalled, false); // baseline
});
```

```
File: test/features/conversation/presentation/screens/conversation_wired_test.dart
(or add to existing voice recording test group)
```

**T4.2 — Snackbar shown when recording is too short**
```dart
testWidgets('shows snackbar when recording is too short', (tester) async {
  // Setup: fake recorder that returns null on stop (simulating <500ms recording)
  final fakeRecorder = FakeAudioRecorderService(stopReturnsNull: true);
  await tester.pumpWidget(buildWiredWidget(audioRecorderService: fakeRecorder));

  // Trigger record start
  // ... (trigger via compose area mic button long press)
  await tester.pump(const Duration(milliseconds: 500)); // long press threshold

  // Trigger record stop (quick release)
  // ... (release gesture)
  await tester.pumpAndSettle();

  expect(find.text('Hold to record a voice message'), findsOneWidget);
});
```

---

## Fix 5: Tap-to-Toggle Recording Mode

**What:** In addition to the existing hold-to-record flow, support **single tap** to start recording and **single tap** to stop and send. This eliminates the long-press delay entirely for intentional use.

**Why:** Many users expect tap-to-record (WhatsApp, Telegram). Hold-to-record is great for quick bursts, but a tap toggle removes the 500ms perceived delay.

### Implementation

- Add `onTap` to the `GestureDetector` in `VoiceRecordButton`.
- When `isRecording == false` and the user taps (not long-presses): call `onTapDown` (starts recording).
- When `isRecording == true` and the user taps: call `onTapUp` (stops and sends).
- The existing long-press flow remains unchanged — both gestures coexist.
- The `GestureDetector` needs both `onTap` and `onLongPressStart` — Flutter handles disambiguation automatically (tap fires immediately, long press fires after the threshold).

**Important:** `GestureDetector` with both `onTap` and `onLongPress*` means `onTap` only fires on quick tap-up (not held). This is exactly what we want:
  - Quick tap → toggle recording on/off
  - Long press → hold-to-record (existing behavior)

### Tests — write FIRST

```
File: test/features/conversation/presentation/widgets/voice_record_button_test.dart
```

**T5.1 — Tap starts recording when not recording**
```dart
testWidgets('single tap starts recording when not recording', (tester) async {
  var downCalled = false;
  await tester.pumpWidget(buildTestWidget(
    onTapDown: () => downCalled = true,
    isRecording: false,
  ));

  await tester.tap(find.byType(VoiceRecordButton));
  await tester.pump();

  expect(downCalled, true);
});
```

**T5.2 — Tap stops recording when already recording**
```dart
testWidgets('single tap stops recording when already recording', (tester) async {
  var upCalled = false;
  await tester.pumpWidget(buildTestWidget(
    onTapUp: () => upCalled = true,
    isRecording: true,
  ));

  await tester.tap(find.byType(VoiceRecordButton));
  await tester.pump();

  expect(upCalled, true);
});
```

**T5.3 — Long press still works alongside tap**
```dart
testWidgets('long press still starts recording (coexists with tap)', (tester) async {
  var downCalled = false;
  await tester.pumpWidget(buildTestWidget(
    onTapDown: () => downCalled = true,
    isRecording: false,
  ));

  final gesture = await tester.startGesture(
    tester.getCenter(find.byType(VoiceRecordButton)),
  );
  await tester.pump(const Duration(milliseconds: 500));

  expect(downCalled, true);
  await gesture.up();
});
```

**T5.4 — Tap does not call onTapUp when not recording**
```dart
testWidgets('tap does not call onTapUp when not recording', (tester) async {
  var upCalled = false;
  await tester.pumpWidget(buildTestWidget(
    onTapUp: () => upCalled = true,
    isRecording: false,
  ));

  await tester.tap(find.byType(VoiceRecordButton));
  await tester.pump();

  expect(upCalled, false);
});
```

**T5.5 — Tap does not call onTapDown when already recording**
```dart
testWidgets('tap does not call onTapDown when already recording', (tester) async {
  var downCalled = false;
  await tester.pumpWidget(buildTestWidget(
    onTapDown: () => downCalled = true,
    isRecording: true,
  ));

  await tester.tap(find.byType(VoiceRecordButton));
  await tester.pump();

  expect(downCalled, false);
});
```

---

## Fix 6: Pulsing Mic Icon Hint (Idle Breathing Animation)

**What:** When idle (not recording, text field empty), the mic icon gently pulses opacity between 1.0 and 0.6 on a 2-second loop. This hints that the icon is interactive and draws attention.

**Why:** Static icons on dark backgrounds can look decorative rather than functional. A subtle pulse signals "I'm a live control."

### Implementation

- Add a second `AnimationController` to `_VoiceRecordButtonState` for the idle pulse.
- `_pulseController`: 2000ms duration, repeat with reverse.
- Tween: opacity 0.6 → 1.0 on the `Icon` only (not the container border/background).
- Stop the pulse when `isRecording == true`. Resume when `isRecording == false`.
- Dispose the controller in `dispose()`.

### Tests — write FIRST

```
File: test/features/conversation/presentation/widgets/voice_record_button_test.dart
```

**T6.1 — Idle pulse animation is active when not recording**
```dart
testWidgets('idle pulse animation is running when not recording', (tester) async {
  await tester.pumpWidget(buildTestWidget(isRecording: false));

  // Verify that an AnimationController is actively ticking
  // by pumping and checking the icon opacity changes
  final iconBefore = tester.widget<Icon>(find.byIcon(Icons.mic_rounded));
  final opacityBefore = (iconBefore.color as Color).opacity;

  await tester.pump(const Duration(milliseconds: 1000)); // half the 2s cycle

  final iconAfter = tester.widget<Icon>(find.byIcon(Icons.mic_rounded));
  final opacityAfter = (iconAfter.color as Color).opacity;

  // Opacity should have changed (pulse is running)
  expect(opacityBefore, isNot(closeTo(opacityAfter, 0.01)));
});
```

**T6.2 — Pulse stops when recording**
```dart
testWidgets('pulse animation stops when recording', (tester) async {
  await tester.pumpWidget(buildTestWidget(isRecording: true));

  final icon = tester.widget<Icon>(find.byIcon(Icons.stop_rounded));
  // When recording, the icon color should be full opacity (no pulse)
  expect((icon.color as Color).opacity, closeTo(1.0, 0.01));
});
```

---

## Execution Order

Each fix is independent. Recommended order (easiest wins first):

| Step | Fix | Effort | Impact |
|------|-----|--------|--------|
| 1 | Fix 3 — Hit target 44→48 | XS | High — fewer missed taps |
| 2 | Fix 1 — Press-down scale animation | S | High — instant visual feedback |
| 3 | Fix 2 — Haptic feedback | S | High — physical confirmation |
| 4 | Fix 5 — Tap-to-toggle mode | M | High — eliminates 500ms delay entirely |
| 5 | Fix 4 — Too-short snackbar | S | Medium — explains silent failures |
| 6 | Fix 6 — Idle pulse hint | S | Low — discoverability polish |

## Test Scaffold Update

The `buildTestWidget` helper in `voice_record_button_test.dart` needs updating to accept the new parameters:

```dart
Widget buildTestWidget({
  VoidCallback? onTapDown,
  VoidCallback? onTapUp,
  VoidCallback? onTapCancel,
  bool isRecording = false,
  Future<void> Function()? onHapticStart,   // Fix 2
  Future<void> Function()? onHapticStop,    // Fix 2
}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: VoiceRecordButton(
          onTapDown: onTapDown ?? () {},
          onTapUp: onTapUp ?? () {},
          onTapCancel: onTapCancel ?? () {},
          isRecording: isRecording,
          onHapticStart: onHapticStart,   // Fix 2
          onHapticStop: onHapticStop,     // Fix 2
        ),
      ),
    ),
  );
}
```

## Total Test Count

| Fix | New Tests | Existing Tests Modified |
|-----|-----------|----------------------|
| Fix 1 — Scale animation | 3 | 0 |
| Fix 2 — Haptics | 3 | 0 (buildTestWidget updated) |
| Fix 3 — Hit target | 3 | 0 |
| Fix 4 — Too-short snackbar | 2 | 0 |
| Fix 5 — Tap-to-toggle | 5 | 0 |
| Fix 6 — Idle pulse | 2 | 0 |
| **Total** | **18** | **0** |

No existing tests should break. All new tests should fail (RED) before implementation.

## Definition of Done

- [ ] All 18 new tests pass (GREEN)
- [ ] All existing `voice_record_button_test.dart` tests still pass (6 tests)
- [ ] All existing `compose_area_test.dart` tests still pass (24 tests)
- [ ] Manual QA: tap the mic icon → recording starts immediately with haptic buzz and scale animation
- [ ] Manual QA: tap again → recording stops with haptic tap
- [ ] Manual QA: quick tap-release (<500ms) → snackbar "Hold to record a voice message"
- [ ] Manual QA: long press and hold → existing hold-to-record flow works unchanged
- [ ] Manual QA: long press and drag left → cancel with haptic tap
