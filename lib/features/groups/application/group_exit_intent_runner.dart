import 'dart:async';

import 'package:flutter_app/features/groups/application/broadcast_voluntary_leave_use_case.dart';
import 'package:flutter_app/features/groups/application/group_membership_event_watermark.dart';
import 'package:flutter_app/features/groups/application/group_pending_broadcast_runner.dart';
import 'package:flutter_app/features/groups/domain/models/group_exit_intent.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_broadcast.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_exit_intent_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_pending_broadcast_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

class GroupExitPreparedNotice {
  const GroupExitPreparedNotice({
    required this.timelineMessage,
    required this.pendingBroadcast,
  });

  final GroupMessage timelineMessage;
  final GroupPendingBroadcast pendingBroadcast;
}

enum GroupExitNoticeAttemptDisposition { delivered, degraded, retryable }

/// Normal best-effort key rotation could not run (for example this leaver is
/// not the creator/authorized rotator). The runner records the bounded durable
/// diagnostic and proceeds to idempotent native leave.
class GroupExitRotationDeferred implements Exception {
  const GroupExitRotationDeferred();
}

enum GroupExitIntentProcessStatus {
  noIntent,
  waitingForRoleSync,
  blockedLastAdmin,
  waitingForNoticeRetry,
  waitingForNativeRetry,
  completed,
  retiredStaleMembership,
  failed,
}

class GroupExitIntentProcessResult {
  const GroupExitIntentProcessResult({
    required this.status,
    this.intent,
    this.cause,
  });

  final GroupExitIntentProcessStatus status;
  final GroupExitIntent? intent;
  final Object? cause;
}

typedef PrepareGroupExitNotice =
    Future<GroupExitPreparedNotice> Function({
      required GroupExitIntent intent,
      required String sourceEventId,
      required DateTime eventAt,
    });
typedef AttemptGroupExitNotice =
    Future<GroupExitNoticeAttemptDisposition> Function({
      required GroupExitIntent intent,
      required GroupPendingBroadcast pendingBroadcast,
    });
typedef RotateGroupExitKeys = Future<void> Function(GroupExitIntent intent);
typedef NativeLeaveGroup = Future<void> Function(GroupExitIntent intent);
typedef LoadCurrentGroupExitSelfPeerId = Future<String?> Function();

abstract interface class GroupExitIntentProcessor {
  Future<GroupExitIntentProcessResult> processGroup(
    String groupId, {
    bool drainRoleBroadcasts = true,
  });

  Future<Map<String, GroupExitIntentProcessResult>> processAll();
}

/// Advances durable voluntary-leave work one event-driven pass at a time.
///
/// Same-group triggers share an identity-safe tail. A pass can cross adjacent
/// deterministic phases, but it attempts each external phase at most once and
/// stops immediately on role, notice, native, or authority uncertainty.
class GroupExitIntentRunner implements GroupExitIntentProcessor {
  GroupExitIntentRunner({
    required this.intentRepository,
    required this.pendingRepository,
    required this.pendingBroadcastRunner,
    required this.groupRepository,
    required this.loadCurrentSelfPeerId,
    required this.prepareNotice,
    required this.attemptNotice,
    required this.rotateKeys,
    required this.nativeLeave,
    DateTime Function()? now,
  }) : _now = now ?? (() => DateTime.now().toUtc());

  final GroupExitIntentRepository intentRepository;
  final GroupPendingBroadcastRepository pendingRepository;
  final GroupPendingBroadcastRunner pendingBroadcastRunner;
  final GroupRepository groupRepository;
  final LoadCurrentGroupExitSelfPeerId loadCurrentSelfPeerId;
  final PrepareGroupExitNotice prepareNotice;
  final AttemptGroupExitNotice attemptNotice;
  final RotateGroupExitKeys rotateKeys;
  final NativeLeaveGroup nativeLeave;
  final DateTime Function() _now;

  final Map<String, Future<void>> _tails = <String, Future<void>>{};

