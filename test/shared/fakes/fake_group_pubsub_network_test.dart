import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'fake_group_pubsub_network.dart';

void main() {
  group('FakeGroupPubSubNetwork', () {
    test('GO-012 seeded drops and scheduled delays are repeatable', () async {
      Future<_Go012Run> runScenario() async {
        final scheduledDelays = <Duration>[];
        final network = FakeGroupPubSubNetwork(
          randomSeed: 12012,
          delay: (duration) {
            scheduledDelays.add(duration);
            return Future<void>.value();
          },
        );

        final alice = network.registerPeer('alice-peer');
        final bob = network.registerPeer('bob-peer');
        final charlie = network.registerPeer('charlie-peer');
        addTearDown(() async {
          await alice.close();
          await bob.close();
          await charlie.close();
        });

        const groupId = 'group-go012-seeded';
        network.subscribe(groupId, 'alice-peer');
        network.subscribe(groupId, 'bob-peer');
        network.subscribe(groupId, 'charlie-peer');
        network.dropRate = 0.35;
        network.deliveryDelay = const Duration(seconds: 7);

        final deliveries = <String>[];
        final subscriptions = <StreamSubscription<Map<String, dynamic>>>[
          bob.stream.listen(
            (event) => deliveries.add('bob:${event['messageId']}'),
          ),
          charlie.stream.listen(
            (event) => deliveries.add('charlie:${event['messageId']}'),
          ),
        ];

        for (var index = 0; index < 12; index++) {
          await network.publish(groupId, 'alice-peer', {
            'messageId': 'msg-$index',
            'text': 'GO-012 message $index',
          });
        }

        await Future<void>.delayed(Duration.zero);
        await Future.wait(
          subscriptions.map((subscription) => subscription.cancel()),
        );

        return _Go012Run(
          deliveries: deliveries,
          scheduledDelays: scheduledDelays,
        );
      }

      final first = await runScenario();
      final second = await runScenario();

      expect(first.deliveries, isNotEmpty);
      expect(first.scheduledDelays, hasLength(first.deliveries.length));
      expect(first.scheduledDelays, everyElement(const Duration(seconds: 7)));
      expect(second.deliveries, first.deliveries);
      expect(second.scheduledDelays, first.scheduledDelays);
    });

    test('GO-012 resetCounters restores seeded drop sequence', () async {
      final network = FakeGroupPubSubNetwork(randomSeed: 12012);
      final alice = network.registerPeer('alice-peer');
      final bob = network.registerPeer('bob-peer');
      addTearDown(() async {
        await alice.close();
        await bob.close();
      });

      const groupId = 'group-go012-reset';
      network.subscribe(groupId, 'alice-peer');
      network.subscribe(groupId, 'bob-peer');
      network.dropRate = 0.5;

      Future<List<String>> publishBatch(String prefix) async {
        final delivered = <String>[];
        final subscription = bob.stream.listen(
          (event) => delivered.add(event['messageId'] as String),
        );
        for (var index = 0; index < 16; index++) {
          await network.publish(groupId, 'alice-peer', {
            'messageId': '$prefix-$index',
            'text': 'GO-012 reset message $index',
          });
        }
        await Future<void>.delayed(Duration.zero);
        await subscription.cancel();
        return delivered.map((id) => id.split('-').last).toList();
      }

      final first = await publishBatch('first');
      network.resetCounters();
      network.dropRate = 0.5;
      final second = await publishBatch('second');

      expect(first, isNotEmpty);
      expect(second, first);
    });
  });
}

class _Go012Run {
  const _Go012Run({required this.deliveries, required this.scheduledDelays});

  final List<String> deliveries;
  final List<Duration> scheduledDelays;
}
