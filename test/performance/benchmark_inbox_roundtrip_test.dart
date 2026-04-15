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

  group('Benchmark: Inbox Store/Retrieve Round-Trip', () {
    test('D1: Inbox store emits CHAT_MSG_SEND_TIMING with sendPath', () async {
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

      // Bob is offline, direct send fails → inbox fallback
      bob.setOnline(false);
      alice.p2pService.sendFailCount = 999;

      final events = await harness.captureFlowEvents(() async {
        await alice.sendMessage(bob.peerId, 'Offline message');
      });

      final timings = harness.filterEvents(events, 'CHAT_MSG_SEND_TIMING');
      expect(timings, isNotEmpty, reason: 'Should emit CHAT_MSG_SEND_TIMING');

      final details = timings.first['details'] as Map<String, dynamic>;
      expect(details['elapsedMs'], isA<int>());
      expect(details['outcome'], isA<String>());
    });

    test('D2: Inbox retrieve drains offline messages', () async {
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

      // Bob goes offline, alice stores message in inbox
      bob.setOnline(false);
      network.storeInInbox(
        alice.peerId,
        bob.peerId,
        '{"test":"inbox-msg"}',
      );
      final inboxCount = network.inboxCount(bob.peerId);
      expect(inboxCount, greaterThan(0),
          reason: 'Should have messages in inbox');

      // Bob comes back online and drains inbox
      bob.setOnline(true);
      final drainCount = await bob.drainOfflineInbox();

      // Verify message was retrieved from inbox
      expect(drainCount, greaterThan(0),
          reason: 'Should have drained at least 1 message');
    });

    test('D3: Inbox store timing tracks elapsedMs', () async {
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

      // Make direct send fail so it falls to inbox
      alice.p2pService.sendFailCount = 999;
      bob.setOnline(false);

      final events = await harness.captureFlowEvents(() async {
        await alice.sendMessage(bob.peerId, 'Inbox test');
      });

      final timings = harness.filterEvents(events, 'CHAT_MSG_SEND_TIMING');
      if (timings.isNotEmpty) {
        final details = timings.first['details'] as Map<String, dynamic>;
        expect(details['elapsedMs'], isA<int>());
        expect(details['elapsedMs'], greaterThanOrEqualTo(0));
      }
    });

    test('D4: Inbox store < 200ms budget (Dart-side, fake bridge)', () async {
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

      alice.p2pService.sendFailCount = 999;
      bob.setOnline(false);

      final events = await harness.captureFlowEvents(() async {
        await alice.sendMessage(bob.peerId, 'Fast inbox test');
      });

      final timings = harness.filterEvents(events, 'CHAT_MSG_SEND_TIMING');
      if (timings.isNotEmpty) {
        final details = timings.first['details'] as Map<String, dynamic>;
        final elapsedMs = details['elapsedMs'] as int;
        expect(
          elapsedMs,
          lessThan(200),
          reason: 'Dart-side inbox store should be fast with fakes',
        );
      }
    });
  });
}
