import 'dart:async';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/broadcast_voluntary_leave_use_case.dart';
import 'package:flutter_app/features/groups/application/group_pending_broadcast_sink.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_retention_policy.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_broadcast.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

enum LeaveGroupAndDeleteLocalHistoryStatus {
  blockedLastAdmin,
  preworkFailed,
  nativeLeaveFailed,
  nativeLeaveUncertain,
  left,
  leftCleanupIncomplete,
}

class LeaveGroupAndDeleteLocalHistoryResult {
  const LeaveGroupAndDeleteLocalHistoryResult({
    required this.status,
    this.broadcastResult,
    this.cause,
  });

  final LeaveGroupAndDeleteLocalHistoryStatus status;
  final VoluntaryLeaveBroadcastResult? broadcastResult;
  final Object? cause;

  bool get didLeave =>
      status == LeaveGroupAndDeleteLocalHistoryStatus.left ||
      status == LeaveGroupAndDeleteLocalHistoryStatus.leftCleanupIncomplete;
}

/// Performs the signed voluntary-leave prework, one native leave, and only
/// then the target-local cleanup.
///
/// This is stateful solely to remember a confirmed native commit for the
/// lifetime of the current UI action. A cleanup retry on the same instance can
/// never publish or issue `group:leave` twice.
class LeaveGroupAndDeleteLocalHistoryUseCase {
  LeaveGroupAndDeleteLocalHistoryUseCase({
    required this.bridge,
    required this.groupRepo,
    required this.groupMessageRepo,
    required this.identityRepo,
    this.sendP2PMessage,
    this.storeP2PMessageInInbox,
    Future<void> Function(String groupId)? discardPendingBroadcasts,
    Future<List<GroupPendingBroadcast>> Function(String groupId)?
    loadPendingBroadcasts,
    this.nativeLeaveTimeout = const Duration(seconds: 30),
  }) : discardPendingBroadcasts =
           discardPendingBroadcasts ?? discardGroupPendingBroadcasts,
       loadPendingBroadcasts =
           loadPendingBroadcasts ?? loadGroupPendingBroadcasts;

  final Bridge bridge;
  final GroupRepository groupRepo;
  final GroupMessageRepository? groupMessageRepo;
  final IdentityRepository identityRepo;
  final Future<bool> Function(String peerId, String message)? sendP2PMessage;
  final Future<bool> Function(String peerId, String message)?
  storeP2PMessageInInbox;
  final Future<void> Function(String groupId) discardPendingBroadcasts;
  final Future<List<GroupPendingBroadcast>> Function(String groupId)
  loadPendingBroadcasts;
  final Duration nativeLeaveTimeout;

  final Map<String, _ConfirmedLeaveMarker> _nativeLeaveCommittedGroups =
      <String, _ConfirmedLeaveMarker>{};
  final Map<String, Future<LeaveGroupAndDeleteLocalHistoryResult>> _inFlight =
      <String, Future<LeaveGroupAndDeleteLocalHistoryResult>>{};

  Future<LeaveGroupAndDeleteLocalHistoryResult> call(String groupId) {
    final existing = _inFlight[groupId];
    if (existing != null) return existing;

    // Schedule the body after registering the future so two same-turn UI taps
    // coalesce before either can reach signed prework or `group:leave`.
    final future = Future<LeaveGroupAndDeleteLocalHistoryResult>.microtask(
      () => _callOnce(groupId),
    );
    _inFlight[groupId] = future;
    future.whenComplete(() {
      if (identical(_inFlight[groupId], future)) {
        _inFlight.remove(groupId);
      }
    }).ignore();
    return future;
  }

