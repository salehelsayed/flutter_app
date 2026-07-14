import 'media_attachment_lifecycle_lock.dart';
import 'private_media_policy.dart';

const Object _privateMediaUnset = Object();

class PrivateMediaLifecycleAttachment {
  const PrivateMediaLifecycleAttachment({
    required this.id,
    required this.messageId,
    required this.storedLocalPath,
    required this.localPath,
    required this.mime,
    required this.size,
    required this.isDownloadComplete,
    required this.isIntegrityEligible,
    this.isDownloadInProgress = false,
  });

  final String id;
  final String messageId;

  /// Exact database value used to prove the lifecycle snapshot and the
  /// current attachment row still describe the same object.
  final String? storedLocalPath;

  /// Canonical, app-owned, existing path verified by the lane adapter.
  final String? localPath;
  final String mime;
  final int size;
  final bool isDownloadComplete;
  final bool isIntegrityEligible;
  final bool isDownloadInProgress;
}

/// Lane-neutral durable lifecycle view consumed by the shared engine.
class PrivateMediaLifecycleTarget {
  const PrivateMediaLifecycleTarget({
    required this.messageId,
    required this.scopeId,
    required this.mode,
    required this.state,
    this.receivedAtMs,
    this.expiresAtMs,
    this.revealedAtMs,
    this.terminalAtMs,
    this.clockHighWaterMs,
    this.hidden = false,
    this.attachments = const [],
  });

  final String messageId;

  /// Lane-defined owner/scope identity (direct contact id, group id, etc.).
  final String scopeId;
  final PrivateMediaMode mode;
  final PrivateMediaLifecycleState state;
  final int? receivedAtMs;
  final int? expiresAtMs;
  final int? revealedAtMs;
  final int? terminalAtMs;
  final int? clockHighWaterMs;
  final bool hidden;
  final List<PrivateMediaLifecycleAttachment> attachments;

  bool get cleanupTerminal => hidden || state.isTerminal;
  bool get hasInterruptedDownload =>
      attachments.any((attachment) => attachment.isDownloadInProgress);

  PrivateMediaLifecycleTarget copyWith({
    PrivateMediaMode? mode,
    PrivateMediaLifecycleState? state,
    Object? receivedAtMs = _privateMediaUnset,
    Object? expiresAtMs = _privateMediaUnset,
    Object? revealedAtMs = _privateMediaUnset,
    Object? terminalAtMs = _privateMediaUnset,
    Object? clockHighWaterMs = _privateMediaUnset,
    bool? hidden,
    List<PrivateMediaLifecycleAttachment>? attachments,
  }) {
    return PrivateMediaLifecycleTarget(
      messageId: messageId,
      scopeId: scopeId,
      mode: mode ?? this.mode,
      state: state ?? this.state,
      receivedAtMs: receivedAtMs == _privateMediaUnset
          ? this.receivedAtMs
          : receivedAtMs as int?,
      expiresAtMs: expiresAtMs == _privateMediaUnset
          ? this.expiresAtMs
          : expiresAtMs as int?,
      revealedAtMs: revealedAtMs == _privateMediaUnset
          ? this.revealedAtMs
          : revealedAtMs as int?,
      terminalAtMs: terminalAtMs == _privateMediaUnset
          ? this.terminalAtMs
          : terminalAtMs as int?,
      clockHighWaterMs: clockHighWaterMs == _privateMediaUnset
          ? this.clockHighWaterMs
          : clockHighWaterMs as int?,
      hidden: hidden ?? this.hidden,
      attachments: attachments ?? this.attachments,
    );
  }
}

/// Lane adapter contract. Direct and future group lanes provide durable CAS,
/// exact owner qualification, and cleanup without leaking repository models
/// into this shared state machine.
abstract class PrivateMediaLifecycleLaneAdapter {
  Future<PrivateMediaLifecycleTarget?> loadTarget(String messageId);

  Future<bool> claimOpening(String messageId, {required int nowMs});

  Future<bool> markViewing(String messageId, {required int nowMs});

  Future<bool> rollbackOpening(String messageId);

  Future<bool> consume(String messageId, {required int nowMs});

  Future<bool> advanceClock(String messageId, {required int nowMs});

