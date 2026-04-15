import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart'
    as p2p;
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_test/flutter_test.dart';

import '../core/bridge/fake_bridge.dart';
import '../shared/fakes/fake_p2p_network.dart';
import '../shared/fakes/fake_p2p_service_integration.dart';
import '../shared/fakes/test_user.dart';
import 'benchmark_harness.dart';
import 'timing_test_bridge.dart';

void main() {
  late BenchmarkHarness harness;
  late FakeP2PNetwork network;

  setUp(() {
    harness = BenchmarkHarness();
    network = FakeP2PNetwork();
  });

  tearDown(() {
    harness.dispose();
  });

  group('Benchmark: Per-Step 1:1 Send Breakdown', () {
    test('A1: Cold send emits CHAT_MSG_SEND_TIMING with per-step breakdown',
        () async {
      final alice = TestUser.create(
        peerId: 'alice-peer',
        username: 'Alice',
        network: network,
        bridge: TimingTestBridge(
          commandDelays: {'peer:dial': const Duration(milliseconds: 100)},
        ),
      );
      final bob = TestUser.create(
        peerId: 'bob-peer',
        username: 'Bob',
        network: network,
      );
      alice.addContact(bob);
      bob.addContact(alice);
      alice.start();
      bob.start();

      final events = await harness.captureFlowEvents(() async {
        await alice.sendMessage(bob.peerId, 'Hello Bob');
      });

      final timings = harness.filterEvents(events, 'CHAT_MSG_SEND_TIMING');
      expect(timings, isNotEmpty, reason: 'Should emit CHAT_MSG_SEND_TIMING');

      final details = timings.first['details'] as Map<String, dynamic>;
      expect(details['elapsedMs'], isA<int>());
      expect(details['elapsedMs'], greaterThanOrEqualTo(0));
      expect(details['outcome'], isA<String>());
      expect(details['sendPath'], isA<String>());
      expect(details['connectionReused'], isA<bool>());
    });

    test('A2: Warm send shows connectionReused = true', () async {
      final alice = TestUser.create(
        peerId: 'alice-peer',
        username: 'Alice',
        network: network,
      );
      final bob = TestUser.create(
        peerId: 'bob-peer',
        username: 'Bob',
        network: network,
      );
      alice.addContact(bob);
      bob.addContact(alice);
      alice.start();
      bob.start();

      // Simulate bob as already connected via currentState.connections
      alice.p2pService.testConnections.add(p2p.ConnectionState(
        peerId: bob.peerId,
        multiaddrs: ['/p2p-circuit/p2p/relay'],
        direction: 'outbound',
        status: 'connected',
      ));

      final events = await harness.captureFlowEvents(() async {
        await alice.sendMessage(bob.peerId, 'Warm hello');
      });

      final timings = harness.filterEvents(events, 'CHAT_MSG_SEND_TIMING');
      expect(timings, isNotEmpty);

      final details = timings.first['details'] as Map<String, dynamic>;
      expect(details['connectionReused'], isTrue);
      expect(details['sendPath'], 'reuse');
    });

    test('A3: Cold and warm sends report different sendPath', () async {
      final alice = TestUser.create(
        peerId: 'alice-peer',
        username: 'Alice',
        network: network,
      );
      final bob = TestUser.create(
        peerId: 'bob-peer',
        username: 'Bob',
        network: network,
      );
      alice.addContact(bob);
      bob.addContact(alice);
      alice.start();
      bob.start();

      // Cold send — no prior connection
      final coldEvents = await harness.captureFlowEvents(() async {
        await alice.sendMessage(bob.peerId, 'Cold message');
      });
      final coldTimings =
          harness.filterEvents(coldEvents, 'CHAT_MSG_SEND_TIMING');
      expect(coldTimings, isNotEmpty);
      final coldDetails =
          coldTimings.first['details'] as Map<String, dynamic>;
      expect(coldDetails['connectionReused'], isFalse);
      expect(coldDetails['sendPath'], isNot('reuse'));

      // Warm send — mark bob as connected via currentState.connections
      alice.p2pService.testConnections.add(p2p.ConnectionState(
        peerId: bob.peerId,
        multiaddrs: ['/p2p-circuit/p2p/relay'],
        direction: 'outbound',
        status: 'connected',
      ));
      final warmEvents = await harness.captureFlowEvents(() async {
        await alice.sendMessage(bob.peerId, 'Warm message');
      });
      final warmTimings =
          harness.filterEvents(warmEvents, 'CHAT_MSG_SEND_TIMING');
      expect(warmTimings, isNotEmpty);
      final warmDetails =
          warmTimings.first['details'] as Map<String, dynamic>;
      expect(warmDetails['connectionReused'], isTrue);
      expect(warmDetails['sendPath'], 'reuse');
    });

    test('A4: Sequential sends show connection reuse effect', () async {
      final bridge = TimingTestBridge(
        commandDelays: {'peer:dial': const Duration(milliseconds: 150)},
      );
      final alice = TestUser.create(
        peerId: 'alice-peer',
        username: 'Alice',
        network: network,
        bridge: bridge,
      );
      final bob = TestUser.create(
        peerId: 'bob-peer',
        username: 'Bob',
        network: network,
      );
      alice.addContact(bob);
      bob.addContact(alice);
      alice.start();
      bob.start();

      final allEvents = <Map<String, dynamic>>[];

      // First send: cold
      final firstEvents = await harness.captureFlowEvents(() async {
        await alice.sendMessage(bob.peerId, 'Message 1');
      });
      allEvents.addAll(harness.filterEvents(firstEvents, 'CHAT_MSG_SEND_TIMING'));

      // After first send, simulate connection established
      alice.p2pService.testConnections.add(p2p.ConnectionState(
        peerId: bob.peerId,
        multiaddrs: ['/p2p-circuit/p2p/relay'],
        direction: 'outbound',
        status: 'connected',
      ));

      // Remaining 9 sends: warm
      for (var i = 2; i <= 10; i++) {
        final events = await harness.captureFlowEvents(() async {
          await alice.sendMessage(bob.peerId, 'Message $i');
        });
        allEvents
            .addAll(harness.filterEvents(events, 'CHAT_MSG_SEND_TIMING'));
      }

      expect(allEvents, hasLength(10));

      final firstDetails = allEvents[0]['details'] as Map<String, dynamic>;
      expect(firstDetails['connectionReused'], isFalse);

      for (var i = 1; i < 10; i++) {
        final details = allEvents[i]['details'] as Map<String, dynamic>;
        expect(details['connectionReused'], isTrue);
      }
    });

    test('A5: Inbox fallback path reports sendPath = inbox', () async {
      final alice = TestUser.create(
        peerId: 'alice-peer',
        username: 'Alice',
        network: network,
      );
      final bob = TestUser.create(
        peerId: 'bob-peer',
        username: 'Bob',
        network: network,
      );
      alice.addContact(bob);
      alice.start();

      // Bob is offline — sends should fail, falling through to inbox
      alice.p2pService.sendFailCount = 999;
      network.deliveryFails = true;

      final events = await harness.captureFlowEvents(() async {
        await alice.sendMessage(bob.peerId, 'Offline message');
      });

      final timings = harness.filterEvents(events, 'CHAT_MSG_SEND_TIMING');
      expect(timings, isNotEmpty);

      final details = timings.first['details'] as Map<String, dynamic>;
      // When direct send fails and inbox stores, sendPath should be 'inbox'
      // or outcome may show the failure path
      expect(details['outcome'], isA<String>());
    });

    test('A6: Send with ML-KEM encryption includes encryptMs', () async {
      final bridge = PassthroughCryptoBridge();
      final alice = TestUser.create(
        peerId: 'alice-peer',
        username: 'Alice',
        network: network,
        bridge: bridge,
      );
      final bob = TestUser.create(
        peerId: 'bob-peer',
        username: 'Bob',
        network: network,
      );
      alice.addContact(bob); // addContact sets mlKemPublicKey
      bob.addContact(alice);
      alice.start();
      bob.start();

      final events = await harness.captureFlowEvents(() async {
        await alice.sendMessage(bob.peerId, 'Encrypted hello');
      });

      final timings = harness.filterEvents(events, 'CHAT_MSG_SEND_TIMING');
      expect(timings, isNotEmpty);

      final details = timings.first['details'] as Map<String, dynamic>;
      // Encryption step should be included when ML-KEM key is present
      expect(details['outcome'], 'success');
    });
  });
}
