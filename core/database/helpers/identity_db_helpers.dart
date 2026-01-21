import 'package:sqflite/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Loads the single identity row (id=1) from the database.
/// 
/// Returns:
/// - A Map with the identity row data if found
/// - null if no row exists
/// - Throws an exception if the table doesn't exist or other DB error
Future<Map<String, Object?>?> dbLoadIdentityRow(Database db) async {
  const int identityId = 1;
  
  emitFlowEvent(
    layer: 'DB',
    event: 'ID_DB_LOAD_IDENTITY_START',
    details: {'id': identityId},
  );
  
  try {
    final List<Map<String, Object?>> results = await db.query(
      'identity',
      where: 'id = ?',
      whereArgs: [identityId],
      limit: 1,
    );
    
    if (results.isNotEmpty) {
      emitFlowEvent(
        layer: 'DB',
        event: 'ID_DB_LOAD_IDENTITY_FOUND',
        details: {'id': identityId},
      );
      return results.first;
    } else {
      emitFlowEvent(
        layer: 'DB',
        event: 'ID_DB_LOAD_IDENTITY_NOT_FOUND',
        details: {'id': identityId},
      );
      return null;
    }
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'ID_DB_LOAD_IDENTITY_ERROR',
      details: {'id': identityId, 'error': e.toString()},
    );
    rethrow;
  }
}

/// Upserts the identity row at id=1.
///
/// The input [row] is expected to contain keys:
/// "peer_id", "public_key", "private_key", "mnemonic12", "created_at", "updated_at"
///
/// This function always writes to id=1, implementing INSERT OR REPLACE semantics.
/// Any database errors are emitted as flow events and then rethrown.
Future<void> dbUpsertIdentityRow(Database db, Map<String, Object?> row) async {
  const int identityId = 1;

  emitFlowEvent(
    layer: 'DB',
    event: 'ID_DB_UPSERT_IDENTITY_START',
    details: {'id': identityId},
  );

  try {
    final rowWithId = <String, Object?>{
      'id': identityId,
      ...row,
    };

    await db.insert(
      'identity',
      rowWithId,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'ID_DB_UPSERT_IDENTITY_SUCCESS',
      details: {'id': identityId},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'ID_DB_UPSERT_IDENTITY_ERROR',
      details: {'id': identityId, 'error': e.toString()},
    );
    rethrow;
  }
}
