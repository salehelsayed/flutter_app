import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/config/direct_linked_devices_flag.dart';
import 'package:flutter_app/core/constants/retry_constants.dart';
import 'package:flutter_app/core/database/direct_media_blob_custody.dart';
import 'package:flutter_app/core/media/group_media_blob_artifact_store.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/group_media_size_policy.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/media_upload_in_flight_tracker.dart';
import 'package:flutter_app/core/media/upload_retry_projection.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/groups/application/foreground_group_media_upload.dart';
import 'package:flutter_app/features/groups/application/group_membership_event_watermark.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/prepared_group_media_blob_custody_coordinator.dart';
import 'package:flutter_app/features/groups/application/protected_group_media_manifest.dart';
import 'package:flutter_app/features/groups/application/protected_group_content_reconciliation.dart';
import 'package:flutter_app/features/groups/application/retry_failed_group_inbox_stores_use_case.dart';
import 'package:flutter_app/features/groups/application/retry_incomplete_group_uploads_use_case.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart'
    show
        GroupContentAuthoringContext,
        GroupContentAuthoringResolutionKind,
        sameExactGroupPrivateMediaDispatchParent,
        setGroupContentAuthoringResolver;
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:path/path.dart' as p;

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
  return p.join(FakeMediaFileManager.testRootPath, localPath);
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
  int? downloadRetryCount,
  String? createdAt,
  String? thumbnailHash,
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
    createdAt: createdAt ?? DateTime.now().toUtc().toIso8601String(),
    uploadRetryCount: uploadRetryCount,
    downloadRetryCount: downloadRetryCount,
    thumbnailHash: thumbnailHash,
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

class _RecordingGroupUploadRetryProjection
    implements GroupUploadRetryProjectionRepository {
  int callCount = 0;
  String? messageId;
  String? attachmentId;
  UploadMediaFailed? failure;

  @override
  Future<UploadRetryProjectionResult> projectUploadFailure({
    required String messageId,
    required String attachmentId,
    required UploadMediaFailed failure,
  }) async {
    callCount++;
    this.messageId = messageId;
    this.attachmentId = attachmentId;
    this.failure = failure;
    return const UploadRetryProjectionResult(
      state: UploadRetryProjectionState.terminal,
    );
  }
}

class _CompletionFailureGroupMessageRepository
    extends InMemoryGroupMessageRepository
    implements
        GroupUploadRetryCompletionRepository,
        GroupUploadRetryProjectionRepository {
  _CompletionFailureGroupMessageRepository({
    required this.mediaRepo,
    required this.throwOnCompletion,
  });

  final InMemoryMediaAttachmentRepository mediaRepo;
  final bool throwOnCompletion;
  Future<void> Function(
    GroupMessage expectedParent,
    MediaAttachment expectedAttachment,
  )?
  beforeFalseCompletion;

  int completionCalls = 0;
  int projectionCalls = 0;
  int appliedProjectionCalls = 0;
  final List<UploadMediaFailed> projectedFailures = <UploadMediaFailed>[];
  final Map<String, GroupMessage> _expectedParents = <String, GroupMessage>{};
  final Map<String, MediaAttachment> _expectedAttachments =
      <String, MediaAttachment>{};

  @override
  Future<bool> completeUploadRetry({
    required GroupMessage expectedParent,
    required MediaAttachment expectedAttachment,
    required MediaAttachment completedAttachment,
  }) async {
    completionCalls++;
    _expectedParents[expectedAttachment.id] = expectedParent;
    _expectedAttachments[expectedAttachment.id] = expectedAttachment;
    if (throwOnCompletion) {
      throw StateError('simulated group upload completion persistence failure');
    }
    await beforeFalseCompletion?.call(expectedParent, expectedAttachment);
    return false;
  }

  @override
  Future<UploadRetryProjectionResult> projectUploadFailure({
    required String messageId,
    required String attachmentId,
    required UploadMediaFailed failure,
  }) async {
    projectionCalls++;
    projectedFailures.add(failure);
    final expectedParent = _expectedParents[attachmentId];
    final expectedAttachment = _expectedAttachments[attachmentId];
    final currentParent = await getMessage(messageId);
    final currentAttachment = await mediaRepo.getAttachmentById(attachmentId);
    if (expectedParent == null ||
        expectedAttachment == null ||
        currentParent == null ||
        currentAttachment == null ||
        !sameExactGroupPrivateMediaDispatchParent(
          currentParent,
          expectedParent,
        ) ||
        !sameExactGroupRetryAttachment(currentAttachment, expectedAttachment) ||
        currentAttachment.downloadStatus != 'upload_pending') {
      return const UploadRetryProjectionResult.notApplied();
    }

    final nextRetryCount = (currentAttachment.uploadRetryCount ?? 0) + 1;
    final terminal = nextRetryCount >= kMaxUploadRetries;
    await mediaRepo.saveAttachment(
      currentAttachment.copyWith(
        downloadStatus: terminal ? 'upload_failed' : 'upload_pending',
        uploadRetryCount: nextRetryCount,
      ),
      owner: MediaOwnerLane.group,
    );
    await saveMessage(
      currentParent.copyWith(status: terminal ? 'failed' : 'queued_offline'),
    );
    appliedProjectionCalls++;
    return UploadRetryProjectionResult(
      state: terminal
          ? UploadRetryProjectionState.terminal
          : UploadRetryProjectionState.retryPending,
      uploadRetryCount: nextRetryCount,
    );
  }
}

class _RecordingGroupManualUploadRetryRearm
    implements GroupManualUploadRetryRearmRepository {
  _RecordingGroupManualUploadRetryRearm({
    required this.groupMsgRepo,
    required this.mediaRepo,
  });

  final InMemoryGroupMessageRepository groupMsgRepo;
  final InMemoryMediaAttachmentRepository mediaRepo;
  int callCount = 0;
  bool willApply = true;
  List<ManualUploadRetryAttachmentExpectation>? lastExpectations;

  @override
  Future<bool> rearmUploadRetryForManualRetry({
    required String messageId,
    required List<ManualUploadRetryAttachmentExpectation> attachments,
  }) async {
    callCount++;
    lastExpectations = List.unmodifiable(attachments);
    if (!willApply) return false;
    final parent = await groupMsgRepo.getMessage(messageId);
    if (parent == null || parent.isIncoming || parent.status != 'failed') {
      return false;
    }
    final persisted = await mediaRepo.getAttachmentsForMessage(
      messageId,
      owner: MediaOwnerLane.group,
    );
    final unfinished = persisted
        .where((attachment) => attachment.downloadStatus != 'done')
        .toList(growable: false);
    if (unfinished.length != attachments.length) return false;
    for (final expected in attachments) {
      final matches = unfinished.where(
        (attachment) =>
            attachment.id == expected.attachmentId &&
            attachment.localPath == expected.storedLocalPath &&
            attachment.downloadStatus == expected.downloadStatus &&
            (attachment.uploadRetryCount ?? 0) == expected.uploadRetryCount,
      );
      if (matches.length != 1) return false;
    }

    await groupMsgRepo.saveMessage(
      parent.copyWith(
        status: 'queued_offline',
        wireEnvelope: null,
        inboxRetryPayload: null,
        inboxStored: false,
        retryAttemptCount: 0,
        nextEligibleAt: null,
      ),
    );
    for (final expected in attachments) {
      if (expected.downloadStatus != 'upload_failed') continue;
      final current = unfinished.singleWhere(
        (attachment) => attachment.id == expected.attachmentId,
      );
      await mediaRepo.saveAttachment(
        current.copyWith(downloadStatus: 'upload_pending', uploadRetryCount: 0),
        owner: MediaOwnerLane.group,
      );
    }
    return true;
  }
}

final class _NoopStrictGroupInboxStore
    implements AckOrExpiryInboxStore, GroupContentExpiryBoundedInboxStore {
  final List<({String recipientPeerId, int expiresAtOrBeforeMs})>
  boundedStores = <({String recipientPeerId, int expiresAtOrBeforeMs})>[];

  @override
  Future<InboxStoreOutcome> storeInAckCustodyInboxDetailed(
    String toPeerId,
    String message, {
    required AckCustodyKind custodyKind,
    int? timeoutMs,
  }) async => const InboxStoreOutcome(
    status: InboxStoreStatus.stored,
    storeStatus: 'stored',
    custodyContract: ackOrExpiryInboxCustodyContract,
  );

  @override
  Future<InboxStoreOutcome> storeInGroupContentExpiryBoundedInboxDetailed(
    String toPeerId,
    String message, {
    required int custodyExpiresAtOrBeforeMs,
    int? timeoutMs,
  }) async {
    boundedStores.add((
      recipientPeerId: toPeerId,
      expiresAtOrBeforeMs: custodyExpiresAtOrBeforeMs,
    ));
    return InboxStoreOutcome(
      status: InboxStoreStatus.stored,
      storeStatus: 'stored',
      expiresAtMs: custodyExpiresAtOrBeforeMs,
      custodyContract: ackOrExpiryInboxCustodyContract,
    );
  }
}

bool _sameBoundStrictContentMessage(
  GroupMessage current,
  GroupMessage expected,
) =>
    current.id == expected.id &&
    current.groupId == expected.groupId &&
    current.senderPeerId == expected.senderPeerId &&
    current.transportPeerId == expected.transportPeerId &&
    current.logicalDeliveryId == expected.logicalDeliveryId &&
    current.keyGeneration == expected.keyGeneration &&
    current.status == expected.status &&
    current.isIncoming == expected.isIncoming &&
    current.wireEnvelope == expected.wireEnvelope &&
    current.inboxStored == expected.inboxStored &&
    current.inboxRetryPayload == expected.inboxRetryPayload;

final class _StrictBoundContentMessageRepository
    extends InMemoryGroupMessageRepository
    implements
        GroupInboxStoreRetryPayloadCasRepository,
        GroupMessageStrictContentCompletionRepository,
        GroupMessageStrictPreparedTerminalRepository {
  GroupMessage? _prepared;

  Future<void> bindPrepared(GroupMessage message) async {
    await saveMessage(message);
    _prepared = message;
  }

  @override
  Future<bool> hasExactStrictContentPrepared(
    GroupMessage expected, {
    required Map<String, Object?> eventPayload,
  }) async {
    final current = await getMessage(expected.id);
    return current != null &&
        _prepared != null &&
        _sameBoundStrictContentMessage(current, expected) &&
        _sameBoundStrictContentMessage(_prepared!, expected);
  }

  @override
  Future<bool> replaceInboxRetryPayloadIfExact(
    GroupMessage expected,
    String replacement,
  ) async {
    final current = await getMessage(expected.id);
    if (current == null || !_sameBoundStrictContentMessage(current, expected)) {
      return false;
    }
    final next = current.copyWith(inboxRetryPayload: replacement);
    await saveMessage(next);
    _prepared = next;
    return true;
  }

  @override
  Future<bool> completeStrictContentIfExact(
    GroupMessage expected, {
    required String sourcePeerId,
    required String sourceEventId,
    required String sourceTimestamp,
    required Map<String, Object?> eventPayload,
  }) async {
    final current = await getMessage(expected.id);
    if (current == null || !_sameBoundStrictContentMessage(current, expected)) {
      return false;
    }
    await saveMessage(
      current.copyWith(
        status: 'sent',
        wireEnvelope: null,
        inboxStored: true,
        inboxRetryPayload: null,
      ),
    );
    _prepared = null;
    return true;
  }

  @override
  Future<bool> terminalizeStrictContentPreparedIfExact(
    GroupMessage expected, {
    required Map<String, Object?> preparedEventPayload,
    required String terminalSourcePeerId,
    required String terminalSourceEventId,
    required String terminalSourceTimestamp,
    required Map<String, Object?> terminalEventPayload,
  }) async => false;
}

