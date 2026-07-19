import 'dart:async';

import 'package:flutter_app/core/constants/retry_constants.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/private_media_lifecycle_engine.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/media/private_media_protection_coordinator.dart';
import 'package:flutter_app/features/conversation/application/private_media_action_eligibility.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/shared/widgets/media/media_viewer_item.dart';

class DirectPrivateMediaViewerIdentity {
  const DirectPrivateMediaViewerIdentity({
    required this.messageId,
    required this.attachmentId,
  });

  final String messageId;
  final String attachmentId;

  @override
  bool operator ==(Object other) =>
      other is DirectPrivateMediaViewerIdentity &&
      other.messageId == messageId &&
      other.attachmentId == attachmentId;

  @override
  int get hashCode => Object.hash(messageId, attachmentId);

  @override
  String toString() => 'DirectPrivateMediaViewerIdentity(redacted)';
}

class DirectPrivateMediaCurrentRows {
  const DirectPrivateMediaCurrentRows({
    required this.parent,
    required this.attachment,
  });

  final ConversationMessage? parent;
  final MediaAttachment? attachment;
}

typedef DirectPrivateMediaCurrentRowsLoader =
    Future<DirectPrivateMediaCurrentRows> Function(
      DirectPrivateMediaViewerIdentity identity,
    );

enum DirectPrivateMediaContinuityState {
  valid,
  routeInvalidated,
  appLifecycleInvalidated,
}

/// Operation-bound classifier captured before a private open starts.
/// Production wiring compares both monotonic generations and gives app
/// lifecycle invalidation precedence when route and lifecycle both changed.
abstract interface class DirectPrivateMediaContinuityGuard {
  DirectPrivateMediaContinuityState get state;
}

class DirectPrivateMediaAlwaysValidContinuityGuard
    implements DirectPrivateMediaContinuityGuard {
  const DirectPrivateMediaAlwaysValidContinuityGuard();

  @override
  DirectPrivateMediaContinuityState get state =>
      DirectPrivateMediaContinuityState.valid;
}

enum DirectPrivateMediaPrepareFailureReason {
  disposed,
  invalidIdentity,
  routeContinuityLost,
  appLifecycleContinuityLost,
  notEligible,
  localAuthorityMissing,
  leaseUnavailable,
  protectionEnterFailed,
  protectionIncident,
  revalidationFailed,
  unsupportedMediaKind,
  unexpectedFailure,
}

enum DirectPrivateMediaExitReason {
  close,
  routePushFailure,
  routeContinuityLoss,
  appLifecycleLoss,
  protectionEnterFailure,
  revalidationFailure,
  background,
  capture,
  expiry,
  postFrameFailure,
  preFrameDecodeFailure,
  dispose,
}

enum DirectPrivateMediaSettleDisposition {
  rolledBackAvailable,
  terminalized,
  lostRollbackRace,
  noLease,
  indeterminateFailClosed,
}

class DirectPrivateMediaSettleResult {
  const DirectPrivateMediaSettleResult({
    required this.disposition,
    required this.exitReason,
    required this.firstFrameRecorded,
  });

  final DirectPrivateMediaSettleDisposition disposition;
  final DirectPrivateMediaExitReason exitReason;
  final bool firstFrameRecorded;
}

class DirectPrivateMediaPrepareResult {
  const DirectPrivateMediaPrepareResult._({
    required this.grant,
    required this.failureReason,
    required this.settleResult,
  });

  const DirectPrivateMediaPrepareResult.granted(
    DirectPrivateMediaViewerGrant grant,
  ) : this._(grant: grant, failureReason: null, settleResult: null);

  const DirectPrivateMediaPrepareResult.failed(
    DirectPrivateMediaPrepareFailureReason reason, {
    DirectPrivateMediaSettleResult? settleResult,
  }) : this._(grant: null, failureReason: reason, settleResult: settleResult);

  final DirectPrivateMediaViewerGrant? grant;
  final DirectPrivateMediaPrepareFailureReason? failureReason;
  final DirectPrivateMediaSettleResult? settleResult;

  bool get isGranted => grant != null;
}

enum DirectPrivateMediaOpenFailureReason {
  prepareFailed,
  routePushFailure,
  preFrameFailure,
  lifecycleInterrupted,
  authorityLost,
}

