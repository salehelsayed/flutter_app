import 'dart:async';

import 'package:flutter_app/core/bridge/bridge_group_helpers.dart';
import 'package:flutter_app/features/groups/domain/models/group_exit_diagnostic.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_exit_diagnostic_repository.dart';

/// Closed, release-safe facts emitted by one group-exit processor invocation.
enum GroupExitProcessDiagnosticOutcome {
  authorityUnavailable,
  roleSyncFailed,
  noticePrepareFailed,
  nativeNodeUnavailable,
  nativeRejected,
  nativeUncertain,
  cleanupIncomplete,
  deliveryDegraded,
  rotationDeferred,
  unexpected,
}

/// A diagnostic outcome together with the phase that causally owns it.
///
/// The phase is carried even for [GroupExitProcessDiagnosticOutcome.unexpected]
/// so EX99 never has to infer one from an exception or a final intent state.
class GroupExitProcessDiagnosticFact {
  const GroupExitProcessDiagnosticFact.authorityUnavailable()
    : outcome = GroupExitProcessDiagnosticOutcome.authorityUnavailable,
      phase = GroupExitDiagnosticPhase.authority;

  const GroupExitProcessDiagnosticFact.roleSyncFailed()
    : outcome = GroupExitProcessDiagnosticOutcome.roleSyncFailed,
      phase = GroupExitDiagnosticPhase.roleSync;

  const GroupExitProcessDiagnosticFact.noticePrepareFailed()
    : outcome = GroupExitProcessDiagnosticOutcome.noticePrepareFailed,
      phase = GroupExitDiagnosticPhase.notice;

  const GroupExitProcessDiagnosticFact.nativeNodeUnavailable()
    : outcome = GroupExitProcessDiagnosticOutcome.nativeNodeUnavailable,
      phase = GroupExitDiagnosticPhase.native;

  const GroupExitProcessDiagnosticFact.nativeRejected()
    : outcome = GroupExitProcessDiagnosticOutcome.nativeRejected,
      phase = GroupExitDiagnosticPhase.native;

  const GroupExitProcessDiagnosticFact.nativeUncertain()
    : outcome = GroupExitProcessDiagnosticOutcome.nativeUncertain,
      phase = GroupExitDiagnosticPhase.native;

  const GroupExitProcessDiagnosticFact.cleanupIncomplete()
    : outcome = GroupExitProcessDiagnosticOutcome.cleanupIncomplete,
      phase = GroupExitDiagnosticPhase.cleanup;

  const GroupExitProcessDiagnosticFact.deliveryDegraded()
    : outcome = GroupExitProcessDiagnosticOutcome.deliveryDegraded,
      phase = GroupExitDiagnosticPhase.delivery;

  const GroupExitProcessDiagnosticFact.rotationDeferred()
    : outcome = GroupExitProcessDiagnosticOutcome.rotationDeferred,
      phase = GroupExitDiagnosticPhase.rotation;

  const GroupExitProcessDiagnosticFact.unexpected(this.phase)
    : assert(phase != GroupExitDiagnosticPhase.localDelete),
      outcome = GroupExitProcessDiagnosticOutcome.unexpected;

  final GroupExitProcessDiagnosticOutcome outcome;
  final GroupExitDiagnosticPhase phase;

  @override
  bool operator ==(Object other) =>
      other is GroupExitProcessDiagnosticFact &&
      other.outcome == outcome &&
      other.phase == phase;

  @override
  int get hashCode => Object.hash(outcome, phase);
}

List<GroupExitProcessDiagnosticFact> immutableGroupExitDiagnosticFacts(
  Iterable<GroupExitProcessDiagnosticFact> facts,
) => List<GroupExitProcessDiagnosticFact>.unmodifiable(facts.toSet());

enum GroupExitNativeFailure { nodeUnavailable, rejected, uncertain, unexpected }

/// Explicit marker for a native call that may have committed but produced no
/// trustworthy acknowledgement.
class GroupExitNativeCommitUnknown implements Exception {
  const GroupExitNativeCommitUnknown([this.cause]);

  final Object? cause;
}

/// Internal typed carrier used between a callback boundary and the runner.
///
/// The runner always exposes [cause] as the original result cause and uses
/// [stackTrace] when replaying an escaped error; callers never classify either.
class GroupExitTypedProcessFailure implements Exception {
  const GroupExitTypedProcessFailure({
    required this.fact,
    required this.cause,
    required this.stackTrace,
  });

  final GroupExitProcessDiagnosticFact fact;
  final Object cause;
  final StackTrace stackTrace;
}

