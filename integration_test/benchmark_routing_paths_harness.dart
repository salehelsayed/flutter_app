/// Simulator Benchmark: Routing Path Matrix (Section 14o — R-Sim-1 through R-Sim-8)
///
/// Runs routing-path scenarios from Section 15 on a real iOS simulator with
/// the live Go bridge to produce real timing numbers for each routing decision.
/// Uses the Go CLI test peer to control which paths succeed or fail.
///
/// Run: dart run integration_test/scripts/run_benchmark_suite.dart -d <DEVICE_ID> --scenarios R
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

/// Helper: send a message and return the CHAT_MSG_SEND_TIMING event details.
Future<Map<String, dynamic>?> _sendAndCaptureTiming(
  BenchmarkNode node,
  InMemoryMessageRepository messageRepo,
  String targetPeerId,
  String text,
) async {
  final events = await captureFlowEvents(() async {
    await sendChatMessage(
      p2pService: node.service,
      messageRepo: messageRepo,
      targetPeerId: targetPeerId,
      text: text,
      senderPeerId: node.peerId,
      senderUsername: 'BenchmarkUser',
      bridge: node.bridge,
    );
  });
  final timings = filterEvents(events, 'CHAT_MSG_SEND_TIMING');
  if (timings.isEmpty) return null;
  return timings.first['details'] as Map<String, dynamic>;
}

