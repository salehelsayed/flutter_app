import 'dart:async';

import 'package:flutter_app/core/database/direct_media_blob_custody.dart';
import 'package:flutter_app/core/media/direct_media_blob_terminalization.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/media_attachment_lifecycle_lock.dart';
import 'package:flutter_app/core/media/outgoing_direct_private_mutation_coordinator.dart';
import 'package:flutter_app/core/media/upload_media_outcome.dart';
import 'package:flutter_app/core/media/upload_retry_projection.dart';

import '../models/media_attachment.dart';
import '../models/conversation_message.dart';
import '../models/direct_media_blob_generation_result.dart';
import '../models/incoming_direct_media_blob_custody_result.dart';
import '../models/media_library.dart';
import '../models/media_preview_descriptor.dart';
import '../models/media_storage.dart';
import '../models/outgoing_ordinary_mutation_result.dart';
import '../models/outgoing_direct_media_custody_stage_result.dart';
import 'message_repository.dart';
import 'package:flutter_app/core/database/outgoing_transport_mutation.dart';

/// Repository interface for managing media attachments.
///
/// 228: direct and group message IDs are independent table-local primary
/// keys, so every message-scoped operation carries a typed [MediaOwnerLane].
/// Omitting the owner is a compile error by design — no call site may fall
/// back to an untyped `message_id` lookup that could cross lanes.
/// Announcement surfaces pass [MediaOwnerLane.group] (their parents are
/// group messages).
abstract class MediaAttachmentRepository {
  /// Saves an attachment to the database under [owner].
  ///
  /// An existing attachment ID is updated in place (transport metadata only —
  /// local owner/bookmark/playback state and a completed local path are
  /// preserved). A save that would re-parent the attachment to another owner
  /// lane or message throws [MediaAttachmentOwnerViolation] before any
  /// secure-store/file/database side effect.
  Future<void> saveAttachment(
    MediaAttachment attachment, {
    required MediaOwnerLane owner,
  });

  /// Retrieves all attachments for a message in [owner]'s lane.
  Future<List<MediaAttachment>> getAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  });

  /// Retrieves all attachments for multiple messages (single lane), grouped
  /// by message ID.
  Future<Map<String, List<MediaAttachment>>> getAttachmentsForMessages(
    List<String> messageIds, {
    required MediaOwnerLane owner,
  });

  /// Updates the local path and marks download as done (by unique ID).
  Future<void> updateLocalPath(String id, String localPath);

  /// Updates the download status of an attachment (by unique ID).
  Future<void> updateDownloadStatus(String id, String downloadStatus);

  /// Deletes all attachments for a message in [owner]'s lane. Returns count
  /// of deleted rows.
  Future<int> deleteAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  });

  /// Deletes all DIRECT-owned attachments for a contact. Returns count of
  /// deleted rows. (Contacts exist only in the direct lane; the SQL is
  /// owner-scoped so same-ID group siblings and unresolved legacy rows
  /// survive.)
  Future<int> deleteAttachmentsForContact(String contactPeerId);

  /// Marks only this message's upload-pending attachments (in [owner]'s
  /// lane) as upload-failed.
  ///
  /// Returns the number of rows transitioned.
  Future<int> markUploadPendingAttachmentsFailedForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  });

  /// Retrieves all attachments with pending download status.
  ///
  /// Untyped by design: consumers resolve rows by unique attachment ID.
  Future<List<MediaAttachment>> getPendingDownloads();

  /// Returns [owner]'s attachments with downloadStatus='upload_pending'.
  ///
  /// These are outgoing attachments persisted optimistically at send time
  /// whose upload to the relay was interrupted by an app kill or lock event.
  /// Used by the per-lane retriers on app resume to re-upload and re-send.
  /// The owner filter applies in SQL before the row limit.
  Future<List<MediaAttachment>> getUploadPendingAttachments({
    required MediaOwnerLane owner,
  });
}

/// Independent durable authority for Plan 347 direct-media blob generations.
///
/// The lifecycle section covers candidate-file publication, compensated secure
/// key writes, and the DB batch boundary. Retry callers can only load/reopen an
/// existing complete generation; only a fresh prepared producer calls
/// [stageOutgoingDirectMediaBlobGeneration].
abstract interface class DirectMediaBlobCustodyRepository {
  bool get supportsDirectMediaBlobCustody;

