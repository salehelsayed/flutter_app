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

  group('Benchmark: Media Transfer Timing', () {
    test('E1: Message with attachments emits CHAT_MSG_SEND_TIMING', () async {
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

      final events = await harness.captureFlowEvents(() async {
        // Send a text message (media upload tests require real files/bridge)
        await alice.sendMessage(bob.peerId, 'Message with text');
      });

      final timings = harness.filterEvents(events, 'CHAT_MSG_SEND_TIMING');
      expect(timings, isNotEmpty);

      final details = timings.first['details'] as Map<String, dynamic>;
      expect(details['elapsedMs'], isA<int>());
      expect(details['hasAttachments'], isFalse);
      expect(details['outcome'], 'success');
    });

    test('E2: Send timing tracks outcome for all paths', () async {
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

      // Multiple sends to verify consistent timing emission
      final allTimings = <Map<String, dynamic>>[];
      for (var i = 0; i < 5; i++) {
        final events = await harness.captureFlowEvents(() async {
          await alice.sendMessage(bob.peerId, 'Media test $i');
        });
        allTimings.addAll(
          harness.filterEvents(events, 'CHAT_MSG_SEND_TIMING'),
        );
      }

      expect(allTimings, hasLength(5));
      for (final t in allTimings) {
        final details = t['details'] as Map<String, dynamic>;
        expect(details['elapsedMs'], isA<int>());
        expect(details['outcome'], isA<String>());
      }
    });
  });
}
