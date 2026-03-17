import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/posts/application/post_comment_listener.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';

import '../../../shared/fakes/fake_notification_service.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';

ContactModel _contact(
  String peerId,
  String username, {
  bool archived = false,
  bool blocked = false,
}) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/dns4/example.invalid/tcp/443',
    username: username,
    signature: 'sig-$peerId',
    scannedAt: '2026-03-15T10:00:00.000Z',
    isArchived: archived,
    isBlocked: blocked,
  );
}

ChatMessage _message({
  required String senderPeerId,
  required String postId,
  required String commentId,
  String? createdAt,
}) {
  final resolvedCreatedAt =
      createdAt ?? DateTime.now().toUtc().toIso8601String();
  return ChatMessage(
    from: senderPeerId,
    to: 'peer-self',
    content: jsonEncode(<String, Object?>{
      'type': 'post_comment',
      'version': '1',
      'event_id': 'evt-$commentId',
      'created_at': resolvedCreatedAt,
      'sender_peer_id': senderPeerId,
      'payload': <String, Object?>{
        'comment_id': commentId,
        'post_id': postId,
        'body': 'I can lend one.',
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
    text: 'Need a ladder',
    audience: PostAudience.allFriends(),
    createdAt: '2026-03-15T10:15:30.000Z',
    visibleAt: '2026-03-15T10:15:30.000Z',
    expiresAt: '2026-03-18T10:15:30.000Z',
  );
}

void main() {
  late StreamController<ChatMessage> controller;
  late InMemoryContactRepository contacts;
  late InMemoryPostRepository posts;
  late FakeNotificationService notifications;
  late PostCommentListener listener;

  setUp(() {
    controller = StreamController<ChatMessage>.broadcast();
    contacts = InMemoryContactRepository();
    posts = InMemoryPostRepository();
    notifications = FakeNotificationService();
    listener = PostCommentListener(
      postCommentStream: controller.stream,
      postRepo: posts,
      contactRepo: contacts,
      notificationService: notifications,
    )..start();
  });

  tearDown(() async {
    listener.dispose();
    posts.dispose();
    await controller.close();
  });

  test('persists comments that arrive for an existing post', () async {
    contacts.addTestContact(_contact('peer-bob', 'Bob'));
    await posts.savePost(_post('post-1'));

    controller.add(
      _message(
        senderPeerId: 'peer-bob',
        postId: 'post-1',
        commentId: 'comment-1',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(await posts.loadComments('post-1'), hasLength(1));
    expect((await posts.loadComments('post-1')).single.body, 'I can lend one.');
  });

  test('stages comments when the parent post has not arrived yet', () async {
    contacts.addTestContact(_contact('peer-bob', 'Bob'));

    controller.add(
      _message(
        senderPeerId: 'peer-bob',
        postId: 'post-1',
        commentId: 'comment-1',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(await posts.loadComments('post-1'), isEmpty);
    expect(await posts.loadPendingChildEvents('post-1'), hasLength(1));
  });

  test('shows notifications for comments on the local user post', () async {
    contacts.addTestContact(_contact('peer-bob', 'Bob'));
    await posts.savePost(_ownPost('post-1'));

    controller.add(
      _message(
        senderPeerId: 'peer-bob',
        postId: 'post-1',
        commentId: 'comment-1',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(notifications.shownGeneric, hasLength(1));
    expect(
      notifications.shownGeneric.single.payload,
      'post_comment:post-1:comment-1',
    );
  });

  test('dedupes repeated deliveries and emits the comment once', () async {
    contacts.addTestContact(_contact('peer-bob', 'Bob'));
    await posts.savePost(_ownPost('post-1'));
    final emittedCommentIds = <String>[];
    final subscription = listener.incomingCommentStream.listen((comment) {
      emittedCommentIds.add(comment.id);
    });
    addTearDown(subscription.cancel);
    final message = _message(
      senderPeerId: 'peer-bob',
      postId: 'post-1',
      commentId: 'comment-1',
      createdAt: '2026-03-15T11:00:00.000Z',
    );

    controller.add(message);
    controller.add(message);
    await Future<void>.delayed(const Duration(milliseconds: 75));

    expect(await posts.loadComments('post-1'), hasLength(1));
    expect(emittedCommentIds, <String>['comment-1']);
    expect(notifications.shownGeneric, hasLength(1));
  });
}

PostModel _ownPost(String postId) {
  return PostModel(
    id: postId,
    eventId: 'evt-$postId',
    senderPeerId: 'peer-self',
    authorPeerId: 'peer-self',
    authorUsername: 'Alice',
    text: 'My own post',
    audience: PostAudience.allFriends(),
    createdAt: '2026-03-15T10:15:30.000Z',
    visibleAt: '2026-03-15T10:15:30.000Z',
    expiresAt: '2026-03-18T10:15:30.000Z',
    isIncoming: false,
  );
}