class DirectPrivateMediaOpenResult {
  const DirectPrivateMediaOpenResult._({
    required this.wasDisplayed,
    required this.failureReason,
    required this.settleResult,
    required this.canRetry,
  });

  const DirectPrivateMediaOpenResult.displayed(
    DirectPrivateMediaSettleResult settleResult,
  ) : this._(
        wasDisplayed: true,
        failureReason: null,
        settleResult: settleResult,
        canRetry: false,
      );

  const DirectPrivateMediaOpenResult.failed(
    DirectPrivateMediaOpenFailureReason reason, {
    DirectPrivateMediaSettleResult? settleResult,
    required bool canRetry,
  }) : this._(
         wasDisplayed: false,
         failureReason: reason,
         settleResult: settleResult,
         canRetry: canRetry,
       );

  final bool wasDisplayed;
  final DirectPrivateMediaOpenFailureReason? failureReason;
  final DirectPrivateMediaSettleResult? settleResult;
  final bool canRetry;
}

class DirectPrivateMediaViewerGrant {
  DirectPrivateMediaViewerGrant._({
    required this.identity,
    required this.direction,
    required this.mode,
    required this.kind,
    required this.localPath,
    required this.protectionOwner,
    required int? expiresAtMs,
    required PrivateMediaOpeningLease? openingLease,
  }) : _openingLease = openingLease,
       _expiresAtMs = expiresAtMs;

  final DirectPrivateMediaViewerIdentity identity;
  final PrivateMediaDirection direction;
  final PrivateMediaMode mode;
  final MediaViewerKind kind;
  final String localPath;
  final PrivateMediaProtectionOwner protectionOwner;
  final PrivateMediaOpeningLease? _openingLease;
  final int? _expiresAtMs;
  final Completer<void> _protectionReleasedCompleter = Completer<void>();
  Timer? _expiryTimer;
  bool _firstFrameRecorded = false;
  bool _lifecycleSettled = false;
  bool _protectionReleased = false;
  DirectPrivateMediaSettleResult? _settleResult;
  Future<DirectPrivateMediaSettleResult>? _settleOperation;

  bool get canEnterPictureInPicture => false;
  bool get settled => _lifecycleSettled;
  bool get protectionReleased => _protectionReleased;
  bool get firstFrameRecorded => _firstFrameRecorded;
  DirectPrivateMediaSettleResult? get settleResult => _settleResult;

  @override
  String toString() => 'DirectPrivateMediaViewerGrant(redacted)';
}

/// Direct-only route authority. It performs both current-row reads around the
/// native enter boundary, owns the Session-03 View Once lease, and never
/// accepts a caller path, MIME, policy boolean, or stale message snapshot.
class DirectPrivateMediaViewerController {
  DirectPrivateMediaViewerController({
    required this.loadCurrentRows,
    required this.lifecycleEngine,
    required this.protectionCoordinator,
    this.disposeProtectionCoordinator = true,
  }) {
    _protectionSubscription = protectionCoordinator.events.listen(
      _forwardProtectionEvent,
      onError: (_, _) =>
          _forwardProtectionEvent(PrivateMediaProtectionEvent.channelFailure),
      onDone: () =>
          _forwardProtectionEvent(PrivateMediaProtectionEvent.channelFailure),
    );
  }

  final DirectPrivateMediaCurrentRowsLoader loadCurrentRows;
  final PrivateMediaLifecycleEngine lifecycleEngine;
  final PrivateMediaProtectionCoordinator protectionCoordinator;
  final bool disposeProtectionCoordinator;
  final _routeEventController =
      StreamController<PrivateMediaProtectionEvent>.broadcast(sync: true);
  final Set<DirectPrivateMediaViewerGrant> _activeGrants = {};
  late final StreamSubscription<PrivateMediaProtectionEvent>
  _protectionSubscription;
  bool _disposeRequested = false;
  Future<void>? _disposeOperation;
  final Map<
    DirectPrivateMediaViewerIdentity,
    Future<DirectPrivateMediaPrepareResult>
  >
  _preparing = {};

  Stream<PrivateMediaProtectionEvent> get protectionEvents =>
      _routeEventController.stream;

  PrivateMediaProtectionEvent? get latchedProtectionEvent =>
      protectionCoordinator.latchedCriticalEvent;