final class _StrictGroupUploadRetryRepository
    extends InMemoryMediaAttachmentRepository
    implements GroupMediaBlobCustodyRepository {
  _StrictGroupUploadRetryRepository(this.messages);

  final InMemoryGroupMessageRepository messages;
  final List<DirectMediaBlobCustodyRow> rows = <DirectMediaBlobCustodyRow>[];
  int stageCalls = 0;

  @override
  bool get supportsGroupMediaBlobCustody => true;

  @override
  Future<T> runGroupMediaBlobCustodyLifecycle<T>(Future<T> Function() action) =>
      action();

  @override
  Future<GroupMediaBlobCustodyStageOutcome>
  stageFreshOutgoingGroupMediaBlobGeneration({
    required GroupMessage parent,
    required List<MediaAttachment> attachments,
    required List<DirectMediaBlobCustodyRow> custodyRows,
    required Map<String, String> custodyBlobIdsByAttachmentId,
  }) async {
    stageCalls++;
    if (rows.isNotEmpty || attachments.isEmpty || custodyRows.isEmpty) {
      return GroupMediaBlobCustodyStageOutcome.refused;
    }
    final attachmentIds = attachments
        .map((attachment) => attachment.id)
        .toSet();
    if (custodyBlobIdsByAttachmentId.keys
            .toSet()
            .difference(attachmentIds)
            .isNotEmpty ||
        attachmentIds
            .difference(custodyBlobIdsByAttachmentId.keys.toSet())
            .isNotEmpty ||
        custodyRows.any(
          (row) =>
              row.ownerLane != MediaBlobCustodyOwnerLane.group ||
              row.groupId != parent.groupId ||
              row.messageId != parent.id ||
              row.direction != DirectMediaBlobCustodyDirection.outgoing ||
              custodyBlobIdsByAttachmentId[row.attachmentId] !=
                  row.custodyBlobId,
        )) {
      return GroupMediaBlobCustodyStageOutcome.refused;
    }
    await messages.saveMessage(parent);
    for (final attachment in attachments) {
      await saveAttachment(attachment, owner: MediaOwnerLane.group);
    }
    rows.addAll(custodyRows);
    return GroupMediaBlobCustodyStageOutcome.applied;
  }

  @override
  Future<List<DirectMediaBlobCustodyRow>> loadGroupMediaBlobCustodyForMessage({
    required String groupId,
    required String messageId,
  }) async => rows
      .where((row) => row.groupId == groupId && row.messageId == messageId)
      .toList(growable: false);

  @override
  Future<List<DirectMediaBlobCustodyRow>> loadGroupMediaBlobCustodyByStates(
    Set<DirectMediaBlobCustodyState> states, {
    int limit = 50,
  }) async => rows
      .where((row) => states.contains(row.state))
      .take(limit)
      .toList(growable: false);

  @override
  Future<DirectMediaBlobCustodyRow?> loadGroupMediaBlobCustodyForTarget({
    required String groupId,
    required String attachmentId,
    required String custodyBlobId,
    required DirectMediaBlobCustodyDirection direction,
    String? recipientPeerId,
  }) async {
    for (final row in rows) {
      if (row.groupId == groupId &&
          row.attachmentId == attachmentId &&
          row.custodyBlobId == custodyBlobId &&
          row.direction == direction &&
          row.recipientPeerId == recipientPeerId) {
        return row;
      }
    }
    return null;
  }

  @override
  Future<bool> transitionGroupMediaBlobCustodyIfExact({
    required DirectMediaBlobCustodyRow expected,
    required DirectMediaBlobCustodyRow next,
  }) async {
    final index = rows.indexWhere(
      (row) => row.exactDatabaseProjectionMatches(expected),
    );
    if (index < 0 || !expected.canTransitionTo(next)) return false;
    rows[index] = next;
    return true;
  }

  @override
  Future<bool> deleteGroupMediaBlobCleanupPendingIfExact(
    DirectMediaBlobCustodyRow expected,
  ) async => false;

  @override
  Future<bool> commitIncomingGroupMediaBlobLocalPath({
    required MediaAttachment expectedAttachment,
    required DirectMediaBlobCustodyRow expectedCustody,
    required String localPath,
    required String sourceRelayPeerId,
    required String updatedAt,
    required int nowMs,
  }) async => false;

  @override
  Future<bool> terminalizeIncomingGroupMediaBlobForLocalDeletion({
    required MediaAttachment expectedAttachment,
    required DirectMediaBlobCustodyRow expectedCustody,
    required String sourceRelayPeerId,
    required String updatedAt,
  }) async => false;

  @override
  Future<bool> deleteIncomingGroupMediaBlobAckPendingIfExact(
    DirectMediaBlobCustodyRow expected,
  ) async => false;

  @override
  Future<bool> deleteIncomingGroupMediaBlobIfExpired({
    required DirectMediaBlobCustodyRow expected,
    required int nowMs,
  }) async => false;

  @override
  Future<int> countOtherGroupMediaBlobCustodyRowsReferencingArtifact(
    DirectMediaBlobCustodyRow expected,
  ) async => rows
      .where(
        (row) =>
            !row.exactDatabaseProjectionMatches(expected) &&
            row.ciphertextRelativePath == expected.ciphertextRelativePath,
      )
      .length;
}

final class _CountingGroupRepository extends InMemoryGroupRepository {
  int getMembersCallCount = 0;

  @override
  Future<List<GroupMember>> getMembers(String groupId) async {
    getMembersCallCount++;
    return super.getMembers(groupId);
  }
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
    test(
      'TC-366-03b forwarded strict survivor preserves marker without source or authority read',
      () {
        final source = File(
          'lib/features/groups/application/'
          'retry_incomplete_group_uploads_use_case.dart',
        ).readAsStringSync();
        final strictBranch = source.lastIndexOf('if (hasStrictGroupCustody)');
        final survivorRetry = source.indexOf(
          'retryPersistedGeneration(',
          strictBranch,
        );
        final markerDispatch = source.indexOf(
          'isForwarded: parentMessage.isForwarded,',
          survivorRetry,
        );
        final legacyAdmission = source.indexOf(
          'prepareGroupContentAuthoringAdmission(',
          markerDispatch,
        );
        final preSurvivor = source.substring(strictBranch, survivorRetry);

        expect(strictBranch, greaterThanOrEqualTo(0));
        expect(survivorRetry, greaterThan(strictBranch));
        expect(markerDispatch, greaterThan(survivorRetry));
        expect(legacyAdmission, greaterThan(markerDispatch));
        expect(preSurvivor, isNot(contains('resolveStoredPath(')));
        expect(preSurvivor, isNot(contains('allowedPeers')));
        expect(preSurvivor, isNot(contains('getMembers(')));
      },
    );

    test(
      'TC-366-04b strict survivors precede authority and initialized no-fingerprint retry refuses before network',
      () async {
        final source = File(
          'lib/features/groups/application/'
          'retry_incomplete_group_uploads_use_case.dart',
        ).readAsStringSync();
        final strictBranch = source.indexOf('if (hasStrictGroupCustody)');
        final legacyAdmission = source.indexOf(
          'prepareGroupContentAuthoringAdmission(',
          strictBranch,
        );
        final descriptorPreprocessing = source.indexOf(
          'GroupMediaMimePolicy.validateDescriptor(',
          strictBranch,
        );
        final legacyNetwork = source.indexOf(
          'final outcome = await runUploadMedia(',
          descriptorPreprocessing,
        );

        expect(strictBranch, greaterThanOrEqualTo(0));
        expect(legacyAdmission, greaterThan(strictBranch));
        expect(descriptorPreprocessing, greaterThan(legacyAdmission));
        expect(legacyNetwork, greaterThan(descriptorPreprocessing));

        final initializedGroupRepo = _CountingGroupRepository();
        final initializedMessages = InMemoryGroupMessageRepository();
        final initializedAttachments = InMemoryMediaAttachmentRepository();
        final initializedBridge = FakeBridge(
          initialResponses: {
            'group:publish': {
              'ok': true,
              'messageId': 'tc366-no-intent-message',
              'topicPeers': 1,
            },
            'group:inboxStore': {'ok': true},
          },
        );
        final initializedP2p = FakeP2PService(
          initialState: const NodeState(
            isStarted: true,
            peerId: 'transport-current',
            circuitAddresses: <String>['/p2p-circuit/tc366-no-intent'],
          ),
          storeInInboxResult: true,
        );
        final initializedIdentity = FakeIdentityRepository()
          ..seed(
            FakeIdentityRepository.makeIdentity(
              peerId: 'peer-admin',
              publicKey: 'pk-admin',
              privateKey: 'sk-admin',
            ),
          );
        final initializedMediaFiles = FakeMediaFileManager();
        final initializedUpload = FakeUploadMediaFn();
        final initializedProjection = _RecordingGroupUploadRetryProjection();
        var pendingDirDeleteCalls = 0;
        initializedMediaFiles.onDeletePendingUploadDir = (_) {
          pendingDirDeleteCalls++;
        };

        await initializedGroupRepo.saveGroup(
          GroupModel(
            id: 'group-tc366-no-intent',
            name: 'Initialized no-intent group',
            type: GroupType.chat,
            topicName: 'topic-tc366-no-intent',
            createdAt: DateTime.utc(2026, 1, 1),
            createdBy: 'peer-admin',
            myRole: GroupRole.admin,
          ),
        );
        await initializedGroupRepo.saveKey(
          GroupKeyInfo(
            groupId: 'group-tc366-no-intent',
            keyGeneration: 0,
            encryptedKey: 'encrypted-tc366-no-intent',
            createdAt: DateTime.utc(2026, 1, 1),
          ),
        );
        await initializedGroupRepo.saveMember(
          GroupMember(
            groupId: 'group-tc366-no-intent',
            peerId: 'peer-admin',
            username: 'Admin',
            role: MemberRole.admin,
            publicKey: 'pk-admin',
            devices: const <GroupMemberDeviceIdentity>[
              GroupMemberDeviceIdentity(
                deviceId: 'transport-current',
                transportPeerId: 'transport-current',
                deviceSigningPublicKey: 'pk-admin',
              ),
              GroupMemberDeviceIdentity(
                deviceId: 'device-sibling',
                transportPeerId: 'transport-sibling',
                deviceSigningPublicKey: 'pk-sibling',
              ),
            ],
            joinedAt: DateTime.utc(2026, 1, 1),
          ),
        );
        await initializedGroupRepo.saveMember(
          GroupMember(
            groupId: 'group-tc366-no-intent',
            peerId: 'peer-remote',
            username: 'Remote',
            role: MemberRole.writer,
            publicKey: 'pk-remote',
            devices: const <GroupMemberDeviceIdentity>[
              GroupMemberDeviceIdentity(
                deviceId: 'device-remote',
                transportPeerId: 'transport-remote',
                deviceSigningPublicKey: 'pk-remote-device',
              ),
            ],
            joinedAt: DateTime.utc(2026, 1, 1, 0, 1),
          ),
        );
        final strictInboxStore = _NoopStrictGroupInboxStore();
        final strictContext = GroupContentAuthoringContext(
          directLinkedDeviceSelector:
              const DirectLinkedDeviceSelector.enabled(),
          multiDeviceSyncEnabled: true,
          authorityVersion: GroupContentAuthorityVersion(
            eventAt: DateTime.utc(2026, 8, 14, 9),
            eventId: 'authority-tc366-no-intent',
            keyEpoch: 0,
          ),
          inboxStore: strictInboxStore,
          authoringDeviceId: 'transport-current',
          authoringTransportPeerId: 'transport-current',
          authoringPublicKey: 'pk-admin',
        );
        var authorityResolverCalls = 0;
        setGroupContentAuthoringResolver(initializedGroupRepo, ({
          required String groupId,
          required String senderPeerId,
          required String senderPublicKey,
          String? senderDeviceId,
          String? senderTransportPeerId,
        }) async {
          authorityResolverCalls++;
          return (
            kind: GroupContentAuthoringResolutionKind.strict,
            context: strictContext,
          );
        });
        addTearDown(
          () => setGroupContentAuthoringResolver(initializedGroupRepo, null),
        );

        final parent = GroupMessage(
          id: 'tc366-no-intent-message',
          groupId: 'group-tc366-no-intent',
          senderPeerId: 'peer-admin',
          transportPeerId: 'transport-current',
          senderUsername: 'Admin',
          text: 'Initialized row without strict blob intent',
          timestamp: DateTime.utc(2026, 8, 14, 8),
          status: 'failed',
          isIncoming: false,
          createdAt: DateTime.utc(2026, 8, 14, 8),
        );
        final pending = _pendingAttachment(
          id: 'tc366-no-intent-attachment',
          messageId: parent.id,
          localPath:
              'pending_uploads/${parent.id}/tc366-no-intent-attachment.jpg',
          createdAt: parent.createdAt.toIso8601String(),
        );
        await initializedMessages.saveMessage(parent);
        await initializedAttachments.saveAttachment(
          pending,
          owner: MediaOwnerLane.group,
        );
        initializedUpload.willReturn(
          _doneAttachment(id: pending.id, messageId: parent.id),
        );

        late final int retryCount;
        final events = await captureFlowEvents(() async {
          retryCount = await retryIncompleteGroupUploads(
            groupRepo: initializedGroupRepo,
            groupMsgRepo: initializedMessages,
            mediaAttachmentRepo: initializedAttachments,
            bridge: initializedBridge,
            p2pService: initializedP2p,
            identityRepo: initializedIdentity,
            uploadMediaFn: initializedUpload.call,
            mediaFileManager: initializedMediaFiles,
            messageId: parent.id,
            uploadRetryProjectionRepo: initializedProjection,
          );
        });

        expect(retryCount, 0);
        expect(initializedUpload.callCount, 0);
        expect(initializedUpload.lastAllowedPeers, isNull);
        expect(initializedMediaFiles.resolveStoredPathCount, 0);
        expect(authorityResolverCalls, 1);
        expect(
          initializedGroupRepo.getMembersCallCount,
          1,
          reason:
              'the one admission snapshot is allowed; no later legacy '
              'membership/allowedPeers read may run',
        );
        expect(initializedMediaFiles.trustedMediaRootPathCount, 0);
        expect(initializedMediaFiles.trustedPendingUploadRootPathCount, 0);
        expect(initializedProjection.callCount, 0);
        expect(pendingDirDeleteCalls, 0);
        expect(initializedBridge.commandLog, isEmpty);
        expect(
          events.where(
            (event) =>
                event['event'] ==
                'RETRY_INCOMPLETE_GROUP_UPLOAD_NO_STRICT_INTENT',
          ),
          hasLength(1),
        );
        final durable = await initializedAttachments.getAttachmentById(
          pending.id,
        );
        expect(durable?.downloadStatus, 'upload_pending');
        expect(durable?.localPath, pending.localPath);
        expect(durable?.groupMediaBlobCustodyFingerprint, isNull);
        expect(
          (await initializedMessages.getMessage(parent.id))?.status,
          'failed',
        );
      },
    );

