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

    test('probes an exact announcement without consuming it', () async {
      await gate.markAnnouncement(payload: 'peer-123', messageId: 'msg-1');

      expect(
        await gate.hasRecentAnnouncement(
          payload: 'peer-123',
          messageId: 'msg-1',
        ),
        isTrue,
      );
      expect(
        await gate.hasRecentAnnouncement(
          payload: 'peer-123',
          messageId: 'msg-1',
        ),
        isTrue,
        reason: 'a durable adopter must retain proof until SQL handoff',
      );
      expect(
        await gate.consumeIfRecentAnnouncement(
          payload: 'peer-123',
          messageId: 'msg-1',
        ),
        isTrue,
      );
      expect(
        await gate.hasRecentAnnouncement(
          payload: 'peer-123',
          messageId: 'msg-1',
        ),
        isFalse,
      );
    });

    test(
      'exact APIs reject payload-only proof and leave legacy proof intact',
      () async {
        await gate.markAnnouncement(payload: 'peer-123');

        expect(
          await gate.hasRecentExactAnnouncement(
            payload: 'peer-123',
            messageId: 'msg-b',
          ),
          isFalse,
          reason: 'conversation-level proof cannot authorize message B',
        );
        expect(
          await gate.consumeIfRecentExactAnnouncement(
            payload: 'peer-123',
            messageId: 'msg-b',
          ),
          isFalse,
        );
        expect(
          await gate.consumeIfRecentPayload('peer-123'),
          isTrue,
          reason: 'an exact miss must not delete the legacy payload marker',
        );
      },
    );

    test(
      'exact APIs never substitute another message in the same chat',
      () async {
        await gate.markAnnouncement(payload: 'peer-123', messageId: 'msg-a');

        expect(
          await gate.hasRecentExactAnnouncement(
            payload: 'peer-123',
            messageId: 'msg-b',
          ),
          isFalse,
        );
        expect(
          await gate.consumeIfRecentExactAnnouncement(
            payload: 'peer-123',
            messageId: 'msg-b',
          ),
          isFalse,
        );
        expect(
          await gate.hasRecentExactAnnouncement(
            payload: 'peer-123',
            messageId: 'msg-a',
          ),
          isTrue,
          reason: 'message B must not consume message A proof',
        );
        expect(
          await gate.consumeIfRecentExactAnnouncement(
            payload: 'peer-123',
            messageId: 'msg-a',
          ),
          isTrue,
        );
        expect(
          await gate.consumeIfRecentExactAnnouncement(
            payload: 'peer-123',
            messageId: 'msg-a',
          ),
          isFalse,
          reason: 'exact consumption remains one-shot',
        );
      },
    );

    test('exact APIs reject blank payload or message identities', () async {
      await gate.markAnnouncement(payload: 'peer-123', messageId: 'msg-a');

      expect(
        await gate.hasRecentExactAnnouncement(payload: ' ', messageId: 'msg-a'),
        isFalse,
      );
      expect(
        await gate.consumeIfRecentExactAnnouncement(
          payload: 'peer-123',
          messageId: ' ',
        ),
        isFalse,
      );
      expect(
        await gate.hasRecentExactAnnouncement(
          payload: 'peer-123',
          messageId: 'msg-a',
        ),
        isTrue,
      );
    });

    test(
      'exact consumption leaves a coexisting legacy payload marker',
      () async {
        await gate.markAnnouncement(payload: 'peer-123');
        await gate.markAnnouncement(payload: 'peer-123', messageId: 'msg-a');

        expect(
          await gate.consumeIfRecentExactAnnouncement(
            payload: 'peer-123',
            messageId: 'msg-a',
          ),
          isTrue,
        );
        expect(
          await gate.consumeIfRecentPayload('peer-123'),
          isTrue,
          reason: 'exact cleanup must never remove payload-only state',
        );
      },
    );

    test(
      'promotes only an explicit exact alias proof without consuming it',
      () async {
        const sourcePayload = 'group:g-1|message:alias-a';
        const sourceMessageId = 'alias-a';
        const targetPayload = 'group:g-1|message:canonical-c';
        const targetMessageId = 'canonical-c';
        await gate.markAnnouncement(
          payload: sourcePayload,
          messageId: sourceMessageId,
        );

        expect(
          await gate.promoteExactAnnouncementAlias(
            sourcePayload: sourcePayload,
            sourceMessageId: sourceMessageId,
            targetPayload: targetPayload,
            targetMessageId: targetMessageId,
          ),
          isTrue,
        );
        expect(
          await gate.hasRecentAnnouncement(
            payload: targetPayload,
            messageId: targetMessageId,
          ),
          isTrue,
        );
        expect(
          await gate.hasRecentAnnouncement(
            payload: sourcePayload,
            messageId: sourceMessageId,
          ),
          isTrue,
          reason: 'promotion must preserve retry proof at the source identity',
        );
        expect(
          await gate.promoteExactAnnouncementAlias(
            sourcePayload: sourcePayload,
            sourceMessageId: sourceMessageId,
            targetPayload: targetPayload,
            targetMessageId: targetMessageId,
          ),
          isTrue,
          reason: 'an exact promotion must be idempotent',
        );

        expect(
          await gate.hasRecentAnnouncement(
            payload: 'group:g-1|message:newer-b',
            messageId: 'newer-b',
          ),
          isFalse,
          reason: 'another message in the same group must remain eligible',
        );
        expect(
          await gate.hasRecentAnnouncement(
            payload: 'group:g-2|message:canonical-c',
            messageId: targetMessageId,
          ),
          isFalse,
          reason: 'the same message id in another group must remain eligible',
        );

        expect(
          await gate.promoteExactAnnouncementAlias(
            sourcePayload: 'group:g-1|message:newer-b',
            sourceMessageId: 'newer-b',
            targetPayload: 'group:g-1|message:canonical-d',
            targetMessageId: 'canonical-d',
          ),
          isFalse,
          reason: 'promotion must never discover proof by scanning a group',
        );
        expect(
          await gate.hasRecentAnnouncement(
            payload: 'group:g-1|message:canonical-d',
            messageId: 'canonical-d',
          ),
          isFalse,
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
        final supportDir = await Directory.systemTemp.createTemp(
          'remote-gate-support-',
        );
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

    test(
      'consumes a GROUP sidecar marker (double message: key shape)',
      () async {
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
      },
    );

    test('probes a GROUP sidecar without deleting NSE proof', () async {
      const payload = 'group:g-1|message:m-9';
      const messageId = 'm-9';
      final marker = File(
        '${sidecarDir.path}/${markerName('message:$payload|$messageId')}',
      );
      await writeMarker('message:$payload|$messageId', now);

      expect(
        await gate.hasRecentAnnouncement(
          payload: payload,
          messageId: messageId,
        ),
        isTrue,
      );
      expect(marker.existsSync(), isTrue);
      expect(
        await gate.consumeIfRecentAnnouncement(
          payload: payload,
          messageId: messageId,
        ),
        isTrue,
      );
      expect(marker.existsSync(), isFalse);
    });

    test(
      'exact APIs probe and consume only the matching NSE sidecar',
      () async {
        const payload = 'peer-123';
        const messageA = 'msg-a';
        const messageB = 'msg-b';
        final markerA = File(
          '${sidecarDir.path}/${markerName('message:$payload|$messageA')}',
        );
        await writeMarker('message:$payload|$messageA', now);

        expect(
          await gate.hasRecentExactAnnouncement(
            payload: payload,
            messageId: messageB,
          ),
          isFalse,
        );
        expect(
          await gate.consumeIfRecentExactAnnouncement(
            payload: payload,
            messageId: messageB,
          ),
          isFalse,
        );
        expect(markerA.existsSync(), isTrue);
        expect(
          await gate.hasRecentExactAnnouncement(
            payload: payload,
            messageId: messageA,
          ),
          isTrue,
        );
        expect(
          markerA.existsSync(),
          isTrue,
          reason: 'probe is non-destructive',
        );
        expect(
          await gate.consumeIfRecentExactAnnouncement(
            payload: payload,
            messageId: messageA,
          ),
          isTrue,
        );
        expect(markerA.existsSync(), isFalse);
        expect(
          await gate.consumeIfRecentExactAnnouncement(
            payload: payload,
            messageId: messageA,
          ),
          isFalse,
        );
      },
    );

    test(
      'exact consumption clears matching Dart and NSE proof together',
      () async {
        const payload = 'peer-123';
        const messageId = 'msg-a';
        final marker = File(
          '${sidecarDir.path}/${markerName('message:$payload|$messageId')}',
        );
        await gate.markAnnouncement(payload: payload, messageId: messageId);
        await writeMarker('message:$payload|$messageId', now);

        expect(
          await gate.consumeIfRecentExactAnnouncement(
            payload: payload,
            messageId: messageId,
          ),
          isTrue,
        );
        expect(marker.existsSync(), isFalse);
        expect(
          await gate.hasRecentExactAnnouncement(
            payload: payload,
            messageId: messageId,
          ),
          isFalse,
        );
      },
    );

    test(
      'exact sidecar alias promotion keeps source proof retryable on write failure',
      () async {
        const sourcePayload = 'group:g-1|message:alias-a';
        const sourceMessageId = 'alias-a';
        const targetPayload = 'group:g-1|message:canonical-c';
        const targetMessageId = 'canonical-c';
        final sourceMarker = File(
          '${sidecarDir.path}/${markerName('message:$sourcePayload|$sourceMessageId')}',
        );
        await writeMarker('message:$sourcePayload|$sourceMessageId', now);
        final blockedGatePath = '${container.path}/blocked-gate-path';
        await Directory(blockedGatePath).create();
        final blockedGate = RecentRemoteNotificationGate(
          filePath: blockedGatePath,
          now: () => now,
          appGroupSidecarDirProvider: () async => container,
        );

        await expectLater(
          blockedGate.promoteExactAnnouncementAlias(
            sourcePayload: sourcePayload,
            sourceMessageId: sourceMessageId,
            targetPayload: targetPayload,
            targetMessageId: targetMessageId,
          ),
          throwsA(isA<FileSystemException>()),
        );
        expect(
          sourceMarker.existsSync(),
          isTrue,
          reason: 'a failed target write must not consume exact source proof',
        );

        await Directory(blockedGatePath).delete();
        expect(
          await blockedGate.promoteExactAnnouncementAlias(
            sourcePayload: sourcePayload,
            sourceMessageId: sourceMessageId,
            targetPayload: targetPayload,
            targetMessageId: targetMessageId,
          ),
          isTrue,
        );
        expect(
          await blockedGate.hasRecentAnnouncement(
            payload: targetPayload,
            messageId: targetMessageId,
          ),
          isTrue,
        );
        expect(sourceMarker.existsSync(), isTrue);
      },
    );

    test('discardSidecarMarker removes the marker without a suppression hit '
        'and leaves Dart-map entries intact', () async {
      await writeMarker('message:group:g-2|message:m-5|m-5', now);
      await gate.markAnnouncement(
        payload: 'group:g-other|message:m-1',
        messageId: 'm-1',
      );

      await gate.discardSidecarMarker(
        payload: 'group:g-2|message:m-5',
        messageId: 'm-5',
      );

      expect(
        File(
          '${sidecarDir.path}/${markerName('message:group:g-2|message:m-5|m-5')}',
        ).existsSync(),
        isFalse,
      );
      // The never-presented foreground push no longer suppresses the
      // local banner.
      expect(
        await gate.consumeIfRecentAnnouncement(
          payload: 'group:g-2|message:m-5',
          messageId: 'm-5',
        ),
        isFalse,
      );
      // Dart-map dedupe (live-first / recovery paths) is unaffected.
      expect(
        await gate.consumeIfRecentAnnouncement(
          payload: 'group:g-other|message:m-1',
          messageId: 'm-1',
        ),
        isTrue,
      );
    });

    test(
      'discardSidecarMarker is a no-op for a missing marker or null messageId',
      () async {
        await gate.discardSidecarMarker(
          payload: 'peer-none',
          messageId: 'm-none',
        );

        await writeMarker('message:peer-keep|m-k', now);
        await gate.discardSidecarMarker(payload: 'peer-keep', messageId: null);
        expect(
          await gate.consumeIfRecentAnnouncement(
            payload: 'peer-keep',
            messageId: 'm-k',
          ),
          isTrue,
        );
      },
    );

    test(
      'pending exact proof survives compatibility expiry and sibling reads',
      () async {
        const payload = 'peer-delayed';
        const eventId = 'reaction-delayed';
        final marker = File(
          '${sidecarDir.path}/${markerName('message:$payload|$eventId')}',
        );
        await writeMarker(
          'message:$payload|$eventId',
          now.subtract(const Duration(hours: 13)),
        );
        expect(
          await gate.consumeIfRecentAnnouncement(
            payload: 'unrelated-peer',
            messageId: 'unrelated-event',
          ),
          isFalse,
        );
        expect(
          await gate.hasRecentExactAnnouncement(
            payload: payload,
            messageId: eventId,
          ),
          isFalse,
        );
        expect(
          await gate.consumeIfRecentExactAnnouncement(
            payload: payload,
            messageId: eventId,
          ),
          isFalse,
        );
        expect(marker.existsSync(), isTrue);
        expect(
          await gate.hasExactPendingAnnouncement(
            payload: payload,
            messageId: eventId,
          ),
          isTrue,
        );
        expect(
          await gate.hasExactPendingAnnouncement(
            payload: payload,
            messageId: 'other-event',
          ),
          isFalse,
        );
        expect(
          await gate.consumeExactPendingAnnouncement(
            payload: 'other-peer',
            messageId: eventId,
          ),
          isFalse,
        );
        expect(marker.existsSync(), isTrue);
        expect(
          await gate.consumeExactPendingAnnouncement(
            payload: payload,
            messageId: eventId,
          ),
          isTrue,
        );
        expect(marker.existsSync(), isFalse);
        expect(
          await gate.hasExactPendingAnnouncement(
            payload: payload,
            messageId: eventId,
          ),
          isFalse,
        );
      },
    );

    test(
      'pending exact APIs never consume a broad conversation hint',
      () async {
        await gate.markAnnouncement(payload: 'peer-broad');
        expect(
          await gate.hasExactPendingAnnouncement(
            payload: 'peer-broad',
            messageId: 'event',
          ),
          isFalse,
        );
        expect(
          await gate.consumeExactPendingAnnouncement(
            payload: 'peer-broad',
            messageId: 'event',
          ),
          isFalse,
        );
        expect(await gate.consumeIfRecentPayload('peer-broad'), isTrue);
        await gate.markAnnouncement(payload: 'peer-broad');
        now = now.add(const Duration(seconds: 31));
        expect(await gate.consumeIfRecentPayload('peer-broad'), isFalse);
      },
    );

    test('aged exact alias remains durable without renewing recent TTL', () async {
      const sourcePayload = 'group:delayed|message:provider-id';
      const targetPayload = 'group:delayed|message:canonical-id';
      final source = File(
        '${sidecarDir.path}/${markerName('message:$sourcePayload|provider-id')}',
      );
      final target = File(
        '${sidecarDir.path}/${markerName('message:$targetPayload|canonical-id')}',
      );
      final originalTime = now.subtract(const Duration(hours: 13));
      await writeMarker('message:$sourcePayload|provider-id', originalTime);
      // A failed target write keeps the source available to the pending owner.
      await Directory(target.path).create();
      Future<bool> promote() => gate.promoteExactAnnouncementAlias(
        sourcePayload: sourcePayload,
        sourceMessageId: 'provider-id',
        targetPayload: targetPayload,
        targetMessageId: 'canonical-id',
      );
      await expectLater(promote(), throwsA(isA<FileSystemException>()));
      expect(source.existsSync(), isTrue);
      await Directory(target.path).delete();
      expect(await promote(), isTrue);
      expect(target.lastModifiedSync(), originalTime.toLocal());
      expect(
        await gate.hasRecentExactAnnouncement(
          payload: targetPayload,
          messageId: 'canonical-id',
        ),
        isFalse,
      );
      now = now.add(const Duration(days: 2));
      expect(
        await gate.hasExactPendingAnnouncement(
          payload: targetPayload,
          messageId: 'canonical-id',
        ),
        isTrue,
      );
      expect(
        await gate.consumeExactPendingAnnouncement(
          payload: targetPayload,
          messageId: 'canonical-id',
        ),
        isTrue,
      );
      expect(target.existsSync(), isFalse);
      expect(source.existsSync(), isFalse);
    });

    test(
      'canonical retirement cleans multiple alias proofs after gate restart',
      () async {
        const targetPayload = 'group:multi|message:canonical';
        const sources = ['alias-a', 'alias-b'];
        for (final source in sources) {
          await writeMarker('message:group:multi|message:$source|$source', now);
        }
        await writeMarker(
          'message:group:other|message:unrelated|unrelated',
          now,
        );
        await Future.wait(
          sources.map(
            (source) =>
                RecentRemoteNotificationGate(
                  filePath: gate.filePath,
                  now: () => now,
                  appGroupSidecarDirProvider: () async => container,
                ).promoteExactAnnouncementAlias(
                  sourcePayload: 'group:multi|message:$source',
                  sourceMessageId: source,
                  targetPayload: targetPayload,
                  targetMessageId: 'canonical',
                ),
          ),
        );
        for (final source in sources) {
          expect(
            await gate.hasExactPendingAnnouncement(
              payload: 'group:multi|message:$source',
              messageId: source,
            ),
            isTrue,
          );
        }
        final restarted = RecentRemoteNotificationGate(
          filePath: gate.filePath,
          now: () => now,
          appGroupSidecarDirProvider: () async => container,
        );
        expect(
          await restarted.consumeExactPendingAnnouncement(
            payload: targetPayload,
            messageId: 'canonical',
          ),
          isTrue,
        );
        for (final source in sources) {
          expect(
            await restarted.hasExactPendingAnnouncement(
              payload: 'group:multi|message:$source',
              messageId: source,
            ),
            isFalse,
          );
        }
        expect(
          await restarted.hasExactPendingAnnouncement(
            payload: 'group:other|message:unrelated',
            messageId: 'unrelated',
          ),
          isTrue,
        );
        expect(
          await restarted.consumeExactPendingAnnouncement(
            payload: targetPayload,
            messageId: 'canonical',
          ),
          isFalse,
        );
      },
    );

    test(
      'account binding preserves migration and restart then clears old proofs',
      () async {
        const payload = 'group:shared|message:canonical';
        const source = 'group:shared|message:alias';
        await writeMarker(
          'message:$source|alias',
          now.subtract(const Duration(hours: 13)),
        );
        await gate.promoteExactAnnouncementAlias(
          sourcePayload: source,
          sourceMessageId: 'alias',
          targetPayload: payload,
          targetMessageId: 'canonical',
        );
        await gate.markPayload('peer-hint');
        await gate.rebindAccount('opaque-account-a');
        expect(
          await gate.hasExactPendingAnnouncement(
            payload: payload,
            messageId: 'canonical',
          ),
          isTrue,
          reason:
              'the initial existing-account upgrade retains pending native proof',
        );
        final restarted = RecentRemoteNotificationGate(
          filePath: gate.filePath,
          now: () => now,
          appGroupSidecarDirProvider: () async => container,
        );
        await restarted.rebindAccount('opaque-account-a');
        expect(
          await restarted.hasExactPendingAnnouncement(
            payload: payload,
            messageId: 'canonical',
          ),
          isTrue,
        );
        await restarted.rebindAccount('opaque-account-b');
        expect(
          await restarted.hasExactPendingAnnouncement(
            payload: payload,
            messageId: 'canonical',
          ),
          isFalse,
        );
        expect(
          await restarted.hasExactPendingAnnouncement(
            payload: source,
            messageId: 'alias',
          ),
          isFalse,
        );
        expect(await restarted.hasRecentPayload('peer-hint'), isFalse);
        expect(Directory('${gate.filePath}.aliases').existsSync(), isFalse);
        // A new account may receive the same group/event route independently.
        await sidecarDir.create();
        await writeMarker('message:$payload|canonical', now);
        await restarted.rebindAccount('opaque-account-b');
        expect(
          await restarted.hasExactPendingAnnouncement(
            payload: payload,
            messageId: 'canonical',
          ),
          isTrue,
        );
        await restarted.rebindAccount(null);
        expect(
          await restarted.hasExactPendingAnnouncement(
            payload: payload,
            messageId: 'canonical',
          ),
          isFalse,
        );
        // Retired startup remains a clearing boundary even if a late old NSE wrote.
        await sidecarDir.create();
        await writeMarker('message:$payload|canonical', now);
        await restarted.rebindAccount(null);
        expect(
          await restarted.hasExactPendingAnnouncement(
            payload: payload,
            messageId: 'canonical',
          ),
          isFalse,
        );
      },
    );

    test(
      'account reset fails before accepting a changed binding then retries',
      () async {
        await gate.rebindAccount('opaque-account-a');
        await writeMarker('message:peer-a|event-a', now);
        var directoryAvailable = false;
        final unavailable = RecentRemoteNotificationGate(
          filePath: gate.filePath,
          now: () => now,
          appGroupSidecarDirProvider: () async {
            if (!directoryAvailable) throw StateError('app group unavailable');
            return container;
          },
        );
        await expectLater(
          unavailable.rebindAccount('opaque-account-b'),
          throwsStateError,
        );
        expect(
          jsonDecode(
            await File('${gate.filePath}.account').readAsString(),
          )['binding'],
          'opaque-account-a',
        );
        expect(
          await gate.hasExactPendingAnnouncement(
            payload: 'peer-a',
            messageId: 'event-a',
          ),
          isTrue,
        );
        directoryAvailable = true;
        await unavailable.rebindAccount('opaque-account-b');
        expect(
          await unavailable.hasExactPendingAnnouncement(
            payload: 'peer-a',
            messageId: 'event-a',
          ),
          isFalse,
        );
        expect(
          jsonDecode(
            await File('${gate.filePath}.account').readAsString(),
          )['binding'],
          'opaque-account-b',
        );
      },
    );

    test('alias provenance survives interrupted sidecar retirement', () async {
      const source = 'group:retry|message:alias';
      const target = 'group:retry|message:canonical';
      await writeMarker('message:$source|alias', now);
      await gate.promoteExactAnnouncementAlias(
        sourcePayload: source,
        sourceMessageId: 'alias',
        targetPayload: target,
        targetMessageId: 'canonical',
      );
      final unavailable = RecentRemoteNotificationGate(
        filePath: gate.filePath,
        now: () => now,
        appGroupSidecarDirProvider: () async => throw StateError('unavailable'),
      );
      await expectLater(
        unavailable.consumeExactPendingAnnouncement(
          payload: target,
          messageId: 'canonical',
        ),
        throwsStateError,
      );
      expect(
        await gate.hasExactPendingAnnouncement(
          payload: source,
          messageId: 'alias',
        ),
        isTrue,
      );
      final restarted = RecentRemoteNotificationGate(
        filePath: gate.filePath,
        now: () => now,
        appGroupSidecarDirProvider: () async => container,
      );
      expect(
        await restarted.consumeExactPendingAnnouncement(
          payload: target,
          messageId: 'canonical',
        ),
        isTrue,
      );
      expect(
        await restarted.hasExactPendingAnnouncement(
          payload: source,
          messageId: 'alias',
        ),
        isFalse,
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

    test('re-resolves the sidecar dir after a transient first-launch failure '
        '(does not negative-cache null)', () async {
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
    });

    test('matches the shared SI-5 dedupe-key fixture (cross-process key parity '
        'with the Swift NSE)', () async {
      // G-S5-1: test_fixtures/si5_dedupe_keys.json is the SINGLE source of
      // truth for the NSE<->Dart dedupe key. The Swift XCTest
      // (NotificationPreviewResolverTests.testGateMessageKeyMatchesSharedDedupeFixture)
      // reads the SAME file and asserts RecentRemoteShownMarkerStore
      // .gateMessageKey(push) == expectedKey. Here we assert the Dart side
      // produces the same expectedKey, so any drift on either side fails both.
      final cases =
          jsonDecode(
                File('test_fixtures/si5_dedupe_keys.json').readAsStringSync(),
              )
              as List;
      expect(cases, isNotEmpty);

      for (final raw in cases) {
        final c = (raw as Map).cast<String, dynamic>();
        final description = c['description'];
        final push = (c['push'] as Map).cast<String, dynamic>();
        final expectedKey = c['expectedKey'] as String?;
        final dartMessageId = c['dartMessageId'] as String?;
        final dartPayload = c['dartPayload'] as String?;

        // messageId derivation must mirror the Swift alias list (message_id /
        // messageId / id / msgId, never 'm') — incl. null for non-keyed pushes.
        expect(
          remoteNotificationMessageIdFromData(push),
          dartMessageId,
          reason: 'messageId derivation drift for "$description"',
        );

        if (expectedKey == null) {
          continue; // non-keyed push: no sidecar marker to consume.
        }

        // Gate key-shape parity: a marker named sha256(expectedKey) must be
        // consumable via the route (payload,messageId), proving the gate's
        // internal _messageKey == expectedKey byte-for-byte with the NSE.
        await writeMarker(expectedKey, now);
        expect(
          await gate.consumeIfRecentAnnouncement(
            payload: dartPayload!,
            messageId: dartMessageId,
          ),
          isTrue,
          reason: 'gate key-shape drift for "$description"',
        );
      }
    });
  });
}
