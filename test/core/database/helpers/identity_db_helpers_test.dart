import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/migrations/001_identity_table.dart';
import 'package:flutter_app/core/database/migrations/003_mlkem_keys.dart';
import 'package:flutter_app/core/database/migrations/004_nullify_secret_columns.dart';
import 'package:flutter_app/core/database/migrations/005_secret_null_checks.dart';
import 'package:flutter_app/core/database/migrations/011_avatar_version.dart';
import 'package:flutter_app/core/database/helpers/identity_db_helpers.dart';

void main() {
  late Database db;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await openDatabase(inMemoryDatabasePath, version: 1);
    await runIdentityTableMigration(db);
    await runMlKemKeysMigration(db);
    await runNullifySecretColumnsMigration(db);
    await runSecretNullChecksMigration(db);
    await runAvatarVersionMigration(db);
  });

  tearDown(() async {
    await db.close();
  });

  Map<String, Object?> makeIdentityRow({
    String peerId = '12D3KooWTestPeerId',
    String publicKey = 'test-public-key-base64',
    String? mlKemPublicKey,
    String username = 'TestUser',
    String createdAt = '2026-01-01T00:00:00.000Z',
    String updatedAt = '2026-01-02T00:00:00.000Z',
  }) {
    return {
      'peer_id': peerId,
      'public_key': publicKey,
      'private_key': null, // CHECK constraint
      'mnemonic12': null, // CHECK constraint
      'ml_kem_public_key': mlKemPublicKey,
      'ml_kem_secret_key': null, // CHECK constraint
      'username': username,
      'avatar_blob': null,
      'avatar_version': null,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  group('dbLoadIdentityRow', () {
    test('returns null when table is empty', () async {
      final result = await dbLoadIdentityRow(db);
      expect(result, isNull);
    });

    test('returns row when identity exists', () async {
      await dbUpsertIdentityRow(db, makeIdentityRow());
      final result = await dbLoadIdentityRow(db);
      expect(result, isNotNull);
    });

    test('returned row contains correct peer_id', () async {
      await dbUpsertIdentityRow(
        db,
        makeIdentityRow(peerId: '12D3KooWSpecificPeerId'),
      );
      final result = await dbLoadIdentityRow(db);
      expect(result, isNotNull);
      expect(result!['peer_id'], '12D3KooWSpecificPeerId');
    });
  });

  group('dbUpsertIdentityRow', () {
    test('inserts new row at id=1', () async {
      await dbUpsertIdentityRow(db, makeIdentityRow());

      final rows = await db.query('identity');
      expect(rows.length, 1);
      expect(rows[0]['id'], 1);
    });

    test('upserts (replaces) on conflict', () async {
      await dbUpsertIdentityRow(
        db,
        makeIdentityRow(username: 'OriginalName'),
      );
      await dbUpsertIdentityRow(
        db,
        makeIdentityRow(username: 'UpdatedName'),
      );

      final rows = await db.query('identity');
      expect(rows.length, 1);
      expect(rows[0]['username'], 'UpdatedName');
    });

    test('CHECK constraint rejects non-null private_key', () async {
      final row = makeIdentityRow();
      row['private_key'] = 'should-fail';

      try {
        await dbUpsertIdentityRow(db, row);
        fail('Expected DatabaseException for CHECK constraint violation');
      } catch (e) {
        expect(e, isA<DatabaseException>());
      }
    });
  });
}
