import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/notifications/notification_service.dart';
import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/application/post_listener.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_create_envelope.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

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

ChatMessage _message(
  String senderPeerId,
  String authorUsername, {
  String? postId,
  String? text,
  String mediaKind = 'none',
}) {
  final id = postId ?? 'post-$senderPeerId';
  final createdAt = DateTime.now().toUtc().toIso8601String();
  final expiresAt = DateTime.now()
      .toUtc()
      .add(const Duration(days: 3))
      .toIso8601String();
  final envelope = PostCreateEnvelope.fromPost(
    PostModel(
      id: id,
      eventId: 'evt-$id',
      senderPeerId: senderPeerId,
      authorPeerId: senderPeerId,
      authorUsername: authorUsername,
      text: text ?? 'A post from $authorUsername',
      audience: const PostAudience(kind: PostAudienceKind.allFriends),
      createdAt: createdAt,
      visibleAt: createdAt,
      expiresAt: expiresAt,
      mediaKind: mediaKind,
      media: [
        if (mediaKind != 'none')
          PostMediaAttachmentModel(
            mediaId: 'media-$id',
            postId: id,
            blobId: 'blob-$id',
            kind: mediaKind,
            mime: mediaKind == 'voice' ? 'audio/aac' : 'image/jpeg',
            sizeBytes: 10,
            createdAt: createdAt,
          ),
      ],
    ),
  );
  return ChatMessage(
    from: senderPeerId,
    to: 'peer-self',
    content: envelope.toJson(),
    timestamp: envelope.createdAt,
    isIncoming: true,
  );
}

class _CancellingNotificationService extends FakeNotificationService
    implements ConversationNotificationCancellation {
  final cancelled = <String>[];

  @override
  Future<void> cancelConversationNotification(
    String conversationKey, {
    ConversationNotificationContentKind? onlyIfContentKind,
    ConversationNotificationContentCancellationPredicate? shouldCancelContent,
  }) async {
    cancelled.add(conversationKey);
  }
}

void main() {
  late StreamController<ChatMessage> controller;
  late InMemoryContactRepository contacts;
  late InMemoryPostRepository posts;
  late _CancellingNotificationService notifications;
  late RecentRemoteNotificationGate remoteGate;
  late PostListener listener;
  var foreground = false;

  setUp(() {
    foreground = false;
    controller = StreamController<ChatMessage>.broadcast();
    contacts = InMemoryContactRepository();
    posts = InMemoryPostRepository();
    notifications = _CancellingNotificationService();
    remoteGate = RecentRemoteNotificationGate(
      filePath:
          '${Directory.systemTemp.path}/post-listener-remote-gate-${DateTime.now().microsecondsSinceEpoch}.json',
    );
    listener = PostListener(
      postCreateStream: controller.stream,
      postRepo: posts,
      contactRepo: contacts,
      notificationService: notifications,
      isAppForegroundActive: () async => foreground,
      remoteNotificationGate: remoteGate,
    )..start();
  });

  tearDown(() async {
    listener.dispose();
    posts.dispose();
    await controller.close();
    await remoteGate.clear();
  });

  test('skips the card the background push already announced', () async {
    contacts.addTestContact(_contact('peer-bob', 'Bob'));
    await remoteGate.markAnnouncement(
      payload: 'post:post-peer-bob',
      messageId: 'evt-post-peer-bob',
    );

    controller.add(_message('peer-bob', 'Bob'));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(notifications.shownThoughts, isEmpty);
    expect(await posts.loadFeed(), hasLength(1));

    controller.add(_message('peer-bob', 'Bob', postId: 'bob-2'));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(notifications.shownThoughts.map((n) => n.payload), ['post:bob-2']);
  });

  test('titles the card with the contact name, never the claimed author', () async {
    contacts.addTestContact(_contact('peer-bob', 'Bob'));

    controller.add(_message('peer-bob', 'ATTACKER CLAIMED NAME', text: 'x' * 200));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final shown = notifications.shownThoughts.single;
    expect(shown.title, 'Bob shared a thought');
    expect(shown.body, 'x' * 140);
  });

  test('shows post notifications for active direct contacts', () async {
    contacts.addTestContact(_contact('peer-bob', 'Bob'));

    controller.add(_message('peer-bob', 'Bob'));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(notifications.shownGeneric, isEmpty);
    final shown = notifications.shownThoughts.single;
    expect(shown.title, 'Bob shared a thought');
    expect(shown.body, 'A post from Bob');
    expect(shown.payload, 'post:post-peer-bob');
    expect((await posts.loadFeed()), hasLength(1));
  });

  test('posts no notification while the app is in the foreground', () async {
    contacts.addTestContact(_contact('peer-bob', 'Bob'));
    foreground = true;
    final emitted = listener.incomingPostStream.first;

    controller.add(_message('peer-bob', 'Bob'));

    expect((await emitted).id, 'post-peer-bob');
    expect(notifications.shownThoughts, isEmpty);
    expect(notifications.shownGeneric, isEmpty);
  });

  test('a newer thought retires only that friend\'s older card', () async {
    contacts.addTestContact(_contact('peer-bob', 'Bob'));
    contacts.addTestContact(_contact('peer-cat', 'Cat'));

    controller.add(_message('peer-cat', 'Cat', postId: 'cat-1'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    controller.add(_message('peer-bob', 'Bob', postId: 'bob-1'));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    notifications.cancelled.clear();
    foreground = true;
    controller.add(_message('peer-bob', 'Bob', postId: 'bob-2'));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(notifications.cancelled, ['post:bob-1']);
    expect(notifications.shownThoughts.map((n) => n.payload), [
      'post:cat-1',
      'post:bob-1',
    ]);
  });

  test('a media-only thought names its media in the body', () async {
    contacts.addTestContact(_contact('peer-bob', 'Bob'));

    controller.add(
      _message('peer-bob', 'Bob', postId: 'v', text: '', mediaKind: 'voice'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    controller.add(
      _message('peer-bob', 'Bob', postId: 'p', text: '', mediaKind: 'image'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(notifications.shownThoughts.map((n) => n.body), [
      'Voice message',
      'Photo',
    ]);
  });

  test(
    'suppresses notifications for archived senders but still persists',
    () async {
      contacts.addTestContact(_contact('peer-bob', 'Bob', archived: true));

      controller.add(_message('peer-bob', 'Bob'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(notifications.shownThoughts, isEmpty);
      expect((await posts.loadFeed()), hasLength(1));
    },
  );
}
