import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../secure_storage/secure_key_store.dart';
import '../utils/flow_event_emitter.dart';

const String _kDbEncryptionKey = 'db_encryption_key';

/// 218 Phase B — the cipher-mode marker is a PREFIX on the `db_encryption_key`
/// record, domain {absent, raw} (§G1/SC-6):
///  - a bare `<hex>` == `absent` == legacy passphrase mode, not yet rekeyed
///    (this is exactly the pre-218 write format, so existing records need no
///    migration);
///  - `raw:<hex>` == the DB is raw-key mode.
/// There is deliberately NO `pass:` value — `(pass,*)` states do not exist.
@visibleForTesting
const String kRawKeyMarkerPrefix = 'raw:';

@visibleForTesting
enum CipherKeyMode { absent, raw }

@visibleForTesting
class CipherKeyRecord {
  const CipherKeyRecord(this.mode, this.hex);
  final CipherKeyMode mode;
  final String hex;
}

/// Parse a stored `db_encryption_key` value into (mode, hex).
@visibleForTesting
CipherKeyRecord parseCipherKeyRecord(String stored) {
  if (stored.startsWith(kRawKeyMarkerPrefix)) {
    return CipherKeyRecord(
      CipherKeyMode.raw,
      stored.substring(kRawKeyMarkerPrefix.length),
    );
  }
  return CipherKeyRecord(CipherKeyMode.absent, stored);
}

/// Format a (mode, hex) pair back into the stored record string.
@visibleForTesting
String formatCipherKeyRecord(CipherKeyMode mode, String hex) =>
    mode == CipherKeyMode.raw ? '$kRawKeyMarkerPrefix$hex' : hex;

/// A full-entropy key is exactly 64 hex chars (256 bits). A stored value that
/// isn't (after stripping the marker) is a FAILING signal, never a silent
/// passphrase-fallback (§I2).
@visibleForTesting
bool isValid256BitHexKey(String hex) =>
    hex.length == 64 && RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(hex);

@visibleForTesting
enum CipherOpenAction { openRaw, createRaw, rekeyToRaw }

