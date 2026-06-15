import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/posts/domain/models/post_media_attachment_model.dart';

void main() {
  PostMediaAttachmentModel keyedAttachment() {
    return PostMediaAttachmentModel(
      mediaId: 'media-1',
      postId: 'post-1',
      blobId: 'blob-1',
      kind: 'image',
      mime: 'image/jpeg',
      sizeBytes: 1024,
      createdAt: '2026-06-12T10:00:00.000Z',
      encryptionKeyBase64: 'key-base64',
      encryptionNonce: 'nonce-base64',
      encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
      contentHash: 'a' * 64,
      isEncrypted: true,
    );
  }

  test('fromMap/toMap round-trip encryption_scheme and content_hash', () {
    final original = keyedAttachment();

    final map = original.toMap();
    expect(
      map['encryption_scheme'],
      kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
    );
    expect(map['content_hash'], 'a' * 64);

    final restored = PostMediaAttachmentModel.fromMap(map);
    expect(
      restored.encryptionScheme,
      kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
    );
    expect(restored.contentHash, 'a' * 64);
    expect(restored.encryptionKeyBase64, 'key-base64');
    expect(restored.encryptionNonce, 'nonce-base64');
    expect(restored.isEncrypted, isTrue);
  });

  test('fromMap tolerates legacy rows without scheme/hash columns values', () {
    final map = keyedAttachment().toMap()
      ..['encryption_scheme'] = null
      ..['content_hash'] = null;

    final restored = PostMediaAttachmentModel.fromMap(map);
    expect(restored.encryptionScheme, isNull);
    expect(restored.contentHash, isNull);
  });

  test('toRenderableJson never emits key, nonce, scheme, or hash', () {
    final json = keyedAttachment().toRenderableJson();

    expect(json.keys, isNot(contains('encryption_key_base64')));
    expect(json.keys, isNot(contains('encryption_nonce')));
    expect(json.keys, isNot(contains('encryption_scheme')));
    expect(json.keys, isNot(contains('content_hash')));
    expect(json.keys, isNot(contains('is_encrypted')));
  });

  test('copyWith carries scheme and hash; isEncrypted default stays false', () {
    final base = PostMediaAttachmentModel(
      mediaId: 'media-2',
      postId: 'post-1',
      blobId: 'blob-2',
      kind: 'image',
      mime: 'image/jpeg',
      sizeBytes: 10,
      createdAt: '2026-06-12T10:00:00.000Z',
    );
    expect(base.isEncrypted, isFalse);
    expect(base.encryptionScheme, isNull);
    expect(base.contentHash, isNull);

    final keyed = base.copyWith(
      encryptionKeyBase64: 'k',
      encryptionNonce: 'n',
      encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
      contentHash: 'b' * 64,
      isEncrypted: true,
    );
    expect(
      keyed.encryptionScheme,
      kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
    );
    expect(keyed.contentHash, 'b' * 64);

    final untouched = keyed.copyWith(position: 1);
    expect(
      untouched.encryptionScheme,
      kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
    );
    expect(untouched.contentHash, 'b' * 64);
    expect(untouched.isEncrypted, isTrue);
  });

  test('fromRenderableJson accepts joined scheme and hash like the key trio',
      () {
    final attachment = PostMediaAttachmentModel.fromRenderableJson(
      <String, dynamic>{
        'media_id': 'media-3',
        'blob_id': 'blob-3',
        'kind': 'image',
        'mime': 'image/jpeg',
        'size_bytes': 12,
      },
      postId: 'post-1',
      position: 0,
      encryptionKeyBase64: 'k',
      encryptionNonce: 'n',
      encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
      contentHash: 'c' * 64,
      isEncrypted: true,
    );
    expect(
      attachment.encryptionScheme,
      kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
    );
    expect(attachment.contentHash, 'c' * 64);
    expect(attachment.isEncrypted, isTrue);
  });
}
