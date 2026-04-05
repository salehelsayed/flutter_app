import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

const _groupsMetadataColumns = <String, String>{
  'avatar_blob_id': 'TEXT',
  'avatar_mime': 'TEXT',
  'avatar_path': 'TEXT',
  'last_metadata_event_at': 'TEXT',
};

Future<void> runGroupsMetadataColumnsMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUPS_METADATA_COLUMNS_MIGRATION_START',
    details: {'migration': '049_groups_metadata_columns'},
  );

  try {
    final columns = await db.rawQuery('PRAGMA table_info(groups)');
    final existingColumnNames = columns
        .map((column) => column['name'] as String?)
        .whereType<String>()
        .toSet();

    var addedColumns = 0;
    for (final entry in _groupsMetadataColumns.entries) {
      if (existingColumnNames.contains(entry.key)) {
        continue;
      }

      await db.execute(
        'ALTER TABLE groups ADD COLUMN ${entry.key} ${entry.value}',
      );
      addedColumns++;
    }

    emitFlowEvent(
      layer: 'DB',
      event: addedColumns == 0
          ? 'GROUPS_METADATA_COLUMNS_MIGRATION_ALREADY_DONE'
          : 'GROUPS_METADATA_COLUMNS_MIGRATION_SUCCESS',
      details: {
        'migration': '049_groups_metadata_columns',
        'addedColumns': addedColumns,
      },
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUPS_METADATA_COLUMNS_MIGRATION_ERROR',
      details: {
        'migration': '049_groups_metadata_columns',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