  /// Compatibility adapter for callers that have not yet adopted the typed
  /// route result. New production wiring uses [prepareResult] with a captured
  /// continuity guard.
  Future<DirectPrivateMediaViewerGrant?> prepare(
    DirectPrivateMediaViewerIdentity identity,
  ) async {
    final result = await prepareResult(
      identity,
      const DirectPrivateMediaAlwaysValidContinuityGuard(),
    );
    return result.grant;
  }

  Future<DirectPrivateMediaPrepareResult> prepareResult(
    DirectPrivateMediaViewerIdentity identity,
    DirectPrivateMediaContinuityGuard continuityGuard,
  ) {
    if (_disposeRequested) {
      return Future.value(
        const DirectPrivateMediaPrepareResult.failed(
          DirectPrivateMediaPrepareFailureReason.disposed,
        ),
      );
    }
    final existing = _preparing[identity];
    if (existing != null) return existing;
    final operation = _prepareResult(identity, continuityGuard);
    _preparing[identity] = operation;
    return operation.whenComplete(() => _preparing.remove(identity));
  }

  Future<DirectPrivateMediaPrepareResult> _prepareResult(
    DirectPrivateMediaViewerIdentity identity,
    DirectPrivateMediaContinuityGuard continuityGuard,
  ) async {
    if (identity.messageId.trim().isEmpty ||
        identity.attachmentId.trim().isEmpty) {
      return const DirectPrivateMediaPrepareResult.failed(
        DirectPrivateMediaPrepareFailureReason.invalidIdentity,
      );
    }
    PrivateMediaOpeningLease? openingLease;
    PrivateMediaProtectionOwner? protectionOwner;
    DirectPrivateMediaSettleResult? unpublishedSettlement;
    var grantPublished = false;

    Future<DirectPrivateMediaPrepareResult?> continuityFailure() async {
      final state = continuityGuard.state;
      if (state == DirectPrivateMediaContinuityState.valid) return null;
      final appLifecycle =
          state == DirectPrivateMediaContinuityState.appLifecycleInvalidated;
      if (openingLease != null && unpublishedSettlement == null) {
        unpublishedSettlement = await _settleUnpublishedLease(
          openingLease,
          appLifecycle
              ? DirectPrivateMediaExitReason.appLifecycleLoss
              : DirectPrivateMediaExitReason.routeContinuityLoss,
          terminalize: appLifecycle,
        );
      }
      return DirectPrivateMediaPrepareResult.failed(
        appLifecycle
            ? DirectPrivateMediaPrepareFailureReason.appLifecycleContinuityLost
            : DirectPrivateMediaPrepareFailureReason.routeContinuityLost,
        settleResult: unpublishedSettlement,
      );
    }

    Future<DirectPrivateMediaPrepareResult> failed(
      DirectPrivateMediaPrepareFailureReason reason, {
      DirectPrivateMediaExitReason? exitReason,
      bool terminalize = false,
    }) async {
      if (openingLease != null && unpublishedSettlement == null) {
        unpublishedSettlement = await _settleUnpublishedLease(
          openingLease,
          exitReason ?? DirectPrivateMediaExitReason.revalidationFailure,
          terminalize: terminalize,
        );
      }
      return DirectPrivateMediaPrepareResult.failed(
        reason,
        settleResult: unpublishedSettlement,
      );
    }

    try {
      final beforeQualification = await continuityFailure();
      if (beforeQualification != null) return beforeQualification;
      final initial = await _qualifyRows(identity);
      final afterInitialRows = await continuityFailure();
      if (afterInitialRows != null) return afterInitialRows;
      if (initial == null ||
          !initial.decision.allows(DirectPrivateMediaAction.openInApp)) {
        return failed(DirectPrivateMediaPrepareFailureReason.notEligible);
      }
      final initialTarget = await _loadExactTarget(identity, initial);
      final afterInitialTarget = await continuityFailure();
      if (afterInitialTarget != null) return afterInitialTarget;
      if (initialTarget == null) {
        return failed(
          DirectPrivateMediaPrepareFailureReason.localAuthorityMissing,
        );
      }
      final initialKind = _qualifiedMediaKind(initial.rows.attachment!);
      if (initialKind == null) {
        return failed(
          DirectPrivateMediaPrepareFailureReason.unsupportedMediaKind,
        );
      }
      final initialPath = _openableTargetPath(initialTarget, identity);
      if (initialPath == null ||
          initialTarget.state != PrivateMediaLifecycleState.available) {
        return failed(
          DirectPrivateMediaPrepareFailureReason.localAuthorityMissing,
        );
      }

      final String authorizedPath;
      if (_requiresOpeningLease(initialTarget)) {
        final beforeLease = await continuityFailure();
        if (beforeLease != null) return beforeLease;
        openingLease = await lifecycleEngine.openOneShot(identity.messageId);
        final afterLease = await continuityFailure();
        if (afterLease != null) return afterLease;
        if (openingLease == null) {
          return failed(
            DirectPrivateMediaPrepareFailureReason.leaseUnavailable,
          );
        }
        if (openingLease.attachmentId != identity.attachmentId ||
            openingLease.direction != initialTarget.direction ||
            openingLease.mode != initialTarget.mode ||
            openingLease.localPath != initialPath) {
          return failed(
            DirectPrivateMediaPrepareFailureReason.revalidationFailed,
            exitReason: DirectPrivateMediaExitReason.revalidationFailure,
          );
        }
        authorizedPath = openingLease.localPath;
      } else {
        if (initialTarget.direction != PrivateMediaDirection.incoming ||
            (initialTarget.mode != PrivateMediaMode.protected &&
                initialTarget.mode != PrivateMediaMode.disappearing)) {
          return failed(DirectPrivateMediaPrepareFailureReason.notEligible);
        }
        authorizedPath = initialPath;
      }

      final beforeProtection = await continuityFailure();
      if (beforeProtection != null) return beforeProtection;
      protectionOwner = await protectionCoordinator.enter();
      final afterProtection = await continuityFailure();
      if (afterProtection != null) return afterProtection;
      if (protectionOwner == null ||
          protectionCoordinator.latchedCriticalEvent != null) {
        return failed(
          protectionOwner == null
              ? DirectPrivateMediaPrepareFailureReason.protectionEnterFailed
              : DirectPrivateMediaPrepareFailureReason.protectionIncident,
          exitReason: DirectPrivateMediaExitReason.protectionEnterFailure,
        );
      }

      if (initialTarget.mode == PrivateMediaMode.disappearing) {
        await lifecycleEngine.lifecycleLock.synchronized(
          identity.attachmentId,
          () => lifecycleEngine.adapter.advanceClock(
            identity.messageId,
            nowMs: lifecycleEngine.nowMs(),
          ),
        );
        final afterClock = await continuityFailure();
        if (afterClock != null) return afterClock;
      }
      final current = await _qualifyRows(identity);
      final afterCurrentRows = await continuityFailure();
      if (afterCurrentRows != null) return afterCurrentRows;
      if (current == null ||
          !current.decision.allows(DirectPrivateMediaAction.openInApp)) {
        if (initialTarget.mode == PrivateMediaMode.disappearing) {
          await _cleanupTerminalSafely(identity.messageId);
        }
        return failed(
          DirectPrivateMediaPrepareFailureReason.revalidationFailed,
          exitReason: DirectPrivateMediaExitReason.revalidationFailure,
        );
      }
      final currentTarget = await _loadExactTarget(identity, current);
      final afterCurrentTarget = await continuityFailure();
      if (afterCurrentTarget != null) return afterCurrentTarget;
      if (currentTarget == null ||
          currentTarget.mode != initialTarget.mode ||
          currentTarget.direction != initialTarget.direction) {
        return failed(
          DirectPrivateMediaPrepareFailureReason.revalidationFailed,
          exitReason: DirectPrivateMediaExitReason.revalidationFailure,
        );
      }

      final String? currentPath;
      if (openingLease != null) {
        currentPath = await lifecycleEngine.revalidateOpeningLease(
          openingLease,
        );
        final afterLeaseRevalidation = await continuityFailure();
        if (afterLeaseRevalidation != null) return afterLeaseRevalidation;
      } else {
        currentPath = _openableTargetPath(currentTarget, identity);
      }
      if (currentPath == null ||
          currentPath != authorizedPath ||
          (openingLease == null &&
              currentTarget.state != PrivateMediaLifecycleState.available)) {
        if (openingLease == null && currentTarget.cleanupTerminal) {
          await _cleanupTerminalSafely(identity.messageId);
        }
        return failed(
          DirectPrivateMediaPrepareFailureReason.revalidationFailed,
          exitReason: DirectPrivateMediaExitReason.revalidationFailure,
        );
      }

      final kind = _qualifiedMediaKind(current.rows.attachment!);
      if (kind == null || kind != initialKind) {
        return failed(
          DirectPrivateMediaPrepareFailureReason.unsupportedMediaKind,
          exitReason: DirectPrivateMediaExitReason.revalidationFailure,
        );
      }
      final grant = DirectPrivateMediaViewerGrant._(
        identity: identity,
        direction: currentTarget.direction,
        mode: currentTarget.mode,
        kind: kind,
        localPath: currentPath,
        protectionOwner: protectionOwner,
        expiresAtMs: currentTarget.expiresAtMs,
        openingLease: openingLease,
      );
      _activeGrants.add(grant);
      grantPublished = true;
      return DirectPrivateMediaPrepareResult.granted(grant);
    } catch (_) {
      final invalidated = await continuityFailure();
      if (invalidated != null) return invalidated;
      return failed(
        DirectPrivateMediaPrepareFailureReason.unexpectedFailure,
        exitReason: DirectPrivateMediaExitReason.revalidationFailure,
      );
    } finally {
      if (!grantPublished) {
        if (openingLease != null && unpublishedSettlement == null) {
          await _settleUnpublishedLease(
            openingLease,
            DirectPrivateMediaExitReason.appLifecycleLoss,
            terminalize: true,
          );
        }
        if (protectionOwner != null) {
          await protectionCoordinator.exit(protectionOwner);
        }
      }
    }
  }

