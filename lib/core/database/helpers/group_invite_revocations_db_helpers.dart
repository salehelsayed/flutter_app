import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

Future<void> dbUpsertGroupInviteRevocation(
  Database db,
  Map<String, Object?> row,
) async {
  final inviteId = row['invite_id'] as String? ?? '';

  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_INVITE_REVOCATIONS_DB_UPSERT_START',
    details: {
      'inviteId': inviteId.length > 8 ? inviteId.substring(0, 8) : inviteId,
    },
  );

  try {
    await db.insert(
      'group_invite_revocations',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_INVITE_REVOCATIONS_DB_UPSERT_SUCCESS',
      details: {
        'inviteId': inviteId.length > 8 ? inviteId.substring(0, 8) : inviteId,
      },
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_INVITE_REVOCATIONS_DB_UPSERT_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

Future<Map<String, Object?>?> dbLoadGroupInviteRevocation(
  Database db,
  String inviteId,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_INVITE_REVOCATIONS_DB_LOAD_START',
    details: {
      'inviteId': inviteId.length > 8 ? inviteId.substring(0, 8) : inviteId,
    },
  );

  try {
    final rows = await db.query(
      'group_invite_revocations',
      where: 'invite_id = ?',
      whereArgs: [inviteId],
      limit: 1,
    );

    final row = rows.isEmpty ? null : rows.first;
    emitFlowEvent(
      layer: 'DB',
      event: row == null
          ? 'GROUP_INVITE_REVOCATIONS_DB_LOAD_NOT_FOUND'
          : 'GROUP_INVITE_REVOCATIONS_DB_LOAD_FOUND',
      details: {
        'inviteId': inviteId.length > 8 ? inviteId.substring(0, 8) : inviteId,
      },
    );
    return row;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_INVITE_REVOCATIONS_DB_LOAD_ERROR',
      details: {'inviteId': inviteId, 'error': e.toString()},
    );
    rethrow;
  }
}

Future<int> dbDeleteExpiredGroupInviteRevocations(
  Database db,
  String cutoff,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_INVITE_REVOCATIONS_DB_DELETE_EXPIRED_START',
    details: {'cutoff': cutoff},
  );

  try {
    final deleted = await db.delete(
      'group_invite_revocations',
      where: 'expires_at <= ?',
      whereArgs: [cutoff],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_INVITE_REVOCATIONS_DB_DELETE_EXPIRED_SUCCESS',
      details: {'deletedCount': deleted},
    );
    return deleted;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_INVITE_REVOCATIONS_DB_DELETE_EXPIRED_ERROR',
      details: {'cutoff': cutoff, 'error': e.toString()},
    );
    rethrow;
  }
}
