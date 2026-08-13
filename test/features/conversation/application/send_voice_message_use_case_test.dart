import 'dart:convert';
import 'package:flutter_app/core/database/direct_event_fanout_contract.dart';
import 'package:flutter_app/core/database/helpers/media_attachments_db_helpers.dart'
    show DirectMediaFanoutStageAuthority, DirectMediaFanoutTargetBinding;
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/config/direct_media_blob_custody_client_flag.dart';
import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';
import 'package:flutter_app/core/database/direct_media_blob_custody.dart';
import 'package:flutter_app/core/media/direct_media_blob_artifact_store.dart';
import 'package:flutter_app/core/media/direct_media_custody_intent.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_file_path_convention.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/upload_retry_projection.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/conversation/application/prepared_direct_media_blob_custody_coordinator.dart';
import 'package:flutter_app/features/conversation/application/send_voice_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/audio_recording.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_inbox_custody_outbox_entry.dart';
import 'package:flutter_app/features/conversation/domain/models/direct_media_blob_generation_result.dart';
import 'package:flutter_app/features/conversation/domain/models/outgoing_direct_media_custody_stage_result.dart';
import 'package:flutter_app/features/conversation/domain/models/outgoing_ordinary_mutation_result.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import 'send_chat_message_use_case_test.dart'
    show FakeP2PService, FakeMessageRepository;
import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';

class _FakeMediaAttachmentRepository
    implements
        MediaAttachmentRepository,
        OutgoingOrdinaryAttemptStagingRepository,
        OutgoingDirectMediaInboxCustodyStagingRepository {
  final List<MediaAttachment> saved = [];
  final List<OutgoingOrdinaryAttemptKind> stagedKinds = [];
  FakeMessageRepository? directMediaCustodyMessageRepository;
  int directMediaCustodyStageCalls = 0;

  @override
  bool get supportsDirectMediaInboxCustody =>
      directMediaCustodyMessageRepository != null;

  @override
  Future<void> saveAttachment(
    MediaAttachment attachment, {
    required MediaOwnerLane owner,
  }) async {
    saved.add(attachment.copyWith(ownerLane: owner));
  }

  @override
  Future<int> deleteAttachmentsForContact(String contactPeerId) async => 0;

  @override
  Future<int> deleteAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async => 0;

  @override
  Future<int> markUploadPendingAttachmentsFailedForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async => 0;

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async {
    return saved
        .where(
          (attachment) =>
              attachment.messageId == messageId &&
              attachment.ownerLane == owner,
        )
        .toList();
  }

  @override
  Future<Map<String, List<MediaAttachment>>> getAttachmentsForMessages(
    List<String> messageIds, {
    required MediaOwnerLane owner,
  }) async {
    final result = <String, List<MediaAttachment>>{};
    for (final messageId in messageIds) {
      final attachments = await getAttachmentsForMessage(
        messageId,
        owner: MediaOwnerLane.direct,
      );
      if (attachments.isNotEmpty) {
        result[messageId] = attachments;
      }
    }
    return result;
  }

  @override
  Future<List<MediaAttachment>> getPendingDownloads() async => const [];

  @override
  Future<List<MediaAttachment>> getUploadPendingAttachments({
    required MediaOwnerLane owner,
  }) async => [];

  @override
  Future<void> updateDownloadStatus(String id, String downloadStatus) async {}

  @override
  Future<void> updateLocalPath(String id, String localPath) async {}

  @override
  Future<OutgoingOrdinaryMutationResult> stageOutgoingOrdinaryAttemptWithMedia({
    required OutgoingTransportMutationRepository messageMutationRepository,
    required ConversationMessage? expected,
    required ConversationMessage staged,
    required List<MediaAttachment> attachments,
    required OutgoingOrdinaryAttemptKind kind,
  }) async {
    stagedKinds.add(kind);
    if (attachments.isEmpty ||
        kind == OutgoingOrdinaryAttemptKind.tombstoneInitial ||
        kind == OutgoingOrdinaryAttemptKind.tombstoneRetry ||
        attachments.any(
          (attachment) =>
              attachment.id.isEmpty || attachment.messageId != staged.id,
        )) {
      return const OutgoingOrdinaryMutationResult(
        outcome: OutgoingOrdinaryMutationOutcome.refused,
        message: null,
      );
    }
    final parent = await messageMutationRepository.stageOutgoingOrdinaryAttempt(
      expected: expected,
      staged: staged,
      kind: kind,
    );
    if (!parent.authorizesTransport) return parent;
    if (parent.outcome == OutgoingOrdinaryMutationOutcome.idempotent &&
        attachments.any((attachment) {
          final index = saved.indexWhere(
            (candidate) => candidate.id == attachment.id,
          );
          return index < 0 ||
              !_sameOrdinaryOutgoingAttachmentAttempt(
                saved[index],
                attachment.copyWith(ownerLane: MediaOwnerLane.direct),
              );
        })) {
      return const OutgoingOrdinaryMutationResult(
        outcome: OutgoingOrdinaryMutationOutcome.refused,
        message: null,
      );
    }
    for (final attachment in attachments) {
      final direct = attachment.copyWith(ownerLane: MediaOwnerLane.direct);
      final index = saved.indexWhere((candidate) => candidate.id == direct.id);
      if (index < 0) {
        saved.add(direct);
      } else {
        final current = saved[index];
        saved[index] = direct.copyWith(
          isBookmarked: current.isBookmarked,
          lastPlaybackPositionMs: current.lastPlaybackPositionMs,
        );
      }
    }
    final committed = saved
        .where(
          (attachment) =>
              attachment.messageId == staged.id &&
              attachment.ownerLane == MediaOwnerLane.direct,
        )
        .toList(growable: false);
    return OutgoingOrdinaryMutationResult(
      outcome: parent.outcome,
      message: parent.message?.copyWith(media: committed),
    );
  }

  @override
  Future<OutgoingDirectMediaCustodyStageResult>
  stageOutgoingDirectMediaInboxCustody({
    required ConversationMessage? expected,
    required ConversationMessage staged,
    required List<MediaAttachment> attachments,
    required OutgoingOrdinaryAttemptKind kind,
    required String recipientPeerId,
    required String wireEnvelope,
    String? wireMediaBlobManifestHash,
    int? wireMediaBlobExpiresAtMs,
  }) async {
    directMediaCustodyStageCalls++;
    final messageRepository = directMediaCustodyMessageRepository;
    if (messageRepository == null || attachments.isEmpty) {
      return const OutgoingDirectMediaCustodyStageResult(
        outcome: OutgoingOrdinaryMutationOutcome.refused,
        message: null,
        custody: null,
      );
    }
    final parent = await messageRepository.stageOutgoingOrdinaryAttempt(
      expected: expected,
      staged: staged,
      kind: kind,
    );
    if (!parent.authorizesTransport || parent.message == null) {
      return OutgoingDirectMediaCustodyStageResult(
        outcome: parent.outcome,
        message: parent.message,
        custody: null,
      );
    }
    final committedMedia = attachments
        .map(
          (attachment) => attachment.copyWith(ownerLane: MediaOwnerLane.direct),
        )
        .toList(growable: false);
    saved
      ..removeWhere((attachment) => attachment.messageId == staged.id)
      ..addAll(committedMedia);
    final committed = parent.message!.copyWith(
      directMediaCustodyIntentId: null,
      media: committedMedia,
    );
    messageRepository.forceCurrent(committed);
    final incarnation =
        expected?.directMediaCustodyIntentId ??
        directMediaCustodyStageCalls.toRadixString(16).padLeft(32, '0');
    final custody = DirectInboxCustodyOutboxEntry(
      recipientPeerId: recipientPeerId,
      messageId: committed.id,
      incarnationId: incarnation,
      wireEnvelope: wireEnvelope,
      retryCount: 0,
      lastAttemptAt: null,
      lastErrorCode: null,
      createdAt: committed.createdAt,
      updatedAt: committed.createdAt,
    );
    messageRepository
            .directCustodyRows['$recipientPeerId\u0000${committed.id}'] =
        custody;
    return OutgoingDirectMediaCustodyStageResult(
      outcome: parent.outcome,
      message: committed,
      custody: custody,
    );
  }
}

bool _sameOrdinaryOutgoingAttachmentAttempt(
  MediaAttachment current,
  MediaAttachment candidate,
) {
  final currentMap = current.toMap()
    ..remove('is_bookmarked')
    ..remove('last_playback_position_ms')
    ..['upload_retry_count'] = current.uploadRetryCount ?? 0
    ..['download_retry_count'] = current.downloadRetryCount ?? 0;
  final candidateMap = candidate.toMap()
    ..remove('is_bookmarked')
    ..remove('last_playback_position_ms')
    ..['upload_retry_count'] = candidate.uploadRetryCount ?? 0
    ..['download_retry_count'] = candidate.downloadRetryCount ?? 0;
  return currentMap.length == candidateMap.length &&
      currentMap.entries.every(
        (entry) => candidateMap[entry.key] == entry.value,
      );
}

class _RecordingVoiceUploadProjection
    implements DirectUploadRetryProjectionRepository {
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
      state: UploadRetryProjectionState.retryPending,
    );
  }
}

/// 362: the prepared-voice fake with the fanout capability visible, so the
/// fresh-lane roster guard is reachable. The stagers must stay uncalled — a
/// fresh voice send on an initialized roster refuses BEFORE any owner work.
class _FanoutCapableVoiceRepository
    extends _StrictPreparedVoiceCustodyRepository
    implements OutgoingDirectLinkedMediaBlobFanoutRepository {
  _FanoutCapableVoiceRepository(FakeMessageRepository messages)
    : super(messages, _TestDirectMediaBlobState());

  @override
  bool get supportsDirectLinkedMediaBlobFanout => true;

  @override
  Future<DirectContactFanoutSnapshot?> readDirectContactFanoutSnapshotForMedia(
    String contactAccountPeerId,
  ) async => DirectContactFanoutSnapshot(
    contactAccountPeerId: contactAccountPeerId,
    contactAccountSigningPublicKey: 'voice-signing-key',
    rosterInitialized: true,
    targets: <DirectContactFanoutTargetFact>[
      DirectContactFanoutTargetFact(
        peerId: contactAccountPeerId,
        mlKemPublicKey: 'mlkem-legacy',
        isLegacyAccountTarget: true,
        fingerprint: 'f' * 64,
      ),
      const DirectContactFanoutTargetFact(
        peerId: 'peer-voice-linked-device',
        mlKemPublicKey: 'mlkem-linked',
        isLegacyAccountTarget: false,
        fingerprint:
            'a1b2c3d4a1b2c3d4a1b2c3d4a1b2c3d4a1b2c3d4a1b2c3d4a1b2c3d4a1b2c3d4',
        deviceId: 'voice-device-a',
        transportPublicKey: 'transport-key-voice-a',
      ),
    ],
  );

  @override
  Future<DirectMediaBlobGenerationStageResult>
  stageOutgoingDirectLinkedMediaBlobFanoutGeneration({
    required ConversationMessage expectedParent,
    required List<MediaAttachment> expectedAttachments,
    required List<MediaAttachment> preparedAttachments,
    required List<DirectMediaBlobCustodyRow> custodyRows,
    required String contactAccountPeerId,
    required DirectContactFanoutSnapshot expectedSnapshot,
  }) => throw StateError('fresh voice must refuse before the fanout owner');

  @override
  Future<DirectMediaFanoutInboxCustodyStageResult>
  stageOutgoingDirectMediaFanoutInboxCustody({
    required ConversationMessage expected,
    required ConversationMessage staged,
    required List<MediaAttachment> attachments,
    required String senderTransportPeerId,
    required String contactAccountPeerId,
    required DirectMediaFanoutStageAuthority authority,
    required DirectContactFanoutSnapshot? expectedSnapshot,
    required List<DirectMediaFanoutTargetBinding> targetBindings,
  }) => throw StateError('fresh voice must refuse before the fanout stage');
}

