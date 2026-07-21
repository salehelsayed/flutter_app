import 'dart:async';

import 'package:flutter_app/features/groups/application/group_exit_intent_runner.dart';
import 'package:flutter_app/features/groups/application/group_membership_event_watermark.dart';
import 'package:flutter_app/features/groups/application/group_pending_broadcast_runner.dart';
import 'package:flutter_app/features/groups/domain/models/group_exit_intent.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_broadcast.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_exit_intent_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_broadcast_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

enum GroupExitIntentRequestStatus {
  started,
  pendingRoleSync,
  queued,
  blockedLastAdmin,
  noOp,
  unavailable,
  failed,
}

class GroupExitIntentRequestResult {
  const GroupExitIntentRequestResult({
    required this.status,
    this.intent,
    this.cause,
  });

  final GroupExitIntentRequestStatus status;
  final GroupExitIntent? intent;
  final Object? cause;
}

enum GroupExitIntentCancelStatus {
  cancelled,
  tooLate,
  notFound,
  unavailable,
  failed,
}

class GroupExitIntentCancelResult {
  const GroupExitIntentCancelResult({
    required this.status,
    this.current,
    this.cause,
  });

  final GroupExitIntentCancelStatus status;
  final GroupExitIntent? current;
  final Object? cause;
}

/// Required-authority entry point shared by every active/stuck Leave surface.
///
/// Unlike legacy optional sinks, every readiness decision comes from concrete
/// repositories. Missing identity/storage/classification fails closed before
/// an intent or native action can be authorized.
class GroupExitIntentCoordinator {
  const GroupExitIntentCoordinator({
    required this.intentRepository,
    required this.pendingRepository,
    required this.pendingBroadcastRunner,
    required this.processor,
    required this.groupRepository,
    required this.identityRepository,
    required this.newId,
    required this.now,
  });

  final GroupExitIntentRepository intentRepository;
  final GroupPendingBroadcastRepository pendingRepository;
  final GroupPendingBroadcastRunner pendingBroadcastRunner;
  final GroupExitIntentProcessor processor;
  final GroupRepository groupRepository;
  final IdentityRepository identityRepository;
  final String Function() newId;
  final DateTime Function() now;

  /// Fresh active Leave. A role row pays exactly one coordinated immediate
  /// drain, followed by an authoritative reload; a count is never trusted.
  Future<GroupExitIntentRequestResult> requestLeave(String groupId) async {
    try {
      final existing = await intentRepository.forGroup(groupId);
      if (existing != null) {
        try {
          final processed = await processor.processGroup(groupId);
          return _mapExistingProcess(existing, processed);
        } catch (error) {
          return GroupExitIntentRequestResult(
            status: GroupExitIntentRequestStatus.failed,
            intent: existing,
            cause: error,
          );
        }
      }

      var authority = await _loadAuthority(groupId);
      if (authority.result != null) return authority.result!;

      var pending = await pendingRepository.forGroup(groupId);
      if (_hasRoleBroadcast(pending, groupId)) {
        try {
          await pendingBroadcastRunner.drainForGroup(groupId);
        } catch (error) {
          return GroupExitIntentRequestResult(
            status: GroupExitIntentRequestStatus.pendingRoleSync,
            cause: error,
          );
        }
        pending = await pendingRepository.forGroup(groupId);
        if (_hasRoleBroadcast(pending, groupId)) {
          return const GroupExitIntentRequestResult(
            status: GroupExitIntentRequestStatus.pendingRoleSync,
          );
        }
        // The role transition itself may have changed last-admin or membership
        // authority. Re-read everything after the coordinated drain.
        authority = await _loadAuthority(groupId);
        if (authority.result != null) return authority.result!;
      }

      if (authority.isLastAdmin) {
        return const GroupExitIntentRequestResult(
          status: GroupExitIntentRequestStatus.blockedLastAdmin,
        );
      }

      final enqueued = await _enqueue(groupId);
      if (enqueued.result != null) return enqueued.result!;
      final intent = enqueued.intent!;
      try {
        final processed = await processor.processGroup(
          groupId,
          // We already performed the only immediate role retry and fresh read.
          drainRoleBroadcasts: false,
        );
        return _mapNewProcess(intent, processed);
      } catch (error) {
        return GroupExitIntentRequestResult(
          status: GroupExitIntentRequestStatus.failed,
          intent: intent,
          cause: error,
        );
      }
    } catch (error) {
      return GroupExitIntentRequestResult(
        status: GroupExitIntentRequestStatus.unavailable,
        cause: error,
      );
    }
  }

