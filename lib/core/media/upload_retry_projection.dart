import 'package:flutter_app/core/constants/retry_constants.dart';
import 'package:flutter_app/core/media/upload_media_outcome.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

/// Whether an explicit manual Retry can act on the complete attachment set.
///
/// Completed blobs need no local source because Retry may reuse their existing
/// envelope metadata. Every unfinished blob must be either resumable pending
/// work or a bounded failure that reached the retry ceiling, and its source
/// must still resolve to readable bytes. Callers pass an owner-appropriate
/// filesystem predicate so presentation and use-case qualification stay on
/// the same all-or-none contract.
bool isManualUploadRetryAttachmentSetEligible(
  Iterable<MediaAttachment> attachments, {
  required bool Function(String storedPath) sourceExists,
}) {
  final snapshot = attachments.toList(growable: false);
  if (snapshot.isEmpty) return false;
  final unfinished = snapshot
      .where((attachment) => attachment.downloadStatus != 'done')
      .toList(growable: false);
  if (unfinished.length > kReuploadMaxAttachmentsPerMessage) return false;
  for (final attachment in unfinished) {
    final retryCount = attachment.uploadRetryCount ?? 0;
    final statusEligible =
        attachment.downloadStatus == 'upload_pending' ||
        (attachment.downloadStatus == 'upload_failed' &&
            retryCount >= kMaxUploadRetries);
    if (!statusEligible) return false;
    final storedPath = attachment.localPath?.trim();
    if (storedPath == null || storedPath.isEmpty) return false;
    try {
      if (!sourceExists(storedPath)) return false;
    } catch (_) {
      return false;
    }
  }
  return true;
}

/// The committed result of an owner-qualified upload-failure projection.
enum UploadRetryProjectionState {
  notApplied,
  notAppliedActiveLease,
  notAppliedTerminal,
  retryPending,
  terminal,
}

class UploadRetryProjectionResult {
  const UploadRetryProjectionResult({
    required this.state,
    this.uploadRetryCount,
  });

  const UploadRetryProjectionResult.notApplied()
    : state = UploadRetryProjectionState.notApplied,
      uploadRetryCount = null;

  const UploadRetryProjectionResult.notAppliedActiveLease()
    : state = UploadRetryProjectionState.notAppliedActiveLease,
      uploadRetryCount = null;

  const UploadRetryProjectionResult.notAppliedTerminal()
    : state = UploadRetryProjectionState.notAppliedTerminal,
      uploadRetryCount = null;

  final UploadRetryProjectionState state;
  final int? uploadRetryCount;

  bool get applied =>
      state == UploadRetryProjectionState.retryPending ||
      state == UploadRetryProjectionState.terminal;
  bool get blockedByActiveLease =>
      state == UploadRetryProjectionState.notAppliedActiveLease;
  bool get isTerminal => state == UploadRetryProjectionState.terminal;
}

/// Crash-atomic projection capability for direct-message upload failures.
abstract interface class DirectUploadRetryProjectionRepository {
  Future<UploadRetryProjectionResult> projectUploadFailure({
    required String messageId,
    required String attachmentId,
    required UploadMediaFailed failure,
  });
}

/// Crash-atomic projection capability for group-message upload failures.
abstract interface class GroupUploadRetryProjectionRepository {
  Future<UploadRetryProjectionResult> projectUploadFailure({
    required String messageId,
    required String attachmentId,
    required UploadMediaFailed failure,
  });
}

/// Exact attachment snapshot used by the crash-atomic manual-rearm CAS.
///
/// Filesystem qualification happens before ownership is claimed. The raw
/// stored path/status/count are then rechecked inside the parent+attachment
/// transaction so a concurrent mutation cannot partially rearm a message.
class ManualUploadRetryAttachmentExpectation {
  const ManualUploadRetryAttachmentExpectation({
    required this.attachmentId,
    required this.storedLocalPath,
    required this.downloadStatus,
    required this.uploadRetryCount,
  });

  final String attachmentId;
  final String storedLocalPath;
  final String downloadStatus;
  final int uploadRetryCount;
}

/// Crash-atomic direct parent+attachment manual-rearm capability.
abstract interface class DirectManualUploadRetryRearmRepository {
  Future<bool> rearmUploadRetryForManualRetry({
    required String messageId,
    required List<ManualUploadRetryAttachmentExpectation> attachments,
  });
}

/// Crash-atomic group parent+attachment manual-rearm capability.
abstract interface class GroupManualUploadRetryRearmRepository {
  Future<bool> rearmUploadRetryForManualRetry({
    required String messageId,
    required List<ManualUploadRetryAttachmentExpectation> attachments,
  });
}
