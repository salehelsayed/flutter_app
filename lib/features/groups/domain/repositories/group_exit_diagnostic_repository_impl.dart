import '../models/group_exit_diagnostic.dart';
import 'group_exit_diagnostic_repository.dart';

class GroupExitDiagnosticRepositoryImpl
    implements GroupExitDiagnosticRepository {
  GroupExitDiagnosticRepositoryImpl({
    required this.dbAppendOutcome,
    required this.dbLoadNewest,
    required this.dbLoadForAction,
    required this.dbClear,
  });

  final Future<void> Function(List<Map<String, Object?>> rows) dbAppendOutcome;
  final Future<List<Map<String, Object?>>> Function() dbLoadNewest;
  final Future<List<Map<String, Object?>>> Function({
    required String groupRef,
    required String intentRef,
  })
  dbLoadForAction;
  final Future<void> Function() dbClear;

  @override
  Future<void> appendOutcome(List<GroupExitDiagnostic> diagnostics) {
    if (diagnostics.isEmpty) {
      throw ArgumentError.value(
        diagnostics,
        'diagnostics',
        'must contain at least one fact',
      );
    }
    final rows = diagnostics
        .map((diagnostic) => diagnostic.toMap(includeId: false))
        .toList(growable: false);
    return dbAppendOutcome(rows);
  }

  @override
  Future<List<GroupExitDiagnostic>> loadNewest() async {
    final rows = await dbLoadNewest();
    return List<GroupExitDiagnostic>.unmodifiable(
      rows.map(GroupExitDiagnostic.fromMap),
    );
  }

  @override
  Future<List<GroupExitDiagnostic>> loadForAction({
    required String groupId,
    required String intentId,
  }) async {
    final rows = await dbLoadForAction(
      groupRef: groupExitGroupRef(groupId),
      intentRef: groupExitIntentRef(intentId),
    );
    return List<GroupExitDiagnostic>.unmodifiable(
      rows.map(GroupExitDiagnostic.fromMap),
    );
  }

  @override
  Future<void> clear() => dbClear();
}
