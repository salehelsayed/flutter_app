import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reusable benchmark test helper that captures, filters, and reports
/// flow event timing data.
class BenchmarkHarness {
  /// Captures [FLOW] events emitted during [action].
  Future<List<Map<String, dynamic>>> captureFlowEvents(
    Future<void> Function() action,
  ) async {
    final printed = <String>[];
    final previousLogging = flowEventLoggingEnabled;
    final originalDebugPrint = debugPrint;
    flowEventLoggingEnabled = true;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) printed.add(message);
    };
    try {
      await action();
    } finally {
      debugPrint = originalDebugPrint;
      flowEventLoggingEnabled = previousLogging;
    }
    return printed
        .where((line) => line.startsWith('[FLOW] '))
        .map((line) {
          final json = line.substring('[FLOW] '.length);
          return jsonDecode(json) as Map<String, dynamic>;
        })
        .toList();
  }

  /// Filters events by event name.
  List<Map<String, dynamic>> filterEvents(
    List<Map<String, dynamic>> events,
    String eventName,
  ) =>
      events.where((e) => e['event'] == eventName).toList();

  /// Extracts elapsedMs from a list of timing events, returned sorted.
  List<int> extractElapsedMs(List<Map<String, dynamic>> events) =>
      events
          .map(
            (e) => (e['details'] as Map<String, dynamic>)['elapsedMs'] as int,
          )
          .toList()
        ..sort();

  /// Computes the given percentile (0-100) from a sorted list.
  /// Uses linear interpolation between adjacent ranks.
  int percentile(List<int> sortedValues, int p) {
    if (sortedValues.isEmpty) return 0;
    if (sortedValues.length == 1) return sortedValues.first;
    final rank = (p / 100.0) * (sortedValues.length - 1);
    final lower = rank.floor();
    final upper = rank.ceil();
    if (lower == upper) return sortedValues[lower];
    return ((sortedValues[lower] + sortedValues[upper]) / 2).round();
  }

  /// Formats a benchmark result line for stdout.
  String formatBenchmarkLine(
    String metric, {
    required int p50,
    required int p95,
    required int n,
  }) =>
      '[BENCHMARK] $metric p50=${p50}ms p95=${p95}ms (n=$n)';

  /// Asserts that the p95 of [sortedValues] is within [p95Budget].
  void assertBudget(List<int> sortedValues, {required int p95Budget}) {
    final p95 = percentile(sortedValues, 95);
    expect(
      p95,
      lessThanOrEqualTo(p95Budget),
      reason: 'p95 ($p95) exceeds budget ($p95Budget)',
    );
  }

  /// Extracts timing from events and prints a [BENCHMARK] line.
  void record(String metricName, List<Map<String, dynamic>> events) {
    final values = extractElapsedMs(events);
    final line = formatBenchmarkLine(
      metricName,
      p50: percentile(values, 50),
      p95: percentile(values, 95),
      n: values.length,
    );
    debugPrint(line);
  }

  void dispose() {}
}