  Future<T> runDirectMediaBlobCustodyLifecycle<T>(Future<T> Function() action);

  Future<DirectMediaBlobGenerationStageResult>
  stageOutgoingDirectMediaBlobGeneration({
    required ConversationMessage expectedParent,
    required List<MediaAttachment> expectedAttachments,
    required List<MediaAttachment> preparedAttachments,
    required List<DirectMediaBlobCustodyRow> custodyRows,
  });

  Future<DirectMediaBlobCustodyRow?> loadDirectMediaBlobCustodyForAttachment(
    String attachmentId,
  );

  Future<List<DirectMediaBlobCustodyRow>> loadDirectMediaBlobCustodyForMessage(
    String messageId,
  );

  Future<List<DirectMediaBlobCustodyRow>> loadDirectMediaBlobCustodyByStates(
    Set<DirectMediaBlobCustodyState> states, {
    int limit = 50,
  });

  Future<bool> transitionDirectMediaBlobCustodyIfExact({
    required DirectMediaBlobCustodyRow expected,
    required DirectMediaBlobCustodyRow next,
  });

  Future<bool> deleteDirectMediaBlobCleanupPendingIfExact(
    DirectMediaBlobCustodyRow expected,
  );
}

/// Optional absent-parent entry into the existing direct-media v111 owner.
///
/// This capability is intentionally independent from
/// [DirectMediaBlobCustodyRepository]. Composer/voice preparation keeps its
/// predecessor-CAS meaning, while an eligible external OS share can atomically
/// publish its canonical parent, complete attachment projection, v110 intent,
/// and v111 generation before its first network request.
abstract interface class FreshOutgoingDirectMediaBlobGenerationRepository {
  bool get supportsFreshOutgoingDirectMediaBlobGeneration;

  Future<FreshOutgoingDirectMediaBlobGenerationStageResult>
  stageFreshOutgoingDirectMediaBlobGeneration({
    required ConversationMessage parent,
    required List<MediaAttachment> expectedAttachments,
    required List<MediaAttachment> preparedAttachments,
    required List<DirectMediaBlobCustodyRow> custodyRows,
  });
}

/// Narrow authority that may publish cleanup for a complete outgoing v111
/// generation after proving exact v108 absence and one terminal reason.
///
/// Keeping this separate from [DirectMediaBlobCustodyRepository] prevents
/// upload/retry fakes from accidentally acquiring cancellation authority.
abstract interface class OutgoingDirectMediaBlobTerminalizationRepository {
  bool get supportsOutgoingDirectMediaBlobTerminalization;

  Future<DirectMediaBlobTerminalizationOutcome>
  terminalizeOutgoingDirectMediaBlobGenerationIfExact({
    required List<DirectMediaBlobCustodyRow> expectedRows,
    required DirectMediaBlobTerminalizationReason reason,
    required int nowMs,
  });
}

/// Receiver-only atomic authority for strict ordinary-direct media.
///
/// This is deliberately separate from [DirectMediaBlobCustodyRepository], so
/// sender-only coordinators and their fakes do not acquire incoming methods.
abstract interface class IncomingDirectMediaBlobCustodyRepository {
  bool get supportsIncomingDirectMediaBlobCustody;

  Future<IncomingDirectMediaBlobCustodyStageResult>
  stageIncomingDirectMediaBlobCustody({
    required ConversationMessage message,
    required List<MediaAttachment> attachments,
    required List<DirectMediaBlobCustodyRow> custodyRows,
  });

  /// Commits an already-durable plaintext file and the exact ACK obligation in
  /// one SQL transaction. A null [sourceRelayPeerId] is verified LAN adoption:
  /// the row remains source-less `incoming_committed` until exact expiry.
  Future<bool> commitIncomingDirectMediaBlobLocalPath({
    required MediaAttachment expectedAttachment,
    required DirectMediaBlobCustodyRow expectedCustody,
    required String localPath,
    required String? sourceRelayPeerId,
    required String updatedAt,
  });

  Future<bool> deleteIncomingDirectMediaBlobAckIfExact(
    DirectMediaBlobCustodyRow expected,
  );

  Future<bool> deleteIncomingDirectMediaBlobIfExpired({
    required DirectMediaBlobCustodyRow expected,
    required int nowMs,
  });
}

