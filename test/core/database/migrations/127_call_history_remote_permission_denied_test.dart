// ignore_for_file: file_names
import 'dart:io';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/migrations/127_call_history_remote_permission_denied.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Map<String, Object?> _row(String callId, String reason) => {
  'call_id': callId,
  'contact_account_peer_id': 'peer-alice',
  'direction': 'outgoing',
  'terminal_reason': reason,
  'status': 'failed',
  'started_at': '2026-10-31T10:00:00.000Z',
  'ended_at': '2026-10-31T10:00:05.000Z',
  'created_at': '2026-10-31T10:00:05.000Z',
  'updated_at': '2026-10-31T10:00:05.000Z',
};

void main() {
  sqfliteFfiInit();
  for (final from126 in [false, true]) {
    test('v127 call_history stores remote_permission_denied '
        '(${from126 ? 'upgrade v126' : 'fresh install'})', () async {
      final dir = await Directory.systemTemp.createTemp('call-127-');
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
      const oldCall = '11111111-1111-4111-8111-111111111111';
      if (from126) {
        final old = await open(126);
        await old.insert('call_history', _row(oldCall, 'permission_denied'));
        await old.update(
          'call_history',
          {'read_at': '2026-10-31T10:01:00.000Z'},
          where: 'call_id = ?',
          whereArgs: [oldCall],
        );
        await expectLater(
          old.insert(
            'call_history',
            _row(
              '22222222-2222-4222-8222-222222222222',
              'remote_permission_denied',
            ),
          ),
          throwsA(isA<DatabaseException>()),
        );
        await old.close();
      }

      final db = await open(currentIdentityDatabaseVersion);
      addTearDown(db.close);
      expect(await db.getVersion(), currentIdentityDatabaseVersion);

      const newCall = '33333333-3333-4333-8333-333333333333';
      await db.insert(
        'call_history',
        _row(newCall, 'remote_permission_denied'),
      );
      expect(
        (await db.query(
          'call_history',
          columns: ['terminal_reason'],
          where: 'call_id = ?',
          whereArgs: [newCall],
        )).single['terminal_reason'],
        'remote_permission_denied',
      );
      await expectLater(
        db.insert(
          'call_history',
          _row('44444444-4444-4444-8444-444444444444', 'made_up'),
        ),
        throwsA(isA<DatabaseException>()),
      );
      await expectLater(
        db.update(
          'call_history',
          {'read_at': 'not a time'},
          where: 'call_id = ?',
          whereArgs: [newCall],
        ),
        throwsA(isA<DatabaseException>()),
      );

      if (from126) {
        final kept = (await db.query(
          'call_history',
          where: 'call_id = ?',
          whereArgs: [oldCall],
        )).single;
        expect(kept['terminal_reason'], 'permission_denied');
        expect(kept['status'], 'failed');
        expect(kept['read_at'], '2026-10-31T10:01:00.000Z');
      }

      final indexes = (await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'index' "
        "AND tbl_name = 'call_history' AND name NOT LIKE 'sqlite_%'",
      )).map((row) => row['name']).toSet();
      expect(indexes, {
        'idx_call_history_contact_timeline',
        'idx_call_history_contact_unread',
      });
      await runCallHistoryRemotePermissionDeniedMigration(db);
      expect(
        (await db.query('call_history')).length,
        from126 ? 2 : 1,
        reason: 'running the migration again keeps every row',
      );
    });
  }

  test('v127 is the create and upgrade step before v128', () {
    for (final registry in [
      productionCreateMigrations,
      productionUpgradeMigrations,
    ]) {
      final entry = registry[registry.length - 4];
      expect(entry.version, 127);
      expect(entry.name, '127_call_history_remote_permission_denied');
      expect(entry.run, same(runCallHistoryRemotePermissionDeniedMigration));
      expect(registry[registry.length - 5].version, 126);
    }
  });
}
