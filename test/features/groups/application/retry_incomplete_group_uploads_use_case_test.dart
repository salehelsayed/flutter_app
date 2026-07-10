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
import 'package:flutter_app/core/media/media_owner_lane.dart';
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
const _retryMp4Bytes = <int>[
  0x00,
  0x00,
  0x00,
  0x18,
  0x66,
  0x74,
  0x79,
  0x70,
  0x6d,
  0x70,
  0x34,
  0x32,
  0x00,
  0x00,
  0x00,
  0x00,
];

String _retryFixturePath(String localPath) {
  if (localPath.startsWith('/')) return localPath;
  return '${Directory.systemTemp.path}/test_docs/$localPath';
}

List<int> _retryFixtureBytesForMime(String mime) {
  return switch (mime) {
    'image/gif' => _retryGifBytes,
    'audio/mp4' => _retryMp4Bytes,
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

List<Map<String, dynamic>> _publishedGroupPayloads(FakeBridge bridge) {
  return bridge.sentMessages
      .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
      .where((message) => message['cmd'] == 'group:publish')
      .map(
        (message) => (message['payload'] as Map<String, dynamic>)
            .cast<String, dynamic>(),
      )
      .toList(growable: false);
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
          ), owner: MediaOwnerLane.group,
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
          bool deleteSourceWhenDone = false,
          preparedArtifact,
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
          ), owner: MediaOwnerLane.group,
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
            'msg-fresh-sending-parent', owner: MediaOwnerLane.group,
          )).single.downloadStatus,
          'upload_pending',
        );
      },
    );

    test(
      'GMF-07U incomplete upload retry preserves forwarded identity',
      () async {
        // 236: the SECOND durable re-drive caller. A forwarded parent whose
        // upload never completed re-sends with its ORIGINAL marker, message
        // id, logical delivery id, and timestamp; an ordinary parent stays
        // unmarked. Neither row is reminted.
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: 'msg-fwd-upload',
            groupId: 'group-1',
            senderPeerId: 'peer-admin',
            senderUsername: 'Admin',
            text: 'forwarded upload retry',
            timestamp: DateTime.utc(2026, 1, 1),
            logicalDeliveryId: 'fwd-upload-logical-1',
            status: 'failed',
            isIncoming: false,
            isForwarded: true,
            createdAt: DateTime.utc(2026, 1, 1),
          ),
        );
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: 'msg-ord-upload',
            groupId: 'group-1',
            senderPeerId: 'peer-admin',
            senderUsername: 'Admin',
            text: 'ordinary upload retry',
            timestamp: DateTime.utc(2026, 1, 1, 0, 1),
            logicalDeliveryId: 'ord-upload-logical-1',
            status: 'failed',
            isIncoming: false,
            createdAt: DateTime.utc(2026, 1, 1, 0, 1),
          ),
        );
        await mediaRepo.saveAttachment(
          _pendingAttachment(
            id: 'upload-pending-fwd',
            messageId: 'msg-fwd-upload',
            localPath: 'pending_uploads/msg-fwd-upload/blob.jpg',
          ),
          owner: MediaOwnerLane.group,
        );
        await mediaRepo.saveAttachment(
          _pendingAttachment(
            id: 'upload-pending-ord',
            messageId: 'msg-ord-upload',
            localPath: 'pending_uploads/msg-ord-upload/blob.jpg',
          ),
          owner: MediaOwnerLane.group,
        );
        uploadFn.willReturnForPath(
          await mediaFileManager.resolveStoredPath(
            'pending_uploads/msg-fwd-upload/blob.jpg',
          ),
          _doneAttachment(id: 'upload-pending-fwd', messageId: 'msg-fwd-upload'),
        );
        uploadFn.willReturnForPath(
          await mediaFileManager.resolveStoredPath(
            'pending_uploads/msg-ord-upload/blob.jpg',
          ),
          _doneAttachment(id: 'upload-pending-ord', messageId: 'msg-ord-upload'),
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
        expect(count, 2);

        Map<String, dynamic> publishPayloadFor(String messageId) {
          for (final raw in bridge.sentMessages.reversed) {
            final parsed = jsonDecode(raw) as Map<String, dynamic>;
            if (parsed['cmd'] != 'group:publish') continue;
            final payload = parsed['payload'] as Map<String, dynamic>;
            if (payload['messageId'] == messageId) return payload;
          }
          fail('missing group:publish for $messageId');
        }

        final forwardedPayload = publishPayloadFor('msg-fwd-upload');
        expect(forwardedPayload['isForwarded'], isTrue);
        expect(forwardedPayload['logicalDeliveryId'], 'fwd-upload-logical-1');
        expect(forwardedPayload['timestamp'], '2026-01-01T00:00:00.000Z');
        final ordinaryPayload = publishPayloadFor('msg-ord-upload');
        expect(ordinaryPayload.containsKey('isForwarded'), isFalse);
        expect(ordinaryPayload['logicalDeliveryId'], 'ord-upload-logical-1');

        // In-place identity: no duplicate rows, markers preserved.
        final rows = await groupMsgRepo.getMessagesPage('group-1', limit: 50);
        expect(
          rows.map((row) => row.id).toSet(),
          {'msg-fwd-upload', 'msg-ord-upload'},
        );
        final forwardedRow = await groupMsgRepo.getMessage('msg-fwd-upload');
        expect(forwardedRow!.isForwarded, isTrue);
        expect(forwardedRow.logicalDeliveryId, 'fwd-upload-logical-1');
        final ordinaryRow = await groupMsgRepo.getMessage('msg-ord-upload');
        expect(ordinaryRow!.isForwarded, isFalse);
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
          ).copyWith(downloadStatus: kMediaDownloadStatusIntegrityFailed), owner: MediaOwnerLane.group,
        );
        await mediaRepo.saveAttachment(
          _doneAttachment(
            id: 'download-transient-failed',
            messageId: 'msg-md012-download-only',
          ).copyWith(downloadStatus: 'failed'), owner: MediaOwnerLane.group,
        );
        await mediaRepo.saveAttachment(
          _pendingAttachment(
            id: 'upload-pending-md012',
            messageId: 'msg-md012-upload-owner',
            localPath: 'pending_uploads/msg-md012-upload-owner/blob.jpg',
          ), owner: MediaOwnerLane.group,
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
          'msg-md012-download-only', owner: MediaOwnerLane.group,
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
          _doneAttachment(id: 'done-1', messageId: 'msg-1'), owner: MediaOwnerLane.group,
        );
        await mediaRepo.saveAttachment(
          _pendingAttachment(id: 'pending-1', messageId: 'msg-1'), owner: MediaOwnerLane.group,
        );
        // 228: the 1:1 row lives in the DIRECT lane; the group retrier's
        // lane-scoped query must never see it.
        await mediaRepo.saveAttachment(
          _pendingAttachment(id: 'dm-1', messageId: 'dm-1'),
          owner: MediaOwnerLane.direct,
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
            'msg-1', owner: MediaOwnerLane.group,
          )).every((a) => a.downloadStatus == 'done'),
          isTrue,
        );
        expect(
          (await mediaRepo.getUploadPendingAttachments(
            owner: MediaOwnerLane.direct,
          )).any((a) => a.messageId == 'dm-1'),
          isTrue,
          reason: '1:1 upload_pending rows must be skipped',
        );
      },
    );

    // 228: attachment ids are globally unique, but message ids can collide
    // across the lanes. The group retrier's lane-scoped pending query must
    // never surface — let alone consume — a DIRECT-lane upload_pending row
    // that shares its parent message id with a group row.
    test(
      'group retrier never consumes same id direct pending media',
      () async {
        const collidingMessageId = 'msg-collide-1';
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: collidingMessageId,
            groupId: 'group-1',
            senderPeerId: 'peer-admin',
            senderUsername: 'Admin',
            text: 'Colliding message id',
            timestamp: DateTime.utc(2026, 1, 1),
            status: 'failed',
            isIncoming: false,
            createdAt: DateTime.utc(2026, 1, 1),
          ),
        );
        // SAME message_id in BOTH lanes, distinct attachment ids.
        await mediaRepo.saveAttachment(
          _pendingAttachment(
            id: 'pending-group-collide',
            messageId: collidingMessageId,
            localPath: 'pending_uploads/msg-collide-1/group-blob.jpg',
          ),
          owner: MediaOwnerLane.group,
        );
        await mediaRepo.saveAttachment(
          _pendingAttachment(
            id: 'pending-direct-collide',
            messageId: collidingMessageId,
            localPath: 'pending_uploads/msg-collide-1/direct-blob.jpg',
          ),
          owner: MediaOwnerLane.direct,
        );
        uploadFn.willReturn(
          _doneAttachment(
            id: 'pending-group-collide',
            messageId: collidingMessageId,
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

        // Only the GROUP row was re-read and re-uploaded.
        expect(count, 1);
        expect(uploadFn.callCount, 1);
        expect(uploadFn.lastBlobId, 'pending-group-collide');
        expect(
          (await mediaRepo.getAttachmentsForMessage(
            collidingMessageId,
            owner: MediaOwnerLane.group,
          )).every((a) => a.downloadStatus == 'done'),
          isTrue,
          reason: 'the group pending row must be consumed by the retry',
        );
        // The direct-lane row is untouched: still upload_pending, same path.
        final directRows = await mediaRepo.getAttachmentsForMessage(
          collidingMessageId,
          owner: MediaOwnerLane.direct,
        );
        expect(directRows, hasLength(1));
        expect(directRows.single.id, 'pending-direct-collide');
        expect(directRows.single.downloadStatus, 'upload_pending');
        expect(
          directRows.single.localPath,
          'pending_uploads/msg-collide-1/direct-blob.jpg',
        );
      },
    );

    test(
      'logical delivery id is reused when retrying an incomplete group upload',
      () async {
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: 'msg-logical-upload-retry',
            groupId: 'group-1',
            senderPeerId: 'peer-admin',
            senderUsername: 'Admin',
            text: 'Logical upload retry',
            timestamp: DateTime.utc(2026, 1, 1),
            status: 'failed',
            isIncoming: false,
            createdAt: DateTime.utc(2026, 1, 1),
            logicalDeliveryId: 'logical-upload-original',
          ),
        );
        await mediaRepo.saveAttachment(
          _pendingAttachment(
            id: 'pending-logical-upload',
            messageId: 'msg-logical-upload-retry',
            localPath: 'pending_uploads/msg-logical-upload-retry/photo.jpg',
          ), owner: MediaOwnerLane.group,
        );
        uploadFn.willReturn(
          _doneAttachment(
            id: 'pending-logical-upload',
            messageId: 'msg-logical-upload-retry',
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
        final saved = await groupMsgRepo.getMessage('msg-logical-upload-retry');
        expect(saved, isNotNull);
        expect(saved!.logicalDeliveryId, 'logical-upload-original');
        final publishPayloads = _publishedGroupPayloads(bridge);
        expect(publishPayloads, hasLength(1));
        expect(publishPayloads.single['messageId'], 'msg-logical-upload-retry');
        expect(
          publishPayloads.single['logicalDeliveryId'],
          'logical-upload-original',
        );
      },
    );

    test(
      'message-scoped voice upload retry reuploads and resends only that failed row',
      () async {
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: 'msg-voice-targeted',
            groupId: 'group-1',
            senderPeerId: 'peer-admin',
            senderUsername: 'Admin',
            text: '',
            timestamp: DateTime.utc(2026, 1, 1, 12, 3, 4),
            status: 'failed',
            isIncoming: false,
            createdAt: DateTime.utc(2026, 1, 1, 12, 3, 4),
          ),
        );
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: 'msg-unrelated-pending',
            groupId: 'group-1',
            senderPeerId: 'peer-admin',
            senderUsername: 'Admin',
            text: 'Do not sweep me',
            timestamp: DateTime.utc(2026, 1, 1, 12, 4),
            status: 'failed',
            isIncoming: false,
            createdAt: DateTime.utc(2026, 1, 1, 12, 4),
          ),
        );
        await mediaRepo.saveAttachment(
          _pendingAttachment(
            id: 'voice-pending-target',
            messageId: 'msg-voice-targeted',
            localPath: 'pending_uploads/msg-voice-targeted/voice.m4a',
            mime: 'audio/mp4',
            size: _retryMp4Bytes.length,
          ).copyWith(durationMs: 4200, waveform: const [0.1, 0.5, 0.2]), owner: MediaOwnerLane.group,
        );
        await mediaRepo.saveAttachment(
          _pendingAttachment(
            id: 'image-pending-unrelated',
            messageId: 'msg-unrelated-pending',
            localPath: 'pending_uploads/msg-unrelated-pending/photo.jpg',
          ), owner: MediaOwnerLane.group,
        );
        uploadFn.willReturn(
          _doneAttachment(
            id: 'voice-pending-target',
            messageId: 'msg-voice-targeted',
            mime: 'audio/mp4',
            size: _retryMp4Bytes.length,
          ).copyWith(durationMs: 4200, waveform: const [0.1, 0.5, 0.2]),
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
          messageId: 'msg-voice-targeted',
        );

        expect(count, 1);
        expect(uploadFn.callCount, 1);
        expect(uploadFn.lastBlobId, 'voice-pending-target');
        expect(uploadFn.lastDurationMs, 4200);
        expect(uploadFn.lastAllowedPeers, ['peer-admin', 'peer-2']);
        expect(
          uploadFn.lastLocalPath,
          endsWith('test_docs/pending_uploads/msg-voice-targeted/voice.m4a'),
        );

        final savedTarget = await groupMsgRepo.getMessage('msg-voice-targeted');
        expect(savedTarget, isNotNull);
        expect(savedTarget!.status, 'sent');
        expect(savedTarget.timestamp, DateTime.utc(2026, 1, 1, 12, 3, 4));
        expect(
          (await groupMsgRepo.getMessage('msg-unrelated-pending'))?.status,
          'failed',
        );

        final targetAttachments = await mediaRepo.getAttachmentsForMessage(
          'msg-voice-targeted', owner: MediaOwnerLane.group,
        );
        expect(targetAttachments, hasLength(1));
        expect(targetAttachments.single.id, 'voice-pending-target');
        expect(targetAttachments.single.downloadStatus, 'done');
        expect(targetAttachments.single.mediaType, 'audio');
        expect(targetAttachments.single.durationMs, 4200);
        expect(targetAttachments.single.waveform, [0.1, 0.5, 0.2]);
        expect(
          (await mediaRepo.getAttachmentsForMessage(
            'msg-unrelated-pending', owner: MediaOwnerLane.group,
          )).single.downloadStatus,
          'upload_pending',
        );

        final publishPayloads = _publishedGroupPayloads(bridge);
        expect(publishPayloads, hasLength(1));
        expect(publishPayloads.single['messageId'], 'msg-voice-targeted');
        expect(publishPayloads.single['timestamp'], '2026-01-01T12:03:04.000Z');
        final media = (publishPayloads.single['media'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        expect(media, hasLength(1));
        expect(media.single['id'], 'voice-pending-target');
        expect(media.single['mediaType'], 'audio');
        expect(media.single['durationMs'], 4200);
        expect(media.single['waveform'], [0.1, 0.5, 0.2]);
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
          ), owner: MediaOwnerLane.group,
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
          ), owner: MediaOwnerLane.group,
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
          'msg-dangerous-mime', owner: MediaOwnerLane.group,
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
          ), owner: MediaOwnerLane.group,
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
            'msg-octet-mime', owner: MediaOwnerLane.group,
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
        ), owner: MediaOwnerLane.group,
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
          'msg-spoofed-retry', owner: MediaOwnerLane.group,
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
          ), owner: MediaOwnerLane.group,
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
          ), owner: MediaOwnerLane.group,
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
            'msg-oversized-pending', owner: MediaOwnerLane.group,
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
          ), owner: MediaOwnerLane.group,
        );
        await mediaRepo.saveAttachment(
          _pendingAttachment(
            id: 'pending-total-extra',
            messageId: 'msg-total-oversized-retry',
            size: 1,
          ), owner: MediaOwnerLane.group,
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
                'msg-total-oversized-retry', owner: MediaOwnerLane.group,
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
          _doneAttachment(id: 'done-jpeg', messageId: 'msg-gif-1'), owner: MediaOwnerLane.group,
        );
        await mediaRepo.saveAttachment(
          _pendingAttachment(
            id: 'pending-gif',
            messageId: 'msg-gif-1',
            localPath: 'pending_uploads/msg-gif-1/funny.gif',
            mime: 'image/gif',
          ), owner: MediaOwnerLane.group,
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
          _doneAttachment(id: 'done-1', messageId: 'msg-1'), owner: MediaOwnerLane.group,
        );
        await mediaRepo.saveAttachment(
          _pendingAttachment(id: 'pending-1', messageId: 'msg-1'), owner: MediaOwnerLane.group,
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
          _pendingAttachment(id: 'pending-2', messageId: 'msg-2'), owner: MediaOwnerLane.group,
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
          (await mediaRepo.getUploadPendingAttachments(owner: MediaOwnerLane.group))
              .single
              .uploadRetryCount,
          1,
        );

        await mediaRepo.saveAttachment(
          _pendingAttachment(
            id: 'pending-2',
            messageId: 'msg-2',
            uploadRetryCount: kMaxUploadRetries - 1,
          ), owner: MediaOwnerLane.group,
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
            'msg-2', owner: MediaOwnerLane.group,
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
          ), owner: MediaOwnerLane.group,
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

        final pending = await mediaRepo.getUploadPendingAttachments(owner: MediaOwnerLane.group);
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
          ), owner: MediaOwnerLane.group,
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

    test(
      'GIRD-002 incomplete-upload retry aborts final send when another owner settled the row',
      () async {
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: 'msg-gird002-settled',
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
            id: 'pending-gird002-settled',
            messageId: 'msg-gird002-settled',
          ), owner: MediaOwnerLane.group,
        );
        mediaRepo.onSaveAttachment = (attachment) {
          if (attachment.messageId == 'msg-gird002-settled' &&
              attachment.downloadStatus == 'done') {
            groupMsgRepo.saveMessage(
              GroupMessage(
                id: 'msg-gird002-settled',
                groupId: 'group-1',
                senderPeerId: 'peer-admin',
                senderUsername: 'Admin',
                text: 'Hello',
                timestamp: DateTime.utc(2026, 1, 1),
                status: 'sent',
                isIncoming: false,
                createdAt: DateTime.utc(2026, 1, 1),
              ),
            );
          }
        };
        addTearDown(() {
          mediaRepo.onSaveAttachment = null;
        });
        uploadFn.willReturn(
          _doneAttachment(
            id: 'pending-gird002-settled',
            messageId: 'msg-gird002-settled',
          ),
        );

        final events = await captureFlowEvents(() async {
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

        expect(
          (await groupMsgRepo.getMessage('msg-gird002-settled'))?.status,
          'sent',
        );
        expect(bridge.commandLog, isNot(contains('group:publish')));
        final abort = events.lastWhere(
          (event) =>
              event['event'] ==
              'RETRY_INCOMPLETE_GROUP_UPLOAD_ABORT_FINAL_SEND',
        );
        expect(abort['details']['reason'], 'message_status_sent');
      },
    );
  });
}
