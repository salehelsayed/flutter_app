import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';

/// In-memory [MediaAttachmentRepository] for integration tests.
class InMemoryMediaAttachmentRepository implements MediaAttachmentRepository {
  final Map<String, MediaAttachment> _attachments = {};

  @override
  Future<void> saveAttachment(MediaAttachment attachment) async {
    _attachments[attachment.id] = attachment;
  }

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
      String messageId) async {
    return _attachments.values
        .where((a) => a.messageId == messageId)
        .toList();
  }

  @override
  Future<Map<String, List<MediaAttachment>>> getAttachmentsForMessages(
      List<String> messageIds) async {
    final result = <String, List<MediaAttachment>>{};
    for (final id in messageIds) {
      final attachments = await getAttachmentsForMessage(id);
      if (attachments.isNotEmpty) {
        result[id] = attachments;
      }
    }
    return result;
  }

  @override
  Future<void> updateLocalPath(String id, String localPath) async {
    final a = _attachments[id];
    if (a != null) {
      _attachments[id] = a.copyWith(
        localPath: localPath,
        downloadStatus: 'done',
      );
    }
  }

  @override
  Future<void> updateDownloadStatus(String id, String downloadStatus) async {
    final a = _attachments[id];
    if (a != null) {
      _attachments[id] = a.copyWith(downloadStatus: downloadStatus);
    }
  }

  @override
  Future<int> deleteAttachmentsForMessage(String messageId) async {
    final keysToRemove = _attachments.entries
        .where((e) => e.value.messageId == messageId)
        .map((e) => e.key)
        .toList();
    for (final key in keysToRemove) {
      _attachments.remove(key);
    }
    return keysToRemove.length;
  }

  @override
  Future<int> deleteAttachmentsForContact(String contactPeerId) async {
    // In a real implementation this would join with messages table.
    // For tests, we don't have that link, so return 0.
    return 0;
  }

  @override
  Future<List<MediaAttachment>> getPendingDownloads() async {
    return _attachments.values
        .where((a) => a.downloadStatus == 'pending')
        .toList();
  }

  int get count => _attachments.length;
}