/// Optional atomic staging authority for ordinary outgoing attempts that own
/// direct attachment rows. The parent/envelope and the exact normalized media
/// projection commit in one SQLite transaction or neither side changes.
abstract interface class OutgoingOrdinaryAttemptStagingRepository {
  Future<OutgoingOrdinaryMutationResult> stageOutgoingOrdinaryAttemptWithMedia({
    required OutgoingTransportMutationRepository messageMutationRepository,
    required ConversationMessage? expected,
    required ConversationMessage staged,
    required List<MediaAttachment> attachments,
    required OutgoingOrdinaryAttemptKind kind,
  });
}

/// Optional fail-closed authority for newly authored ordinary direct media.
///
/// Parent, exact attachment projection, manifest-intent consumption and the
/// immutable v108 outbox row commit in one SQLCipher transaction. The
/// prepared intent (when present) is the incarnation; a marker-free fresh
/// stage mints its incarnation inside that transaction.
abstract interface class OutgoingDirectMediaInboxCustodyStagingRepository {
  bool get supportsDirectMediaInboxCustody;

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
  });
}

/// Exact failure projection for a manifest-bound direct-media preparation.
///
/// Implementations revalidate the original parent, the complete authored
/// attachment projection, the manifest token, and global v108 absence in the
/// same transaction that changes retry state. Token-bearing callers must not
/// fall back to [MediaAttachmentRepository.saveAttachment] when this authority
/// is unavailable or refuses the crossed snapshot.
abstract interface class OutgoingDirectMediaCustodyFailureRepository {
  bool get supportsDirectMediaCustodyFailureProjection;

  Future<UploadRetryProjectionResult> projectDirectMediaCustodyUploadFailure({
    required ConversationMessage expectedParent,
    required List<MediaAttachment> expectedAttachments,
    required String failedAttachmentId,
    required UploadMediaFailed failure,
  });
}

/// Durable attachment mutations that can change current playback authority.
enum MediaAttachmentAuthorizationMutation {
  saved,
  localPathChanged,
  downloadStatusChanged,
  downloadStarted,
  downloadCommitted,
  evicted,
  evictionFinalized,
  removed,
}

/// Exact post-commit identity for an authorization-relevant attachment write.
///
/// [scopeId] is present when the mutation itself is contact/group scoped.
/// Message- and attachment-scoped operations instead carry their exact IDs.
/// A null [attachmentId] applies to every attachment under [messageId], and a
/// null [messageId] applies to the exact [scopeId].
class MediaAttachmentAuthorizationChange {
  const MediaAttachmentAuthorizationChange({
    required this.owner,
    this.scopeId,
    this.messageId,
    this.attachmentId,
    required this.kind,
  }) : assert(scopeId != null || messageId != null || attachmentId != null);

  final MediaOwnerLane owner;
  final String? scopeId;
  final String? messageId;
  final String? attachmentId;
  final MediaAttachmentAuthorizationMutation kind;
}

/// Optional repository capability for exact, post-commit media invalidation.
abstract class MediaAttachmentAuthorizationChangeSource {
  Stream<MediaAttachmentAuthorizationChange> get authorizationChanges;
}

/// Optional compensation capability for a brand-new message whose attachment
/// rows were written before its parent row became durable.
///
/// Callers may use this only after proving that [messageId] had no pre-existing
/// parent. Implementations must remove the exact new attachment rows and any
/// secure-key side effects without touching another message or owner lane.
abstract class NewMessageMediaPersistenceRollback {
  Future<int> rollbackNewMessageAttachments({
    required String messageId,
    required Set<String> attachmentIds,
    required MediaOwnerLane owner,
  });
}

/// Optional narrow lookup for callers that must reconcile an out-of-band media
/// event with an attachment row regardless of current download status.
abstract class MediaAttachmentByIdLookup {
  Future<MediaAttachment?> getAttachmentById(String id);
}

/// Optional capability (235): the guarded FINAL write for incoming GROUP
/// media.
///
/// In the SAME transaction as the attachment-row write it verifies a live
/// exact `(groupId, messageId)` parent and the absence of an active
/// `group_media_deletion_journal` reservation for the attachment ID; when the
/// guard refuses it returns false with ZERO row/secure-key side effects. This
/// closes the save-vs-delete race that a pre-write reload cannot: a same-ID
/// parent silently rejected by the migration-069 tombstone must never acquire
/// group-owned attachment rows.
abstract class GroupGuardedMediaAttachmentSave {
  Future<bool> saveGroupAttachmentGuarded(
    MediaAttachment attachment, {
    required String groupId,
  });
}