    test(
      'TC-365-02b strict group blob survivors reuse one durable artifact without roster recompute',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'tc365-group-survivor-',
        );
        addTearDown(() => root.delete(recursive: true));

        await groupRepo.saveMemberBypassingValidationForTest(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-admin',
            username: 'Admin',
            role: MemberRole.admin,
            publicKey: 'pk-admin',
            devices: const <GroupMemberDeviceIdentity>[
              GroupMemberDeviceIdentity(
                deviceId: 'device-current',
                transportPeerId: 'transport-current',
                deviceSigningPublicKey: 'pk-admin',
              ),
              GroupMemberDeviceIdentity(
                deviceId: 'device-sibling',
                transportPeerId: 'transport-sibling',
                deviceSigningPublicKey: 'pk-sibling',
              ),
            ],
            joinedAt: DateTime.utc(2026, 1, 1),
          ),
        );
        await groupRepo.saveMemberBypassingValidationForTest(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-2',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-2',
            devices: const <GroupMemberDeviceIdentity>[
              GroupMemberDeviceIdentity(
                deviceId: 'device-remote',
                transportPeerId: 'transport-remote',
                deviceSigningPublicKey: 'pk-remote',
              ),
            ],
            joinedAt: DateTime.utc(2026, 1, 1),
          ),
        );
        final strictInboxStore = _NoopStrictGroupInboxStore();
        final authoringContext = GroupContentAuthoringContext(
          directLinkedDeviceSelector:
              const DirectLinkedDeviceSelector.enabled(),
          multiDeviceSyncEnabled: true,
          authorityVersion: GroupContentAuthorityVersion(
            eventAt: DateTime.utc(2026, 8, 14, 9, 30),
            eventId: 'authority-tc365-02b',
            keyEpoch: 0,
          ),
          inboxStore: strictInboxStore,
          authoringDeviceId: 'device-current',
          authoringTransportPeerId: 'transport-current',
          authoringPublicKey: 'pk-admin',
        );
        setGroupContentAuthoringResolver(
          groupRepo,
          ({
            required String groupId,
            required String senderPeerId,
            required String senderPublicKey,
            String? senderDeviceId,
            String? senderTransportPeerId,
          }) async => (
            kind: GroupContentAuthoringResolutionKind.strict,
            context: authoringContext,
          ),
        );
        addTearDown(() => setGroupContentAuthoringResolver(groupRepo, null));

        final plaintext = File('${root.path}/source.jpg');
        final plaintextBytes = <int>[
          0xff,
          0xd8,
          0xff,
          ...List<int>.generate(61, (index) => index),
        ];
        await plaintext.writeAsBytes(plaintextBytes);
        final encryptedSource = File('${root.path}/fresh-ciphertext.bin');
        final ciphertextBytes = <int>[
          ...List<int>.filled(16, 0xa5),
          ...plaintextBytes,
        ];
        await encryptedSource.writeAsBytes(ciphertextBytes);
        final ciphertextHash = sha256.convert(ciphertextBytes).toString();

        const messageId = 'msg-tc365-survivor';
        const attachmentId = 'blob-tc365-survivor';
        final parent = GroupMessage(
          id: messageId,
          groupId: 'group-1',
          senderPeerId: 'peer-admin',
          senderUsername: 'Admin',
          text: 'one durable artifact',
          timestamp: DateTime.utc(2026, 8, 14, 10),
          status: GroupMessage.statusQueuedOffline,
          isIncoming: false,
          createdAt: DateTime.utc(2026, 8, 14, 10),
        );
        final sourceAttachment = MediaAttachment(
          id: attachmentId,
          messageId: messageId,
          mime: 'image/jpeg',
          size: plaintextBytes.length,
          mediaType: 'image',
          width: 8,
          height: 8,
          localPath: plaintext.path,
          downloadStatus: 'upload_pending',
          createdAt: parent.createdAt.toIso8601String(),
          ownerLane: MediaOwnerLane.group,
        );
        final strictRepository = _StrictGroupUploadRetryRepository(
          groupMsgRepo,
        );
        final firstAttempts =
            <
              ({String recipient, String blobId, String path, List<int> bytes})
            >[];
        final firstCoordinator = PreparedGroupMediaBlobCustodyCoordinator(
          artifactStore: GroupMediaBlobArtifactStore(
            documentsDirectoryProvider: () async => root,
          ),
          clock: () => DateTime.utc(2026, 8, 14, 10),
          strictUpload:
              ({
                required Bridge bridge,
                required String custodyBlobId,
                required String recipientPeerId,
                required String ciphertextPath,
                required String contentHash,
                required int ciphertextSize,
              }) async {
                final bytes = await File(ciphertextPath).readAsBytes();
                firstAttempts.add((
                  recipient: recipientPeerId,
                  blobId: custodyBlobId,
                  path: ciphertextPath,
                  bytes: List<int>.unmodifiable(bytes),
                ));
                expect(contentHash, ciphertextHash);
                expect(ciphertextSize, ciphertextBytes.length);
                if (recipientPeerId == 'transport-sibling') {
                  throw StateError('simulated process stop with one survivor');
                }
                return <String, dynamic>{
                  'ok': true,
                  'id': custodyBlobId,
                  'storeStatus': 'stored',
                  'custodyKind': groupMediaBlobCustodyKind,
                  'custodyContract': groupMediaBlobCustodyContract,
                  'contentHash': contentHash,
                  'size': ciphertextSize,
                  'mime': groupMediaBlobTransportMime,
                  'expiresAtMs': DateTime.utc(
                    2036,
                    8,
                    20,
                  ).millisecondsSinceEpoch,
                  'custodyRelayPeerId': 'relay-remote',
                };
              },
        );

        final first = await firstCoordinator.prepareAndUploadFresh(
          bridge: bridge,
          groupRepository: groupRepo,
          mediaAttachmentRepository: strictRepository,
          identityPeerId: 'peer-admin',
          senderPublicKey: 'pk-admin',
          senderDeviceId: 'device-current',
          senderTransportPeerId: 'transport-current',
          parent: parent,
          sources: <PreparedGroupMediaBlobSource>[
            PreparedGroupMediaBlobSource(
              attachment: sourceAttachment,
              plaintextPath: plaintext.path,
              preparedArtifact: EncryptedMediaArtifact(
                encryptedPath: encryptedSource.path,
                keyBase64: 'strict-key',
                nonce: 'strict-nonce',
                scheme: groupMediaBlobEncryptionScheme,
                contentHash: ciphertextHash,
                plaintextSize: plaintextBytes.length,
              ),
            ),
          ],
          groupContentAuthoring: authoringContext,
        );

        expect(first.state, PreparedGroupMediaBlobState.retained);
        expect(strictRepository.stageCalls, 1);
        expect(firstAttempts.map((attempt) => attempt.recipient), <String>[
          'transport-remote',
          'transport-sibling',
        ]);
        expect(
          firstAttempts.map((attempt) => attempt.blobId).toSet(),
          hasLength(1),
        );
        expect(
          firstAttempts.map((attempt) => attempt.path).toSet(),
          hasLength(1),
        );
        for (final attempt in firstAttempts) {
          expect(attempt.bytes, ciphertextBytes);
        }

        final storedBeforeRestart = strictRepository.rows.singleWhere(
          (row) => row.recipientPeerId == 'transport-remote',
        );
        final survivorBeforeRestart = strictRepository.rows.singleWhere(
          (row) => row.recipientPeerId == 'transport-sibling',
        );
        expect(
          storedBeforeRestart.state,
          DirectMediaBlobCustodyState.outgoingStored,
        );
        expect(
          survivorBeforeRestart.state,
          DirectMediaBlobCustodyState.outgoingPrepared,
        );
        expect(
          survivorBeforeRestart.custodyBlobId,
          storedBeforeRestart.custodyBlobId,
        );
        expect(
          survivorBeforeRestart.ciphertextRelativePath,
          storedBeforeRestart.ciphertextRelativePath,
        );

        // A roster change after durable staging must neither add a blob target
        // nor replace the original target matrix during restart recovery.
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-late',
            username: 'Late',
            role: MemberRole.reader,
            publicKey: 'pk-late',
            devices: const <GroupMemberDeviceIdentity>[
              GroupMemberDeviceIdentity(
                deviceId: 'device-late',
                transportPeerId: 'transport-late',
                deviceSigningPublicKey: 'pk-late-device',
              ),
            ],
            joinedAt: DateTime.utc(2026, 8, 14, 10, 1),
          ),
        );

        final retryAttempts =
            <
              ({String recipient, String blobId, String path, List<int> bytes})
            >[];
        final restartedCoordinator = PreparedGroupMediaBlobCustodyCoordinator(
          artifactStore: GroupMediaBlobArtifactStore(
            documentsDirectoryProvider: () async => root,
          ),
          prepareArtifact:
              ({required Bridge bridge, required String localFilePath}) async =>
                  throw StateError(
                    'persisted strict retry must never encrypt again',
                  ),
          clock: () => DateTime.utc(2026, 8, 14, 10, 5),
          strictUpload:
              ({
                required Bridge bridge,
                required String custodyBlobId,
                required String recipientPeerId,
                required String ciphertextPath,
                required String contentHash,
                required int ciphertextSize,
              }) async {
                final bytes = await File(ciphertextPath).readAsBytes();
                retryAttempts.add((
                  recipient: recipientPeerId,
                  blobId: custodyBlobId,
                  path: ciphertextPath,
                  bytes: List<int>.unmodifiable(bytes),
                ));
                return <String, dynamic>{
                  'ok': true,
                  'id': custodyBlobId,
                  'storeStatus': 'stored',
                  'custodyKind': groupMediaBlobCustodyKind,
                  'custodyContract': groupMediaBlobCustodyContract,
                  'contentHash': contentHash,
                  'size': ciphertextSize,
                  'mime': groupMediaBlobTransportMime,
                  'expiresAtMs': DateTime.utc(
                    2036,
                    8,
                    21,
                  ).millisecondsSinceEpoch,
                  'custodyRelayPeerId': 'relay-sibling',
                };
              },
        );
        final legacyUpload = FakeUploadMediaFn();
        final strictP2p = FakeP2PService(
          initialState: const NodeState(
            isStarted: true,
            peerId: 'transport-current',
            circuitAddresses: <String>['/p2p-circuit/strict'],
          ),
          storeInInboxResult: true,
        );

        await retryIncompleteGroupUploads(
          groupRepo: groupRepo,
          groupMsgRepo: groupMsgRepo,
          mediaAttachmentRepo: strictRepository,
          bridge: bridge,
          p2pService: strictP2p,
          identityRepo: identityRepo,
          uploadMediaFn: legacyUpload.call,
          mediaFileManager: mediaFileManager,
          preparedGroupMediaBlobCustodyCoordinator: restartedCoordinator,
          strictGroupCustodyOnly: true,
        );

        expect(retryAttempts, hasLength(1));
        expect(retryAttempts.single.recipient, 'transport-sibling');
        expect(
          retryAttempts.single.blobId,
          survivorBeforeRestart.custodyBlobId,
        );
        expect(retryAttempts.single.path, firstAttempts.first.path);
        expect(retryAttempts.single.bytes, ciphertextBytes);
        expect(
          retryAttempts.map((attempt) => attempt.recipient),
          isNot(contains('transport-late')),
          reason:
              'restart recovery must not derive targets from the live roster',
        );
        expect(legacyUpload.callCount, 0);
        expect(
          strictRepository.stageCalls,
          1,
          reason: 'restart adopts the generation instead of staging a new one',
        );
        expect(
          strictRepository.rows.map((row) => row.state).toSet(),
          <DirectMediaBlobCustodyState>{
            DirectMediaBlobCustodyState.outgoingStored,
          },
        );
        final storedAfterRestart = strictRepository.rows.singleWhere(
          (row) => row.recipientPeerId == 'transport-remote',
        );
        expect(
          storedAfterRestart.exactDatabaseProjectionMatches(
            storedBeforeRestart,
          ),
          isTrue,
          reason: 'the already-stored target is not uploaded or rewritten',
        );
        final artifactFiles = await root
            .list(recursive: true)
            .where((entry) => entry is File && entry.path.endsWith('.blob'))
            .cast<File>()
            .toList();
        expect(artifactFiles, hasLength(1));
        expect(await artifactFiles.single.readAsBytes(), ciphertextBytes);

        // Once protected content binds the exact blob proofs, the blob retry
        // owner is retired for this parent. Even an upload-pending shortlist
        // observed after every signed expiry has elapsed must not remint the
        // proofs or build a second protected content envelope.
        final boundRows =
            List<DirectMediaBlobCustodyRow>.from(strictRepository.rows)..sort(
              (left, right) =>
                  left.recipientPeerId!.compareTo(right.recipientPeerId!),
            );
        final boundAttachment =
            (await strictRepository.getAttachmentsForMessage(
              messageId,
              owner: MediaOwnerLane.group,
            )).single;
        final boundManifest = ProtectedGroupMediaManifest(
          groupId: 'group-1',
          messageId: messageId,
          attachments: <ProtectedGroupMediaAttachmentCommitment>[
            ProtectedGroupMediaAttachmentCommitment(
              attachmentId: attachmentId,
              custodyBlobId: boundRows.first.custodyBlobId,
              ciphertextSha256: ciphertextHash,
              ciphertextSize: ciphertextBytes.length,
              mime: boundAttachment.mime,
              mediaType: boundAttachment.mediaType,
              width: boundAttachment.width,
              height: boundAttachment.height,
              encryptionKeyBase64: boundAttachment.encryptionKeyBase64!,
              encryptionNonce: boundAttachment.encryptionNonce!,
              encryptionScheme: boundAttachment.encryptionScheme!,
              caption: parent.text,
              targets: boundRows.map(
                (row) => GroupMediaBlobTargetCommitment(
                  recipientPeerId: row.recipientPeerId!,
                  expiresAtMs: row.expiresAtMs!,
                ),
              ),
            ),
          ],
        );
        final contentAt = DateTime.utc(2026, 8, 14, 10, 6);
        final wireContent = jsonEncode(<String, Object?>{
          'groupId': 'group-1',
          'senderId': 'peer-admin',
          'senderDeviceId': 'device-current',
          'transportPeerId': 'transport-current',
          'senderUsername': 'Admin',
          'keyEpoch': 0,
          'text': parent.text,
          'timestamp': fixedGroupContentUtc(contentAt),
          'messageId': messageId,
          'logicalDeliveryId': messageId,
          'mediaManifest': boundManifest.encode(),
          'mediaManifestHash': boundManifest.fingerprintSha256,
        });
        final replayEnvelope = await buildGroupOfflineReplayEnvelope(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: 'group-1',
          payloadType: groupOfflineReplayPayloadTypeMessage,
          plaintext: wireContent,
          senderPeerId: 'peer-admin',
          senderPublicKey: 'pk-admin',
          senderPrivateKey: 'sk-admin',
          messageId: messageId,
          senderDeviceId: 'device-current',
          senderTransportPeerId: 'transport-current',
          recipientPeerIds: boundManifest.recipientPeerIds,
          contentAuthorityVersion: authoringContext.authorityVersion,
          contentEventId: messageId,
          mediaManifest: boundManifest,
        );
        final boundRetryPayload = jsonEncode(<String, Object?>{
          'groupId': 'group-1',
          'message': replayEnvelope,
          'custodyContract': ackOrExpiryInboxCustodyContract,
          'custodyKind': groupContentCustodyKind,
          'recipientPeerIds': boundManifest.recipientPeerIds,
        });
        final decodedBoundContent = GroupContentRetryPayload.decode(
          boundRetryPayload,
        );
        expect(
          decodedBoundContent.mediaManifest?.encode(),
          boundManifest.encode(),
        );

        final boundParent = parent.copyWith(
          transportPeerId: 'transport-current',
          logicalDeliveryId: messageId,
          keyGeneration: 0,
          status: GroupMessage.statusQueuedOffline,
          wireEnvelope: wireContent,
          inboxStored: false,
          inboxRetryPayload: boundRetryPayload,
        );
        final contentMessages = _StrictBoundContentMessageRepository();
        await contentMessages.bindPrepared(boundParent);
        await strictRepository.saveAttachment(
          boundAttachment.copyWith(downloadStatus: 'upload_pending'),
          owner: MediaOwnerLane.group,
        );
        final artifactPathBeforeBindingRetry = artifactFiles.single.path;
        final artifactBytesBeforeBindingRetry = await artifactFiles.single
            .readAsBytes();
        final artifactModifiedBeforeBindingRetry =
            (await artifactFiles.single.stat()).modified;
        final bridgeCommandsBeforeBindingRetry = List<String>.from(
          bridge.commandLog,
        );
        var postBindingUploadCalls = 0;
        final postBindingCoordinator = PreparedGroupMediaBlobCustodyCoordinator(
          artifactStore: GroupMediaBlobArtifactStore(
            documentsDirectoryProvider: () async => root,
          ),
          clock: () => DateTime.utc(2036, 8, 22),
          strictUpload:
              ({
                required Bridge bridge,
                required String custodyBlobId,
                required String recipientPeerId,
                required String ciphertextPath,
                required String contentHash,
                required int ciphertextSize,
              }) async {
                postBindingUploadCalls++;
                return <String, dynamic>{
                  'ok': true,
                  'id': custodyBlobId,
                  'storeStatus': 'stored',
                  'custodyKind': groupMediaBlobCustodyKind,
                  'custodyContract': groupMediaBlobCustodyContract,
                  'contentHash': contentHash,
                  'size': ciphertextSize,
                  'mime': groupMediaBlobTransportMime,
                  'expiresAtMs': DateTime.utc(
                    2036,
                    9,
                    22,
                  ).millisecondsSinceEpoch,
                  'custodyRelayPeerId': 'relay-reminted',
                };
              },
        );

        final postBindingRetried = await retryIncompleteGroupUploads(
          groupRepo: groupRepo,
          groupMsgRepo: contentMessages,
          mediaAttachmentRepo: strictRepository,
          bridge: bridge,
          p2pService: strictP2p,
          identityRepo: identityRepo,
          uploadMediaFn: legacyUpload.call,
          mediaFileManager: mediaFileManager,
          preparedGroupMediaBlobCustodyCoordinator: postBindingCoordinator,
          strictGroupCustodyOnly: true,
        );

        expect(postBindingRetried, 0);
        expect(postBindingUploadCalls, 0);
        expect(bridge.commandLog, bridgeCommandsBeforeBindingRetry);
        expect(legacyUpload.callCount, 0);
        final rowsAfterBindingRetry = strictRepository.rows.toList()
          ..sort(
            (left, right) =>
                left.recipientPeerId!.compareTo(right.recipientPeerId!),
          );
        expect(rowsAfterBindingRetry, hasLength(boundRows.length));
        for (var index = 0; index < boundRows.length; index++) {
          expect(
            rowsAfterBindingRetry[index].exactDatabaseProjectionMatches(
              boundRows[index],
            ),
            isTrue,
            reason: 'signed blob proof $index is immutable after binding',
          );
        }
        final parentAfterBindingRetry = await contentMessages.getMessage(
          messageId,
        );
        expect(parentAfterBindingRetry?.wireEnvelope, wireContent);
        expect(parentAfterBindingRetry?.inboxRetryPayload, boundRetryPayload);
        expect(artifactFiles.single.path, artifactPathBeforeBindingRetry);
        expect(
          await artifactFiles.single.readAsBytes(),
          artifactBytesBeforeBindingRetry,
        );
        expect(
          (await artifactFiles.single.stat()).modified,
          artifactModifiedBeforeBindingRetry,
        );

        // The immutable signed payload remains actionable by the production
        // protected-content retry owner, which converges the parent with its
        // original expiry ceilings instead of reminting blob proof.
        final contentRetried = await retryFailedGroupInboxStores(
          bridge: bridge,
          msgRepo: contentMessages,
          groupRepo: groupRepo,
          groupContentInboxStore: strictInboxStore,
          strictContentOnly: true,
          classifyStrictContentAuthority:
              ({
                required groupId,
                required observedAuthority,
                required contentAt,
                required contentEventId,
              }) async =>
                  ProtectedGroupContentRetryAuthorityDisposition.eligible,
        );
        expect(contentRetried, 1);
        expect(
          strictInboxStore.boundedStores,
          decodedBoundContent.pendingRecipientPeerIds
              .map(
                (recipient) => (
                  recipientPeerId: recipient,
                  expiresAtOrBeforeMs: boundManifest
                      .contentExpiresAtOrBeforeMsFor(recipient),
                ),
              )
              .toList(growable: false),
        );
        final convergedParent = await contentMessages.getMessage(messageId);
        expect(convergedParent?.status, 'sent');
        expect(convergedParent?.inboxStored, isTrue);
        expect(convergedParent?.wireEnvelope, isNull);
        expect(convergedParent?.inboxRetryPayload, isNull);
      },
    );

    test(
      'P269 foreground image and voice uploads lose authority when the group dissolves between durable prep and the shared leaf',
      () async {
        final activeGroup = await groupRepo.getGroup('group-1');
        expect(activeGroup, isNotNull);

        final plans = <({String id, String mime, String mediaType})>[
          (
            id: 'foreground-image-after-dissolve',
            mime: 'image/jpeg',
            mediaType: 'image',
          ),
          (
            id: 'foreground-voice-after-dissolve',
            mime: 'audio/mp4',
            mediaType: 'audio',
          ),
        ];
        final parents = <GroupMessage>[];
        final attachments = <MediaAttachment>[];
        for (final plan in plans) {
          final parent = GroupMessage(
            id: 'msg-${plan.id}',
            groupId: 'group-1',
            senderPeerId: 'peer-admin',
            senderUsername: 'Admin',
            text: '',
            timestamp: DateTime.utc(2026, 7, 22, 18),
            status: 'sending',
            isIncoming: false,
            createdAt: DateTime.utc(2026, 7, 22, 18),
          );
          final attachment = MediaAttachment(
            id: plan.id,
            messageId: parent.id,
            mime: plan.mime,
            size: 2048,
            mediaType: plan.mediaType,
            durationMs: plan.mediaType == 'audio' ? 1200 : null,
            localPath: 'pending_uploads/${parent.id}/${plan.id}',
            downloadStatus: 'upload_pending',
            createdAt: '2026-07-22T18:00:00.000Z',
            uploadRetryCount: 0,
            downloadRetryCount: 0,
            ownerLane: MediaOwnerLane.group,
          );
          await groupMsgRepo.saveMessage(parent);
          await mediaRepo.saveAttachment(
            attachment,
            owner: MediaOwnerLane.group,
          );
          parents.add(parent);
          attachments.add(attachment);
        }

        // The durable rows were prepared while active. The authenticated
        // dissolve wins before either foreground leaf acquires the membership
        // phase, so neither image nor voice may reach encryption/relay upload.
        await groupRepo.updateGroup(
          activeGroup!.copyWith(
            isDissolved: true,
            dissolvedAt: DateTime.utc(2026, 7, 22, 18, 1),
            dissolvedBy: 'peer-admin',
          ),
        );

        var uploadCalls = 0;
        var completionBuildCalls = 0;
        for (var index = 0; index < plans.length; index++) {
          final result = await runForegroundGroupUploadLeaf(
            groupRepository: groupRepo,
            groupMessageRepository: groupMsgRepo,
            mediaAttachmentRepository: mediaRepo,
            expectedParent: parents[index],
            expectedAttachment: attachments[index],
            senderPeerId: 'peer-admin',
            upload: (_) async {
              uploadCalls++;
              return UploadMediaSucceeded(
                attachments[index].copyWith(downloadStatus: 'done'),
              );
            },
            buildCompleted: (uploaded) async {
              completionBuildCalls++;
              return uploaded;
            },
          );

          expect(result, isNull, reason: plans[index].mediaType);
          final durable = await mediaRepo.getAttachmentById(plans[index].id);
          expect(durable?.downloadStatus, 'upload_pending');
          expect(durable?.localPath, attachments[index].localPath);
        }
        expect(uploadCalls, 0);
        expect(completionBuildCalls, 0);
      },
    );

    test(
      'P269 sameExactGroupRetryAttachment treats null retry counters as database zero but remains strict for every other authority field',
      () {
        const expected = MediaAttachment(
          id: 'blob-p269-authority',
          messageId: 'msg-p269-authority',
          mime: 'image/jpeg',
          size: 2048,
          mediaType: 'image',
          width: 640,
          height: 480,
          durationMs: 1200,
          localPath: 'pending_uploads/msg-p269-authority/blob.jpg',
          downloadStatus: 'upload_pending',
          createdAt: '2026-07-22T08:00:00.000Z',
          waveform: <double>[0.1, 0.5, 0.9],
          contentHash:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          thumbnailHash:
              'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
          encryptionKeyBase64: 'local-key',
          encryptionNonce: 'local-nonce',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          ownerLane: MediaOwnerLane.group,
        );
        final databaseDefaulted = expected.copyWith(
          uploadRetryCount: 0,
          downloadRetryCount: 0,
        );

        expect(
          sameExactGroupRetryAttachment(databaseDefaulted, expected),
          isTrue,
          reason: 'SQLite reloads omitted NOT NULL counters as zero',
        );

        final nonCounterMutations = <MediaAttachment>[
          databaseDefaulted.copyWith(id: 'different-blob'),
          databaseDefaulted.copyWith(messageId: 'different-message'),
          databaseDefaulted.copyWith(ownerLane: MediaOwnerLane.direct),
          databaseDefaulted.copyWith(mime: 'image/png'),
          databaseDefaulted.copyWith(size: 4096),
          databaseDefaulted.copyWith(mediaType: 'video'),
          databaseDefaulted.copyWith(width: 641),
          databaseDefaulted.copyWith(height: 481),
          databaseDefaulted.copyWith(durationMs: 1201),
          databaseDefaulted.copyWith(
            localPath: 'pending_uploads/msg-p269-authority/other.jpg',
          ),
          databaseDefaulted.copyWith(downloadStatus: 'done'),
          databaseDefaulted.copyWith(createdAt: '2026-07-22T08:00:01.000Z'),
          databaseDefaulted.copyWith(waveform: const <double>[0.1, 0.6, 0.9]),
          databaseDefaulted.copyWith(
            contentHash:
                'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
          ),
          databaseDefaulted.copyWith(
            thumbnailHash:
                'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd',
          ),
          databaseDefaulted.copyWith(encryptionKeyBase64: 'different-key'),
          databaseDefaulted.copyWith(encryptionNonce: 'different-nonce'),
          databaseDefaulted.copyWith(encryptionScheme: 'different-scheme'),
        ];
        for (final mutation in nonCounterMutations) {
          expect(
            sameExactGroupRetryAttachment(mutation, expected),
            isFalse,
            reason: 'Only database-default-equivalent counters may normalize',
          );
        }

        expect(
          sameExactGroupRetryAttachment(
            databaseDefaulted.copyWith(uploadRetryCount: 1),
            expected,
          ),
          isFalse,
        );
        expect(
          sameExactGroupRetryAttachment(
            databaseDefaulted.copyWith(downloadRetryCount: 1),
            expected,
          ),
          isFalse,
        );
      },
    );

    test(
      'automatic pass with no OS connectivity issues no upload and leaves queued rows untouched',
      () async {
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: 'msg-offline-gate',
            groupId: 'group-1',
            senderPeerId: 'peer-admin',
            senderUsername: 'Admin',
            text: 'Offline upload',
            timestamp: DateTime.utc(2026, 1, 1),
            status: 'queued_offline',
            isIncoming: false,
            createdAt: DateTime.utc(2026, 1, 1),
          ),
        );
        await mediaRepo.saveAttachment(
          _pendingAttachment(
            id: 'pending-offline-gate',
            messageId: 'msg-offline-gate',
            localPath: 'pending_uploads/msg-offline-gate/photo.jpg',
          ),
          owner: MediaOwnerLane.group,
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
          requireOsConnectivity: true,
          connectivityProbe: () async => false,
        );

        expect(count, 0);
        expect(uploadFn.callCount, 0);
        final rows = await mediaRepo.getAttachmentsForMessage(
          'msg-offline-gate',
          owner: MediaOwnerLane.group,
        );
        expect(rows.single.downloadStatus, 'upload_pending');
        expect(rows.single.uploadRetryCount, isNull);
        expect(
          (await groupMsgRepo.getMessage('msg-offline-gate'))?.status,
          'queued_offline',
        );
      },
    );

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
      'P269 successful incomplete-group recovery carries both persisted counters into completion and settles only once',
      () async {
        const messageId = 'msg-p269-retry-completion';
        const attachmentId = 'blob-p269-retry-completion';
        const createdAt = '2026-07-22T09:15:00.000Z';
        const thumbnailHash =
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: messageId,
            groupId: 'group-1',
            senderPeerId: 'peer-admin',
            senderUsername: 'Admin',
            text: 'Durable retry completion',
            timestamp: DateTime.utc(2026, 7, 22, 9, 15),
            status: 'failed',
            isIncoming: false,
            createdAt: DateTime.utc(2026, 7, 22, 9, 15),
          ),
        );
        await mediaRepo.saveAttachment(
          _pendingAttachment(
            id: attachmentId,
            messageId: messageId,
            localPath: 'pending_uploads/$messageId/photo.jpg',
            uploadRetryCount: 2,
            downloadRetryCount: 1,
            createdAt: createdAt,
            thumbnailHash: thumbnailHash,
          ),
          owner: MediaOwnerLane.group,
        );
        uploadFn.willReturn(
          _doneAttachment(id: attachmentId, messageId: messageId).copyWith(
            size: 8192,
            localPath: 'media/group-1/$attachmentId.jpg',
            createdAt: '2036-01-02T03:04:05.000Z',
          ),
        );

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
        final callsAfterFirstPass = uploadFn.callCount;
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

        expect(first, 1);
        expect(second, 0);
        expect(callsAfterFirstPass, 1);
        expect(uploadFn.callCount, callsAfterFirstPass);
        expect(_publishedGroupPayloads(bridge), hasLength(1));
        final persisted = await mediaRepo.getAttachmentById(attachmentId);
        expect(persisted?.downloadStatus, 'done');
        expect(persisted?.uploadRetryCount, 2);
        expect(persisted?.downloadRetryCount, 1);
        expect(persisted?.createdAt, createdAt);
        expect(persisted?.thumbnailHash, thumbnailHash);
        expect(persisted?.size, 8192);
        expect(persisted?.localPath, 'media/group-1/$attachmentId.jpg');
      },
    );

    test(
      'manual Retry claims the complete unfinished set and rearms only at-ceiling rows',
      () async {
        const messageId = 'msg-manual-rearm';
        final parent = GroupMessage(
          id: messageId,
          groupId: 'group-1',
          senderPeerId: 'peer-admin',
          senderUsername: 'Admin',
          text: 'Manual media retry',
          timestamp: DateTime.utc(2026, 1, 1),
          status: 'failed',
          isIncoming: false,
          createdAt: DateTime.utc(2026, 1, 1),
          wireEnvelope: 'stale-envelope',
          inboxStored: true,
          inboxRetryPayload: 'stale-payload',
          retryAttemptCount: 4,
          nextEligibleAt: DateTime.utc(2026, 1, 2),
        );
        final terminal =
            _pendingAttachment(
              id: 'manual-terminal',
              messageId: messageId,
              localPath: 'pending_uploads/$messageId/terminal.jpg',
            ).copyWith(
              downloadStatus: 'upload_failed',
              uploadRetryCount: kMaxUploadRetries,
            );
        final pending = _pendingAttachment(
          id: 'manual-pending',
          messageId: messageId,
          localPath: 'pending_uploads/$messageId/pending.jpg',
          uploadRetryCount: 1,
        );
        final done = _doneAttachment(id: 'manual-done', messageId: messageId);
        await groupMsgRepo.saveMessage(parent);
        for (final attachment in [terminal, pending, done]) {
          await mediaRepo.saveAttachment(
            attachment,
            owner: MediaOwnerLane.group,
          );
        }
        uploadFn.willReturnForPath(
          _retryFixturePath(terminal.localPath!),
          _doneAttachment(id: terminal.id, messageId: messageId),
        );
        uploadFn.willReturnForPath(
          _retryFixturePath(pending.localPath!),
          _doneAttachment(id: pending.id, messageId: messageId),
        );
        final tracker = MediaUploadInFlightTracker();
        final rearm = _RecordingGroupManualUploadRetryRearm(
          groupMsgRepo: groupMsgRepo,
          mediaRepo: mediaRepo,
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
          messageId: messageId,
          manualRetry: true,
          uploadRetryRearmRepo: rearm,
          tryClaimUploadLease: (attachmentIds) => tracker.tryClaimAll(
            attachmentIds,
            source: MediaUploadTriggerSource.manual,
          ),
          releaseUploadLease: tracker.release,
        );

        expect(count, 1);
        expect(rearm.callCount, 1);
        expect(rearm.lastExpectations, hasLength(2));
        expect(
          rearm.lastExpectations!.map((item) => item.attachmentId).toSet(),
          {terminal.id, pending.id},
        );
        expect(uploadFn.callCount, 2);
        expect(tracker.inFlightCount, 0);
        final rows = await mediaRepo.getAttachmentsForMessage(
          messageId,
          owner: MediaOwnerLane.group,
        );
        expect(rows, hasLength(3));
        expect(
          rows.every((attachment) => attachment.downloadStatus == 'done'),
          isTrue,
        );
      },
    );

    test(
      'manual Retry proves identity and group authority before claim or rearm',
      () async {
        const noIdentityMessageId = 'msg-manual-no-identity';
        const missingGroupMessageId = 'msg-manual-missing-group';
        final parents = [
          for (final messageId in [noIdentityMessageId, missingGroupMessageId])
            GroupMessage(
              id: messageId,
              groupId: 'group-1',
              senderPeerId: 'peer-admin',
              senderUsername: 'Admin',
              text: 'Manual authority precheck',
              timestamp: DateTime.utc(2026, 1, 1),
              status: 'failed',
              isIncoming: false,
              createdAt: DateTime.utc(2026, 1, 1),
              wireEnvelope: 'stale-envelope',
            ),
        ];
        final attachments = [
          for (final messageId in [noIdentityMessageId, missingGroupMessageId])
            _pendingAttachment(
              id: '$messageId-terminal',
              messageId: messageId,
              localPath: 'pending_uploads/$messageId/terminal.jpg',
            ).copyWith(
              downloadStatus: 'upload_failed',
              uploadRetryCount: kMaxUploadRetries,
            ),
        ];
        for (final parent in parents) {
          await groupMsgRepo.saveMessage(parent);
        }
        for (final attachment in attachments) {
          await mediaRepo.saveAttachment(
            attachment,
            owner: MediaOwnerLane.group,
          );
        }
        final rearm = _RecordingGroupManualUploadRetryRearm(
          groupMsgRepo: groupMsgRepo,
          mediaRepo: mediaRepo,
        );
        final tracker = MediaUploadInFlightTracker();
        var claimCount = 0;
        MediaUploadLease? claim(Iterable<String> attachmentIds) {
          claimCount++;
          return tracker.tryClaimAll(
            attachmentIds,
            source: MediaUploadTriggerSource.manual,
          );
        }

        final noIdentityCount = await retryIncompleteGroupUploads(
          groupRepo: groupRepo,
          groupMsgRepo: groupMsgRepo,
          mediaAttachmentRepo: mediaRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: FakeIdentityRepository(),
          uploadMediaFn: uploadFn.call,
          mediaFileManager: mediaFileManager,
          messageId: noIdentityMessageId,
          manualRetry: true,
          uploadRetryRearmRepo: rearm,
          tryClaimUploadLease: claim,
          releaseUploadLease: tracker.release,
        );

        await groupRepo.deleteGroup('group-1');
        final missingGroupCount = await retryIncompleteGroupUploads(
          groupRepo: groupRepo,
          groupMsgRepo: groupMsgRepo,
          mediaAttachmentRepo: mediaRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          uploadMediaFn: uploadFn.call,
          mediaFileManager: mediaFileManager,
          messageId: missingGroupMessageId,
          manualRetry: true,
          uploadRetryRearmRepo: rearm,
          tryClaimUploadLease: claim,
          releaseUploadLease: tracker.release,
        );

        expect(noIdentityCount, 0);
        expect(missingGroupCount, 0);
        expect(claimCount, 0);
        expect(rearm.callCount, 0);
        expect(uploadFn.callCount, 0);
        expect(tracker.inFlightCount, 0);
        for (var i = 0; i < parents.length; i++) {
          expect(
            (await groupMsgRepo.getMessage(parents[i].id))!.toMap(),
            parents[i].toMap(),
          );
          expect(
            (await mediaRepo.getAttachmentById(attachments[i].id))!.toMap(),
            attachments[i].copyWith(ownerLane: MediaOwnerLane.group).toMap(),
          );
        }
      },
    );

    test(
      'over-limit group manual set is refused before claim or terminal rearm',
      () async {
        const messageId = 'msg-group-manual-over-limit';
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: messageId,
            groupId: 'group-1',
            senderPeerId: 'peer-admin',
            senderUsername: 'Admin',
            text: 'Over limit',
            timestamp: DateTime.utc(2026, 1, 1),
            status: 'failed',
            isIncoming: false,
            createdAt: DateTime.utc(2026, 1, 1),
          ),
        );
        for (var i = 0; i < kReuploadMaxAttachmentsPerMessage + 1; i++) {
          await mediaRepo.saveAttachment(
            _pendingAttachment(
              id: 'group-over-limit-$i',
              messageId: messageId,
              localPath: 'pending_uploads/$messageId/$i.jpg',
            ).copyWith(
              downloadStatus: 'upload_failed',
              uploadRetryCount: kMaxUploadRetries,
            ),
            owner: MediaOwnerLane.group,
          );
        }
        final rearm = _RecordingGroupManualUploadRetryRearm(
          groupMsgRepo: groupMsgRepo,
          mediaRepo: mediaRepo,
        );
        final tracker = MediaUploadInFlightTracker();
        var claimCount = 0;

        final count = await retryIncompleteGroupUploads(
          groupRepo: groupRepo,
          groupMsgRepo: groupMsgRepo,
          mediaAttachmentRepo: mediaRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          uploadMediaFn: uploadFn.call,
          mediaFileManager: mediaFileManager,
          messageId: messageId,
          manualRetry: true,
          uploadRetryRearmRepo: rearm,
          tryClaimUploadLease: (attachmentIds) {
            claimCount++;
            return tracker.tryClaimAll(
              attachmentIds,
              source: MediaUploadTriggerSource.manual,
            );
          },
          releaseUploadLease: tracker.release,
        );

        expect(count, 0);
        expect(claimCount, 0);
        expect(rearm.callCount, 0);
        expect(uploadFn.callCount, 0);
        expect(tracker.inFlightCount, 0);
      },
    );

    test(
      'group manual Retry loses to a held competitor before terminal mutation',
      () async {
        const messageId = 'msg-manual-held';
        final parent = GroupMessage(
          id: messageId,
          groupId: 'group-1',
          senderPeerId: 'peer-admin',
          senderUsername: 'Admin',
          text: 'Held retry',
          timestamp: DateTime.utc(2026, 1, 1),
          status: 'failed',
          isIncoming: false,
          createdAt: DateTime.utc(2026, 1, 1),
          wireEnvelope: 'stale-envelope',
        );
        final terminal =
            _pendingAttachment(
              id: 'manual-held-terminal',
              messageId: messageId,
              localPath: 'pending_uploads/$messageId/terminal.jpg',
            ).copyWith(
              downloadStatus: 'upload_failed',
              uploadRetryCount: kMaxUploadRetries,
            );
        await groupMsgRepo.saveMessage(parent);
        await mediaRepo.saveAttachment(terminal, owner: MediaOwnerLane.group);
        final tracker = MediaUploadInFlightTracker();
        final competitor = tracker.tryClaimAll([
          terminal.id,
        ], source: MediaUploadTriggerSource.foreground)!;
        final rearm = _RecordingGroupManualUploadRetryRearm(
          groupMsgRepo: groupMsgRepo,
          mediaRepo: mediaRepo,
        );
        final parentBefore = (await groupMsgRepo.getMessage(
          messageId,
        ))!.toMap();
        final attachmentBefore = (await mediaRepo.getAttachmentById(
          terminal.id,
        ))!.toMap();

        final count = await retryIncompleteGroupUploads(
          groupRepo: groupRepo,
          groupMsgRepo: groupMsgRepo,
          mediaAttachmentRepo: mediaRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          uploadMediaFn: uploadFn.call,
          mediaFileManager: mediaFileManager,
          messageId: messageId,
          manualRetry: true,
          uploadRetryRearmRepo: rearm,
          tryClaimUploadLease: (attachmentIds) => tracker.tryClaimAll(
            attachmentIds,
            source: MediaUploadTriggerSource.manual,
          ),
          releaseUploadLease: tracker.release,
        );

        expect(count, 0);
        expect(rearm.callCount, 0);
        expect(uploadFn.callCount, 0);
        expect(
          (await groupMsgRepo.getMessage(messageId))!.toMap(),
          parentBefore,
        );
        expect(
          (await mediaRepo.getAttachmentById(terminal.id))!.toMap(),
          attachmentBefore,
        );
        expect(tracker.release(competitor), isTrue);
      },
    );

    test(
      'one cancelled group sibling prevents claim and partial terminal rearm',
      () async {
        const messageId = 'msg-manual-cancelled';
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: messageId,
            groupId: 'group-1',
            senderPeerId: 'peer-admin',
            senderUsername: 'Admin',
            text: 'Cancelled sibling',
            timestamp: DateTime.utc(2026, 1, 1),
            status: 'failed',
            isIncoming: false,
            createdAt: DateTime.utc(2026, 1, 1),
          ),
        );
        final terminal =
            _pendingAttachment(
              id: 'manual-qualified-terminal',
              messageId: messageId,
              localPath: 'pending_uploads/$messageId/terminal.jpg',
            ).copyWith(
              downloadStatus: 'upload_failed',
              uploadRetryCount: kMaxUploadRetries,
            );
        final cancelled = _pendingAttachment(
          id: 'manual-cancelled',
          messageId: messageId,
          localPath: 'pending_uploads/$messageId/cancelled.jpg',
        ).copyWith(downloadStatus: 'upload_cancelled');
        await mediaRepo.saveAttachment(terminal, owner: MediaOwnerLane.group);
        await mediaRepo.saveAttachment(cancelled, owner: MediaOwnerLane.group);
        final tracker = MediaUploadInFlightTracker();
        var claimCount = 0;
        final rearm = _RecordingGroupManualUploadRetryRearm(
          groupMsgRepo: groupMsgRepo,
          mediaRepo: mediaRepo,
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
          messageId: messageId,
          manualRetry: true,
          uploadRetryRearmRepo: rearm,
          tryClaimUploadLease: (attachmentIds) {
            claimCount++;
            return tracker.tryClaimAll(
              attachmentIds,
              source: MediaUploadTriggerSource.manual,
            );
          },
          releaseUploadLease: tracker.release,
        );

        expect(count, 0);
        expect(claimCount, 0);
        expect(rearm.callCount, 0);
        expect(uploadFn.callCount, 0);
        expect(
          (await mediaRepo.getAttachmentById(terminal.id))!.downloadStatus,
          'upload_failed',
        );
        expect(
          (await mediaRepo.getAttachmentById(terminal.id))!.uploadRetryCount,
          kMaxUploadRetries,
        );
      },
    );

    test(
      'queued-offline typed failure invokes projection exactly once without sequential writes',
      () async {
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: 'msg-projection',
            groupId: 'group-1',
            senderPeerId: 'peer-admin',
            senderUsername: 'Admin',
            text: 'Queued upload',
            timestamp: DateTime.utc(2026, 1, 1),
            status: 'queued_offline',
            isIncoming: false,
            createdAt: DateTime.utc(2026, 1, 1),
          ),
        );
        await mediaRepo.saveAttachment(
          _pendingAttachment(
            id: 'pending-projection',
            messageId: 'msg-projection',
            localPath: 'pending_uploads/msg-projection/photo.jpg',
          ),
          owner: MediaOwnerLane.group,
        );
        final projection = _RecordingGroupUploadRetryProjection();
        var probeCalls = 0;

        final count = await retryIncompleteGroupUploads(
          groupRepo: groupRepo,
          groupMsgRepo: groupMsgRepo,
          mediaAttachmentRepo: mediaRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          uploadMediaFn: uploadFn.call,
          mediaFileManager: mediaFileManager,
          uploadRetryProjectionRepo: projection,
          connectivityProbe: () async {
            probeCalls++;
            return false;
          },
        );

        expect(count, 0);
        expect(probeCalls, 0);
        expect(uploadFn.callCount, 1);
        expect(projection.callCount, 1);
        expect(projection.messageId, 'msg-projection');
        expect(projection.attachmentId, 'pending-projection');
        expect(
          projection.failure?.disposition,
          UploadMediaDisposition.terminal,
        );
        final rows = await mediaRepo.getAttachmentsForMessage(
          'msg-projection',
          owner: MediaOwnerLane.group,
        );
        expect(rows.single.downloadStatus, 'upload_pending');
        expect(rows.single.uploadRetryCount, isNull);
        expect(
          (await groupMsgRepo.getMessage('msg-projection'))?.status,
          'queued_offline',
        );
      },
    );

    test(
      'missing local source projects once without a generic attachment rewrite',
      () async {
        const messageId = 'msg-missing-local-source';
        const attachmentId = 'pending-missing-local-source';
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: messageId,
            groupId: 'group-1',
            senderPeerId: 'peer-admin',
            senderUsername: 'Admin',
            text: 'Missing local source',
            timestamp: DateTime.utc(2026, 7, 20),
            status: 'failed',
            isIncoming: false,
            createdAt: DateTime.utc(2026, 7, 20),
          ),
        );
        await mediaRepo.saveAttachment(
          MediaAttachment(
            id: attachmentId,
            messageId: messageId,
            mime: 'image/jpeg',
            size: 2048,
            mediaType: 'image',
            downloadStatus: 'upload_pending',
            createdAt: DateTime.utc(2026, 7, 20).toIso8601String(),
          ),
          owner: MediaOwnerLane.group,
        );
        var sequentialAttachmentSaves = 0;
        mediaRepo.onSaveAttachment = (_) => sequentialAttachmentSaves++;
        final projection = _RecordingGroupUploadRetryProjection();

        final count = await retryIncompleteGroupUploads(
          groupRepo: groupRepo,
          groupMsgRepo: groupMsgRepo,
          mediaAttachmentRepo: mediaRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          uploadMediaFn: uploadFn.call,
          mediaFileManager: mediaFileManager,
          uploadRetryProjectionRepo: projection,
        );

        expect(count, 0);
        expect(uploadFn.callCount, 0);
        expect(projection.callCount, 1);
        expect(projection.messageId, messageId);
        expect(projection.attachmentId, attachmentId);
        expect(projection.failure?.stage, UploadMediaStage.localSource);
        expect(projection.failure?.errorCode, 'MISSING_LOCAL_SOURCE');
        expect(sequentialAttachmentSaves, 0);
        final persisted = await mediaRepo.getAttachmentById(attachmentId);
        expect(persisted?.downloadStatus, 'upload_pending');
        expect(persisted?.uploadRetryCount, isNull);
      },
    );

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
          owner: MediaOwnerLane.group,
        );

        final uploadStarted = Completer<void>();
        final allowUpload = Completer<void>();
        var uploadCallCount = 0;
        Future<UploadMediaOutcome> blockingUpload({
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
          return UploadMediaSucceeded(
            _doneAttachment(
              id: blobId ?? 'pending-concurrent-retry',
              messageId: 'msg-concurrent-retry',
            ),
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
      'PGC-010 action-first upload completion precedes B3 and blocks final send',
      () async {
        const messageId = 'pgc010-upload-action-first';
        const attachmentId = 'pgc010-upload-action-first-att';
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: messageId,
            groupId: 'group-1',
            senderPeerId: 'peer-admin',
            senderUsername: 'Admin',
            text: 'Finish the bounded upload leaf',
            timestamp: DateTime.utc(2026, 7, 20, 10),
            keyGeneration: 0,
            status: 'queued_offline',
            isIncoming: false,
            createdAt: DateTime.utc(2026, 7, 20, 10),
          ),
        );
        await mediaRepo.saveAttachment(
          _pendingAttachment(
            id: attachmentId,
            messageId: messageId,
            localPath: 'pending_uploads/$messageId/photo.jpg',
          ),
          owner: MediaOwnerLane.group,
        );

        final uploadStarted = Completer<void>();
        final uploadMayFinish = Completer<void>();
        Future<UploadMediaOutcome> blockingUpload({
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
          uploadStarted.complete();
          await uploadMayFinish.future;
          return UploadMediaSucceeded(
            _doneAttachment(id: blobId!, messageId: messageId),
          );
        }

        final retryFuture = retryIncompleteGroupUploads(
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

        var markerCommitted = false;
        final markerFuture = runGroupMembershipMutationLocked(
          groupId: 'group-1',
          action: () async {
            final current = await groupRepo.getGroup('group-1');
            await groupRepo.updateGroup(
              current!.copyWith(
                selfRemovedAt: DateTime.utc(2026, 7, 20, 10, 1),
              ),
            );
            markerCommitted = true;
          },
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(
          markerCommitted,
          isFalse,
          reason: 'B3 must wait for upload action plus exact completion',
        );

        uploadMayFinish.complete();
        await markerFuture;
        expect(markerCommitted, isTrue);
        expect(await retryFuture, 0);
        final attachments = await mediaRepo.getAttachmentsForMessage(
          messageId,
          owner: MediaOwnerLane.group,
        );
        expect(attachments.single.downloadStatus, 'done');
        expect(_publishedGroupPayloads(bridge), isEmpty);
      },
    );

    test(
      'PGC-010 B3-first membership phase stops incomplete upload dispatch',
      () async {
        const messageId = 'pgc010-upload-b3-first';
        const attachmentId = 'pgc010-upload-b3-first-att';
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: messageId,
            groupId: 'group-1',
            senderPeerId: 'peer-admin',
            senderUsername: 'Admin',
            text: 'Do not upload from the removed shell',
            timestamp: DateTime.utc(2026, 7, 20, 10, 2),
            keyGeneration: 0,
            status: 'queued_offline',
            isIncoming: false,
            createdAt: DateTime.utc(2026, 7, 20, 10, 2),
          ),
        );
        await mediaRepo.saveAttachment(
          _pendingAttachment(
            id: attachmentId,
            messageId: messageId,
            localPath: 'pending_uploads/$messageId/photo.jpg',
          ),
          owner: MediaOwnerLane.group,
        );

        final markerMayFinish = Completer<void>();
        final markerCommitted = Completer<void>();
        final markerFuture = runGroupMembershipMutationLocked(
          groupId: 'group-1',
          action: () async {
            final current = await groupRepo.getGroup('group-1');
            await groupRepo.updateGroup(
              current!.copyWith(
                selfRemovedAt: DateTime.utc(2026, 7, 20, 10, 3),
              ),
            );
            markerCommitted.complete();
            await markerMayFinish.future;
          },
        );
        await markerCommitted.future;

        var retryCompleted = false;
        final retryFuture = retryIncompleteGroupUploads(
          groupRepo: groupRepo,
          groupMsgRepo: groupMsgRepo,
          mediaAttachmentRepo: mediaRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          uploadMediaFn: uploadFn.call,
          mediaFileManager: mediaFileManager,
        ).whenComplete(() => retryCompleted = true);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(retryCompleted, isFalse, reason: 'upload must queue behind B3');
        expect(uploadFn.callCount, 0);

        markerMayFinish.complete();
        await markerFuture;
        expect(await retryFuture, 0);
        expect(uploadFn.callCount, 0);
        final attachments = await mediaRepo.getAttachmentsForMessage(
          messageId,
          owner: MediaOwnerLane.group,
        );
        expect(attachments.single.downloadStatus, 'upload_pending');
        expect(_publishedGroupPayloads(bridge), isEmpty);
      },
    );

    test(
      'manual retry for another message bypasses the automatic pass coalescer',
      () async {
        const automaticMessageId = 'msg-auto-coalescer-owner';
        const manualMessageId = 'msg-manual-coalescer-bypass';
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: automaticMessageId,
            groupId: 'group-1',
            senderPeerId: 'peer-admin',
            senderUsername: 'Admin',
            text: 'Automatic owner',
            timestamp: DateTime.utc(2026, 1, 1),
            status: 'queued_offline',
            isIncoming: false,
            createdAt: DateTime.utc(2026, 1, 1),
          ),
        );
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: manualMessageId,
            groupId: 'group-1',
            senderPeerId: 'peer-admin',
            senderUsername: 'Admin',
            text: 'Manual bypass',
            timestamp: DateTime.utc(2026, 1, 1),
            status: 'failed',
            isIncoming: false,
            createdAt: DateTime.utc(2026, 1, 1),
          ),
        );
        final automaticAttachment = _pendingAttachment(
          id: 'auto-coalescer-att',
          messageId: automaticMessageId,
          localPath: 'pending_uploads/$automaticMessageId/photo.jpg',
        );
        final manualAttachment =
            _pendingAttachment(
              id: 'manual-coalescer-att',
              messageId: manualMessageId,
              localPath: 'pending_uploads/$manualMessageId/photo.jpg',
            ).copyWith(
              downloadStatus: 'upload_failed',
              uploadRetryCount: kMaxUploadRetries,
            );
        await mediaRepo.saveAttachment(
          automaticAttachment,
          owner: MediaOwnerLane.group,
        );
        await mediaRepo.saveAttachment(
          manualAttachment,
          owner: MediaOwnerLane.group,
        );
        final automaticStarted = Completer<void>();
        final allowAutomatic = Completer<void>();
        Future<UploadMediaOutcome> blockingAutomaticUpload({
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
          if (!automaticStarted.isCompleted) automaticStarted.complete();
          await allowAutomatic.future;
          return UploadMediaSucceeded(
            _doneAttachment(id: blobId!, messageId: automaticMessageId),
          );
        }

        uploadFn.willReturn(
          _doneAttachment(id: manualAttachment.id, messageId: manualMessageId),
        );
        final automaticRetry = retryIncompleteGroupUploads(
          groupRepo: groupRepo,
          groupMsgRepo: groupMsgRepo,
          mediaAttachmentRepo: mediaRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          uploadMediaFn: blockingAutomaticUpload,
          mediaFileManager: mediaFileManager,
        );
        await automaticStarted.future;
        final tracker = MediaUploadInFlightTracker();
        final rearm = _RecordingGroupManualUploadRetryRearm(
          groupMsgRepo: groupMsgRepo,
          mediaRepo: mediaRepo,
        );

        final manualRetry = retryIncompleteGroupUploads(
          groupRepo: groupRepo,
          groupMsgRepo: groupMsgRepo,
          mediaAttachmentRepo: mediaRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          uploadMediaFn: uploadFn.call,
          mediaFileManager: mediaFileManager,
          messageId: manualMessageId,
          manualRetry: true,
          uploadRetryRearmRepo: rearm,
          tryClaimUploadLease: (attachmentIds) => tracker.tryClaimAll(
            attachmentIds,
            source: MediaUploadTriggerSource.manual,
          ),
          releaseUploadLease: tracker.release,
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(
          uploadFn.callCount,
          0,
          reason:
              'manual process-coalescer bypass still queues behind the active '
              'per-group membership leaf',
        );
        final overlappingAutomatic = await retryIncompleteGroupUploads(
          groupRepo: groupRepo,
          groupMsgRepo: groupMsgRepo,
          mediaAttachmentRepo: mediaRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          uploadMediaFn: blockingAutomaticUpload,
          mediaFileManager: mediaFileManager,
        );

        expect(overlappingAutomatic, 0);
        allowAutomatic.complete();
        final manualCount = await manualRetry;
        expect(await automaticRetry, 1);
        expect(manualCount, 1);
        expect(rearm.callCount, 1);
        expect(uploadFn.callCount, 1);
      },
    );

    test(
      'TC-15 group foreground lease defeats a full retry and the later winner '
      'releases after envelope settlement',
      () async {
        const messageId = 'msg-group-token-owned';
        const attachmentId = 'pending-group-token-owned';
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: messageId,
            groupId: 'group-1',
            senderPeerId: 'peer-admin',
            senderUsername: 'Admin',
            text: 'Token owned retry',
            timestamp: DateTime.utc(2026, 1, 1),
            status: 'failed',
            isIncoming: false,
            createdAt: DateTime.utc(2026, 1, 1),
          ),
        );
        await mediaRepo.saveAttachment(
          _pendingAttachment(
            id: attachmentId,
            messageId: messageId,
            localPath: 'pending_uploads/$messageId/photo.jpg',
          ),
          owner: MediaOwnerLane.group,
        );
        uploadFn.willReturn(
          _doneAttachment(id: attachmentId, messageId: messageId),
        );
        final tracker = MediaUploadInFlightTracker();
        final foregroundLease = tracker.tryClaimAll(const [
          attachmentId,
        ], source: MediaUploadTriggerSource.foreground)!;

        Future<int> runFullRetry() => retryIncompleteGroupUploads(
          groupRepo: groupRepo,
          groupMsgRepo: groupMsgRepo,
          mediaAttachmentRepo: mediaRepo,
          bridge: bridge,
          p2pService: p2pService,
          identityRepo: identityRepo,
          uploadMediaFn: uploadFn.call,
          mediaFileManager: mediaFileManager,
          tryClaimUploadLease: (attachmentIds) => tracker.tryClaimAll(
            attachmentIds,
            source: MediaUploadTriggerSource.full,
          ),
          releaseUploadLease: tracker.release,
        );

        expect(await runFullRetry(), 0);
        expect(uploadFn.callCount, 0);
        expect(tracker.isInFlight(attachmentId), isTrue);

        expect(tracker.release(foregroundLease), isTrue);
        expect(await runFullRetry(), 1);
        expect(uploadFn.callCount, 1);
        expect(tracker.isInFlight(attachmentId), isFalse);
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
          owner: MediaOwnerLane.group,
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
            owner: MediaOwnerLane.group,
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
          _doneAttachment(
            id: 'upload-pending-fwd',
            messageId: 'msg-fwd-upload',
          ),
        );
        uploadFn.willReturnForPath(
          await mediaFileManager.resolveStoredPath(
            'pending_uploads/msg-ord-upload/blob.jpg',
          ),
          _doneAttachment(
            id: 'upload-pending-ord',
            messageId: 'msg-ord-upload',
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
        expect(rows.map((row) => row.id).toSet(), {
          'msg-fwd-upload',
          'msg-ord-upload',
        });
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
          ).copyWith(downloadStatus: kMediaDownloadStatusIntegrityFailed),
          owner: MediaOwnerLane.group,
        );
        await mediaRepo.saveAttachment(
          _doneAttachment(
            id: 'download-transient-failed',
            messageId: 'msg-md012-download-only',
          ).copyWith(downloadStatus: 'failed'),
          owner: MediaOwnerLane.group,
        );
        await mediaRepo.saveAttachment(
          _pendingAttachment(
            id: 'upload-pending-md012',
            messageId: 'msg-md012-upload-owner',
            localPath: 'pending_uploads/msg-md012-upload-owner/blob.jpg',
          ),
          owner: MediaOwnerLane.group,
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
          owner: MediaOwnerLane.group,
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
          owner: MediaOwnerLane.group,
        );
        await mediaRepo.saveAttachment(
          _pendingAttachment(id: 'pending-1', messageId: 'msg-1'),
          owner: MediaOwnerLane.group,
        );
        // 228: the 1:1 row lives in the DIRECT lane; the group retrier's
        // lane-scoped query must never see it.
        await mediaRepo.saveAttachment(
          _pendingAttachment(id: 'dm-1', messageId: 'dm-1'),
          owner: MediaOwnerLane.direct,
        );
        uploadFn.willReturn(
          _doneAttachment(id: 'server-reassigned-id', messageId: 'msg-1'),
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
        final completed = await mediaRepo.getAttachmentsForMessage(
          'msg-1',
          owner: MediaOwnerLane.group,
        );
        expect(completed.every((a) => a.downloadStatus == 'done'), isTrue);
        expect(completed.map((a) => a.id), contains('pending-1'));
        expect(
          completed.map((a) => a.id),
          isNot(contains('server-reassigned-id')),
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
    test('group retrier never consumes same id direct pending media', () async {
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
    });

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
          ),
          owner: MediaOwnerLane.group,
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
          ).copyWith(durationMs: 4200, waveform: const [0.1, 0.5, 0.2]),
          owner: MediaOwnerLane.group,
        );
        await mediaRepo.saveAttachment(
          _pendingAttachment(
            id: 'image-pending-unrelated',
            messageId: 'msg-unrelated-pending',
            localPath: 'pending_uploads/msg-unrelated-pending/photo.jpg',
          ),
          owner: MediaOwnerLane.group,
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
          'msg-voice-targeted',
          owner: MediaOwnerLane.group,
        );
        expect(targetAttachments, hasLength(1));
        expect(targetAttachments.single.id, 'voice-pending-target');
        expect(targetAttachments.single.downloadStatus, 'done');
        expect(targetAttachments.single.mediaType, 'audio');
        expect(targetAttachments.single.durationMs, 4200);
        expect(targetAttachments.single.waveform, [0.1, 0.5, 0.2]);
        expect(
          (await mediaRepo.getAttachmentsForMessage(
            'msg-unrelated-pending',
            owner: MediaOwnerLane.group,
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
          ),
          owner: MediaOwnerLane.group,
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
          owner: MediaOwnerLane.group,
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
          owner: MediaOwnerLane.group,
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
          owner: MediaOwnerLane.group,
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
            owner: MediaOwnerLane.group,
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
        owner: MediaOwnerLane.group,
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
          owner: MediaOwnerLane.group,
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
          owner: MediaOwnerLane.group,
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
          owner: MediaOwnerLane.group,
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
            owner: MediaOwnerLane.group,
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
          owner: MediaOwnerLane.group,
        );
        await mediaRepo.saveAttachment(
          _pendingAttachment(
            id: 'pending-total-extra',
            messageId: 'msg-total-oversized-retry',
            size: 1,
          ),
          owner: MediaOwnerLane.group,
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
                owner: MediaOwnerLane.group,
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
          owner: MediaOwnerLane.group,
        );
        await mediaRepo.saveAttachment(
          _pendingAttachment(
            id: 'pending-gif',
            messageId: 'msg-gif-1',
            localPath: 'pending_uploads/msg-gif-1/funny.gif',
            mime: 'image/gif',
          ),
          owner: MediaOwnerLane.group,
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
          owner: MediaOwnerLane.group,
        );
        await mediaRepo.saveAttachment(
          _pendingAttachment(id: 'pending-1', messageId: 'msg-1'),
          owner: MediaOwnerLane.group,
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
          owner: MediaOwnerLane.group,
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
          (await mediaRepo.getUploadPendingAttachments(
            owner: MediaOwnerLane.group,
          )).single.uploadRetryCount,
          1,
        );

        await mediaRepo.saveAttachment(
          _pendingAttachment(
            id: 'pending-2',
            messageId: 'msg-2',
            uploadRetryCount: kMaxUploadRetries - 1,
          ),
          owner: MediaOwnerLane.group,
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
            owner: MediaOwnerLane.group,
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
          owner: MediaOwnerLane.group,
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

        final pending = await mediaRepo.getUploadPendingAttachments(
          owner: MediaOwnerLane.group,
        );
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
          owner: MediaOwnerLane.group,
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
      'late extra pending sibling blocks group send and staging cleanup',
      () async {
        const messageId = 'msg-group-late-extra';
        const originalId = 'group-original-stable';
        const extraId = 'group-late-extra';
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: messageId,
            groupId: 'group-1',
            senderPeerId: 'peer-admin',
            senderUsername: 'Admin',
            text: 'Late sibling guard',
            timestamp: DateTime.utc(2026, 1, 1),
            status: 'failed',
            isIncoming: false,
            createdAt: DateTime.utc(2026, 1, 1),
          ),
        );
        await mediaRepo.saveAttachment(
          _pendingAttachment(
            id: originalId,
            messageId: messageId,
            localPath: 'pending_uploads/$messageId/original.jpg',
          ),
          owner: MediaOwnerLane.group,
        );
        var insertedExtraSibling = false;
        mediaRepo.onSaveAttachment = (attachment) {
          if (!insertedExtraSibling &&
              attachment.id == originalId &&
              attachment.downloadStatus == 'done') {
            insertedExtraSibling = true;
            unawaited(
              mediaRepo.saveAttachment(
                _pendingAttachment(
                  id: extraId,
                  messageId: messageId,
                  localPath: 'pending_uploads/$messageId/extra.jpg',
                ),
                owner: MediaOwnerLane.group,
              ),
            );
          }
        };
        addTearDown(() {
          mediaRepo.onSaveAttachment = null;
        });
        uploadFn.willReturn(
          _doneAttachment(id: 'server-reassigned-id', messageId: messageId),
        );
        var cleanupCalled = false;
        mediaFileManager.onDeletePendingUploadDir = (_) => cleanupCalled = true;

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
        expect(bridge.commandLog, isNot(contains('group:publish')));
        expect(bridge.commandLog, isNot(contains('group:inboxStore')));
        expect(cleanupCalled, isFalse);
        final rows = await mediaRepo.getAttachmentsForMessage(
          messageId,
          owner: MediaOwnerLane.group,
        );
        expect(
          rows.map((row) => row.id),
          unorderedEquals([originalId, extraId]),
        );
        expect(
          rows.singleWhere((row) => row.id == originalId).downloadStatus,
          'done',
        );
        expect(
          rows.singleWhere((row) => row.id == extraId).downloadStatus,
          'upload_pending',
        );
        expect(rows.any((row) => row.id == 'server-reassigned-id'), isFalse);
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
          ),
          owner: MediaOwnerLane.group,
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

    test(
      'P269 completion persistence failures advance exact bounded sequence and discriminate lost authority',
      () async {
        Future<MediaAttachment> seedPending({
          required _CompletionFailureGroupMessageRepository messages,
          required InMemoryMediaAttachmentRepository attachments,
          required String suffix,
        }) async {
          final messageId = 'msg-p269-completion-$suffix';
          final attachmentId = 'blob-p269-completion-$suffix';
          await messages.saveMessage(
            GroupMessage(
              id: messageId,
              groupId: 'group-1',
              senderPeerId: 'peer-admin',
              senderUsername: 'Admin',
              text: 'Completion $suffix',
              timestamp: DateTime.utc(2026, 7, 22, 10),
              status: 'failed',
              isIncoming: false,
              createdAt: DateTime.utc(2026, 7, 22, 10),
            ),
          );
          final attachment = _pendingAttachment(
            id: attachmentId,
            messageId: messageId,
            localPath: 'pending_uploads/$messageId/photo.jpg',
            uploadRetryCount: 0,
            downloadRetryCount: 0,
          );
          await attachments.saveAttachment(
            attachment,
            owner: MediaOwnerLane.group,
          );
          return (await attachments.getAttachmentById(attachmentId))!;
        }

        Future<int> runPass({
          required _CompletionFailureGroupMessageRepository messages,
          required InMemoryMediaAttachmentRepository attachments,
          required FakeUploadMediaFn uploader,
        }) {
          return retryIncompleteGroupUploads(
            groupRepo: groupRepo,
            groupMsgRepo: messages,
            mediaAttachmentRepo: attachments,
            bridge: bridge,
            p2pService: p2pService,
            identityRepo: identityRepo,
            uploadMediaFn: uploader.call,
            mediaFileManager: mediaFileManager,
            requireOsConnectivity: true,
            connectivityProbe: () async => true,
          );
        }

        final boundedMedia = InMemoryMediaAttachmentRepository();
        final boundedMessages = _CompletionFailureGroupMessageRepository(
          mediaRepo: boundedMedia,
          throwOnCompletion: true,
        );
        final boundedPending = await seedPending(
          messages: boundedMessages,
          attachments: boundedMedia,
          suffix: 'throwing',
        );
        final boundedUpload = FakeUploadMediaFn()
          ..willReturn(
            _doneAttachment(
              id: boundedPending.id,
              messageId: boundedPending.messageId,
            ),
          );
        final durableSource = File(
          _retryFixturePath(boundedPending.localPath!),
        );
        final durableSourceBytes = durableSource.readAsBytesSync();
        final siblingFiles = <File, List<int>>{};
        for (final lane in const <String>['direct', 'group', 'private']) {
          final path = 'pending_uploads/p269-completion-sibling-$lane/blob.bin';
          final bytes = <int>[lane.length, 0x26, 0x09, 0x06];
          _writeRetryFixtureFile(
            localPath: path,
            mime: 'application/octet-stream',
            bytes: bytes,
          );
          siblingFiles[File(_retryFixturePath(path))] = bytes;
        }

        for (var attempt = 1; attempt <= kMaxUploadRetries; attempt++) {
          expect(
            await runPass(
              messages: boundedMessages,
              attachments: boundedMedia,
              uploader: boundedUpload,
            ),
            0,
          );
          final persisted = (await boundedMedia.getAttachmentById(
            boundedPending.id,
          ))!;
          expect(persisted.uploadRetryCount, attempt);
          expect(
            persisted.downloadStatus,
            attempt == kMaxUploadRetries ? 'upload_failed' : 'upload_pending',
          );
          expect(durableSource.readAsBytesSync(), durableSourceBytes);
          for (final sibling in siblingFiles.entries) {
            expect(sibling.key.readAsBytesSync(), sibling.value);
          }
        }

        expect(boundedUpload.callCount, kMaxUploadRetries);
        expect(boundedMessages.completionCalls, kMaxUploadRetries);
        expect(boundedMessages.projectionCalls, kMaxUploadRetries);
        expect(boundedMessages.appliedProjectionCalls, kMaxUploadRetries);
        expect(
          boundedMessages.projectedFailures,
          everyElement(
            isA<UploadMediaFailed>()
                .having(
                  (failure) => failure.stage,
                  'stage',
                  UploadMediaStage.consumerBoundary,
                )
                .having(
                  (failure) => failure.disposition,
                  'disposition',
                  UploadMediaDisposition.boundedRetryable,
                ),
          ),
        );

        expect(
          await runPass(
            messages: boundedMessages,
            attachments: boundedMedia,
            uploader: boundedUpload,
          ),
          0,
        );
        expect(boundedUpload.callCount, kMaxUploadRetries);
        expect(boundedMessages.completionCalls, kMaxUploadRetries);
        expect(boundedMessages.projectionCalls, kMaxUploadRetries);
        expect(durableSource.readAsBytesSync(), durableSourceBytes);

        final unchangedMedia = InMemoryMediaAttachmentRepository();
        final unchangedMessages = _CompletionFailureGroupMessageRepository(
          mediaRepo: unchangedMedia,
          throwOnCompletion: false,
        );
        final unchangedPending = await seedPending(
          messages: unchangedMessages,
          attachments: unchangedMedia,
          suffix: 'unchanged-false',
        );
        final unchangedUpload = FakeUploadMediaFn()
          ..willReturn(
            _doneAttachment(
              id: unchangedPending.id,
              messageId: unchangedPending.messageId,
            ),
          );

        expect(
          await runPass(
            messages: unchangedMessages,
            attachments: unchangedMedia,
            uploader: unchangedUpload,
          ),
          0,
        );
        final unchangedPersisted = (await unchangedMedia.getAttachmentById(
          unchangedPending.id,
        ))!;
        expect(unchangedPersisted.uploadRetryCount, 1);
        expect(unchangedPersisted.downloadStatus, 'upload_pending');
        expect(unchangedMessages.completionCalls, 1);
        expect(unchangedMessages.projectionCalls, 1);
        expect(unchangedMessages.appliedProjectionCalls, 1);

        final changedMedia = InMemoryMediaAttachmentRepository();
        final changedMessages = _CompletionFailureGroupMessageRepository(
          mediaRepo: changedMedia,
          throwOnCompletion: false,
        );
        final changedPending = await seedPending(
          messages: changedMessages,
          attachments: changedMedia,
          suffix: 'lost-authority',
        );
        changedMessages.beforeFalseCompletion =
            (expectedParent, expectedAttachment) async {
              await changedMessages.saveMessage(
                expectedParent.copyWith(text: 'Competing parent mutation'),
              );
            };
        final changedUpload = FakeUploadMediaFn()
          ..willReturn(
            _doneAttachment(
              id: changedPending.id,
              messageId: changedPending.messageId,
            ),
          );

        expect(
          await runPass(
            messages: changedMessages,
            attachments: changedMedia,
            uploader: changedUpload,
          ),
          0,
        );
        final changedPersisted = (await changedMedia.getAttachmentById(
          changedPending.id,
        ))!;
        expect(changedUpload.callCount, 1);
        expect(changedMessages.completionCalls, 1);
        expect(changedMessages.projectionCalls, 0);
        expect(changedMessages.appliedProjectionCalls, 0);
        expect(changedPersisted.uploadRetryCount, 0);
        expect(changedPersisted.downloadStatus, 'upload_pending');
        expect(
          (await changedMessages.getMessage(changedPending.messageId))?.text,
          'Competing parent mutation',
        );
      },
    );
  });
}
