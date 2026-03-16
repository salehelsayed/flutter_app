import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_app/features/posts/application/post_follow_on_delivery.dart';
import 'package:flutter_app/features/posts/application/post_pin_delivery_support.dart';

import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';

void main() {
  late FakeP2PNetwork network;

  setUp(() {
    network = FakeP2PNetwork();
  });

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
      final service = _ControlledP2PService(
        peerId: 'peer-alice',
        network: network,
        policies: {
          for (final peerId in recipientPeerIds)
            peerId: _PeerPolicy(sendGate: sendGates[peerId]),
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
      await _drainMicrotasks();

      expect(service.maxInFlightSends, 2);
      expect(service.sendStartOrder, recipientPeerIds.take(2).toList());

      sendGates['peer-bob']!.complete();
      await service.waitForSendCount(3);
      await _drainMicrotasks();

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
      final service = _ControlledP2PService(
        peerId: 'peer-alice',
        network: network,
        policies: const {
          'peer-bob': _PeerPolicy(sendResult: false, storeInInboxResult: true),
          'peer-cara': _PeerPolicy(
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
      final service = _ControlledP2PService(
        peerId: 'peer-alice',
        network: network,
        policies: const {
          'peer-bob': _PeerPolicy(sendResult: true),
          'peer-cara': _PeerPolicy(
            sendResult: false,
            storeInInboxResult: false,
          ),
        },
      );
      final postRepo = InMemoryPostRepository();
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

Future<void> _drainMicrotasks([int turns = 3]) async {
  for (var index = 0; index < turns; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _ControlledP2PService extends FakeP2PService {
  final Map<String, _PeerPolicy> policies;
  final List<String> sendStartOrder = <String>[];
  final List<String> inboxAttempts = <String>[];

  int _inFlightSends = 0;
  int maxInFlightSends = 0;

  _ControlledP2PService({
    required super.peerId,
    required super.network,
    this.policies = const <String, _PeerPolicy>{},
  });

  Future<void> waitForSendCount(int count) async {
    while (sendStartOrder.length < count) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String targetPeerId,
    String message, {
    int? timeoutMs,
  }) async {
    final policy = policies[targetPeerId] ?? const _PeerPolicy();
    sendStartOrder.add(targetPeerId);
    _inFlightSends++;
    if (_inFlightSends > maxInFlightSends) {
      maxInFlightSends = _inFlightSends;
    }

    try {
      final gate = policy.sendGate;
      if (gate != null) {
        await gate.future;
      }
      return SendMessageResult(
        sent: policy.sendResult ?? true,
        reply: (policy.sendResult ?? true) ? 'received' : null,
      );
    } finally {
      _inFlightSends--;
    }
  }

  @override
  Future<bool> storeInInbox(String toPeerId, String message) async {
    inboxAttempts.add(toPeerId);
    return (policies[toPeerId] ?? const _PeerPolicy()).storeInInboxResult ??
        true;
  }
}

class _PeerPolicy {
  final Completer<void>? sendGate;
  final bool? sendResult;
  final bool? storeInInboxResult;

  const _PeerPolicy({this.sendGate, this.sendResult, this.storeInInboxResult});
}
