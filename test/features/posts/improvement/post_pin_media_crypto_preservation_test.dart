import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/posts/application/handle_incoming_post_pins_use_case.dart';
import 'package:flutter_app/features/posts/application/handle_incoming_post_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_pin_envelope.dart';
import 'package:flutter_app/features/posts/domain/models/post_pin_state_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';

const _createdAt = '2026-03-15T10:15:30.000Z';
const _pinAt = '2026-03-16T08:00:00.000Z';

void main() {
  late InMemoryContactRepository contacts;
  late InMemoryPostRepository posts;

  setUp(() {
    contacts = InMemoryContactRepository();
    posts = InMemoryPostRepository();
    contacts.addTestContact(
      ContactModel(
        peerId: 'peer-bob',
        publicKey: 'pk-peer-bob',
        rendezvous: '/dns4/example.invalid/tcp/443',
        username: 'Bob',
        signature: 'sig-peer-bob',
        scannedAt: '2026-03-15T10:00:00.000Z',
      ),
    );
  });

  tearDown(() {
    posts.dispose();
  });

  Future<void> seedKeyedPost() async {
    await posts.savePost(_parentPost());
    await posts.savePostMediaAttachment(_keyedRow());
  }

  test('pin update over keyed encrypted rows never drops key material',
      () async {
    await seedKeyedPost();

    final (result, _) = await handleIncomingPostPinUpdate(
      message: _pinMessage(_pinUpdateJson()),
      postRepo: posts,
      contactRepo: contacts,
    );

    expect(result, HandleIncomingPostPinUpdateResult.pinApplied);

    final stored = (await posts.loadPostMediaAttachments('post-1')).single;
    expect(stored.encryptionKeyBase64, 'row-key-b64');
    expect(stored.encryptionNonce, 'row-nonce-b64');
    expect(
      stored.encryptionScheme,
      kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
    );
    expect(stored.contentHash, 'e' * 64);
    expect(stored.isEncrypted, isTrue);
    expect(stored.blobId, 'blob-enc-1');
    expect(stored.localPath, 'post_media/post-1/blob-enc-1.jpg');
    expect(stored.downloadStatus, 'done');
  });

  test('edit-pinned snapshot merge over keyed rows preserves crypto fields',
      () async {
    await seedKeyedPost();

    final (result, _) = await handleIncomingPostPinUpdate(
      message: _pinMessage(_pinUpdateJson(text: 'Edited while pinned')),
      postRepo: posts,
      contactRepo: contacts,
    );

    expect(result, HandleIncomingPostPinUpdateResult.pinApplied);

    final post = await posts.getPost('post-1');
    expect(post!.text, 'Edited while pinned');

    final stored = (await posts.loadPostMediaAttachments('post-1')).single;
    expect(stored.encryptionKeyBase64, 'row-key-b64');
    expect(stored.encryptionNonce, 'row-nonce-b64');
    expect(
      stored.encryptionScheme,
      kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
    );
    expect(stored.contentHash, 'e' * 64);
    expect(stored.isEncrypted, isTrue);
  });

  test('post_create-with-keys then staged-pin replay: joined keys survive',
      () async {
    // Pin arrives before the parent post → staged.
    final (stagedResult, _) = await handleIncomingPostPinUpdate(
      message: _pinMessage(_pinUpdateJson()),
      postRepo: posts,
      contactRepo: contacts,
    );
    expect(
      stagedResult,
      HandleIncomingPostPinUpdateResult.stagedPendingParent,
    );

    // The keyed v2 post_create lands; reconcile replays the staged pin in
    // the same tick (reconcile_pending_post_child_events_use_case).
    final (createResult, _) = await handleIncomingPost(
      message: _encryptedMediaPostMessage(),
      postRepo: posts,
      contactRepo: contacts,
      bridge: PassthroughCryptoBridge(),
      ownMlKemSecretKey: 'own-sk',
    );
    expect(createResult, HandleIncomingPostResult.postCreated);

    final pinState = await posts.getPostPinState('post-1');
    expect(pinState, isNotNull);
    expect(pinState!.state, 'active');

    final stored = (await posts.loadPostMediaAttachments('post-1')).single;
    expect(stored.encryptionKeyBase64, 'wire-key-b64');
    expect(stored.encryptionNonce, 'wire-nonce-b64');
    expect(
      stored.encryptionScheme,
      kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
    );
    expect(stored.contentHash, 'f' * 64);
    expect(stored.isEncrypted, isTrue);
  });

  test('pin snapshot media carries no key material (v1 envelope stays crypto-free)',
      () {
    final wire = _pinUpdateJson();

    expect(wire, isNot(contains('row-key-b64')));
    expect(wire, isNot(contains('row-nonce-b64')));
    expect(wire, isNot(contains('media_keys')));

    final decoded = jsonDecode(wire) as Map<String, dynamic>;
    final snapshot = (decoded['payload'] as Map<String, dynamic>)['snapshot']
        as Map<String, dynamic>;
    final media =
        (snapshot['media'] as List<dynamic>).cast<Map<String, dynamic>>();
    for (final entry in media) {
      expect(entry.keys, isNot(contains('encryption_key_base64')));
      expect(entry.keys, isNot(contains('encryption_nonce')));
      expect(entry.keys, isNot(contains('encryption_scheme')));
      expect(entry.keys, isNot(contains('content_hash')));
      expect(entry.keys, isNot(contains('is_encrypted')));
    }
  });
}

