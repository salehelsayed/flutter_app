/// Simulator Benchmark: Time-to-Online Badge (Test M)
///
/// Measures the full user-perceived latency from app launch to green badge.
/// Run: flutter test integration_test/benchmark_time_to_online_harness.dart -d <DEVICE_ID>
@Tags(['device'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/features/p2p/presentation/widgets/connection_status_indicator.dart';

import 'benchmark_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  final relayPeerId = defaultRendezvousAddress.split('/p2p/').last;

  testWidgets('M-Sim-1: Cold start — wall-clock to green badge',
      (tester) async {
    print('\n${'═' * 60}');
    print('  BENCHMARK: TIME-TO-ONLINE BADGE (M-Sim-1)');
    print('${'═' * 60}\n');

    final node = await createBenchmarkNode();

    final events = await captureFlowEvents(() async {
      await node.startAndWaitOnline(timeout: const Duration(seconds: 30));
    });

    final badge = filterEvents(events, 'TIME_TO_ONLINE_BADGE');
    expect(badge, isNotEmpty, reason: 'Should emit TIME_TO_ONLINE_BADGE');

    final details = badge.first['details'] as Map<String, dynamic>;
    final totalMs = details['totalMs'] as int;

    printBenchmarkSingle('sim_time_to_online_badge_ms', totalMs);
    print('[BENCHMARK] sim_time_to_online_source = ${details['source']}');
    print('[BENCHMARK] sim_time_to_online_phase = ${details['phase']}');

    // §24: Widget transition timing
    final widgetBadge = filterEvents(events, 'TIME_TO_ONLINE_BADGE_WIDGET');
    for (final e in widgetBadge) {
      final wd = e['details'] as Map<String, dynamic>;
      if (wd.containsKey('widgetTransitionMs')) {
        printBenchmarkSingle(
            'sim_time_to_online_widget_ms',
            (wd['widgetTransitionMs'] as num).toInt());
      }
    }

    // Total user-perceived = badge + widget
    if (widgetBadge.isNotEmpty) {
      final widgetMs = (widgetBadge.first['details']
          as Map<String, dynamic>)['widgetTransitionMs'] as num?;
      if (widgetMs != null) {
        printBenchmarkSingle(
            'sim_time_to_online_total_ms', totalMs + widgetMs.toInt());
      }
    }

    expect(totalMs, lessThan(6000),
        reason: 'User-perceived startup should be < 6s');

    await node.dispose();
  });

  testWidgets('M-Sim-Hot: Hot restart — resync to green badge',
      (tester) async {
    print('\n${'═' * 60}');
    print('  BENCHMARK: HOT RESTART (M-Sim-Hot)');
    print('${'═' * 60}\n');

    final node = await createBenchmarkNode();
    await node.startAndWaitOnline();
    print('[PHASE 1] Online');

    // Call startNodeCore again — triggers "already started" resync path
    final events = await captureFlowEvents(() async {
      await node.service.startNodeCore(node.privateKey, node.peerId);
    });

    final badge = filterEvents(events, 'TIME_TO_ONLINE_BADGE');
    if (badge.isNotEmpty) {
      final d = badge.first['details'] as Map<String, dynamic>;
      printBenchmarkSingle(
          'sim_hot_restart_ms', d['totalMs'] as int);
      print('[BENCHMARK] sim_hot_restart_phase = ${d['phase']}');
      print('[BENCHMARK] sim_hot_restart_source = ${d['source']}');
    } else {
      print('[NOTE] No TIME_TO_ONLINE_BADGE on hot restart '
          '(may already be online)');
    }

    await node.dispose();
  });

  testWidgets('M-Sim-2: Recovery — wall-clock from degraded to green',
      (tester) async {
    print('\n${'═' * 60}');
    print('  BENCHMARK: RECOVERY TO ONLINE (M-Sim-2)');
    print('${'═' * 60}\n');

    final node = await createBenchmarkNode();
    await node.startAndWaitOnline();
    print('[PHASE 1] Online');

    // Disconnect relay
    await node.bridge.send(
      '{"cmd":"peer:disconnect","payload":{"peerId":"$relayPeerId"}}',
    );

    await waitFor(
      () =>
          healthFromState(node.service.currentState) !=
          ConnectionHealth.online,
      timeout: const Duration(seconds: 15),
      label: 'Degraded',
    );
    print('[PHASE 2] Degraded');

    // Recover
    final events = await captureFlowEvents(() async {
      await node.service.performImmediateHealthCheck();
      await waitForOnline(node.service, timeout: const Duration(seconds: 30));
    });

    final badge = filterEvents(events, 'TIME_TO_ONLINE_BADGE');
    if (badge.isNotEmpty) {
      final d = badge.first['details'] as Map<String, dynamic>;
      printBenchmarkSingle('sim_recovery_to_online_badge_ms', d['totalMs'] as int);
    }

    await node.dispose();
  });

  testWidgets('M-Sim-3: 5 cold starts for source distribution',
      (tester) async {
    print('\n${'═' * 60}');
    print('  BENCHMARK: SOURCE DISTRIBUTION (M-Sim-3)');
    print('${'═' * 60}\n');

    final sources = <String, int>{};
    final timings = <int>[];

    for (var i = 0; i < 5; i++) {
      print('\n--- Run ${i + 1}/5 ---');
      final node = await createBenchmarkNode();

      final events = await captureFlowEvents(() async {
        await node.startAndWaitOnline(timeout: const Duration(seconds: 30));
      });

      final badge = filterEvents(events, 'TIME_TO_ONLINE_BADGE');
      if (badge.isNotEmpty) {
        final d = badge.first['details'] as Map<String, dynamic>;
        final source = d['source'] as String;
        sources[source] = (sources[source] ?? 0) + 1;
        timings.add(d['totalMs'] as int);
        print('[RUN ${i + 1}] source=$source totalMs=${d['totalMs']}');
      }

      await node.dispose();
    }

    final distribution = sources.entries
        .map((e) => '${e.key}=${e.value}')
        .join(' ');
    print('\n[BENCHMARK] sim_online_source_distribution $distribution');

    if (timings.isNotEmpty) {
      timings.sort();
      printBenchmark(
        'sim_time_to_online_ms',
        p50: percentile(timings, 50),
        p95: percentile(timings, 95),
        n: timings.length,
      );
    }
  });
}
