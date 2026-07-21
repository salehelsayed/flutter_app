import 'package:flutter_app/features/groups/domain/models/group_exit_diagnostic.dart';

typedef LoadGroupExitDiagnosticsForAction =
    Future<List<GroupExitDiagnostic>> Function({
      required String groupId,
      required String intentId,
    });

LoadGroupExitDiagnosticsForAction? _loadForAction;

void setGroupExitDiagnosticAccessSink({
  LoadGroupExitDiagnosticsForAction? loadForAction,
}) {
  _loadForAction = loadForAction;
}

enum GroupExitDiagnosticLookupStatus { available, unavailable }

class GroupExitDiagnosticLookupResult {
  const GroupExitDiagnosticLookupResult.available(this.diagnostics)
    : status = GroupExitDiagnosticLookupStatus.available,
      cause = null;

  const GroupExitDiagnosticLookupResult.unavailable([this.cause])
    : status = GroupExitDiagnosticLookupStatus.unavailable,
      diagnostics = const <GroupExitDiagnostic>[];

  final GroupExitDiagnosticLookupStatus status;
  final List<GroupExitDiagnostic> diagnostics;
  final Object? cause;

  bool get isAvailable => status == GroupExitDiagnosticLookupStatus.available;
}

/// Reads history for one exact durable action. A missing sink/read error is
/// distinct from an empty successful lookup, so presentation never attaches a
/// stale same-group row as a fallback.
Future<GroupExitDiagnosticLookupResult> loadGroupExitDiagnosticsForAction({
  required String groupId,
  required String intentId,
}) async {
  final load = _loadForAction;
  if (load == null) {
    return GroupExitDiagnosticLookupResult.unavailable(
      StateError('Group exit diagnostic lookup is unavailable.'),
    );
  }
  try {
    return GroupExitDiagnosticLookupResult.available(
      List<GroupExitDiagnostic>.unmodifiable(
        await load(groupId: groupId, intentId: intentId),
      ),
    );
  } catch (error) {
    return GroupExitDiagnosticLookupResult.unavailable(error);
  }
}