  @override
  Future<GroupExitIntentProcessResult> processGroup(
    String groupId, {
    bool drainRoleBroadcasts = true,
  }) {
    final result = Completer<GroupExitIntentProcessResult>();
    final previous = _tails[groupId] ?? Future<void>.value();
    late final Future<void> current;
    current = previous
        .then((_) async {
          try {
            result.complete(
              await _processGroup(
                groupId,
                drainRoleBroadcasts: drainRoleBroadcasts,
              ),
            );
          } catch (error, stackTrace) {
            result.completeError(error, stackTrace);
          }
        })
        .whenComplete(() {
          if (identical(_tails[groupId], current)) _tails.remove(groupId);
        });
    _tails[groupId] = current;
    return result.future;
  }

  /// Processes every discovered intent with per-group error isolation.
  @override
  Future<Map<String, GroupExitIntentProcessResult>> processAll() async {
    final discovered = await intentRepository.all();
    final results = <String, GroupExitIntentProcessResult>{};
    await Future.wait(
      discovered.map((intent) async {
        try {
          results[intent.groupId] = await processGroup(intent.groupId);
        } catch (error) {
          results[intent.groupId] = GroupExitIntentProcessResult(
            status: GroupExitIntentProcessStatus.failed,
            intent: intent,
            cause: error,
          );
        }
      }),
    );
    return results;
  }

  Future<GroupExitIntentProcessResult> _processGroup(
    String groupId, {
    required bool drainRoleBroadcasts,
  }) async {
    var mayDrainRoleBroadcasts = drainRoleBroadcasts;
    var sawIntent = false;

    // Six durable states plus bounded CAS reloads. No failure path spins.
    for (var step = 0; step < 16; step++) {
      final loaded = await intentRepository.forGroup(groupId);
      if (loaded == null) {
        return GroupExitIntentProcessResult(
          status: sawIntent
              ? GroupExitIntentProcessStatus.completed
              : GroupExitIntentProcessStatus.noIntent,
        );
      }
      sawIntent = true;

      if (loaded.state == GroupExitIntentState.queued &&
          mayDrainRoleBroadcasts) {
        final preDrainGate =
            await runGroupMembershipMutationLocked<
              ({bool mayDrain, _IntentStep step})
            >(
              groupId: groupId,
              action: () async {
                final current = await intentRepository.forGroup(groupId);
                if (current == null ||
                    !sameExactGroupExitIntent(current, loaded)) {
                  return (mayDrain: false, step: const _IntentStep.reload());
                }
                final authorityStep = await _authorityAndOwnershipStepLocked(
                  current,
                );
                return (
                  mayDrain: authorityStep == null,
                  step: authorityStep ?? const _IntentStep.reload(),
                );
              },
            );
        if (!preDrainGate.mayDrain) {
          final terminal = preDrainGate.step.result;
          if (terminal != null) return terminal;
          continue;
        }
        mayDrainRoleBroadcasts = false;
        try {
          await pendingBroadcastRunner.drainForGroup(groupId);
        } catch (error) {
          return GroupExitIntentProcessResult(
            status: GroupExitIntentProcessStatus.waitingForRoleSync,
            intent: loaded,
            cause: error,
          );
        }
      }

      final stateResult = await runGroupMembershipMutationLocked<_IntentStep>(
        groupId: groupId,
        action: () async {
          final current = await intentRepository.forGroup(groupId);
          if (current == null) return const _IntentStep.reload();
          if (!sameExactGroupExitIntent(current, loaded)) {
            return const _IntentStep.reload();
          }
          return _processStateLocked(current);
        },
      );
      final terminal = stateResult.result;
      if (terminal != null) return terminal;
    }

    final current = await intentRepository.forGroup(groupId);
    return GroupExitIntentProcessResult(
      status: GroupExitIntentProcessStatus.failed,
      intent: current,
      cause: StateError('Group exit state did not settle in a bounded pass.'),
    );
  }

