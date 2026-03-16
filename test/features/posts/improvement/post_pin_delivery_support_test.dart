import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/posts/application/post_follow_on_delivery.dart';
import 'package:flutter_app/features/posts/application/post_pin_delivery_support.dart';

import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';
import 'support/controlled_post_pin_delivery_harness.dart';

void main() {
  late FakeP2PNetwork network;

  setUp(() {
    network = FakeP2PNetwork();
  });

  test(
    'sendPostPinEnvelope default pin fanout allows up to 25 in-flight recipients',
    () async {
      final recipientPeerIds = _buildRecipientPeerIds(30);
      final sendGates = <String, Completer<void>>{
        for (final peerId in recipientPeerIds) peerId: Completer<void>(),
      };
      final service = ControlledPostPinDeliveryP2PService(
        peerId: 'peer-alice',
        network: network,
        policies: {
          for (final peerId in recipientPeerIds)
            peerId: PostPinDeliveryPeerPolicy(sendGate: sendGates[peerId]),
        },
      );
      addTearDown(service.dispose);

      final sendFuture = sendPostPinEnvelope(
        p2pService: service,
        recipientPeerIds: recipientPeerIds,
        envelope: '{"type":"post_pin_update"}',
      );

      await service.waitForSendCount(25);
      await drainPostPinDeliveryMicrotasks();

      expect(service.maxInFlightSends, 25);
      expect(
        service.sendStartOrder.take(25).toList(growable: false),
        recipientPeerIds.take(25).toList(growable: false),
      );

      sendGates[recipientPeerIds.first]!.complete();
      await service.waitForSendCount(26);
      await drainPostPinDeliveryMicrotasks();

      expect(service.maxInFlightSends, 25);
      expect(
        service.sendStartOrder.take(26).toList(growable: false),
        recipientPeerIds.take(26).toList(growable: false),
      );

      for (final gate in sendGates.values) {
        if (!gate.isCompleted) {
          gate.complete();
        }
      }

      final result = await sendFuture;
      expect(result.settlement, PostFollowOnSettlement.fullySettled);
      expect(service.maxInFlightSends, 25);
    },
  );

  test(
    'sendPostPinEnvelope lets later recipients start before an earlier slow recipient completes by default',
    () async {
      final recipientPeerIds = _buildRecipientPeerIds(26);
      final sendGates = <String, Completer<void>>{
        for (final peerId in recipientPeerIds) peerId: Completer<void>(),
      };
      final service = ControlledPostPinDeliveryP2PService(
        peerId: 'peer-alice',
        network: network,
        policies: {
          for (final peerId in recipientPeerIds)
            peerId: PostPinDeliveryPeerPolicy(sendGate: sendGates[peerId]),
        },
      );
      addTearDown(service.dispose);

      final sendFuture = sendPostPinEnvelope(
        p2pService: service,
        recipientPeerIds: recipientPeerIds,
        envelope: '{"type":"post_pin_remove"}',
      );

      await service.waitForSendCount(25);
      await drainPostPinDeliveryMicrotasks(6);

      expect(service.maxInFlightSends, 25);
      expect(service.sendStartOrder.first, recipientPeerIds.first);
      expect(
        service.sendStartOrder.skip(1).toList(growable: false),
        recipientPeerIds.skip(1).take(24).toList(growable: false),
      );

      sendGates[recipientPeerIds.first]!.complete();
      await service.waitForSendCount(26);
      await drainPostPinDeliveryMicrotasks();

      expect(service.maxInFlightSends, 25);
      expect(service.sendStartOrder.last, recipientPeerIds.last);

      for (final gate in sendGates.values) {
        if (!gate.isCompleted) {
          gate.complete();
        }
      }

      await sendFuture;
    },
  );

  test(
    'sendPostPinEnvelope default fanout never exceeds 25 in-flight recipients',
    () async {
      final recipientPeerIds = _buildRecipientPeerIds(30);
      final sendGates = <String, Completer<void>>{
        for (final peerId in recipientPeerIds) peerId: Completer<void>(),
      };
      final service = ControlledPostPinDeliveryP2PService(
        peerId: 'peer-alice',
        network: network,
        policies: {
          for (final peerId in recipientPeerIds)
            peerId: PostPinDeliveryPeerPolicy(sendGate: sendGates[peerId]),
        },
      );
      addTearDown(service.dispose);

      final sendFuture = sendPostPinEnvelope(
        p2pService: service,
        recipientPeerIds: recipientPeerIds,
        envelope: '{"type":"post_pin_update"}',
      );

      await service.waitForSendCount(25);
      await drainPostPinDeliveryMicrotasks(6);

      expect(service.maxInFlightSends, 25);
      expect(service.sendStartOrder, hasLength(25));

      sendGates[recipientPeerIds[4]]!.complete();
      await service.waitForSendCount(26);
      await drainPostPinDeliveryMicrotasks();

      expect(service.maxInFlightSends, 25);
      expect(service.sendStartOrder, hasLength(26));

      for (final gate in sendGates.values) {
        if (!gate.isCompleted) {
          gate.complete();
        }
      }

      final result = await sendFuture;
      expect(result.settlement, PostFollowOnSettlement.fullySettled);
    },
  );

  test(
    'sendPostPinEnvelope never exceeds the configured concurrency limit',
    () async {
      const recipientPeerIds = <String>[
        'peer-bob',
        'peer-cara',
        'peer-drew',
        'peer-erin',
      ];
      final sendGates = <String, Completer<void>>{
        for (final peerId in recipientPeerIds) peerId: Completer<void>(),
      };
      final service = ControlledPostPinDeliveryP2PService(
        peerId: 'peer-alice',
        network: network,
        policies: {
          for (final peerId in recipientPeerIds)
            peerId: PostPinDeliveryPeerPolicy(sendGate: sendGates[peerId]),
        },
      );
      addTearDown(service.dispose);

      final sendFuture = sendPostPinEnvelope(
        p2pService: service,
        recipientPeerIds: recipientPeerIds,
        envelope: '{"type":"post_pin_update"}',
        maxConcurrentRecipients: 2,
      );

      await service.waitForSendCount(2);
      await drainPostPinDeliveryMicrotasks();

      expect(service.maxInFlightSends, 2);
      expect(service.sendStartOrder, recipientPeerIds.take(2).toList());

      sendGates['peer-bob']!.complete();
      await service.waitForSendCount(3);
      await drainPostPinDeliveryMicrotasks();

      expect(service.maxInFlightSends, 2);
      expect(service.sendStartOrder, recipientPeerIds.take(3).toList());

      for (final gate in sendGates.values) {
        if (!gate.isCompleted) {
          gate.complete();
        }
      }

      final result = await sendFuture;
      expect(result.settlement, PostFollowOnSettlement.fullySettled);
      expect(result.didDeliverAny, isTrue);
      expect(service.maxInFlightSends, 2);
    },
  );

  test(
    'sendPostPinEnvelope returns structured settlement when some recipients store and others stay unresolved',
    () async {
      final service = ControlledPostPinDeliveryP2PService(
        peerId: 'peer-alice',
        network: network,
        policies: const {
          'peer-bob': PostPinDeliveryPeerPolicy(
            sendResult: false,
            storeInInboxResult: true,
          ),
          'peer-cara': PostPinDeliveryPeerPolicy(
            sendResult: false,
            storeInInboxResult: false,
          ),
        },
      );
      addTearDown(service.dispose);

      final result = await sendPostPinEnvelope(
        p2pService: service,
        recipientPeerIds: const <String>['peer-bob', 'peer-cara'],
        envelope: '{"type":"post_pin_remove"}',
        maxConcurrentRecipients: 2,
      );

      expect(result.settlement, PostFollowOnSettlement.partiallySettled);
      expect(result.didDeliverAny, isTrue);
      expect(
        result.recipientResults
            .map(
              (recipient) =>
                  '${recipient.recipientPeerId}:${recipient.deliveryStatus}:${recipient.deliveryPath}',
            )
            .toList(growable: false),
        <String>['peer-bob:inbox:inbox', 'peer-cara:failed:inbox'],
      );
      expect(
        service.sendStartOrder,
        containsAll(const <String>['peer-bob', 'peer-cara']),
      );
      expect(
        service.inboxAttempts,
        containsAll(const <String>['peer-bob', 'peer-cara']),
      );
    },
  );

  test(
    'queueAndSendPostPinFollowOn persists outbox rows and excludes settled recipients from retry',
    () async {
      final pendingSnapshot = Completer<List<String>>();
      final postRepo = InMemoryPostRepository();
      final service = ControlledPostPinDeliveryP2PService(
        peerId: 'peer-alice',
        network: network,
        policies: {
          'peer-bob': PostPinDeliveryPeerPolicy(
            sendResult: true,
            onSendStart: (_) async {
              final deliveries = await postRepo
                  .loadFollowOnOutboxRecipientDeliveries('evt-pin-remove-1');
              pendingSnapshot.complete(
                deliveries
                    .map(
                      (delivery) =>
                          '${delivery.recipientPeerId}:${delivery.deliveryStatus}:${delivery.deliveryPath}',
                    )
                    .toList(growable: false),
              );
            },
          ),
          'peer-cara': const PostPinDeliveryPeerPolicy(
            sendResult: false,
            storeInInboxResult: false,
          ),
        },
      );
      addTearDown(service.dispose);
      addTearDown(postRepo.dispose);

      final result = await queueAndSendPostPinFollowOn(
        postRepo: postRepo,
        p2pService: service,
        eventId: 'evt-pin-remove-1',
        eventType: postPinRemoveFollowOnEventType,
        postId: 'post-1',
        senderPeerId: 'peer-alice',
        envelope: '{"type":"post_pin_remove"}',
        createdAt: '2026-03-15T11:25:00.000Z',
        recipientPeerIds: const <String>['peer-bob', 'peer-cara'],
      );

      expect(await pendingSnapshot.future, <String>[
        'peer-bob:pending:queued',
        'peer-cara:pending:queued',
      ]);
      expect(result.settlement, PostFollowOnSettlement.partiallySettled);
      expect(
        result.recipientResults.map((result) => result.recipientPeerId),
        <String>['peer-bob', 'peer-cara'],
      );

      final storedDeliveries = await postRepo
          .loadFollowOnOutboxRecipientDeliveries('evt-pin-remove-1');
      expect(storedDeliveries, hasLength(2));
      expect(storedDeliveries.first.deliveryStatus, 'delivered');
      expect(storedDeliveries.last.deliveryStatus, 'failed');

      final retryableJobs = await postRepo.loadRetryableFollowOnOutboxJobs();
      expect(retryableJobs, hasLength(1));
      expect(
        retryableJobs.single.recipientDeliveries.map(
          (delivery) => delivery.recipientPeerId,
        ),
        <String>['peer-cara'],
      );
    },
  );
}

List<String> _buildRecipientPeerIds(int count) {
  return List<String>.generate(
    count,
    (index) => 'peer-${(index + 1).toString().padLeft(2, '0')}',
    growable: false,
  );
}
