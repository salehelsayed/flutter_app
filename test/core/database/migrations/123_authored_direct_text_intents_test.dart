// ignore_for_file: file_names
import 'dart:io';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  for (final from122 in [false, true]) {
    test(
      'v123 authored intent schema ${from122 ? 'upgrades v122' : 'fresh install'}',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'authored-text-migration-',
        );
        addTearDown(() => dir.delete(recursive: true));
        final path = '${dir.path}/db.sqlite';
        Future<Database> open(int version) =>
            databaseFactoryFfiNoIsolate.openDatabase(
              path,
              options: OpenDatabaseOptions(
                version: version,
                singleInstance: false,
                onCreate: runProductionOnCreate,
                onUpgrade: runProductionOnUpgrade,
              ),
            );
        if (from122) {
          final old = await open(122);
          expect(
            await old.rawQuery(
              "SELECT name FROM sqlite_master WHERE name = 'authored_direct_text_intents'",
            ),
            isEmpty,
          );
          await old.insert('contacts', {
            'peer_id': 'kept',
            'public_key': 'key',
            'rendezvous': '/relay',
            'username': 'kept',
            'signature': 'sig',
            'scanned_at': '2026-10-25T00:00:00Z',
          });
          await old.close();
        }
        final db = await open(currentIdentityDatabaseVersion);
        addTearDown(db.close);
        expect(await db.getVersion(), 123);
        expect(
          (await db.rawQuery(
            'PRAGMA table_info(authored_direct_text_intents)',
          )).map((row) => row['name']),
          orderedEquals([
            'id',
            'contact_peer_id',
            'text',
            'quoted_message_id',
            'timestamp',
            'token',
          ]),
        );
        expect(await db.query('authored_direct_text_intents'), isEmpty);
        if (from122) {
          expect((await db.query('contacts')).single['peer_id'], 'kept');
        }
      },
    );
  }
}
