// ignore_for_file: file_names

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Migration 083: Adds the audit-borne source event id of the latest applied
/// membership event to `groups`, used as a deterministic tie-breaker when two
/// membership events share `last_membership_event_at`.
Future<void> runGroupsLastMembershipEventIdMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUPS_LAST_MEMBERSHIP_EVENT_ID_MIGRATION_START',
    details: {'migration': '083_groups_last_membership_event_id'},
  );

  try {
    final columns = await db.rawQuery('PRAGMA table_info(groups)');
    final columnNames = columns.map((column) => column['name']).toSet();

    if (columnNames.contains('last_membership_event_id')) {
      emitFlowEvent(
        layer: 'DB',
        event: 'GROUPS_LAST_MEMBERSHIP_EVENT_ID_MIGRATION_ALREADY_DONE',
        details: {'migration': '083_groups_last_membership_event_id'},
      );
      return;
    }

    await db.execute(
      'ALTER TABLE groups ADD COLUMN last_membership_event_id TEXT',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUPS_LAST_MEMBERSHIP_EVENT_ID_MIGRATION_SUCCESS',
      details: {'migration': '083_groups_last_membership_event_id'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUPS_LAST_MEMBERSHIP_EVENT_ID_MIGRATION_ERROR',
      details: {
        'migration': '083_groups_last_membership_event_id',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
