/// Simulator Benchmark: Relay Reconnect / Recovery (Test C)
///
/// Measures wall-clock time from relay failure to:
/// - the usable sendable badge returning
/// - the dotted relay-ready badge returning
@Tags(['device'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';

import 'benchmark_helpers.dart';

Map<String, dynamic> _requirePhaseEvent(
  List<Map<String, dynamic>> events,
  String eventName, {
  required String phase,
}) {
  final details = firstEventDetails(events, eventName, phase: phase);
  expect(details, isNotNull, reason: 'Missing $eventName for phase=$phase');
  return details!;
}

void _printPhase6Metrics(
  String prefix,
  List<Map<String, dynamic>> events, {
  required String phase,
}) {
  final sendable = _requirePhaseEvent(
    events,
    'TIME_TO_SENDABLE_BADGE',
    phase: phase,
  );
  final relayReady = firstEventDetails(
    events,
    'TIME_TO_RELAY_READY_BADGE',
    phase: phase,
  );
  final firstSend = firstEventDetails(
    events,
    'FIRST_SEND_SUCCESS_IN_WINDOW',
    phase: phase,
  );
  final firstInbox = firstEventDetails(
    events,
    'FIRST_INBOX_SUCCESS_IN_WINDOW',
    phase: phase,
  );

  printBenchmarkSingle('${prefix}_to_sendable_ms', sendable['totalMs'] as int);
  print('[BENCHMARK] ${prefix}_sendable_source = ${sendable['source']}');
  print(
    '[BENCHMARK] ${prefix}_sendable_send_source = '
    '${sendable['sendProofSource'] ?? 'n/a'}',
  );
  print(
    '[BENCHMARK] ${prefix}_sendable_inbox_source = '
    '${sendable['inboxProofSource'] ?? 'n/a'}',
  );

  if (relayReady != null) {
    printBenchmarkSingle(
      '${prefix}_to_relay_ready_ms',
      relayReady['totalMs'] as int,
    );
    print('[BENCHMARK] ${prefix}_relay_ready_source = ${relayReady['source']}');
  }

  if (firstSend != null) {
    printBenchmarkSingle(
      '${prefix}_to_first_send_success_ms',
      firstSend['totalMs'] as int,
    );
    print('[BENCHMARK] ${prefix}_first_send_source = ${firstSend['source']}');
    print(
      '[BENCHMARK] ${prefix}_first_send_path = '
      '${firstSend['sendPath'] ?? 'n/a'}',
    );
  }

  if (firstInbox != null) {
    printBenchmarkSingle(
      '${prefix}_to_first_inbox_success_ms',
      firstInbox['totalMs'] as int,
    );
    print('[BENCHMARK] ${prefix}_first_inbox_source = ${firstInbox['source']}');
  }

  final relayGap = phaseEventGapMs(
    events,
    phase: phase,
    earlierEvent: 'TIME_TO_SENDABLE_BADGE',
    laterEvent: 'TIME_TO_RELAY_READY_BADGE',
  );
  if (relayGap != null) {
    printBenchmarkSingle('${prefix}_sendable_to_relay_ready_gap_ms', relayGap);
  }

  final honestyGap = badgeHonestyGapMs(events, phase: phase);
  if (honestyGap != null) {
    printBenchmarkSingle('${prefix}_badge_honesty_gap_ms', honestyGap);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  final relayPeerId = defaultRendezvousAddress.split('/p2p/').last;

  testWidgets('C-Sim-1: Kill relay, measure usable and relay-ready recovery', (
    tester,
  ) async {
    print('\n${'═' * 60}');
    print('  BENCHMARK: RELAY RECOVERY (C-Sim-1)');
    print('${'═' * 60}\n');

    final node = await createBenchmarkNode();
    final ready = await node.startAndWaitRelayReady();
    expect(ready, isTrue, reason: 'Node should reach Online.');
    print('[PHASE 1] Node is Online.');

    print('[PHASE 2] Disconnecting relay peer...');
    final disconnectSw = Stopwatch()..start();
    await node.bridge.send(
      jsonEncode({
        'cmd': 'peer:disconnect',
        'payload': {'peerId': relayPeerId},
      }),
    );

    final degraded = await waitFor(
      () => !isRelayReadyBadgeState(node.service.currentState),
      timeout: const Duration(seconds: 15),
      label: 'Lost dotted relay-ready badge',
    );
    disconnectSw.stop();
    print(
      '[PHASE 2] Relay-ready lost after ${disconnectSw.elapsedMilliseconds}ms',
    );

    if (!degraded) {
      print('[WARNING] Dotted state never dropped after disconnect');
      await node.dispose();
      return;
    }

    print('[PHASE 3] Triggering recovery...');
    final recoverySw = Stopwatch()..start();

    final events = await captureFlowEventsUntil(
      () async {
        await node.service.performImmediateHealthCheck();
        await node.service.drainOfflineInbox();
        await waitForSendableBadge(
          node.service,
          timeout: const Duration(seconds: 30),
        );
        await waitForRelayReadyBadge(
          node.service,
          timeout: const Duration(seconds: 30),
        );
      },
      postActionTimeout: const Duration(milliseconds: 200),
      until: (captured) {
        return firstEventDetails(
              captured,
              'TIME_TO_RELAY_READY_BADGE',
              phase: 'recovery',
            ) !=
            null;
      },
    );
    recoverySw.stop();

    printBenchmarkSingle(
      'sim_relay_detection_ms',
      disconnectSw.elapsedMilliseconds,
    );
    printBenchmarkSingle(
      'sim_relay_recovery_wall_clock_ms',
      recoverySw.elapsedMilliseconds,
    );

    _printPhase6Metrics('sim_recovery', events, phase: 'recovery');

    final outageEvents = filterEvents(events, 'RELAY_OUTAGE_TIMING');
    for (final event in outageEvents) {
      final details = event['details'] as Map<String, dynamic>;
      print(
        '[BENCHMARK] sim_relay_outage_phase=${details['phase']} '
        'ms=${details['recoveryMs'] ?? details['detectionMs'] ?? 'n/a'}',
      );
      if (details['phase'] == 'recovered') {
        print('[BENCHMARK] sim_recovery_source = ${details['recoverySource']}');
        print(
          '[BENCHMARK] sim_recovery_trigger_source = '
          '${details['recoveryTriggerSource']}',
        );
        print('[BENCHMARK] sim_reused_host = ${details['reusedHost']}');
        print(
          '[BENCHMARK] sim_coalesced_recovery_requests = '
          '${details['coalescedRecoveryRequests']}',
        );
        printBenchmarkSingle(
          'sim_relay_refresh_ms',
          (details['relayRefreshMs'] as num).toInt(),
        );
        printBenchmarkSingle(
          'sim_relay_warm_ms',
          (details['relayWarmMs'] as num).toInt(),
        );
        printBenchmarkSingle(
          'sim_reserve_rpc_ms',
          (details['reserveRpcMs'] as num).toInt(),
        );
        printBenchmarkSingle(
          'sim_relay_warm_parallelism',
          (details['relayWarmParallelism'] as num?)?.toInt() ?? 0,
        );
        print(
          '[BENCHMARK] sim_foreground_recovery_path = '
          '${details['foregroundRecoveryPath'] ?? 'n/a'}',
        );
        printBenchmarkSingle(
          'sim_foreground_relay_dial_timeout_ms',
          (details['foregroundRelayDialTimeoutMs'] as num?)?.toInt() ?? 0,
        );
        printBenchmarkSingle(
          'sim_autorelay_retry_cadence_ms',
          (details['autorelayRetryCadenceMs'] as num?)?.toInt() ?? 0,
        );
        printBenchmarkSingle(
          'sim_circuit_address_wait_ms',
          (details['circuitAddressWaitMs'] as num).toInt(),
        );
        print(
          '[BENCHMARK] sim_reservation_path = ${details['reservationPath']}',
        );
        print(
          '[BENCHMARK] sim_reservation_winner_peer = '
          '${details['reservationWinnerPeer'] ?? 'n/a'}',
        );
        printBenchmarkSingle(
          'sim_personal_reregister_ms',
          (details['personalReregisterMs'] as num).toInt(),
        );
      }
    }

    final timeoutEvents = filterEvents(events, 'timeout:fired');
    for (final event in timeoutEvents) {
      final details = event['details'] as Map<String, dynamic>;
      if (details['timeoutName'] == 'RecoveryWaitTimeout') {
        print(
          '[BENCHMARK] sim_recovery_timeout_fired = true '
          'actualMs=${details['actualMs']} configuredMs=${details['configuredMs']}',
        );
      }
    }

    await node.dispose();
  });

  testWidgets('C-Sim-2: Repeated recovery cycles (3 runs)', (tester) async {
    print('\n${'═' * 60}');
    print('  BENCHMARK: REPEATED RECOVERY (C-Sim-2)');
    print('${'═' * 60}\n');

    final node = await createBenchmarkNode();
    final ready = await node.startAndWaitRelayReady();
    expect(ready, isTrue);

    final sendableTimings = <int>[];
    final relayReadyTimings = <int>[];

    for (var i = 0; i < 3; i++) {
      print('\n--- Cycle ${i + 1}/3 ---');

      await node.bridge.send(
        jsonEncode({
          'cmd': 'peer:disconnect',
          'payload': {'peerId': relayPeerId},
        }),
      );

      await waitFor(
        () => !isRelayReadyBadgeState(node.service.currentState),
        timeout: const Duration(seconds: 15),
        label: 'Lost dotted state cycle ${i + 1}',
      );

      final events = await captureFlowEventsUntil(
        () async {
          await node.service.performImmediateHealthCheck();
          await node.service.drainOfflineInbox();
          await waitForSendableBadge(
            node.service,
            timeout: const Duration(seconds: 30),
          );
          await waitForRelayReadyBadge(
            node.service,
            timeout: const Duration(seconds: 30),
          );
        },
        postActionTimeout: const Duration(milliseconds: 200),
        until: (captured) {
          return firstEventDetails(
                captured,
                'TIME_TO_RELAY_READY_BADGE',
                phase: 'recovery',
              ) !=
              null;
        },
      );

      final sendable = _requirePhaseEvent(
        events,
        'TIME_TO_SENDABLE_BADGE',
        phase: 'recovery',
      );
      final relayReady = _requirePhaseEvent(
        events,
        'TIME_TO_RELAY_READY_BADGE',
        phase: 'recovery',
      );

      sendableTimings.add(sendable['totalMs'] as int);
      relayReadyTimings.add(relayReady['totalMs'] as int);
      print(
        '[CYCLE ${i + 1}] sendable=${sendable['totalMs']}ms '
        'relayReady=${relayReady['totalMs']}ms',
      );
    }

    if (sendableTimings.isNotEmpty) {
      sendableTimings.sort();
      printBenchmark(
        'sim_recovery_to_sendable_ms',
        p50: percentile(sendableTimings, 50),
        p95: percentile(sendableTimings, 95),
        n: sendableTimings.length,
      );
    }

    if (relayReadyTimings.isNotEmpty) {
      relayReadyTimings.sort();
      printBenchmark(
        'sim_recovery_to_relay_ready_ms',
        p50: percentile(relayReadyTimings, 50),
        p95: percentile(relayReadyTimings, 95),
        n: relayReadyTimings.length,
      );
    }

    await node.dispose();
  });
}
