import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_app/core/database/helpers/media_library_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/media_attachments_db_helpers.dart'
    show
        DirectMediaBlobGenerationDbStageOutcome,
        DirectMediaBlobGenerationDbStageResult,
        DirectMediaInboxCustodyDbStageResult,
        GenericMediaAttachmentCustodySaveRefused,
        IncomingDirectMediaBlobDbStageOutcome,
        IncomingDirectMediaBlobDbStageResult,
        mediaLocalPathIsTransient,
        shouldPreserveImmutableDirectMediaCustodyAttachmentProjection;
import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';
import 'package:flutter_app/core/database/direct_media_blob_custody.dart';
import 'package:flutter_app/core/media/direct_private_media_path_guard.dart';
import 'package:flutter_app/core/media/direct_private_media_transfer_registry.dart';
import 'package:flutter_app/core/media/direct_media_blob_custody.dart';
import 'package:flutter_app/core/media/direct_media_blob_terminalization.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/media_attachment_lifecycle_lock.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_file_path_convention.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/outgoing_direct_private_mutation_coordinator.dart';
import 'package:flutter_app/core/media/upload_media_outcome.dart';
import 'package:flutter_app/core/media/upload_retry_projection.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/secure_storage/secret_storage_references.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';

import '../../domain/models/media_attachment.dart';
import '../../domain/models/conversation_message.dart';
import '../../domain/models/direct_media_blob_generation_result.dart';
import '../../domain/models/incoming_direct_media_blob_custody_result.dart';
import '../../domain/models/media_library.dart';
import '../../domain/models/media_preview_descriptor.dart';
import '../../domain/models/media_storage.dart';
import '../../domain/models/outgoing_ordinary_mutation_result.dart';
import '../../domain/models/outgoing_direct_media_custody_stage_result.dart';
import '../../domain/models/direct_inbox_custody_outbox_entry.dart';
import '../../domain/repositories/media_attachment_repository.dart';
import '../../domain/repositories/message_repository.dart';

({String? manifestHash, int? expiresAtMs})?
_canonicalDirectMediaBlobWireBinding(List<MediaAttachment> attachments) {
  if (attachments.isEmpty) return null;
  final hasAnyCommitment = attachments.any(
    (attachment) => attachment.blobCustody != null,
  );
  if (!hasAnyCommitment) {
    return (manifestHash: null, expiresAtMs: null);
  }
  if (attachments.any((attachment) {
    final commitment = attachment.blobCustody;
    return commitment == null ||
        !commitment.isValid ||
        commitment.contentHash != attachment.contentHash;
  })) {
    return null;
  }
  try {
    final manifest = attachments
        .map(
          (attachment) => DirectMediaBlobManifestProjection(
            attachmentId: attachment.id,
            commitment: attachment.blobCustody!,
          ),
        )
        .toList(growable: false);
    return (
      manifestHash: computeDirectMediaBlobManifestHash(manifest),
      expiresAtMs: earliestDirectMediaBlobExpiryMs(manifest),
    );
  } on FormatException {
    return null;
  }
}

