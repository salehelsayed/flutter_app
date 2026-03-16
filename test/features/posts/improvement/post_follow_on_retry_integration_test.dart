import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/services/incoming_message_router.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/application/pending_post_follow_on_retrier.dart';
import 'package:flutter_app/features/posts/application/post_comment_listener.dart';
import 'package:flutter_app/features/posts/application/post_reaction_listener.dart';
import 'package:flutter_app/features/posts/application/send_post_comment_reaction_use_case.dart';
import 'package:flutter_app/features/posts/application/send_post_comment_use_case.dart';
import 'package:flutter_app/features/posts/application/send_post_reaction_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_comment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_recipient_delivery.dart';

import '../../../shared/fakes/fake_p2p_network.dart';
import '../../../shared/fakes/fake_p2p_service_integration.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';

void main() {
  late FakeP2PNetwork network;
  late _PostEngagementUser author;
  late _PostEngagementUser recipientOne;
  late _PostEngagementUser recipientTwo;

  setUp(() {
    network = FakeP2PNetwork();
    author = _PostEngagementUser.create(
      peerId: 'peer-bob',
      username: 'Bob',
      network: network,
    );
    recipientOne = _PostEngagementUser.create(
      peerId: 'peer-cara',
      username: 'Cara',
      network: network,
    );
    recipientTwo = _PostEngagementUser.create(
      peerId: 'peer-drew',
      username: 'Drew',
      network: network,
    );

    author.addContact(recipientOne);
    author.addContact(recipientTwo);
    recipientOne.addContact(author);
    recipientTwo.addContact(author);
    recipientOne.start();
    recipientTwo.start();
  });

  tearDown(() {
    author.dispose();
    recipientOne.dispose();
    recipientTwo.dispose();
  });

  test(
    'comment retry only targets unresolved recipients and does not duplicate sender or recipient comments',
    () async {
      await _seedSharedPost(
        author: author,
        recipients: <_PostEngagementUser>[recipientOne, recipientTwo],
      );
      recipientTwo.p2pService.setOnline(false);
      network.inboxDisabled = true;
      final commentedAt = DateTime.parse('2026-03-15T11:40:00.000Z');

      final (result, comment) = await sendPostComment(
        p2pService: author.p2pService,
        postRepo: author.postRepo,
        contactRepo: author.contactRepo,
        postId: 'post-1',
        senderPeerId: author.peerId,
        senderUsername: author.username,
        body: 'I can lend one.',
        nowProvider: () => commentedAt,
      );

      expect(result, SendPostCommentResult.partiallySettled);
      expect(comment, isNotNull);
      expect(await author.postRepo.loadComments('post-1'), hasLength(1));
      expect(
        (await author.postRepo.getPost('post-1'))?.lastEngagementAt,
        commentedAt.toIso8601String(),
      );
      await _waitForCommentCount(
        recipientOne,
        expectedCount: 1,
        description: 'first recipient comment delivery',
      );
      expect(await recipientTwo.postRepo.loadComments('post-1'), isEmpty);

      final retryableJobs = await author.postRepo
          .loadRetryableFollowOnOutboxJobs();
      expect(retryableJobs, hasLength(1));
      expect(retryableJobs.single.event.eventType, 'post_comment');
      expect(
        retryableJobs.single.recipientDeliveries.map(
          (delivery) => delivery.recipientPeerId,
        ),
        <String>[recipientTwo.peerId],
      );

      recipientTwo.p2pService.setOnline(true);
      network.inboxDisabled = false;

      final retried = await retryPendingPostFollowOns(
        postRepo: author.postRepo,
        p2pService: author.p2pService,
      );

      expect(retried, 1);
      await _waitForCommentCount(
        recipientTwo,
        expectedCount: 1,
        description: 'second recipient comment retry delivery',
      );
      expect(await author.postRepo.loadComments('post-1'), hasLength(1));
      expect(await recipientOne.postRepo.loadComments('post-1'), hasLength(1));
      expect(await recipientTwo.postRepo.loadComments('post-1'), hasLength(1));
      expect(await author.postRepo.loadRetryableFollowOnOutboxJobs(), isEmpty);

      final secondRetry = await retryPendingPostFollowOns(
        postRepo: author.postRepo,
        p2pService: author.p2pService,
      );

      expect(secondRetry, 0);
      expect(await author.postRepo.loadComments('post-1'), hasLength(1));
      expect(await recipientOne.postRepo.loadComments('post-1'), hasLength(1));
      expect(await recipientTwo.postRepo.loadComments('post-1'), hasLength(1));
    },
  );

  test(
    'reaction retry only targets unresolved recipients and does not duplicate sender or recipient reactions',
    () async {
      await _seedSharedPost(
        author: author,
        recipients: <_PostEngagementUser>[recipientOne, recipientTwo],
      );
      recipientTwo.p2pService.setOnline(false);
      network.inboxDisabled = true;

      final (result, reaction) = await sendPostReaction(
        p2pService: author.p2pService,
        postRepo: author.postRepo,
        contactRepo: author.contactRepo,
        postId: 'post-1',
        senderPeerId: author.peerId,
        isActive: true,
      );

      expect(result, SendPostReactionResult.partiallySettled);
      expect(reaction, isNotNull);
      expect(await author.postRepo.loadPostReactions('post-1'), hasLength(1));
      await _waitForReactionCount(
        recipientOne,
        expectedCount: 1,
        description: 'first recipient reaction delivery',
      );
      expect(await recipientTwo.postRepo.loadPostReactions('post-1'), isEmpty);

      final retryableJobs = await author.postRepo
          .loadRetryableFollowOnOutboxJobs();
      expect(retryableJobs, hasLength(1));
      expect(retryableJobs.single.event.eventType, 'post_reaction');
      expect(
        retryableJobs.single.recipientDeliveries.map(
          (delivery) => delivery.recipientPeerId,
        ),
        <String>[recipientTwo.peerId],
      );

      recipientTwo.p2pService.setOnline(true);
      network.inboxDisabled = false;

      final retried = await retryPendingPostFollowOns(
        postRepo: author.postRepo,
        p2pService: author.p2pService,
      );

      expect(retried, 1);
      await _waitForReactionCount(
        recipientTwo,
        expectedCount: 1,
        description: 'second recipient reaction retry delivery',
      );
      expect(await author.postRepo.loadPostReactions('post-1'), hasLength(1));
      expect(
        await recipientOne.postRepo.loadPostReactions('post-1'),
        hasLength(1),
      );
      expect(
        await recipientTwo.postRepo.loadPostReactions('post-1'),
        hasLength(1),
      );
      expect(await author.postRepo.loadRetryableFollowOnOutboxJobs(), isEmpty);

      final secondRetry = await retryPendingPostFollowOns(
        postRepo: author.postRepo,
        p2pService: author.p2pService,
      );

      expect(secondRetry, 0);
      expect(await author.postRepo.loadPostReactions('post-1'), hasLength(1));
      expect(
        await recipientOne.postRepo.loadPostReactions('post-1'),
        hasLength(1),
      );
      expect(
        await recipientTwo.postRepo.loadPostReactions('post-1'),
        hasLength(1),
      );
    },
  );

  test(
    'comment reaction retry only targets unresolved recipients and does not duplicate sender or recipient reaction state',
    () async {
      await _seedSharedPost(
        author: author,
        recipients: <_PostEngagementUser>[recipientOne, recipientTwo],
      );
      await _seedSharedComment(
        author: author,
        recipients: <_PostEngagementUser>[recipientOne, recipientTwo],
      );
      recipientTwo.p2pService.setOnline(false);
      network.inboxDisabled = true;

      final (result, reaction) = await sendPostCommentReaction(
        p2pService: author.p2pService,
        postRepo: author.postRepo,
        contactRepo: author.contactRepo,
        postId: 'post-1',
        commentId: 'comment-1',
        senderPeerId: author.peerId,
        isActive: true,
      );

      expect(result, SendPostCommentReactionResult.partiallySettled);
      expect(reaction, isNotNull);
      expect(
        await author.postRepo.loadCommentReactions('comment-1'),
        hasLength(1),
      );
      await _waitForCommentReactionCount(
        recipientOne,
        expectedCount: 1,
        description: 'first recipient comment reaction delivery',
      );
      expect(
        await recipientTwo.postRepo.loadCommentReactions('comment-1'),
        isEmpty,
      );

      final retryableJobs = await author.postRepo
          .loadRetryableFollowOnOutboxJobs();
      expect(retryableJobs, hasLength(1));
      expect(retryableJobs.single.event.eventType, 'post_comment_reaction');
      expect(retryableJobs.single.event.commentId, 'comment-1');
      expect(
        retryableJobs.single.recipientDeliveries.map(
          (delivery) => delivery.recipientPeerId,
        ),
        <String>[recipientTwo.peerId],
      );

      recipientTwo.p2pService.setOnline(true);
      network.inboxDisabled = false;

      final retried = await retryPendingPostFollowOns(
        postRepo: author.postRepo,
        p2pService: author.p2pService,
      );

      expect(retried, 1);
      await _waitForCommentReactionCount(
        recipientTwo,
        expectedCount: 1,
        description: 'second recipient comment reaction retry delivery',
      );
      expect(
        await author.postRepo.loadCommentReactions('comment-1'),
        hasLength(1),
      );
      expect(
        await recipientOne.postRepo.loadCommentReactions('comment-1'),
        hasLength(1),
      );
      expect(
        await recipientTwo.postRepo.loadCommentReactions('comment-1'),
        hasLength(1),
      );
      expect(await author.postRepo.loadRetryableFollowOnOutboxJobs(), isEmpty);

      final secondRetry = await retryPendingPostFollowOns(
        postRepo: author.postRepo,
        p2pService: author.p2pService,
      );

      expect(secondRetry, 0);
      expect(
        await author.postRepo.loadCommentReactions('comment-1'),
        hasLength(1),
      );
      expect(
        await recipientOne.postRepo.loadCommentReactions('comment-1'),
        hasLength(1),
      );
      expect(
        await recipientTwo.postRepo.loadCommentReactions('comment-1'),
        hasLength(1),
      );
    },
  );
}

