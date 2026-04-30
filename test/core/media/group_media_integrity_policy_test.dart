import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

void main() {
  const validHash =
      '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824';

  test('computes canonical SHA-256 for a file', () async {
    final dir = await Directory.systemTemp.createTemp('mknoon_hash_test_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/media.bin');
    await file.writeAsString('hello');

    final hash = await GroupMediaIntegrityPolicy.computeFileSha256Hex(
      file.path,
    );

    expect(hash, validHash);
  });

  test('validates required lowercase SHA-256 content hash', () {
    expect(
      GroupMediaIntegrityPolicy.validateRequiredContentHash(validHash).isValid,
      isTrue,
    );
    expect(
      GroupMediaIntegrityPolicy.normalizeSha256Hex(validHash.toUpperCase()),
      validHash,
    );
    expect(
      GroupMediaIntegrityPolicy.validateRequiredContentHash(null).reason,
      'missing_content_hash',
    );
    expect(
      GroupMediaIntegrityPolicy.validateRequiredContentHash('abc').reason,
      'malformed_content_hash',
    );
  });

  test('compares downloaded file hash against descriptor digest', () async {
    final dir = await Directory.systemTemp.createTemp('mknoon_hash_test_');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/media.bin');
    await file.writeAsString('hello');

    final match = await GroupMediaIntegrityPolicy.validateFileContentHash(
      path: file.path,
      expectedHash: validHash,
    );
    final mismatch = await GroupMediaIntegrityPolicy.validateFileContentHash(
      path: file.path,
      expectedHash:
          'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    );

    expect(match.isValid, isTrue);
    expect(mismatch.reason, 'content_hash_mismatch');
  });

  test(
    'display eligibility requires done status, local path, hash, and encryption metadata',
    () {
      const attachment = MediaAttachment(
        id: 'blob',
        messageId: 'msg',
        mime: 'image/jpeg',
        size: 5,
        mediaType: 'image',
        localPath: '/tmp/media.jpg',
        downloadStatus: 'done',
        createdAt: '2026-04-30T12:00:00.000Z',
        contentHash: validHash,
        encryptionKeyBase64: 'key-1',
        encryptionNonce: 'nonce-1',
        encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
      );

      expect(
        GroupMediaIntegrityPolicy.canDisplayVerifiedGroupMedia(attachment),
        isTrue,
      );
      expect(
        GroupMediaIntegrityPolicy.canDisplayVerifiedGroupMedia(
          attachment.copyWith(clearContentHash: true),
        ),
        isFalse,
      );
      expect(
        GroupMediaIntegrityPolicy.canDisplayVerifiedGroupMedia(
          attachment.copyWith(
            downloadStatus: kMediaDownloadStatusIntegrityFailed,
          ),
        ),
        isFalse,
      );
      expect(
        GroupMediaIntegrityPolicy.canDisplayVerifiedGroupMedia(
          attachment.copyWith(
            clearEncryptionKeyBase64: true,
            clearEncryptionNonce: true,
            clearEncryptionScheme: true,
          ),
        ),
        isFalse,
      );
    },
  );

  test('thumbnail hash is optional unless a remote thumbnail exists', () {
    expect(
      GroupMediaIntegrityPolicy.validateOptionalThumbnailHash(null).isValid,
      isTrue,
    );
    expect(
      GroupMediaIntegrityPolicy.validateOptionalThumbnailHash(
        validHash,
      ).isValid,
      isTrue,
    );
    expect(
      GroupMediaIntegrityPolicy.validateOptionalThumbnailHash('xyz').reason,
      'malformed_thumbnail_hash',
    );
  });

  test(
    'MD-012 status helpers separate quarantine, download retry, and upload retry owners',
    () {
      const base = MediaAttachment(
        id: 'blob',
        messageId: 'msg',
        mime: 'image/jpeg',
        size: 5,
        mediaType: 'image',
        localPath: '/tmp/media.jpg',
        downloadStatus: kMediaDownloadStatusDone,
        createdAt: '2026-04-30T12:00:00.000Z',
        contentHash: validHash,
        encryptionKeyBase64: 'key-1',
        encryptionNonce: 'nonce-1',
        encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
      );

      expect(
        GroupMediaIntegrityPolicy.isQuarantinedGroupMedia(
          base.copyWith(downloadStatus: kMediaDownloadStatusIntegrityFailed),
        ),
        isTrue,
      );
      expect(
        GroupMediaIntegrityPolicy.isRetryableDownloadFailure(
          base.copyWith(downloadStatus: kMediaDownloadStatusFailed),
        ),
        isTrue,
      );
      expect(
        GroupMediaIntegrityPolicy.isRetryableDownloadFailure(
          base.copyWith(downloadStatus: kMediaDownloadStatusIntegrityFailed),
        ),
        isTrue,
      );
      expect(
        GroupMediaIntegrityPolicy.isRetryableDownloadFailure(
          base.copyWith(downloadStatus: kMediaDownloadStatusUploadPending),
        ),
        isFalse,
      );
      expect(
        GroupMediaIntegrityPolicy.isUnavailableMedia(
          base.copyWith(downloadStatus: kMediaDownloadStatusUploadFailed),
          requireVerifiedContentHash: true,
        ),
        isTrue,
      );
      expect(
        GroupMediaIntegrityPolicy.isUnavailableMedia(
          base.copyWith(clearContentHash: true),
          requireVerifiedContentHash: true,
        ),
        isTrue,
      );
      expect(
        GroupMediaIntegrityPolicy.isUnavailableMedia(
          base,
          requireVerifiedContentHash: true,
        ),
        isFalse,
      );
    },
  );
}
