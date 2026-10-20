import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/application/send_post_comment_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
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
    expiresAt: '2026-03-16T10:15:30.000Z',
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
    'rejects outgoing comments with bidi controls without storing or sending',
    () async {
      await posts.savePost(_post('post-1'));
      final (result, comment) = await sendPostComment(
        p2pService: bobService,
        postRepo: posts,
        contactRepo: contacts,
        postId: 'post-1',
        senderPeerId: 'peer-bob',
        senderUsername: 'Bob',
        body: 'مرحبا\u202E Hello\u200E 123',
      );

      expect(result, SendPostCommentResult.sendFailed);
      expect(comment, isNull);
      expect(await posts.loadComments('post-1'), isEmpty);
      expect(await posts.loadPostReactions('post-1'), isEmpty);
      expect(await posts.loadCommentReactions('comment-1'), isEmpty);
      expect(await posts.loadRetryableFollowOnOutboxJobs(), isEmpty);
      expect(
        (await posts.getPost('post-1'))?.expiresAt,
        _post('post-1').expiresAt,
      );
      expect((await posts.getPost('post-1'))?.lastEngagementAt, isNull);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
    },
  );

  test('rejects outgoing comments containing only removed controls', () async {
    await posts.savePost(_post('post-1'));

    final (result, comment) = await sendPostComment(
      p2pService: bobService,
      postRepo: posts,
      contactRepo: contacts,
      postId: 'post-1',
      senderPeerId: 'peer-bob',
      senderUsername: 'Bob',
      body: '\u202E   \u202C',
    );

    expect(result, SendPostCommentResult.sendFailed);
    expect(comment, isNull);
    expect(await posts.loadComments('post-1'), isEmpty);
    expect(await posts.loadPostReactions('post-1'), isEmpty);
    expect(await posts.loadCommentReactions('comment-1'), isEmpty);
    expect(await posts.loadRetryableFollowOnOutboxJobs(), isEmpty);
    expect(
      (await posts.getPost('post-1'))?.expiresAt,
      _post('post-1').expiresAt,
    );
    expect((await posts.getPost('post-1'))?.lastEngagementAt, isNull);
    expect(network.deliverCallCount, 0);
    expect(network.storeInInboxCallCount, 0);
  });

  test(
    'rejects comments without fanout or extending the thought expiry',
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
      final commentedAt = DateTime.now().toUtc().subtract(
        const Duration(minutes: 1),
      );

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

      expect(result, SendPostCommentResult.sendFailed);
      expect(comment, isNull);
      expect(await posts.loadComments('post-1'), isEmpty);
      expect(await posts.loadPostReactions('post-1'), isEmpty);
      expect(await posts.loadCommentReactions('comment-1'), isEmpty);
      expect(await posts.loadRetryableFollowOnOutboxJobs(), isEmpty);
      expect(
        (await posts.getPost('post-1'))?.expiresAt,
        _post('post-1').expiresAt,
      );
      expect((await posts.getPost('post-1'))?.lastEngagementAt, isNull);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
    },
  );

  test(
    'rejects comments before any local state or delayed delivery is created',
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
      FakeP2PService(peerId: 'peer-alice', network: network);
      FakeP2PService(peerId: 'peer-cara', network: network);
      network.deliveryDelay = const Duration(milliseconds: 150);
      final commentedAt = DateTime.parse('2026-03-15T11:14:00.000Z');

      final sendFuture = sendPostComment(
        p2pService: bobService,
        postRepo: posts,
        contactRepo: contacts,
        postId: 'post-1',
        senderPeerId: 'peer-bob',
        senderUsername: 'Bob',
        body: 'I can lend one.',
        nowProvider: () => commentedAt,
      );

      final (result, comment) = await sendFuture;
      expect(result, SendPostCommentResult.sendFailed);
      expect(comment, isNull);
      expect(await posts.loadComments('post-1'), isEmpty);
      expect(await posts.loadPostReactions('post-1'), isEmpty);
      expect(await posts.loadCommentReactions('comment-1'), isEmpty);
      expect(await posts.loadRetryableFollowOnOutboxJobs(), isEmpty);
      expect(
        (await posts.getPost('post-1'))?.expiresAt,
        _post('post-1').expiresAt,
      );
      expect((await posts.getPost('post-1'))?.lastEngagementAt, isNull);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
    },
  );

  test('rejects comments to 29 recipients without starting a fanout', () async {
    await posts.savePost(_post('post-1'));
    final deliveryRecipientPeerIds = _deliveryRecipientPeerIds(29);
    for (final peerId in deliveryRecipientPeerIds) {
      contacts.addTestContact(_contact(peerId, 'User $peerId'));
    }
    await _seedRecipientDeliveries(posts, deliveryRecipientPeerIds);
    final resolvedRecipientPeerIds = _resolvedRecipientPeerIds(
      deliveryRecipientPeerIds,
    );
    final recipientServices = [
      for (final peerId in resolvedRecipientPeerIds)
        FakeP2PService(peerId: peerId, network: network),
    ];
    for (final serviceNode in recipientServices) {
      addTearDown(serviceNode.dispose);
    }
    final service = FakeP2PService(peerId: 'peer-bob', network: network);
    addTearDown(service.dispose);
    final commentedAt = DateTime.parse('2026-03-15T11:15:00.000Z');

    final sendFuture = sendPostComment(
      p2pService: service,
      postRepo: posts,
      contactRepo: contacts,
      postId: 'post-1',
      senderPeerId: 'peer-bob',
      senderUsername: 'Bob',
      body: 'I can lend one.',
      nowProvider: () => commentedAt,
    );

    final (result, comment) = await sendFuture;
    expect(result, SendPostCommentResult.sendFailed);
    expect(comment, isNull);
    expect(await posts.loadComments('post-1'), isEmpty);
    expect(await posts.loadPostReactions('post-1'), isEmpty);
    expect(await posts.loadCommentReactions('comment-1'), isEmpty);
    expect(await posts.loadRetryableFollowOnOutboxJobs(), isEmpty);
    expect(
      (await posts.getPost('post-1'))?.expiresAt,
      _post('post-1').expiresAt,
    );
    expect((await posts.getPost('post-1'))?.lastEngagementAt, isNull);
    expect(network.deliverCallCount, 0);
    expect(network.storeInInboxCallCount, 0);
  });

  test(
    'rejects comments without creating retry jobs when transport is unavailable',
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
      final commentedAt = DateTime.parse('2026-03-15T11:16:00.000Z');

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

      expect(result, SendPostCommentResult.sendFailed);
      expect(comment, isNull);
      expect(await posts.loadComments('post-1'), isEmpty);
      expect(await posts.loadPostReactions('post-1'), isEmpty);
      expect(await posts.loadCommentReactions('comment-1'), isEmpty);
      expect(await posts.loadRetryableFollowOnOutboxJobs(), isEmpty);
      expect(
        (await posts.getPost('post-1'))?.expiresAt,
        _post('post-1').expiresAt,
      );
      expect((await posts.getPost('post-1'))?.lastEngagementAt, isNull);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
    },
  );

  test('rejects repost comments without changing participant state', () async {
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
        expiresAt: '2026-03-16T10:15:30.000Z',
        isIncoming: true,
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

    final (result, comment) = await createLocalPostComment(
      p2pService: service,
      postRepo: posts,
      contactRepo: contacts,
      postId: 'post-1',
      senderPeerId: 'peer-ibra',
      senderUsername: 'Ibra',
      body: 'I can help too.',
    );

    expect(result, SendPostCommentResult.sendFailed);
    expect(comment, isNull);
    expect(await posts.loadComments('post-1'), isEmpty);
    expect(await posts.loadPostReactions('post-1'), isEmpty);
    expect(await posts.loadCommentReactions('comment-1'), isEmpty);
    expect(await posts.loadRetryableFollowOnOutboxJobs(), isEmpty);
    expect(
      (await posts.getPost('post-1'))?.expiresAt,
      _post('post-1').expiresAt,
    );
    expect((await posts.getPost('post-1'))?.lastEngagementAt, isNull);
    expect(network.deliverCallCount, 0);
    expect(network.storeInInboxCallCount, 0);
  });

  test(
    'rejects repost comments when the original author is not a contact',
    () async {
      final repostContacts = InMemoryContactRepository();
      repostContacts.addTestContact(_contact('peer-hisam', 'Hisam'));
      repostContacts.addTestContact(_contact('peer-ibra', 'Ibra'));
      final solzService = FakeP2PService(peerId: 'peer-solz', network: network);
      final hisamService = FakeP2PService(
        peerId: 'peer-hisam',
        network: network,
      );
      final ibraService = FakeP2PService(peerId: 'peer-ibra', network: network);
      addTearDown(solzService.dispose);
      addTearDown(hisamService.dispose);
      addTearDown(ibraService.dispose);

      await posts.savePost(
        _post('post-1').copyWith(
          senderPeerId: 'peer-hisam',
          authorPeerId: 'peer-solz',
          authorUsername: 'Solz',
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

      final (result, comment) = await sendPostComment(
        p2pService: ibraService,
        postRepo: posts,
        contactRepo: repostContacts,
        postId: 'post-1',
        senderPeerId: 'peer-ibra',
        senderUsername: 'Ibra',
        body: 'I can help too.',
      );

      expect(result, SendPostCommentResult.sendFailed);
      expect(comment, isNull);
      expect(await posts.loadComments('post-1'), isEmpty);
      expect(await posts.loadPostReactions('post-1'), isEmpty);
      expect(await posts.loadCommentReactions('comment-1'), isEmpty);
      expect(await posts.loadRetryableFollowOnOutboxJobs(), isEmpty);
      expect(
        (await posts.getPost('post-1'))?.expiresAt,
        _post('post-1').expiresAt,
      );
      expect((await posts.getPost('post-1'))?.lastEngagementAt, isNull);
      expect(network.deliverCallCount, 0);
      expect(network.storeInInboxCallCount, 0);
    },
  );
}

List<String> _deliveryRecipientPeerIds(int count) {
  return List<String>.generate(
    count,
    (index) => 'peer-recipient-${(index + 1).toString().padLeft(2, '0')}',
    growable: false,
  );
}

Set<String> _resolvedRecipientPeerIds(
  Iterable<String> deliveryRecipientPeerIds,
) {
  return <String>{'peer-alice', ...deliveryRecipientPeerIds}
    ..remove('peer-bob');
}

Future<void> _seedRecipientDeliveries(
  InMemoryPostRepository posts,
  Iterable<String> recipientPeerIds,
) async {
  for (final peerId in recipientPeerIds) {
    await posts.saveRecipientDelivery(
      PostRecipientDelivery(
        postId: 'post-1',
        recipientPeerId: peerId,
        deliveryStatus: 'delivered',
        lastAttemptAt: '2026-03-15T10:15:31.000Z',
        deliveryPath: 'direct',
        createdAt: '2026-03-15T10:15:31.000Z',
        updatedAt: '2026-03-15T10:15:31.000Z',
      ),
    );
  }
}