Future<void> _seedSharedPost({
  required _PostEngagementUser author,
  required List<_PostEngagementUser> recipients,
}) async {
  await author.postRepo.savePost(_sharedPost(author.peerId, author.username));
  for (final recipient in recipients) {
    await author.postRepo.saveRecipientDelivery(
      PostRecipientDelivery(
        postId: 'post-1',
        recipientPeerId: recipient.peerId,
        deliveryStatus: 'delivered',
        lastAttemptAt: '2026-03-15T10:16:00.000Z',
        deliveryPath: 'direct',
        createdAt: '2026-03-15T10:16:00.000Z',
        updatedAt: '2026-03-15T10:16:00.000Z',
      ),
    );
    await recipient.postRepo.savePost(
      _sharedPost(author.peerId, author.username),
    );
  }
}

Future<void> _seedSharedComment({
  required _PostEngagementUser author,
  required List<_PostEngagementUser> recipients,
}) async {
  const comment = PostCommentModel(
    id: 'comment-1',
    eventId: 'evt-comment-1',
    postId: 'post-1',
    senderPeerId: 'peer-bob',
    authorUsername: 'Bob',
    body: 'I can lend one.',
    commentedAt: '2026-03-15T11:00:00.000Z',
  );
  await author.postRepo.saveComment(comment);
  for (final recipient in recipients) {
    await recipient.postRepo.saveComment(comment);
  }
}

