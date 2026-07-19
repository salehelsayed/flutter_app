import 'media_attachment_lifecycle_lock.dart';
import 'private_media_policy.dart';

const Object _privateMediaUnset = Object();

/// Durable direction is part of private-media lifecycle authority.
///
/// Incoming View Once and outgoing sender one-more-look rows use different
/// policy lanes even when their persisted mode is the same.
enum PrivateMediaDirection { incoming, outgoing }

enum PrivateMediaLifecycleSettlementIntent { rollbackPreFrame, terminalize }

enum PrivateMediaLifecycleSettlementDisposition {
  rolledBackAvailable,
  terminalized,
  lostRollbackRace,
  indeterminateFailClosed,
}

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
    this.direction = PrivateMediaDirection.incoming,
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
  final PrivateMediaDirection direction;
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
    PrivateMediaDirection? direction,
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
      direction: direction ?? this.direction,
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

  Future<bool> claimOpening(
    PrivateMediaOpeningLeaseIdentity identity, {
    required int nowMs,
  });

  Future<bool> markViewing(
    PrivateMediaOpeningLeaseIdentity identity, {
    required int nowMs,
  });

  Future<bool> rollbackOpening(PrivateMediaOpeningLeaseIdentity identity);

  /// Exact active-lease terminal transition. Recovery uses [consume] because
  /// no same-process lease survives a restart.
  Future<bool> consumeOpening(
    PrivateMediaOpeningLeaseIdentity identity, {
    required int nowMs,
  });

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

/// Optional exact-CAS capability used only when terminalization throws after
/// an authoritative reread still proves the original row `available`.
///
/// Implementations must qualify every field, including the stored path, and
/// are called while the engine already owns the attachment lifecycle lock.
abstract class PrivateMediaIndeterminateQuarantineAdapter {
  Future<bool> quarantineIndeterminateAvailable(
    PrivateMediaOpeningLeaseIdentity identity, {
    required int nowMs,
  });
}

/// Optional lane capability for crash-stale download ownership recovery.
abstract class PrivateMediaInterruptedDownloadRecoveryAdapter {
  Future<int> recoverInterruptedDownloadsWithinLock(
    PrivateMediaLifecycleTarget current, {
    required int nowMs,
  });
}

class PrivateMediaOpeningLeaseIdentity {
  const PrivateMediaOpeningLeaseIdentity({
    required this.messageId,
    required this.direction,
    required this.mode,
    required this.attachmentId,
    required this.storedLocalPath,
    required this.localPath,
  });

  final String messageId;
  final PrivateMediaDirection direction;
  final PrivateMediaMode mode;
  final String attachmentId;
  final String storedLocalPath;
  final String localPath;
}

class PrivateMediaOpeningLease {
  PrivateMediaOpeningLease._({required this.identity});

  final PrivateMediaOpeningLeaseIdentity identity;
  String get messageId => identity.messageId;
  PrivateMediaDirection get direction => identity.direction;
  PrivateMediaMode get mode => identity.mode;
  String get attachmentId => identity.attachmentId;
  String get storedLocalPath => identity.storedLocalPath;
  String get localPath => identity.localPath;
  final Object _token = Object();
  bool _firstFrameRecorded = false;
  bool _closed = false;
  PrivateMediaLifecycleSettlementDisposition? _settlementDisposition;
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

