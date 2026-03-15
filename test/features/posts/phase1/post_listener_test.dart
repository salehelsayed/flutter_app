import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/application/post_listener.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_create_envelope.dart';
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

ChatMessage _message(String senderPeerId, String authorUsername) {
  final createdAt = DateTime.now().toUtc().toIso8601String();
  final expiresAt = DateTime.now()
      .toUtc()
      .add(const Duration(days: 3))
      .toIso8601String();
  final envelope = PostCreateEnvelope.fromPost(
    PostModel(
      id: 'post-$senderPeerId',
      eventId: 'evt-$senderPeerId',
      senderPeerId: senderPeerId,
      authorPeerId: senderPeerId,
      authorUsername: authorUsername,
      text: 'A post from $authorUsername',
      audience: const PostAudience(kind: PostAudienceKind.allFriends),
      createdAt: createdAt,
      visibleAt: createdAt,
      expiresAt: expiresAt,
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

void main() {
  late StreamController<ChatMessage> controller;
  late InMemoryContactRepository contacts;
  late InMemoryPostRepository posts;
  late FakeNotificationService notifications;
  late PostListener listener;

  setUp(() {
    controller = StreamController<ChatMessage>.broadcast();
    contacts = InMemoryContactRepository();
    posts = InMemoryPostRepository();
    notifications = FakeNotificationService();
    listener = PostListener(
      postCreateStream: controller.stream,
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

  test('shows post notifications for active direct contacts', () async {
    contacts.addTestContact(_contact('peer-bob', 'Bob'));

    controller.add(_message('peer-bob', 'Bob'));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(notifications.shownGeneric, hasLength(1));
    expect(notifications.shownGeneric.single.payload, 'post:post-peer-bob');
    expect((await posts.loadFeed()), hasLength(1));
  });

  test(
    'suppresses notifications for archived senders but still persists',
    () async {
      contacts.addTestContact(_contact('peer-bob', 'Bob', archived: true));

      controller.add(_message('peer-bob', 'Bob'));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(notifications.shownGeneric, isEmpty);
      expect((await posts.loadFeed()), hasLength(1));
    },
  );
}
