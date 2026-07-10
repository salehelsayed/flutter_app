import 'package:flutter_app/core/media/media_owner_lane.dart';

import '../models/media_attachment.dart';
import '../models/media_library.dart';
import '../models/media_preview_descriptor.dart';
import '../models/media_storage.dart';

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
