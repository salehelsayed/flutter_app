import 'package:flutter/foundation.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_test/flutter_test.dart';

import 'benchmark_harness.dart';

void main() {
  late BenchmarkHarness harness;

  setUp(() {
    harness = BenchmarkHarness();
  });

  tearDown(() {
    harness.dispose();
  });

  group('BenchmarkHarness', () {
    test('captureFlowEvents collects events emitted during action', () async {
      final events = await harness.captureFlowEvents(() async {
        emitFlowEvent(
          layer: 'FL',
          event: 'TEST_EVENT',
          details: {'elapsedMs': 42},
        );
      });

      expect(events, hasLength(1));
      expect(events[0]['event'], 'TEST_EVENT');
      expect(
        (events[0]['details'] as Map<String, dynamic>)['elapsedMs'],
        42,
      );
    });

    test('captureFlowEvents restores logging state', () async {
      final previousLogging = flowEventLoggingEnabled;
      final originalDebugPrint = debugPrint;

      await harness.captureFlowEvents(() async {
        // Inside action, logging should be enabled
        expect(flowEventLoggingEnabled, isTrue);
      });

      // After action, state should be restored
      expect(flowEventLoggingEnabled, previousLogging);
      expect(debugPrint, originalDebugPrint);
    });

    test('filterEvents returns only matching events', () {
      final events = [
        {'event': 'TARGET', 'details': {}},
        {'event': 'OTHER', 'details': {}},
        {'event': 'TARGET', 'details': {}},
        {'event': 'OTHER', 'details': {}},
        {'event': 'TARGET', 'details': {}},
      ];

      final filtered = harness.filterEvents(events, 'TARGET');
      expect(filtered, hasLength(3));
      expect(filtered.every((e) => e['event'] == 'TARGET'), isTrue);
    });

    test('percentile computes p50 correctly', () {
      final values = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100];
      final p50 = harness.percentile(values, 50);
      expect(p50, 55); // median of even-length list: avg(50, 60)
    });

    test('percentile computes p95 correctly', () {
      final values = List.generate(100, (i) => i + 1); // 1..100
      final p95 = harness.percentile(values, 95);
      // rank = 0.95 * 99 = 94.05 → avg(values[94], values[95]) = avg(95, 96) = 96
      expect(p95, 96);
    });

    test('percentile handles single value', () {
      final p50 = harness.percentile([42], 50);
      expect(p50, 42);
    });

    test('percentile handles empty list', () {
      final p50 = harness.percentile([], 50);
      expect(p50, 0);
    });

    test('formatBenchmarkLine produces parseable output', () {
      final line = harness.formatBenchmarkLine(
        'cold_send',
        p50: 120,
        p95: 340,
        n: 10,
      );
      expect(line, '[BENCHMARK] cold_send p50=120ms p95=340ms (n=10)');
    });

    test('assertBudget passes when p95 is within budget', () {
      final values = [10, 20, 30, 40, 50, 60, 70, 80, 90, 200];
      // p95 = avg(values[8], values[9]) = avg(90, 200) = 145
      expect(
        () => harness.assertBudget(values, p95Budget: 500),
        returnsNormally,
      );
    });

    test('assertBudget fails when p95 exceeds budget', () {
      final values = [10, 20, 30, 40, 50, 60, 70, 80, 90, 600];
      // p95 = avg(values[8], values[9]) = avg(90, 600) = 345
      // Wait, let's recalculate: rank = 0.95 * 9 = 8.55
      // avg(values[8], values[9]) = avg(90, 600) = 345
      // This is < 500, so we need bigger values
      final bigValues = [100, 200, 300, 400, 500, 600, 700, 800, 900, 1000];
      // p95: rank = 0.95 * 9 = 8.55 → avg(900, 1000) = 950
      expect(
        () => harness.assertBudget(bigValues, p95Budget: 500),
        throwsA(isA<TestFailure>()),
      );
    });

    test('extractElapsedMs parses and sorts values from events', () {
      final events = [
        {
          'event': 'TEST',
          'details': {'elapsedMs': 100},
        },
        {
          'event': 'TEST',
          'details': {'elapsedMs': 20},
        },
        {
          'event': 'TEST',
          'details': {'elapsedMs': 50},
        },
      ];

      final values = harness.extractElapsedMs(events);
      expect(values, [20, 50, 100]); // sorted
    });

    test('record prints benchmark line to stdout', () {
      final printed = <String>[];
      final originalDebugPrint = debugPrint;
      debugPrint = (String? message, {int? wrapWidth}) {
        if (message != null) printed.add(message);
      };

      final events = [
        {
          'event': 'TEST',
          'details': {'elapsedMs': 100},
        },
        {
          'event': 'TEST',
          'details': {'elapsedMs': 200},
        },
      ];

      harness.record('test_metric', events);

      debugPrint = originalDebugPrint;

      expect(printed, hasLength(1));
      expect(printed[0], contains('[BENCHMARK]'));
      expect(printed[0], contains('test_metric'));
    });
  });
}
