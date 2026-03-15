import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/posts/application/post_reaction_listener.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_comment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';

import '../../../shared/fakes/fake_notification_service.dart';
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
  );
}

ChatMessage _reactionMessage({
  required String type,
  required String senderPeerId,
  required String postId,
  required String reactionId,
  required String eventId,
  required bool isActive,
  String? commentId,
}) {
  final reactedAt = DateTime.now().toUtc().toIso8601String();
  return ChatMessage(
    from: senderPeerId,
    to: 'peer-self',
    content: jsonEncode(<String, Object?>{
      'type': type,
      'version': '1',
      'event_id': eventId,
      'created_at': reactedAt,
      'sender_peer_id': senderPeerId,
      'payload': <String, Object?>{
        'reaction_id': reactionId,
        'post_id': postId,
        'comment_id': commentId,
        'kind': 'heart',
        'is_active': isActive,
        'reacted_at': reactedAt,
      },
    }),
    timestamp: reactedAt,
    isIncoming: true,
  );
}

void main() {
  late StreamController<ChatMessage> postReactionController;
  late StreamController<ChatMessage> commentReactionController;
  late InMemoryContactRepository contacts;
  late InMemoryPostRepository posts;
  late FakeNotificationService notifications;
  late PostReactionListener listener;

  setUp(() {
    postReactionController = StreamController<ChatMessage>.broadcast();
    commentReactionController = StreamController<ChatMessage>.broadcast();
    contacts = InMemoryContactRepository();
    posts = InMemoryPostRepository();
    notifications = FakeNotificationService();
    listener = PostReactionListener(
      postReactionStream: postReactionController.stream,
      postCommentReactionStream: commentReactionController.stream,
      postRepo: posts,
      contactRepo: contacts,
      notificationService: notifications,
    )..start();
  });

  tearDown(() async {
    listener.dispose();
    posts.dispose();
    await postReactionController.close();
    await commentReactionController.close();
  });

  test('emits updates for post hearts and persists the latest state', () async {
    contacts.addTestContact(_contact('peer-bob', 'Bob'));
    await posts.savePost(_post('post-1'));

    postReactionController.add(
      _reactionMessage(
        type: 'post_reaction',
        senderPeerId: 'peer-bob',
        postId: 'post-1',
        reactionId: 'post_heart:post-1:peer-bob',
        eventId: 'evt-reaction-1',
        isActive: true,
      ),
    );

    final update = await listener.incomingPostReactionStream.first.timeout(
      const Duration(seconds: 1),
    );
    expect(update.reactionId, 'post_heart:post-1:peer-bob');
    expect((await posts.loadPostReactions('post-1')).single.isActive, isTrue);
  });

  test('stages comment-heart events until the target comment exists', () async {
    contacts.addTestContact(_contact('peer-bob', 'Bob'));
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

    commentReactionController.add(
      _reactionMessage(
        type: 'post_comment_reaction',
        senderPeerId: 'peer-bob',
        postId: 'post-1',
        commentId: 'comment-2',
        reactionId: 'comment_heart:comment-2:peer-bob',
        eventId: 'evt-comment-reaction-1',
        isActive: true,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(await posts.loadCommentReactions('comment-2'), isEmpty);
    expect(await posts.loadPendingChildEvents('post-1'), hasLength(1));
  });

  test('shows notifications for hearts on the local user post', () async {
    contacts.addTestContact(_contact('peer-bob', 'Bob'));
    await posts.savePost(_ownPost('post-1'));

    postReactionController.add(
      _reactionMessage(
        type: 'post_reaction',
        senderPeerId: 'peer-bob',
        postId: 'post-1',
        reactionId: 'post_heart:post-1:peer-bob',
        eventId: 'evt-reaction-1',
        isActive: true,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(notifications.shownGeneric, hasLength(1));
    expect(notifications.shownGeneric.single.payload, 'post:post-1');
  });
}

PostModel _ownPost(String postId) {
  return PostModel(
    id: postId,
    eventId: 'evt-$postId',
    senderPeerId: 'peer-self',
    authorPeerId: 'peer-self',
    authorUsername: 'Alice',
    text: 'My post',
    audience: PostAudience.allFriends(),
    createdAt: '2026-03-15T10:15:30.000Z',
    visibleAt: '2026-03-15T10:15:30.000Z',
    expiresAt: '2026-03-18T10:15:30.000Z',
    isIncoming: false,
  );
}
