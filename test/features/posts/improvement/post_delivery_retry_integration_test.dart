import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
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
}
