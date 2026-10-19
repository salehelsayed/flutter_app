import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/production_verbatim_keyboard.dart';

void main() {
  const gboard =
      'com.google.android.inputmethod.latin/com.android.inputmethod.latin.LatinIME';

  ProcessResult result(String stdout) => ProcessResult(0, 0, stdout, '');

  test('switches to the verbatim keyboard and restores the original', () async {
    final calls = <List<String>>[];
    Future<ProcessResult> adb(List<String> args) async {
      calls.add(args);
      if (args.join(' ') == 'shell ime list -a -s') {
        return result('$gboard\n$productionVerbatimIme\n');
      }
      if (args.join(' ') == 'shell settings get secure default_input_method') {
        return result('$gboard\n');
      }
      return result('');
    }

    final switches = <Map<String, Object?>>[];
    final seen = await withProductionVerbatimKeyboard(
      adb,
      'G5-send-5',
      switches,
      (verbatim) async {
        expect(calls.last, ['shell', 'ime', 'set', productionVerbatimIme]);
        return verbatim;
      },
    );
    expect(seen, isTrue);
    expect(calls, anyElement(equals(['shell', 'ime', 'set', gboard])));
    expect(switches.single, {'label': 'G5-send-5', 'restoreTo': gboard});
  });

  test('a session keeps the verbatim keyboard until restored', () async {
    final calls = <String>[];
    Future<ProcessResult> adb(List<String> args) async {
      calls.add(args.join(' '));
      return switch (args.join(' ')) {
        'shell ime list -a -s' => result(productionVerbatimIme),
        'shell settings get secure default_input_method' => result(gboard),
        _ => result(''),
      };
    }

    final switches = <Map<String, Object?>>[];
    final session = ProductionVerbatimKeyboardSession(adb, switches);
    expect(await session.run('S8-send-1', (v) async => v), isTrue);
    expect(await session.run('S8-send-2', (v) async => v), isTrue);
    // Switched once, never restored between sends: restoring the device
    // keyboard while the composer has focus opens it over the next step.
    expect(
      calls.where((c) => c == 'shell ime set $productionVerbatimIme'),
      hasLength(1),
    );
    expect(calls.where((c) => c == 'shell ime set $gboard'), isEmpty);
    await session.restore();
    await session.restore();
    expect(calls.where((c) => c == 'shell ime set $gboard'), hasLength(1));
    expect(switches.map((s) => s['label']), ['S8-send-1', 'S8-send-2']);
    expect(switches.first['restoreTo'], gboard);
    // After a restore the next send switches again.
    await session.run('S9-send-1', (v) async => v);
    expect(
      calls.where((c) => c == 'shell ime set $productionVerbatimIme'),
      hasLength(2),
    );
  });

  test('a session without the verbatim keyboard never switches', () async {
    final calls = <String>[];
    Future<ProcessResult> adb(List<String> args) async {
      calls.add(args.join(' '));
      return result(gboard);
    }

    final session = ProductionVerbatimKeyboardSession(adb, []);
    expect(await session.run('S1-send-1', (v) async => v), isFalse);
    await session.restore();
    expect(calls.where((c) => c.startsWith('shell ime set')), isEmpty);
  });

  test('restores the original keyboard when the flow fails', () async {
    final calls = <List<String>>[];
    Future<ProcessResult> adb(List<String> args) async {
      calls.add(args);
      if (args.join(' ') == 'shell ime list -a -s') {
        return result(productionVerbatimIme);
      }
      if (args.join(' ') == 'shell settings get secure default_input_method') {
        return result(gboard);
      }
      return result('');
    }

    await expectLater(
      withProductionVerbatimKeyboard(
        adb,
        'x',
        [],
        (_) async => throw StateError('flow failed'),
      ),
      throwsStateError,
    );
    expect(calls, anyElement(equals(['shell', 'ime', 'set', gboard])));
  });

  test('uses the device keyboard when the verbatim one is absent', () async {
    final calls = <List<String>>[];
    Future<ProcessResult> adb(List<String> args) async {
      calls.add(args);
      return result(gboard);
    }

    final switches = <Map<String, Object?>>[];
    final seen = await withProductionVerbatimKeyboard(
      adb,
      'S1-send-1',
      switches,
      (verbatim) async => verbatim,
    );
    expect(seen, isFalse);
    expect(calls, [
      ['shell', 'ime', 'list', '-a', '-s'],
    ]);
    expect(switches.single, {'label': 'S1-send-1', 'restoreTo': null});
  });

  test('routing and catalog sends share the verbatim keyboard helper', () {
    final routing = File(
      'integration_test/scripts/run_production_routing.dart',
    ).readAsStringSync();
    final catalog = File(
      'integration_test/support/production_catalog_session.dart',
    ).readAsStringSync();
    expect(routing, contains('ProductionVerbatimKeyboardSession('));
    expect(routing, contains('restoreKeyboards()'));
    expect(routing, contains("'production_verbatim_send'"));
    expect(catalog, contains('withProductionVerbatimKeyboard('));
    expect(catalog, isNot(contains("'shell', 'ime', 'set'")));
  });
}
