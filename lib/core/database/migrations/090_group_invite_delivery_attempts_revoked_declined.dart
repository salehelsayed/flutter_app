// ignore_for_file: file_names

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Rebuilds `group_invite_delivery_attempts` to:
///  - widen the status CHECK to include `revoked` (Review-08 finding C) and
///    `declined` (finding F) — folded into one rebuild since SQLite cannot
///    ALTER a CHECK constraint, and
///  - add a nullable `invite_id TEXT` column so the sender can persist the
///    exact invite id the receiver matches on when honoring a revocation
///    (HOLE-4: without it, revocation tombstones save but the live pending
///    invite is never deleted → a false "revoked" auth hole).
///
/// Legacy rows keep `invite_id = NULL`.
Future<void> runGroupInviteDeliveryAttemptsRevokedDeclinedMigration(
  Database db,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_INVITE_DELIVERY_ATTEMPTS_REVOKED_DECLINED_MIGRATION_START',
    details: {'migration': '090_group_invite_delivery_attempts_revoked_declined'},
  );

  try {
    await db.execute('''
      CREATE TABLE group_invite_delivery_attempts_new (
        group_id TEXT NOT NULL,
        peer_id TEXT NOT NULL,
        username TEXT,
        status TEXT NOT NULL CHECK(status IN (
          'sent',
          'queued',
          'needs_resend',
          'cannot_send',
          'joined',
          'revoked',
          'declined'
        )),
        attempted_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        last_error TEXT,
        invite_id TEXT,
        PRIMARY KEY(group_id, peer_id)
      )
    ''');
    await db.execute('''
      INSERT INTO group_invite_delivery_attempts_new (
        group_id, peer_id, username, status, attempted_at, updated_at, last_error
      )
      SELECT
        group_id, peer_id, username, status, attempted_at, updated_at, last_error
      FROM group_invite_delivery_attempts
    ''');
    await db.execute('DROP TABLE group_invite_delivery_attempts');
    await db.execute(
      'ALTER TABLE group_invite_delivery_attempts_new '
      'RENAME TO group_invite_delivery_attempts',
    );

    // Recreate the two indexes from 067.
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_group_invite_delivery_attempts_group_status
      ON group_invite_delivery_attempts(group_id, status)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_group_invite_delivery_attempts_peer
      ON group_invite_delivery_attempts(peer_id)
    ''');

    emitFlowEvent(
      layer: 'DB',
      event:
          'GROUP_INVITE_DELIVERY_ATTEMPTS_REVOKED_DECLINED_MIGRATION_SUCCESS',
      details: {
        'migration': '090_group_invite_delivery_attempts_revoked_declined',
      },
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_INVITE_DELIVERY_ATTEMPTS_REVOKED_DECLINED_MIGRATION_ERROR',
      details: {
        'migration': '090_group_invite_delivery_attempts_revoked_declined',
        'error': e.toString(),
      },
    );
    rethrow;
  }
}
