/// Simulator Benchmark: Node Startup Timing (Test B)
///
/// Measures the full startup sequence from node:start to Online.
/// Run: flutter test integration_test/benchmark_node_startup_harness.dart -d <DEVICE_ID>
@Tags(['device'])
library;

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

  testWidgets('B-Sim-1: Cold start — measure each phase', (tester) async {
    print('\n${'═' * 60}');
    print('  BENCHMARK: NODE STARTUP (B-Sim-1)');
    print('${'═' * 60}\n');

    final node = await createBenchmarkNode();

    final events = await captureFlowEvents(() async {
      final started = await node.startAndWaitOnline(
        timeout: const Duration(seconds: 30),
      );
      expect(started, isTrue, reason: 'Node should reach Online');
    });

    // TIME_TO_ONLINE_BADGE
    final badge = filterEvents(events, 'TIME_TO_ONLINE_BADGE');
    if (badge.isNotEmpty) {
      final details = badge.first['details'] as Map<String, dynamic>;
      final totalMs = details['totalMs'] as int;
      final phase = details['phase'] as String;
      final source = details['source'] as String;

      printBenchmarkSingle('sim_time_to_online_badge_ms', totalMs);
      print('[BENCHMARK] sim_time_to_online_phase = $phase');
      print('[BENCHMARK] sim_time_to_online_source = $source');

      expect(totalMs, lessThan(6000),
          reason: 'Simulator budget: < 6s for cold start');
    } else {
      print('[WARNING] No TIME_TO_ONLINE_BADGE event captured');
    }

    // §18: Per-phase startup timing from Go side (node:startup_timing)
    final startupEvents = filterEvents(events, 'node:startup_timing');
    for (final e in startupEvents) {
      final d = e['details'] as Map<String, dynamic>;
      final phase = d['phase'] ?? 'unknown';
      if (d.containsKey('libp2pNewMs')) {
        printBenchmarkSingle(
            'sim_startup_host_ready_ms', (d['libp2pNewMs'] as num).toInt());
      }
      if (d.containsKey('pubsubInitMs')) {
        printBenchmarkSingle(
            'sim_startup_pubsub_ms', (d['pubsubInitMs'] as num).toInt());
      }
      if (d.containsKey('relayWarmMs')) {
        printBenchmarkSingle(
            'sim_startup_relay_warm_ms', (d['relayWarmMs'] as num).toInt());
      }
      if (d.containsKey('relaysAttempted')) {
        printBenchmarkSingle(
            'sim_startup_relays_attempted', (d['relaysAttempted'] as num).toInt());
      }
      if (d.containsKey('totalToDiscoverableMs')) {
        final total = (d['totalToDiscoverableMs'] as num).toInt();
        printBenchmarkSingle('sim_startup_total_discoverable_ms', total);
        expect(total, lessThan(5000),
            reason: 'totalToDiscoverableMs should be < 5s');
      }
      print('[BENCHMARK] sim_startup_phase_$phase = $d');
    }

    // §11: Circuit address timing
    final circuitEvents = filterEvents(events, 'circuit_address:timing');
    for (final e in circuitEvents) {
      final d = e['details'] as Map<String, dynamic>;
      if (d.containsKey('elapsedMs')) {
        printBenchmarkSingle(
            'sim_startup_circuit_address_ms', (d['elapsedMs'] as num).toInt());
      }
      if (d.containsKey('pollCount')) {
        print('[BENCHMARK] sim_startup_circuit_poll_count = ${d['pollCount']}');
      }
    }

    // §24: Widget transition timing
    final widgetBadge = filterEvents(events, 'TIME_TO_ONLINE_BADGE_WIDGET');
    for (final e in widgetBadge) {
      final d = e['details'] as Map<String, dynamic>;
      if (d.containsKey('widgetTransitionMs')) {
        printBenchmarkSingle(
            'sim_time_to_online_widget_ms',
            (d['widgetTransitionMs'] as num).toInt());
      }
    }

    await node.dispose();
  });

  testWidgets('B-Sim-2: Repeated cold starts (5 runs)', (tester) async {
    print('\n${'═' * 60}');
    print('  BENCHMARK: REPEATED COLD STARTS (B-Sim-2)');
    print('${'═' * 60}\n');

    final timings = <int>[];

    for (var i = 0; i < 5; i++) {
      print('\n--- Run ${i + 1}/5 ---');
      final node = await createBenchmarkNode();

      final events = await captureFlowEvents(() async {
        await node.startAndWaitOnline(timeout: const Duration(seconds: 30));
      });

      final badge = filterEvents(events, 'TIME_TO_ONLINE_BADGE');
      if (badge.isNotEmpty) {
        final totalMs =
            (badge.first['details'] as Map<String, dynamic>)['totalMs'] as int;
        timings.add(totalMs);
        print('[RUN ${i + 1}] TIME_TO_ONLINE = ${totalMs}ms');
      }

      await node.dispose();
    }

    if (timings.isNotEmpty) {
      timings.sort();
      printBenchmark(
        'sim_cold_start_ms',
        p50: percentile(timings, 50),
        p95: percentile(timings, 95),
        n: timings.length,
      );
    }
  });

  testWidgets('B-Sim-3: Hot restart', (tester) async {
    print('\n${'═' * 60}');
    print('  BENCHMARK: HOT RESTART (B-Sim-3)');
    print('${'═' * 60}\n');

    final node = await createBenchmarkNode();
    await node.startAndWaitOnline();

    // Call startNodeCore again — triggers "already started" resync
    final events = await captureFlowEvents(() async {
      await node.service.startNodeCore(node.privateKey, node.peerId);
    });

    final badge = filterEvents(events, 'TIME_TO_ONLINE_BADGE');
    if (badge.isNotEmpty) {
      final details = badge.first['details'] as Map<String, dynamic>;
      printBenchmarkSingle(
          'sim_hot_restart_ms', details['totalMs'] as int);
      print('[BENCHMARK] sim_hot_restart_phase = ${details['phase']}');
    }

    await node.dispose();
  });
}
