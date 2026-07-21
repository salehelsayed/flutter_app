// ignore_for_file: prefer_initializing_formals

import 'dart:async';

import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/features/groups/application/broadcast_voluntary_leave_use_case.dart';
import 'package:flutter_app/features/groups/application/group_exit_release_diagnostics.dart';
import 'package:flutter_app/features/groups/domain/models/group_exit_diagnostic.dart';
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

/// Closed, non-sensitive vocabulary persisted in
/// [GroupExitIntent.lastErrorCode].
///
/// Unknown legacy values are canonicalized to a fixed allowlisted outcome so
/// raw text can never flow into a later durable transition or stop an already
/// signed, irreversible leave.
enum GroupExitPersistedOutcome {
  noticeDelivered('notice_delivered'),
  noticeDegraded('notice_degraded'),
  rotationDeferred('rotation_deferred'),
  rotationDeferredRestart('rotation_deferred_restart'),
  noticeDegradedRotationDeferred('notice_degraded:rotation_deferred'),
  noticeDegradedRotationDeferredRestart(
    'notice_degraded:rotation_deferred_restart',
  ),
  legacyUnknown('legacy_unknown'),
  legacyUnknownRotationDeferred('legacy_unknown:rotation_deferred'),
  legacyUnknownRotationDeferredRestart(
    'legacy_unknown:rotation_deferred_restart',
  );

  const GroupExitPersistedOutcome(this.persistedCode);

  final String persistedCode;

  static GroupExitPersistedOutcome? fromPersistedCode(String? code) {
    if (code == null) return null;
    for (final outcome in values) {
      if (outcome.persistedCode == code) return outcome;
    }
    return GroupExitPersistedOutcome.legacyUnknown;
  }
}

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
  }) : diagnosticFacts = const <GroupExitProcessDiagnosticFact>[];

  GroupExitIntentProcessResult.withDiagnosticFacts({
    required this.status,
    this.intent,
    this.cause,
    required Iterable<GroupExitProcessDiagnosticFact> diagnosticFacts,
  }) : diagnosticFacts = immutableGroupExitDiagnosticFacts(diagnosticFacts);

  final GroupExitIntentProcessStatus status;
  final GroupExitIntent? intent;
  final Object? cause;
  final List<GroupExitProcessDiagnosticFact> diagnosticFacts;

  GroupExitIntentProcessResult withDiagnosticFacts(
    Iterable<GroupExitProcessDiagnosticFact> facts,
  ) {
    final immutable = immutableGroupExitDiagnosticFacts(
      <GroupExitProcessDiagnosticFact>[...diagnosticFacts, ...facts],
    );
    if (immutable.isEmpty && diagnosticFacts.isEmpty) return this;
    return GroupExitIntentProcessResult.withDiagnosticFacts(
      status: status,
      intent: intent,
      cause: cause,
      diagnosticFacts: immutable,
    );
  }
}

/// The non-throwing execution form used by the diagnosing composition boundary.
class GroupExitIntentProcessExecution {
  GroupExitIntentProcessExecution.result({
    required GroupExitIntentProcessResult result,
    required this.intent,
  }) : result = result,
       diagnosticFacts = result.diagnosticFacts,
       error = null,
       stackTrace = null;

  GroupExitIntentProcessExecution.error({
    required Object error,
    required StackTrace stackTrace,
    required this.intent,
    required Iterable<GroupExitProcessDiagnosticFact> diagnosticFacts,
  }) : error = error,
       stackTrace = stackTrace,
       diagnosticFacts = immutableGroupExitDiagnosticFacts(diagnosticFacts),
       result = null;

  final GroupExitIntentProcessResult? result;
  final Object? error;
  final StackTrace? stackTrace;
  final GroupExitIntent? intent;
  final List<GroupExitProcessDiagnosticFact> diagnosticFacts;

  bool get hasError => error != null;

  GroupExitIntentProcessResult replay() {
    final failure = error;
    if (failure != null) {
      Error.throwWithStackTrace(failure, stackTrace!);
    }
    return result!;
  }
}

