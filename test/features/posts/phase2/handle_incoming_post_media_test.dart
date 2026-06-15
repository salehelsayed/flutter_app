import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/posts/application/handle_incoming_passed_post_use_case.dart'
    hide HydratePostMediaFn;
import 'package:flutter_app/features/posts/application/handle_incoming_post_use_case.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';

void main() {
  late InMemoryContactRepository contacts;
  late InMemoryPostRepository posts;

  setUp(() {
    contacts = InMemoryContactRepository();
    posts = InMemoryPostRepository();
    contacts.addTestContact(_contact('peer-bob', 'Bob'));
    contacts.addTestContact(_contact('peer-carol', 'Carol'));
  });

  tearDown(() {
    posts.dispose();
  });

  test(
    'hydrates incoming post media from pending to local-path-ready during ingest',
    () async {
      final hydratedBlobIds = <String>[];

      final (result, post) = await handleIncomingPost(
        message: _mediaPostMessage(),
        postRepo: posts,
        contactRepo: contacts,
        hydratePostMediaFn: ({required attachment, required postId}) async {
          hydratedBlobIds.add(attachment.blobId);
          return attachment.copyWith(
            localPath: 'post_media/$postId/${attachment.blobId}.jpg',
            downloadStatus: 'done',
          );
        },
      );

      expect(result, HandleIncomingPostResult.postCreated);
      expect(post, isNotNull);
      expect(hydratedBlobIds, ['blob-1']);

      final attachments = await posts.loadPostMediaAttachments('post-1');
      expect(attachments, hasLength(1));
      expect(attachments.single.downloadStatus, 'done');
      expect(attachments.single.localPath, 'post_media/post-1/blob-1.jpg');
    },
  );

  test(
    'incoming post_create with media_keys persists attachments with key/nonce/scheme/hash and isEncrypted=true',
    () async {
      final (result, _) = await handleIncomingPost(
        message: _encryptedMediaPostMessage(mediaKeys: _wireMediaKeys()),
        postRepo: posts,
        contactRepo: contacts,
        bridge: PassthroughCryptoBridge(),
        ownMlKemSecretKey: 'own-sk',
        hydratePostMediaFn: ({required attachment, required postId}) async {
          return attachment;
        },
      );

      expect(result, HandleIncomingPostResult.postCreated);

      final stored = (await posts.loadPostMediaAttachments('post-1')).single;
      expect(stored.encryptionKeyBase64, 'wire-key-b64');
      expect(stored.encryptionNonce, 'wire-nonce-b64');
      expect(
        stored.encryptionScheme,
        kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
      );
      expect(stored.contentHash, 'f' * 64);
      expect(stored.isEncrypted, isTrue);
    },
  );

  test(
    'incoming post_create without media_keys persists plaintext attachments exactly as today',
    () async {
      final (result, _) = await handleIncomingPost(
        message: _mediaPostMessage(),
        postRepo: posts,
        contactRepo: contacts,
      );

      expect(result, HandleIncomingPostResult.postCreated);

      final stored = (await posts.loadPostMediaAttachments('post-1')).single;
      expect(stored.encryptionKeyBase64, isNull);
      expect(stored.encryptionNonce, isNull);
      expect(stored.encryptionScheme, isNull);
      expect(stored.contentHash, isNull);
      expect(stored.isEncrypted, isFalse);
    },
  );

  test(
    'dedup preserve-existing keeps the stored row crypto metadata when a duplicate copy arrives',
    () async {
      final (first, _) = await handleIncomingPost(
        message: _encryptedMediaPostMessage(mediaKeys: _wireMediaKeys()),
        postRepo: posts,
        contactRepo: contacts,
        bridge: PassthroughCryptoBridge(),
        ownMlKemSecretKey: 'own-sk',
      );
      expect(first, HandleIncomingPostResult.postCreated);

      final (second, _) = await handleIncomingPost(
        message: _encryptedMediaPostMessage(mediaKeys: _wireMediaKeys()),
        postRepo: posts,
        contactRepo: contacts,
        bridge: PassthroughCryptoBridge(),
        ownMlKemSecretKey: 'own-sk',
      );
      expect(second, HandleIncomingPostResult.duplicate);

      final stored = (await posts.loadPostMediaAttachments('post-1')).single;
      expect(stored.encryptionKeyBase64, 'wire-key-b64');
      expect(stored.encryptionNonce, 'wire-nonce-b64');
      expect(stored.isEncrypted, isTrue);
    },
  );

  test(
    'pass-then-create ordering: keyed rows survive the keyless create merge',
    () async {
      final (passResult, _) = await handleIncomingPassedPost(
        message: _passMessageWithKeys(),
        postRepo: posts,
        contactRepo: contacts,
      );
      expect(passResult, HandleIncomingPassedPostResult.passAccepted);

      final keyed = (await posts.loadPostMediaAttachments('post-1')).single;
      expect(keyed.encryptionKeyBase64, 'pass-key-b64');
      expect(keyed.isEncrypted, isTrue);

      // The author's own keyless v1 copy arrives later (legacy sender).
      final (createResult, _) = await handleIncomingPost(
        message: _mediaPostMessage(blobId: 'blob-pass-1'),
        postRepo: posts,
        contactRepo: contacts,
      );
      expect(createResult, HandleIncomingPostResult.duplicate);

      final stored = (await posts.loadPostMediaAttachments('post-1')).single;
      expect(stored.encryptionKeyBase64, 'pass-key-b64');
      expect(stored.encryptionNonce, 'pass-nonce-b64');
      expect(stored.isEncrypted, isTrue);
    },
  );

  test(
    'create-then-pass ordering: key-less rows are not repaired by a later keyed pass',
    () async {
      final (createResult, _) = await handleIncomingPost(
        message: _mediaPostMessage(),
        postRepo: posts,
        contactRepo: contacts,
      );
      expect(createResult, HandleIncomingPostResult.postCreated);

      final (passResult, _) = await handleIncomingPassedPost(
        message: _passMessageWithKeys(),
        postRepo: posts,
        contactRepo: contacts,
      );
      expect(passResult, HandleIncomingPassedPostResult.passAccepted);

      // Existing-post early return: media rows stay keyless (Non-goal 3).
      final stored = (await posts.loadPostMediaAttachments('post-1')).single;
      expect(stored.encryptionKeyBase64, isNull);
      expect(stored.blobId, 'blob-1');
      expect(stored.isEncrypted, isFalse);
    },
  );
}

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