  Future<DirectPrivateMediaSettleResult> _settleUnpublishedLease(
    PrivateMediaOpeningLease lease,
    DirectPrivateMediaExitReason exitReason, {
    required bool terminalize,
  }) async {
    final disposition = await lifecycleEngine.settleOpeningLease(
      lease,
      intent: terminalize
          ? PrivateMediaLifecycleSettlementIntent.terminalize
          : PrivateMediaLifecycleSettlementIntent.rollbackPreFrame,
    );
    return DirectPrivateMediaSettleResult(
      disposition: _mapLifecycleDisposition(disposition),
      exitReason: exitReason,
      firstFrameRecorded: false,
    );
  }

  Future<bool> markFirstFrame(DirectPrivateMediaViewerGrant grant) async {
    if (grant._lifecycleSettled || grant._firstFrameRecorded) return false;
    final lease = grant._openingLease;
    if (lease != null && !await lifecycleEngine.markFirstFrame(lease)) {
      return false;
    }
    grant._firstFrameRecorded = true;
    return true;
  }

  Future<bool> revalidateForLifecycleEvent(
    DirectPrivateMediaViewerGrant grant,
  ) async {
    if (grant._lifecycleSettled) return false;
    final lease = grant._openingLease;
    if (lease != null) {
      return await lifecycleEngine.revalidateOpeningLease(lease) ==
          grant.localPath;
    }
    if (grant.mode == PrivateMediaMode.disappearing) {
      await lifecycleEngine.lifecycleLock.synchronized(
        grant.identity.attachmentId,
        () => lifecycleEngine.adapter.advanceClock(
          grant.identity.messageId,
          nowMs: lifecycleEngine.nowMs(),
        ),
      );
    }
    final current = await _qualifyRows(grant.identity);
    if (current == null ||
        !current.decision.allows(DirectPrivateMediaAction.openInApp)) {
      if (grant.mode == PrivateMediaMode.disappearing) {
        await _cleanupTerminalSafely(grant.identity.messageId);
      }
      return false;
    }
    final target = await _loadExactTarget(grant.identity, current);
    return target != null &&
        target.mode == grant.mode &&
        target.state == PrivateMediaLifecycleState.available &&
        _openableTargetPath(target, grant.identity) == grant.localPath;
  }

