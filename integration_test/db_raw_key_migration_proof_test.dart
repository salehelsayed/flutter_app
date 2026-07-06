import 'dart:io';

import 'package:flutter_app/core/database/encrypted_db_opener.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/push/application/background_message_handler.dart'
    show openBackgroundIdentityDbReadTolerant;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;

/// 218 — SQLCipher raw-key mode device proof suite.
///
/// Cipher is DEVICE-ONLY (host FFI has no cipher). Run on a real device:
///   flutter test integration_test/db_raw_key_migration_proof_test.dart \
///     -d 21071FDF600CSC                 # Pixel 6
///   flutter clean && flutter test integration_test/db_raw_key_migration_proof_test.dart \
///     -d IPHONE_DEVICE_ID               # iOS build needs `flutter clean`
///
/// Slices are authored just-in-time per the plan (§C1). SC-8 is the
/// self-contained feasibility GATE — it inlines the mechanism (zero prod dep)
/// and gates every production edit: PASS == GO, FAIL == STOP-and-re-diagnose.
/// SC-R / SC-B are the Phase A (read-tolerant floor) proofs; each is
/// mutation-verified by reverting the raw-try branch (→ RED).

/// Two full-entropy 256-bit keys rendered as 64 hex chars — the exact shape
/// identity.db stores (`_generateRandomKey`, encrypted_db_opener.dart:12).
const String _hexKey =
    'a1b2c3d4e5f6071829304152637485960f1e2d3c4b5a69788796a5b4c3d2e1f0';
const String _hexKey2 =
    '00112233445566778899aabbccddeeff102030405060708090a0b0c0d0e0f000';

/// The SQLCipher raw-key literal form — a 67-char blob literal `x'<64hex>'`
/// that SQLCipher's core recognizes as a pre-derived key (PBKDF2 skipped),
/// NOT a passphrase (§H1/§H3).
String _rawLiteral(String hex) => "x'$hex'";

int _median(List<int> xs) {
  final sorted = [...xs]..sort();
  return sorted[sorted.length ~/ 2];
}

/// Creates a fixture DB (raw when [openPassword] is `x'<hex>'`, passphrase when
/// it is bare hex), seeds a `probe` row, and stamps user_version=1 so the
/// production opener (version:1) runs no migration.
Future<void> _writeProbeFixture(String path, String openPassword) async {
  final db = await sqlcipher.openDatabase(
    path,
    password: openPassword,
    singleInstance: false,
  );
  try {
    await db.execute('CREATE TABLE probe (id INTEGER PRIMARY KEY, v TEXT)');
    await db.insert('probe', {'id': 1, 'v': 'fixture-row'});
    await db.execute('PRAGMA user_version = 1');
  } finally {
    await db.close();
  }
}

/// Like [_writeProbeFixture] but shaped like identity.db (an `identity` row with
/// a `peer_id`) for the background-eligibility read (SC-B).
Future<void> _writeIdentityFixture(String path, String openPassword) async {
  final db = await sqlcipher.openDatabase(
    path,
    password: openPassword,
    singleInstance: false,
  );
  try {
    await db.execute(
      'CREATE TABLE identity (id INTEGER PRIMARY KEY, peer_id TEXT)',
    );
    await db.insert('identity', {'id': 1, 'peer_id': 'local-peer'});
    await db.execute('PRAGMA user_version = 1');
  } finally {
    await db.close();
  }
}

