import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

const String _groupsMembershipEventWatermarkColumn =
    'last_membership_event_at';

Future<void> runGroupsLastMembershipEventAtMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUPS_LAST_MEMBERSHIP_EVENT_AT_MIGRATION_START',
    details: {'migration': '048_groups_last_membership_event_at'},
  );

  try {
    final columns = await db.rawQuery('PRAGMA table_info(groups)');
    final hasColumn = columns.any(
      (column) => column['name'] == _groupsMembershipEventWatermarkColumn,
    );

    if (hasColumn) {
      emitFlowEvent(
        layer: 'DB',
        event: 'GROUPS_LAST_MEMBERSHIP_EVENT_AT_MIGRATION_ALREADY_DONE',
        details: {'migration': '048_groups_last_membership_event_at'},
      );
      return;
    }

    await db.execute(
      'ALTER TABLE groups ADD COLUMN $_groupsMembershipEventWatermarkColumn TEXT',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUPS_LAST_MEMBERSHIP_EVENT_AT_MIGRATION_SUCCESS',
      details: {'migration': '048_groups_last_membership_event_at'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUPS_LAST_MEMBERSHIP_EVENT_AT_MIGRATION_ERROR',
      details: {
        'migration': '048_groups_last_membership_event_at',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