  /// Arms the authoritative disappearing deadline without publishing the
  /// deadline or duration to the widget. The timer merely schedules a fresh
  /// locked high-water/current-row decision; that decision, not wall clock
  /// alone, decides whether the route must close.
  void armDisappearingDeadline(
    DirectPrivateMediaViewerGrant grant,
    Future<void> Function() onExpired,
  ) {
    if (grant.mode != PrivateMediaMode.disappearing ||
        grant._lifecycleSettled ||
        grant._expiryTimer != null) {
      return;
    }
    final deadline = grant._expiresAtMs;
    if (deadline == null) {
      scheduleMicrotask(() => unawaited(_closeExpired(onExpired)));
      return;
    }
    _scheduleDisappearingDeadline(grant, deadline, onExpired);
  }

  void _scheduleDisappearingDeadline(
    DirectPrivateMediaViewerGrant grant,
    int deadline,
    Future<void> Function() onExpired,
  ) {
    final remainingMs = deadline - lifecycleEngine.nowMs();
    grant._expiryTimer = Timer(
      Duration(milliseconds: remainingMs > 0 ? remainingMs : 0),
      () async {
        grant._expiryTimer = null;
        if (grant._lifecycleSettled) return;
        try {
          final stillAvailable = await revalidateForLifecycleEvent(grant);
          if (grant._lifecycleSettled) return;
          if (!stillAvailable) {
            await _closeExpired(onExpired);
            return;
          }

          // The accepted Session-03 high-water contract permits a backward
          // wall-clock sample to remain below the persisted expiry. Re-arm for
          // that genuine remainder; never permanently disarm the live route.
          final refreshedRemaining = deadline - lifecycleEngine.nowMs();
          if (refreshedRemaining > 0) {
            _scheduleDisappearingDeadline(grant, deadline, onExpired);
            return;
          }
          await _closeExpired(onExpired);
        } catch (_) {
          if (!grant._lifecycleSettled) await _closeExpired(onExpired);
        }
      },
    );
  }

