import 'dart:async';

/// 235: one process-wide async mutex per attachment ID.
///
/// Serializes the operations that touch one attachment's row + secure key +
/// canonical file across features: the guarded incoming group save, the
/// download commit, and the deletion-journal cleanup saga. The database CAS /
/// journal anti-join stays the correctness authority; this lock orders the
/// surrounding FILE and SECURE-KEY I/O so a cleanup can never interleave with
/// a promotion or key write on the same attachment.
class MediaAttachmentLifecycleLock {
  final Map<String, Future<void>> _tails = <String, Future<void>>{};

  Future<T> synchronized<T>(
    String attachmentId,
    Future<T> Function() action,
  ) async {
    final previous = _tails[attachmentId] ?? Future<void>.value();
    final gate = Completer<void>();
    _tails[attachmentId] = gate.future;
    // A failed predecessor must not poison the queue.
    await previous.catchError((_) {});
    try {
      return await action();
    } finally {
      gate.complete();
      if (identical(_tails[attachmentId], gate.future)) {
        _tails.remove(attachmentId);
      }
    }
  }
}

/// Process-wide instance shared by save/download/cleanup (mirrors
/// [mediaUploadInFlightTracker]'s house style).
final MediaAttachmentLifecycleLock mediaAttachmentLifecycleLock =
    MediaAttachmentLifecycleLock();