class _PreparedVoiceCustodyRepository extends _FakeMediaAttachmentRepository
    implements
        OutgoingDirectMediaInboxCustodyStagingRepository,
        OutgoingDirectMediaCustodyFailureRepository {
  _PreparedVoiceCustodyRepository(this.messageRepository);

  final FakeMessageRepository messageRepository;
  MediaAttachment? lastCustodyAttachment;
  int directMediaCustodyFailureCalls = 0;
  ConversationMessage? lastFailureParent;
  List<MediaAttachment>? lastFailureAttachments;
  String? lastFailedAttachmentId;

  @override
  bool get supportsDirectMediaInboxCustody => true;

  @override
  bool get supportsDirectMediaCustodyFailureProjection => true;

  @override
  Future<void> saveAttachment(
    MediaAttachment attachment, {
    required MediaOwnerLane owner,
  }) async {
    saved.removeWhere((candidate) => candidate.id == attachment.id);
    await super.saveAttachment(attachment, owner: owner);
  }

  @override
  Future<UploadRetryProjectionResult> projectDirectMediaCustodyUploadFailure({
    required ConversationMessage expectedParent,
    required List<MediaAttachment> expectedAttachments,
    required String failedAttachmentId,
    required UploadMediaFailed failure,
  }) async {
    directMediaCustodyFailureCalls++;
    lastFailureParent = expectedParent;
    lastFailureAttachments = List<MediaAttachment>.from(expectedAttachments);
    lastFailedAttachmentId = failedAttachmentId;

    final currentParent = messageRepository.existingMessages[expectedParent.id];
    final currentAttachments = saved
        .where((attachment) => attachment.messageId == expectedParent.id)
        .toList(growable: false);
    final currentById = <String, MediaAttachment>{
      for (final attachment in currentAttachments) attachment.id: attachment,
    };
    final hasGlobalCustody = messageRepository.directCustodyRows.values.any(
      (entry) => entry.messageId == expectedParent.id,
    );
    final exactParent =
        currentParent != null &&
        _sameTestDatabaseMap(expectedParent.toMap(), currentParent.toMap());
    final exactAttachments =
        currentAttachments.length == expectedAttachments.length &&
        currentById.length == currentAttachments.length &&
        expectedAttachments.every((attachment) {
          final current = currentById[attachment.id];
          return current != null &&
              _sameTestDatabaseMap(attachment.toMap(), current.toMap());
        });
    final intent = expectedParent.directMediaCustodyIntentId;
    final exactManifest =
        intent != null &&
        intent ==
            computeDirectMediaCustodyIntentId(
              messageId: expectedParent.id,
              attachmentIds: expectedAttachments.map(
                (attachment) => attachment.id,
              ),
            );
    final failed = currentById[failedAttachmentId];
    if (hasGlobalCustody ||
        !exactParent ||
        !exactAttachments ||
        !exactManifest ||
        failed == null ||
        failed.downloadStatus != 'upload_pending') {
      return const UploadRetryProjectionResult.notApplied();
    }

    switch (failure.disposition) {
      case UploadMediaDisposition.connectivityRetryable:
        return const UploadRetryProjectionResult(
          state: UploadRetryProjectionState.retryPending,
        );
      case UploadMediaDisposition.boundedRetryable:
      case UploadMediaDisposition.terminal:
        final terminal = failed.copyWith(downloadStatus: 'upload_failed');
        saved
          ..removeWhere((attachment) => attachment.id == failedAttachmentId)
          ..add(terminal);
        messageRepository.existingMessages[expectedParent.id] = currentParent
            .copyWith(status: 'failed');
        return const UploadRetryProjectionResult(
          state: UploadRetryProjectionState.terminal,
        );
    }
  }

  @override
  Future<OutgoingDirectMediaCustodyStageResult>
  stageOutgoingDirectMediaInboxCustody({
    required ConversationMessage? expected,
    required ConversationMessage staged,
    required List<MediaAttachment> attachments,
    required OutgoingOrdinaryAttemptKind kind,
    required String recipientPeerId,
    required String wireEnvelope,
    String? wireMediaBlobManifestHash,
    int? wireMediaBlobExpiresAtMs,
  }) async {
    directMediaCustodyStageCalls++;
    if (kind != OutgoingOrdinaryAttemptKind.existing ||
        expected?.directMediaCustodyIntentId == null ||
        attachments.length != 1) {
      return const OutgoingDirectMediaCustodyStageResult(
        outcome: OutgoingOrdinaryMutationOutcome.refused,
        message: null,
        custody: null,
      );
    }
    final attempted = attachments.single;
    final persisted = saved
        .where((candidate) => candidate.id == attempted.id)
        .toList(growable: false);
    final exactPendingIdentity =
        persisted.length == 1 &&
        persisted.single.messageId == attempted.messageId &&
        persisted.single.mime == attempted.mime &&
        persisted.single.size == attempted.size &&
        persisted.single.mediaType == attempted.mediaType &&
        persisted.single.durationMs == attempted.durationMs &&
        persisted.single.createdAt == attempted.createdAt &&
        persisted.single.waveform.toString() == attempted.waveform.toString() &&
        persisted.single.downloadStatus == 'upload_pending';
    if (!exactPendingIdentity) {
      return const OutgoingDirectMediaCustodyStageResult(
        outcome: OutgoingOrdinaryMutationOutcome.refused,
        message: null,
        custody: null,
      );
    }
    lastCustodyAttachment = attempted;
    final committedMedia = attachments
        .map(
          (attachment) => attachment.copyWith(ownerLane: MediaOwnerLane.direct),
        )
        .toList(growable: false);
    saved
      ..removeWhere((attachment) => attachment.messageId == staged.id)
      ..addAll(committedMedia);
    final committed = staged.copyWith(
      directMediaCustodyIntentId: null,
      media: committedMedia,
    );
    messageRepository.existingMessages[committed.id] = committed;
    final custody = DirectInboxCustodyOutboxEntry(
      recipientPeerId: recipientPeerId,
      messageId: committed.id,
      incarnationId: expected!.directMediaCustodyIntentId!,
      wireEnvelope: wireEnvelope,
      retryCount: 0,
      lastAttemptAt: null,
      lastErrorCode: null,
      createdAt: committed.createdAt,
      updatedAt: committed.createdAt,
    );
    messageRepository
            .directCustodyRows['$recipientPeerId\u0000${committed.id}'] =
        custody;
    return OutgoingDirectMediaCustodyStageResult(
      outcome: OutgoingOrdinaryMutationOutcome.applied,
      message: committed,
      custody: custody,
    );
  }
}

class _TestDirectMediaBlobState {
  final Map<String, DirectMediaBlobCustodyRow> rows =
      <String, DirectMediaBlobCustodyRow>{};
}

class _StrictPreparedVoiceCustodyRepository
    extends _PreparedVoiceCustodyRepository
    implements DirectMediaBlobCustodyRepository {
  _StrictPreparedVoiceCustodyRepository(
    super.messageRepository,
    this.blobState,
  );

  final _TestDirectMediaBlobState blobState;

  @override
  bool get supportsDirectMediaBlobCustody => true;

  @override
  Future<T> runDirectMediaBlobCustodyLifecycle<T>(
    Future<T> Function() action,
  ) => action();

  @override
  Future<DirectMediaBlobGenerationStageResult>
  stageOutgoingDirectMediaBlobGeneration({
    required ConversationMessage expectedParent,
    required List<MediaAttachment> expectedAttachments,
    required List<MediaAttachment> preparedAttachments,
    required List<DirectMediaBlobCustodyRow> custodyRows,
  }) async {
    if (expectedAttachments.length != preparedAttachments.length ||
        preparedAttachments.length != custodyRows.length ||
        preparedAttachments.isEmpty) {
      return const DirectMediaBlobGenerationStageResult.refused();
    }
    if (blobState.rows.isNotEmpty) {
      final winnerRows = blobState.rows.values
          .where((row) => row.messageId == expectedParent.id)
          .toList(growable: false);
      final winnerAttachments = saved
          .where((attachment) => attachment.messageId == expectedParent.id)
          .toList(growable: false);
      if (winnerRows.length != custodyRows.length ||
          winnerAttachments.length != preparedAttachments.length) {
        return const DirectMediaBlobGenerationStageResult.refused();
      }
      return DirectMediaBlobGenerationStageResult(
        outcome: DirectMediaBlobGenerationStageOutcome.idempotent,
        attachments: winnerAttachments,
        custodyRows: winnerRows,
      );
    }
    saved
      ..removeWhere((attachment) => attachment.messageId == expectedParent.id)
      ..addAll(preparedAttachments);
    for (final row in custodyRows) {
      blobState.rows[row.attachmentId] = row;
    }
    return DirectMediaBlobGenerationStageResult(
      outcome: DirectMediaBlobGenerationStageOutcome.applied,
      attachments: List<MediaAttachment>.from(preparedAttachments),
      custodyRows: List<DirectMediaBlobCustodyRow>.from(custodyRows),
    );
  }

  @override
  Future<List<DirectMediaBlobCustodyRow>>
  loadDirectMediaBlobCustodyRowsForAttachment(String attachmentId) async {
    final row = blobState.rows[attachmentId];
    return row == null
        ? const <DirectMediaBlobCustodyRow>[]
        : <DirectMediaBlobCustodyRow>[row];
  }

  @override
  Future<DirectMediaBlobCustodyRow?>
  loadIncomingDirectMediaBlobCustodyForAttachment(String attachmentId) async {
    final row = blobState.rows[attachmentId];
    return row != null &&
            row.direction == DirectMediaBlobCustodyDirection.incoming
        ? row
        : null;
  }

  @override
  Future<DirectMediaBlobCustodyRow?>
  loadOutgoingDirectMediaBlobCustodyForTarget({
    required String attachmentId,
    required String recipientPeerId,
  }) async {
    final row = blobState.rows[attachmentId];
    return row != null &&
            row.direction == DirectMediaBlobCustodyDirection.outgoing &&
            row.recipientPeerId == recipientPeerId
        ? row
        : null;
  }

  @override
  Future<List<DirectMediaBlobCustodyRow>> loadDirectMediaBlobCustodyForMessage(
    String messageId,
  ) async => blobState.rows.values
      .where((row) => row.messageId == messageId)
      .toList(growable: false);

  @override
  Future<List<DirectMediaBlobCustodyRow>> loadDirectMediaBlobCustodyByStates(
    Set<DirectMediaBlobCustodyState> states, {
    int limit = 50,
  }) async => blobState.rows.values
      .where((row) => states.contains(row.state))
      .take(limit)
      .toList(growable: false);

  @override
  Future<bool> transitionDirectMediaBlobCustodyIfExact({
    required DirectMediaBlobCustodyRow expected,
    required DirectMediaBlobCustodyRow next,
  }) async {
    final current = blobState.rows[expected.attachmentId];
    if (current == null ||
        !current.exactDatabaseProjectionMatches(expected) ||
        !expected.canTransitionTo(next)) {
      return false;
    }
    blobState.rows[expected.attachmentId] = next;
    return true;
  }

  @override
  Future<bool> deleteDirectMediaBlobCleanupPendingIfExact(
    DirectMediaBlobCustodyRow expected,
  ) async {
    final current = blobState.rows[expected.attachmentId];
    if (current == null ||
        current.state != DirectMediaBlobCustodyState.outgoingCleanupPending ||
        !current.exactDatabaseProjectionMatches(expected)) {
      return false;
    }
    blobState.rows.remove(expected.attachmentId);
    return true;
  }
}

/// 362: publishes a PLURAL linked (fanout) v114 row set for the prepared
/// voice parent and records every singular reopen-stage consultation, so the
/// test can prove the single-target voice lane fails closed instead of
/// demoting the plural generation.
class _LinkedFanoutVoiceCustodyRepository
    extends _StrictPreparedVoiceCustodyRepository {
  _LinkedFanoutVoiceCustodyRepository(super.messageRepository, super.blobState);

  final List<DirectMediaBlobCustodyRow> linkedRows =
      <DirectMediaBlobCustodyRow>[];
  int singularReopenStageCalls = 0;

  @override
  Future<List<DirectMediaBlobCustodyRow>> loadDirectMediaBlobCustodyForMessage(
    String messageId,
  ) async => linkedRows
      .where((row) => row.messageId == messageId)
      .toList(growable: false);

  @override
  Future<DirectMediaBlobGenerationStageResult>
  stageOutgoingDirectMediaBlobGeneration({
    required ConversationMessage expectedParent,
    required List<MediaAttachment> expectedAttachments,
    required List<MediaAttachment> preparedAttachments,
    required List<DirectMediaBlobCustodyRow> custodyRows,
  }) async {
    singularReopenStageCalls++;
    return const DirectMediaBlobGenerationStageResult.refused();
  }
}

bool _sameTestDatabaseMap(
  Map<String, Object?> expected,
  Map<String, Object?> current,
) =>
    expected.length == current.length &&
    expected.entries.every((entry) => current[entry.key] == entry.value);

class _CustodyDisappearsBeforeCompletionRepository
    extends FakeMessageRepository {
  int exactCustodyLoads = 0;

  @override
  Future<DirectInboxCustodyOutboxEntry?>
  loadDirectInboxCustodyOwnerForMessageId({required String messageId}) async {
    exactCustodyLoads++;
    return super.loadDirectInboxCustodyOwnerForMessageId(messageId: messageId);
  }

  @override
  Future<DirectInboxCustodyCompletionResult>
  completeAcceptedDirectInboxCustodyIfExact({
    required DirectInboxCustodyOutboxEntry expected,
    required int? relayExpiresAt,
  }) {
    directCustodyRows.remove(
      '${expected.recipientPeerId}\u0000${expected.messageId}',
    );
    return super.completeAcceptedDirectInboxCustodyIfExact(
      expected: expected,
      relayExpiresAt: relayExpiresAt,
    );
  }
}

class _CiphertextCapturingVoiceBridge extends FakeBridge {
  _CiphertextCapturingVoiceBridge({super.initialResponses});

  final List<List<int>> uploadedCiphertexts = <List<int>>[];
  final List<String> uploadedBlobIds = <String>[];
  final List<String> uploadedCiphertextPaths = <String>[];
  final List<({String keyBase64, String nonce})> encryptionProofs =
      <({String keyBase64, String nonce})>[];

