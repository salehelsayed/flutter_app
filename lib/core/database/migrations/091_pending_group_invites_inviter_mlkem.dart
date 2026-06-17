// ignore_for_file: file_names

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Migration 091: Add `inviter_mlkem_public_key TEXT` to `pending_group_invites`.
///
/// A group invite routinely comes from a non-contact, so a decline-ack could
/// not be encrypted back to the inviter (no resolvable ML-KEM key → silent
/// `DECLINE_ACK_ENCRYPTION_SKIPPED`). This nullable column persists the
/// inviter's account-level ML-KEM public key (captured from the invite's
/// membership-freshness proof at receive time) so the decline path can reach a
/// non-contact inviter (Review-08 finding F / gap G1). Legacy rows keep
/// `inviter_mlkem_public_key = NULL` and fall back to a contacts lookup.
Future<void> runPendingGroupInvitesInviterMlKemMigration(Database db) async {
  final columns = await db.rawQuery('PRAGMA table_info(pending_group_invites)');
  final columnNames = columns.map((col) => col['name'] as String).toSet();

  if (columnNames.contains('inviter_mlkem_public_key')) {
    emitFlowEvent(
      layer: 'DB',
      event: 'PENDING_GROUP_INVITES_INVITER_MLKEM_MIGRATION_ALREADY_DONE',
      details: {'migration': '091_pending_group_invites_inviter_mlkem'},
    );
    return;
  }

  emitFlowEvent(
    layer: 'DB',
    event: 'PENDING_GROUP_INVITES_INVITER_MLKEM_MIGRATION_START',
    details: {'migration': '091_pending_group_invites_inviter_mlkem'},
  );

  try {
    await db.execute(
      'ALTER TABLE pending_group_invites ADD COLUMN inviter_mlkem_public_key TEXT',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'PENDING_GROUP_INVITES_INVITER_MLKEM_MIGRATION_SUCCESS',
      details: {'migration': '091_pending_group_invites_inviter_mlkem'},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'PENDING_GROUP_INVITES_INVITER_MLKEM_MIGRATION_ERROR',
      details: {
        'migration': '091_pending_group_invites_inviter_mlkem',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
