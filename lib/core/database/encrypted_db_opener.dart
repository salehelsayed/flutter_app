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
    if (kDebugMode) {
      print('[EAR] DB encryption key: GENERATED NEW (256-bit random)');
    }
  } else {
    if (kDebugMode) {
      print('[EAR] DB encryption key: LOADED FROM SECURE STORAGE');
    }
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

  // 4. Open the (now encrypted) database.
  //
  // 218 Phase A — read-tolerant open via a READ-ONLY probe. An EXISTING
  // identity.db may be legacy passphrase-mode OR (post-Phase-B) raw-key mode.
  // We DETECT the mode with a throwaway read-only, singleInstance:false probe
  // that validates the raw-key literal, then do the SINGLE real open with the
  // correct key. We must NOT do a wrong-key read-WRITE open on the real path:
  // on iOS (FMDB) a failed read-write open leaves a dangling `BEGIN EXCLUSIVE`
  // that poisons the immediate passphrase re-open ("out of memory") and bricks
  // cold start — SC-R caught this on device; the read-only path (bg 5th site /
  // SC-B) was already clean. Fresh installs are created in PASSPHRASE mode here
  // ON PURPOSE — creating raw before this floor is the shipped-and-soaked
  // default would brick a rollback to a pre-floor, passphrase-only reader
  // (raw-on-create is deferred to Phase B / SC-1).
  final dbFileExists = await databaseExists(fullPath);
  final useRawKey =
      dbFileExists && await _isRawKeyDatabase(fullPath, key, dbName);
  final openPassword = useRawKey ? "x'$key'" : key;
  // 218 Step 0a — bracket ONLY the real openDatabase call (probe excluded) so
  // the passphrase baseline (denominator) and the raw-key fix (numerator) read
  // the SAME `elapsedMs` field on ENCRYPTED_DB_OPEN_SUCCESS. Mirrors
  // posts_db_helpers.dart:6-19.
  final openStopwatch = Stopwatch()..start();
  final db = await openDatabase(
    fullPath,
    version: version,
    password: openPassword, // RAW_KEY / LEGACY_PASSPHRASE_FALLBACK
    onConfigure: _configureDbBusyTimeout,
    onCreate: onCreate,
    onUpgrade: onUpgrade,
  );
  openStopwatch.stop();

  // 5. Validate encryption is active
  try {
    final cipherResult = await db.rawQuery("PRAGMA cipher_version");
    final cipherVersion = cipherResult.isNotEmpty
        ? cipherResult.first.values.first
        : 'UNKNOWN';
    if (kDebugMode) print('[EAR] SQLCipher version: $cipherVersion');
    if (kDebugMode) print('[EAR] DATABASE IS ENCRYPTED');
  } catch (e) {
    if (kDebugMode) {
      print('[EAR] WARNING: Could not verify cipher_version — $e');
    }
  }

  emitFlowEvent(
    layer: 'DB',
    event: 'ENCRYPTED_DB_OPEN_SUCCESS',
    details: {'dbName': dbName, 'elapsedMs': openStopwatch.elapsedMilliseconds},
  );

  return db;
}

/// Fail fast instead of hanging forever if the DB file is momentarily locked
/// (e.g. a prior connection/process hasn't released it yet). Without this a
/// stale lock blocks the open/first query and the app sits on the splash
/// screen indefinitely; with it the query returns SQLITE_BUSY after the
/// timeout so startup can surface an error/retry. Set in onConfigure so
/// migrations (onUpgrade) inherit it too — and shared across the read-tolerant
/// raw-try and passphrase-fallback opens (218 Phase A).
///
/// NOTE: must use rawQuery, not execute — `PRAGMA busy_timeout = N` returns the
/// new value, and Android's execSQL rejects value-returning statements
/// ("Queries can be performed using ... query or rawQuery").
Future<void> _configureDbBusyTimeout(Database db) async {
  await db.rawQuery('PRAGMA busy_timeout = 5000');
}

/// 218 Phase A — detect whether the existing DB at [fullPath] is raw-key mode
/// by validating the raw-key literal `x'<hex>'` with a throwaway READ-ONLY,
/// singleInstance:false connection. Read-only is deliberate: it avoids the
/// `BEGIN EXCLUSIVE` write transaction whose failure (wrong key) poisons the
/// immediate re-open on iOS FMDB (SC-R). A read-only open may defer decryption
/// until the first read, so we touch `sqlite_master` to force key validation.
/// The probe is always closed; any failure means "not raw" → passphrase.
Future<bool> _isRawKeyDatabase(
  String fullPath,
  String key,
  String dbName,
) async {
  Database? probe;
  try {
    probe = await openDatabase(
      fullPath,
      password: "x'$key'", // RAW_KEY
      readOnly: true,
      singleInstance: false,
    );
    await probe.rawQuery('SELECT count(*) FROM sqlite_master');
    return true;
  } catch (_) {
    emitFlowEvent(
      layer: 'DB',
      event: 'ENCRYPTED_DB_RAW_OPEN_FALLBACK',
      details: {'dbName': dbName},
    );
    return false;
  } finally {
    await probe?.close();
  }
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
    await plaintextDb.rawQuery("SELECT sqlcipher_export('encrypted')");

    // Detach
    await plaintextDb.execute('DETACH DATABASE encrypted');
  } finally {
    await plaintextDb.close();
  }

  // Replace original with encrypted version
  await deleteDatabase(fullPath);

  // Rename encrypted to original path
  final encryptedDb =
      await openDatabase(encryptedPath, password: key); // PLAINTEXT_MIGRATION
  await encryptedDb.close();

  // Use file operations via sqflite: delete old, rename new
  // Since sqflite doesn't expose rename, we re-export
  final tempDb =
      await openDatabase(encryptedPath, password: key); // PLAINTEXT_MIGRATION
  try {
    await tempDb.execute("ATTACH DATABASE '$fullPath' AS newdb KEY '$key'");
    await tempDb.rawQuery("SELECT sqlcipher_export('newdb')");
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