class _InMemorySecureKeyStore implements SecureKeyStore {
  _InMemorySecureKeyStore(this._values);
  final Map<String, String> _values;

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<bool> containsKey(String key) async => _values.containsKey(key);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('218 SQLCipher raw-key migration proof', () {
    // -----------------------------------------------------------------------
    // SC-8 (device, PHASE 0, self-contained): the feasibility GATE.
    //   (a) raw-key open (`password:"x'<hex>'"`) round-trips data AND skips
    //       PBKDF2 → latency << passphrase open (locked SC-5 ratio raw<=pass/5).
    //   (b) the SAME 64-hex used as a PLAIN passphrase FAILS to open the raw DB
    //       (proves the file is genuinely raw-mode, not a passphrase DB that
    //        would silently no-op the speed win). §F2/§F8.
    // Per-platform mechanism divergence (Android execSQL vs iOS FMDB) is a
    // first-class outcome — the printed latency line documents which platform.
    // -----------------------------------------------------------------------
    testWidgets(
      'SC-8 raw-key open skips PBKDF2 and round-trips; passphrase-of-literal '
      'fails',
      (_) async {
        final tempDir = await Directory.systemTemp.createTemp('db218_sc8_');
        try {
          // --- (a) create a raw-key DB, seed the "node private key" row ---
          final rawPath = p.join(tempDir.path, 'raw_identity.db');
          final rawDb = await sqlcipher.openDatabase(
            rawPath,
            password: _rawLiteral(_hexKey), // RAW_KEY
            singleInstance: false,
          );
          await rawDb.execute(
            'CREATE TABLE identity (id INTEGER PRIMARY KEY, private_key TEXT)',
          );
          await rawDb.insert('identity', {
            'id': 1,
            'private_key': 'node-private-key-material',
          });
          await rawDb.close();

          // round-trip: reopen raw, read the row back
          final rawReopen = await sqlcipher.openDatabase(
            rawPath,
            password: _rawLiteral(_hexKey), // RAW_KEY
            singleInstance: false,
          );
          final rows = await rawReopen.query('identity');
          expect(
            rows.single['private_key'],
            'node-private-key-material',
            reason: 'raw-key DB must round-trip its rows',
          );
          await rawReopen.close();

          // --- (b) SC-8(b): the SAME 64-hex as a PLAIN passphrase must FAIL ---
          // A passphrase DB derives a DIFFERENT key via PBKDF2, so opening the
          // raw file with `password: <hex>` (no x'...') reads as "file is not a
          // database" / HMAC failure. This is the no-op discriminator (§F2).
          await expectLater(
            () async {
              final wrong = await sqlcipher.openDatabase(
                rawPath,
                password: _hexKey, // plain passphrase of the same hex → FAIL
                singleInstance: false,
              );
              try {
                await wrong.query('identity');
              } finally {
                await wrong.close();
              }
            }(),
            throwsA(anything),
            reason: 'passphrase-of-the-literal must NOT open a raw-mode DB',
          );

          // --- latency: raw open << passphrase open (PBKDF2 skipped) ---
          final passPath = p.join(tempDir.path, 'pass_identity.db');
          final seedPass = await sqlcipher.openDatabase(
            passPath,
            password: _hexKey, // passphrase mode (SC-8 latency control)
            singleInstance: false,
          );
          await seedPass.execute(
            'CREATE TABLE identity (id INTEGER PRIMARY KEY)',
          );
          await seedPass.close();

          const samples = 5;
          final passSamples = <int>[];
          final rawSamples = <int>[];
          for (var i = 0; i < samples; i++) {
            // close between opens to force COLD key derivation each time
            final swPass = Stopwatch()..start();
            final dPass = await sqlcipher.openDatabase(
              passPath,
              password: _hexKey,
              singleInstance: false,
            );
            await dPass.rawQuery('SELECT count(*) FROM sqlite_master');
            swPass.stop();
            await dPass.close();
            passSamples.add(swPass.elapsedMilliseconds);

            final swRaw = Stopwatch()..start();
            final dRaw = await sqlcipher.openDatabase(
              rawPath,
              password: _rawLiteral(_hexKey),
              singleInstance: false,
            );
            await dRaw.rawQuery('SELECT count(*) FROM sqlite_master');
            swRaw.stop();
            await dRaw.close();
            rawSamples.add(swRaw.elapsedMilliseconds);
          }
          final passP50 = _median(passSamples);
          final rawP50 = _median(rawSamples);
          // ignore: avoid_print
          print(
            'SC-8 latency platform=${Platform.operatingSystem} '
            'passphrase_p50=${passP50}ms raw_p50=${rawP50}ms '
            'passSamples=$passSamples rawSamples=$rawSamples',
          );

          // Feasibility signal == the locked SC-5 ratio: raw must skip PBKDF2.
          expect(
            rawP50 * 5 <= passP50,
            isTrue,
            reason:
                'SC-8 GATE: raw_p50=${rawP50}ms must be <= passphrase_p50/5='
                '${passP50 / 5}ms — PBKDF2 must be skipped by the raw literal. '
                'If this FAILS the mechanism is unsound → STOP-and-re-diagnose.',
          );
        } finally {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        }
      },
    );

    // -----------------------------------------------------------------------
    // SC-R (device, PHASE A): the REAL read-tolerant opener
    // (`openEncryptedDatabase`) SUCCEEDS on BOTH a legacy passphrase DB and a
    // raw DB; a *passphrase-only* open of a raw DB FAILS. Proves the
    // rollback-read path (a Phase-A floor reads a raw DB) AND documents the
    // one-way boundary. Mutation: drop the raw-try branch → (b) RED.
    // -----------------------------------------------------------------------
    testWidgets(
      'SC-R read-tolerant opener reads passphrase AND raw DBs; passphrase-only '
      'open of a raw DB fails',
      (_) async {
        final dbDir = await sqlcipher.getDatabasesPath();
        const passName = 'sc_r_pass_fixture.db';
        const rawName = 'sc_r_raw_fixture.db';
        final passFull = p.join(dbDir, passName);
        final rawFull = p.join(dbDir, rawName);
        await sqlcipher.deleteDatabase(passFull);
        await sqlcipher.deleteDatabase(rawFull);
        try {
          await _writeProbeFixture(passFull, _hexKey); // passphrase mode
          await _writeProbeFixture(rawFull, _rawLiteral(_hexKey2)); // raw mode

          // (a) legacy passphrase DB → raw-try fails, passphrase fallback opens
          final passDb = await openEncryptedDatabase(
            secureKeyStore: _InMemorySecureKeyStore({
              'db_encryption_key': _hexKey,
            }),
            dbName: passName,
            version: 1,
            onCreate: (db, v) async {},
            onUpgrade: (db, o, n) async {},
          );
          expect(
            (await passDb.query('probe')).single['v'],
            'fixture-row',
            reason: 'read-tolerant opener must read a legacy passphrase DB',
          );
          await passDb.close();

          // (b) raw DB → raw-try succeeds (the rollback-read path)
          final rawDb = await openEncryptedDatabase(
            secureKeyStore: _InMemorySecureKeyStore({
              'db_encryption_key': _hexKey2,
            }),
            dbName: rawName,
            version: 1,
            onCreate: (db, v) async {},
            onUpgrade: (db, o, n) async {},
          );
          expect(
            (await rawDb.query('probe')).single['v'],
            'fixture-row',
            reason:
                'read-tolerant opener must read a raw-key DB (rollback-read path)',
          );
          await rawDb.close();

          // (c) one-way boundary: a passphrase-ONLY open of the raw DB FAILS —
          // a pre-floor, passphrase-only reader cannot read a rekeyed DB.
          await expectLater(
            () async {
              final wrong = await sqlcipher.openDatabase(
                rawFull,
                password: _hexKey2, // plain passphrase → must FAIL on raw DB
                singleInstance: false,
              );
              try {
                await wrong.query('probe');
              } finally {
                await wrong.close();
              }
            }(),
            throwsA(anything),
            reason: 'a passphrase-only reader must NOT open a raw DB',
          );
        } finally {
          await sqlcipher.deleteDatabase(passFull);
          await sqlcipher.deleteDatabase(rawFull);
        }
      },
    );

    // -----------------------------------------------------------------------
    // SC-B (device, PHASE A): the background 5th-site helper
    // (`openBackgroundIdentityDbReadTolerant`) opens a raw-keyed identity.db and
    // returns rows (no `background_local_state_unavailable`), and still reads a
    // legacy passphrase identity.db. Mutation: revert the raw-try → raw RED.
    // -----------------------------------------------------------------------
    testWidgets(
      'SC-B background 5th-site helper reads raw AND passphrase identity.db',
      (_) async {
        final dbDir = await sqlcipher.getDatabasesPath();
        final rawFull = p.join(dbDir, 'sc_b_raw_identity.db');
        final passFull = p.join(dbDir, 'sc_b_pass_identity.db');
        await sqlcipher.deleteDatabase(rawFull);
        await sqlcipher.deleteDatabase(passFull);
        try {
          await _writeIdentityFixture(rawFull, _rawLiteral(_hexKey2)); // raw
          await _writeIdentityFixture(passFull, _hexKey); // passphrase

          final rawDb = await openBackgroundIdentityDbReadTolerant(
            path: rawFull,
            key: _hexKey2,
          );
          expect(
            (await rawDb.query('identity')).single['peer_id'],
            'local-peer',
            reason:
                'bg 5th site must read a raw identity.db (SC-B) — no '
                'background_local_state_unavailable post-rekey',
          );
          await rawDb.close();

          final passDb = await openBackgroundIdentityDbReadTolerant(
            path: passFull,
            key: _hexKey,
          );
          expect(
            (await passDb.query('identity')).single['peer_id'],
            'local-peer',
            reason: 'bg 5th site must still read a legacy passphrase identity.db',
          );
          await passDb.close();
        } finally {
          await sqlcipher.deleteDatabase(rawFull);
          await sqlcipher.deleteDatabase(passFull);
        }
      },
    );
  });
}