  Future<void> _closeExpired(Future<void> Function() onExpired) async {
    try {
      await onExpired();
    } catch (_) {}
  }

  Future<DirectPrivateMediaSettleResult> settle(
    DirectPrivateMediaViewerGrant grant,
    DirectPrivateMediaExitReason reason, {
    bool releaseProtection = true,
  }) async {
    var operation = grant._settleOperation;
    if (operation == null) {
      operation = _settleGrant(grant, reason);
      grant._settleOperation = operation;
    }
    final result = await operation;
    if (releaseProtection) await releaseProtectionOwner(grant);
    return result;
  }

  Future<DirectPrivateMediaSettleResult> _settleGrant(
    DirectPrivateMediaViewerGrant grant,
    DirectPrivateMediaExitReason reason,
  ) async {
    grant._lifecycleSettled = true;
    grant._expiryTimer?.cancel();
    grant._expiryTimer = null;
    final lease = grant._openingLease;
    late final DirectPrivateMediaSettleDisposition disposition;
    if (lease == null) {
      disposition = DirectPrivateMediaSettleDisposition.noLease;
    } else {
      final rollbackAllowed =
          !grant._firstFrameRecorded &&
          (reason == DirectPrivateMediaExitReason.preFrameDecodeFailure ||
              reason == DirectPrivateMediaExitReason.routePushFailure ||
              reason == DirectPrivateMediaExitReason.routeContinuityLoss ||
              reason == DirectPrivateMediaExitReason.protectionEnterFailure ||
              reason == DirectPrivateMediaExitReason.revalidationFailure);
      try {
        final lifecycleDisposition = await lifecycleEngine.settleOpeningLease(
          lease,
          intent: rollbackAllowed
              ? PrivateMediaLifecycleSettlementIntent.rollbackPreFrame
              : PrivateMediaLifecycleSettlementIntent.terminalize,
        );
        disposition = _mapLifecycleDisposition(lifecycleDisposition);
      } catch (_) {
        disposition =
            DirectPrivateMediaSettleDisposition.indeterminateFailClosed;
      }
    }
    return grant._settleResult ??= DirectPrivateMediaSettleResult(
      disposition: disposition,
      exitReason: reason,
      firstFrameRecorded: grant._firstFrameRecorded,
    );
  }

  Future<void> releaseProtectionOwner(
    DirectPrivateMediaViewerGrant grant,
  ) async {
    if (grant._protectionReleased) return;
    grant._protectionReleased = true;
    try {
      await protectionCoordinator.exit(grant.protectionOwner);
    } finally {
      _activeGrants.remove(grant);
      if (!grant._protectionReleasedCompleter.isCompleted) {
        grant._protectionReleasedCompleter.complete();
      }
    }
  }

