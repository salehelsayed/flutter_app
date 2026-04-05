import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

const String _groupsLastBacklogExpiredAtColumn = 'last_backlog_expired_at';
const String _groupsLastBacklogRetainedAtColumn = 'last_backlog_retained_at';

Future<void> runGroupsBacklogRetentionColumnsMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUPS_BACKLOG_RETENTION_COLUMNS_MIGRATION_START',
    details: {'migration': '053_groups_backlog_retention_columns'},
  );

  try {
    final columns = await db.rawQuery('PRAGMA table_info(groups)');
    final columnNames = columns
        .map((column) => column['name'] as String?)
        .whereType<String>()
        .toSet();

    if (!columnNames.contains(_groupsLastBacklogExpiredAtColumn)) {
      await db.execute(
        'ALTER TABLE groups ADD COLUMN $_groupsLastBacklogExpiredAtColumn TEXT',
      );
    }

    if (!columnNames.contains(_groupsLastBacklogRetainedAtColumn)) {
      await db.execute(
        'ALTER TABLE groups ADD COLUMN $_groupsLastBacklogRetainedAtColumn TEXT',
      );
    }

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUPS_BACKLOG_RETENTION_COLUMNS_MIGRATION_SUCCESS',
      details: {'migration': '053_groups_backlog_retention_columns'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUPS_BACKLOG_RETENTION_COLUMNS_MIGRATION_ERROR',
      details: {
        'migration': '053_groups_backlog_retention_columns',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
