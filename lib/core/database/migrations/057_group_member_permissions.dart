import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

const String _groupMemberPermissionsColumn = 'permissions_json';

Future<void> runGroupMemberPermissionsMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_MEMBER_PERMISSIONS_MIGRATION_START',
    details: {'migration': '057_group_member_permissions'},
  );

  try {
    final columns = await db.rawQuery('PRAGMA table_info(group_members)');
    final hasColumn = columns.any(
      (column) => column['name'] == _groupMemberPermissionsColumn,
    );

    if (hasColumn) {
      emitFlowEvent(
        layer: 'DB',
        event: 'GROUP_MEMBER_PERMISSIONS_MIGRATION_ALREADY_DONE',
        details: {'migration': '057_group_member_permissions'},
      );
      return;
    }

    await db.execute(
      'ALTER TABLE group_members ADD COLUMN $_groupMemberPermissionsColumn TEXT',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MEMBER_PERMISSIONS_MIGRATION_SUCCESS',
      details: {'migration': '057_group_member_permissions'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MEMBER_PERMISSIONS_MIGRATION_ERROR',
      details: {
        'migration': '057_group_member_permissions',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