  Future<bool> dispatchSafeAction(
    DirectPrivateMediaViewerGrant grant,
    DirectPrivateMediaAction action,
    Future<void> Function() dispatch,
  ) async {
    if (grant._lifecycleSettled ||
        (action != DirectPrivateMediaAction.reply &&
            action != DirectPrivateMediaAction.info &&
            action != DirectPrivateMediaAction.deleteForMe)) {
      return false;
    }
    final current = await _qualifyRows(grant.identity);
    if (current == null || !current.decision.allows(action)) return false;
    await dispatch();
    return true;
  }

  /// Re-reads every retry authority dimension after a typed failure. A stale
  /// pre-failure snapshot never enables View/Try Again.
  Future<bool> canRetryAfterPrepareFailure(
    DirectPrivateMediaViewerIdentity identity,
    DirectPrivateMediaPrepareFailureReason reason, {
    DirectPrivateMediaSettleResult? settleResult,
  }) {
    final allowedPreFrameReason =
        reason == DirectPrivateMediaPrepareFailureReason.routeContinuityLost ||
        reason ==
            DirectPrivateMediaPrepareFailureReason.protectionEnterFailed ||
        reason == DirectPrivateMediaPrepareFailureReason.protectionIncident ||
        reason == DirectPrivateMediaPrepareFailureReason.revalidationFailed;
    return _requalifyRetry(
      identity,
      allowedDoneRetry: allowedPreFrameReason,
      settleResult: settleResult,
    );
  }

  Future<bool> canRetryAfterOpenFailure(
    DirectPrivateMediaViewerIdentity identity,
    DirectPrivateMediaOpenFailureReason reason, {
    DirectPrivateMediaSettleResult? settleResult,
  }) {
    final allowedPreFrameReason =
        reason == DirectPrivateMediaOpenFailureReason.routePushFailure ||
        reason == DirectPrivateMediaOpenFailureReason.preFrameFailure;
    return _requalifyRetry(
      identity,
      allowedDoneRetry: allowedPreFrameReason,
      settleResult: settleResult,
    );
  }

  Future<bool> _requalifyRetry(
    DirectPrivateMediaViewerIdentity identity, {
    required bool allowedDoneRetry,
    required DirectPrivateMediaSettleResult? settleResult,
  }) async {
    final current = await _qualifyRows(identity);
    if (current == null ||
        !current.decision.allows(DirectPrivateMediaAction.openInApp)) {
      return false;
    }
    final parent = current.rows.parent!;
    final attachment = current.rows.attachment!;
    if (!parent.isIncoming &&
        parent.privateMediaMode == PrivateMediaMode.disappearing) {
      return false;
    }
    if (attachment.downloadStatus == kMediaDownloadStatusFailed) {
      return attachment.downloadRetryCount != null
          ? attachment.downloadRetryCount! < kMaxDownloadRetries
          : true;
    }
    if (attachment.downloadStatus != kMediaDownloadStatusDone ||
        !allowedDoneRetry ||
        settleResult == null ||
        (settleResult.disposition !=
                DirectPrivateMediaSettleDisposition.rolledBackAvailable &&
            settleResult.disposition !=
                DirectPrivateMediaSettleDisposition.noLease)) {
      return false;
    }
    final target = await _loadExactTarget(identity, current);
    return target != null &&
        target.state == PrivateMediaLifecycleState.available &&
        _openableTargetPath(target, identity) != null;
  }

  Future<
    ({
      DirectPrivateMediaCurrentRows rows,
      DirectPrivateMediaActionDecision decision,
    })?
  >
  _qualifyRows(DirectPrivateMediaViewerIdentity identity) async {
    final rows = await loadCurrentRows(identity);
    final decision = DirectPrivateMediaActionEligibility.evaluate(
      parent: rows.parent,
      attachment: rows.attachment,
      expectedMessageId: identity.messageId,
      expectedAttachmentId: identity.attachmentId,
      requiredDirection: null,
    );
    if (!decision.isPrivateOrUnsupported || rows.attachment == null) {
      return null;
    }
    return (rows: rows, decision: decision);
  }