  Future<bool> failClosedCorruptState(String messageId, {required int nowMs});

  Future<List<PrivateMediaLifecycleTarget>> loadActiveDisappearing({
    int limit = 100,
  });

  Future<List<PrivateMediaLifecycleTarget>> loadRecoveryCandidates({
    int limit = 100,
  });

  Future<bool> rotateRecoveryCandidate(String messageId, {required int nowMs});

  Future<int?> loadNextExpiryAtMs();

  /// Called only while every exact attachment id is held by the engine's
  /// shared process lock. Implementations must not recursively acquire it.
  Future<void> cleanupTerminalWithinLock(PrivateMediaLifecycleTarget current);
}

/// Optional lane capability for crash-stale download ownership recovery.
abstract class PrivateMediaInterruptedDownloadRecoveryAdapter {
  Future<int> recoverInterruptedDownloadsWithinLock(
    PrivateMediaLifecycleTarget current, {
    required int nowMs,
  });
}

class PrivateMediaOpeningLease {
  PrivateMediaOpeningLease._({
    required this.messageId,
    required this.attachmentId,
    required this.localPath,
  });

  final String messageId;
  final String attachmentId;
  final String localPath;
  final Object _token = Object();
  bool _firstFrameRecorded = false;
  bool _closed = false;
}

class PrivateMediaLifecycleReconcileResult {
  int terminalClaims = 0;
  int cleanupCompleted = 0;
  int retainedAfterError = 0;
  int downloadClaimsRecovered = 0;
}

class PrivateMediaLifecycleEngine {
  PrivateMediaLifecycleEngine({
    required this.adapter,
    required this.lifecycleLock,
    required this.nowMs,
  });

  final PrivateMediaLifecycleLaneAdapter adapter;
  final MediaAttachmentLifecycleLock lifecycleLock;
  final int Function() nowMs;
  final Map<String, PrivateMediaOpeningLease> _activeLeases = {};

  Future<PrivateMediaOpeningLease?> openViewOnce(String messageId) async {
    final initial = await adapter.loadTarget(messageId);
    if (!_isOpenableViewOnce(initial)) return null;
    final attachment = initial!.attachments.single;
    final localPath = attachment.localPath;
    if (!attachment.isDownloadComplete ||
        !attachment.isIntegrityEligible ||
        localPath == null ||
        localPath.isEmpty) {
      return null;
    }

    return lifecycleLock.synchronized(attachment.id, () async {
      final current = await adapter.loadTarget(messageId);
      if (!_isOpenableViewOnce(current)) return null;
      final currentAttachment = current!.attachments.single;
      final currentPath = currentAttachment.localPath;
      if (currentAttachment.id != attachment.id ||
          !currentAttachment.isDownloadComplete ||
          !currentAttachment.isIntegrityEligible ||
          currentPath == null ||
          currentPath.isEmpty) {
        return null;
      }
      if (!await adapter.claimOpening(messageId, nowMs: nowMs())) return null;
      final lease = PrivateMediaOpeningLease._(
        messageId: messageId,
        attachmentId: attachment.id,
        localPath: currentPath,
      );
      _activeLeases[messageId] = lease;
      return lease;
    });
  }

  Future<bool> markFirstFrame(PrivateMediaOpeningLease lease) {
    return lifecycleLock.synchronized(lease.attachmentId, () async {
      if (!_ownsActiveLease(lease) ||
          lease._closed ||
          lease._firstFrameRecorded) {
        return false;
      }
      final current = await adapter.loadTarget(lease.messageId);
      if (current == null ||
          current.hidden ||
          current.mode != PrivateMediaMode.viewOnce ||
          current.state != PrivateMediaLifecycleState.opening) {
        _invalidateLease(lease.messageId);
        return false;
      }
      final updated = await adapter.markViewing(
        lease.messageId,
        nowMs: nowMs(),
      );
      if (updated) lease._firstFrameRecorded = true;
      return updated;
    });
  }

