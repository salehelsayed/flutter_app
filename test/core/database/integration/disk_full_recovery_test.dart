import 'dart:io';

import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/encrypted_db_opener.dart';
import 'package:flutter_app/core/database/helpers/messages_db_helpers.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' show Sqflite;

import '../../secure_storage/fake_secure_key_store.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory directory;
  late String path;
  Database? database;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('disk-full-recovery-');
    path = '${directory.path}/identity.db';
  });

  tearDown(() async {
    await database?.close();
    database = null;
    await directory.delete(recursive: true);
  });

  Future<Database> openCurrent() async {
    final db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: currentIdentityDatabaseVersion,
        singleInstance: false,
        onCreate: runProductionOnCreate,
        onUpgrade: runProductionOnUpgrade,
      ),
    );
    database = db;
    return db;
  }

  for (final replacingExisting in [false, true]) {
    test(
      'LL-34 SQLITE_FULL during ${replacingExisting ? 'replacement' : 'insert'} '
      'preserves accepted history after reopen and allows retry',
      () async {
        var db = await openCurrent();
        await dbInsertMessage(db, _message('accepted', 'already saved'));
        final acceptedBefore = await dbLoadMessage(db, 'accepted');
        expect(acceptedBefore?['text'], 'already saved');
        final pageCount = Sqflite.firstIntValue(
          await db.rawQuery('PRAGMA page_count'),
        )!;
        expect(
          Sqflite.firstIntValue(
            await db.rawQuery('PRAGMA max_page_count = $pageCount'),
          ),
          pageCount,
        );

        // Bound only this temporary database; never fill the host filesystem.
        final attempted = _message(
          replacingExisting ? 'accepted' : 'pending',
          List.filled(65536, 'x').join(),
        );
        await expectLater(
          dbInsertMessage(db, attempted),
          throwsA(
            isA<DatabaseException>().having(
              (error) => error.getResultCode(),
              'SQLITE_FULL',
              13,
            ),
          ),
        );
        await db.close();
        database = null;

        db = await openCurrent();
        expect(await dbLoadMessage(db, 'accepted'), acceptedBefore);
        expect(await dbLoadMessage(db, 'pending'), isNull);
        expect(await db.rawQuery('PRAGMA quick_check'), [
          {'quick_check': 'ok'},
        ]);
        await db.rawQuery('PRAGMA max_page_count = 1048576');
        await dbInsertMessage(db, attempted);
        await db.close();
        database = null;

        db = await openCurrent();
        expect(
          (await dbLoadMessage(db, attempted['id']! as String))?['text'],
          attempted['text'],
        );
        expect(await dbGetMessageCount(db), replacingExisting ? 1 : 2);
      },
    );
  }

  test(
    'LL-34 SQLITE_FULL during an upgrade retains the old database and retries',
    () async {
      var db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 3,
          singleInstance: false,
          onCreate: runProductionOnCreate,
        ),
      );
      database = db;
      await dbInsertMessage(db, _message('accepted', 'already saved'));
      final oldSchema = await db.rawQuery(
        'SELECT type, name, sql FROM sqlite_master ORDER BY type, name',
      );
      await db.close();
      database = null;

      await expectLater(
        databaseFactoryFfi.openDatabase(
          path,
          options: OpenDatabaseOptions(
            version: currentIdentityDatabaseVersion,
            singleInstance: false,
            onConfigure: (opening) async {
              final pages = Sqflite.firstIntValue(
                await opening.rawQuery('PRAGMA page_count'),
              )!;
              await opening.rawQuery('PRAGMA max_page_count = $pages');
            },
            onUpgrade: runProductionOnUpgrade,
          ),
        ),
        throwsA(
          isA<DatabaseException>().having(
            (error) => error.getResultCode(),
            'SQLITE_FULL',
            13,
          ),
        ),
      );

      db = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      database = db;
      expect(await db.getVersion(), 3);
      expect(
        await db.rawQuery(
          'SELECT type, name, sql FROM sqlite_master ORDER BY type, name',
        ),
        oldSchema,
      );
      expect(
        (await db.query('messages')).single,
        _message('accepted', 'already saved'),
      );
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
          onConfigure: (opening) async {
            await opening.rawQuery('PRAGMA max_page_count = 1048576');
          },
          onUpgrade: runProductionOnUpgrade,
        ),
      );
      database = db;
      expect(await db.getVersion(), currentIdentityDatabaseVersion);
      expect((await dbLoadMessage(db, 'accepted'))?['text'], 'already saved');
    },
  );

  test(
    'LL-34 interrupted rekey before swap restores the original readable file',
    () async {
      var db = await openCurrent();
      await dbInsertMessage(db, _message('accepted', 'already saved'));
      await db.close();
      database = null;
      await File(path).rename('$path.pre-raw.bak');
      await File('$path.rekey-tmp').writeAsBytes([1, 2, 3], flush: true);

      final keyStore = FakeSecureKeyStore();
      await keyStore.write(
        dbEncryptionKeyStorageKey,
        'raw:${List.filled(64, 'a').join()}',
      );
      // Actual file recovery runs; only the SQLCipher open is adapted to FFI.
      db = await openEncryptedDatabase(
        secureKeyStore: keyStore,
        dbName: 'identity.db',
        version: currentIdentityDatabaseVersion,
        onCreate: runProductionOnCreate,
        onUpgrade: runProductionOnUpgrade,
        debugHooks: EncryptedDatabaseOpenDebugHooks(
          resolveDatabasesPath: () async => directory.path,
          isRawKeyDatabase: (_, _, _) async => true,
          openDatabase:
              (
                recoveredPath, {
                required version,
                required password,
                required onConfigure,
                required onCreate,
                required onUpgrade,
                required onDowngrade,
              }) => databaseFactoryFfi.openDatabase(
                recoveredPath,
                options: OpenDatabaseOptions(
                  version: version,
                  singleInstance: false,
                  onConfigure: onConfigure,
                  onCreate: onCreate,
                  onUpgrade: onUpgrade,
                  onDowngrade: onDowngrade,
                ),
              ),
        ),
      );
      database = db;
      expect((await dbLoadMessage(db, 'accepted'))?['text'], 'already saved');
      expect(await db.getVersion(), currentIdentityDatabaseVersion);
      expect(await File('$path.pre-raw.bak').exists(), isFalse);
      expect(await File('$path.rekey-tmp').exists(), isFalse);
      await db.close();
      database = null;

      db = await openCurrent();
      expect((await dbLoadMessage(db, 'accepted'))?['text'], 'already saved');
      expect(await db.rawQuery('PRAGMA quick_check'), [
        {'quick_check': 'ok'},
      ]);
    },
  );
}

Map<String, Object?> _message(String id, String text) => {
  'id': id,
  'contact_peer_id': 'contact',
  'sender_peer_id': 'owner',
  'text': text,
  'timestamp': '2026-10-31T00:00:00Z',
  'status': 'sent',
  'is_incoming': 0,
  'created_at': '2026-10-31T00:00:00Z',
};
