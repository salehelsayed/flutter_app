/// Simulator Benchmark: Inbox Store/Retrieve Round-Trip (Test D)
///
/// Measures inbox store per-step timing and e2e delivery latency.
/// Run: flutter test integration_test/benchmark_inbox_harness.dart -d <DEVICE_ID>
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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  testWidgets('D-Sim-1: Store message in offline peer inbox', (tester) async {
    print('\n${'═' * 60}');
    print('  BENCHMARK: INBOX STORE (D-Sim-1)');
    print('${'═' * 60}\n');

    final node = await createBenchmarkNode();
    await node.startAndWaitOnline();

    final messageRepo = InMemoryMessageRepository();

    // Send to an offline peer — should go through inbox path
    final events = await captureFlowEvents(() async {
      await sendChatMessage(
        p2pService: node.service,
        messageRepo: messageRepo,
        targetPeerId: '12D3KooWOfflinePeerForInboxBenchmark0000000',
        text: 'Inbox store test',
        senderPeerId: node.peerId,
        senderUsername: 'BenchmarkUser',
        bridge: node.bridge,
      );
    });

    // §12: CHAT_MSG_SEND_TIMING overall
    final send = filterEvents(events, 'CHAT_MSG_SEND_TIMING');
    if (send.isNotEmpty) {
      final d = send.first['details'] as Map<String, dynamic>;
      printBenchmarkSingle('sim_inbox_store_ms', d['elapsedMs'] as int);
      print('[BENCHMARK] sim_inbox_store_path = ${d['sendPath']}');
      print('[BENCHMARK] sim_inbox_store_outcome = ${d['outcome']}');
    }

    // §12: Go-side per-step inbox timing (inbox:store_timing push event)
    final storeTimings = filterEvents(events, 'inbox:store_timing');
    for (final e in storeTimings) {
      final d = e['details'] as Map<String, dynamic>;
      for (final key in [
        'connectMs', 'streamOpenMs', 'writeMs', 'readMs', 'totalMs',
      ]) {
        if (d.containsKey(key)) {
          printBenchmarkSingle('sim_inbox_$key', (d[key] as num).toInt());
        }
      }
      print('[BENCHMARK] sim_inbox_store_outcome_go = ${d['outcome']}');
    }

    await node.dispose();
  });

  testWidgets('D-Sim-2: Inbox retrieve timing', (tester) async {
    print('\n${'═' * 60}');
    print('  BENCHMARK: INBOX RETRIEVE (D-Sim-2)');
    print('${'═' * 60}\n');

    final node = await createBenchmarkNode();
    await node.startAndWaitOnline();

    // Trigger inbox retrieve — even with no messages, measures timing
    final events = await captureFlowEvents(() async {
      await node.bridge.send(jsonEncode({
        'cmd': 'inbox:retrieve',
        'payload': {'timeoutMs': 5000},
      }));
    });

    // §20: inbox:retrieve_timing from Go push
    final retrieveTimings = filterEvents(events, 'inbox:retrieve_timing');
    for (final e in retrieveTimings) {
      final d = e['details'] as Map<String, dynamic>;
      if (d.containsKey('totalMs')) {
        printBenchmarkSingle(
            'sim_inbox_retrieve_ms', (d['totalMs'] as num).toInt());
      }
      if (d.containsKey('messageCount')) {
        print('[BENCHMARK] sim_inbox_retrieve_count = ${d['messageCount']}');
      }
      print('[BENCHMARK] sim_inbox_retrieve_outcome = ${d['outcome']}');
    }

    // §20: INBOX_DELIVERY_TIMING if available
    final deliveryTimings = filterEvents(events, 'INBOX_DELIVERY_TIMING');
    for (final e in deliveryTimings) {
      final d = e['details'] as Map<String, dynamic>;
      if (d.containsKey('deliveryMs')) {
        printBenchmarkSingle(
            'sim_inbox_e2e_delivery_ms', (d['deliveryMs'] as num).toInt());
      }
    }

    await node.dispose();
  });
}
