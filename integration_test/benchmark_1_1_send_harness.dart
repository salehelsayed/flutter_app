/// Simulator Benchmark: Per-Step 1:1 Send Breakdown (Test A)
///
/// Measures cold vs warm send latency with a real Go CLI test peer.
/// Requires orchestrator to start the test peer and provide fixture file.
/// Run: dart run integration_test/scripts/run_benchmark_suite.dart -d <DEVICE_ID> --scenarios A
@Tags(['device'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';

import '../test/shared/fakes/in_memory_message_repository.dart';

import 'benchmark_helpers.dart';

const _configuredCliPeerFixture = String.fromEnvironment(
  'CLI_PEER_FIXTURE',
  defaultValue: '',
);

Map<String, dynamic>? _loadCliPeerFixture() {
  final path = _configuredCliPeerFixture.isNotEmpty
      ? _configuredCliPeerFixture
      : '${Directory.systemTemp.path}/cli_peer_fixture.json';
  final file = File(path);
  if (!file.existsSync()) return null;
  try {
    return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  } catch (e) {
    print('[TEST] Failed to parse CLI peer fixture: $e');
    return null;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  testWidgets('A-Sim-1: Cold send to test peer', (tester) async {
    print('\n${'═' * 60}');
    print('  BENCHMARK: 1:1 SEND (A-Sim-1)');
    print('${'═' * 60}\n');

    final fixture = _loadCliPeerFixture();
    if (fixture == null) {
      print('[SKIP] No CLI peer fixture found — run via orchestrator');
      return;
    }

    final targetPeerId = fixture['peerId'] as String;
    print('[SETUP] CLI peer: ${targetPeerId.substring(0, 24)}...');

    final node = await createBenchmarkNode();
    await node.startAndWaitOnline();
    print('[SETUP] Flutter node online');

    final messageRepo = InMemoryMessageRepository();
    final allTimings = <Map<String, dynamic>>[];

    // Send 5 messages: first is cold, subsequent may be warm
    for (var i = 0; i < 5; i++) {
      final events = await captureFlowEvents(() async {
        await sendChatMessage(
          p2pService: node.service,
          messageRepo: messageRepo,
          targetPeerId: targetPeerId,
          text: 'Benchmark message ${i + 1}',
          senderPeerId: node.peerId,
          senderUsername: 'BenchmarkUser',
          bridge: node.bridge,
        );
      });
      allTimings.addAll(filterEvents(events, 'CHAT_MSG_SEND_TIMING'));
    }

    // Analyze results
    final coldTimings = <int>[];
    final warmTimings = <int>[];

    for (final t in allTimings) {
      final d = t['details'] as Map<String, dynamic>;
      final ms = d['elapsedMs'] as int;
      final reused = d['connectionReused'] as bool;
      final path = d['sendPath'] as String;

      // Log sub-step breakdown when present (§10 per-step fields)
      final substeps = <String>[];
      for (final key in [
        'discoverMs', 'dialMs', 'sendMs', 'encryptMs',
        'streamOpenMs', 'writeMs', 'ackWaitMs',
      ]) {
        if (d.containsKey(key)) substeps.add('$key=${d[key]}');
      }
      print(
        '[SEND] elapsedMs=$ms sendPath=$path '
        'reused=$reused outcome=${d['outcome']}'
        '${substeps.isNotEmpty ? ' ${substeps.join(' ')}' : ''}',
      );

      if (reused) {
        warmTimings.add(ms);
      } else {
        coldTimings.add(ms);
      }
    }

    // Log Go-side SendMessageResult sub-step timing if available
    // These come through as fields in CHAT_MSG_SEND_TIMING details
    if (allTimings.isNotEmpty) {
      final first = allTimings.first['details'] as Map<String, dynamic>;
      if (first.containsKey('streamOpenMs')) {
        printBenchmarkSingle(
            'sim_1_1_stream_open_ms', first['streamOpenMs'] as int);
      }
      if (first.containsKey('writeMs')) {
        printBenchmarkSingle('sim_1_1_write_ms', first['writeMs'] as int);
      }
      if (first.containsKey('ackWaitMs')) {
        printBenchmarkSingle(
            'sim_1_1_ack_wait_ms', first['ackWaitMs'] as int);
      }
    }

    if (coldTimings.isNotEmpty) {
      coldTimings.sort();
      printBenchmark(
        'sim_1_1_cold_send_ms',
        p50: percentile(coldTimings, 50),
        p95: percentile(coldTimings, 95),
        n: coldTimings.length,
      );
    }
    if (warmTimings.isNotEmpty) {
      warmTimings.sort();
      printBenchmark(
        'sim_1_1_warm_send_ms',
        p50: percentile(warmTimings, 50),
        p95: percentile(warmTimings, 95),
        n: warmTimings.length,
      );
    }

    // Send path distribution
    final pathCounts = <String, int>{};
    for (final t in allTimings) {
      final path =
          (t['details'] as Map<String, dynamic>)['sendPath'] as String;
      pathCounts[path] = (pathCounts[path] ?? 0) + 1;
    }
    final distribution =
        pathCounts.entries.map((e) => '${e.key}=${e.value}').join(' ');
    print('[BENCHMARK] sim_1_1_send_path_distribution $distribution');

    await node.dispose();
  });

  testWidgets('A-Sim-2: 10 warm sequential sends', (tester) async {
    print('\n${'═' * 60}');
    print('  BENCHMARK: SEQUENTIAL WARM SENDS (A-Sim-2)');
    print('${'═' * 60}\n');

    final fixture = _loadCliPeerFixture();
    if (fixture == null) {
      print('[SKIP] No CLI peer fixture');
      return;
    }

    final targetPeerId = fixture['peerId'] as String;
    final node = await createBenchmarkNode();
    await node.startAndWaitOnline();

    final messageRepo = InMemoryMessageRepository();

    // First send (cold) to establish connection
    await sendChatMessage(
      p2pService: node.service,
      messageRepo: messageRepo,
      targetPeerId: targetPeerId,
      text: 'Warmup message',
      senderPeerId: node.peerId,
      senderUsername: 'BenchmarkUser',
      bridge: node.bridge,
    );

    // Wait briefly for connection to establish
    await Future<void>.delayed(const Duration(seconds: 1));

    // 10 sequential warm sends
    final timings = <int>[];
    for (var i = 0; i < 10; i++) {
      final events = await captureFlowEvents(() async {
        await sendChatMessage(
          p2pService: node.service,
          messageRepo: messageRepo,
          targetPeerId: targetPeerId,
          text: 'Sequential ${i + 1}',
          senderPeerId: node.peerId,
          senderUsername: 'BenchmarkUser',
          bridge: node.bridge,
        );
      });
      final send = filterEvents(events, 'CHAT_MSG_SEND_TIMING');
      if (send.isNotEmpty) {
        timings.add(
          (send.first['details'] as Map<String, dynamic>)['elapsedMs'] as int,
        );
      }
    }

    if (timings.isNotEmpty) {
      timings.sort();
      printBenchmark(
        'sim_1_1_sequential_warm_ms',
        p50: percentile(timings, 50),
        p95: percentile(timings, 95),
        n: timings.length,
      );
    }

    await node.dispose();
  });

  testWidgets('A-Sim-3: Inbox fallback (peer offline)', (tester) async {
    print('\n${'═' * 60}');
    print('  BENCHMARK: INBOX FALLBACK (A-Sim-3)');
    print('${'═' * 60}\n');

    // No CLI peer needed — send to a nonexistent peer, should fall to inbox
    final node = await createBenchmarkNode();
    await node.startAndWaitOnline();

    final messageRepo = InMemoryMessageRepository();

    final events = await captureFlowEvents(() async {
      await sendChatMessage(
        p2pService: node.service,
        messageRepo: messageRepo,
        targetPeerId: '12D3KooWOfflinePeerForBenchmarkTest0000000000',
        text: 'Offline test',
        senderPeerId: node.peerId,
        senderUsername: 'BenchmarkUser',
        bridge: node.bridge,
      );
    });

    final send = filterEvents(events, 'CHAT_MSG_SEND_TIMING');
    if (send.isNotEmpty) {
      final d = send.first['details'] as Map<String, dynamic>;
      printBenchmarkSingle(
          'sim_1_1_inbox_fallback_ms', d['elapsedMs'] as int);
      print('[BENCHMARK] sim_1_1_inbox_fallback_path = ${d['sendPath']}');
      print('[BENCHMARK] sim_1_1_inbox_fallback_outcome = ${d['outcome']}');
    }

    await node.dispose();
  });
}
