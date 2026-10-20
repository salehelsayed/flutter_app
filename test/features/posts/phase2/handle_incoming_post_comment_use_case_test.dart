import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/posts/application/handle_incoming_post_comment_use_case.dart';
import 'package:flutter_app/features/posts/application/reconcile_pending_post_child_events_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_origin_model.dart';

import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';

ContactModel _contact(String peerId, String username, {bool blocked = false}) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/dns4/example.invalid/tcp/443',
    username: username,
    signature: 'sig-$peerId',
    scannedAt: '2026-03-15T10:00:00.000Z',
    isBlocked: blocked,
  );
}

ChatMessage _commentMessage({
  required String eventId,
  required String commentId,
  required String postId,
  required String transportSender,
  required String body,
  String? createdAt,
}) {
  final resolvedCreatedAt =
      createdAt ?? DateTime.now().toUtc().toIso8601String();
  return ChatMessage(
    from: transportSender,
    to: 'peer-self',
    content: jsonEncode(<String, Object?>{
      'type': 'post_comment',
      'version': '1',
      'event_id': eventId,
      'created_at': resolvedCreatedAt,
      'sender_peer_id': transportSender,
      'payload': <String, Object?>{
        'comment_id': commentId,
        'post_id': postId,
        'body': body,
        'commented_at': resolvedCreatedAt,
      },
    }),
    timestamp: resolvedCreatedAt,
    isIncoming: true,
  );
}

PostModel _post(String postId) {
  return PostModel(
    id: postId,
    eventId: 'evt-$postId',
    senderPeerId: 'peer-bob',
    authorPeerId: 'peer-bob',
    authorUsername: 'Bob',
    text: 'Need a ladder in Kreuzberg',
    audience: PostAudience.allFriends(),
    createdAt: '2026-03-15T10:15:30.000Z',
    visibleAt: '2026-03-15T10:15:30.000Z',
    expiresAt: '2026-03-16T10:15:30.000Z',
  );
}

