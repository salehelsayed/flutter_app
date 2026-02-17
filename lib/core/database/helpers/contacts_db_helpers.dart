import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

/// Loads all contacts from the database.
Future<List<Map<String, Object?>>> dbLoadAllContacts(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'CONTACTS_DB_LOAD_ALL_START',
    details: {},
  );

  try {
    final results = await db.query(
      'contacts',
      orderBy: 'scanned_at DESC',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'CONTACTS_DB_LOAD_ALL_SUCCESS',
      details: {'count': results.length},
    );

    return results;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'CONTACTS_DB_LOAD_ALL_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Loads a single contact by peer ID.
Future<Map<String, Object?>?> dbLoadContact(Database db, String peerId) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'CONTACTS_DB_LOAD_START',
    details: {'peerId': peerId.substring(0, 10)},
  );

  try {
    final results = await db.query(
      'contacts',
      where: 'peer_id = ?',
      whereArgs: [peerId],
      limit: 1,
    );

    if (results.isNotEmpty) {
      emitFlowEvent(
        layer: 'DB',
        event: 'CONTACTS_DB_LOAD_FOUND',
        details: {'peerId': peerId.substring(0, 10)},
      );
      return results.first;
    } else {
      emitFlowEvent(
        layer: 'DB',
        event: 'CONTACTS_DB_LOAD_NOT_FOUND',
        details: {'peerId': peerId.substring(0, 10)},
      );
      return null;
    }
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'CONTACTS_DB_LOAD_ERROR',
      details: {'peerId': peerId.substring(0, 10), 'error': e.toString()},
    );
    rethrow;
  }
}

/// Inserts or updates a contact.
Future<void> dbUpsertContact(Database db, Map<String, Object?> row) async {
  final peerId = row['peer_id'] as String? ?? '';

  emitFlowEvent(
    layer: 'DB',
    event: 'CONTACTS_DB_UPSERT_START',
    details: {'peerId': peerId.length > 10 ? peerId.substring(0, 10) : peerId},
  );

  try {
    await db.insert(
      'contacts',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'CONTACTS_DB_UPSERT_SUCCESS',
      details: {'peerId': peerId.length > 10 ? peerId.substring(0, 10) : peerId},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'CONTACTS_DB_UPSERT_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Deletes a contact by peer ID.
Future<void> dbDeleteContact(Database db, String peerId) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'CONTACTS_DB_DELETE_START',
    details: {'peerId': peerId.substring(0, 10)},
  );

  try {
    await db.delete(
      'contacts',
      where: 'peer_id = ?',
      whereArgs: [peerId],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'CONTACTS_DB_DELETE_SUCCESS',
      details: {'peerId': peerId.substring(0, 10)},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'CONTACTS_DB_DELETE_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Returns the count of contacts.
Future<int> dbGetContactCount(Database db) async {
  try {
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM contacts');
    return Sqflite.firstIntValue(result) ?? 0;
  } catch (e) {
    return 0;
  }
}

/// Archives a contact by peer ID.
Future<void> dbArchiveContact(Database db, String peerId) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'CONTACTS_DB_ARCHIVE_START',
    details: {'peerId': peerId.substring(0, 10)},
  );

  try {
    final now = DateTime.now().toUtc().toIso8601String();
    await db.rawUpdate(
      'UPDATE contacts SET is_archived = 1, archived_at = ? WHERE peer_id = ?',
      [now, peerId],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'CONTACTS_DB_ARCHIVE_SUCCESS',
      details: {'peerId': peerId.substring(0, 10)},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'CONTACTS_DB_ARCHIVE_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Unarchives a contact by peer ID.
Future<void> dbUnarchiveContact(Database db, String peerId) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'CONTACTS_DB_UNARCHIVE_START',
    details: {'peerId': peerId.substring(0, 10)},
  );

  try {
    await db.rawUpdate(
      'UPDATE contacts SET is_archived = 0, archived_at = NULL WHERE peer_id = ?',
      [peerId],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'CONTACTS_DB_UNARCHIVE_SUCCESS',
      details: {'peerId': peerId.substring(0, 10)},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'CONTACTS_DB_UNARCHIVE_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Loads only active (non-archived) contacts.
Future<List<Map<String, Object?>>> dbLoadActiveContacts(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'CONTACTS_DB_LOAD_ACTIVE_START',
    details: {},
  );

  try {
    final results = await db.rawQuery(
      'SELECT * FROM contacts WHERE is_archived = 0 ORDER BY scanned_at DESC',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'CONTACTS_DB_LOAD_ACTIVE_SUCCESS',
      details: {'count': results.length},
    );

    return results;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'CONTACTS_DB_LOAD_ACTIVE_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Loads only archived contacts.
Future<List<Map<String, Object?>>> dbLoadArchivedContacts(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'CONTACTS_DB_LOAD_ARCHIVED_START',
    details: {},
  );

  try {
    final results = await db.rawQuery(
      'SELECT * FROM contacts WHERE is_archived = 1 ORDER BY archived_at DESC',
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'CONTACTS_DB_LOAD_ARCHIVED_SUCCESS',
      details: {'count': results.length},
    );

    return results;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'CONTACTS_DB_LOAD_ARCHIVED_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Blocks a contact by peer ID.
Future<void> dbBlockContact(Database db, String peerId) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'CONTACTS_DB_BLOCK_START',
    details: {'peerId': peerId.substring(0, 10)},
  );

  try {
    final now = DateTime.now().toUtc().toIso8601String();
    await db.rawUpdate(
      'UPDATE contacts SET is_blocked = 1, blocked_at = ? WHERE peer_id = ?',
      [now, peerId],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'CONTACTS_DB_BLOCK_SUCCESS',
      details: {'peerId': peerId.substring(0, 10)},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'CONTACTS_DB_BLOCK_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Unblocks a contact by peer ID.
Future<void> dbUnblockContact(Database db, String peerId) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'CONTACTS_DB_UNBLOCK_START',
    details: {'peerId': peerId.substring(0, 10)},
  );

  try {
    await db.rawUpdate(
      'UPDATE contacts SET is_blocked = 0, blocked_at = NULL WHERE peer_id = ?',
      [peerId],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'CONTACTS_DB_UNBLOCK_SUCCESS',
      details: {'peerId': peerId.substring(0, 10)},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'CONTACTS_DB_UNBLOCK_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Checks if a contact exists.
Future<bool> dbContactExists(Database db, String peerId) async {
  try {
    final result = await db.query(
      'contacts',
      columns: ['peer_id'],
      where: 'peer_id = ?',
      whereArgs: [peerId],
      limit: 1,
    );
    return result.isNotEmpty;
  } catch (e) {
    return false;
  }
}
