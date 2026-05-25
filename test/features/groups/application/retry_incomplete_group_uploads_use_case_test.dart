import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/constants/retry_constants.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
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
const _retryJpegBytes = <int>[0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10];
const _retryPdfBytes = <int>[0x25, 0x50, 0x44, 0x46, 0x2d, 0x31, 0x2e, 0x37];
const _retryGifBytes = <int>[0x47, 0x49, 0x46, 0x38, 0x39, 0x61];

String _retryFixturePath(String localPath) {
  if (localPath.startsWith('/')) return localPath;
  return '${Directory.systemTemp.path}/test_docs/$localPath';
}

List<int> _retryFixtureBytesForMime(String mime) {
  return switch (mime) {
    'image/gif' => _retryGifBytes,
    'application/pdf' => _retryPdfBytes,
    _ => _retryJpegBytes,
  };
}

void _writeRetryFixtureFile({
  required String localPath,
  required String mime,
  List<int>? bytes,
}) {
  final file = File(_retryFixturePath(localPath));
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes ?? _retryFixtureBytesForMime(mime));
}

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
  _writeRetryFixtureFile(localPath: localPath, mime: mime);
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
      'returns 0 for overlapping same-isolate retry while first upload is in flight',
      () async {
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: 'msg-concurrent-retry',
            groupId: 'group-1',
            senderPeerId: 'peer-admin',
            senderUsername: 'Admin',
            text: 'Concurrent retry',
            timestamp: DateTime.utc(2026, 1, 1),
            status: 'failed',
            isIncoming: false,
            createdAt: DateTime.utc(2026, 1, 1),
          ),
        );
        await mediaRepo.saveAttachment(
          _pendingAttachment(
            id: 'pending-concurrent-retry',
            messageId: 'msg-concurrent-retry',
            localPath: 'pending_uploads/msg-concurrent-retry/photo.jpg',
          ),
        );

        final uploadStarted = Completer<void>();
        final allowUpload = Completer<void>();
        var uploadCallCount = 0;
        Future<MediaAttachment?> blockingUpload({
          required Bridge bridge,
          required String localFilePath,
          required String mime,
          required String recipientPeerId,
          MediaFileManager? mediaFileManager,
          int? width,
          int? height,
          int? durationMs,
          List<double>? waveform,
          List<String>? allowedPeers,
          String? blobId,
        }) async {
          uploadCallCount++;
          if (!uploadStarted.isCompleted) {
            uploadStarted.complete();
          }
          await allowUpload.future;
          return _doneAttachment(
            id: blobId ?? 'pending-concurrent-retry',
            messageId: 'msg-concurrent-retry',
          );
        }

        final firstRetry = retryIncompleteGroupUploads(
          groupRepo: groupRepo,
          groupMsgRepo: groupMsgRepo,
          mediaAttachmentRepo: mediaRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          uploadMediaFn: blockingUpload,
          mediaFileManager: mediaFileManager,
        );
        await uploadStarted.future;

        final secondRetry = retryIncompleteGroupUploads(
          groupRepo: groupRepo,
          groupMsgRepo: groupMsgRepo,
          mediaAttachmentRepo: mediaRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          uploadMediaFn: blockingUpload,
          mediaFileManager: mediaFileManager,
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(uploadCallCount, 1);
        allowUpload.complete();

        expect(await secondRetry, 0);
        expect(await firstRetry, 1);
        expect(uploadCallCount, 1);
        expect(
          bridge.commandLog.where((command) => command == 'group:publish'),
          hasLength(1),
        );
        expect(
          bridge.commandLog.where((command) => command == 'group:inboxStore'),
          hasLength(1),
        );
      },
    );

    test(
      'skips fresh outgoing sending parent before upload or publish',
      () async {
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: 'msg-fresh-sending-parent',
            groupId: 'group-1',
            senderPeerId: 'peer-admin',
            senderUsername: 'Admin',
            text: 'Fresh active send',
            timestamp: DateTime.now().toUtc(),
            status: 'sending',
            isIncoming: false,
            createdAt: DateTime.now().toUtc(),
          ),
        );
        await mediaRepo.saveAttachment(
          _pendingAttachment(
            id: 'pending-fresh-sending-parent',
            messageId: 'msg-fresh-sending-parent',
            localPath: 'pending_uploads/msg-fresh-sending-parent/photo.jpg',
          ),
        );
        uploadFn.willReturn(
          _doneAttachment(
            id: 'pending-fresh-sending-parent',
            messageId: 'msg-fresh-sending-parent',
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
            'msg-fresh-sending-parent',
          )).single.downloadStatus,
          'upload_pending',
        );
      },
    );

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
          equals(['peer-admin', 'peer-2']),
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
      'PL-005 retry upload allowedPeers match active membership at retry time',
      () async {
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-charlie',
            username: 'Charlie',
            role: MemberRole.writer,
            publicKey: 'pk-charlie',
            joinedAt: DateTime.utc(2026, 1, 1, 0, 1),
          ),
        );
        await groupRepo.removeMember('group-1', 'peer-charlie');

        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: 'msg-pl005-retry',
            groupId: 'group-1',
            senderPeerId: 'peer-admin',
            senderUsername: 'Admin',
            text: 'Retry active ACL',
            timestamp: DateTime.utc(2026, 5, 14),
            status: 'failed',
            isIncoming: false,
            createdAt: DateTime.utc(2026, 5, 14),
          ),
        );
        await mediaRepo.saveAttachment(
          _pendingAttachment(
            id: 'pending-pl005-retry',
            messageId: 'msg-pl005-retry',
            localPath: 'pending_uploads/msg-pl005-retry/photo.jpg',
          ),
        );
        uploadFn.willReturn(
          _doneAttachment(
            id: 'pending-pl005-retry',
            messageId: 'msg-pl005-retry',
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
        expect(
          uploadFn.lastAllowedPeers,
          unorderedEquals(['peer-admin', 'peer-2']),
        );
        expect(uploadFn.lastAllowedPeers, isNot(contains('peer-charlie')));
        expect(uploadFn.lastAllowedPeers, isNot(contains('peer-dave')));
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
      'terminalizes octet-stream pending attachments without upload or resend',
      () async {
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: 'msg-octet-mime',
            groupId: 'group-1',
            senderPeerId: 'peer-admin',
            senderUsername: 'Admin',
            text: 'Blocked octet',
            timestamp: DateTime.utc(2026, 1, 1),
            status: 'failed',
            isIncoming: false,
            createdAt: DateTime.utc(2026, 1, 1),
          ),
        );
        await mediaRepo.saveAttachment(
          _pendingAttachment(
            id: 'pending-octet',
            messageId: 'msg-octet-mime',
            localPath: 'pending_uploads/msg-octet-mime/payload.bin',
            mime: 'application/octet-stream',
          ),
        );
        uploadFn.willReturn(
          _doneAttachment(id: 'pending-octet', messageId: 'msg-octet-mime'),
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
        expect(
          (await mediaRepo.getAttachmentsForMessage(
            'msg-octet-mime',
          )).single.downloadStatus,
          'upload_failed',
        );
      },
    );

    test('terminalizes spoofed retry bytes before upload or resend', () async {
      const localPath = 'pending_uploads/msg-spoofed-retry/photo.jpg';
      await groupMsgRepo.saveMessage(
        GroupMessage(
          id: 'msg-spoofed-retry',
          groupId: 'group-1',
          senderPeerId: 'peer-admin',
          senderUsername: 'Admin',
          text: 'Spoofed retry',
          timestamp: DateTime.utc(2026, 1, 1),
          status: 'failed',
          isIncoming: false,
          createdAt: DateTime.utc(2026, 1, 1),
        ),
      );
      await mediaRepo.saveAttachment(
        _pendingAttachment(
          id: 'pending-spoofed-retry',
          messageId: 'msg-spoofed-retry',
          localPath: localPath,
          mime: 'image/jpeg',
        ),
      );
      _writeRetryFixtureFile(
        localPath: localPath,
        mime: 'image/jpeg',
        bytes: _retryPdfBytes,
      );
      uploadFn.willReturn(
        _doneAttachment(
          id: 'pending-spoofed-retry',
          messageId: 'msg-spoofed-retry',
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
      expect(
        (await mediaRepo.getAttachmentsForMessage(
          'msg-spoofed-retry',
        )).single.downloadStatus,
        'upload_failed',
      );
    });

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
        expect(
          uploadFn.lastAllowedPeers,
          unorderedEquals(['peer-admin', 'peer-2']),
        );
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
