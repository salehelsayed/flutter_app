import 'dart:async';

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

enum DirectPrivateMediaExitReason {
  close,
  routePushFailure,
  background,
  capture,
  expiry,
  postFrameFailure,
  preFrameDecodeFailure,
  dispose,
}

class DirectPrivateMediaViewerGrant {
  DirectPrivateMediaViewerGrant._({
    required this.identity,
    required this.mode,
    required this.kind,
    required this.localPath,
    required this.protectionOwner,
    required int? expiresAtMs,
    required PrivateMediaOpeningLease? openingLease,
  }) : _openingLease = openingLease,
       _expiresAtMs = expiresAtMs;

  final DirectPrivateMediaViewerIdentity identity;
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

  bool get canEnterPictureInPicture => false;
  bool get settled => _lifecycleSettled;
  bool get protectionReleased => _protectionReleased;

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
    Future<DirectPrivateMediaViewerGrant?>
  >
  _preparing = {};

  Stream<PrivateMediaProtectionEvent> get protectionEvents =>
      _routeEventController.stream;

  PrivateMediaProtectionEvent? get latchedProtectionEvent =>
      protectionCoordinator.latchedCriticalEvent;

  Future<DirectPrivateMediaViewerGrant?> prepare(
    DirectPrivateMediaViewerIdentity identity,
  ) {
    if (_disposeRequested) return Future.value(null);
    final existing = _preparing[identity];
    if (existing != null) return existing;
    final operation = _prepare(identity);
    _preparing[identity] = operation;
    return operation.whenComplete(() => _preparing.remove(identity));
  }

  Future<DirectPrivateMediaViewerGrant?> _prepare(
    DirectPrivateMediaViewerIdentity identity,
  ) async {
    if (identity.messageId.trim().isEmpty ||
        identity.attachmentId.trim().isEmpty) {
      return null;
    }
    PrivateMediaOpeningLease? openingLease;
    PrivateMediaProtectionOwner? protectionOwner;
    var grantPublished = false;
    try {
      final initial = await _qualifyRows(identity);
      if (initial == null ||
          !initial.decision.allows(DirectPrivateMediaAction.openInApp)) {
        return null;
      }
      final initialTarget = await _loadExactTarget(identity, initial);
      if (initialTarget == null) return null;

      final String authorizedPath;
      if (initialTarget.mode == PrivateMediaMode.viewOnce) {
        openingLease = await lifecycleEngine.openViewOnce(identity.messageId);
        if (openingLease == null) return null;
        if (openingLease.attachmentId != identity.attachmentId) return null;
        authorizedPath = openingLease.localPath;
      } else {
        if (initialTarget.mode != PrivateMediaMode.protected &&
            initialTarget.mode != PrivateMediaMode.disappearing) {
          return null;
        }
        final initialPath = _openableTargetPath(initialTarget, identity);
        if (initialPath == null ||
            initialTarget.state != PrivateMediaLifecycleState.available) {
          return null;
        }
        authorizedPath = initialPath;
      }

      protectionOwner = await protectionCoordinator.enter();
      if (protectionOwner == null ||
          protectionCoordinator.latchedCriticalEvent != null) {
        return null;
      }

      if (initialTarget.mode == PrivateMediaMode.disappearing) {
        await lifecycleEngine.lifecycleLock.synchronized(
          identity.attachmentId,
          () => lifecycleEngine.adapter.advanceClock(
            identity.messageId,
            nowMs: lifecycleEngine.nowMs(),
          ),
        );
      }
      final current = await _qualifyRows(identity);
      if (current == null ||
          !current.decision.allows(DirectPrivateMediaAction.openInApp)) {
        if (initialTarget.mode == PrivateMediaMode.disappearing) {
          await _cleanupTerminalSafely(identity.messageId);
        }
        return null;
      }
      final currentTarget = await _loadExactTarget(identity, current);
      if (currentTarget == null || currentTarget.mode != initialTarget.mode) {
        return null;
      }

      final String? currentPath;
      if (openingLease != null) {
        currentPath = await lifecycleEngine.revalidateOpeningLease(
          openingLease,
        );
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
        return null;
      }

      final mediaType = current.rows.attachment!.mediaType;
      final kind = switch (mediaType) {
        'image' => MediaViewerKind.image,
        'video' => MediaViewerKind.video,
        _ => null,
      };
      if (kind == null) return null;
      final grant = DirectPrivateMediaViewerGrant._(
        identity: identity,
        mode: currentTarget.mode,
        kind: kind,
        localPath: currentPath,
        protectionOwner: protectionOwner,
        expiresAtMs: currentTarget.expiresAtMs,
        openingLease: openingLease,
      );
      _activeGrants.add(grant);
      grantPublished = true;
      return grant;
    } catch (_) {
      return null;
    } finally {
      if (!grantPublished) {
        if (openingLease != null) {
          await _terminalizeLeaseSafely(openingLease);
        }
        if (protectionOwner != null) {
          await protectionCoordinator.exit(protectionOwner);
        }
      }
    }
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

  Future<void> settle(
    DirectPrivateMediaViewerGrant grant,
    DirectPrivateMediaExitReason reason, {
    bool releaseProtection = true,
  }) async {
    if (!grant._lifecycleSettled) {
      grant._lifecycleSettled = true;
      grant._expiryTimer?.cancel();
      grant._expiryTimer = null;
      final lease = grant._openingLease;
      if (lease != null) {
        final shouldRollback =
            reason == DirectPrivateMediaExitReason.preFrameDecodeFailure &&
            !grant._firstFrameRecorded;
        if (shouldRollback) {
          final rolledBack = await lifecycleEngine.rollbackPreFirstFrame(lease);
          if (!rolledBack) {
            await lifecycleEngine.terminalizeViewOnce(lease);
          }
        } else {
          await lifecycleEngine.terminalizeViewOnce(lease);
        }
      }
    }
    if (releaseProtection) await releaseProtectionOwner(grant);
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
        target.mode != parent.privateMediaPolicy.mode ||
        target.state != parent.privateMediaState ||
        targetAttachment.storedLocalPath != rowAttachment.localPath ||
        targetAttachment.mime != rowAttachment.mime ||
        targetAttachment.size != rowAttachment.size ||
        !_mimeMatchesMediaType(
          targetAttachment.mime,
          rowAttachment.mediaType,
        ) ||
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

  bool _mimeMatchesMediaType(String mime, String mediaType) =>
      switch (mediaType) {
        'image' => mime.startsWith('image/'),
        'video' => mime.startsWith('video/'),
        _ => false,
      };

  Future<void> _terminalizeLeaseSafely(PrivateMediaOpeningLease lease) async {
    try {
      await lifecycleEngine.terminalizeViewOnce(lease);
    } catch (_) {}
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
