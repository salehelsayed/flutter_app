import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';

/// In-memory [MediaAttachmentRepository] for integration tests.
///
/// 228: owner-enforcing — every stored attachment is stamped with the lane it
/// was saved under, reads filter by lane, and a same-ID save under another
/// lane (or parent) throws [MediaAttachmentOwnerViolation] exactly like the
/// production repository, so a wrong enum at a caller fails the test instead
/// of being hidden by an untyped fake.
class InMemoryMediaAttachmentRepository
    implements
        MediaAttachmentRepository,
        MediaAttachmentByIdLookup,
        NewMessageMediaPersistenceRollback {
  final Map<String, MediaAttachment> _attachments = {};
  void Function(MediaAttachment attachment)? onSaveAttachment;

  /// Owner-migration boundary fixture: installs a legacy/unresolved row
  /// without weakening normal owner-enforcing writes. Production callers can
  /// never reach this seam; owner-scoped reads must exclude the row.
  void seedUnresolvedOwnerRowForTest(MediaAttachment attachment) {
    if (attachment.ownerLane != null) {
      throw ArgumentError('unresolved fixture must have ownerLane == null');
    }
    _attachments[attachment.id] = attachment;
  }

  @override
  Future<void> saveAttachment(
    MediaAttachment attachment, {
    required MediaOwnerLane owner,
  }) async {
    if (attachment.ownerLane != null && attachment.ownerLane != owner) {
      throw MediaAttachmentOwnerViolation(
        'attachment ${attachment.id} is stamped ${attachment.ownerLane!.dbValue} '
        'but the caller passed ${owner.dbValue}',
      );
    }
    var stamped = attachment.copyWith(ownerLane: owner);
    final existing = _attachments[attachment.id];
    if (existing != null) {
      if (existing.ownerLane != owner ||
          existing.messageId != stamped.messageId) {
        throw MediaAttachmentOwnerViolation(
          'save would re-parent attachment ${attachment.id} from '
          '(${existing.ownerLane?.dbValue}, ${existing.messageId}) to '
          '(${owner.dbValue}, ${stamped.messageId})',
        );
      }
      // Ordinary replay preserves local-only viewer state.
      stamped = stamped.copyWith(
        isBookmarked: existing.isBookmarked,
        lastPlaybackPositionMs: existing.lastPlaybackPositionMs,
      );
    }
    onSaveAttachment?.call(stamped);
    _attachments[attachment.id] = stamped;
  }

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async {
    return _attachments.values
        .where((a) => a.messageId == messageId && a.ownerLane == owner)
        .toList();
  }

  @override
  Future<MediaAttachment?> getAttachmentById(String id) async {
    return _attachments[id];
  }

  @override
  Future<Map<String, List<MediaAttachment>>> getAttachmentsForMessages(
    List<String> messageIds, {
    required MediaOwnerLane owner,
  }) async {
    final result = <String, List<MediaAttachment>>{};
    for (final id in messageIds) {
      final attachments = await getAttachmentsForMessage(id, owner: owner);
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
  Future<int> deleteAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async {
    final keysToRemove = _attachments.entries
        .where(
          (e) => e.value.messageId == messageId && e.value.ownerLane == owner,
        )
        .map((e) => e.key)
        .toList();
    for (final key in keysToRemove) {
      _attachments.remove(key);
    }
    return keysToRemove.length;
  }

  @override
  Future<int> rollbackNewMessageAttachments({
    required String messageId,
    required Set<String> attachmentIds,
    required MediaOwnerLane owner,
  }) async {
    final unexpected = _attachments.values.any(
      (attachment) =>
          attachment.messageId == messageId &&
          attachment.ownerLane == owner &&
          !attachmentIds.contains(attachment.id),
    );
    if (unexpected) {
      throw StateError(
        'refusing new-message media rollback with unexpected attachment ids',
      );
    }
    return deleteAttachmentsForMessage(messageId, owner: owner);
  }

  @override
  Future<int> deleteAttachmentsForContact(String contactPeerId) async {
    // In a real implementation this would join with messages table.
    // For tests, we don't have that link, so return 0.
    return 0;
  }

  @override
  Future<int> markUploadPendingAttachmentsFailedForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async {
    var count = 0;
    for (final entry in _attachments.entries.toList()) {
      final attachment = entry.value;
      if (attachment.messageId == messageId &&
          attachment.ownerLane == owner &&
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
  Future<List<MediaAttachment>> getUploadPendingAttachments({
    required MediaOwnerLane owner,
  }) async {
    return _attachments.values
        .where(
          (a) => a.downloadStatus == 'upload_pending' && a.ownerLane == owner,
        )
        .toList();
  }

  int get count => _attachments.length;
}
