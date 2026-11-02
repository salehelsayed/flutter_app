import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/diagnostics/app_diagnostic_schema.dart';
import 'package:flutter_app/core/diagnostics/app_diagnostics.dart';
import 'package:flutter_app/features/stickers/data/app_diagnostic_sticker_usage_recorder.dart';
import 'package:flutter_app/features/stickers/domain/sticker_usage_recorder.dart';
import 'package:flutter_test/flutter_test.dart';

const _firstSticker = 'orbit_crew.planet.hello';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late DateTime now;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('sticker-diagnostics-');
    now = DateTime(2026, 10, 29, 12);
  });

  tearDown(() async {
    await AppDiagnostics.instance.dispose();
    if (await directory.exists()) await directory.delete(recursive: true);
  });

  Future<AppDiagnostics> install({
    bool? enabled = true,
    AppDiagnosticUpload? upload,
    AppDiagnosticPersist? persist,
  }) => AppDiagnostics.installForTesting(
    directory: directory,
    enabled: enabled,
    now: () => now,
    upload: upload,
    persist: persist,
  );

  Future<List<Map<String, Object?>>> snapshots(
    AppDiagnostics diagnostics,
  ) async => (await diagnostics.eventsForTesting())
      .where((event) => event['feature'] == 'stickers')
      .toList();

  Future<Map<String, dynamic>> saved() async =>
      jsonDecode(await File('${directory.path}/state.json').readAsString())
          as Map<String, dynamic>;

  Future<void> send(AppDiagnostics diagnostics, String id) =>
      AppDiagnosticStickerUsageRecorder(
        diagnostics: diagnostics,
      ).recordSent(id);

  test(
    'closed sticker enum exactly matches bundled and reserved IDs',
    () async {
      final manifest =
          jsonDecode(await File('assets/stickers/packs.json').readAsString())
              as Map;
      final ids = <String>{
        ...List<String>.from(manifest['reservedIds'] as List),
        for (final pack in manifest['packs'] as List)
          for (final group in pack['groups'] as List)
            for (final sticker in group['stickers'] as List)
              sticker['id'] as String,
      };
      expect(
        (appDiagnosticSchemaV1['enumValues'] as Map)['sticker'],
        unorderedEquals(ids),
      );
      expect(appDiagnosticSchemaV1['feature'], contains('stickers'));
    },
  );

  test('same-day counts persist without emitting per-send events', () async {
    final diagnostics = await install();
    await send(diagnostics, _firstSticker);
    await send(diagnostics, _firstSticker);
    await diagnostics.flush();
    expect(await snapshots(diagnostics), isEmpty);
    final state = await saved();
    expect(jsonEncode(state['stickerUsage']), contains(_firstSticker));
    final restarted = await install(enabled: null);
    expect(await snapshots(restarted), isEmpty);
    now = DateTime(2026, 10, 30, 1);
    final nextDay = await install(enabled: null);
    final events = await snapshots(nextDay);
    expect(events, hasLength(1));
    expect(events.single['values'], {
      'sticker': _firstSticker,
      'count': 2,
      'reportTimeIsIntervalEnd': true,
    });
    expect(events.single['stage'], 'snapshot');
    expect(events.single['outcome'], 'ok');
    expect(events.single['reason'], 'none');
    expect(
      events.single['occurredAtMs'],
      DateTime(2026, 10, 30).millisecondsSinceEpoch - 1,
    );
    expect(events.single.containsKey('attemptId'), false);
    expect((await saved())['stickerUsage'], isEmpty);
    final id = events.single['eventId'];
    final again = await install(enabled: null);
    expect((await snapshots(again)).map((e) => e['eventId']), [id]);
  });

  test(
    'unknown input is erased immediately and custom remains separate',
    () async {
      final diagnostics = await install();
      await send(diagnostics, 'PRIVATE_UNKNOWN_STICKER_CONTENT');
      await send(diagnostics, 'custom');
      await diagnostics.flush();
      expect(jsonEncode(await saved()), isNot(contains('PRIVATE_UNKNOWN')));
      now = DateTime(2026, 10, 30, 1);
      final restarted = await install(enabled: null);
      expect(
        (await snapshots(
          restarted,
        )).map((e) => (e['values'] as Map)['sticker']),
        unorderedEquals(['unknown', 'custom']),
      );
    },
  );

  test(
    'disabled and disposed recorders retain nothing and do not throw',
    () async {
      final diagnostics = await install(enabled: false);
      final recorder = AppDiagnosticStickerUsageRecorder(
        diagnostics: diagnostics,
      );
      await recorder.recordSent(_firstSticker);
      await const NoopStickerUsageRecorder().recordSent(_firstSticker);
      await diagnostics.dispose();
      await recorder.recordSent(_firstSticker);
      now = DateTime(2026, 10, 30, 1);
      final restarted = await install(enabled: null);
      expect(await snapshots(restarted), isEmpty);
      expect(jsonEncode(await saved()), isNot(contains(_firstSticker)));
    },
  );

  for (final clear in [false, true]) {
    test(
      '${clear ? 'clear' : 'disable'} removes pending counts before restart',
      () async {
        final diagnostics = await install();
        await send(diagnostics, _firstSticker);
        if (clear) {
          await diagnostics.clear();
        } else {
          await diagnostics.setEnabled(false);
          await send(diagnostics, _firstSticker);
        }
        expect(jsonEncode(await saved()), isNot(contains(_firstSticker)));
        now = DateTime(2026, 10, 30, 1);
        final restarted = await install(enabled: null);
        expect(await snapshots(restarted), isEmpty);
      },
    );
  }

  test('disable wins over an earlier held persistence write', () async {
    final entered = Completer<void>();
    final release = Completer<void>();
    var hold = false;
    final diagnostics = await install(
      persist: (path, state) async {
        final copy = jsonEncode(state);
        if (hold) {
          hold = false;
          entered.complete();
          await release.future;
        }
        await File(path).writeAsString(copy);
      },
    );
    await send(diagnostics, _firstSticker);
    hold = true;
    // Force a write even on the RED scaffold so the privacy test cannot hang.
    diagnostics.record(feature: 'runtime', stage: 'snapshot', outcome: 'ok');
    final flushing = diagnostics.flush();
    await entered.future;
    final disabling = diagnostics.setEnabled(false);
    await send(diagnostics, _firstSticker);
    release.complete();
    await Future.wait([flushing, disabling]);
    now = DateTime(2026, 10, 30, 1);
    final restarted = await install(enabled: null);
    expect(await snapshots(restarted), isEmpty);
    expect(jsonEncode(await saved()), isNot(contains(_firstSticker)));
  });

  test(
    'all sticker IDs across two days survive per-group event limits',
    () async {
      final manifest =
          jsonDecode(await File('assets/stickers/packs.json').readAsString())
              as Map;
      final ids = <String>[
        ...List<String>.from(manifest['reservedIds'] as List),
        for (final pack in manifest['packs'] as List)
          for (final group in pack['groups'] as List)
            for (final sticker in group['stickers'] as List)
              sticker['id'] as String,
      ];
      final diagnostics = await install();
      for (final id in ids) {
        await send(diagnostics, id);
      }
      now = DateTime(2026, 10, 30, 12);
      for (final id in ids) {
        await send(diagnostics, id);
      }
      await diagnostics.flush();
      expect(await snapshots(diagnostics), isEmpty);
      now = DateTime(2026, 10, 31, 1);
      final restarted = await install(enabled: null);
      final events = await snapshots(restarted);
      expect(events, hasLength(ids.length * 2));
      for (final event in events) {
        expect((event['values'] as Map)['count'], 1);
      }
      expect((await saved())['stickerUsage'], isEmpty);
    },
  );

  test('old days expire while recent days retain their original end', () async {
    now = DateTime(2026, 10, 1, 12);
    final diagnostics = await install();
    await send(diagnostics, _firstSticker);
    now = DateTime(2026, 10, 8, 12);
    await send(diagnostics, 'custom');
    await diagnostics.flush();
    now = DateTime(2026, 10, 9, 1);
    final restarted = await install(enabled: null);
    final events = await snapshots(restarted);
    expect(events, hasLength(1));
    expect((events.single['values'] as Map)['sticker'], 'custom');
    expect(
      events.single['occurredAtMs'],
      DateTime(2026, 10, 9).millisecondsSinceEpoch - 1,
    );
  });

  test('restored tally rejects private keys and malformed counts', () async {
    final diagnostics = await install();
    await diagnostics.dispose();
    final state = await saved();
    final end = DateTime(2026, 10, 30).millisecondsSinceEpoch - 1;
    state['stickerUsage'] = [
      {
        'intervalEndMs': end,
        'counts': {
          _firstSticker: 3,
          'custom': -1,
          'unknown': true,
          'PRIVATE_ARCHIVE_KEY': 9,
        },
      },
      {
        'intervalEndMs': 'PRIVATE_TIMESTAMP',
        'counts': {'custom': 2},
      },
      {
        'intervalEndMs': end + 86400000 * 30,
        'counts': {'custom': 2},
      },
    ];
    await File('${directory.path}/state.json').writeAsString(jsonEncode(state));
    now = DateTime(2026, 10, 30, 1);
    final restarted = await install(enabled: null);
    final events = await snapshots(restarted);
    expect(events, hasLength(1));
    expect(events.single['values'], {
      'sticker': _firstSticker,
      'count': 3,
      'reportTimeIsIntervalEnd': true,
    });
    expect(jsonEncode(await saved()), isNot(contains('PRIVATE_')));
  });

  test('restored count saturates at the diagnostic integer bound', () async {
    final diagnostics = await install();
    await diagnostics.dispose();
    final state = await saved();
    state['stickerUsage'] = [
      {
        'intervalEndMs': DateTime(2026, 10, 30).millisecondsSinceEpoch - 1,
        'counts': {_firstSticker: 9007199254740991},
      },
    ];
    await File('${directory.path}/state.json').writeAsString(jsonEncode(state));
    final sameDay = await install(enabled: null);
    await send(sameDay, _firstSticker);
    now = DateTime(2026, 10, 30, 1);
    final restarted = await install(enabled: null);
    final events = await snapshots(restarted);
    expect(events, hasLength(1));
    expect((events.single['values'] as Map)['count'], 9007199254740991);
  });

  test('storage failure drops tally when it disables diagnostics', () async {
    var fail = false;
    final states = <Map<String, dynamic>>[];
    final diagnostics = await install(
      persist: (_, state) async {
        if (fail) throw const FileSystemException('unavailable');
        states.add(jsonDecode(jsonEncode(state)) as Map<String, dynamic>);
      },
    );
    await send(diagnostics, _firstSticker);
    fail = true;
    diagnostics.record(feature: 'runtime', stage: 'snapshot', outcome: 'ok');
    await diagnostics.flush();
    expect(diagnostics.enabled, false);
    fail = false;
    await diagnostics.setEnabled(true);
    expect(
      jsonEncode(states.last['stickerUsage']),
      isNot(contains(_firstSticker)),
    );
  });

  for (final date in [DateTime(2026, 3, 29), DateTime(2026, 10, 25)]) {
    test(
      'local day boundary survives seasonal offset change on $date',
      () async {
        now = date;
        final diagnostics = await install();
        await send(diagnostics, _firstSticker);
        now = DateTime(date.year, date.month, date.day + 1, 1);
        final restarted = await install(enabled: null);
        final events = await snapshots(restarted);
        expect(events, hasLength(1));
        expect(
          events.single['occurredAtMs'],
          DateTime(date.year, date.month, date.day + 1).millisecondsSinceEpoch -
              1,
        );
      },
    );
  }

  test('backwards clock does not publish a still-open day', () async {
    final diagnostics = await install();
    await send(diagnostics, _firstSticker);
    await diagnostics.flush();
    now = DateTime(2026, 10, 29, 10);
    final earlier = await install(enabled: null);
    expect(await snapshots(earlier), isEmpty);
    now = DateTime(2026, 10, 30, 1);
    final closed = await install(enabled: null);
    expect(await snapshots(closed), hasLength(1));
  });

  test('upload retry preserves snapshot identity and closed values', () async {
    final diagnostics = await install();
    await send(diagnostics, _firstSticker);
    now = DateTime(2026, 10, 30, 1);
    final uploaded = <Map<String, Object?>>[];
    final restarted = await install(
      enabled: null,
      upload: (events) async {
        uploaded.addAll(events.where((e) => e['feature'] == 'stickers'));
        return {};
      },
    );
    now = now.add(const Duration(minutes: 10));
    await restarted.flush();
    expect(uploaded.length, greaterThanOrEqualTo(2));
    expect(uploaded.map((e) => e['eventId']).toSet(), hasLength(1));
    for (final event in uploaded) {
      expect(event['values'], {
        'sticker': _firstSticker,
        'count': 1,
        'reportTimeIsIntervalEnd': true,
      });
    }
  });
}
