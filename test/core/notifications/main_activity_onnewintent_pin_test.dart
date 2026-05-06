// Pin: MainActivity.kt must override onNewIntent and call setIntent(intent),
// otherwise on Android with launchMode="singleTask" the
// flutter_local_notifications plugin never observes the notification
// PendingIntent and the Dart _onNotificationTap callback never fires (Pixel
// hardware soak 2026-05-05).
//
// This is a text-level pin and a belt-and-braces companion to the
// behaviour-level Robolectric test at
// android/app/src/test/kotlin/com/mknoon/app/MainActivityOnNewIntentTest.kt
// (added in Session N+1, 2026-05-05). Either test catching a regression is
// sufficient; both passing is the green-bar guarantee. Standing Rule 2.1 in
// `Test-Flight-Improv/Group-Chat-Feature/lock-window-fix-followups-tdd-plan-2026-05-04.md`
// requires a real-OS-tap hardware soak as the runtime regression catcher;
// this pin plus the Robolectric regression are cheap PR-time catchers that go
// alongside it.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('MainActivity.kt overrides onNewIntent and calls setIntent(intent)', () {
    final file = File(
      'android/app/src/main/kotlin/com/mknoon/app/MainActivity.kt',
    );
    expect(
      file.existsSync(),
      isTrue,
      reason: 'MainActivity.kt is the override target named by Session N.',
    );

    final source = file.readAsStringSync();

    // Must override onNewIntent — accept both `Intent` and `Intent?` spellings
    // for forward-compatibility with future Flutter embedding API changes.
    final overrideRegex = RegExp(
      r'override\s+fun\s+onNewIntent\s*\(\s*intent\s*:\s*Intent\??\s*\)',
    );
    expect(
      overrideRegex.hasMatch(source),
      isTrue,
      reason:
          'MainActivity must override onNewIntent — without this, the '
          'flutter_local_notifications plugin never observes the notification '
          'PendingIntent on singleTask resume (Pixel soak 2026-05-05).',
    );

    // Must call setIntent(intent) — the actual fix per plugin docs for
    // singleTask apps.
    expect(
      RegExp(r'setIntent\s*\(\s*intent\s*\)').hasMatch(source),
      isTrue,
      reason:
          'onNewIntent must call setIntent(intent); without this the '
          'subsequent FlutterActivity / plugin pickup of the intent extras '
          'silently fails.',
    );

    // Must call super.onNewIntent(intent) — required by the embedding
    // contract; skipping super has historically broken plugin propagation.
    expect(
      RegExp(r'super\.onNewIntent\s*\(\s*intent\s*\)').hasMatch(source),
      isTrue,
      reason:
          'onNewIntent must call super.onNewIntent(intent) so the Flutter '
          'embedding plugin pipeline runs.',
    );
  });
}
