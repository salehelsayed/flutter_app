// Real SQLite ownership/claims/counters; files and group parent lookup are test ports.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/application/download_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import '../bridge/fake_bridge.dart';
import '../../shared/fixtures/media_repository_real_db_fixture.dart';
import '../../shared/fakes/fake_media_file_manager.dart';
import '../../shared/fakes/in_memory_group_message_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final owner in [MediaOwnerLane.direct, MediaOwnerLane.group]) {
    test(
      '$owner network failure preserves the real SQL nontransport budget',
      () async {
        final root = await Directory.systemTemp.createTemp('media-budget-');
        final fixture = await MediaRepositoryRealDbFixture.create(
          databasePath: '${root.path}/identity.db',
          databaseFactoryOverride: databaseFactoryFfiNoIsolate,
        );
        addTearDown(() async {
          MediaFileManager.debugResetDocumentsDirCache();
          await fixture.dispose();
          await root.delete(recursive: true);
        });
        MediaFileManager.cacheDocumentsDir(FakeMediaFileManager.testRootPath);
        final groupParents = InMemoryGroupMessageRepository();
        if (owner == MediaOwnerLane.direct) {
          await fixture.seedDirectParent(
            'transport-budget',
            contactPeerId: 'sender',
          );
        } else {
          await fixture.seedGroupParent('transport-budget', groupId: 'group-1');
          final row = (await fixture.db.query(
            'group_messages',
            where: 'id = ?',
            whereArgs: ['transport-budget'],
          )).single;
          await groupParents.saveMessage(
            GroupMessage.fromMap(Map<String, dynamic>.from(row)),
          );
        }
        final attachment = MediaAttachment(
          id: 'budget-blob',
          messageId: 'transport-budget',
          mime: 'image/jpeg',
          size: 4096,
          mediaType: 'image',
          downloadStatus: kMediaDownloadStatusPending,
          downloadRetryCount: 2,
          contentHash: 'a' * 64,
          encryptionKeyBase64: base64Encode(List.filled(32, 1)),
          encryptionNonce: base64Encode(List.filled(12, 2)),
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          createdAt: '2026-10-20T00:00:00Z',
        );
        await fixture.repo.saveAttachment(attachment, owner: owner);
        final bridge = FakeBridge(
          initialResponses: {
            'media:download': {
              'ok': false,
              'errorCode': 'MEDIA_ERROR',
              'errorMessage': 'connection closed (remote): transport error',
            },
          },
        );
        final result = await downloadMedia(
          bridge: bridge,
          mediaAttachmentRepo: fixture.repo,
          mediaFileManager: FakeMediaFileManager(),
          attachment: attachment,
          contactPeerId: owner == MediaOwnerLane.direct ? 'sender' : 'group-1',
          owner: owner,
          messageRepo: fixture.messageRepo,
          groupMessageRepo: owner == MediaOwnerLane.group ? groupParents : null,
          enforceGroupMediaPolicy: owner == MediaOwnerLane.group,
        );
        expect(result, isNull);
        final persisted = (await fixture.repo.getAttachmentsForMessage(
          'transport-budget',
          owner: owner,
        )).single;
        expect(
          persisted.downloadRetryCount,
          2,
          reason: 'network did not consume the final nontransport attempt',
        );
        expect(
          persisted.downloadStatus,
          owner == MediaOwnerLane.direct
              ? kMediaDownloadStatusRetryWaiting
              : kMediaDownloadStatusPending,
        );
        expect(
          bridge.commandLog.where((cmd) => cmd == 'media:download'),
          hasLength(owner == MediaOwnerLane.direct ? 3 : 1),
        );
      },
    );
  }
}
