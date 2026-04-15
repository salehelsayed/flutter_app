/// Simulator Benchmark: Connection Reuse Hit Rate (Test J)
///
/// Measures how often the fast path carries traffic.
/// Requires CLI test peer via orchestrator for two-node sends.
/// Run: dart run integration_test/scripts/run_benchmark_suite.dart -d <DEVICE_ID> --scenarios J
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

  testWidgets('J-Sim-1: Scripted conversation workload', (tester) async {
    print('\n${'═' * 60}');
    print('  BENCHMARK: CONNECTION REUSE (J-Sim-1)');
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
    final allTimings = <Map<String, dynamic>>[];

    // Phase 1: 1 cold send + 5 warm sends
    for (var i = 0; i < 6; i++) {
      final events = await captureFlowEvents(() async {
        await sendChatMessage(
          p2pService: node.service,
          messageRepo: messageRepo,
          targetPeerId: targetPeerId,
          text: 'Phase1 msg ${i + 1}',
          senderPeerId: node.peerId,
          senderUsername: 'BenchmarkUser',
          bridge: node.bridge,
        );
      });
      allTimings.addAll(filterEvents(events, 'CHAT_MSG_SEND_TIMING'));
    }

    // Phase 2: Wait 5s (connection may persist), then 4 more sends
    await Future<void>.delayed(const Duration(seconds: 5));
    for (var i = 0; i < 4; i++) {
      final events = await captureFlowEvents(() async {
        await sendChatMessage(
          p2pService: node.service,
          messageRepo: messageRepo,
          targetPeerId: targetPeerId,
          text: 'Phase2 msg ${i + 1}',
          senderPeerId: node.peerId,
          senderUsername: 'BenchmarkUser',
          bridge: node.bridge,
        );
      });
      allTimings.addAll(filterEvents(events, 'CHAT_MSG_SEND_TIMING'));
    }

    // Analyze reuse rate
    var reuseCount = 0;
    final coldTimings = <int>[];
    final warmTimings = <int>[];

    for (final t in allTimings) {
      final d = t['details'] as Map<String, dynamic>;
      final ms = d['elapsedMs'] as int;
      final reused = d['connectionReused'] as bool;
      if (reused) {
        reuseCount++;
        warmTimings.add(ms);
      } else {
        coldTimings.add(ms);
      }
    }

    final hitRate = allTimings.isNotEmpty
        ? (reuseCount / allTimings.length * 100).round()
        : 0;

    print('[BENCHMARK] sim_connection_reuse_hit_rate_pct = $hitRate%');

    if (coldTimings.isNotEmpty) {
      coldTimings.sort();
      printBenchmark(
        'sim_reuse_cold_send_ms',
        p50: percentile(coldTimings, 50),
        p95: percentile(coldTimings, 95),
        n: coldTimings.length,
      );
    }
    if (warmTimings.isNotEmpty) {
      warmTimings.sort();
      printBenchmark(
        'sim_reuse_warm_send_ms',
        p50: percentile(warmTimings, 50),
        p95: percentile(warmTimings, 95),
        n: warmTimings.length,
      );
    }

    await node.dispose();
  });
}
