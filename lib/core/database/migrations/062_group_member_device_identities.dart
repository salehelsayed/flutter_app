import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

const String _groupMemberDevicesColumn = 'devices_json';

/// Migration 062: Adds first-class device roster storage to group members.
Future<void> runGroupMemberDeviceIdentitiesMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_MEMBER_DEVICE_IDENTITIES_MIGRATION_START',
    details: {'migration': '062_group_member_device_identities'},
  );

  try {
    final columns = await db.rawQuery('PRAGMA table_info(group_members)');
    final hasColumn = columns.any(
      (column) => column['name'] == _groupMemberDevicesColumn,
    );

    if (hasColumn) {
      emitFlowEvent(
        layer: 'DB',
        event: 'GROUP_MEMBER_DEVICE_IDENTITIES_MIGRATION_ALREADY_DONE',
        details: {'migration': '062_group_member_device_identities'},
      );
      return;
    }

    await db.execute(
      'ALTER TABLE group_members ADD COLUMN $_groupMemberDevicesColumn TEXT',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MEMBER_DEVICE_IDENTITIES_MIGRATION_SUCCESS',
      details: {'migration': '062_group_member_device_identities'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_MEMBER_DEVICE_IDENTITIES_MIGRATION_ERROR',
      details: {
        'migration': '062_group_member_device_identities',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
