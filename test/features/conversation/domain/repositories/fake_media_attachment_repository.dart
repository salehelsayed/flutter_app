import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';

/// In-memory [MediaAttachmentRepository] for tests.
///
/// Stores attachments in a list, configurable callbacks, tracks saves.
///
/// 228: owner-enforcing — every save stamps the caller's typed lane, reads
/// filter by lane, and a same-ID save under another lane (or parent) throws
/// [MediaAttachmentOwnerViolation] exactly like the production repository,
/// so a wrong enum at a caller fails the test instead of being hidden by an
/// untyped fake. Seeded attachments without an explicit lane default to
/// [seedOwnerLane] (direct unless overridden).
class FakeMediaAttachmentRepository
    implements MediaAttachmentRepository, MediaAttachmentByIdLookup {
  FakeMediaAttachmentRepository({this.seedOwnerLane = MediaOwnerLane.direct});

  final List<MediaAttachment> _attachments = [];

  /// Lane stamped onto seeded attachments that carry none.
  final MediaOwnerLane seedOwnerLane;

  // Pre-upload ordering hook
  void Function(MediaAttachment att)? onSaveAttachment;

  // Track all saves for assertion in multi-attachment tests
  final _savedAttachments = <MediaAttachment>[];
  List<MediaAttachment> get allSavedAttachments =>
      List.unmodifiable(_savedAttachments);

  /// Lanes passed to [saveAttachment], in call order.
  final savedOwnerLanes = <MediaOwnerLane>[];

  MediaAttachment? get lastSavedAttachment =>
      _savedAttachments.isNotEmpty ? _savedAttachments.last : null;

  MediaAttachment _withSeedLane(MediaAttachment attachment) =>
      attachment.ownerLane == null
      ? attachment.copyWith(ownerLane: seedOwnerLane)
      : attachment;

  /// Seed attachments for testing.
  void seed(List<MediaAttachment> attachments) {
    _attachments
      ..clear()
      ..addAll(attachments.map(_withSeedLane));
  }

  /// Seed attachments for a specific message (append, don't clear).
  void seedAttachments({
    required String messageId,
    required List<MediaAttachment> attachments,
  }) {
    _attachments.addAll(attachments.map(_withSeedLane));
  }

  // Track getAttachmentsForMessage calls
  int getAttachmentsForMessageCallCount = 0;

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
    final stamped = attachment.copyWith(ownerLane: owner);
    final idx = _attachments.indexWhere((a) => a.id == attachment.id);
    if (idx >= 0) {
      final existing = _attachments[idx];
      if (existing.ownerLane != owner ||
          existing.messageId != stamped.messageId) {
        throw MediaAttachmentOwnerViolation(
          'save would re-parent attachment ${attachment.id} from '
          '(${existing.ownerLane?.dbValue}, ${existing.messageId}) to '
          '(${owner.dbValue}, ${stamped.messageId})',
        );
      }
    }
    onSaveAttachment?.call(stamped);
    _savedAttachments.add(stamped);
    savedOwnerLanes.add(owner);
    // Upsert by ID
    if (idx >= 0) {
      _attachments[idx] = stamped;
    } else {
      _attachments.add(stamped);
    }
  }

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async {
    getAttachmentsForMessageCallCount++;
    return _attachments
        .where((a) => a.messageId == messageId && a.ownerLane == owner)
        .toList();
  }

  @override
  Future<MediaAttachment?> getAttachmentById(String id) async {
    for (final attachment in _attachments) {
      if (attachment.id == id) return attachment;
    }
    return null;
  }

  @override
  Future<Map<String, List<MediaAttachment>>> getAttachmentsForMessages(
    List<String> messageIds, {
    required MediaOwnerLane owner,
  }) async {
    final result = <String, List<MediaAttachment>>{};
    for (final a in _attachments) {
      if (messageIds.contains(a.messageId) && a.ownerLane == owner) {
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
      _attachments[idx] = _attachments[idx].copyWith(
        downloadStatus: downloadStatus,
      );
    }
  }

  @override
  Future<int> deleteAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async {
    final before = _attachments.length;
    _attachments.removeWhere(
      (a) => a.messageId == messageId && a.ownerLane == owner,
    );
    return before - _attachments.length;
  }

  @override
  Future<int> deleteAttachmentsForContact(String contactPeerId) async {
    // simplified - in tests we don't join with messages table
    return 0;
  }

  @override
  Future<int> markUploadPendingAttachmentsFailedForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async {
    var count = 0;
    for (var i = 0; i < _attachments.length; i++) {
      final attachment = _attachments[i];
      if (attachment.messageId == messageId &&
          attachment.ownerLane == owner &&
          attachment.downloadStatus == 'upload_pending') {
        _attachments[i] = attachment.copyWith(downloadStatus: 'upload_failed');
        count++;
      }
    }
    return count;
  }

  @override
  Future<List<MediaAttachment>> getPendingDownloads() async {
    return _attachments.where((a) => a.downloadStatus == 'pending').toList();
  }

  @override
  Future<List<MediaAttachment>> getUploadPendingAttachments({
    required MediaOwnerLane owner,
  }) async {
    return _attachments
        .where(
          (a) => a.downloadStatus == 'upload_pending' && a.ownerLane == owner,
        )
        .toList();
  }
}
