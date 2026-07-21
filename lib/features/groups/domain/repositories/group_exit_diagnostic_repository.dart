import '../models/group_exit_diagnostic.dart';

abstract interface class GroupExitDiagnosticRepository {
  /// Persists the nonempty complete fact set for one processor outcome.
  Future<void> appendOutcome(List<GroupExitDiagnostic> diagnostics);

  /// Returns the bounded history in local insertion order, newest first.
  Future<List<GroupExitDiagnostic>> loadNewest();

  /// Returns only diagnostics for this exact current group-exit action.
  Future<List<GroupExitDiagnostic>> loadForAction({
    required String groupId,
    required String intentId,
  });

  Future<void> clear();
}
