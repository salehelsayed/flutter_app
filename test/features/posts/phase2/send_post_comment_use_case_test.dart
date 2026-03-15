import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/application/send_post_comment_use_case.dart';
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

PostModel _post(String postId) {
  return PostModel(
    id: postId,
    eventId: 'evt-$postId',
    senderPeerId: 'peer-alice',
    authorPeerId: 'peer-alice',
    authorUsername: 'Alice',
    text: 'Need a ladder',
    audience: PostAudience.allFriends(),
    createdAt: '2026-03-15T10:15:30.000Z',
    visibleAt: '2026-03-15T10:15:30.000Z',
    expiresAt: '2026-03-18T10:15:30.000Z',
    isIncoming: false,
  );
}

void main() {
  late FakeP2PNetwork network;
  late FakeP2PService bobService;
  late InMemoryContactRepository contacts;
  late InMemoryPostRepository posts;

  setUp(() {
    network = FakeP2PNetwork();
    bobService = FakeP2PService(peerId: 'peer-bob', network: network);
    contacts = InMemoryContactRepository();
    posts = InMemoryPostRepository();
    contacts.addTestContact(_contact('peer-alice', 'Alice'));
    contacts.addTestContact(_contact('peer-bob', 'Bob'));
    contacts.addTestContact(_contact('peer-cara', 'Cara'));
  });

  tearDown(() {
    posts.dispose();
  });

  test(
    'comment fanout reuses the persisted recipient set, includes the author, and extends expiry',
    () async {
      await posts.savePost(_post('post-1'));
      await posts.saveRecipientDelivery(
        const PostRecipientDelivery(
          postId: 'post-1',
          recipientPeerId: 'peer-bob',
          deliveryStatus: 'delivered',
          lastAttemptAt: '2026-03-15T10:15:31.000Z',
          deliveryPath: 'direct',
          createdAt: '2026-03-15T10:15:31.000Z',
          updatedAt: '2026-03-15T10:15:31.000Z',
        ),
      );
      await posts.saveRecipientDelivery(
        const PostRecipientDelivery(
          postId: 'post-1',
          recipientPeerId: 'peer-cara',
          deliveryStatus: 'inbox',
          lastAttemptAt: '2026-03-15T10:15:31.000Z',
          deliveryPath: 'inbox',
          createdAt: '2026-03-15T10:15:31.000Z',
          updatedAt: '2026-03-15T10:15:31.000Z',
        ),
      );
      FakeP2PService(peerId: 'peer-alice', network: network);
      final commentedAt = DateTime.now()
          .toUtc()
          .subtract(const Duration(minutes: 1));

      final (result, comment) = await sendPostComment(
        p2pService: bobService,
        postRepo: posts,
        contactRepo: contacts,
        postId: 'post-1',
        senderPeerId: 'peer-bob',
        senderUsername: 'Bob',
        body: 'I can lend one.',
        nowProvider: () => commentedAt,
      );

      expect(result, SendPostCommentResult.success);
      expect(comment, isNotNull);
      expect(comment!.body, 'I can lend one.');
      expect(await posts.loadComments('post-1'), hasLength(1));

      final updatedPost = await posts.getPost('post-1');
      expect(
        updatedPost?.expiresAt,
        commentedAt.add(const Duration(days: 3)).toIso8601String(),
      );
      expect(updatedPost?.lastEngagementAt, commentedAt.toIso8601String());
      expect(network.inboxCount('peer-cara'), 1);

      final inboxMessage =
          network.retrieveInbox('peer-cara').single['message'] as String;
      final payload = jsonDecode(inboxMessage) as Map<String, dynamic>;
      expect(payload['type'], 'post_comment');
      expect(payload['payload']['comment_id'], comment.id);
    },
  );
}
