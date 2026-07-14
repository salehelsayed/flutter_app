// Post-move behavior on the NEW phone, starting from imported state.
//
// The Move Account importer copies rows verbatim (groups, group_keys,
// group_inbox_cursors, media_attachments) and writes media files to the
// documents root. These tests pin the three behaviors that would silently
// regress if migrated state were dropped or mishandled on the new phone:
//   1. group rejoin uses the IMPORTED key material and generation,
//   2. the offline-inbox drain opens with the IMPORTED cursor (no restart
//      from scratch → no duplicate/skipped backlog),
//   3. opening imported conversations resolves media LOCALLY — zero
//      `media:download` relay commands (the relay-free product rule).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/application/download_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/application/rejoin_group_topics_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../shared/fakes/in_memory_message_repository.dart';

void main() {
  late List<Map<String, dynamic>> flowEvents;

  setUp(() {
    flowEvents = <Map<String, dynamic>>[];
    debugSetFlowEventSink(flowEvents.add);
  });

  tearDown(() {
    debugSetFlowEventSink(null);
  });

  group('post-import group rejoin', () {
    test('rejoins with the imported key material and generation', () async {
      final bridge = FakeBridge();
      final groupRepo = InMemoryGroupRepository();
      final importedJoinedAt = DateTime.utc(2026, 5, 1);
      await groupRepo.saveGroup(
        GroupModel(
          id: 'imported-group-1',
          name: 'Imported group',
          type: GroupType.chat,
          topicName: 'topic-imported-group-1',
          createdAt: importedJoinedAt,
          createdBy: 'old-peer',
          myRole: GroupRole.admin,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'imported-group-1',
          peerId: 'old-peer',
          username: 'alice',
          role: MemberRole.admin,
          publicKey: 'public',
          joinedAt: importedJoinedAt,
        ),
      );
      // Exactly what the importer delivers: the group_keys row verbatim,
      // including the secure-store reference and its generation.
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'imported-group-1',
          keyGeneration: 7,
          encryptedKey: 'secure:group_key_material:imported-group-1:7',
          createdAt: importedJoinedAt,
        ),
      );

      final result = await rejoinGroupTopics(
        bridge: bridge,
        groupRepo: groupRepo,
      );

      expect(result.joinedGroupCount, 1);
      expect(result.skippedNoKeyCount, 0);
      expect(result.errorCount, 0);

      final joins = bridge.sentMessages
          .map((message) => jsonDecode(message) as Map<String, dynamic>)
          .where((message) => message['cmd'] == 'group:join')
          .toList(growable: false);
      expect(joins, hasLength(1));
      final payload = joins.single['payload'] as Map<String, dynamic>;
      expect(payload['groupId'], 'imported-group-1');
      expect(
        payload['groupKey'],
        'secure:group_key_material:imported-group-1:7',
        reason: 'rejoin must use the migrated key material verbatim',
      );
      expect(
        payload['keyEpoch'],
        7,
        reason: 'rejoin must keep the migrated key generation',
      );
    });
  });

  group('post-import offline-inbox drain', () {
    test('first relay request carries the imported cursor', () async {
      final bridge = FakeBridge();
      bridge.responses['group:inboxRetrieveCursor'] = {
        'ok': true,
        'messages': <Object>[],
        'cursor': '',
      };
      final groupRepo = InMemoryGroupRepository();
      await groupRepo.saveGroup(
        GroupModel(
          id: 'imported-group-1',
          name: 'Imported group',
          type: GroupType.chat,
          topicName: 'topic-imported-group-1',
          createdAt: DateTime.utc(2026, 5, 1),
          createdBy: 'old-peer',
          myRole: GroupRole.admin,
        ),
      );
      final msgRepo = InMemoryGroupMessageRepository();
      // Seed the cursor the way the importer leaves it: persisted per group.
      await msgRepo.runInboxPageTransaction(
        groupId: 'imported-group-1',
        nextCursor: 'imported-cursor-token',
        apply: (_) async {},
      );

      await drainGroupOfflineInboxForGroup(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'imported-group-1',
        retentionNowUtc: DateTime.utc(2026, 6, 10, 12),
      );

      final retrieves = bridge.sentMessages
          .map((message) => jsonDecode(message) as Map<String, dynamic>)
          .where((message) => message['cmd'] == 'group:inboxRetrieveCursor')
          .toList(growable: false);
      expect(retrieves, isNotEmpty);
      final firstPayload = retrieves.first['payload'] as Map<String, dynamic>;
      expect(firstPayload['groupId'], 'imported-group-1');
      expect(
        firstPayload['cursor'],
        'imported-cursor-token',
        reason:
            'the drain must resume from the migrated cursor, not restart '
            'from scratch (which would re-pull or skip backlog)',
      );
    });
  });

  group('post-import media is relay-free', () {
    late Directory tempDir;
    late List<Duration> savedProbeDelays;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('post_import_media_');
      savedProbeDelays = debugGroupMediaDownloadPostCommitProbeDelays;
      debugGroupMediaDownloadPostCommitProbeDelays = const [];
    });

    tearDown(() async {
      debugGroupMediaDownloadPostCommitProbeDelays = savedProbeDelays;
      await tempDir.delete(recursive: true);
    });

    test(
      'imported attachments resolve locally with zero media:download',
      () async {
        final bridge = FakeBridge();
        final repo = InMemoryMediaAttachmentRepository();
        final messageRepo = InMemoryMessageRepository();
        final groupMessageRepo = InMemoryGroupMessageRepository();
        final fileManager = _ImportedDocsFileManager(tempDir.path);

        // Exactly the import outcome: rows with relative paths + status done,
        // and the bytes present under the documents root.
        const oneToOnePath = 'media/peer-bob/blob-imported.jpg';
        await _writeRelative(tempDir, oneToOnePath, 'image-bytes');
        final oneToOne = MediaAttachment(
          id: 'blob-imported',
          messageId: 'message-1',
          mime: 'image/jpeg',
          size: 'image-bytes'.length,
          mediaType: 'image',
          localPath: oneToOnePath,
          downloadStatus: 'done',
          createdAt: '2026-06-10T08:00:00.000Z',
        );
        await repo.saveAttachment(oneToOne, owner: MediaOwnerLane.direct);
        await messageRepo.saveMessage(
          const ConversationMessage(
            id: 'message-1',
            contactPeerId: 'peer-bob',
            senderPeerId: 'peer-bob',
            text: '',
            timestamp: '2026-06-10T08:00:00.000Z',
            status: 'delivered',
            isIncoming: true,
            createdAt: '2026-06-10T08:00:00.000Z',
          ),
        );

        const groupPath = 'media/imported-group-1/blob-group.jpg';
        await _writeRelative(tempDir, groupPath, 'group-image-bytes');
        final groupAttachment = MediaAttachment(
          id: 'blob-group',
          messageId: 'group-message-1',
          mime: 'image/jpeg',
          size: 'group-image-bytes'.length,
          mediaType: 'image',
          localPath: groupPath,
          downloadStatus: 'done',
          createdAt: '2026-06-10T08:00:00.000Z',
          contentHash: 'a' * 64,
          encryptionKeyBase64: 'imported-media-key',
          encryptionNonce: 'imported-nonce',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        );
        await repo.saveAttachment(groupAttachment, owner: MediaOwnerLane.group);
        await groupMessageRepo.saveMessage(
          GroupMessage(
            id: 'group-message-1',
            groupId: 'imported-group-1',
            senderPeerId: 'peer-bob',
            senderUsername: 'Bob',
            text: '',
            timestamp: DateTime.utc(2026, 6, 10, 8),
            status: 'delivered',
            isIncoming: true,
            createdAt: DateTime.utc(2026, 6, 10, 8),
          ),
        );

        await downloadMedia(
          bridge: bridge,
          mediaAttachmentRepo: repo,
          mediaFileManager: fileManager,
          attachment: oneToOne,
          contactPeerId: 'peer-bob',
          owner: MediaOwnerLane.direct,
          messageRepo: messageRepo,
        );
        await downloadMedia(
          bridge: bridge,
          mediaAttachmentRepo: repo,
          mediaFileManager: fileManager,
          attachment: groupAttachment,
          contactPeerId: 'imported-group-1',
          owner: MediaOwnerLane.group,
          groupMessageRepo: groupMessageRepo,
          enforceGroupMediaPolicy: true,
        );

        expect(
          bridge.commandLog.where((cmd) => cmd == 'media:download'),
          isEmpty,
          reason: 'imported media must open locally, never from the relay',
        );
        expect(
          bridge.commandLog.where((cmd) => cmd == 'blob:decrypt'),
          isEmpty,
          reason: 'a present plaintext must not trigger companion restore',
        );
        expect(
          (await repo.getAttachmentById('blob-imported'))?.downloadStatus,
          'done',
        );
        expect(
          (await repo.getAttachmentById('blob-group'))?.downloadStatus,
          'done',
          reason: 'group policy checks must not quarantine healthy imports',
        );
        expect(
          flowEvents.where(
            (event) => event['event'] == 'MEDIA_DOWNLOAD_SKIP_LOCAL_READY',
          ),
          hasLength(2),
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
  final file = File('${root.path}/$relativePath');
  await file.parent.create(recursive: true);
  await file.writeAsString(contents, flush: true);
}

/// Maps relative stored paths under a fixed documents root — the shape the
/// importer produces (relative `media/<peerOrGroup>/<blob><ext>` paths).
class _ImportedDocsFileManager extends MediaFileManager {
  final String basePath;

  _ImportedDocsFileManager(this.basePath);

  @override
  Future<String> localPathForAttachment({
    required String contactPeerId,
    required String blobId,
    required String mime,
  }) async {
    const mimeToExt = {'image/jpeg': '.jpg', 'image/png': '.png'};
    return '$basePath/$contactPeerId/$blobId${mimeToExt[mime] ?? ''}';
  }

  @override
  Future<String> resolveStoredPath(String storedPath) async {
    if (storedPath.startsWith('/')) {
      return storedPath;
    }
    return '$basePath/$storedPath';
  }
}