/// Optional capability: a key-free batch lookup of [MediaPreviewDescriptor]s
/// for messages, used by the orbit chat-list to label media without paying a
/// `SecureKeyStore.read` per attachment on the hot screen-load path.
///
/// Callers that only have a plain [MediaAttachmentRepository] should fall back
/// to `getAttachmentsForMessages` + [MediaPreviewDescriptor.fromAttachments]
/// (correct, just not key-free) when a repo does not implement this.
abstract class MediaPreviewDescriptorLookup {
  Future<Map<String, MediaPreviewDescriptor>> getMediaPreviewDescriptors(
    List<String> messageIds, {
    required MediaOwnerLane owner,
  });
}

/// Optional capability (228): stable newest-first paged access to a
/// conversation's visual media for the Shared Media library.
///
/// Pages order by `(parentTimestamp DESC, messageId DESC, attachmentId
/// DESC)`. The returned cursor is opaque and bound to the exact scope +
/// filter signature that minted it; replaying it with any other signature
/// (or a malformed cursor) throws [ArgumentError] before any SQL runs.
/// Limits outside `1..kMediaLibraryMaxPageSize` also fail before SQL.
abstract class MediaLibraryRepository {
  Future<MediaLibraryPage> getMediaLibraryPage({
    required MediaLibraryScope scope,
    MediaLibraryFilter filter = const MediaLibraryFilter(),
    int limit = 50,
    String? cursor,
  });
}

/// Optional capability (229): the owner-scoped all-media STORAGE page query
/// behind `MediaStorageManager.inventory`.
///
/// Reuses the 228 visibility contract (owner-lane SQL predicate, live/
/// un-hidden direct parents, group tombstone anti-join, `unresolved`
/// invisible) but addresses all four media types and returns only rows with
/// a stored local path. Cursors are opaque and bound to the exact scope +
/// kind signature; replaying one under another signature (or malformed)
/// throws [ArgumentError] before SQL, as do limits outside
/// `1..kMediaLibraryMaxPageSize`. This deliberately does NOT broaden the
/// visual [MediaLibraryRepository] contract.
abstract class MediaStorageInventoryRepository {
  Future<MediaStoragePage> getMediaStoragePage({
    required MediaLibraryScope scope,
    MediaStorageKind kind = MediaStorageKind.all,
    int limit = kMediaLibraryMaxPageSize,
    String? cursor,
  });
}

/// Optional capability (229): owner-aware conditional download/eviction
/// state transitions with affected-row results.
///
/// The download use case claims a row into `downloading` before transfer and
/// commits the canonical path/`done` ONLY from its own claim; the storage
/// manager claims `done` rows into `evicted` before touching any file and
/// nulls the path only after a successful delete. Every method returns how
/// many rows the conditional write affected — zero is a lost claim, never
/// success.
abstract class MediaDownloadStateRepository {
  /// CAS: claim [id] into `downloading` under [owner]. Allowed source states
  /// are pending/downloading/failed/download_failed/evicted; `done` rows are
  /// adopted, never re-claimed. Returns true when exactly one row was
  /// claimed.
  Future<bool> beginMediaDownload(String id, {required MediaOwnerLane owner});

  /// CAS: commit the canonical relative [localPath] + `done` (retry budget
  /// resets) only while the row is still this download's `downloading`
  /// claim under [owner]. Returns true when the commit landed; false means
  /// the claim was lost and the caller must fail closed (removing only the
  /// exact artifact it promoted).
  Future<bool> commitMediaDownloadLocalPath(
    String id, {
    required MediaOwnerLane owner,
    required String localPath,
  });

  /// CAS: claim the exact `(id, owner, expectedLocalPath, done)` row as
  /// `evicted`, retaining the stored path for the deletion step. Returns the
  /// affected row count (0 = row changed underneath the caller — delete
  /// nothing).
  Future<int> claimMediaEvicted(
    String id, {
    required MediaOwnerLane owner,
    required String expectedLocalPath,
  });

