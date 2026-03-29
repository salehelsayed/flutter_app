import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';

/// In-memory [MediaAttachmentRepository] for integration tests.
class InMemoryMediaAttachmentRepository implements MediaAttachmentRepository {
  final Map<String, MediaAttachment> _attachments = {};
  void Function(MediaAttachment attachment)? onSaveAttachment;

  @override
  Future<void> saveAttachment(MediaAttachment attachment) async {
    onSaveAttachment?.call(attachment);
    _attachments[attachment.id] = attachment;
  }

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
    String messageId,
  ) async {
    return _attachments.values.where((a) => a.messageId == messageId).toList();
  }

  @override
  Future<Map<String, List<MediaAttachment>>> getAttachmentsForMessages(
    List<String> messageIds,
  ) async {
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
  Future<int> markUploadPendingAttachmentsFailedForMessage(
    String messageId,
  ) async {
    var count = 0;
    for (final entry in _attachments.entries.toList()) {
      final attachment = entry.value;
      if (attachment.messageId == messageId &&
          attachment.downloadStatus == 'upload_pending') {
        _attachments[entry.key] = attachment.copyWith(
          downloadStatus: 'upload_failed',
        );
        count++;
      }
    }
    return count;
  }

  @override
  Future<List<MediaAttachment>> getPendingDownloads() async {
    return _attachments.values
        .where((a) => a.downloadStatus == 'pending')
        .toList();
  }

  @override
  Future<List<MediaAttachment>> getUploadPendingAttachments() async {
    return _attachments.values
        .where((a) => a.downloadStatus == 'upload_pending')
        .toList();
  }

  int get count => _attachments.length;
}
