import 'dart:io';

import 'package:flutter_app/features/account_migration/application/migration_file_manifest_validator.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_file_manifest.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('MigrationFileManifestValidator', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('mig005_validator_');
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('fails when a required local file is missing', () async {
      final validator = MigrationFileManifestValidator(
        documentsRootPath: tempDir.path,
      );

      final result = await validator.validateRows(
        chatMediaRows: [
          {
            'id': 'missing-file',
            'message_id': 'msg-1',
            'local_path': 'media/peer-bob/missing.jpg',
            'download_status': 'done',
            'size': 10,
          },
        ],
      );

      expect(result.isValid, isFalse);
      expect(
        result.hasIssue(MigrationFileManifestIssueCode.missingRequiredFile),
        isTrue,
      );
    });

    test(
      'requires encrypted chat media content hash, nonce, scheme, and secure key',
      () async {
        await _writeRelative(tempDir, 'media/group-1/blob.jpg', 'image');
        final validator = MigrationFileManifestValidator(
          documentsRootPath: tempDir.path,
          secureValueReader: (_) async => null,
        );

        final result = await validator.validateRows(
          chatMediaRows: [
            {
              'id': 'blob-secure',
              'message_id': 'msg-1',
              'local_path': 'media/group-1/blob.jpg',
              'download_status': 'done',
              'size': 5,
              'encryption_key_base64':
                  'secure:media_attachment_encryption_key:blob-secure',
              'encryption_nonce': '',
              'encryption_scheme': kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            },
          ],
        );

        expect(result.isValid, isFalse);
        expect(
          result.hasIssue(
            MigrationFileManifestIssueCode.missingChatMediaMetadata,
          ),
          isTrue,
        );
        expect(
          result.hasIssue(MigrationFileManifestIssueCode.missingSecureStoreKey),
          isTrue,
        );
      },
    );

    test(
      'requires DB-resident crypto fields for encrypted post media without secure-store lookup',
      () async {
        await _writeRelative(tempDir, 'post_media/post-1/blob.jpg', 'post');
        var secureLookupCount = 0;
        final validator = MigrationFileManifestValidator(
          documentsRootPath: tempDir.path,
          secureValueReader: (_) async {
            secureLookupCount++;
            return null;
          },
        );

        final result = await validator.validateRows(
          postMediaRows: [
            {
              'media_id': 'media-post',
              'post_id': 'post-1',
              'local_path': 'post_media/post-1/blob.jpg',
              'size_bytes': 4,
              'is_encrypted': 1,
              'encryption_key_base64': '',
              'encryption_nonce': '',
            },
          ],
        );

        expect(result.isValid, isFalse);
        expect(
          result.hasIssue(
            MigrationFileManifestIssueCode.missingPostMediaCrypto,
          ),
          isTrue,
        );
        expect(secureLookupCount, 0);
      },
    );

    test(
      'missing generated thumbnails do not fail the critical manifest',
      () async {
        await _writeRelative(tempDir, 'media/peer-bob/video.mp4', 'video');
        final validator = MigrationFileManifestValidator(
          documentsRootPath: tempDir.path,
        );

        final result = await validator.validateRows(
          chatMediaRows: [
            {
              'id': 'video',
              'message_id': 'msg-1',
              'local_path': 'media/peer-bob/video.mp4',
              'download_status': 'done',
              'size': 5,
            },
          ],
        );

        expect(result.isValid, isTrue);
        expect(
          result.hasIssue(MigrationFileManifestIssueCode.missingRequiredFile),
          isFalse,
        );
      },
    );
  });
}

Future<void> _writeRelative(
  Directory root,
  String relativePath,
  String contents,
) async {
  final file = File(p.join(root.path, relativePath));
  await file.parent.create(recursive: true);
  await file.writeAsString(contents, flush: true);
}
