import 'dart:io';

import 'package:flutter_app/core/database/encrypted_db_opener.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart'
    show debugSetFlowEventSink;
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

/// Seed a legacy PASSPHRASE identity.db at [path] (user_version 95 + rows) —
/// the "existing user" state Phase B must rekey.
Future<void> _seedLegacyPassphraseDb(String path, String hexKey) async {
  await sqlcipher.deleteDatabase(path);
  await _deleteRekeyArtifacts(path);
  final db = await sqlcipher.openDatabase(
    path,
    password: hexKey, // passphrase mode (legacy)
    singleInstance: false,
  );
  try {
    await db.execute(
      'CREATE TABLE identity (id INTEGER PRIMARY KEY, peer_id TEXT)',
    );
    await db.execute('CREATE TABLE messages (id TEXT PRIMARY KEY, body TEXT)');
    await db.insert('identity', {'id': 1, 'peer_id': 'legacy-peer'});
    for (var i = 0; i < 20; i++) {
      await db.insert('messages', {'id': 'm$i', 'body': 'msg-$i'});
    }
    await db.execute('PRAGMA user_version = 95');
  } finally {
    await db.close();
  }
}

Future<void> _deleteRekeyArtifacts(String fullPath) async {
  for (final base in ['$fullPath.pre-raw.bak', '$fullPath.rekey-tmp']) {
    for (final s in ['', '-wal', '-shm', '-journal']) {
      final f = File('$base$s');
      if (await f.exists()) await f.delete();
    }
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

    // -----------------------------------------------------------------------
    // SC-1 (device, PHASE B/4a): a fresh install creates identity.db in RAW-key
    // mode and persists marker=raw. No-op discriminator (§F2): the created
    // on-disk file opens RAW but FAILS to open with the 64-hex as a plain
    // passphrase — proving the create path really wrote raw mode (not a
    // passphrase DB that would silently no-op the speed win).
    // -----------------------------------------------------------------------
    testWidgets('SC-1 fresh install creates raw identity.db + marker=raw; '
        'passphrase-of-the-key fails on the created file', (_) async {
      final dbDir = await sqlcipher.getDatabasesPath();
      const dbName = 'sc_1_fresh.db';
      final fullPath = p.join(dbDir, dbName);
      await sqlcipher.deleteDatabase(fullPath);
      final store = _InMemorySecureKeyStore({}); // empty → fresh install
      try {
        final db = await openEncryptedDatabase(
          secureKeyStore: store,
          dbName: dbName,
          version: 1,
          onCreate: (db, v) async {
            await db.execute(
              'CREATE TABLE identity (id INTEGER PRIMARY KEY, v TEXT)',
            );
            await db.insert('identity', {'id': 1, 'v': 'fresh'});
          },
          onUpgrade: (db, o, n) async {},
        );
        expect((await db.query('identity')).single['v'], 'fresh');
        await db.close();

        // marker persisted as raw:<64hex>
        final stored = await store.read('db_encryption_key');
        expect(stored, isNotNull);
        expect(
          stored!.startsWith('raw:'),
          isTrue,
          reason: 'fresh install must persist cipher-mode marker=raw',
        );
        final hex = stored.substring('raw:'.length);
        expect(hex.length, 64);

        // §F2 discriminator: opens RAW, does NOT open as a plain passphrase.
        final rawOpen = await sqlcipher.openDatabase(
          fullPath,
          password: "x'$hex'", // RAW_KEY
          singleInstance: false,
        );
        expect((await rawOpen.query('identity')).single['v'], 'fresh');
        await rawOpen.close();
        await expectLater(
          () async {
            final wrong = await sqlcipher.openDatabase(
              fullPath,
              password: hex, // plain passphrase of the same hex → must FAIL
              singleInstance: false,
            );
            try {
              await wrong.query('identity');
            } finally {
              await wrong.close();
            }
          }(),
          throwsA(anything),
          reason: 'a freshly created raw DB must NOT open as a passphrase DB',
        );
      } finally {
        await sqlcipher.deleteDatabase(fullPath);
      }
    });

    // -----------------------------------------------------------------------
    // SC-4 (device, PHASE B/4a): the marker survives a real restart (fresh
    // opener re-reads the persisted record) and the 2nd launch opens raw
    // DIRECTLY — no rekey, no read-only probe/fallback, no marker re-write.
    // -----------------------------------------------------------------------
    testWidgets('SC-4 marker durable; 2nd launch opens raw directly with no '
        'rekey/probe', (_) async {
      final dbDir = await sqlcipher.getDatabasesPath();
      const dbName = 'sc_4_durable.db';
      final fullPath = p.join(dbDir, dbName);
      await sqlcipher.deleteDatabase(fullPath);
      final store = _InMemorySecureKeyStore({});
      final events = <String>[];
      debugSetFlowEventSink((payload) {
        final name = payload['event'];
        if (name is String) events.add(name);
      });
      try {
        // 1st launch — creates raw + persists marker
        final db1 = await openEncryptedDatabase(
          secureKeyStore: store,
          dbName: dbName,
          version: 1,
          onCreate: (db, v) async {
            await db.execute('CREATE TABLE t (id INTEGER PRIMARY KEY)');
          },
          onUpgrade: (db, o, n) async {},
        );
        await db1.close();
        expect(
          (await store.read('db_encryption_key'))!.startsWith('raw:'),
          isTrue,
        );

        // 2nd launch — a fresh opener reads the persisted marker (real restart).
        events.clear();
        final db2 = await openEncryptedDatabase(
          secureKeyStore: store,
          dbName: dbName,
          version: 1,
          onCreate: (db, v) async {},
          onUpgrade: (db, o, n) async {},
        );
        await db2.close();

        expect(events, contains('ENCRYPTED_DB_OPEN_SUCCESS'));
        expect(
          events,
          isNot(contains('DB_REKEY_TO_RAW_KEY')),
          reason: 'a marked raw DB must not rekey on the steady launch',
        );
        expect(
          events,
          isNot(contains('ENCRYPTED_DB_RAW_OPEN_FALLBACK')),
          reason: '(raw, exists) must open raw DIRECTLY — no probe/fallback',
        );
        expect(
          events,
          isNot(contains('ENCRYPTED_DB_CIPHER_MARKER_RAW')),
          reason: 'marker already raw — no re-write on the steady launch',
        );
      } finally {
        debugSetFlowEventSink(null);
        await sqlcipher.deleteDatabase(fullPath);
      }
    });

    // -----------------------------------------------------------------------
    // SC-2 (device, PHASE B/4b): a legacy passphrase DB rekeys to raw with FULL
    // preservation — user_version==95 (§E1), all rows across tables, marker
    // flips to raw, opens raw but NOT as a passphrase of the same hex (§F2),
    // and no leftover .bak/.rekey-tmp artifacts remain.
    // -----------------------------------------------------------------------
    testWidgets('SC-2 legacy passphrase DB rekeys to raw; user_version==95 + '
        'rows preserved', (_) async {
      final dbDir = await sqlcipher.getDatabasesPath();
      const dbName = 'sc_2_rekey.db';
      final fullPath = p.join(dbDir, dbName);
      await _seedLegacyPassphraseDb(fullPath, _hexKey);
      // stored key = bare hex (absent marker == legacy passphrase)
      final store = _InMemorySecureKeyStore({'db_encryption_key': _hexKey});
      try {
        final db = await openEncryptedDatabase(
          secureKeyStore: store,
          dbName: dbName,
          version: 95,
          onCreate: (db, v) async {},
          onUpgrade: (db, o, n) async {},
        );
        expect((await db.query('identity')).single['peer_id'], 'legacy-peer');
        expect((await db.query('messages')).length, 20);
        expect(
          (await db.rawQuery('PRAGMA user_version')).first.values.first,
          95,
          reason: 'user_version must be preserved through the rekey (§E1)',
        );
        await db.close();

        // marker flipped to raw
        expect(
          (await store.read('db_encryption_key'))!.startsWith('raw:'),
          isTrue,
          reason: 'rekey must persist marker=raw',
        );

        // §F2: opens raw, NOT as a plain passphrase of the same hex.
        final rawOpen = await sqlcipher.openDatabase(
          fullPath,
          password: "x'$_hexKey'", // RAW_KEY
          singleInstance: false,
        );
        expect((await rawOpen.query('messages')).length, 20);
        await rawOpen.close();
        await expectLater(
          () async {
            final w = await sqlcipher.openDatabase(
              fullPath,
              password: _hexKey, // passphrase of the same hex → must FAIL
              singleInstance: false,
            );
            try {
              await w.query('identity');
            } finally {
              await w.close();
            }
          }(),
          throwsA(anything),
          reason: 'a rekeyed DB must NOT open as a passphrase DB',
        );

        // no leftover rekey artifacts
        expect(await File('$fullPath.pre-raw.bak').exists(), isFalse);
        expect(await File('$fullPath.rekey-tmp').exists(), isFalse);
      } finally {
        await sqlcipher.deleteDatabase(fullPath);
        await _deleteRekeyArtifacts(fullPath);
      }
    });

    // -----------------------------------------------------------------------
    // SC-3 (device, PHASE B/4b): the rekey is ATOMIC. A @visibleForTesting fault
    // injector throws at the swap boundary so the interrupted-rename branches
    // are driven deterministically. In every case the next open recovers an
    // OPENABLE DB with data intact — never a brick (§E2/§F4).
    // -----------------------------------------------------------------------
    testWidgets('SC-3 rekey atomic — interrupted swap recovers an openable DB, '
        'data preserved', (_) async {
      final dbDir = await sqlcipher.getDatabasesPath();
      const dbName = 'sc_3_atomic.db';
      final fullPath = p.join(dbDir, dbName);

      Future<sqlcipher.Database> openOnce() => openEncryptedDatabase(
            secureKeyStore: _InMemorySecureKeyStore({
              'db_encryption_key': _hexKey,
            }),
            dbName: dbName,
            version: 95,
            onCreate: (db, v) async {},
            onUpgrade: (db, o, n) async {},
          );

      try {
        // (a) fault AFTER backup (original→.bak done, tmp not yet swapped in →
        //     main missing): recovery restores the passphrase original.
        await _seedLegacyPassphraseDb(fullPath, _hexKey);
        debugRekeyFaultInjector = (stage) {
          if (stage == 'afterBackup') throw StateError('inject-afterBackup');
        };
        final dbA = await openOnce();
        expect(
          (await dbA.query('identity')).single['peer_id'],
          'legacy-peer',
          reason: 'afterBackup interruption must restore the original, intact',
        );
        expect((await dbA.query('messages')).length, 20);
        await dbA.close();

        // (b) fault AFTER swap (main = raw, .bak present): recovery finishes the
        //     cleanup and the DB opens raw with data intact.
        await _seedLegacyPassphraseDb(fullPath, _hexKey);
        debugRekeyFaultInjector = (stage) {
          if (stage == 'afterSwap') throw StateError('inject-afterSwap');
        };
        final dbB = await openOnce();
        expect(
          (await dbB.query('identity')).single['peer_id'],
          'legacy-peer',
          reason: 'afterSwap interruption must leave an openable raw DB, intact',
        );
        await dbB.close();
        final rawOpen = await sqlcipher.openDatabase(
          fullPath,
          password: "x'$_hexKey'", // RAW_KEY
          singleInstance: false,
        );
        expect((await rawOpen.query('messages')).length, 20);
        await rawOpen.close();

        // (c) no fault → clean rekey, no leftover artifacts.
        await _seedLegacyPassphraseDb(fullPath, _hexKey);
        debugRekeyFaultInjector = null;
        final dbC = await openOnce();
        expect((await dbC.query('identity')).single['peer_id'], 'legacy-peer');
        await dbC.close();
        expect(await File('$fullPath.pre-raw.bak').exists(), isFalse);
        expect(await File('$fullPath.rekey-tmp').exists(), isFalse);
      } finally {
        debugRekeyFaultInjector = null;
        await sqlcipher.deleteDatabase(fullPath);
        await _deleteRekeyArtifacts(fullPath);
      }
    });

    // -----------------------------------------------------------------------
    // SC-9 (device, PHASE B/4b): a pre-encryption PLAINTEXT identity.db migrates
    // DIRECTLY to raw-key (one export, not plaintext→passphrase→raw), preserving
    // user_version==95 and all rows. Opens raw; no longer opens as plaintext.
    // -----------------------------------------------------------------------
    testWidgets('SC-9 pre-encryption plaintext DB migrates directly to raw; '
        'user_version + rows preserved', (_) async {
      final dbDir = await sqlcipher.getDatabasesPath();
      const dbName = 'sc_9_plaintext.db';
      final fullPath = p.join(dbDir, dbName);
      await sqlcipher.deleteDatabase(fullPath);
      await _deleteRekeyArtifacts(fullPath);
      // Seed a PLAINTEXT DB (no password) with user_version 95 + rows.
      final seed = await sqlcipher.openDatabase(fullPath, singleInstance: false);
      await seed.execute(
        'CREATE TABLE identity (id INTEGER PRIMARY KEY, peer_id TEXT)',
      );
      await seed.insert('identity', {'id': 1, 'peer_id': 'plaintext-peer'});
      await seed.execute('PRAGMA user_version = 95');
      await seed.close();

      final store = _InMemorySecureKeyStore({}); // fresh key → plaintext branch
      try {
        final db = await openEncryptedDatabase(
          secureKeyStore: store,
          dbName: dbName,
          version: 95,
          onCreate: (db, v) async {},
          onUpgrade: (db, o, n) async {},
        );
        expect(
          (await db.query('identity')).single['peer_id'],
          'plaintext-peer',
        );
        expect(
          (await db.rawQuery('PRAGMA user_version')).first.values.first,
          95,
          reason: 'user_version must be preserved through plaintext→raw (§E1)',
        );
        await db.close();

        final stored = await store.read('db_encryption_key');
        expect(stored, isNotNull);
        expect(stored!.startsWith('raw:'), isTrue);
        final hex = stored.substring('raw:'.length);

        // opens raw
        final rawOpen = await sqlcipher.openDatabase(
          fullPath,
          password: "x'$hex'", // RAW_KEY
          singleInstance: false,
        );
        expect(
          (await rawOpen.query('identity')).single['peer_id'],
          'plaintext-peer',
        );
        await rawOpen.close();

        // no longer plaintext-openable
        await expectLater(
          () async {
            final w = await sqlcipher.openDatabase(
              fullPath,
              singleInstance: false,
            );
            try {
              await w.query('identity');
            } finally {
              await w.close();
            }
          }(),
          throwsA(anything),
          reason: 'the migrated DB must no longer open as plaintext',
        );
        expect(await File('$fullPath.pre-raw.bak').exists(), isFalse);
      } finally {
        await sqlcipher.deleteDatabase(fullPath);
        await _deleteRekeyArtifacts(fullPath);
      }
    });
  });
}