  /// CAS: null the stored path of a row still `evicted` under [owner] (the
  /// post-delete finalize, or fresh-manager reconciliation after proving the
  /// canonical file absent). Returns the affected row count.
  Future<int> finalizeMediaEvictedPathCleared(
    String id, {
    required MediaOwnerLane owner,
  });
}

/// Exact UPDATE-only failure persistence for an incoming ordinary GROUP
/// download.
///
/// Implementations atomically qualify the attachment's exact owner/message/
/// status/path tuple, its live ordinary incoming parent, and the absence of an
/// active group deletion journal. A false result is lost authority and must
/// never fall back to an insert-capable preserving save.
abstract class OrdinaryGroupMediaDownloadFailureRepository {
  Future<bool> recordOrdinaryGroupMediaDownloadFailure(
    String id, {
    required String groupId,
    required String messageId,
    required bool incrementRetryCount,
    required String failureStatus,
    required String expectedDownloadStatus,
    required String? expectedLocalPath,
    required bool clearLocalPath,
  });
}

/// Authority-complete CAS transitions for automatic ordinary GROUP recovery.
///
/// Unlike [MediaDownloadStateRepository], this capability deliberately never
/// claims terminal `download_failed` or user-only `evicted` rows. Both writes
/// requalify the exact attachment tuple, current ordinary incoming parent,
/// active group, local visibility, and deletion-journal authority in the same
/// database statement. Explicit user retry uses the dedicated exact capability
/// below so it can retain its broader status admission without weakening this
/// authority tuple.
abstract class OrdinaryGroupAutomaticMediaDownloadStateRepository {
  Future<bool> beginOrdinaryGroupAutomaticMediaDownload(
    String id, {
    required String groupId,
    required String messageId,
    required String expectedDownloadStatus,
    required String? expectedLocalPath,
  });

  Future<bool> commitOrdinaryGroupAutomaticMediaDownloadLocalPath(
    String id, {
    required String groupId,
    required String messageId,
    required String? expectedLocalPath,
    required String localPath,
  });
}

/// Authority-complete CAS transitions for explicit ordinary GROUP retries.
///
/// These writes use the same exact attachment, live-parent, active-group,
/// local-visibility, and deletion-journal qualification as automatic recovery,
/// while deliberately retaining the broader explicit-user retry surface:
/// terminal `download_failed` and user-only `evicted` rows remain claimable and
/// the automatic retry ceiling does not apply.
abstract class OrdinaryGroupExplicitMediaDownloadStateRepository {
  Future<bool> beginOrdinaryGroupExplicitMediaDownload(
    String id, {
    required String groupId,
    required String messageId,
    required String expectedDownloadStatus,
    required String? expectedLocalPath,
  });

  Future<bool> commitOrdinaryGroupExplicitMediaDownloadLocalPath(
    String id, {
    required String groupId,
    required String messageId,
    required String? expectedLocalPath,
    required String localPath,
  });
}

/// Stable durable cursor for automatic ordinary GROUP download recovery.
///
/// Rows are ordered by this exact `(created_at ASC, attachment_id ASC)` pair.
/// Callers advance from the last row they inspected, independently of whether
/// policy allowed that row to transfer.
class DurableGroupMediaDownloadCursor {
  const DurableGroupMediaDownloadCursor({
    required this.createdAt,
    required this.attachmentId,
  });

  final String createdAt;
  final String attachmentId;
}

/// Query-time snapshot of one recoverable ordinary incoming GROUP attachment.
///
/// Automatic recovery must reload current attachment, message, and group
/// authority before network access; this snapshot exists only to provide a
/// bounded, forward-progressing durable scan.
class DurableGroupMediaDownloadCandidate {
  const DurableGroupMediaDownloadCandidate({
    required this.attachment,
    required this.groupId,
  });

  final MediaAttachment attachment;
  final String groupId;

  DurableGroupMediaDownloadCursor get cursor => DurableGroupMediaDownloadCursor(
    createdAt: attachment.createdAt,
    attachmentId: attachment.id,
  );
}