PostModel _parentPost() {
  return PostModel(
    id: 'post-1',
    eventId: 'evt-post-1',
    senderPeerId: 'peer-bob',
    authorPeerId: 'peer-bob',
    authorUsername: 'Bob',
    text: 'Photo post',
    mediaKind: 'image',
    audience: PostAudience.allFriends(),
    createdAt: _createdAt,
    visibleAt: _createdAt,
    expiresAt: '2026-03-18T10:15:30.000Z',
    isIncoming: true,
    deliveryStatus: 'delivered',
  );
}

PostMediaAttachmentModel _keyedRow() {
  return PostMediaAttachmentModel(
    mediaId: 'media-1',
    postId: 'post-1',
    blobId: 'blob-enc-1',
    kind: 'image',
    mime: 'image/jpeg',
    sizeBytes: 248120,
    localPath: 'post_media/post-1/blob-enc-1.jpg',
    downloadStatus: 'done',
    createdAt: _createdAt,
    encryptionKeyBase64: 'row-key-b64',
    encryptionNonce: 'row-nonce-b64',
    encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
    contentHash: 'e' * 64,
    isEncrypted: true,
  );
}

/// What the author's device fans out on pin/edit-pinned: a v1-plaintext-only
/// envelope whose media snapshot is the crypto-free renderable JSON.
String _pinUpdateJson({String text = 'Photo post'}) {
  return PostPinUpdateEnvelope.buildJson(
    pinState: PostPinStateModel(
      postId: 'post-1',
      eventId: 'evt-pin-1',
      pinEventId: 'pin-1',
      senderPeerId: 'peer-bob',
      state: 'active',
      effectiveAt: _pinAt,
      pinnedAt: _pinAt,
      createdAt: _pinAt,
    ),
    post: _parentPost().copyWith(text: text, keepAvailable: true),
    media: <PostMediaAttachmentModel>[_keyedRow()],
  );
}

ChatMessage _pinMessage(String content) {
  return ChatMessage(
    from: 'peer-bob',
    to: 'peer-self',
    content: content,
    timestamp: _pinAt,
    isIncoming: true,
  );
}

ChatMessage _encryptedMediaPostMessage() {
  final innerPayload = <String, Object?>{
    'post_id': 'post-1',
    'snapshot': <String, Object?>{
      'post_id': 'post-1',
      'author_peer_id': 'peer-bob',
      'author_username': 'Bob',
      'post_created_at': _createdAt,
      'audience': <String, Object?>{
        'kind': 'all_friends',
        'radius_m': null,
        'scope_label': null,
      },
      'text': 'Photo post',
      'media_kind': 'image',
      'media': <Object?>[
        <String, Object?>{
          'media_id': 'media-1',
          'blob_id': 'blob-enc-1',
          'kind': 'image',
          'mime': 'image/jpeg',
          'size_bytes': 248120,
        },
      ],
      'keep_available': false,
      'expires_at': '2026-03-18T10:15:30.000Z',
    },
    'media_keys': <String, Object?>{
      'media-1': <String, Object?>{
        'key_base64': 'wire-key-b64',
        'nonce': 'wire-nonce-b64',
        'blob_id': 'blob-enc-1',
        'scheme': kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        'content_hash': 'f' * 64,
      },
    },
  };
  return ChatMessage(
    from: 'peer-bob',
    to: 'peer-self',
    content: jsonEncode(<String, Object?>{
      'type': 'post_create',
      'version': '2',
      'event_id': 'evt-post-1',
      'created_at': _createdAt,
      'sender_peer_id': 'peer-bob',
      'encrypted': <String, Object?>{
        'kem': 'fake-kem',
        'ciphertext': jsonEncode(innerPayload),
        'nonce': 'fake-nonce',
      },
    }),
    timestamp: _createdAt,
    isIncoming: true,
  );
}