GroupExitNativeFailure classifyGroupExitNativeFailure(Object error) {
  if (error is GroupExitTypedProcessFailure) {
    return switch (error.fact.outcome) {
      GroupExitProcessDiagnosticOutcome.nativeNodeUnavailable =>
        GroupExitNativeFailure.nodeUnavailable,
      GroupExitProcessDiagnosticOutcome.nativeRejected =>
        GroupExitNativeFailure.rejected,
      GroupExitProcessDiagnosticOutcome.nativeUncertain =>
        GroupExitNativeFailure.uncertain,
      _ => GroupExitNativeFailure.unexpected,
    };
  }
  if (error is TimeoutException || error is GroupExitNativeCommitUnknown) {
    return GroupExitNativeFailure.uncertain;
  }
  if (error is! BridgeCommandException || error.command != 'group:leave') {
    return GroupExitNativeFailure.unexpected;
  }
  return switch (error.errorCode) {
    'NOT_INITIALIZED' => GroupExitNativeFailure.nodeUnavailable,
    'INVALID_INPUT' || 'GROUP_ERROR' => GroupExitNativeFailure.rejected,
    'INTERNAL_ERROR' => GroupExitNativeFailure.uncertain,
    _ => GroupExitNativeFailure.unexpected,
  };
}

GroupExitProcessDiagnosticFact groupExitFactForNativeFailure(
  GroupExitNativeFailure failure,
) => switch (failure) {
  GroupExitNativeFailure.nodeUnavailable =>
    const GroupExitProcessDiagnosticFact.nativeNodeUnavailable(),
  GroupExitNativeFailure.rejected =>
    const GroupExitProcessDiagnosticFact.nativeRejected(),
  GroupExitNativeFailure.uncertain =>
    const GroupExitProcessDiagnosticFact.nativeUncertain(),
  GroupExitNativeFailure.unexpected =>
    const GroupExitProcessDiagnosticFact.unexpected(
      GroupExitDiagnosticPhase.native,
    ),
};

GroupExitDiagnosticPublicCode groupExitPublicCodeForNativeFailure(
  GroupExitNativeFailure failure,
) => groupExitPublicCodeForFact(groupExitFactForNativeFailure(failure));

GroupExitDiagnosticPublicCode groupExitPublicCodeForFact(
  GroupExitProcessDiagnosticFact fact,
) => switch (fact.outcome) {
  GroupExitProcessDiagnosticOutcome.authorityUnavailable =>
    GroupExitDiagnosticPublicCode.ex01,
  GroupExitProcessDiagnosticOutcome.roleSyncFailed =>
    GroupExitDiagnosticPublicCode.ex02,
  GroupExitProcessDiagnosticOutcome.noticePrepareFailed =>
    GroupExitDiagnosticPublicCode.ex03,
  GroupExitProcessDiagnosticOutcome.nativeNodeUnavailable =>
    GroupExitDiagnosticPublicCode.ex04,
  GroupExitProcessDiagnosticOutcome.nativeRejected =>
    GroupExitDiagnosticPublicCode.ex05,
  GroupExitProcessDiagnosticOutcome.nativeUncertain =>
    GroupExitDiagnosticPublicCode.ex06,
  GroupExitProcessDiagnosticOutcome.cleanupIncomplete =>
    GroupExitDiagnosticPublicCode.ex07,
  GroupExitProcessDiagnosticOutcome.deliveryDegraded =>
    GroupExitDiagnosticPublicCode.ex08,
  GroupExitProcessDiagnosticOutcome.rotationDeferred =>
    GroupExitDiagnosticPublicCode.ex09,
  GroupExitProcessDiagnosticOutcome.unexpected =>
    GroupExitDiagnosticPublicCode.ex99,
};

GroupExitDiagnosticSeverity groupExitSeverityForFact(
  GroupExitProcessDiagnosticFact fact,
) => switch (fact.outcome) {
  GroupExitProcessDiagnosticOutcome.cleanupIncomplete ||
  GroupExitProcessDiagnosticOutcome.deliveryDegraded ||
  GroupExitProcessDiagnosticOutcome.rotationDeferred =>
    GroupExitDiagnosticSeverity.warning,
  _ => GroupExitDiagnosticSeverity.failure,
};