/// Implementation of MediaAttachmentRepository using database helper functions.
///
/// 228 ownership contract: every message-scoped closure takes the owner-lane
/// string as its final argument, and [saveAttachment] validates the immutable
/// `(attachmentId, ownerLane, messageId)` identity BEFORE `_toStorageRow` or
/// any secure-store side effect. The save closure
/// ([dbSaveMediaAttachmentPreservingLocalState]) must merge atomically,
/// preserving local-only owner/bookmark/playback state and a completed local
/// path, and re-validate identity inside the write transaction as the final
/// race guard.
///
/// Every public attachment-row mutator enters [lifecycleLock]. Methods whose
/// names end in `WithinLock` also enter it defensively; acquisition is
/// reentrant only for the same async-zone attachment lease, so these public
/// capabilities cannot be used to bypass the row mutation authority. Bulk
/// message/contact writers use the lock's exclusive mode because their full
/// affected attachment set cannot be frozen before the database statement.
class MediaAttachmentRepositoryImpl
    implements
        MediaAttachmentRepository,
        MediaAttachmentAuthorizationChangeSource,
        MediaAttachmentByIdLookup,
        MediaPreviewDescriptorLookup,
        MediaLibraryStateRepository,
        DirectMediaLibraryStateRepository,
        GroupMediaLibraryStateRepository,
        MediaLibraryRepository,
        MediaDownloadStateRepository,
        OrdinaryGroupAutomaticMediaDownloadStateRepository,
        OrdinaryGroupExplicitMediaDownloadStateRepository,
        OrdinaryGroupMediaDownloadFailureRepository,
        RecoverableGroupMediaDownloadRepository,
        DirectPrivateMediaDownloadStateRepository,
        DirectPrivateMediaAttachmentSaveRepository,
        DirectPrivateMediaCleanupRepository,
        DirectPrivateCommittedPendingCleanupCandidateRepository,
        DirectPrivateMediaLegacyPathRepairRepository,
        OutgoingDirectPrivateMutationRepository,
        DirectPrivateMediaCleanupRuntime,
        GroupPrivateMediaDownloadStateRepository,
        GroupPrivateMediaCleanupRepository,
        GroupPrivateMediaCleanupRuntime,
        MediaStorageInventoryRepository,
        GroupGuardedMediaAttachmentSave,
        OutgoingOrdinaryAttemptStagingRepository,
        OutgoingDirectMediaInboxCustodyStagingRepository,
        DirectMediaBlobCustodyRepository,
        OutgoingDirectMediaBlobTerminalizationRepository,
        IncomingDirectMediaBlobCustodyRepository,
        OutgoingDirectMediaCustodyFailureRepository,
        NewMessageMediaPersistenceRollback {
  final Future<void> Function(Map<String, Object?> row)
  dbSaveMediaAttachmentPreservingLocalState;
  final Future<bool> Function(Map<String, Object?> row)?
  dbCanApplyGenericMediaAttachmentSave;
  final Future<OutgoingOrdinaryMutationOutcome> Function({
    required Map<String, Object?>? expectedRow,
    required Map<String, Object?> stagedRow,
    required List<Map<String, Object?>> attachmentRows,
    required OutgoingOrdinaryAttemptKind kind,
  })?
  dbStageOutgoingOrdinaryAttemptWithMedia;
  final Future<DirectMediaInboxCustodyDbStageResult> Function({
    required Map<String, Object?>? expectedRow,
    required Map<String, Object?> stagedRow,
    required List<Map<String, Object?>> attachmentRows,
    required OutgoingOrdinaryAttemptKind kind,
    required String recipientPeerId,
    required String wireEnvelope,
    String? wireMediaBlobManifestHash,
    int? wireMediaBlobExpiresAtMs,
  })?
  dbStageOutgoingDirectMediaInboxCustody;
  final Future<DirectMediaBlobGenerationDbStageResult> Function({
    required Map<String, Object?> expectedParentRow,
    required List<Map<String, Object?>> expectedAttachmentRows,
    required List<Map<String, Object?>> preparedAttachmentRows,
    required List<DirectMediaBlobCustodyRow> custodyRows,
  })?
  dbStageOutgoingDirectMediaBlobGeneration;
  final Future<DirectMediaBlobCustodyRow?> Function({
    required String attachmentId,
  })?
  dbLoadDirectMediaBlobCustodyForAttachment;
  final Future<List<DirectMediaBlobCustodyRow>> Function({
    required String messageId,
  })?
  dbLoadDirectMediaBlobCustodyForMessage;
  final Future<List<DirectMediaBlobCustodyRow>> Function({
    required Set<DirectMediaBlobCustodyState> states,
    int limit,
  })?
  dbLoadDirectMediaBlobCustodyByStates;
  final Future<bool> Function({
    required DirectMediaBlobCustodyRow expected,
    required DirectMediaBlobCustodyRow next,
  })?
  dbTransitionDirectMediaBlobCustodyIfExact;
  final Future<bool> Function({required DirectMediaBlobCustodyRow expected})?
  dbDeleteDirectMediaBlobCleanupPendingIfExact;
  final Future<DirectMediaBlobTerminalizationOutcome> Function({
    required List<DirectMediaBlobCustodyRow> expectedRows,
    required DirectMediaBlobTerminalizationReason reason,
    required int nowMs,
  })?
  dbTerminalizeOutgoingDirectMediaBlobGenerationIfExact;
  final Future<IncomingDirectMediaBlobDbStageResult> Function({
    required Map<String, Object?> messageRow,
    required List<Map<String, Object?>> attachmentRows,
    required List<DirectMediaBlobCustodyRow> custodyRows,
  })?
  dbStageIncomingDirectMediaBlobCustody;
  final Future<bool> Function({
    required Map<String, Object?> expectedAttachmentRow,
    required DirectMediaBlobCustodyRow expectedCustody,
    required String localPath,
    required String? sourceRelayPeerId,
    required String updatedAt,
  })?
  dbCommitIncomingDirectMediaBlobLocalPath;
  final Future<bool> Function({required DirectMediaBlobCustodyRow expected})?
  dbDeleteIncomingDirectMediaBlobAckPendingIfExact;
  final Future<bool> Function({
    required DirectMediaBlobCustodyRow expected,
    required int nowMs,
  })?
  dbDeleteIncomingDirectMediaBlobIfExpired;
  final Future<UploadRetryProjectionResult> Function({
    required Map<String, Object?> expectedParentRow,
    required List<Map<String, Object?>> expectedAttachmentRows,
    required String failedAttachmentId,
    required UploadMediaDisposition disposition,
  })?
  dbProjectOutgoingDirectMediaCustodyUploadFailure;
  final Future<OutgoingOrdinaryMutationResult> Function({
    required String messageId,
    required OutgoingOrdinaryMutationOutcome outcome,
    required List<MediaAttachment> committedMedia,
  })?
  publishOutgoingOrdinaryMutation;
  final Future<List<Map<String, Object?>>> Function(
    String messageId,
    String ownerLane,
  )
  dbLoadMediaForMessage;
  final Future<Map<String, Object?>?> Function(String id) dbLoadMediaById;
  final Future<List<Map<String, Object?>>> Function(
    List<String> messageIds,
    String ownerLane,
  )
  dbLoadMediaForMessages;
  final Future<List<Map<String, Object?>>> Function({int limit})?
  dbLoadOutgoingDirectPrivateCommittedPendingCleanupCandidates;
  final Future<void> Function(
    String id,
    String localPath,
    String downloadStatus,
  )
  dbUpdateMediaLocalPath;
  final Future<void> Function(String id, String downloadStatus)
  dbUpdateMediaDownloadStatus;
  final Future<int> Function(String messageId, String ownerLane)
  dbDeleteMediaForMessage;
  final Future<int> Function(String contactPeerId) dbDeleteMediaForContact;
  final Future<int> Function(String messageId, String ownerLane)
  dbMarkUploadPendingAttachmentsFailedForMessage;
  final Future<List<Map<String, Object?>>> Function()
  dbLoadPendingMediaDownloads;
  final Future<List<Map<String, Object?>>> Function({
    required int limit,
    String? afterCreatedAt,
    String? afterAttachmentId,
  })?
  dbLoadRecoverableGroupMediaDownloadPage;
  final Future<List<Map<String, Object?>>> Function({
    int limit,
    required String ownerLane,
  })
  dbLoadUploadPendingAttachments;
  final Future<void> Function(String id, bool bookmarked) dbSetMediaBookmarked;
  final Future<bool> Function({
    required String messageId,
    required String attachmentId,
    required bool bookmarked,
  })?
  dbSetDirectMediaBookmarkedIfOrdinary;
  final Future<bool> Function({
    required String groupId,
    required String messageId,
    required String attachmentId,
    required bool bookmarked,
  })?
  dbSetGroupMediaBookmarkedIfOrdinary;
  final Future<void> Function(String id, int positionMs)
  dbUpdateMediaPlaybackPosition;
  final Future<List<Map<String, Object?>>> Function({
    required String scopeKind,
    required String scopeId,
    required List<String> mediaTypes,
    required bool bookmarkedOnly,
    required bool incomingOnly,
    required int limit,
    String? afterTimestamp,
    String? afterMessageId,
    String? afterAttachmentId,
  })
  dbLoadMediaLibraryPage;

  // 229: the owner-scoped all-media storage page closure. Optional like the
  // CAS closures below; the capability fails closed when missing.
  final Future<List<Map<String, Object?>>> Function({
    required String scopeKind,
    required String scopeId,
    required List<String> mediaTypes,
    required int limit,
    String? afterTimestamp,
    String? afterMessageId,
    String? afterAttachmentId,
  })?
  dbLoadMediaStoragePage;

  // 229: owner-aware CAS closures. Optional so schema-only constructions
  // keep compiling, but the capability methods fail closed (StateError)
  // rather than silently degrading when a closure is missing.
  final Future<int> Function(String id, {required String ownerLane})?
  dbBeginMediaDownload;
  final Future<int> Function(
    String id, {
    required String ownerLane,
    required String localPath,
  })?
  dbCommitMediaDownloadLocalPath;
  final Future<int> Function(
    String id, {
    required String groupId,
    required String messageId,
    required String expectedDownloadStatus,
    required String? expectedLocalPath,
  })?
  dbBeginOrdinaryGroupAutomaticMediaDownloadExact;
  final Future<int> Function(
    String id, {
    required String groupId,
    required String messageId,
    required String? expectedLocalPath,
    required String localPath,
  })?
  dbCommitOrdinaryGroupAutomaticMediaDownloadLocalPathExact;
  final Future<int> Function(
    String id, {
    required String groupId,
    required String messageId,
    required String expectedDownloadStatus,
    required String? expectedLocalPath,
  })?
  dbBeginOrdinaryGroupExplicitMediaDownloadExact;
  final Future<int> Function(
    String id, {
    required String groupId,
    required String messageId,
    required String? expectedLocalPath,
    required String localPath,
  })?
  dbCommitOrdinaryGroupExplicitMediaDownloadLocalPathExact;
  final Future<int> Function(
    String id, {
    required String groupId,
    required String messageId,
    required bool incrementRetryCount,
    required String failureStatus,
    required String expectedDownloadStatus,
    required String? expectedLocalPath,
    required bool clearLocalPath,
  })?
  dbRecordOrdinaryGroupMediaDownloadFailureExact;
  final Future<int> Function(
    String id, {
    required String ownerLane,
    required String expectedLocalPath,
  })?
  dbClaimMediaEvicted;
  final Future<int> Function(String id, {required String ownerLane})?
  dbFinalizeMediaEvictedPathCleared;
  final Future<int> Function({
    required String messageId,
    required String attachmentId,
    required String localPath,
    required int nowMs,
  })?
  dbCommitDirectPrivateMediaDownloadIfEligible;
  final Future<int> Function({
    required String messageId,
    required String attachmentId,
    required int nowMs,
  })?
  dbBeginDirectPrivateMediaDownloadIfEligible;
  final Future<int> Function({
    required String messageId,
    required String attachmentId,
    required String expectedLocalPath,
    required int nowMs,
  })?
  dbQualifyDirectPrivateMediaLocalReadyIfEligible;
  final Future<int> Function({
    required String messageId,
    required String attachmentId,
    required String expectedStoredLocalPath,
    required String canonicalLocalPath,
    required String expectedContactPeerId,
    required String expectedMime,
    required int expectedSize,
  })?
  dbRepairOutgoingDirectPrivateMediaDoneLocalPathIfEligible;
  final Future<int> Function({
    required String messageId,
    required String attachmentId,
    required int nowMs,
  })?
  dbQualifyDirectPrivateMediaDownloadClaimIfEligible;
  final Future<int> Function({
    required String messageId,
    required String attachmentId,
    required int nowMs,
    required bool incrementRetryCount,
    required String failureStatus,
    required String expectedDownloadStatus,
    String? expectedLocalPath,
    bool clearLocalPath,
  })?
  dbRecordDirectPrivateMediaDownloadFailureIfEligible;
  final Future<bool> Function(
    Map<String, Object?> row, {
    required String messageId,
    required int nowMs,
  })?
  dbSaveDirectPrivateMediaAttachmentGuarded;
  final Future<bool> Function({
    required String messageId,
    required String attachmentId,
  })?
  dbCanCleanupDirectPrivateMediaAttachmentExact;
  final Future<int> Function({
    required String messageId,
    required String attachmentId,
  })?
  dbDeleteDirectPrivateMediaAttachmentExact;
  final Future<OutgoingDirectPrivateCompletionQualification> Function(
    Map<String, Object?> row, {
    required String expectedPendingLocalPath,
  })?
  dbClassifyOutgoingDirectPrivateMediaCompletion;
  final Future<bool> Function(
    Map<String, Object?> row, {
    required String expectedPendingLocalPath,
  })?
  dbCommitOutgoingDirectPrivateMediaAvailableCompletion;
  final Future<bool> Function(
    Map<String, Object?> row, {
    required String expectedPendingLocalPath,
    required String mode,
  })?
  dbRollbackOutgoingDirectPrivateMediaOpeningWithCompletion;
  final Future<OutgoingDirectPrivateNonCompletionMutationOutcome> Function(
    Map<String, Object?> row, {
    required bool missingParentIsOrdinary,
  })?
  dbApplyOutgoingDirectPrivateNonCompletionMutation;
  final Future<OutgoingDirectPrivatePendingPreparationOutcome> Function(
    List<Map<String, Object?>> rows,
  )?
  dbInsertOutgoingDirectPrivatePendingAttachmentsIfEligible;
  final Future<OutgoingDirectPrivateNonCompletionMutationOutcome> Function(
    String messageId,
  )?
  dbQualifyOutgoingDirectPrivatePendingAttachmentsDeletion;
  final Future<OutgoingDirectPrivateNonCompletionMutationOutcome> Function(
    String messageId,
  )?
  dbDeleteOutgoingDirectPrivatePendingAttachmentsIfEligible;
  final Future<int> Function({
    required String groupId,
    required String messageId,
    required String attachmentId,
    required int nowMs,
  })?
  dbBeginGroupPrivateMediaDownloadIfEligible;
  final Future<int> Function({
    required String groupId,
    required String messageId,
    required String attachmentId,
    required String expectedLocalPath,
    required int nowMs,
  })?
  dbQualifyGroupPrivateMediaLocalReadyIfEligible;
  final Future<int> Function({
    required String groupId,
    required String messageId,
    required String attachmentId,
    required int nowMs,
  })?
  dbQualifyGroupPrivateMediaDownloadClaimIfEligible;
  final Future<int> Function({
    required String groupId,
    required String messageId,
    required String attachmentId,
    required int nowMs,
    required bool incrementRetryCount,
    required String failureStatus,
    required String expectedDownloadStatus,
    String? expectedLocalPath,
    required bool clearLocalPath,
  })?
  dbRecordGroupPrivateMediaDownloadFailureIfEligible;
  final Future<int> Function({
    required String groupId,
    required String messageId,
    required String attachmentId,
    required String localPath,
    required int nowMs,
  })?
  dbCommitGroupPrivateMediaDownloadIfEligible;
  final Future<bool> Function({
    required String messageId,
    required String attachmentId,
  })?
  dbCanCleanupGroupPrivateMediaAttachmentExact;
  final Future<int> Function({
    required String messageId,
    required String attachmentId,
  })?
  dbDeleteGroupPrivateMediaAttachmentExact;

  // 235: guarded final write for incoming GROUP media (parent + deletion-
  // journal check in the SAME transaction as the row write). Optional like
  // the CAS closures; the capability fails closed when missing.
  final Future<bool> Function(
    Map<String, Object?> row, {
    required String groupId,
  })?
  dbSaveGroupMediaAttachmentGuarded;
  final Future<bool> Function({
    required Map<String, Object?> expectedParent,
    required Map<String, Object?> expectedAttachment,
    required Map<String, Object?> completedAttachment,
  })?
  dbCompleteGroupUploadRetryExact;

  final SecureKeyStore? secureKeyStore;
  final Future<void> Function(String messageId)?
  refreshDirectPrivateMediaParent;

  /// 235: serializes row/key/file work per attachment across the guarded
  /// save, the download commit, and the deletion-journal cleanup saga.
  final MediaAttachmentLifecycleLock lifecycleLock;
  final StreamController<MediaAttachmentAuthorizationChange>
  _authorizationChangesController =
      StreamController<MediaAttachmentAuthorizationChange>.broadcast(
        sync: true,
      );

  MediaAttachmentRepositoryImpl({
    required this.dbSaveMediaAttachmentPreservingLocalState,
    this.dbCanApplyGenericMediaAttachmentSave,
    this.dbStageOutgoingOrdinaryAttemptWithMedia,
    this.dbStageOutgoingDirectMediaInboxCustody,
    this.dbStageOutgoingDirectMediaBlobGeneration,
    this.dbLoadDirectMediaBlobCustodyForAttachment,
    this.dbLoadDirectMediaBlobCustodyForMessage,
    this.dbLoadDirectMediaBlobCustodyByStates,
    this.dbTransitionDirectMediaBlobCustodyIfExact,
    this.dbDeleteDirectMediaBlobCleanupPendingIfExact,
    this.dbTerminalizeOutgoingDirectMediaBlobGenerationIfExact,
    this.dbStageIncomingDirectMediaBlobCustody,
    this.dbCommitIncomingDirectMediaBlobLocalPath,
    this.dbDeleteIncomingDirectMediaBlobAckPendingIfExact,
    this.dbDeleteIncomingDirectMediaBlobIfExpired,
    this.dbProjectOutgoingDirectMediaCustodyUploadFailure,
    this.publishOutgoingOrdinaryMutation,
    required this.dbLoadMediaForMessage,
    required this.dbLoadMediaById,
    required this.dbLoadMediaForMessages,
    this.dbLoadOutgoingDirectPrivateCommittedPendingCleanupCandidates,
    required this.dbUpdateMediaLocalPath,
    required this.dbUpdateMediaDownloadStatus,
    required this.dbDeleteMediaForMessage,
    required this.dbDeleteMediaForContact,
    required this.dbMarkUploadPendingAttachmentsFailedForMessage,
    required this.dbLoadPendingMediaDownloads,
    this.dbLoadRecoverableGroupMediaDownloadPage,
    required this.dbLoadUploadPendingAttachments,
    required this.dbSetMediaBookmarked,
    this.dbSetDirectMediaBookmarkedIfOrdinary,
    this.dbSetGroupMediaBookmarkedIfOrdinary,
    required this.dbUpdateMediaPlaybackPosition,
    required this.dbLoadMediaLibraryPage,
    this.dbLoadMediaStoragePage,
    this.dbBeginMediaDownload,
    this.dbCommitMediaDownloadLocalPath,
    this.dbBeginOrdinaryGroupAutomaticMediaDownloadExact,
    this.dbCommitOrdinaryGroupAutomaticMediaDownloadLocalPathExact,
    this.dbBeginOrdinaryGroupExplicitMediaDownloadExact,
    this.dbCommitOrdinaryGroupExplicitMediaDownloadLocalPathExact,
    this.dbRecordOrdinaryGroupMediaDownloadFailureExact,
    this.dbClaimMediaEvicted,
    this.dbFinalizeMediaEvictedPathCleared,
    this.dbCommitDirectPrivateMediaDownloadIfEligible,
    this.dbBeginDirectPrivateMediaDownloadIfEligible,
    this.dbQualifyDirectPrivateMediaLocalReadyIfEligible,
    this.dbRepairOutgoingDirectPrivateMediaDoneLocalPathIfEligible,
    this.dbQualifyDirectPrivateMediaDownloadClaimIfEligible,
    this.dbRecordDirectPrivateMediaDownloadFailureIfEligible,
    this.dbSaveDirectPrivateMediaAttachmentGuarded,
    this.dbCanCleanupDirectPrivateMediaAttachmentExact,
    this.dbDeleteDirectPrivateMediaAttachmentExact,
    this.dbClassifyOutgoingDirectPrivateMediaCompletion,
    this.dbCommitOutgoingDirectPrivateMediaAvailableCompletion,
    this.dbRollbackOutgoingDirectPrivateMediaOpeningWithCompletion,
    this.dbApplyOutgoingDirectPrivateNonCompletionMutation,
    this.dbInsertOutgoingDirectPrivatePendingAttachmentsIfEligible,
    this.dbQualifyOutgoingDirectPrivatePendingAttachmentsDeletion,
    this.dbDeleteOutgoingDirectPrivatePendingAttachmentsIfEligible,
    this.dbBeginGroupPrivateMediaDownloadIfEligible,
    this.dbQualifyGroupPrivateMediaLocalReadyIfEligible,
    this.dbQualifyGroupPrivateMediaDownloadClaimIfEligible,
    this.dbRecordGroupPrivateMediaDownloadFailureIfEligible,
    this.dbCommitGroupPrivateMediaDownloadIfEligible,
    this.dbCanCleanupGroupPrivateMediaAttachmentExact,
    this.dbDeleteGroupPrivateMediaAttachmentExact,
    this.dbSaveGroupMediaAttachmentGuarded,
    this.dbCompleteGroupUploadRetryExact,
    this.secureKeyStore,
    this.refreshDirectPrivateMediaParent,
    MediaAttachmentLifecycleLock? lifecycleLock,
  }) : lifecycleLock = lifecycleLock ?? mediaAttachmentLifecycleLock;

  @override
  bool get supportsDirectMediaInboxCustody =>
      dbStageOutgoingDirectMediaInboxCustody != null &&
      dbCanApplyGenericMediaAttachmentSave != null &&
      publishOutgoingOrdinaryMutation != null;

  @override
  bool get supportsDirectMediaCustodyFailureProjection =>
      dbProjectOutgoingDirectMediaCustodyUploadFailure != null;

  @override
  bool get supportsDirectMediaBlobCustody =>
      dbStageOutgoingDirectMediaBlobGeneration != null &&
      dbLoadDirectMediaBlobCustodyForAttachment != null &&
      dbLoadDirectMediaBlobCustodyForMessage != null &&
      dbLoadDirectMediaBlobCustodyByStates != null &&
      dbTransitionDirectMediaBlobCustodyIfExact != null &&
      dbDeleteDirectMediaBlobCleanupPendingIfExact != null &&
      dbTerminalizeOutgoingDirectMediaBlobGenerationIfExact != null;

  @override
  bool get supportsOutgoingDirectMediaBlobTerminalization =>
      dbTerminalizeOutgoingDirectMediaBlobGenerationIfExact != null &&
      dbLoadDirectMediaBlobCustodyForMessage != null;

  @override
  bool get supportsIncomingDirectMediaBlobCustody =>
      dbStageIncomingDirectMediaBlobCustody != null &&
      dbCommitIncomingDirectMediaBlobLocalPath != null &&
      dbDeleteIncomingDirectMediaBlobAckPendingIfExact != null &&
      dbDeleteIncomingDirectMediaBlobIfExpired != null &&
      dbLoadDirectMediaBlobCustodyForAttachment != null &&
      dbLoadDirectMediaBlobCustodyByStates != null;

  @override
  Future<T> runDirectMediaBlobCustodyLifecycle<T>(
    Future<T> Function() action,
  ) => lifecycleLock.synchronizedAll(action);

  @override
  Future<DirectMediaBlobGenerationStageResult>
  stageOutgoingDirectMediaBlobGeneration({
    required ConversationMessage expectedParent,
    required List<MediaAttachment> expectedAttachments,
    required List<MediaAttachment> preparedAttachments,
    required List<DirectMediaBlobCustodyRow> custodyRows,
  }) async {
    final stage = dbStageOutgoingDirectMediaBlobGeneration;
    if (!supportsDirectMediaBlobCustody ||
        stage == null ||
        expectedAttachments.isEmpty ||
        expectedAttachments.length != preparedAttachments.length ||
        expectedAttachments.length != custodyRows.length) {
      return const DirectMediaBlobGenerationStageResult.refused();
    }
    final expectedIds = expectedAttachments
        .map((attachment) => attachment.id)
        .toSet();
    if (expectedIds.length != expectedAttachments.length ||
        preparedAttachments.any(
          (attachment) =>
              !expectedIds.contains(attachment.id) ||
              attachment.messageId != expectedParent.id ||
              attachment.ownerLane != MediaOwnerLane.direct ||
              attachment.encryptionKeyBase64 == null ||
              attachment.encryptionKeyBase64!.isEmpty ||
              isSecureStoreReference(attachment.encryptionKeyBase64),
        ) ||
        custodyRows.any(
          (row) =>
              !expectedIds.contains(row.attachmentId) ||
              row.messageId != expectedParent.id,
        )) {
      return const DirectMediaBlobGenerationStageResult.refused();
    }

    final stamped = preparedAttachments
        .map(
          (attachment) => attachment.copyWith(ownerLane: MediaOwnerLane.direct),
        )
        .toList(growable: false);
    final dbResult = await lifecycleLock.synchronizedAll(() async {
      // The process-wide lifecycle lock serializes every production preparer.
      // If a complete DB winner is already visible, ask the DB helper to
      // validate/adopt it using reference-only candidate rows. Crucially, the
      // losing raw key never reaches the stable per-attachment secure slot.
      final existingRows = await dbLoadDirectMediaBlobCustodyForMessage!(
        messageId: expectedParent.id,
      );
      if (existingRows.isNotEmpty) {
        return stage(
          expectedParentRow: expectedParent.toMap(),
          expectedAttachmentRows: expectedAttachments
              .map((attachment) => attachment.toMap())
              .toList(growable: false),
          preparedAttachmentRows: stamped
              .map(_toStorageReferenceRowWithoutKeyWrite)
              .toList(growable: false),
          custodyRows: custodyRows,
        );
      }

      final snapshots = <_MediaEncryptionKeyWriteSnapshot>[];
      var restored = false;
      Future<void> restoreAll() async {
        if (restored) return;
        restored = true;
        Object? firstError;
        for (final snapshot in snapshots.reversed) {
          try {
            await snapshot.restore();
          } catch (error) {
            firstError ??= error;
          }
        }
        if (firstError != null) {
          throw StateError(
            'direct-media blob generation key compensation failed: '
            '$firstError',
          );
        }
      }

      try {
        for (final attachment in stamped) {
          snapshots.add(await _captureEncryptionKeyWriteSnapshot(attachment));
        }
        final preparedRows = <Map<String, Object?>>[];
        for (final attachment in stamped) {
          preparedRows.add(await _toStorageRow(attachment));
        }
        final result = await stage(
          expectedParentRow: expectedParent.toMap(),
          expectedAttachmentRows: expectedAttachments
              .map((attachment) => attachment.toMap())
              .toList(growable: false),
          preparedAttachmentRows: preparedRows,
          custodyRows: custodyRows,
        );
        if (result.outcome != DirectMediaBlobGenerationDbStageOutcome.applied) {
          // An idempotent result belongs to a concurrent winner. Never leave a
          // loser's raw key under the stable per-attachment secure-store name.
          await restoreAll();
        }
        return result;
      } catch (_) {
        await restoreAll();
        rethrow;
      }
    });

    if (!dbResult.outcome.authorizesStrictUpload ||
        dbResult.attachmentRows.length != expectedAttachments.length ||
        dbResult.custodyRows.length != custodyRows.length) {
      return const DirectMediaBlobGenerationStageResult.refused();
    }
    final attachments = await _attachmentsFromRows(dbResult.attachmentRows);
    final rows = dbResult.custodyRows
        .map(DirectMediaBlobCustodyRow.fromMap)
        .toList(growable: false);
    final outcome = switch (dbResult.outcome) {
      DirectMediaBlobGenerationDbStageOutcome.applied =>
        DirectMediaBlobGenerationStageOutcome.applied,
      DirectMediaBlobGenerationDbStageOutcome.idempotent =>
        DirectMediaBlobGenerationStageOutcome.idempotent,
      DirectMediaBlobGenerationDbStageOutcome.refused =>
        DirectMediaBlobGenerationStageOutcome.refused,
    };
    return DirectMediaBlobGenerationStageResult(
      outcome: outcome,
      attachments: attachments,
      custodyRows: rows,
    );
  }

  @override
  Future<DirectMediaBlobCustodyRow?> loadDirectMediaBlobCustodyForAttachment(
    String attachmentId,
  ) {
    final load = dbLoadDirectMediaBlobCustodyForAttachment;
    if (load == null) return Future.value();
    return load(attachmentId: attachmentId);
  }

  @override
  Future<List<DirectMediaBlobCustodyRow>> loadDirectMediaBlobCustodyForMessage(
    String messageId,
  ) {
    final load = dbLoadDirectMediaBlobCustodyForMessage;
    if (load == null) return Future.value(const []);
    return load(messageId: messageId);
  }

  @override
  Future<List<DirectMediaBlobCustodyRow>> loadDirectMediaBlobCustodyByStates(
    Set<DirectMediaBlobCustodyState> states, {
    int limit = 50,
  }) {
    final load = dbLoadDirectMediaBlobCustodyByStates;
    if (load == null) return Future.value(const []);
    return load(states: states, limit: limit);
  }

  @override
  Future<bool> transitionDirectMediaBlobCustodyIfExact({
    required DirectMediaBlobCustodyRow expected,
    required DirectMediaBlobCustodyRow next,
  }) {
    // Cleanup publication is message-wide authority. The generic per-row API
    // remains available for prepared -> stored upload proof, but can never
    // expose a raw prepared/stored -> cleanup transition.
    if (next.state == DirectMediaBlobCustodyState.outgoingCleanupPending) {
      return Future.value(false);
    }
    final transition = dbTransitionDirectMediaBlobCustodyIfExact;
    if (transition == null) return Future.value(false);
    return lifecycleLock.synchronized(
      expected.attachmentId,
      () => transition(expected: expected, next: next),
    );
  }

  @override
  Future<DirectMediaBlobTerminalizationOutcome>
  terminalizeOutgoingDirectMediaBlobGenerationIfExact({
    required List<DirectMediaBlobCustodyRow> expectedRows,
    required DirectMediaBlobTerminalizationReason reason,
    required int nowMs,
  }) {
    final terminalize = dbTerminalizeOutgoingDirectMediaBlobGenerationIfExact;
    if (!supportsOutgoingDirectMediaBlobTerminalization ||
        terminalize == null) {
      return Future.value(DirectMediaBlobTerminalizationOutcome.refused);
    }
    return lifecycleLock.synchronizedAll(
      () =>
          terminalize(expectedRows: expectedRows, reason: reason, nowMs: nowMs),
    );
  }

  @override
  Future<bool> deleteDirectMediaBlobCleanupPendingIfExact(
    DirectMediaBlobCustodyRow expected,
  ) {
    final delete = dbDeleteDirectMediaBlobCleanupPendingIfExact;
    if (delete == null) return Future.value(false);
    return lifecycleLock.synchronized(
      expected.attachmentId,
      () => delete(expected: expected),
    );
  }

  @override
  Future<IncomingDirectMediaBlobCustodyStageResult>
  stageIncomingDirectMediaBlobCustody({
    required ConversationMessage message,
    required List<MediaAttachment> attachments,
    required List<DirectMediaBlobCustodyRow> custodyRows,
  }) async {
    final stage = dbStageIncomingDirectMediaBlobCustody;
    if (!supportsIncomingDirectMediaBlobCustody ||
        stage == null ||
        !message.isIncoming ||
        message.privateMediaPolicy.requiresRedaction ||
        attachments.isEmpty ||
        attachments.length != custodyRows.length ||
        attachments.any(
          (attachment) =>
              attachment.messageId != message.id ||
              attachment.ownerLane != MediaOwnerLane.direct ||
              attachment.blobCustody == null ||
              !attachment.blobCustody!.isValid ||
              (attachment.directMediaBlobCustodyFingerprint != null &&
                  attachment.directMediaBlobCustodyFingerprint !=
                      computeDirectMediaBlobCommitmentFingerprint(
                        attachmentId: attachment.id,
                        commitment: attachment.blobCustody!,
                      )),
        )) {
      return const IncomingDirectMediaBlobCustodyStageResult.refused();
    }
    final commitmentById = <String, DirectMediaBlobCustodyRow>{
      for (final row in custodyRows) row.attachmentId: row,
    };
    if (commitmentById.length != attachments.length ||
        attachments.any((attachment) {
          final commitment = attachment.blobCustody!;
          final row = commitmentById[attachment.id];
          return row == null ||
              row.messageId != message.id ||
              row.state != DirectMediaBlobCustodyState.incomingCommitted ||
              row.contentHash != commitment.contentHash ||
              row.ciphertextSize != commitment.ciphertextSize ||
              row.custodyKind != commitment.kind ||
              row.custodyContract != commitment.contract ||
              row.transportMime != commitment.transportMime ||
              row.expiresAtMs != commitment.expiresAtMs;
        })) {
      return const IncomingDirectMediaBlobCustodyStageResult.refused();
    }

    final dbResult = await lifecycleLock.synchronizedAll(() async {
      final snapshots = <_MediaEncryptionKeyWriteSnapshot>[];
      var restored = false;
      Future<void> restoreAll() async {
        if (restored) return;
        restored = true;
        Object? firstError;
        for (final snapshot in snapshots.reversed) {
          try {
            await snapshot.restore();
          } catch (error) {
            firstError ??= error;
          }
        }
        if (firstError != null) {
          throw StateError(
            'strict incoming media key compensation failed: $firstError',
          );
        }
      }

      try {
        final storageRows = <Map<String, Object?>>[];
        for (final attachment in attachments) {
          snapshots.add(await _captureEncryptionKeyWriteSnapshot(attachment));
          storageRows.add(
            await _toStorageRow(
              attachment.copyWith(
                directMediaBlobCustodyFingerprint:
                    computeDirectMediaBlobCommitmentFingerprint(
                      attachmentId: attachment.id,
                      commitment: attachment.blobCustody!,
                    ),
              ),
            ),
          );
        }
        final result = await stage(
          messageRow: message.toMap(),
          attachmentRows: storageRows,
          custodyRows: custodyRows,
        );
        if (result.outcome != IncomingDirectMediaBlobDbStageOutcome.applied) {
          await restoreAll();
        }
        return result;
      } catch (_) {
        await restoreAll();
        rethrow;
      }
    });
    if (dbResult.messageRow == null ||
        dbResult.attachmentRows.length != attachments.length) {
      return const IncomingDirectMediaBlobCustodyStageResult.refused();
    }
    final outcome = switch (dbResult.outcome) {
      IncomingDirectMediaBlobDbStageOutcome.applied =>
        IncomingDirectMediaBlobCustodyStageOutcome.applied,
      IncomingDirectMediaBlobDbStageOutcome.idempotent =>
        IncomingDirectMediaBlobCustodyStageOutcome.idempotent,
      IncomingDirectMediaBlobDbStageOutcome.refused =>
        IncomingDirectMediaBlobCustodyStageOutcome.refused,
    };
    return IncomingDirectMediaBlobCustodyStageResult(
      outcome: outcome,
      attachments: await _attachmentsFromRows(dbResult.attachmentRows),
    );
  }

  @override
  Future<bool> commitIncomingDirectMediaBlobLocalPath({
    required MediaAttachment expectedAttachment,
    required DirectMediaBlobCustodyRow expectedCustody,
    required String localPath,
    required String? sourceRelayPeerId,
    required String updatedAt,
  }) {
    final commit = dbCommitIncomingDirectMediaBlobLocalPath;
    if (commit == null) return Future.value(false);
    return lifecycleLock.synchronized(expectedAttachment.id, () {
      return commit(
        expectedAttachmentRow: _toStorageExpectationRow(expectedAttachment),
        expectedCustody: expectedCustody,
        localPath: localPath,
        sourceRelayPeerId: sourceRelayPeerId,
        updatedAt: updatedAt,
      );
    });
  }

  @override
  Future<bool> deleteIncomingDirectMediaBlobAckIfExact(
    DirectMediaBlobCustodyRow expected,
  ) {
    final delete = dbDeleteIncomingDirectMediaBlobAckPendingIfExact;
    if (delete == null) return Future.value(false);
    return lifecycleLock.synchronized(
      expected.attachmentId,
      () => delete(expected: expected),
    );
  }

  @override
  Future<bool> deleteIncomingDirectMediaBlobIfExpired({
    required DirectMediaBlobCustodyRow expected,
    required int nowMs,
  }) {
    final delete = dbDeleteIncomingDirectMediaBlobIfExpired;
    if (delete == null) return Future.value(false);
    return lifecycleLock.synchronized(
      expected.attachmentId,
      () => delete(expected: expected, nowMs: nowMs),
    );
  }

  late final OutgoingDirectPrivateMutationCoordinator
  _outgoingDirectPrivateMutationCoordinator =
      OutgoingDirectPrivateMutationCoordinator(
        lifecycleLock: lifecycleLock,
        classifyCompletion: _classifyOutgoingDirectPrivateCompletion,
        commitAvailable: _commitOutgoingDirectPrivateAvailableCompletion,
        commitRollback: _commitOutgoingDirectPrivateRollbackCompletion,
      );

  @override
  OutgoingDirectPrivateMutationCoordinator
  get outgoingDirectPrivateMutationCoordinator =>
      _outgoingDirectPrivateMutationCoordinator;

  @override
  Stream<MediaAttachmentAuthorizationChange> get authorizationChanges =>
      _authorizationChangesController.stream;

  void _emitAuthorizationChange({
    required MediaOwnerLane owner,
    String? scopeId,
    String? messageId,
    String? attachmentId,
    required MediaAttachmentAuthorizationMutation kind,
  }) {
    _authorizationChangesController.add(
      MediaAttachmentAuthorizationChange(
        owner: owner,
        scopeId: scopeId,
        messageId: messageId,
        attachmentId: attachmentId,
        kind: kind,
      ),
    );
  }

  void _emitAuthorizationChangeForRow(
    Map<String, Object?> row,
    MediaAttachmentAuthorizationMutation kind,
  ) {
    final owner = mediaOwnerLaneFromDbValue(row['owner_lane'] as String?);
    final messageId = row['message_id'] as String?;
    final attachmentId = row['id'] as String?;
    if (owner == null || messageId == null || attachmentId == null) return;
    _emitAuthorizationChange(
      owner: owner,
      messageId: messageId,
      attachmentId: attachmentId,
      kind: kind,
    );
  }

  @override
  MediaAttachmentLifecycleLock get directPrivateMediaLifecycleLock =>
      lifecycleLock;

  @override
  MediaAttachmentLifecycleLock get groupPrivateMediaLifecycleLock =>
      lifecycleLock;

  @override
  Future<bool> deleteDirectPrivateMediaEncryptionKeyWithinLock({
    required String messageId,
    required String attachmentId,
  }) => lifecycleLock.synchronized(attachmentId, () async {
    final canCleanup = _requireCasClosure(
      dbCanCleanupDirectPrivateMediaAttachmentExact,
      'deleteDirectPrivateMediaEncryptionKeyWithinLock',
    );
    if (!await canCleanup(messageId: messageId, attachmentId: attachmentId)) {
      return false;
    }
    final store = secureKeyStore;
    if (store == null) {
      throw StateError(
        'direct private-media cleanup requires secure key storage',
      );
    }
    await store.delete(mediaAttachmentEncryptionKeyStoreName(attachmentId));
    return true;
  });

  T _requireCasClosure<T>(T? closure, String name) {
    if (closure == null) {
      throw StateError(
        '229 CAS closure $name is not wired on this '
        'MediaAttachmentRepositoryImpl — conditional download/eviction '
        'transitions fail closed instead of degrading to unconditional '
        'writes',
      );
    }
    return closure;
  }

  Future<T> _withCompensatedEncryptionKeyWrite<T>(
    MediaAttachment attachment,
    Future<T> Function(Map<String, Object?> row) persist, {
    required bool Function(T result) committed,
  }) async {
    final snapshot = await _captureEncryptionKeyWriteSnapshot(attachment);
    try {
      final row = await _toStorageRow(attachment);
      final result = await persist(row);
      if (!committed(result)) await snapshot.restore();
      return result;
    } catch (_) {
      await snapshot.restore();
      rethrow;
    }
  }

  Future<_MediaEncryptionKeyWriteSnapshot> _captureEncryptionKeyWriteSnapshot(
    MediaAttachment attachment,
  ) async {
    final store = secureKeyStore;
    final rawKey = attachment.encryptionKeyBase64;
    if (store == null ||
        rawKey == null ||
        rawKey.isEmpty ||
        isSecureStoreReference(rawKey)) {
      return _MediaEncryptionKeyWriteSnapshot.inactive();
    }
    final keyName = mediaAttachmentEncryptionKeyStoreName(attachment.id);
    final existed = await store.containsKey(keyName);
    final previousValue = existed ? await store.read(keyName) : null;
    if (existed && previousValue == null) {
      throw StateError(
        'existing secure media key is unreadable; refusing overwrite',
      );
    }
    return _MediaEncryptionKeyWriteSnapshot(
      store: store,
      keyName: keyName,
      existed: existed,
      previousValue: previousValue,
      replacementValue: rawKey,
    );
  }

  Future<OutgoingDirectPrivateCompletionQualification>
  _classifyOutgoingDirectPrivateCompletion(
    MediaAttachment attachment,
    OutgoingDirectPrivateCompletionFingerprint fingerprint,
  ) async {
    final completionKey = attachment.encryptionKeyBase64;
    if (completionKey != null && isSecureStoreReference(completionKey)) {
      // A successful upload carries the raw rotated key. Accepting a storage
      // reference here would let a first commit skip the compensated key
      // write and could persist a dangling or attacker-selected reference.
      return OutgoingDirectPrivateCompletionQualification.refused;
    }
    final classify = _requireCasClosure(
      dbClassifyOutgoingDirectPrivateMediaCompletion,
      'dbClassifyOutgoingDirectPrivateMediaCompletion',
    );
    final row = _toStorageReferenceRowWithoutKeyWrite(attachment);
    final qualification = await classify(
      row,
      expectedPendingLocalPath: fingerprint.expectedPendingLocalPath,
    );
    if (qualification !=
        OutgoingDirectPrivateCompletionQualification
            .identicalCommittedCandidate) {
      return qualification;
    }
    final persisted = await getAttachmentById(attachment.id);
    if (persisted == null ||
        !fingerprint.matchesHydratedAttachment(persisted)) {
      return OutgoingDirectPrivateCompletionQualification.refused;
    }
    return qualification;
  }

  Future<bool> _commitOutgoingDirectPrivateAvailableCompletion(
    MediaAttachment attachment,
    OutgoingDirectPrivateCompletionFingerprint fingerprint,
  ) async {
    final commit = _requireCasClosure(
      dbCommitOutgoingDirectPrivateMediaAvailableCompletion,
      'dbCommitOutgoingDirectPrivateMediaAvailableCompletion',
    );
    final stamped = attachment.copyWith(ownerLane: MediaOwnerLane.direct);
    final committed = await _withCompensatedEncryptionKeyWrite<bool>(
      stamped,
      (row) => commit(
        row,
        expectedPendingLocalPath: fingerprint.expectedPendingLocalPath,
      ),
      committed: (result) => result,
    );
    if (committed) {
      await _publishOutgoingPrivateCompletionBestEffort(attachment);
    }
    return committed;
  }

  Future<bool> _commitOutgoingDirectPrivateRollbackCompletion(
    MediaAttachment attachment,
    OutgoingDirectPrivateCompletionFingerprint fingerprint, {
    required String mode,
  }) async {
    final commit = _requireCasClosure(
      dbRollbackOutgoingDirectPrivateMediaOpeningWithCompletion,
      'dbRollbackOutgoingDirectPrivateMediaOpeningWithCompletion',
    );
    final stamped = attachment.copyWith(ownerLane: MediaOwnerLane.direct);
    final committed = await _withCompensatedEncryptionKeyWrite<bool>(
      stamped,
      (row) => commit(
        row,
        expectedPendingLocalPath: fingerprint.expectedPendingLocalPath,
        mode: mode,
      ),
      committed: (result) => result,
    );
    // Refresh/event publication is deliberately outside the compensated
    // key+DB callback. Once the DB transaction commits, an observer failure
    // cannot restore the old key or downgrade the durable result.
    if (committed) {
      await _publishOutgoingPrivateCompletionBestEffort(attachment);
    }
    return committed;
  }

  Future<void> _publishOutgoingPrivateCompletionBestEffort(
    MediaAttachment attachment,
  ) async {
    try {
      await _refreshDirectPrivateParent(attachment.messageId);
      _emitAuthorizationChange(
        owner: MediaOwnerLane.direct,
        messageId: attachment.messageId,
        attachmentId: attachment.id,
        kind: MediaAttachmentAuthorizationMutation.saved,
      );
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'OUTGOING_PRIVATE_COMPLETION_NOTIFICATION_ERROR',
        details: {'error': error.runtimeType.toString()},
      );
    }
  }

  MediaAttachment _pinImmutableDirectMediaProjection({
    required MediaAttachment incoming,
    required Map<String, Object?> existing,
  }) {
    final stored = MediaAttachment.fromMap(Map<String, dynamic>.from(existing));
    return MediaAttachment(
      id: stored.id,
      messageId: stored.messageId,
      mime: stored.mime,
      size: stored.size,
      mediaType: stored.mediaType,
      width: stored.width,
      height: stored.height,
      durationMs: stored.durationMs,
      localPath: incoming.localPath,
      downloadStatus: incoming.downloadStatus,
      createdAt: stored.createdAt,
      waveform: stored.waveform,
      uploadRetryCount: incoming.uploadRetryCount,
      downloadRetryCount: incoming.downloadRetryCount,
      contentHash: stored.contentHash,
      thumbnailHash: stored.thumbnailHash,
      encryptionKeyBase64: stored.encryptionKeyBase64,
      encryptionNonce: stored.encryptionNonce,
      encryptionScheme: stored.encryptionScheme,
      ownerLane: MediaOwnerLane.direct,
      isBookmarked: incoming.isBookmarked,
      lastPlaybackPositionMs: incoming.lastPlaybackPositionMs,
    );
  }

  Map<String, Object?> _toStorageReferenceRowWithoutKeyWrite(
    MediaAttachment attachment,
  ) {
    final stamped = attachment.copyWith(ownerLane: MediaOwnerLane.direct);
    final row = Map<String, Object?>.from(stamped.toMap());
    final key = stamped.encryptionKeyBase64;
    if (secureKeyStore != null &&
        key != null &&
        key.isNotEmpty &&
        !isSecureStoreReference(key)) {
      final keyName = mediaAttachmentEncryptionKeyStoreName(stamped.id);
      row['encryption_key_base64'] = secureStoreReferenceForKey(keyName);
    }
    return row;
  }

  @override
  Future<bool> saveDirectPrivateAttachmentGuarded(
    MediaAttachment attachment, {
    required String messageId,
    required int nowMs,
  }) async {
    if (attachment.messageId != messageId ||
        (attachment.ownerLane != null &&
            attachment.ownerLane != MediaOwnerLane.direct)) {
      throw MediaAttachmentOwnerViolation(
        'guarded direct private save received mismatched identity',
      );
    }
    final guarded = _requireCasClosure(
      dbSaveDirectPrivateMediaAttachmentGuarded,
      'saveDirectPrivateAttachmentGuarded',
    );
    final stamped = attachment.copyWith(ownerLane: MediaOwnerLane.direct);
    return lifecycleLock.synchronized(stamped.id, () async {
      final existingRow = await dbLoadMediaById(stamped.id);
      if (existingRow != null &&
          (existingRow['owner_lane'] != MediaOwnerLane.direct.dbValue ||
              existingRow['message_id'] != messageId)) {
        throw MediaAttachmentOwnerViolation(
          'guarded direct private save would re-parent attachment '
          '${stamped.id}',
        );
      }
      final saved = await _withCompensatedEncryptionKeyWrite<bool>(stamped, (
        row,
      ) async {
        try {
          return await guarded(row, messageId: messageId, nowMs: nowMs);
        } finally {
          await _refreshDirectPrivateParent(messageId);
        }
      }, committed: (saved) => saved);
      if (saved) {
        _emitAuthorizationChange(
          owner: MediaOwnerLane.direct,
          messageId: messageId,
          attachmentId: stamped.id,
          kind: MediaAttachmentAuthorizationMutation.saved,
        );
      }
      return saved;
    });
  }

  @override
  Future<bool> beginDirectPrivateMediaDownload(
    String id, {
    required String messageId,
    required int nowMs,
  }) {
    return lifecycleLock.synchronized(
      id,
      () => beginDirectPrivateMediaDownloadWithinLock(
        id,
        messageId: messageId,
        nowMs: nowMs,
      ),
    );
  }

  @override
  Future<bool> beginDirectPrivateMediaDownloadWithinLock(
    String id, {
    required String messageId,
    required int nowMs,
  }) => lifecycleLock.synchronized(id, () async {
    final begin = _requireCasClosure(
      dbBeginDirectPrivateMediaDownloadIfEligible,
      'beginDirectPrivateMediaDownload',
    );
    try {
      return await begin(messageId: messageId, attachmentId: id, nowMs: nowMs) >
          0;
    } finally {
      await _refreshDirectPrivateParent(messageId);
    }
  });

  @override
  Future<bool> qualifyDirectPrivateMediaLocalReady(
    String id, {
    required String messageId,
    required String expectedLocalPath,
    required int nowMs,
  }) {
    return lifecycleLock.synchronized(
      id,
      () => qualifyDirectPrivateMediaLocalReadyWithinLock(
        id,
        messageId: messageId,
        expectedLocalPath: expectedLocalPath,
        nowMs: nowMs,
      ),
    );
  }

  @override
  Future<bool> qualifyDirectPrivateMediaLocalReadyWithinLock(
    String id, {
    required String messageId,
    required String expectedLocalPath,
    required int nowMs,
  }) => lifecycleLock.synchronized(id, () async {
    final qualify = _requireCasClosure(
      dbQualifyDirectPrivateMediaLocalReadyIfEligible,
      'qualifyDirectPrivateMediaLocalReady',
    );
    try {
      return await qualify(
            messageId: messageId,
            attachmentId: id,
            expectedLocalPath: expectedLocalPath,
            nowMs: nowMs,
          ) >
          0;
    } finally {
      await _refreshDirectPrivateParent(messageId);
    }
  });

  @override
  Future<bool> repairOutgoingDirectPrivateMediaDoneLocalPathWithinLock({
    required String messageId,
    required String attachmentId,
    required String expectedStoredLocalPath,
    required String canonicalLocalPath,
    required String expectedContactPeerId,
    required String expectedMime,
    required int expectedSize,
  }) => lifecycleLock.synchronized(attachmentId, () async {
    final repair = _requireCasClosure(
      dbRepairOutgoingDirectPrivateMediaDoneLocalPathIfEligible,
      'repairOutgoingDirectPrivateMediaDoneLocalPathWithinLock',
    );
    var repaired = false;
    try {
      repaired =
          await repair(
            messageId: messageId,
            attachmentId: attachmentId,
            expectedStoredLocalPath: expectedStoredLocalPath,
            canonicalLocalPath: canonicalLocalPath,
            expectedContactPeerId: expectedContactPeerId,
            expectedMime: expectedMime,
            expectedSize: expectedSize,
          ) ==
          1;
    } finally {
      await _refreshDirectPrivateParent(messageId);
    }
    if (repaired) {
      _emitAuthorizationChange(
        owner: MediaOwnerLane.direct,
        messageId: messageId,
        attachmentId: attachmentId,
        kind: MediaAttachmentAuthorizationMutation.localPathChanged,
      );
    }
    return repaired;
  });

  @override
  Future<bool> qualifyDirectPrivateMediaDownloadClaimWithinLock(
    String id, {
    required String messageId,
    required int nowMs,
  }) => lifecycleLock.synchronized(id, () async {
    final qualify = _requireCasClosure(
      dbQualifyDirectPrivateMediaDownloadClaimIfEligible,
      'qualifyDirectPrivateMediaDownloadClaim',
    );
    try {
      return await qualify(
            messageId: messageId,
            attachmentId: id,
            nowMs: nowMs,
          ) >
          0;
    } finally {
      await _refreshDirectPrivateParent(messageId);
    }
  });

  @override
  Future<bool> recordDirectPrivateMediaDownloadFailure(
    String id, {
    required String messageId,
    required int nowMs,
    required bool incrementRetryCount,
    required String failureStatus,
    required String expectedDownloadStatus,
    String? expectedLocalPath,
    bool clearLocalPath = false,
  }) {
    return lifecycleLock.synchronized(
      id,
      () => recordDirectPrivateMediaDownloadFailureWithinLock(
        id,
        messageId: messageId,
        nowMs: nowMs,
        incrementRetryCount: incrementRetryCount,
        failureStatus: failureStatus,
        expectedDownloadStatus: expectedDownloadStatus,
        expectedLocalPath: expectedLocalPath,
        clearLocalPath: clearLocalPath,
      ),
    );
  }

  @override
  Future<bool> recordDirectPrivateMediaDownloadFailureWithinLock(
    String id, {
    required String messageId,
    required int nowMs,
    required bool incrementRetryCount,
    required String failureStatus,
    required String expectedDownloadStatus,
    String? expectedLocalPath,
    bool clearLocalPath = false,
  }) => lifecycleLock.synchronized(id, () async {
    final record = _requireCasClosure(
      dbRecordDirectPrivateMediaDownloadFailureIfEligible,
      'recordDirectPrivateMediaDownloadFailure',
    );
    try {
      return await record(
            messageId: messageId,
            attachmentId: id,
            nowMs: nowMs,
            incrementRetryCount: incrementRetryCount,
            failureStatus: failureStatus,
            expectedDownloadStatus: expectedDownloadStatus,
            expectedLocalPath: expectedLocalPath,
            clearLocalPath: clearLocalPath,
          ) >
          0;
    } finally {
      await _refreshDirectPrivateParent(messageId);
    }
  });

  @override
  Future<bool> beginMediaDownload(String id, {required MediaOwnerLane owner}) =>
      lifecycleLock.synchronized(id, () async {
        final claim = _requireCasClosure(
          dbBeginMediaDownload,
          'beginMediaDownload',
        );
        final previous = await dbLoadMediaById(id);
        final changed = await claim(id, ownerLane: owner.dbValue) > 0;
        if (changed && previous != null) {
          _emitAuthorizationChangeForRow(
            previous,
            MediaAttachmentAuthorizationMutation.downloadStarted,
          );
        }
        return changed;
      });

  @override
  Future<bool> commitMediaDownloadLocalPath(
    String id, {
    required MediaOwnerLane owner,
    required String localPath,
  }) => lifecycleLock.synchronized(id, () async {
    final commit = _requireCasClosure(
      dbCommitMediaDownloadLocalPath,
      'commitMediaDownloadLocalPath',
    );
    // 235: the commit shares the attachment lifecycle lock with the guarded
    // group save and the deletion-journal cleanup saga so a cleanup never
    // interleaves with a promotion on the same attachment. The SQL CAS (plus
    // the group journal anti-join) remains the correctness authority.
    final previous = await dbLoadMediaById(id);
    final changed =
        await commit(id, ownerLane: owner.dbValue, localPath: localPath) > 0;
    if (changed && previous != null) {
      _emitAuthorizationChangeForRow(
        previous,
        MediaAttachmentAuthorizationMutation.downloadCommitted,
      );
    }
    return changed;
  });

  @override
  Future<bool> beginOrdinaryGroupAutomaticMediaDownload(
    String id, {
    required String groupId,
    required String messageId,
    required String expectedDownloadStatus,
    required String? expectedLocalPath,
  }) => lifecycleLock.synchronized(id, () async {
    final claim = _requireCasClosure(
      dbBeginOrdinaryGroupAutomaticMediaDownloadExact,
      'beginOrdinaryGroupAutomaticMediaDownload',
    );
    final previous = await dbLoadMediaById(id);
    final changed =
        await claim(
          id,
          groupId: groupId,
          messageId: messageId,
          expectedDownloadStatus: expectedDownloadStatus,
          expectedLocalPath: expectedLocalPath,
        ) ==
        1;
    if (changed && previous != null) {
      _emitAuthorizationChangeForRow(
        previous,
        MediaAttachmentAuthorizationMutation.downloadStarted,
      );
    }
    return changed;
  });

  @override
  Future<bool> commitOrdinaryGroupAutomaticMediaDownloadLocalPath(
    String id, {
    required String groupId,
    required String messageId,
    required String? expectedLocalPath,
    required String localPath,
  }) => lifecycleLock.synchronized(id, () async {
    final commit = _requireCasClosure(
      dbCommitOrdinaryGroupAutomaticMediaDownloadLocalPathExact,
      'commitOrdinaryGroupAutomaticMediaDownloadLocalPath',
    );
    final previous = await dbLoadMediaById(id);
    final changed =
        await commit(
          id,
          groupId: groupId,
          messageId: messageId,
          expectedLocalPath: expectedLocalPath,
          localPath: localPath,
        ) ==
        1;
    if (changed && previous != null) {
      _emitAuthorizationChangeForRow(
        previous,
        MediaAttachmentAuthorizationMutation.downloadCommitted,
      );
    }
    return changed;
  });

  @override
  Future<bool> beginOrdinaryGroupExplicitMediaDownload(
    String id, {
    required String groupId,
    required String messageId,
    required String expectedDownloadStatus,
    required String? expectedLocalPath,
  }) => lifecycleLock.synchronized(id, () async {
    final claim = _requireCasClosure(
      dbBeginOrdinaryGroupExplicitMediaDownloadExact,
      'beginOrdinaryGroupExplicitMediaDownload',
    );
    final previous = await dbLoadMediaById(id);
    final changed =
        await claim(
          id,
          groupId: groupId,
          messageId: messageId,
          expectedDownloadStatus: expectedDownloadStatus,
          expectedLocalPath: expectedLocalPath,
        ) ==
        1;
    if (changed && previous != null) {
      _emitAuthorizationChangeForRow(
        previous,
        MediaAttachmentAuthorizationMutation.downloadStarted,
      );
    }
    return changed;
  });

  @override
  Future<bool> commitOrdinaryGroupExplicitMediaDownloadLocalPath(
    String id, {
    required String groupId,
    required String messageId,
    required String? expectedLocalPath,
    required String localPath,
  }) => lifecycleLock.synchronized(id, () async {
    final commit = _requireCasClosure(
      dbCommitOrdinaryGroupExplicitMediaDownloadLocalPathExact,
      'commitOrdinaryGroupExplicitMediaDownloadLocalPath',
    );
    final previous = await dbLoadMediaById(id);
    final changed =
        await commit(
          id,
          groupId: groupId,
          messageId: messageId,
          expectedLocalPath: expectedLocalPath,
          localPath: localPath,
        ) ==
        1;
    if (changed && previous != null) {
      _emitAuthorizationChangeForRow(
        previous,
        MediaAttachmentAuthorizationMutation.downloadCommitted,
      );
    }
    return changed;
  });

  @override
  Future<bool> recordOrdinaryGroupMediaDownloadFailure(
    String id, {
    required String groupId,
    required String messageId,
    required bool incrementRetryCount,
    required String failureStatus,
    required String expectedDownloadStatus,
    required String? expectedLocalPath,
    required bool clearLocalPath,
  }) => lifecycleLock.synchronized(id, () async {
    final record = _requireCasClosure(
      dbRecordOrdinaryGroupMediaDownloadFailureExact,
      'recordOrdinaryGroupMediaDownloadFailure',
    );
    final changed =
        await record(
          id,
          groupId: groupId,
          messageId: messageId,
          incrementRetryCount: incrementRetryCount,
          failureStatus: failureStatus,
          expectedDownloadStatus: expectedDownloadStatus,
          expectedLocalPath: expectedLocalPath,
          clearLocalPath: clearLocalPath,
        ) ==
        1;
    if (changed) {
      _emitAuthorizationChange(
        owner: MediaOwnerLane.group,
        scopeId: groupId,
        messageId: messageId,
        attachmentId: id,
        kind: MediaAttachmentAuthorizationMutation.downloadStatusChanged,
      );
    }
    return changed;
  });

  @override
  Future<bool> commitDirectPrivateMediaDownloadLocalPath(
    String id, {
    required String messageId,
    required String localPath,
    required int nowMs,
  }) {
    return lifecycleLock.synchronized(
      id,
      () => commitDirectPrivateMediaDownloadLocalPathWithinLock(
        id,
        messageId: messageId,
        localPath: localPath,
        nowMs: nowMs,
      ),
    );
  }

  @override
  Future<bool> commitDirectPrivateMediaDownloadLocalPathWithinLock(
    String id, {
    required String messageId,
    required String localPath,
    required int nowMs,
  }) => lifecycleLock.synchronized(id, () async {
    final commit = _requireCasClosure(
      dbCommitDirectPrivateMediaDownloadIfEligible,
      'commitDirectPrivateMediaDownloadLocalPath',
    );
    try {
      return await commit(
            messageId: messageId,
            attachmentId: id,
            localPath: localPath,
            nowMs: nowMs,
          ) >
          0;
    } finally {
      await _refreshDirectPrivateParent(messageId);
    }
  });

  Future<void> _refreshDirectPrivateParent(String messageId) async {
    final refresh = refreshDirectPrivateMediaParent;
    if (refresh == null) return;
    try {
      await refresh(messageId);
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'PRIVATE_MEDIA_PARENT_REFRESH_ERROR',
        details: {'error': error.runtimeType.toString()},
      );
    }
  }

  @override
  Future<List<DirectPrivateMediaLifecycleAttachmentMetadata>>
  loadDirectPrivateMediaLifecycleAttachmentMetadata(String messageId) async {
    final rows = await dbLoadMediaForMessage(
      messageId,
      MediaOwnerLane.direct.dbValue,
    );
    return rows
        .where(
          (row) =>
              row['message_id'] == messageId &&
              row['owner_lane'] == MediaOwnerLane.direct.dbValue,
        )
        .map(
          (row) => DirectPrivateMediaLifecycleAttachmentMetadata(
            id: row['id'] as String,
            messageId: row['message_id'] as String,
            mime: row['mime'] as String,
            size: (row['size'] as num).toInt(),
            downloadStatus: row['download_status'] as String,
            localPath: row['local_path'] as String?,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<DirectPrivateCommittedPendingCleanupCandidate>>
  loadDirectPrivateCommittedPendingCleanupCandidates({int limit = 50}) async {
    final load = dbLoadOutgoingDirectPrivateCommittedPendingCleanupCandidates;
    if (load == null || limit <= 0) {
      return const <DirectPrivateCommittedPendingCleanupCandidate>[];
    }
    final rows = await load(limit: limit.clamp(1, 100));
    final candidates = <DirectPrivateCommittedPendingCleanupCandidate>[];
    for (final row in rows) {
      final hydrated = MediaAttachment.fromMap(await _hydrateRow(row));
      final messageId = row['message_id'] as String? ?? '';
      final attachmentId = row['id'] as String? ?? '';
      final contactPeerId = row['contact_peer_id'] as String? ?? '';
      final mime = row['mime'] as String? ?? '';
      final localPath = row['local_path'] as String?;
      if (hydrated.id != attachmentId ||
          hydrated.messageId != messageId ||
          hydrated.ownerLane != MediaOwnerLane.direct ||
          hydrated.downloadStatus != kMediaDownloadStatusDone ||
          hydrated.mime != mime ||
          hydrated.localPath != localPath ||
          hydrated.size <= 0 ||
          hydrated.contentHash == null ||
          hydrated.contentHash!.trim().isEmpty ||
          !hydrated.hasEncryptionKeyMaterial ||
          hydrated.encryptionScheme !=
              kMediaAttachmentEncryptionSchemeBlobAesGcmV1 ||
          !DirectPrivateMediaPathGuard.identifiersAreSafe(
            contactPeerId: contactPeerId,
            messageId: messageId,
            attachmentId: attachmentId,
          ) ||
          MediaFilePathConvention.extensionFromMime(mime).isEmpty) {
        continue;
      }
      final expectedCanonical =
          MediaFilePathConvention.relativePathForAttachment(
            contactPeerId: contactPeerId,
            blobId: attachmentId,
            mime: mime,
          );
      if (localPath != expectedCanonical) continue;
      candidates.add(
        DirectPrivateCommittedPendingCleanupCandidate(
          messageId: messageId,
          attachmentId: attachmentId,
          mime: mime,
          expectedPendingLocalPath:
              MediaFilePathConvention.relativePathForPendingUpload(
                messageId: messageId,
                attachmentId: attachmentId,
                mime: mime,
              ),
        ),
      );
    }
    return candidates;
  }

  @override
  Future<List<DirectPrivateMediaCleanupAttachment>>
  loadDirectPrivateMediaCleanupAttachments(String messageId) async {
    final rows = await dbLoadMediaForMessage(
      messageId,
      MediaOwnerLane.direct.dbValue,
    );
    return rows
        .where(
          (row) =>
              row['message_id'] == messageId &&
              row['owner_lane'] == MediaOwnerLane.direct.dbValue,
        )
        .map(
          (row) => DirectPrivateMediaCleanupAttachment(
            id: row['id'] as String,
            messageId: row['message_id'] as String,
            mime: row['mime'] as String,
            size: (row['size'] as num?)?.toInt() ?? 0,
            downloadStatus: row['download_status'] as String?,
            localPath: row['local_path'] as String?,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<int> deleteDirectPrivateMediaAttachmentWithinLock({
    required String messageId,
    required String attachmentId,
  }) => lifecycleLock.synchronized(attachmentId, () {
    final delete = _requireCasClosure(
      dbDeleteDirectPrivateMediaAttachmentExact,
      'deleteDirectPrivateMediaAttachmentWithinLock',
    );
    return delete(messageId: messageId, attachmentId: attachmentId);
  });

  @override
  Future<bool> beginGroupPrivateMediaDownloadWithinLock(
    String id, {
    required String groupId,
    required String messageId,
    required int nowMs,
  }) => lifecycleLock.synchronized(id, () async {
    final begin = _requireCasClosure(
      dbBeginGroupPrivateMediaDownloadIfEligible,
      'beginGroupPrivateMediaDownloadWithinLock',
    );
    return await begin(
          groupId: groupId,
          messageId: messageId,
          attachmentId: id,
          nowMs: nowMs,
        ) ==
        1;
  });

  @override
  Future<bool> qualifyGroupPrivateMediaLocalReadyWithinLock(
    String id, {
    required String groupId,
    required String messageId,
    required String expectedLocalPath,
    required int nowMs,
  }) => lifecycleLock.synchronized(id, () async {
    final qualify = _requireCasClosure(
      dbQualifyGroupPrivateMediaLocalReadyIfEligible,
      'qualifyGroupPrivateMediaLocalReadyWithinLock',
    );
    return await qualify(
          groupId: groupId,
          messageId: messageId,
          attachmentId: id,
          expectedLocalPath: expectedLocalPath,
          nowMs: nowMs,
        ) ==
        1;
  });

  @override
  Future<bool> qualifyGroupPrivateMediaDownloadClaimWithinLock(
    String id, {
    required String groupId,
    required String messageId,
    required int nowMs,
  }) => lifecycleLock.synchronized(id, () async {
    final qualify = _requireCasClosure(
      dbQualifyGroupPrivateMediaDownloadClaimIfEligible,
      'qualifyGroupPrivateMediaDownloadClaimWithinLock',
    );
    return await qualify(
          groupId: groupId,
          messageId: messageId,
          attachmentId: id,
          nowMs: nowMs,
        ) ==
        1;
  });

  @override
  Future<bool> recordGroupPrivateMediaDownloadFailure(
    String id, {
    required String groupId,
    required String messageId,
    required int nowMs,
    required bool incrementRetryCount,
    required String failureStatus,
    required String expectedDownloadStatus,
    String? expectedLocalPath,
    required bool clearLocalPath,
  }) {
    return lifecycleLock.synchronized(
      id,
      () => recordGroupPrivateMediaDownloadFailureWithinLock(
        id,
        groupId: groupId,
        messageId: messageId,
        nowMs: nowMs,
        incrementRetryCount: incrementRetryCount,
        failureStatus: failureStatus,
        expectedDownloadStatus: expectedDownloadStatus,
        expectedLocalPath: expectedLocalPath,
        clearLocalPath: clearLocalPath,
      ),
    );
  }

  @override
  Future<bool> recordGroupPrivateMediaDownloadFailureWithinLock(
    String id, {
    required String groupId,
    required String messageId,
    required int nowMs,
    required bool incrementRetryCount,
    required String failureStatus,
    required String expectedDownloadStatus,
    String? expectedLocalPath,
    required bool clearLocalPath,
  }) => lifecycleLock.synchronized(id, () async {
    final record = _requireCasClosure(
      dbRecordGroupPrivateMediaDownloadFailureIfEligible,
      'recordGroupPrivateMediaDownloadFailureWithinLock',
    );
    return await record(
          groupId: groupId,
          messageId: messageId,
          attachmentId: id,
          nowMs: nowMs,
          incrementRetryCount: incrementRetryCount,
          failureStatus: failureStatus,
          expectedDownloadStatus: expectedDownloadStatus,
          expectedLocalPath: expectedLocalPath,
          clearLocalPath: clearLocalPath,
        ) ==
        1;
  });

  @override
  Future<bool> commitGroupPrivateMediaDownloadLocalPathWithinLock(
    String id, {
    required String groupId,
    required String messageId,
    required String localPath,
    required int nowMs,
  }) => lifecycleLock.synchronized(id, () async {
    final commit = _requireCasClosure(
      dbCommitGroupPrivateMediaDownloadIfEligible,
      'commitGroupPrivateMediaDownloadLocalPathWithinLock',
    );
    final committed = await commit(
      groupId: groupId,
      messageId: messageId,
      attachmentId: id,
      localPath: localPath,
      nowMs: nowMs,
    );
    return committed == 1;
  });

  @override
  Future<List<GroupPrivateMediaLifecycleAttachmentMetadata>>
  loadGroupPrivateMediaLifecycleAttachmentMetadata(String messageId) async {
    final rows = await dbLoadMediaForMessage(
      messageId,
      MediaOwnerLane.group.dbValue,
    );
    return rows
        .where(
          (row) =>
              row['message_id'] == messageId &&
              row['owner_lane'] == MediaOwnerLane.group.dbValue,
        )
        .map(
          (row) => GroupPrivateMediaLifecycleAttachmentMetadata(
            id: row['id'] as String,
            messageId: row['message_id'] as String,
            mime: row['mime'] as String,
            size: (row['size'] as num).toInt(),
            downloadStatus: row['download_status'] as String,
            localPath: row['local_path'] as String?,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<bool> deleteGroupPrivateMediaEncryptionKeyWithinLock({
    required String messageId,
    required String attachmentId,
  }) => lifecycleLock.synchronized(attachmentId, () async {
    final canCleanup = _requireCasClosure(
      dbCanCleanupGroupPrivateMediaAttachmentExact,
      'deleteGroupPrivateMediaEncryptionKeyWithinLock',
    );
    if (!await canCleanup(messageId: messageId, attachmentId: attachmentId)) {
      return false;
    }
    final store = secureKeyStore;
    if (store == null) {
      throw StateError(
        'group private-media cleanup requires secure key storage',
      );
    }
    await store.delete(mediaAttachmentEncryptionKeyStoreName(attachmentId));
    return true;
  });

  @override
  Future<int> deleteGroupPrivateMediaAttachmentWithinLock({
    required String messageId,
    required String attachmentId,
  }) => lifecycleLock.synchronized(attachmentId, () {
    final delete = _requireCasClosure(
      dbDeleteGroupPrivateMediaAttachmentExact,
      'deleteGroupPrivateMediaAttachmentWithinLock',
    );
    return delete(messageId: messageId, attachmentId: attachmentId);
  });

  @override
  Future<bool> saveGroupAttachmentGuarded(
    MediaAttachment attachment, {
    required String groupId,
  }) async {
    final guarded = _requireCasClosure(
      dbSaveGroupMediaAttachmentGuarded,
      'saveGroupAttachmentGuarded',
    );
    if (attachment.ownerLane != null &&
        attachment.ownerLane != MediaOwnerLane.group) {
      throw MediaAttachmentOwnerViolation(
        'guarded group save received a row stamped '
        '${attachment.ownerLane!.dbValue}',
      );
    }
    final stamped = attachment.copyWith(ownerLane: MediaOwnerLane.group);
    return lifecycleLock.synchronized(stamped.id, () async {
      // Secure-key write + guarded row persistence form one compensated saga.
      // A refused or throwing guard restores the exact prior key value (or
      // removes a newly introduced key) while this attachment lock is held.
      final saved = await _withCompensatedEncryptionKeyWrite<bool>(
        stamped,
        (row) => guarded(row, groupId: groupId),
        committed: (saved) => saved,
      );
      if (saved) {
        _emitAuthorizationChange(
          owner: MediaOwnerLane.group,
          scopeId: groupId,
          messageId: stamped.messageId,
          attachmentId: stamped.id,
          kind: MediaAttachmentAuthorizationMutation.saved,
        );
      }
      return saved;
    });
  }

  /// Commits one exact group upload retry without ever persisting its raw
  /// encryption key in SQL. The secure-key write and the DB CAS form a
  /// compensated saga under the attachment lifecycle lock: a refused/throwing
  /// CAS restores the previous secure value (or removes the newly staged one).
  Future<bool> completeGroupUploadRetrySecurely({
    required Map<String, Object?> expectedParent,
    required MediaAttachment expectedAttachment,
    required MediaAttachment completedAttachment,
  }) async {
    final complete = _requireCasClosure(
      dbCompleteGroupUploadRetryExact,
      'dbCompleteGroupUploadRetryExact',
    );
    if (expectedAttachment.id != completedAttachment.id ||
        expectedAttachment.messageId != completedAttachment.messageId ||
        expectedAttachment.ownerLane != MediaOwnerLane.group ||
        completedAttachment.ownerLane != MediaOwnerLane.group ||
        expectedAttachment.downloadStatus != 'upload_pending' ||
        completedAttachment.downloadStatus != 'done' ||
        isSecureStoreReference(completedAttachment.encryptionKeyBase64 ?? '')) {
      return false;
    }

    return lifecycleLock.synchronized(completedAttachment.id, () async {
      final committed = await _withCompensatedEncryptionKeyWrite<bool>(
        completedAttachment,
        (completedRow) => complete(
          expectedParent: expectedParent,
          expectedAttachment: expectedAttachment.toMap(),
          completedAttachment: completedRow,
        ),
        committed: (result) => result,
      );
      if (committed) {
        _emitAuthorizationChange(
          owner: MediaOwnerLane.group,
          messageId: completedAttachment.messageId,
          attachmentId: completedAttachment.id,
          kind: MediaAttachmentAuthorizationMutation.saved,
        );
      }
      return committed;
    });
  }

  @override
  Future<int> claimMediaEvicted(
    String id, {
    required MediaOwnerLane owner,
    required String expectedLocalPath,
  }) => lifecycleLock.synchronized(id, () async {
    final claim = _requireCasClosure(dbClaimMediaEvicted, 'claimMediaEvicted');
    final previous = await dbLoadMediaById(id);
    final count = await claim(
      id,
      ownerLane: owner.dbValue,
      expectedLocalPath: expectedLocalPath,
    );
    if (count > 0 && previous != null) {
      _emitAuthorizationChangeForRow(
        previous,
        MediaAttachmentAuthorizationMutation.evicted,
      );
    }
    return count;
  });

  @override
  Future<int> finalizeMediaEvictedPathCleared(
    String id, {
    required MediaOwnerLane owner,
  }) => lifecycleLock.synchronized(id, () async {
    final finalize = _requireCasClosure(
      dbFinalizeMediaEvictedPathCleared,
      'finalizeMediaEvictedPathCleared',
    );
    final previous = await dbLoadMediaById(id);
    final count = await finalize(id, ownerLane: owner.dbValue);
    if (count > 0 && previous != null) {
      _emitAuthorizationChangeForRow(
        previous,
        MediaAttachmentAuthorizationMutation.evictionFinalized,
      );
    }
    return count;
  });

  @override
  Future<void> saveAttachment(
    MediaAttachment attachment, {
    required MediaOwnerLane owner,
  }) => lifecycleLock.synchronized(attachment.id, () async {
    var attachmentForPersistence = attachment;
    if (dbClassifyOutgoingDirectPrivateMediaCompletion != null &&
        owner == MediaOwnerLane.direct &&
        attachment.downloadStatus == 'done' &&
        attachment.localPath != null &&
        attachment.localPath!.isNotEmpty &&
        !mediaLocalPathIsTransient(attachment.localPath) &&
        attachment.contentHash != null &&
        attachment.contentHash!.isNotEmpty &&
        attachment.encryptionKeyBase64 != null &&
        attachment.encryptionKeyBase64!.isNotEmpty &&
        attachment.encryptionNonce != null &&
        attachment.encryptionNonce!.isNotEmpty &&
        attachment.encryptionScheme != null &&
        attachment.encryptionScheme!.isNotEmpty &&
        (attachment.ownerLane == null ||
            attachment.ownerLane == MediaOwnerLane.direct)) {
      final expectedPendingLocalPath =
          MediaFilePathConvention.relativePathForPendingUpload(
            messageId: attachment.messageId,
            attachmentId: attachment.id,
            mime: attachment.mime,
          );
      final result = await outgoingDirectPrivateMutationCoordinator
          .commitCompletion(
            attachment: attachment.copyWith(ownerLane: MediaOwnerLane.direct),
            expectedPendingLocalPath: expectedPendingLocalPath,
          );
      if (result.appliesToPrivateParent) {
        // Private completion refusal/defer/commit is final. In particular, a
        // late fallback after terminal cleanup must remain a silent no-op and
        // can never fall through to an INSERT-capable generic save.
        return;
      }
    }
    if (owner == MediaOwnerLane.direct) {
      final existing = await dbLoadMediaById(attachment.id);
      if (existing != null) {
        if (existing['owner_lane'] != owner.dbValue ||
            existing['message_id'] != attachment.messageId) {
          throw MediaAttachmentOwnerViolation(
            'save would re-parent attachment ${attachment.id} from '
            '(${existing['owner_lane']}, ${existing['message_id']}) to '
            '(${owner.dbValue}, ${attachment.messageId})',
          );
        }
        final loadBlobCustody = dbLoadDirectMediaBlobCustodyForAttachment;
        if (loadBlobCustody != null) {
          final blobCustody = await loadBlobCustody(
            attachmentId: attachment.id,
          );
          if (blobCustody != null &&
              blobCustody.messageId == attachment.messageId &&
              blobCustody.direction ==
                  DirectMediaBlobCustodyDirection.outgoing &&
              blobCustody.state ==
                  DirectMediaBlobCustodyState.outgoingPrepared) {
            // A v111 generation already owns the exact ciphertext identity
            // and its pending-upload path. Only the typed blob coordinator may
            // advance it; the legacy upload_pending -> done exception below is
            // valid only when no active v111 generation exists. This check is
            // inside the shared lifecycle lock and precedes every secure-key
            // write, so a generic completion cannot rotate key/nonce/hash or
            // replace the winner's path between the DB check and persistence.
            return;
          }
        }
        if (shouldPreserveImmutableDirectMediaCustodyAttachmentProjection(
          existing: existing,
          candidate: attachment.toMap(),
        )) {
          attachmentForPersistence = _pinImmutableDirectMediaProjection(
            incoming: attachment,
            existing: existing,
          );
        }
      }
      final genericSaveGuard = dbCanApplyGenericMediaAttachmentSave;
      if (genericSaveGuard != null &&
          !await genericSaveGuard(
            _toStorageReferenceRowWithoutKeyWrite(
              attachmentForPersistence.copyWith(
                ownerLane: MediaOwnerLane.direct,
              ),
            ),
          )) {
        // Active v108 custody and exact terminal/deletion authority own both
        // present and user-removed attachment rows. This check must precede
        // _toStorageRow so a delayed generic save cannot transiently recreate
        // a row or overwrite the stable secure-store key. Settled rows instead
        // keep their immutable descriptor/crypto projection pinned above while
        // allowing local lifecycle repair.
        return;
      }
      if (existing != null) {
        final result = await _applyOutgoingDirectPrivateNonCompletionWithinLock(
          attachment.copyWith(ownerLane: MediaOwnerLane.direct),
          missingParentIsOrdinary: true,
        );
        if (result !=
            OutgoingDirectPrivateNonCompletionMutationOutcome
                .notPrivateParent) {
          if (result ==
              OutgoingDirectPrivateNonCompletionMutationOutcome.applied) {
            _emitAuthorizationChange(
              owner: owner,
              messageId: attachment.messageId,
              attachmentId: attachment.id,
              kind: MediaAttachmentAuthorizationMutation.saved,
            );
          }
          return;
        }
      } else if (_isOutgoingDirectPrivatePendingPreparationCandidate(
        attachment,
      )) {
        final result = await _prepareOutgoingDirectPrivatePendingWithinLock(
          <MediaAttachment>[
            attachment.copyWith(ownerLane: MediaOwnerLane.direct),
          ],
        );
        if (result !=
            OutgoingDirectPrivatePendingPreparationOutcome.notPrivateParent) {
          if (result ==
              OutgoingDirectPrivatePendingPreparationOutcome.refused) {
            throw OutgoingDirectPrivatePendingPreparationRefused(result);
          }
          return;
        }
      }
    }
    emitFlowEvent(
      layer: 'FL',
      event: 'MEDIA_REPO_SAVE_START',
      details: {
        'id': attachment.id.length > 8
            ? attachment.id.substring(0, 8)
            : attachment.id,
        'ownerLane': owner.dbValue,
      },
    );

    String? keyNameForCompensation;
    var keyExistedBefore = false;
    String? previousKeyValue;
    var keyWriteMayHaveMutated = false;
    var rowPersisted = false;
    try {
      // A model stamped with a DIFFERENT lane than the caller's typed owner
      // is a caller bug — fail closed before any side effect.
      if (attachment.ownerLane != null && attachment.ownerLane != owner) {
        throw MediaAttachmentOwnerViolation(
          'attachment ${attachment.id} is stamped ${attachment.ownerLane!.dbValue} '
          'but the caller passed ${owner.dbValue}',
        );
      }
      final stamped = attachmentForPersistence.copyWith(ownerLane: owner);

      // Immutable-identity validation BEFORE _toStorageRow or any
      // secure-store side effect (TC-228-04K): a rejected cross-owner or
      // cross-parent save must leave the existing row, secure-store
      // reference/value and decryptability unchanged.
      final existingRow = await dbLoadMediaById(stamped.id);
      if (existingRow != null) {
        final existingOwner = existingRow['owner_lane'] as String?;
        final existingMessageId = existingRow['message_id'] as String?;
        if (existingOwner != owner.dbValue ||
            existingMessageId != stamped.messageId) {
          throw MediaAttachmentOwnerViolation(
            'save would re-parent attachment ${stamped.id} from '
            '($existingOwner, $existingMessageId) to '
            '(${owner.dbValue}, ${stamped.messageId})',
          );
        }
      }

      final rawKey = stamped.encryptionKeyBase64;
      final store = secureKeyStore;
      if (store != null &&
          rawKey != null &&
          rawKey.isNotEmpty &&
          !isSecureStoreReference(rawKey)) {
        keyNameForCompensation = mediaAttachmentEncryptionKeyStoreName(
          stamped.id,
        );
        keyExistedBefore = await store.containsKey(keyNameForCompensation);
        if (keyExistedBefore) {
          previousKeyValue = await store.read(keyNameForCompensation);
          if (previousKeyValue == null) {
            throw StateError(
              'secure media key disappeared before attachment save',
            );
          }
        }
      }

      keyWriteMayHaveMutated = keyNameForCompensation != null;
      final storageRow = await _toStorageRow(stamped);
      await dbSaveMediaAttachmentPreservingLocalState(storageRow);
      rowPersisted = true;
      _emitAuthorizationChange(
        owner: owner,
        messageId: stamped.messageId,
        attachmentId: stamped.id,
        kind: MediaAttachmentAuthorizationMutation.saved,
      );

      emitFlowEvent(
        layer: 'FL',
        event: 'MEDIA_REPO_SAVE_SUCCESS',
        details: {
          'id': attachment.id.length > 8
              ? attachment.id.substring(0, 8)
              : attachment.id,
        },
      );
    } catch (e) {
      final keyName = keyNameForCompensation;
      final store = secureKeyStore;
      if (!rowPersisted &&
          keyWriteMayHaveMutated &&
          keyName != null &&
          store != null) {
        try {
          if (keyExistedBefore) {
            await store.write(keyName, previousKeyValue!);
          } else if (!keyExistedBefore) {
            await store.delete(keyName);
          }
        } catch (compensationError) {
          emitFlowEvent(
            layer: 'FL',
            event: 'MEDIA_REPO_SAVE_COMPENSATION_FAILED',
            details: {'error': compensationError.toString()},
          );
          throw StateError(
            'attachment save failed and secure-key compensation failed: '
            '$e; compensation: $compensationError',
          );
        }
      }
      if (e is GenericMediaAttachmentCustodySaveRefused) {
        emitFlowEvent(
          layer: 'FL',
          event: 'MEDIA_REPO_SAVE_CUSTODY_REFUSED',
          details: {
            'id': attachment.id.length > 8
                ? attachment.id.substring(0, 8)
                : attachment.id,
          },
        );
        return;
      }
      emitFlowEvent(
        layer: 'FL',
        event: 'MEDIA_REPO_SAVE_ERROR',
        details: {'error': e.toString()},
      );
      rethrow;
    }
  });

  @override
  Future<OutgoingOrdinaryMutationResult> stageOutgoingOrdinaryAttemptWithMedia({
    required OutgoingTransportMutationRepository messageMutationRepository,
    required ConversationMessage? expected,
    required ConversationMessage staged,
    required List<MediaAttachment> attachments,
    required OutgoingOrdinaryAttemptKind kind,
  }) async {
    final stage = dbStageOutgoingOrdinaryAttemptWithMedia;
    final publish = publishOutgoingOrdinaryMutation;
    if (stage == null || publish == null || attachments.isEmpty) {
      return const OutgoingOrdinaryMutationResult(
        outcome: OutgoingOrdinaryMutationOutcome.refused,
        message: null,
      );
    }
    if (attachments.any(
      (attachment) =>
          attachment.id.isEmpty ||
          attachment.messageId != staged.id ||
          (attachment.ownerLane != null &&
              attachment.ownerLane != MediaOwnerLane.direct),
    )) {
      return const OutgoingOrdinaryMutationResult(
        outcome: OutgoingOrdinaryMutationOutcome.refused,
        message: null,
      );
    }

    final outcome = await lifecycleLock.synchronizedAll(() async {
      final stamped = attachments
          .map(
            (attachment) =>
                attachment.copyWith(ownerLane: MediaOwnerLane.direct),
          )
          .toList(growable: false);
      final snapshots = <_MediaEncryptionKeyWriteSnapshot>[];
      var restoreAttempted = false;
      Future<void> restoreSnapshots() async {
        if (restoreAttempted) return;
        restoreAttempted = true;
        Object? firstError;
        for (final snapshot in snapshots.reversed) {
          try {
            await snapshot.restore();
          } catch (error) {
            firstError ??= error;
          }
        }
        if (firstError != null) {
          throw StateError(
            'ordinary media attempt secure-key compensation failed: '
            '$firstError',
          );
        }
      }

      try {
        for (final attachment in stamped) {
          snapshots.add(await _captureEncryptionKeyWriteSnapshot(attachment));
        }
        final rows = <Map<String, Object?>>[];
        for (final attachment in stamped) {
          rows.add(await _toStorageRow(attachment));
        }
        final result = await stage(
          expectedRow: expected?.toMap(),
          stagedRow: staged.toMap(),
          attachmentRows: rows,
          kind: kind,
        );
        if (result == OutgoingOrdinaryMutationOutcome.idempotent) {
          // Storage-reference rows deliberately keep a stable key name, so
          // SQL cannot distinguish a repeated raw key from a crossed one. An
          // idempotent parent/projection belongs to the already-durable
          // envelope: retain its existing key while leaving a genuinely
          // missing key repaired by this retry.
          for (final snapshot in snapshots.reversed) {
            if (snapshot.overwroteDifferentExistingValue) {
              await snapshot.restore();
            }
          }
        }
        if (!result.authorizesTransport) {
          await restoreSnapshots();
        }
        return result;
      } catch (_) {
        await restoreSnapshots();
        rethrow;
      }
    });

    final committedMedia = await getAttachmentsForMessage(
      staged.id,
      owner: MediaOwnerLane.direct,
    );
    return publish(
      messageId: staged.id,
      outcome: outcome,
      committedMedia: committedMedia,
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
    final stage = dbStageOutgoingDirectMediaInboxCustody;
    final canonicalWireBinding = _canonicalDirectMediaBlobWireBinding(
      attachments,
    );
    if (!supportsDirectMediaInboxCustody ||
        stage == null ||
        canonicalWireBinding == null ||
        canonicalWireBinding.manifestHash != wireMediaBlobManifestHash ||
        canonicalWireBinding.expiresAtMs != wireMediaBlobExpiresAtMs ||
        attachments.isEmpty ||
        staged.id.isEmpty ||
        staged.contactPeerId != recipientPeerId ||
        staged.wireEnvelope != wireEnvelope ||
        attachments.any(
          (attachment) =>
              attachment.id.isEmpty ||
              attachment.messageId != staged.id ||
              attachment.encryptionKeyBase64 == null ||
              attachment.encryptionKeyBase64!.isEmpty ||
              isSecureStoreReference(attachment.encryptionKeyBase64) ||
              (attachment.ownerLane != null &&
                  attachment.ownerLane != MediaOwnerLane.direct),
        ) ||
        attachments.map((attachment) => attachment.id).toSet().length !=
            attachments.length) {
      return const OutgoingDirectMediaCustodyStageResult(
        outcome: OutgoingOrdinaryMutationOutcome.refused,
        message: null,
        custody: null,
      );
    }

    final stamped = attachments
        .map(
          (attachment) => attachment.copyWith(ownerLane: MediaOwnerLane.direct),
        )
        .toList(growable: false);
    final dbResult = await lifecycleLock.synchronizedAll(() async {
      final snapshots = <_MediaEncryptionKeyWriteSnapshot>[];
      var restoreAttempted = false;
      Future<void> restoreSnapshots() async {
        if (restoreAttempted) return;
        restoreAttempted = true;
        Object? firstError;
        for (final snapshot in snapshots.reversed) {
          try {
            await snapshot.restore();
          } catch (error) {
            firstError ??= error;
          }
        }
        if (firstError != null) {
          throw StateError(
            'direct media custody secure-key compensation failed: '
            '$firstError',
          );
        }
      }

      try {
        for (final attachment in stamped) {
          snapshots.add(await _captureEncryptionKeyWriteSnapshot(attachment));
        }
        final rows = <Map<String, Object?>>[];
        for (final attachment in stamped) {
          rows.add(await _toStorageRow(attachment));
        }
        final result = await stage(
          expectedRow: expected?.toMap(),
          stagedRow: staged.toMap(),
          attachmentRows: rows,
          kind: kind,
          recipientPeerId: recipientPeerId,
          wireEnvelope: wireEnvelope,
          wireMediaBlobManifestHash: wireMediaBlobManifestHash,
          wireMediaBlobExpiresAtMs: wireMediaBlobExpiresAtMs,
        );
        if (result.outcome == OutgoingOrdinaryMutationOutcome.idempotent) {
          if (result.hasExactMutableProjection) {
            // A competing finalizer may have written a different raw key
            // under the same stable secure-store reference. Restore only
            // values that this losing attempt overwrote; a genuinely missing
            // key may still be repaired while the exact durable attachment
            // projection proves which blob the reference belongs to.
            for (final snapshot in snapshots.reversed) {
              if (snapshot.overwroteDifferentExistingValue) {
                await snapshot.restore();
              }
            }
          } else {
            // The immutable v108 row still authorizes replay after settlement
            // or physical deletion, but a missing/mutated attachment
            // projection cannot authorize installing this loser's raw key.
            await restoreSnapshots();
          }
        }
        final exactAuthority =
            result.outcome.authorizesTransport &&
            result.custodyRow != null &&
            (result.hasExactMutableProjection
                ? result.messageRow != null && result.attachmentRows.isNotEmpty
                : result.outcome == OutgoingOrdinaryMutationOutcome.idempotent);
        if (!exactAuthority) await restoreSnapshots();
        return result;
      } catch (_) {
        await restoreSnapshots();
        rethrow;
      }
    });

    if (!dbResult.outcome.authorizesTransport ||
        dbResult.custodyRow == null ||
        (dbResult.hasExactMutableProjection &&
            (dbResult.messageRow == null || dbResult.attachmentRows.isEmpty)) ||
        (!dbResult.hasExactMutableProjection &&
            dbResult.outcome != OutgoingOrdinaryMutationOutcome.idempotent)) {
      return OutgoingDirectMediaCustodyStageResult(
        outcome: dbResult.outcome,
        message: null,
        custody: null,
      );
    }

    var committedMedia = const <MediaAttachment>[];
    if (dbResult.hasExactMutableProjection) {
      try {
        committedMedia = await _attachmentsFromRows(dbResult.attachmentRows);
      } catch (error) {
        // Hydration is post-commit publication work. Preserve the exact DB
        // projection (including stable secure-store references) if
        // secure-store observation itself fails after custody committed.
        committedMedia = dbResult.attachmentRows
            .map(MediaAttachment.fromMap)
            .toList(growable: false);
        emitFlowEvent(
          layer: 'FL',
          event: 'DIRECT_MEDIA_CUSTODY_HYDRATION_ERROR',
          details: {'errorType': error.runtimeType.toString()},
        );
      }
    }
    final custody = DirectInboxCustodyOutboxEntry.fromMap(dbResult.custodyRow!);
    ConversationMessage? committedMessage;
    if (dbResult.hasExactMutableProjection) {
      committedMessage = ConversationMessage.fromMap(
        dbResult.messageRow!,
      ).copyWith(media: committedMedia);
    } else {
      final currentRow = dbResult.messageRow;
      if (currentRow != null &&
          currentRow['id'] == staged.id &&
          currentRow['contact_peer_id'] == recipientPeerId &&
          currentRow['sender_peer_id'] == staged.senderPeerId) {
        try {
          committedMessage = ConversationMessage.fromMap(
            currentRow,
          ).copyWith(media: const <MediaAttachment>[]);
        } catch (_) {
          // Mutable projection hydration cannot revoke immutable custody.
        }
      }
    }

    // The transaction is already committed. Cache/stream publication is best
    // effort and can neither compensate keys nor revoke exact custody.
    if (dbResult.hasExactMutableProjection) {
      try {
        await publishOutgoingOrdinaryMutation!(
          messageId: committedMessage!.id,
          outcome: dbResult.outcome,
          committedMedia: committedMedia,
        );
        for (final attachment in committedMedia) {
          _emitAuthorizationChange(
            owner: MediaOwnerLane.direct,
            messageId: committedMessage.id,
            attachmentId: attachment.id,
            kind: MediaAttachmentAuthorizationMutation.saved,
          );
        }
      } catch (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'DIRECT_MEDIA_CUSTODY_PUBLICATION_ERROR',
          details: {'errorType': error.runtimeType.toString()},
        );
      }
    }
    return OutgoingDirectMediaCustodyStageResult(
      outcome: dbResult.outcome,
      message: committedMessage,
      custody: custody,
    );
  }

  @override
  Future<UploadRetryProjectionResult> projectDirectMediaCustodyUploadFailure({
    required ConversationMessage expectedParent,
    required List<MediaAttachment> expectedAttachments,
    required String failedAttachmentId,
    required UploadMediaFailed failure,
  }) async {
    final project = dbProjectOutgoingDirectMediaCustodyUploadFailure;
    final attachmentIds = expectedAttachments
        .map((attachment) => attachment.id)
        .toSet();
    if (project == null ||
        expectedParent.directMediaCustodyIntentId == null ||
        expectedParent.id.isEmpty ||
        expectedParent.contactPeerId.isEmpty ||
        expectedAttachments.isEmpty ||
        attachmentIds.length != expectedAttachments.length ||
        !attachmentIds.contains(failedAttachmentId) ||
        expectedAttachments.any(
          (attachment) =>
              attachment.messageId != expectedParent.id ||
              attachment.ownerLane != MediaOwnerLane.direct,
        )) {
      return const UploadRetryProjectionResult.notApplied();
    }

    final expectedRows = expectedAttachments
        .map(_toStorageExpectationRow)
        .toList(growable: false);
    final result = await lifecycleLock.synchronizedAll(
      () => project(
        expectedParentRow: expectedParent.toMap(),
        expectedAttachmentRows: expectedRows,
        failedAttachmentId: failedAttachmentId,
        disposition: failure.disposition,
      ),
    );
    if (!result.applied) return result;

    _emitAuthorizationChange(
      owner: MediaOwnerLane.direct,
      messageId: expectedParent.id,
      attachmentId: failedAttachmentId,
      kind: MediaAttachmentAuthorizationMutation.downloadStatusChanged,
    );
    final publish = publishOutgoingOrdinaryMutation;
    if (publish != null) {
      try {
        await publish(
          messageId: expectedParent.id,
          outcome: OutgoingOrdinaryMutationOutcome.applied,
          committedMedia: await getAttachmentsForMessage(
            expectedParent.id,
            owner: MediaOwnerLane.direct,
          ),
        );
      } catch (error) {
        emitFlowEvent(
          layer: 'FL',
          event: 'DIRECT_MEDIA_CUSTODY_FAILURE_PUBLICATION_ERROR',
          details: {'errorType': error.runtimeType.toString()},
        );
      }
    }
    return result;
  }

  // Legacy saveAttachment callers have no parent-policy argument. Enter the
  // typed first-preparation seam only for its exact convention-owned shape;
  // the DB seam then remains the authority for ordinary/private parent policy.
  bool _isOutgoingDirectPrivatePendingPreparationCandidate(
    MediaAttachment attachment,
  ) {
    if (attachment.downloadStatus != kMediaDownloadStatusUploadPending ||
        attachment.messageId.isEmpty ||
        attachment.id.isEmpty ||
        attachment.mime.isEmpty ||
        attachment.size <= 0 ||
        attachment.localPath == null) {
      return false;
    }
    try {
      return attachment.localPath ==
          MediaFilePathConvention.relativePathForPendingUpload(
            messageId: attachment.messageId,
            attachmentId: attachment.id,
            mime: attachment.mime,
          );
    } catch (_) {
      return false;
    }
  }

  @override
  Future<OutgoingDirectPrivatePendingPreparationOutcome>
  prepareOutgoingDirectPrivatePendingAttachments(
    List<MediaAttachment> attachments,
  ) => lifecycleLock.synchronizedAll(
    () => _prepareOutgoingDirectPrivatePendingWithinLock(attachments),
  );

  Future<OutgoingDirectPrivatePendingPreparationOutcome>
  _prepareOutgoingDirectPrivatePendingWithinLock(
    List<MediaAttachment> attachments,
  ) async {
    if (attachments.isEmpty) {
      return OutgoingDirectPrivatePendingPreparationOutcome.refused;
    }
    final messageIds = attachments
        .map((attachment) => attachment.messageId)
        .toSet();
    final attachmentIds = attachments
        .map((attachment) => attachment.id)
        .toSet();
    if (messageIds.length != 1 ||
        messageIds.single.isEmpty ||
        attachmentIds.length != attachments.length ||
        attachmentIds.contains('') ||
        attachments.any(
          (attachment) =>
              attachment.ownerLane != null &&
              attachment.ownerLane != MediaOwnerLane.direct,
        )) {
      return OutgoingDirectPrivatePendingPreparationOutcome.refused;
    }
    final prepare = dbInsertOutgoingDirectPrivatePendingAttachmentsIfEligible;
    if (prepare == null) {
      return OutgoingDirectPrivatePendingPreparationOutcome.refused;
    }
    final result = await prepare(
      attachments
          .map(
            (attachment) => _toStorageReferenceRowWithoutKeyWrite(
              attachment.copyWith(ownerLane: MediaOwnerLane.direct),
            ),
          )
          .toList(growable: false),
    );
    if (result == OutgoingDirectPrivatePendingPreparationOutcome.inserted) {
      for (final attachment in attachments) {
        _emitAuthorizationChange(
          owner: MediaOwnerLane.direct,
          messageId: attachment.messageId,
          attachmentId: attachment.id,
          kind: MediaAttachmentAuthorizationMutation.saved,
        );
      }
    }
    return result;
  }

  @override
  Future<OutgoingDirectPrivateNonCompletionMutationOutcome>
  applyOutgoingDirectPrivateNonCompletionMutation(MediaAttachment attachment) =>
      lifecycleLock.synchronized(
        attachment.id,
        () => _applyOutgoingDirectPrivateNonCompletionWithinLock(
          attachment,
          missingParentIsOrdinary: false,
        ),
      );

  Future<OutgoingDirectPrivateNonCompletionMutationOutcome>
  _applyOutgoingDirectPrivateNonCompletionWithinLock(
    MediaAttachment attachment, {
    required bool missingParentIsOrdinary,
  }) async {
    if (attachment.ownerLane != null &&
        attachment.ownerLane != MediaOwnerLane.direct) {
      return OutgoingDirectPrivateNonCompletionMutationOutcome.refused;
    }
    final existing = await dbLoadMediaById(attachment.id);
    if (existing == null ||
        existing['owner_lane'] != MediaOwnerLane.direct.dbValue ||
        existing['message_id'] != attachment.messageId) {
      return OutgoingDirectPrivateNonCompletionMutationOutcome.refused;
    }
    final apply = dbApplyOutgoingDirectPrivateNonCompletionMutation;
    if (apply == null) {
      return OutgoingDirectPrivateNonCompletionMutationOutcome.refused;
    }
    return apply(
      _toStorageReferenceRowWithoutKeyWrite(
        attachment.copyWith(ownerLane: MediaOwnerLane.direct),
      ),
      missingParentIsOrdinary: missingParentIsOrdinary,
    );
  }

  @override
  Future<OutgoingDirectPrivateNonCompletionMutationOutcome>
  deleteOutgoingDirectPrivatePendingAttachmentsForMessage(
    String messageId, {
    required MediaFileManager mediaFileManager,
  }) => lifecycleLock.synchronizedAll(() async {
    final qualify = dbQualifyOutgoingDirectPrivatePendingAttachmentsDeletion;
    final delete = dbDeleteOutgoingDirectPrivatePendingAttachmentsIfEligible;
    if (qualify == null || delete == null) {
      return OutgoingDirectPrivateNonCompletionMutationOutcome.refused;
    }
    final previousRows = await dbLoadMediaForMessage(
      messageId,
      MediaOwnerLane.direct.dbValue,
    );
    if (directPrivateMediaTransferRegistry.isActiveForMessage(messageId) ||
        previousRows.any(
          (row) => directPrivateMediaTransferRegistry.isActive(
            row['id'] as String? ?? '',
          ),
        )) {
      return OutgoingDirectPrivateNonCompletionMutationOutcome
          .notAppliedActiveLease;
    }
    final qualification = await qualify(messageId);
    if (qualification !=
        OutgoingDirectPrivateNonCompletionMutationOutcome.applied) {
      return qualification;
    }
    final storedPaths = previousRows
        .map((row) => row['local_path'] as String?)
        .toList(growable: false);
    try {
      // Plaintext disappears first while every row/key still carries exact
      // authority. A failed unlink therefore cannot strand bytes after their
      // only durable identity has been removed.
      await mediaFileManager.deleteOwnedPendingUploadFilesForMessage(
        messageId: messageId,
        storedPaths: storedPaths,
      );
      for (final storedPath in storedPaths) {
        if (storedPath == null || storedPath.isEmpty) {
          return OutgoingDirectPrivateNonCompletionMutationOutcome.refused;
        }
        final resolved = await mediaFileManager.resolveStoredPath(storedPath);
        if (await FileSystemEntity.type(resolved, followLinks: false) !=
            FileSystemEntityType.notFound) {
          return OutgoingDirectPrivateNonCompletionMutationOutcome.refused;
        }
      }
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'OUTGOING_PRIVATE_PENDING_FILE_DELETE_REFUSED',
        details: {'error': error.runtimeType.toString()},
      );
      return OutgoingDirectPrivateNonCompletionMutationOutcome.refused;
    }
    final store = secureKeyStore;
    if (store == null) {
      return OutgoingDirectPrivateNonCompletionMutationOutcome.refused;
    }
    final keySnapshots = <_MediaEncryptionKeyDeletionSnapshot>[];
    Future<void> restoreKeys() async {
      for (final snapshot in keySnapshots.reversed) {
        await snapshot.restore();
      }
    }

    late final OutgoingDirectPrivateNonCompletionMutationOutcome result;
    try {
      for (final row in previousRows) {
        final attachmentId = row['id'] as String? ?? '';
        if (attachmentId.isEmpty) {
          await restoreKeys();
          return OutgoingDirectPrivateNonCompletionMutationOutcome.refused;
        }
        final keyName = mediaAttachmentEncryptionKeyStoreName(attachmentId);
        final existed = await store.containsKey(keyName);
        final value = existed ? await store.read(keyName) : null;
        if (existed && value == null) {
          await restoreKeys();
          return OutgoingDirectPrivateNonCompletionMutationOutcome.refused;
        }
        keySnapshots.add(
          _MediaEncryptionKeyDeletionSnapshot(
            store: store,
            keyName: keyName,
            existed: existed,
            previousValue: value,
          ),
        );
        if (existed) await store.delete(keyName);
      }
      result = await delete(messageId);
      if (result != OutgoingDirectPrivateNonCompletionMutationOutcome.applied) {
        await restoreKeys();
      }
    } catch (_) {
      await restoreKeys();
      rethrow;
    }
    if (result == OutgoingDirectPrivateNonCompletionMutationOutcome.applied) {
      for (final row in previousRows) {
        _emitAuthorizationChangeForRow(
          row,
          MediaAttachmentAuthorizationMutation.removed,
        );
      }
    }
    return result;
  });

  @override
  Future<int> rollbackNewMessageAttachments({
    required String messageId,
    required Set<String> attachmentIds,
    required MediaOwnerLane owner,
  }) => lifecycleLock.synchronizedAll(() async {
    final rows = await dbLoadMediaForMessage(messageId, owner.dbValue);
    final persistedIds = rows
        .map((row) => row['id'])
        .whereType<String>()
        .toSet();
    if (!attachmentIds.containsAll(persistedIds)) {
      throw StateError(
        'refusing new-message media rollback with unexpected attachment ids',
      );
    }

    final deleted = await dbDeleteMediaForMessage(messageId, owner.dbValue);
    final store = secureKeyStore;
    if (store != null) {
      final failures = <String>[];
      for (final attachmentId in persistedIds) {
        final keyName = mediaAttachmentEncryptionKeyStoreName(attachmentId);
        try {
          await store.delete(keyName);
        } catch (_) {
          try {
            await store.delete(keyName);
          } catch (error) {
            failures.add('$attachmentId: $error');
          }
        }
      }
      if (failures.isNotEmpty) {
        throw StateError(
          'new-message media rollback left secure-key residue: '
          '${failures.join('; ')}',
        );
      }
    }
    return deleted;
  });

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async {
    final rows = await dbLoadMediaForMessage(messageId, owner.dbValue);
    return _attachmentsFromRows(rows);
  }

  @override
  Future<MediaAttachment?> getAttachmentById(String id) async {
    final row = await dbLoadMediaById(id);
    if (row == null) return null;
    return MediaAttachment.fromMap(await _hydrateRow(row));
  }

  @override
  Future<Map<String, List<MediaAttachment>>> getAttachmentsForMessages(
    List<String> messageIds, {
    required MediaOwnerLane owner,
  }) async {
    if (messageIds.isEmpty) return {};

    final rows = await dbLoadMediaForMessages(messageIds, owner.dbValue);
    final Map<String, List<MediaAttachment>> result = {};
    for (final attachment in await _attachmentsFromRows(rows)) {
      result.putIfAbsent(attachment.messageId, () => []).add(attachment);
    }
    return result;
  }

  @override
  Future<Map<String, MediaPreviewDescriptor>> getMediaPreviewDescriptors(
    List<String> messageIds, {
    required MediaOwnerLane owner,
  }) async {
    if (messageIds.isEmpty) return {};

    final rows = await dbLoadMediaForMessages(messageIds, owner.dbValue);
    // Parse rows WITHOUT _hydrateRow: a preview label is derived purely from
    // media_type/mime/count and never needs the decryption key, so we skip the
    // per-attachment SecureKeyStore.read this path would otherwise pay once per
    // contact/group on every orbit load.
    final Map<String, List<MediaAttachment>> byMessage = {};
    for (final row in rows) {
      final attachment = MediaAttachment.fromMap(row);
      byMessage.putIfAbsent(attachment.messageId, () => []).add(attachment);
    }
    final Map<String, MediaPreviewDescriptor> result = {};
    byMessage.forEach((messageId, attachments) {
      final descriptor = MediaPreviewDescriptor.fromAttachments(attachments);
      if (descriptor != null) result[messageId] = descriptor;
    });
    return result;
  }

  @override
  Future<void> updateLocalPath(
    String id,
    String localPath,
  ) => lifecycleLock.synchronized(id, () async {
    final previous = await dbLoadMediaById(id);
    final applyPrivate = dbApplyOutgoingDirectPrivateNonCompletionMutation;
    if (previous != null &&
        previous['owner_lane'] == MediaOwnerLane.direct.dbValue &&
        applyPrivate != null) {
      final result = await applyPrivate(<String, Object?>{
        ...previous,
        'local_path': localPath,
        'download_status': 'done',
      }, missingParentIsOrdinary: true);
      if (result !=
          OutgoingDirectPrivateNonCompletionMutationOutcome.notPrivateParent) {
        return;
      }
    }
    await dbUpdateMediaLocalPath(id, localPath, 'done');
    final updated = await dbLoadMediaById(id);
    if (updated != null &&
        (previous == null ||
            previous['local_path'] != updated['local_path'] ||
            previous['download_status'] != updated['download_status'])) {
      _emitAuthorizationChangeForRow(
        updated,
        MediaAttachmentAuthorizationMutation.localPathChanged,
      );
    }
  });

  @override
  Future<void> updateDownloadStatus(
    String id,
    String downloadStatus,
  ) => lifecycleLock.synchronized(id, () async {
    final previous = await dbLoadMediaById(id);
    final applyPrivate = dbApplyOutgoingDirectPrivateNonCompletionMutation;
    if (previous != null &&
        previous['owner_lane'] == MediaOwnerLane.direct.dbValue &&
        applyPrivate != null) {
      final result = await applyPrivate(<String, Object?>{
        ...previous,
        'download_status': downloadStatus,
      }, missingParentIsOrdinary: true);
      if (result !=
          OutgoingDirectPrivateNonCompletionMutationOutcome.notPrivateParent) {
        if (result ==
            OutgoingDirectPrivateNonCompletionMutationOutcome.applied) {
          final updated = await dbLoadMediaById(id);
          if (updated != null) {
            _emitAuthorizationChangeForRow(
              updated,
              MediaAttachmentAuthorizationMutation.downloadStatusChanged,
            );
          }
        }
        return;
      }
    }
    await dbUpdateMediaDownloadStatus(id, downloadStatus);
    final updated = await dbLoadMediaById(id);
    if (updated != null &&
        previous?['download_status'] != updated['download_status']) {
      _emitAuthorizationChangeForRow(
        updated,
        MediaAttachmentAuthorizationMutation.downloadStatusChanged,
      );
    }
  });

  @override
  Future<void> setBookmarked(String id, {required bool bookmarked}) =>
      lifecycleLock.synchronized(id, () async {
        await dbSetMediaBookmarked(id, bookmarked);
      });

  @override
  Future<bool> setDirectBookmarkedIfOrdinary({
    required String messageId,
    required String attachmentId,
    required bool bookmarked,
  }) => lifecycleLock.synchronized(attachmentId, () async {
    final guarded = dbSetDirectMediaBookmarkedIfOrdinary;
    if (guarded == null) return false;
    return guarded(
      messageId: messageId,
      attachmentId: attachmentId,
      bookmarked: bookmarked,
    );
  });

  @override
  Future<bool> setGroupBookmarkedIfOrdinary({
    required String groupId,
    required String messageId,
    required String attachmentId,
    required bool bookmarked,
  }) => lifecycleLock.synchronized(attachmentId, () async {
    final guarded = dbSetGroupMediaBookmarkedIfOrdinary;
    if (guarded == null) return false;
    return guarded(
      groupId: groupId,
      messageId: messageId,
      attachmentId: attachmentId,
      bookmarked: bookmarked,
    );
  });

  @override
  Future<MediaLibraryPage> getMediaLibraryPage({
    required MediaLibraryScope scope,
    MediaLibraryFilter filter = const MediaLibraryFilter(),
    int limit = 50,
    String? cursor,
  }) async {
    // Every argument-contract failure happens HERE, before any SQL.
    if (limit < 1 || limit > kMediaLibraryMaxPageSize) {
      throw ArgumentError.value(
        limit,
        'limit',
        'must be within 1..$kMediaLibraryMaxPageSize',
      );
    }
    _MediaLibraryCursor? after;
    if (cursor != null) {
      after = _MediaLibraryCursor.decode(cursor);
      if (after.scopeKind != scope.lane.dbValue ||
          after.scopeId != scope.id ||
          after.kind != filter.kind.name ||
          after.bookmarkedOnly != filter.bookmarkedOnly ||
          after.incomingOnly != filter.incomingOnly) {
        throw ArgumentError.value(
          cursor,
          'cursor',
          'cursor was minted for a different scope/filter signature',
        );
      }
    }

    final rows = await dbLoadMediaLibraryPage(
      scopeKind: scope.lane.dbValue,
      scopeId: scope.id,
      mediaTypes: filter.kind.mediaTypes,
      bookmarkedOnly: filter.bookmarkedOnly,
      incomingOnly: filter.incomingOnly,
      limit: limit,
      afterTimestamp: after?.timestamp,
      afterMessageId: after?.messageId,
      afterAttachmentId: after?.attachmentId,
    );

    final entries = <MediaLibraryEntry>[];
    for (final row in rows) {
      final attachmentMap = await _hydrateRow(
        mediaLibraryRowToAttachmentMap(row),
      );
      entries.add(
        MediaLibraryEntry(
          attachment: MediaAttachment.fromMap(attachmentMap),
          parentTimestamp: row['parent_timestamp'] as String,
          parentSenderPeerId: row['parent_sender_peer_id'] as String?,
        ),
      );
    }

    String? nextCursor;
    if (entries.length == limit) {
      final last = entries.last;
      nextCursor = _MediaLibraryCursor(
        scopeKind: scope.lane.dbValue,
        scopeId: scope.id,
        kind: filter.kind.name,
        bookmarkedOnly: filter.bookmarkedOnly,
        incomingOnly: filter.incomingOnly,
        timestamp: last.parentTimestamp,
        messageId: last.attachment.messageId,
        attachmentId: last.attachment.id,
      ).encode();
    }
    return MediaLibraryPage(entries: entries, nextCursor: nextCursor);
  }

  @override
  Future<MediaStoragePage> getMediaStoragePage({
    required MediaLibraryScope scope,
    MediaStorageKind kind = MediaStorageKind.all,
    int limit = kMediaLibraryMaxPageSize,
    String? cursor,
  }) async {
    final loadPage = _requireCasClosure(
      dbLoadMediaStoragePage,
      'getMediaStoragePage',
    );
    // Every argument-contract failure happens HERE, before any SQL.
    if (limit < 1 || limit > kMediaLibraryMaxPageSize) {
      throw ArgumentError.value(
        limit,
        'limit',
        'must be within 1..$kMediaLibraryMaxPageSize',
      );
    }
    _MediaStorageCursor? after;
    if (cursor != null) {
      after = _MediaStorageCursor.decode(cursor);
      if (after.scopeKind != scope.lane.dbValue ||
          after.scopeId != scope.id ||
          after.kind != kind.name) {
        throw ArgumentError.value(
          cursor,
          'cursor',
          'cursor was minted for a different scope/kind signature',
        );
      }
    }

    final rows = await loadPage(
      scopeKind: scope.lane.dbValue,
      scopeId: scope.id,
      mediaTypes: kind.mediaTypes,
      limit: limit,
      afterTimestamp: after?.timestamp,
      afterMessageId: after?.messageId,
      afterAttachmentId: after?.attachmentId,
    );

    final entries = <MediaStorageEntry>[];
    for (final row in rows) {
      final attachmentMap = await _hydrateRow(
        mediaLibraryRowToAttachmentMap(row),
      );
      entries.add(
        MediaStorageEntry(
          attachment: MediaAttachment.fromMap(attachmentMap),
          parentTimestamp: row['parent_timestamp'] as String,
        ),
      );
    }

    String? nextCursor;
    if (entries.length == limit) {
      final last = entries.last;
      nextCursor = _MediaStorageCursor(
        scopeKind: scope.lane.dbValue,
        scopeId: scope.id,
        kind: kind.name,
        timestamp: last.parentTimestamp,
        messageId: last.attachment.messageId,
        attachmentId: last.attachment.id,
      ).encode();
    }
    return MediaStoragePage(entries: entries, nextCursor: nextCursor);
  }

  @override
  Future<void> updatePlaybackPosition(String id, int positionMs) =>
      lifecycleLock.synchronized(id, () async {
        await dbUpdateMediaPlaybackPosition(id, positionMs);
      });

  @override
  Future<int> deleteAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) => lifecycleLock.synchronizedAll(() async {
    emitFlowEvent(
      layer: 'FL',
      event: 'MEDIA_REPO_DELETE_FOR_MESSAGE_START',
      details: {
        'messageId': messageId.length > 8
            ? messageId.substring(0, 8)
            : messageId,
        'ownerLane': owner.dbValue,
      },
    );

    try {
      final previousRows = await dbLoadMediaForMessage(
        messageId,
        owner.dbValue,
      );
      final count = await dbDeleteMediaForMessage(messageId, owner.dbValue);
      if (count > 0) {
        if (previousRows.isEmpty) {
          _emitAuthorizationChange(
            owner: owner,
            messageId: messageId,
            kind: MediaAttachmentAuthorizationMutation.removed,
          );
        } else {
          for (final row in previousRows) {
            _emitAuthorizationChangeForRow(
              row,
              MediaAttachmentAuthorizationMutation.removed,
            );
          }
        }
      }

      emitFlowEvent(
        layer: 'FL',
        event: 'MEDIA_REPO_DELETE_FOR_MESSAGE_SUCCESS',
        details: {'count': count},
      );

      return count;
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'MEDIA_REPO_DELETE_FOR_MESSAGE_ERROR',
        details: {'error': e.toString()},
      );
      rethrow;
    }
  });

  @override
  Future<int> deleteAttachmentsForContact(String contactPeerId) =>
      lifecycleLock.synchronizedAll(() async {
        emitFlowEvent(
          layer: 'FL',
          event: 'MEDIA_REPO_DELETE_FOR_CONTACT_START',
          details: {
            'contactPeerId': contactPeerId.length > 10
                ? contactPeerId.substring(0, 10)
                : contactPeerId,
          },
        );

        try {
          final count = await dbDeleteMediaForContact(contactPeerId);
          if (count > 0) {
            _emitAuthorizationChange(
              owner: MediaOwnerLane.direct,
              scopeId: contactPeerId,
              kind: MediaAttachmentAuthorizationMutation.removed,
            );
          }

          emitFlowEvent(
            layer: 'FL',
            event: 'MEDIA_REPO_DELETE_FOR_CONTACT_SUCCESS',
            details: {'count': count},
          );

          return count;
        } catch (e) {
          emitFlowEvent(
            layer: 'FL',
            event: 'MEDIA_REPO_DELETE_FOR_CONTACT_ERROR',
            details: {'error': e.toString()},
          );
          rethrow;
        }
      });

  @override
  Future<int> markUploadPendingAttachmentsFailedForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) => lifecycleLock.synchronizedAll(() async {
    emitFlowEvent(
      layer: 'FL',
      event: 'MEDIA_REPO_TERMINALIZE_UPLOADS_START',
      details: {
        'messageId': messageId.length > 8
            ? messageId.substring(0, 8)
            : messageId,
        'ownerLane': owner.dbValue,
      },
    );

    try {
      final count = await dbMarkUploadPendingAttachmentsFailedForMessage(
        messageId,
        owner.dbValue,
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'MEDIA_REPO_TERMINALIZE_UPLOADS_SUCCESS',
        details: {'count': count},
      );
      return count;
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'MEDIA_REPO_TERMINALIZE_UPLOADS_ERROR',
        details: {'error': e.toString()},
      );
      rethrow;
    }
  });

  @override
  Future<List<MediaAttachment>> getPendingDownloads() async {
    final rows = await dbLoadPendingMediaDownloads();
    return _attachmentsFromRows(rows);
  }

  @override
  Future<List<DurableGroupMediaDownloadCandidate>>
  loadRecoverableGroupDownloadPage({
    DurableGroupMediaDownloadCursor? after,
    int limit = 25,
  }) async {
    final loadPage = dbLoadRecoverableGroupMediaDownloadPage;
    if (loadPage == null) {
      throw StateError(
        'recoverable GROUP download page query is not wired on this '
        'MediaAttachmentRepositoryImpl',
      );
    }
    if (limit <= 0) {
      throw ArgumentError.value(limit, 'limit', 'must be positive');
    }
    if (after != null &&
        (after.createdAt.isEmpty || after.attachmentId.isEmpty)) {
      throw ArgumentError.value(after, 'after', 'cursor fields must be set');
    }

    final rows = await loadPage(
      limit: limit,
      afterCreatedAt: after?.createdAt,
      afterAttachmentId: after?.attachmentId,
    );
    final candidates = <DurableGroupMediaDownloadCandidate>[];
    for (final row in rows) {
      final groupId = row['recovery_group_id'] as String?;
      if (groupId == null || groupId.isEmpty) {
        throw StateError(
          'recoverable GROUP download row omitted current group authority',
        );
      }
      candidates.add(
        DurableGroupMediaDownloadCandidate(
          attachment: MediaAttachment.fromMap(await _hydrateRow(row)),
          groupId: groupId,
        ),
      );
    }
    return candidates;
  }

  @override
  Future<List<MediaAttachment>> getUploadPendingAttachments({
    required MediaOwnerLane owner,
  }) async {
    final rows = await dbLoadUploadPendingAttachments(ownerLane: owner.dbValue);
    return _attachmentsFromRows(rows);
  }

  Future<Map<String, Object?>> _toStorageRow(MediaAttachment attachment) async {
    final row = Map<String, Object?>.from(attachment.toMap());
    final key = attachment.encryptionKeyBase64;
    final store = secureKeyStore;
    if (store == null ||
        key == null ||
        key.isEmpty ||
        isSecureStoreReference(key)) {
      return row;
    }

    final secureStoreKey = mediaAttachmentEncryptionKeyStoreName(attachment.id);
    await store.write(secureStoreKey, key);
    row['encryption_key_base64'] = secureStoreReferenceForKey(secureStoreKey);
    return row;
  }

  Map<String, Object?> _toStorageExpectationRow(MediaAttachment attachment) {
    final row = Map<String, Object?>.from(attachment.toMap());
    final key = attachment.encryptionKeyBase64;
    if (key != null && key.isNotEmpty && !isSecureStoreReference(key)) {
      row['encryption_key_base64'] = secureStoreReferenceForKey(
        mediaAttachmentEncryptionKeyStoreName(attachment.id),
      );
    }
    return row;
  }

  Future<List<MediaAttachment>> _attachmentsFromRows(
    List<Map<String, Object?>> rows,
  ) async {
    final attachments = <MediaAttachment>[];
    for (final row in rows) {
      attachments.add(MediaAttachment.fromMap(await _hydrateRow(row)));
    }
    return attachments;
  }

  Future<Map<String, Object?>> _hydrateRow(Map<String, Object?> row) async {
    final keyValue = row['encryption_key_base64'] as String?;
    final store = secureKeyStore;
    if (keyValue == null || !isSecureStoreReference(keyValue)) {
      return row;
    }

    final missingKeyRow = Map<String, Object?>.from(row)
      ..['encryption_key_base64'] = null;
    if (store == null) {
      return missingKeyRow;
    }

    final hydrated = await store.read(secureStoreKeyFromReference(keyValue));
    if (hydrated == null) {
      return missingKeyRow;
    }

    return Map<String, Object?>.from(row)..['encryption_key_base64'] = hydrated;
  }
}

class _MediaEncryptionKeyWriteSnapshot {
  _MediaEncryptionKeyWriteSnapshot({
    required this.store,
    required this.keyName,
    required this.existed,
    required this.previousValue,
    required this.replacementValue,
  });

  _MediaEncryptionKeyWriteSnapshot.inactive()
    : store = null,
      keyName = null,
      existed = false,
      previousValue = null,
      replacementValue = null;

  final SecureKeyStore? store;
  final String? keyName;
  final bool existed;
  final String? previousValue;
  final String? replacementValue;
  var _restored = false;

  bool get overwroteDifferentExistingValue =>
      store != null && existed && previousValue != replacementValue;

  Future<void> restore() async {
    final effectiveStore = store;
    final effectiveKeyName = keyName;
    if (_restored || effectiveStore == null || effectiveKeyName == null) return;
    if (existed) {
      await effectiveStore.write(effectiveKeyName, previousValue!);
    } else {
      await effectiveStore.delete(effectiveKeyName);
    }
    _restored = true;
  }
}

class _MediaEncryptionKeyDeletionSnapshot {
  _MediaEncryptionKeyDeletionSnapshot({
    required this.store,
    required this.keyName,
    required this.existed,
    required this.previousValue,
  });

  final SecureKeyStore store;
  final String keyName;
  final bool existed;
  final String? previousValue;
  var _restored = false;

  Future<void> restore() async {
    if (_restored) return;
    if (existed) {
      await store.write(keyName, previousValue!);
    } else {
      await store.delete(keyName);
    }
    _restored = true;
  }
}

/// Opaque keyset cursor for [MediaAttachmentRepositoryImpl.getMediaStoragePage]
/// (229). Embeds the complete scope/kind signature alongside the keyset
/// position; a `v`/`q` mismatch or replay under another signature fails
/// before SQL. Deliberately a distinct codec from [_MediaLibraryCursor] so a
/// visual-library cursor can never address the storage query (and vice
/// versa).
class _MediaStorageCursor {
  const _MediaStorageCursor({
    required this.scopeKind,
    required this.scopeId,
    required this.kind,
    required this.timestamp,
    required this.messageId,
    required this.attachmentId,
  });

  final String scopeKind;
  final String scopeId;
  final String kind;
  final String timestamp;
  final String messageId;
  final String attachmentId;

  String encode() => base64Url.encode(
    utf8.encode(
      jsonEncode({
        'v': 1,
        'q': 'storage',
        'scopeKind': scopeKind,
        'scopeId': scopeId,
        'kind': kind,
        'ts': timestamp,
        'mid': messageId,
        'aid': attachmentId,
      }),
    ),
  );

  static _MediaStorageCursor decode(String cursor) {
    try {
      final decoded =
          jsonDecode(utf8.decode(base64Url.decode(cursor)))
              as Map<String, dynamic>;
      if (decoded['v'] != 1 || decoded['q'] != 'storage') {
        throw const FormatException('unknown storage cursor signature');
      }
      return _MediaStorageCursor(
        scopeKind: decoded['scopeKind'] as String,
        scopeId: decoded['scopeId'] as String,
        kind: decoded['kind'] as String,
        timestamp: decoded['ts'] as String,
        messageId: decoded['mid'] as String,
        attachmentId: decoded['aid'] as String,
      );
    } catch (e) {
      throw ArgumentError.value(cursor, 'cursor', 'malformed cursor: $e');
    }
  }
}

/// Opaque keyset cursor for [MediaAttachmentRepositoryImpl.getMediaLibraryPage].
/// Embeds the complete scope/filter signature alongside the keyset position so
/// a cursor can never be replayed under another query signature.
class _MediaLibraryCursor {
  const _MediaLibraryCursor({
    required this.scopeKind,
    required this.scopeId,
    required this.kind,
    required this.bookmarkedOnly,
    required this.incomingOnly,
    required this.timestamp,
    required this.messageId,
    required this.attachmentId,
  });

  final String scopeKind;
  final String scopeId;
  final String kind;
  final bool bookmarkedOnly;
  final bool incomingOnly;
  final String timestamp;
  final String messageId;
  final String attachmentId;

  String encode() => base64Url.encode(
    utf8.encode(
      jsonEncode({
        'v': 2,
        'scopeKind': scopeKind,
        'scopeId': scopeId,
        'kind': kind,
        'bookmarkedOnly': bookmarkedOnly,
        'incomingOnly': incomingOnly,
        'ts': timestamp,
        'mid': messageId,
        'aid': attachmentId,
      }),
    ),
  );

  static _MediaLibraryCursor decode(String cursor) {
    try {
      final decoded =
          jsonDecode(utf8.decode(base64Url.decode(cursor)))
              as Map<String, dynamic>;
      final version = decoded['v'];
      if (version != 1 && version != 2) {
        throw const FormatException('unknown cursor version');
      }
      return _MediaLibraryCursor(
        scopeKind: decoded['scopeKind'] as String,
        scopeId: decoded['scopeId'] as String,
        kind: decoded['kind'] as String,
        bookmarkedOnly: decoded['bookmarkedOnly'] as bool,
        incomingOnly: version == 1 ? false : decoded['incomingOnly'] as bool,
        timestamp: decoded['ts'] as String,
        messageId: decoded['mid'] as String,
        attachmentId: decoded['aid'] as String,
      );
    } catch (e) {
      throw ArgumentError.value(cursor, 'cursor', 'malformed cursor: $e');
    }
  }
}
