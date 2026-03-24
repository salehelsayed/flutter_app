import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
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
    'comment text strips dangerous bidi controls but preserves safe markers',
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

      expect(result, SendPostCommentResult.success);
      expect(comment, isNotNull);
      expect(comment!.body, 'مرحبا Hello\u200E 123');

      final savedComments = await posts.loadComments('post-1');
      expect(savedComments, hasLength(1));
      expect(savedComments.single.body, 'مرحبا Hello\u200E 123');

      final inboxMessage =
          network.retrieveInbox('peer-alice').single['message'] as String;
      final payload = jsonDecode(inboxMessage) as Map<String, dynamic>;
      expect(payload['payload']['body'], 'مرحبا Hello\u200E 123');
    },
  );

  test(
    'comment is rejected when sanitization removes all non-whitespace text',
    () async {
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

      expect(result, SendPostCommentResult.invalidComment);
      expect(comment, isNull);
      expect(await posts.loadComments('post-1'), isEmpty);
    },
  );

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

  test(
    'comment is persisted locally and refreshes expiry before delivery completes',
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

      await Future<void>.delayed(const Duration(milliseconds: 20));

      final localComments = await posts.loadComments('post-1');
      expect(localComments, hasLength(1));
      expect(localComments.single.body, 'I can lend one.');
      expect(
        (await posts.getFollowOnOutboxEvent(
          localComments.single.eventId,
        ))?.eventType,
        'post_comment',
      );
      expect(
        (await posts.loadFollowOnOutboxRecipientDeliveries(
          localComments.single.eventId,
        )).map((delivery) => delivery.deliveryStatus),
        everyElement('pending'),
      );
      final updatedPost = await posts.getPost('post-1');
      expect(
        updatedPost?.expiresAt,
        commentedAt.add(const Duration(days: 3)).toIso8601String(),
      );
      expect(updatedPost?.lastEngagementAt, commentedAt.toIso8601String());

      final (result, comment) = await sendFuture;
      expect(result, SendPostCommentResult.success);
      expect(comment?.id, localComments.single.id);
    },
  );

  test(
    'comment defaults to a 25-recipient fanout cap and keeps local state before delivery completes',
    () async {
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
      final service = _ControlledP2PService(
        peerId: 'peer-bob',
        network: network,
        sendGates: <String, Completer<void>>{
          for (final peerId in resolvedRecipientPeerIds)
            peerId: Completer<void>(),
        },
      );
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

      await service.waitForSendCount(25);
      await _drainMicrotasks();

      final localComments = await posts.loadComments('post-1');
      expect(localComments, hasLength(1));
      expect(localComments.single.body, 'I can lend one.');
      expect(
        (await posts.getFollowOnOutboxEvent(
          localComments.single.eventId,
        ))?.eventType,
        'post_comment',
      );
      final queuedDeliveries = await posts
          .loadFollowOnOutboxRecipientDeliveries(localComments.single.eventId);
      expect(queuedDeliveries, hasLength(resolvedRecipientPeerIds.length));
      expect(
        queuedDeliveries.map((delivery) => delivery.deliveryStatus),
        everyElement('pending'),
      );
      final updatedPost = await posts.getPost('post-1');
      expect(
        updatedPost?.expiresAt,
        commentedAt.add(const Duration(days: 3)).toIso8601String(),
      );
      expect(updatedPost?.lastEngagementAt, commentedAt.toIso8601String());
      expect(service.maxInFlightSends, 25);

      service.releaseOneStartedRecipient();
      await service.waitForSendCount(26);
      await _drainMicrotasks();

      expect(service.maxInFlightSends, 25);
      expect(service.blockedStartedRecipients, hasLength(25));

      service.releaseAllRecipients();

      final (result, comment) = await sendFuture;
      expect(result, SendPostCommentResult.success);
      expect(comment?.id, localComments.single.id);
    },
  );

  test(
    'comment keeps local sender state, refreshed expiry, and retryable outbox state when first send fails',
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

      expect(result, SendPostCommentResult.queuedForRetry);
      expect(comment, isNotNull);
      expect(await posts.loadComments('post-1'), hasLength(1));
      final updatedPost = await posts.getPost('post-1');
      expect(
        updatedPost?.expiresAt,
        commentedAt.add(const Duration(days: 3)).toIso8601String(),
      );
      expect(updatedPost?.lastEngagementAt, commentedAt.toIso8601String());

      final retryableJobs = await posts.loadRetryableFollowOnOutboxJobs();
      expect(retryableJobs, hasLength(1));
      expect(retryableJobs.single.event.eventType, 'post_comment');
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
    'repost-thread comments target the original author plus persisted participants and add the sender to participant state',
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

      final (result, created) = await createLocalPostComment(
        p2pService: service,
        postRepo: posts,
        contactRepo: contacts,
        postId: 'post-1',
        senderPeerId: 'peer-ibra',
        senderUsername: 'Ibra',
        body: 'I can help too.',
      );

      expect(result, SendPostCommentResult.success);
      expect(created, isNotNull);
      expect(
        await posts.loadRepostEngagementParticipantPeerIds('post-1'),
        <String>{'peer-hisam', 'peer-ibra', 'peer-solz'},
      );
      final deliveries = await posts.loadFollowOnOutboxRecipientDeliveries(
        created!.comment.eventId,
      );
      expect(
        deliveries.map((delivery) => delivery.recipientPeerId).toList(),
        <String>['peer-hisam', 'peer-solz'],
      );
    },
  );

  test(
    'repost-thread comments still reach the original author when that author is not a direct contact',
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

      expect(result, SendPostCommentResult.success);
      expect(comment, isNotNull);
      expect(
        await posts.loadFollowOnOutboxRecipientDeliveries(comment!.eventId),
        hasLength(2),
      );
      expect(
        (await posts.loadFollowOnOutboxRecipientDeliveries(
          comment.eventId,
        )).map((delivery) => delivery.recipientPeerId).toSet(),
        <String>{'peer-hisam', 'peer-solz'},
      );
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

Future<void> _drainMicrotasks([int turns = 3]) async {
  for (var index = 0; index < turns; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _ControlledP2PService extends FakeP2PService {
  final Map<String, Completer<void>> sendGates;
  final List<String> sendStartOrder = <String>[];
  final StreamController<void> _sendStarted =
      StreamController<void>.broadcast();

  int _inFlightSends = 0;
  int maxInFlightSends = 0;

  _ControlledP2PService({
    required super.peerId,
    required super.network,
    required this.sendGates,
  });

  List<String> get blockedStartedRecipients {
    return sendStartOrder
        .where(
          (recipientPeerId) =>
              !(sendGates[recipientPeerId]?.isCompleted ?? true),
        )
        .toList(growable: false);
  }

  Future<void> waitForSendCount(
    int count, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (sendStartOrder.length < count) {
      final remaining = deadline.difference(DateTime.now());
      if (remaining <= Duration.zero) {
        throw StateError('Timed out waiting for $count recipients to start.');
      }
      await _sendStarted.stream.first.timeout(remaining);
    }
  }

  void releaseOneStartedRecipient() {
    for (final recipientPeerId in sendStartOrder) {
      final gate = sendGates[recipientPeerId];
      if (gate != null && !gate.isCompleted) {
        gate.complete();
        return;
      }
    }
    fail('No started recipient remained blocked.');
  }

  void releaseAllRecipients() {
    for (final gate in sendGates.values) {
      if (!gate.isCompleted) {
        gate.complete();
      }
    }
  }

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String targetPeerId,
    String message, {
    int? timeoutMs,
  }) async {
    sendStartOrder.add(targetPeerId);
    _inFlightSends++;
    if (_inFlightSends > maxInFlightSends) {
      maxInFlightSends = _inFlightSends;
    }
    _sendStarted.add(null);

    try {
      final gate = sendGates[targetPeerId];
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