/// §G2 decision table over (marker mode, on-disk DB file exists):
///   (raw,    T) -> openRaw       (2nd steady launch — the SC-5 fast path)
///   (raw,    F) -> createRaw     (reinstall; key survived in the keystore)
///   (absent, T) -> rekeyToRaw    (legacy passphrase DB — migrate once)
///   (absent, F) -> createRaw     (fresh install)
@visibleForTesting
CipherOpenAction decideCipherOpenAction({
  required CipherKeyMode mode,
  required bool dbFileExists,
}) {
  switch (mode) {
    case CipherKeyMode.raw:
      return dbFileExists
          ? CipherOpenAction.openRaw
          : CipherOpenAction.createRaw;
    case CipherKeyMode.absent:
      return dbFileExists
          ? CipherOpenAction.rekeyToRaw
          : CipherOpenAction.createRaw;
  }
}

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

  // 1. Load the stored key record + its cipher-mode marker (§G1). A bare hex
  //    value is the legacy `absent` (passphrase) state; `raw:<hex>` is raw mode.
  final storedValue = await secureKeyStore.read(_kDbEncryptionKey);
  final isNewKey = storedValue == null;
  final String key;
  var mode = CipherKeyMode.absent;
  if (isNewKey) {
    key = _generateRandomKey();
    if (kDebugMode) {
      print('[EAR] DB encryption key: GENERATED NEW (256-bit random)');
    }
  } else {
    final record = parseCipherKeyRecord(storedValue);
    key = record.hex;
    mode = record.mode;
    if (!isValid256BitHexKey(key)) {
      // §I2 — a malformed stored key is a FAILING signal, never a silent
      // passphrase-fallback that could mask a corrupted/attacker-substituted
      // record.
      emitFlowEvent(
        layer: 'DB',
        event: 'ENCRYPTED_DB_KEY_MALFORMED',
        details: {'dbName': dbName},
      );
      throw StateError(
        'db_encryption_key is not a 64-hex key (mode=${mode.name})',
      );
    }
    if (kDebugMode) print('[EAR] DB encryption key: LOADED (mode=${mode.name})');
  }

  // 2. Resolve full path
  final dbPath = await getDatabasesPath();
  final fullPath = '$dbPath/$dbName';
  if (kDebugMode) print('[EAR] DB path: $fullPath');

  // 2b. Recover any interrupted rekey (leftover .rekey-tmp / .pre-raw.bak)
  //     BEFORE any existence checks so the decision below sees a consistent
  //     on-disk file (§F4).
  await _recoverInterruptedRekey(fullPath, dbName, keyPersisted: !isNewKey);

  // 3. Key persistence + legacy plaintext migration (isNewKey only).
  if (isNewKey) {
    final plaintextExists = await databaseExists(fullPath);
    if (kDebugMode) print('[EAR] Existing DB file found: $plaintextExists');
    if (plaintextExists) {
      // Legacy pre-encryption plaintext DB → migrate DIRECTLY to raw-key mode in
      // one atomic export (SC-9), NOT plaintext→passphrase→raw (which would pay
      // PBKDF2 once for nothing). Persist the raw marker so the decision below
      // takes the fast (raw, exists)→openRaw path.
      if (kDebugMode) print('[EAR] MIGRATING plaintext DB → raw-key...');
      emitFlowEvent(
        layer: 'DB',
        event: 'ENCRYPTED_DB_MIGRATING_PLAINTEXT',
        details: {'dbName': dbName},
      );
      await _exportToRawAtomic(fullPath, key, dbName, sourcePassword: null);
      await secureKeyStore.write(
        _kDbEncryptionKey,
        formatCipherKeyRecord(CipherKeyMode.raw, key),
      );
      mode = CipherKeyMode.raw;
      emitFlowEvent(
        layer: 'DB',
        event: 'ENCRYPTED_DB_PLAINTEXT_MIGRATED',
        details: {'dbName': dbName},
      );
      if (kDebugMode) print('[EAR] Plaintext → raw-key migration DONE');
    } else {
      // Fresh install → will create a RAW DB below. Persist the raw marker
      // FIRST so a crash between persist and create recovers via
      // (raw, dbAbsent)→createRaw rather than being mistaken for a plaintext DB.
      await secureKeyStore.write(
        _kDbEncryptionKey,
        formatCipherKeyRecord(CipherKeyMode.raw, key),
      );
      mode = CipherKeyMode.raw;
      if (kDebugMode) print('[EAR] Fresh install — key stored, marker=raw');
    }
  }

  // 4. Decide the open action from (marker mode, on-disk DB exists) — §G2.
  final dbFileExists = await databaseExists(fullPath);
  final action = decideCipherOpenAction(mode: mode, dbFileExists: dbFileExists);

  // 5. Resolve the open password + whether we open raw.
  //  - openRaw / createRaw → raw literal (marker authoritative; NO probe, so the
  //    2nd steady launch stays on the SC-5 fast path).
  //  - rekeyToRaw → 4a: read-tolerant passphrase open via the read-only probe
  //    (an EXISTING legacy DB opens without a rekey); the probe also self-heals
  //    a marker=absent record that already points at a raw DB (a Phase-B
  //    crash-before-marker or a rollback return). 4b replaces this branch with
  //    the atomic passphrase→raw rekey.
  String openPassword;
  bool openedRaw;
  switch (action) {
    case CipherOpenAction.openRaw:
    case CipherOpenAction.createRaw:
      openPassword = "x'$key'"; // RAW_KEY
      openedRaw = true;
      break;
    case CipherOpenAction.rekeyToRaw:
      // marker=absent + DB exists. Either a legacy PASSPHRASE DB (rekey it) or
      // already RAW (a Phase-B crash-before-marker / rollback return → self-heal
      // via the marker write in step 6). §E2/§F4.
      final alreadyRaw = await _isRawKeyDatabase(fullPath, key, dbName);
      if (alreadyRaw) {
        openPassword = "x'$key'"; // RAW_KEY
        openedRaw = true;
      } else {
        // Atomic passphrase→raw rekey. On ANY failure the original passphrase DB
        // is intact (verify-before-swap), so fall back to opening passphrase and
        // retry next launch — NEVER brick.
        try {
          await _exportToRawAtomic(fullPath, key, dbName, sourcePassword: key);
          openPassword = "x'$key'"; // RAW_KEY
          openedRaw = true;
        } catch (e) {
          emitFlowEvent(
            layer: 'DB',
            event: 'DB_REKEY_TO_RAW_KEY_ABORTED',
            details: {'dbName': dbName, 'error': e.toString()},
          );
          // The rekey may have failed BEFORE or AFTER the swap → recover any
          // interrupted swap and re-probe the actual on-disk mode. Assuming
          // passphrase would fail (and could create a fresh empty DB) if the
          // swap had already made the file raw.
          await _recoverInterruptedRekey(fullPath, dbName, keyPersisted: !isNewKey);
          final nowRaw = await _isRawKeyDatabase(fullPath, key, dbName);
          openPassword = nowRaw ? "x'$key'" : key; // RAW_KEY / LEGACY_PASSPHRASE_FALLBACK
          openedRaw = nowRaw;
        }
      }
      break;
  }

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
    // 228: DB v96 is a one-way supported release floor. Without this callback
    // the pinned sqflite_common would LOWER user_version on a downgrade open
    // even though no migration ran, letting an older model's INSERT OR REPLACE
    // silently reset newer local-state columns. Fail closed instead: a
    // requested version below the on-disk user_version throws and leaves the
    // database untouched. A manually sideloaded pre-v96 binary is unsupported
    // and requires profile reset/restore — it is never a compatible rollback.
    onDowngrade: onDatabaseVersionChangeError,
  );
  openStopwatch.stop();

  // 6. Persist the raw marker once, after a successful raw open, if not already
  //    recorded — makes the mode durable so the next launch takes the fast
  //    openRaw path (SC-4) and self-heals an absent record over a raw DB.
  if (openedRaw && mode != CipherKeyMode.raw) {
    await secureKeyStore.write(
      _kDbEncryptionKey,
      formatCipherKeyRecord(CipherKeyMode.raw, key),
    );
    emitFlowEvent(
      layer: 'DB',
      event: 'ENCRYPTED_DB_CIPHER_MARKER_RAW',
      details: {'dbName': dbName},
    );
    if (kDebugMode) print('[EAR] Cipher-mode marker persisted: raw');
  }

  // Post-commit cleanup: the key/marker is now durable, so drop the rekey
  // backup (a no-op unless a rekey/migration ran this launch). Recovery cleans
  // up any lingering .bak across launches.
  await _deleteDbAndSidecars(_preRawBakPath(fullPath));

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

