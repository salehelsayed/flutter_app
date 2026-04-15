/// Simulator Benchmark: Bridge Crossing (Test F)
///
/// Measures the raw round-trip latency of Dart→Go→Dart bridge calls
/// using the real MethodChannel and Go native library.
/// Collects BRIDGE_CALL_TIMING events from FLOW log for accurate measurement.
/// Run: flutter test integration_test/benchmark_bridge_crossing_harness.dart -d <DEVICE_ID>
@Tags(['device'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/bridge/go_bridge_client.dart';

import 'benchmark_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  testWidgets('F-Sim-1: 1000 round-trip bridge calls', (tester) async {
    print('\n${'═' * 60}');
    print('  BENCHMARK: BRIDGE CROSSING (F-Sim-1)');
    print('${'═' * 60}\n');

    final bridge = GoBridgeClient();
    await bridge.initialize();

    // Generate identity so node:status has something to report
    await bridge.send(
      jsonEncode({'cmd': 'identity.generate', 'payload': {}}),
    );

    const iterations = 1000;

    print('[PHASE 1] Running $iterations sequential bridge round-trips...');
    print('[PHASE 1] Collecting BRIDGE_CALL_TIMING from FLOW log...');
    final overallSw = Stopwatch()..start();

    // Capture BRIDGE_CALL_TIMING events from the FLOW log
    final events = await captureFlowEvents(() async {
      for (var i = 0; i < iterations; i++) {
        await bridge.send(
            jsonEncode({'cmd': 'node:status', 'payload': {}}));
      }
    });
    overallSw.stop();

    // §14: Extract bridgeMs from BRIDGE_CALL_TIMING events
    final bridgeTimings = filterEvents(events, 'BRIDGE_CALL_TIMING');
    print('[PHASE 1] Captured ${bridgeTimings.length} BRIDGE_CALL_TIMING '
        'events in ${overallSw.elapsedMilliseconds}ms');

    if (bridgeTimings.isNotEmpty) {
      final bridgeMsList = bridgeTimings
          .map((e) =>
              ((e['details'] as Map<String, dynamic>)['bridgeMs'] as num)
                  .toInt())
          .toList()
        ..sort();

      final p50 = percentile(bridgeMsList, 50);
      final p95 = percentile(bridgeMsList, 95);
      final p99 = percentile(bridgeMsList, 99);

      print('\n--- Results (from BRIDGE_CALL_TIMING events) ---');
      print(
        '[BENCHMARK] sim_bridge_crossing_ms '
        'p50=${p50}ms p95=${p95}ms p99=${p99}ms (n=${bridgeMsList.length})',
      );

      // Also verify outcomes
      final outcomes = <String, int>{};
      for (final e in bridgeTimings) {
        final outcome =
            (e['details'] as Map<String, dynamic>)['outcome'] as String;
        outcomes[outcome] = (outcomes[outcome] ?? 0) + 1;
      }
      print('[BENCHMARK] sim_bridge_outcomes = $outcomes');

      expect(p99, lessThan(50),
          reason: 'p99 bridge crossing should be < 50ms on simulator');
    } else {
      print('[WARNING] No BRIDGE_CALL_TIMING events captured');

      // Fallback: use Stopwatch timing
      final fallbackTimings = <int>[];
      for (var i = 0; i < 100; i++) {
        final sw = Stopwatch()..start();
        await bridge.send(
            jsonEncode({'cmd': 'node:status', 'payload': {}}));
        sw.stop();
        fallbackTimings.add(sw.elapsedMilliseconds);
      }
      fallbackTimings.sort();
      print(
        '[BENCHMARK] sim_bridge_crossing_fallback_ms '
        'p50=${percentile(fallbackTimings, 50)}ms '
        'p95=${percentile(fallbackTimings, 95)}ms (n=100)',
      );
    }

    print(
      '[BENCHMARK] sim_bridge_total_ms = ${overallSw.elapsedMilliseconds}ms '
      '(avg=${(overallSw.elapsedMilliseconds / iterations).toStringAsFixed(1)}ms)',
    );

    bridge.dispose();
  });
}
