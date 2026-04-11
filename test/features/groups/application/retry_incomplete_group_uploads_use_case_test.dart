import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_app/core/constants/retry_constants.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/groups/application/retry_incomplete_group_uploads_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';
import '../../conversation/application/helpers/fake_upload_media_fn.dart';

Future<List<Map<String, dynamic>>> captureFlowEvents(
  Future<void> Function() action,
) async {
  final printed = <String>[];
  final previousLogging = flowEventLoggingEnabled;
  final originalDebugPrint = debugPrint;
  flowEventLoggingEnabled = true;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) {
      printed.add(message);
    }
  };
  try {
    await action();
  } finally {
    debugPrint = originalDebugPrint;
    flowEventLoggingEnabled = previousLogging;
  }

  return printed
      .where((line) => line.startsWith('[FLOW] '))
      .map(
        (line) =>
            jsonDecode(line.substring('[FLOW] '.length))
                as Map<String, dynamic>,
      )
      .toList();
}

MediaAttachment _pendingAttachment({
  required String id,
  required String messageId,
  String localPath = 'pending_uploads/msg-1/blob.jpg',
  String mime = 'image/jpeg',
  int? uploadRetryCount,
}) {
  return MediaAttachment(
    id: id,
    messageId: messageId,
    mime: mime,
    size: 2048,
    mediaType: MediaAttachment.mediaTypeFromMime(mime),
    localPath: localPath,
    downloadStatus: 'upload_pending',
    createdAt: DateTime.now().toUtc().toIso8601String(),
    uploadRetryCount: uploadRetryCount,
  );
}

MediaAttachment _doneAttachment({
  required String id,
  required String messageId,
  String mime = 'image/jpeg',
}) {
  return MediaAttachment(
    id: id,
    messageId: messageId,
    mime: mime,
    size: 4096,
    mediaType: MediaAttachment.mediaTypeFromMime(mime),
    localPath: 'media/group-1/$id.jpg',
    downloadStatus: 'done',
    createdAt: DateTime.now().toUtc().toIso8601String(),
  );
}

