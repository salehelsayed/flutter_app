import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/diagnostics/anonymous_sticker_counter.dart';
import 'package:flutter_app/core/diagnostics/app_diagnostics.dart';
import 'package:flutter_app/core/bridge/go_bridge_client.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late DateTime now;
  late bool enabled;
  const sticker = 'orbit_crew.planet.hello';
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('anonymous-stickers-');
    now = DateTime.utc(2026, 11, 8, 12);
    enabled = true;
  });
  tearDown(() async => directory.delete(recursive: true));

  AnonymousStickerCounter counter(
    Future<bool> Function(Map<String, Object?>) upload,
  ) => AnonymousStickerCounter(
    directory: directory,
    stickerIds: const [sticker],
    enabled: () => enabled,
    now: () => now,
    upload: upload,
  );

  test(
    'closed-day batch is anonymous, persistent and acknowledged once',
    () async {
      final reports = <Map<String, Object?>>[];
      var c = counter((r) async {
        reports.add(r);
        return true;
      });
      await c.initialize();
      c.record(sticker);
      c.record(sticker);
      c.record('PRIVATE_UNKNOWN_ID');
      await c.flush();
      expect(reports, isEmpty);
      await c.dispose();
      c = counter((r) async {
        reports.add(r);
        return true;
      });
      await c.initialize();
      now = now.add(const Duration(days: 1));
      await c.flush();
      expect(reports, hasLength(1));
      expect(reports.single.keys, unorderedEquals(['day', 'nonce', 'counts']));
      expect(reports.single['day'], '2026-11-08');
      expect(reports.single['counts'], {sticker: 2});
      expect(jsonEncode(reports), isNot(contains('PRIVATE_UNKNOWN')));
      await c.flush();
      expect(reports, hasLength(1));
      await c.dispose();
    },
  );

  test(
    'failure preserves hourly retry pacing and batch ownership across restart',
    () async {
      final reports = <Map<String, Object?>>[];
      var c = counter((r) async {
        reports.add(r);
        return false;
      });
      await c.initialize();
      c.record(sticker);
      now = now.add(const Duration(days: 1));
      await c.flush();
      expect(reports, hasLength(1));
      // Restore the state durable at failure, before graceful disposal writes.
      final stateFile = File('${directory.path}/counts.json');
      final durableState = await stateFile.readAsBytes();
      await c.dispose();
      await stateFile.writeAsBytes(durableState, flush: true);
      c = counter((r) async {
        reports.add(r);
        return true;
      });
      await c.initialize();
      await c.flush();
      expect(reports, hasLength(1));
      now = now.add(const Duration(minutes: 59, seconds: 59));
      await c.flush();
      expect(reports, hasLength(1));
      now = now.add(const Duration(seconds: 1));
      await c.flush();
      expect(reports, hasLength(2));
      expect(reports.first, reports.last);
      await c.flush();
      expect(reports, hasLength(2));
      await c.dispose();
    },
  );

  test(
    'legacy count archive keeps its batch without a retry deadline',
    () async {
      final batch = {
        'day': '2026-11-07',
        'nonce': '00000000-0000-4000-8000-000000000001',
        'counts': {sticker: 2},
      };
      await File(
        '${directory.path}/counts.json',
      ).writeAsString(jsonEncode([batch]));
      final reports = <Map<String, Object?>>[];
      final c = counter((report) async {
        reports.add(report);
        return true;
      });
      await c.initialize();
      await c.flush();
      expect(reports, [batch]);
      await c.dispose();
    },
  );

  test('opt-out clears pending counts and fences an in-flight reply', () async {
    final reply = Completer<bool>();
    final started = Completer<void>();
    var calls = 0;
    final c = counter((_) {
      calls++;
      started.complete();
      return reply.future;
    });
    await c.initialize();
    c.record(sticker);
    now = now.add(const Duration(days: 1));
    final pending = c.flush();
    await started.future;
    expect(calls, 1);
    enabled = false;
    await c.clear();
    c.record(sticker);
    reply.complete(true);
    await pending;
    enabled = true;
    now = now.add(const Duration(days: 1));
    await c.flush();
    expect(calls, 1);
    await c.dispose();
  });

  test('old batches are dropped and reports are capped', () async {
    final reports = <Map<String, Object?>>[];
    final c = counter((r) async {
      reports.add(r);
      return true;
    });
    await c.initialize();
    for (var i = 0; i < 1200; i++) {
      c.record(sticker);
    }
    now = now.add(const Duration(days: 1));
    await c.flush();
    expect(reports.single['counts'], {sticker: 1000});
    c.record(sticker);
    now = now.add(const Duration(days: 4));
    await c.flush();
    expect(reports, hasLength(1));
    await c.dispose();
  });

  test(
    'production recorder sends only the separate anonymous native report',
    () async {
      const channel = MethodChannel('com.mknoon/go_bridge');
      const codec = StandardMethodCodec();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final reports = <Map<String, dynamic>>[];
      messenger.setMockMessageHandler(
        'com.mknoon/go_bridge_events',
        (_) async => codec.encodeSuccessEnvelope(null),
      );
      messenger.setMockMethodCallHandler(channel, (call) async {
        final body =
            jsonDecode(call.arguments as String) as Map<String, dynamic>;
        if (call.method == 'stickerUsageV1') reports.add(body);
        return jsonEncode({
          'ok': true,
          'data': {
            'supported': true,
            'accepted': true,
            'enabled': body['enabled'] ?? true,
            'consentEpoch': body['consentEpoch'],
          },
        });
      });
      final bridge = GoBridgeClient();
      await bridge.initialize();
      final diagnostics = await AppDiagnostics.installForTesting(
        directory: directory,
        now: () => now,
        bridge: bridge,
        upload: (events) async =>
            events.map((e) => e['eventId'] as String).toSet(),
      );
      try {
        diagnostics.recordStickerSent(sticker);
        now = now.add(const Duration(days: 1));
        await diagnostics.flush();
        expect(reports, hasLength(1));
        expect(
          reports.single.keys,
          unorderedEquals(['day', 'nonce', 'counts']),
        );
        expect(reports.single['counts'], {sticker: 1});
        await diagnostics.setEnabled(false);
        diagnostics.recordStickerSent(sticker);
        now = now.add(const Duration(days: 1));
        await diagnostics.flush();
        expect(reports, hasLength(1));
      } finally {
        await diagnostics.dispose();
        bridge.dispose();
        await Future<void>.delayed(Duration.zero);
        messenger.setMockMethodCallHandler(channel, null);
        messenger.setMockMessageHandler('com.mknoon/go_bridge_events', null);
      }
    },
  );
}
