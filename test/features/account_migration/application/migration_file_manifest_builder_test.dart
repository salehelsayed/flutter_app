import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/features/account_migration/application/migration_file_manifest_builder.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_file_manifest.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('MigrationFileManifestBuilder', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('mig005_manifest_');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test(
      'builds relative checksummed manifest items for app-owned media roots',
      () async {
        await _writeRelative(tempDir, 'media/peer-bob/blob-chat.jpg', 'chat');
        await _writeRelative(
          tempDir,
          'post_media/post-1/blob-post.jpg',
          'post',
        );
        await _writeRelative(tempDir, 'media/avatars/peer-bob.jpg', 'avatar');
        await _writeRelative(
          tempDir,
          'media/group_avatars/group-1.jpg',
          'group-avatar',
        );
        await _writeRelative(
          tempDir,
          'pending_uploads/msg-1/voice.m4a',
          'pending',
        );
        await _writeRelative(
          tempDir,
          'media/peer-bob/video.thumb.jpg',
          'thumb',
        );
        await _writeRelative(tempDir, 'media/peer-bob/blob-chat.jpg.enc', 'ct');
        await _writeRelative(
          tempDir,
          'media/group_avatars/group-1.jpg.download.jpg',
          'temp',
        );
        await _writeRelative(
          tempDir,
          'media/avatars/peer-bob.raw.abc.jpg',
          'raw',
        );

        final builder = MigrationFileManifestBuilder(
          documentsRootPath: tempDir.path,
          secureValueReader: (key) async =>
              key == 'media_attachment_encryption_key:blob-chat'
              ? 'media-key'
              : null,
        );

        final manifest = await builder.build(
          chatMediaRows: [
            {
              'id': 'blob-chat',
              'message_id': 'msg-1',
              'local_path': 'media/peer-bob/blob-chat.jpg',
              'download_status': 'done',
              'size': 4,
              'content_hash': 'a' * 64,
              'encryption_key_base64':
                  'secure:media_attachment_encryption_key:blob-chat',
              'encryption_nonce': 'nonce',
              'encryption_scheme': kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            },
            {
              'id': 'blob-pending',
              'message_id': 'msg-1',
              'local_path': 'pending_uploads/msg-1/voice.m4a',
              'download_status': 'upload_pending',
              'size': 7,
            },
          ],
          postMediaRows: [
            {
              'media_id': 'media-post',
              'post_id': 'post-1',
              'local_path': 'post_media/post-1/blob-post.jpg',
              'size_bytes': 4,
              'is_encrypted': 1,
              'encryption_key_base64': 'post-key',
              'encryption_nonce': 'post-nonce',
            },
          ],
          contactRows: [
            {
              'peer_id': 'peer-bob',
              'avatar_path': 'media/avatars/peer-bob.jpg',
            },
          ],
          groupRows: [
            {'id': 'group-1', 'avatar_path': 'media/group_avatars/group-1.jpg'},
          ],
        );

        expect(manifest.isValid, isTrue);
        expect(
          manifest.items.map((item) => item.relativePath),
          containsAll(<String>[
            'media/peer-bob/blob-chat.jpg',
            'post_media/post-1/blob-post.jpg',
            'media/avatars/peer-bob.jpg',
            'media/group_avatars/group-1.jpg',
            'pending_uploads/msg-1/voice.m4a',
            'media/peer-bob/video.thumb.jpg',
          ]),
        );
        expect(
          manifest.items
              .where(
                (item) =>
                    item.relativePath.endsWith('.enc') ||
                    item.relativePath.endsWith('.download.jpg') ||
                    item.relativePath.contains('.raw.'),
              )
              .toList(),
          isEmpty,
        );
        expect(
          manifest.items.every((item) => !p.isAbsolute(item.relativePath)),
          isTrue,
        );

        final chatItem = manifest.items.singleWhere(
          (item) => item.relativePath == 'media/peer-bob/blob-chat.jpg',
        );
        expect(chatItem.kind, MigrationFileManifestItemKind.chatMedia);
        expect(chatItem.criticality, MigrationFileCriticality.critical);
        expect(chatItem.sizeBytes, 4);
        expect(chatItem.sha256, sha256.convert('chat'.codeUnits).toString());
        expect(chatItem.sourceTable, 'media_attachments');
        expect(chatItem.sourceId, 'blob-chat');

        final thumbnail = manifest.items.singleWhere(
          (item) => item.relativePath == 'media/peer-bob/video.thumb.jpg',
        );
        expect(thumbnail.kind, MigrationFileManifestItemKind.videoThumbnail);
        expect(
          thumbnail.criticality,
          MigrationFileCriticality.nonCriticalCache,
        );

        expect(
          manifest.issues
              .where(
                (issue) =>
                    issue.code == MigrationFileManifestIssueCode.transientFile,
              )
              .length,
          3,
        );
      },
    );

    test(
      'heals legacy app-document absolute paths and flags arbitrary absolute paths',
      () async {
        await _writeRelative(tempDir, 'media/peer-bob/healed.jpg', 'healed');
        final builder = MigrationFileManifestBuilder(
          documentsRootPath: tempDir.path,
        );

        final manifest = await builder.build(
          chatMediaRows: [
            {
              'id': 'healed',
              'message_id': 'msg-1',
              'local_path':
                  '/old-container/Documents/media/peer-bob/healed.jpg',
              'download_status': 'done',
              'size': 6,
            },
            {
              'id': 'gallery',
              'message_id': 'msg-2',
              'local_path': '/var/mobile/Media/DCIM/100APPLE/source.jpg',
              'download_status': 'done',
              'size': 10,
            },
          ],
        );

        expect(
          manifest.items.map((item) => item.relativePath),
          contains('media/peer-bob/healed.jpg'),
        );
        expect(
          manifest.issues.where(
            (issue) =>
                issue.code ==
                    MigrationFileManifestIssueCode.unsupportedAbsolutePath &&
                issue.sourceId == 'gallery',
          ),
          hasLength(1),
        );
      },
    );

    test(
      'uses canonical one-to-one media path when stored path is stale',
      () async {
        await _writeRelative(
          tempDir,
          'media/peer-bob/blob-canonical.jpg',
          'image',
        );
        final builder = MigrationFileManifestBuilder(
          documentsRootPath: tempDir.path,
        );

        final manifest = await builder.build(
          chatMediaRows: [
            {
              'id': 'blob-canonical',
              'message_id': 'msg-1',
              'migration_contact_peer_id': 'peer-bob',
              'local_path':
                  '/data/user/0/com.mknoon.app/cache/image_picker/source.jpg',
              'download_status': 'done',
              'mime': 'image/jpeg',
              'size': 5,
            },
          ],
        );

        expect(manifest.isValid, isTrue);
        expect(
          manifest.items.map((item) => item.relativePath),
          contains('media/peer-bob/blob-canonical.jpg'),
        );
        expect(manifest.pathRepairs, hasLength(1));
        expect(manifest.pathRepairs.single.sourceTable, 'media_attachments');
        expect(manifest.pathRepairs.single.sourceId, 'blob-canonical');
        expect(
          manifest.pathRepairs.single.relativePath,
          'media/peer-bob/blob-canonical.jpg',
        );
      },
    );

    test(
      'uses canonical group media path when stored path is missing',
      () async {
        await _writeRelative(
          tempDir,
          'media/group-1/blob-group.jpg',
          'group-image',
        );
        final builder = MigrationFileManifestBuilder(
          documentsRootPath: tempDir.path,
        );

        final manifest = await builder.build(
          chatMediaRows: [
            {
              'id': 'blob-group',
              'message_id': 'group-msg-1',
              'migration_group_id': 'group-1',
              'local_path': null,
              'download_status': 'done',
              'mime': 'image/jpeg',
              'size': 11,
            },
          ],
        );

        expect(manifest.isValid, isTrue);
        expect(
          manifest.items.map((item) => item.relativePath),
          contains('media/group-1/blob-group.jpg'),
        );
        expect(manifest.pathRepairs, hasLength(1));
        expect(
          manifest.pathRepairs.single.relativePath,
          'media/group-1/blob-group.jpg',
        );
      },
    );

    test(
      'materializes completed group media from durable pending upload fallback',
      () async {
        await _writeRelative(
          tempDir,
          'pending_uploads/group-msg-1/blob-group.jpg',
          'group-image',
        );
        final builder = MigrationFileManifestBuilder(
          documentsRootPath: tempDir.path,
        );

        final manifest = await builder.build(
          chatMediaRows: [
            {
              'id': 'blob-group',
              'message_id': 'group-msg-1',
              'migration_group_id': 'group-1',
              'local_path': 'media/group-1/blob-group.jpg',
              'download_status': 'done',
              'mime': 'image/jpeg',
              'size': 11,
            },
          ],
        );

        expect(manifest.isValid, isTrue);
        expect(
          manifest.items.map((item) => item.relativePath),
          contains('media/group-1/blob-group.jpg'),
        );
        expect(
          File(
            p.join(tempDir.path, 'media/group-1/blob-group.jpg'),
          ).existsSync(),
          isTrue,
        );
        expect(manifest.pathRepairs, isEmpty);
      },
    );

    test(
      'includes encrypted group companion when plaintext media is missing',
      () async {
        await _writeRelative(
          tempDir,
          'media/group-1/blob-group.jpg.enc',
          'encrypted-group-image',
        );
        final builder = MigrationFileManifestBuilder(
          documentsRootPath: tempDir.path,
        );

        final manifest = await builder.build(
          chatMediaRows: [
            {
              'id': 'blob-group',
              'message_id': 'group-msg-1',
              'migration_group_id': 'group-1',
              'local_path': 'media/group-1/blob-group.jpg',
              'download_status': 'done',
              'mime': 'image/jpeg',
              'size': 11,
              'content_hash': 'a' * 64,
              'encryption_key_base64': 'media-key',
              'encryption_nonce': 'nonce',
              'encryption_scheme': kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            },
          ],
        );

        expect(manifest.isValid, isTrue);
        expect(
          manifest.items.map((item) => item.relativePath),
          contains('media/group-1/blob-group.jpg.enc'),
        );
        expect(manifest.pathRepairs, isEmpty);
        expect(
          manifest.issues.where(
            (issue) =>
                issue.code == MigrationFileManifestIssueCode.transientFile,
          ),
          isEmpty,
        );
      },
    );

    test(
      'missing chat media with no local recovery path is a blocking issue',
      () async {
        final builder = MigrationFileManifestBuilder(
          documentsRootPath: tempDir.path,
        );

        final manifest = await builder.build(
          chatMediaRows: [
            {
              'id': 'missing-media',
              'message_id': 'msg-1',
              'migration_contact_peer_id': 'peer-bob',
              'local_path': null,
              'download_status': 'done',
              'mime': 'image/jpeg',
              'size': 10,
            },
          ],
        );

        expect(manifest.isValid, isFalse);
        expect(
          manifest.hasIssue(MigrationFileManifestIssueCode.missingRequiredFile),
          isTrue,
        );
        final issue = manifest.issues.singleWhere(
          (issue) =>
              issue.code == MigrationFileManifestIssueCode.missingRequiredFile,
        );
        expect(issue.relativePath, 'media/peer-bob/missing-media.jpg');
        expect(issue.criticality, MigrationFileCriticality.critical);
        expect(
          issue.diagnostics,
          allOf(
            containsPair('messageId', 'msg-1'),
            containsPair('downloadStatus', 'done'),
            containsPair('mime', 'image/jpeg'),
            containsPair('storedPathKind', 'empty'),
            containsPair('migrationContactPeerId', 'peer-bob'),
            containsPair('candidateCount', 2),
          ),
        );
        final candidates =
            issue.diagnostics['candidateDiagnostics'] as List<dynamic>;
        expect(
          candidates,
          contains(
            allOf(
              isA<Map<String, Object?>>(),
              containsPair('reason', 'source_file_missing'),
              containsPair(
                'candidateRelativePath',
                'media/peer-bob/missing-media.jpg',
              ),
              containsPair('fileExists', false),
              containsPair('expectedSizeBytes', 10),
            ),
          ),
        );
      },
    );

    test(
      'does not require local files for chat media states without local bytes',
      () async {
        final builder = MigrationFileManifestBuilder(
          documentsRootPath: tempDir.path,
        );

        final manifest = await builder.build(
          chatMediaRows: [
            for (final status in const [
              'pending',
              'downloading',
              'failed',
              'upload_failed',
            ])
              {
                'id': 'media-$status',
                'message_id': 'message-$status',
                'migration_group_id': 'group-1',
                'local_path': 'media/group-1/media-$status.jpg',
                'download_status': status,
                'mime': 'image/jpeg',
                'size': 10,
              },
          ],
        );

        expect(manifest.isValid, isTrue);
        expect(manifest.items, isEmpty);
        expect(manifest.issues, isEmpty);
        expect(manifest.pathRepairs, isEmpty);
      },
    );

    test('bundles the stored file when the row size column diverges from disk '
        '(LAN-received media records the sender-declared size)', () async {
      // Regression for the 2026-06-11 Pixel→iPhone move abort: every
      // LAN-received attachment stores an absolute local_media path and a
      // sender-declared `size` that legitimately differs from the bytes the
      // LAN transfer delivered. The row's OWN stored file is id-keyed and
      // is what the app displays — migration must mirror it as-is, not
      // hard-block the whole move on the stale size column.
      await _writeRelative(
        tempDir,
        'local_media/peer-lan/lan-blob.jpg',
        'actual-lan-bytes',
      );
      final storedAbsolutePath = p.join(
        tempDir.path,
        'local_media/peer-lan/lan-blob.jpg',
      );

      final builder = MigrationFileManifestBuilder(
        documentsRootPath: tempDir.path,
        secureValueReader: (_) async => null,
      );
      final manifest = await builder.build(
        chatMediaRows: [
          {
            'id': 'lan-blob',
            'message_id': 'msg-lan',
            'migration_contact_peer_id': 'peer-lan',
            'local_path': storedAbsolutePath,
            'download_status': 'done',
            'mime': 'image/jpeg',
            // Sender-declared size: diverges from the 16 bytes on disk.
            'size': 51105802,
          },
        ],
      );

      expect(
        manifest.isValid,
        isTrue,
        reason: 'a healthy stored file must never block the move',
      );
      final item = manifest.items.singleWhere(
        (item) => item.sourceId == 'lan-blob',
      );
      expect(item.relativePath, 'media/peer-lan/lan-blob.jpg');
      expect(
        item.sizeBytes,
        'actual-lan-bytes'.length,
        reason: 'the manifest must carry the on-disk size, not the column',
      );
      // The divergence stays observable as a NON-blocking issue.
      final issue = manifest.issues.singleWhere(
        (issue) =>
            issue.code == MigrationFileManifestIssueCode.fileSizeMismatch,
      );
      expect(issue.blocking, isFalse);
      expect(issue.sourceId, 'lan-blob');
      expect(issue.diagnostics['fileBytes'], 'actual-lan-bytes'.length);
      expect(issue.diagnostics['expectedSizeBytes'], 51105802);
      // The local_media file is canonicalized into media/ and the row is
      // queued for path repair, like any other local-media canonicalization.
      expect(
        File(p.join(tempDir.path, 'media/peer-lan/lan-blob.jpg')).existsSync(),
        isTrue,
      );
      expect(manifest.pathRepairs, hasLength(1));
      expect(
        manifest.pathRepairs.single.relativePath,
        'media/peer-lan/lan-blob.jpg',
      );
    });

    test('bundles post media whose size column diverges from disk without '
        'blocking the move', () async {
      // Same principle as chat media: the row's own stored file is what
      // the app uses — a stale size_bytes column must not block the move.
      await _writeRelative(
        tempDir,
        'post_media/post-1/inflated.jpg',
        'inflated-post-bytes',
      );

      final builder = MigrationFileManifestBuilder(
        documentsRootPath: tempDir.path,
        secureValueReader: (_) async => null,
      );
      final manifest = await builder.build(
        postMediaRows: [
          {
            'media_id': 'post-blob',
            'local_path': 'post_media/post-1/inflated.jpg',
            'size_bytes': 999999,
          },
        ],
      );

      expect(manifest.isValid, isTrue);
      final item = manifest.items.singleWhere(
        (item) => item.sourceId == 'post-blob',
      );
      expect(item.sizeBytes, 'inflated-post-bytes'.length);
      final issue = manifest.issues.singleWhere(
        (issue) =>
            issue.code == MigrationFileManifestIssueCode.fileSizeMismatch,
      );
      expect(issue.blocking, isFalse);
      expect(issue.diagnostics['fileBytes'], 'inflated-post-bytes'.length);
      expect(issue.diagnostics['expectedSizeBytes'], 999999);
    });

    test('still blocks when a fallback candidate found by guessing has the '
        'wrong size (wrong-file guard)', () async {
      // The stored path is gone; the canonical-location guess finds a file
      // whose size contradicts the row. Bundling it could ship the wrong
      // bytes, so this stays a blocking fileSizeMismatch.
      await _writeRelative(
        tempDir,
        'media/peer-x/ghost-blob.jpg',
        'unexpected-bytes',
      );

      final builder = MigrationFileManifestBuilder(
        documentsRootPath: tempDir.path,
        secureValueReader: (_) async => null,
      );
      final manifest = await builder.build(
        chatMediaRows: [
          {
            'id': 'ghost-blob',
            'message_id': 'msg-ghost',
            'migration_contact_peer_id': 'peer-x',
            'local_path': null,
            'download_status': 'done',
            'mime': 'image/jpeg',
            'size': 999,
          },
        ],
      );

      expect(manifest.isValid, isFalse);
      final issue = manifest.issues.singleWhere(
        (issue) =>
            issue.code == MigrationFileManifestIssueCode.fileSizeMismatch,
      );
      expect(issue.blocking, isTrue);
      expect(manifest.items, isEmpty);
    });

    test(
      'TC-347-07 custody ciphertext is exact critical identity-scoped authority',
      () async {
        const identityPeerId = 'migration-self';
        const ciphertext = 'exact-retained-ciphertext';
        final identityScope = sha256
            .convert(identityPeerId.codeUnits)
            .toString();
        final contentHash = sha256.convert(ciphertext.codeUnits).toString();
        final relativePath =
            'direct_media_blob_custody_v1/$identityScope/candidate.blob';
        await _writeRelative(tempDir, relativePath, ciphertext);

        final manifest =
            await MigrationFileManifestBuilder(
              documentsRootPath: tempDir.path,
            ).build(
              identityRows: const <Map<String, Object?>>[
                <String, Object?>{'peer_id': identityPeerId},
              ],
              directMediaBlobCustodyRows: <Map<String, Object?>>[
                _outgoingBlobCustodyRow(
                  attachmentId: 'attachment-347',
                  relativePath: relativePath,
                  contentHash: contentHash,
                  ciphertextSize: ciphertext.length,
                ),
              ],
              scanDocumentsForCacheAndTransients: false,
            );

        expect(manifest.isValid, isTrue);
        expect(manifest.issues, isEmpty);
        final item = manifest.items.single;
        expect(item.kind, MigrationFileManifestItemKind.directMediaBlobCustody);
        expect(item.criticality, MigrationFileCriticality.critical);
        expect(item.relativePath, relativePath);
        expect(item.sizeBytes, ciphertext.length);
        expect(item.sha256, contentHash);
        expect(item.sourceTable, 'direct_media_blob_custody');
        expect(item.sourceId, 'attachment-347');
      },
    );

    test(
      'TC-347-07 rejects absolute traversal and cross-identity custody paths',
      () async {
        const identityPeerId = 'migration-self';
        final identityScope = sha256
            .convert(identityPeerId.codeUnits)
            .toString();
        final hash = sha256.convert('bytes'.codeUnits).toString();
        final base = _outgoingBlobCustodyRow(
          attachmentId: 'absolute',
          relativePath: '/tmp/absolute.blob',
          contentHash: hash,
          ciphertextSize: 5,
        );

        final manifest =
            await MigrationFileManifestBuilder(
              documentsRootPath: tempDir.path,
            ).build(
              identityRows: const <Map<String, Object?>>[
                <String, Object?>{'peer_id': identityPeerId},
              ],
              directMediaBlobCustodyRows: <Map<String, Object?>>[
                base,
                <String, Object?>{
                  ...base,
                  'attachment_id': 'traversal',
                  'ciphertext_relative_path':
                      'direct_media_blob_custody_v1/$identityScope/../escape.blob',
                },
                <String, Object?>{
                  ...base,
                  'attachment_id': 'cross-identity',
                  'ciphertext_relative_path':
                      'direct_media_blob_custody_v1/${'b' * 64}/cross.blob',
                },
              ],
              scanDocumentsForCacheAndTransients: false,
            );

        expect(manifest.isValid, isFalse);
        expect(manifest.items, isEmpty);
        expect(manifest.issues, hasLength(3));
        expect(
          manifest.issues.map((issue) => issue.code),
          everyElement(MigrationFileManifestIssueCode.unsupportedAbsolutePath),
        );
        expect(
          manifest.issues.every(
            (issue) =>
                issue.blocking &&
                issue.criticality == MigrationFileCriticality.critical,
          ),
          isTrue,
        );
      },
    );

    test(
      'TC-347-07 missing or changed custody ciphertext blocks transfer',
      () async {
        const identityPeerId = 'migration-self';
        final identityScope = sha256
            .convert(identityPeerId.codeUnits)
            .toString();
        final missingPath =
            'direct_media_blob_custody_v1/$identityScope/missing.blob';
        final expectedHash = sha256.convert('right'.codeUnits).toString();
        final builder = MigrationFileManifestBuilder(
          documentsRootPath: tempDir.path,
        );

        final missing = await builder.build(
          identityRows: const <Map<String, Object?>>[
            <String, Object?>{'peer_id': identityPeerId},
          ],
          directMediaBlobCustodyRows: <Map<String, Object?>>[
            _outgoingBlobCustodyRow(
              attachmentId: 'missing-347',
              relativePath: missingPath,
              contentHash: expectedHash,
              ciphertextSize: 5,
            ),
          ],
          scanDocumentsForCacheAndTransients: false,
        );
        expect(missing.isValid, isFalse);
        expect(
          missing.issues.single.code,
          MigrationFileManifestIssueCode.missingRequiredFile,
        );

        final changedPath =
            'direct_media_blob_custody_v1/$identityScope/changed.blob';
        await _writeRelative(tempDir, changedPath, 'wrong');
        final changed = await builder.build(
          identityRows: const <Map<String, Object?>>[
            <String, Object?>{'peer_id': identityPeerId},
          ],
          directMediaBlobCustodyRows: <Map<String, Object?>>[
            _outgoingBlobCustodyRow(
              attachmentId: 'changed-347',
              relativePath: changedPath,
              contentHash: expectedHash,
              ciphertextSize: 5,
            ),
          ],
          scanDocumentsForCacheAndTransients: false,
        );
        expect(changed.isValid, isFalse);
        expect(
          changed.issues.single.code,
          MigrationFileManifestIssueCode.fileSizeMismatch,
        );
        expect(changed.items, isEmpty);
      },
    );
  });
}

