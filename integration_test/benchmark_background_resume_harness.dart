/// Simulator Benchmark: Background Resume to Online Badge
///
/// Exercises the production `TIME_TO_ONLINE_BADGE` resume phases on a real
/// bridge-backed node: healthy resume, degraded resume with recovery, and an
/// extended 30s background window.
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
import 'package:flutter_app/features/p2p/presentation/widgets/connection_status_indicator.dart';

import '../test/shared/fakes/in_memory_message_repository.dart';
import 'benchmark_helpers.dart';

final _relayPeerId = defaultRendezvousAddress.split('/p2p/').last;

Map<String, dynamic> _findBadge(
  List<Map<String, dynamic>> events, {
  required String phase,
}) {
  final matches = filterEvents(events, 'TIME_TO_ONLINE_BADGE')
      .where(
        (event) => (event['details'] as Map<String, dynamic>)['phase'] == phase,
      )
      .toList(growable: false);
  expect(matches, isNotEmpty, reason: 'Missing TIME_TO_ONLINE_BADGE $phase');
  return matches.first['details'] as Map<String, dynamic>;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  testWidgets('BR-S1: Resume with healthy relay', (tester) async {
    print('\n${'═' * 60}');
    print('  BENCHMARK: BACKGROUND RESUME — HEALTHY RELAY (BR-S1)');
    print('${'═' * 60}\n');

    final node = await createBenchmarkNode();
    final messageRepo = InMemoryMessageRepository();

    try {
      final online = await node.startAndWaitOnline();
      expect(online, isTrue, reason: 'Node should reach Online');

      await handleAppPaused(messageRepo: messageRepo);

      final events = await captureFlowEvents(() async {
        node.service.markResumeStarted();
        await handleAppResumed(bridge: node.bridge, p2pService: node.service);
        node.service.checkResumeAlreadyOnline();
      });

      final badge = _findBadge(
        events,
        phase: 'background_resume_already_online',
      );
      printBenchmarkSingle(
        'sim_background_resume_healthy_ms',
        badge['totalMs'] as int,
      );
      print(
        '[BENCHMARK] sim_background_resume_healthy_phase = '
        '${badge['phase']}',
      );
      print(
        '[BENCHMARK] sim_background_resume_healthy_source = '
        '${badge['source']}',
      );
    } finally {
      await node.dispose();
    }
  });

  testWidgets('BR-S2: Resume with degraded relay', (tester) async {
    print('\n${'═' * 60}');
    print('  BENCHMARK: BACKGROUND RESUME — DEGRADED RELAY (BR-S2)');
    print('${'═' * 60}\n');

    final node = await createBenchmarkNode();
    final messageRepo = InMemoryMessageRepository();

    try {
      final online = await node.startAndWaitOnline();
      expect(online, isTrue, reason: 'Node should reach Online');

      await handleAppPaused(messageRepo: messageRepo);

      await node.bridge.send(
        jsonEncode({
          'cmd': 'peer:disconnect',
          'payload': {'peerId': _relayPeerId},
        }),
      );
      final degraded = await waitFor(
        () =>
            healthFromState(node.service.currentState) !=
            ConnectionHealth.online,
        timeout: const Duration(seconds: 15),
        label: 'Degraded before resume benchmark',
      );
      expect(degraded, isTrue, reason: 'Relay drop should degrade the node');

      final events = await captureFlowEvents(() async {
        node.service.markResumeStarted();
        await handleAppResumed(bridge: node.bridge, p2pService: node.service);
        final recovered = await waitForOnline(
          node.service,
          timeout: const Duration(seconds: 30),
        );
        expect(recovered, isTrue, reason: 'Node should recover after resume');
        node.service.checkResumeAlreadyOnline();
      });

      final badge = _findBadge(events, phase: 'background_resume');
      printBenchmarkSingle(
        'sim_background_resume_degraded_ms',
        badge['totalMs'] as int,
      );
      print(
        '[BENCHMARK] sim_background_resume_degraded_phase = '
        '${badge['phase']}',
      );
      print(
        '[BENCHMARK] sim_background_resume_degraded_source = '
        '${badge['source']}',
      );
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
      final online = await node.startAndWaitOnline();
      expect(online, isTrue, reason: 'Node should reach Online');

      await handleAppPaused(messageRepo: messageRepo);
      print('[PHASE] Holding the app backgrounded for 30 seconds...');
      await Future<void>.delayed(const Duration(seconds: 30));

      final events = await captureFlowEvents(() async {
        node.service.markResumeStarted();
        await handleAppResumed(bridge: node.bridge, p2pService: node.service);
        node.service.checkResumeAlreadyOnline();
      });

      final badges = filterEvents(events, 'TIME_TO_ONLINE_BADGE');
      expect(badges, isNotEmpty, reason: 'Extended resume should emit a badge');
      final details = badges.first['details'] as Map<String, dynamic>;
      printBenchmarkSingle(
        'sim_background_resume_extended_ms',
        details['totalMs'] as int,
      );
      print(
        '[BENCHMARK] sim_background_resume_extended_phase = '
        '${details['phase']}',
      );
      print(
        '[BENCHMARK] sim_background_resume_extended_source = '
        '${details['source']}',
      );
    } finally {
      await node.dispose();
    }
  });
}
