import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/diagnostics/anonymous_sticker_counter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

  test('closed-day batch is anonymous, persistent and acknowledged once', () async {
    final reports = <Map<String, Object?>>[];
    var c = counter((r) async { reports.add(r); return true; });
    await c.initialize();
    c.record(sticker);
    c.record(sticker);
    c.record('PRIVATE_UNKNOWN_ID');
    await c.flush();
    expect(reports, isEmpty);
    await c.dispose();
    c = counter((r) async { reports.add(r); return true; });
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
  });

  test('failure retries the identical nonce and counts after restart', () async {
    final reports = <Map<String, Object?>>[];
    var c = counter((r) async { reports.add(r); return false; });
    await c.initialize();
    c.record(sticker);
    now = now.add(const Duration(days: 1));
    await c.flush();
    await c.dispose();
    c = counter((r) async { reports.add(r); return true; });
    await c.initialize();
    await c.flush();
    expect(reports, hasLength(2));
    expect(reports.first, reports.last);
    await c.dispose();
  });

  test('opt-out clears pending counts and fences an in-flight reply', () async {
    final reply = Completer<bool>();
    var calls = 0;
    final c = counter((_) { calls++; return reply.future; });
    await c.initialize();
    c.record(sticker);
    now = now.add(const Duration(days: 1));
    final pending = c.flush();
    await Future<void>.delayed(const Duration(milliseconds: 20));
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
    final c = counter((r) async { reports.add(r); return true; });
    await c.initialize();
    for (var i = 0; i < 1200; i++) { c.record(sticker); }
    now = now.add(const Duration(days: 1));
    await c.flush();
    expect(reports.single['counts'], {sticker: 1000});
    c.record(sticker);
    now = now.add(const Duration(days: 4));
    await c.flush();
    expect(reports, hasLength(1));
    await c.dispose();
  });
}