const _createdAt = '2026-03-15T10:15:30.000Z';

Map<String, Object?> _mediaPostPayload({String blobId = 'blob-1'}) {
  return <String, Object?>{
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
          'blob_id': blobId,
          'kind': 'image',
          'mime': 'image/jpeg',
          'size_bytes': 248120,
          'width': 1440,
          'height': 1080,
          'duration_ms': null,
          'waveform': null,
          'thumbnail_blob_id': null,
        },
      ],
      'keep_available': false,
      'expires_at': '2026-03-18T10:15:30.000Z',
    },
  };
}

Map<String, Object?> _wireMediaKeys() {
  return <String, Object?>{
    'media-1': <String, Object?>{
      'key_base64': 'wire-key-b64',
      'nonce': 'wire-nonce-b64',
      'blob_id': 'blob-1',
      'scheme': kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
      'content_hash': 'f' * 64,
    },
  };
}

ChatMessage _mediaPostMessage({String blobId = 'blob-1'}) {
  return ChatMessage(
    from: 'peer-bob',
    to: 'peer-self',
    content: jsonEncode(<String, Object?>{
      'type': 'post_create',
      'version': '1',
      'event_id': 'evt-post-1',
      'created_at': _createdAt,
      'sender_peer_id': 'peer-bob',
      'payload': _mediaPostPayload(blobId: blobId),
    }),
    timestamp: _createdAt,
    isIncoming: true,
  );
}

/// A v2 post_create whose ML-KEM inner payload carries `media_keys`.
/// [PassthroughCryptoBridge] returns the `ciphertext` field verbatim as the
/// decrypted plaintext, so the inner payload is embedded directly.
ChatMessage _encryptedMediaPostMessage({
  required Map<String, Object?> mediaKeys,
}) {
  final innerPayload = _mediaPostPayload()..['media_keys'] = mediaKeys;
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

ChatMessage _passMessageWithKeys() {
  return ChatMessage(
    from: 'peer-carol',
    to: 'peer-self',
    content: jsonEncode(<String, Object?>{
      'type': 'post_pass',
      'version': '1',
      'event_id': 'evt-pass-1',
      'created_at': _createdAt,
      'sender_peer_id': 'peer-carol',
      'payload': <String, Object?>{
        'pass_id': 'pass-1',
        'post_id': 'post-1',
        'passed_at': _createdAt,
        'passer_peer_id': 'peer-carol',
        'passer_username': 'Carol',
        'media_keys': <String, Object?>{
          'media-1': <String, Object?>{
            'key_base64': 'pass-key-b64',
            'nonce': 'pass-nonce-b64',
            'blob_id': 'blob-pass-1',
          },
        },
        'original_snapshot': <String, Object?>{
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
              'blob_id': 'blob-pass-1',
              'kind': 'image',
              'mime': 'image/jpeg',
              'size_bytes': 248120,
            },
          ],
          'keep_available': false,
          'expires_at': '2026-03-18T10:15:30.000Z',
        },
      },
    }),
    timestamp: _createdAt,
    isIncoming: true,
  );
}
