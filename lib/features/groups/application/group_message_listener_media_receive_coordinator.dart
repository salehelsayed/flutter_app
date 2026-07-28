part of 'group_message_listener.dart';

final class _GroupMediaReceiveCriticalTaskLease {
  _GroupMediaReceiveCriticalTaskLease(this.taskId);

  final String? taskId;
  int participants = 0;
}

final class _GroupMediaReceiveCoordinator {
  _GroupMediaReceiveCoordinator({
    required Bridge? bridge,
    required GroupMessageRepository msgRepo,
    required MediaAttachmentRepository? mediaAttachmentRepo,
    required MediaFileManager? mediaFileManager,
    required AppLifecycleState Function()? getAppLifecycleState,
    required GroupMediaDownloadCoordinator? groupMediaDownloadCoordinator,
    required BeginGroupMediaReceiveCriticalTask?
    beginGroupMediaReceiveCriticalTask,
    required EndGroupMediaReceiveCriticalTask? endGroupMediaReceiveCriticalTask,
    required void Function(GroupMessage) emitGroupMessage,
    required Future<void> Function(Future<void>) trackInFlight,
    required bool Function() isStoppingOrDisposed,
  }) : _bridge = bridge,
       _msgRepo = msgRepo,
       _mediaAttachmentRepo = mediaAttachmentRepo,
       _mediaFileManager = mediaFileManager,
       _getAppLifecycleState = getAppLifecycleState,
       _groupMediaDownloadCoordinator = groupMediaDownloadCoordinator,
       _beginGroupMediaReceiveCriticalTask = beginGroupMediaReceiveCriticalTask,
       _endGroupMediaReceiveCriticalTask = endGroupMediaReceiveCriticalTask,
       _emitGroupMessage = emitGroupMessage,
       _trackInFlight = trackInFlight,
       _isStoppingOrDisposed = isStoppingOrDisposed;

  final Bridge? _bridge;
  final GroupMessageRepository _msgRepo;
  final MediaAttachmentRepository? _mediaAttachmentRepo;
  final MediaFileManager? _mediaFileManager;
  final AppLifecycleState Function()? _getAppLifecycleState;
  final GroupMediaDownloadCoordinator? _groupMediaDownloadCoordinator;
  final BeginGroupMediaReceiveCriticalTask? _beginGroupMediaReceiveCriticalTask;
  final EndGroupMediaReceiveCriticalTask? _endGroupMediaReceiveCriticalTask;
  final void Function(GroupMessage) _emitGroupMessage;
  final Future<void> Function(Future<void>) _trackInFlight;
  final bool Function() _isStoppingOrDisposed;

  _GroupMediaReceiveCriticalTaskLease? _groupMediaReceiveCriticalTaskLease;
  Future<_GroupMediaReceiveCriticalTaskLease>?
  _groupMediaReceiveCriticalTaskLeaseAcquisition;
  Future<void>? _groupMediaReceiveCriticalTaskLeaseEnd;

  bool get _hasAutomaticMediaRecovery =>
      _groupMediaDownloadCoordinator != null ||
      (_bridge != null &&
          _mediaAttachmentRepo != null &&
          _mediaFileManager != null);

  Future<GroupMediaReceiveCriticalTaskReservation>
  reserveGroupMediaReceiveCriticalTaskForForegroundHandoff() async {
    if (_isStoppingOrDisposed()) {
      throw StateError(
        'cannot reserve a group-media receive critical task while stopping',
      );
    }

    final reservationReleased = Completer<void>();
    _trackInFlight(reservationReleased.future);
    try {
      final lease = await _acquireReceiveCriticalTaskLease();
      if (lease.taskId == null) {
        await _releaseReceiveCriticalTaskLease(lease);
        throw StateError(
          'native group-media receive critical-task reservation was refused',
        );
      }
      if (_isStoppingOrDisposed()) {
        await _releaseReceiveCriticalTaskLease(lease);
        throw StateError(
          'group-media receive critical-task reservation stopped during acquisition',
        );
      }

      return GroupMediaReceiveCriticalTaskReservation._(() async {
        try {
          await _releaseReceiveCriticalTaskLease(lease);
        } finally {
          if (!reservationReleased.isCompleted) {
            reservationReleased.complete();
          }
        }
      });
    } catch (_) {
      if (!reservationReleased.isCompleted) {
        reservationReleased.complete();
      }
      rethrow;
    }
  }

  Future<void> _recoverAutomaticMedia(
    GroupMessage message, {
    required Iterable<String> attachmentIds,
    bool emitAfterDownload = true,
  }) async {
    final exactAttachmentIds = attachmentIds
        .where((attachmentId) => attachmentId.isNotEmpty)
        .toSet();
    _GroupMediaReceiveCriticalTaskLease? criticalTaskLease;
    if (_shouldOwnReceiveCriticalTask(message, exactAttachmentIds)) {
      criticalTaskLease = await _acquireReceiveCriticalTaskLease();
    }
    try {
      final coordinator = _groupMediaDownloadCoordinator;
      if (coordinator == null) {
        await _autoDownloadMedia(
          message,
          attachmentIds: exactAttachmentIds,
          emitAfterDownload: emitAfterDownload,
        );
        return;
      }

      final recovery = await coordinator.recoverAttachments(
        groupId: message.groupId,
        attachmentIds: exactAttachmentIds,
      );
      if (emitAfterDownload &&
          recovery.affectedMessageIds.contains(message.id)) {
        _emitGroupMessage(message);
      }
    } finally {
      if (criticalTaskLease != null) {
        await _releaseReceiveCriticalTaskLease(criticalTaskLease);
      }
    }
  }