  Future<_IntentStep> _processStateLocked(GroupExitIntent intent) async {
    final authorityStep = await _authorityAndOwnershipStepLocked(intent);
    if (authorityStep != null) return authorityStep;
    final lastAdminStep = await _lastAdminGuardStepLocked(intent);
    if (lastAdminStep != null) return lastAdminStep;

    switch (intent.state) {
      case GroupExitIntentState.queued:
        return _prepareQueuedIntent(intent);
      case GroupExitIntentState.leaveNoticePending:
        return _attemptPendingNotice(intent);
      case GroupExitIntentState.leaveNoticeAttempted:
        return _claimAndRunRotation(intent);
      case GroupExitIntentState.rotationClaimed:
        // A process that starts in this phase cannot know whether the claimant
        // crashed before or after rotation. Preserve at-most-once semantics.
        final advanced = await intentRepository.advance(
          expected: intent,
          nextState: GroupExitIntentState.nativeLeavePending,
          updatedAt: _nowUtc(),
          lastErrorCode: 'rotation_deferred_restart',
        );
        return advanced.committed
            ? const _IntentStep.reload()
            : _mutationStep(intent, advanced);
      case GroupExitIntentState.nativeLeavePending:
        return _attemptNativeLeave(intent);
      case GroupExitIntentState.cleanupPending:
        return _cleanup(intent);
    }
  }

  /// Resolves terminal membership authority before consulting the active
  /// account. Terminal and later-generation cleanup is local exact retirement;
  /// it must remain possible after logout/account switch and must never expose
  /// queued broadcasts to the replacement identity.
  Future<_IntentStep?> _authorityAndOwnershipStepLocked(
    GroupExitIntent intent,
  ) async {
    final authority = await _loadAuthority(intent);
    switch (authority.disposition) {
      case _IntentAuthorityDisposition.active:
        break;
      case _IntentAuthorityDisposition.ambiguous:
        return _IntentStep.result(
          GroupExitIntentProcessResult(
            status: GroupExitIntentProcessStatus.failed,
            intent: intent,
            cause: authority.cause,
          ),
        );
      case _IntentAuthorityDisposition.terminal:
        await intentRepository.retireExact(intent);
        return _IntentStep.result(
          GroupExitIntentProcessResult(
            status: GroupExitIntentProcessStatus.completed,
            intent: intent,
          ),
        );
      case _IntentAuthorityDisposition.newerMembership:
        await intentRepository.retireExact(intent);
        return _IntentStep.result(
          GroupExitIntentProcessResult(
            status: GroupExitIntentProcessStatus.retiredStaleMembership,
            intent: intent,
          ),
        );
    }

    final String? currentSelfPeerId;
    try {
      currentSelfPeerId = (await loadCurrentSelfPeerId())?.trim();
    } catch (error) {
      return _IntentStep.result(
        GroupExitIntentProcessResult(
          status: GroupExitIntentProcessStatus.failed,
          intent: intent,
          cause: error,
        ),
      );
    }
    if (currentSelfPeerId == null ||
        currentSelfPeerId.isEmpty ||
        currentSelfPeerId != intent.selfPeerId) {
      return _IntentStep.result(
        GroupExitIntentProcessResult(
          status: GroupExitIntentProcessStatus.failed,
          intent: intent,
          cause: StateError(
            'Current identity does not own this group exit intent.',
          ),
        ),
      );
    }
    return null;
  }

