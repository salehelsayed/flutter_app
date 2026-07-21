import 'dart:async';

import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/groups/application/delete_group_and_messages_use_case.dart';
import 'package:flutter_app/features/groups/application/delete_self_removed_group_shell_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_exit_diagnostic.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';

typedef SubmitGroupExitDiagnosticOutcome =
    Future<void> Function(List<GroupExitDiagnostic> diagnostics);

enum DeleteDissolvedGroupShellActionStatus { deleted, authorityUnavailable }

class DeleteSelfRemovedGroupShellActionObservation {
  const DeleteSelfRemovedGroupShellActionObservation({
    required this.result,
    this.publicCode,
  });

  final DeleteSelfRemovedGroupShellResult result;
  final GroupExitDiagnosticPublicCode? publicCode;
}

class DeleteDissolvedGroupShellActionObservation {
  const DeleteDissolvedGroupShellActionObservation({
    required this.status,
    this.publicCode,
  });

  final DeleteDissolvedGroupShellActionStatus status;
  final GroupExitDiagnosticPublicCode? publicCode;
}

typedef LoadGroupExitTerminalIdentityPeerId = Future<String?> Function();
typedef DeleteDissolvedGroupShellCallback =
    Future<void> Function(String groupId);
typedef DeleteSelfRemovedGroupShellActionCallback =
    Future<DeleteSelfRemovedGroupShellActionObservation> Function(
      String groupId,
    );
typedef DeleteDissolvedGroupShellActionCallback =
    Future<DeleteDissolvedGroupShellActionObservation> Function(String groupId);

DeleteSelfRemovedGroupShellActionCallback?
defaultDiagnosingDeleteSelfRemovedGroupShellAction;
DeleteDissolvedGroupShellActionCallback?
defaultDiagnosingDeleteDissolvedGroupShellAction;

/// Presentation entry used by production surfaces. Production installs the
/// diagnosing action at the composition root. The legacy callback exists only
/// to keep isolated widget fixtures injectable; its identity resolution still
/// lives here in the application layer rather than in a widget.
Future<DeleteSelfRemovedGroupShellActionObservation>
runDeleteSelfRemovedGroupShellPresentationAction({
  required String groupId,
  required IdentityRepository identityRepository,
  DeleteSelfRemovedGroupShellCallback? legacyTestCallback,
}) async {
  final action = defaultDiagnosingDeleteSelfRemovedGroupShellAction;
  if (action != null) return action(groupId);
  final callback = legacyTestCallback;
  if (callback == null) {
    return const DeleteSelfRemovedGroupShellActionObservation(
      result: DeleteSelfRemovedGroupShellResult.cleanupIncomplete,
      publicCode: GroupExitDiagnosticPublicCode.ex01,
    );
  }
  final selfPeerId = (await identityRepository.loadIdentity())?.peerId.trim();
  if (selfPeerId == null || selfPeerId.isEmpty) {
    return const DeleteSelfRemovedGroupShellActionObservation(
      result: DeleteSelfRemovedGroupShellResult.cleanupIncomplete,
      publicCode: GroupExitDiagnosticPublicCode.ex01,
    );
  }
  final result = await callback(groupId: groupId, selfPeerId: selfPeerId);
  return DeleteSelfRemovedGroupShellActionObservation(result: result);
}

Future<DeleteDissolvedGroupShellActionObservation>
runDeleteDissolvedGroupShellPresentationAction({
  required String groupId,
  DeleteDissolvedGroupShellCallback? legacyTestCallback,
}) async {
  final action = defaultDiagnosingDeleteDissolvedGroupShellAction;
  if (action != null) return action(groupId);
  final callback = legacyTestCallback;
  if (callback == null) {
    return const DeleteDissolvedGroupShellActionObservation(
      status: DeleteDissolvedGroupShellActionStatus.authorityUnavailable,
      publicCode: GroupExitDiagnosticPublicCode.ex01,
    );
  }
  await callback(groupId);
  return const DeleteDissolvedGroupShellActionObservation(
    status: DeleteDissolvedGroupShellActionStatus.deleted,
  );
}

/// Application-owned terminal action for a self-removed group shell.
///
/// Identity and required production callback authority are resolved before
/// the destructive callback. Once invoked, its exact result or error/stack is
/// preserved. Diagnostic persistence is detached and can never authorize,
/// retry, or delay deletion.
class DiagnosingDeleteSelfRemovedGroupShellAction {
  DiagnosingDeleteSelfRemovedGroupShellAction({
    required this.loadCurrentSelfPeerId,
    required this.inner,
    required this.submit,
    DateTime Function()? now,
  }) : _now = now ?? (() => DateTime.now().toUtc());

  final LoadGroupExitTerminalIdentityPeerId loadCurrentSelfPeerId;
  final DeleteSelfRemovedGroupShellCallback? inner;
  final SubmitGroupExitDiagnosticOutcome submit;
  final DateTime Function() _now;

