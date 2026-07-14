import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/constants/retry_constants.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

import '../../shared/fakes/fake_media_file_manager.dart';

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

  group('canonical local plaintext authority', () {
    const jpegBytes = <int>[
      0xff,
      0xd8,
      0xff,
      0xe0,
      0x00,
      0x10,
      0x4a,
      0x46,
      0x49,
      0x46,
    ];
    late FakeMediaFileManager fileManager;
    late Set<String> ownedFiles;

    setUp(() {
      fileManager = FakeMediaFileManager();
      ownedFiles = <String>{};
    });

    tearDown(() {
      for (final path in ownedFiles) {
        final file = File(path);
        if (file.existsSync()) file.deleteSync();
      }
    });

    Future<MediaAttachment> seed({
      required String ownerScopeId,
      required String attachmentId,
      String? storedPath,
      List<int> bytes = jpegBytes,
    }) async {
      final absolute = await fileManager.localPathForAttachment(
        contactPeerId: ownerScopeId,
        blobId: attachmentId,
        mime: 'image/jpeg',
      );
      File(absolute).writeAsBytesSync(bytes);
      ownedFiles.add(absolute);
      return MediaAttachment(
        id: attachmentId,
        messageId: 'message-$attachmentId',
        mime: 'image/jpeg',
        size: bytes.length,
        mediaType: 'image',
        localPath: storedPath ?? 'media/$ownerScopeId/$attachmentId.jpg',
        downloadStatus: kMediaDownloadStatusDone,
        createdAt: '2026-07-14T00:00:00.000Z',
        contentHash: validHash,
        encryptionKeyBase64: 'relay-key',
        encryptionNonce: 'relay-nonce',
        encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
      );
    }

    test(
      'accepts exact relative current absolute and stale iOS canonical paths',
      () async {
        final relative = await seed(
          ownerScopeId: 'authority-relative',
          attachmentId: 'attachment-relative',
        );
        final absolute = await seed(
          ownerScopeId: 'authority-absolute',
          attachmentId: 'attachment-absolute',
        );
        final absolutePath = await fileManager.localPathForAttachment(
          contactPeerId: 'authority-absolute',
          blobId: 'attachment-absolute',
          mime: 'image/jpeg',
        );
        final legacy = await seed(
          ownerScopeId: 'authority-legacy',
          attachmentId: 'attachment-legacy',
          storedPath:
              '/var/mobile/Containers/Data/Application/OLD/Documents/media/'
              'authority-legacy/attachment-legacy.jpg',
        );

        expect(
          (await GroupMediaIntegrityPolicy.validateCanonicalLocalPlaintext(
            attachment: relative,
            ownerScopeId: 'authority-relative',
            mediaFileManager: fileManager,
          )).isValid,
          isTrue,
        );
        expect(
          (await GroupMediaIntegrityPolicy.validateCanonicalLocalPlaintext(
            attachment: absolute.copyWith(localPath: absolutePath),
            ownerScopeId: 'authority-absolute',
            mediaFileManager: fileManager,
          )).isValid,
          isTrue,
        );
        final legacyResult =
            await GroupMediaIntegrityPolicy.validateCanonicalLocalPlaintext(
              attachment: legacy,
              ownerScopeId: 'authority-legacy',
              mediaFileManager: fileManager,
            );
        expect(legacyResult.isValid, isTrue);
        expect(
          legacyResult.resolvedPath,
          await fileManager.localPathForAttachment(
            contactPeerId: 'authority-legacy',
            blobId: 'attachment-legacy',
            mime: 'image/jpeg',
          ),
        );
      },
    );

    test('rejects unsafe identifiers before constructing any path', () async {
      final base = MediaAttachment(
        id: 'attachment-safe',
        messageId: 'message-safe',
        mime: 'image/jpeg',
        size: jpegBytes.length,
        mediaType: 'image',
        localPath: 'media/safe-owner/attachment-safe.jpg',
        downloadStatus: kMediaDownloadStatusDone,
        createdAt: '2026-07-14T00:00:00.000Z',
        contentHash: validHash,
        encryptionKeyBase64: 'relay-key',
        encryptionNonce: 'relay-nonce',
        encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
      );

      expect(
        (await GroupMediaIntegrityPolicy.validateCanonicalLocalPlaintext(
          attachment: base,
          ownerScopeId: '../escape',
          mediaFileManager: fileManager,
        )).reason,
        'unsafe_owner_scope_id',
      );
      expect(
        (await GroupMediaIntegrityPolicy.validateCanonicalLocalPlaintext(
          attachment: base.copyWith(id: '/absolute'),
          ownerScopeId: 'safe-owner',
          mediaFileManager: fileManager,
        )).reason,
        'unsafe_attachment_id',
      );
    });

    test(
      'rejects traversal arbitrary absolute and resolver-derived authority',
      () async {
        final traversal = await seed(
          ownerScopeId: 'authority-traversal',
          attachmentId: 'attachment-traversal',
          storedPath:
              'media/authority-traversal/../authority-traversal/'
              'attachment-traversal.jpg',
        );
        expect(
          (await GroupMediaIntegrityPolicy.validateCanonicalLocalPlaintext(
            attachment: traversal,
            ownerScopeId: 'authority-traversal',
            mediaFileManager: fileManager,
          )).reason,
          'noncanonical_local_path',
        );

        final arbitrary = await seed(
          ownerScopeId: 'authority-arbitrary',
          attachmentId: 'attachment-arbitrary',
          storedPath: '/tmp/foreign/attachment-arbitrary.jpg',
        );
        expect(
          (await GroupMediaIntegrityPolicy.validateCanonicalLocalPlaintext(
            attachment: arbitrary,
            ownerScopeId: 'authority-arbitrary',
            mediaFileManager: fileManager,
          )).reason,
          'noncanonical_local_path',
        );

        final poisoned = await seed(
          ownerScopeId: 'authority-poisoned',
          attachmentId: 'attachment-poisoned',
          storedPath:
              '/old/Documents/media/authority-poisoned/'
              'attachment-poisoned.jpg',
        );
        fileManager.resolveResult = '/tmp/attacker-controlled/source.jpg';
        expect(
          (await GroupMediaIntegrityPolicy.validateCanonicalLocalPlaintext(
            attachment: poisoned,
            ownerScopeId: 'authority-poisoned',
            mediaFileManager: fileManager,
          )).reason,
          'noncanonical_local_path',
        );
      },
    );

    test('rejects a symlinked owner directory that escapes the root', () async {
      const owner = 'authority-symlink';
      const attachmentId = 'attachment-symlink';
      final mediaRoot = await fileManager.trustedMediaRootPath();
      Directory(mediaRoot).createSync(recursive: true);
      final ownerPath = p.join(mediaRoot, owner);
      final existingOwner = Directory(ownerPath);
      if (existingOwner.existsSync()) existingOwner.deleteSync(recursive: true);
      final outside = Directory.systemTemp.createTempSync(
        'group_integrity_escape_',
      );
      addTearDown(() {
        final link = Link(ownerPath);
        if (link.existsSync()) link.deleteSync();
        if (outside.existsSync()) outside.deleteSync(recursive: true);
      });
      File(
        p.join(outside.path, '$attachmentId.jpg'),
      ).writeAsBytesSync(jpegBytes);
      Link(ownerPath).createSync(outside.path);
      final attachment = MediaAttachment(
        id: attachmentId,
        messageId: 'message-symlink',
        mime: 'image/jpeg',
        size: jpegBytes.length,
        mediaType: 'image',
        localPath: 'media/$owner/$attachmentId.jpg',
        downloadStatus: kMediaDownloadStatusDone,
        createdAt: '2026-07-14T00:00:00.000Z',
        contentHash: validHash,
        encryptionKeyBase64: 'relay-key',
        encryptionNonce: 'relay-nonce',
        encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
      );

      expect(
        (await GroupMediaIntegrityPolicy.validateCanonicalLocalPlaintext(
          attachment: attachment,
          ownerScopeId: owner,
          mediaFileManager: fileManager,
        )).reason,
        'unsafe_or_missing_local_file',
      );
    });
  });

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
      // INV-DL-3: integrity_failed (tamper) is no longer retryable.
      expect(
        GroupMediaIntegrityPolicy.isRetryableDownloadFailure(
          base.copyWith(downloadStatus: kMediaDownloadStatusIntegrityFailed),
        ),
        isFalse,
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

  test(
    'GIRD-005 treats verified done media without a local path as resolving while unsafe states stay unavailable',
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
      final resolving = base.copyWith(clearLocalPath: true);

      expect(
        GroupMediaIntegrityPolicy.canDisplayVerifiedGroupMedia(resolving),
        isFalse,
      );
      expect(
        GroupMediaIntegrityPolicy.isUnavailableMedia(
          resolving,
          requireVerifiedContentHash: true,
        ),
        isFalse,
      );
      expect(
        GroupMediaIntegrityPolicy.isUnavailableMedia(
          resolving.copyWith(clearContentHash: true),
          requireVerifiedContentHash: true,
        ),
        isTrue,
      );
      expect(
        GroupMediaIntegrityPolicy.isUnavailableMedia(
          resolving.copyWith(contentHash: 'abc'),
          requireVerifiedContentHash: true,
        ),
        isTrue,
      );
      expect(
        GroupMediaIntegrityPolicy.isUnavailableMedia(
          resolving.copyWith(
            clearEncryptionKeyBase64: true,
            clearEncryptionNonce: true,
            clearEncryptionScheme: true,
          ),
          requireVerifiedContentHash: true,
        ),
        isTrue,
      );
      expect(
        GroupMediaIntegrityPolicy.isUnavailableMedia(
          resolving.copyWith(
            downloadStatus: kMediaDownloadStatusIntegrityFailed,
          ),
          requireVerifiedContentHash: true,
        ),
        isTrue,
      );
      expect(
        GroupMediaIntegrityPolicy.isUnavailableMedia(
          resolving.copyWith(downloadStatus: kMediaDownloadStatusUploadFailed),
          requireVerifiedContentHash: true,
        ),
        isTrue,
      );
      expect(
        GroupMediaIntegrityPolicy.isUnavailableMedia(
          resolving.copyWith(
            downloadStatus: kMediaDownloadStatusUploadCancelled,
          ),
          requireVerifiedContentHash: true,
        ),
        isTrue,
      );
    },
  );

  group('bounded download retries', () {
    const base = MediaAttachment(
      id: 'blob',
      messageId: 'msg',
      mime: 'image/jpeg',
      size: 5,
      mediaType: 'image',
      downloadStatus: kMediaDownloadStatusFailed,
      createdAt: '2026-06-17T12:00:00.000Z',
    );

    test(
      'failed is retryable only while under the retry ceiling (INV-DL-1)',
      () {
        expect(
          GroupMediaIntegrityPolicy.isRetryableDownloadFailure(base),
          isTrue, // count null -> treated as 0 < ceiling
        );
        expect(
          GroupMediaIntegrityPolicy.isRetryableDownloadFailure(
            base.copyWith(downloadRetryCount: kMaxDownloadRetries - 1),
          ),
          isTrue,
        );
        expect(
          GroupMediaIntegrityPolicy.isRetryableDownloadFailure(
            base.copyWith(downloadRetryCount: kMaxDownloadRetries),
          ),
          isFalse,
        );
      },
    );

    test('download_failed is terminal: not retryable, and unavailable', () {
      final terminal = base.copyWith(
        downloadStatus: kMediaDownloadStatusDownloadFailed,
        downloadRetryCount: kMaxDownloadRetries,
      );
      expect(
        GroupMediaIntegrityPolicy.isRetryableDownloadFailure(terminal),
        isFalse,
      );
      expect(GroupMediaIntegrityPolicy.isUnavailableMedia(terminal), isTrue);
    });
  });
}