String _rekeyTmpPath(String fullPath) => '$fullPath.rekey-tmp';
String _preRawBakPath(String fullPath) => '$fullPath.pre-raw.bak';

const List<String> _dbSidecarSuffixes = ['-wal', '-shm', '-journal'];

/// 218 SC-3 — deterministic fault injection for the rekey swap. Tests set this
/// to throw at a named stage ('afterExport' | 'afterVerify' | 'afterBackup' |
/// 'afterSwap') to drive the interrupted-rename branches without file surgery.
@visibleForTesting
void Function(String stage)? debugRekeyFaultInjector;

void _rekeyFaultPoint(String stage) {
  final injector = debugRekeyFaultInjector;
  if (injector != null) injector(stage);
}

Future<void> _deleteFileIfExists(String path) async {
  final f = File(path);
  if (await f.exists()) await f.delete();
}

/// Delete a DB file AND its SQLite sidecars (-wal/-shm/-journal).
Future<void> _deleteDbAndSidecars(String path) async {
  await _deleteFileIfExists(path);
  for (final s in _dbSidecarSuffixes) {
    await _deleteFileIfExists('$path$s');
  }
}

/// §F4 — restore a consistent identity.db after an interrupted rekey/migration
/// swap. Idempotent, so it is safe to run at launch AND again after an abort.
/// [keyPersisted] distinguishes the two post-swap cases: a passphrase→raw rekey
/// keeps its key throughout (persisted), so a completed swap is kept; a
/// plaintext→raw migration commits a NEW key only AFTER the swap, so a completed
/// swap whose key was never persisted is unreadable → discard the raw file and
/// restore the plaintext original to retry cleanly.
Future<void> _recoverInterruptedRekey(
  String fullPath,
  String dbName, {
  required bool keyPersisted,
}) async {
  final tmpPath = _rekeyTmpPath(fullPath);
  final bakPath = _preRawBakPath(fullPath);
  if (await File(bakPath).exists()) {
    final mainExists = await File(fullPath).exists();
    if (!mainExists) {
      // Swap interrupted between (original→.bak) and (tmp→original): the main
      // file is missing → restore the original from the backup.
      await File(bakPath).rename(fullPath);
      emitFlowEvent(
        layer: 'DB',
        event: 'DB_REKEY_RECOVERED_RESTORED_ORIGINAL',
        details: {'dbName': dbName},
      );
    } else if (keyPersisted) {
      // Swap completed and the key is committed → main (raw) is the good DB.
      await _deleteDbAndSidecars(bakPath);
      emitFlowEvent(
        layer: 'DB',
        event: 'DB_REKEY_RECOVERED_POST_SWAP',
        details: {'dbName': dbName},
      );
    } else {
      // Swap completed but the new key was NEVER persisted (interrupted
      // plaintext→raw migration): the raw main is unreadable → discard it and
      // restore the plaintext original to retry.
      await _deleteDbAndSidecars(fullPath);
      await File(bakPath).rename(fullPath);
      emitFlowEvent(
        layer: 'DB',
        event: 'DB_REKEY_RECOVERED_RESTORED_ORIGINAL',
        details: {'dbName': dbName},
      );
    }
  }
  // Always discard a partial/complete export tmp that no longer has a role.
  await _deleteDbAndSidecars(tmpPath);
}

