/// Simulator Benchmark: Deferred Direct ACK Timing (Test L)
///
/// Measures ACK round-trip latency with a real test peer.
/// Requires CLI test peer via orchestrator.
/// Run: dart run integration_test/scripts/run_benchmark_suite.dart -d <DEVICE_ID> --scenarios L
@Tags(['device'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';

import '../test/shared/fakes/in_memory_message_repository.dart';

import 'benchmark_helpers.dart';

const _configuredCliPeerFixture = String.fromEnvironment(
  'CLI_PEER_FIXTURE',
  defaultValue: '',
);

Map<String, dynamic>? _loadFixture() {
  final path = _configuredCliPeerFixture.isNotEmpty
      ? _configuredCliPeerFixture
      : '${Directory.systemTemp.path}/cli_peer_fixture.json';
  final file = File(path);
  if (!file.existsSync()) return null;
  try {
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  testWidgets('L-Sim-1: Direct send with ACK from test peer',
      (tester) async {
    print('\n${'═' * 60}');
    print('  BENCHMARK: DIRECT ACK (L-Sim-1)');
    print('${'═' * 60}\n');

    final fixture = _loadFixture();
    if (fixture == null) {
      print('[SKIP] No CLI peer fixture');
      return;
    }

    final targetPeerId = fixture['peerId'] as String;
    final node = await createBenchmarkNode();
    await node.startAndWaitOnline();

    final messageRepo = InMemoryMessageRepository();
    final timings = <int>[];

    for (var i = 0; i < 10; i++) {
      final events = await captureFlowEvents(() async {
        await sendChatMessage(
          p2pService: node.service,
          messageRepo: messageRepo,
          targetPeerId: targetPeerId,
          text: 'ACK test ${i + 1}',
          senderPeerId: node.peerId,
          senderUsername: 'BenchmarkUser',
          bridge: node.bridge,
        );
      });

      final send = filterEvents(events, 'CHAT_MSG_SEND_TIMING');
      if (send.isNotEmpty) {
        final d = send.first['details'] as Map<String, dynamic>;
        timings.add(d['elapsedMs'] as int);
        print(
          '[SEND ${i + 1}] elapsedMs=${d['elapsedMs']} '
          'sendPath=${d['sendPath']} outcome=${d['outcome']}'
          '${d.containsKey('ackRoundTripMs') ? ' ackRoundTripMs=${d['ackRoundTripMs']}' : ''}',
        );
      }

      // §9: message:direct_ack_timing from Go push events
      final ackTimings = filterEvents(events, 'message:direct_ack_timing');
      for (final e in ackTimings) {
        final ad = e['details'] as Map<String, dynamic>;
        print(
          '[ACK ${i + 1}] waitMs=${ad['waitMs'] ?? ad['ackMs'] ?? 'n/a'} '
          'outcome=${ad['outcome'] ?? 'n/a'} '
          'transport=${ad['transport'] ?? 'n/a'}',
        );
      }
    }

    if (timings.isNotEmpty) {
      timings.sort();
      printBenchmark(
        'sim_direct_ack_wait_ms',
        p50: percentile(timings, 50),
        p95: percentile(timings, 95),
        n: timings.length,
      );
      expect(
        percentile(timings, 95),
        lessThan(2000),
        reason: 'p95 should be within DirectConfirmTimeout',
      );
    }

    await node.dispose();
  });
}
