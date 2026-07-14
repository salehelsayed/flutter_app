import 'dart:async';

import 'package:flutter_app/core/media/private_media_protection_coordinator.dart';
import 'package:flutter_app/features/groups/application/group_private_media_lifecycle.dart';

class GroupPrivateMediaViewerIdentity {
  const GroupPrivateMediaViewerIdentity({
    required this.groupId,
    required this.messageId,
    required this.attachmentId,
  });

  final String groupId;
  final String messageId;
  final String attachmentId;

  @override
  bool operator ==(Object other) =>
      other is GroupPrivateMediaViewerIdentity &&
      other.groupId == groupId &&
      other.messageId == messageId &&
      other.attachmentId == attachmentId;

  @override
  int get hashCode => Object.hash(groupId, messageId, attachmentId);
}

enum GroupPrivateMediaExitReason {
  close,
  routePushFailure,
  background,
  capture,
  expiry,
  postFrameFailure,
  preFrameDecodeFailure,
  dispose,
}

class GroupPrivateMediaViewerGrant {
  GroupPrivateMediaViewerGrant._({
    required this.identity,
    required this.data,
    required this.protectionOwner,
  });

  final GroupPrivateMediaViewerIdentity identity;
  final GroupPrivateMediaOpenGrantData data;
  final PrivateMediaProtectionOwner protectionOwner;
  final Completer<void> _released = Completer<void>();
  Timer? _expiryTimer;
  bool firstFrameRecorded = false;
  bool settled = false;
  bool protectionReleased = false;
}

class GroupPrivateMediaViewerController {
  GroupPrivateMediaViewerController({
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

  final GroupPrivateMediaLifecycleEngine lifecycleEngine;
  final PrivateMediaProtectionCoordinator protectionCoordinator;
  final bool disposeProtectionCoordinator;
  final StreamController<PrivateMediaProtectionEvent> _events =
      StreamController<PrivateMediaProtectionEvent>.broadcast(sync: true);
  final Set<GroupPrivateMediaViewerGrant> _activeGrants = {};
  final Map<
    GroupPrivateMediaViewerIdentity,
    Future<GroupPrivateMediaViewerGrant?>
  >
  _preparing = {};
  late final StreamSubscription<PrivateMediaProtectionEvent>
  _protectionSubscription;
  bool _disposeRequested = false;
  Future<void>? _disposeOperation;

  Stream<PrivateMediaProtectionEvent> get protectionEvents => _events.stream;

  PrivateMediaProtectionEvent? get latchedProtectionEvent =>
      protectionCoordinator.latchedCriticalEvent;

  Future<GroupPrivateMediaViewerGrant?> prepare(
    GroupPrivateMediaViewerIdentity identity,
  ) {
    if (_disposeRequested) return Future.value(null);
    final existing = _preparing[identity];
    if (existing != null) return existing;
    final operation = _prepare(identity);
    _preparing[identity] = operation;
    return operation.whenComplete(() => _preparing.remove(identity));
  }

  Future<GroupPrivateMediaViewerGrant?> _prepare(
    GroupPrivateMediaViewerIdentity identity,
  ) async {
    PrivateMediaProtectionOwner? owner;
    var published = false;
    try {
      final initial = await lifecycleEngine.qualifyOpen(
        groupId: identity.groupId,
        messageId: identity.messageId,
        attachmentId: identity.attachmentId,
      );
      if (initial == null) return null;
      owner = await protectionCoordinator.enter();
      if (owner == null || protectionCoordinator.latchedCriticalEvent != null) {
        return null;
      }
      final current = await lifecycleEngine.qualifyOpen(
        groupId: identity.groupId,
        messageId: identity.messageId,
        attachmentId: identity.attachmentId,
      );
      if (current == null ||
          current.policy != initial.policy ||
          current.localPath != initial.localPath) {
        return null;
      }
      final grant = GroupPrivateMediaViewerGrant._(
        identity: identity,
        data: current,
        protectionOwner: owner,
      );
      _activeGrants.add(grant);
      published = true;
      return grant;
    } catch (_) {
      return null;
    } finally {
      if (!published && owner != null) {
        await protectionCoordinator.exit(owner);
      }
    }
  }

  Future<bool> markFirstFrame(GroupPrivateMediaViewerGrant grant) async {
    if (grant.settled || grant.firstFrameRecorded) return false;
    final accepted = await lifecycleEngine.consumeAtFirstFrame(grant.data);
    if (!accepted) return false;
    grant.firstFrameRecorded = true;
    return true;
  }

  Future<bool> revalidateForLifecycleEvent(
    GroupPrivateMediaViewerGrant grant,
  ) => grant.settled
      ? Future.value(false)
      : lifecycleEngine.revalidateOpen(grant.data);

  void armDisappearingDeadline(
    GroupPrivateMediaViewerGrant grant,
    Future<void> Function() onExpired,
  ) {
    final deadline = grant.data.expiresAtMs;
    if (deadline == null || grant.settled || grant._expiryTimer != null) return;
    _scheduleDeadline(grant, deadline, onExpired);
  }

  void _scheduleDeadline(
    GroupPrivateMediaViewerGrant grant,
    int deadline,
    Future<void> Function() onExpired,
  ) {
    final delay = deadline - lifecycleEngine.nowMs();
    grant._expiryTimer = Timer(
      Duration(milliseconds: delay > 0 ? delay : 0),
      () async {
        grant._expiryTimer = null;
        if (grant.settled) return;
        try {
          if (!await lifecycleEngine.revalidateOpen(grant.data)) {
            await onExpired();
            return;
          }
          final remaining = deadline - lifecycleEngine.nowMs();
          if (remaining > 0) {
            _scheduleDeadline(grant, deadline, onExpired);
          } else {
            await onExpired();
          }
        } catch (_) {
          await onExpired();
        }
      },
    );
  }

  Future<void> settle(
    GroupPrivateMediaViewerGrant grant,
    GroupPrivateMediaExitReason reason, {
    bool releaseProtection = true,
  }) async {
    if (!grant.settled) {
      grant.settled = true;
      grant._expiryTimer?.cancel();
      grant._expiryTimer = null;
      await lifecycleEngine.settle(grant.data);
    }
    if (releaseProtection) await releaseProtectionOwner(grant);
  }

  Future<void> releaseProtectionOwner(
    GroupPrivateMediaViewerGrant grant,
  ) async {
    if (grant.protectionReleased) return;
    grant.protectionReleased = true;
    try {
      await protectionCoordinator.exit(grant.protectionOwner);
    } finally {
      _activeGrants.remove(grant);
      if (!grant._released.isCompleted) grant._released.complete();
    }
  }

  void _forwardProtectionEvent(PrivateMediaProtectionEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  Future<void> dispose() => _disposeOperation ??= _dispose();

  Future<void> _dispose() async {
    if (_disposeRequested) return;
    _disposeRequested = true;
    _forwardProtectionEvent(PrivateMediaProtectionEvent.channelFailure);
    final releases = _activeGrants
        .map((grant) => grant._released.future)
        .toList(growable: false);
    if (releases.isNotEmpty) await Future.wait(releases);
    await _protectionSubscription.cancel();
    if (disposeProtectionCoordinator) {
      await protectionCoordinator.dispose();
    }
    await _events.close();
  }
}
