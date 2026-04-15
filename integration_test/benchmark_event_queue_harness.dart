/// Simulator Benchmark: Event Queue Wait (Test I)
///
/// Measures latency from Go event emission to Dart callback delivery,
/// under both idle and loaded conditions.
/// Run: flutter test integration_test/benchmark_event_queue_harness.dart -d <DEVICE_ID>
@Tags(['device'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'benchmark_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  testWidgets('I-Sim-1: Idle event delivery latency', (tester) async {
    print('\n${'═' * 60}');
    print('  BENCHMARK: EVENT QUEUE — IDLE (I-Sim-1)');
    print('${'═' * 60}\n');

    final node = await createBenchmarkNode();
    await node.startAndWaitOnline();

    // Collect delivery latencies by measuring health check round-trip
    final deliveryTimings = <int>[];

    for (var i = 0; i < 20; i++) {
      final sw = Stopwatch()..start();
      await node.service.performImmediateHealthCheck();
      sw.stop();
      deliveryTimings.add(sw.elapsedMilliseconds);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    deliveryTimings.sort();
    final p50 = percentile(deliveryTimings, 50);
    final p95 = percentile(deliveryTimings, 95);

    printBenchmark(
      'sim_event_queue_idle_ms',
      p50: p50,
      p95: p95,
      n: deliveryTimings.length,
    );

    // §6: Collect queueWaitMs from events if available
    final events = await captureFlowEvents(() async {
      await node.service.performImmediateHealthCheck();
    });

    // Look for any event with queueWaitMs field
    for (final e in events) {
      final d = e['details'] as Map<String, dynamic>;
      if (d.containsKey('queueWaitMs')) {
        print('[BENCHMARK] sim_event_queue_wait_ms = ${d['queueWaitMs']}');
      }
    }

    expect(p95, lessThan(500),
        reason: 'Idle event delivery should be < 500ms');

    await node.dispose();
  });

  testWidgets('I-Sim-2: Loaded event delivery', (tester) async {
    print('\n${'═' * 60}');
    print('  BENCHMARK: EVENT QUEUE — LOADED (I-Sim-2)');
    print('${'═' * 60}\n');

    final node = await createBenchmarkNode();
    await node.startAndWaitOnline();

    // Generate load: burst of bridge calls + health checks simultaneously
    final loadTimings = <int>[];

    // Phase 1: Burst 10 bridge calls, then immediately measure health check
    for (var i = 0; i < 10; i++) {
      // Fire multiple bridge calls to create backpressure
      unawaited(node.bridge.send(
          jsonEncode({'cmd': 'node:status', 'payload': {}})));
      unawaited(node.bridge.send(
          jsonEncode({'cmd': 'node:status', 'payload': {}})));

      final sw = Stopwatch()..start();
      await node.service.performImmediateHealthCheck();
      sw.stop();
      loadTimings.add(sw.elapsedMilliseconds);
    }

    loadTimings.sort();
    final p50 = percentile(loadTimings, 50);
    final p95 = percentile(loadTimings, 95);

    printBenchmark(
      'sim_event_queue_loaded_ms',
      p50: p50,
      p95: p95,
      n: loadTimings.length,
    );

    // Wait for pending futures to complete
    await Future<void>.delayed(const Duration(milliseconds: 500));

    await node.dispose();
  });
}
