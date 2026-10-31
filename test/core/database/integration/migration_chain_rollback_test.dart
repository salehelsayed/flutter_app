import 'dart:io';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/migrations/005_secret_null_checks.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/secure_storage/migrate_secrets_to_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../secure_storage/fake_secure_key_store.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory directory;
  late String path;
  Database? database;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('migration-rollback-');
    path = '${directory.path}/identity.db';
  });

  tearDown(() async {
    await database?.close();
    database = null;
    await directory.delete(recursive: true);
  });

  Future<Database> seedVersionThree() async {
    final db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 3,
        singleInstance: false,
        onCreate: runProductionOnCreate,
      ),
    );
    database = db;
    await db.insert('identity', _identity);
    await db.insert('messages', _message);
    return db;
  }

  for (final stopVersion in [4, 44, 100, currentIdentityDatabaseVersion]) {
    test('LL-35 failed upgrade after version $stopVersion keeps the original '
        'account readable and retries cleanly', () async {
      var db = await seedVersionThree();
      final oldSchema = await _schema(db);
      await db.close();
      database = null;
      var reachedCheckpoint = false;

      await expectLater(
        databaseFactoryFfi.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: currentIdentityDatabaseVersion,
            singleInstance: false,
            onUpgrade: (upgrading, oldVersion, newVersion) async {
              await runProductionOnUpgrade(upgrading, oldVersion, stopVersion);
              reachedCheckpoint = true;
              throw StateError('LL-35 interrupted upgrade checkpoint');
            },
          ),
        ),
        throwsA(isA<StateError>()),
      );
      expect(reachedCheckpoint, isTrue);

      db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      database = db;
      expect(await db.getVersion(), 3);
      expect(await _schema(db), oldSchema);
      expect(await db.query('identity'), [_identity]);
      expect(await db.query('messages'), [_message]);
      expect(await db.rawQuery('PRAGMA quick_check'), [
        {'quick_check': 'ok'},
      ]);
      await db.close();
      database = null;

      db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: currentIdentityDatabaseVersion,
          singleInstance: false,
          onUpgrade: runProductionOnUpgrade,
        ),
      );
      database = db;
      expect(await db.getVersion(), currentIdentityDatabaseVersion);
      expect(
        (await db.query('identity')).single,
        containsPair('peer_id', 'owner'),
      );
      expect(
        (await db.query('messages')).single,
        containsPair('text', 'saved conversation'),
      );
      await db.close();
      database = null;

      db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      database = db;
      expect(await db.getVersion(), currentIdentityDatabaseVersion);
      expect(
        (await db.query('messages')).single,
        containsPair('id', 'accepted'),
      );
    });
  }

  test('LL-35 secret-check table replacement rolls back a failed copy and '
      'retries after secret migration', () async {
    var db = await seedVersionThree();
    await runProductionOnUpgrade(db, 3, 4);
    await db.setVersion(4);
    final oldSchema = await _schema(db);
    final oldIdentity = await db.query('identity');

    // The real COPY hits the new CHECK after the old table was renamed.
    await expectLater(
      runSecretNullChecksMigration(db),
      throwsA(
        isA<DatabaseException>().having(
          (error) => error.toString(),
          'COPY into the secret-null CHECK constraint',
          contains('CHECK constraint failed'),
        ),
      ),
    );
    await db.close();
    database = null;

    db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    database = db;
    expect(await _schema(db), oldSchema);
    expect(await db.getVersion(), 4);
    expect(await db.query('identity'), oldIdentity);
    expect(await db.query('messages'), [_message]);

    final keys = FakeSecureKeyStore();
    await migrateSecretsToSecureStorage(db: db, secureKeyStore: keys);
    await runSecretNullChecksMigration(db);
    await runSecretNullChecksMigration(db);
    await db.close();
    database = null;

    db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(singleInstance: false),
    );
    database = db;
    final restored = (await db.query('identity')).single;
    expect(restored['peer_id'], 'owner');
    expect(restored['private_key'], isNull);
    expect(restored['mnemonic12'], isNull);
    expect(restored['ml_kem_secret_key'], isNull);
    expect(await keys.read('identity_private_key'), 'fixture-private');
    expect(await keys.read('identity_mnemonic12'), 'fixture-mnemonic');
    expect(await keys.read('identity_ml_kem_secret_key'), 'fixture-kem-secret');
    expect(await db.query('messages'), [_message]);
    await expectLater(
      db.update('identity', {'private_key': 'rejected-secret'}),
      throwsA(isA<DatabaseException>()),
    );
  });
}

Future<List<Map<String, Object?>>> _schema(Database db) => db.rawQuery(
  'SELECT type, name, tbl_name, sql FROM sqlite_master ORDER BY type, name',
);

const _identity = <String, Object?>{
  'id': 1,
  'peer_id': 'owner',
  'public_key': 'fixture-public',
  'private_key': 'fixture-private',
  'mnemonic12': 'fixture-mnemonic',
  'ml_kem_public_key': 'fixture-kem-public',
  'ml_kem_secret_key': 'fixture-kem-secret',
  'username': 'Account owner',
  'avatar_path': null,
  'created_at': '2026-10-31T00:00:00Z',
  'updated_at': '2026-10-31T00:00:00Z',
};

const _message = <String, Object?>{
  'id': 'accepted',
  'contact_peer_id': 'contact',
  'sender_peer_id': 'owner',
  'text': 'saved conversation',
  'timestamp': '2026-10-31T00:00:00Z',
  'status': 'sent',
  'is_incoming': 0,
  'created_at': '2026-10-31T00:00:00Z',
};