void main() {
  late InMemoryContactRepository contacts;
  late InMemoryPostRepository posts;

  setUp(() {
    contacts = InMemoryContactRepository();
    posts = InMemoryPostRepository();
    contacts.addTestContact(_contact('peer-bob', 'Bob'));
  });

  tearDown(() {
    posts.dispose();
  });

  test('rejects orphan comments without staging a pending event', () async {
    final previousPost = await posts.getPost('post-1');
    final previousParticipants = await posts
        .loadRepostEngagementParticipantPeerIds('post-1');
    final (result, comment) = await handleIncomingPostComment(
      message: _commentMessage(
        eventId: 'evt-comment-1',
        commentId: 'comment-1',
        postId: 'post-1',
        transportSender: 'peer-bob',
        body: 'I can lend one.',
      ),
      postRepo: posts,
      contactRepo: contacts,
    );

    expect(result, HandleIncomingPostCommentResult.notPostComment);
    expect(comment, isNull);
    expect(await posts.loadComments('post-1'), isEmpty);
    expect(await posts.loadPostReactions('post-1'), isEmpty);
    expect(await posts.loadCommentReactions('comment-1'), isEmpty);
    expect(await posts.loadPendingChildEvents('post-1'), isEmpty);
    expect(
      await posts.loadRepostEngagementParticipantPeerIds('post-1'),
      previousParticipants,
    );
    if (previousPost != null) {
      expect(
        (await posts.getPost('post-1'))?.expiresAt,
        previousPost.expiresAt,
      );
      expect(
        (await posts.getPost('post-1'))?.lastEngagementAt,
        previousPost.lastEngagementAt,
      );
    }
  });

  test(
    'rejects comments under an existing thought without extending expiry',
    () async {
      await posts.savePost(_post('post-1'));
      final commentedAt = DateTime.now().toUtc().subtract(
        const Duration(minutes: 1),
      );

      final previousPost = await posts.getPost('post-1');
      final previousParticipants = await posts
          .loadRepostEngagementParticipantPeerIds('post-1');
      final (result, comment) = await handleIncomingPostComment(
        message: _commentMessage(
          eventId: 'evt-comment-1',
          commentId: 'comment-1',
          postId: 'post-1',
          transportSender: 'peer-bob',
          body: 'I can lend one.',
          createdAt: commentedAt.toIso8601String(),
        ),
        postRepo: posts,
        contactRepo: contacts,
      );

      expect(result, HandleIncomingPostCommentResult.notPostComment);
      expect(comment, isNull);
      expect(await posts.loadComments('post-1'), isEmpty);
      expect(await posts.loadPostReactions('post-1'), isEmpty);
      expect(await posts.loadCommentReactions('comment-1'), isEmpty);
      expect(await posts.loadPendingChildEvents('post-1'), isEmpty);
      expect(
        await posts.loadRepostEngagementParticipantPeerIds('post-1'),
        previousParticipants,
      );
      if (previousPost != null) {
        expect(
          (await posts.getPost('post-1'))?.expiresAt,
          previousPost.expiresAt,
        );
        expect(
          (await posts.getPost('post-1'))?.lastEngagementAt,
          previousPost.lastEngagementAt,
        );
      }
    },
  );

  test(
    'rejects comments containing bidi controls without storing text',
    () async {
      await posts.savePost(_post('post-1'));

      final previousPost = await posts.getPost('post-1');
      final previousParticipants = await posts
          .loadRepostEngagementParticipantPeerIds('post-1');
      final (result, comment) = await handleIncomingPostComment(
        message: _commentMessage(
          eventId: 'evt-comment-1',
          commentId: 'comment-1',
          postId: 'post-1',
          transportSender: 'peer-bob',
          body: 'مرحبا\u202E Hello\u200E 123',
        ),
        postRepo: posts,
        contactRepo: contacts,
      );

      expect(result, HandleIncomingPostCommentResult.notPostComment);
      expect(comment, isNull);
      expect(await posts.loadComments('post-1'), isEmpty);
      expect(await posts.loadPostReactions('post-1'), isEmpty);
      expect(await posts.loadCommentReactions('comment-1'), isEmpty);
      expect(await posts.loadPendingChildEvents('post-1'), isEmpty);
      expect(
        await posts.loadRepostEngagementParticipantPeerIds('post-1'),
        previousParticipants,
      );
      if (previousPost != null) {
        expect(
          (await posts.getPost('post-1'))?.expiresAt,
          previousPost.expiresAt,
        );
        expect(
          (await posts.getPost('post-1'))?.lastEngagementAt,
          previousPost.lastEngagementAt,
        );
      }
    },
  );

  test('rejects both deliveries of a repeated comment', () async {
    await posts.savePost(_post('post-1'));
    final message = _commentMessage(
      eventId: 'evt-comment-1',
      commentId: 'comment-1',
      postId: 'post-1',
      transportSender: 'peer-bob',
      body: 'I can lend one.',
    );

    final previousPost = await posts.getPost('post-1');
    final previousParticipants = await posts
        .loadRepostEngagementParticipantPeerIds('post-1');
    final first = await handleIncomingPostComment(
      message: message,
      postRepo: posts,
      contactRepo: contacts,
    );
    final second = await handleIncomingPostComment(
      message: message,
      postRepo: posts,
      contactRepo: contacts,
    );

    expect(first.$1, HandleIncomingPostCommentResult.notPostComment);
    expect(second.$1, HandleIncomingPostCommentResult.notPostComment);
    expect(await posts.loadComments('post-1'), isEmpty);
    expect(await posts.loadPostReactions('post-1'), isEmpty);
    expect(await posts.loadCommentReactions('comment-1'), isEmpty);
    expect(await posts.loadPendingChildEvents('post-1'), isEmpty);
    expect(
      await posts.loadRepostEngagementParticipantPeerIds('post-1'),
      previousParticipants,
    );
    if (previousPost != null) {
      expect(
        (await posts.getPost('post-1'))?.expiresAt,
        previousPost.expiresAt,
      );
      expect(
        (await posts.getPost('post-1'))?.lastEngagementAt,
        previousPost.lastEngagementAt,
      );
    }
  });

  test(
    'rejected comments are not reconciled after their parent arrives',
    () async {
      final previousPost = await posts.getPost('post-1');
      final previousParticipants = await posts
          .loadRepostEngagementParticipantPeerIds('post-1');
      await handleIncomingPostComment(
        message: _commentMessage(
          eventId: 'evt-comment-1',
          commentId: 'comment-1',
          postId: 'post-1',
          transportSender: 'peer-bob',
          body: 'I can lend one.',
        ),
        postRepo: posts,
        contactRepo: contacts,
      );
      await posts.savePost(_post('post-1'));

      final applied = await reconcilePendingPostChildEvents(
        postId: 'post-1',
        postRepo: posts,
        contactRepo: contacts,
      );

      expect(applied, 0);
      expect(await posts.loadComments('post-1'), isEmpty);
      expect(await posts.loadPostReactions('post-1'), isEmpty);
      expect(await posts.loadCommentReactions('comment-1'), isEmpty);
      expect(await posts.loadPendingChildEvents('post-1'), isEmpty);
      expect(
        await posts.loadRepostEngagementParticipantPeerIds('post-1'),
        previousParticipants,
      );
      if (previousPost != null) {
        expect(
          (await posts.getPost('post-1'))?.expiresAt,
          previousPost.expiresAt,
        );
        expect(
          (await posts.getPost('post-1'))?.lastEngagementAt,
          previousPost.lastEngagementAt,
        );
      }
    },
  );

  test(
    'rejects repost-thread comments without adding the sender as a participant',
    () async {
      await posts.savePost(
        _post('post-1').copyWith(
          senderPeerId: 'peer-james',
          authorPeerId: 'peer-bob',
          authorUsername: 'Bob',
        ),
      );
      await posts.savePostOrigin(
        const PostOriginModel(
          postId: 'post-1',
          originKind: PostOriginKind.pass,
          passId: 'pass-1',
          passerPeerId: 'peer-james',
          passerUsername: 'James',
          passCreatedAt: '2026-03-15T11:15:00.000Z',
        ),
      );
      await posts.saveRepostEngagementParticipant(
        postId: 'post-1',
        participantPeerId: 'peer-james',
        createdAt: '2026-03-15T11:15:00.000Z',
      );
      contacts.addTestContact(_contact('peer-ibra', 'Ibra'));

      final previousPost = await posts.getPost('post-1');
      final previousParticipants = await posts
          .loadRepostEngagementParticipantPeerIds('post-1');
      final (result, comment) = await handleIncomingPostComment(
        message: _commentMessage(
          eventId: 'evt-comment-2',
          commentId: 'comment-2',
          postId: 'post-1',
          transportSender: 'peer-ibra',
          body: 'I can help too.',
        ),
        postRepo: posts,
        contactRepo: contacts,
      );

      expect(result, HandleIncomingPostCommentResult.notPostComment);
      expect(comment, isNull);
      expect(await posts.loadComments('post-1'), isEmpty);
      expect(await posts.loadPostReactions('post-1'), isEmpty);
      expect(await posts.loadCommentReactions('comment-1'), isEmpty);
      expect(await posts.loadPendingChildEvents('post-1'), isEmpty);
      expect(
        await posts.loadRepostEngagementParticipantPeerIds('post-1'),
        previousParticipants,
      );
      if (previousPost != null) {
        expect(
          (await posts.getPost('post-1'))?.expiresAt,
          previousPost.expiresAt,
        );
        expect(
          (await posts.getPost('post-1'))?.lastEngagementAt,
          previousPost.lastEngagementAt,
        );
      }
    },
  );

  test(
    'rejects comments from trusted non-contact repost participants',
    () async {
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
          passCreatedAt: '2026-03-15T11:15:00.000Z',
        ),
      );
      await posts.saveRepostEngagementParticipant(
        postId: 'post-1',
        participantPeerId: 'peer-solz',
        createdAt: '2026-03-15T11:15:00.000Z',
      );
      await posts.saveRepostEngagementParticipant(
        postId: 'post-1',
        participantPeerId: 'peer-hisam',
        createdAt: '2026-03-15T11:15:00.000Z',
      );
      await posts.saveRepostEngagementParticipant(
        postId: 'post-1',
        participantPeerId: 'peer-ibra',
        createdAt: '2026-03-15T11:16:30.000Z',
      );

      final previousPost = await posts.getPost('post-1');
      final previousParticipants = await posts
          .loadRepostEngagementParticipantPeerIds('post-1');
      final (result, comment) = await handleIncomingPostComment(
        message: _commentMessage(
          eventId: 'evt-comment-3',
          commentId: 'comment-3',
          postId: 'post-1',
          transportSender: 'peer-ibra',
          body: 'I can help too.',
        ),
        postRepo: posts,
        contactRepo: contacts,
      );

      expect(result, HandleIncomingPostCommentResult.notPostComment);
      expect(comment, isNull);
      expect(await posts.loadComments('post-1'), isEmpty);
      expect(await posts.loadPostReactions('post-1'), isEmpty);
      expect(await posts.loadCommentReactions('comment-1'), isEmpty);
      expect(await posts.loadPendingChildEvents('post-1'), isEmpty);
      expect(
        await posts.loadRepostEngagementParticipantPeerIds('post-1'),
        previousParticipants,
      );
      if (previousPost != null) {
        expect(
          (await posts.getPost('post-1'))?.expiresAt,
          previousPost.expiresAt,
        );
        expect(
          (await posts.getPost('post-1'))?.lastEngagementAt,
          previousPost.lastEngagementAt,
        );
      }
    },
  );

  test('rejects comments from unknown non-contact senders', () async {
    await posts.savePost(_post('post-1'));

    final previousPost = await posts.getPost('post-1');
    final previousParticipants = await posts
        .loadRepostEngagementParticipantPeerIds('post-1');
    final (result, comment) = await handleIncomingPostComment(
      message: _commentMessage(
        eventId: 'evt-comment-unknown',
        commentId: 'comment-unknown',
        postId: 'post-1',
        transportSender: 'peer-ibra',
        body: 'I do not belong here.',
      ),
      postRepo: posts,
      contactRepo: contacts,
    );

    expect(result, HandleIncomingPostCommentResult.notPostComment);
    expect(comment, isNull);
    expect(await posts.loadComments('post-1'), isEmpty);
    expect(await posts.loadPostReactions('post-1'), isEmpty);
    expect(await posts.loadCommentReactions('comment-1'), isEmpty);
    expect(await posts.loadPendingChildEvents('post-1'), isEmpty);
    expect(
      await posts.loadRepostEngagementParticipantPeerIds('post-1'),
      previousParticipants,
    );
    if (previousPost != null) {
      expect(
        (await posts.getPost('post-1'))?.expiresAt,
        previousPost.expiresAt,
      );
      expect(
        (await posts.getPost('post-1'))?.lastEngagementAt,
        previousPost.lastEngagementAt,
      );
    }
  });

  test(
    'rejects comments from blocked but trusted repost participants',
    () async {
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
          passCreatedAt: '2026-03-15T11:15:00.000Z',
        ),
      );
      await posts.saveRepostEngagementParticipant(
        postId: 'post-1',
        participantPeerId: 'peer-solz',
        createdAt: '2026-03-15T11:15:00.000Z',
      );
      await posts.saveRepostEngagementParticipant(
        postId: 'post-1',
        participantPeerId: 'peer-hisam',
        createdAt: '2026-03-15T11:15:00.000Z',
      );
      contacts.addTestContact(_contact('peer-ibra', 'Ibra', blocked: true));

      final previousPost = await posts.getPost('post-1');
      final previousParticipants = await posts
          .loadRepostEngagementParticipantPeerIds('post-1');
      final (result, comment) = await handleIncomingPostComment(
        message: _commentMessage(
          eventId: 'evt-comment-blocked',
          commentId: 'comment-blocked',
          postId: 'post-1',
          transportSender: 'peer-ibra',
          body: 'This should stay blocked.',
        ),
        postRepo: posts,
        contactRepo: contacts,
      );

      expect(result, HandleIncomingPostCommentResult.notPostComment);
      expect(comment, isNull);
      expect(await posts.loadComments('post-1'), isEmpty);
      expect(await posts.loadPostReactions('post-1'), isEmpty);
      expect(await posts.loadCommentReactions('comment-1'), isEmpty);
      expect(await posts.loadPendingChildEvents('post-1'), isEmpty);
      expect(
        await posts.loadRepostEngagementParticipantPeerIds('post-1'),
        previousParticipants,
      );
      if (previousPost != null) {
        expect(
          (await posts.getPost('post-1'))?.expiresAt,
          previousPost.expiresAt,
        );
        expect(
          (await posts.getPost('post-1'))?.lastEngagementAt,
          previousPost.lastEngagementAt,
        );
      }
    },
  );
}
