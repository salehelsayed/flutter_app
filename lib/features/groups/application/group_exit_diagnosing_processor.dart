import 'package:flutter_app/features/groups/application/group_exit_intent_coordinator.dart';
import 'package:flutter_app/features/groups/application/group_exit_intent_runner.dart';
import 'package:flutter_app/features/groups/application/group_exit_policy.dart';
import 'package:flutter_app/features/groups/application/group_exit_release_diagnostics.dart';
import 'package:flutter_app/features/groups/domain/models/group_exit_intent.dart';
import 'package:flutter_app/features/groups/domain/models/group_pending_broadcast.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

/// The sole diagnostic composition boundary around the durable runner.
///
/// Persistence starts only after the runner's per-group execution future has
/// completed, which is after its keyed tail has been removed.
class DiagnosingGroupExitIntentProcessor
    implements GroupExitIntentProcessor, GroupExitIntentExecutionProcessor {
  const DiagnosingGroupExitIntentProcessor({
    required this.inner,
    required this.observer,
  });

  final GroupExitIntentProcessor inner;
  final GroupExitDiagnosticObserver observer;

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
  }) async {
    final currentInner = inner;
    late final GroupExitIntentProcessExecution execution;
    try {
      if (currentInner is GroupExitIntentExecutionProcessor) {
        final executable = currentInner as GroupExitIntentExecutionProcessor;
        execution = await executable.executeGroup(
          groupId,
          drainRoleBroadcasts: drainRoleBroadcasts,
          knownIntent: knownIntent,
        );
      } else {
        final result = await currentInner.processGroup(
          groupId,
          drainRoleBroadcasts: drainRoleBroadcasts,
        );
        execution = GroupExitIntentProcessExecution.result(
          result: result,
          intent: result.intent ?? knownIntent,
        );
      }
    } catch (error, stackTrace) {
      execution = GroupExitIntentProcessExecution.error(
        error: error,
        stackTrace: stackTrace,
        intent: knownIntent,
        diagnosticFacts: const <GroupExitProcessDiagnosticFact>[],
      );
    }
    _observe(groupId, execution.intent, execution.diagnosticFacts);
    return execution;
  }

  @override
  Future<Map<String, GroupExitIntentProcessResult>> processAll() async =>
      (await executeAll()).replay();

  @override
  Future<GroupExitIntentProcessAllExecution> executeAll() async {
    try {
      // Deliberately call the inner aggregate once. GroupExitIntentRunner's
      // aggregate uses per-group diagnostic executions internally, so each map
      // entry already carries its complete facts without a second processGroup.
      final results = await inner.processAll();
      for (final entry in results.entries) {
        _observe(entry.key, entry.value.intent, entry.value.diagnosticFacts);
      }
      return GroupExitIntentProcessAllExecution.result(results);
    } catch (error, stackTrace) {
      return GroupExitIntentProcessAllExecution.error(
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _observe(
    String groupId,
    GroupExitIntent? intent,
    Iterable<GroupExitProcessDiagnosticFact> facts,
  ) {
    // Processor facts are post-intent facts. If storage failed before an exact
    // action could be observed, preserve the in-memory fact but do not create a
    // nullable history row that could later correlate to the wrong action.
    if (intent == null) return;
    observer.submitVoluntary(
      groupId: groupId,
      intentId: intent.intentId,
      facts: facts,
    );
  }
}

typedef ResolveCurrentGroupExitSnapshot =
    Future<GroupExitSnapshot> Function(String groupId);

/// Application-owned identity + snapshot resolver used by every presentation
/// exit surface. Identity and the snapshot are each resolved exactly once.
class CurrentGroupExitSnapshotResolver {
  const CurrentGroupExitSnapshotResolver({
    required this.identityRepository,
    required this.groupRepository,
    this.messageRepository,
    this.inviteDeliveryAttemptRepository,
    this.loadPendingBroadcasts,
  });

  final IdentityRepository identityRepository;
  final GroupRepository groupRepository;
  final GroupMessageRepository? messageRepository;
  final GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepository;
  final Future<List<GroupPendingBroadcast>> Function(String groupId)?
  loadPendingBroadcasts;

  Future<GroupExitSnapshot> call(String groupId) async {
    final identity = await identityRepository.loadIdentity();
    if (identity == null || identity.peerId.trim().isEmpty) {
      throw StateError('Current group-exit identity is unavailable.');
    }
    return resolveGroupExitSnapshot(
      groupRepo: groupRepository,
      groupId: groupId,
      selfPeerId: identity.peerId,
      messageRepo: messageRepository,
      inviteDeliveryAttemptRepo: inviteDeliveryAttemptRepository,
      loadPendingBroadcasts: loadPendingBroadcasts,
    );
  }
}

/// Disjoint observer for failures that occur before an intent is available.
/// It never submits an intent-bearing result already owned by the processor.
class DiagnosingGroupExitActionAdapter {
  const DiagnosingGroupExitActionAdapter({
    required this.resolveSnapshot,
    required this.requestLeaveInner,
    required this.queueLeaveInner,
    required this.retryInner,
    required this.observer,
  });

  final ResolveCurrentGroupExitSnapshot resolveSnapshot;
  final Future<GroupExitIntentRequestResult> Function(String groupId)
  requestLeaveInner;
  final Future<GroupExitIntentRequestResult> Function(String groupId)
  queueLeaveInner;
  final Future<GroupExitIntentRequestResult> Function(String groupId)
  retryInner;
  final GroupExitDiagnosticObserver observer;

  Future<GroupExitSnapshot> loadSnapshot(String groupId) async {
    try {
      return await resolveSnapshot(groupId);
    } catch (error, stackTrace) {
      observer.submitVoluntary(
        groupId: groupId,
        intentId: null,
        facts: const <GroupExitProcessDiagnosticFact>[
          GroupExitProcessDiagnosticFact.authorityUnavailable(),
        ],
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<GroupExitIntentRequestResult> requestLeave(String groupId) =>
      _runRequest(groupId, requestLeaveInner);

  Future<GroupExitIntentRequestResult> queueLeaveWhenSyncCompletes(
    String groupId,
  ) => _runRequest(groupId, queueLeaveInner);

  Future<GroupExitIntentRequestResult> retry(String groupId) =>
      _runRequest(groupId, retryInner);

  Future<GroupExitIntentRequestResult> _runRequest(
    String groupId,
    Future<GroupExitIntentRequestResult> Function(String groupId) action,
  ) async {
    final GroupExitIntentRequestResult result;
    try {
      result = await action(groupId);
    } catch (error, stackTrace) {
      observer.submitVoluntary(
        groupId: groupId,
        intentId: null,
        facts: const <GroupExitProcessDiagnosticFact>[
          GroupExitProcessDiagnosticFact.authorityUnavailable(),
        ],
      );
      Error.throwWithStackTrace(error, stackTrace);
    }

    if (result.intent == null) {
      final ownedFacts = result.diagnosticFacts.where(
        (fact) =>
            fact.outcome ==
                GroupExitProcessDiagnosticOutcome.authorityUnavailable ||
            fact.outcome == GroupExitProcessDiagnosticOutcome.roleSyncFailed,
      );
      observer.submitVoluntary(
        groupId: groupId,
        intentId: null,
        facts: ownedFacts,
      );
    }
    return result;
  }
}
