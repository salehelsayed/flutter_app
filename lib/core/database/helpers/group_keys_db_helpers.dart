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
    final existing = await db.query(
      'group_keys',
      columns: ['encrypted_key'],
      where: 'group_id = ? AND key_generation = ?',
      whereArgs: [groupId, keyGen],
      limit: 1,
    );
    if (existing.isNotEmpty) {
      final existingEncryptedKey = existing.first['encrypted_key'];
      if (existingEncryptedKey == row['encrypted_key']) {
        emitFlowEvent(
          layer: 'DB',
          event: 'GROUP_KEYS_DB_INSERT_IDEMPOTENT',
          details: {
            'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
            'keyGeneration': keyGen,
          },
        );
        emitFlowEvent(
          layer: 'DB',
          event: 'GROUP_KEYS_DB_INSERT_SUCCESS',
          details: {
            'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
            'keyGeneration': keyGen,
          },
        );
        return;
      }

      emitFlowEvent(
        layer: 'DB',
        event: 'GROUP_KEYS_DB_INSERT_CONFLICT',
        details: {
          'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
          'keyGeneration': keyGen,
          'reason': 'encrypted_key_mismatch',
        },
      );
      throw StateError(
        'Conflicting group key for group $groupId generation $keyGen',
      );
    }

    await db.insert(
      'group_keys',
      row,
      conflictAlgorithm: ConflictAlgorithm.abort,
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

/// Upserts the locally generated but not yet committed rotation key for a
/// group. Only one draft is kept per group because rotation execution is
/// serialized at the use-case boundary.
Future<void> dbUpsertPendingGroupKeyRotation(
  Database db,
  Map<String, Object?> row,
) async {
  final groupId = row['group_id'] as String? ?? '';
  final keyGen = row['key_generation'] as int? ?? 0;

  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_KEY_ROTATION_DRAFT_DB_UPSERT_START',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'keyGeneration': keyGen,
    },
  );

  try {
    await db.insert(
      'group_key_rotation_drafts',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_KEY_ROTATION_DRAFT_DB_UPSERT_SUCCESS',
      details: {'keyGeneration': keyGen},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_KEY_ROTATION_DRAFT_DB_UPSERT_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Loads the pending local rotation draft for a group, if one exists.
Future<Map<String, Object?>?> dbLoadPendingGroupKeyRotation(
  Database db,
  String groupId,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_KEY_ROTATION_DRAFT_DB_LOAD_START',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
    },
  );

  try {
    final results = await db.query(
      'group_key_rotation_drafts',
      where: 'group_id = ?',
      whereArgs: [groupId],
      limit: 1,
    );

    if (results.isEmpty) {
      emitFlowEvent(
        layer: 'DB',
        event: 'GROUP_KEY_ROTATION_DRAFT_DB_LOAD_NOT_FOUND',
        details: {},
      );
      return null;
    }

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_KEY_ROTATION_DRAFT_DB_LOAD_FOUND',
      details: {'keyGeneration': results.first['key_generation']},
    );
    return results.first;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_KEY_ROTATION_DRAFT_DB_LOAD_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Deletes one pending local rotation draft when it matches the generation
/// being abandoned or promoted.
Future<void> dbDeletePendingGroupKeyRotation(
  Database db,
  String groupId,
  int keyGeneration,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_KEY_ROTATION_DRAFT_DB_DELETE_START',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
      'keyGeneration': keyGeneration,
    },
  );

  try {
    await db.delete(
      'group_key_rotation_drafts',
      where: 'group_id = ? AND key_generation = ?',
      whereArgs: [groupId, keyGeneration],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_KEY_ROTATION_DRAFT_DB_DELETE_SUCCESS',
      details: {'keyGeneration': keyGeneration},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_KEY_ROTATION_DRAFT_DB_DELETE_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Deletes all pending local rotation drafts for a group.
Future<void> dbDeletePendingGroupKeyRotations(
  Database db,
  String groupId,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_KEY_ROTATION_DRAFT_DB_DELETE_ALL_START',
    details: {
      'groupId': groupId.length > 8 ? groupId.substring(0, 8) : groupId,
    },
  );

  try {
    await db.delete(
      'group_key_rotation_drafts',
      where: 'group_id = ?',
      whereArgs: [groupId],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_KEY_ROTATION_DRAFT_DB_DELETE_ALL_SUCCESS',
      details: {},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_KEY_ROTATION_DRAFT_DB_DELETE_ALL_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}
