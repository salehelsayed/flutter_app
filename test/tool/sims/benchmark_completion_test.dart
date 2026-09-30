import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../../integration_test/scripts/benchmark_completion.dart';

void main() {
  void start(BenchmarkCompletion completion, String name) {
    completion.observe(
      jsonEncode({
        'type': 'testStart',
        'test': {'id': 1, 'name': name},
      }),
    );
  }

  test(
    'only the exact test starts the scenario deadline',
    () async {
      final completion = BenchmarkCompletion(
        expectedTestName: 'benchmark GROUP_PUBLISH',
      );
      final exit = Completer<int>();
      var started = false;
      final waiting = completion
          .waitForStart(exitCode: exit.future)
          .then((_) => started = true);
      start(completion, 'loading benchmark_harness.dart');
      start(completion, 'benchmark OTHER');
      await Future<void>.delayed(Duration.zero);
      expect(started, isFalse);
      start(completion, 'benchmark GROUP_PUBLISH');
      await waiting;
      expect(started, isTrue);
      expect(completion.requireCompleted, throwsStateError);
    },
  );

  test(
    'build failure exits startup immediately without a signal wait',
    () async {
      final completion = BenchmarkCompletion(
        expectedTestName: 'benchmark GROUP_PUBLISH',
      );
      await expectLater(
        completion.waitForStart(exitCode: Future.value(65)),
        throwsStateError,
      );
    },
  );

  test('silent startup retains its separate bound', () async {
    final completion = BenchmarkCompletion(
      expectedTestName: 'benchmark GROUP_PUBLISH',
    );
    await expectLater(
      completion.waitForStart(
        exitCode: Completer<int>().future,
        timeout: const Duration(milliseconds: 1),
      ),
      throwsA(isA<TimeoutException>()),
    );
  });

  test('startup requires an exact scenario name', () {
    expect(
      () => BenchmarkCompletion().waitForStart(exitCode: Future.value(0)),
      throwsStateError,
    );
  });
}
