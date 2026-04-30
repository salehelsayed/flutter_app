import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_app/core/constants/retry_constants.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/group_media_size_policy.dart';
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

const _validContentHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

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
  int size = 2048,
  int? uploadRetryCount,
}) {
  return MediaAttachment(
    id: id,
    messageId: messageId,
    mime: mime,
    size: size,
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
  int size = 4096,
}) {
  return MediaAttachment(
    id: id,
    messageId: messageId,
    mime: mime,
    size: size,
    mediaType: MediaAttachment.mediaTypeFromMime(mime),
    localPath: 'media/group-1/$id.jpg',
    downloadStatus: 'done',
    contentHash: _validContentHash,
    encryptionKeyBase64: 'key-$id',
    encryptionNonce: 'nonce-$id',
    encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
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
        peerId: 'peer-admin',
        username: 'Admin',
        role: MemberRole.admin,
        publicKey: 'pk-admin',
        joinedAt: DateTime.utc(2026, 1, 1),
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
      'MD-012 quarantined download failures are not picked up by incomplete upload retry',
      () async {
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: 'msg-md012-download-only',
            groupId: 'group-1',
            senderPeerId: 'peer-2',
            senderUsername: 'Bob',
            text: 'download repair only',
            timestamp: DateTime.utc(2026, 1, 1),
            status: 'delivered',
            isIncoming: true,
            createdAt: DateTime.utc(2026, 1, 1),
          ),
        );
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: 'msg-md012-upload-owner',
            groupId: 'group-1',
            senderPeerId: 'peer-admin',
            senderUsername: 'Admin',
            text: 'upload retry owner',
            timestamp: DateTime.utc(2026, 1, 1),
            status: 'failed',
            isIncoming: false,
            createdAt: DateTime.utc(2026, 1, 1),
          ),
        );
        await mediaRepo.saveAttachment(
          _doneAttachment(
            id: 'download-integrity-failed',
            messageId: 'msg-md012-download-only',
          ).copyWith(downloadStatus: kMediaDownloadStatusIntegrityFailed),
        );
        await mediaRepo.saveAttachment(
          _doneAttachment(
            id: 'download-transient-failed',
            messageId: 'msg-md012-download-only',
          ).copyWith(downloadStatus: 'failed'),
        );
        await mediaRepo.saveAttachment(
          _pendingAttachment(
            id: 'upload-pending-md012',
            messageId: 'msg-md012-upload-owner',
            localPath: 'pending_uploads/msg-md012-upload-owner/blob.jpg',
          ),
        );
        uploadFn.willReturn(
          _doneAttachment(
            id: 'upload-pending-md012',
            messageId: 'msg-md012-upload-owner',
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
        expect(uploadFn.lastBlobId, 'upload-pending-md012');
        final downloadOnly = await mediaRepo.getAttachmentsForMessage(
          'msg-md012-download-only',
        );
        expect(
          downloadOnly.map((attachment) => attachment.id),
          unorderedEquals([
            'download-integrity-failed',
            'download-transient-failed',
          ]),
        );
        expect(
          downloadOnly.map((attachment) => attachment.downloadStatus),
          unorderedEquals([kMediaDownloadStatusIntegrityFailed, 'failed']),
        );
        expect(bridge.commandLog, contains('group:publish'));
        expect(bridge.commandLog, contains('group:inboxStore'));
      },
    );

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
        final publishMsg = bridge.sentMessages.firstWhere(
          (raw) =>
              (jsonDecode(raw) as Map<String, dynamic>)['cmd'] ==
              'group:publish',
        );
        expect(publishMsg, contains('"contentHash":"$_validContentHash"'));
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
      'terminalizes dangerous MIME pending attachments without upload or resend',
      () async {
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: 'msg-dangerous-mime',
            groupId: 'group-1',
            senderPeerId: 'peer-admin',
            senderUsername: 'Admin',
            text: 'Blocked media',
            timestamp: DateTime.utc(2026, 1, 1),
            status: 'failed',
            isIncoming: false,
            createdAt: DateTime.utc(2026, 1, 1),
          ),
        );
        await mediaRepo.saveAttachment(
          _pendingAttachment(
            id: 'pending-dangerous',
            messageId: 'msg-dangerous-mime',
            localPath: 'pending_uploads/msg-dangerous-mime/payload.pdf',
            mime: 'application/pdf',
          ),
        );
        uploadFn.willReturn(
          _doneAttachment(
            id: 'pending-dangerous',
            messageId: 'msg-dangerous-mime',
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

        final attachments = await mediaRepo.getAttachmentsForMessage(
          'msg-dangerous-mime',
        );
        expect(attachments.single.downloadStatus, 'upload_failed');
      },
    );

    test(
      'MD-011 retry excludes a removed member from media ACLs and inbox recipients',
      () async {
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-removed',
            username: 'Removed',
            role: MemberRole.writer,
            publicKey: 'pk-removed',
            joinedAt: DateTime.utc(2026, 1, 1),
          ),
        );
        await groupRepo.removeMember('group-1', 'peer-removed');
        expect(
          (await groupRepo.getMembers(
            'group-1',
          )).map((member) => member.peerId),
          unorderedEquals(['peer-admin', 'peer-2']),
        );

        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: 'msg-md011-retry',
            groupId: 'group-1',
            senderPeerId: 'peer-admin',
            senderUsername: 'Admin',
            text: 'Retry future media',
            timestamp: DateTime.utc(2026, 1, 1, 12),
            status: 'failed',
            isIncoming: false,
            createdAt: DateTime.utc(2026, 1, 1, 12),
          ),
        );
        await mediaRepo.saveAttachment(
          _pendingAttachment(
            id: 'pending-md011-retry',
            messageId: 'msg-md011-retry',
            localPath: 'pending_uploads/msg-md011-retry/photo.jpg',
          ),
        );
        uploadFn.willReturn(
          _doneAttachment(
            id: 'pending-md011-retry',
            messageId: 'msg-md011-retry',
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
        expect(uploadFn.lastAllowedPeers, unorderedEquals(['peer-2']));
        expect(uploadFn.lastAllowedPeers, isNot(contains('peer-admin')));
        expect(uploadFn.lastAllowedPeers, isNot(contains('peer-removed')));

        final inboxPayload = bridge.sentMessages
            .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
            .where((message) => message['cmd'] == 'group:inboxStore')
            .map((message) => message['payload'] as Map<String, dynamic>)
            .last;
        expect(
          (inboxPayload['recipientPeerIds'] as List<dynamic>).cast<String>(),
          unorderedEquals(['peer-2']),
        );
        final replayEnvelope =
            jsonDecode(inboxPayload['message'] as String)
                as Map<String, dynamic>;
        final replayPlaintext =
            jsonDecode(replayEnvelope['ciphertext'] as String)
                as Map<String, dynamic>;
        expect(replayPlaintext['messageId'], 'msg-md011-retry');
        expect(
          ((replayPlaintext['media'] as List<dynamic>).single
              as Map<String, dynamic>)['id'],
          'pending-md011-retry',
        );
      },
    );

    test(
      'terminalizes oversized pending attachments without upload or resend',
      () async {
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: 'msg-oversized-pending',
            groupId: 'group-1',
            senderPeerId: 'peer-admin',
            senderUsername: 'Admin',
            text: 'Blocked media',
            timestamp: DateTime.utc(2026, 1, 1),
            status: 'failed',
            isIncoming: false,
            createdAt: DateTime.utc(2026, 1, 1),
          ),
        );
        await mediaRepo.saveAttachment(
          _pendingAttachment(
            id: 'pending-oversized',
            messageId: 'msg-oversized-pending',
            localPath: 'pending_uploads/msg-oversized-pending/photo.jpg',
            size: kGroupMediaPerAttachmentLimitBytes + 1,
          ),
        );
        uploadFn.willReturn(
          _doneAttachment(
            id: 'pending-oversized',
            messageId: 'msg-oversized-pending',
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
        expect(
          (await mediaRepo.getAttachmentsForMessage(
            'msg-oversized-pending',
          )).single.downloadStatus,
          'upload_failed',
        );
      },
    );

    test(
      'aborts final resend when done plus pending attachments exceed total limit',
      () async {
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: 'msg-total-oversized-retry',
            groupId: 'group-1',
            senderPeerId: 'peer-admin',
            senderUsername: 'Admin',
            text: 'Blocked total media',
            timestamp: DateTime.utc(2026, 1, 1),
            status: 'failed',
            isIncoming: false,
            createdAt: DateTime.utc(2026, 1, 1),
          ),
        );
        await mediaRepo.saveAttachment(
          _doneAttachment(
            id: 'done-total-boundary',
            messageId: 'msg-total-oversized-retry',
            size: kGroupMediaTotalMessageLimitBytes,
          ),
        );
        await mediaRepo.saveAttachment(
          _pendingAttachment(
            id: 'pending-total-extra',
            messageId: 'msg-total-oversized-retry',
            size: 1,
          ),
        );
        uploadFn.willReturn(
          _doneAttachment(
            id: 'pending-total-extra',
            messageId: 'msg-total-oversized-retry',
            size: 1,
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
        expect(
          (await mediaRepo.getAttachmentsForMessage(
                'msg-total-oversized-retry',
              ))
              .where((attachment) => attachment.id == 'pending-total-extra')
              .single
              .downloadStatus,
          'upload_failed',
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
          (raw) =>
              (jsonDecode(raw) as Map<String, dynamic>)['cmd'] ==
              'group:publish',
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
