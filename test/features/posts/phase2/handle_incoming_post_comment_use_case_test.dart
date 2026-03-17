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
    expiresAt: '2026-03-18T10:15:30.000Z',
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

  test(
    'stages orphan post_comment events when the parent post is missing',
    () async {
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

      expect(result, HandleIncomingPostCommentResult.stagedPendingParent);
      expect(comment, isNull);
      expect(await posts.loadComments('post-1'), isEmpty);

      final pending = await posts.loadPendingChildEvents('post-1');
      expect(pending, hasLength(1));
      expect(pending.single.eventType, 'post_comment');
      expect(pending.single.eventId, 'evt-comment-1');
    },
  );

  test('persists post_comment events under an existing post', () async {
    await posts.savePost(_post('post-1'));
    final commentedAt = DateTime.now().toUtc().subtract(
      const Duration(minutes: 1),
    );

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

    expect(result, HandleIncomingPostCommentResult.commentCreated);
    expect(comment, isNotNull);
    expect(comment!.body, 'I can lend one.');

    final comments = await posts.loadComments('post-1');
    expect(comments, hasLength(1));
    expect(comments.single.id, 'comment-1');

    final updatedPost = await posts.getPost('post-1');
    expect(
      updatedPost?.expiresAt,
      commentedAt.add(const Duration(days: 3)).toIso8601String(),
    );
    expect(updatedPost?.lastEngagementAt, commentedAt.toIso8601String());
  });

  test('dedupes repeated post_comment deliveries by comment_id', () async {
    await posts.savePost(_post('post-1'));
    final message = _commentMessage(
      eventId: 'evt-comment-1',
      commentId: 'comment-1',
      postId: 'post-1',
      transportSender: 'peer-bob',
      body: 'I can lend one.',
    );

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

    expect(first.$1, HandleIncomingPostCommentResult.commentCreated);
    expect(second.$1, HandleIncomingPostCommentResult.duplicate);
    expect(await posts.loadComments('post-1'), hasLength(1));
  });

  test(
    'reconciles staged comments after the parent post is ingested',
    () async {
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

      expect(applied, 1);
      expect(await posts.loadPendingChildEvents('post-1'), isEmpty);
      expect(await posts.loadComments('post-1'), hasLength(1));
      expect(
        (await posts.loadComments('post-1')).single.body,
        'I can lend one.',
      );
    },
  );

  test(
    'persists the incoming sender as a repost-engagement participant for repost-threaded posts',
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

      expect(result, HandleIncomingPostCommentResult.commentCreated);
      expect(comment, isNotNull);
      expect(
        await posts.loadRepostEngagementParticipantPeerIds('post-1'),
        <String>{'peer-ibra', 'peer-james'},
      );
    },
  );
}
