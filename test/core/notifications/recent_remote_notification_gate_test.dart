import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';

void main() {
  group('RecentRemoteNotificationGate', () {
    late String filePath;
    late DateTime now;
    late RecentRemoteNotificationGate gate;

    setUp(() async {
      filePath =
          '${Directory.systemTemp.path}/recent-remote-notification-gate-${DateTime.now().microsecondsSinceEpoch}.json';
      now = DateTime.utc(2026, 4, 3, 12);
      gate = RecentRemoteNotificationGate(
        filePath: filePath,
        ttl: const Duration(seconds: 30),
        now: () => now,
      );
      await gate.clear();
    });

    tearDown(() async {
      await gate.clear();
    });

    test('marks and consumes a recent payload once', () async {
      await gate.markPayload('peer-123');

      expect(await gate.consumeIfRecentPayload('peer-123'), isTrue);
      expect(await gate.consumeIfRecentPayload('peer-123'), isFalse);
    });

    test('ignores expired payloads', () async {
      await gate.markPayload('peer-123');
      now = now.add(const Duration(seconds: 31));

      expect(await gate.consumeIfRecentPayload('peer-123'), isFalse);
    });

    test('treats blank payloads as absent', () async {
      await gate.markPayload('   ');

      expect(await gate.consumeIfRecentPayload('   '), isFalse);
      expect(File(filePath).existsSync(), isFalse);
    });
  });
}