void main() {
  late InMemoryGroupRepository groupRepo;
  late InMemoryGroupMessageRepository groupMsgRepo;
  late InMemoryMediaAttachmentRepository mediaRepo;
  late FakeBridge bridge;
  late FakeP2PService p2pService;
  late FakeIdentityRepository identityRepo;
  late FakeUploadMediaFn uploadFn;
  late FakeMediaFileManager mediaFileManager;

  setUp(() async {
    groupRepo = InMemoryGroupRepository();
    groupMsgRepo = InMemoryGroupMessageRepository();
    mediaRepo = InMemoryMediaAttachmentRepository();
    bridge = FakeBridge(
      initialResponses: {
        'group:publish': {'ok': true, 'messageId': 'msg-1', 'topicPeers': 1},
        'group:inboxStore': {'ok': true},
      },
    );
    p2pService = FakeP2PService(
      initialState: const NodeState(
        isStarted: true,
        peerId: 'peer-admin',
        circuitAddresses: ['/p2p-circuit/addr1'],
      ),
      storeInInboxResult: true,
    );
    identityRepo = FakeIdentityRepository()
      ..seed(
        FakeIdentityRepository.makeIdentity(
          peerId: 'peer-admin',
          publicKey: 'pk-admin',
          privateKey: 'sk-admin',
        ),
      );
    uploadFn = FakeUploadMediaFn();
    mediaFileManager = FakeMediaFileManager();

    await groupRepo.saveGroup(
      GroupModel(
        id: 'group-1',
        name: 'Group',
        type: GroupType.chat,
        topicName: 'topic-1',
        createdAt: DateTime.utc(2026, 1, 1),
        createdBy: 'peer-admin',
        myRole: GroupRole.admin,
      ),
    );
    await groupRepo.saveKey(
      GroupKeyInfo(
        groupId: 'group-1',
        keyGeneration: 0,
        encryptedKey: 'encrypted',
        createdAt: DateTime.utc(2026, 1, 1),
      ),
    );
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-2',
        username: 'Bob',
        role: MemberRole.writer,
        publicKey: 'pk-2',
        joinedAt: DateTime.utc(2026, 1, 1),
      ),
    );
  });

  group('retryIncompleteGroupUploads', () {
    test('returns 0 when no upload_pending attachments exist', () async {
      final count = await retryIncompleteGroupUploads(
        groupRepo: groupRepo,
        groupMsgRepo: groupMsgRepo,
        mediaAttachmentRepo: mediaRepo,
        bridge: bridge,
        p2pService: p2pService,
        identityRepo: identityRepo,
        uploadMediaFn: uploadFn.call,
        mediaFileManager: mediaFileManager,
      );

      expect(count, 0);
    });

    test(
      'reuploads only group upload_pending attachments and uses blobId',
      () async {
        final deletedDirs = <String>[];
        mediaFileManager.onDeletePendingUploadDir = deletedDirs.add;

        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: 'msg-1',
            groupId: 'group-1',
            senderPeerId: 'peer-admin',
            senderUsername: 'Admin',
            text: 'Hello',
            timestamp: DateTime.utc(2026, 1, 1),
            status: 'failed',
            isIncoming: false,
            createdAt: DateTime.utc(2026, 1, 1),
          ),
        );
        await mediaRepo.saveAttachment(
          _doneAttachment(id: 'done-1', messageId: 'msg-1'),
        );
        await mediaRepo.saveAttachment(
          _pendingAttachment(id: 'pending-1', messageId: 'msg-1'),
        );
        await mediaRepo.saveAttachment(
          _pendingAttachment(id: 'dm-1', messageId: 'dm-1'),
        );
        uploadFn.willReturn(
          _doneAttachment(id: 'pending-1', messageId: 'msg-1'),
        );

        final count = await retryIncompleteGroupUploads(
          groupRepo: groupRepo,
          groupMsgRepo: groupMsgRepo,
          mediaAttachmentRepo: mediaRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          uploadMediaFn: uploadFn.call,
          mediaFileManager: mediaFileManager,
        );

        expect(count, 1);
        expect(uploadFn.callCount, 1);
        expect(uploadFn.lastBlobId, 'pending-1');
        expect(
          uploadFn.lastAllowedPeers,
          equals(['peer-2']),
          reason: 'allowedPeers must come from group members',
        );
        expect(
          uploadFn.lastLocalPath,
          endsWith('test_docs/pending_uploads/msg-1/blob.jpg'),
        );
        expect(bridge.commandLog, contains('group:publish'));
        expect(bridge.commandLog, contains('group:inboxStore'));
        expect(deletedDirs, contains('msg-1'));
        expect(
          (await mediaRepo.getAttachmentsForMessage(
            'msg-1',
          )).every((a) => a.downloadStatus == 'done'),
          isTrue,
        );
        expect(
          (await mediaRepo.getUploadPendingAttachments()).any(
            (a) => a.messageId == 'dm-1',
          ),
          isTrue,
          reason: '1:1 upload_pending rows must be skipped',
        );
      },
    );

    test(
      'reuploads only pending GIF attachments while preserving done JPEG siblings',
      () async {
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: 'msg-gif-1',
            groupId: 'group-1',
            senderPeerId: 'peer-admin',
            senderUsername: 'Admin',
            text: '',
            timestamp: DateTime.utc(2026, 1, 1),
            status: 'failed',
            isIncoming: false,
            createdAt: DateTime.utc(2026, 1, 1),
          ),
        );
        await mediaRepo.saveAttachment(
          _doneAttachment(id: 'done-jpeg', messageId: 'msg-gif-1'),
        );
        await mediaRepo.saveAttachment(
          _pendingAttachment(
            id: 'pending-gif',
            messageId: 'msg-gif-1',
            localPath: 'pending_uploads/msg-gif-1/funny.gif',
            mime: 'image/gif',
          ),
        );
        uploadFn.willReturn(
          _doneAttachment(
            id: 'pending-gif',
            messageId: 'msg-gif-1',
            mime: 'image/gif',
          ),
        );

        final count = await retryIncompleteGroupUploads(
          groupRepo: groupRepo,
          groupMsgRepo: groupMsgRepo,
          mediaAttachmentRepo: mediaRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          uploadMediaFn: uploadFn.call,
          mediaFileManager: mediaFileManager,
        );

        expect(count, 1);
        expect(uploadFn.callCount, 1);
        expect(uploadFn.lastMime, 'image/gif');
        expect(uploadFn.lastBlobId, 'pending-gif');
        final publishMsg = bridge.sentMessages.firstWhere(
          (raw) => (jsonDecode(raw) as Map<String, dynamic>)['cmd'] == 'group:publish',
        );
        expect(publishMsg, contains('"mime":"image/gif"'));
      },
    );

    test(
      'emits RETRY_INCOMPLETE_GROUP_UPLOADS_TIMING with attachment and message counts',
      () async {
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: 'msg-1',
            groupId: 'group-1',
            senderPeerId: 'peer-admin',
            senderUsername: 'Admin',
            text: 'Hello',
            timestamp: DateTime.utc(2026, 1, 1),
            status: 'failed',
            isIncoming: false,
            createdAt: DateTime.utc(2026, 1, 1),
          ),
        );
        await mediaRepo.saveAttachment(
          _doneAttachment(id: 'done-1', messageId: 'msg-1'),
        );
        await mediaRepo.saveAttachment(
          _pendingAttachment(id: 'pending-1', messageId: 'msg-1'),
        );
        uploadFn.willReturn(
          _doneAttachment(id: 'pending-1', messageId: 'msg-1'),
        );

        final events = await captureFlowEvents(() async {
          await retryIncompleteGroupUploads(
            groupRepo: groupRepo,
            groupMsgRepo: groupMsgRepo,
            mediaAttachmentRepo: mediaRepo,
            bridge: bridge,
            p2pService: p2pService,
            identityRepo: identityRepo,
            uploadMediaFn: uploadFn.call,
            mediaFileManager: mediaFileManager,
          );
        });

        final timing = events.lastWhere(
          (event) => event['event'] == 'RETRY_INCOMPLETE_GROUP_UPLOADS_TIMING',
        );
        expect(timing['details']['outcome'], 'complete');
        expect(timing['details']['attachmentCount'], 1);
        expect(timing['details']['messageCount'], 1);
        expect(timing['details']['succeeded'], 1);
        expect(timing['details']['elapsedMs'], isA<int>());
      },
    );

    test(
      'transient failure increments retry count and terminal state at max',
      () async {
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: 'msg-2',
            groupId: 'group-1',
            senderPeerId: 'peer-admin',
            senderUsername: 'Admin',
            text: 'Hello',
            timestamp: DateTime.utc(2026, 1, 1),
            status: 'failed',
            isIncoming: false,
            createdAt: DateTime.utc(2026, 1, 1),
          ),
        );
        await mediaRepo.saveAttachment(
          _pendingAttachment(id: 'pending-2', messageId: 'msg-2'),
        );
        uploadFn.willReturn(null);

        final first = await retryIncompleteGroupUploads(
          groupRepo: groupRepo,
          groupMsgRepo: groupMsgRepo,
          mediaAttachmentRepo: mediaRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          uploadMediaFn: uploadFn.call,
          mediaFileManager: mediaFileManager,
        );
        expect(first, 0);
        expect(
          (await mediaRepo.getUploadPendingAttachments())
              .single
              .uploadRetryCount,
          1,
        );

        await mediaRepo.saveAttachment(
          _pendingAttachment(
            id: 'pending-2',
            messageId: 'msg-2',
            uploadRetryCount: kMaxUploadRetries - 1,
          ),
        );

        final second = await retryIncompleteGroupUploads(
          groupRepo: groupRepo,
          groupMsgRepo: groupMsgRepo,
          mediaAttachmentRepo: mediaRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          uploadMediaFn: uploadFn.call,
          mediaFileManager: mediaFileManager,
        );

        expect(second, 0);
        expect(
          (await mediaRepo.getAttachmentsForMessage(
            'msg-2',
          )).single.downloadStatus,
          'upload_failed',
        );
      },
    );

    test(
      'skips retry work when upload_pending attachments have no parent group message row',
      () async {
        await mediaRepo.saveAttachment(
          _pendingAttachment(
            id: 'pending-missing-parent',
            messageId: 'msg-404',
          ),
        );

        final count = await retryIncompleteGroupUploads(
          groupRepo: groupRepo,
          groupMsgRepo: groupMsgRepo,
          mediaAttachmentRepo: mediaRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          uploadMediaFn: uploadFn.call,
          mediaFileManager: mediaFileManager,
        );

        expect(count, 0);
        expect(uploadFn.callCount, 0);
        expect(bridge.commandLog, isNot(contains('group:publish')));
        expect(bridge.commandLog, isNot(contains('group:inboxStore')));

        final pending = await mediaRepo.getUploadPendingAttachments();
        expect(pending, hasLength(1));
        expect(pending.single.id, 'pending-missing-parent');
        expect(pending.single.messageId, 'msg-404');
        expect(pending.single.downloadStatus, 'upload_pending');
      },
    );

    test(
      'skips the final group send when the parent row is deleted after uploads complete',
      () async {
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: 'msg-late-delete',
            groupId: 'group-1',
            senderPeerId: 'peer-admin',
            senderUsername: 'Admin',
            text: 'Hello',
            timestamp: DateTime.utc(2026, 1, 1),
            status: 'failed',
            isIncoming: false,
            createdAt: DateTime.utc(2026, 1, 1),
          ),
        );
        await mediaRepo.saveAttachment(
          _pendingAttachment(
            id: 'pending-late-delete',
            messageId: 'msg-late-delete',
          ),
        );
        mediaRepo.onSaveAttachment = (attachment) {
          if (attachment.messageId == 'msg-late-delete' &&
              attachment.downloadStatus == 'done') {
            groupMsgRepo.deleteMessage('msg-late-delete');
          }
        };
        uploadFn.willReturn(
          _doneAttachment(
            id: 'pending-late-delete',
            messageId: 'msg-late-delete',
          ),
        );

        final count = await retryIncompleteGroupUploads(
          groupRepo: groupRepo,
          groupMsgRepo: groupMsgRepo,
          mediaAttachmentRepo: mediaRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          uploadMediaFn: uploadFn.call,
          mediaFileManager: mediaFileManager,
        );

        expect(count, 0);
        expect(await groupMsgRepo.getMessage('msg-late-delete'), isNull);
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:publish'),
          isEmpty,
          reason: 'late-send guard must suppress the final group send',
        );
      },
    );
  });
}