  bool _shouldOwnReceiveCriticalTask(
    GroupMessage message,
    Set<String> attachmentIds,
  ) {
    if (attachmentIds.isEmpty ||
        !message.isIncoming ||
        !message.privateMediaPolicy.isOrdinary) {
      return false;
    }

    if (_groupMediaReceiveCriticalTaskLease != null ||
        _groupMediaReceiveCriticalTaskLeaseAcquisition != null) {
      return true;
    }

    final lifecycle = _getAppLifecycleState;
    if (lifecycle == null) return false;
    try {
      return lifecycle() != AppLifecycleState.resumed;
    } catch (_) {
      return false;
    }
  }

  Future<String?> _beginReceiveCriticalTask() async {
    try {
      final injected = _beginGroupMediaReceiveCriticalTask;
      final taskId = injected != null
          ? await injected()
          : _bridge == null
          ? null
          : await callBgBegin(_bridge);
      final normalizedTaskId = taskId?.trim();
      return normalizedTaskId == null || normalizedTaskId.isEmpty
          ? null
          : normalizedTaskId;
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_MEDIA_RECEIVE_CRITICAL_TASK_BEGIN_FAILED',
        details: {'error': error.toString()},
      );
      return null;
    }
  }

  Future<_GroupMediaReceiveCriticalTaskLease>
  _acquireReceiveCriticalTaskLease() async {
    while (true) {
      final existing = _groupMediaReceiveCriticalTaskLease;
      if (existing != null) {
        existing.participants += 1;
        return existing;
      }

      final ending = _groupMediaReceiveCriticalTaskLeaseEnd;
      if (ending != null) {
        await ending;
        continue;
      }

      var acquisition = _groupMediaReceiveCriticalTaskLeaseAcquisition;
      if (acquisition == null) {
        late final Future<_GroupMediaReceiveCriticalTaskLease> tracked;
        tracked = _beginReceiveCriticalTask()
            .then((taskId) {
              final lease = _GroupMediaReceiveCriticalTaskLease(taskId);
              _groupMediaReceiveCriticalTaskLease = lease;
              return lease;
            })
            .whenComplete(() {
              if (identical(
                _groupMediaReceiveCriticalTaskLeaseAcquisition,
                tracked,
              )) {
                _groupMediaReceiveCriticalTaskLeaseAcquisition = null;
              }
            });
        _groupMediaReceiveCriticalTaskLeaseAcquisition = tracked;
        acquisition = tracked;
      }
      final acquired = await acquisition;
      acquired.participants += 1;
      return acquired;
    }
  }

  Future<void> _releaseReceiveCriticalTaskLease(
    _GroupMediaReceiveCriticalTaskLease lease,
  ) async {
    if (lease.participants <= 0) {
      throw StateError('group-media receive critical-task lease underflow');
    }
    lease.participants -= 1;
    if (lease.participants != 0 ||
        !identical(_groupMediaReceiveCriticalTaskLease, lease)) {
      return;
    }

    _groupMediaReceiveCriticalTaskLease = null;
    late final Future<void> tracked;
    tracked = _endReceiveCriticalTask(lease.taskId).whenComplete(() {
      if (identical(_groupMediaReceiveCriticalTaskLeaseEnd, tracked)) {
        _groupMediaReceiveCriticalTaskLeaseEnd = null;
      }
    });
    _groupMediaReceiveCriticalTaskLeaseEnd = tracked;
    await tracked;
  }

  Future<void> _endReceiveCriticalTask(String? taskId) async {
    if (taskId == null) return;
    try {
      final injected = _endGroupMediaReceiveCriticalTask;
      if (injected != null) {
        await injected(taskId);
      } else {
        final bridge = _bridge;
        if (bridge != null) await callBgEnd(bridge, taskId);
      }
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_MEDIA_RECEIVE_CRITICAL_TASK_END_FAILED',
        details: {'error': error.toString()},
      );
    }
  }

  Future<void> _autoDownloadMedia(
    GroupMessage message, {
    Set<String>? attachmentIds,
    bool emitAfterDownload = true,
  }) async {
    try {
      final bridge = _bridge;
      final mediaAttachmentRepo = _mediaAttachmentRepo;
      final mediaFileManager = _mediaFileManager;
      if (bridge == null ||
          mediaAttachmentRepo == null ||
          mediaFileManager == null) {
        return;
      }

      final attachments = await mediaAttachmentRepo.getAttachmentsForMessage(
        message.id,
        owner: MediaOwnerLane.group,
      );
      if (attachments.isEmpty) return;

      for (final attachment in attachments) {
        if (attachmentIds != null && !attachmentIds.contains(attachment.id)) {
          continue;
        }
        if (attachment.downloadStatus != 'pending') continue;
        try {
          await downloadMedia(
            bridge: bridge,
            mediaAttachmentRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
            attachment: attachment,
            contactPeerId: message.groupId,
            owner: MediaOwnerLane.group,
            enforceGroupMediaPolicy: true,
            groupMessageRepo: _msgRepo,
          );
        } catch (e) {
          emitFlowEvent(
            layer: 'FL',
            event: 'GROUP_LISTENER_DOWNLOAD_ERROR',
            details: {
              'blobId': attachment.id.length > 8
                  ? attachment.id.substring(0, 8)
                  : attachment.id,
              'error': e.toString(),
            },
          );
        }
      }

      if (emitAfterDownload) {
        _emitGroupMessage(message);
      }
    } catch (e) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_LISTENER_AUTO_DOWNLOAD_ERROR',
        details: {
          'messageId': message.id.length > 8
              ? message.id.substring(0, 8)
              : message.id,
          'error': e.toString(),
        },
      );
    }
  }
}