  @override
  Future<String> send(String message) async {
    final request = jsonDecode(message) as Map<String, dynamic>;
    final command = request['cmd'] as String?;
    final payload = request['payload'] as Map<String, dynamic>?;
    if (command == 'media:upload' && payload != null) {
      final ciphertextPath = payload['filePath'] as String;
      uploadedBlobIds.add(payload['id'] as String);
      uploadedCiphertextPaths.add(ciphertextPath);
      uploadedCiphertexts.add(File(ciphertextPath).readAsBytesSync());
    }

    final response = await super.send(message);
    if (command == 'media:upload' && payload != null) {
      final decoded = jsonDecode(response) as Map<String, dynamic>;
      if (decoded['ok'] == true && payload['custodyContract'] != null) {
        return jsonEncode(<String, dynamic>{
          ...decoded,
          'id': payload['id'],
          'storeStatus': 'stored',
          'custodyKind': payload['custodyKind'],
          'custodyContract': payload['custodyContract'],
          'contentHash': payload['contentHash'],
          'size': File(payload['filePath'] as String).lengthSync(),
          'mime': payload['mime'],
          'expiresAtMs': DateTime.now()
              .toUtc()
              .add(const Duration(days: 1))
              .millisecondsSinceEpoch,
          'custodyRelayPeerId': 'relay-347',
        });
      }
    }
    if (command == 'blob:encrypt' && payload != null) {
      final decoded = jsonDecode(response) as Map<String, dynamic>;
      encryptionProofs.add((
        keyBase64: payload['keyBase64'] as String,
        nonce: decoded['nonce'] as String,
      ));
    }
    return response;
  }
}

