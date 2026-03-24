import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';

/// In-memory [MediaAttachmentRepository] for tests.
///
/// Stores attachments in a list, configurable callbacks, tracks saves.
class FakeMediaAttachmentRepository implements MediaAttachmentRepository {
  final List<MediaAttachment> _attachments = [];

  // Pre-upload ordering hook
  void Function(MediaAttachment att)? onSaveAttachment;

  // Track all saves for assertion in multi-attachment tests
  final _savedAttachments = <MediaAttachment>[];
  List<MediaAttachment> get allSavedAttachments =>
      List.unmodifiable(_savedAttachments);

  MediaAttachment? get lastSavedAttachment =>
      _savedAttachments.isNotEmpty ? _savedAttachments.last : null;

  /// Seed attachments for testing.
  void seed(List<MediaAttachment> attachments) {
    _attachments
      ..clear()
      ..addAll(attachments);
  }

  /// Seed attachments for a specific message (append, don't clear).
  void seedAttachments({
    required String messageId,
    required List<MediaAttachment> attachments,
  }) {
    _attachments.addAll(attachments);
  }

  // Track getAttachmentsForMessage calls
  int getAttachmentsForMessageCallCount = 0;

  @override
  Future<void> saveAttachment(MediaAttachment attachment) async {
    onSaveAttachment?.call(attachment);
    _savedAttachments.add(attachment);
    // Upsert by ID
    final idx = _attachments.indexWhere((a) => a.id == attachment.id);
    if (idx >= 0) {
      _attachments[idx] = attachment;
    } else {
      _attachments.add(attachment);
    }
  }

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
      String messageId) async {
    getAttachmentsForMessageCallCount++;
    return _attachments.where((a) => a.messageId == messageId).toList();
  }

  @override
  Future<Map<String, List<MediaAttachment>>> getAttachmentsForMessages(
      List<String> messageIds) async {
    final result = <String, List<MediaAttachment>>{};
    for (final a in _attachments) {
      if (messageIds.contains(a.messageId)) {
        result.putIfAbsent(a.messageId, () => []).add(a);
      }
    }
    return result;
  }

  @override
  Future<void> updateLocalPath(String id, String localPath) async {
    final idx = _attachments.indexWhere((a) => a.id == id);
    if (idx >= 0) {
      _attachments[idx] = _attachments[idx].copyWith(
        localPath: localPath,
        downloadStatus: 'done',
      );
    }
  }

  @override
  Future<void> updateDownloadStatus(String id, String downloadStatus) async {
    final idx = _attachments.indexWhere((a) => a.id == id);
    if (idx >= 0) {
      _attachments[idx] =
          _attachments[idx].copyWith(downloadStatus: downloadStatus);
    }
  }

  @override
  Future<int> deleteAttachmentsForMessage(String messageId) async {
    final before = _attachments.length;
    _attachments.removeWhere((a) => a.messageId == messageId);
    return before - _attachments.length;
  }

  @override
  Future<int> deleteAttachmentsForContact(String contactPeerId) async {
    // simplified - in tests we don't join with messages table
    return 0;
  }

  @override
  Future<List<MediaAttachment>> getPendingDownloads() async {
    return _attachments.where((a) => a.downloadStatus == 'pending').toList();
  }

  @override
  Future<List<MediaAttachment>> getUploadPendingAttachments() async {
    return _attachments
        .where((a) => a.downloadStatus == 'upload_pending')
        .toList();
  }
}