PostModel _sharedPost(String authorPeerId, String authorUsername) {
  return PostModel(
    id: 'post-1',
    eventId: 'evt-post-1',
    senderPeerId: authorPeerId,
    authorPeerId: authorPeerId,
    authorUsername: authorUsername,
    text: 'Need a ladder',
    audience: PostAudience.allFriends(),
    createdAt: '2026-03-15T10:15:30.000Z',
    visibleAt: '2026-03-15T10:15:30.000Z',
    expiresAt: '2026-03-18T10:15:30.000Z',
    isIncoming: false,
  );
}

Future<void> _waitForCommentCount(
  _PostEngagementUser user, {
  required int expectedCount,
  required String description,
}) async {
  Future<bool> condition() async {
    return (await user.postRepo.loadComments('post-1')).length == expectedCount;
  }

  if (await condition()) {
    return;
  }

  final deadline = DateTime.now().add(const Duration(seconds: 1));
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (await condition()) {
      return;
    }
  }

  throw StateError('Timed out waiting for $description');
}

Future<void> _waitForReactionCount(
  _PostEngagementUser user, {
  required int expectedCount,
  required String description,
}) async {
  Future<bool> condition() async {
    return (await user.postRepo.loadPostReactions('post-1')).length ==
        expectedCount;
  }

  if (await condition()) {
    return;
  }

  final deadline = DateTime.now().add(const Duration(seconds: 1));
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (await condition()) {
      return;
    }
  }

  throw StateError('Timed out waiting for $description');
}

