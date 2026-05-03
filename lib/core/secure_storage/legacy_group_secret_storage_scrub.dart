import 'package:sqflite_sqlcipher/sqflite.dart';

import '../utils/flow_event_emitter.dart';
import 'secret_storage_references.dart';
import 'secure_key_store.dart';

Future<void> scrubLegacyGroupSecretsToSecureStorage({
  required Database db,
  required SecureKeyStore secureKeyStore,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_SECRET_STORAGE_SCRUB_START',
    details: {},
  );

  final mediaCount = await _scrubLegacyMediaKeys(
    db: db,
    secureKeyStore: secureKeyStore,
  );
  final groupKeyCount = await _scrubLegacyGroupKeys(
    db: db,
    secureKeyStore: secureKeyStore,
  );

  emitFlowEvent(
    layer: 'FL',
    event: 'GROUP_SECRET_STORAGE_SCRUB_SUCCESS',
    details: {'mediaRowsMoved': mediaCount, 'groupRowsMoved': groupKeyCount},
  );
}

Future<int> _scrubLegacyMediaKeys({
  required Database db,
  required SecureKeyStore secureKeyStore,
}) async {
  if (!await _tableExists(db, 'media_attachments')) {
    return 0;
  }

  final rows = await db.query(
    'media_attachments',
    columns: ['id', 'encryption_key_base64'],
    where: "encryption_key_base64 IS NOT NULL AND encryption_key_base64 != ''",
  );

  var migrated = 0;
  for (final row in rows) {
    final id = row['id'] as String?;
    final legacyKey = row['encryption_key_base64'] as String?;
    if (id == null ||
        legacyKey == null ||
        legacyKey.isEmpty ||
        isSecureStoreReference(legacyKey)) {
      continue;
    }

    final secureStoreKey = mediaAttachmentEncryptionKeyStoreName(id);
    await secureKeyStore.write(secureStoreKey, legacyKey);
    await db.update(
      'media_attachments',
      {'encryption_key_base64': secureStoreReferenceForKey(secureStoreKey)},
      where: 'id = ?',
      whereArgs: [id],
    );
    migrated++;
  }

  return migrated;
}

Future<int> _scrubLegacyGroupKeys({
  required Database db,
  required SecureKeyStore secureKeyStore,
}) async {
  if (!await _tableExists(db, 'group_keys')) {
    return 0;
  }

  final rows = await db.query(
    'group_keys',
    columns: ['group_id', 'key_generation', 'encrypted_key'],
    where: "encrypted_key IS NOT NULL AND encrypted_key != ''",
  );

  var migrated = 0;
  for (final row in rows) {
    final groupId = row['group_id'] as String?;
    final keyGeneration = row['key_generation'] as int?;
    final legacyKey = row['encrypted_key'] as String?;
    if (groupId == null ||
        keyGeneration == null ||
        legacyKey == null ||
        legacyKey.isEmpty ||
        isSecureStoreReference(legacyKey)) {
      continue;
    }

    final secureStoreKey = groupKeyMaterialStoreName(groupId, keyGeneration);
    await secureKeyStore.write(secureStoreKey, legacyKey);
    await db.update(
      'group_keys',
      {'encrypted_key': secureStoreReferenceForKey(secureStoreKey)},
      where: 'group_id = ? AND key_generation = ?',
      whereArgs: [groupId, keyGeneration],
    );
    migrated++;
  }

  return migrated;
}

Future<bool> _tableExists(Database db, String tableName) async {
  final rows = await db.query(
    'sqlite_master',
    columns: ['name'],
    where: "type = 'table' AND name = ?",
    whereArgs: [tableName],
    limit: 1,
  );
  return rows.isNotEmpty;
}
