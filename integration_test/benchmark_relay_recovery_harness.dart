/// Simulator Benchmark: Relay Reconnect / Recovery (Test C)
///
/// Measures wall-clock time from relay failure to recovery.
/// Run: flutter test integration_test/benchmark_relay_recovery_harness.dart -d <DEVICE_ID>
@Tags(['device'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/lifecycle/handle_app_resumed.dart';
import 'package:flutter_app/features/p2p/presentation/widgets/connection_status_indicator.dart';

import 'benchmark_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  final relayPeerId = defaultRendezvousAddress.split('/p2p/').last;

  testWidgets('C-Sim-1: Kill relay, measure recovery', (tester) async {
    print('\n${'═' * 60}');
    print('  BENCHMARK: RELAY RECOVERY (C-Sim-1)');
    print('${'═' * 60}\n');

    final node = await createBenchmarkNode();
    final online = await node.startAndWaitOnline();
    expect(online, isTrue, reason: 'Node should reach Online');
    print('[PHASE 1] Node is Online');

    // Disconnect relay peer to simulate relay drop
    print('[PHASE 2] Disconnecting relay peer...');
    final disconnectSw = Stopwatch()..start();
    await node.bridge.send(
      jsonEncode({
        'cmd': 'peer:disconnect',
        'payload': {'peerId': relayPeerId},
      }),
    );

    // Wait for degraded state
    final degraded = await waitFor(
      () =>
          healthFromState(node.service.currentState) != ConnectionHealth.online,
      timeout: const Duration(seconds: 15),
      label: 'Degraded after disconnect',
    );
    disconnectSw.stop();
    print('[PHASE 2] Degraded after ${disconnectSw.elapsedMilliseconds}ms');

    if (!degraded) {
      print('[WARNING] State never went degraded — relay may have reconnected');
      await node.dispose();
      return;
    }

    // Trigger recovery via handleAppResumed
    print('[PHASE 3] Triggering recovery...');
    final recoverySw = Stopwatch()..start();

    final events = await captureFlowEvents(() async {
      await node.service.performImmediateHealthCheck();
    });

    // Wait for online again
    final recovered = await waitForOnline(
      node.service,
      timeout: const Duration(seconds: 30),
    );
    recoverySw.stop();

    if (recovered) {
      printBenchmarkSingle(
        'sim_relay_detection_ms',
        disconnectSw.elapsedMilliseconds,
      );
      printBenchmarkSingle(
        'sim_relay_recovery_ms',
        recoverySw.elapsedMilliseconds,
      );

      // Check for RELAY_OUTAGE_TIMING events
      final outageEvents = filterEvents(events, 'RELAY_OUTAGE_TIMING');
      for (final e in outageEvents) {
        final d = e['details'] as Map<String, dynamic>;
        print(
          '[BENCHMARK] sim_relay_outage_phase=${d['phase']} '
          'ms=${d['recoveryMs'] ?? d['detectionMs'] ?? 'n/a'}',
        );
        if (d['phase'] == 'recovered') {
          print('[BENCHMARK] sim_recovery_source = ${d['recoverySource']}');
          print(
            '[BENCHMARK] sim_recovery_trigger_source = '
            '${d['recoveryTriggerSource']}',
          );
          print('[BENCHMARK] sim_reused_host = ${d['reusedHost']}');
          print(
            '[BENCHMARK] sim_coalesced_recovery_requests = '
            '${d['coalescedRecoveryRequests']}',
          );
          printBenchmarkSingle(
            'sim_relay_refresh_ms',
            (d['relayRefreshMs'] as num).toInt(),
          );
          printBenchmarkSingle(
            'sim_relay_warm_ms',
            (d['relayWarmMs'] as num).toInt(),
          );
          printBenchmarkSingle(
            'sim_reserve_rpc_ms',
            (d['reserveRpcMs'] as num).toInt(),
          );
          printBenchmarkSingle(
            'sim_circuit_address_wait_ms',
            (d['circuitAddressWaitMs'] as num).toInt(),
          );
          print('[BENCHMARK] sim_reservation_path = ${d['reservationPath']}');
          print(
            '[BENCHMARK] sim_reservation_winner_peer = '
            '${d['reservationWinnerPeer'] ?? 'n/a'}',
          );
          printBenchmarkSingle(
            'sim_personal_reregister_ms',
            (d['personalReregisterMs'] as num).toInt(),
          );
        }
      }

      // Check for TIME_TO_ONLINE_BADGE recovery
      final badge = filterEvents(events, 'TIME_TO_ONLINE_BADGE');
      for (final b in badge) {
        final d = b['details'] as Map<String, dynamic>;
        printBenchmarkSingle(
          'sim_recovery_time_to_online_ms',
          d['totalMs'] as int,
        );
      }

      // §24: Widget transition timing
      final widgetBadge = filterEvents(events, 'TIME_TO_ONLINE_BADGE_WIDGET');
      for (final w in widgetBadge) {
        final wd = w['details'] as Map<String, dynamic>;
        if (wd.containsKey('widgetTransitionMs')) {
          printBenchmarkSingle(
            'sim_recovery_widget_transition_ms',
            (wd['widgetTransitionMs'] as num).toInt(),
          );
        }
      }

      // §4: Check for RecoveryWaitTimeout event
      final timeoutEvents = filterEvents(events, 'timeout:fired');
      for (final t in timeoutEvents) {
        final td = t['details'] as Map<String, dynamic>;
        if (td['timeoutName'] == 'RecoveryWaitTimeout') {
          print(
            '[BENCHMARK] sim_recovery_timeout_fired = true '
            'actualMs=${td['actualMs']} configuredMs=${td['configuredMs']}',
          );
        }
      }
    } else {
      print('[WARNING] Did not recover within timeout');
    }

    await node.dispose();
  });

  testWidgets('C-Sim-2: Repeated recovery cycles (3 runs)', (tester) async {
    print('\n${'═' * 60}');
    print('  BENCHMARK: REPEATED RECOVERY (C-Sim-2)');
    print('${'═' * 60}\n');

    final node = await createBenchmarkNode();
    final online = await node.startAndWaitOnline();
    expect(online, isTrue);

    final recoveryTimings = <int>[];

    for (var i = 0; i < 3; i++) {
      print('\n--- Cycle ${i + 1}/3 ---');

      // Disconnect relay
      await node.bridge.send(
        jsonEncode({
          'cmd': 'peer:disconnect',
          'payload': {'peerId': relayPeerId},
        }),
      );

      await waitFor(
        () =>
            healthFromState(node.service.currentState) !=
            ConnectionHealth.online,
        timeout: const Duration(seconds: 15),
        label: 'Degraded cycle ${i + 1}',
      );

      // Recover
      final sw = Stopwatch()..start();
      await node.service.performImmediateHealthCheck();
      final recovered = await waitForOnline(
        node.service,
        timeout: const Duration(seconds: 30),
      );
      sw.stop();

      if (recovered) {
        recoveryTimings.add(sw.elapsedMilliseconds);
        print('[CYCLE ${i + 1}] Recovery: ${sw.elapsedMilliseconds}ms');
      } else {
        print('[CYCLE ${i + 1}] Recovery FAILED');
      }
    }

    if (recoveryTimings.isNotEmpty) {
      recoveryTimings.sort();
      printBenchmark(
        'sim_relay_recovery_ms',
        p50: percentile(recoveryTimings, 50),
        p95: percentile(recoveryTimings, 95),
        n: recoveryTimings.length,
      );
    }

    await node.dispose();
  });
}