Map<String, Object?> _outgoingBlobCustodyRow({
  required String attachmentId,
  required String relativePath,
  required String contentHash,
  required int ciphertextSize,
}) => <String, Object?>{
  'attachment_id': attachmentId,
  'message_id': 'message-347',
  'direction': 'outgoing',
  'state': 'outgoing_stored',
  'inbox_custody_incarnation_id': '1234567890abcdef1234567890abcdef',
  'recipient_peer_id': 'recipient-347',
  'ciphertext_relative_path': relativePath,
  'custody_kind': 'direct_media_blob_v1',
  'custody_contract': 'ack_or_expiry_v1',
  'content_hash': contentHash,
  'ciphertext_size': ciphertextSize,
  'transport_mime': 'application/octet-stream',
  'expires_at_ms': 2000000000000,
  'custody_relay_peer_id': 'relay-347',
  'retry_count': 0,
  'last_attempt_at': null,
  'next_attempt_at': null,
  'created_at': '2026-08-08T09:00:00.000Z',
  'updated_at': '2026-08-08T09:01:00.000Z',
};

Future<void> _writeRelative(
  Directory root,
  String relativePath,
  String contents,
) async {
  final file = File(p.join(root.path, relativePath));
  await file.parent.create(recursive: true);
  await file.writeAsString(contents, flush: true);
}
