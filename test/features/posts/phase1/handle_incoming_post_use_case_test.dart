import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/application/handle_incoming_post_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_create_envelope.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

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

ChatMessage _messageFromEnvelope(PostCreateEnvelope envelope) {
  return _messageFromJson(
    envelope.toJson(),
    transportSender: envelope.senderPeerId,
    timestamp: envelope.createdAt,
  );
}

ChatMessage _messageFromJson(
  String json, {
  required String transportSender,
  String timestamp = '2026-03-15T10:15:30.000Z',
}) {
  return ChatMessage(
    from: transportSender,
    to: 'peer-self',
    content: json,
    timestamp: timestamp,
    isIncoming: true,
  );
}

void main() {
  late InMemoryContactRepository contacts;
  late InMemoryPostRepository posts;
  late PostCreateEnvelope envelope;

  setUp(() {
    contacts = InMemoryContactRepository();
    posts = InMemoryPostRepository();
    final createdAt = DateTime.now().toUtc().toIso8601String();
    final expiresAt = DateTime.now()
        .toUtc()
        .add(const Duration(days: 3))
        .toIso8601String();
    envelope = PostCreateEnvelope.fromPost(
      PostModel(
        id: 'post-1',
        eventId: 'evt-1',
        senderPeerId: 'peer-bob',
        authorPeerId: 'peer-bob',
        authorUsername: 'Bob',
        text: 'Hello from Bob',
        audience: const PostAudience(kind: PostAudienceKind.allFriends),
        createdAt: createdAt,
        visibleAt: createdAt,
        expiresAt: expiresAt,
      ),
    );
  });

  tearDown(() {
    posts.dispose();
  });

  test('rejects unknown senders before persistence', () async {
    final (result, post) = await handleIncomingPost(
      message: _messageFromEnvelope(envelope),
      postRepo: posts,
      contactRepo: contacts,
    );

    expect(result, HandleIncomingPostResult.unknownSender);
    expect(post, isNull);
    expect(await posts.postExists('post-1'), isFalse);
  });

  test('rejects blocked senders before persistence', () async {
    contacts.addTestContact(_contact('peer-bob', 'Bob', blocked: true));

    final (result, post) = await handleIncomingPost(
      message: _messageFromEnvelope(envelope),
      postRepo: posts,
      contactRepo: contacts,
    );

    expect(result, HandleIncomingPostResult.blockedSender);
    expect(post, isNull);
    expect(await posts.postExists('post-1'), isFalse);
  });

  test('dedupes duplicate post_create deliveries by post id', () async {
    contacts.addTestContact(_contact('peer-bob', 'Bob'));

    final first = await handleIncomingPost(
      message: _messageFromEnvelope(envelope),
      postRepo: posts,
      contactRepo: contacts,
    );
    final second = await handleIncomingPost(
      message: _messageFromEnvelope(envelope),
      postRepo: posts,
      contactRepo: contacts,
    );

    expect(first.$1, HandleIncomingPostResult.postCreated);
    expect(second.$1, HandleIncomingPostResult.duplicate);
    expect((await posts.loadFeed()), hasLength(1));
  });

  test('rejects post_create when snapshot author does not match sender', () async {
    contacts.addTestContact(_contact('peer-bob', 'Bob'));
    final json = jsonDecode(envelope.toJson()) as Map<String, dynamic>;
    final payload = json['payload'] as Map<String, dynamic>;
    final snapshot = payload['snapshot'] as Map<String, dynamic>;
    snapshot['author_peer_id'] = 'peer-spoofed';

    final (result, post) = await handleIncomingPost(
      message: _messageFromJson(
        jsonEncode(json),
        transportSender: envelope.senderPeerId,
      ),
      postRepo: posts,
      contactRepo: contacts,
    );

    expect(result, HandleIncomingPostResult.notPostCreate);
    expect(post, isNull);
    expect(await posts.postExists('post-1'), isFalse);
  });

  test('rejects post_create when snapshot post_id mismatches payload post_id', () async {
    contacts.addTestContact(_contact('peer-bob', 'Bob'));
    final json = jsonDecode(envelope.toJson()) as Map<String, dynamic>;
    final payload = json['payload'] as Map<String, dynamic>;
    final snapshot = payload['snapshot'] as Map<String, dynamic>;
    snapshot['post_id'] = 'post-other';

    final (result, post) = await handleIncomingPost(
      message: _messageFromJson(
        jsonEncode(json),
        transportSender: envelope.senderPeerId,
      ),
      postRepo: posts,
      contactRepo: contacts,
    );

    expect(result, HandleIncomingPostResult.notPostCreate);
    expect(post, isNull);
    expect(await posts.postExists('post-1'), isFalse);
  });

  test('rejects post_create when created_at is beyond allowed future skew', () async {
    contacts.addTestContact(_contact('peer-bob', 'Bob'));
    final futureCreatedAt = DateTime.now()
        .toUtc()
        .add(const Duration(minutes: 6))
        .toIso8601String();
    final json = jsonDecode(envelope.toJson()) as Map<String, dynamic>;
    json['created_at'] = futureCreatedAt;

    final (result, post) = await handleIncomingPost(
      message: _messageFromJson(
        jsonEncode(json),
        transportSender: envelope.senderPeerId,
        timestamp: futureCreatedAt,
      ),
      postRepo: posts,
      contactRepo: contacts,
    );

    expect(result, HandleIncomingPostResult.notPostCreate);
    expect(post, isNull);
    expect(await posts.postExists('post-1'), isFalse);
  });
}
