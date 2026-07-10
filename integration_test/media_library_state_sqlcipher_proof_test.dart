// 228 TC-228-02D: production-SQLCipher proof for the DB v96 media library
// migration on a PHYSICAL Android/iOS device (the acceptance gate enforces
// non-emulator device selection via `flutter devices --machine`).
//
// Boundary proven here, with the REAL sqflite_sqlcipher engine and the REAL
// shared production registry callbacks (never hand-copied migration lists):
//  * non-empty `PRAGMA cipher_version` (SQLCipher is actually active);
//  * literal v95 create through the production create callback;
//  * v95 -> v96 upgrade through the production upgrade callback:
//    deterministic fail-closed owner backfill, enforced three-value CHECK,
//    byte/metadata preservation, exact indexes;
//  * explicit bookmark/playback writes persist; migration rerun is stable;
//  * close/reopen maps durable state back;
//  * a separate FRESH v96 create;
//  * wrong-password rejection (READ-ONLY probe — a failed keyed write-open
//    would poison the immediate re-open on iOS FMDB);
//  * fail-closed downgrade: a requested-v95 open of the v96 database throws
//    and leaves user_version=96 and all owner/bookmark/resume state
//    unchanged (the one-way v96 release floor).

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;

import 'package:flutter_app/core/database/encrypted_db_opener.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';

import '_support/fake_secure_key_store.dart';
import '_support/test_db_seeder.dart';

Future<String> _cipherVersion(sqlcipher.Database db) async {
  final rows = await db.rawQuery('PRAGMA cipher_version');
  if (rows.isEmpty) return '';
  return rows.first.values.first?.toString() ?? '';
}

Future<int> _userVersion(sqlcipher.Database db) async {
  final rows = await db.rawQuery('PRAGMA user_version');
  final v = rows.isNotEmpty ? rows.first.values.first : null;
  return v is int ? v : 0;
}

Future<Map<String, Object?>> _attachmentRow(
  sqlcipher.Database db,
  String id,
) async {
  final rows = await db.query(
    'media_attachments',
    where: 'id = ?',
    whereArgs: [id],
  );
  expect(rows, hasLength(1), reason: 'attachment $id must exist');
  return rows.single;
}

