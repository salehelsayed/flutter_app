import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../media/media_attachment_lifecycle_lock.dart';
import '../../secure_storage/secret_storage_references.dart';
import '../../secure_storage/secure_key_store.dart';

/// Key material read before a SQL transaction, while media ownership is held.
/// The snapshot cannot authorize a later callback after its scope completes.
final class GroupMediaKeySnapshot {
  GroupMediaKeySnapshot._(this._database, this._keys);

  final Database _database;
  final Map<String, ({String messageId, String reference, String key})> _keys;
  bool _active = true;

  bool matches({
    required DatabaseExecutor db,
    required String attachmentId,
    required String messageId,
    required Object? storedKey,
    required String committedKey,
  }) {
    if (!_active || !identical(db.database, _database)) return false;
    final entry = _keys[attachmentId];
    return entry != null &&
        entry.messageId == messageId &&
        entry.reference == storedKey &&
        entry.key == committedKey;
  }
}

/// Keeps secure-key reads and the following SQL checks in one existing media
/// lifecycle scope. SQL callers consume the snapshot without platform I/O.
final class GroupMediaKeyAccess {
  GroupMediaKeyAccess({
    required SecureKeyStore secureKeyStore,
    MediaAttachmentLifecycleLock? lifecycleLock,
  }) : _secureKeyStore = secureKeyStore,
       _lifecycleLock = lifecycleLock ?? mediaAttachmentLifecycleLock;

  final SecureKeyStore _secureKeyStore;
  final MediaAttachmentLifecycleLock _lifecycleLock;

  Future<T> run<T>({
    required DatabaseExecutor db,
    required Iterable<String> messageIds,
    required Future<T> Function(GroupMediaKeySnapshot snapshot) action,
  }) {
    if (db is! Database) {
      throw StateError('group media key reads must precede the transaction');
    }
    final ids = messageIds.where((id) => id.isNotEmpty).toSet().toList()
      ..sort();
    return _lifecycleLock.synchronizedAll(() async {
      final keys =
          <String, ({String messageId, String reference, String key})>{};
      for (final messageId in ids) {
        final rows = await db.query(
          'media_attachments',
          columns: const <String>['id', 'encryption_key_base64'],
          where: 'message_id = ? AND owner_lane = ?',
          whereArgs: <Object?>[messageId, 'group'],
        );
        for (final row in rows) {
          final id = row['id'];
          if (id is! String || id.isEmpty) continue;
          final keyName = mediaAttachmentEncryptionKeyStoreName(id);
          final reference = secureStoreReferenceForKey(keyName);
          if (row['encryption_key_base64'] != reference) continue;
          final key = await _secureKeyStore.read(keyName);
          if (key == null || key.isEmpty || isSecureStoreReference(key)) {
            continue;
          }
          keys[id] = (messageId: messageId, reference: reference, key: key);
        }
      }
      final snapshot = GroupMediaKeySnapshot._(db, Map.unmodifiable(keys));
      try {
        return await action(snapshot);
      } finally {
        snapshot._active = false;
      }
    });
  }
}
