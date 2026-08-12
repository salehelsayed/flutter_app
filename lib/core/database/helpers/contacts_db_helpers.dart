import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';
import '../db_write_transaction.dart';
import 'direct_contact_device_bindings_db_helpers.dart';

/// Loads all contacts from the database.
Future<List<Map<String, Object?>>> dbLoadAllContacts(Database db) async {
  emitFlowEvent(layer: 'DB', event: 'CONTACTS_DB_LOAD_ALL_START', details: {});

  try {
    final results = await db.query('contacts', orderBy: 'scanned_at DESC');

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
      details: {
        'peerId': peerId.length > 10 ? peerId.substring(0, 10) : peerId,
      },
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
///
/// 360: this is the EXACT contact-deletion owner, so it also removes that
/// contact's linked-device roster metadata and bindings — in ONE transaction,
/// roster first, contact last.
///
/// The v112 roster deliberately declares no FOREIGN KEY to `contacts`, because
/// ordinary contact upsert (`dbUpsertContact`) uses SQLite REPLACE semantics: a
/// cascade would silently destroy explicitly-verified device authority every
/// time the same contact re-announced their ML-KEM key. Deleting here — and
/// only here — is what keeps routine reannounce lossless while a real deletion
/// leaves nothing behind.
Future<void> dbDeleteContact(Database db, String peerId) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'CONTACTS_DB_DELETE_START',
    details: {'peerId': peerId.substring(0, 10)},
  );

  try {
    await dbWriteTransaction<void>(db, (txn) async {
      await dbDeleteContactWithinTransaction(txn, peerId);
    });

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

/// Transaction-body variant of [dbDeleteContact] (Plan 361).
///
/// The final serialized contact-deletion owner must remove v108/v109 rows,
/// reactions, messages, roster and contact in ONE transaction; factoring the
/// roster+contact body out lets that owner serialize everything without
/// nesting a second transaction.
Future<void> dbDeleteContactWithinTransaction(
  DatabaseExecutor txn,
  String peerId,
) async {
  await dbDeleteDirectContactDeviceRoster(txn, peerId);
  await txn.delete('contacts', where: 'peer_id = ?', whereArgs: [peerId]);
}

/// Row counts committed by one final serialized contact-conversation purge.
class DbContactConversationPurgeResult {
  const DbContactConversationPurgeResult({
    required this.deletedTextCustodyRows,
    required this.deletedEventCustodyRows,
    required this.deletedReactions,
    required this.deletedMessages,
    required this.deletedContact,
  });

  final int deletedTextCustodyRows;
  final int deletedEventCustodyRows;
  final int deletedReactions;
  final int deletedMessages;
  final bool deletedContact;
}

/// The exact final DB owner of direct-contact deletion (Plan 361).
///
/// In ONE serialized transaction: delete v108/v109 rows whose LOGICAL contact
/// is the removed account (`COALESCE(contact_account_peer_id,
/// recipient_peer_id)` for historical compatibility), delete
/// `message_reactions` through the still-live contact message IDs, delete
/// those messages, then delete the Plan 360 roster metadata/bindings and the
/// contact row itself. Reaction/apply/completion racing this owner either
/// commits first and is swept here, or runs after and finds its parent and
/// contact authority gone.
///
/// [beforeContactDeleteForTest] is a test-only barrier between the message
/// purge and the roster/contact deletion. It must only signal/await
/// completers; a same-connection write inside it would deadlock SQLite.
Future<DbContactConversationPurgeResult>
dbPurgeDirectContactConversationAndContact(
  Database db,
  String peerId, {
  Future<void> Function()? beforeContactDeleteForTest,
}) async {
  final normalized = peerId.trim();
  emitFlowEvent(
    layer: 'DB',
    event: 'CONTACTS_DB_PURGE_START',
    details: {
      'peerId': normalized.length > 10
          ? normalized.substring(0, 10)
          : normalized,
    },
  );

  try {
    final result = await dbWriteTransaction<DbContactConversationPurgeResult>(
      db,
      (txn) async {
        Future<bool> tableExists(String name) async => (await txn.rawQuery(
          "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? "
          'LIMIT 1',
          <Object?>[name],
        )).isNotEmpty;

        // 362: the final contact owner transitions every OUTGOING
        // logical-contact v114 blob row to cleanup BEFORE the v108/v109/
        // message purge, so the shared encrypted artifacts drain through the
        // incumbent last-reference lifecycle instead of orphaning. Exact
        // INCOMING committed/ACK-pending obligations deliberately survive —
        // they finish their own ACK/expiry convergence. The raw state UPDATE
        // is CHECK-safe for every legal outgoing shape (prepared rows carry
        // no proof tuple; stored/bound rows keep theirs).
        if (await tableExists('direct_media_blob_custody')) {
          await txn.rawUpdate(
            "UPDATE direct_media_blob_custody SET state = ?, updated_at = ? "
            "WHERE direction = 'outgoing' AND state IN (?, ?) "
            'AND COALESCE(contact_account_peer_id, recipient_peer_id) = ?',
            <Object?>[
              'outgoing_cleanup_pending',
              DateTime.now().toUtc().toIso8601String(),
              'outgoing_prepared',
              'outgoing_stored',
              normalized,
            ],
          );
        }
        var textCustodyRows = 0;
        if (await tableExists('direct_inbox_custody_outbox')) {
          textCustodyRows = await txn.rawDelete(
            'DELETE FROM direct_inbox_custody_outbox '
            'WHERE COALESCE(contact_account_peer_id, recipient_peer_id) = ?',
            <Object?>[normalized],
          );
        }
        var eventCustodyRows = 0;
        if (await tableExists('direct_reaction_inbox_custody_outbox')) {
          eventCustodyRows = await txn.rawDelete(
            'DELETE FROM direct_reaction_inbox_custody_outbox '
            'WHERE COALESCE(contact_account_peer_id, recipient_peer_id) = ?',
            <Object?>[normalized],
          );
        }
        var reactions = 0;
        if (await tableExists('message_reactions')) {
          // Reactions resolve through the STILL-LIVE contact message IDs, so
          // physically purging messages first would strand them; the order
          // here is load-bearing.
          reactions = await txn.rawDelete(
            'DELETE FROM message_reactions WHERE message_id IN '
            '(SELECT id FROM messages WHERE contact_peer_id = ?)',
            <Object?>[normalized],
          );
        }
        final messages = await txn.delete(
          'messages',
          where: 'contact_peer_id = ?',
          whereArgs: <Object?>[normalized],
        );
        // Test-only barrier between the conversation purge and the
        // roster/contact deletion. It must only signal/await completers.
        await beforeContactDeleteForTest?.call();
        await dbDeleteContactWithinTransaction(txn, normalized);
        final contactRemains = await txn.query(
          'contacts',
          columns: const <String>['peer_id'],
          where: 'peer_id = ?',
          whereArgs: <Object?>[normalized],
          limit: 1,
        );
        return DbContactConversationPurgeResult(
          deletedTextCustodyRows: textCustodyRows,
          deletedEventCustodyRows: eventCustodyRows,
          deletedReactions: reactions,
          deletedMessages: messages,
          deletedContact: contactRemains.isEmpty,
        );
      },
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'CONTACTS_DB_PURGE_SUCCESS',
      details: {
        'deletedMessages': result.deletedMessages,
        'deletedReactions': result.deletedReactions,
        'deletedTextCustodyRows': result.deletedTextCustodyRows,
        'deletedEventCustodyRows': result.deletedEventCustodyRows,
      },
    );
    return result;
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'CONTACTS_DB_PURGE_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Private SIMS-only primitive: insert one disposable contact without ever
/// replacing a row that appeared before or during the transaction.
Future<bool> dbSimsInsertContactIfAbsent(
  Database db,
  Map<String, Object?> row,
) => db.transaction<bool>((txn) async {
  final peerId = row['peer_id'];
  if (peerId is! String || peerId.isEmpty) return false;
  final existing = await txn.query(
    'contacts',
    columns: const <String>['peer_id'],
    where: 'peer_id = ?',
    whereArgs: <Object?>[peerId],
    limit: 1,
  );
  if (existing.isNotEmpty) return false;
  await txn.insert('contacts', row, conflictAlgorithm: ConflictAlgorithm.abort);
  return true;
});

/// Private SIMS-only primitive: remove one row only when every fixture-owned
/// column still has the expected value. An absent or changed row is untouched.
Future<bool> dbSimsDeleteContactIfExact(
  Database db,
  Map<String, Object?> expected,
) => db.transaction<bool>((txn) async {
  final peerId = expected['peer_id'];
  if (peerId is! String || peerId.isEmpty) return false;
  final rows = await txn.query(
    'contacts',
    where: 'peer_id = ?',
    whereArgs: <Object?>[peerId],
    limit: 1,
  );
  if (rows.length != 1 || !_simsContactRowsMatchExact(rows.single, expected)) {
    return false;
  }
  return await txn.delete(
        'contacts',
        where: 'peer_id = ?',
        whereArgs: <Object?>[peerId],
      ) ==
      1;
});

bool _simsContactRowsMatchExact(
  Map<String, Object?> actual,
  Map<String, Object?> expected,
) {
  for (final entry in expected.entries) {
    if (actual[entry.key] != entry.value) return false;
  }
  return true;
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

/// Dismisses the intro banner for a contact.
Future<void> dbDismissIntroBanner(Database db, String peerId) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'CONTACTS_DB_DISMISS_INTRO_BANNER_START',
    details: {'peerId': peerId.substring(0, 10)},
  );

  try {
    await db.rawUpdate(
      'UPDATE contacts SET intros_banner_dismissed = 1 WHERE peer_id = ?',
      [peerId],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'CONTACTS_DB_DISMISS_INTRO_BANNER_SUCCESS',
      details: {'peerId': peerId.substring(0, 10)},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'CONTACTS_DB_DISMISS_INTRO_BANNER_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}

/// Sets the intros_sent_at timestamp and auto-dismisses the banner.
Future<void> dbSetIntrosSentAt(
  Database db,
  String peerId,
  String timestamp,
) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'CONTACTS_DB_SET_INTROS_SENT_AT_START',
    details: {'peerId': peerId.substring(0, 10)},
  );

  try {
    await db.rawUpdate(
      'UPDATE contacts SET intros_sent_at = ?, intros_banner_dismissed = 1 WHERE peer_id = ?',
      [timestamp, peerId],
    );

    emitFlowEvent(
      layer: 'DB',
      event: 'CONTACTS_DB_SET_INTROS_SENT_AT_SUCCESS',
      details: {'peerId': peerId.substring(0, 10)},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'DB',
      event: 'CONTACTS_DB_SET_INTROS_SENT_AT_ERROR',
      details: {'error': e.toString()},
    );
    rethrow;
  }
}