  Future<LeaveGroupAndDeleteLocalHistoryResult> _callOnce(
    String groupId,
  ) async {
    final confirmedLeave = _nativeLeaveCommittedGroups[groupId];
    if (confirmedLeave != null) {
      try {
        final currentGroup = await groupRepo.getGroup(groupId);
        final currentSelf = await groupRepo.getMember(
          groupId,
          confirmedLeave.peerId,
        );
        if (currentGroup != null && currentSelf == null) {
          // A newly accepted invite materializes the group before its members.
          // Missing membership is therefore ambiguous and must never authorize
          // deletion of the current group.
          return LeaveGroupAndDeleteLocalHistoryResult(
            status: LeaveGroupAndDeleteLocalHistoryStatus.leftCleanupIncomplete,
            cause: StateError(
              'Confirmed-leave cleanup paused while current membership is '
              'being resolved.',
            ),
          );
        }
        final isLaterMembership =
            currentGroup != null &&
            currentSelf != null &&
            (confirmedLeave.joinedAt == null ||
                !currentSelf.joinedAt.toUtc().isAtSameMomentAs(
                  confirmedLeave.joinedAt!,
                ));
        if (!isLaterMembership) {
          return _cleanupAfterConfirmedLeave(groupId, broadcastResult: null);
        }
        // A cleanup marker belongs to one local membership, not forever to a
        // reusable group id. A later join must execute a fresh signed leave.
        _nativeLeaveCommittedGroups.remove(groupId);
      } catch (error) {
        return LeaveGroupAndDeleteLocalHistoryResult(
          status: LeaveGroupAndDeleteLocalHistoryStatus.leftCleanupIncomplete,
          cause: error,
        );
      }
    }

    _LeaveRollbackSnapshot? snapshot;
    try {
      final pending = await loadPendingBroadcasts(groupId);
      if (_hasPendingRoleTransition(pending, groupId)) {
        return LeaveGroupAndDeleteLocalHistoryResult(
          status: LeaveGroupAndDeleteLocalHistoryStatus.preworkFailed,
          cause: StateError(
            'A member role change must finish syncing before leaving.',
          ),
        );
      }
      snapshot = await _captureRollbackSnapshot(groupId);
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_ACTIVE_EXIT_SNAPSHOT_FAILED',
        details: const {
          'code': 'EX01',
          'phase': 'authority',
          'severity': 'failure',
        },
      );
      return LeaveGroupAndDeleteLocalHistoryResult(
        status: LeaveGroupAndDeleteLocalHistoryStatus.preworkFailed,
        cause: error,
      );
    }
    if (snapshot == null) {
      return LeaveGroupAndDeleteLocalHistoryResult(
        status: LeaveGroupAndDeleteLocalHistoryStatus.preworkFailed,
        cause: StateError('Group or identity not found'),
      );
    }

