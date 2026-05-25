import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Inserts a group into the database.
Future<void> dbInsertGroup(Database db, Map<String, Object?> row) async {
  final id = row['id'] as String? ?? '';

  emitFlowEvent(
    layer: 'DB',
    event: 'GROUPS_DB_INSERT_START',
    details: {'id': id.length > 8 ? id.substring(0, 8) : id},
  );

  try {
    await db.insert(
      'groups',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUPS_DB_INSERT_SUCCESS',
      details: {'id': id.length > 8 ? id.substring(0, 8) : id},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUPS_DB_INSERT_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Loads all groups from the database, ordered by created_at DESC.
Future<List<Map<String, Object?>>> dbLoadAllGroups(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUPS_DB_LOAD_ALL_START',
    details: {},
  );

  try {
    final results = await db.query(
      'groups',
      orderBy: 'created_at DESC',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUPS_DB_LOAD_ALL_SUCCESS',
      details: {'count': results.length},
    );

    return results;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUPS_DB_LOAD_ALL_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Loads a single group by ID.
Future<Map<String, Object?>?> dbLoadGroup(Database db, String id) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUPS_DB_LOAD_START',
    details: {'id': id.length > 8 ? id.substring(0, 8) : id},
  );

  try {
    final results = await db.query(
      'groups',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );

    if (results.isNotEmpty) {
      emitFlowEvent(
        layer: 'DB',
        event: 'GROUPS_DB_LOAD_FOUND',
        details: {'id': id.length > 8 ? id.substring(0, 8) : id},
      );
      return results.first;
    } else {
      emitFlowEvent(
        layer: 'DB',
        event: 'GROUPS_DB_LOAD_NOT_FOUND',
        details: {'id': id.length > 8 ? id.substring(0, 8) : id},
      );
      return null;
    }
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUPS_DB_LOAD_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Updates a group in the database (full row replace).
Future<void> dbUpdateGroup(Database db, Map<String, Object?> row) async {
  final id = row['id'] as String? ?? '';

  emitFlowEvent(
    layer: 'DB',
    event: 'GROUPS_DB_UPDATE_START',
    details: {'id': id.length > 8 ? id.substring(0, 8) : id},
  );

  try {
    await db.update(
      'groups',
      row,
      where: 'id = ?',
      whereArgs: [id],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUPS_DB_UPDATE_SUCCESS',
      details: {'id': id.length > 8 ? id.substring(0, 8) : id},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUPS_DB_UPDATE_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Deletes a group by ID.
Future<void> dbDeleteGroup(Database db, String id) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUPS_DB_DELETE_START',
    details: {'id': id.length > 8 ? id.substring(0, 8) : id},
  );

  try {
    await db.delete(
      'groups',
      where: 'id = ?',
      whereArgs: [id],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUPS_DB_DELETE_SUCCESS',
      details: {'id': id.length > 8 ? id.substring(0, 8) : id},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUPS_DB_DELETE_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Returns the count of groups.
Future<int> dbCountGroups(Database db) async {
  try {
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM groups');
    return Sqflite.firstIntValue(result) ?? 0;
  } catch (e) {
    return 0;
  }
}

/// Archives a group by ID.
Future<void> dbArchiveGroup(Database db, String id) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUPS_DB_ARCHIVE_START',
    details: {'id': id.length > 8 ? id.substring(0, 8) : id},
  );

  try {
    final now = DateTime.now().toUtc().toIso8601String();
    await db.rawUpdate(
      'UPDATE groups SET is_archived = 1, archived_at = ? WHERE id = ?',
      [now, id],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUPS_DB_ARCHIVE_SUCCESS',
      details: {'id': id.length > 8 ? id.substring(0, 8) : id},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUPS_DB_ARCHIVE_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Unarchives a group by ID.
Future<void> dbUnarchiveGroup(Database db, String id) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUPS_DB_UNARCHIVE_START',
    details: {'id': id.length > 8 ? id.substring(0, 8) : id},
  );

  try {
    await db.rawUpdate(
      'UPDATE groups SET is_archived = 0, archived_at = NULL WHERE id = ?',
      [id],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUPS_DB_UNARCHIVE_SUCCESS',
      details: {'id': id.length > 8 ? id.substring(0, 8) : id},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUPS_DB_UNARCHIVE_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Loads only active (non-archived) groups.
Future<List<Map<String, Object?>>> dbLoadActiveGroups(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUPS_DB_LOAD_ACTIVE_START',
    details: {},
  );

  try {
    final results = await db.rawQuery(
      'SELECT * FROM groups WHERE is_archived = 0 ORDER BY created_at DESC',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUPS_DB_LOAD_ACTIVE_SUCCESS',
      details: {'count': results.length},
    );

    return results;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUPS_DB_LOAD_ACTIVE_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}