  Future<_IntentStep> _prepareQueuedIntent(GroupExitIntent intent) async {
    final pending = await pendingRepository.forGroup(intent.groupId);
    if (pending.any((row) => isPendingGroupMemberRoleBroadcastKind(row.kind))) {
      return _IntentStep.result(
        GroupExitIntentProcessResult(
          status: GroupExitIntentProcessStatus.waitingForRoleSync,
          intent: intent,
        ),
      );
    }

    final group = await groupRepository.getGroup(intent.groupId);

    var eventAt = intent.createdAt.toUtc();
    final watermark = group?.lastMembershipEventAt?.toUtc();
    if (watermark != null && !eventAt.isAfter(watermark)) {
      eventAt = watermark.add(const Duration(microseconds: 1));
    }
    final sourceEventId =
        'member_removed:${intent.groupId}:${intent.selfPeerId}:${intent.intentId}';

    final GroupExitPreparedNotice prepared;
    try {
      prepared = await prepareNotice(
        intent: intent,
        sourceEventId: sourceEventId,
        eventAt: eventAt,
      );
    } on VoluntaryLeaveLastAdminPreparationRefused {
      return _IntentStep.result(
        GroupExitIntentProcessResult(
          status: GroupExitIntentProcessStatus.blockedLastAdmin,
          intent: intent,
        ),
      );
    } catch (error) {
      return _IntentStep.result(
        GroupExitIntentProcessResult(
          status: GroupExitIntentProcessStatus.failed,
          intent: intent,
          cause: error,
        ),
      );
    }
    final notice = prepared.pendingBroadcast;
    if (notice.id != intent.pendingBroadcastId ||
        notice.groupId != intent.groupId ||
        notice.kind != groupPendingBroadcastKindExitLeaveNotice ||
        notice.sourceMessageId != sourceEventId ||
        !notice.eventAt.toUtc().isAtSameMomentAs(eventAt) ||
        !hasExactSignedVoluntaryLeaveNoticeAuthority(
          pendingBroadcast: notice,
          expectedGroupId: intent.groupId,
          expectedSelfPeerId: intent.selfPeerId,
          expectedSourceEventId: sourceEventId,
          expectedEventAt: eventAt,
        ) ||
        prepared.timelineMessage.groupId != intent.groupId ||
        prepared.timelineMessage.senderPeerId != intent.selfPeerId ||
        prepared.timelineMessage.id !=
            'sys-member_removed:${intent.groupId}:${intent.selfPeerId}:'
                '${intent.selfPeerId}:${eventAt.microsecondsSinceEpoch}' ||
        !prepared.timelineMessage.timestamp.toUtc().isAtSameMomentAs(eventAt)) {
      return _IntentStep.result(
        GroupExitIntentProcessResult(
          status: GroupExitIntentProcessStatus.failed,
          intent: intent,
          cause: StateError('Prepared leave notice identity is inconsistent.'),
        ),
      );
    }

    final mutation = await intentRepository.prepareLeaveNotice(
      expected: intent,
      timelineMessage: prepared.timelineMessage,
      pendingBroadcast: notice,
      updatedAt: _nowUtc(),
    );
    if (mutation.committed) return const _IntentStep.reload();
    if (mutation.disposition ==
        GroupExitIntentMutationDisposition.refusedLastAdmin) {
      return _IntentStep.result(
        GroupExitIntentProcessResult(
          status: GroupExitIntentProcessStatus.blockedLastAdmin,
          intent: mutation.current ?? intent,
        ),
      );
    }
    if (mutation.disposition ==
        GroupExitIntentMutationDisposition.refusedRoleBroadcastPresent) {
      return _IntentStep.result(
        GroupExitIntentProcessResult(
          status: GroupExitIntentProcessStatus.waitingForRoleSync,
          intent: mutation.current ?? intent,
        ),
      );
    }
    return _mutationStep(intent, mutation);
  }

  Future<_IntentStep> _attemptPendingNotice(GroupExitIntent intent) async {
    final rows = await pendingRepository.forGroup(intent.groupId);
    GroupPendingBroadcast? notice;
    for (final row in rows) {
      if (row.id == intent.pendingBroadcastId) {
        notice = row;
        break;
      }
    }
    if (notice == null ||
        notice.kind != groupPendingBroadcastKindExitLeaveNotice ||
        notice.sourceMessageId != intent.sourceEventId ||
        intent.eventAt == null ||
        !notice.eventAt.toUtc().isAtSameMomentAs(intent.eventAt!.toUtc()) ||
        !hasExactSignedVoluntaryLeaveNoticeAuthority(
          pendingBroadcast: notice,
          expectedGroupId: intent.groupId,
          expectedSelfPeerId: intent.selfPeerId,
          expectedSourceEventId: intent.sourceEventId!,
          expectedEventAt: intent.eventAt!,
        )) {
      return _IntentStep.result(
        GroupExitIntentProcessResult(
          status: GroupExitIntentProcessStatus.waitingForNoticeRetry,
          intent: intent,
          cause: StateError('Exact durable leave notice is unavailable.'),
        ),
      );
    }

    final GroupExitNoticeAttemptDisposition attempt;
    try {
      attempt = await attemptNotice(intent: intent, pendingBroadcast: notice);
    } catch (error) {
      return _IntentStep.result(
        GroupExitIntentProcessResult(
          status: GroupExitIntentProcessStatus.waitingForNoticeRetry,
          intent: intent,
          cause: error,
        ),
      );
    }
    if (attempt == GroupExitNoticeAttemptDisposition.retryable) {
      return _IntentStep.result(
        GroupExitIntentProcessResult(
          status: GroupExitIntentProcessStatus.waitingForNoticeRetry,
          intent: intent,
        ),
      );
    }

    final mutation = await intentRepository.completeLeaveNoticeAttempt(
      expected: intent,
      pendingBroadcast: notice,
      completionCode: attempt == GroupExitNoticeAttemptDisposition.delivered
          ? 'notice_delivered'
          : 'notice_degraded',
      updatedAt: _nowUtc(),
    );
    return mutation.committed
        ? const _IntentStep.reload()
        : _mutationStep(intent, mutation);
  }

