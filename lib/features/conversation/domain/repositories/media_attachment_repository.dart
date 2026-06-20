import '../models/media_attachment.dart';
import '../models/media_preview_descriptor.dart';

/// Repository interface for managing media attachments.
abstract class MediaAttachmentRepository {
  /// Saves an attachment to the database.
  ///
  /// If an attachment with the same ID exists, it will be replaced.
  Future<void> saveAttachment(MediaAttachment attachment);

  /// Retrieves all attachments for a message.
  Future<List<MediaAttachment>> getAttachmentsForMessage(String messageId);

  /// Retrieves all attachments for multiple messages, grouped by message ID.
  Future<Map<String, List<MediaAttachment>>> getAttachmentsForMessages(
    List<String> messageIds,
  );

  /// Updates the local path and marks download as done.
  Future<void> updateLocalPath(String id, String localPath);

  /// Updates the download status of an attachment.
  Future<void> updateDownloadStatus(String id, String downloadStatus);

  /// Deletes all attachments for a message. Returns count of deleted rows.
  Future<int> deleteAttachmentsForMessage(String messageId);

  /// Deletes all attachments for a contact. Returns count of deleted rows.
  Future<int> deleteAttachmentsForContact(String contactPeerId);

  /// Marks only this message's upload-pending attachments as upload-failed.
  ///
  /// Returns the number of rows transitioned.
  Future<int> markUploadPendingAttachmentsFailedForMessage(String messageId);

  /// Retrieves all attachments with pending download status.
  Future<List<MediaAttachment>> getPendingDownloads();

  /// Returns all attachments with downloadStatus='upload_pending'.
  ///
  /// These are outgoing attachments persisted optimistically at send time
  /// whose upload to the relay was interrupted by an app kill or lock event.
  /// Used by [retryIncompleteUploads] on app resume to re-upload and re-send.
  Future<List<MediaAttachment>> getUploadPendingAttachments();
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
    List<String> messageIds,
  );
}