  /// Persists the user's queued choice before returning. Processing is kicked
  /// after persistence but is not awaited, so the caller may dismiss/navigate.
  Future<GroupExitIntentRequestResult> queueLeaveWhenSyncCompletes(
    String groupId,
  ) async {
    try {
      final existing = await intentRepository.forGroup(groupId);
      if (existing != null) {
        return GroupExitIntentRequestResult(
          status: GroupExitIntentRequestStatus.queued,
          intent: existing,
        );
      }
      final authority = await _loadAuthority(groupId);
      if (authority.result != null) return authority.result!;
      if (authority.isLastAdmin) {
        final pending = await pendingRepository.forGroup(groupId);
        if (!_hasRoleBroadcast(pending, groupId)) {
          return const GroupExitIntentRequestResult(
            status: GroupExitIntentRequestStatus.blockedLastAdmin,
          );
        }
      }
      final enqueued = await _enqueue(groupId, allowPendingRole: true);
      if (enqueued.result != null) return enqueued.result!;
      final intent = enqueued.intent!;
      unawaited(
        processor
            .processGroup(groupId, drainRoleBroadcasts: false)
            .catchError(
              (_) => GroupExitIntentProcessResult(
                status: GroupExitIntentProcessStatus.failed,
                intent: intent,
              ),
            ),
      );
      return GroupExitIntentRequestResult(
        status: GroupExitIntentRequestStatus.queued,
        intent: intent,
      );
    } catch (error) {
      return GroupExitIntentRequestResult(
        status: GroupExitIntentRequestStatus.unavailable,
        cause: error,
      );
    }
  }

  Future<GroupExitIntentRequestResult> retry(String groupId) async {
    try {
      final existing = await intentRepository.forGroup(groupId);
      if (existing == null) return requestLeave(groupId);
      try {
        final processed = await processor.processGroup(groupId);
        return _mapExistingProcess(existing, processed);
      } catch (error) {
        return GroupExitIntentRequestResult(
          status: GroupExitIntentRequestStatus.failed,
          intent: existing,
          cause: error,
        );
      }
    } catch (error) {
      return GroupExitIntentRequestResult(
        status: GroupExitIntentRequestStatus.unavailable,
        cause: error,
      );
    }
  }

  Future<GroupExitIntentCancelResult> cancelQueued(String groupId) async {
    try {
      final current = await intentRepository.forGroup(groupId);
      if (current == null) {
        return const GroupExitIntentCancelResult(
          status: GroupExitIntentCancelStatus.notFound,
        );
      }
      if (!current.isCancelable) {
        return GroupExitIntentCancelResult(
          status: GroupExitIntentCancelStatus.tooLate,
          current: current,
        );
      }
      final mutation = await intentRepository.cancelQueued(
        current,
        updatedAt: now().toUtc(),
      );
      if (mutation.committed) {
        return const GroupExitIntentCancelResult(
          status: GroupExitIntentCancelStatus.cancelled,
        );
      }
      final fresh =
          mutation.current ?? await intentRepository.forGroup(groupId);
      if (mutation.disposition == GroupExitIntentMutationDisposition.absent ||
          mutation.disposition ==
              GroupExitIntentMutationDisposition.retiredStaleMembership) {
        // Cancellation began with a known queued intent, but the serialized
        // mutation observed that a worker/terminal lifecycle had already won
        // and removed it. This is a truthful too-late outcome, not a generic
        // leave failure; presentation must refresh the durable group state.
        return GroupExitIntentCancelResult(
          status: GroupExitIntentCancelStatus.tooLate,
          current: fresh,
        );
      }
      if (fresh != null && !fresh.isCancelable) {
        return GroupExitIntentCancelResult(
          status: GroupExitIntentCancelStatus.tooLate,
          current: fresh,
        );
      }
      return GroupExitIntentCancelResult(
        status: GroupExitIntentCancelStatus.failed,
        current: fresh,
      );
    } catch (error) {
      return GroupExitIntentCancelResult(
        status: GroupExitIntentCancelStatus.unavailable,
        cause: error,
      );
    }
  }

