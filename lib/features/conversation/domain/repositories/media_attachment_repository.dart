import 'package:flutter_app/core/media/media_owner_lane.dart';

import '../models/media_attachment.dart';
import '../models/media_library.dart';
import '../models/media_preview_descriptor.dart';

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