  /// Route-adapter check used after native protection enters and immediately
  /// before any private byte path is handed to a widget. The same in-memory
  /// lease, exact attachment, opening state, and canonical path must survive.
  Future<String?> revalidateOpeningLease(PrivateMediaOpeningLease lease) {
    return lifecycleLock.synchronized(lease.attachmentId, () async {
      if (!_ownsActiveLease(lease) || lease._closed) return null;
      final current = await adapter.loadTarget(lease.messageId);
      if (current == null ||
          current.hidden ||
          current.mode != PrivateMediaMode.viewOnce ||
          current.state != PrivateMediaLifecycleState.opening ||
          current.attachments.length != 1) {
        return null;
      }
      final attachment = current.attachments.single;
      if (attachment.id != lease.attachmentId ||
          !attachment.isDownloadComplete ||
          !attachment.isIntegrityEligible ||
          attachment.localPath != lease.localPath) {
        return null;
      }
      return lease.localPath;
    });
  }

  Future<bool> rollbackPreFirstFrame(PrivateMediaOpeningLease lease) {
    return lifecycleLock.synchronized(lease.attachmentId, () async {
      if (!_ownsActiveLease(lease) ||
          lease._closed ||
          lease._firstFrameRecorded) {
        return false;
      }
      final rolledBack = await adapter.rollbackOpening(lease.messageId);
      if (rolledBack) {
        lease._closed = true;
        _activeLeases.remove(lease.messageId);
      }
      return rolledBack;
    });
  }

  Future<bool> terminalizeViewOnce(PrivateMediaOpeningLease lease) {
    return lifecycleLock.synchronized(lease.attachmentId, () async {
      if (!_ownsActiveLease(lease) || lease._closed) return false;
      final claimed = await adapter.consume(lease.messageId, nowMs: nowMs());
      lease._closed = true;
      _activeLeases.remove(lease.messageId);
      final current = await adapter.loadTarget(lease.messageId);
      if (current != null && current.cleanupTerminal) {
        await adapter.cleanupTerminalWithinLock(current);
      }
      return claimed;
    });
  }

  Future<bool> cleanupTerminalMessage(String messageId) async {
    final target = await adapter.loadTarget(messageId);
    if (target == null || !target.cleanupTerminal) return false;
    return _withAttachmentLocks(target.attachments, () async {
      final current = await adapter.loadTarget(messageId);
      if (current == null || !current.cleanupTerminal) return false;
      await adapter.cleanupTerminalWithinLock(current);
      _invalidateLease(messageId);
      return true;
    });
  }

  Future<PrivateMediaLifecycleReconcileResult> reconcileLocalLifecycle({
    int limit = 100,
  }) async {
    final result = PrivateMediaLifecycleReconcileResult();
    final interrupted = await adapter.loadRecoveryCandidates(limit: limit);
    final downloadRecovery =
        adapter is PrivateMediaInterruptedDownloadRecoveryAdapter
        ? adapter as PrivateMediaInterruptedDownloadRecoveryAdapter
        : null;

    for (final candidate in interrupted) {
      if (downloadRecovery == null ||
          candidate.hidden ||
          candidate.state.isTerminal ||
          !candidate.hasInterruptedDownload) {
        continue;
      }
      try {
        await _withAttachmentLocks(candidate.attachments, () async {
          final current = await adapter.loadTarget(candidate.messageId);
          if (current == null ||
              current.hidden ||
              current.state.isTerminal ||
              !current.hasInterruptedDownload) {
            return;
          }
          result.downloadClaimsRecovered += await downloadRecovery
              .recoverInterruptedDownloadsWithinLock(current, nowMs: nowMs());
        });
      } catch (_) {
        result.retainedAfterError++;
        await _rotateRecoveryCandidate(candidate.messageId);
      }
    }

    // First persist every interrupted/corrupt terminal claim. Cleanup is a
    // separate pass so every destructive action observes durable authority.
    for (final candidate in interrupted) {
      if (candidate.hidden || candidate.state.isTerminal) continue;
      if (candidate.state != PrivateMediaLifecycleState.opening &&
          candidate.state != PrivateMediaLifecycleState.viewing) {
        continue;
      }
      try {
        await _withAttachmentLocks(candidate.attachments, () async {
          final current = await adapter.loadTarget(candidate.messageId);
          if (current == null || current.hidden || current.state.isTerminal) {
            return;
          }
          final bool claimed;
          if (current.mode == PrivateMediaMode.viewOnce) {
            claimed = await adapter.consume(current.messageId, nowMs: nowMs());
          } else {
            claimed = await adapter.failClosedCorruptState(
              current.messageId,
              nowMs: nowMs(),
            );
          }
          if (claimed) result.terminalClaims++;
          _invalidateLease(current.messageId);
        });
      } catch (_) {
        result.retainedAfterError++;
        await _rotateRecoveryCandidate(candidate.messageId);
      }
    }

    final expiry = await sweepExpiries(limit: limit, cleanup: false);
    result.terminalClaims += expiry.terminalClaims;
    result.retainedAfterError += expiry.retainedAfterError;

    final cleanupCandidates = await adapter.loadRecoveryCandidates(
      limit: limit,
    );
    for (final candidate in cleanupCandidates) {
      if (!candidate.cleanupTerminal) continue;
      try {
        await _withAttachmentLocks(candidate.attachments, () async {
          final current = await adapter.loadTarget(candidate.messageId);
          if (current == null || !current.cleanupTerminal) return;
          await adapter.cleanupTerminalWithinLock(current);
          result.cleanupCompleted++;
          _invalidateLease(current.messageId);
        });
      } catch (_) {
        result.retainedAfterError++;
        await _rotateRecoveryCandidate(candidate.messageId);
      }
    }
    return result;
  }