  Future<_ExitAuthority> _loadAuthority(String groupId) async {
    final identity = await identityRepository.loadIdentity();
    if (identity == null || identity.peerId.trim().isEmpty) {
      return _ExitAuthority.result(
        const GroupExitIntentRequestResult(
          status: GroupExitIntentRequestStatus.unavailable,
        ),
      );
    }
    final group = await groupRepository.getGroup(groupId);
    if (group == null || group.isDissolved || group.selfRemovedAt != null) {
      return _ExitAuthority.result(
        const GroupExitIntentRequestResult(
          status: GroupExitIntentRequestStatus.noOp,
        ),
      );
    }
    final self = await groupRepository.getMember(groupId, identity.peerId);
    if (self == null) {
      return _ExitAuthority.result(
        GroupExitIntentRequestResult(
          status: GroupExitIntentRequestStatus.unavailable,
          cause: StateError('Current self membership is unavailable.'),
        ),
      );
    }
    final members = await groupRepository.getMembers(groupId);
    final adminCount = members
        .where((member) => member.role == MemberRole.admin)
        .length;
    return _ExitAuthority.active(
      group: group,
      self: self,
      isLastAdmin: self.role == MemberRole.admin && adminCount <= 1,
    );
  }

  Future<_EnqueueResult> _enqueue(
    String groupId, {
    bool allowPendingRole = false,
  }) {
    return runGroupMembershipMutationLocked(
      groupId: groupId,
      action: () async {
        // This is the decisive leave claim. Repeat every mutable authority
        // read under the same phase used by role preparation and Dissolve.
        final authority = await _loadAuthority(groupId);
        if (authority.result != null) {
          return _EnqueueResult.result(authority.result!);
        }
        if (!allowPendingRole) {
          final pending = await pendingRepository.forGroup(groupId);
          if (_hasRoleBroadcast(pending, groupId)) {
            return _EnqueueResult.result(
              const GroupExitIntentRequestResult(
                status: GroupExitIntentRequestStatus.pendingRoleSync,
              ),
            );
          }
        }
        if (authority.isLastAdmin) {
          final mayQueueBehindRole =
              allowPendingRole &&
              _hasRoleBroadcast(
                await pendingRepository.forGroup(groupId),
                groupId,
              );
          if (!mayQueueBehindRole) {
            return _EnqueueResult.result(
              const GroupExitIntentRequestResult(
                status: GroupExitIntentRequestStatus.blockedLastAdmin,
              ),
            );
          }
        }

        final at = now().toUtc();
        final operationId = newId();
        final intent = GroupExitIntent(
          groupId: authority.group!.id,
          intentId: operationId,
          selfPeerId: authority.self!.peerId,
          selfJoinedAt: authority.self!.joinedAt.toUtc(),
          state: GroupExitIntentState.queued,
          pendingBroadcastId: 'group-exit-notice:${newId()}',
          createdAt: at,
          updatedAt: at,
        );
        final mutation = await intentRepository.enqueue(intent);
        if (mutation.committed) {
          return _EnqueueResult.intent(mutation.current ?? intent);
        }
        if (mutation.current != null) {
          return _EnqueueResult.intent(mutation.current!);
        }
        return _EnqueueResult.result(
          GroupExitIntentRequestResult(
            status: GroupExitIntentRequestStatus.failed,
            cause: StateError(
              'Exit intent enqueue refused: ${mutation.disposition.name}',
            ),
          ),
        );
      },
    );
  }

