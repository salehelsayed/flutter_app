/// Simulator Benchmark: Time-to-Sendable and Relay-Ready Badge (Test M)
///
/// Measures the user-visible latency from app launch to:
/// - the first truthful usable green badge (`Online`)
/// - the dotted relay-ready upgrade (`Online.`), when different
@Tags(['device'])
library;

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
    print('[BENCHMARK] ${prefix}_first_send_trigger = ${firstSend['trigger']}');
  }

  if (firstInbox != null) {
    printBenchmarkSingle(
      '${prefix}_to_first_inbox_success_ms',
      firstInbox['totalMs'] as int,
    );
    print('[BENCHMARK] ${prefix}_first_inbox_source = ${firstInbox['source']}');
    print(
      '[BENCHMARK] ${prefix}_first_inbox_trigger = ${firstInbox['trigger']}',
    );
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

  testWidgets('M-Sim-1: Cold start — wall-clock to sendable badge', (
    tester,
  ) async {
    print('\n${'═' * 60}');
    print('  BENCHMARK: TIME-TO-SENDABLE BADGE (M-Sim-1)');
    print('${'═' * 60}\n');

    final node = await createBenchmarkNode();

    final events = await captureFlowEventsUntil(
      () async {
        await node.startAndWaitSendable(timeout: const Duration(seconds: 30));
        await waitForRelayReadyBadge(
          node.service,
          timeout: const Duration(seconds: 5),
        );
      },
      postActionTimeout: const Duration(milliseconds: 200),
      until: (captured) {
        return firstEventDetails(
              captured,
              'TIME_TO_SENDABLE_BADGE',
              phase: 'cold_start',
            ) !=
            null;
      },
    );

    final sendable = _requirePhaseEvent(
      events,
      'TIME_TO_SENDABLE_BADGE',
      phase: 'cold_start',
    );
    _printPhase6Metrics('sim_cold_start', events, phase: 'cold_start');

    expect(
      sendable['totalMs'],
      lessThan(6000),
      reason: 'User-perceived sendable startup should be < 6s',
    );

    await node.dispose();
  });

  testWidgets('M-Sim-Hot: Hot restart — resync to sendable badge', (
    tester,
  ) async {
    print('\n${'═' * 60}');
    print('  BENCHMARK: HOT RESTART TO SENDABLE BADGE (M-Sim-Hot)');
    print('${'═' * 60}\n');

    final node = await createBenchmarkNode();
    await node.startAndWaitRelayReady();
    print('[PHASE 1] Online.');

    final events = await captureFlowEventsUntil(
      () async {
        await node.service.startNode(node.privateKey, node.peerId);
        await waitForSendableBadge(
          node.service,
          timeout: const Duration(seconds: 10),
        );
        await waitForRelayReadyBadge(
          node.service,
          timeout: const Duration(seconds: 10),
        );
      },
      postActionTimeout: const Duration(milliseconds: 200),
      until: (captured) {
        return firstEventDetails(
              captured,
              'TIME_TO_SENDABLE_BADGE',
              phase: 'hot_restart',
            ) !=
            null;
      },
    );

    _printPhase6Metrics('sim_hot_restart', events, phase: 'hot_restart');

    await node.dispose();
  });

  testWidgets('M-Sim-2: Recovery — wall-clock from degraded to usable badge', (
    tester,
  ) async {
    print('\n${'═' * 60}');
    print('  BENCHMARK: RECOVERY TO SENDABLE BADGE (M-Sim-2)');
    print('${'═' * 60}\n');

    final node = await createBenchmarkNode();
    await node.startAndWaitRelayReady();
    print('[PHASE 1] Online.');

    await node.bridge.send(
      '{"cmd":"peer:disconnect","payload":{"peerId":"$relayPeerId"}}',
    );

    await waitFor(
      () => !isRelayReadyBadgeState(node.service.currentState),
      timeout: const Duration(seconds: 15),
      label: 'Degraded to non-dotted badge',
    );
    print('[PHASE 2] Relay-ready lost');

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

    _printPhase6Metrics('sim_recovery', events, phase: 'recovery');

    await node.dispose();
  });

  testWidgets('M-Sim-3: 5 cold starts for sendable-source distribution', (
    tester,
  ) async {
    print('\n${'═' * 60}');
    print('  BENCHMARK: SENDABLE SOURCE DISTRIBUTION (M-Sim-3)');
    print('${'═' * 60}\n');

    final sources = <String, int>{};
    final timings = <int>[];
    final relayGaps = <int>[];

    for (var i = 0; i < 5; i++) {
      print('\n--- Run ${i + 1}/5 ---');
      final node = await createBenchmarkNode();

      final events = await captureFlowEventsUntil(
        () async {
          await node.startAndWaitSendable(timeout: const Duration(seconds: 30));
          await waitForRelayReadyBadge(
            node.service,
            timeout: const Duration(seconds: 5),
          );
        },
        postActionTimeout: const Duration(milliseconds: 200),
        until: (captured) {
          return firstEventDetails(
                captured,
                'TIME_TO_SENDABLE_BADGE',
                phase: 'cold_start',
              ) !=
              null;
        },
      );

      final sendable = _requirePhaseEvent(
        events,
        'TIME_TO_SENDABLE_BADGE',
        phase: 'cold_start',
      );
      final source = sendable['source'] as String;
      sources[source] = (sources[source] ?? 0) + 1;
      timings.add(sendable['totalMs'] as int);

      final relayGap = phaseEventGapMs(
        events,
        phase: 'cold_start',
        earlierEvent: 'TIME_TO_SENDABLE_BADGE',
        laterEvent: 'TIME_TO_RELAY_READY_BADGE',
      );
      if (relayGap != null) {
        relayGaps.add(relayGap);
      }

      print(
        '[RUN ${i + 1}] source=$source sendableMs=${sendable['totalMs']} '
        'relayGapMs=${relayGap ?? 'n/a'}',
      );

      await node.dispose();
    }

    final distribution = sources.entries
        .map((entry) => '${entry.key}=${entry.value}')
        .join(' ');
    print('\n[BENCHMARK] sim_sendable_source_distribution $distribution');

    if (timings.isNotEmpty) {
      timings.sort();
      printBenchmark(
        'sim_time_to_sendable_ms',
        p50: percentile(timings, 50),
        p95: percentile(timings, 95),
        n: timings.length,
      );
    }

    if (relayGaps.isNotEmpty) {
      relayGaps.sort();
      printBenchmark(
        'sim_sendable_to_relay_ready_gap_ms',
        p50: percentile(relayGaps, 50),
        p95: percentile(relayGaps, 95),
        n: relayGaps.length,
      );
    }
  });
}