  Future<PrivateMediaLifecycleTarget?> _loadExactTarget(
    DirectPrivateMediaViewerIdentity identity,
    ({
      DirectPrivateMediaCurrentRows rows,
      DirectPrivateMediaActionDecision decision,
    })
    current,
  ) async {
    final target = await lifecycleEngine.adapter.loadTarget(identity.messageId);
    final parent = current.rows.parent!;
    final rowAttachment = current.rows.attachment!;
    final targetMatches = target?.attachments.where(
      (attachment) =>
          attachment.id == identity.attachmentId &&
          attachment.messageId == identity.messageId,
    );
    final targetAttachment = targetMatches != null && targetMatches.length == 1
        ? targetMatches.single
        : null;
    if (target == null ||
        targetAttachment == null ||
        target.hidden ||
        target.scopeId != parent.contactPeerId ||
        target.direction !=
            (parent.isIncoming
                ? PrivateMediaDirection.incoming
                : PrivateMediaDirection.outgoing) ||
        target.mode != parent.privateMediaPolicy.mode ||
        target.state != parent.privateMediaState ||
        targetAttachment.storedLocalPath != rowAttachment.localPath ||
        targetAttachment.mime != rowAttachment.mime ||
        targetAttachment.size != rowAttachment.size ||
        _openableTargetPath(target, identity) == null) {
      return null;
    }
    return target;
  }

  String? _openableTargetPath(
    PrivateMediaLifecycleTarget target,
    DirectPrivateMediaViewerIdentity identity,
  ) {
    final matches = target.attachments.where(
      (attachment) =>
          attachment.id == identity.attachmentId &&
          attachment.messageId == identity.messageId,
    );
    if (matches.length != 1) return null;
    final attachment = matches.single;
    final path = attachment.localPath;
    if (!attachment.isDownloadComplete ||
        !attachment.isIntegrityEligible ||
        path == null ||
        path.isEmpty) {
      return null;
    }
    return path;
  }

  MediaViewerKind? _qualifiedMediaKind(MediaAttachment attachment) {
    final mime = attachment.mime.toLowerCase();
    final mediaType = attachment.mediaType.toLowerCase();
    if (mime == 'image/gif') {
      return mediaType == 'image' || mediaType == 'gif'
          ? MediaViewerKind.gif
          : null;
    }
    return switch (mediaType) {
      'image' when mime.startsWith('image/') => MediaViewerKind.image,
      'video' when mime.startsWith('video/') => MediaViewerKind.video,
      'gif' => null,
      _ => null,
    };
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

  DirectPrivateMediaSettleDisposition _mapLifecycleDisposition(
    PrivateMediaLifecycleSettlementDisposition disposition,
  ) {
    return switch (disposition) {
      PrivateMediaLifecycleSettlementDisposition.rolledBackAvailable =>
        DirectPrivateMediaSettleDisposition.rolledBackAvailable,
      PrivateMediaLifecycleSettlementDisposition.terminalized =>
        DirectPrivateMediaSettleDisposition.terminalized,
      PrivateMediaLifecycleSettlementDisposition.lostRollbackRace =>
        DirectPrivateMediaSettleDisposition.lostRollbackRace,
      PrivateMediaLifecycleSettlementDisposition.indeterminateFailClosed =>
        DirectPrivateMediaSettleDisposition.indeterminateFailClosed,
    };
  }

  Future<void> _cleanupTerminalSafely(String messageId) async {
    try {
      await lifecycleEngine.cleanupTerminalMessage(messageId);
    } catch (_) {}
  }

  void _forwardProtectionEvent(PrivateMediaProtectionEvent event) {
    if (_routeEventController.isClosed) return;
    _routeEventController.add(event);
  }

  Future<void> dispose() => _disposeOperation ??= _dispose();

  Future<void> _dispose() async {
    if (_disposeRequested) return;
    _disposeRequested = true;
    _forwardProtectionEvent(PrivateMediaProtectionEvent.channelFailure);
    final releases = _activeGrants
        .map((grant) => grant._protectionReleasedCompleter.future)
        .toList(growable: false);
    if (releases.isNotEmpty) await Future.wait(releases);
    await _protectionSubscription.cancel();
    if (disposeProtectionCoordinator) {
      await protectionCoordinator.dispose();
    }
    await _routeEventController.close();
  }
}
