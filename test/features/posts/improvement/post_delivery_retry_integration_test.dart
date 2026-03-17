import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_app/features/posts/application/pending_post_delivery_retrier.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';

import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';

ContactModel _contact(String peerId, String username) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/dns4/example.invalid/tcp/443',
    username: username,
    signature: 'sig-$peerId',
    scannedAt: '2026-03-15T10:00:00.000Z',
  );
}

void main() {
  late InMemoryPostRepository posts;
  late InMemoryContactRepository contacts;

  setUp(() {
    posts = InMemoryPostRepository();
    contacts = InMemoryContactRepository();
  });

  tearDown(() {
    posts.dispose();
  });

  test(
    'retryPendingPostDeliveries retries unresolved recipients and settles aggregate to sent',
    () async {
      final network = FakeP2PNetwork();
      final p2pService = FakeP2PService(
        peerId: 'peer-self',
        network: network,
      );
      contacts.addTestContact(_contact('peer-bob', 'Bob'));
      contacts.addTestContact(_contact('peer-cara', 'Cara'));

      await posts.savePost(
        const PostModel(
          id: 'post-1',
          eventId: 'evt-1',
          senderPeerId: 'peer-self',
          authorPeerId: 'peer-self',
          authorUsername: 'Alice',
          text: 'Need a ladder',
          audience: PostAudience(kind: PostAudienceKind.allFriends),
          createdAt: '2026-03-15T10:00:00.000Z',
          visibleAt: '2026-03-15T10:00:00.000Z',
          expiresAt: '2026-03-18T10:00:00.000Z',
          isIncoming: false,
          deliveryStatus: 'partial',
        ),
      );
      await posts.saveRecipientDelivery(
        const PostRecipientDelivery(
          postId: 'post-1',
          recipientPeerId: 'peer-bob',
          deliveryStatus: 'delivered',
          lastAttemptAt: '2026-03-15T10:00:01.000Z',
          deliveryPath: 'direct',
          createdAt: '2026-03-15T10:00:01.000Z',
          updatedAt: '2026-03-15T10:00:01.000Z',
        ),
      );
      await posts.saveRecipientDelivery(
        const PostRecipientDelivery(
          postId: 'post-1',
          recipientPeerId: 'peer-cara',
          deliveryStatus: 'failed',
          lastAttemptAt: '2026-03-15T10:00:02.000Z',
          deliveryPath: 'failed',
          lastError: 'direct_and_inbox_failed',
          createdAt: '2026-03-15T10:00:02.000Z',
          updatedAt: '2026-03-15T10:00:02.000Z',
        ),
      );

      final retried = await retryPendingPostDeliveries(
        postRepo: posts,
        contactRepo: contacts,
        p2pService: p2pService,
      );

      expect(retried, 1);
      expect((await posts.getPost('post-1'))!.deliveryStatus, 'sent');
      expect(network.inboxCount('peer-bob'), 0);
      final inboxMessage = network.retrieveInbox('peer-cara').single;
      final payload = jsonDecode(inboxMessage['message'] as String)
          as Map<String, dynamic>;
      final envelopePayload = payload['payload'] as Map<String, dynamic>;
      expect(
        envelopePayload['recipient_peer_ids'],
        unorderedEquals(<String>['peer-bob', 'peer-cara']),
      );
    },
  );

  test(
    'retryPendingPostDeliveries preserves persisted nearby distance when rebuilding jobs',
    () async {
      final network = FakeP2PNetwork();
      final p2pService = FakeP2PService(
        peerId: 'peer-self',
        network: network,
      );
      contacts.addTestContact(_contact('peer-bob', 'Bob'));

      await posts.savePost(
        const PostModel(
          id: 'post-nearby',
          eventId: 'evt-nearby',
          senderPeerId: 'peer-self',
          authorPeerId: 'peer-self',
          authorUsername: 'Alice',
          text: 'Coffee nearby',
          audience: PostAudience(
            kind: PostAudienceKind.peopleNearby,
            radiusM: 500,
            scopeLabel: 'Shared nearby',
          ),
          createdAt: '2026-03-15T10:00:00.000Z',
          visibleAt: '2026-03-15T10:00:00.000Z',
          expiresAt: '2026-03-18T10:00:00.000Z',
          isIncoming: false,
          deliveryStatus: 'failed',
        ),
      );
      await posts.saveRecipientDelivery(
        const PostRecipientDelivery(
          postId: 'post-nearby',
          recipientPeerId: 'peer-bob',
          deliveryStatus: 'failed',
          lastAttemptAt: '2026-03-15T10:00:02.000Z',
          deliveryPath: 'failed',
          lastError: 'direct_and_inbox_failed',
          createdAt: '2026-03-15T10:00:02.000Z',
          updatedAt: '2026-03-15T10:00:02.000Z',
          nearbyDistanceM: 87,
        ),
      );

      final retried = await retryPendingPostDeliveries(
        postRepo: posts,
        contactRepo: contacts,
        p2pService: p2pService,
      );

      expect(retried, 1);
      final inboxMessage = network.retrieveInbox('peer-bob').single;
      final payload = jsonDecode(inboxMessage['message'] as String)
          as Map<String, dynamic>;
      final envelopePayload = payload['payload'] as Map<String, dynamic>;
      final nearbyContext =
          envelopePayload['nearby_context'] as Map<String, dynamic>;
      expect(nearbyContext['distance_m'], 87);
    },
  );

  test(
    'retryPendingPostDeliveries uses the default concurrency cap of 25',
    () async {
      final recipientPeerIds = List<String>.generate(
        30,
        (index) => 'peer-${index.toString().padLeft(2, '0')}',
      );
      final sendGates = <String, Completer<void>>{
        for (final peerId in recipientPeerIds) peerId: Completer<void>(),
      };
      final service = _ControlledP2PService(
        peerId: 'peer-self',
        network: FakeP2PNetwork(),
        policies: {
          for (final peerId in recipientPeerIds)
            peerId: _PeerPolicy(sendGate: sendGates[peerId]),
        },
      );
      addTearDown(service.dispose);

      await posts.savePost(
        const PostModel(
          id: 'post-25',
          eventId: 'evt-25',
          senderPeerId: 'peer-self',
          authorPeerId: 'peer-self',
          authorUsername: 'Alice',
          text: 'Need a ladder',
          audience: PostAudience(kind: PostAudienceKind.allFriends),
          createdAt: '2026-03-15T10:00:00.000Z',
          visibleAt: '2026-03-15T10:00:00.000Z',
          expiresAt: '2026-03-18T10:00:00.000Z',
          isIncoming: false,
          deliveryStatus: 'failed',
        ),
      );

      for (final peerId in recipientPeerIds) {
        contacts.addTestContact(_contact(peerId, peerId));
        await posts.saveRecipientDelivery(
          PostRecipientDelivery(
            postId: 'post-25',
            recipientPeerId: peerId,
            deliveryStatus: 'failed',
            lastAttemptAt: '2026-03-15T10:00:02.000Z',
            deliveryPath: 'failed',
            lastError: 'direct_and_inbox_failed',
            createdAt: '2026-03-15T10:00:02.000Z',
            updatedAt: '2026-03-15T10:00:02.000Z',
          ),
        );
      }

      final retryFuture = retryPendingPostDeliveries(
        postRepo: posts,
        contactRepo: contacts,
        p2pService: service,
      );

      await service
          .waitForSendCount(25)
          .timeout(const Duration(milliseconds: 200));

      expect(service.maxInFlightSends, 25);
      expect(service.sendStartOrder, recipientPeerIds.take(25).toList());

      sendGates[recipientPeerIds.first]!.complete();
      await service
          .waitForSendCount(26)
          .timeout(const Duration(milliseconds: 200));

      expect(service.maxInFlightSends, 25);
      expect(service.sendStartOrder, recipientPeerIds.take(26).toList());

      for (final gate in sendGates.values) {
        if (!gate.isCompleted) {
          gate.complete();
        }
      }

      final retried = await retryFuture;
      expect(retried, 1);
      expect((await posts.getPost('post-25'))!.deliveryStatus, 'sent');
      expect(service.maxInFlightSends, 25);
    },
  );
}

class _ControlledP2PService extends FakeP2PService {
  final Map<String, _PeerPolicy> policies;
  final List<String> sendStartOrder = <String>[];
  final StreamController<void> _sendStarted =
      StreamController<void>.broadcast();

  int _inFlightSends = 0;
  int maxInFlightSends = 0;

  _ControlledP2PService({
    required super.peerId,
    required super.network,
    this.policies = const <String, _PeerPolicy>{},
  });

  Future<void> waitForSendCount(int count) async {
    while (sendStartOrder.length < count) {
      await _sendStarted.stream.first;
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
    _sendStarted.add(null);

    try {
      final gate = policy.sendGate;
      if (gate != null) {
        await gate.future;
      }
      return const SendMessageResult(sent: true, reply: 'received');
    } finally {
      _inFlightSends--;
    }
  }

  @override
  void dispose() {
    _sendStarted.close();
    super.dispose();
  }
}

class _PeerPolicy {
  final Completer<void>? sendGate;

  const _PeerPolicy({this.sendGate});
}
