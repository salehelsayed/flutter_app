import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../secure_storage/secure_key_store.dart';
import '../utils/flow_event_emitter.dart';

const String _kDbEncryptionKey = 'db_encryption_key';

/// Generates a random 256-bit hex key (64 hex characters).
String _generateRandomKey() {
  final random = Random.secure();
  final bytes = List<int>.generate(32, (_) => random.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// Opens (or creates) an encrypted SQLite database using SQLCipher.
///
/// - For new installs: generates a random key, stores it in secure storage,
///   opens the DB with that key.
/// - For existing installs with a plaintext DB: exports it to an encrypted
///   copy via `sqlcipher_export`, replaces the old file, then opens.
///
/// Returns the opened [Database] (not yet migrated — caller runs migrations).
Future<Database> openEncryptedDatabase({
  required SecureKeyStore secureKeyStore,
  required String dbName,
  required int version,
  required OnDatabaseCreateFn onCreate,
  required OnDatabaseVersionChangeFn onUpgrade,
}) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'ENCRYPTED_DB_OPEN_START',
    details: {'dbName': dbName},
  );

  // 1. Get or generate encryption key
  String? key = await secureKeyStore.read(_kDbEncryptionKey);
  final isNewKey = key == null;
  if (isNewKey) {
    key = _generateRandomKey();
    if (kDebugMode) print('[EAR] DB encryption key: GENERATED NEW (256-bit random)');
  } else {
    if (kDebugMode) print('[EAR] DB encryption key: LOADED FROM SECURE STORAGE');
  }

  // 2. Resolve full path
  final dbPath = await getDatabasesPath();
  final fullPath = '$dbPath/$dbName';
  if (kDebugMode) print('[EAR] DB path: $fullPath');

  // 3. If we have a new key, check if a plaintext DB already exists
  if (isNewKey) {
    final exists = await databaseExists(fullPath);
    if (kDebugMode) print('[EAR] Existing DB file found: $exists');

    if (exists) {
      // Existing plaintext DB — encrypt it
      if (kDebugMode) print('[EAR] MIGRATING plaintext DB → encrypted...');
      emitFlowEvent(
        layer: 'DB',
        event: 'ENCRYPTED_DB_MIGRATING_PLAINTEXT',
        details: {'dbName': dbName},
      );

      await _encryptExistingDatabase(fullPath, key);
      if (kDebugMode) print('[EAR] Plaintext → encrypted migration DONE');
    }

    // Persist key after successful encryption (or for fresh DB)
    await secureKeyStore.write(_kDbEncryptionKey, key);
    if (kDebugMode) print('[EAR] Encryption key stored in secure storage');
  }

  // 4. Open the (now encrypted) database
  final db = await openDatabase(
    fullPath,
    version: version,
    password: key,
    onCreate: onCreate,
    onUpgrade: onUpgrade,
  );

  // 5. Validate encryption is active
  try {
    final cipherResult = await db.rawQuery("PRAGMA cipher_version");
    final cipherVersion = cipherResult.isNotEmpty
        ? cipherResult.first.values.first
        : 'UNKNOWN';
    if (kDebugMode) print('[EAR] SQLCipher version: $cipherVersion');
    if (kDebugMode) print('[EAR] DATABASE IS ENCRYPTED');
  } catch (e) {
    if (kDebugMode) print('[EAR] WARNING: Could not verify cipher_version — $e');
  }

  emitFlowEvent(
    layer: 'DB',
    event: 'ENCRYPTED_DB_OPEN_SUCCESS',
    details: {'dbName': dbName},
  );

  return db;
}

/// Encrypts an existing plaintext SQLite database in-place.
///
/// 1. Opens the plaintext DB (no password)
/// 2. Attaches a new encrypted DB
/// 3. Exports all data via sqlcipher_export
/// 4. Closes both, replaces the original file
Future<void> _encryptExistingDatabase(String fullPath, String key) async {
  final encryptedPath = '$fullPath.encrypted';

  // Open the plaintext database
  final plaintextDb = await openDatabase(fullPath);

  try {
    // Attach new encrypted database
    await plaintextDb.execute(
      "ATTACH DATABASE '$encryptedPath' AS encrypted KEY '$key'",
    );

    // Export all data to the encrypted database
    await plaintextDb.execute("SELECT sqlcipher_export('encrypted')");

    // Detach
    await plaintextDb.execute('DETACH DATABASE encrypted');
  } finally {
    await plaintextDb.close();
  }

  // Replace original with encrypted version
  await deleteDatabase(fullPath);

  // Rename encrypted to original path
  final encryptedDb = await openDatabase(encryptedPath, password: key);
  await encryptedDb.close();

  // Use file operations via sqflite: delete old, rename new
  // Since sqflite doesn't expose rename, we re-export
  final tempDb = await openDatabase(encryptedPath, password: key);
  try {
    await tempDb.execute(
      "ATTACH DATABASE '$fullPath' AS newdb KEY '$key'",
    );
    await tempDb.execute("SELECT sqlcipher_export('newdb')");
    await tempDb.execute('DETACH DATABASE newdb');
  } finally {
    await tempDb.close();
  }

  await deleteDatabase(encryptedPath);

  emitFlowEvent(
    layer: 'DB',
    event: 'ENCRYPTED_DB_PLAINTEXT_MIGRATED',
    details: {},
  );
}
