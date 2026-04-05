import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

const String _groupsMuteColumn = 'is_muted';

Future<void> runGroupsMuteColumnMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUPS_MUTE_COLUMN_MIGRATION_START',
    details: {'migration': '050_groups_mute_column'},
  );

  try {
    final columns = await db.rawQuery('PRAGMA table_info(groups)');
    final hasColumn = columns.any(
      (column) => column['name'] == _groupsMuteColumn,
    );

    if (hasColumn) {
      emitFlowEvent(
        layer: 'DB',
        event: 'GROUPS_MUTE_COLUMN_MIGRATION_ALREADY_DONE',
        details: {'migration': '050_groups_mute_column'},
      );
      return;
    }

    await db.execute(
      'ALTER TABLE groups ADD COLUMN $_groupsMuteColumn INTEGER NOT NULL DEFAULT 0',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUPS_MUTE_COLUMN_MIGRATION_SUCCESS',
      details: {'migration': '050_groups_mute_column'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUPS_MUTE_COLUMN_MIGRATION_ERROR',
      details: {'migration': '050_groups_mute_column', 'error': e.toString()},
    );
    rethrow;
  }
}
