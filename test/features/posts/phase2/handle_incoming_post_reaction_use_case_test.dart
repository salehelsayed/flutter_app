import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/posts/application/handle_incoming_post_reaction_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_comment_model.dart';
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
  );
}

ChatMessage _postReactionMessage({
  required String senderPeerId,
  required String postId,
  required String reactionId,
  required String eventId,
  required bool isActive,
  String? reactedAt,
}) {
  final resolvedReactedAt =
      reactedAt ?? DateTime.now().toUtc().toIso8601String();
  return ChatMessage(
    from: senderPeerId,
    to: 'peer-self',
    content: jsonEncode(<String, Object?>{
      'type': 'post_reaction',
      'version': '1',
      'event_id': eventId,
      'created_at': resolvedReactedAt,
      'sender_peer_id': senderPeerId,
      'payload': <String, Object?>{
        'reaction_id': reactionId,
        'post_id': postId,
        'kind': 'heart',
        'is_active': isActive,
        'reacted_at': resolvedReactedAt,
      },
    }),
    timestamp: resolvedReactedAt,
    isIncoming: true,
  );
}

ChatMessage _commentReactionMessage({
  required String senderPeerId,
  required String postId,
  required String commentId,
  required String reactionId,
  required String eventId,
  required bool isActive,
  String? reactedAt,
}) {
  final resolvedReactedAt =
      reactedAt ?? DateTime.now().toUtc().toIso8601String();
  return ChatMessage(
    from: senderPeerId,
    to: 'peer-self',
    content: jsonEncode(<String, Object?>{
      'type': 'post_comment_reaction',
      'version': '1',
      'event_id': eventId,
      'created_at': resolvedReactedAt,
      'sender_peer_id': senderPeerId,
      'payload': <String, Object?>{
        'reaction_id': reactionId,
        'post_id': postId,
        'comment_id': commentId,
        'kind': 'heart',
        'is_active': isActive,
        'reacted_at': resolvedReactedAt,
      },
    }),
    timestamp: resolvedReactedAt,
    isIncoming: true,
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

  test('rejects orphan post reactions without staging them', () async {
    final previousPost = await posts.getPost('post-1');
    final previousParticipants = await posts
        .loadRepostEngagementParticipantPeerIds('post-1');
    final (result, reaction) = await handleIncomingPostReaction(
      message: _postReactionMessage(
        senderPeerId: 'peer-bob',
        postId: 'post-1',
        reactionId: 'post_heart:post-1:peer-bob',
        eventId: 'evt-reaction-1',
        isActive: true,
      ),
      postRepo: posts,
      contactRepo: contacts,
    );

    expect(result, HandleIncomingPostReactionResult.notPostReaction);
    expect(reaction, isNull);
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

  test('rejects post reactions for an existing thought', () async {
    await posts.savePost(_post('post-1'));

    final previousPost = await posts.getPost('post-1');
    final previousParticipants = await posts
        .loadRepostEngagementParticipantPeerIds('post-1');
    final (result, reaction) = await handleIncomingPostReaction(
      message: _postReactionMessage(
        senderPeerId: 'peer-bob',
        postId: 'post-1',
        reactionId: 'post_heart:post-1:peer-bob',
        eventId: 'evt-reaction-1',
        isActive: true,
      ),
      postRepo: posts,
      contactRepo: contacts,
    );

    expect(result, HandleIncomingPostReactionResult.notPostReaction);
    expect(reaction, isNull);
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

  test('rejects both newer and older updates to the same reaction', () async {
    await posts.savePost(_post('post-1'));
    final newerReactionAt = DateTime.now().toUtc().subtract(
      const Duration(minutes: 1),
    );
    final olderReactionAt = newerReactionAt.subtract(const Duration(hours: 1));
    final previousPost = await posts.getPost('post-1');
    final previousParticipants = await posts
        .loadRepostEngagementParticipantPeerIds('post-1');
    await handleIncomingPostReaction(
      message: _postReactionMessage(
        senderPeerId: 'peer-bob',
        postId: 'post-1',
        reactionId: 'post_heart:post-1:peer-bob',
        eventId: 'evt-reaction-2',
        isActive: false,
        reactedAt: newerReactionAt.toIso8601String(),
      ),
      postRepo: posts,
      contactRepo: contacts,
    );

    final (result, _) = await handleIncomingPostReaction(
      message: _postReactionMessage(
        senderPeerId: 'peer-bob',
        postId: 'post-1',
        reactionId: 'post_heart:post-1:peer-bob',
        eventId: 'evt-reaction-1',
        isActive: true,
        reactedAt: olderReactionAt.toIso8601String(),
      ),
      postRepo: posts,
      contactRepo: contacts,
    );

    expect(result, HandleIncomingPostReactionResult.notPostReaction);
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
    'rejects comment reactions when the target comment is missing',
    () async {
      await posts.savePost(_post('post-1'));

      final previousPost = await posts.getPost('post-1');
      final previousParticipants = await posts
          .loadRepostEngagementParticipantPeerIds('post-1');
      final (result, reaction) = await handleIncomingPostCommentReaction(
        message: _commentReactionMessage(
          senderPeerId: 'peer-bob',
          postId: 'post-1',
          commentId: 'comment-1',
          reactionId: 'comment_heart:comment-1:peer-bob',
          eventId: 'evt-comment-reaction-1',
          isActive: true,
        ),
        postRepo: posts,
        contactRepo: contacts,
      );

      expect(
        result,
        HandleIncomingPostCommentReactionResult.notPostCommentReaction,
      );
      expect(reaction, isNull);
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
    'rejects repost comment reactions without adding a participant',
    () async {
      await posts.savePost(
        _post('post-1').copyWith(
          senderPeerId: 'peer-hisam',
          authorPeerId: 'peer-bob',
          authorUsername: 'Bob',
        ),
      );
      await posts.saveComment(
        const PostCommentModel(
          id: 'comment-1',
          eventId: 'evt-comment-1',
          postId: 'post-1',
          senderPeerId: 'peer-bob',
          authorUsername: 'Bob',
          body: 'I can lend one.',
          commentedAt: '2026-03-15T11:00:00.000Z',
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
        participantPeerId: 'peer-hisam',
        createdAt: '2026-03-15T11:15:00.000Z',
      );
      contacts.addTestContact(_contact('peer-ibra', 'Ibra'));

      final previousPost = await posts.getPost('post-1');
      final previousParticipants = await posts
          .loadRepostEngagementParticipantPeerIds('post-1');
      final (result, reaction) = await handleIncomingPostCommentReaction(
        message: _commentReactionMessage(
          senderPeerId: 'peer-ibra',
          postId: 'post-1',
          commentId: 'comment-1',
          reactionId: 'comment_heart:comment-1:peer-ibra',
          eventId: 'evt-comment-reaction-2',
          isActive: true,
        ),
        postRepo: posts,
        contactRepo: contacts,
      );

      expect(
        result,
        HandleIncomingPostCommentReactionResult.notPostCommentReaction,
      );
      expect(reaction, isNull);
      expect(await posts.loadComments('post-1'), hasLength(1));
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
    'rejects post reactions from trusted non-contact participants',
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
      await posts.saveRepostEngagementParticipant(
        postId: 'post-1',
        participantPeerId: 'peer-ibra',
        createdAt: '2026-03-15T11:16:30.000Z',
      );

      final previousPost = await posts.getPost('post-1');
      final previousParticipants = await posts
          .loadRepostEngagementParticipantPeerIds('post-1');
      final (result, reaction) = await handleIncomingPostReaction(
        message: _postReactionMessage(
          senderPeerId: 'peer-ibra',
          postId: 'post-1',
          reactionId: 'post_heart:post-1:peer-ibra',
          eventId: 'evt-reaction-3',
          isActive: true,
        ),
        postRepo: posts,
        contactRepo: contacts,
      );

      expect(result, HandleIncomingPostReactionResult.notPostReaction);
      expect(reaction, isNull);
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
    'rejects comment reactions from trusted non-contact participants',
    () async {
      await posts.savePost(
        _post('post-1').copyWith(
          senderPeerId: 'peer-hisam',
          authorPeerId: 'peer-solz',
          authorUsername: 'Solz',
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
      await posts.saveRepostEngagementParticipant(
        postId: 'post-1',
        participantPeerId: 'peer-ibra',
        createdAt: '2026-03-15T11:16:30.000Z',
      );

      final previousPost = await posts.getPost('post-1');
      final previousParticipants = await posts
          .loadRepostEngagementParticipantPeerIds('post-1');
      final (result, reaction) = await handleIncomingPostCommentReaction(
        message: _commentReactionMessage(
          senderPeerId: 'peer-ibra',
          postId: 'post-1',
          commentId: 'comment-1',
          reactionId: 'comment_heart:comment-1:peer-ibra',
          eventId: 'evt-comment-reaction-3',
          isActive: true,
        ),
        postRepo: posts,
        contactRepo: contacts,
      );

      expect(
        result,
        HandleIncomingPostCommentReactionResult.notPostCommentReaction,
      );
      expect(reaction, isNull);
      expect(await posts.loadComments('post-1'), hasLength(1));
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

  test('rejects post reactions from unknown non-contact senders', () async {
    await posts.savePost(_post('post-1'));

    final previousPost = await posts.getPost('post-1');
    final previousParticipants = await posts
        .loadRepostEngagementParticipantPeerIds('post-1');
    final (result, reaction) = await handleIncomingPostReaction(
      message: _postReactionMessage(
        senderPeerId: 'peer-ibra',
        postId: 'post-1',
        reactionId: 'post_heart:post-1:peer-ibra',
        eventId: 'evt-reaction-unknown',
        isActive: true,
      ),
      postRepo: posts,
      contactRepo: contacts,
    );

    expect(result, HandleIncomingPostReactionResult.notPostReaction);
    expect(reaction, isNull);
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

  test('rejects post reactions from blocked trusted participants', () async {
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
    contacts.addTestContact(_contact('peer-ibra', 'Ibra', blocked: true));

    final previousPost = await posts.getPost('post-1');
    final previousParticipants = await posts
        .loadRepostEngagementParticipantPeerIds('post-1');
    final (result, reaction) = await handleIncomingPostReaction(
      message: _postReactionMessage(
        senderPeerId: 'peer-ibra',
        postId: 'post-1',
        reactionId: 'post_heart:post-1:peer-ibra',
        eventId: 'evt-reaction-blocked',
        isActive: true,
      ),
      postRepo: posts,
      contactRepo: contacts,
    );

    expect(result, HandleIncomingPostReactionResult.notPostReaction);
    expect(reaction, isNull);
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

  test('rejects comment reactions from unknown non-contact senders', () async {
    await posts.savePost(_post('post-1'));
    await posts.saveComment(
      const PostCommentModel(
        id: 'comment-1',
        eventId: 'evt-comment-1',
        postId: 'post-1',
        senderPeerId: 'peer-alice',
        authorUsername: 'Alice',
        body: 'I can help too.',
        commentedAt: '2026-03-15T11:16:00.000Z',
      ),
    );

    final previousPost = await posts.getPost('post-1');
    final previousParticipants = await posts
        .loadRepostEngagementParticipantPeerIds('post-1');
    final (result, reaction) = await handleIncomingPostCommentReaction(
      message: _commentReactionMessage(
        senderPeerId: 'peer-ibra',
        postId: 'post-1',
        commentId: 'comment-1',
        reactionId: 'comment_heart:comment-1:peer-ibra',
        eventId: 'evt-comment-reaction-unknown',
        isActive: true,
      ),
      postRepo: posts,
      contactRepo: contacts,
    );

    expect(
      result,
      HandleIncomingPostCommentReactionResult.notPostCommentReaction,
    );
    expect(reaction, isNull);
    expect(await posts.loadComments('post-1'), hasLength(1));
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

  test('rejects comment reactions from blocked trusted participants', () async {
    await posts.savePost(
      _post('post-1').copyWith(
        senderPeerId: 'peer-hisam',
        authorPeerId: 'peer-solz',
        authorUsername: 'Solz',
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
    contacts.addTestContact(_contact('peer-ibra', 'Ibra', blocked: true));

    final previousPost = await posts.getPost('post-1');
    final previousParticipants = await posts
        .loadRepostEngagementParticipantPeerIds('post-1');
    final (result, reaction) = await handleIncomingPostCommentReaction(
      message: _commentReactionMessage(
        senderPeerId: 'peer-ibra',
        postId: 'post-1',
        commentId: 'comment-1',
        reactionId: 'comment_heart:comment-1:peer-ibra',
        eventId: 'evt-comment-reaction-blocked',
        isActive: true,
      ),
      postRepo: posts,
      contactRepo: contacts,
    );

    expect(
      result,
      HandleIncomingPostCommentReactionResult.notPostCommentReaction,
    );
    expect(reaction, isNull);
    expect(await posts.loadComments('post-1'), hasLength(1));
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
}
