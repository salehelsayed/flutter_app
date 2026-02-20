import '../models/media_attachment.dart';

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
      List<String> messageIds);

  /// Updates the local path and marks download as done.
  Future<void> updateLocalPath(String id, String localPath);

  /// Updates the download status of an attachment.
  Future<void> updateDownloadStatus(String id, String downloadStatus);

  /// Deletes all attachments for a message. Returns count of deleted rows.
  Future<int> deleteAttachmentsForMessage(String messageId);

  /// Deletes all attachments for a contact. Returns count of deleted rows.
  Future<int> deleteAttachmentsForContact(String contactPeerId);

  /// Retrieves all attachments with pending download status.
  Future<List<MediaAttachment>> getPendingDownloads();
}
