import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../../integration_test/support/android_app_state_guard.dart';
import '../../integration_test/support/production_android_journey.dart';

class _Adapter implements AndroidHostProcessRunner {
  var fail = false;
  var missing = false;
  var wrongFlow = false;
  // Debug-log lines for leading failed Maestro runs; process.log only reports
  // the failed flow, as Maestro's own console output does.
  final serverDeaths = <String>[];
  final destinations = <String>[];
  final adbCalls = <List<String>>[];
  final adapterArgs = <List<String>>[];
  @override
  Future<ProcessResult> run(String executable, List<String> args) async {
    if (executable == 'adb') {
      adbCalls.add(args);
      return ProcessResult(1, 0, '', '');
    }
    adapterArgs.add(List.of(args));
    final output = args[args.indexOf('--output') + 1];
    destinations.add(output);
    final directory = Directory(output);
    if (directory.existsSync()) return ProcessResult(1, 1, '', 'output exists');
    directory.createSync();
    if (serverDeaths.isNotEmpty) {
      File('$output/process.log').writeAsStringSync(
        '[Failed] production_reopen_seeded (182ms)\n1/1 Flow Failed\n',
      );
      File('$output/debug/.maestro/tests/2026-10-06_124903/maestro.log')
        ..createSync(recursive: true)
        ..writeAsStringSync(serverDeaths.removeAt(0));
      return ProcessResult(1, 1, '', '');
    }
    if (!missing) {
      File('$output/result.json').writeAsStringSync(
        jsonEncode({
          'status': fail ? 'FAIL' : 'PASS',
          'exit_status': fail ? 1 : 0,
          'flows': [
            wrongFlow ? 'foreign' : args[args.indexOf('--expected-name') + 1],
          ],
        }),
      );
    }
    return ProcessResult(
      1,
      fail ? 1 : 0,
      'adapter stdout',
      fail ? 'first failure' : '',
    );
  }
}

class _TimedAdapter extends _Adapter
    implements AndroidHostProcessRunnerWithTimeout {
  final timeouts = <Duration>[];

  @override
  Future<ProcessResult> runWithTimeout(
    String executable,
    List<String> args, {
    required Duration timeout,
  }) {
    timeouts.add(timeout);
    return run(executable, args);
  }
}

void main() {
  late Directory root;
  late _Adapter adapter;
  late ProductionJourneyFlowRunner runner;
  setUp(() {
    root = Directory.systemTemp.createTempSync('journey-flow-');
    adapter = _Adapter();
    runner = ProductionJourneyFlowRunner(root, adapter);
  });
  tearDown(() => root.deleteSync(recursive: true));
  Future<String> run() =>
      runner.run('pinned', 'production_reopen_seeded', 'alice-reopen', {});
  for (final (device, flow, inner, outer) in [
    ('pinned', 'production_direct_send_batch5', '180', 210),
    ('pinned', 'production_reopen_seeded', null, null),
    (
      '00000000-0000-0000-0000-000000000001',
      'production_reopen_seeded',
      '300',
      330,
    ),
    (
      '00000000-0000-0000-0000-000000000001',
      'production_direct_send_batch5',
      '300',
      330,
    ),
  ]) {
    test('flow deadline stays scoped to $device/$flow', () async {
      final timed = _TimedAdapter();
      await ProductionJourneyFlowRunner(
        root,
        timed,
      ).run(device, flow, 'deadline', {});
      final args = timed.adapterArgs.single;
      if (inner == null) {
        expect(args, isNot(contains('--timeout')));
      } else {
        expect(args[args.indexOf('--timeout') + 1], inner);
      }
      expect(
        timed.timeouts,
        outer == null ? isEmpty : [Duration(seconds: outer)],
      );
    });
  }
  test('started batch failure keeps its receipt and is not replayed', () async {
    final timed = _TimedAdapter()
      ..serverDeaths.add(
        'maestro.cli.runner.MaestroCommandRunner.invoke: inputText RUNNING\n'
        "Device server died during 'deviceInfo'\n",
      );
    await expectLater(
      ProductionJourneyFlowRunner(
        root,
        timed,
      ).run('pinned', 'production_direct_send_batch5', 'batch', {}),
      throwsStateError,
    );
    expect(timed.destinations, hasLength(1));
    expect(timed.adbCalls, isEmpty);
    expect(timed.timeouts, [const Duration(seconds: 210)]);
    expect(
      File(
        '${Directory(timed.destinations.single).parent.path}/adapter.json',
      ).existsSync(),
      isTrue,
    );
  });
  test('repeated reopen labels keep independent exact receipts', () async {
    final first = await run();
    final bytes = File(first).readAsBytesSync();
    final second = await run();
    expect(second, isNot(first));
    expect(File(first).readAsBytesSync(), bytes);
    expect(File(second).existsSync(), isTrue);
  });
  test(
    'later adapter failure cannot reuse prior PASS and preserves diagnostics',
    () async {
      final first = await run();
      adapter.fail = true;
      await expectLater(run(), throwsStateError);
      expect(jsonDecode(File(first).readAsStringSync())['status'], 'PASS');
      final report = File(
        '${Directory(adapter.destinations.last).parent.path}/adapter.json',
      );
      expect(jsonDecode(report.readAsStringSync())['stderr'], 'first failure');
    },
  );
  test('zero exit without receipt cannot pass', () async {
    adapter.missing = true;
    await expectLater(run(), throwsA(isA<FileSystemException>()));
  });
  test('receipt from a different flow cannot pass', () async {
    adapter.wrongFlow = true;
    await expectLater(run(), throwsStateError);
  });
  test(
    'a device server that dies before the first UI step reruns once',
    () async {
      adapter.serverDeaths.add(
        'maestro.android.DeviceServerDiedException: Device server died '
        "during 'deviceInfo' on pinned (1423ms since last byte)\n",
      );
      final receipt = await run();
      expect(adapter.destinations, hasLength(2));
      expect(receipt, startsWith(Directory(adapter.destinations.last).path));
      expect(
        adapter.adbCalls.map((call) => call.last),
        containsAll(['dev.mobile.maestro', 'dev.mobile.maestro.test']),
      );
    },
  );
  test(
    'a failed device-info call before the first UI step reruns once',
    () async {
      adapter.serverDeaths.add(
        "maestro.android.DeviceCallFailedException: 'deviceInfo' failed: "
        'INTERNAL - error in frame handler\n',
      );
      await run();
      expect(adapter.destinations, hasLength(2));
    },
  );
  test('a device server that dies mid-flow is not replayed', () async {
    adapter.serverDeaths.add(
      'Running flow production_reopen_seeded\n'
      'maestro.android.DeviceServerDiedException: Device server died '
      "during 'tapOn' on pinned\n",
    );
    await expectLater(run(), throwsStateError);
    expect(adapter.destinations, hasLength(1));
    expect(adapter.adbCalls, isEmpty);
  });
  for (final (command, failure) in [
    ('inputText', "'deviceInfo' failed: INTERNAL"),
    ('tapOn', "Device server died during 'deviceInfo'"),
  ]) {
    test('device-info failure after $command is not replayed', () async {
      adapter.serverDeaths.add(
        '12:00:00 [ INFO] maestro.cli.runner.MaestroCommandRunner.invoke: '
        '$command RUNNING\n'
        '12:00:01 [ INFO] maestro.cli.runner.MaestroCommandRunner.invoke: '
        '$command COMPLETED\n'
        '$failure\n',
      );
      await expectLater(run(), throwsStateError);
      expect(adapter.destinations, hasLength(1));
      expect(adapter.adbCalls, isEmpty);
    });
  }
}