  Future<_IntentStep> _claimAndRunRotation(GroupExitIntent intent) async {
    final claimed = await intentRepository.advance(
      expected: intent,
      nextState: GroupExitIntentState.rotationClaimed,
      updatedAt: _nowUtc(),
    );
    if (!claimed.committed || claimed.current == null) {
      return _mutationStep(intent, claimed);
    }

    String? rotationError;
    try {
      await rotateKeys(claimed.current!);
    } catch (_) {
      rotationError = 'rotation_deferred';
    }
    final advanced = await intentRepository.advance(
      expected: claimed.current!,
      nextState: GroupExitIntentState.nativeLeavePending,
      updatedAt: _nowUtc(),
      lastErrorCode: rotationError,
    );
    return advanced.committed
        ? const _IntentStep.reload()
        : _mutationStep(claimed.current!, advanced);
  }

  Future<_IntentStep> _attemptNativeLeave(GroupExitIntent intent) async {
    try {
      await nativeLeave(intent);
    } catch (error) {
      return _IntentStep.result(
        GroupExitIntentProcessResult(
          status: GroupExitIntentProcessStatus.waitingForNativeRetry,
          intent: intent,
          cause: error,
        ),
      );
    }
    final advanced = await intentRepository.advance(
      expected: intent,
      nextState: GroupExitIntentState.cleanupPending,
      updatedAt: _nowUtc(),
    );
    return advanced.committed
        ? const _IntentStep.reload()
        : _mutationStep(intent, advanced);
  }

  Future<_IntentStep> _cleanup(GroupExitIntent intent) async {
    final GroupExitIntentMutationResult mutation;
    final cleanupRepository = groupRepository;
    if (cleanupRepository is! GroupExitCleanupRepository) {
      return _IntentStep.result(
        GroupExitIntentProcessResult(
          status: GroupExitIntentProcessStatus.failed,
          intent: intent,
          cause: StateError(
            'Strict voluntary-exit external cleanup is unavailable.',
          ),
        ),
      );
    }
    final strictCleanupRepository =
        cleanupRepository as GroupExitCleanupRepository;
    try {
      mutation = await strictCleanupRepository
          .cleanupExactVoluntaryExit<GroupExitIntentMutationResult>(
            groupId: intent.groupId,
            selfPeerId: intent.selfPeerId,
            selfJoinedAt: intent.selfJoinedAt,
            finalizeSql: () =>
                intentRepository.cleanupOrRetire(intent, updatedAt: _nowUtc()),
          );
    } catch (error) {
      return _IntentStep.result(
        GroupExitIntentProcessResult(
          status: GroupExitIntentProcessStatus.failed,
          intent: intent,
          cause: error,
        ),
      );
    }
    switch (mutation.disposition) {
      case GroupExitIntentMutationDisposition.committed:
      case GroupExitIntentMutationDisposition.cleanupAlreadyComplete:
        return _IntentStep.result(
          GroupExitIntentProcessResult(
            status: GroupExitIntentProcessStatus.completed,
            intent: intent,
          ),
        );
      case GroupExitIntentMutationDisposition.retiredStaleMembership:
        return _IntentStep.result(
          GroupExitIntentProcessResult(
            status: GroupExitIntentProcessStatus.retiredStaleMembership,
            intent: intent,
          ),
        );
      default:
        return _mutationStep(intent, mutation);
    }
  }