  Future<DeleteSelfRemovedGroupShellActionObservation> call(
    String groupId,
  ) async {
    final callback = inner;
    final String? selfPeerId;
    try {
      selfPeerId = (await loadCurrentSelfPeerId())?.trim();
    } catch (_) {
      _record(groupId, GroupExitDiagnosticPublicCode.ex01);
      return const DeleteSelfRemovedGroupShellActionObservation(
        result: DeleteSelfRemovedGroupShellResult.cleanupIncomplete,
        publicCode: GroupExitDiagnosticPublicCode.ex01,
      );
    }
    if (callback == null || selfPeerId == null || selfPeerId.isEmpty) {
      _record(groupId, GroupExitDiagnosticPublicCode.ex01);
      return const DeleteSelfRemovedGroupShellActionObservation(
        result: DeleteSelfRemovedGroupShellResult.cleanupIncomplete,
        publicCode: GroupExitDiagnosticPublicCode.ex01,
      );
    }

    try {
      final result = await callback(groupId: groupId, selfPeerId: selfPeerId);
      if (result == DeleteSelfRemovedGroupShellResult.cleanupIncomplete) {
        _record(groupId, GroupExitDiagnosticPublicCode.ex10);
        return DeleteSelfRemovedGroupShellActionObservation(
          result: result,
          publicCode: GroupExitDiagnosticPublicCode.ex10,
        );
      }
      return DeleteSelfRemovedGroupShellActionObservation(result: result);
    } catch (error, stackTrace) {
      _record(groupId, GroupExitDiagnosticPublicCode.ex10);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  void _record(String groupId, GroupExitDiagnosticPublicCode code) {
    _submitDetached(submit, <GroupExitDiagnostic>[
      _terminalDiagnostic(
        occurredAt: _now(),
        groupId: groupId,
        kind: GroupExitDiagnosticKind.selfRemovedShell,
        code: code,
      ),
    ]);
  }
}

/// Application-owned strict local delete for a dissolved group shell.
///
/// A typed stale-state refusal is preserved without a diagnostic. Any other
/// error after invocation is EX10 and is rethrown with its original stack.
class DiagnosingDeleteDissolvedGroupShellAction {
  DiagnosingDeleteDissolvedGroupShellAction({
    required this.inner,
    required this.submit,
    DateTime Function()? now,
  }) : _now = now ?? (() => DateTime.now().toUtc());

  final DeleteDissolvedGroupShellCallback? inner;
  final SubmitGroupExitDiagnosticOutcome submit;
  final DateTime Function() _now;

  Future<DeleteDissolvedGroupShellActionObservation> call(
    String groupId,
  ) async {
    final callback = inner;
    if (callback == null) {
      _record(groupId, GroupExitDiagnosticPublicCode.ex01);
      return const DeleteDissolvedGroupShellActionObservation(
        status: DeleteDissolvedGroupShellActionStatus.authorityUnavailable,
        publicCode: GroupExitDiagnosticPublicCode.ex01,
      );
    }

    try {
      await callback(groupId);
      return const DeleteDissolvedGroupShellActionObservation(
        status: DeleteDissolvedGroupShellActionStatus.deleted,
      );
    } on DissolvedGroupDeleteStateChangedException {
      rethrow;
    } catch (error, stackTrace) {
      _record(groupId, GroupExitDiagnosticPublicCode.ex10);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  void _record(String groupId, GroupExitDiagnosticPublicCode code) {
    _submitDetached(submit, <GroupExitDiagnostic>[
      _terminalDiagnostic(
        occurredAt: _now(),
        groupId: groupId,
        kind: GroupExitDiagnosticKind.dissolvedShell,
        code: code,
      ),
    ]);
  }
}

GroupExitDiagnostic _terminalDiagnostic({
  required DateTime occurredAt,
  required String groupId,
  required GroupExitDiagnosticKind kind,
  required GroupExitDiagnosticPublicCode code,
}) {
  final isAuthority = code == GroupExitDiagnosticPublicCode.ex01;
  return GroupExitDiagnostic.create(
    occurredAt: occurredAt,
    groupId: groupId,
    kind: kind,
    severity: GroupExitDiagnosticSeverity.failure,
    phase: isAuthority
        ? GroupExitDiagnosticPhase.authority
        : GroupExitDiagnosticPhase.localDelete,
    publicCode: code,
    reason: isAuthority
        ? GroupExitDiagnosticReason.authorityUnavailable
        : GroupExitDiagnosticReason.terminalShellCleanup,
  );
}

void _submitDetached(
  SubmitGroupExitDiagnosticOutcome submit,
  List<GroupExitDiagnostic> diagnostics,
) {
  unawaited(
    Future<void>.sync(() => submit(diagnostics)).catchError((Object _) {
      emitFlowEvent(
        layer: 'FL',
        event: 'GROUP_EXIT_DIAGNOSTIC_WRITE_FAILED',
        details: const {
          'code': 'EX01',
          'phase': 'local_delete',
          'severity': 'failure',
        },
      );
    }),
  );
}
