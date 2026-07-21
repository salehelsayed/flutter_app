// ignore_for_file: file_names

import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

const _migrationName = '102_groups_self_removed_at';

/// Adds durable local authority for a retained group shell whose local member
/// was removed by an authenticated membership event.
///
/// The legacy backfill is deliberately structural: an active group is marked
/// only when the singleton identity is usable and both its self-member row and
/// every committed group key are absent. Pending invitations and retained
/// history are evidence owned by other flows and are never consumed here.
Future<void> runGroupsSelfRemovedAtMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUPS_SELF_REMOVED_AT_MIGRATION_START',
    details: const {'migration': _migrationName},
  );

  try {
    final columns = await db.rawQuery('PRAGMA table_info(groups)');
    final columnNames = columns.map((row) => row['name'] as String).toSet();
    if (!columnNames.contains('self_removed_at')) {
      await db.execute('ALTER TABLE groups ADD COLUMN self_removed_at TEXT');
    }

    await db.rawUpdate('''
      UPDATE groups
      SET self_removed_at = COALESCE(last_membership_event_at, created_at)
      WHERE self_removed_at IS NULL
        AND is_dissolved = 0
        AND EXISTS (
          SELECT 1 FROM identity self
          WHERE self.id = 1 AND TRIM(self.peer_id) <> ''
        )
        AND NOT EXISTS (
          SELECT 1
          FROM group_members member
          JOIN identity self ON self.id = 1
          WHERE member.group_id = groups.id
            AND member.peer_id = self.peer_id
        )
        AND NOT EXISTS (
          SELECT 1 FROM group_keys key
          WHERE key.group_id = groups.id
        )
    ''');

    const markedGroups =
        '(SELECT id FROM groups WHERE self_removed_at IS NOT NULL)';
    for (final table in const <String>[
      'group_rejoin_state',
      'pending_group_broadcasts',
      'group_pending_key_repairs',
      'group_pending_key_distributions',
      'group_pending_membership_messages',
      'group_history_gap_repairs',
      'group_pending_reactions',
      'pending_sibling_devices',
    ]) {
      await db.rawDelete('DELETE FROM $table WHERE group_id IN $markedGroups');
    }

    // A stored replay row is durable receipt/evidence, not executable work.
    // Only rows that can still be delivered belong to the membership-instance
    // cleanup manifest.
    await db.rawDelete('''
      DELETE FROM group_reaction_replay_outbox
      WHERE group_id IN $markedGroups
        AND delivery_status IN ('pending', 'failed')
    ''');

    // Terminalize uploads before scrubbing their parent transport rows. The
    // visible parent and local media remain; only executable upload state ends.
    await db.rawUpdate('''
      UPDATE media_attachments
      SET download_status = 'upload_failed'
      WHERE owner_lane = 'group'
        AND download_status = 'upload_pending'
        AND message_id IN (
          SELECT message.id FROM group_messages message
          WHERE message.group_id IN $markedGroups
            AND message.is_incoming = 0
        )
    ''');

    await db.rawUpdate('''
      UPDATE group_messages
      SET status = 'send_failed',
          wire_envelope = NULL,
          inbox_retry_payload = NULL,
          next_eligible_at = NULL
      WHERE group_id IN $markedGroups
        AND is_incoming = 0
        AND (
          status IN ('sending', 'pending', 'failed', 'queued_offline', 'send_failed')
          OR wire_envelope IS NOT NULL
          OR inbox_retry_payload IS NOT NULL
          OR next_eligible_at IS NOT NULL
        )
    ''');

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUPS_SELF_REMOVED_AT_MIGRATION_SUCCESS',
      details: const {'migration': _migrationName},
    );
  } catch (error) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUPS_SELF_REMOVED_AT_MIGRATION_ERROR',
      details: {'migration': _migrationName, 'error': error.toString()},
    );
    rethrow;
  }
}
