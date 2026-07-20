import 'package:flutter_app/core/media/media_file_path_convention.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/application/direct_private_media_lifecycle.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';

class RetryDirectPrivateCommittedPendingCleanupResult {
  const RetryDirectPrivateCommittedPendingCleanupResult({
    required this.loaded,
    required this.cleanedOrAlreadyAbsent,
    required this.refused,
    required this.failed,
  });

  final int loaded;
  final int cleanedOrAlreadyAbsent;
  final int refused;
  final int failed;
}

/// Retries only the exact redundant pending sources shortlisted by the real
/// repository query. Each item is independently requalified by
/// [DirectPrivateMediaLifecycle] under the attachment lifecycle lock, so one
/// transient filesystem failure cannot block later candidates and is retried
/// naturally by the next cold-start/resume bounded pass.
Future<RetryDirectPrivateCommittedPendingCleanupResult>
retryDirectPrivateCommittedPendingCleanup({
  required DirectPrivateCommittedPendingCleanupCandidateRepository repository,
  required DirectPrivateMediaLifecycle lifecycle,
  int limit = 50,
}) async {
  final boundedLimit = limit.clamp(1, 100);
  final candidates = await repository
      .loadDirectPrivateCommittedPendingCleanupCandidates(limit: boundedLimit);
  var cleanedOrAlreadyAbsent = 0;
  var refused = 0;
  var failed = 0;

  for (final candidate in candidates) {
    final expectedPending =
        MediaFilePathConvention.relativePathForPendingUpload(
          messageId: candidate.messageId,
          attachmentId: candidate.attachmentId,
          mime: candidate.mime,
        );
    if (MediaFilePathConvention.extensionFromMime(candidate.mime).isEmpty ||
        candidate.expectedPendingLocalPath != expectedPending) {
      refused++;
      continue;
    }
    try {
      final cleaned = await lifecycle.cleanupCommittedPendingSource(
        messageId: candidate.messageId,
        attachmentId: candidate.attachmentId,
        expectedPendingLocalPath: expectedPending,
      );
      if (cleaned) {
        cleanedOrAlreadyAbsent++;
      } else {
        refused++;
      }
    } catch (error) {
      failed++;
      emitFlowEvent(
        layer: 'FL',
        event: 'DIRECT_PRIVATE_COMMITTED_PENDING_CLEANUP_RETRY_FAILED',
        details: {'error': error.runtimeType.toString()},
      );
    }
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'DIRECT_PRIVATE_COMMITTED_PENDING_CLEANUP_RETRY_DONE',
    details: {
      'loaded': candidates.length,
      'cleanedOrAlreadyAbsent': cleanedOrAlreadyAbsent,
      'refused': refused,
      'failed': failed,
    },
  );
  return RetryDirectPrivateCommittedPendingCleanupResult(
    loaded: candidates.length,
    cleanedOrAlreadyAbsent: cleanedOrAlreadyAbsent,
    refused: refused,
    failed: failed,
  );
}
