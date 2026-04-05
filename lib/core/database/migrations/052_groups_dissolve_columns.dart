import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

const String _groupsIsDissolvedColumn = 'is_dissolved';
const String _groupsDissolvedAtColumn = 'dissolved_at';
const String _groupsDissolvedByColumn = 'dissolved_by';

Future<void> runGroupsDissolveColumnsMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUPS_DISSOLVE_COLUMNS_MIGRATION_START',
    details: {'migration': '052_groups_dissolve_columns'},
  );

  try {
    final columns = await db.rawQuery('PRAGMA table_info(groups)');
    final columnNames = columns
        .map((column) => column['name'] as String?)
        .whereType<String>()
        .toSet();

    if (!columnNames.contains(_groupsIsDissolvedColumn)) {
      await db.execute(
        'ALTER TABLE groups ADD COLUMN $_groupsIsDissolvedColumn INTEGER NOT NULL DEFAULT 0',
      );
    }

    if (!columnNames.contains(_groupsDissolvedAtColumn)) {
      await db.execute(
        'ALTER TABLE groups ADD COLUMN $_groupsDissolvedAtColumn TEXT',
      );
    }

    if (!columnNames.contains(_groupsDissolvedByColumn)) {
      await db.execute(
        'ALTER TABLE groups ADD COLUMN $_groupsDissolvedByColumn TEXT',
      );
    }

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUPS_DISSOLVE_COLUMNS_MIGRATION_SUCCESS',
      details: {'migration': '052_groups_dissolve_columns'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUPS_DISSOLVE_COLUMNS_MIGRATION_ERROR',
      details: {
        'migration': '052_groups_dissolve_columns',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
