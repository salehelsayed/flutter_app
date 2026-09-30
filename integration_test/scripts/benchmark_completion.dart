import 'dart:async';
import 'dart:convert';

/// Proof of Flutter test execution, independent of a child process exit code.
class BenchmarkCompletion {
  BenchmarkCompletion({this.expectedTestName});

  final String? expectedTestName;
  final _started = Completer<void>();
  final _names = <int, String>{};
  final _completedTests = <int>{};
  final _routingStages = <String>{};
  int passed = 0;
  bool incomplete = false;
  bool done = false;

  void observe(String line) {
    // Existing harnesses report missing prerequisites with print-and-return;
    // package:test then emits a successful testDone. That is not completion.
    if (line.contains('[SKIP]') || line.contains('[BLOCKED]')) {
      incomplete = true;
    }
    dynamic event;
    try {
      event = jsonDecode(line);
    } on FormatException {
      return;
    }
    if (event is! Map<String, dynamic>) return;
    if (event['type'] == 'testStart') {
      final test = event['test'] as Map<String, dynamic>;
      _names[test['id'] as int] = test['name'] as String;
      if (expectedTestName != null &&
          test['name'] == expectedTestName &&
          !_started.isCompleted) {
        _started.complete();
      }
    }
    if (event['type'] == 'testDone') {
      final name = _names[event['testID']] ?? '';
      if (name.startsWith('loading ') ||
          name.endsWith('(setUpAll)') ||
          name.endsWith('(tearDownAll)')) {
        return;
      }
      if (!_completedTests.add(event['testID'] as int)) incomplete = true;
      if (event['result'] == 'success' &&
          event['skipped'] != true &&
          name.isNotEmpty) {
        passed++;
      } else {
        incomplete = true;
      }
    }
    if (event['type'] == 'print' &&
        _names[event['testID']] == 'benchmark ROUTING_PATHS') {
      final match = RegExp(
        r'^BENCHMARK_STAGE_COMPLETED (R-Sim-[1-8])$',
      ).firstMatch(event['message'] as String? ?? '');
      if (match != null && !_routingStages.add(match[1]!)) incomplete = true;
    }
    if (event['type'] == 'error') incomplete = true;
    if (event['type'] == 'done') done = event['success'] == true;
  }

  /// Build/install time is setup, before a scenario's signal deadlines begin.
  Future<void> waitForStart({
    required Future<int> exitCode,
    Duration timeout = const Duration(minutes: 15),
  }) {
    if (expectedTestName == null) {
      throw StateError('An exact benchmark test name is required for startup.');
    }
    return Future.any<void>([
      _started.future,
      exitCode.then<void>((code) {
        throw StateError(
          'Benchmark child exited $code before $expectedTestName started.',
        );
      }),
    ]).timeout(timeout);
  }

  void requireCompleted() {
    if (expectedTestName != null &&
        !_completedTests.any((id) => _names[id] == expectedTestName)) {
      incomplete = true;
    }
    if (_names.containsValue('benchmark ROUTING_PATHS') &&
        _routingStages.length != 8) {
      incomplete = true;
    }
    if (!done || incomplete || passed == 0) {
      throw StateError(
        'Benchmark child omitted terminal assertions or skipped/failed tests.',
      );
    }
  }
}
