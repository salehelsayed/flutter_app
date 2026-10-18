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
    expect(calls.last, ['shell', 'ime', 'set', gboard]);
    expect(switches.single, {'label': 'G5-send-5', 'restoreTo': gboard});
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
    expect(calls.last, ['shell', 'ime', 'set', gboard]);
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
    expect(routing, contains('withProductionVerbatimKeyboard('));
    expect(routing, contains("'production_verbatim_send'"));
    expect(catalog, contains('withProductionVerbatimKeyboard('));
    expect(catalog, isNot(contains("'shell', 'ime', 'set'")));
  });
}
