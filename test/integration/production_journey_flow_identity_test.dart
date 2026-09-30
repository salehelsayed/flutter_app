import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import '../../integration_test/support/android_app_state_guard.dart';
import '../../integration_test/support/production_android_journey.dart';

class _Adapter implements AndroidHostProcessRunner {
  var fail = false;
  var missing = false;
  var wrongFlow = false;
  final destinations = <String>[];
  @override
  Future<ProcessResult> run(String executable, List<String> args) async {
    final output = args[args.indexOf('--output') + 1];
    destinations.add(output);
    final directory = Directory(output);
    if (directory.existsSync()) return ProcessResult(1, 1, '', 'output exists');
    directory.createSync();
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
}