Future<List<String>> _indexColumns(
  sqlcipher.Database db,
  String indexName,
) async {
  final info = await db.rawQuery('PRAGMA index_info($indexName)');
  final ordered = [...info]..sort(
    (a, b) =>
        ((a['seqno'] as num).toInt()).compareTo((b['seqno'] as num).toInt()),
  );
  return ordered.map((r) => r['name'] as String).toList();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'production v95 upgrade fresh create and downgrade floor preserve '
    'encrypted media state',
    (tester) async {
      final secureKeyStore = FakeSecureKeyStore();
      final dbName =
          'media_library_sqlcipher_proof_'
          '${DateTime.now().millisecondsSinceEpoch}.db';
      final freshDbName = 'fresh_$dbName';

      try {
        // ---- Phase 1: literal v95 create through the PRODUCTION create
        // callback (target-version-aware shared registry). ----
        var db = await openEncryptedDatabase(
          secureKeyStore: secureKeyStore,
          dbName: dbName,
          version: 95,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        );
        final cipher = await _cipherVersion(db);
        expect(
          cipher,
          isNotEmpty,
          reason: 'PRAGMA cipher_version empty — not a SQLCipher engine',
        );
        expect(await _userVersion(db), 95);
        final v95Cols = (await db.rawQuery(
          'PRAGMA table_info(media_attachments)',
        )).map((c) => c['name'] as String).toSet();
        expect(v95Cols, isNot(contains('owner_lane')));

        // v95 collision fixture: direct-only, group-only, both-parents and
        // orphan attachments, each with distinctive bytes/metadata.
        Future<void> seedParent(String table, String id) async {
          if (table == 'messages') {
            await db.insert('messages', {
              'id': id,
              'contact_peer_id': 'contact-1',
              'sender_peer_id': 'contact-1',
              'text': 'direct parent $id',
              'timestamp': '2026-07-01T00:00:00.000Z',
              'status': 'delivered',
              'is_incoming': 1,
              'created_at': '2026-07-01T00:00:00.000Z',
            });
          } else {
            await db.insert('group_messages', {
              'id': id,
              'group_id': 'group-1',
              'sender_peer_id': 'peer-g',
              'sender_username': 'GroupSender',
              'text': 'group parent $id',
              'timestamp': '2026-07-01T00:00:00.000Z',
              'key_generation': 0,
              'status': 'delivered',
              'is_incoming': 1,
              'created_at': '2026-07-01T00:00:00.000Z',
            });
          }
        }

        await seedParent('messages', 'msg-direct-only');
        await seedParent('group_messages', 'msg-group-only');
        await seedParent('messages', 'msg-shared');
        await seedParent('group_messages', 'msg-shared');

        Future<void> seedAttachment(String id, String messageId) async {
          await db.insert('media_attachments', {
            'id': id,
            'message_id': messageId,
            'mime': 'image/jpeg',
            'size': 4321,
            'media_type': 'image',
            'local_path': '/media/$id.jpg',
            'download_status': 'done',
            'created_at': '2026-07-01T00:00:01.000Z',
            'encryption_key_base64': 'key-$id',
            'encryption_nonce': 'nonce-$id',
          });
        }

        await seedAttachment('att-direct', 'msg-direct-only');
        await seedAttachment('att-group', 'msg-group-only');
        await seedAttachment('att-ambiguous', 'msg-shared');
        await seedAttachment('att-orphan', 'msg-missing');
        await db.close();

        // ---- Phase 2: v95 -> v96 upgrade through the PRODUCTION upgrade
        // callback. ----
        db = await openEncryptedDatabase(
          secureKeyStore: secureKeyStore,
          dbName: dbName,
          version: 96,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        );
        expect(await _userVersion(db), 96);

        // Deterministic fail-closed backfill.
        expect((await _attachmentRow(db, 'att-direct'))['owner_lane'], 'direct');
        expect((await _attachmentRow(db, 'att-group'))['owner_lane'], 'group');
        expect(
          (await _attachmentRow(db, 'att-ambiguous'))['owner_lane'],
          'unresolved',
        );
        expect(
          (await _attachmentRow(db, 'att-orphan'))['owner_lane'],
          'unresolved',
        );

        // Bytes/metadata preserved; local-state defaults applied.
        for (final id in [
          'att-direct',
          'att-group',
          'att-ambiguous',
          'att-orphan',
        ]) {
          final row = await _attachmentRow(db, id);
          expect(row['size'], 4321);
          expect(row['local_path'], '/media/$id.jpg');
          expect(row['encryption_key_base64'], 'key-$id');
          expect(row['is_bookmarked'], 0);
          expect(row['last_playback_position_ms'], 0);
        }

        // Exact indexes.
        expect(await _indexColumns(db, 'idx_media_attachments_owner_message'), [
          'owner_lane',
          'message_id',
        ]);
        expect(
          await _indexColumns(
            db,
            'idx_media_attachments_owner_bookmark_message',
          ),
          ['owner_lane', 'is_bookmarked', 'message_id'],
        );

        // Enforced CHECK on the real cipher engine: invalid INSERT + UPDATE.
        await expectLater(
          () => db.insert('media_attachments', {
            'id': 'att-bogus',
            'message_id': 'msg-direct-only',
            'mime': 'image/jpeg',
            'size': 1,
            'media_type': 'image',
            'download_status': 'pending',
            'created_at': '2026-07-01T00:00:02.000Z',
            'owner_lane': 'not_a_lane',
          }),
          throwsA(anything),
        );
        await expectLater(
          () => db.update(
            'media_attachments',
            {'owner_lane': 'not_a_lane'},
            where: 'id = ?',
            whereArgs: ['att-direct'],
          ),
          throwsA(anything),
        );
        expect((await _attachmentRow(db, 'att-direct'))['owner_lane'], 'direct');

        // Explicit local-state writes persist.
        await db.update(
          'media_attachments',
          {'is_bookmarked': 1, 'last_playback_position_ms': 4200},
          where: 'id = ?',
          whereArgs: ['att-direct'],
        );

        // Rerun stability: the migration is idempotent and never mutates an
        // owner that is no longer unresolved.
        await runMediaLibraryStateMigrationRerun(db);
        expect((await _attachmentRow(db, 'att-direct'))['owner_lane'], 'direct');
        expect(
          (await _attachmentRow(db, 'att-ambiguous'))['owner_lane'],
          'unresolved',
        );
        final rerun = await _attachmentRow(db, 'att-direct');
        expect(rerun['is_bookmarked'], 1);
        expect(rerun['last_playback_position_ms'], 4200);
        await db.close();

        // ---- Phase 3: close/reopen maps durable state back. ----
        db = await openEncryptedDatabase(
          secureKeyStore: secureKeyStore,
          dbName: dbName,
          version: 96,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        );
        expect(await _userVersion(db), 96);
        final reopened = await _attachmentRow(db, 'att-direct');
        expect(reopened['owner_lane'], 'direct');
        expect(reopened['is_bookmarked'], 1);
        expect(reopened['last_playback_position_ms'], 4200);
        await db.close();

        // ---- Phase 4: separate FRESH v96 create. ----
        final freshDb = await openEncryptedDatabase(
          secureKeyStore: secureKeyStore,
          dbName: freshDbName,
          version: 96,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        );
        expect(await _userVersion(freshDb), 96);
        final freshCols = (await freshDb.rawQuery(
          'PRAGMA table_info(media_attachments)',
        )).map((c) => c['name'] as String).toSet();
        expect(
          freshCols,
          containsAll([
            'owner_lane',
            'is_bookmarked',
            'last_playback_position_ms',
          ]),
        );
        expect(
          await _indexColumns(
            freshDb,
            'idx_media_attachments_owner_bookmark_message',
          ),
          ['owner_lane', 'is_bookmarked', 'message_id'],
        );
        await freshDb.close();

        // ---- Phase 5: wrong password fails. READ-ONLY probe: a failed
        // keyed WRITE open would poison the immediate re-open on iOS FMDB.
        final dbPath = await sqlcipher.getDatabasesPath();
        final fullPath = '$dbPath/$dbName';
        const wrongKey =
            'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef';
        await expectLater(() async {
          final probe = await sqlcipher.openDatabase(
            fullPath,
            password: "x'$wrongKey'",
            readOnly: true,
            singleInstance: false,
          );
          try {
            await probe.rawQuery('SELECT count(*) FROM sqlite_master');
          } finally {
            await probe.close();
          }
        }, throwsA(anything));

        // ---- Phase 6: fail-closed downgrade floor. A requested-v95 open of
        // the v96 database must throw WITHOUT lowering user_version or
        // touching state. ----
        await expectLater(
          () => openEncryptedDatabase(
            secureKeyStore: secureKeyStore,
            dbName: dbName,
            version: 95,
            onCreate: runProductionOnCreate,
            onUpgrade: runProductionOnUpgrade,
          ),
          throwsA(anything),
        );

        // Correct reopen still works and everything is unchanged.
        db = await openEncryptedDatabase(
          secureKeyStore: secureKeyStore,
          dbName: dbName,
          version: 96,
          onCreate: runProductionOnCreate,
          onUpgrade: runProductionOnUpgrade,
        );
        expect(await _userVersion(db), 96);
        final afterDowngradeAttempt = await _attachmentRow(db, 'att-direct');
        expect(afterDowngradeAttempt['owner_lane'], 'direct');
        expect(afterDowngradeAttempt['is_bookmarked'], 1);
        expect(afterDowngradeAttempt['last_playback_position_ms'], 4200);
        expect(
          (await _attachmentRow(db, 'att-ambiguous'))['owner_lane'],
          'unresolved',
        );
        await db.close();
      } finally {
        await deleteTestDatabase(dbName);
        await deleteTestDatabase(freshDbName);
      }
    },
  );
}

/// Reruns migration 096 through the shared registry (rerun-stability proof).
/// Uses the registry entry rather than a direct import so the proof exercises
/// EXACTLY what production would run.
Future<void> runMediaLibraryStateMigrationRerun(sqlcipher.Database db) async {
  final entry = productionUpgradeMigrations.lastWhere((e) => e.version == 96);
  await entry.run(db);
}
