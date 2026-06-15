// Phase G2 (plan 120) — FOUNDATION test bootstrap: per-test notification-gate
// isolation.
//
// The two notification gates are module globals defaulting to FIXED on-disk
// file paths (recent_remote_notification_gate.dart:33-35 /
// recent_background_notification_gate.dart:32-34). `debugReset*` re-news with
// the SAME fixed path and never deletes the file, so it is NOT isolation:
// tests that don't inject a unique-temp gate race on the shared file and the
// notification/group suites only pass deterministically at `-j 1`.
//
// Flutter resolves `flutter_test_config.dart` by walking UP from each test
// file to the nearest one, so this single root config is auto-applied to every
// nested test dir (test/features/..., test/integration/..., test/core/...).
// That recursion assumption is validated by the Phase-G2a probe in
// test/core/notifications/notification_gate_isolation_test.dart.
//
// In setUp we swap BOTH globals to unique-temp-file gates (monotonic counter +
// clock, so two tests in the same microsecond still get distinct files).
// Isolation is per-test (setUp), not per-call, so within a single test the gate
// persists and the 118 within-test dedup behavior is preserved.
//
// IMPORTANT — cleanup is SYNCHRONOUS only. An earlier version registered
// addTearDown(gate.clear) (an awaited async File.delete); awaiting async dart:io
// inside the teardown of a timing-sensitive *widget* test (uploads, wakelocks,
// animations with pending timers) intermittently destabilized those tests —
// e.g. group_conversation_wired_test.dart flaked WITH the config and passed
// without it. Per the project rule "testWidgets: sync I/O only", we delete the
// temp files with deleteSync. Unique paths already provide the isolation; the
// delete is only hygiene to avoid temp accumulation.
//
// The per-test gate blocks already present in some test files
// (background_message_handler_test.dart, the dedupe integration tests,
// show_notification_use_case_test.dart) remain as belt-and-suspenders; they
// also exercise the `remoteNotificationGate:` injection seam.

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/recent_background_notification_gate.dart';
import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  var counter = 0;
  setUp(() {
    final stamp = '${DateTime.now().microsecondsSinceEpoch}_${counter++}';
    final remotePath =
        '${Directory.systemTemp.path}/mknoon_remote_gate_$stamp.json';
    final bgPath = '${Directory.systemTemp.path}/mknoon_bg_gate_$stamp.json';
    debugSetRecentRemoteNotificationGate(
      RecentRemoteNotificationGate(filePath: remotePath),
    );
    debugSetRecentBackgroundNotificationGate(
      RecentBackgroundNotificationGate(filePath: bgPath),
    );
    addTearDown(() {
      // Synchronous only — never await async dart:io in a widget-test teardown.
      try {
        final f = File(remotePath);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
      try {
        final f = File(bgPath);
        if (f.existsSync()) f.deleteSync();
      } catch (_) {}
      debugResetRecentRemoteNotificationGate();
      debugResetRecentBackgroundNotificationGate();
    });
  });
  await testMain();
}