bool _sameBytes(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

void main() {
  late FakeP2PService p2pService;
  late FakeMessageRepository messageRepo;
  late FakeBridge bridge;
  late _FakeMediaAttachmentRepository mediaAttachmentRepo;
  const mlKemKey = 'test-recipient-mlkem-pub-key';

  final tempDir = Directory.systemTemp.createTempSync('voice_test_');

  setUp(() {
    p2pService = FakeP2PService();
    messageRepo = FakeMessageRepository();
    mediaAttachmentRepo = _FakeMediaAttachmentRepository()
      ..directMediaCustodyMessageRepository = messageRepo;
    bridge = FakeBridge(
      initialResponses: {
        'message.encrypt': {
          'ok': true,
          'kem': 'fake-kem',
          'ciphertext': 'fake-ct',
          'nonce': 'fake-nonce',
        },
        'media:upload': {'ok': true},
      },
    );
  });

  tearDownAll(() {
    tempDir.deleteSync(recursive: true);
  });

  AudioRecording createRecording({
    String? filePath,
    int durationMs = 3000,
    int sizeBytes = 48000,
  }) {
    // Create a real temp file for validation tests
    final path =
        filePath ??
        '${tempDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    if (!File(path).existsSync()) {
      File(path).writeAsBytesSync(List.filled(sizeBytes, 0));
    }
    return AudioRecording(
      filePath: path,
      durationMs: durationMs,
      sizeBytes: sizeBytes,
    );
  }

  group('sendVoiceMessage', () {
    group('validation', () {
      test('returns invalidMessage if file does not exist', () async {
        final recording = AudioRecording(
          filePath: '/nonexistent/voice.m4a',
          durationMs: 3000,
          sizeBytes: 48000,
        );

        final (result, _) = await sendVoiceMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          recording: recording,
          bridge: bridge,
          recipientMlKemPublicKey: mlKemKey,
        );

        expect(result, SendVoiceMessageResult.invalidRecording);
      });

      test('returns invalidMessage if file is 0 bytes', () async {
        final path = '${tempDir.path}/empty.m4a';
        File(path).writeAsBytesSync([]);

        final recording = AudioRecording(
          filePath: path,
          durationMs: 3000,
          sizeBytes: 0,
        );

        final (result, _) = await sendVoiceMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          recording: recording,
          bridge: bridge,
          recipientMlKemPublicKey: mlKemKey,
        );

        expect(result, SendVoiceMessageResult.invalidRecording);
      });

      test(
        'returns invalidMessage if file exceeds 100 MB by one byte',
        () async {
          // Keep the file tiny; the use case validates the dedicated voice size
          // field before upload.
          final path = '${tempDir.path}/big.m4a';
          File(path).writeAsBytesSync([
            1,
            2,
            3,
          ]); // tiny file but model says 100MB + 1 byte

          final recording = AudioRecording(
            filePath: path,
            durationMs: 3000,
            sizeBytes: (100 * 1024 * 1024) + 1,
          );

          final (result, _) = await sendVoiceMessage(
            p2pService: p2pService,
            messageRepo: messageRepo,
            targetPeerId: 'target-peer',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
            recording: recording,
            bridge: bridge,
            recipientMlKemPublicKey: mlKemKey,
            mediaAttachmentRepo: mediaAttachmentRepo,
          );

          expect(result, SendVoiceMessageResult.invalidRecording);
        },
      );

      test(
        'returns sendFailed before upload when recipient ML-KEM key is missing',
        () async {
          final recording = createRecording();

          final (result, message) = await sendVoiceMessage(
            p2pService: p2pService,
            messageRepo: messageRepo,
            targetPeerId: 'target-peer',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
            recording: recording,
            bridge: bridge,
          );

          expect(result, SendVoiceMessageResult.sendFailed);
          expect(message, isNull);
          expect(bridge.commandLog, isNot(contains('media:upload')));
          expect(p2pService.sendCallCount, 0);
          expect(p2pService.localSendCallCount, 0);
          expect(p2pService.storeInInboxCallCount, 0);
          expect(messageRepo.saved, isEmpty);
        },
      );
    });

    group('upload and send', () {
      test(
        'TC-347-02 fresh prepared voice ambiguity then restart reuses one durable ciphertext',
        () async {
          const messageId = 'voice-347-ambiguous-restart';
          const attachmentId = 'voice-347-ambiguous-restart-attachment';
          const authoredAt = '2026-08-08T12:00:00.000Z';
          final intent = computeDirectMediaCustodyIntentId(
            messageId: messageId,
            attachmentIds: const <String>[attachmentId],
          );
          final recording = createRecording(
            filePath: '${tempDir.path}/voice_347_ambiguous_restart.m4a',
          );
          final preparedParent = ConversationMessage(
            id: messageId,
            contactPeerId: 'target-peer',
            senderPeerId: 'my-peer',
            text: '',
            timestamp: authoredAt,
            status: 'sending',
            isIncoming: false,
            createdAt: authoredAt,
            directMediaCustodyIntentId: intent,
          );
          final preparedAttachment = MediaAttachment(
            id: attachmentId,
            messageId: messageId,
            mime: recording.mime,
            size: recording.sizeBytes,
            mediaType: 'audio',
            durationMs: recording.durationMs,
            localPath: MediaFilePathConvention.relativePathForPendingUpload(
              messageId: messageId,
              attachmentId: attachmentId,
              mime: recording.mime,
            ),
            downloadStatus: 'upload_pending',
            createdAt: authoredAt,
            ownerLane: MediaOwnerLane.direct,
          );
          final firstMessages = FakeMessageRepository()
            ..existingMessages[messageId] = preparedParent;
          final blobState = _TestDirectMediaBlobState();
          final artifactStore = DirectMediaBlobArtifactStore(
            documentsDirectoryProvider: () async =>
                Directory('${tempDir.path}/plan347-custody'),
          );
          final firstMedia = _StrictPreparedVoiceCustodyRepository(
            firstMessages,
            blobState,
          )..saved.add(preparedAttachment);
          final rawBridge =
              _CiphertextCapturingVoiceBridge(
                  initialResponses: {
                    'message.encrypt': {
                      'ok': true,
                      'kem': 'fake-kem',
                      'ciphertext': 'fake-ct',
                      'nonce': 'fake-nonce',
                    },
                  },
                )
                ..responseSequences['media:upload'] = <Map<String, dynamic>>[
                  {
                    'ok': false,
                    'errorCode': 'MEDIA_ERROR',
                    'errorMessage': 'connection reset after request body',
                  },
                  {'ok': true},
                ];

          final (firstResult, _) = await sendVoiceMessage(
            p2pService: FakeP2PService(),
            messageRepo: firstMessages,
            targetPeerId: preparedParent.contactPeerId,
            senderPeerId: preparedParent.senderPeerId,
            senderUsername: 'Me',
            recording: recording,
            bridge: rawBridge,
            recipientMlKemPublicKey: mlKemKey,
            mediaAttachmentRepo: firstMedia,
            mediaFileManager: FakeMediaFileManager(),
            messageId: messageId,
            timestamp: authoredAt,
            blobId: attachmentId,
            uploadMediaFn: uploadMedia,
            directMediaBlobArtifactStore: artifactStore,
          );
          expect(firstResult, SendVoiceMessageResult.uploadQueued);
          expect(rawBridge.uploadedCiphertexts, hasLength(1));
          final firstCiphertextWasRetained = File(
            rawBridge.uploadedCiphertextPaths.single,
          ).existsSync();

          // Model a process restart from only the durable Plan 345 projection.
          // The recorder source remains present but no longer contains the bytes
          // that produced the relay's possibly committed first request.
          final restartedParent = ConversationMessage.fromMap(
            Map<String, dynamic>.from(
              firstMessages.existingMessages[messageId]!.toMap(),
            ),
          );
          final restartedAttachment = MediaAttachment.fromMap(
            Map<String, dynamic>.from(firstMedia.saved.single.toMap()),
          );
          File(recording.filePath).writeAsBytesSync(
            List<int>.filled(recording.sizeBytes, 7),
            flush: true,
          );
          final restartedMessages = FakeMessageRepository()
            ..existingMessages[messageId] = restartedParent;
          final restartedMedia = _StrictPreparedVoiceCustodyRepository(
            restartedMessages,
            blobState,
          )..saved.add(restartedAttachment);

          await sendVoiceMessage(
            p2pService: FakeP2PService(
              currentState: const NodeState(
                isStarted: false,
                peerId: 'my-peer',
              ),
            ),
            messageRepo: restartedMessages,
            targetPeerId: restartedParent.contactPeerId,
            senderPeerId: restartedParent.senderPeerId,
            senderUsername: 'Me',
            recording: recording,
            bridge: rawBridge,
            recipientMlKemPublicKey: mlKemKey,
            mediaAttachmentRepo: restartedMedia,
            mediaFileManager: FakeMediaFileManager(),
            messageId: messageId,
            timestamp: authoredAt,
            blobId: attachmentId,
            uploadMediaFn: uploadMedia,
            directMediaBlobArtifactStore: artifactStore,
          );

          final persisted = restartedMedia.saved.single;
          final hasTwoUploads = rawBridge.uploadedCiphertexts.length == 2;
          final firstCiphertext = rawBridge.uploadedCiphertexts.first;
          final firstProof = rawBridge.encryptionProofs.first;
          expect(
            <String, Object>{
              'uploadCount': rawBridge.uploadedCiphertexts.length,
              'stableBlobIds': rawBridge.uploadedBlobIds,
              'firstCiphertextRetainedAfterAmbiguity':
                  firstCiphertextWasRetained,
              'ciphertextReusedAfterRestart':
                  hasTwoUploads &&
                  _sameBytes(firstCiphertext, rawBridge.uploadedCiphertexts[1]),
              'persistedHashMatchesFirstCiphertext':
                  persisted.contentHash ==
                  sha256.convert(firstCiphertext).toString(),
              'persistedKeyMatchesFirstGeneration':
                  persisted.encryptionKeyBase64 == firstProof.keyBase64,
              'persistedNonceMatchesFirstGeneration':
                  persisted.encryptionNonce == firstProof.nonce,
            },
            <String, Object>{
              'uploadCount': 2,
              'stableBlobIds': const <String>[attachmentId, attachmentId],
              'firstCiphertextRetainedAfterAmbiguity': true,
              'ciphertextReusedAfterRestart': true,
              'persistedHashMatchesFirstCiphertext': true,
              'persistedKeyMatchesFirstGeneration': true,
              'persistedNonceMatchesFirstGeneration': true,
            },
            reason:
                'a prepared voice retry must reopen the exact ciphertext and '
                'crypto generation that may already be committed at the relay',
          );
        },
        skip: !kDirectMediaBlobCustodyClientEnabled,
      );

      test(
        'TC-362-02a prepared voice delegates to the shared fanout owner when linked authority is marked',
        () async {
          // The voice send lane owns NO plural fanout branch of its own —
          // linked-generation uploads ride the shared fanout owner through
          // the retry/coordinator lanes. What THIS lane must guarantee is
          // fail-closed: persisted LINKED rows are plural authority that the
          // singular prepare/reopen/upload paths may never demote to one
          // single-target attempt.
          const messageId = 'voice-362-linked-marked';
          const attachmentId = 'voice-362-linked-marked-attachment';
          const authoredAt = '2026-08-10T11:00:00.000Z';
          const contentHash =
              'cdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcdcd';
          final intent = computeDirectMediaCustodyIntentId(
            messageId: messageId,
            attachmentIds: const <String>[attachmentId],
          );
          final recording = createRecording(
            filePath: '${tempDir.path}/voice_362_linked_marked.m4a',
          );
          final preparedParent = ConversationMessage(
            id: messageId,
            contactPeerId: 'target-peer',
            senderPeerId: 'my-peer',
            text: '',
            timestamp: authoredAt,
            status: 'sending',
            isIncoming: false,
            createdAt: authoredAt,
            directMediaCustodyIntentId: intent,
          ).copyWith(directEventFanoutGenerationId: messageId);
          final preparedAttachment = MediaAttachment(
            id: attachmentId,
            messageId: messageId,
            mime: recording.mime,
            size: recording.sizeBytes,
            mediaType: 'audio',
            durationMs: recording.durationMs,
            localPath: MediaFilePathConvention.relativePathForPendingUpload(
              messageId: messageId,
              attachmentId: attachmentId,
              mime: recording.mime,
            ),
            downloadStatus: 'upload_pending',
            createdAt: authoredAt,
            ownerLane: MediaOwnerLane.direct,
            contentHash: contentHash,
            encryptionKeyBase64: 'voice-362-raw-key',
            encryptionNonce: 'voice-362-nonce',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          );
          DirectMediaBlobCustodyRow linkedRow(
            String recipientPeerId,
            String recipientMlKemPublicKey,
          ) => DirectMediaBlobCustodyRow(
            attachmentId: attachmentId,
            messageId: messageId,
            direction: DirectMediaBlobCustodyDirection.outgoing,
            state: DirectMediaBlobCustodyState.outgoingPrepared,
            inboxCustodyIncarnationId: null,
            recipientPeerId: recipientPeerId,
            contactAccountPeerId: 'target-peer',
            recipientMlKemPublicKey: recipientMlKemPublicKey,
            ciphertextRelativePath:
                'direct_media_blob_custody_v1/$contentHash/$attachmentId.blob',
            contentHash: contentHash,
            ciphertextSize: 4096,
            expiresAtMs: null,
            custodyRelayPeerId: null,
            lastAttemptAt: null,
            nextAttemptAt: null,
            createdAt: authoredAt,
            updatedAt: authoredAt,
          );
          final messages = FakeMessageRepository()
            ..existingMessages[messageId] = preparedParent;
          final media =
              _LinkedFanoutVoiceCustodyRepository(
                  messages,
                  _TestDirectMediaBlobState(),
                )
                ..saved.add(preparedAttachment)
                ..linkedRows.addAll(<DirectMediaBlobCustodyRow>[
                  linkedRow('target-peer', 'mlkem-legacy-account'),
                  linkedRow('peer-device-a', 'mlkem-device-a'),
                ]);
          final linkedRowsBefore = media.linkedRows
              .map((row) => row.toMap())
              .toList(growable: false);
          var prepareArtifactCalls = 0;
          var strictUploadCalls = 0;
          final coordinator = PreparedDirectMediaBlobCustodyCoordinator(
            repository: media,
            artifactStore: DirectMediaBlobArtifactStore(
              documentsDirectoryProvider: () async =>
                  Directory('${tempDir.path}/tc362_voice_store'),
            ),
            prepareArtifact:
                ({
                  required Bridge bridge,
                  required String localFilePath,
                }) async {
                  prepareArtifactCalls++;
                  throw StateError('a linked generation must never re-encrypt');
                },
            strictUpload:
                ({
                  required bridge,
                  required attachmentId,
                  required recipientPeerId,
                  required ciphertextPath,
                  required contentHash,
                  required ciphertextSize,
                }) async {
                  strictUploadCalls++;
                  return const <String, dynamic>{'ok': false};
                },
          );
          Future<UploadMediaOutcome> forbiddenUpload({
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
            EncryptedMediaArtifact? preparedArtifact,
          }) async {
            fail('a linked generation must never reach the legacy upload lane');
          }

          final (result, message) = await sendVoiceMessage(
            p2pService: FakeP2PService(),
            messageRepo: messages,
            targetPeerId: 'target-peer',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
            recording: recording,
            bridge: bridge,
            recipientMlKemPublicKey: mlKemKey,
            mediaAttachmentRepo: media,
            mediaFileManager: FakeMediaFileManager(),
            messageId: messageId,
            timestamp: authoredAt,
            blobId: attachmentId,
            uploadMediaFn: forbiddenUpload,
            directMediaBlobCustodyCoordinator: coordinator,
          );

          expect(
            result,
            SendVoiceMessageResult.sendFailed,
            reason: 'plural linked authority refuses the singular voice lane',
          );
          expect(message, isNull);
          expect(
            prepareArtifactCalls,
            0,
            reason: 'no re-encryption of the shared canonical artifact',
          );
          expect(
            strictUploadCalls,
            0,
            reason:
                'NO singular demotion: the single-target strict upload '
                'owner is never invoked over a plural linked generation',
          );
          expect(
            media.singularReopenStageCalls,
            0,
            reason: 'the singular reopen CAS is never consulted either',
          );
          expect(media.directMediaCustodyStageCalls, 0);
          expect(bridge.commandLog, isNot(contains('media:upload')));
          expect(bridge.commandLog, isNot(contains('message.encrypt')));
          expect(
            media.linkedRows.map((row) => row.toMap()).toList(growable: false),
            linkedRowsBefore,
            reason: 'every persisted linked row is byte-identical',
          );
          expect(
            (await messages.getMessage(messageId))!.status,
            'sending',
            reason: 'the durable prepared parent is retained untouched',
          );
        },
        // Deliberately NOT gated on kDirectMediaBlobCustodyClientEnabled:
        // the no-singular-demotion invariant must hold in BOTH compilations
        // (selector off refuses even earlier).
      );

      test(
        'TC-347-08b prepared ordinary voice selects strict blob coordinator',
        () async {
          const messageId = 'voice-347-strict-selector';
          const attachmentId = 'voice-347-strict-selector-attachment';
          const authoredAt = '2026-08-08T12:30:00.000Z';
          final recording = createRecording(
            filePath: '${tempDir.path}/voice_347_strict_selector.m4a',
          );
          final intent = computeDirectMediaCustodyIntentId(
            messageId: messageId,
            attachmentIds: const <String>[attachmentId],
          );
          final parent = ConversationMessage(
            id: messageId,
            contactPeerId: 'target-peer',
            senderPeerId: 'my-peer',
            text: '',
            timestamp: authoredAt,
            status: 'sending',
            isIncoming: false,
            createdAt: authoredAt,
            directMediaCustodyIntentId: intent,
          );
          final pending = MediaAttachment(
            id: attachmentId,
            messageId: messageId,
            mime: recording.mime,
            size: recording.sizeBytes,
            mediaType: 'audio',
            durationMs: recording.durationMs,
            localPath: MediaFilePathConvention.relativePathForPendingUpload(
              messageId: messageId,
              attachmentId: attachmentId,
              mime: recording.mime,
            ),
            downloadStatus: 'upload_pending',
            createdAt: authoredAt,
            ownerLane: MediaOwnerLane.direct,
          );
          final messages = FakeMessageRepository()
            ..existingMessages[messageId] = parent;
          final blobState = _TestDirectMediaBlobState();
          final media = _StrictPreparedVoiceCustodyRepository(
            messages,
            blobState,
          )..saved.add(pending);
          final strictBridge = _CiphertextCapturingVoiceBridge(
            initialResponses: const <String, Map<String, dynamic>>{
              'message.encrypt': <String, dynamic>{
                'ok': true,
                'kem': 'fake-kem',
                'ciphertext': 'fake-ct',
                'nonce': 'fake-nonce',
              },
              'media:upload': <String, dynamic>{'ok': true},
            },
          );
          var legacyUploadCalls = 0;
          Future<UploadMediaOutcome> legacyMustNotRun({
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
            EncryptedMediaArtifact? preparedArtifact,
          }) async {
            legacyUploadCalls++;
            return const UploadMediaFailed(
              stage: UploadMediaStage.transport,
              disposition: UploadMediaDisposition.terminal,
              errorCode: 'LEGACY_UPLOAD_MUST_NOT_RUN',
            );
          }

          await sendVoiceMessage(
            p2pService: FakeP2PService(
              currentState: const NodeState(
                isStarted: false,
                peerId: 'my-peer',
              ),
            ),
            messageRepo: messages,
            targetPeerId: parent.contactPeerId,
            senderPeerId: parent.senderPeerId,
            senderUsername: 'Me',
            recording: recording,
            bridge: strictBridge,
            recipientMlKemPublicKey: mlKemKey,
            mediaAttachmentRepo: media,
            mediaFileManager: FakeMediaFileManager(),
            messageId: messageId,
            timestamp: authoredAt,
            blobId: attachmentId,
            uploadMediaFn: legacyMustNotRun,
            directMediaBlobArtifactStore: DirectMediaBlobArtifactStore(
              documentsDirectoryProvider: () async =>
                  Directory('${tempDir.path}/plan347-selector-custody'),
            ),
          );

          expect(legacyUploadCalls, 0);
          expect(strictBridge.uploadedBlobIds, const <String>[attachmentId]);
          expect(strictBridge.uploadedCiphertexts, hasLength(1));
          expect(blobState.rows, hasLength(1));
          expect(
            blobState.rows[attachmentId]?.state,
            DirectMediaBlobCustodyState.outgoingStored,
          );
          expect(media.saved.single.contentHash, isNotNull);
          expect(media.saved.single.encryptionKeyBase64, isNotNull);
          expect(media.saved.single.encryptionNonce, isNotNull);
        },
        skip: !kDirectMediaBlobCustodyClientEnabled,
      );

      test(
        'TC-362-02a fresh voice fails closed on an initialized roster before '
        'any coordinator work',
        () async {
          final messages = FakeMessageRepository();
          final media = _FanoutCapableVoiceRepository(messages);
          const messageId = 'voice-362-fresh-roster';
          const attachmentId = 'voice-362-fresh-roster-attachment';
          final intent = computeDirectMediaCustodyIntentId(
            messageId: messageId,
            attachmentIds: <String>[attachmentId],
          );
          final prepared = ConversationMessage(
            id: messageId,
            contactPeerId: 'target-peer',
            senderPeerId: 'my-peer',
            text: '',
            timestamp: '2026-08-12T12:00:00.000Z',
            status: 'sending',
            isIncoming: false,
            createdAt: '2026-08-12T12:00:00.000Z',
            directMediaCustodyIntentId: intent,
          );
          messages.existingMessages[messageId] = prepared;
          media.saved.add(
            MediaAttachment(
              id: attachmentId,
              messageId: messageId,
              mime: 'audio/mp4',
              size: 48000,
              mediaType: 'audio',
              localPath: MediaFilePathConvention.relativePathForPendingUpload(
                messageId: messageId,
                attachmentId: attachmentId,
                mime: 'audio/mp4',
              ),
              durationMs: 3000,
              downloadStatus: 'upload_pending',
              createdAt: '2026-08-12T12:00:00.000Z',
              ownerLane: MediaOwnerLane.direct,
            ),
          );
          final savedBefore = media.saved.single;
          var prepareArtifactCalls = 0;
          var strictUploadCalls = 0;
          final coordinator = PreparedDirectMediaBlobCustodyCoordinator(
            repository: media,
            artifactStore: DirectMediaBlobArtifactStore(),
            prepareArtifact: ({required bridge, required localFilePath}) async {
              prepareArtifactCalls++;
              throw StateError('fresh voice must refuse before crypto');
            },
            strictUpload:
                ({
                  required bridge,
                  required attachmentId,
                  required recipientPeerId,
                  required ciphertextPath,
                  required contentHash,
                  required ciphertextSize,
                }) async {
                  strictUploadCalls++;
                  throw StateError('fresh voice must refuse before upload');
                },
          );
          final p2p = FakeP2PService(
            currentState: const NodeState(isStarted: false, peerId: 'my-peer'),
          );

          final (result, message) = await sendVoiceMessage(
            p2pService: p2p,
            messageRepo: messages,
            targetPeerId: prepared.contactPeerId,
            senderPeerId: prepared.senderPeerId,
            senderUsername: 'Me',
            recording: createRecording(),
            bridge: bridge,
            recipientMlKemPublicKey: mlKemKey,
            mediaAttachmentRepo: media,
            mediaFileManager: FakeMediaFileManager(),
            messageId: messageId,
            timestamp: prepared.timestamp,
            blobId: attachmentId,
            directMediaBlobCustodyCoordinator: coordinator,
            directMediaBlobCustodyClientEnabled: true,
          );

          // 362: an initialized roster forbids the singular fresh voice path
          // — the refusal precedes media crypto, artifact persistence,
          // upload and network, and demotes nothing.
          expect(result, SendVoiceMessageResult.sendFailed);
          expect(message, isNull);
          expect(prepareArtifactCalls, 0);
          expect(strictUploadCalls, 0);
          expect(media.saved.single, same(savedBefore));
          expect(
            messages.existingMessages[messageId]!.directMediaCustodyIntentId,
            intent,
            reason: 'the v110 token is not consumed by a refused attempt',
          );
          expect(p2p.sendCallCount, 0);
          expect(p2p.storeInInboxCallCount, 0);
        },
      );

      test(
        'TC-345-06 prepared voice delegates uploaded audio to exact v108 media custody',
        () async {
          for (final scenario in <({String suffix, String text})>[
            (suffix: 'textless', text: ''),
            (suffix: 'captioned', text: 'Voice caption'),
          ]) {
            final scenarioMessages = FakeMessageRepository();
            final scenarioMedia = _PreparedVoiceCustodyRepository(
              scenarioMessages,
            );
            final scenarioP2p = FakeP2PService(
              currentState: const NodeState(
                isStarted: false,
                peerId: 'my-peer',
              ),
            );
            final scenarioFileManager = FakeMediaFileManager();
            final deleteSourceValues = <bool>[];
            var pendingCleanupCalls = 0;
            final messageId = 'voice-345-${scenario.suffix}';
            final attachmentId = 'voice-345-${scenario.suffix}-attachment';
            final intent = computeDirectMediaCustodyIntentId(
              messageId: messageId,
              attachmentIds: <String>[attachmentId],
            );
            final prepared = ConversationMessage(
              id: messageId,
              contactPeerId: 'target-peer',
              senderPeerId: 'my-peer',
              text: scenario.text,
              timestamp: '2026-08-07T12:00:00.000Z',
              status: 'sending',
              isIncoming: false,
              createdAt: '2026-08-07T12:00:00.000Z',
              directMediaCustodyIntentId: intent,
            );
            scenarioMessages.existingMessages[messageId] = prepared;
            scenarioMedia.saved.add(
              MediaAttachment(
                id: attachmentId,
                messageId: messageId,
                mime: 'audio/mp4',
                size: 48000,
                mediaType: 'audio',
                localPath: MediaFilePathConvention.relativePathForPendingUpload(
                  messageId: messageId,
                  attachmentId: attachmentId,
                  mime: 'audio/mp4',
                ),
                durationMs: 3000,
                downloadStatus: 'upload_pending',
                createdAt: '2026-08-07T12:00:00.000Z',
                ownerLane: MediaOwnerLane.direct,
              ),
            );

            scenarioFileManager.onDeletePendingUploadDir = (deletedMessageId) {
              pendingCleanupCalls++;
              expect(deletedMessageId, messageId);
              expect(
                scenarioMessages
                    .existingMessages[messageId]!
                    .directMediaCustodyIntentId,
                isNull,
                reason: 'cleanup must follow durable intent consumption',
              );
              expect(scenarioMedia.saved.single.downloadStatus, 'done');
            };
            Future<UploadMediaOutcome> completePreparedUpload({
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
              EncryptedMediaArtifact? preparedArtifact,
            }) async {
              deleteSourceValues.add(deleteSourceWhenDone);
              return UploadMediaSucceeded(
                MediaAttachment(
                  id: blobId!,
                  messageId: '',
                  mime: mime,
                  size: 48000,
                  mediaType: 'audio',
                  durationMs: durationMs,
                  localPath: 'media/target-peer/$attachmentId.m4a',
                  downloadStatus: 'done',
                  createdAt: prepared.createdAt,
                  waveform: waveform,
                  contentHash: List<String>.filled(64, 'a').join(),
                  encryptionKeyBase64: 'voice-key',
                  encryptionNonce: 'voice-nonce',
                  encryptionScheme:
                      kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
                ),
              );
            }

            final (result, message) = await sendVoiceMessage(
              p2pService: scenarioP2p,
              messageRepo: scenarioMessages,
              targetPeerId: prepared.contactPeerId,
              senderPeerId: prepared.senderPeerId,
              senderUsername: 'Me',
              recording: createRecording(),
              bridge: bridge,
              recipientMlKemPublicKey: mlKemKey,
              mediaAttachmentRepo: scenarioMedia,
              mediaFileManager: scenarioFileManager,
              text: scenario.text,
              messageId: messageId,
              timestamp: prepared.timestamp,
              blobId: attachmentId,
              uploadMediaFn: completePreparedUpload,
            );

            expect(result, SendVoiceMessageResult.sendFailed);
            expect(message, isNull);
            expect(scenarioMedia.directMediaCustodyStageCalls, 1);
            expect(
              scenarioMedia.stagedKinds,
              isEmpty,
              reason: 'voice must not fall through to generic media staging',
            );
            expect(scenarioMessages.directCustodyRows, hasLength(1));
            expect(
              scenarioMessages.directCustodyRows.values.single.incarnationId,
              intent,
            );
            expect(
              scenarioMessages
                  .existingMessages[messageId]!
                  .directMediaCustodyIntentId,
              isNull,
            );
            expect(scenarioMedia.saved, hasLength(1));
            expect(scenarioMedia.saved.single.downloadStatus, 'done');
            expect(deleteSourceValues, <bool>[false]);
            expect(pendingCleanupCalls, 1);
            expect(scenarioP2p.sendCallCount, 0);
            expect(scenarioP2p.storeInInboxCallCount, 0);
          }

          final failedMessages = FakeMessageRepository();
          final failedMedia = _PreparedVoiceCustodyRepository(failedMessages);
          final failedFileManager = FakeMediaFileManager();
          var failedPendingCleanupCalls = 0;
          failedFileManager.onDeletePendingUploadDir = (_) {
            failedPendingCleanupCalls++;
          };
          const failedMessageId = 'voice-345-upload-failure';
          const failedAttachmentId = 'voice-345-upload-failure-attachment';
          const failedAuthoredAt = '2026-08-07T12:00:00.000Z';
          final failedIntent = computeDirectMediaCustodyIntentId(
            messageId: failedMessageId,
            attachmentIds: const <String>[failedAttachmentId],
          );
          failedMessages.existingMessages[failedMessageId] =
              ConversationMessage(
                id: failedMessageId,
                contactPeerId: 'target-peer',
                senderPeerId: 'my-peer',
                text: '',
                timestamp: failedAuthoredAt,
                status: 'sending',
                isIncoming: false,
                createdAt: failedAuthoredAt,
                directMediaCustodyIntentId: failedIntent,
              );
          failedMedia.saved.add(
            MediaAttachment(
              id: failedAttachmentId,
              messageId: failedMessageId,
              mime: 'audio/mp4',
              size: 48000,
              mediaType: 'audio',
              durationMs: 3000,
              localPath: MediaFilePathConvention.relativePathForPendingUpload(
                messageId: failedMessageId,
                attachmentId: failedAttachmentId,
                mime: 'audio/mp4',
              ),
              downloadStatus: 'upload_pending',
              createdAt: failedAuthoredAt,
              ownerLane: MediaOwnerLane.direct,
            ),
          );
          final failedDeleteSourceValues = <bool>[];
          final legacyFailureProjection = _RecordingVoiceUploadProjection();
          Future<UploadMediaOutcome> failPreparedUpload({
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
            EncryptedMediaArtifact? preparedArtifact,
          }) async {
            failedDeleteSourceValues.add(deleteSourceWhenDone);
            return const UploadMediaFailed(
              stage: UploadMediaStage.transport,
              disposition: UploadMediaDisposition.connectivityRetryable,
              errorCode: 'offline',
            );
          }

          final (failure, _) = await sendVoiceMessage(
            p2pService: FakeP2PService(),
            messageRepo: failedMessages,
            targetPeerId: 'target-peer',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
            recording: createRecording(),
            bridge: bridge,
            recipientMlKemPublicKey: mlKemKey,
            mediaAttachmentRepo: failedMedia,
            mediaFileManager: failedFileManager,
            messageId: failedMessageId,
            blobId: failedAttachmentId,
            uploadMediaFn: failPreparedUpload,
            uploadRetryProjectionRepo: legacyFailureProjection,
          );

          expect(failure, SendVoiceMessageResult.uploadQueued);
          expect(failedMedia.directMediaCustodyStageCalls, 0);
          expect(failedMedia.directMediaCustodyFailureCalls, 1);
          expect(
            failedMedia.lastFailureParent?.directMediaCustodyIntentId,
            failedIntent,
          );
          expect(
            failedMedia.lastFailureAttachments?.map(
              (attachment) => attachment.id,
            ),
            <String>[failedAttachmentId],
          );
          expect(failedMedia.lastFailedAttachmentId, failedAttachmentId);
          expect(
            legacyFailureProjection.callCount,
            0,
            reason:
                'manifest-bound voice failure must never use legacy projection',
          );
          expect(failedMessages.directCustodyRows, isEmpty);
          expect(
            failedMessages
                .existingMessages[failedMessageId]!
                .directMediaCustodyIntentId,
            failedIntent,
          );
          expect(failedMedia.saved.single.downloadStatus, 'upload_pending');
          expect(failedMedia.saved.single.createdAt, failedAuthoredAt);
          expect(failedDeleteSourceValues, <bool>[false]);
          expect(failedPendingCleanupCalls, 0);
        },
      );

      test(
        'TC-345-06h prepared voice failure refuses crossed metadata partial token and global v108 state without legacy fallback',
        () async {
          for (final scenario in <String>[
            'metadata',
            'partial',
            'token',
            'global-v108',
          ]) {
            final scenarioMessages = FakeMessageRepository();
            final scenarioMedia = _PreparedVoiceCustodyRepository(
              scenarioMessages,
            );
            final legacyProjection = _RecordingVoiceUploadProjection();
            final messageId = 'voice-345-failure-cross-$scenario';
            final attachmentId = '$messageId-attachment';
            const authoredAt = '2026-08-07T12:00:00.000Z';
            final intent = computeDirectMediaCustodyIntentId(
              messageId: messageId,
              attachmentIds: <String>[attachmentId],
            );
            final preparedParent = ConversationMessage(
              id: messageId,
              contactPeerId: 'target-peer',
              senderPeerId: 'my-peer',
              text: '',
              timestamp: authoredAt,
              status: 'sending',
              isIncoming: false,
              createdAt: authoredAt,
              directMediaCustodyIntentId: intent,
            );
            final preparedAttachment = MediaAttachment(
              id: attachmentId,
              messageId: messageId,
              mime: 'audio/mp4',
              size: 48000,
              mediaType: 'audio',
              durationMs: 3000,
              localPath: MediaFilePathConvention.relativePathForPendingUpload(
                messageId: messageId,
                attachmentId: attachmentId,
                mime: 'audio/mp4',
              ),
              downloadStatus: 'upload_pending',
              createdAt: authoredAt,
              ownerLane: MediaOwnerLane.direct,
            );
            scenarioMessages.existingMessages[messageId] = preparedParent;
            scenarioMedia.saved.add(preparedAttachment);

            Future<UploadMediaOutcome> failAfterCross({
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
              EncryptedMediaArtifact? preparedArtifact,
            }) async {
              switch (scenario) {
                case 'metadata':
                  scenarioMedia.saved[0] = scenarioMedia.saved.single.copyWith(
                    durationMs: 4000,
                  );
                  break;
                case 'partial':
                  scenarioMedia.saved.clear();
                  break;
                case 'token':
                  scenarioMessages.existingMessages[messageId] = preparedParent
                      .copyWith(directMediaCustodyIntentId: null);
                  break;
                case 'global-v108':
                  scenarioMessages
                          .directCustodyRows['other-peer\u0000$messageId'] =
                      DirectInboxCustodyOutboxEntry(
                        recipientPeerId: 'other-peer',
                        messageId: messageId,
                        incarnationId: intent,
                        wireEnvelope: '{"winner":true}',
                        retryCount: 0,
                        lastAttemptAt: null,
                        lastErrorCode: null,
                        createdAt: authoredAt,
                        updatedAt: authoredAt,
                      );
                  break;
              }
              return const UploadMediaFailed(
                stage: UploadMediaStage.transport,
                disposition: UploadMediaDisposition.connectivityRetryable,
                errorCode: 'offline',
              );
            }

            final (result, message) = await sendVoiceMessage(
              p2pService: FakeP2PService(),
              messageRepo: scenarioMessages,
              targetPeerId: 'target-peer',
              senderPeerId: 'my-peer',
              senderUsername: 'Me',
              recording: createRecording(),
              bridge: bridge,
              recipientMlKemPublicKey: mlKemKey,
              mediaAttachmentRepo: scenarioMedia,
              mediaFileManager: FakeMediaFileManager(),
              messageId: messageId,
              blobId: attachmentId,
              uploadMediaFn: failAfterCross,
              uploadRetryProjectionRepo: legacyProjection,
            );

            expect(
              result,
              SendVoiceMessageResult.uploadFailed,
              reason: scenario,
            );
            expect(message, isNull, reason: scenario);
            expect(legacyProjection.callCount, 0, reason: scenario);
            expect(scenarioMedia.directMediaCustodyStageCalls, 0);
            expect(
              scenarioMedia.directMediaCustodyFailureCalls,
              scenario == 'global-v108' ? 1 : 0,
              reason: scenario,
            );
          }
        },
      );

      test(
        'TC-345-06c malformed prepared voice parent fails before upload',
        () async {
          const authoredAt = '2026-08-07T12:00:00.000Z';
          for (final malformed in <({String suffix, bool forwarded})>[
            (suffix: 'hidden', forwarded: false),
            (suffix: 'forwarded', forwarded: true),
          ]) {
            final messageId = 'voice-345-malformed-${malformed.suffix}';
            final attachmentId = '$messageId-attachment';
            final scenarioMessages = FakeMessageRepository();
            final scenarioMedia = _PreparedVoiceCustodyRepository(
              scenarioMessages,
            );
            final intent = computeDirectMediaCustodyIntentId(
              messageId: messageId,
              attachmentIds: <String>[attachmentId],
            );
            scenarioMessages.existingMessages[messageId] = ConversationMessage(
              id: messageId,
              contactPeerId: 'target-peer',
              senderPeerId: 'my-peer',
              text: '',
              timestamp: authoredAt,
              status: 'sending',
              isIncoming: false,
              createdAt: authoredAt,
              hiddenAt: malformed.forwarded ? null : '2026-08-07T12:00:01.000Z',
              isForwarded: malformed.forwarded,
              directMediaCustodyIntentId: intent,
            );
            scenarioMedia.saved.add(
              MediaAttachment(
                id: attachmentId,
                messageId: messageId,
                mime: 'audio/mp4',
                size: 48000,
                mediaType: 'audio',
                durationMs: 3000,
                localPath: MediaFilePathConvention.relativePathForPendingUpload(
                  messageId: messageId,
                  attachmentId: attachmentId,
                  mime: 'audio/mp4',
                ),
                downloadStatus: 'upload_pending',
                createdAt: authoredAt,
                ownerLane: MediaOwnerLane.direct,
              ),
            );
            var uploadCalls = 0;
            Future<UploadMediaOutcome> shouldNotUpload({
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
              EncryptedMediaArtifact? preparedArtifact,
            }) async {
              uploadCalls++;
              return const UploadMediaFailed(
                stage: UploadMediaStage.transport,
                disposition: UploadMediaDisposition.connectivityRetryable,
                errorCode: 'UNEXPECTED_UPLOAD',
              );
            }

            final (result, message) = await sendVoiceMessage(
              p2pService: FakeP2PService(),
              messageRepo: scenarioMessages,
              targetPeerId: 'target-peer',
              senderPeerId: 'my-peer',
              senderUsername: 'Me',
              recording: createRecording(),
              bridge: FakeBridge(),
              recipientMlKemPublicKey: mlKemKey,
              mediaAttachmentRepo: scenarioMedia,
              messageId: messageId,
              timestamp: authoredAt,
              blobId: attachmentId,
              uploadMediaFn: shouldNotUpload,
            );

            expect(result, SendVoiceMessageResult.sendFailed);
            expect(message, isNull);
            expect(uploadCalls, 0, reason: malformed.suffix);
            expect(scenarioMedia.directMediaCustodyStageCalls, 0);
            expect(scenarioMessages.directCustodyRows, isEmpty);
            expect(
              scenarioMessages
                  .existingMessages[messageId]!
                  .directMediaCustodyIntentId,
              intent,
            );
          }
        },
      );

      test(
        'TC-345-06b prepared voice preserves authored pending identity across upload completion',
        () async {
          const messageId = 'voice-345-authored-identity';
          const attachmentId = 'voice-345-authored-identity-attachment';
          const authoredAt = '2026-08-07T12:00:00.000Z';
          const uploadCompletedAt = '2026-08-07T12:00:09.000Z';
          const voiceWaveform = <double>[0.1, 0.4, 0.2];
          final scenarioMessages = FakeMessageRepository();
          final scenarioMedia = _PreparedVoiceCustodyRepository(
            scenarioMessages,
          );
          final intent = computeDirectMediaCustodyIntentId(
            messageId: messageId,
            attachmentIds: const <String>[attachmentId],
          );
          scenarioMessages.existingMessages[messageId] = ConversationMessage(
            id: messageId,
            contactPeerId: 'target-peer',
            senderPeerId: 'my-peer',
            text: '',
            timestamp: authoredAt,
            status: 'sending',
            isIncoming: false,
            createdAt: authoredAt,
            directMediaCustodyIntentId: intent,
          );
          scenarioMedia.saved.add(
            MediaAttachment(
              id: attachmentId,
              messageId: messageId,
              mime: 'audio/mp4',
              size: 48000,
              mediaType: 'audio',
              durationMs: 3000,
              localPath: MediaFilePathConvention.relativePathForPendingUpload(
                messageId: messageId,
                attachmentId: attachmentId,
                mime: 'audio/mp4',
              ),
              downloadStatus: 'upload_pending',
              createdAt: authoredAt,
              waveform: voiceWaveform,
              ownerLane: MediaOwnerLane.direct,
            ),
          );

          Future<UploadMediaOutcome> shiftedCompletion({
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
            EncryptedMediaArtifact? preparedArtifact,
          }) async => UploadMediaSucceeded(
            MediaAttachment(
              id: blobId!,
              messageId: '',
              mime: mime,
              size: 48000,
              mediaType: 'audio',
              durationMs: durationMs,
              localPath: 'media/target-peer/$attachmentId.m4a',
              downloadStatus: 'done',
              createdAt: uploadCompletedAt,
              waveform: waveform,
              contentHash: List<String>.filled(64, 'a').join(),
              encryptionKeyBase64: 'a2V5',
              encryptionNonce: 'nonce',
              encryptionScheme: 'blob_aes_256_gcm_v1',
            ),
          );

          final (result, message) = await sendVoiceMessage(
            p2pService: FakeP2PService(
              currentState: const NodeState(
                isStarted: false,
                peerId: 'my-peer',
              ),
            ),
            messageRepo: scenarioMessages,
            targetPeerId: 'target-peer',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
            recording: createRecording(),
            bridge: bridge,
            recipientMlKemPublicKey: mlKemKey,
            mediaAttachmentRepo: scenarioMedia,
            waveform: voiceWaveform,
            messageId: messageId,
            timestamp: authoredAt,
            blobId: attachmentId,
            uploadMediaFn: shiftedCompletion,
          );

          expect(result, SendVoiceMessageResult.sendFailed);
          expect(message, isNull);
          expect(scenarioMedia.directMediaCustodyStageCalls, 1);
          expect(scenarioMedia.stagedKinds, isEmpty);
          expect(scenarioMedia.lastCustodyAttachment!.createdAt, authoredAt);
          expect(
            scenarioMedia.lastCustodyAttachment!.createdAt,
            isNot(uploadCompletedAt),
          );
          expect(scenarioMedia.lastCustodyAttachment!.mime, 'audio/mp4');
          expect(scenarioMedia.lastCustodyAttachment!.size, 48000);
          expect(scenarioMedia.lastCustodyAttachment!.waveform, voiceWaveform);
          expect(scenarioMessages.directCustodyRows, hasLength(1));
        },
      );

      test(
        'TC-345-06e prepared voice rejects crossed raw upload identity before message encryption',
        () async {
          const authoredAt = '2026-08-07T12:05:00.000Z';
          const authoredWaveform = <double>[0.1, 0.4, 0.2];
          final mutations =
              <
                ({String name, MediaAttachment Function(MediaAttachment) apply})
              >[
                (name: 'id', apply: (value) => value.copyWith(id: 'crossed')),
                (
                  name: 'message-id',
                  apply: (value) => value.copyWith(messageId: 'crossed'),
                ),
                (
                  name: 'mime',
                  apply: (value) => value.copyWith(mime: 'audio/ogg'),
                ),
                (name: 'size', apply: (value) => value.copyWith(size: 48001)),
                (
                  name: 'media-type',
                  apply: (value) => value.copyWith(mediaType: 'video'),
                ),
                (
                  name: 'duration',
                  apply: (value) => value.copyWith(durationMs: 3001),
                ),
                (
                  name: 'waveform',
                  apply: (value) =>
                      value.copyWith(waveform: const <double>[0.9]),
                ),
                (
                  name: 'status',
                  apply: (value) =>
                      value.copyWith(downloadStatus: 'upload_pending'),
                ),
              ];

          for (final mutation in mutations) {
            final messageId = 'voice-345-upload-cross-${mutation.name}';
            final attachmentId = '$messageId-attachment';
            final messages = FakeMessageRepository();
            final media = _PreparedVoiceCustodyRepository(messages);
            final intent = computeDirectMediaCustodyIntentId(
              messageId: messageId,
              attachmentIds: <String>[attachmentId],
            );
            messages.existingMessages[messageId] = ConversationMessage(
              id: messageId,
              contactPeerId: 'target-peer',
              senderPeerId: 'my-peer',
              text: '',
              timestamp: authoredAt,
              status: 'sending',
              isIncoming: false,
              createdAt: authoredAt,
              directMediaCustodyIntentId: intent,
            );
            media.saved.add(
              MediaAttachment(
                id: attachmentId,
                messageId: messageId,
                mime: 'audio/mp4',
                size: 48000,
                mediaType: 'audio',
                durationMs: 3000,
                localPath: MediaFilePathConvention.relativePathForPendingUpload(
                  messageId: messageId,
                  attachmentId: attachmentId,
                  mime: 'audio/mp4',
                ),
                downloadStatus: 'upload_pending',
                createdAt: authoredAt,
                waveform: authoredWaveform,
                ownerLane: MediaOwnerLane.direct,
              ),
            );
            var uploadCalls = 0;
            final deleteSourceValues = <bool>[];
            Future<UploadMediaOutcome> crossedUpload({
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
              EncryptedMediaArtifact? preparedArtifact,
            }) async {
              uploadCalls++;
              deleteSourceValues.add(deleteSourceWhenDone);
              final completed = MediaAttachment(
                id: blobId!,
                messageId: '',
                mime: mime,
                size: 48000,
                mediaType: 'audio',
                durationMs: durationMs,
                localPath: 'media/target-peer/$attachmentId.m4a',
                downloadStatus: 'done',
                createdAt: '2026-08-07T12:05:09.000Z',
                waveform: waveform,
                contentHash: List<String>.filled(64, 'a').join(),
                encryptionKeyBase64: 'crossed-key',
                encryptionNonce: 'crossed-nonce',
                encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
              );
              return UploadMediaSucceeded(mutation.apply(completed));
            }

            final scenarioBridge = FakeBridge(
              initialResponses: {
                'message.encrypt': {
                  'ok': true,
                  'kem': 'unexpected-kem',
                  'ciphertext': 'unexpected-ciphertext',
                  'nonce': 'unexpected-nonce',
                },
              },
            );
            final fileManager = FakeMediaFileManager();
            var cleanupCalls = 0;
            fileManager.onDeletePendingUploadDir = (_) {
              cleanupCalls++;
            };

            final (result, message) = await sendVoiceMessage(
              p2pService: FakeP2PService(),
              messageRepo: messages,
              targetPeerId: 'target-peer',
              senderPeerId: 'my-peer',
              senderUsername: 'Me',
              recording: createRecording(),
              bridge: scenarioBridge,
              recipientMlKemPublicKey: mlKemKey,
              mediaAttachmentRepo: media,
              mediaFileManager: fileManager,
              waveform: authoredWaveform,
              messageId: messageId,
              timestamp: authoredAt,
              blobId: attachmentId,
              uploadMediaFn: crossedUpload,
            );

            expect(
              result,
              SendVoiceMessageResult.sendFailed,
              reason: mutation.name,
            );
            expect(message, isNull);
            expect(uploadCalls, 1);
            expect(deleteSourceValues, <bool>[false]);
            expect(
              scenarioBridge.commandLog,
              isNot(contains('message.encrypt')),
            );
            expect(media.directMediaCustodyStageCalls, 0);
            expect(media.stagedKinds, isEmpty);
            expect(messages.directCustodyRows, isEmpty);
            expect(
              messages.existingMessages[messageId]!.directMediaCustodyIntentId,
              intent,
            );
            expect(media.saved.single.downloadStatus, 'upload_pending');
            expect(cleanupCalls, 0);
          }
        },
      );

      test(
        'TC-345-06d existing v108 voice custody replays durable done media without upload',
        () async {
          const messageId = 'voice-345-existing-custody';
          const attachmentId = 'voice-345-existing-custody-attachment';
          const authoredAt = '2026-08-07T12:10:00.000Z';
          const contentHash =
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
          const waveform = <double>[0.1, 0.5, 0.2];

          Future<UploadMediaOutcome> unexpectedUpload({
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
            EncryptedMediaArtifact? preparedArtifact,
          }) async {
            fail('existing custody must replay without upload');
          }

          Future<
            ({
              SendVoiceMessageResult result,
              ConversationMessage? message,
              FakeMessageRepository messages,
              _PreparedVoiceCustodyRepository media,
              FakeP2PService p2p,
              FakeBridge bridge,
              int cleanupCalls,
            })
          >
          runReplay({required bool malformedEnvelope}) async {
            final envelope = malformedEnvelope
                ? '{"type":"chat_message","version":"2","id":"wrong"}'
                : jsonEncode(<String, Object?>{
                    'type': 'chat_message',
                    'version': '2',
                    'id': messageId,
                    'senderPeerId': 'my-peer',
                    'encrypted': <String, String>{
                      'kem': 'durable-kem',
                      'ciphertext': 'durable-ciphertext',
                      'nonce': 'durable-nonce',
                    },
                  });
            final messages = FakeMessageRepository();
            final media = _PreparedVoiceCustodyRepository(messages);
            final parent = ConversationMessage(
              id: messageId,
              contactPeerId: 'target-peer',
              senderPeerId: 'my-peer',
              text: '',
              timestamp: authoredAt,
              status: 'sending',
              isIncoming: false,
              createdAt: authoredAt,
              wireEnvelope: envelope,
            );
            messages.existingMessages[messageId] = parent;
            messages.directCustodyRows['target-peer\u0000$messageId'] =
                DirectInboxCustodyOutboxEntry(
                  recipientPeerId: 'target-peer',
                  messageId: messageId,
                  incarnationId: '0123456789abcdef0123456789abcdef',
                  wireEnvelope: envelope,
                  retryCount: 0,
                  lastAttemptAt: null,
                  lastErrorCode: null,
                  createdAt: authoredAt,
                  updatedAt: authoredAt,
                );
            media.saved.add(
              const MediaAttachment(
                id: attachmentId,
                messageId: messageId,
                mime: 'audio/mp4',
                size: 48000,
                mediaType: 'audio',
                durationMs: 3000,
                localPath:
                    'media/target-peer/voice-345-existing-custody-attachment.m4a',
                downloadStatus: 'done',
                createdAt: authoredAt,
                waveform: waveform,
                contentHash: contentHash,
                encryptionKeyBase64: 'durable-key',
                encryptionNonce: 'durable-nonce',
                encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
                ownerLane: MediaOwnerLane.direct,
              ),
            );
            final p2p = FakeP2PService();
            final replayBridge = FakeBridge();
            final fileManager = FakeMediaFileManager();
            var cleanupCalls = 0;
            fileManager.onDeletePendingUploadDir = (_) {
              cleanupCalls++;
            };

            final (result, message) = await sendVoiceMessage(
              p2pService: p2p,
              messageRepo: messages,
              targetPeerId: 'target-peer',
              senderPeerId: 'my-peer',
              senderUsername: 'Me',
              recording: AudioRecording(
                filePath: '/missing/previous-recorder-source.m4a',
                durationMs: 3000,
                mime: 'audio/mp4',
                sizeBytes: 48000,
              ),
              bridge: replayBridge,
              recipientMlKemPublicKey: null,
              mediaAttachmentRepo: media,
              mediaFileManager: fileManager,
              waveform: waveform,
              messageId: messageId,
              timestamp: authoredAt,
              blobId: attachmentId,
              uploadMediaFn: unexpectedUpload,
            );
            return (
              result: result,
              message: message,
              messages: messages,
              media: media,
              p2p: p2p,
              bridge: replayBridge,
              cleanupCalls: cleanupCalls,
            );
          }

          final exact = await runReplay(malformedEnvelope: false);
          expect(exact.result, SendVoiceMessageResult.success);
          expect(exact.message, isNotNull);
          expect(exact.p2p.lastSentMessage, isNotNull);
          expect(exact.media.directMediaCustodyStageCalls, 0);
          expect(exact.messages.ordinaryStageCalls, isEmpty);
          expect(exact.messages.directCustodyLoadForMessageCallCount, 2);
          expect(exact.bridge.commandLog, isNot(contains('media:upload')));
          expect(exact.bridge.commandLog, isNot(contains('message.encrypt')));
          expect(exact.cleanupCalls, 0);

          final malformed = await runReplay(malformedEnvelope: true);
          expect(malformed.result, SendVoiceMessageResult.sendFailed);
          expect(malformed.message, isNull);
          expect(malformed.p2p.sendCallCount, 0);
          expect(malformed.p2p.storeInInboxCallCount, 0);
          expect(malformed.media.directMediaCustodyStageCalls, 0);
          expect(malformed.messages.ordinaryStageCalls, isEmpty);
          expect(malformed.messages.directCustodyRows, hasLength(1));
          expect(malformed.bridge.commandLog, isNot(contains('media:upload')));
          expect(
            malformed.bridge.commandLog,
            isNot(contains('message.encrypt')),
          );
          expect(malformed.cleanupCalls, 0);
        },
      );

      test(
        'TC-345-06f outbox-only voice custody drains immutable bytes without upload or parent mutation',
        () async {
          const authoredAt = '2026-08-07T12:15:00.000Z';
          var uploadCalls = 0;
          Future<UploadMediaOutcome> unexpectedUpload({
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
            EncryptedMediaArtifact? preparedArtifact,
          }) async {
            uploadCalls++;
            return const UploadMediaFailed(
              stage: UploadMediaStage.transport,
              disposition: UploadMediaDisposition.connectivityRetryable,
              errorCode: 'UNEXPECTED_UPLOAD',
            );
          }

          for (final storeAccepted in <bool>[false, true]) {
            final suffix = storeAccepted ? 'completed' : 'retained';
            final messageId = 'voice-345-outbox-only-$suffix';
            final envelope = jsonEncode(<String, Object?>{
              'type': 'chat_message',
              'version': '2',
              'id': messageId,
              'senderPeerId': 'my-peer',
              'encrypted': <String, String>{
                'kem': 'immutable-kem',
                'ciphertext': 'immutable-ciphertext',
                'nonce': 'immutable-nonce',
              },
            });
            final messages = FakeMessageRepository();
            final media = _PreparedVoiceCustodyRepository(messages);
            messages.directCustodyRows['target-peer\u0000$messageId'] =
                DirectInboxCustodyOutboxEntry(
                  recipientPeerId: 'target-peer',
                  messageId: messageId,
                  incarnationId: 'fedcba9876543210fedcba9876543210',
                  wireEnvelope: envelope,
                  retryCount: 0,
                  lastAttemptAt: null,
                  lastErrorCode: null,
                  createdAt: authoredAt,
                  updatedAt: authoredAt,
                );
            final p2p = FakeP2PService(storeInInboxResult: storeAccepted);
            final scenarioBridge = FakeBridge();
            final fileManager = FakeMediaFileManager();
            var cleanupCalls = 0;
            fileManager.onDeletePendingUploadDir = (_) {
              cleanupCalls++;
            };

            final (result, message) = await sendVoiceMessage(
              p2pService: p2p,
              messageRepo: messages,
              targetPeerId: 'target-peer',
              senderPeerId: 'my-peer',
              senderUsername: 'Me',
              recording: AudioRecording(
                filePath: '/missing/outbox-only-recorder-source.m4a',
                durationMs: 3000,
                mime: 'audio/mp4',
                sizeBytes: storeAccepted ? 0 : 104857601,
              ),
              bridge: scenarioBridge,
              recipientMlKemPublicKey: null,
              mediaAttachmentRepo: media,
              mediaFileManager: fileManager,
              messageId: messageId,
              blobId: '$messageId-attachment',
              uploadMediaFn: unexpectedUpload,
            );

            expect(
              result,
              storeAccepted
                  ? SendVoiceMessageResult.success
                  : SendVoiceMessageResult.sendFailed,
              reason: suffix,
            );
            expect(message, isNull);
            expect(uploadCalls, 0);
            expect(p2p.storeInInboxCallCount, 1);
            expect(p2p.lastInboxMessage, envelope);
            expect(p2p.sendCallCount, 0);
            expect(media.directMediaCustodyStageCalls, 0);
            expect(messages.ordinaryStageCalls, isEmpty);
            expect(messages.ordinarySettlementCalls, isEmpty);
            expect(messages.existingMessages, isEmpty);
            expect(scenarioBridge.commandLog, isNot(contains('media:upload')));
            expect(
              scenarioBridge.commandLog,
              isNot(contains('message.encrypt')),
            );
            expect(cleanupCalls, 0);
            if (storeAccepted) {
              expect(messages.directCustodyRows, isEmpty);
            } else {
              expect(messages.directCustodyRows, hasLength(1));
              expect(messages.directCustodyRows.values.single.retryCount, 1);
            }
          }
        },
      );

      test(
        'TC-345-06i voice global custody drains stored recipient before validation or upload',
        () async {
          const messageId = 'voice-345-stored-recipient-drift';
          const storedRecipient = 'voice-original-recipient';
          const driftedRecipient = 'voice-mutated-recipient';
          const authoredAt = '2026-08-07T12:17:00.000Z';
          final envelope = jsonEncode(<String, Object?>{
            'type': 'chat_message',
            'version': '2',
            'id': messageId,
            'senderPeerId': 'my-peer',
            'encrypted': <String, String>{
              'kem': 'immutable-kem',
              'ciphertext': 'immutable-ciphertext',
              'nonce': 'immutable-nonce',
            },
          });
          final messages = FakeMessageRepository()
            ..forceCurrent(
              ConversationMessage(
                id: messageId,
                contactPeerId: driftedRecipient,
                senderPeerId: 'my-peer',
                text: 'mutable losing projection',
                timestamp: authoredAt,
                status: 'failed',
                isIncoming: false,
                createdAt: authoredAt,
                wireEnvelope: envelope,
              ),
            );
          messages.directCustodyRows['$storedRecipient\u0000$messageId'] =
              DirectInboxCustodyOutboxEntry(
                recipientPeerId: storedRecipient,
                messageId: messageId,
                incarnationId: '0123456789abcdef0123456789abcdef',
                wireEnvelope: envelope,
                retryCount: 0,
                lastAttemptAt: null,
                lastErrorCode: null,
                createdAt: authoredAt,
                updatedAt: authoredAt,
              );
          final media = _PreparedVoiceCustodyRepository(messages);
          final p2p = FakeP2PService(
            ackCustodyStoreOutcome: const InboxStoreOutcome(
              status: InboxStoreStatus.stored,
              storeStatus: 'stored',
              custodyContract: ackOrExpiryInboxCustodyContract,
              expiresAtMs: 345060,
            ),
          );
          final scenarioBridge = FakeBridge();
          var uploadCalls = 0;
          Future<UploadMediaOutcome> unexpectedUpload({
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
            EncryptedMediaArtifact? preparedArtifact,
          }) async {
            uploadCalls++;
            return const UploadMediaFailed(
              stage: UploadMediaStage.transport,
              disposition: UploadMediaDisposition.connectivityRetryable,
              errorCode: 'UNEXPECTED_UPLOAD',
            );
          }

          final (result, message) = await sendVoiceMessage(
            p2pService: p2p,
            messageRepo: messages,
            targetPeerId: driftedRecipient,
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
            recording: AudioRecording(
              filePath: '/missing/drifted-recorder-source.m4a',
              durationMs: 0,
              mime: 'audio/mp4',
              sizeBytes: 104857601,
            ),
            bridge: scenarioBridge,
            mediaAttachmentRepo: media,
            messageId: messageId,
            blobId: '$messageId-attachment',
            uploadMediaFn: unexpectedUpload,
          );

          expect(result, SendVoiceMessageResult.success);
          expect(message, isNull);
          expect(uploadCalls, 0);
          expect(p2p.ackCustodyStoreCallCount, 1);
          expect(p2p.lastAckCustodyKind, AckCustodyKind.directTextV108);
          expect(p2p.lastInboxPeerId, storedRecipient);
          expect(p2p.lastInboxMessage, envelope);
          expect(p2p.storeInInboxCallCount, 0);
          expect(p2p.sendCallCount, 0);
          expect(media.directMediaCustodyStageCalls, 0);
          expect(messages.ordinaryStageCalls, isEmpty);
          expect(messages.directCustodyRows, isEmpty);
          expect(scenarioBridge.commandLog, isNot(contains('media:upload')));
          expect(scenarioBridge.commandLog, isNot(contains('message.encrypt')));
        },
      );

      test(
        'TC-345-06g disappearance before exact completion converges without upload',
        () async {
          const messageId = 'voice-345-outbox-converged-between-loads';
          const authoredAt = '2026-08-07T12:20:00.000Z';
          final envelope = jsonEncode(<String, Object?>{
            'type': 'chat_message',
            'version': '2',
            'id': messageId,
            'senderPeerId': 'my-peer',
            'encrypted': <String, String>{
              'kem': 'converged-kem',
              'ciphertext': 'converged-ciphertext',
              'nonce': 'converged-nonce',
            },
          });
          final messages = _CustodyDisappearsBeforeCompletionRepository();
          final media = _PreparedVoiceCustodyRepository(messages);
          messages.directCustodyRows['target-peer\u0000$messageId'] =
              DirectInboxCustodyOutboxEntry(
                recipientPeerId: 'target-peer',
                messageId: messageId,
                incarnationId: '00112233445566778899aabbccddeeff',
                wireEnvelope: envelope,
                retryCount: 0,
                lastAttemptAt: null,
                lastErrorCode: null,
                createdAt: authoredAt,
                updatedAt: authoredAt,
              );
          var uploadCalls = 0;
          Future<UploadMediaOutcome> unexpectedUpload({
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
            EncryptedMediaArtifact? preparedArtifact,
          }) async {
            uploadCalls++;
            return const UploadMediaFailed(
              stage: UploadMediaStage.transport,
              disposition: UploadMediaDisposition.connectivityRetryable,
              errorCode: 'UNEXPECTED_UPLOAD',
            );
          }

          final p2p = FakeP2PService(storeInInboxResult: true);
          final scenarioBridge = FakeBridge();

          final (result, message) = await sendVoiceMessage(
            p2pService: p2p,
            messageRepo: messages,
            targetPeerId: 'target-peer',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
            recording: AudioRecording(
              filePath: '/missing/converged-recorder-source.m4a',
              durationMs: 3000,
              mime: 'audio/mp4',
              sizeBytes: 48000,
            ),
            bridge: scenarioBridge,
            recipientMlKemPublicKey: null,
            mediaAttachmentRepo: media,
            messageId: messageId,
            blobId: '$messageId-attachment',
            uploadMediaFn: unexpectedUpload,
          );

          expect(result, SendVoiceMessageResult.success);
          expect(message, isNull);
          expect(messages.exactCustodyLoads, 2);
          expect(messages.directCustodyRows, isEmpty);
          expect(messages.directCustodyCompletionCalls, hasLength(1));
          expect(messages.existingMessages, isEmpty);
          expect(uploadCalls, 0);
          expect(p2p.storeInInboxCallCount, 1);
          expect(p2p.lastInboxMessage, envelope);
          expect(p2p.sendCallCount, 0);
          expect(media.directMediaCustodyStageCalls, 0);
          expect(messages.ordinaryStageCalls, isEmpty);
          expect(messages.ordinarySettlementCalls, isEmpty);
          expect(scenarioBridge.commandLog, isNot(contains('media:upload')));
          expect(scenarioBridge.commandLog, isNot(contains('message.encrypt')));
        },
      );

      test(
        'caller-owned fresh voice ID is insert-only before transport',
        () async {
          const messageId = 'caller-owned-fresh-voice';
          const blobId = 'caller-owned-fresh-voice-blob';
          final recording = createRecording();
          var observedCommittedPair = false;
          p2pService
            ..isConnectedToPeerResult = true
            ..sendMessageAcked = true
            ..sendMessageTransport = 'direct'
            ..onSendMessage = () {
              final parent = messageRepo.existingMessages[messageId];
              observedCommittedPair =
                  parent != null &&
                  parent.status == 'sending' &&
                  parent.wireEnvelope != null &&
                  mediaAttachmentRepo.saved.length == 1 &&
                  mediaAttachmentRepo.saved.single.messageId == messageId &&
                  mediaAttachmentRepo.saved.single.id == blobId;
            };

          final (result, message) = await sendVoiceMessage(
            p2pService: p2pService,
            messageRepo: messageRepo,
            targetPeerId: 'target-peer',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
            recording: recording,
            bridge: bridge,
            recipientMlKemPublicKey: mlKemKey,
            mediaAttachmentRepo: mediaAttachmentRepo,
            messageId: messageId,
            preassignedMessageIdIsFresh: true,
            timestamp: '2026-08-05T12:00:00.000Z',
            blobId: blobId,
          );

          expect(result, SendVoiceMessageResult.success);
          expect(observedCommittedPair, isTrue);
          expect(mediaAttachmentRepo.directMediaCustodyStageCalls, 1);
          expect(
            mediaAttachmentRepo.stagedKinds,
            isEmpty,
            reason: 'fresh voice uses the combined custody authority',
          );
          expect(message!.id, messageId);
          expect(message.media.single.id, blobId);
          expect(messageRepo.ordinaryStageCalls.single.expected, isNull);
          expect(messageRepo.wireEnvelopeUpdates, isEmpty);

          final transportCallsBeforeCollision = p2pService.sendCallCount;
          final inboxCallsBeforeCollision = p2pService.storeInInboxCallCount;
          final collisionRecording = createRecording();
          final (collisionResult, collisionMessage) = await sendVoiceMessage(
            p2pService: p2pService,
            messageRepo: messageRepo,
            targetPeerId: 'target-peer',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
            recording: collisionRecording,
            bridge: bridge,
            recipientMlKemPublicKey: mlKemKey,
            mediaAttachmentRepo: mediaAttachmentRepo,
            messageId: messageId,
            preassignedMessageIdIsFresh: true,
            timestamp: '2026-08-05T12:01:00.000Z',
            blobId: blobId,
          );
          expect(collisionResult, SendVoiceMessageResult.sendFailed);
          expect(collisionMessage, isNull);
          expect(p2pService.sendCallCount, transportCallsBeforeCollision);
          expect(
            p2pService.storeInInboxCallCount,
            inboxCallsBeforeCollision + 1,
            reason:
                'the immutable v108 owner drains instead of re-uploading the colliding draft',
          );
          expect(messageRepo.existingMessages[messageId]!.status, 'delivered');
        },
      );

      test('calls sendChatMessage with audio MediaAttachment', () async {
        final recording = createRecording();

        final (result, _) = await sendVoiceMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          recording: recording,
          bridge: bridge,
          recipientMlKemPublicKey: mlKemKey,
          mediaAttachmentRepo: mediaAttachmentRepo,
        );

        expect(result, SendVoiceMessageResult.success);
        // sendChatMessage should have been called (the message was sent via P2P)
        expect(p2pService.sendCallCount, greaterThan(0));
      });

      test('message persisted with correct status after send', () async {
        final recording = createRecording();

        await sendVoiceMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          recording: recording,
          bridge: bridge,
          recipientMlKemPublicKey: mlKemKey,
          mediaAttachmentRepo: mediaAttachmentRepo,
        );

        // sendChatMessage persists the message
        expect(messageRepo.saved, isNotEmpty);
      });

      test(
        'forwards blobId to uploadMedia and persists stable attachment id',
        () async {
          final recording = createRecording();
          const stableBlobId = 'voice-stable-blob-001';

          final (result, _) = await sendVoiceMessage(
            p2pService: p2pService,
            messageRepo: messageRepo,
            targetPeerId: 'target-peer',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
            recording: recording,
            bridge: bridge,
            recipientMlKemPublicKey: mlKemKey,
            mediaAttachmentRepo: mediaAttachmentRepo,
            blobId: stableBlobId,
          );

          expect(result, SendVoiceMessageResult.success);
          expect(mediaAttachmentRepo.saved, isNotEmpty);
          expect(mediaAttachmentRepo.saved.first.id, stableBlobId);
        },
      );

      test('allows empty text (voice-only message)', () async {
        final recording = createRecording();

        final (result, _) = await sendVoiceMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          recording: recording,
          bridge: bridge,
          recipientMlKemPublicKey: mlKemKey,
          mediaAttachmentRepo: mediaAttachmentRepo,
        );

        expect(result, SendVoiceMessageResult.success);
      });

      test('allows text caption alongside voice', () async {
        final recording = createRecording();

        final (result, _) = await sendVoiceMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          recording: recording,
          bridge: bridge,
          recipientMlKemPublicKey: mlKemKey,
          mediaAttachmentRepo: mediaAttachmentRepo,
          text: 'Listen to this!',
        );

        expect(result, SendVoiceMessageResult.success);
      });

      test('preserves quotedMessageId on the sent voice message', () async {
        final recording = createRecording();

        final (result, message) = await sendVoiceMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          recording: recording,
          bridge: bridge,
          recipientMlKemPublicKey: mlKemKey,
          mediaAttachmentRepo: mediaAttachmentRepo,
          quotedMessageId: 'parent-voice-1',
        );

        expect(result, SendVoiceMessageResult.success);
        expect(message!.quotedMessageId, 'parent-voice-1');
        expect(messageRepo.saved.last.quotedMessageId, 'parent-voice-1');
      });

      test('returns uploadFailed when bridge upload fails', () async {
        bridge.responses['media:upload'] = {
          'ok': false,
          'errorMessage': 'fail',
        };
        final recording = createRecording();

        final (result, _) = await sendVoiceMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          recording: recording,
          bridge: bridge,
          recipientMlKemPublicKey: mlKemKey,
          mediaAttachmentRepo: mediaAttachmentRepo,
        );

        expect(result, SendVoiceMessageResult.uploadFailed);
      });

      test(
        'connectivity failure stages pending media and projects exactly once into queued result',
        () async {
          final recording = createRecording();
          final projection = _RecordingVoiceUploadProjection();
          Future<UploadMediaOutcome> connectivityFailure({
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
            EncryptedMediaArtifact? preparedArtifact,
          }) async => const UploadMediaFailed(
            stage: UploadMediaStage.transport,
            disposition: UploadMediaDisposition.connectivityRetryable,
            errorCode: 'NOT_INITIALIZED',
          );

          final (result, _) = await sendVoiceMessage(
            p2pService: p2pService,
            messageRepo: messageRepo,
            targetPeerId: 'target-peer',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
            recording: recording,
            bridge: bridge,
            recipientMlKemPublicKey: mlKemKey,
            messageId: 'voice-message-1',
            blobId: 'voice-attachment-1',
            mediaAttachmentRepo: mediaAttachmentRepo,
            mediaFileManager: FakeMediaFileManager(),
            uploadMediaFn: connectivityFailure,
            uploadRetryProjectionRepo: projection,
          );

          expect(result, SendVoiceMessageResult.uploadQueued);
          expect(projection.callCount, 1);
          expect(projection.messageId, 'voice-message-1');
          expect(projection.attachmentId, 'voice-attachment-1');
          expect(
            projection.failure?.disposition,
            UploadMediaDisposition.connectivityRetryable,
          );
          expect(mediaAttachmentRepo.saved, hasLength(1));
          expect(
            mediaAttachmentRepo.saved.single.downloadStatus,
            'upload_pending',
          );
        },
      );

      test(
        'returns sendFailed when upload succeeds but message send fails',
        () async {
          p2pService.sendMessageResult = false;
          final recording = createRecording();

          final (result, message) = await sendVoiceMessage(
            p2pService: p2pService,
            messageRepo: messageRepo,
            targetPeerId: 'target-peer',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
            recording: recording,
            bridge: bridge,
            recipientMlKemPublicKey: mlKemKey,
            mediaAttachmentRepo: mediaAttachmentRepo,
          );

          expect(result, SendVoiceMessageResult.sendFailed);
          expect(message, isNull);
        },
      );

      test(
        'creates MediaAttachment with audio mediaType and correct durationMs',
        () async {
          final recording = createRecording(durationMs: 5500);

          await sendVoiceMessage(
            p2pService: p2pService,
            messageRepo: messageRepo,
            targetPeerId: 'target-peer',
            senderPeerId: 'my-peer',
            senderUsername: 'Me',
            recording: recording,
            bridge: bridge,
            recipientMlKemPublicKey: mlKemKey,
            mediaAttachmentRepo: mediaAttachmentRepo,
          );

          // The media attachment should have been saved
          expect(mediaAttachmentRepo.saved, isNotEmpty);
          final attachment = mediaAttachmentRepo.saved.first;
          expect(attachment.mediaType, 'audio');
          expect(attachment.mime, 'audio/mp4');
          expect(attachment.durationMs, 5500);
        },
      );
    });

    // --- 112 Phase 2.3: voice inherits the 1:1 blob-encryption flip ---
    group('blob encryption', () {
      test('voice upload produces encrypted attachment metadata and passes the '
          'send gate', () async {
        final recording = createRecording();

        final (result, message) = await sendVoiceMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          recording: recording,
          bridge: bridge,
          recipientMlKemPublicKey: mlKemKey,
          mediaAttachmentRepo: mediaAttachmentRepo,
        );

        expect(result, SendVoiceMessageResult.success);
        expect(message, isNotNull);
        expect(
          bridge.commandLog,
          containsAllInOrder(['blob:keygen', 'blob:encrypt', 'media:upload']),
        );
        final attachment = mediaAttachmentRepo.saved.first;
        expect(attachment.encryptionKeyBase64, isNotNull);
        expect(attachment.encryptionNonce, isNotNull);
        expect(
          attachment.encryptionScheme,
          kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        );
        expect(attachment.contentHash, isNotNull);
      });

      test('voice temp recording deleted after durable copy and successful '
          'upload', () async {
        final recording = createRecording(
          filePath:
              '${tempDir.path}/voice_temp_cleanup_'
              '${DateTime.now().microsecondsSinceEpoch}.m4a',
        );
        final recordingFile = File(recording.filePath);
        expect(recordingFile.existsSync(), isTrue);

        final (result, _) = await sendVoiceMessage(
          p2pService: p2pService,
          messageRepo: messageRepo,
          targetPeerId: 'target-peer',
          senderPeerId: 'my-peer',
          senderUsername: 'Me',
          recording: recording,
          bridge: bridge,
          recipientMlKemPublicKey: mlKemKey,
          mediaAttachmentRepo: mediaAttachmentRepo,
          mediaFileManager: FakeMediaFileManager(),
        );

        expect(result, SendVoiceMessageResult.success);
        // The recorder temp (`voice_<ts>.m4a`) is plaintext residue once
        // the durable copy is the render source — it must be unlinked.
        expect(recordingFile.existsSync(), isFalse);
      });
    });
  });
}