/// Optional read-only capability for cursor-paged automatic GROUP recovery.
///
/// Implementations return only group-owned attachments whose current parent
/// is incoming, live, locally visible, canonically ordinary, and outside any
/// active deletion journal. Recoverable states are `pending`, `downloading`,
/// and under-budget `failed`; `downloading` deliberately survives process
/// death as durable retry work.
abstract class RecoverableGroupMediaDownloadRepository {
  Future<List<DurableGroupMediaDownloadCandidate>>
  loadRecoverableGroupDownloadPage({
    DurableGroupMediaDownloadCursor? after,
    int limit = 25,
  });
}

/// Session 03 capability: the direct-private final download commit checks the
/// current parent and attachment claim in one database transaction while the
/// process-wide attachment lock is held.
abstract class DirectPrivateMediaDownloadStateRepository {
  Future<bool> beginDirectPrivateMediaDownload(
    String id, {
    required String messageId,
    required int nowMs,
  });

  /// Same transition as [beginDirectPrivateMediaDownload], but the caller
  /// already owns [DirectPrivateMediaCleanupRuntime]'s attachment lock.
  Future<bool> beginDirectPrivateMediaDownloadWithinLock(
    String id, {
    required String messageId,
    required int nowMs,
  });

  /// Rechecks the exact active parent and exact persisted done/path row in one
  /// transaction while the implementation holds the shared attachment lock.
  Future<bool> qualifyDirectPrivateMediaLocalReady(
    String id, {
    required String messageId,
    required String expectedLocalPath,
    required int nowMs,
  });

  Future<bool> qualifyDirectPrivateMediaLocalReadyWithinLock(
    String id, {
    required String messageId,
    required String expectedLocalPath,
    required int nowMs,
  });

  Future<bool> qualifyDirectPrivateMediaDownloadClaimWithinLock(
    String id, {
    required String messageId,
    required int nowMs,
  });

  /// UPDATE-only parent-qualified failure transition. It never inserts a
  /// missing attachment or rewrites secure-key material after cleanup wins.
  Future<bool> recordDirectPrivateMediaDownloadFailure(
    String id, {
    required String messageId,
    required int nowMs,
    required bool incrementRetryCount,
    required String failureStatus,
    required String expectedDownloadStatus,
    String? expectedLocalPath,
    bool clearLocalPath,
  });

  Future<bool> recordDirectPrivateMediaDownloadFailureWithinLock(
    String id, {
    required String messageId,
    required int nowMs,
    required bool incrementRetryCount,
    required String failureStatus,
    required String expectedDownloadStatus,
    String? expectedLocalPath,
    bool clearLocalPath,
  });

  Future<bool> commitDirectPrivateMediaDownloadLocalPath(
    String id, {
    required String messageId,
    required String localPath,
    required int nowMs,
  });

  Future<bool> commitDirectPrivateMediaDownloadLocalPathWithinLock(
    String id, {
    required String messageId,
    required String localPath,
    required int nowMs,
  });
}

/// Atomic parent-qualified save for incoming direct private attachment
/// metadata. A lost parent race returns false with no durable row/key effect.
abstract class DirectPrivateMediaAttachmentSaveRepository {
  Future<bool> saveDirectPrivateAttachmentGuarded(
    MediaAttachment attachment, {
    required String messageId,
    required int nowMs,
  });
}

class DirectPrivateMediaCleanupAttachment {
  const DirectPrivateMediaCleanupAttachment({
    required this.id,
    required this.messageId,
    required this.mime,
    this.size = 0,
    this.downloadStatus,
    this.localPath,
  });

  final String id;
  final String messageId;
  final String mime;
  final int size;
  final String? downloadStatus;
  final String? localPath;
}

/// Raw, key-free direct attachment metadata used to decide whether a View Once
/// local copy is openable. The application adapter validates status, canonical
/// containment, symlinks, and file existence before exposing a path to the
/// shared engine; secure key material is never hydrated on recovery scans.
class DirectPrivateMediaLifecycleAttachmentMetadata {
  const DirectPrivateMediaLifecycleAttachmentMetadata({
    required this.id,
    required this.messageId,
    required this.mime,
    required this.size,
    required this.downloadStatus,
    required this.localPath,
  });

  final String id;
  final String messageId;
  final String mime;
  final int size;
  final String downloadStatus;
  final String? localPath;
}