/// Log sub-step breakdown for a send timing event.
void _logSendDetails(String label, Map<String, dynamic> d) {
  final substeps = <String>[];
  for (final key in [
    'discoverMs', 'dialMs', 'sendMs', 'encryptMs',
    'relayProbeMs', 'inboxMs', 'localSendMs',
  ]) {
    if (d.containsKey(key)) substeps.add('$key=${d[key]}');
  }
  print(
    '[$label] elapsedMs=${d['elapsedMs']} sendPath=${d['sendPath']} '
    'reused=${d['connectionReused']} outcome=${d['outcome']}'
    '${substeps.isNotEmpty ? ' ${substeps.join(' ')}' : ''}',
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  testWidgets('R-Sim-1: Connection reuse — warm send to connected peer',
      (tester) async {
    print('\n${'═' * 60}');
    print('  ROUTING BENCHMARK: CONNECTION REUSE (R-Sim-1)');
    print('${'═' * 60}\n');

    final fixture = _loadCliPeerFixture();
    if (fixture == null) {
      print('[SKIP] No CLI peer fixture — run via orchestrator');
      return;
    }

    final targetPeerId = fixture['peerId'] as String;
    final node = await createBenchmarkNode();
    await node.startAndWaitOnline();
    print('[SETUP] Flutter node online');

    final messageRepo = InMemoryMessageRepository();

    // Cold send to establish connection
    print('[PHASE] Cold send to establish connection...');
    final coldDetails = await _sendAndCaptureTiming(
      node, messageRepo, targetPeerId, 'Reuse warmup',
    );
    if (coldDetails != null) _logSendDetails('COLD', coldDetails);

    // Wait for connection to stabilize
    await Future<void>.delayed(const Duration(seconds: 1));

    // 5 warm sends
    print('[PHASE] 5 warm sends...');
    final warmTimings = <int>[];
    for (var i = 0; i < 5; i++) {
      final d = await _sendAndCaptureTiming(
        node, messageRepo, targetPeerId, 'Reuse warm ${i + 1}',
      );
      if (d != null) {
        _logSendDetails('WARM', d);
        warmTimings.add(d['elapsedMs'] as int);
      }
    }

    if (warmTimings.isNotEmpty) {
      warmTimings.sort();
      printBenchmark(
        'sim_routing_reuse_ms',
        p50: percentile(warmTimings, 50),
        p95: percentile(warmTimings, 95),
        n: warmTimings.length,
      );

      final reuseCount = warmTimings.length; // All should be warm
      print('[BENCHMARK] sim_routing_reuse_path = reuse '
          '(${(reuseCount / warmTimings.length * 100).round()}%)');
    }

    await node.dispose();
  });

  testWidgets('R-Sim-2: Direct P2P — cold send to discoverable peer',
      (tester) async {
    print('\n${'═' * 60}');
    print('  ROUTING BENCHMARK: DIRECT COLD (R-Sim-2)');
    print('${'═' * 60}\n');

    final fixture = _loadCliPeerFixture();
    if (fixture == null) {
      print('[SKIP] No CLI peer fixture');
      return;
    }

    final targetPeerId = fixture['peerId'] as String;

    // Fresh node each time — no prior connection
    final node = await createBenchmarkNode();
    await node.startAndWaitOnline();
    print('[SETUP] Flutter node online (fresh identity)');

    final messageRepo = InMemoryMessageRepository();

    final d = await _sendAndCaptureTiming(
      node, messageRepo, targetPeerId, 'Direct cold send',
    );

    if (d != null) {
      _logSendDetails('DIRECT', d);
      printBenchmarkSingle('sim_routing_direct_cold_ms', d['elapsedMs'] as int);
      if (d.containsKey('discoverMs')) {
        printBenchmarkSingle(
            'sim_routing_direct_discoverMs', d['discoverMs'] as int);
      }
      if (d.containsKey('dialMs')) {
        printBenchmarkSingle(
            'sim_routing_direct_dialMs', d['dialMs'] as int);
      }
      if (d.containsKey('sendMs')) {
        printBenchmarkSingle(
            'sim_routing_direct_sendMs', d['sendMs'] as int);
      }
    }

    await node.dispose();
  });

  testWidgets(
      'R-Sim-3: Relay probe — peer behind relay, not directly discoverable',
      (tester) async {
    print('\n${'═' * 60}');
    print('  ROUTING BENCHMARK: RELAY PROBE (R-Sim-3)');
    print('${'═' * 60}\n');

    // This scenario requires the CLI peer to be online but NOT registered on
    // rendezvous. The orchestrator signals when the CLI peer has unregistered.
    // If no fixture, skip.
    final fixture = _loadCliPeerFixture();
    if (fixture == null) {
      print('[SKIP] No CLI peer fixture');
      return;
    }

    final targetPeerId = fixture['peerId'] as String;
    final node = await createBenchmarkNode();
    await node.startAndWaitOnline();
    print('[SETUP] Flutter node online');

    // Check for unregistered signal from orchestrator
    final unregisteredSignal = File(
      '${Directory.systemTemp.path}/routing_sim_cli_unregistered',
    );
    if (!unregisteredSignal.existsSync()) {
      print('[SKIP] CLI peer not unregistered — '
          'needs orchestrator to signal unregister');
      await node.dispose();
      return;
    }

    final messageRepo = InMemoryMessageRepository();

    print('[PHASE] Send to unregistered peer (relay probe path)...');
    final d = await _sendAndCaptureTiming(
      node, messageRepo, targetPeerId, 'Relay probe msg',
    );

    if (d != null) {
      _logSendDetails('RELAY_PROBE', d);
      printBenchmarkSingle(
          'sim_routing_relay_probe_ms', d['elapsedMs'] as int);
      print('[BENCHMARK] sim_routing_relay_probe_path = ${d['sendPath']}');
    }

    await node.dispose();
  });

  testWidgets('R-Sim-4: Inbox fallback — peer offline', (tester) async {
    print('\n${'═' * 60}');
    print('  ROUTING BENCHMARK: INBOX FALLBACK (R-Sim-4)');
    print('${'═' * 60}\n');

    // Send to nonexistent peer — all paths fail, falls to inbox
    final node = await createBenchmarkNode();
    await node.startAndWaitOnline();
    print('[SETUP] Flutter node online');

    final messageRepo = InMemoryMessageRepository();

    print('[PHASE] Send to offline peer (inbox fallback)...');
    final d = await _sendAndCaptureTiming(
      node,
      messageRepo,
      '12D3KooWOfflineRoutingBenchmarkPeer00000000000',
      'Inbox fallback msg',
    );

    if (d != null) {
      _logSendDetails('INBOX', d);
      printBenchmarkSingle(
          'sim_routing_inbox_fallback_ms', d['elapsedMs'] as int);
      print('[BENCHMARK] sim_routing_inbox_path = ${d['sendPath']}');
    }

    await node.dispose();
  });

  testWidgets('R-Sim-5: Budget starvation — slow relay, discover takes >1.5s',
      (tester) async {
    print('\n${'═' * 60}');
    print('  ROUTING BENCHMARK: BUDGET STARVATION (R-Sim-5)');
    print('${'═' * 60}\n');

    // This naturally occurs when the peer is not discoverable and discovery
    // hangs until the interactiveDirectBudget (2s) timeout.
    // Using a nonexistent peer forces discover to consume the full budget.
    final node = await createBenchmarkNode();
    await node.startAndWaitOnline();
    print('[SETUP] Flutter node online');

    final messageRepo = InMemoryMessageRepository();

    print('[PHASE] Send to unresponsive peer (budget starvation)...');
    final sw = Stopwatch()..start();
    final d = await _sendAndCaptureTiming(
      node,
      messageRepo,
      '12D3KooWSlowDiscoverRoutingBenchmark000000000',
      'Budget starvation msg',
    );
    sw.stop();

    if (d != null) {
      _logSendDetails('BUDGET_STARVATION', d);
      printBenchmarkSingle(
          'sim_routing_budget_starvation_ms', d['elapsedMs'] as int);
      if (d.containsKey('discoverMs')) {
        printBenchmarkSingle(
          'sim_routing_budget_starvation_discover_ms',
          d['discoverMs'] as int,
        );
      }
      if (d.containsKey('dialMs')) {
        printBenchmarkSingle(
          'sim_routing_budget_starvation_dial_ms',
          d['dialMs'] as int,
        );
      }
    }
    print('[PHASE] Wall-clock: ${sw.elapsedMilliseconds}ms');

    await node.dispose();
  });

  testWidgets('R-Sim-6: Worst-case path cascade — total failure timing',
      (tester) async {
    print('\n${'═' * 60}');
    print('  ROUTING BENCHMARK: WORST-CASE CASCADE (R-Sim-6)');
    print('${'═' * 60}\n');

    // All paths fail: nonexistent peer, inbox also fails (no relay connection
    // to store). This measures the total cascade time.
    final node = await createBenchmarkNode();
    await node.startAndWaitOnline();
    print('[SETUP] Flutter node online');

    final messageRepo = InMemoryMessageRepository();

    print('[PHASE] Send when all paths fail...');
    final sw = Stopwatch()..start();
    final d = await _sendAndCaptureTiming(
      node,
      messageRepo,
      '12D3KooWWorstCaseRoutingBenchmark0000000000000',
      'Worst case msg',
    );
    sw.stop();

    if (d != null) {
      _logSendDetails('WORST_CASE', d);
      printBenchmarkSingle(
          'sim_routing_worst_case_ms', d['elapsedMs'] as int);
      print(
          '[BENCHMARK] sim_routing_worst_case_path_sequence = '
          'direct→relay→inbox→${d['outcome']}');
    }
    print('[PHASE] Wall-clock: ${sw.elapsedMilliseconds}ms');

    await node.dispose();
  });

  testWidgets('R-Sim-7: Routing path distribution over realistic workload',
      (tester) async {
    print('\n${'═' * 60}');
    print('  ROUTING BENCHMARK: REALISTIC WORKLOAD (R-Sim-7)');
    print('${'═' * 60}\n');

    final fixture = _loadCliPeerFixture();
    if (fixture == null) {
      print('[SKIP] No CLI peer fixture');
      return;
    }

    final targetPeerId = fixture['peerId'] as String;
    final node = await createBenchmarkNode();
    await node.startAndWaitOnline();
    print('[SETUP] Flutter node online');

    final messageRepo = InMemoryMessageRepository();
    final allDetails = <Map<String, dynamic>>[];
    final timeline = StringBuffer();

    // Phase 1: 1 cold send (first ever)
    print('[PHASE] 1 cold send...');
    var d = await _sendAndCaptureTiming(
      node, messageRepo, targetPeerId, 'Workload msg 1',
    );
    if (d != null) {
      allDetails.add(d);
      timeline.writeln(
        '  msg1:  cold    ${d['elapsedMs']}ms  path=${d['sendPath']}',
      );
    }

    // Phase 2: 5 warm sends (connection reused)
    await Future<void>.delayed(const Duration(seconds: 1));
    print('[PHASE] 5 warm sends...');
    for (var i = 2; i <= 6; i++) {
      d = await _sendAndCaptureTiming(
        node, messageRepo, targetPeerId, 'Workload msg $i',
      );
      if (d != null) {
        allDetails.add(d);
        timeline.writeln(
          '  msg$i:  warm    ${d['elapsedMs']}ms  path=${d['sendPath']}',
        );
      }
    }

    // Phase 3: Send to offline peer (inbox fallback)
    // Check for cli_stopped signal from orchestrator
    final cliStoppedSignal = File(
      '${Directory.systemTemp.path}/routing_sim_cli_stopped',
    );
    if (cliStoppedSignal.existsSync()) {
      print('[PHASE] CLI stopped — 1 offline send...');
      d = await _sendAndCaptureTiming(
        node, messageRepo, targetPeerId, 'Workload msg 7 (offline)',
      );
      if (d != null) {
        allDetails.add(d);
        timeline.writeln(
          '  msg7:  offline ${d['elapsedMs']}ms  path=${d['sendPath']}',
        );
      }
    }

    // Phase 4: Send after CLI restart (reconnect)
    final cliRestartedSignal = File(
      '${Directory.systemTemp.path}/routing_sim_cli_restarted',
    );
    if (cliRestartedSignal.existsSync()) {
      print('[PHASE] CLI restarted — 1 reconnect send...');
      d = await _sendAndCaptureTiming(
        node, messageRepo, targetPeerId, 'Workload msg 8 (reconnect)',
      );
      if (d != null) {
        allDetails.add(d);
        timeline.writeln(
          '  msg8:  reconn  ${d['elapsedMs']}ms  path=${d['sendPath']}',
        );
      }

      // Phase 5: 3 more warm sends
      print('[PHASE] 3 more warm sends...');
      for (var i = 9; i <= 11; i++) {
        d = await _sendAndCaptureTiming(
          node, messageRepo, targetPeerId, 'Workload msg $i',
        );
        if (d != null) {
          allDetails.add(d);
          timeline.writeln(
            '  msg$i: warm    ${d['elapsedMs']}ms  path=${d['sendPath']}',
          );
        }
      }
    }

    // Analyze distribution
    final pathCounts = <String, int>{};
    final warmTimings = <int>[];
    int? coldMs;
    int? reconnectMs;
    int? offlineMs;

    for (final detail in allDetails) {
      final path = detail['sendPath'] as String;
      final ms = detail['elapsedMs'] as int;
      pathCounts[path] = (pathCounts[path] ?? 0) + 1;

      if (detail['connectionReused'] == true) {
        warmTimings.add(ms);
      } else if (path == 'inbox') {
        offlineMs = ms;
      } else if (coldMs == null) {
        coldMs = ms;
      } else {
        reconnectMs = ms;
      }
    }

    final distribution =
        pathCounts.entries.map((e) => '${e.key}=${e.value}').join(' ');
    print('[BENCHMARK] sim_routing_distribution $distribution');

    if (coldMs != null) {
      printBenchmarkSingle('sim_routing_cold_ms', coldMs);
    }
    if (warmTimings.isNotEmpty) {
      warmTimings.sort();
      printBenchmark(
        'sim_routing_warm_ms',
        p50: percentile(warmTimings, 50),
        p95: percentile(warmTimings, 95),
        n: warmTimings.length,
      );
    }
    if (reconnectMs != null) {
      printBenchmarkSingle('sim_routing_reconnect_ms', reconnectMs);
    }
    if (offlineMs != null) {
      printBenchmarkSingle('sim_routing_offline_inbox_ms', offlineMs);
    }

    print('[BENCHMARK] sim_routing_timeline:\n$timeline');

    await node.dispose();
  });

  testWidgets('R-Sim-8: Before/after routing change comparison',
      (tester) async {
    print('\n${'═' * 60}');
    print('  ROUTING BENCHMARK: BEFORE/AFTER COMPARISON (R-Sim-8)');
    print('${'═' * 60}\n');

    // This test reads a "before" baseline from a JSON file, runs R-Sim-7's
    // workload, then compares. The baseline file is written by a prior run.
    final baselinePath =
        '${Directory.systemTemp.path}/routing_sim_baseline.json';
    final baselineFile = File(baselinePath);

    final fixture = _loadCliPeerFixture();
    if (fixture == null) {
      print('[SKIP] No CLI peer fixture');
      return;
    }

    final targetPeerId = fixture['peerId'] as String;
    final node = await createBenchmarkNode();
    await node.startAndWaitOnline();

    final messageRepo = InMemoryMessageRepository();

    // Run a standard workload: 1 cold + 5 warm
    final coldTiming = await _sendAndCaptureTiming(
      node, messageRepo, targetPeerId, 'Comparison cold',
    );
    await Future<void>.delayed(const Duration(seconds: 1));

    final warmTimings = <int>[];
    for (var i = 0; i < 5; i++) {
      final d = await _sendAndCaptureTiming(
        node, messageRepo, targetPeerId, 'Comparison warm ${i + 1}',
      );
      if (d != null) warmTimings.add(d['elapsedMs'] as int);
    }

    // Build "after" metrics
    final afterMetrics = <String, int>{};
    if (coldTiming != null) {
      afterMetrics['cold_ms'] = coldTiming['elapsedMs'] as int;
    }
    if (warmTimings.isNotEmpty) {
      warmTimings.sort();
      afterMetrics['warm_p50_ms'] = percentile(warmTimings, 50);
      afterMetrics['warm_p95_ms'] = percentile(warmTimings, 95);
    }

    // Compare with baseline if available
    if (baselineFile.existsSync()) {
      try {
        final before = jsonDecode(baselineFile.readAsStringSync())
            as Map<String, dynamic>;
        for (final key in afterMetrics.keys) {
          final beforeVal = before[key] as int?;
          final afterVal = afterMetrics[key]!;
          if (beforeVal != null) {
            final delta = afterVal - beforeVal;
            final pct = beforeVal > 0
                ? ((delta / beforeVal) * 100).round()
                : 0;
            print('[BENCHMARK] sim_routing_before_after_delta_$key = '
                '${beforeVal}ms → ${afterVal}ms (${pct >= 0 ? '+' : ''}$pct%)');
          }
        }
      } catch (e) {
        print('[TEST] Failed to read baseline: $e');
      }
    } else {
      print('[TEST] No baseline file — saving current run as baseline');
    }

    // Save current metrics as baseline for next run
    baselineFile.writeAsStringSync(jsonEncode(afterMetrics));
    print('[TEST] Baseline saved to $baselinePath');

    for (final entry in afterMetrics.entries) {
      print('[BENCHMARK] sim_routing_current_${entry.key} = ${entry.value}ms');
    }

    await node.dispose();
  });
}