  /// Claims the one-shot lifecycle lane for either incoming View Once or the
  /// sender-only one-more-look contract (outgoing protected/View Once).
  Future<PrivateMediaOpeningLease?> openOneShot(String messageId) async {
    final initial = await adapter.loadTarget(messageId);
    if (!_isOpenableOneShot(initial)) return null;
    final attachment = initial!.attachments.single;
    final localPath = attachment.localPath;
    final storedLocalPath = attachment.storedLocalPath;
    if (!attachment.isDownloadComplete ||
        !attachment.isIntegrityEligible ||
        storedLocalPath == null ||
        storedLocalPath.isEmpty ||
        localPath == null ||
        localPath.isEmpty) {
      return null;
    }

    return lifecycleLock.synchronized(attachment.id, () async {
      final current = await adapter.loadTarget(messageId);
      if (!_isOpenableOneShot(current)) return null;
      final currentAttachment = current!.attachments.single;
      final currentPath = currentAttachment.localPath;
      final currentStoredPath = currentAttachment.storedLocalPath;
      if (currentAttachment.id != attachment.id ||
          current.direction != initial.direction ||
          current.mode != initial.mode ||
          !currentAttachment.isDownloadComplete ||
          !currentAttachment.isIntegrityEligible ||
          currentStoredPath == null ||
          currentStoredPath != storedLocalPath ||
          currentPath == null ||
          currentPath.isEmpty) {
        return null;
      }
      final identity = PrivateMediaOpeningLeaseIdentity(
        messageId: messageId,
        direction: current.direction,
        mode: current.mode,
        attachmentId: attachment.id,
        storedLocalPath: currentStoredPath,
        localPath: currentPath,
      );
      if (!await adapter.claimOpening(identity, nowMs: nowMs())) return null;
      final lease = PrivateMediaOpeningLease._(identity: identity);
      _activeLeases[messageId] = lease;
      return lease;
    });
  }

  /// Compatibility name retained for existing engine-tier callers. Direction
  /// and mode are still requalified by [openOneShot].
  Future<PrivateMediaOpeningLease?> openViewOnce(String messageId) =>
      openOneShot(messageId);

