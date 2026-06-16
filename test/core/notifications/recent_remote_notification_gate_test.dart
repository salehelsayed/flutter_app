import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';
import 'package:flutter_app/core/notifications/remote_notification_identity.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

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

    test(
      'keeps exact-message announcements beyond the short payload ttl',
      () async {
        await gate.markAnnouncement(payload: 'peer-123', messageId: 'msg-1');
        now = now.add(const Duration(seconds: 31));

        expect(
          await gate.consumeIfRecentAnnouncement(
            payload: 'peer-123',
            messageId: 'msg-1',
          ),
          isTrue,
        );
      },
    );

    test(
      'does not suppress a different message id in the same conversation',
      () async {
        await gate.markAnnouncement(payload: 'peer-123', messageId: 'msg-1');

        expect(
          await gate.consumeIfRecentAnnouncement(
            payload: 'peer-123',
            messageId: 'msg-2',
          ),
          isFalse,
        );
      },
    );

    test(
      'marks remote group notification opens as exact recent announcements',
      () async {
        final marked = await markRemoteNotificationOpenAsRecentAnnouncement(
          gate: gate,
          data: const <String, dynamic>{
            'type': 'group_message',
            'groupId': 'group-123',
            'message_id': 'msg-123',
          },
        );

        expect(marked, isTrue);
        expect(
          await gate.consumeIfRecentAnnouncement(
            payload: 'group:group-123|message:msg-123',
            messageId: 'msg-123',
          ),
          isTrue,
        );
        expect(
          await gate.consumeIfRecentAnnouncement(
            payload: 'group:group-123|message:msg-123',
            messageId: 'msg-123',
          ),
          isFalse,
        );
      },
    );
  });

  // 04-P0 / QW-3 + SI-4 — durable app-support storage + decode-error
  // observability. A wiped/corrupt file must be distinguishable from "no
  // entries" (telemetry), and prod must not depend on OS-evictable systemTemp.
  group('RecentRemoteNotificationGate durability + telemetry (04-P0)', () {
    test(
      'a decode error on a corrupt file fires onLoadError once; a clean miss does not',
      () async {
        final path =
            '${Directory.systemTemp.path}/remote-gate-decode-${DateTime.now().microsecondsSinceEpoch}.json';
        var errors = 0;
        final gate = RecentRemoteNotificationGate(
          filePath: path,
          onLoadError: (_, _) => errors++,
        );
        addTearDown(() async => gate.clear());

        // Clean miss (absent file) must NOT fire telemetry.
        expect(await gate.consumeIfRecentPayload('peer-x'), isFalse);
        expect(errors, 0);

        // Corrupt (non-JSON) file: decode failure must fire telemetry once.
        File(path).writeAsStringSync('this is not json {');
        expect(await gate.consumeIfRecentPayload('peer-x'), isFalse);
        expect(errors, 1);
      },
    );

    test(
      'a non-object JSON payload fires onLoadError (still a decode failure)',
      () async {
        final path =
            '${Directory.systemTemp.path}/remote-gate-nonmap-${DateTime.now().microsecondsSinceEpoch}.json';
        var errors = 0;
        final gate = RecentRemoteNotificationGate(
          filePath: path,
          onLoadError: (_, _) => errors++,
        );
        addTearDown(() async => gate.clear());

        File(path).writeAsStringSync('[]'); // valid JSON, but not a Map
        expect(await gate.consumeIfRecentPayload('peer-x'), isFalse);
        expect(errors, 1);
      },
    );

    test(
      'resolves a durable path under the injected support dir; explicit filePath wins',
      () async {
        final supportDir =
            await Directory.systemTemp.createTemp('remote-gate-support-');
        addTearDown(() => supportDir.deleteSync(recursive: true));

        var providerCalls = 0;
        final gate = RecentRemoteNotificationGate(
          supportDirectoryProvider: () async {
            providerCalls++;
            return supportDir;
          },
        );
        addTearDown(() async => gate.clear());

        await gate.markPayload('peer-durable');
        final resolved = await gate.resolveFilePath();
        expect(resolved, startsWith(supportDir.path));
        // The actual IO write must land at the resolved (support-dir) path —
        // bites a mutation that routes IO through the sync `filePath` getter
        // (systemTemp) instead of the resolved durable path.
        expect(File(resolved).existsSync(), isTrue);
        expect(
          resolved,
          isNot(
            '${Directory.systemTemp.path}/mknoon_recent_remote_notifications.json',
          ),
        );
        // Resolved once and cached across multiple IO calls.
        await gate.consumeIfRecentPayload('peer-durable');
        expect(providerCalls, 1);

        // An explicit filePath short-circuits the provider entirely (sync path).
        final explicitPath =
            '${Directory.systemTemp.path}/remote-gate-explicit-${DateTime.now().microsecondsSinceEpoch}.json';
        var explicitProviderCalls = 0;
        final explicitGate = RecentRemoteNotificationGate(
          filePath: explicitPath,
          supportDirectoryProvider: () async {
            explicitProviderCalls++;
            return supportDir;
          },
        );
        expect(await explicitGate.resolveFilePath(), explicitPath);
        expect(explicitProviderCalls, 0);
      },
    );

    test(
      'falls back to systemTemp and emits DIR_FALLBACK when the provider throws',
      () async {
        final events = <Map<String, dynamic>>[];
        debugSetFlowEventSink(events.add);
        addTearDown(() => debugSetFlowEventSink(null));

        final gate = RecentRemoteNotificationGate(
          supportDirectoryProvider: () async =>
              throw Exception('support dir unavailable'),
        );
        addTearDown(() async => gate.clear());

        final resolved = await gate.resolveFilePath();
        expect(resolved, startsWith(Directory.systemTemp.path));
        expect(
          events.any(
            (e) => e['event'] == 'RECENT_REMOTE_NOTIFICATION_GATE_DIR_FALLBACK',
          ),
          isTrue,
        );
        // Degrades gracefully — no crash on a normal read.
        await gate.clear();
        expect(await gate.consumeIfRecentPayload('peer-x'), isFalse);
      },
    );
  });
}