  GroupExitIntentRequestResult _mapNewProcess(
    GroupExitIntent intent,
    GroupExitIntentProcessResult processed,
  ) {
    switch (processed.status) {
      case GroupExitIntentProcessStatus.blockedLastAdmin:
        return GroupExitIntentRequestResult(
          status: GroupExitIntentRequestStatus.blockedLastAdmin,
          intent: processed.intent ?? intent,
          cause: processed.cause,
        );
      case GroupExitIntentProcessStatus.failed:
        return GroupExitIntentRequestResult(
          status: GroupExitIntentRequestStatus.failed,
          intent: processed.intent ?? intent,
          cause: processed.cause,
        );
      case GroupExitIntentProcessStatus.waitingForRoleSync:
        return GroupExitIntentRequestResult(
          status: GroupExitIntentRequestStatus.queued,
          intent: processed.intent ?? intent,
          cause: processed.cause,
        );
      default:
        return GroupExitIntentRequestResult(
          status: GroupExitIntentRequestStatus.started,
          intent: processed.intent ?? intent,
          cause: processed.cause,
        );
    }
  }

  GroupExitIntentRequestResult _mapExistingProcess(
    GroupExitIntent existing,
    GroupExitIntentProcessResult processed,
  ) {
    switch (processed.status) {
      case GroupExitIntentProcessStatus.noIntent:
      case GroupExitIntentProcessStatus.completed:
      case GroupExitIntentProcessStatus.retiredStaleMembership:
        return GroupExitIntentRequestResult(
          status: GroupExitIntentRequestStatus.noOp,
          cause: processed.cause,
        );
      case GroupExitIntentProcessStatus.failed:
        return GroupExitIntentRequestResult(
          status: GroupExitIntentRequestStatus.failed,
          intent: processed.intent ?? existing,
          cause: processed.cause,
        );
      case GroupExitIntentProcessStatus.blockedLastAdmin:
        return GroupExitIntentRequestResult(
          status: GroupExitIntentRequestStatus.blockedLastAdmin,
          intent: processed.intent ?? existing,
          cause: processed.cause,
        );
      case GroupExitIntentProcessStatus.waitingForRoleSync:
      case GroupExitIntentProcessStatus.waitingForNoticeRetry:
      case GroupExitIntentProcessStatus.waitingForNativeRetry:
        return GroupExitIntentRequestResult(
          status: GroupExitIntentRequestStatus.queued,
          intent: processed.intent ?? existing,
          cause: processed.cause,
        );
    }
  }
}

bool _hasRoleBroadcast(Iterable<GroupPendingBroadcast> rows, String groupId) =>
    rows.any(
      (row) =>
          row.groupId == groupId &&
          isPendingGroupMemberRoleBroadcastKind(row.kind),
    );

class _ExitAuthority {
  const _ExitAuthority.active({
    required this.group,
    required this.self,
    required this.isLastAdmin,
  }) : result = null;

  const _ExitAuthority.result(this.result)
    : group = null,
      self = null,
      isLastAdmin = false;

  final GroupModel? group;
  final GroupMember? self;
  final bool isLastAdmin;
  final GroupExitIntentRequestResult? result;
}

class _EnqueueResult {
  const _EnqueueResult.intent(this.intent) : result = null;
  const _EnqueueResult.result(this.result) : intent = null;

  final GroupExitIntent? intent;
  final GroupExitIntentRequestResult? result;
}
