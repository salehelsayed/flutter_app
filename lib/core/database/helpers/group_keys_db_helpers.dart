import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Inserts a group key into the database.
Future<void> dbInsertGroupKey(Database db, Map<String, Object?> row) async {
  final groupId = row['group_id'] as String? ?? '';
  final keyGen = row['key_generation'] as int? ?? 0;

  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_KEYS_DB_INSERT_START',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'keyGeneration': keyGen,
    },
  );

  try {
    await db.insert(
      'group_keys',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_KEYS_DB_INSERT_SUCCESS',
      details: {
        'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
        'keyGeneration': keyGen,
      },
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_KEYS_DB_INSERT_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Loads the latest (highest generation) key for a group.
Future<Map<String, Object?>?> dbLoadLatestGroupKey(
  Database db,
  String groupId,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_KEYS_DB_LOAD_LATEST_START',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
    },
  );

  try {
    final results = await db.query(
      'group_keys',
      where: 'group_id = ?',
      whereArgs: [groupId],
      orderBy: 'key_generation DESC',
      limit: 1,
    );

    if (results.isNotEmpty) {
      emitFlowEvent(
        layer: 'DB',
        event: 'GROUP_KEYS_DB_LOAD_LATEST_FOUND',
        details: {'keyGeneration': results.first['key_generation']},
      );
      return results.first;
    } else {
      emitFlowEvent(
        layer: 'DB',
        event: 'GROUP_KEYS_DB_LOAD_LATEST_NOT_FOUND',
        details: {},
      );
      return null;
    }
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_KEYS_DB_LOAD_LATEST_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Loads a group key by group ID and key generation.
Future<Map<String, Object?>?> dbLoadGroupKeyByGeneration(
  Database db,
  String groupId,
  int keyGeneration,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_KEYS_DB_LOAD_BY_GEN_START',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'keyGeneration': keyGeneration,
    },
  );

  try {
    final results = await db.query(
      'group_keys',
      where: 'group_id = ? AND key_generation = ?',
      whereArgs: [groupId, keyGeneration],
      limit: 1,
    );

    if (results.isNotEmpty) {
      emitFlowEvent(
        layer: 'DB',
        event: 'GROUP_KEYS_DB_LOAD_BY_GEN_FOUND',
        details: {},
      );
      return results.first;
    } else {
      emitFlowEvent(
        layer: 'DB',
        event: 'GROUP_KEYS_DB_LOAD_BY_GEN_NOT_FOUND',
        details: {},
      );
      return null;
    }
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_KEYS_DB_LOAD_BY_GEN_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Loads all keys for a group, ordered by key_generation ASC.
Future<List<Map<String, Object?>>> dbLoadAllGroupKeys(
  Database db,
  String groupId,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_KEYS_DB_LOAD_ALL_START',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
    },
  );

  try {
    final results = await db.query(
      'group_keys',
      where: 'group_id = ?',
      whereArgs: [groupId],
      orderBy: 'key_generation ASC',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_KEYS_DB_LOAD_ALL_SUCCESS',
      details: {'count': results.length},
    );

    return results;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_KEYS_DB_LOAD_ALL_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Deletes all keys for a group.
Future<void> dbDeleteAllGroupKeys(Database db, String groupId) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_KEYS_DB_DELETE_ALL_START',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
    },
  );

  try {
    await db.delete('group_keys', where: 'group_id = ?', whereArgs: [groupId]);

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_KEYS_DB_DELETE_ALL_SUCCESS',
      details: {},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_KEYS_DB_DELETE_ALL_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Deletes keys older than [minKeyGenerationToKeep] for a group.
Future<void> dbDeleteGroupKeysBeforeGeneration(
  Database db,
  String groupId,
  int minKeyGenerationToKeep,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_KEYS_DB_DELETE_OBSOLETE_START',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'minKeyGenerationToKeep': minKeyGenerationToKeep,
    },
  );

  try {
    await db.delete(
      'group_keys',
      where: 'group_id = ? AND key_generation < ?',
      whereArgs: [groupId, minKeyGenerationToKeep],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_KEYS_DB_DELETE_OBSOLETE_SUCCESS',
      details: {'minKeyGenerationToKeep': minKeyGenerationToKeep},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_KEYS_DB_DELETE_OBSOLETE_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}