Future<int> _readUserVersion(Database db) async {
  final r = await db.rawQuery('PRAGMA user_version');
  final v = r.isNotEmpty ? r.first.values.first : null;
  return v is int ? v : 0;
}

/// §E2 — atomic export of the identity.db at [fullPath] to raw-key mode via a
/// side file. Used for BOTH the legacy passphrase→raw rekey (`sourcePassword` =
/// the key) and the pre-encryption plaintext→raw migration (`sourcePassword` =
/// null, SC-9). Side-path export → verify (raw-open + quick_check +
/// user_version) → back up original → evict its sidecars → atomic rename tmp in
/// → (marker written by the caller). On ANY failure the error propagates and the
/// caller re-runs recovery + re-probes the on-disk mode, so a legacy identity is
/// NEVER bricked. Preserves `user_version` (§E1) — `sqlcipher_export` does not
/// copy it. §H3 raw KEY form: KEY "x'<64hex>'".
Future<void> _exportToRawAtomic(
  String fullPath,
  String key,
  String dbName, {
  required String? sourcePassword,
}) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'DB_REKEY_TO_RAW_KEY_START',
    details: {'dbName': dbName},
  );
  final tmpPath = _rekeyTmpPath(fullPath);
  final bakPath = _preRawBakPath(fullPath);
  await _deleteDbAndSidecars(tmpPath); // clear any stale tmp

  // 1. Export the source (passphrase OR plaintext) to a raw-keyed side file,
  //    preserving user_version (§E1).
  final source = sourcePassword == null
      ? await openDatabase(fullPath, singleInstance: false) // plaintext source
      : await openDatabase(
          fullPath,
          password: sourcePassword, // LEGACY_PASSPHRASE_FALLBACK
          singleInstance: false,
        );
  int userVersion;
  try {
    userVersion = await _readUserVersion(source);
    await source.execute(
      'ATTACH DATABASE \'$tmpPath\' AS rawdb KEY "x\'$key\'"',
    );
    await source.rawQuery("SELECT sqlcipher_export('rawdb')");
    await source.execute('PRAGMA rawdb.user_version = $userVersion');
    await source.execute('DETACH DATABASE rawdb');
  } finally {
    await source.close();
  }
  _rekeyFaultPoint('afterExport');

  // 2. Verify the tmp raw DB: opens raw, is intact, and kept user_version.
  final verify = await openDatabase(
    tmpPath,
    password: "x'$key'", // RAW_KEY
    singleInstance: false,
  );
  try {
    final qc = await verify.rawQuery('PRAGMA quick_check');
    final quickOk = qc.isNotEmpty &&
        qc.first.values.first.toString().toLowerCase() == 'ok';
    final tmpVersion = await _readUserVersion(verify);
    if (!quickOk || tmpVersion != userVersion) {
      throw StateError(
        'rekey verify failed (quick_check=$quickOk, '
        'version=$tmpVersion expected=$userVersion)',
      );
    }
  } finally {
    await verify.close();
  }
  _rekeyFaultPoint('afterVerify');

  // 3. Atomic swap: back up original → evict its sidecars → rename tmp in.
  await _deleteDbAndSidecars(bakPath);
  await File(fullPath).rename(bakPath);
  _rekeyFaultPoint('afterBackup');
  for (final s in _dbSidecarSuffixes) {
    await _deleteFileIfExists('$fullPath$s');
  }
  await File(tmpPath).rename(fullPath);
  _rekeyFaultPoint('afterSwap');

  // 4. Success — the backup (.bak) is RETAINED until the caller commits the
  //    key/marker (the opener deletes it at the end; recovery cleans up any
  //    lingering .bak). This preserves a restore point across the swap→key
  //    commit window for the plaintext→raw migration (its new key is persisted
  //    only after this returns).
  emitFlowEvent(
    layer: 'DB',
    event: 'DB_REKEY_TO_RAW_KEY',
    details: {'dbName': dbName, 'userVersion': userVersion},
  );
}
