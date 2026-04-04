import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/recent_background_notification_gate.dart';

void main() {
  group('RecentBackgroundNotificationGate', () {
    late String filePath;
    late DateTime now;
    late RecentBackgroundNotificationGate gate;

    setUp(() async {
      filePath =
          '${Directory.systemTemp.path}/recent-background-notification-gate-${DateTime.now().microsecondsSinceEpoch}.json';
      now = DateTime.utc(2026, 4, 4, 12);
      gate = RecentBackgroundNotificationGate(
        filePath: filePath,
        ttl: const Duration(hours: 12),
        now: () => now,
      );
      await gate.clear();
    });

    tearDown(() async {
      await gate.clear();
    });

    test('marks and reads a recent key', () async {
      await gate.markShown('push-key-123');

      expect(await gate.wasRecentlyShown('push-key-123'), isTrue);
    });

    test('expires old keys after the ttl window', () async {
      await gate.markShown('push-key-123');
      now = now.add(const Duration(hours: 12, seconds: 1));

      expect(await gate.wasRecentlyShown('push-key-123'), isFalse);
    });

    test('treats blank keys as absent', () async {
      await gate.markShown('   ');

      expect(await gate.wasRecentlyShown('   '), isFalse);
      expect(File(filePath).existsSync(), isFalse);
    });
  });
}
