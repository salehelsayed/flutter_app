import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/application/send_post_comment_reaction_use_case.dart';
import 'package:flutter_app/features/posts/application/send_post_reaction_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_comment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_origin_model.dart';
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
    'post heart fanout reuses the persisted recipient set and includes the author',
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

      final (result, reaction) = await sendPostReaction(
        p2pService: bobService,
        postRepo: posts,
        contactRepo: contacts,
        postId: 'post-1',
        senderPeerId: 'peer-bob',
        isActive: true,
      );

      expect(result, SendPostReactionResult.success);
      expect(reaction, isNotNull);
      expect(network.inboxCount('peer-cara'), 1);

      final inboxMessage =
          network.retrieveInbox('peer-cara').single['message'] as String;
      final payload = jsonDecode(inboxMessage) as Map<String, dynamic>;
      expect(payload['type'], 'post_reaction');
      expect(payload['payload']['reaction_id'], 'post_heart:post-1:peer-bob');
    },
  );

  test('post heart is persisted locally before delivery completes', () async {
    await posts.savePost(_post('post-1'));
    await posts.saveRecipientDelivery(
      const PostRecipientDelivery(
        postId: 'post-1',
        recipientPeerId: 'peer-cara',
        deliveryStatus: 'delivered',
        lastAttemptAt: '2026-03-15T10:15:31.000Z',
        deliveryPath: 'direct',
        createdAt: '2026-03-15T10:15:31.000Z',
        updatedAt: '2026-03-15T10:15:31.000Z',
      ),
    );
    FakeP2PService(peerId: 'peer-alice', network: network);
    FakeP2PService(peerId: 'peer-cara', network: network);
    network.deliveryDelay = const Duration(milliseconds: 150);

    final sendFuture = sendPostReaction(
      p2pService: bobService,
      postRepo: posts,
      contactRepo: contacts,
      postId: 'post-1',
      senderPeerId: 'peer-bob',
      isActive: true,
    );

    await Future<void>.delayed(const Duration(milliseconds: 20));

    final localReactions = await posts.loadPostReactions('post-1');
    expect(localReactions, hasLength(1));
    expect(
      (await posts.getFollowOnOutboxEvent(
        localReactions.single.eventId,
      ))?.eventType,
      'post_reaction',
    );
    expect(
      (await posts.loadFollowOnOutboxRecipientDeliveries(
        localReactions.single.eventId,
      )).map((delivery) => delivery.deliveryStatus),
      everyElement('pending'),
    );

    final (result, reaction) = await sendFuture;
    expect(result, SendPostReactionResult.success);
    expect(reaction?.reactionId, localReactions.single.reactionId);
  });

  test(
    'post heart keeps local sender state and retryable outbox rows when no recipient settles',
    () async {
      await posts.savePost(_post('post-1'));
      await posts.saveRecipientDelivery(
        const PostRecipientDelivery(
          postId: 'post-1',
          recipientPeerId: 'peer-cara',
          deliveryStatus: 'delivered',
          lastAttemptAt: '2026-03-15T10:15:31.000Z',
          deliveryPath: 'direct',
          createdAt: '2026-03-15T10:15:31.000Z',
          updatedAt: '2026-03-15T10:15:31.000Z',
        ),
      );
      network.deliveryFails = true;
      network.inboxDisabled = true;

      final (result, reaction) = await sendPostReaction(
        p2pService: bobService,
        postRepo: posts,
        contactRepo: contacts,
        postId: 'post-1',
        senderPeerId: 'peer-bob',
        isActive: true,
      );

      expect(result, SendPostReactionResult.queuedForRetry);
      expect(reaction, isNotNull);
      expect(await posts.loadPostReactions('post-1'), hasLength(1));
      final retryableJobs = await posts.loadRetryableFollowOnOutboxJobs();
      expect(retryableJobs, hasLength(1));
      expect(retryableJobs.single.event.eventType, 'post_reaction');
      expect(
        retryableJobs.single.recipientDeliveries.map(
          (delivery) => delivery.recipientPeerId,
        ),
        <String>['peer-alice', 'peer-cara'],
      );
      expect(
        retryableJobs.single.recipientDeliveries.map(
          (delivery) => delivery.deliveryStatus,
        ),
        everyElement('failed'),
      );
    },
  );

  test(
    'comment heart fanout reuses the persisted recipient set and local state updates',
    () async {
      await posts.savePost(_post('post-1'));
      await posts.saveComment(
        const PostCommentModel(
          id: 'comment-1',
          eventId: 'evt-comment-1',
          postId: 'post-1',
          senderPeerId: 'peer-alice',
          authorUsername: 'Alice',
          body: 'I can lend one.',
          commentedAt: '2026-03-15T11:00:00.000Z',
        ),
      );
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
          deliveryStatus: 'delivered',
          lastAttemptAt: '2026-03-15T10:15:31.000Z',
          deliveryPath: 'direct',
          createdAt: '2026-03-15T10:15:31.000Z',
          updatedAt: '2026-03-15T10:15:31.000Z',
        ),
      );
      FakeP2PService(peerId: 'peer-alice', network: network);
      FakeP2PService(peerId: 'peer-cara', network: network);

      final (result, reaction) = await sendPostCommentReaction(
        p2pService: bobService,
        postRepo: posts,
        contactRepo: contacts,
        postId: 'post-1',
        commentId: 'comment-1',
        senderPeerId: 'peer-bob',
        isActive: true,
      );

      expect(result, SendPostCommentReactionResult.success);
      expect(reaction, isNotNull);
      expect(await posts.loadCommentReactions('comment-1'), hasLength(1));
      expect(network.deliverCallCount, greaterThanOrEqualTo(2));
    },
  );

  test(
    'comment heart is persisted locally before delivery completes',
    () async {
      await posts.savePost(_post('post-1'));
      await posts.saveComment(
        const PostCommentModel(
          id: 'comment-1',
          eventId: 'evt-comment-1',
          postId: 'post-1',
          senderPeerId: 'peer-alice',
          authorUsername: 'Alice',
          body: 'I can lend one.',
          commentedAt: '2026-03-15T11:00:00.000Z',
        ),
      );
      await posts.saveRecipientDelivery(
        const PostRecipientDelivery(
          postId: 'post-1',
          recipientPeerId: 'peer-cara',
          deliveryStatus: 'delivered',
          lastAttemptAt: '2026-03-15T10:15:31.000Z',
          deliveryPath: 'direct',
          createdAt: '2026-03-15T10:15:31.000Z',
          updatedAt: '2026-03-15T10:15:31.000Z',
        ),
      );
      FakeP2PService(peerId: 'peer-alice', network: network);
      FakeP2PService(peerId: 'peer-cara', network: network);
      network.deliveryDelay = const Duration(milliseconds: 150);

      final sendFuture = sendPostCommentReaction(
        p2pService: bobService,
        postRepo: posts,
        contactRepo: contacts,
        postId: 'post-1',
        commentId: 'comment-1',
        senderPeerId: 'peer-bob',
        isActive: true,
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));

      final localReactions = await posts.loadCommentReactions('comment-1');
      expect(localReactions, hasLength(1));
      expect(
        (await posts.getFollowOnOutboxEvent(
          localReactions.single.eventId,
        ))?.eventType,
        'post_comment_reaction',
      );
      expect(
        (await posts.loadFollowOnOutboxRecipientDeliveries(
          localReactions.single.eventId,
        )).map((delivery) => delivery.deliveryStatus),
        everyElement('pending'),
      );

      final (result, reaction) = await sendFuture;
      expect(result, SendPostCommentReactionResult.success);
      expect(reaction?.reactionId, localReactions.single.reactionId);
    },
  );

  test(
    'repost-thread reactions stay scoped to the original author plus persisted participants and add the sender to participant state',
    () async {
      final service = FakeP2PService(peerId: 'peer-ibra', network: network);
      addTearDown(service.dispose);
      contacts.addTestContact(_contact('peer-solz', 'Solz'));
      contacts.addTestContact(_contact('peer-hisam', 'Hisam'));
      contacts.addTestContact(_contact('peer-ibra', 'Ibra'));
      contacts.addTestContact(_contact('peer-dana', 'Dana'));
      await posts.savePost(
        PostModel(
          id: 'post-1',
          eventId: 'evt-post-1',
          senderPeerId: 'peer-hisam',
          authorPeerId: 'peer-solz',
          authorUsername: 'Solz',
          text: 'Need a ladder',
          audience: PostAudience.allFriends(),
          createdAt: '2026-03-15T10:15:30.000Z',
          visibleAt: '2026-03-15T11:15:30.000Z',
          expiresAt: '2026-03-18T10:15:30.000Z',
          isIncoming: true,
        ),
      );
      await posts.saveRecipientDelivery(
        const PostRecipientDelivery(
          postId: 'post-1',
          recipientPeerId: 'peer-dana',
          deliveryStatus: 'delivered',
          lastAttemptAt: '2026-03-15T10:15:31.000Z',
          deliveryPath: 'direct',
          createdAt: '2026-03-15T10:15:31.000Z',
          updatedAt: '2026-03-15T10:15:31.000Z',
        ),
      );
      await posts.savePostOrigin(
        const PostOriginModel(
          postId: 'post-1',
          originKind: PostOriginKind.pass,
          passId: 'pass-1',
          passerPeerId: 'peer-hisam',
          passerUsername: 'Hisam',
          passCreatedAt: '2026-03-15T11:15:30.000Z',
        ),
      );
      await posts.saveRepostEngagementParticipant(
        postId: 'post-1',
        participantPeerId: 'peer-solz',
        createdAt: '2026-03-15T11:15:30.000Z',
      );
      await posts.saveRepostEngagementParticipant(
        postId: 'post-1',
        participantPeerId: 'peer-hisam',
        createdAt: '2026-03-15T11:15:30.000Z',
      );
      FakeP2PService(peerId: 'peer-solz', network: network);
      FakeP2PService(peerId: 'peer-hisam', network: network);

      final (result, reaction) = await sendPostReaction(
        p2pService: service,
        postRepo: posts,
        contactRepo: contacts,
        postId: 'post-1',
        senderPeerId: 'peer-ibra',
        isActive: true,
      );

      expect(result, SendPostReactionResult.success);
      expect(reaction, isNotNull);
      expect(
        await posts.loadRepostEngagementParticipantPeerIds('post-1'),
        <String>{'peer-hisam', 'peer-ibra', 'peer-solz'},
      );
      final deliveries = await posts.loadFollowOnOutboxRecipientDeliveries(
        reaction!.eventId,
      );
      expect(
        deliveries.map((delivery) => delivery.recipientPeerId).toList(),
        <String>['peer-hisam', 'peer-solz'],
      );
    },
  );

  test(
    'repost-thread comment reactions stay scoped to the original author plus persisted participants and add the sender to participant state',
    () async {
      final service = FakeP2PService(peerId: 'peer-ibra', network: network);
      addTearDown(service.dispose);
      contacts.addTestContact(_contact('peer-solz', 'Solz'));
      contacts.addTestContact(_contact('peer-hisam', 'Hisam'));
      contacts.addTestContact(_contact('peer-ibra', 'Ibra'));
      contacts.addTestContact(_contact('peer-dana', 'Dana'));
      await posts.savePost(
        PostModel(
          id: 'post-1',
          eventId: 'evt-post-1',
          senderPeerId: 'peer-hisam',
          authorPeerId: 'peer-solz',
          authorUsername: 'Solz',
          text: 'Need a ladder',
          audience: PostAudience.allFriends(),
          createdAt: '2026-03-15T10:15:30.000Z',
          visibleAt: '2026-03-15T11:15:30.000Z',
          expiresAt: '2026-03-18T10:15:30.000Z',
          isIncoming: true,
        ),
      );
      await posts.saveComment(
        const PostCommentModel(
          id: 'comment-1',
          eventId: 'evt-comment-1',
          postId: 'post-1',
          senderPeerId: 'peer-solz',
          authorUsername: 'Solz',
          body: 'I can help too.',
          commentedAt: '2026-03-15T11:16:00.000Z',
        ),
      );
      await posts.saveRecipientDelivery(
        const PostRecipientDelivery(
          postId: 'post-1',
          recipientPeerId: 'peer-dana',
          deliveryStatus: 'delivered',
          lastAttemptAt: '2026-03-15T10:15:31.000Z',
          deliveryPath: 'direct',
          createdAt: '2026-03-15T10:15:31.000Z',
          updatedAt: '2026-03-15T10:15:31.000Z',
        ),
      );
      await posts.savePostOrigin(
        const PostOriginModel(
          postId: 'post-1',
          originKind: PostOriginKind.pass,
          passId: 'pass-1',
          passerPeerId: 'peer-hisam',
          passerUsername: 'Hisam',
          passCreatedAt: '2026-03-15T11:15:30.000Z',
        ),
      );
      await posts.saveRepostEngagementParticipant(
        postId: 'post-1',
        participantPeerId: 'peer-solz',
        createdAt: '2026-03-15T11:15:30.000Z',
      );
      await posts.saveRepostEngagementParticipant(
        postId: 'post-1',
        participantPeerId: 'peer-hisam',
        createdAt: '2026-03-15T11:15:30.000Z',
      );
      FakeP2PService(peerId: 'peer-solz', network: network);
      FakeP2PService(peerId: 'peer-hisam', network: network);

      final (result, reaction) = await sendPostCommentReaction(
        p2pService: service,
        postRepo: posts,
        contactRepo: contacts,
        postId: 'post-1',
        commentId: 'comment-1',
        senderPeerId: 'peer-ibra',
        isActive: true,
      );

      expect(result, SendPostCommentReactionResult.success);
      expect(reaction, isNotNull);
      expect(
        await posts.loadRepostEngagementParticipantPeerIds('post-1'),
        <String>{'peer-hisam', 'peer-ibra', 'peer-solz'},
      );
      final deliveries = await posts.loadFollowOnOutboxRecipientDeliveries(
        reaction!.eventId,
      );
      expect(
        deliveries.map((delivery) => delivery.recipientPeerId).toList(),
        <String>['peer-hisam', 'peer-solz'],
      );
    },
  );
}