/// Bounded restart/resume candidate for an outgoing one-more-look upload whose
/// canonical completion is durable but whose exact pending plaintext source
/// may have survived a transient unlink failure. The transport settlement may
/// already have cleared its wire envelope, so envelope presence is not part of
/// this local file-custody qualification.
///
/// This shape is deliberately key-free. The application use case derives the
/// convention pending path, while [DirectPrivateMediaLifecycle] requalifies
/// the parent, row, canonical file, roots, and transfer lease under the exact
/// attachment lifecycle lock before deleting anything.
class DirectPrivateCommittedPendingCleanupCandidate {
  const DirectPrivateCommittedPendingCleanupCandidate({
    required this.messageId,
    required this.attachmentId,
    required this.mime,
    required this.expectedPendingLocalPath,
  });

  final String messageId;
  final String attachmentId;
  final String mime;
  final String expectedPendingLocalPath;
}

/// Read-only, bounded candidate source for committed pending-source recovery.
abstract class DirectPrivateCommittedPendingCleanupCandidateRepository {
  Future<List<DirectPrivateCommittedPendingCleanupCandidate>>
  loadDirectPrivateCommittedPendingCleanupCandidates({int limit = 50});
}

/// Raw, key-free exact-direct cleanup seam. The lifecycle engine owns the
/// process lock; these methods must not recursively acquire it.
abstract class DirectPrivateMediaCleanupRepository {
  Future<List<DirectPrivateMediaLifecycleAttachmentMetadata>>
  loadDirectPrivateMediaLifecycleAttachmentMetadata(String messageId);

  Future<List<DirectPrivateMediaCleanupAttachment>>
  loadDirectPrivateMediaCleanupAttachments(String messageId);

  /// Deletes only the secure-storage key derived from [attachmentId]. The
  /// caller already owns [DirectPrivateMediaCleanupRuntime]'s lifecycle lock;
  /// generic secret-store read/write access is deliberately not exposed.
  Future<bool> deleteDirectPrivateMediaEncryptionKeyWithinLock({
    required String messageId,
    required String attachmentId,
  });

  Future<int> deleteDirectPrivateMediaAttachmentWithinLock({
    required String messageId,
    required String attachmentId,
  });
}

/// Narrow path-only repair for the deployed outgoing private-media shape
/// whose successful upload left a `done` row pointing at the now-removed
/// absolute pending-upload file.
///
/// Callers authorize the canonical file while holding the exact attachment
/// lifecycle lock. Implementations must exact-CAS only `local_path`; status,
/// crypto metadata, retry counters, bookmarks, and playback state are never
/// inferred or rewritten.
abstract class DirectPrivateMediaLegacyPathRepairRepository {
  Future<bool> repairOutgoingDirectPrivateMediaDoneLocalPathWithinLock({
    required String messageId,
    required String attachmentId,
    required String expectedStoredLocalPath,
    required String canonicalLocalPath,
    required String expectedContactPeerId,
    required String expectedMime,
    required int expectedSize,
  });
}

/// Repository-owned outgoing direct-private upload-completion authority.
///
/// Every adapter and upload writer resolving this capability from the same
/// repository instance receives the exact same coordinator and lifecycle
/// lock. Private callers must fail closed when the capability is absent.
abstract class OutgoingDirectPrivateMutationRepository {
  OutgoingDirectPrivateMutationCoordinator
  get outgoingDirectPrivateMutationCoordinator;

  /// Applies a failure/cancel/retry-count mutation to one exact outgoing
  /// protected/view-once pending row. Ordinary/incoming/disappearing parents
  /// return `notPrivateParent`; callers may retain their generic path only for
  /// that result.
  Future<OutgoingDirectPrivateNonCompletionMutationOutcome>
  applyOutgoingDirectPrivateNonCompletionMutation(MediaAttachment attachment);

  /// Atomically prepares the complete first pending-row set for one outgoing
  /// protected/view-once parent. The result is always authoritative: only
  /// [OutgoingDirectPrivatePendingPreparationOutcome.notPrivateParent] may
  /// use generic persistence, while a private refusal must clean the copied
  /// pending files and stop.
  Future<OutgoingDirectPrivatePendingPreparationOutcome>
  prepareOutgoingDirectPrivatePendingAttachments(
    List<MediaAttachment> attachments,
  );

