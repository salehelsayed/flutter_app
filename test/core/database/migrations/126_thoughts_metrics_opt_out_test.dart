// ignore_for_file: file_names
import 'dart:io';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/migrations/126_thoughts_metrics_opt_out.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  for (final from125 in [false, true]) {
    test(
      'v126 posts.metrics_opt_out ${from125 ? 'upgrade v125' : 'fresh install'}',
      () async {
        final dir = await Directory.systemTemp.createTemp('thought-126-');
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
        if (from125) {
          final old = await open(125);
          await old.insert('posts', {
            'post_id': 'old-post',
            'event_id': 'old-event',
            'sender_peer_id': 'peer-alice',
            'author_peer_id': 'peer-alice',
            'author_username': 'Alice',
            'text': 'sent before 129',
            'audience_kind': 'all_friends',
            'post_created_at': '2026-10-29T10:00:00Z',
            'visible_at': '2026-10-29T10:00:00Z',
            'expires_at': '2026-10-30T10:00:00Z',
            'is_incoming': 0,
            'delivery_status': 'sending',
          });
          await old.close();
        }
        final db = await open(currentIdentityDatabaseVersion);
        addTearDown(db.close);
        expect(await db.getVersion(), 126);

        final column = (await db.rawQuery(
          'PRAGMA table_info(posts)',
        )).singleWhere((column) => column['name'] == 'metrics_opt_out');
        expect(column['type'], 'INTEGER');
        expect(column['notnull'], 1);
        expect(column['dflt_value'], '0');

        if (from125) {
          final kept = await db.query(
            'posts',
            where: 'post_id = ?',
            whereArgs: ['old-post'],
          );
          expect(kept.single['text'], 'sent before 129');
          expect(kept.single['metrics_opt_out'], 0);
        }

        await expectLater(
          db.rawUpdate('UPDATE posts SET metrics_opt_out = 2'),
          from125 ? throwsA(isA<DatabaseException>()) : completion(0),
        );

        await runThoughtsMetricsOptOutMigration(db);
        expect(
          (await db.rawQuery(
            'PRAGMA table_info(posts)',
          )).where((column) => column['name'] == 'metrics_opt_out'),
          hasLength(1),
        );
      },
    );
  }

  test('v126 is the last entry of both production registries', () {
    expect(currentIdentityDatabaseVersion, 126);
    for (final registry in [
      productionCreateMigrations,
      productionUpgradeMigrations,
    ]) {
      expect(registry.where((entry) => entry.version == 126), hasLength(1));
      expect(registry.last.version, 126);
      expect(registry.last.name, '126_thoughts_metrics_opt_out');
      expect(registry.last.run, same(runThoughtsMetricsOptOutMigration));
      expect(registry[registry.length - 2].version, 125);
    }
  });
}