Future<void> _waitForCommentReactionCount(
  _PostEngagementUser user, {
  required int expectedCount,
  required String description,
}) async {
  Future<bool> condition() async {
    return (await user.postRepo.loadCommentReactions('comment-1')).length ==
        expectedCount;
  }

  if (await condition()) {
    return;
  }

  final deadline = DateTime.now().add(const Duration(seconds: 1));
  while (DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (await condition()) {
      return;
    }
  }

  throw StateError('Timed out waiting for $description');
}

class _PostEngagementUser {
  final String peerId;
  final String username;
  final FakeP2PService p2pService;
  final InMemoryContactRepository contactRepo;
  final InMemoryPostRepository postRepo;
  final IncomingMessageRouter router;
  final PostCommentListener commentListener;
  final PostReactionListener reactionListener;

  _PostEngagementUser._({
    required this.peerId,
    required this.username,
    required this.p2pService,
    required this.contactRepo,
    required this.postRepo,
    required this.router,
    required this.commentListener,
    required this.reactionListener,
  });

  factory _PostEngagementUser.create({
    required String peerId,
    required String username,
    required FakeP2PNetwork network,
  }) {
    final p2pService = FakeP2PService(peerId: peerId, network: network);
    final contactRepo = InMemoryContactRepository();
    final postRepo = InMemoryPostRepository();
    final router = IncomingMessageRouter(p2pService: p2pService);
    final commentListener = PostCommentListener(
      postCommentStream: router.postCommentStream,
      postRepo: postRepo,
      contactRepo: contactRepo,
    );
    final reactionListener = PostReactionListener(
      postReactionStream: router.postReactionStream,
      postCommentReactionStream: router.postCommentReactionStream,
      postRepo: postRepo,
      contactRepo: contactRepo,
    );

    return _PostEngagementUser._(
      peerId: peerId,
      username: username,
      p2pService: p2pService,
      contactRepo: contactRepo,
      postRepo: postRepo,
      router: router,
      commentListener: commentListener,
      reactionListener: reactionListener,
    );
  }

  void addContact(_PostEngagementUser other) {
    contactRepo.addTestContact(_contact(other.peerId, other.username));
  }

  void start() {
    router.start();
    commentListener.start();
    reactionListener.start();
  }

  void dispose() {
    reactionListener.dispose();
    commentListener.dispose();
    router.dispose();
    postRepo.dispose();
    p2pService.dispose();
  }
}

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