  Future<bool> markFirstFrame(PrivateMediaOpeningLease lease) {
    return lifecycleLock.synchronized(lease.attachmentId, () async {
      if (!_ownsActiveLease(lease) ||
          lease._closed ||
          lease._firstFrameRecorded) {
        return false;
      }
      final current = await adapter.loadTarget(lease.messageId);
      if (!_matchesLease(
        current,
        lease,
        expectedStates: const <PrivateMediaLifecycleState>{
          PrivateMediaLifecycleState.opening,
        },
      )) {
        _invalidateLease(lease.messageId);
        return false;
      }
      final updated = await adapter.markViewing(lease.identity, nowMs: nowMs());
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
      if (!_matchesLease(
        current,
        lease,
        expectedStates: const <PrivateMediaLifecycleState>{
          PrivateMediaLifecycleState.opening,
        },
      )) {
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
      final rolledBack = await adapter.rollbackOpening(lease.identity);
      if (rolledBack) {
        lease._closed = true;
        _activeLeases.remove(lease.messageId);
      }
      return rolledBack;
    });
  }

  Future<bool> terminalizeViewOnce(PrivateMediaOpeningLease lease) {
    return settleOpeningLease(
      lease,
      intent: PrivateMediaLifecycleSettlementIntent.terminalize,
    ).then(
      (disposition) =>
          disposition ==
          PrivateMediaLifecycleSettlementDisposition.terminalized,
    );
  }

  /// Performs the complete rollback/terminalize decision, operation-aware
  /// reread, exact quarantine, terminal retry, and cleanup while holding one
  /// attachment lifecycle lock. The lease caches the result so a repeated
  /// settlement cannot perform another durable transition.
  Future<PrivateMediaLifecycleSettlementDisposition> settleOpeningLease(
    PrivateMediaOpeningLease lease, {
    required PrivateMediaLifecycleSettlementIntent intent,
  }) {
    final cached = lease._settlementDisposition;
    if (cached != null) return Future.value(cached);
    return lifecycleLock.synchronized(lease.attachmentId, () async {
      final insideCached = lease._settlementDisposition;
      if (insideCached != null) return insideCached;
      if (!_ownsActiveLease(lease) || lease._closed) {
        return _cacheSettlement(
          lease,
          PrivateMediaLifecycleSettlementDisposition.indeterminateFailClosed,
        );
      }
      if (intent == PrivateMediaLifecycleSettlementIntent.rollbackPreFrame &&
          !lease._firstFrameRecorded) {
        return _rollbackWithinLock(lease);
      }
      return _terminalizeWithinLock(lease);
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
          if (_requiresOpeningLease(current)) {
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

  bool _isOpenableOneShot(PrivateMediaLifecycleTarget? target) {
    return target != null &&
        !target.hidden &&
        _requiresOpeningLease(target) &&
        target.state == PrivateMediaLifecycleState.available &&
        target.attachments.length == 1;
  }

  bool _requiresOpeningLease(PrivateMediaLifecycleTarget target) {
    return switch (target.direction) {
      PrivateMediaDirection.incoming =>
        target.mode == PrivateMediaMode.viewOnce,
      PrivateMediaDirection.outgoing =>
        target.mode == PrivateMediaMode.protected ||
            target.mode == PrivateMediaMode.viewOnce,
    };
  }

  bool _matchesLease(
    PrivateMediaLifecycleTarget? target,
    PrivateMediaOpeningLease lease, {
    required Set<PrivateMediaLifecycleState> expectedStates,
    bool allowCleanedTerminal = false,
  }) {
    if (target == null ||
        target.hidden ||
        target.messageId != lease.messageId ||
        target.direction != lease.direction ||
        target.mode != lease.mode ||
        !expectedStates.contains(target.state)) {
      return false;
    }
    if (allowCleanedTerminal &&
        target.state.isTerminal &&
        target.attachments.isEmpty) {
      return true;
    }
    if (target.attachments.length != 1) return false;
    final attachment = target.attachments.single;
    return attachment.id == lease.attachmentId &&
        attachment.messageId == lease.messageId &&
        attachment.storedLocalPath == lease.storedLocalPath &&
        attachment.localPath == lease.localPath &&
        attachment.isDownloadComplete &&
        attachment.isIntegrityEligible;
  }

  Future<PrivateMediaLifecycleSettlementDisposition> _rollbackWithinLock(
    PrivateMediaOpeningLease lease,
  ) async {
    final before = await _loadTargetSafely(lease.messageId);
    if (!_matchesLease(
      before,
      lease,
      expectedStates: const <PrivateMediaLifecycleState>{
        PrivateMediaLifecycleState.opening,
      },
    )) {
      return _cacheSettlement(
        lease,
        PrivateMediaLifecycleSettlementDisposition.lostRollbackRace,
      );
    }
    try {
      final rolledBack = await adapter.rollbackOpening(lease.identity);
      if (rolledBack) {
        return _cacheSettlement(
          lease,
          PrivateMediaLifecycleSettlementDisposition.rolledBackAvailable,
        );
      }
    } catch (_) {
      // The operation-aware reread below is authoritative. In particular, an
      // exact available row is safe only after rollback intent, never after a
      // failed terminalization attempt.
    }
    final current = await _loadTargetSafely(lease.messageId);
    if (_matchesLease(
      current,
      lease,
      expectedStates: const <PrivateMediaLifecycleState>{
        PrivateMediaLifecycleState.available,
      },
    )) {
      return _cacheSettlement(
        lease,
        PrivateMediaLifecycleSettlementDisposition.rolledBackAvailable,
      );
    }
    return _cacheSettlement(
      lease,
      PrivateMediaLifecycleSettlementDisposition.lostRollbackRace,
    );
  }

  Future<PrivateMediaLifecycleSettlementDisposition> _terminalizeWithinLock(
    PrivateMediaOpeningLease lease,
  ) async {
    final before = await _loadTargetSafely(lease.messageId);
    if (_isExactTerminal(before, lease)) {
      await _cleanupTerminalBestEffort(before!);
      return _cacheSettlement(
        lease,
        PrivateMediaLifecycleSettlementDisposition.terminalized,
      );
    }
    if (!_matchesLease(
      before,
      lease,
      expectedStates: const <PrivateMediaLifecycleState>{
        PrivateMediaLifecycleState.opening,
        PrivateMediaLifecycleState.viewing,
      },
    )) {
      return _cacheSettlement(
        lease,
        PrivateMediaLifecycleSettlementDisposition.indeterminateFailClosed,
      );
    }
    try {
      await adapter.consumeOpening(lease.identity, nowMs: nowMs());
    } catch (_) {}

    var current = await _loadTargetSafely(lease.messageId);
    if (_isExactTerminal(current, lease)) {
      await _cleanupTerminalBestEffort(current!);
      return _cacheSettlement(
        lease,
        PrivateMediaLifecycleSettlementDisposition.terminalized,
      );
    }

    final exactAvailable = _matchesLease(
      current,
      lease,
      expectedStates: const <PrivateMediaLifecycleState>{
        PrivateMediaLifecycleState.available,
      },
    );
    if (exactAvailable) {
      final quarantine = adapter is PrivateMediaIndeterminateQuarantineAdapter
          ? adapter as PrivateMediaIndeterminateQuarantineAdapter
          : null;
      if (quarantine == null) {
        return _cacheSettlement(
          lease,
          PrivateMediaLifecycleSettlementDisposition.indeterminateFailClosed,
        );
      }
      var quarantined = false;
      try {
        quarantined = await quarantine.quarantineIndeterminateAvailable(
          lease.identity,
          nowMs: nowMs(),
        );
      } catch (_) {
        quarantined = false;
      }
      current = await _loadTargetSafely(lease.messageId);
      if (_isExactTerminal(current, lease)) {
        await _cleanupTerminalBestEffort(current!);
        return _cacheSettlement(
          lease,
          PrivateMediaLifecycleSettlementDisposition.terminalized,
        );
      }
      final alreadyQuarantined = _matchesLease(
        current,
        lease,
        expectedStates: const <PrivateMediaLifecycleState>{
          PrivateMediaLifecycleState.opening,
        },
      );
      if (!quarantined && !alreadyQuarantined) {
        return _cacheSettlement(
          lease,
          PrivateMediaLifecycleSettlementDisposition.indeterminateFailClosed,
        );
      }
    } else {
      final exactQuarantined = _matchesLease(
        current,
        lease,
        expectedStates: const <PrivateMediaLifecycleState>{
          PrivateMediaLifecycleState.opening,
          PrivateMediaLifecycleState.viewing,
        },
      );
      if (!exactQuarantined) {
        return _cacheSettlement(
          lease,
          PrivateMediaLifecycleSettlementDisposition.indeterminateFailClosed,
        );
      }
    }

    // A terminalization throw/false result that left an exact available row
    // has now been quarantined back to `opening`. Retry once under the same
    // lifecycle lock. If persistence remains uncertain, retain that opening
    // row for the existing startup/resume reconciler.
    try {
      await adapter.consumeOpening(lease.identity, nowMs: nowMs());
    } catch (_) {}
    current = await _loadTargetSafely(lease.messageId);
    if (_isExactTerminal(current, lease)) {
      await _cleanupTerminalBestEffort(current!);
      return _cacheSettlement(
        lease,
        PrivateMediaLifecycleSettlementDisposition.terminalized,
      );
    }
    return _cacheSettlement(
      lease,
      PrivateMediaLifecycleSettlementDisposition.indeterminateFailClosed,
    );
  }

  bool _isExactTerminal(
    PrivateMediaLifecycleTarget? current,
    PrivateMediaOpeningLease lease,
  ) {
    if (current == null || !current.state.isTerminal) return false;
    return _matchesLease(
      current,
      lease,
      expectedStates: <PrivateMediaLifecycleState>{current.state},
      allowCleanedTerminal: true,
    );
  }

  Future<PrivateMediaLifecycleTarget?> _loadTargetSafely(
    String messageId,
  ) async {
    try {
      return await adapter.loadTarget(messageId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _cleanupTerminalBestEffort(
    PrivateMediaLifecycleTarget current,
  ) async {
    if (!current.cleanupTerminal || current.attachments.isEmpty) return;
    try {
      await adapter.cleanupTerminalWithinLock(current);
    } catch (_) {
      // The durable terminal row remains authoritative and the ordinary
      // reconciler retains responsibility for residual cleanup.
    }
  }

  PrivateMediaLifecycleSettlementDisposition _cacheSettlement(
    PrivateMediaOpeningLease lease,
    PrivateMediaLifecycleSettlementDisposition disposition,
  ) {
    lease._settlementDisposition ??= disposition;
    lease._closed = true;
    _activeLeases.remove(lease.messageId);
    return lease._settlementDisposition!;
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
