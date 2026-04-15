import 'package:flutter_app/features/p2p/domain/models/connection_state.dart'
    as p2p;
import 'package:flutter_test/flutter_test.dart';

import '../shared/fakes/fake_p2p_network.dart';
import '../shared/fakes/test_user.dart';
import 'benchmark_harness.dart';

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

  group('Benchmark: Deferred Direct ACK Timing', () {
    test('L-Dart-1: Send reports ACK timing in CHAT_MSG_SEND_TIMING',
        () async {
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

      // Use connection reuse path (fast path)
      alice.p2pService.testConnections.add(p2p.ConnectionState(
        peerId: bob.peerId,
        multiaddrs: ['/p2p-circuit/p2p/relay'],
        direction: 'outbound',
        status: 'connected',
      ));

      final events = await harness.captureFlowEvents(() async {
        await alice.sendMessage(bob.peerId, 'ACK test message');
      });

      final timings = harness.filterEvents(events, 'CHAT_MSG_SEND_TIMING');
      expect(timings, isNotEmpty);

      final details = timings.first['details'] as Map<String, dynamic>;
      expect(details['outcome'], 'success');
      expect(details['connectionReused'], isTrue);
      expect(details['sendPath'], 'reuse');
      expect(details['elapsedMs'], isA<int>());

      // sendMs is reported for the reuse path
      if (details.containsKey('sendMs')) {
        expect(details['sendMs'], isA<int>());
        expect(details['sendMs'], greaterThanOrEqualTo(0));
      }
    });
  });
}
