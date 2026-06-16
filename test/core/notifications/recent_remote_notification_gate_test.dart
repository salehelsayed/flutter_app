import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
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

  // 04-P0 / SI-5 — cross-process dedupe: the out-of-process iOS NSE drops a
  // per-message sidecar marker (filename = sha256 of the gate message key) into
  // the shared app-group container; the Dart gate consumes it so a banner the
  // NSE already showed suppresses the duplicate Dart banner without the Dart
  // isolate ever seeing the push via its own JSON map.
  group('RecentRemoteNotificationGate SI-5 app-group sidecar', () {
    late Directory container;
    late Directory sidecarDir;
    late DateTime now;
    late RecentRemoteNotificationGate gate;

    String markerName(String key) =>
        sha256.convert(utf8.encode(key)).toString();

    Future<void> writeMarker(String key, DateTime mtime) async {
      final f = File('${sidecarDir.path}/${markerName(key)}');
      await f.writeAsString('');
      await f.setLastModified(mtime);
    }

    setUp(() async {
      container = await Directory.systemTemp.createTemp('si5-appgroup-');
      sidecarDir = Directory('${container.path}/RecentRemoteShown');
      await sidecarDir.create(recursive: true);
      now = DateTime.utc(2026, 4, 3, 12);
      gate = RecentRemoteNotificationGate(
        filePath: '${container.path}/mknoon_recent_remote_notifications.json',
        now: () => now,
        appGroupSidecarDirProvider: () async => container,
      );
      await gate.clear();
    });

    tearDown(() async {
      try {
        container.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('consumes an NSE-written 1:1 sidecar marker exactly once', () async {
      await writeMarker('message:peer-123|msg-7', now);

      expect(
        await gate.consumeIfRecentAnnouncement(
          payload: 'peer-123',
          messageId: 'msg-7',
        ),
        isTrue,
      );
      // Consumed: the marker is gone and a second call returns false.
      expect(
        File(
          '${sidecarDir.path}/${markerName('message:peer-123|msg-7')}',
        ).existsSync(),
        isFalse,
      );
      expect(
        await gate.consumeIfRecentAnnouncement(
          payload: 'peer-123',
          messageId: 'msg-7',
        ),
        isFalse,
      );
    });

    test('consumes a GROUP sidecar marker (double message: key shape)', () async {
      // Group payload = 'group:<gid>|message:<id>', so the gate key is
      // 'message:group:<gid>|message:<id>|<id>' — the NSE must reproduce this.
      await writeMarker('message:group:g-1|message:m-9|m-9', now);

      expect(
        await gate.consumeIfRecentAnnouncement(
          payload: 'group:g-1|message:m-9',
          messageId: 'm-9',
        ),
        isTrue,
      );
    });

    test('honors the 12h message TTL on sidecar markers', () async {
      await writeMarker(
        'message:peer-x|m-1',
        now.subtract(const Duration(hours: 13)),
      );
      expect(
        await gate.consumeIfRecentAnnouncement(
          payload: 'peer-x',
          messageId: 'm-1',
        ),
        isFalse,
      );

      await writeMarker(
        'message:peer-y|m-2',
        now.subtract(const Duration(hours: 11)),
      );
      expect(
        await gate.consumeIfRecentAnnouncement(
          payload: 'peer-y',
          messageId: 'm-2',
        ),
        isTrue,
      );
    });

    test('ignores sidecar markers when no provider is configured', () async {
      final noProvider = RecentRemoteNotificationGate(
        filePath: '${container.path}/np.json',
        now: () => now,
      );
      await writeMarker('message:peer-z|m-3', now);

      expect(
        await noProvider.consumeIfRecentAnnouncement(
          payload: 'peer-z',
          messageId: 'm-3',
        ),
        isFalse,
      );
    });

    test(
      're-resolves the sidecar dir after a transient first-launch failure '
      '(does not negative-cache null)',
      () async {
        // Reproduces the first-ever-launch race: main() persists the app-group
        // path via an UNAWAITED call, so an early push can hit the gate before
        // the provider can resolve. The provider throws on the first consume,
        // then succeeds. A naive `??=` would pin the transient null and disable
        // SI-5 for the whole session; the gate must retry and still honor the
        // marker once the path becomes available.
        var pathReady = false;
        final racingGate = RecentRemoteNotificationGate(
          filePath: '${container.path}/race.json',
          now: () => now,
          appGroupSidecarDirProvider: () async {
            if (!pathReady) {
              throw StateError('app-group container path not persisted yet');
            }
            return container;
          },
        );
        await racingGate.clear();
        await writeMarker('message:peer-race|m-r', now);

        // First consume loses the race: provider throws, marker untouched.
        expect(
          await racingGate.consumeIfRecentAnnouncement(
            payload: 'peer-race',
            messageId: 'm-r',
          ),
          isFalse,
        );
        expect(
          File(
            '${sidecarDir.path}/${markerName('message:peer-race|m-r')}',
          ).existsSync(),
          isTrue,
        );

        // Path becomes available — a later consume must now read the marker.
        pathReady = true;
        expect(
          await racingGate.consumeIfRecentAnnouncement(
            payload: 'peer-race',
            messageId: 'm-r',
          ),
          isTrue,
        );
      },
    );
  });
}
