import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/posts/application/handle_incoming_post_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_create_envelope.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_origin_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

import '../../../shared/fakes/fake_media_file_manager.dart';
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

/// A friend's thought with one photo, written at [createdAt].
PostCreateEnvelope _thought(String id, String author, String createdAt) =>
    PostCreateEnvelope.fromPost(
      PostModel(
        id: id,
        eventId: 'evt-$id',
        senderPeerId: author,
        authorPeerId: author,
        authorUsername: author,
        text: 'Thought $id',
        audience: const PostAudience(kind: PostAudienceKind.allFriends),
        createdAt: createdAt,
        visibleAt: createdAt,
        expiresAt: '2026-03-18T10:15:30.000Z',
        mediaKind: 'image',
        media: [
          PostMediaAttachmentModel(
            mediaId: 'media-$id',
            postId: id,
            blobId: 'blob-$id',
            kind: 'image',
            mime: 'image/jpeg',
            sizeBytes: 10,
            createdAt: createdAt,
          ),
        ],
      ),
    );

void main() {
  late InMemoryContactRepository contacts;
  late InMemoryPostRepository posts;
  late PostCreateEnvelope envelope;

  setUp(() {
    contacts = InMemoryContactRepository();
    posts = InMemoryPostRepository();
    const createdAt = '2026-03-15T10:15:30.000Z';
    const expiresAt = '2026-03-18T10:15:30.000Z';
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
      nowProvider: () => DateTime.parse('2026-03-15T13:00:00Z'),
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
      nowProvider: () => DateTime.parse('2026-03-15T13:00:00Z'),
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
      nowProvider: () => DateTime.parse('2026-03-15T13:00:00Z'),
      contactRepo: contacts,
    );
    final second = await handleIncomingPost(
      message: _messageFromEnvelope(envelope),
      postRepo: posts,
      nowProvider: () => DateTime.parse('2026-03-15T13:00:00Z'),
      contactRepo: contacts,
    );

    expect(first.$1, HandleIncomingPostResult.postCreated);
    expect(second.$1, HandleIncomingPostResult.duplicate);
    expect((await posts.loadFeed()), hasLength(1));
  });

  group('one live thought per friend', () {
    final now = DateTime.parse('2026-03-15T13:00:00Z');
    late FakeMediaFileManager media;
    late List<String> changes;

    setUp(() {
      media = FakeMediaFileManager();
      changes = <String>[];
      posts.postChanges.listen(changes.add);
      contacts.addTestContact(_contact('peer-bob', 'Bob'));
      contacts.addTestContact(_contact('peer-cat', 'Cat'));
    });

    Future<(HandleIncomingPostResult, PostModel?)> receive(
      PostCreateEnvelope thought,
    ) => handleIncomingPost(
      message: _messageFromEnvelope(thought),
      postRepo: posts,
      contactRepo: contacts,
      mediaFileManager: media,
      nowProvider: () => now,
    );

    test(
      "a friend's newer thought replaces the older one stored here",
      () async {
        await receive(
          _thought('bob-1', 'peer-bob', '2026-03-15T09:00:00.000Z'),
        );
        await receive(
          _thought('cat-1', 'peer-cat', '2026-03-15T09:30:00.000Z'),
        );
        changes.clear();

        final (result, _) = await receive(
          _thought('bob-2', 'peer-bob', '2026-03-15T10:00:00.000Z'),
        );

        expect(result, HandleIncomingPostResult.postCreated);
        expect(
          (await posts.loadFeed()).map((post) => post.id),
          unorderedEquals(['bob-2', 'cat-1']),
        );
        expect(await posts.loadPostMediaAttachments('bob-1'), isEmpty);
        expect(media.deletedPostIds, ['bob-1']);
        expect(changes, contains('bob-1'));
      },
    );

    test('a late older thought is not stored beside the newer one', () async {
      await receive(_thought('bob-2', 'peer-bob', '2026-03-15T10:00:00.000Z'));

      final (result, _) = await receive(
        _thought('bob-1', 'peer-bob', '2026-03-15T09:00:00.000Z'),
      );

      expect(result, HandleIncomingPostResult.superseded);
      expect((await posts.loadFeed()).map((post) => post.id), ['bob-2']);
      expect(await posts.loadPostMediaAttachments('bob-1'), isEmpty);
      expect(media.deletedPostIds, isEmpty);
    });
  });

  test(
    'merges a later direct author copy into an existing reposted copy without losing receiver pass attribution',
    () async {
      contacts.addTestContact(_contact('peer-bob', 'Bob'));
      await posts.savePost(
        PostModel(
          id: 'post-1',
          eventId: 'evt-pass-1',
          senderPeerId: 'peer-james',
          authorPeerId: 'peer-bob',
          authorUsername: 'Bob',
          text: 'Hello from Bob',
          audience: const PostAudience(kind: PostAudienceKind.allFriends),
          createdAt: envelope.createdAt,
          visibleAt: '2026-03-15T11:15:00.000Z',
          expiresAt: envelope.expiresAt,
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

      final (result, post) = await handleIncomingPost(
        message: _messageFromEnvelope(envelope),
        postRepo: posts,
        nowProvider: () => DateTime.parse('2026-03-15T13:00:00Z'),
        contactRepo: contacts,
      );

      final mergedPost = await posts.getPost('post-1');
      final mergedOrigin = await posts.getPostOrigin('post-1');
      expect(result, HandleIncomingPostResult.duplicate);
      expect(post, isNotNull);
      expect((await posts.loadFeed()), hasLength(1));
      expect(mergedPost, isNotNull);
      expect(mergedPost!.senderPeerId, 'peer-bob');
      expect(mergedPost.authorPeerId, 'peer-bob');
      expect(mergedPost.authorUsername, 'Bob');
      expect(mergedPost.visibleAt, '2026-03-15T11:15:00.000Z');
      expect(mergedPost.passedByUsername, 'James');
      expect(mergedOrigin, isNotNull);
      expect(mergedOrigin!.originKind, PostOriginKind.direct);
      expect(mergedOrigin.passerUsername, 'James');
      expect(mergedOrigin.passCreatedAt, '2026-03-15T11:15:00.000Z');
    },
  );

  test(
    'rejects post_create when snapshot author does not match sender',
    () async {
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
        nowProvider: () => DateTime.parse('2026-03-15T13:00:00Z'),
        contactRepo: contacts,
      );

      expect(result, HandleIncomingPostResult.notPostCreate);
      expect(post, isNull);
      expect(await posts.postExists('post-1'), isFalse);
    },
  );

  test(
    'rejects post_create when snapshot post_id mismatches payload post_id',
    () async {
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
        nowProvider: () => DateTime.parse('2026-03-15T13:00:00Z'),
        contactRepo: contacts,
      );

      expect(result, HandleIncomingPostResult.notPostCreate);
      expect(post, isNull);
      expect(await posts.postExists('post-1'), isFalse);
    },
  );

  test('clamps a future creation time to the receiving clock', () async {
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
      nowProvider: () => DateTime.parse('2026-03-15T13:00:00Z'),
      contactRepo: contacts,
    );

    expect(result, HandleIncomingPostResult.postCreated);
    expect(post!.createdAt, '2026-03-15T13:00:00.000Z');
    expect(post.expiresAt, '2026-03-16T13:00:00.000Z');
    expect(await posts.postExists('post-1'), isTrue);
  });

  test(
    'sanitizes dangerous bidi controls in incoming post text and author username',
    () async {
      contacts.addTestContact(_contact('peer-bob', 'Bob'));
      final sanitizedEnvelope = PostCreateEnvelope.fromPost(
        PostModel(
          id: 'post-2',
          eventId: 'evt-2',
          senderPeerId: 'peer-bob',
          authorPeerId: 'peer-bob',
          authorUsername: 'A\u202Eli\u200Fce',
          text: '  Hi\u202E there\u200F  ',
          audience: const PostAudience(kind: PostAudienceKind.allFriends),
          createdAt: '2026-03-15T12:00:00.000Z',
          visibleAt: '2026-03-15T12:00:00.000Z',
          expiresAt: '2026-03-18T12:00:00.000Z',
        ),
      );

      final (result, post) = await handleIncomingPost(
        message: _messageFromEnvelope(sanitizedEnvelope),
        postRepo: posts,
        nowProvider: () => DateTime.parse('2026-03-15T13:00:00Z'),
        contactRepo: contacts,
      );

      expect(result, HandleIncomingPostResult.postCreated);
      expect(post, isNotNull);
      expect(post!.authorUsername, 'Ali\u200Fce');
      expect(post.text, '  Hi there\u200F  ');

      final stored = await posts.getPost('post-2');
      expect(stored, isNotNull);
      expect(stored!.authorUsername, 'Ali\u200Fce');
      expect(stored.text, '  Hi there\u200F  ');
    },
  );
}