  Future<_IntentAuthority> _loadAuthority(GroupExitIntent intent) async {
    final group = await groupRepository.getGroup(intent.groupId);
    if (group == null || group.isDissolved || group.selfRemovedAt != null) {
      return const _IntentAuthority(_IntentAuthorityDisposition.terminal);
    }
    final self = await groupRepository.getMember(
      intent.groupId,
      intent.selfPeerId,
    );
    if (self == null) {
      return _IntentAuthority(
        _IntentAuthorityDisposition.ambiguous,
        cause: StateError('Current self membership is unavailable.'),
      );
    }
    if (!self.joinedAt.toUtc().isAtSameMomentAs(intent.selfJoinedAt.toUtc())) {
      return const _IntentAuthority(
        _IntentAuthorityDisposition.newerMembership,
      );
    }
    return const _IntentAuthority(_IntentAuthorityDisposition.active);
  }

  /// Enforces the last-admin invariant at the final reversible boundary.
  ///
  /// Once the signed leave notice is durably claimed, delivery is ambiguous: a
  /// peer may already have removed this actor. Pausing a later phase to create a
  /// successor role update cannot converge because leave-first peers reject the
  /// now-absent actor, while promotion-first peers can be overwritten by the
  /// immutable leave snapshot. Post-notice phases therefore remain irreversible;
  /// only [GroupExitIntentState.queued] may stop for last-admin recovery.
  Future<_IntentStep?> _lastAdminGuardStepLocked(GroupExitIntent intent) async {
    if (intent.state != GroupExitIntentState.queued) return null;

    final List<GroupMember> members;
    try {
      members = await groupRepository.getMembers(intent.groupId);
    } catch (error) {
      return _IntentStep.result(
        GroupExitIntentProcessResult(
          status: GroupExitIntentProcessStatus.failed,
          intent: intent,
          cause: error,
        ),
      );
    }
    GroupMember? exactSelf;
    for (final member in members) {
      if (member.peerId == intent.selfPeerId &&
          member.joinedAt.toUtc().isAtSameMomentAs(
            intent.selfJoinedAt.toUtc(),
          )) {
        exactSelf = member;
        break;
      }
    }
    if (exactSelf == null) {
      return _IntentStep.result(
        GroupExitIntentProcessResult(
          status: GroupExitIntentProcessStatus.failed,
          intent: intent,
          cause: StateError(
            'Exact self membership is unavailable for last-admin validation.',
          ),
        ),
      );
    }
    final adminCount = members
        .where((member) => member.role == MemberRole.admin)
        .length;
    if (exactSelf.role != MemberRole.admin || adminCount > 1) return null;
    return _IntentStep.result(
      GroupExitIntentProcessResult(
        status: GroupExitIntentProcessStatus.blockedLastAdmin,
        intent: intent,
      ),
    );
  }

  _IntentStep _mutationStep(
    GroupExitIntent expected,
    GroupExitIntentMutationResult mutation,
  ) {
    if (mutation.disposition ==
        GroupExitIntentMutationDisposition.retiredStaleMembership) {
      return _IntentStep.result(
        GroupExitIntentProcessResult(
          status: GroupExitIntentProcessStatus.retiredStaleMembership,
          intent: mutation.current ?? expected,
        ),
      );
    }
    if (mutation.disposition == GroupExitIntentMutationDisposition.absent ||
        mutation.disposition ==
            GroupExitIntentMutationDisposition.alreadyCurrent ||
        mutation.disposition ==
            GroupExitIntentMutationDisposition.refusedConflict) {
      return const _IntentStep.reload();
    }
    return _IntentStep.result(
      GroupExitIntentProcessResult(
        status: GroupExitIntentProcessStatus.failed,
        intent: mutation.current ?? expected,
        cause: StateError(
          'Group exit mutation refused: ${mutation.disposition.name}',
        ),
      ),
    );
  }

  DateTime _nowUtc() => _now().toUtc();
}

class _IntentStep {
  const _IntentStep.reload() : result = null;
  const _IntentStep.result(this.result);

  final GroupExitIntentProcessResult? result;
}

enum _IntentAuthorityDisposition {
  active,
  terminal,
  newerMembership,
  ambiguous,
}

class _IntentAuthority {
  const _IntentAuthority(this.disposition, {this.cause});

  final _IntentAuthorityDisposition disposition;
  final Object? cause;
}