  Future<PrivateMediaLifecycleReconcileResult> sweepExpiries({
    int limit = 100,
    bool cleanup = true,
    int? evaluationFloorMs,
  }) async {
    final result = PrivateMediaLifecycleReconcileResult();
    final sampledNowMs = nowMs();
    final evaluationNowMs =
        evaluationFloorMs != null && evaluationFloorMs > sampledNowMs
        ? evaluationFloorMs
        : sampledNowMs;
    final candidates = await adapter.loadActiveDisappearing(limit: limit);
    for (final candidate in candidates) {
      try {
        await _withAttachmentLocks(candidate.attachments, () async {
          final before = await adapter.loadTarget(candidate.messageId);
          if (before == null ||
              before.hidden ||
              before.mode != PrivateMediaMode.disappearing ||
              before.state.isTerminal) {
            return;
          }
          await adapter.advanceClock(before.messageId, nowMs: evaluationNowMs);
          final after = await adapter.loadTarget(before.messageId);
          if (after != null &&
              after.state == PrivateMediaLifecycleState.expired) {
            if (before.state != PrivateMediaLifecycleState.expired) {
              result.terminalClaims++;
            }
            if (cleanup) {
              await adapter.cleanupTerminalWithinLock(after);
              result.cleanupCompleted++;
            }
            _invalidateLease(after.messageId);
          }
        });
      } catch (_) {
        result.retainedAfterError++;
      }
    }
    return result;
  }

  Future<int?> loadNextExpiryAtMs() => adapter.loadNextExpiryAtMs();

  Future<void> _rotateRecoveryCandidate(String messageId) async {
    try {
      await adapter.rotateRecoveryCandidate(messageId, nowMs: nowMs());
    } catch (_) {
      // The original residue remains retryable; rotation is fairness metadata,
      // never authority for destructive cleanup.
    }
  }

  bool _ownsActiveLease(PrivateMediaOpeningLease lease) {
    final active = _activeLeases[lease.messageId];
    return identical(active, lease) && identical(active?._token, lease._token);
  }

  void _invalidateLease(String messageId) {
    final lease = _activeLeases.remove(messageId);
    if (lease != null) lease._closed = true;
  }

  bool _isOpenableViewOnce(PrivateMediaLifecycleTarget? target) {
    return target != null &&
        !target.hidden &&
        target.mode == PrivateMediaMode.viewOnce &&
        target.state == PrivateMediaLifecycleState.available &&
        target.attachments.length == 1;
  }

  Future<T> _withAttachmentLocks<T>(
    Iterable<PrivateMediaLifecycleAttachment> attachments,
    Future<T> Function() action,
  ) {
    final ids = attachments.map((item) => item.id).toSet().toList()..sort();
    Future<T> acquire(int index) {
      if (index >= ids.length) return action();
      return lifecycleLock.synchronized(ids[index], () => acquire(index + 1));
    }

    return acquire(0);
  }
}