  /// Deletes one message's exact convention-pending protected/view-once row
  /// set under available-state authority. File deletion runs first, under the
  /// same repository lifecycle lock, while the rows and keys still authorize
  /// every plaintext path. Key/row deletion follows only after every exact
  /// pending file has been removed. This never performs terminal lifecycle
  /// cleanup and therefore returns an active-lease or terminal no-op
  /// explicitly.
  Future<OutgoingDirectPrivateNonCompletionMutationOutcome>
  deleteOutgoingDirectPrivatePendingAttachmentsForMessage(
    String messageId, {
    required MediaFileManager mediaFileManager,
  });
}

/// Narrow runtime dependencies needed to compose the application-level direct
/// lifecycle adapter without depending on a concrete repository class.
abstract class DirectPrivateMediaCleanupRuntime {
  MediaAttachmentLifecycleLock get directPrivateMediaLifecycleLock;
}

/// Group-private equivalent of the direct guarded download protocol. The
/// implementation uses group-parent policy/expiry authority while preserving
/// the same attachment-lock ordering required by the shared downloader.
abstract class GroupPrivateMediaDownloadStateRepository {
  Future<bool> beginGroupPrivateMediaDownloadWithinLock(
    String id, {
    required String groupId,
    required String messageId,
    required int nowMs,
  });

  Future<bool> qualifyGroupPrivateMediaLocalReadyWithinLock(
    String id, {
    required String groupId,
    required String messageId,
    required String expectedLocalPath,
    required int nowMs,
  });

  Future<bool> qualifyGroupPrivateMediaDownloadClaimWithinLock(
    String id, {
    required String groupId,
    required String messageId,
    required int nowMs,
  });

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
  });

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
  });

  Future<bool> commitGroupPrivateMediaDownloadLocalPathWithinLock(
    String id, {
    required String groupId,
    required String messageId,
    required String localPath,
    required int nowMs,
  });
}

class GroupPrivateMediaLifecycleAttachmentMetadata {
  const GroupPrivateMediaLifecycleAttachmentMetadata({
    required this.id,
    required this.messageId,
    required this.mime,
    required this.size,
    required this.downloadStatus,
    required this.localPath,
  });

  final String id;
  final String messageId;
  final String mime;
  final int size;
  final String downloadStatus;
  final String? localPath;
}

abstract class GroupPrivateMediaCleanupRepository {
  Future<List<GroupPrivateMediaLifecycleAttachmentMetadata>>
  loadGroupPrivateMediaLifecycleAttachmentMetadata(String messageId);

  Future<bool> deleteGroupPrivateMediaEncryptionKeyWithinLock({
    required String messageId,
    required String attachmentId,
  });

  Future<int> deleteGroupPrivateMediaAttachmentWithinLock({
    required String messageId,
    required String attachmentId,
  });
}

abstract class GroupPrivateMediaCleanupRuntime {
  MediaAttachmentLifecycleLock get groupPrivateMediaLifecycleLock;
}

/// Optional capability (228): explicit local viewer-state writers. These are
/// the ONLY paths that may flip bookmark/playback state — ordinary replays
/// preserve it (see [MediaAttachmentRepository.saveAttachment]).
abstract class MediaLibraryStateRepository {
  /// Sets the local bookmark flag. Image/video attachments only.
  Future<void> setBookmarked(String id, {required bool bookmarked});

  /// Stores a durable video resume position (video attachments only).
  /// Negative positions clamp to 0; with a known duration, reaching the end
  /// resets to 0 (completion); with an unknown duration the non-negative
  /// position is stored and re-clamped when a later replay supplies the
  /// duration.
  Future<void> updatePlaybackPosition(String id, int positionMs);
}

/// Narrow direct-only bookmark capability. Unlike the generic library state
/// seam, this write is keyed by exact parent/attachment identity and guarded
/// atomically by the current parent remaining live and ordinary.
abstract class DirectMediaLibraryStateRepository {
  Future<bool> setDirectBookmarkedIfOrdinary({
    required String messageId,
    required String attachmentId,
    required bool bookmarked,
  });
}

/// Narrow group-only bookmark capability. The write is keyed by exact
/// group/message/attachment identity and atomically guarded by the current
/// parent remaining visible and canonically ordinary.
abstract class GroupMediaLibraryStateRepository {
  Future<bool> setGroupBookmarkedIfOrdinary({
    required String groupId,
    required String messageId,
    required String attachmentId,
    required bool bookmarked,
  });
}