    VoluntaryLeaveBroadcastResult? broadcastResult;
    String? tentativeTimelineMessageId;
    try {
      final group = await groupRepo.getGroup(groupId);
      if (group == null || group.isDissolved) {
        throw StateError('Active group not found: $groupId');
      }
      broadcastResult = await broadcastVoluntaryLeaveAndRotateKey(
        bridge: bridge,
        groupRepo: groupRepo,
        group: group,
        identityRepo: identityRepo,
        msgRepo: groupMessageRepo,
        sendP2PMessage: sendP2PMessage,
        storeP2PMessageInInbox: storeP2PMessageInInbox,
        onTimelineMessageSaved: (messageId) {
          tentativeTimelineMessageId = messageId;
        },
      );
      if (broadcastResult.skipReason ==
          VoluntaryLeaveBroadcastSkipReason.lastAdmin) {
        return LeaveGroupAndDeleteLocalHistoryResult(
          status: LeaveGroupAndDeleteLocalHistoryStatus.blockedLastAdmin,
          broadcastResult: broadcastResult,
        );
      }
      if (!broadcastResult.didBroadcast) {
        throw StateError('Voluntary leave prework could not be prepared');
      }

      // Revalidate the lower invariant at the actual native boundary. Existing
      // peer-admin rows stay authoritative; successor eligibility is a UI
      // policy and is not substituted for this guard.
      final freshGroup = await groupRepo.getGroup(groupId);
      final freshMembers = await groupRepo.getMembers(groupId);
      final freshPending = await loadPendingBroadcasts(groupId);
      if (freshGroup == null || freshGroup.isDissolved) {
        throw StateError('Active group not found: $groupId');
      }
      if (_hasPendingRoleTransition(freshPending, groupId)) {
        final rollbackError = await _rollbackTentativeArtifactsOrError(
          snapshot,
          timelineMessageId: tentativeTimelineMessageId,
        );
        final pendingError = StateError(
          'A member role change must finish syncing before leaving.',
        );
        return LeaveGroupAndDeleteLocalHistoryResult(
          status: LeaveGroupAndDeleteLocalHistoryStatus.preworkFailed,
          broadcastResult: broadcastResult,
          cause: rollbackError == null
              ? pendingError
              : _combinedRollbackCause(pendingError, rollbackError),
        );
      }
      final adminCount = freshMembers
          .where((member) => member.role == MemberRole.admin)
          .length;
      if (freshGroup.myRole == GroupRole.admin && adminCount <= 1) {
        final rollbackError = await _rollbackTentativeArtifactsOrError(
          snapshot,
          timelineMessageId: tentativeTimelineMessageId,
        );
        if (rollbackError != null) {
          return LeaveGroupAndDeleteLocalHistoryResult(
            status: LeaveGroupAndDeleteLocalHistoryStatus.preworkFailed,
            broadcastResult: broadcastResult,
            cause: _combinedRollbackCause(
              StateError('Last-admin guard required tentative rollback'),
              rollbackError,
            ),
          );
        }
        return LeaveGroupAndDeleteLocalHistoryResult(
          status: LeaveGroupAndDeleteLocalHistoryStatus.blockedLastAdmin,
          broadcastResult: broadcastResult,
        );
      }
    } catch (error) {
      final rollbackError = await _rollbackTentativeArtifactsOrError(
        snapshot,
        timelineMessageId: tentativeTimelineMessageId,
      );
      final cause = rollbackError == null
          ? error
          : _combinedRollbackCause(error, rollbackError);
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_ACTIVE_EXIT_PREWORK_FAILED',
        details: const {
          'code': 'EX03',
          'phase': 'notice',
          'severity': 'failure',
        },
      );
      return LeaveGroupAndDeleteLocalHistoryResult(
        status: LeaveGroupAndDeleteLocalHistoryStatus.preworkFailed,
        broadcastResult: broadcastResult,
        cause: cause,
      );
    }

    try {
      await callGroupLeave(bridge, groupId, timeout: nativeLeaveTimeout);
      _nativeLeaveCommittedGroups[groupId] = _ConfirmedLeaveMarker(
        peerId: snapshot.peerId,
        joinedAt: snapshot.selfJoinedAt,
      );
    } on TimeoutException catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_ACTIVE_EXIT_NATIVE_UNCERTAIN',
        details: const {
          'code': 'EX06',
          'phase': 'native',
          'severity': 'failure',
        },
      );
      return LeaveGroupAndDeleteLocalHistoryResult(
        status: LeaveGroupAndDeleteLocalHistoryStatus.nativeLeaveUncertain,
        broadcastResult: broadcastResult,
        cause: error,
      );
    } on BridgeCommandException catch (error) {
      if (error.command != 'group:leave') {
        return LeaveGroupAndDeleteLocalHistoryResult(
          status: LeaveGroupAndDeleteLocalHistoryStatus.nativeLeaveUncertain,
          broadcastResult: broadcastResult,
          cause: error,
        );
      }
      final rollbackError = await _rollbackTentativeArtifactsOrError(
        snapshot,
        timelineMessageId: tentativeTimelineMessageId,
      );
      return LeaveGroupAndDeleteLocalHistoryResult(
        status: LeaveGroupAndDeleteLocalHistoryStatus.nativeLeaveFailed,
        broadcastResult: broadcastResult,
        cause: rollbackError == null
            ? error
            : _combinedRollbackCause(error, rollbackError),
      );
    } catch (error) {
      // Without a negative native acknowledgement, an arbitrary transport or
      // decode failure cannot prove whether the command committed.
      return LeaveGroupAndDeleteLocalHistoryResult(
        status: LeaveGroupAndDeleteLocalHistoryStatus.nativeLeaveUncertain,
        broadcastResult: broadcastResult,
        cause: error,
      );
    }

    return _cleanupAfterConfirmedLeave(
      groupId,
      broadcastResult: broadcastResult,
    );
  }

  Future<LeaveGroupAndDeleteLocalHistoryResult> _cleanupAfterConfirmedLeave(
    String groupId, {
    required VoluntaryLeaveBroadcastResult? broadcastResult,
  }) async {
    Object? firstError;

    Future<void> attempt(Future<void> Function() cleanup) async {
      try {
        await cleanup();
      } catch (error) {
        firstError ??= error;
      }
    }

    await attempt(
      () =>
          groupMessageRepo?.deleteMessagesForGroup(groupId).then((_) {}) ??
          Future<void>.value(),
    );
    await attempt(() => groupRepo.removeAllMembers(groupId));
    await attempt(() => groupRepo.removeAllKeys(groupId));
    if (groupRepo is GroupKeyRotationDraftRepository) {
      await attempt(
        () => (groupRepo as GroupKeyRotationDraftRepository)
            .clearPendingKeyRotations(groupId),
      );
    }
    await attempt(() => groupRepo.deleteGroup(groupId));
    await attempt(() => groupRepo.clearGroupRejoinState(groupId));
    await attempt(() => discardPendingBroadcasts(groupId));

    final status = firstError == null
        ? LeaveGroupAndDeleteLocalHistoryStatus.left
        : LeaveGroupAndDeleteLocalHistoryStatus.leftCleanupIncomplete;
    if (firstError == null) {
      _nativeLeaveCommittedGroups.remove(groupId);
    }
    emitFlowEvent(
      layer: 'FL',
      event: firstError == null
          ? 'GROUP_ACTIVE_EXIT_LEFT'
          : 'GROUP_ACTIVE_EXIT_CLEANUP_INCOMPLETE',
      details: {
        if (firstError != null) 'code': 'EX07',
        'phase': 'cleanup',
        'severity': firstError == null ? 'info' : 'warning',
      },
    );
    return LeaveGroupAndDeleteLocalHistoryResult(
      status: status,
      broadcastResult: broadcastResult,
      cause: firstError,
    );
  }

  Future<_LeaveRollbackSnapshot?> _captureRollbackSnapshot(
    String groupId,
  ) async {
    final identity = await identityRepo.loadIdentity();
    final group = await groupRepo.getGroup(groupId);
    if (identity == null || group == null) return null;
    final selfMember = await groupRepo.getMember(groupId, identity.peerId);

    final retainedKeys = <GroupKeyInfo>[];
    final latestKey = await groupRepo.getLatestKey(groupId);
    if (latestKey != null) {
      final firstGeneration = minRetainedGroupKeyGeneration(
        latestKey.keyGeneration,
      );
      for (
        var generation = firstGeneration;
        generation <= latestKey.keyGeneration;
        generation++
      ) {
        final key = await groupRepo.getKeyByGeneration(groupId, generation);
        if (key != null) retainedKeys.add(key);
      }
    }
    final draftRepo = groupRepo is GroupKeyRotationDraftRepository
        ? groupRepo as GroupKeyRotationDraftRepository
        : null;
    final pendingDraft = await draftRepo?.getPendingKeyRotation(groupId);
    return _LeaveRollbackSnapshot(
      groupId: groupId,
      peerId: identity.peerId,
      selfJoinedAt: selfMember?.joinedAt.toUtc(),
      retainedKeys: retainedKeys,
      pendingDraft: pendingDraft,
    );
  }

  Future<void> _rollbackTentativeArtifacts(
    _LeaveRollbackSnapshot snapshot, {
    String? timelineMessageId,
  }) async {
    if (timelineMessageId != null) {
      await groupMessageRepo?.deleteMessage(timelineMessageId);
    }
    await groupRepo.removeAllKeys(snapshot.groupId);
    for (final key in snapshot.retainedKeys) {
      await groupRepo.saveKey(key);
    }
    if (groupRepo is GroupKeyRotationDraftRepository) {
      final draftRepo = groupRepo as GroupKeyRotationDraftRepository;
      await draftRepo.clearPendingKeyRotations(snapshot.groupId);
      final pendingDraft = snapshot.pendingDraft;
      if (pendingDraft != null) {
        await draftRepo.savePendingKeyRotation(pendingDraft);
      }
    }
  }

  Future<Object?> _rollbackTentativeArtifactsOrError(
    _LeaveRollbackSnapshot snapshot, {
    String? timelineMessageId,
  }) async {
    try {
      await _rollbackTentativeArtifacts(
        snapshot,
        timelineMessageId: timelineMessageId,
      );
      return null;
    } catch (error) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_ACTIVE_EXIT_ROLLBACK_FAILED',
        details: const {
          'code': 'EX03',
          'phase': 'notice',
          'severity': 'failure',
        },
      );
      return error;
    }
  }
}

StateError _combinedRollbackCause(Object original, Object rollbackError) =>
    StateError('$original; tentative rollback also failed: $rollbackError');

class _LeaveRollbackSnapshot {
  const _LeaveRollbackSnapshot({
    required this.groupId,
    required this.peerId,
    required this.selfJoinedAt,
    required this.retainedKeys,
    required this.pendingDraft,
  });

  final String groupId;
  final String peerId;
  final DateTime? selfJoinedAt;
  final List<GroupKeyInfo> retainedKeys;
  final GroupKeyInfo? pendingDraft;
}

class _ConfirmedLeaveMarker {
  const _ConfirmedLeaveMarker({required this.peerId, required this.joinedAt});

  final String peerId;
  final DateTime? joinedAt;
}

bool _hasPendingRoleTransition(
  Iterable<GroupPendingBroadcast> pending,
  String groupId,
) => pending.any(
  (row) =>
      row.groupId == groupId && isPendingGroupMemberRoleBroadcastKind(row.kind),
);
