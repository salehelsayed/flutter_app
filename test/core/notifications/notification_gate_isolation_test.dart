// Phase G2 (plan 120) — gate-leak repro + per-test isolation probe.
//
// Two sequential tests, both using the DEFAULT module-global
// `recentRemoteNotificationGate` (no injection). Without the per-test
// isolation installed by `test/flutter_test_config.dart`, test A's on-disk
// write leaks into test B (the global re-news with the SAME fixed default
// path and never deletes the file), so B's consume returns `true`.
//
// This deterministically encodes the `-j 1`-passes / parallel-fails hazard:
//   - RED before Phase-G2 GREEN (`flutter_test_config.dart` absent).
//   - GREEN once the root config swaps the global to a unique-temp gate per
//     test in setUp and tears it down.
//
// The Phase-G2a probe (third test) validates the flagged recursion
// assumption: the ACTIVE gate `filePath` must carry the per-test stamp
// (`mknoon_remote_gate_`), NOT the fixed
// `mknoon_recent_remote_notifications.json` — confirming the single root
// `test/flutter_test_config.dart` is auto-applied here.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';

void main() {
  // Test A and B intentionally share the DEFAULT global with no injection.
  test('gate-leak repro A: marks an announcement on the default global', () async {
    await recentRemoteNotificationGate.markAnnouncement(
      payload: 'p',
      messageId: 'm',
    );
    // Sanity: within this test the mark is visible (proves the write landed).
    // We do NOT consume here — the leak is asserted by test B.
  });

  test('gate-leak repro B: clean state — A must not leak into B', () async {
    // With per-test isolation (flutter_test_config.dart), B runs on a fresh
    // unique-temp gate, so A's write is invisible → consume returns false.
    // Without isolation, A's write to the shared fixed default path leaks in
    // → consume returns true → this assertion FAILS (the reproduced flake).
    final leaked = await recentRemoteNotificationGate.consumeIfRecentAnnouncement(
      payload: 'p',
      messageId: 'm',
    );
    expect(
      leaked,
      isFalse,
      reason:
          'Test A leaked into test B via the shared default gate file. '
          'Phase-G2 per-test isolation (test/flutter_test_config.dart) is '
          'not active.',
    );
  });

  // Phase-G2a — recursion-assumption probe.
  test('Phase-G2a: active gate uses the per-test stamped temp path', () {
    expect(
      recentRemoteNotificationGate.filePath,
      contains('mknoon_remote_gate_'),
      reason:
          'The single root test/flutter_test_config.dart was not auto-applied '
          'to this nested test directory: the active gate still uses the fixed '
          'default path instead of the per-test stamp.',
    );
    expect(
      recentRemoteNotificationGate.filePath,
      isNot(contains('mknoon_recent_remote_notifications.json')),
      reason:
          'The active gate is still the fixed-default-path global; per-test '
          'isolation did not swap it.',
    );
  });
}
