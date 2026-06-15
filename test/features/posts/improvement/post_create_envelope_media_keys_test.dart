import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_create_envelope.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';
import 'package:flutter_app/features/posts/domain/models/post_pass_envelope.dart';

import '../../../core/bridge/fake_bridge.dart';

void main() {
  const createdAt = '2026-06-12T10:00:00.000Z';

  PostMediaAttachmentModel attachment() {
    return PostMediaAttachmentModel(
      mediaId: 'media-1',
      postId: 'post-1',
      blobId: 'blob-1',
      kind: 'image',
      mime: 'image/jpeg',
      sizeBytes: 2048,
      createdAt: createdAt,
    );
  }

  PostMediaCryptoEntry cryptoEntry() {
    return PostMediaCryptoEntry(
      keyBase64: 'key-b64',
      nonce: 'nonce-b64',
      blobId: 'blob-1',
      scheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
      contentHash: 'f' * 64,
    );
  }

  PostCreateEnvelope envelope({
    Map<String, PostMediaCryptoEntry>? mediaKeys,
  }) {
    return PostCreateEnvelope(
      eventId: 'evt-1',
      createdAt: createdAt,
      senderPeerId: 'peer-alice',
      postId: 'post-1',
      authorPeerId: 'peer-alice',
      authorUsername: 'Alice',
      text: 'hello',
      mediaKind: 'image',
      media: <PostMediaAttachmentModel>[attachment()],
      audience: PostAudience.allFriends(),
      expiresAt: '2026-06-15T10:00:00.000Z',
      keepAvailable: false,
      mediaKeys: mediaKeys,
    );
  }

  test(
    'fromEncryptedJson parses media_keys from the decrypted inner payload, keyed by mediaId, into PostMediaCryptoEntry',
    () async {
      final inner = envelope(
        mediaKeys: <String, PostMediaCryptoEntry>{'media-1': cryptoEntry()},
      ).toInnerJson(recipientPeerIds: const <String>['peer-bob']);
      final wire = PostCreateEnvelope.buildEncryptedEnvelope(
        eventId: 'evt-1',
        createdAt: createdAt,
        senderPeerId: 'peer-alice',
        kem: 'fake-kem',
        ciphertext: inner,
        nonce: 'fake-nonce',
      );

      final parsed = await PostCreateEnvelope.fromEncryptedJson(
        jsonString: wire,
        bridge: PassthroughCryptoBridge(),
        ownMlKemSecretKey: 'own-sk',
      );

      expect(parsed, isNotNull);
      expect(parsed!.mediaKeys, isNotNull);
      final entry = parsed.mediaKeys!['media-1'];
      expect(entry, isNotNull);
      expect(entry!.keyBase64, 'key-b64');
      expect(entry.nonce, 'nonce-b64');
      expect(entry.blobId, 'blob-1');
      expect(entry.scheme, kMediaAttachmentEncryptionSchemeBlobAesGcmV1);
      expect(entry.contentHash, 'f' * 64);
    },
  );

  test('fromEncryptedJson without media_keys parses with mediaKeys == null',
      () async {
    final inner = envelope().toInnerJson();
    final wire = PostCreateEnvelope.buildEncryptedEnvelope(
      eventId: 'evt-1',
      createdAt: createdAt,
      senderPeerId: 'peer-alice',
      kem: 'fake-kem',
      ciphertext: inner,
      nonce: 'fake-nonce',
    );

    final parsed = await PostCreateEnvelope.fromEncryptedJson(
      jsonString: wire,
      bridge: PassthroughCryptoBridge(),
      ownMlKemSecretKey: 'own-sk',
    );

    expect(parsed, isNotNull);
    expect(parsed!.mediaKeys, isNull);
  });

  test('toInnerJson serializes media_keys; v1 toJson NEVER emits media_keys',
      () {
    final withKeys = envelope(
      mediaKeys: <String, PostMediaCryptoEntry>{'media-1': cryptoEntry()},
    );

    final innerPayload =
        jsonDecode(withKeys.toInnerJson()) as Map<String, dynamic>;
    final innerKeys = innerPayload['media_keys'] as Map<String, dynamic>?;
    expect(innerKeys, isNotNull);
    final innerEntry = innerKeys!['media-1'] as Map<String, dynamic>;
    expect(innerEntry['key_base64'], 'key-b64');
    expect(innerEntry['nonce'], 'nonce-b64');
    expect(innerEntry['blob_id'], 'blob-1');
    expect(
      innerEntry['scheme'],
      kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
    );
    expect(innerEntry['content_hash'], 'f' * 64);

    // KC-P3 structural-leak guard: keys must never appear ANYWHERE in the
    // v1 plaintext wire form, regardless of fail-closed gates upstream.
    final v1Wire = withKeys.toJson(
      recipientPeerIds: const <String>['peer-bob'],
    );
    expect(v1Wire, isNot(contains('media_keys')));
    expect(v1Wire, isNot(contains('key-b64')));
    expect(v1Wire, isNot(contains('nonce-b64')));
  });

  test(
    'v1 plaintext post_create carrying media_keys parses with mediaKeys == null — keys join only from the v2 decrypt path',
    () {
      final v1 = jsonDecode(envelope().toJson()) as Map<String, dynamic>;
      (v1['payload'] as Map<String, dynamic>)['media_keys'] =
          <String, Object?>{
        'media-1': cryptoEntry().toJson(),
      };

      final parsed = PostCreateEnvelope.fromJson(jsonEncode(v1));

      expect(parsed, isNotNull);
      expect(parsed!.mediaKeys, isNull);
    },
  );

  test('PostMediaCryptoEntry round-trips scheme + content_hash and ignores unknown fields',
      () {
    final json = cryptoEntry().toJson();
    expect(json['scheme'], kMediaAttachmentEncryptionSchemeBlobAesGcmV1);
    expect(json['content_hash'], 'f' * 64);

    final withUnknown = Map<String, dynamic>.from(json)
      ..['future_field'] = 'ignored';
    final restored = PostMediaCryptoEntry.fromJson(withUnknown);
    expect(restored, isNotNull);
    expect(restored!.keyBase64, 'key-b64');
    expect(restored.scheme, kMediaAttachmentEncryptionSchemeBlobAesGcmV1);
    expect(restored.contentHash, 'f' * 64);

    // Deployed-receiver wire compat: legacy entries without the new fields
    // still parse (shipped pass senders never write scheme/hash).
    final legacy = PostMediaCryptoEntry.fromJson(<String, dynamic>{
      'key_base64': 'k',
      'nonce': 'n',
      'blob_id': 'b',
    });
    expect(legacy, isNotNull);
    expect(legacy!.scheme, isNull);
    expect(legacy.contentHash, isNull);
  });

  test('snapshot media entries still carry no key material', () {
    final innerPayload = jsonDecode(
      envelope(
        mediaKeys: <String, PostMediaCryptoEntry>{'media-1': cryptoEntry()},
      ).toInnerJson(),
    ) as Map<String, dynamic>;
    final snapshotMedia =
        ((innerPayload['snapshot'] as Map<String, dynamic>)['media']
                as List<dynamic>)
            .cast<Map<String, dynamic>>();

    for (final entry in snapshotMedia) {
      expect(entry.keys, isNot(contains('encryption_key_base64')));
      expect(entry.keys, isNot(contains('encryption_nonce')));
      expect(entry.keys, isNot(contains('encryption_scheme')));
      expect(entry.keys, isNot(contains('content_hash')));
      expect(entry.keys, isNot(contains('is_encrypted')));
    }
  });
}
