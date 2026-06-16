import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/recent_background_notification_gate.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

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

  // 04-P0 / QW-3 + SI-4 — durable app-support storage + decode-error
  // observability (mirrors the remote gate).
  group('RecentBackgroundNotificationGate durability + telemetry (04-P0)', () {
    test(
      'a decode error on a corrupt file fires onLoadError once; a clean miss does not',
      () async {
        final path =
            '${Directory.systemTemp.path}/bg-gate-decode-${DateTime.now().microsecondsSinceEpoch}.json';
        var errors = 0;
        final gate = RecentBackgroundNotificationGate(
          filePath: path,
          onLoadError: (_, _) => errors++,
        );
        addTearDown(() async => gate.clear());

        expect(await gate.wasRecentlyShown('push-key'), isFalse);
        expect(errors, 0);

        File(path).writeAsStringSync('this is not json {');
        expect(await gate.wasRecentlyShown('push-key'), isFalse);
        expect(errors, 1);
      },
    );

    test(
      'a non-object JSON payload fires onLoadError (still a decode failure)',
      () async {
        final path =
            '${Directory.systemTemp.path}/bg-gate-nonmap-${DateTime.now().microsecondsSinceEpoch}.json';
        var errors = 0;
        final gate = RecentBackgroundNotificationGate(
          filePath: path,
          onLoadError: (_, _) => errors++,
        );
        addTearDown(() async => gate.clear());

        File(path).writeAsStringSync('"a string is not a map"');
        expect(await gate.wasRecentlyShown('push-key'), isFalse);
        expect(errors, 1);
      },
    );

    test(
      'resolves a durable path under the injected support dir; explicit filePath wins',
      () async {
        final supportDir =
            await Directory.systemTemp.createTemp('bg-gate-support-');
        addTearDown(() => supportDir.deleteSync(recursive: true));

        var providerCalls = 0;
        final gate = RecentBackgroundNotificationGate(
          supportDirectoryProvider: () async {
            providerCalls++;
            return supportDir;
          },
        );
        addTearDown(() async => gate.clear());

        await gate.markShown('push-durable');
        final resolved = await gate.resolveFilePath();
        expect(resolved, startsWith(supportDir.path));
        // The actual IO write must land at the resolved (support-dir) path —
        // bites a mutation that routes IO through the sync `filePath` getter
        // (systemTemp) instead of the resolved durable path.
        expect(File(resolved).existsSync(), isTrue);
        expect(
          resolved,
          isNot(
            '${Directory.systemTemp.path}/mknoon_recent_background_notifications.json',
          ),
        );
        await gate.wasRecentlyShown('push-durable');
        expect(providerCalls, 1);

        final explicitPath =
            '${Directory.systemTemp.path}/bg-gate-explicit-${DateTime.now().microsecondsSinceEpoch}.json';
        var explicitProviderCalls = 0;
        final explicitGate = RecentBackgroundNotificationGate(
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

        final gate = RecentBackgroundNotificationGate(
          supportDirectoryProvider: () async =>
              throw Exception('support dir unavailable'),
        );
        addTearDown(() async => gate.clear());

        final resolved = await gate.resolveFilePath();
        expect(resolved, startsWith(Directory.systemTemp.path));
        expect(
          events.any(
            (e) =>
                e['event'] ==
                'RECENT_BACKGROUND_NOTIFICATION_GATE_DIR_FALLBACK',
          ),
          isTrue,
        );
        await gate.clear();
        expect(await gate.wasRecentlyShown('push-key'), isFalse);
      },
    );
  });
}
