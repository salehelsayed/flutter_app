import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

Future<void> dbUpsertGroupWelcomeKeyPackageTombstone(
  Database db,
  Map<String, Object?> row,
) async {
  final packageId = row['package_id'] as String? ?? '';

  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_WELCOME_KEY_PACKAGE_TOMBSTONE_DB_UPSERT_START',
    details: {
      'packageId': packageId.length > 8 ? packageId.substring(0, 8) : packageId,
    },
  );

  try {
    await db.insert(
      'group_welcome_key_package_tombstones',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_WELCOME_KEY_PACKAGE_TOMBSTONE_DB_UPSERT_SUCCESS',
      details: {
        'packageId': packageId.length > 8
            ? packageId.substring(0, 8)
            : packageId,
      },
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_WELCOME_KEY_PACKAGE_TOMBSTONE_DB_UPSERT_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

Future<Map<String, Object?>?> dbLoadGroupWelcomeKeyPackageTombstone(
  Database db, {
  required String packageId,
  required String recipientDeviceId,
  required String groupId,
}) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_WELCOME_KEY_PACKAGE_TOMBSTONE_DB_LOAD_START',
    details: {
      'packageId': packageId.length > 8 ? packageId.substring(0, 8) : packageId,
    },
  );

  try {
    final rows = await db.query(
      'group_welcome_key_package_tombstones',
      where: 'package_id = ? AND recipient_device_id = ? AND group_id = ?',
      whereArgs: [packageId, recipientDeviceId, groupId],
      limit: 1,
    );
    final row = rows.isEmpty ? null : rows.first;
    emitFlowEvent(
      layer: 'DB',
      event: row == null
          ? 'GROUP_WELCOME_KEY_PACKAGE_TOMBSTONE_DB_LOAD_NOT_FOUND'
          : 'GROUP_WELCOME_KEY_PACKAGE_TOMBSTONE_DB_LOAD_FOUND',
      details: {
        'packageId': packageId.length > 8
            ? packageId.substring(0, 8)
            : packageId,
      },
    );
    return row;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_WELCOME_KEY_PACKAGE_TOMBSTONE_DB_LOAD_ERROR',
      details: {'packageId': packageId, 'error': e.toString()},
    );
    rethrow;
  }
}

Future<int> dbDeleteExpiredGroupWelcomeKeyPackageTombstones(
  Database db,
  String cutoff,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_WELCOME_KEY_PACKAGE_TOMBSTONE_DB_DELETE_EXPIRED_START',
    details: {'cutoff': cutoff},
  );

  try {
    final deleted = await db.delete(
      'group_welcome_key_package_tombstones',
      where: 'expires_at <= ?',
      whereArgs: [cutoff],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_WELCOME_KEY_PACKAGE_TOMBSTONE_DB_DELETE_EXPIRED_SUCCESS',
      details: {'deletedCount': deleted},
    );
    return deleted;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_WELCOME_KEY_PACKAGE_TOMBSTONE_DB_DELETE_EXPIRED_ERROR',
      details: {'cutoff': cutoff, 'error': e.toString()},
    );
    rethrow;
  }
}