GroupExitDiagnosticReason groupExitReasonForFact(
  GroupExitProcessDiagnosticFact fact,
) => switch (fact.outcome) {
  GroupExitProcessDiagnosticOutcome.authorityUnavailable =>
    GroupExitDiagnosticReason.authorityUnavailable,
  GroupExitProcessDiagnosticOutcome.roleSyncFailed =>
    GroupExitDiagnosticReason.roleSyncFailed,
  GroupExitProcessDiagnosticOutcome.noticePrepareFailed =>
    GroupExitDiagnosticReason.noticePrepareFailed,
  GroupExitProcessDiagnosticOutcome.nativeNodeUnavailable =>
    GroupExitDiagnosticReason.nodeNotInitialized,
  GroupExitProcessDiagnosticOutcome.nativeRejected =>
    GroupExitDiagnosticReason.nativeRejected,
  GroupExitProcessDiagnosticOutcome.nativeUncertain =>
    GroupExitDiagnosticReason.nativeUncertain,
  GroupExitProcessDiagnosticOutcome.cleanupIncomplete =>
    GroupExitDiagnosticReason.cleanupIncomplete,
  GroupExitProcessDiagnosticOutcome.deliveryDegraded =>
    GroupExitDiagnosticReason.noticeDeliveryDegraded,
  GroupExitProcessDiagnosticOutcome.rotationDeferred =>
    GroupExitDiagnosticReason.rotationDeferred,
  GroupExitProcessDiagnosticOutcome.unexpected =>
    GroupExitDiagnosticReason.unexpected,
};

GroupExitDiagnostic diagnosticForVoluntaryGroupExitFact({
  required DateTime occurredAt,
  required String groupId,
  required String? intentId,
  required GroupExitProcessDiagnosticFact fact,
}) => GroupExitDiagnostic.create(
  occurredAt: occurredAt,
  groupId: groupId,
  intentId: intentId,
  kind: GroupExitDiagnosticKind.voluntary,
  severity: groupExitSeverityForFact(fact),
  phase: fact.phase,
  publicCode: groupExitPublicCodeForFact(fact),
  reason: groupExitReasonForFact(fact),
);

/// Runs the native command after identity authority has already been resolved.
/// Any non-negative post-dispatch failure is commit-unknown and therefore EX06.
Future<void> runTypedGroupExitNativeLeave(
  Future<void> Function() invoke,
) async {
  try {
    await invoke();
  } catch (error, stackTrace) {
    final failure =
        error is BridgeCommandException ||
            error is TimeoutException ||
            error is GroupExitNativeCommitUnknown
        ? classifyGroupExitNativeFailure(error)
        : GroupExitNativeFailure.uncertain;
    throw GroupExitTypedProcessFailure(
      fact: groupExitFactForNativeFailure(failure),
      cause: error,
      stackTrace: stackTrace,
    );
  }
}

Never throwGroupExitAuthorityFailure(Object error, StackTrace stackTrace) {
  throw GroupExitTypedProcessFailure(
    fact: const GroupExitProcessDiagnosticFact.authorityUnavailable(),
    cause: error,
    stackTrace: stackTrace,
  );
}

/// Starts a bounded diagnostic append without making it exit authority.
class GroupExitDiagnosticObserver {
  const GroupExitDiagnosticObserver({
    required this.repository,
    required this.now,
    this.onSubmissionFailure,
  });

  final GroupExitDiagnosticRepository repository;
  final DateTime Function() now;
  final void Function()? onSubmissionFailure;

  void submitVoluntary({
    required String groupId,
    required String? intentId,
    required Iterable<GroupExitProcessDiagnosticFact> facts,
  }) {
    unawaited(
      Future<void>.sync(() async {
        final unique = immutableGroupExitDiagnosticFacts(facts);
        if (unique.isEmpty) return;

        final occurredAt = now();
        final diagnostics = <GroupExitDiagnostic>[];
        for (final fact in unique) {
          // EX03+ and EX99 require exact action correlation. If a processor
          // failed before any intent snapshot was available, keep its
          // in-memory code but never manufacture a null post-intent row.
          if (intentId == null &&
              fact.outcome !=
                  GroupExitProcessDiagnosticOutcome.authorityUnavailable &&
              fact.outcome !=
                  GroupExitProcessDiagnosticOutcome.roleSyncFailed) {
            continue;
          }
          diagnostics.add(
            diagnosticForVoluntaryGroupExitFact(
              occurredAt: occurredAt,
              groupId: groupId,
              intentId: intentId,
              fact: fact,
            ),
          );
        }
        if (diagnostics.isEmpty) return;

        await repository.appendOutcome(
          List<GroupExitDiagnostic>.unmodifiable(diagnostics),
        );
      }).catchError((Object _, StackTrace _) {
        try {
          onSubmissionFailure?.call();
        } catch (_) {
          // Diagnostic failure telemetry is best-effort too.
        }
      }),
    );
  }
}
