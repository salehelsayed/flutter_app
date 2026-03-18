import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_app/features/posts/application/post_follow_on_delivery.dart';

import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';

void main() {
  late FakeP2PNetwork network;

  setUp(() {
    network = FakeP2PNetwork();
  });

  test(
    'fanoutPostFollowOnEnvelope never exceeds the configured concurrency limit',
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

      final sendFuture = fanoutPostFollowOnEnvelope(
        p2pService: service,
        recipientPeerIds: recipientPeerIds,
        envelope: '{"type":"post_reaction"}',
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
    'fanoutPostFollowOnEnvelope reports a partial settlement when only some recipients settle',
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

      final result = await fanoutPostFollowOnEnvelope(
        p2pService: service,
        recipientPeerIds: const <String>['peer-bob', 'peer-cara'],
        envelope: '{"type":"post_comment"}',
        maxConcurrentRecipients: 2,
      );

      expect(result.settlement, PostFollowOnSettlement.partiallySettled);
      expect(result.didDeliverAny, isTrue);
      expect(
        result.recipientResults
            .where((recipient) => recipient.isSettled)
            .map((recipient) => recipient.recipientPeerId),
        const <String>['peer-bob'],
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
    'fanoutPostFollowOnEnvelope preserves default direct-send error behavior',
    () async {
      final service = _ControlledP2PService(
        peerId: 'peer-alice',
        network: network,
        policies: const {
          'peer-bob': _PeerPolicy(throwOnSend: true, storeInInboxResult: true),
        },
      );
      addTearDown(service.dispose);

      await expectLater(
        fanoutPostFollowOnEnvelope(
          p2pService: service,
          recipientPeerIds: const <String>['peer-bob'],
          envelope: '{"type":"post_comment"}',
        ),
        throwsA(isA<StateError>()),
      );
      expect(service.inboxAttempts, isEmpty);
    },
  );

  test(
    'fanoutPostFollowOnEnvelope can fall back after a direct-send error when requested',
    () async {
      final service = _ControlledP2PService(
        peerId: 'peer-alice',
        network: network,
        policies: const {
          'peer-bob': _PeerPolicy(throwOnSend: true, storeInInboxResult: true),
          'peer-cara': _PeerPolicy(sendResult: true),
        },
      );
      addTearDown(service.dispose);

      final result = await fanoutPostFollowOnEnvelope(
        p2pService: service,
        recipientPeerIds: const <String>['peer-bob', 'peer-cara'],
        envelope: '{"type":"post_presence_update"}',
        maxConcurrentRecipients: 1,
        fallbackToInboxOnDirectSendError: true,
      );

      expect(result.settlement, PostFollowOnSettlement.fullySettled);
      expect(result.didDeliverAny, isTrue);
      expect(service.sendStartOrder, const <String>['peer-bob', 'peer-cara']);
      expect(service.inboxAttempts, const <String>['peer-bob']);
    },
  );

  test(
    'fanoutPostFollowOnEnvelope reports not settled when no recipient settles',
    () async {
      final service = _ControlledP2PService(
        peerId: 'peer-alice',
        network: network,
        policies: const {
          'peer-bob': _PeerPolicy(sendResult: false, storeInInboxResult: false),
          'peer-cara': _PeerPolicy(
            sendResult: false,
            storeInInboxResult: false,
          ),
        },
      );
      addTearDown(service.dispose);

      final result = await fanoutPostFollowOnEnvelope(
        p2pService: service,
        recipientPeerIds: const <String>['peer-bob', 'peer-cara'],
        envelope: '{"type":"post_pass_along"}',
        maxConcurrentRecipients: 2,
      );

      expect(result.settlement, PostFollowOnSettlement.notSettled);
      expect(result.didDeliverAny, isFalse);
      expect(
        result.recipientResults.every((recipient) => !recipient.isSettled),
        isTrue,
      );
    },
  );

  test(
    'fanoutPostFollowOnEnvelope discovers and dials before direct send',
    () async {
      final service = _ControlledP2PService(
        peerId: 'peer-alice',
        network: network,
        policies: const {
          'peer-bob': _PeerPolicy(requireDiscoverAndDialBeforeSend: true),
        },
      );
      addTearDown(service.dispose);

      final result = await fanoutPostFollowOnEnvelope(
        p2pService: service,
        recipientPeerIds: const <String>['peer-bob'],
        envelope: '{"type":"post_comment"}',
      );

      expect(result.settlement, PostFollowOnSettlement.fullySettled);
      expect(service.discoverAttempts, <String>['peer-bob']);
      expect(service.dialAttempts, <String>['peer-bob']);
      expect(service.inboxAttempts, isEmpty);
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
  final List<String> discoverAttempts = <String>[];
  final List<String> dialAttempts = <String>[];
  final Set<String> _dialedPeers = <String>{};

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
    if (policy.requireDiscoverAndDialBeforeSend &&
        !_dialedPeers.contains(targetPeerId)) {
      return const SendMessageResult(sent: false);
    }
    sendStartOrder.add(targetPeerId);
    _inFlightSends++;
    if (_inFlightSends > maxInFlightSends) {
      maxInFlightSends = _inFlightSends;
    }

    try {
      if (policy.throwOnSend) {
        throw StateError('send failed for $targetPeerId');
      }
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

  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId, {int? timeoutMs}) async {
    discoverAttempts.add(peerId);
    return DiscoveredPeer(
      id: peerId,
      addresses: <String>['/ip4/127.0.0.1/tcp/4001/p2p/$peerId'],
    );
  }

  @override
  Future<bool> dialPeer(
    String peerId, {
    List<String>? addresses,
    int? timeoutMs,
  }) async {
    dialAttempts.add(peerId);
    _dialedPeers.add(peerId);
    return true;
  }
}

class _PeerPolicy {
  final Completer<void>? sendGate;
  final bool? sendResult;
  final bool? storeInInboxResult;
  final bool throwOnSend;
  final bool requireDiscoverAndDialBeforeSend;

  const _PeerPolicy({
    this.sendGate,
    this.sendResult,
    this.storeInInboxResult,
    this.throwOnSend = false,
    this.requireDiscoverAndDialBeforeSend = false,
  });
}