class GroupExitIntentProcessAllExecution {
  const GroupExitIntentProcessAllExecution.result(
    Map<String, GroupExitIntentProcessResult> result,
  ) : result = result,
      error = null,
      stackTrace = null;

  const GroupExitIntentProcessAllExecution.error({
    required Object error,
    required StackTrace stackTrace,
  }) : error = error,
       stackTrace = stackTrace,
       result = null;

  final Map<String, GroupExitIntentProcessResult>? result;
  final Object? error;
  final StackTrace? stackTrace;

  Map<String, GroupExitIntentProcessResult> replay() {
    final failure = error;
    if (failure != null) {
      Error.throwWithStackTrace(failure, stackTrace!);
    }
    return result!;
  }
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

/// Optional diagnostic-aware form. Production decorators and the coordinator
/// use it to retain typed facts while preserving the normal throwing contract.
abstract interface class GroupExitIntentExecutionProcessor {
  Future<GroupExitIntentProcessExecution> executeGroup(
    String groupId, {
    bool drainRoleBroadcasts = true,
    GroupExitIntent? knownIntent,
  });

  Future<GroupExitIntentProcessAllExecution> executeAll();
}

/// Advances durable voluntary-leave work one event-driven pass at a time.
///
/// Same-group triggers share an identity-safe tail. A pass can cross adjacent
/// deterministic phases, but it attempts each external phase at most once and
/// stops immediately on role, notice, native, or authority uncertainty.
class GroupExitIntentRunner
    implements GroupExitIntentProcessor, GroupExitIntentExecutionProcessor {
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
  }) async => (await executeGroup(
    groupId,
    drainRoleBroadcasts: drainRoleBroadcasts,
  )).replay();

  @override
  Future<GroupExitIntentProcessExecution> executeGroup(
    String groupId, {
    bool drainRoleBroadcasts = true,
    GroupExitIntent? knownIntent,
  }) {
    final result = Completer<GroupExitIntentProcessExecution>();
    final previous = _tails[groupId] ?? Future<void>.value();
    GroupExitIntentProcessExecution? execution;
    late final Future<void> current;
    current = previous
        .then((_) async {
          execution = await _executeGroupPass(
            groupId,
            drainRoleBroadcasts: drainRoleBroadcasts,
            knownIntent: knownIntent,
          );
        })
        .whenComplete(() {
          if (identical(_tails[groupId], current)) _tails.remove(groupId);
          result.complete(execution!);
        });
    _tails[groupId] = current;
    return result.future;
  }

  /// Processes every discovered intent with per-group error isolation.
  @override
  Future<Map<String, GroupExitIntentProcessResult>> processAll() async =>
      (await executeAll()).replay();

  @override
  Future<GroupExitIntentProcessAllExecution> executeAll() async {
    final List<GroupExitIntent> discovered;
    try {
      discovered = await intentRepository.all();
    } catch (error, stackTrace) {
      return GroupExitIntentProcessAllExecution.error(
        error: error,
        stackTrace: stackTrace,
      );
    }
    final results = <String, GroupExitIntentProcessResult>{};
    await Future.wait(
      discovered.map((intent) async {
        final execution = await executeGroup(
          intent.groupId,
          knownIntent: intent,
        );
        if (execution.hasError) {
          results[intent.groupId] =
              GroupExitIntentProcessResult.withDiagnosticFacts(
                status: GroupExitIntentProcessStatus.failed,
                intent: execution.intent ?? intent,
                cause: execution.error,
                diagnosticFacts: execution.diagnosticFacts,
              );
          return;
        }
        final processed = execution.result!;
        results[intent.groupId] =
            processed.intent == null && execution.diagnosticFacts.isNotEmpty
            ? GroupExitIntentProcessResult.withDiagnosticFacts(
                status: processed.status,
                intent: execution.intent ?? intent,
                cause: processed.cause,
                diagnosticFacts: execution.diagnosticFacts,
              )
            : processed;
      }),
    );
    return GroupExitIntentProcessAllExecution.result(results);
  }

  Future<GroupExitIntentProcessExecution> _executeGroupPass(
    String groupId, {
    required bool drainRoleBroadcasts,
    required GroupExitIntent? knownIntent,
  }) async {
    final tracker = _GroupExitDiagnosticTracker(knownIntent);
    try {
      final rawResult = await _processGroup(
        groupId,
        drainRoleBroadcasts: drainRoleBroadcasts,
        tracker: tracker,
      );
      tracker.observeIntent(rawResult.intent);
      final result = rawResult.withDiagnosticFacts(tracker.facts);
      return GroupExitIntentProcessExecution.result(
        result: result,
        intent: tracker.intent ?? result.intent,
      );
    } catch (error, stackTrace) {
      if (error is GroupExitTypedProcessFailure) {
        tracker.add(error.fact);
        return GroupExitIntentProcessExecution.error(
          error: error.cause,
          stackTrace: error.stackTrace,
          intent: tracker.intent,
          diagnosticFacts: tracker.facts,
        );
      }
      tracker.addFallback();
      return GroupExitIntentProcessExecution.error(
        error: error,
        stackTrace: stackTrace,
        intent: tracker.intent,
        diagnosticFacts: tracker.facts,
      );
    }
  }

  Future<GroupExitIntentProcessResult> _processGroup(
    String groupId, {
    required bool drainRoleBroadcasts,
    required _GroupExitDiagnosticTracker tracker,
  }) async {
    var mayDrainRoleBroadcasts = drainRoleBroadcasts;
    var sawIntent = false;

    // Six durable states plus bounded CAS reloads. No failure path spins.
    for (var step = 0; step < 16; step++) {
      tracker.setFallback(
        const GroupExitProcessDiagnosticFact.authorityUnavailable(),
      );
      final loaded = await intentRepository.forGroup(groupId);
      if (loaded == null) {
        return GroupExitIntentProcessResult(
          status: sawIntent
              ? GroupExitIntentProcessStatus.completed
              : GroupExitIntentProcessStatus.noIntent,
        );
      }
      if (tracker.hasFactsForDifferentAction(loaded)) {
        // Facts already committed for the prior exact action. A replacement
        // intent gets its own invocation so no diagnostic can be correlated to
        // the wrong membership/action reference.
        return GroupExitIntentProcessResult(
          status: GroupExitIntentProcessStatus.completed,
          intent: tracker.intent,
        );
      }
      sawIntent = true;
      tracker.observeIntent(loaded);

      if (loaded.state == GroupExitIntentState.queued &&
          mayDrainRoleBroadcasts) {
        tracker.setFallback(
          const GroupExitProcessDiagnosticFact.authorityUnavailable(),
        );
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
                tracker.observeIntent(current);
                final authorityStep = await _authorityAndOwnershipStepLocked(
                  current,
                  tracker,
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
          tracker.setFallback(
            const GroupExitProcessDiagnosticFact.roleSyncFailed(),
          );
          await pendingBroadcastRunner.drainForGroup(groupId);
        } catch (error) {
          tracker.add(const GroupExitProcessDiagnosticFact.roleSyncFailed());
          return GroupExitIntentProcessResult(
            status: GroupExitIntentProcessStatus.waitingForRoleSync,
            intent: loaded,
            cause: error,
          );
        }
      }

      tracker.setFallback(_fallbackForIntentState(loaded.state));
      final stateResult = await runGroupMembershipMutationLocked<_IntentStep>(
        groupId: groupId,
        action: () async {
          final current = await intentRepository.forGroup(groupId);
          if (current == null) return const _IntentStep.reload();
          if (!sameExactGroupExitIntent(current, loaded)) {
            return const _IntentStep.reload();
          }
          tracker.observeIntent(current);
          return _processStateLocked(current, tracker);
        },
      );
      final terminal = stateResult.result;
      if (terminal != null) return terminal;
    }

    final boundedFailure = GroupExitProcessDiagnosticFact.unexpected(
      tracker.fallbackPhase,
    );
    tracker.setFallback(boundedFailure);
    final current = await intentRepository.forGroup(groupId);
    tracker.observeIntent(current);
    tracker.add(boundedFailure);
    return GroupExitIntentProcessResult(
      status: GroupExitIntentProcessStatus.failed,
      intent: current,
      cause: StateError('Group exit state did not settle in a bounded pass.'),
    );
  }

  Future<_IntentStep> _processStateLocked(
    GroupExitIntent intent,
    _GroupExitDiagnosticTracker tracker,
  ) async {
    final authorityStep = await _authorityAndOwnershipStepLocked(
      intent,
      tracker,
    );
    if (authorityStep != null) return authorityStep;
    final lastAdminStep = await _lastAdminGuardStepLocked(intent, tracker);
    if (lastAdminStep != null) return lastAdminStep;

    switch (intent.state) {
      case GroupExitIntentState.queued:
        return _prepareQueuedIntent(intent, tracker);
      case GroupExitIntentState.leaveNoticePending:
        return _attemptPendingNotice(intent, tracker);
      case GroupExitIntentState.leaveNoticeAttempted:
        return _claimAndRunRotation(intent, tracker);
      case GroupExitIntentState.rotationClaimed:
        // A process that starts in this phase cannot know whether the claimant
        // crashed before or after rotation. Preserve at-most-once semantics.
        final priorOutcome = GroupExitPersistedOutcome.fromPersistedCode(
          intent.lastErrorCode,
        );
        final nextOutcome = _withRotationDeferred(
          priorOutcome,
          afterRestart: true,
        );
        tracker.setFallback(
          const GroupExitProcessDiagnosticFact.unexpected(
            GroupExitDiagnosticPhase.rotation,
          ),
        );
        final advanced = await intentRepository.advance(
          expected: intent,
          nextState: GroupExitIntentState.nativeLeavePending,
          updatedAt: _nowUtc(),
          lastErrorCode: nextOutcome.persistedCode,
        );
        if (advanced.committed && !_hasRotationDeferred(priorOutcome)) {
          tracker.add(const GroupExitProcessDiagnosticFact.rotationDeferred());
        }
        return advanced.committed
            ? const _IntentStep.reload()
            : _mutationStep(
                intent,
                advanced,
                tracker: tracker,
                failureFact: const GroupExitProcessDiagnosticFact.unexpected(
                  GroupExitDiagnosticPhase.rotation,
                ),
              );
      case GroupExitIntentState.nativeLeavePending:
        return _attemptNativeLeave(intent, tracker);
      case GroupExitIntentState.cleanupPending:
        return _cleanup(intent, tracker);
    }
  }

  /// Resolves terminal membership authority before consulting the active
  /// account. Terminal and later-generation cleanup is local exact retirement;
  /// it must remain possible after logout/account switch and must never expose
  /// queued broadcasts to the replacement identity.
  Future<_IntentStep?> _authorityAndOwnershipStepLocked(
    GroupExitIntent intent,
    _GroupExitDiagnosticTracker tracker,
  ) async {
    tracker.setFallback(
      const GroupExitProcessDiagnosticFact.authorityUnavailable(),
    );
    final authority = await _loadAuthority(intent, tracker);
    switch (authority.disposition) {
      case _IntentAuthorityDisposition.active:
        break;
      case _IntentAuthorityDisposition.ambiguous:
        tracker.add(
          const GroupExitProcessDiagnosticFact.authorityUnavailable(),
        );
        return _IntentStep.result(
          GroupExitIntentProcessResult(
            status: GroupExitIntentProcessStatus.failed,
            intent: intent,
            cause: authority.cause,
          ),
        );
      case _IntentAuthorityDisposition.terminal:
        tracker.setFallback(
          const GroupExitProcessDiagnosticFact.authorityUnavailable(),
        );
        await intentRepository.retireExact(intent);
        return _IntentStep.result(
          GroupExitIntentProcessResult(
            status: GroupExitIntentProcessStatus.completed,
            intent: intent,
          ),
        );
      case _IntentAuthorityDisposition.newerMembership:
        tracker.setFallback(
          const GroupExitProcessDiagnosticFact.authorityUnavailable(),
        );
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
      tracker.setFallback(
        const GroupExitProcessDiagnosticFact.authorityUnavailable(),
      );
      currentSelfPeerId = (await loadCurrentSelfPeerId())?.trim();
    } catch (error) {
      tracker.add(const GroupExitProcessDiagnosticFact.authorityUnavailable());
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
      tracker.add(const GroupExitProcessDiagnosticFact.authorityUnavailable());
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

  Future<_IntentStep> _prepareQueuedIntent(
    GroupExitIntent intent,
    _GroupExitDiagnosticTracker tracker,
  ) async {
    tracker.setFallback(const GroupExitProcessDiagnosticFact.roleSyncFailed());
    final pending = await pendingRepository.forGroup(intent.groupId);
    if (pending.any((row) => isPendingGroupMemberRoleBroadcastKind(row.kind))) {
      return _IntentStep.result(
        GroupExitIntentProcessResult(
          status: GroupExitIntentProcessStatus.waitingForRoleSync,
          intent: intent,
        ),
      );
    }

    tracker.setFallback(
      const GroupExitProcessDiagnosticFact.noticePrepareFailed(),
    );
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
      tracker.setFallback(
        const GroupExitProcessDiagnosticFact.noticePrepareFailed(),
      );
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
    } on GroupExitTypedProcessFailure catch (error) {
      tracker.add(error.fact);
      return _IntentStep.result(
        GroupExitIntentProcessResult(
          status: GroupExitIntentProcessStatus.failed,
          intent: intent,
          cause: error.cause,
        ),
      );
    } catch (error) {
      tracker.add(const GroupExitProcessDiagnosticFact.noticePrepareFailed());
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
      tracker.add(
        const GroupExitProcessDiagnosticFact.unexpected(
          GroupExitDiagnosticPhase.notice,
        ),
      );
      return _IntentStep.result(
        GroupExitIntentProcessResult(
          status: GroupExitIntentProcessStatus.failed,
          intent: intent,
          cause: StateError('Prepared leave notice identity is inconsistent.'),
        ),
      );
    }

    tracker.setFallback(
      const GroupExitProcessDiagnosticFact.noticePrepareFailed(),
    );
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
    return _mutationStep(
      intent,
      mutation,
      tracker: tracker,
      failureFact: const GroupExitProcessDiagnosticFact.noticePrepareFailed(),
    );
  }

  Future<_IntentStep> _attemptPendingNotice(
    GroupExitIntent intent,
    _GroupExitDiagnosticTracker tracker,
  ) async {
    tracker.setFallback(
      const GroupExitProcessDiagnosticFact.noticePrepareFailed(),
    );
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
      tracker.add(const GroupExitProcessDiagnosticFact.noticePrepareFailed());
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
      tracker.setFallback(
        const GroupExitProcessDiagnosticFact.noticePrepareFailed(),
      );
      attempt = await attemptNotice(intent: intent, pendingBroadcast: notice);
    } on GroupExitTypedProcessFailure catch (error) {
      tracker.add(error.fact);
      return _IntentStep.result(
        GroupExitIntentProcessResult(
          status: GroupExitIntentProcessStatus.waitingForNoticeRetry,
          intent: intent,
          cause: error.cause,
        ),
      );
    } catch (error) {
      tracker.add(const GroupExitProcessDiagnosticFact.noticePrepareFailed());
      return _IntentStep.result(
        GroupExitIntentProcessResult(
          status: GroupExitIntentProcessStatus.waitingForNoticeRetry,
          intent: intent,
          cause: error,
        ),
      );
    }
    if (attempt == GroupExitNoticeAttemptDisposition.retryable) {
      tracker.add(const GroupExitProcessDiagnosticFact.noticePrepareFailed());
      return _IntentStep.result(
        GroupExitIntentProcessResult(
          status: GroupExitIntentProcessStatus.waitingForNoticeRetry,
          intent: intent,
        ),
      );
    }

    tracker.setFallback(
      const GroupExitProcessDiagnosticFact.noticePrepareFailed(),
    );
    final mutation = await intentRepository.completeLeaveNoticeAttempt(
      expected: intent,
      pendingBroadcast: notice,
      completionCode: attempt == GroupExitNoticeAttemptDisposition.delivered
          ? GroupExitPersistedOutcome.noticeDelivered.persistedCode
          : GroupExitPersistedOutcome.noticeDegraded.persistedCode,
      updatedAt: _nowUtc(),
    );
    if (mutation.committed &&
        attempt == GroupExitNoticeAttemptDisposition.degraded) {
      tracker.add(const GroupExitProcessDiagnosticFact.deliveryDegraded());
    }
    return mutation.committed
        ? const _IntentStep.reload()
        : _mutationStep(
            intent,
            mutation,
            tracker: tracker,
            failureFact:
                const GroupExitProcessDiagnosticFact.noticePrepareFailed(),
          );
  }

  Future<_IntentStep> _claimAndRunRotation(
    GroupExitIntent intent,
    _GroupExitDiagnosticTracker tracker,
  ) async {
    final priorOutcome = GroupExitPersistedOutcome.fromPersistedCode(
      intent.lastErrorCode,
    );
    tracker.setFallback(
      const GroupExitProcessDiagnosticFact.unexpected(
        GroupExitDiagnosticPhase.rotation,
      ),
    );
    final claimed = await intentRepository.advance(
      expected: intent,
      nextState: GroupExitIntentState.rotationClaimed,
      updatedAt: _nowUtc(),
      lastErrorCode: priorOutcome?.persistedCode,
    );
    if (!claimed.committed || claimed.current == null) {
      return _mutationStep(
        intent,
        claimed,
        tracker: tracker,
        failureFact: const GroupExitProcessDiagnosticFact.unexpected(
          GroupExitDiagnosticPhase.rotation,
        ),
      );
    }
    tracker.observeIntent(claimed.current);

    var outcome = GroupExitPersistedOutcome.fromPersistedCode(
      claimed.current!.lastErrorCode,
    );
    try {
      await rotateKeys(claimed.current!);
    } catch (_) {
      outcome = _withRotationDeferred(outcome, afterRestart: false);
    }
    tracker.setFallback(
      const GroupExitProcessDiagnosticFact.unexpected(
        GroupExitDiagnosticPhase.rotation,
      ),
    );
    final advanced = await intentRepository.advance(
      expected: claimed.current!,
      nextState: GroupExitIntentState.nativeLeavePending,
      updatedAt: _nowUtc(),
      lastErrorCode: outcome?.persistedCode,
    );
    if (advanced.committed &&
        _hasRotationDeferred(outcome) &&
        !_hasRotationDeferred(
          GroupExitPersistedOutcome.fromPersistedCode(
            claimed.current!.lastErrorCode,
          ),
        )) {
      tracker.add(const GroupExitProcessDiagnosticFact.rotationDeferred());
    }
    return advanced.committed
        ? const _IntentStep.reload()
        : _mutationStep(
            claimed.current!,
            advanced,
            tracker: tracker,
            failureFact: const GroupExitProcessDiagnosticFact.unexpected(
              GroupExitDiagnosticPhase.rotation,
            ),
          );
  }

  Future<_IntentStep> _attemptNativeLeave(
    GroupExitIntent intent,
    _GroupExitDiagnosticTracker tracker,
  ) async {
    final outcome = GroupExitPersistedOutcome.fromPersistedCode(
      intent.lastErrorCode,
    );
    try {
      tracker.setFallback(
        const GroupExitProcessDiagnosticFact.nativeUncertain(),
      );
      await nativeLeave(intent);
    } on GroupExitTypedProcessFailure catch (error) {
      tracker.add(error.fact);
      return _IntentStep.result(
        GroupExitIntentProcessResult(
          status: GroupExitIntentProcessStatus.waitingForNativeRetry,
          intent: intent,
          cause: error.cause,
        ),
      );
    } catch (error) {
      final fact =
          error is BridgeCommandException ||
              error is TimeoutException ||
              error is GroupExitNativeCommitUnknown
          ? groupExitFactForNativeFailure(classifyGroupExitNativeFailure(error))
          : const GroupExitProcessDiagnosticFact.nativeUncertain();
      tracker.add(fact);
      return _IntentStep.result(
        GroupExitIntentProcessResult(
          status: GroupExitIntentProcessStatus.waitingForNativeRetry,
          intent: intent,
          cause: error,
        ),
      );
    }
    tracker.setFallback(
      const GroupExitProcessDiagnosticFact.cleanupIncomplete(),
    );
    final advanced = await intentRepository.advance(
      expected: intent,
      nextState: GroupExitIntentState.cleanupPending,
      updatedAt: _nowUtc(),
      lastErrorCode: outcome?.persistedCode,
    );
    return advanced.committed
        ? const _IntentStep.reload()
        : _mutationStep(
            intent,
            advanced,
            tracker: tracker,
            failureFact:
                const GroupExitProcessDiagnosticFact.cleanupIncomplete(),
          );
  }

  Future<_IntentStep> _cleanup(
    GroupExitIntent intent,
    _GroupExitDiagnosticTracker tracker,
  ) async {
    final GroupExitIntentMutationResult mutation;
    final cleanupRepository = groupRepository;
    if (cleanupRepository is! GroupExitCleanupRepository) {
      tracker.add(const GroupExitProcessDiagnosticFact.cleanupIncomplete());
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
      tracker.setFallback(
        const GroupExitProcessDiagnosticFact.cleanupIncomplete(),
      );
      mutation = await strictCleanupRepository
          .cleanupExactVoluntaryExit<GroupExitIntentMutationResult>(
            groupId: intent.groupId,
            selfPeerId: intent.selfPeerId,
            selfJoinedAt: intent.selfJoinedAt,
            finalizeSql: () =>
                intentRepository.cleanupOrRetire(intent, updatedAt: _nowUtc()),
          );
    } catch (error) {
      tracker.add(const GroupExitProcessDiagnosticFact.cleanupIncomplete());
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
        return _mutationStep(
          intent,
          mutation,
          tracker: tracker,
          failureFact: const GroupExitProcessDiagnosticFact.cleanupIncomplete(),
        );
    }
  }

  Future<_IntentAuthority> _loadAuthority(
    GroupExitIntent intent,
    _GroupExitDiagnosticTracker tracker,
  ) async {
    tracker.setFallback(
      const GroupExitProcessDiagnosticFact.authorityUnavailable(),
    );
    final group = await groupRepository.getGroup(intent.groupId);
    if (group == null || group.isDissolved || group.selfRemovedAt != null) {
      return const _IntentAuthority(_IntentAuthorityDisposition.terminal);
    }
    tracker.setFallback(
      const GroupExitProcessDiagnosticFact.authorityUnavailable(),
    );
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
  Future<_IntentStep?> _lastAdminGuardStepLocked(
    GroupExitIntent intent,
    _GroupExitDiagnosticTracker tracker,
  ) async {
    if (intent.state != GroupExitIntentState.queued) return null;

    final List<GroupMember> members;
    try {
      tracker.setFallback(
        const GroupExitProcessDiagnosticFact.authorityUnavailable(),
      );
      members = await groupRepository.getMembers(intent.groupId);
    } catch (error) {
      tracker.add(const GroupExitProcessDiagnosticFact.authorityUnavailable());
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
      tracker.add(const GroupExitProcessDiagnosticFact.authorityUnavailable());
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
    GroupExitIntentMutationResult mutation, {
    required _GroupExitDiagnosticTracker tracker,
    required GroupExitProcessDiagnosticFact failureFact,
  }) {
    tracker.observeIntent(mutation.current ?? expected);
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
    tracker.add(failureFact);
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

GroupExitPersistedOutcome _withRotationDeferred(
  GroupExitPersistedOutcome? priorOutcome, {
  required bool afterRestart,
}) {
  final noticeWasDegraded =
      priorOutcome == GroupExitPersistedOutcome.noticeDegraded ||
      priorOutcome ==
          GroupExitPersistedOutcome.noticeDegradedRotationDeferred ||
      priorOutcome ==
          GroupExitPersistedOutcome.noticeDegradedRotationDeferredRestart;
  if (noticeWasDegraded) {
    return afterRestart
        ? GroupExitPersistedOutcome.noticeDegradedRotationDeferredRestart
        : GroupExitPersistedOutcome.noticeDegradedRotationDeferred;
  }
  final legacyOutcomeWasPresent =
      priorOutcome == GroupExitPersistedOutcome.legacyUnknown ||
      priorOutcome == GroupExitPersistedOutcome.legacyUnknownRotationDeferred ||
      priorOutcome ==
          GroupExitPersistedOutcome.legacyUnknownRotationDeferredRestart;
  if (legacyOutcomeWasPresent) {
    return afterRestart
        ? GroupExitPersistedOutcome.legacyUnknownRotationDeferredRestart
        : GroupExitPersistedOutcome.legacyUnknownRotationDeferred;
  }
  return afterRestart
      ? GroupExitPersistedOutcome.rotationDeferredRestart
      : GroupExitPersistedOutcome.rotationDeferred;
}

bool _hasRotationDeferred(GroupExitPersistedOutcome? outcome) =>
    outcome == GroupExitPersistedOutcome.rotationDeferred ||
    outcome == GroupExitPersistedOutcome.rotationDeferredRestart ||
    outcome == GroupExitPersistedOutcome.noticeDegradedRotationDeferred ||
    outcome ==
        GroupExitPersistedOutcome.noticeDegradedRotationDeferredRestart ||
    outcome == GroupExitPersistedOutcome.legacyUnknownRotationDeferred ||
    outcome == GroupExitPersistedOutcome.legacyUnknownRotationDeferredRestart;

GroupExitProcessDiagnosticFact _fallbackForIntentState(
  GroupExitIntentState state,
) => switch (state) {
  GroupExitIntentState.queued =>
    const GroupExitProcessDiagnosticFact.authorityUnavailable(),
  GroupExitIntentState.leaveNoticePending =>
    const GroupExitProcessDiagnosticFact.noticePrepareFailed(),
  GroupExitIntentState.leaveNoticeAttempted ||
  GroupExitIntentState.rotationClaimed =>
    const GroupExitProcessDiagnosticFact.unexpected(
      GroupExitDiagnosticPhase.rotation,
    ),
  GroupExitIntentState.nativeLeavePending =>
    const GroupExitProcessDiagnosticFact.unexpected(
      GroupExitDiagnosticPhase.native,
    ),
  GroupExitIntentState.cleanupPending =>
    const GroupExitProcessDiagnosticFact.cleanupIncomplete(),
};

class _GroupExitDiagnosticTracker {
  _GroupExitDiagnosticTracker(this.intent);

  GroupExitIntent? intent;
  GroupExitIntent? _factOwner;
  GroupExitProcessDiagnosticFact? _fallback;
  final List<GroupExitProcessDiagnosticFact> _facts =
      <GroupExitProcessDiagnosticFact>[];

  List<GroupExitProcessDiagnosticFact> get facts =>
      immutableGroupExitDiagnosticFacts(_facts);

  GroupExitDiagnosticPhase get fallbackPhase =>
      _fallback?.phase ?? GroupExitDiagnosticPhase.authority;

  void observeIntent(GroupExitIntent? value) {
    if (value == null || hasFactsForDifferentAction(value)) return;
    intent = value;
  }

  bool hasFactsForDifferentAction(GroupExitIntent value) {
    final owner = _factOwner;
    return owner != null && !_sameGroupExitDiagnosticAction(owner, value);
  }

  void setFallback(GroupExitProcessDiagnosticFact fact) {
    _fallback = fact;
  }

  void addFallback() {
    final fallback = _fallback;
    if (fallback != null) add(fallback);
  }

  void add(GroupExitProcessDiagnosticFact fact) {
    _factOwner ??= intent;
    if (!_facts.contains(fact)) _facts.add(fact);
  }
}

bool _sameGroupExitDiagnosticAction(
  GroupExitIntent left,
  GroupExitIntent right,
) =>
    left.groupId == right.groupId &&
    left.intentId == right.intentId &&
    left.selfPeerId == right.selfPeerId &&
    left.selfJoinedAt.toUtc().isAtSameMomentAs(right.selfJoinedAt.toUtc());

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
