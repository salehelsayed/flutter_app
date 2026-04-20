/// Simulator Benchmark: Background Resume to Sendable and Relay-Ready Badge
///
/// Exercises the production Phase 6 readiness timing on a real bridge-backed
/// node across healthy resume, degraded resume with recovery, and an extended
/// background window.
@Tags(['device'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/lifecycle/handle_app_paused.dart';
import 'package:flutter_app/core/lifecycle/handle_app_resumed.dart';

import '../test/shared/fakes/in_memory_message_repository.dart';
import 'benchmark_helpers.dart';

final _relayPeerId = defaultRendezvousAddress.split('/p2p/').last;

Map<String, dynamic> _requirePhaseEvent(
  List<Map<String, dynamic>> events,
  String eventName, {
  required String phase,
}) {
  final details = firstEventDetails(events, eventName, phase: phase);
  expect(details, isNotNull, reason: 'Missing $eventName for phase=$phase');
  return details!;
}

Map<String, dynamic>? _maybeFindRecoveryStart(
  List<Map<String, dynamic>> events,
) {
  return firstEventDetails(events, 'RELAY_RECOVERY_START');
}

Map<String, dynamic> _findRecoveredOutage(List<Map<String, dynamic>> events) {
  final matches = filterEvents(events, 'RELAY_OUTAGE_TIMING')
      .where(
        (event) =>
            (event['details'] as Map<String, dynamic>)['phase'] == 'recovered',
      )
      .toList(growable: false);
  expect(matches, isNotEmpty, reason: 'Missing recovered RELAY_OUTAGE_TIMING');
  return matches.first['details'] as Map<String, dynamic>;
}

Map<String, dynamic>? _maybeFindResumeComplete(
  List<Map<String, dynamic>> events,
) {
  return firstEventDetails(events, 'APP_LIFECYCLE_RESUME_COMPLETE');
}

String? _resolvePhase6Phase(
  List<Map<String, dynamic>> events,
  List<String> preferredPhases,
) {
  for (final phase in preferredPhases) {
    if (firstEventDetails(events, 'TIME_TO_SENDABLE_BADGE', phase: phase) !=
        null) {
      return phase;
    }
  }
  return null;
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

  testWidgets(
    'BR-S1: Healthy resume keeps the already-online compatibility signal',
    (tester) async {
      print('\n${'═' * 60}');
      print('  BENCHMARK: BACKGROUND RESUME — HEALTHY RELAY (BR-S1)');
      print('${'═' * 60}\n');

      final node = await createBenchmarkNode();
      final messageRepo = InMemoryMessageRepository();

      try {
        final ready = await node.startAndWaitRelayReady();
        expect(ready, isTrue, reason: 'Node should reach Online.');

        await handleAppPaused(messageRepo: messageRepo);

        final events = await captureFlowEvents(() async {
          node.service.markResumeStarted();
          node.service.checkResumeAlreadyOnline();
        });

        final badge = firstEventDetails(
          events,
          'TIME_TO_ONLINE_BADGE',
          phase: 'background_resume_already_online',
        );
        expect(
          badge,
          isNotNull,
          reason: 'Healthy resume should stay already-online',
        );
        printBenchmarkSingle(
          'sim_background_resume_already_online_ms',
          badge!['totalMs'] as int,
        );
        print(
          '[BENCHMARK] sim_background_resume_already_online_source = '
          '${badge['source']}',
        );
      } finally {
        await node.dispose();
      }
    },
  );

  testWidgets('BR-S2: Degraded resume records sendable and relay-ready split', (
    tester,
  ) async {
    print('\n${'═' * 60}');
    print('  BENCHMARK: BACKGROUND RESUME — DEGRADED RELAY (BR-S2)');
    print('${'═' * 60}\n');

    final node = await createBenchmarkNode();
    final messageRepo = InMemoryMessageRepository();

    try {
      final ready = await node.startAndWaitRelayReady();
      expect(ready, isTrue, reason: 'Node should reach Online.');

      await handleAppPaused(messageRepo: messageRepo);

      await node.bridge.send(
        jsonEncode({
          'cmd': 'peer:disconnect',
          'payload': {'peerId': _relayPeerId},
        }),
      );
      final degraded = await waitFor(
        () => !isRelayReadyBadgeState(node.service.currentState),
        timeout: const Duration(seconds: 15),
        label: 'Degraded before resume benchmark',
      );
      expect(
        degraded,
        isTrue,
        reason: 'Relay drop should remove dotted readiness',
      );

      final events = await captureFlowEventsUntil(
        () async {
          node.service.markResumeStarted();
          await handleAppResumed(bridge: node.bridge, p2pService: node.service);
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
                    phase: 'background_resume',
                  ) !=
                  null ||
              firstEventDetails(
                    captured,
                    'TIME_TO_RELAY_READY_BADGE',
                    phase: 'recovery',
                  ) !=
                  null;
        },
      );

      final phase = _resolvePhase6Phase(events, [
        'background_resume',
        'recovery',
      ]);
      expect(
        phase,
        isNotNull,
        reason: 'Degraded resume should emit Phase 6 timing',
      );
      print('[BENCHMARK] sim_background_resume_phase = $phase');
      _printPhase6Metrics(
        'sim_background_resume',
        events,
        phase: phase!,
      );

      final recovered = _findRecoveredOutage(events);
      final recoveryStart = _maybeFindRecoveryStart(events);
      final resumeComplete = _maybeFindResumeComplete(events);
      if (recoveryStart != null &&
          recoveryStart['resumeToRecoveryStartMs'] != null) {
        printBenchmarkSingle(
          'sim_background_resume_to_recovery_start_ms',
          (recoveryStart['resumeToRecoveryStartMs'] as num).toInt(),
        );
      }
      print(
        '[BENCHMARK] sim_background_resume_recovery_start_source = '
        '${recoveryStart?['recoverySource'] ?? recovered['recoveryTriggerSource']}',
      );
      print(
        '[BENCHMARK] sim_background_resume_recovery_source = '
        '${recovered['recoverySource']}',
      );
      print(
        '[BENCHMARK] sim_background_resume_reused_host = ${recovered['reusedHost']}',
      );
      print(
        '[BENCHMARK] sim_background_resume_coalesced_recovery_requests = '
        '${recovered['coalescedRecoveryRequests']}',
      );
      printBenchmarkSingle(
        'sim_background_resume_relay_refresh_ms',
        (recovered['relayRefreshMs'] as num).toInt(),
      );
      printBenchmarkSingle(
        'sim_background_resume_relay_warm_ms',
        (recovered['relayWarmMs'] as num).toInt(),
      );
      printBenchmarkSingle(
        'sim_background_resume_reserve_rpc_ms',
        (recovered['reserveRpcMs'] as num).toInt(),
      );
      printBenchmarkSingle(
        'sim_background_resume_relay_warm_parallelism',
        (recovered['relayWarmParallelism'] as num?)?.toInt() ?? 0,
      );
      print(
        '[BENCHMARK] sim_background_resume_foreground_recovery_path = '
        '${recovered['foregroundRecoveryPath'] ?? 'n/a'}',
      );
      printBenchmarkSingle(
        'sim_background_resume_foreground_relay_dial_timeout_ms',
        (recovered['foregroundRelayDialTimeoutMs'] as num?)?.toInt() ?? 0,
      );
      printBenchmarkSingle(
        'sim_background_resume_autorelay_retry_cadence_ms',
        (recovered['autorelayRetryCadenceMs'] as num?)?.toInt() ?? 0,
      );
      printBenchmarkSingle(
        'sim_background_resume_circuit_address_wait_ms',
        (recovered['circuitAddressWaitMs'] as num).toInt(),
      );
      print(
        '[BENCHMARK] sim_background_resume_reservation_path = '
        '${recovered['reservationPath']}',
      );
      print(
        '[BENCHMARK] sim_background_resume_reservation_winner_peer = '
        '${recovered['reservationWinnerPeer'] ?? 'n/a'}',
      );
      printBenchmarkSingle(
        'sim_background_resume_personal_reregister_ms',
        (recovered['personalReregisterMs'] as num).toInt(),
      );
      if (resumeComplete?['groupReregisterMs'] != null) {
        printBenchmarkSingle(
          'sim_background_resume_group_reregister_ms',
          (resumeComplete!['groupReregisterMs'] as num).toInt(),
        );
      }
    } finally {
      await node.dispose();
    }
  });

  testWidgets('BR-S3: Resume after extended background (30s)', (tester) async {
    print('\n${'═' * 60}');
    print('  BENCHMARK: BACKGROUND RESUME — EXTENDED 30S (BR-S3)');
    print('${'═' * 60}\n');

    final node = await createBenchmarkNode();
    final messageRepo = InMemoryMessageRepository();

    try {
      final ready = await node.startAndWaitRelayReady();
      expect(ready, isTrue, reason: 'Node should reach Online.');

      await handleAppPaused(messageRepo: messageRepo);
      print('[PHASE] Holding the app backgrounded for 30 seconds...');
      await Future<void>.delayed(const Duration(seconds: 30));

      final events = await captureFlowEventsUntil(
        () async {
          node.service.markResumeStarted();
          await handleAppResumed(bridge: node.bridge, p2pService: node.service);
          node.service.checkResumeAlreadyOnline();
          await waitForSendableBadge(
            node.service,
            timeout: const Duration(seconds: 30),
          );
        },
        postActionTimeout: const Duration(milliseconds: 200),
        until: (captured) {
          return firstEventDetails(
                    captured,
                    'TIME_TO_SENDABLE_BADGE',
                    phase: 'background_resume',
                  ) !=
                  null ||
              firstEventDetails(
                    captured,
                    'TIME_TO_SENDABLE_BADGE',
                    phase: 'recovery',
                  ) !=
                  null ||
              firstEventDetails(
                    captured,
                    'TIME_TO_ONLINE_BADGE',
                    phase: 'background_resume_already_online',
                  ) !=
                  null ||
              false;
        },
      );

      final phase = _resolvePhase6Phase(events, [
        'background_resume',
        'recovery',
      ]);
      if (phase != null) {
        print('[BENCHMARK] sim_background_resume_extended_phase = $phase');
        _printPhase6Metrics(
          'sim_background_resume_extended',
          events,
          phase: phase,
        );
      } else {
        final alreadyOnline = firstEventDetails(
          events,
          'TIME_TO_ONLINE_BADGE',
          phase: 'background_resume_already_online',
        );
        expect(
          alreadyOnline,
          isNotNull,
          reason:
              'Extended resume should emit either sendable or already-online timing',
        );
        printBenchmarkSingle(
          'sim_background_resume_extended_ms',
          alreadyOnline!['totalMs'] as int,
        );
        print(
          '[BENCHMARK] sim_background_resume_extended_source = '
          '${alreadyOnline['source']}',
        );
      }
    } finally {
      await node.dispose();
    }
  });
}
